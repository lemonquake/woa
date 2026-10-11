class_name SimMap
extends RefCounted
## The battlefield: terrain levels (river / ground / high ground), cliffs and ramps, trees, the pathing grid, lanes,
## building sites and neutral camps. Built deterministically from a seed; both the simulation and the renderer read it.
##
## Layout follows the classic three-lane map: Dawn's base in the south-west corner, Dusk's in the north-east, the
## river running north-west to south-east through the middle. Dusk's half is Dawn's rotated 180 degrees (p -> -p).

const C = preload("res://src/sim/sim_const.gd")
const N := 256                             # pathing cells per side (64 units each)
const CELL := 64.0
const HALF := 8192.0
const VN := 128                            # vision cells per side (128 units each)

# Terrain levels
const RIVER := 0
const GROUND := 1
const HIGH := 2

var seed_value := 1
var level := PackedByteArray()             # N*N terrain level per path cell
var height := PackedFloat32Array()         # (N+1)*(N+1) smooth corner heights in game units (for rendering + z)
var walkable := PackedByteArray()          # N*N 1 = walkable for ground units (static: terrain + trees + buildings)
var tree_cell := PackedInt32Array()        # N*N index into trees or -1
var trees: Array = []                      # [{pos: Vector2, alive: bool, kind: int, scale: float, regrow: float}]
var astar := AStarGrid2D.new()
var vision_block := PackedByteArray()      # VN*VN 1 = a tree stands here (blocks sight beyond)
var vision_level := PackedByteArray()      # VN*VN terrain level

var lanes := {}                            # "top"/"mid"/"bot" -> PackedVector2Array from Dawn's base to Dusk's
var ramps: Array = []                      # [{pos: Vector2, radius: float}]
var buildings: Array = []                  # [{id, team, pos, lane, tier, name}]
var camps: Array = []                      # [{id, team_side, kind, pos, box_half, units: [ids]}]
var fountains := [Vector2(-7050, -6650), Vector2(7050, 6650)]
var shops := [Vector2(-6700, -6200), Vector2(6700, 6200)]
var paths: Array = []                      # jungle walkways (PackedVector2Array), kept clear of trees

# ---- Construction ---------------------------------------------------------------------------------------------------

func build(p_seed := 1) -> void:
	seed_value = p_seed
	_layout()
	_terrain()
	_place_trees()
	_pathing()
	_vision_grid()

