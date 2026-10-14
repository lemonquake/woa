class_name SimVision
extends RefCounted
## Fog of war. Each team sees the union of its units' sight discs on a 128-unit grid, cast as rays that stop at trees
## and at higher ground (low ground cannot see up a cliff; trees block what lies behind them). Updated at 10 Hz.
##
## Buildings are always known (their last state shows in the fog), but are only *targetable* when in sight, as in
## Dota. Neutral creeps see everything near them.

const C = preload("res://src/sim/sim_const.gd")
const VN := 128

var w: SimWorld
var visible: Array[PackedByteArray] = []   # per team (0, 1): VN*VN, 1 = in sight
var _templates := {}                       # radius in cells -> Array of rays (PackedInt32Array of dx,dy pairs)
var revealed := {}                         # unit id -> game time until which it is visible to everyone (attacking from fog)
var sources: Array = []                    # timed sight not tied to a unit: {team, pos, r, until} (Shuriken Hook's catch)

func _init(world: SimWorld = null) -> void:
	w = world
	for t in 2:
		var a := PackedByteArray()
		a.resize(VN * VN)
		visible.append(a)

## Buildings never move: their combined sight is cached per team and rebuilt only when one falls, a tree changes or
## day turns to night.
var static_dirty := true
var reveal_all := false                     # Debug panel: every cell is in sight for both teams
var _static: Array[PackedByteArray] = []
var _static_night := false

func update() -> void:
	var night := w.is_night()
	if static_dirty or night != _static_night or _static.is_empty():
		_rebuild_static(night)
	if w.map.vision_rev != _stamp_rev:
		_stamps.clear()
		_stamp_rev = w.map.vision_rev
	if _team_img.is_empty():
		for t in 2:
			_team_img.append(Image.create(VN, VN, false, Image.FORMAT_LA8))
	for team in 2:
		var img: Image = _team_img[team]
		img.copy_from(_static_img[team])
		var done := {}                     # vision cell -> largest radius already cast from it
		for u in w.units:
			if not u.alive or u.team != team or u.is_building():
				continue
			var r := u.vision_night if night else u.vision_day
			if r <= 0.0:
				continue
			var c := w.map.world_to_vcell(u.pos)
			var key := c.y * VN + c.x
			if float(done.get(key, 0.0)) >= r:
				continue
			done[key] = r
			_blit(img, c, r, u.has_flag("flying"))
		for s in sources:
			if int(s.team) == team and w.time < float(s.until):
				_blit(img, w.map.world_to_vcell(s.pos), float(s.r), true)
		# cursed enemies (Tainted Touch) grant sight around themselves
		for u in w.units:
			if not u.alive or u.team == team:
				continue
			for m in u.modifiers:
				if int(m.get("reveal", -1)) == team:
					_blit(img, w.map.world_to_vcell(u.pos), float(m.get("reveal_r", 300.0)), true)
					break
		var l8 := img.duplicate() as Image
		l8.convert(Image.FORMAT_L8)
		visible[team] = l8.get_data()
	_true_sight_sources()

## Sight shapes cached per (vision cell, radius, flying) until a tree changes: each is a small luminance + alpha image
## (alpha 255 where seen, value 1) blitted into the team's grid by the engine, so a unit that stays in its cell costs one
## blit instead of a ray cast. The result is exactly the union of the ray casts.
var _stamps := {}
var _stamp_rev := -1
var _team_img: Array[Image] = []
var _static_img: Array[Image] = []

func _blit(img: Image, c: Vector2i, radius: float, flying: bool) -> void:
	var rc := int(ceil(radius / C.VISION_CELL))
	var key := ((c.y * VN + c.x) * 128 + mini(rc, 127)) * 2 + (1 if flying else 0)
	var st = _stamps.get(key)
	if st == null:
		st = _make_stamp(c, rc, flying)
		if _stamps.size() > 6000:
			_stamps.clear()
		_stamps[key] = st
	var size := 2 * rc + 1
	img.blit_rect_mask(st, st, Rect2i(0, 0, size, size), Vector2i(c.x - rc, c.y - rc))

func _make_stamp(c: Vector2i, rc: int, flying: bool) -> Image:
	var size := 2 * rc + 1
	var buf := PackedByteArray()
	buf.resize(size * size * 2)
	var m := w.map
	var src_level := m.vision_level[c.y * VN + c.x]
	var ci := (rc * size + rc) * 2
	buf[ci] = 1
	buf[ci + 1] = 255
	var block := m.vision_block
	var lvl := m.vision_level
	for ray: PackedInt32Array in _rays(rc):
		var n := ray.size()
		var i := 0
		while i < n:
			var dx := ray[i]
			var dy := ray[i + 1]
			var x := c.x + dx
			var y := c.y + dy
			i += 2
			if x < 0 or y < 0 or x >= VN or y >= VN:
				break
			var idx := y * VN + x
			if not flying and lvl[idx] > src_level:
				break
			var li := ((dy + rc) * size + dx + rc) * 2
			buf[li] = 1
			buf[li + 1] = 255
			if not flying and block[idx] == 1:
				break
	return Image.create_from_data(size, size, false, Image.FORMAT_LA8, buf)

