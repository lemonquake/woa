class_name SimMap
extends RefCounted
## The battlefield: terrain levels (river / ground / high ground), cliffs and ramps, trees, the pathing grid, lanes,
## building sites and neutral camps. Built deterministically from a seed; both the simulation and the renderer read it.
##
## Layout follows the classic three-lane map: Dawn's base in the south-west corner, Dusk's in the north-east, the
## river running north-west to south-east through the middle. Dusk's half is Dawn's rotated 180 degrees (p -> -p).

const C = preload("res://src/sim/sim_const.gd")
const N := 288                             # pathing cells per side (64 units each)
const CELL := 64.0
const HALF := 9216.0
const VN := 144                            # vision cells per side (128 units each)
## The classic map's half size. Lanes, bases and the jungle lie inside it; the map reaches 1024 further on every side,
## open beyond the top and bottom lanes and in the two river corners, rock beside the bases (see is_mountain).
const OLD_HALF := 8192.0
const EDGE := HALF - 292.0                 # units never stand farther out than this

# Terrain levels
const RIVER := 0
const GROUND := 1
const HIGH := 2
const MOUNTAIN := 3                        # impassable rock massifs at the corners and edges (block sight)

## Jungle plateaus (Dawn's side; Dusk's are the same rotated 180 degrees): high ground with cliffs, reached by ramps
## where jungle walkways cross their edges. [centre, half-axes, angle in degrees].
const PLATEAUS := [
	[Vector2(2200, -4500), Vector2(1250, 820), -20.0],   # the hard camp bluff (large and small camps)
	[Vector2(-2400, -5100), Vector2(1100, 600), 8.0],     # the west ridge above the bottom lane
	[Vector2(950, -3050), Vector2(720, 480), -40.0],      # the ancient camp terrace
	[Vector2(-3900, 250), Vector2(1280, 800), 55.0],      # the off-lane bluff with two camps
	[Vector2(-5000, 2750), Vector2(760, 460), 75.0],      # a lookout above the top lane
]

var seed_value := 1
var level := PackedByteArray()             # N*N terrain level per path cell
var height := PackedFloat32Array()         # (N+1)*(N+1) smooth corner heights in game units (for rendering + z)
var walkable := PackedByteArray()          # N*N 1 = walkable for ground units (static: terrain + trees + buildings)
var tree_cell := PackedInt32Array()        # N*N index into trees or -1
var rock := PackedByteArray()              # N*N resting boulders on the cell (Summon Boulders); blocks walking
var trees: Array = []                      # [{pos, alive, kind, scale, regrow (s left, <= 0 = not regrowing), rot,
                                           #   planted: true for Ironwood Twig trees, expires, under (cell's old index)}]
var astar := AStarGrid2D.new()
var vision_block := PackedByteArray()      # VN*VN 1 = a tree stands here (blocks sight beyond)
var vision_level := PackedByteArray()
var vision_rev := 0                         # bumped whenever vision_block changes (SimVision's sight cache)
var vision_changes: Array[Vector2i] = []    # the vision cells changed since SimVision last looked (it clears this)

var lanes := {}                            # "top"/"mid"/"bot" -> PackedVector2Array from Dawn's base to Dusk's
var ramps: Array = []                      # [{pos: Vector2, radius: float}]
var buildings: Array = []                  # [{id, team, pos, lane, tier, name}]
var camps: Array = []                      # [{id, side, kind, pos, box (half size), box_half, pull, units: the first spawn's group}]

## The creep groups a camp of each kind can spawn (a camp picks one at random each time, never the same twice in a
## row), after Dota's groups: small = kobolds / hill trolls with a kobold foreman; medium = wolves, centaurs, trolls
## with an ogre; large = centaurs, ogres; ancient = black dragons.
const CAMP_GROUPS := {
	"small": [["mudling", "mudling", "mudling", "mudling_digger", "mudling_foreman"],
		["hill_troll", "hill_troll", "mudling_foreman"]],
	"medium": [["ashfang", "ashfang", "ashfang_alpha"], ["strider", "strider_warlord"],
		["hill_troll", "hill_troll", "ogre_brute"]],
	"large": [["strider", "strider", "strider_warlord"], ["ogre_brute", "ogre_brute", "strider_warlord"]],
	"ancient": [["cinder_wyrmling", "cinder_wyrmling", "elder_cinder_wyrm"]],
}
var fountains := [Vector2(-7050, -6650), Vector2(7050, 6650)]
var shops := [Vector2(-6700, -6200), Vector2(6700, 6200)]
var paths: Array = []                      # jungle walkways (PackedVector2Array), kept clear of trees
var classic_paths: Array = []              # the walkways of the classic map (they shaped its forest)
var plateau_ramps: Array = []              # the ramps made where walkways cross plateau edges (also in ramps)
var sites: Array = []                      # [{kind: "gate" | "pond" | "lamp", pos, exit, pair}] (SimSites)