## Building sites, lanes, camps. Everything is stated for Dawn and mirrored for Dusk.
func _layout() -> void:
	var dawn_lanes := {
		"top": [Vector2(-6550, -4350), Vector2(-6550, -3500), Vector2(-6450, 4800), Vector2(-5900, 5900),
			Vector2(-4800, 6350), Vector2(3800, 6350), Vector2(4400, 6300)],
		"mid": [Vector2(-5000, -4650), Vector2(-4350, -3950), Vector2(4350, 3950), Vector2(5000, 4650)],
		"bot": [Vector2(-4350, -6350), Vector2(4800, -6350), Vector2(5900, -5900), Vector2(6450, -4800),
			Vector2(6550, 3500), Vector2(6550, 4350)],
	}
	for k in dawn_lanes:
		lanes[k] = PackedVector2Array(dawn_lanes[k])
	ramps = [
		{"pos": Vector2(-6550, -3700), "radius": 420.0}, {"pos": Vector2(-4300, -6350), "radius": 420.0},
		{"pos": Vector2(-4400, -3850), "radius": 480.0},
	]
	for r in ramps.duplicate():
		ramps.append({"pos": -(r.pos as Vector2), "radius": r.radius})
	var dawn_buildings := [
		["ancient", "ancient", "", 0, Vector2(-5800, -5350)],
		["fountain", "fountain", "", 0, fountains[0]],
		["tower4", "tower4", "", 4, Vector2(-5050, -5700)],
		["tower4", "tower4", "", 4, Vector2(-6150, -4600)],
		["tower3", "tower3", "top", 3, Vector2(-6550, -4050)],
		["melee_rax", "melee_rax", "top", 0, Vector2(-6900, -4550)],
		["ranged_rax", "ranged_rax", "top", 0, Vector2(-6200, -4550)],
		["tower2", "tower2", "top", 2, Vector2(-6300, -900)],
		["tower1", "tower1", "top", 1, Vector2(-6300, 1900)],
		["tower3", "tower3", "mid", 3, Vector2(-4700, -4250)],
		["melee_rax", "melee_rax", "mid", 0, Vector2(-4950, -4800)],
		["ranged_rax", "ranged_rax", "mid", 0, Vector2(-5350, -4400)],
		["tower2", "tower2", "mid", 2, Vector2(-3400, -2900)],
		["tower1", "tower1", "mid", 1, Vector2(-1600, -1350)],
		["tower3", "tower3", "bot", 3, Vector2(-4650, -6350)],
		["melee_rax", "melee_rax", "bot", 0, Vector2(-5100, -6700)],
		["ranged_rax", "ranged_rax", "bot", 0, Vector2(-5100, -6000)],
		["tower2", "tower2", "bot", 2, Vector2(-450, -6350)],
		["tower1", "tower1", "bot", 1, Vector2(4900, -6300)],
		["filler", "filler", "top", 0, Vector2(-7250, -4100)],
		["filler", "filler", "mid", 0, Vector2(-5700, -4300)],
		["filler", "filler", "bot", 0, Vector2(-4650, -7150)],
	]
	buildings.clear()
	var mirror_lane := {"top": "bot", "mid": "mid", "bot": "top", "": ""}
	for team in [C.DAWN, C.DUSK]:
		for b in dawn_buildings:
			var p: Vector2 = b[4] if team == C.DAWN else -(b[4] as Vector2)
			# rotated 180 degrees, Dawn's bottom lane becomes the north edge: Dusk's end of the top lane
			var lane: String = b[2] if team == C.DAWN else mirror_lane[b[2]]
			buildings.append({"unit": b[0], "team": team, "lane": lane, "tier": b[3], "pos": p})
	# Neutral camps. kind: small / medium / large / ancient. The south-east jungle is Dawn's, the north-west Dusk's.
	var dawn_camps := [
		["small", Vector2(1150, -4500), ["mudling", "mudling", "mudling_digger", "mudling_foreman"]],
		["medium", Vector2(-1350, -4150), ["ashfang", "ashfang", "ashfang_alpha"]],
		["large", Vector2(2700, -3900), ["strider", "strider", "strider_warlord"]],
		["ancient", Vector2(450, -2350), ["cinder_wyrmling", "cinder_wyrmling", "elder_cinder_wyrm"]],
		["medium", Vector2(-4450, -650), ["hill_troll", "hill_troll", "ogre_brute"]],
		["large", Vector2(-3250, 1050), ["ogre_brute", "ogre_brute", "strider_warlord"]],
	]
	camps.clear()
	var i := 0
	for side in [C.DAWN, C.DUSK]:
		for c in dawn_camps:
			var p: Vector2 = c[1] if side == C.DAWN else -(c[1] as Vector2)
			camps.append({"id": i, "side": side, "kind": c[0], "pos": p, "box_half": 260.0, "units": c[2]})
			i += 1
	# Jungle walkways: from lanes to camps and between camps, plus river crossings.
	var dawn_paths := [
		[Vector2(-1600, -1350), Vector2(-1350, -4150), Vector2(1150, -4500), Vector2(2700, -3900), Vector2(4300, -6200)],
		[Vector2(-1350, -4150), Vector2(-2500, -6300)],
		[Vector2(-3400, -2900), Vector2(-1350, -4150)],
		[Vector2(450, -2350), Vector2(1150, -4500)],
		[Vector2(450, -2350), Vector2(-700, -700)],
		[Vector2(2700, -3900), Vector2(2900, -2900)],
		[Vector2(-6300, -900), Vector2(-4450, -650), Vector2(-3250, 1050), Vector2(-1600, -1350)],
		[Vector2(-3400, -2900), Vector2(-4450, -650)],
		[Vector2(-3250, 1050), Vector2(-2600, 2600)],
		[Vector2(-5600, -2600), Vector2(-3400, -2900)],
	]
	paths.clear()
	for side in [1.0, -1.0]:
		for pth in dawn_paths:
			var arr := PackedVector2Array()
			for p: Vector2 in pth:
				arr.append(p * side)
			paths.append(arr)

