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

func _init(world: SimWorld) -> void:
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
	for team in 2:
		var vis := _static[team].duplicate()
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
			_cast(vis, u.pos, r, u.has_flag("flying"))
		for s in sources:
			if int(s.team) == team and w.time < float(s.until):
				_cast(vis, s.pos, float(s.r), true)
		# cursed enemies (Tainted Touch) grant sight around themselves
		for u in w.units:
			if not u.alive or u.team == team:
				continue
			for m in u.modifiers:
				if int(m.get("reveal", -1)) == team:
					_cast(vis, u.pos, float(m.get("reveal_r", 300.0)), true)
					break
		visible[team] = vis

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
	for team in 2:
		var vis := PackedByteArray()
		vis.resize(VN * VN)
		for u in w.units:
			if u.alive and u.team == team and u.is_building():
				_cast(vis, u.pos, u.vision_night if night else u.vision_day, false)
		_static.append(vis)

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
		return false
	if cell_visible(team, u.pos):
		return true
	# a building's footprint may poke into sight
	if u.is_building():
		return cell_visible(team, u.pos + (w.map.fountains[team] - u.pos).normalized() * u.hull)
	return false
