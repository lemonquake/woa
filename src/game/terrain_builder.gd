class_name TerrainBuilder
extends RefCounted
## Builds the rendered terrain from the simulation map: an 8x8 grid of chunk meshes (32-unit vertex spacing) with
## rocky cliff displacement, the splat map (roads, forest floor, base paving, Dusk blight), a macro noise texture,
## and the river water surface. Mountains: a distance field into the simulation's mountain cells raises ridged peaks
## inside the map, and an outer ring of coarser chunks continues the range past the map edge (the river leaves the
## map through a gorge in the north-west and south-east), so the battlefield never ends in a void.

const C = preload("res://src/sim/sim_const.gd")
const TERRAIN_SHADER := preload("res://src/game/terrain.gdshader")
const WATER_SHADER := preload("res://src/game/water.gdshader")
const STEP := 32.0                         # game units between vertices
const CHUNKS := 8
const SPLAT := 512
const WATER_LEVEL := 70.0                  # game units above the river bed
const EXT := 7680.0                        # how far the outer mountain ring reaches past the map edge
const DSTEP := 64.0                        # mountain distance field spacing
const OSTEP := 128.0                       # outer ring vertex spacing

var map: SimMap
var heights := PackedFloat32Array()       # (V x V) displaced heights, game units
var V := 0
var material: ShaderMaterial
var _dist := PackedFloat32Array()         # distance (game units) into the mountains, DN x DN over the extended area
var DN := 0
var _ridge := FastNoiseLite.new()
var _ridge2 := FastNoiseLite.new()
var mountain_mask := PackedFloat32Array()  # V x V, 0..1: how much of each inner vertex is mountain

func _init(p_map: SimMap) -> void:
	map = p_map