# ---- Construction ---------------------------------------------------------------------------------------------------

func build(p_seed := 1) -> void:
	seed_value = p_seed
	_layout()
	_plateau_ramps()
	_terrain()
	_place_trees()
	_pathing()
	_vision_grid()

## Buildings moved after the forest was laid out: new spot (Dawn's) -> the old one, which the forest still keeps clear
## of, so every tree stands where it stood (the forest's random numbers depend on which spots it may use).
const GROVE_SPOT := {Vector2(-4600, -4550): Vector2(-4700, -4250)}

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
		# beside the lane, back from the top of the mid ramp (it stood in the ramp's mouth, at the head of the stairs)
		["tower3", "tower3", "mid", 3, Vector2(-4600, -4550)],
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
			buildings.append({"unit": b[0], "team": team, "lane": lane, "tier": b[3], "pos": p,
				"grove": p if not GROVE_SPOT.has(b[4]) else (GROVE_SPOT[b[4]] if team == C.DAWN else -(GROVE_SPOT[b[4]] as Vector2))})
	# Neutral camps, as in Dota 2 (7.41): 14 a side, 3 small, 7 medium, 3 large, 1 ancient. The south-east jungle
	# (between mid and the bottom lane) is Dawn's main jungle, the "triangle" between the top lane and mid its off-lane
	# jungle; Dusk's are the same rotated 180 degrees. [kind, centre, spawn box half size, pull camp]. Pull camps sit
	# beside the safe lane's tier 1 tower: lane creeps fight only their neutrals (research/camps.md).
	var dawn_camps := [
		["small", Vector2(3300, -5600), Vector2(260, 220), true],      # small pull camp by the safe tier 1
		["medium", Vector2(-1350, -4150), Vector2(300, 260), false],   # main jungle, between the tier 2 towers
		["large", Vector2(1900, -5600), Vector2(330, 270), true],      # large pull camp by the safe tier 1, clear of the lane
		["medium", Vector2(800, -2150), Vector2(300, 260), false],     # by the river, below the mid tier 1
		["medium", Vector2(-5150, -1250), Vector2(300, 260), false],   # off-lane jungle below the bluff
		["large", Vector2(-3670, 910), Vector2(330, 270), false],      # off-lane bluff (high ground)
		["medium", Vector2(2350, -4750), Vector2(300, 260), false],    # main jungle high ground
		["large", Vector2(-700, -2900), Vector2(330, 270), false],     # main jungle by the mid tier 1
		["medium", Vector2(-2400, -5100), Vector2(300, 260), false],   # west ridge near the base (high ground)
		["medium", Vector2(500, -5200), Vector2(300, 260), false],     # by the safe lane's tier 2, clear of the lane
		["medium", Vector2(-2700, -900), Vector2(300, 260), false],    # triangle, by the mid tier 1
		["ancient", Vector2(-3900, 2000), Vector2(360, 300), false],   # triangle ancient camp
		["small", Vector2(-5200, -2250), Vector2(260, 220), false],    # by the off lane's gate near the base
		["small", Vector2(1500, -7150), Vector2(260, 220), false],     # outside the safe lane, by the map edge
	]
	camps.clear()
	var i := 0
	for side in [C.DAWN, C.DUSK]:
		for c in dawn_camps:
			var p: Vector2 = c[1] if side == C.DAWN else -(c[1] as Vector2)
			camps.append({"id": i, "side": side, "kind": c[0], "pos": p, "box": c[2], "box_half": maxf(c[2].x, c[2].y),
				"pull": c[3], "units": CAMP_GROUPS[c[0]][i % (CAMP_GROUPS[c[0]] as Array).size()]})
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
		# walkways to the camps added for the 14-camp layout
		[Vector2(800, -6300), Vector2(500, -5200), Vector2(1150, -4500)],
		[Vector2(1900, -5600), Vector2(2300, -6300)],
		[Vector2(3300, -5600), Vector2(3300, -6300)],
		[Vector2(-700, -2900), Vector2(-1450, -2900)],
		[Vector2(-700, -2900), Vector2(450, -2350)],
		[Vector2(-2700, -900), Vector2(-2250, -1600)],
		[Vector2(-3900, 2000), Vector2(-3250, 1050)],
		[Vector2(-3900, 2000), Vector2(-6400, 1700)],
		[Vector2(-5200, -2250), Vector2(-5600, -2600)],
		[Vector2(1500, -7150), Vector2(1500, -6400)],
	]
	# the outer ground (added 2026-10-17 with the larger map)
	var outer_paths := [
		# beyond the bottom lane: from the lane by the tier 2 tower, past the edge camp and the lamp, to
		# the Warp Gate in the river corner and back up to the lane's bend
		[Vector2(-450, -6450), Vector2(-150, -7550), Vector2(1500, -8000), Vector2(2600, -8250), Vector2(4700, -8350),
			Vector2(6350, -8000)],
		[Vector2(1500, -7150), Vector2(1500, -8000)],
		[Vector2(6350, -8000), Vector2(5600, -6950), Vector2(5150, -6300)],
		[Vector2(6350, -8000), Vector2(7300, -7650)],
		# west of the top lane's north end: from the lane by the tier 1 tower, past the lamp, to the Lily Pond on the
		# river bank and on to the lane's bend
		[Vector2(-6350, 2450), Vector2(-7500, 3200), Vector2(-8250, 4300), Vector2(-8150, 5800), Vector2(-8100, 6700)],
		[Vector2(-8100, 6700), Vector2(-7200, 6700), Vector2(-6250, 5600)],
	]
	# Map sites (SimSites) in the outer ground, Dawn's half; Dusk's are the same rotated 180 degrees. Each river corner
	# holds a Warp Gate on one bank and a Lily Pond on the other; the two gates are linked. [kind, spot, exit offset].
	var dawn_sites := [
		["gate", Vector2(6700, -8350), Vector2(-260, 250)],
		["pond", Vector2(-8350, 6900), Vector2.ZERO],
		["lamp", Vector2(2700, -8550), Vector2.ZERO],
		["lamp", Vector2(-8600, 4250), Vector2.ZERO],
	]
	sites.clear()
	for side in [1.0, -1.0]:
		for st in dawn_sites:
			var sp: Vector2 = st[1] * side
			sites.append({"kind": st[0], "pos": sp, "exit": sp + st[2] * side, "pair": -1})
	var gates: Array = []
	for si in sites.size():
		if String(sites[si].kind) == "gate":
			gates.append(si)
	if gates.size() == 2:
		sites[gates[0]].pair = gates[1]
		sites[gates[1]].pair = gates[0]
	paths.clear()
	classic_paths.clear()
	for side in [1.0, -1.0]:
		for pth in dawn_paths + outer_paths:
			var arr := PackedVector2Array()
			for p: Vector2 in pth:
				arr.append(p * side)
			paths.append(arr)
			if pth in dawn_paths:
				classic_paths.append(arr)