# ---- Terrain ----------------------------------------------------------------------------------------------------------

## Raw (pre-smoothing) level of a world point.
func level_at_raw(p: Vector2) -> int:
	# river: low ground along x + y = 0
	var river_d := absf(p.x + p.y) / sqrt(2.0)
	var river_w := 520.0 + 120.0 * sin(p.x * 0.0011) + 60.0 * sin(p.y * 0.0023)
	if river_d < river_w:
		return RIVER
	if _in_base(p) or _in_base(-p):
		return HIGH
	return GROUND

func _in_base(p: Vector2) -> bool:
	# Dawn's high ground: the south-west block, its north-east corner cut diagonally (the mid ramp sits on the cut)
	if p.x > -4300.0 or p.y > -3700.0:
		return false
	return (p.x + p.y) < -8150.0

func _terrain() -> void:
	level.resize(N * N)
	for cy in N:
		for cx in N:
			level[cy * N + cx] = level_at_raw(cell_center(cx, cy))
	# corner heights: average of the touching cells' levels, with ramps blended, then a few smoothing passes
	var M := N + 1
	height.resize(M * M)
	for vy in M:
		for vx in M:
			var s := 0.0
			var n := 0
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var cx: int = clampi(vx + ox, 0, N - 1)
					var cy: int = clampi(vy + oy, 0, N - 1)
					s += float(level[cy * N + cx])
					n += 1
			height[vy * M + vx] = s / n * C.LEVEL_HEIGHT
	for pass_i in 3:
		var h2 := height.duplicate()
		for vy in range(1, M - 1):
			for vx in range(1, M - 1):
				var p := Vector2(-HALF + vx * CELL, -HALF + vy * CELL)
				var w := _slope_weight(p)
				var avg := (height[vy * M + vx - 1] + height[vy * M + vx + 1] + height[(vy - 1) * M + vx] + height[(vy + 1) * M + vx]) * 0.25
				h2[vy * M + vx] = lerpf(height[vy * M + vx], avg, w)
		height = h2

## How much smoothing a terrain corner gets: river banks and ramps are gentle slopes, base edges stay as cliffs.
func _slope_weight(p: Vector2) -> float:
	for r in ramps:
		if p.distance_to(r.pos) < r.radius:
			return 0.95
	var river_d := absf(p.x + p.y) / sqrt(2.0)
	if river_d < 900.0:
		return 0.85
	return 0.12