func build(parent: Node3D) -> void:
	V = int(SimMap.HALF * 2.0 / STEP) + 1
	_mountain_field()
	_heights()
	material = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("albedo_tex", load("res://assets/generated/terrain_albedo.res"))
	material.set_shader_parameter("normal_tex", load("res://assets/generated/terrain_normal.res"))
	material.set_shader_parameter("splat_tex", ImageTexture.create_from_image(_splat()))
	material.set_shader_parameter("macro_tex", _macro())
	material.set_shader_parameter("map_half", View.MAP_HALF_M)
	material.set_shader_parameter("river_height", WATER_LEVEL * View.S)
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)
	var per := (V - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk(cx * per, cz * per, per)
			mi.material_override = material
			mi.name = "Chunk_%d_%d" % [cx, cz]
			root.add_child(mi)
	_outer_ring(root)
	_water(parent)

var _max_h := -INF

## The highest point of the battlefield's height grid, in game units (camera ray marches start below it).
func max_height() -> float:
	if _max_h == -INF:
		for h in heights:
			_max_h = maxf(_max_h, h)
	return _max_h

## Height in game units at a world point, including the rendered displacement (units stand on this).
func height_at(p: Vector2) -> float:
	var fx := clampf((p.x + SimMap.HALF) / STEP, 0.0, V - 1.001)
	var fy := clampf((p.y + SimMap.HALF) / STEP, 0.0, V - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var h00 := heights[y0 * V + x0]
	var h10 := heights[y0 * V + x0 + 1]
	var h01 := heights[(y0 + 1) * V + x0]
	var h11 := heights[(y0 + 1) * V + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)

func _heights() -> void:
	heights.resize(V * V)
	var n := FastNoiseLite.new()
	n.seed = map.seed_value + 11
	n.frequency = 0.004
	n.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = map.seed_value + 23
	n2.frequency = 0.0007
	for iy in V:
		for ix in V:
			var p := Vector2(-SimMap.HALF + ix * STEP, -SimMap.HALF + iy * STEP)
			heights[iy * V + ix] = map.height_at(p)
	# cliff faces get rocky relief; open ground gets gentle undulation (flatter on roads)
	var out := heights.duplicate()
	for iy in range(1, V - 1):
		for ix in range(1, V - 1):
			var i := iy * V + ix
			var gx := (heights[i + 1] - heights[i - 1]) / (2.0 * STEP)
			var gy := (heights[i + V] - heights[i - V]) / (2.0 * STEP)
			var g := sqrt(gx * gx + gy * gy)
			var p := Vector2(-SimMap.HALF + ix * STEP, -SimMap.HALF + iy * STEP)
			var cliff := clampf((g - 0.35) * 2.5, 0.0, 1.0)
			var rough := n.get_noise_2dv(p)
			out[i] = heights[i] + cliff * rough * 55.0 + (1.0 - cliff) * n2.get_noise_2dv(p) * 14.0
	heights = out
	mountain_mask.resize(V * V)
	for iy in V:
		for ix in V:
			var p := Vector2(-SimMap.HALF + ix * STEP, -SimMap.HALF + iy * STEP)
			var d := mountain_dist(p)
			heights[iy * V + ix] += mountain_height(p, d)
			mountain_mask[iy * V + ix] = clampf(d / 260.0, 0.0, 1.0)

# ---- Mountains --------------------------------------------------------------------------------------------------------

## River width beyond the map (same rule as SimMap.level_at_raw), for the gorge in the outer ring.
static func _river_w(p: Vector2) -> float:
	return 500.0 + 120.0 * cos(p.x * 0.0011) + 60.0 * cos(p.y * 0.0023)

## Whether an extended-area point is mountain: the simulation's mountain cells inside the map, everything outside
## except the river's gorge.
func _is_mtn(p: Vector2) -> bool:
	if maxf(absf(p.x), absf(p.y)) < SimMap.HALF - 1.0:
		return map.level_at(p) == SimMap.MOUNTAIN
	var rd := absf(p.x + p.y) / sqrt(2.0)
	return rd > _river_w(p) + 420.0

## Chamfer distance transform (two passes) from every non-mountain point.
func _mountain_field() -> void:
	_ridge.seed = map.seed_value + 71
	_ridge.frequency = 0.00042
	_ridge.fractal_octaves = 5
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge2.seed = map.seed_value + 97
	_ridge2.frequency = 0.0021
	_ridge2.fractal_octaves = 3
	var span := (SimMap.HALF + EXT) * 2.0
	DN = int(span / DSTEP) + 1
	_dist.resize(DN * DN)
	var big := 1.0e9
	for j in DN:
		for i in DN:
			var p := Vector2(-SimMap.HALF - EXT + i * DSTEP, -SimMap.HALF - EXT + j * DSTEP)
			_dist[j * DN + i] = big if _is_mtn(p) else 0.0
	var a := DSTEP
	var b := DSTEP * 1.4142
	for j in DN:
		for i in DN:
			var k := j * DN + i
			var v := _dist[k]
			if v == 0.0:
				continue
			if i > 0: v = minf(v, _dist[k - 1] + a)
			if j > 0:
				v = minf(v, _dist[k - DN] + a)
				if i > 0: v = minf(v, _dist[k - DN - 1] + b)
				if i < DN - 1: v = minf(v, _dist[k - DN + 1] + b)
			_dist[k] = v
	for j in range(DN - 1, -1, -1):
		for i in range(DN - 1, -1, -1):
			var k := j * DN + i
			var v := _dist[k]
			if v == 0.0:
				continue
			if i < DN - 1: v = minf(v, _dist[k + 1] + a)
			if j < DN - 1:
				v = minf(v, _dist[k + DN] + a)
				if i < DN - 1: v = minf(v, _dist[k + DN + 1] + b)
				if i > 0: v = minf(v, _dist[k + DN - 1] + b)
			_dist[k] = v

## Distance into the mountains at a point (bilinear in the field; 0 outside mountains).
func mountain_dist(p: Vector2) -> float:
	var fx := clampf((p.x + SimMap.HALF + EXT) / DSTEP, 0.0, DN - 1.001)
	var fy := clampf((p.y + SimMap.HALF + EXT) / DSTEP, 0.0, DN - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var d00 := _dist[y0 * DN + x0]
	var d10 := _dist[y0 * DN + x0 + 1]
	var d01 := _dist[(y0 + 1) * DN + x0]
	var d11 := _dist[(y0 + 1) * DN + x0 + 1]
	return maxf(0.0, lerpf(lerpf(d00, d10, tx), lerpf(d01, d11, tx), ty) - DSTEP * 0.5)

## Extra height of a mountain point: a steep rocky foot, then ridged peaks that grow with depth into the range.
func mountain_height(p: Vector2, d: float) -> float:
	if d <= 0.0:
		return 0.0
	var r := _ridge.get_noise_2dv(p) * 0.5 + 0.5
	var r2 := _ridge2.get_noise_2dv(p)
	var foot := 760.0 * (1.0 - exp(-d / 300.0))
	var rise := maxf(0.0, d - 450.0) * 0.42
	return ((foot + rise) * (0.45 + 0.85 * r * r) + r2 * 70.0 * clampf(d / 400.0, 0.0, 1.0)) * south_scale(p)

## The camera looks north from up to ~10 m south of its target, so anything tall on the south side would stand between
## it and the battlefield: mountains there stay low rocky hills, growing to full peaks over the first 3000 units north
## of the south edge. The north, east and west ranges rise at full height.
static func south_scale(p: Vector2) -> float:
	return clampf(0.14 + (p.y + SimMap.HALF - 300.0) / 3000.0, 0.14, 1.0)

## Ground height outside the map (before mountains): ground level, dropping into the river gorge.
func _outer_base(p: Vector2) -> float:
	var rd := absf(p.x + p.y) / sqrt(2.0)
	var w := _river_w(p)
	return lerpf(0.0, C.LEVEL_HEIGHT, smoothstep(w - 120.0, w + 260.0, rd))

## Height of any point of the extended area (the inner terrain where it exists).
func outer_height(p: Vector2) -> float:
	if maxf(absf(p.x), absf(p.y)) <= SimMap.HALF:
		return height_at(p)
	return _outer_base(p) + mountain_height(p, mountain_dist(p))

## Chunks around the map: a finer ring (64 units) out to NEAR past the edge, then a coarse one (128) out to EXT.
## Each ring's innermost row tucks under whatever lies inside it, hiding the seams.
const NEAR := 3072.0

func _outer_ring(root: Node3D) -> void:
	_ring(root, SimMap.HALF, SimMap.HALF + NEAR, 64.0, "Near")
	_ring(root, SimMap.HALF + NEAR, SimMap.HALF + EXT, OSTEP, "Far")

func _ring(root: Node3D, inner_half: float, outer_half: float, step: float, tag: String) -> void:
	var lo := -outer_half
	var n := int(roundf(outer_half * 2.0 / step))
	var hv := PackedFloat32Array()
	hv.resize((n + 1) * (n + 1))
	var mk := PackedFloat32Array()
	mk.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := Vector2(lo + i * step, lo + j * step)
			var m := maxf(absf(p.x), absf(p.y))
			var h := 0.0
			if m < SimMap.HALF - 0.5:
				h = height_at(p) - 40.0
			elif m < inner_half - 0.5:
				h = outer_height(p) - 60.0
			else:
				h = outer_height(p)
			hv[j * (n + 1) + i] = h
			mk[j * (n + 1) + i] = clampf(mountain_dist(p) / 260.0, 0.0, 1.0)
	var parts := 6
	var per := n / parts
	for cz in parts:
		for cx in parts:
			var x0 := cx * per
			var y0 := cz * per
			var x1 := n if cx == parts - 1 else x0 + per
			var y1 := n if cz == parts - 1 else y0 + per
			var mesh := _outer_chunk(hv, mk, n, lo, step, inner_half - step, x0, y0, x1, y1)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = material
			mi.name = "%s_%d_%d" % [tag, cx, cz]
			root.add_child(mi)

## One chunk of a ring; quads fully inside `inner` are covered by what lies within the ring and are skipped.
func _outer_chunk(hv: PackedFloat32Array, mk: PackedFloat32Array, n: int, lo: float, step: float, inner: float, x0: int, y0: int, x1: int, y1: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var vert := func(i: int, j: int) -> void:
		var p := Vector2(lo + i * step, lo + j * step)
		var h := hv[j * (n + 1) + i]
		var hx0 := hv[j * (n + 1) + maxi(i - 1, 0)]
		var hx1 := hv[j * (n + 1) + mini(i + 1, n)]
		var hy0 := hv[maxi(j - 1, 0) * (n + 1) + i]
		var hy1 := hv[mini(j + 1, n) * (n + 1) + i]
		var nn := Vector3(-(hx1 - hx0) / (2.0 * step), 1.0, (hy1 - hy0) / (2.0 * step)).normalized()
		st.set_normal(nn)
		st.set_uv(Vector2(p.x * View.S, -p.y * View.S))
		st.set_color(Color(mk[j * (n + 1) + i], 0.0, 0.0))
		st.add_vertex(View.to3(p, h))
	for j in range(y0, y1):
		for i in range(x0, x1):
			var ax := lo + i * step
			var ay := lo + j * step
			if ax >= -inner and ax + step <= inner and ay >= -inner and ay + step <= inner:
				continue
			any = true
			# same winding as the inner chunks (sim +y is world -z)
			vert.call(i, j); vert.call(i, j + 1); vert.call(i + 1, j)
			vert.call(i + 1, j); vert.call(i, j + 1); vert.call(i + 1, j + 1)
	if not any:
		return null
	st.generate_tangents()
	return st.commit()

func _vert(ix: int, iy: int) -> Vector3:
	var p := Vector2(-SimMap.HALF + ix * STEP, -SimMap.HALF + iy * STEP)
	return View.to3(p, heights[iy * V + ix])

func _normal(ix: int, iy: int) -> Vector3:
	var x0 := maxi(ix - 1, 0)
	var x1 := mini(ix + 1, V - 1)
	var y0 := maxi(iy - 1, 0)
	var y1 := mini(iy + 1, V - 1)
	var dx := (heights[iy * V + x1] - heights[iy * V + x0]) / ((x1 - x0) * STEP)
	var dy := (heights[y1 * V + ix] - heights[y0 * V + ix]) / ((y1 - y0) * STEP)
	# world: x east, z = -north. height rises along +x by dx, along -z by dy
	return Vector3(-dx, 1.0, dy).normalized()

func _chunk(x0: int, y0: int, per: int) -> ArrayMesh:
	var n := per + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	cols.resize(n * n)
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	tans.resize(n * n * 4)
	for j in n:
		for i in n:
			var k := j * n + i
			var v := _vert(x0 + i, y0 + j)
			verts[k] = v
			var nn := _normal(x0 + i, y0 + j)
			norms[k] = nn
			uvs[k] = Vector2(v.x, v.z)
			cols[k] = Color(mountain_mask[(y0 + j) * V + x0 + i], 0.0, 0.0)
			var t := (Vector3(1, 0, 0) - nn * nn.x).normalized()
			tans[k * 4] = t.x
			tans[k * 4 + 1] = t.y
			tans[k * 4 + 2] = t.z
			tans[k * 4 + 3] = -1.0
	var idx := PackedInt32Array()
	idx.resize(per * per * 6)
	var w := 0
	for j in per:
		for i in per:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# sim +y is world -z: rows run towards -z; Godot front faces wind clockwise seen from above
			idx[w] = a; idx[w + 1] = c; idx[w + 2] = b
			idx[w + 3] = b; idx[w + 4] = c; idx[w + 5] = d
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# ---- Splat map --------------------------------------------------------------------------------------------------------

## R road, G forest floor, B base paving, A Dusk blight. Row j covers world z, i.e. sim y descending.
func _splat() -> Image:
	var N := SPLAT
	var px := SimMap.HALF * 2.0 / N
	var road := PackedFloat32Array()
	road.resize(N * N)
	var forest := PackedFloat32Array()
	forest.resize(N * N)
	var stamp := func(arr: PackedFloat32Array, p: Vector2, r: float, strength: float) -> void:
		var cx := (p.x + SimMap.HALF) / px
		var cy := (-p.y + SimMap.HALF) / px
		var rp := r / px
		for yy in range(int(cy - rp - 1), int(cy + rp + 2)):
			if yy < 0 or yy >= N:
				continue
			for xx in range(int(cx - rp - 1), int(cx + rp + 2)):
				if xx < 0 or xx >= N:
					continue
				var d := Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() / rp
				if d < 1.0:
					var v := strength * clampf((1.0 - d) * 1.6, 0.0, 1.0)
					var k := yy * N + xx
					arr[k] = maxf(arr[k], v)
	var lanes: Array = []
	for k in map.lanes:
		lanes.append(map.lanes[k])
		var m := PackedVector2Array()
		for p in map.lanes[k]:
			m.append(-p)
		lanes.append(m)
	for line: PackedVector2Array in lanes:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var steps := int(a.distance_to(b) / (px * 2.0)) + 1
			for s in steps + 1:
				stamp.call(road, a.lerp(b, float(s) / steps), 300.0, 1.0)
	for line: PackedVector2Array in map.paths:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var steps := int(a.distance_to(b) / (px * 2.0)) + 1
			for s in steps + 1:
				stamp.call(road, a.lerp(b, float(s) / steps), 170.0, 0.75)
	# neutral camps: a trampled earth clearing around the spawn box
	for c in map.camps:
		var cb: Vector2 = c.box
		stamp.call(road, c.pos, cb.length() * 1.25, 0.8)
		for k in 5:
			stamp.call(road, (c.pos as Vector2) + Vector2.from_angle(k * TAU / 5.0 + float(c.id)) * cb.length() * 0.7, cb.length() * 0.55, 0.6)
	for t in map.trees:
		stamp.call(forest, t.pos, 230.0, 1.0)
	# paved plazas only around base buildings; open grass (Dawn) or ash (Dusk) between them
	var plaza := PackedFloat32Array()
	plaza.resize(N * N)
	for b in map.buildings:
		var def := SimData.unit(b.unit)
		var r := float(def.hull) * 1.5 + 260.0
		if b.unit == "fountain":
			r = 1000.0
		elif b.unit == "ancient":
			r = 900.0
		if map.level_at(b.pos) == SimMap.HIGH or b.unit == "fountain":
			stamp.call(plaza, b.pos, r, 1.0)
	# paved base roads (Landscape.base_roads, mirrored for Dusk)
	for broad: PackedVector2Array in Landscape.base_roads():
		for sgn in [1.0, -1.0]:
			for i in broad.size() - 1:
				var a2: Vector2 = broad[i] * sgn
				var b2: Vector2 = broad[i + 1] * sgn
				var steps2 := int(a2.distance_to(b2) / (px * 2.0)) + 1
				for s2 in steps2 + 1:
					stamp.call(plaza, a2.lerp(b2, float(s2) / steps2), 250.0, 1.0)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var bn := FastNoiseLite.new()
	bn.seed = 5
	bn.frequency = 0.0012
	for j in N:
		for i in N:
			var p := Vector2(-SimMap.HALF + (i + 0.5) * px, SimMap.HALF - (j + 0.5) * px)
			var k := j * N + i
			var base := plaza[k]
			var side := (p.x + p.y) / sqrt(2.0)
			var blight := clampf((side - 500.0) / 3500.0, 0.0, 1.0)
			blight = clampf(blight * 0.85 + bn.get_noise_2dv(p) * 0.35, 0.0, 1.0)
			img.set_pixel(i, j, Color(road[k], forest[k] * 0.85, base, blight))
	return img

## Three independent tileable noises in R, G, B (the shader uses each for a different variation).
func _macro() -> ImageTexture:
	var size := 256
	var imgs: Array[Image] = []
	for c in 3:
		var fn := FastNoiseLite.new()
		fn.seed = 3 + c * 17
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		imgs.append(fn.get_seamless_image(size, size))
	var out := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			out.set_pixel(x, y, Color(imgs[0].get_pixel(x, y).r, imgs[1].get_pixel(x, y).r, imgs[2].get_pixel(x, y).r))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)

# ---- Water ----------------------------------------------------------------------------------------------------------

func _water(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "River"
	var pm := PlaneMesh.new()
	pm.size = Vector2(420.0, 24.0)
	pm.subdivide_width = 200
	pm.subdivide_depth = 8
	mi.mesh = pm
	# the river runs along sim x + y = 0: from north-west to south-east
	mi.rotation.y = deg_to_rad(-45.0)
	mi.position = Vector3(0, WATER_LEVEL * View.S, 0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var wn := NoiseTexture2D.new()
	wn.width = 512
	wn.height = 512
	wn.seamless = true
	wn.as_normal_map = true
	wn.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	wn.noise = fn
	mat.set_shader_parameter("normal_tex", wn)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