# ---- Terrain ----------------------------------------------------------------------------------------------------------

## Raw (pre-smoothing) level of a world point.
func level_at_raw(p: Vector2) -> int:
	# river: low ground along x + y = 0
	var river_d := absf(p.x + p.y) / sqrt(2.0)
	var river_w := 500.0 + 120.0 * cos(p.x * 0.0011) + 60.0 * cos(p.y * 0.0023)    # even in p: both banks match
	if river_d < river_w:
		return RIVER
	if is_mountain(p):
		return MOUNTAIN
	if _in_base(p) or _in_base(-p):
		return HIGH
	if _on_plateau(p) or _on_plateau(-p):
		return HIGH
	return GROUND

## Mountains (symmetric under p -> -p; stated for Dawn's half, x + y < 0):
##   * the massif behind Dawn's fountain, in the classic map's south-west corner;
##   * a ragged band along the edge. Beside the bases the band stays at the classic edge (everything past it is rock);
##     beyond the bottom lane (Dawn's half; the top lane on Dusk's) and west of the top lane's north end (Dusk's: east
##     of the bottom lane's south end) it moves out to the map's edge, opening the outer ground (outer_open);
##   * small massifs right in the two river corners, where the river leaves the map through a gorge.
## Kept clear of lanes, the river and the fountains.
func is_mountain(p: Vector2) -> bool:
	var q := p if (p.x + p.y) < 0.0 or ((p.x + p.y) == 0.0 and p.x < 0.0) else -p
	var river_d := absf(q.x + q.y) / sqrt(2.0)
	if river_d < 900.0:
		return false
	var wob := 160.0 * sin(q.x * 0.0021 + 1.3) + 120.0 * sin(q.y * 0.0017 + 0.4) + 70.0 * sin((q.x - q.y) * 0.0043)
	# corner behind Dawn's fountain (south-west)
	if q.distance_to(OLD_HALF * Vector2(-1, -1)) < 1450.0 + wob:
		return true
	# the river corners (north-west / south-east, mirrored): small massifs beside the river's gorge
	for c in [Vector2(-HALF, HALF), Vector2(HALF, -HALF)]:
		if q.distance_to(c) < 1500.0 + wob and river_d > 1050.0 + wob * 0.5:
			return true
	var edge := edge_distance(q, wob)
	if edge < 0.0:
		return true                        # past the classic edge beside the bases
	if edge < 260.0 + maxf(0.0, wob) * 0.8:
		return _lane_clear(q, 900.0) and q.distance_to(fountains[0]) > 1300.0
	return false

