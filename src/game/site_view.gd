class_name SiteView
extends Node3D
## The map sites (SimSites) in the world, built from primitives:
##   Warp Gate: a stone ring standing on a round dais, a swirling violet field inside it that brightens while a hero
##     channels, a few stones floating round it.
##   Lily Pond: a ring of rocks round clear water, six lily pads; a pink flower opens on a pad for every Healing Lily.
##   Lookout Lamp: a stone post with an iron lantern: dim when dark, the holding team's colour when lit, a faint red
##     ember glow while it is out.
## What a site shows (lilies, who holds a lamp) is updated only while your team can see the spot (the last seen state
## stays in the fog). Right click on a site uses it (InputController asks pick()).

const TEX := "res://assets/textures/building/"
const DAWN_COL := Color(0.4, 0.75, 1.0)
const DUSK_COL := Color(1.0, 0.36, 0.3)

var game: Node
var fx: Fx
var _nodes := {}                            # site id -> {root: Node3D, kind, ...parts}
var _t := 0.0
var _channel := {}                          # site id -> game time a channel at it ends (gates brighten)
var _by_unit := {}                          # unit id -> site id it channels at
func build(w: SimWorld) -> void:
	for s in w.sites.sites:
		var d: Dictionary
		match String(s.kind):
			"gate":
				d = _gate()
			"pond":
				d = _pond()
			"lamp":
				d = _lamp()
			_:
				continue
		var root: Node3D = d.root
		root.name = "Site_%d_%s" % [int(s.id), String(s.kind)]
		add_child(root)
		root.global_position = fx.ground3(s.pos)
		d["kind"] = String(s.kind)
		_nodes[int(s.id)] = d

## A hero began or ended a channel at a site (the gate's field flares up while it lasts).
func on_channel(site_id: int, until: float, uid := -1) -> void:
	_channel[site_id] = until
	if uid >= 0:
		_by_unit[uid] = site_id

func on_channel_end(uid: int) -> void:
	if _by_unit.has(uid):
		_channel[_by_unit[uid]] = -1.0
		_by_unit.erase(uid)

func frame(dt: float) -> void:
	_t += dt
	var w: SimWorld = game.world
	for id in _nodes:
		var d: Dictionary = _nodes[id]
		var s := w.sites.get_site(int(id))
		if s.is_empty():
			continue
		var seen: bool = w.vision.cell_visible(game.player_team, s.pos)
		match String(d.kind):
			"gate":
				var busy := w.time < float(_channel.get(id, -1.0))
				var target := 2.6 if busy else 1.0
				d["glow"] = lerpf(float(d.get("glow", 1.0)), target, clampf(dt * 3.0, 0.0, 1.0))
				(d.field_mat as ShaderMaterial).set_shader_parameter("power", float(d.glow))
				(d.light as OmniLight3D).light_energy = 1.2 * float(d.glow)
				var ring: Node3D = d.stones
				ring.rotation.y = _t * 0.35
				for i in ring.get_child_count():
					var st := ring.get_child(i) as Node3D
					st.position.y = 2.2 + 0.18 * sin(_t * 1.3 + i * 1.7)
			"pond":
				if seen:
					d["shown"] = int(s.lilies)
				var n := int(d.get("shown", 0))
				var flowers: Array = d.flowers
				for i in flowers.size():
					var f := flowers[i] as Node3D
					var want := 1.0 if i < n else 0.0
					var sc := lerpf(f.scale.x, want, clampf(dt * 4.0, 0.0, 1.0))
					f.scale = Vector3.ONE * maxf(sc, 0.001)
					f.visible = sc > 0.02
					f.rotation.y = _t * 0.2 + i
			"lamp":
				if seen:
					var st2 := -1
					if w.time < float(s.out_until):
						st2 = 2
					elif int(s.team) >= 0 and w.time < float(s.until):
						st2 = int(s.team)
					d["state"] = st2
				_lamp_state(d, int(d.get("state", -1)))

func _lamp_state(d: Dictionary, st: int) -> void:
	if int(d.get("drawn", -9)) == st:
		var lt: OmniLight3D = d.light
		if st == 0 or st == 1:
			lt.light_energy = 2.2 + 0.25 * sin(_t * 5.0) + 0.1 * sin(_t * 13.0)
		return
	d["drawn"] = st
	var col := Color(0.55, 0.55, 0.5)
	var energy := 0.0
	var emit := 0.4
	match st:
		0:
			col = DAWN_COL
			energy = 2.2
			emit = 5.0
		1:
			col = DUSK_COL
			energy = 2.2
			emit = 5.0
		2:
			col = Color(0.9, 0.25, 0.1)
			energy = 0.4
			emit = 1.2
	(d.core.material_override as StandardMaterial3D).albedo_color = col
	(d.core.material_override as StandardMaterial3D).emission = col
	(d.core.material_override as StandardMaterial3D).emission_energy_multiplier = emit
	var l: OmniLight3D = d.light
	l.light_color = col
	l.light_energy = energy
	l.visible = energy > 0.0