## True Sight (Dota 2 wiki, Invisibility): towers, the Throne, the fountain and Reveal Wards see invisible enemies
## within their radius, wherever their team has vision; Reveal Dust marks the units it touches. Rebuilt with vision.
var true_sight := [[], []]                 # team -> [[pos, radius], ...]

func _true_sight_sources() -> void:
	true_sight = [[], []]
	for u in w.units:
		if not u.alive or u.team < 0 or u.team > 1:
			continue
		var r := float(u.def.get("true_sight", 0.0))
		if r <= 0.0 and u.kind == C.Kind.TOWER:
			r = C.TOWER_TRUE_SIGHT
		elif r <= 0.0 and u.kind == C.Kind.ANCIENT:
			r = C.ANCIENT_TRUE_SIGHT
		if r > 0.0:
			true_sight[u.team].append([u.pos, r])

## Whether `team` has True Sight over unit `u` (a source in range or Reveal Dust on it).
func true_sighted(team: int, u: SimUnit) -> bool:
	if team < 0 or team > 1:
		return false
	for m in u.modifiers:
		if int(m.get("truesight_by", -1)) == team:
			return true
	for s in true_sight[team]:
		if (s[0] as Vector2).distance_to(u.pos) <= float(s[1]):
			return true
	return false

## Sight for `team` over `pos` (flying vision: sees over cliffs and trees) for `dur` seconds.
func add_source(team: int, pos: Vector2, r: float, dur: float) -> void:
	sources.append({"team": team, "pos": pos, "r": r, "until": w.time + dur})

func prune_sources() -> void:
	for i in range(sources.size() - 1, -1, -1):
		if w.time >= float(sources[i].until):
			sources.remove_at(i)

func _rebuild_static(night: bool) -> void:
	static_dirty = false
	_static_night = night
	_static.clear()
	_static_img.clear()
	for team in 2:
		var vis := PackedByteArray()
		vis.resize(VN * VN)
		for u in w.units:
			if u.alive and u.team == team and u.is_building():
				_cast(vis, u.pos, u.vision_night if night else u.vision_day, false)
		_static.append(vis)
		# the same grid as a luminance + alpha image (alpha 255 where seen) to start each update from
		var la := PackedByteArray()
		la.resize(VN * VN * 2)
		for i in VN * VN:
			if vis[i] == 1:
				la[i * 2] = 1
				la[i * 2 + 1] = 255
		_static_img.append(Image.create_from_data(VN, VN, false, Image.FORMAT_LA8, la))

func _cast(vis: PackedByteArray, p: Vector2, radius: float, flying: bool) -> void:
	var m := w.map
	var c := m.world_to_vcell(p)
	var rc := int(ceil(radius / C.VISION_CELL))
	var src_level := m.vision_level[c.y * VN + c.x]
	vis[c.y * VN + c.x] = 1
	var rays: Array = _rays(rc)
	var block := m.vision_block
	var lvl := m.vision_level
	for ray: PackedInt32Array in rays:
		var n := ray.size()
		var i := 0
		while i < n:
			var x := c.x + ray[i]
			var y := c.y + ray[i + 1]
			i += 2
			if x < 0 or y < 0 or x >= VN or y >= VN:
				break
			var idx := y * VN + x
			if not flying and lvl[idx] > src_level:
				break
			vis[idx] = 1
			if not flying and block[idx] == 1:
				break

## Rays for a radius (in cells): one per outer cell of the disc, as the list of cells it passes.
func _rays(rc: int) -> Array:
	if _templates.has(rc):
		return _templates[rc]
	var rays: Array = []
	var count := maxi(16, int(TAU * rc * 1.15))
	for k in count:
		var a := TAU * k / count
		var ray := PackedInt32Array()
		var last := Vector2i(0, 0)
		var steps := rc * 3
		for s in range(1, steps + 1):
			var f := float(s) / steps * rc
			var cell := Vector2i(roundi(cos(a) * f), roundi(sin(a) * f))
			if cell == last:
				continue
			if cell.x * cell.x + cell.y * cell.y > rc * rc:
				break
			last = cell
			ray.append(cell.x)
			ray.append(cell.y)
		rays.append(ray)
	_templates[rc] = rays
	return rays

## A curse (Tainted Touch) reveals its bearer to the curser's team, invisible or not.
func revealed_to(u: SimUnit, team: int) -> bool:
	for m in u.modifiers:
		if int(m.get("reveal", -1)) == team:
			return true
	return false

func cell_visible(team: int, p: Vector2) -> bool:
	if team < 0 or team > 1 or reveal_all:
		return true
	var c := w.map.world_to_vcell(p)
	return visible[team][c.y * VN + c.x] == 1

## Whether `team` can see unit `u` (own units always; invisible units never without true sight).
func sees(team: int, u: SimUnit) -> bool:
	if u.team == team or team == C.NEUTRAL:
		return true
	if revealed_to(u, team):
		return true
	if u.has_flag("invisible"):
		# invisible: seen only under True Sight, where the team has vision
		return cell_visible(team, u.pos) and true_sighted(team, u)
	if cell_visible(team, u.pos):
		return true
	# a building's footprint may poke into sight
	if u.is_building():
		return cell_visible(team, u.pos + (w.map.fountains[team] - u.pos).normalized() * u.hull)
	return false