## Whether a point of Dawn's half (x + y < 0) lies in the outer ground: south of the bottom lane east of Dawn's base, or
## west of the top lane north of its tier 1 tower. `wob` ragged-edges the border with the rock beside the bases.
static func outer_open(q: Vector2, wob := 0.0) -> bool:
	if q.y < -5200.0 and q.x > -3900.0 + wob * 2.0:
		return true
	return q.x < -5200.0 and q.y > 1700.0 + wob * 2.0

## Distance from a point to the map's working edge: the map's own edge in the outer ground, the classic edge elsewhere
## (negative past it). Symmetric under p -> -p.
func edge_distance(p: Vector2, wob := 0.0) -> float:
	var q := p if (p.x + p.y) < 0.0 or ((p.x + p.y) == 0.0 and p.x < 0.0) else -p
	var bound := HALF if outer_open(q, wob) else OLD_HALF
	return bound - maxf(absf(q.x), absf(q.y))

func _lane_clear(p: Vector2, r: float) -> bool:
	for k in lanes:
		if _polyline_distance(p, lanes[k]) < r or _polyline_distance(-p, lanes[k]) < r:
			return false
	return true

## Whether a point (Dawn's side) is on a jungle plateau. Plateaus keep away from lanes, the river and buildings.
func _on_plateau(p: Vector2) -> bool:
	if (p.x + p.y) >= 0.0:
		return false
	for pl in PLATEAUS:
		var d: Vector2 = (p - (pl[0] as Vector2)).rotated(-deg_to_rad(float(pl[2])))
		var ax: Vector2 = pl[1]
		var wob := 1.0 + 0.08 * sin(atan2(d.y, d.x) * 5.0 + float(pl[2]))
		if (d.x * d.x) / (ax.x * ax.x) + (d.y * d.y) / (ax.y * ax.y) > wob * wob:
			continue
		if absf(p.x + p.y) / sqrt(2.0) < 1050.0:
			return false
		if not _lane_clear(p, 560.0):
			return false
		for b in buildings:
			if p.distance_to(b.grove) < 700.0:
				return false
		return true
	return false

