class_name RankEmblem
extends Node3D
## The ranked emblems (run 2026-10-19 b; the owner: "a very epic emblem ... a very shiny 3D emblem (click drag to
## rotate)"). Each of the twelve ranks is built in code from extruded, bevelled shapes, richer as the rank rises:
##   0 Rookie          iron medallion, a bronze star
##   1 Advanced        copper medallion, laurel branches
##   2 Licensed        silver shield, blue enamel, a chevron, laurels
##   3 Expert          gold shield, red enamel, a star, laurels, small wings
##   4 Commander       crossed swords behind an emerald shield, two stars
##   5 Chief Commander crossed swords, sapphire shield, wings, a gem on top
##   6 Legendary       great gold wings, amethyst shield and a cut amethyst
##   7 Mythic          ruby on dark gold, a ring of spikes, glowing red
##   8 Hero            obsidian and gold, wide wings, crossed swords, a burning gem
##   9 Transcendent    pearl and platinum, a halo, white-gold wings, a glowing ice gem
##  10 Aetherium       a rainbow crystal in a star burst, two turning rings, wings of light
##  11 Aetherium+      Aetherium with a gold flare, a third ring and sparks
## Stars (1-5 inside a rank) sit in an arc under the emblem. Metal uses rank_metal.gdshader (a sweeping glint).
##
## RankEmblem.stage(tier, stars, px, live) makes a SubViewport with the emblem, lights and reflections;
## RankEmblem.icon(tier) is a small picture of a rank's emblem (rendered once, kept for the rest of the run).

const METAL := preload("res://src/ui/rank_metal.gdshader")

## Colours per rank: metal, trim metal, enamel, gem, glow.
const LOOK := [
	{"metal": Color(0.42, 0.40, 0.38), "trim": Color(0.66, 0.45, 0.25), "enamel": Color(0.16, 0.15, 0.15), "gem": Color(0.5, 0.35, 0.2), "glow": Color(0.0, 0.0, 0.0), "rough": 0.42},
	{"metal": Color(0.80, 0.45, 0.27), "trim": Color(0.62, 0.34, 0.18), "enamel": Color(0.18, 0.1, 0.07), "gem": Color(0.6, 0.3, 0.1), "glow": Color(0.0, 0.0, 0.0), "rough": 0.32},
	{"metal": Color(0.80, 0.82, 0.86), "trim": Color(0.66, 0.68, 0.74), "enamel": Color(0.08, 0.2, 0.55), "gem": Color(0.4, 0.6, 1.0), "glow": Color(0.0, 0.0, 0.0), "rough": 0.24},
	{"metal": Color(1.0, 0.78, 0.36), "trim": Color(0.95, 0.70, 0.30), "enamel": Color(0.55, 0.05, 0.06), "gem": Color(1.0, 0.2, 0.15), "glow": Color(0.0, 0.0, 0.0), "rough": 0.2},
	{"metal": Color(1.0, 0.80, 0.42), "trim": Color(0.80, 0.82, 0.86), "enamel": Color(0.03, 0.38, 0.2), "gem": Color(0.2, 1.0, 0.5), "glow": Color(0.1, 0.5, 0.25), "rough": 0.2},
	{"metal": Color(0.85, 0.87, 0.92), "trim": Color(1.0, 0.80, 0.42), "enamel": Color(0.03, 0.14, 0.5), "gem": Color(0.3, 0.55, 1.0), "glow": Color(0.15, 0.3, 0.9), "rough": 0.16},
	{"metal": Color(1.0, 0.79, 0.40), "trim": Color(1.0, 0.86, 0.55), "enamel": Color(0.26, 0.06, 0.42), "gem": Color(0.72, 0.3, 1.0), "glow": Color(0.5, 0.2, 0.9), "rough": 0.15},
	{"metal": Color(0.62, 0.42, 0.22), "trim": Color(1.0, 0.72, 0.35), "enamel": Color(0.35, 0.02, 0.04), "gem": Color(1.0, 0.08, 0.12), "glow": Color(1.0, 0.15, 0.1), "rough": 0.18},
	{"metal": Color(0.08, 0.075, 0.09), "trim": Color(1.0, 0.76, 0.36), "enamel": Color(0.04, 0.035, 0.05), "gem": Color(1.0, 0.5, 0.1), "glow": Color(1.0, 0.45, 0.1), "rough": 0.08},
	{"metal": Color(0.95, 0.93, 0.88), "trim": Color(0.88, 0.9, 0.96), "enamel": Color(0.82, 0.84, 0.9), "gem": Color(0.45, 0.95, 1.0), "glow": Color(0.45, 0.9, 1.0), "rough": 0.12},
	{"metal": Color(0.92, 0.92, 1.0), "trim": Color(1.0, 0.85, 0.5), "enamel": Color(0.1, 0.12, 0.3), "gem": Color(0.8, 0.9, 1.0), "glow": Color(0.6, 0.5, 1.0), "rough": 0.08},
	{"metal": Color(1.0, 0.86, 0.5), "trim": Color(1.0, 0.95, 0.8), "enamel": Color(0.12, 0.08, 0.25), "gem": Color(1.0, 0.95, 0.85), "glow": Color(1.0, 0.7, 0.3), "rough": 0.07},
]