## Smooth height (game units) at a world point.
func height_at(p: Vector2) -> float:
	var M := N + 1
	var fx := clampf((p.x + HALF) / CELL, 0.0, N - 0.001)
	var fy := clampf((p.y + HALF) / CELL, 0.0, N - 0.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var h00 := height[y0 * M + x0]
	var h10 := height[y0 * M + x0 + 1]
	var h01 := height[(y0 + 1) * M + x0]
	var h11 := height[(y0 + 1) * M + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)

func level_at(p: Vector2) -> int:
	var c := world_to_cell(p)
	return level[c.y * N + c.x]

func in_ramp(p: Vector2) -> bool:
	for r in ramps:
		if p.distance_to(r.pos) < r.radius:
			return true
	return false

## Cliffs: a high-ground cell next to lower ground is a cliff unless it lies on a ramp.
func is_cliff_cell(cx: int, cy: int) -> bool:
	var l := level[cy * N + cx]
	if l != HIGH:
		return false
	if in_ramp(cell_center(cx, cy)):
		return false
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var nx: int = cx + o.x
		var ny: int = cy + o.y
		if nx < 0 or ny < 0 or nx >= N or ny >= N:
			continue
		if level[ny * N + nx] < HIGH:
			return true
	return false

# ---- Trees ------------------------------------------------------------------------------------------------------------

func _place_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.00042
	noise.fractal_octaves = 3
	trees.clear()
	tree_cell.resize(N * N)
	tree_cell.fill(-1)
	var step := 112.0
	var y := -HALF + 60.0
	while y < HALF - 60.0:
		var x := -HALF + 60.0
		while x < HALF - 60.0:
			var p := Vector2(x + rng.randf_range(-40, 40), y + rng.randf_range(-40, 40))
			x += step
			if not _tree_allowed(p):
				continue
			var edge := maxf(absf(p.x), absf(p.y)) > HALF - 700.0
			var dens := noise.get_noise_2dv(p) * 0.5 + 0.5
			var clear := _clearance(p)
			# thick forest close to the map edge, clumps elsewhere, thinning towards lanes and paths
			var chance := 0.92 if edge else clampf((dens - 0.33) * 2.6, 0.0, 0.95) * clampf((clear - 220.0) / 500.0, 0.25, 1.0)
			if rng.randf() > chance:
				continue
			var c := world_to_cell(p)
			if tree_cell[c.y * N + c.x] >= 0:
				continue
			tree_cell[c.y * N + c.x] = trees.size()
			trees.append({"pos": p, "alive": true, "kind": rng.randi_range(0, 3), "scale": rng.randf_range(0.85, 1.25),
				"regrow": 0.0, "rot": rng.randf() * TAU})
		y += step

## Distance from p to the nearest lane, path, or open area (camp, building, ramp).
func _clearance(p: Vector2) -> float:
	var d := 1e9
	for k in lanes:
		d = minf(d, _polyline_distance(p, lanes[k]))
		d = minf(d, _polyline_distance(-p, lanes[k]))
	for pth in paths:
		d = minf(d, _polyline_distance(p, pth) + 120.0)
	return d

func _tree_allowed(p: Vector2) -> bool:
	if maxf(absf(p.x), absf(p.y)) > HALF - 80.0:
		return false
	var river_d := absf(p.x + p.y) / sqrt(2.0)
	if river_d < 780.0:
		return false
	if _in_base(p) or _in_base(-p):
		return false
	for k in lanes:
		if _polyline_distance(p, lanes[k]) < 430.0:
			return false
	for pth in paths:
		if _polyline_distance(p, pth) < 210.0:
			return false
	for c in camps:
		if p.distance_to(c.pos) < 520.0:
			return false
	for b in buildings:
		if p.distance_to(b.pos) < 520.0:
			return false
	for r in ramps:
		if p.distance_to(r.pos) < r.radius + 200.0:
			return false
	for f in fountains:
		if p.distance_to(f) < 1400.0:
			return false
	return true

static func _polyline_distance(p: Vector2, line: PackedVector2Array) -> float:
	var d := 1e9
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return d

# ---- Pathing grid ---------------------------------------------------------------------------------------------------

func _pathing() -> void:
	walkable.resize(N * N)
	for cy in N:
		for cx in N:
			var ok := 1
			if cx <= 1 or cy <= 1 or cx >= N - 2 or cy >= N - 2:
				ok = 0
			elif tree_cell[cy * N + cx] >= 0:
				ok = 0
			elif is_cliff_cell(cx, cy):
				ok = 0
			walkable[cy * N + cx] = ok
	# buildings block their footprint (fountains are walkable around their centre for heroes to stand in)
	for b in buildings:
		var def := SimData.unit(b.unit)
		if def.is_empty() or def.kind == C.Kind.FOUNTAIN:
			continue
		set_block_circle(b.pos, def.hull * 0.85, false)
	astar.region = Rect2i(0, 0, N, N)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = false
	astar.update()
	for cy in N:
		for cx in N:
			if walkable[cy * N + cx] == 0:
				astar.set_point_solid(Vector2i(cx, cy), true)

func set_block_circle(center: Vector2, radius: float, open: bool) -> void:
	var c0 := world_to_cell(center - Vector2(radius, radius))
	var c1 := world_to_cell(center + Vector2(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if cell_center(cx, cy).distance_to(center) <= radius + CELL * 0.5:
				walkable[cy * N + cx] = 1 if open else 0
				if astar.region.size.x > 0:
					astar.set_point_solid(Vector2i(cx, cy), not open)

## Cut down a tree (it regrows after `regrow` seconds when that is > 0). Returns false if there was none.
func destroy_tree(index: int, regrow_time: float) -> bool:
	if index < 0 or index >= trees.size() or not trees[index].alive:
		return false
	var t: Dictionary = trees[index]
	t.alive = false
	t.regrow = regrow_time
	var c := world_to_cell(t.pos)
	walkable[c.y * N + c.x] = 1
	astar.set_point_solid(c, false)
	var v := world_to_vcell(t.pos)
	vision_block[v.y * VN + v.x] = 0
	_refresh_vision_cell(v)
	return true

func regrow_tree(index: int) -> void:
	var t: Dictionary = trees[index]
	t.alive = true
	var c := world_to_cell(t.pos)
	walkable[c.y * N + c.x] = 0
	astar.set_point_solid(c, true)
	var v := world_to_vcell(t.pos)
	vision_block[v.y * VN + v.x] = 1

func _refresh_vision_cell(v: Vector2i) -> void:
	# another living tree may still stand in this vision cell
	var p0 := vcell_center(v.x, v.y) - Vector2(C.VISION_CELL, C.VISION_CELL) * 0.5
	var c0 := world_to_cell(p0)
	for oy in 2:
		for ox in 2:
			var ti := tree_cell[(c0.y + oy) * N + c0.x + ox]
			if ti >= 0 and trees[ti].alive:
				vision_block[v.y * VN + v.x] = 1
				return

func tree_at(p: Vector2, radius: float) -> int:
	var best := -1
	var bd := radius
	var c0 := world_to_cell(p - Vector2(radius, radius))
	var c1 := world_to_cell(p + Vector2(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var ti := tree_cell[cy * N + cx]
			if ti >= 0 and trees[ti].alive:
				var d: float = (trees[ti].pos as Vector2).distance_to(p)
				if d <= bd:
					bd = d
					best = ti
	return best

## A path for a ground unit from a to b (world points). Grid A* with collinear points removed; units smooth the
## corners as they walk (SimOrders looks ahead along the path). Empty if unreachable.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := world_to_cell(a)
	var cb := world_to_cell(b)
	if not is_walkable_cell(ca):
		ca = nearest_walkable(ca)
	if not is_walkable_cell(cb):
		cb = nearest_walkable(cb)
		b = cell_center(cb.x, cb.y)
	if ca == cb:
		return PackedVector2Array([b])
	if a.distance_squared_to(b) < 2000.0 * 2000.0 and line_walkable(a, b):
		return PackedVector2Array([b])
	var ids := astar.get_id_path(ca, cb, true)
	if ids.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	var prev_dir := Vector2i.ZERO
	for i in range(1, ids.size()):
		var d: Vector2i = ids[i] - ids[i - 1]
		if d != prev_dir and i > 1:
			out.append(cell_center(ids[i - 1].x, ids[i - 1].y))
		prev_dir = d
	out.append(b)
	return out

func is_walkable_cell(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return false
	return walkable[c.y * N + c.x] == 1

func is_walkable(p: Vector2) -> bool:
	return is_walkable_cell(world_to_cell(p))

func nearest_walkable(c: Vector2i) -> Vector2i:
	for r in range(1, 24):
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if absi(ox) != r and absi(oy) != r:
					continue
				var t := Vector2i(c.x + ox, c.y + oy)
				if is_walkable_cell(t):
					return t
	return c

## Whether a straight walk from a to b crosses only walkable cells (exact grid traversal).
func line_walkable(a: Vector2, b: Vector2) -> bool:
	var fx := (a.x + HALF) / CELL
	var fy := (a.y + HALF) / CELL
	var tx := (b.x + HALF) / CELL
	var ty := (b.y + HALF) / CELL
	var x := int(floor(fx))
	var y := int(floor(fy))
	var ex := int(floor(tx))
	var ey := int(floor(ty))
	var dx := tx - fx
	var dy := ty - fy
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var tdx := absf(1.0 / dx) if dx != 0.0 else INF
	var tdy := absf(1.0 / dy) if dy != 0.0 else INF
	var tmx := INF
	var tmy := INF
	if dx != 0.0:
		tmx = ((floor(fx) + 1.0 - fx) if dx > 0.0 else (fx - floor(fx))) * tdx
	if dy != 0.0:
		tmy = ((floor(fy) + 1.0 - fy) if dy > 0.0 else (fy - floor(fy))) * tdy
	var guard := 0
	while guard < 1024:
		guard += 1
		if x < 0 or y < 0 or x >= N or y >= N or walkable[y * N + x] == 0:
			return false
		if x == ex and y == ey:
			return true
		if tmx < tmy:
			tmx += tdx
			x += sx
		else:
			tmy += tdy
			y += sy
	return true

# ---- Vision grid ------------------------------------------------------------------------------------------------------

func _vision_grid() -> void:
	vision_block.resize(VN * VN)
	vision_level.resize(VN * VN)
	vision_block.fill(0)
	for vy in VN:
		for vx in VN:
			var p := vcell_center(vx, vy)
			# the level of a vision cell is its centre's; ramp cells count as the lower side
			var l := level_at(p)
			if in_ramp(p):
				l = mini(l, GROUND)
			vision_level[vy * VN + vx] = l
	for t in trees:
		if t.alive:
			var v := world_to_vcell(t.pos)
			vision_block[v.y * VN + v.x] = 1

# ---- Coordinates ------------------------------------------------------------------------------------------------------

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + HALF) / CELL), 0, N - 1), clampi(int((p.y + HALF) / CELL), 0, N - 1))

func cell_center(cx: int, cy: int) -> Vector2:
	return Vector2(-HALF + (cx + 0.5) * CELL, -HALF + (cy + 0.5) * CELL)

func world_to_vcell(p: Vector2) -> Vector2i:
	var s := C.VISION_CELL
	return Vector2i(clampi(int((p.x + HALF) / s), 0, VN - 1), clampi(int((p.y + HALF) / s), 0, VN - 1))

func vcell_center(vx: int, vy: int) -> Vector2:
	var s := C.VISION_CELL
	return Vector2(-HALF + (vx + 0.5) * s, -HALF + (vy + 0.5) * s)

## A team's lane path, ordered from that team's base towards the enemy's (empty for an unknown lane).
var _lane_cache := {}

func lane_path(lane: String, team: int) -> PackedVector2Array:
	var key := "%s:%d" % [lane, team]
	if _lane_cache.has(key):
		return _lane_cache[key]
	var out := PackedVector2Array()
	if lanes.has(lane):
		if team == C.DAWN:
			out = lanes[lane]
		else:
			# Dusk walks the mirrored lane: its "top" is Dawn's "bot" rotated, so it runs along the same north edge
			var mirror_of := {"top": "bot", "mid": "mid", "bot": "top"}
			for p in lanes[mirror_of[lane]]:
				out.append(-p)
	_lane_cache[key] = out
	return out