## Ramps where the jungle walkways cross plateau edges (merged when close), added to `ramps` with their mirrors.
func _plateau_ramps() -> void:
	plateau_ramps.clear()
	var found: Array = []
	for pth: PackedVector2Array in paths:
		if (pth[0].x + pth[0].y) > 0.0:
			continue                       # Dusk's walkways: mirrored below
		for i in pth.size() - 1:
			var a := pth[i]
			var b := pth[i + 1]
			var steps := int(a.distance_to(b) / 24.0) + 1
			var prev := _on_plateau(a)
			for s2 in range(1, steps + 1):
				var q := a.lerp(b, float(s2) / steps)
				var cur := _on_plateau(q)
				if cur != prev:
					var near := false
					for f: Vector2 in found:
						if f.distance_to(q) < 520.0:
							near = true
					if not near:
						found.append(q)
				prev = cur
	# a plateau no walkway crosses gets one ramp on the side facing the nearest lane
	for pl in PLATEAUS:
		var c: Vector2 = pl[0]
		var has := false
		for f: Vector2 in found:
			if f.distance_to(c) < (pl[1] as Vector2).x + 400.0:
				has = true
		if has or not _on_plateau(c):
			continue
		var best := Vector2.ZERO
		var best_d := INF
		for k in lanes:
			for side in [1.0, -1.0]:
				var ln: PackedVector2Array = lanes[k]
				for i in ln.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(c, ln[i] * side, ln[i + 1] * side)
					if q.distance_to(c) < best_d:
						best_d = q.distance_to(c)
						best = q
		var dir := (best - c).normalized()
		var q2 := c
		while _on_plateau(q2) and q2.distance_to(c) < 3000.0:
			q2 += dir * 24.0
		found.append(q2)
	for f: Vector2 in found:
		var r := {"pos": f, "radius": 320.0, "plateau": true}
		plateau_ramps.append(r)
		ramps.append(r)
		var m := {"pos": -f, "radius": 320.0, "plateau": true}
		plateau_ramps.append(m)
		ramps.append(m)

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
	if is_mountain(p):
		return 0.3
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

## The forest. The classic map's forest is placed first exactly as it was (the same random numbers under the classic
## rules, so every tree a test or a habit relies on stands where it stood), less the trees the new walkways and sites
## need gone; then the new ground (beyond the classic edge and where the classic map had rock) is planted with its own
## random numbers.
func _place_trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.00042
	noise.fractal_octaves = 3
	trees.clear()
	tree_cell.resize(N * N)
	tree_cell.fill(-1)
	var step := 112.0
	# 1) the classic forest
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var taken := {}
	var classic: Array = []
	_classic = true
	var y := -OLD_HALF + 60.0
	while y < OLD_HALF - 60.0:
		var x := -OLD_HALF + 60.0
		while x < OLD_HALF - 60.0:
			var p := Vector2(x + rng.randf_range(-40, 40), y + rng.randf_range(-40, 40))
			x += step
			if not _tree_allowed(p):
				continue
			var edge := maxf(absf(p.x), absf(p.y)) > OLD_HALF - 700.0
			var dens := noise.get_noise_2dv(p) * 0.5 + 0.5
			var clear := _clearance(p)
			# thick forest close to the map edge, clumps elsewhere, thinning towards lanes and paths
			var chance := 0.92 if edge else clampf((dens - 0.33) * 2.6, 0.0, 0.95) * clampf((clear - 220.0) / 500.0, 0.25, 1.0)
			if rng.randf() > chance:
				continue
			var c := world_to_cell(p)
			if taken.has(c):
				continue
			taken[c] = true
			classic.append({"pos": p, "alive": true, "kind": rng.randi_range(0, 3), "scale": rng.randf_range(0.85, 1.25),
				"regrow": 0.0, "rot": rng.randf() * TAU})
		y += step
	_classic = false
	for t in classic:
		if _tree_allowed(t.pos):
			_add_tree(t)
	# 2) the new ground
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = seed_value * 104729 + 31
	y = -HALF + 60.0
	while y < HALF - 60.0:
		var x := -HALF + 60.0
		while x < HALF - 60.0:
			var p := Vector2(x + rng2.randf_range(-40, 40), y + rng2.randf_range(-40, 40))
			x += step
			var roll := rng2.randf()
			var kind := rng2.randi_range(0, 3)
			var sc := rng2.randf_range(0.85, 1.25)
			var rot := rng2.randf() * TAU
			if _classic_ground(p) or not _tree_allowed(p):
				continue
			var edge := edge_distance(p) < 700.0
			var dens := noise.get_noise_2dv(p) * 0.5 + 0.5
			var chance := 0.92 if edge else clampf((dens - 0.3) * 2.6, 0.0, 0.95) * clampf((_clearance(p) - 220.0) / 500.0, 0.25, 1.0)
			if roll > chance:
				continue
			_add_tree({"pos": p, "alive": true, "kind": kind, "scale": sc, "regrow": 0.0, "rot": rot})
		y += step