## How far each rank's emblem reaches from its centre (the camera frames it).
const EXTENT := [0.95, 1.0, 1.02, 1.12, 1.15, 1.3, 1.48, 1.45, 1.42, 1.45, 1.62, 1.68]

var tier := 0
var stars := 0
var live := true                           # turning rings, flickering glow (false for icons)
var _spin: Array = []                      # [node, axis, speed]
var _t := 0.0

func build(p_tier: int, p_stars := 0, p_live := true) -> void:
	tier = clampi(p_tier, 0, 11)
	stars = clampi(p_stars, 0, 5)
	live = p_live
	for c in get_children():
		c.queue_free()
	_spin.clear()
	var L: Dictionary = LOOK[tier]
	var metal := _metal(L.metal, L.rough)
	var trim := _metal(L.trim, maxf(0.08, float(L.rough) - 0.05))
	var enamel := _enamel(L.enamel)
	var gem := _gem(L.gem, L.glow)
	match tier:
		0:
			_medallion(metal, trim, enamel, 0.62)
			_part(_extrude(_star(5, 0.3, 0.13), 0.08, 0.035), trim, Vector3(0, 0.02, 0.1))
		1:
			_laurels(trim, 0.8, 7)
			_medallion(metal, trim, enamel, 0.6)
			_part(_extrude(_star(5, 0.3, 0.13), 0.08, 0.035), trim, Vector3(0, 0.02, 0.1))
		2:
			_laurels(trim, 0.88, 7)
			_shield(metal, trim, enamel, 0.62)
			_part(_extrude(_chevron(0.34, 0.12), 0.06, 0.03), metal, Vector3(0, -0.02, 0.14))
			_part(_extrude(_chevron(0.34, 0.12), 0.06, 0.03), metal, Vector3(0, 0.2, 0.14))
		3:
			_wings(trim, 3, 0.75, 0.0)
			_laurels(metal, 0.92, 7)
			_shield(metal, trim, enamel, 0.64)
			_part(_extrude(_star(5, 0.27, 0.11), 0.08, 0.035), metal, Vector3(0, 0.06, 0.15))
		4:
			_swords(trim, metal, 1.7)
			_shield(metal, trim, enamel, 0.64)
			_part(_extrude(_star(5, 0.17, 0.07), 0.07, 0.03), metal, Vector3(-0.14, 0.12, 0.15))
			_part(_extrude(_star(5, 0.17, 0.07), 0.07, 0.03), metal, Vector3(0.14, 0.12, 0.15))
			_part(_extrude(_chevron(0.3, 0.1), 0.06, 0.03), trim, Vector3(0, -0.18, 0.14))
		5:
			_wings(trim, 4, 0.95, 0.05)
			_swords(metal, trim, 1.75)
			_shield(metal, trim, enamel, 0.66)
			_part(_extrude(_star(5, 0.2, 0.085), 0.07, 0.03), trim, Vector3(0, 0.02, 0.15))
			_part(_cut_gem(0.14, 8), gem, Vector3(0, 0.66, 0.1))
		6:
			_wings(metal, 6, 1.25, 0.12)
			_laurels(trim, 0.98, 8)
			_shield(metal, trim, enamel, 0.68)
			_part(_cut_gem(0.2, 10), gem, Vector3(0, 0.05, 0.17))
			_glow(L.glow, 1.7, 0.35)
		7:
			_spikes(trim, 14, 0.72, 1.18)
			_wings(trim, 4, 1.05, -0.05)
			_shield(metal, trim, enamel, 0.72)
			_part(_extrude(_star(8, 0.4, 0.22), 0.06, 0.03), trim, Vector3(0, 0.02, 0.14))
			_part(_cut_gem(0.22, 12), gem, Vector3(0, 0.02, 0.22))
			_glow(L.glow, 2.2, 0.55)
		8:
			_burst(trim, 12, 0.7, 1.15)
			_laurels(trim, 0.98, 8)
			_wings(trim, 7, 1.45, 0.15)
			_swords(trim, metal, 1.85)
			_shield(metal, trim, enamel, 0.72)
			_part(_extrude(_star(4, 0.4, 0.12), 0.05, 0.025), trim, Vector3(0, 0.04, 0.14))
			_part(_cut_gem(0.2, 10), gem, Vector3(0, 0.04, 0.2))
			_glow(L.glow, 2.1, 0.55)
		9:
			_burst(trim, 20, 0.75, 1.3)
			_halo(trim, 0.5, Vector3(0, 0.86, -0.05))
			_laurels(trim, 1.0, 8)
			_wings(metal, 8, 1.5, 0.18)
			_shield(metal, trim, enamel, 0.7)
			_part(_extrude(_star(6, 0.42, 0.2), 0.05, 0.025), trim, Vector3(0, 0.03, 0.15))
			_part(_cut_gem(0.22, 12), gem, Vector3(0, 0.03, 0.22))
			_glow(L.glow, 2.4, 0.6)
		10, 11:
			_burst(trim, 16 if tier == 10 else 24, 0.8, 1.35 if tier == 10 else 1.55)
			_wings(_light(L.glow), 7, 1.55, 0.2)
			_rings(trim, tier)
			var crystal := _metal(L.metal, 0.05)
			crystal.set_shader_parameter("iridescence", 0.85)
			crystal.set_shader_parameter("metallic", 0.55)
			crystal.set_shader_parameter("emission", L.glow)
			crystal.set_shader_parameter("emission_energy", 0.5)
			_part(_crystal(0.55, 0.9), crystal, Vector3(0, 0, 0.1))
			_glow(L.glow, 2.8 if tier == 10 else 3.3, 0.75)
			if tier == 11:
				_glow(Color(1.0, 0.65, 0.2), 2.0, 0.6)
				_sparks(Color(1.0, 0.8, 0.4))
	if stars > 0:
		_stars(trim, stars)

