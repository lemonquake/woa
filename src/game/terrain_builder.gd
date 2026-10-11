class_name TerrainBuilder
extends RefCounted
## Builds the rendered terrain from the simulation map: an 8x8 grid of chunk meshes (32-unit vertex spacing) with
## rocky cliff displacement, the splat map (roads, forest floor, base paving, Dusk blight), a macro noise texture,
## and the river water surface.

const C = preload("res://src/sim/sim_const.gd")
const TERRAIN_SHADER := preload("res://src/game/terrain.gdshader")
const WATER_SHADER := preload("res://src/game/water.gdshader")
const STEP := 32.0                         # game units between vertices
const CHUNKS := 8
const SPLAT := 512
const WATER_LEVEL := 40.0                  # game units above the river bed

var map: SimMap
var heights := PackedFloat32Array()       # (V x V) displaced heights, game units
var V := 0
var material: ShaderMaterial

func _init(p_map: SimMap) -> void:
	map = p_map

func build(parent: Node3D) -> void:
	V = int(SimMap.HALF * 2.0 / STEP) + 1
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
	_water(parent)

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
	pm.size = Vector2(250.0, 24.0)
	pm.subdivide_width = 120
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