func _add_tree(t: Dictionary) -> void:
	var c := world_to_cell(t.pos)
	if tree_cell[c.y * N + c.x] >= 0:
		return
	tree_cell[c.y * N + c.x] = trees.size()
	trees.append(t)

## While true, the map answers tree placement questions with the classic map's rules (its edge, its rock, its walkways).
var _classic := false

## Whether the classic map could have grown a tree at p (it decided there, and the new planting leaves p alone).
func _classic_ground(p: Vector2) -> bool:
	_classic = true
	var ok := maxf(absf(p.x), absf(p.y)) <= OLD_HALF - 80.0 and _tree_allowed(p)
	_classic = false
	return ok

## The classic map's rock (its corner massifs and edge band) at a terrain cell's centre, as its level grid had it.
func _classic_rock(p: Vector2) -> bool:
	var cc := world_to_cell(p)
	var q := cell_center(cc.x, cc.y)
	var river_d0 := absf(q.x + q.y) / sqrt(2.0)
	if river_d0 < 500.0 + 120.0 * cos(q.x * 0.0011) + 60.0 * cos(q.y * 0.0023):
		return false
	q = q if (q.x + q.y) < 0.0 or ((q.x + q.y) == 0.0 and q.x < 0.0) else -q
	var river_d := absf(q.x + q.y) / sqrt(2.0)
	if river_d < 900.0:
		return false
	var wob := 160.0 * sin(q.x * 0.0021 + 1.3) + 120.0 * sin(q.y * 0.0017 + 0.4) + 70.0 * sin((q.x - q.y) * 0.0043)
	if q.distance_to(OLD_HALF * Vector2(-1, -1)) < 1450.0 + wob:
		return true
	for c in [Vector2(-OLD_HALF, OLD_HALF), Vector2(OLD_HALF, -OLD_HALF)]:
		if q.distance_to(c) < 3100.0 + wob * 1.5 and river_d > 1050.0 + wob * 0.5:
			return _lane_clear(q, 800.0)
	var edge := OLD_HALF - maxf(absf(q.x), absf(q.y))
	if edge < 260.0 + maxf(0.0, wob) * 0.8:
		return _lane_clear(q, 900.0) and q.distance_to(fountains[0]) > 1300.0
	return false

## Distance from p to the nearest lane, path, or open area (camp, building, ramp).
func _clearance(p: Vector2) -> float:
	var d := 1e9
	for k in lanes:
		d = minf(d, _polyline_distance(p, lanes[k]))
		d = minf(d, _polyline_distance(-p, lanes[k]))
	for pth in (classic_paths if _classic else paths):
		d = minf(d, _polyline_distance(p, pth) + 120.0)
	return d

func _tree_allowed(p: Vector2) -> bool:
	if maxf(absf(p.x), absf(p.y)) > (OLD_HALF if _classic else HALF) - 80.0:
		return false
	var river_d := absf(p.x + p.y) / sqrt(2.0)
	if river_d < 780.0:
		return false
	if _classic_rock(p) if _classic else level_at(p) == MOUNTAIN:
		return false
	if _in_base(p) or _in_base(-p):
		# groves inside the bases: only well away from lanes, buildings and the fountain
		var q := p if _in_base(p) else -p
		if q.distance_to(fountains[0]) < 1700.0 or not _lane_clear(q, 650.0):
			return false
		for b in buildings:
			if q.distance_to(b.grove if b.team == C.DAWN else -(b.grove as Vector2)) < 700.0:
				return false
	for k in lanes:
		if _polyline_distance(p, lanes[k]) < 430.0:
			return false
	for pth in (classic_paths if _classic else paths):
		if _polyline_distance(p, pth) < 210.0:
			return false
	for c in camps:
		if p.distance_to(c.pos) < 520.0:
			return false
	for b in buildings:
		if p.distance_to(b.grove) < 520.0:
			return false
	for r in ramps:
		if p.distance_to(r.pos) < r.radius + 200.0:
			return false
	for f in fountains:
		if p.distance_to(f) < 1400.0:
			return false
	if not _classic:
		for st in sites:
			if p.distance_to(st.pos) < 520.0:
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
			elif is_cliff_cell(cx, cy) or level[cy * N + cx] == MOUNTAIN:
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