## The site under a screen point (-1 if none): within 60 px of its middle.
func pick(cam: Camera3D, screen: Vector2) -> int:
	var best := -1
	var bd := 60.0
	for id in _nodes:
		var root: Node3D = _nodes[id].root
		var up := 1.8 if String(_nodes[id].kind) == "gate" else (1.4 if String(_nodes[id].kind) == "lamp" else 0.2)
		var p3 := root.global_position + Vector3(0, up, 0)
		if cam.is_position_behind(p3):
			continue
		var d := cam.unproject_position(p3).distance_to(screen)
		if d < bd:
			bd = d
			best = int(id)
	return best

# ---- Building the models ----------------------------------------------------------------------------------------------

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _cyl(r_top: float, r_bot: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

## Plain stone with a tiling rock texture (world-space, so pieces of any size match).
func _rock(tint: Color, tex := "ph_rough_block_wall", scale := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex + "_albedo.png")
	m.normal_enabled = true
	m.normal_texture = load(TEX + tex + "_normal.png")
	m.albedo_color = tint
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m

## The Warp Gate seen from the game camera (high and steep): a round stepped dais, a swirling violet pool of light
## lying in it, six standing stones round the rim with violet crystals on top, and a few stones floating above.
func _gate() -> Dictionary:
	var root := Node3D.new()
	var stone := _rock(Color(1.0, 1.0, 1.0), "ph_rough_block_wall", 0.5)
	var dark := _rock(Color(0.62, 0.62, 0.68), "ph_rough_block_wall", 0.5)
	_mesh(root, _cyl(2.45, 2.65, 0.24, 32), dark, Vector3(0, 0.06, 0))
	_mesh(root, _cyl(2.05, 2.15, 0.22, 32), stone, Vector3(0, 0.28, 0))
	# the pool of light in the dais
	var field := MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(3.5, 3.5)
	disc.orientation = PlaneMesh.FACE_Y
	field.mesh = disc
	var fm := ShaderMaterial.new()
	fm.shader = _field_shader()
	field.material_override = fm
	field.position = Vector3(0, 0.42, 0)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(field)
	# standing stones with crystals
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.7, 0.5, 1.0)
	cm.emission_enabled = true
	cm.emission = Color(0.62, 0.4, 1.0)
	cm.emission_energy_multiplier = 2.5
	cm.roughness = 0.2
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.26, 0.5, 0.26)
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		var at := Vector3(cos(a) * 2.25, 0, sin(a) * 2.25)
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.42, 1.7 + 0.25 * float(i % 2), 0.42)
		_mesh(root, pillar, stone, at + Vector3(0, pillar.size.y * 0.5 + 0.1, 0), Vector3(0, -a, 0))
		_mesh(root, crystal, cm, at + Vector3(0, pillar.size.y + 0.38, 0), Vector3(0, a, 0), false)
	var stones := Node3D.new()
	root.add_child(stones)
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.3
	sm.radial_segments = 8
	sm.rings = 4
	for i in 4:
		var a := TAU * i / 4.0
		_mesh(stones, sm, dark, Vector3(cos(a) * 1.1, 2.2, sin(a) * 1.1), Vector3(a, a * 2.0, 0), false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.62, 0.42, 1.0)
	l.light_energy = 1.2
	l.omni_range = 6.0
	l.position = Vector3(0, 1.4, 0)
	root.add_child(l)
	return {"root": root, "field_mat": fm, "light": l, "stones": stones, "glow": 1.0}

static var _field: Shader