func _process(dt: float) -> void:
	if not live:
		return
	_t += dt
	for s in _spin:
		var n: Node3D = s[0]
		if is_instance_valid(n):
			n.rotate(s[1], float(s[2]) * dt)

# ---- Materials ------------------------------------------------------------------------------------------------------

func _metal(c: Color, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = METAL
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	if not live:
		m.set_shader_parameter("sweep_at", 0.35)
	return m

func _enamel(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.35
	m.metallic = 0.1
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	return m

func _gem(c: Color, glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.25)
	m.metallic = 0.3
	m.roughness = 0.04
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = true
	m.rim = 0.8
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = c if glow.v < 0.05 else glow
	m.emission_energy_multiplier = 0.6 if glow.v < 0.05 else 1.6
	m.clearcoat_enabled = true
	m.clearcoat_roughness = 0.0
	return m

func _light(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, 0.55)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---- Shapes (2D outlines, emblem radius about 1) -------------------------------------------------------------------

static func _circle(r: float, n := 48) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

static func _star(points: int, ro: float, ri: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in points * 2:
		var a := PI * 0.5 + PI * float(i) / float(points)
		p.append(Vector2(cos(a), sin(a)) * (ro if i % 2 == 0 else ri))
	return p

## A heater shield: flat-ish top with rounded shoulders, curving down to a point.
static func _shield_shape(s: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var n := 18
	# right side from the top shoulder down to the point
	for i in n + 1:
		var t := float(i) / float(n)
		var y := lerpf(0.82, -1.0, t)
		var x := 0.78 * (1.0 - pow(t, 2.2)) * (1.0 if t > 0.06 else lerpf(0.9, 1.0, t / 0.06))
		p.append(Vector2(x, y) * s)
	# left side back up
	for i in range(n - 1, -1, -1):
		var t := float(i) / float(n)
		var y := lerpf(0.82, -1.0, t)
		var x := 0.78 * (1.0 - pow(t, 2.2)) * (1.0 if t > 0.06 else lerpf(0.9, 1.0, t / 0.06))
		p.append(Vector2(-x, y) * s)
	# the top edge with a slight arch
	var out := PackedVector2Array()
	for q in p:
		out.append(q)
	for i in range(1, 8):
		var x := lerpf(-0.78, 0.78, float(i) / 8.0) * s
		out.append(Vector2(x, (0.82 + 0.06 * (1.0 - pow(x / (0.78 * s), 2.0))) * s))
	return _ccw(out)

static func _chevron(w: float, th: float) -> PackedVector2Array:
	return _ccw(PackedVector2Array([Vector2(-w, 0.0), Vector2(0, w * 0.55), Vector2(w, 0.0), Vector2(w, -th),
		Vector2(0, w * 0.55 - th), Vector2(-w, -th)]))

## A laurel leaf: pointed at both ends.
static func _leaf(l: float, wd: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var n := 8
	for i in n + 1:
		var t := float(i) / float(n)
		p.append(Vector2((t - 0.5) * l, wd * 0.5 * sin(PI * t)))
	for i in range(n - 1, 0, -1):
		var t := float(i) / float(n)
		p.append(Vector2((t - 0.5) * l, -wd * 0.42 * sin(PI * t)))
	return _ccw(p)

static func _feather(l: float, wd: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var n := 10
	for i in n + 1:
		var t := float(i) / float(n)
		p.append(Vector2(t * l, wd * 0.5 * sin(PI * pow(t, 0.7)) + 0.02))
	for i in range(n - 1, 0, -1):
		var t := float(i) / float(n)
		p.append(Vector2(t * l, -wd * 0.35 * sin(PI * pow(t, 0.8))))
	return _ccw(p)

static func _blade(l: float, wd: float) -> PackedVector2Array:
	return _ccw(PackedVector2Array([Vector2(-wd * 0.5, 0), Vector2(wd * 0.5, 0), Vector2(wd * 0.5, l * 0.85),
		Vector2(0, l), Vector2(-wd * 0.5, l * 0.85)]))

static func _ccw(p: PackedVector2Array) -> PackedVector2Array:
	if Geometry2D.is_polygon_clockwise(p):
		p.reverse()
	return p

# ---- Meshes ---------------------------------------------------------------------------------------------------------

## An outline extruded to `depth` with a bevel of `bevel` on the front (the face inset toward the centre and raised).
static func _extrude(poly: PackedVector2Array, depth: float, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(n)
	var rad := 0.0
	for q in poly:
		rad = maxf(rad, q.distance_to(c))
	var k := clampf(1.0 - bevel / maxf(rad, 0.01), 0.3, 1.0)
	var inner := PackedVector2Array()
	for q in poly:
		inner.append(c + (q - c) * k)
	var zf := depth * 0.5
	var zb := -depth * 0.5
	var zt := zf + bevel * 0.7
	var tri := Geometry2D.triangulate_polygon(inner)
	# front face (flat)
	st.set_smooth_group(0xFFFFFFFF)
	for i in range(0, tri.size(), 3):
		for j in [0, 2, 1]:
			var q: Vector2 = inner[tri[i + j]]
			st.set_uv(q * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(q.x, q.y, zt))
	# back face
	var tb := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tb.size(), 3):
		for j in [0, 1, 2]:
			var q: Vector2 = poly[tb[i + j]]
			st.set_uv(q * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(q.x, q.y, zb))
	# the bevel ring (faceted) and the side wall (smooth)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var ia := inner[i]
		var ib := inner[(i + 1) % n]
		st.set_smooth_group(0xFFFFFFFF)
		_quad(st, Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), Vector3(ib.x, ib.y, zt), Vector3(ia.x, ia.y, zt))
		st.set_smooth_group(1)
		_quad(st, Vector3(a.x, a.y, zb), Vector3(b.x, b.y, zb), Vector3(b.x, b.y, zf), Vector3(a.x, a.y, zf))
	st.generate_normals()
	return st.commit()

static func _v(st: SurfaceTool, v: Vector3) -> void:
	st.set_uv(Vector2(v.x, v.y) * 0.5 + Vector2(0.5, 0.5))
	st.add_vertex(v)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_uv(Vector2(v.x, v.y) * 0.5 + Vector2(0.5, 0.5))
		st.add_vertex(v)

## A cut gem: a table on top, a crown, a girdle and a pointed pavilion, flat facets.
static func _cut_gem(r: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	var top := Vector3(0, 0, r * 0.55)
	var tip := Vector3(0, 0, -r * 0.7)
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var g0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var g1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		var t0 := Vector3(cos(a0) * r * 0.55, sin(a0) * r * 0.55, r * 0.45)
		var t1 := Vector3(cos(a1) * r * 0.55, sin(a1) * r * 0.55, r * 0.45)
		for v in [top, t1, t0]:
			_v(st, v)
		_quad(st, g0, g1, t1, t0)
		for v in [tip, g0, g1]:
			_v(st, v)
	st.generate_normals()
	return st.commit()

## A crystal: a long double-pointed shard with six sides.
static func _crystal(wd: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)
	var up := Vector3(0, h, 0)
	var dn := Vector3(0, -h, 0)
	var n := 6
	for i in n:
		var a0 := TAU * float(i) / float(n) + 0.3
		var a1 := TAU * float(i + 1) / float(n) + 0.3
		var p0 := Vector3(cos(a0) * wd * 0.5, h * 0.25, sin(a0) * wd * 0.35)
		var p1 := Vector3(cos(a1) * wd * 0.5, h * 0.25, sin(a1) * wd * 0.35)
		var q0 := Vector3(cos(a0) * wd * 0.5, -h * 0.25, sin(a0) * wd * 0.35)
		var q1 := Vector3(cos(a1) * wd * 0.5, -h * 0.25, sin(a1) * wd * 0.35)
		for v in [up, p1, p0]:
			_v(st, v)
		_quad(st, q0, q1, p1, p0)
		for v in [dn, q0, q1]:
			_v(st, v)
	st.generate_normals()
	return st.commit()

func _part(mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi

# ---- Pieces ---------------------------------------------------------------------------------------------------------

func _medallion(metal: Material, trim: Material, enamel: Material, r: float) -> void:
	_part(_extrude(_circle(r), 0.14, 0.06), metal, Vector3.ZERO)
	_part(_extrude(_circle(r * 0.72), 0.06, 0.02), enamel, Vector3(0, 0, 0.07))
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.94
	ring.outer_radius = r * 1.06
	ring.rings = 48
	ring.ring_segments = 10
	_part(ring, trim, Vector3(0, 0, 0.05), Vector3(PI * 0.5, 0, 0))

func _shield(metal: Material, trim: Material, enamel: Material, s: float) -> void:
	_part(_extrude(_shield_shape(s * 1.08), 0.12, 0.05), trim, Vector3(0, 0, -0.01))
	_part(_extrude(_shield_shape(s), 0.12, 0.05), metal, Vector3(0, 0, 0.03))
	_part(_extrude(_shield_shape(s * 0.78), 0.05, 0.02), enamel, Vector3(0, -0.02 * s, 0.1))

func _laurels(mat: Material, r: float, leaves: int) -> void:
	# two branches from the bottom up each side, leaves along the arc pointing up, tilted out and in in turn
	for side: float in [-1.0, 1.0]:
		for i in leaves:
			var t := float(i) / float(maxi(1, leaves - 1))
			var a := lerpf(0.3, 2.05, t)
			var p := Vector2(side * sin(a) * r, -cos(a) * r)
			var ang := atan2(sin(a), side * cos(a)) + (0.55 if i % 2 == 0 else -0.35) * side
			_part(_extrude(_leaf(0.34, 0.13), 0.045, 0.018), mat, Vector3(p.x, p.y, -0.06 + 0.004 * float(i)), Vector3(0, 0, ang))

func _wings(mat: Material, n: int, span: float, lift: float) -> void:
	for side: float in [-1.0, 1.0]:
		for i in n:
			var t := float(i) / float(maxi(1, n - 1))
			var l := span * lerpf(1.0, 0.55, t)
			var ang := lerpf(0.55, -0.55, t) + lift
			var root := Vector3(0.25 * side, 0.15 - 0.12 * t, -0.12 - 0.02 * float(i))
			var mi := _part(_extrude(_feather(l, 0.24 + 0.05 * (1.0 - t)), 0.035, 0.015), mat, root, Vector3(0, 0, ang if side > 0 else PI - ang))
			if side < 0:
				mi.scale = Vector3(1, -1, 1)
				mi.rotation = Vector3(0, 0, PI - ang)

func _swords(blade: Material, hilt: Material, l: float) -> void:
	for side: float in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.rotation = Vector3(0, 0, side * 0.72)
		piv.position = Vector3(0, -0.05, -0.15)
		add_child(piv)
		var b := MeshInstance3D.new()
		b.mesh = _extrude(_blade(l, 0.13), 0.04, 0.02)
		b.material_override = blade
		b.position = Vector3(0, -l * 0.42, 0)
		piv.add_child(b)
		var guard := BoxMesh.new()
		guard.size = Vector3(0.36, 0.06, 0.07)
		var g := MeshInstance3D.new()
		g.mesh = guard
		g.material_override = hilt
		g.position = Vector3(0, -l * 0.44, 0.0)
		piv.add_child(g)
		var grip := CylinderMesh.new()
		grip.top_radius = 0.03
		grip.bottom_radius = 0.03
		grip.height = 0.24
		var gr := MeshInstance3D.new()
		gr.mesh = grip
		gr.material_override = hilt
		gr.position = Vector3(0, -l * 0.44 - 0.14, 0)
		piv.add_child(gr)
		var pom := SphereMesh.new()
		pom.radius = 0.055
		pom.height = 0.11
		var pm := MeshInstance3D.new()
		pm.mesh = pom
		pm.material_override = hilt
		pm.position = Vector3(0, -l * 0.44 - 0.28, 0)
		piv.add_child(pm)

func _spikes(mat: Material, n: int, r0: float, r1: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n) + PI / float(n)
		var l := r1 if i % 2 == 0 else lerpf(r0, r1, 0.6)
		var tri := _ccw(PackedVector2Array([Vector2(r0 * 0.8, -0.09), Vector2(l, 0), Vector2(r0 * 0.8, 0.09)]))
		_part(_extrude(tri, 0.05, 0.02), mat, Vector3(0, 0, -0.06), Vector3(0, 0, a))

func _halo(mat: Material, r: float, at: Vector3) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.92
	ring.outer_radius = r
	ring.rings = 64
	ring.ring_segments = 8
	_part(ring, mat, at, Vector3(0.42, 0, 0))

func _rings(mat: Material, t: int) -> void:
	var tilts := [Vector3(1.2, 0.3, 0), Vector3(1.9, -0.4, 0.2), Vector3(0.6, 0.9, 0.0)]
	for i in (2 if t == 10 else 3):
		var piv := Node3D.new()
		piv.rotation = tilts[i]
		add_child(piv)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.86 + 0.08 * float(i)
		ring.outer_radius = 0.9 + 0.08 * float(i)
		ring.rings = 72
		ring.ring_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = mat
		piv.add_child(mi)
		# a small bead riding each ring
		var bead := SphereMesh.new()
		bead.radius = 0.05
		bead.height = 0.1
		var bm := MeshInstance3D.new()
		bm.mesh = bead
		bm.material_override = mat
		bm.position = Vector3(0.88 + 0.08 * float(i), 0, 0)
		mi.add_child(bm)
		_spin.append([mi, Vector3(0, 1, 0), 0.6 + 0.35 * float(i)])

func _burst(mat: Material, n: int, r0: float, r1: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n)
		var l := r1 if i % 2 == 0 else lerpf(r0, r1, 0.55)
		var tri := _ccw(PackedVector2Array([Vector2(0.2, -0.05), Vector2(l, 0), Vector2(0.2, 0.05)]))
		_part(_extrude(tri, 0.03, 0.012), mat, Vector3(0, 0, -0.22), Vector3(0, 0, a))

func _stars(mat: Material, n: int) -> void:
	for i in n:
		var t := (float(i) - float(n - 1) * 0.5)
		var x := t * 0.3
		var y := -0.86 + 0.025 * t * t
		_part(_extrude(_star(5, 0.13, 0.055), 0.06, 0.025), mat, Vector3(x, y, 0.26))

## A soft light behind the emblem (additive quad with a radial falloff).
func _glow(c: Color, size: float, strength: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _radial_tex()
	m.albedo_color = Color(c.r, c.g, c.b, strength)
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_part(q, m, Vector3(0, 0, -0.35))

func _sparks(c: Color) -> void:
	var piv := Node3D.new()
	add_child(piv)
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	for i in 14:
		var s := SphereMesh.new()
		s.radius = rr.randf_range(0.015, 0.035)
		s.height = s.radius * 2.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		var a := rr.randf() * TAU
		_part(s, m, Vector3(cos(a) * rr.randf_range(0.9, 1.3), sin(a) * rr.randf_range(0.9, 1.3), rr.randf_range(-0.2, 0.2)), Vector3.ZERO, Vector3.ONE, piv)
	_spin.append([piv, Vector3(0, 0, 1), 0.25])

static var _radial: Texture2D

static func _radial_tex() -> Texture2D:
	if _radial != null:
		return _radial
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_radial = t
	return t

# ---- Stages and icons -----------------------------------------------------------------------------------------------

## A viewport showing one emblem: transparent background, a camera, a warm key light, a cool rim light, a fill, and a
## sky for the metal to reflect. live: animated (glints, turning rings); else rendered once.
static func stage(p_tier: int, p_stars: int, px: int, p_live: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if p_live else SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.18, 0.24, 0.4)
	sm.sky_horizon_color = Color(0.95, 0.8, 0.55)
	sm.ground_horizon_color = Color(0.5, 0.36, 0.22)
	sm.ground_bottom_color = Color(0.05, 0.05, 0.08)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, -0.1, float(EXTENT[clampi(p_tier, 0, 11)]) * 3.75)
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.6
	key.rotation = Vector3(-0.6, -0.5, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 1.2
	rim.rotation = Vector3(-0.3, 2.5, 0)
	vp.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, -1.2, 3.0)
	fill.light_energy = 0.8
	fill.omni_range = 8.0
	vp.add_child(fill)
	var em := RankEmblem.new()
	em.name = "Emblem"
	vp.add_child(em)
	em.build(p_tier, p_stars, p_live)
	em.rotation = Vector3(0.05, -0.32, 0) if not p_live else Vector3.ZERO
	return vp

static var _icons := {}
static var _holder: Node
static var baked := 0                      # icons made so far (screens redraw when it changes)

## A rank's emblem as a picture: rendered once per run (256 px) in a viewport under the tree's root, then kept as a
## plain image and the viewport freed (a viewport left alive could be drawn again later in another state).
static func icon(p_tier: int) -> Texture2D:
	var t := clampi(p_tier, 0, 11)
	if _icons.has(t):
		return _icons[t]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = "RankIcons"
		tree.root.add_child.call_deferred(_holder)
	var vp := stage(t, 0, 256, false)
	_holder.add_child.call_deferred(vp)
	_icons[t] = null                         # nothing to show until the picture is made (_bake)
	_bake.call_deferred(t, vp)
	return null

## Keep rendering the icon's viewport until a frame holds the whole emblem (its centre and upper part drawn, the
## picture square), then keep that frame as an image. Until then the live viewport texture is used.
static func _bake(t: int, vp: SubViewport) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 240:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return
		if i < 2:
			continue
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty() or img.get_width() != 256 or img.get_height() != 256:
			continue
		if img.get_pixel(128, 128).a > 0.5 and img.get_pixel(128, 84).a > 0.3 and img.get_pixel(128, 172).a > 0.3:
			_icons[t] = ImageTexture.create_from_image(img)
			baked += 1
			vp.queue_free()
			return

## A rank's emblem picture as a control (it shows up as soon as the picture is made).
class Icon extends Control:
	var tier := 0
	func _process(_dt: float) -> void:
		if RankEmblem._icons.get(tier) == null:
			queue_redraw()
	func _draw() -> void:
		var tex := RankEmblem.icon(tier)
		if tex:
			var s := minf(size.x, size.y)
			draw_texture_rect(tex, Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s)), false)