## A destroyed building leaves no footprint: its cells open again unless the border, a cliff, a living tree, a
## resting boulder or a building still standing (`standing`: [[pos, radius]]) holds them.
func open_building(center: Vector2, radius: float, standing: Array = []) -> void:
	var c0 := world_to_cell(center - Vector2(radius, radius))
	var c1 := world_to_cell(center + Vector2(radius, radius))
	for cy in range(maxi(2, c0.y), mini(N - 3, c1.y) + 1):
		for cx in range(maxi(2, c0.x), mini(N - 3, c1.x) + 1):
			if cell_center(cx, cy).distance_to(center) > radius + CELL * 0.5:
				continue
			var i := cy * N + cx
			var ti := tree_cell[i]
			if ti >= 0 and trees[ti].alive or rock_at(Vector2i(cx, cy)) > 0:
				continue
			if is_cliff_cell(cx, cy) or level[i] == MOUNTAIN:
				continue
			var held := false
			for sb: Array in standing:
				if cell_center(cx, cy).distance_to(sb[0]) <= float(sb[1]) + CELL * 0.5:
					held = true
					break
			if held:
				continue
			walkable[i] = 1
			astar.set_point_solid(Vector2i(cx, cy), false)

## Cut down a tree (it regrows after `regrow_time` seconds when that is > 0; planted trees never regrow). Returns
## false if there was none.
func destroy_tree(index: int, regrow_time: float) -> bool:
	if index < 0 or index >= trees.size() or not trees[index].alive:
		return false
	var t: Dictionary = trees[index]
	t.alive = false
	t.regrow = 0.0 if t.get("planted", false) else regrow_time
	var c := world_to_cell(t.pos)
	var rocked := rock_at(c) > 0
	walkable[c.y * N + c.x] = 0 if rocked else 1
	astar.set_point_solid(c, rocked)
	if t.get("planted", false):
		# give the cell back to the natural tree (alive or not) that stood there before
		tree_cell[c.y * N + c.x] = int(t.get("under", -1))
		var u := int(t.get("under", -1))
		if u >= 0 and trees[u].alive:
			walkable[c.y * N + c.x] = 0
			astar.set_point_solid(c, true)
	var v := world_to_vcell(t.pos)
	vision_block[v.y * VN + v.x] = 0
	vision_rev += 1
	vision_changes.append(v)
	_refresh_vision_cell(v)
	return true

func regrow_tree(index: int) -> void:
	var t: Dictionary = trees[index]
	t.alive = true
	t.regrow = 0.0
	var c := world_to_cell(t.pos)
	walkable[c.y * N + c.x] = 0
	astar.set_point_solid(c, true)
	var v := world_to_vcell(t.pos)
	vision_block[v.y * VN + v.x] = 1
	vision_rev += 1
	vision_changes.append(v)

## Resting boulders: their cells (centres within `radius`) stop walking units and paths until remove_rock. Returns the
## cells taken (to give back later). Cells already blocked by terrain, trees or buildings are left alone.
func add_rock(center: Vector2, radius: float) -> Array:
	if rock.size() != N * N:
		rock.resize(N * N)
	var out: Array = []
	var c0 := world_to_cell(center - Vector2(radius, radius))
	var c1 := world_to_cell(center + Vector2(radius, radius))
	for cy in range(maxi(0, c0.y), mini(N - 1, c1.y) + 1):
		for cx in range(maxi(0, c0.x), mini(N - 1, c1.x) + 1):
			if cell_center(cx, cy).distance_to(center) > radius + CELL * 0.25:
				continue
			var i := cy * N + cx
			if rock[i] == 0 and walkable[i] == 0:
				continue
			rock[i] = mini(255, rock[i] + 1)
			walkable[i] = 0
			astar.set_point_solid(Vector2i(cx, cy), true)
			out.append(Vector2i(cx, cy))
	return out