## The gate's field: a disc of violet light turning inward, brighter with `power`.
static func _field_shader() -> Shader:
	if _field == null:
		_field = Shader.new()
		_field.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float power = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 2.6);
	float swirl2 = 0.5 + 0.5 * sin(a * 5.0 - r * 14.0 + TIME * 1.7);
	float edge = smoothstep(1.0, 0.82, r);
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	vec3 col = mix(vec3(0.35, 0.18, 0.85), vec3(0.75, 0.6, 1.0), swirl * swirl2);
	ALBEDO = col * (0.35 + 0.65 * swirl * swirl2 + core * 0.6) * edge * power * 0.9;
}
"""
	return _field

func _pond() -> Dictionary:
	var root := Node3D.new()
	var rockm := _rock(Color(0.92, 0.92, 0.95))
	# rocks round the rim
	var rm := SphereMesh.new()
	rm.radius = 0.42
	rm.height = 0.5
	rm.radial_segments = 8
	rm.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 18:
		var a := TAU * i / 18.0 + rng.randf_range(-0.08, 0.08)
		var r := 2.75 + rng.randf_range(-0.1, 0.15)
		var mi := _mesh(root, rm, rockm, Vector3(cos(a) * r, 0.05, sin(a) * r), Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0))
		mi.scale = Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.3))
	# the water
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.3, 0.32, 0.82)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.04
	wm.metallic = 0.3
	wm.rim_enabled = true
	wm.rim = 0.4
	_mesh(root, _cyl(2.7, 2.7, 0.04, 40), wm, Vector3(0, 0.1, 0), Vector3.ZERO, false)
	var bed := StandardMaterial3D.new()
	bed.albedo_color = Color(0.06, 0.1, 0.08)
	_mesh(root, _cyl(2.7, 2.7, 0.02, 40), bed, Vector3(0, 0.06, 0), Vector3.ZERO, false)
	# six pads, each with a flower that opens when a lily is there
	var pad := _cyl(0.42, 0.42, 0.02, 14)
	var padm := StandardMaterial3D.new()
	padm.albedo_color = Color(0.2, 0.5, 0.18)
	padm.roughness = 0.6
	var petal := SphereMesh.new()
	petal.radius = 0.14
	petal.height = 0.12
	petal.radial_segments = 8
	petal.rings = 4
	var petm := StandardMaterial3D.new()
	petm.albedo_color = Color(1.0, 0.72, 0.85)
	petm.emission_enabled = true
	petm.emission = Color(1.0, 0.55, 0.75)
	petm.emission_energy_multiplier = 0.9
	var heart := fx._glow(Color(1.0, 0.95, 0.55), 3.0)
	var flowers: Array = []
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var at := Vector3(cos(a) * 1.55, 0.13, sin(a) * 1.55)
		_mesh(root, pad, padm, at, Vector3(0, a, 0), false)
		var f := Node3D.new()
		f.position = at + Vector3(0, 0.05, 0)
		root.add_child(f)
		for k in 6:
			var pa := TAU * k / 6.0
			var p := _mesh(f, petal, petm, Vector3(cos(pa) * 0.13, 0.06, sin(pa) * 0.13), Vector3(0, -pa, 0.6), false)
			p.scale = Vector3(1.3, 1.0, 0.7)
		var c := SphereMesh.new()
		c.radius = 0.07
		c.height = 0.14
		_mesh(f, c, heart, Vector3(0, 0.1, 0), Vector3.ZERO, false)
		f.scale = Vector3.ONE * 0.001
		f.visible = false
		flowers.append(f)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.85)
	l.light_energy = 0.6
	l.omni_range = 4.0
	l.position = Vector3(0, 0.8, 0)
	root.add_child(l)
	return {"root": root, "flowers": flowers, "shown": 0}

func _lamp() -> Dictionary:
	var root := Node3D.new()
	var stone := _rock(Color(0.85, 0.83, 0.8), "ph_rough_block_wall", 0.8)
	var base := BoxMesh.new()
	base.size = Vector3(0.8, 0.35, 0.8)
	_mesh(root, base, stone, Vector3(0, 0.12, 0))
	_mesh(root, _cyl(0.17, 0.24, 2.3, 10), stone, Vector3(0, 1.35, 0))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.11, 0.1)
	iron.metallic = 0.75
	iron.roughness = 0.4
	var cap := BoxMesh.new()
	cap.size = Vector3(0.56, 0.08, 0.56)
	_mesh(root, cap, iron, Vector3(0, 2.52, 0))
	_mesh(root, _cyl(0.0, 0.36, 0.3, 4), iron, Vector3(0, 3.14, 0), Vector3(0, PI * 0.25, 0))
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var bar := BoxMesh.new()
		bar.size = Vector3(0.05, 0.5, 0.05)
		_mesh(root, bar, iron, Vector3(cos(a) * 0.25, 2.78, sin(a) * 0.25), Vector3.ZERO, false)
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.17
	cm.height = 0.38
	core.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.albedo_color = Color(0.55, 0.55, 0.5)
	mat.emission = Color(0.55, 0.55, 0.5)
	mat.emission_energy_multiplier = 0.4
	core.material_override = mat
	core.position = Vector3(0, 2.78, 0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var l := OmniLight3D.new()
	l.light_energy = 0.0
	l.omni_range = 7.0
	l.position = Vector3(0, 2.8, 0)
	l.visible = false
	root.add_child(l)
	root.scale = Vector3.ONE * 1.25
	return {"root": root, "core": core, "light": l, "state": -1}