func remove_rock(cells: Array) -> void:
	for c: Vector2i in cells:
		var i := c.y * N + c.x
		if rock.size() != N * N or rock[i] == 0:
			continue
		rock[i] -= 1
		if rock[i] == 0:
			var ti := tree_cell[i]
			var open: bool = not (ti >= 0 and trees[ti].alive)
			walkable[i] = 1 if open else 0
			astar.set_point_solid(c, not open)

func rock_at(c: Vector2i) -> int:
	if rock.size() != N * N or c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return 0
	return rock[c.y * N + c.x]

## Whether a fallen natural tree may grow back now: its cell must not hold a planted tree.
func can_regrow(index: int) -> bool:
	var c := world_to_cell(trees[index].pos)
	var cur := tree_cell[c.y * N + c.x]
	return cur == index

## Whether a tree may be planted at p: open, walkable ground away from the fountains (Dota bars the fountain area).
func can_plant(p: Vector2) -> bool:
	var c := world_to_cell(p)
	if c.x <= 1 or c.y <= 1 or c.x >= N - 2 or c.y >= N - 2 or is_cliff_cell(c.x, c.y):
		return false
	if walkable[c.y * N + c.x] == 0:
		return false
	for f in fountains:
		if p.distance_to(f) < 1200.0:
			return false
	return true

## Ironwood Twig: a planted tree at p for `duration` seconds (expires at game time `until`). Returns its index, or -1
## when the ground cannot take a tree (cliff, building, water's edge, another living tree).
func plant_tree(p: Vector2, until: float) -> int:
	if not can_plant(p):
		return -1
	var c := world_to_cell(p)
	var under := tree_cell[c.y * N + c.x]
	var idx := trees.size()
	trees.append({"pos": cell_center(c.x, c.y), "alive": false, "kind": 0, "scale": 0.8, "regrow": 0.0, "rot": 0.0,
		"planted": true, "expires": until, "under": under})
	tree_cell[c.y * N + c.x] = idx
	regrow_tree(idx)
	return idx

func _refresh_vision_cell(v: Vector2i) -> void:
	# another living tree may still stand in this vision cell
	var p0 := vcell_center(v.x, v.y) - Vector2(C.VISION_CELL, C.VISION_CELL) * 0.5
	var c0 := world_to_cell(p0)
	for oy in 2:
		for ox in 2:
			var ti := tree_cell[(c0.y + oy) * N + c0.x + ox]
			if ti >= 0 and trees[ti].alive:
				vision_block[v.y * VN + v.x] = 1
				vision_rev += 1
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

## Whether sight from a to b is cut by a tree or higher ground (the vision cells between them, as SimVision casts
## sight). Bots use it to pick escape spots a chaser cannot see.
func sight_blocked(a: Vector2, b: Vector2) -> bool:
	var ca := world_to_vcell(a)
	var cb := world_to_vcell(b)
	var lvl := vision_level[ca.y * VN + ca.x]
	var n := maxi(absi(cb.x - ca.x), absi(cb.y - ca.y))
	for i in range(1, n):
		var f := float(i) / float(n)
		var cx := int(round(lerpf(ca.x, cb.x, f)))
		var cy := int(round(lerpf(ca.y, cb.y, f)))
		var idx := cy * VN + cx
		if vision_block[idx] == 1 or vision_level[idx] > lvl:
			return true
	return vision_level[cb.y * VN + cb.x] > lvl

## How many tree cells stand within `rc` vision cells of a point (0 in the open, high in a wood).
func tree_cover(p: Vector2, rc := 2) -> int:
	var c := world_to_vcell(p)
	var n := 0
	for oy in range(-rc, rc + 1):
		for ox in range(-rc, rc + 1):
			var x := c.x + ox
			var y := c.y + oy
			if x >= 0 and y >= 0 and x < VN and y < VN and vision_block[y * VN + x] == 1:
				n += 1
	return n

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
