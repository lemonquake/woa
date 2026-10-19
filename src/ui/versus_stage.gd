class_name VersusStage
extends Node3D
## The versus scene before a ranked match (run 2026-10-19 b; the owner: "a fully rendered versus screen where all the
## heroes face each other as team vs team like an epic battle is about to unfold"). Both teams stand on a dark battle
## field in wedges, the leader in front, facing each other across a seam of light: your team on the left in blue
## light, the enemy on the right in red, each hero on a glowing ring of its team's colour, embers rising, fog, moon
## light with shadows. Each hero plays its flourish, then stands ready. The camera pushes in from high and wide to a low
## heroic angle. Heroes are added one at a time (add_hero, as they are picked) so the reveal does not stall; begin()
## starts the shot. head_point(id) gives where a hero's head is on screen (for the name and rank over it).
## Put it in a SubViewport with own_world_3d.

const FORMATION := [Vector2(1.8, 0.6), Vector2(3.1, 2.5), Vector2(3.6, -1.5), Vector2(4.9, 1.0), Vector2(5.9, -2.8)]
const BLUE := Color(0.35, 0.62, 1.0)
const RED := Color(1.0, 0.3, 0.25)
const GROUND := """
shader_type spatial;
render_mode diffuse_burley;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * n(p); p *= 2.1; a *= 0.5; } return v; }
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float f = fbm(p * 0.6);
	float g = fbm(p * 3.0 + 7.0);
	vec3 dirt = mix(vec3(0.07, 0.06, 0.055), vec3(0.16, 0.13, 0.1), f);
	dirt = mix(dirt, vec3(0.1, 0.1, 0.11), smoothstep(0.55, 0.75, g));
	// cracks
	float c = abs(fbm(p * 1.4 + 3.0) - 0.5);
	float crack = smoothstep(0.035, 0.0, c);
	// the seam of light between the teams
	float seam = exp(-pow(p.x * 2.2, 2.0)) * smoothstep(9.0, 0.0, abs(p.y));
	vec3 team = mix(vec3(0.1, 0.3, 0.9), vec3(0.9, 0.18, 0.1), smoothstep(-1.0, 1.0, p.x));
	ALBEDO = dirt * (1.0 - crack * 0.5);
	ROUGHNESS = 0.9 - 0.3 * g;
	EMISSION = vec3(1.0, 0.62, 0.25) * (seam * 0.9 + crack * seam * 2.0) + team * crack * 0.25 * smoothstep(1.0, 4.0, abs(p.x));
}
"""

var cam: Camera3D
var heroes := {}                           # id -> {model, anim, skeleton, lift, cfg, side, index, depth}
var _t := -1.0
var _shake := 0.0
var _cam_from := Vector3(0.0, 4.2, 16.0)
var _cam_to := Vector3(0.0, 1.35, 10.2)
var _look := Vector3(0.0, 1.45, 0.0)
var _embers: CPUParticles3D

func _ready() -> void:
	_build()

func _build() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.02, 0.025, 0.05)
	sm.sky_horizon_color = Color(0.16, 0.1, 0.12)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.12, 0.08, 0.08)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.035
	env.fog_light_color = Color(0.12, 0.09, 0.12)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-42, 18, 0)
	moon.light_energy = 1.3
	moon.light_color = Color(0.8, 0.85, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	add_child(moon)
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var col := BLUE if side == 0 else RED
		# the team's light from above and behind
		var sp := SpotLight3D.new()
		sp.position = Vector3(sx * 6.5, 7.0, 3.0)
		sp.look_at_from_position(sp.position, Vector3(sx * 3.4, 0.0, 0.0))
		sp.light_color = col
		sp.light_energy = 9.0
		sp.spot_range = 18.0
		sp.spot_angle = 38.0
		sp.shadow_enabled = true
		add_child(sp)
		# rim light from behind the line
		var rim := OmniLight3D.new()
		rim.position = Vector3(sx * 6.5, 2.4, -4.5)
		rim.light_color = col
		rim.light_energy = 4.0
		rim.omni_range = 9.0
		add_child(rim)
	var mid := OmniLight3D.new()
	mid.position = Vector3(0, 1.0, 1.0)
	mid.light_color = Color(1.0, 0.68, 0.32)
	mid.light_energy = 2.5
	mid.omni_range = 6.0
	add_child(mid)
	# the field
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 50)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = GROUND
	gm.shader = gs
	ground.material_override = gm
	add_child(ground)
	# the seam's column of light
	var beam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 9.0)
	beam.mesh = q
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	bm.albedo_texture = _beam_tex()
	bm.albedo_color = Color(1.0, 0.7, 0.35, 0.55)
	beam.material_override = bm
	beam.position = Vector3(0, 4.0, 0)
	add_child(beam)
	# embers rising over the field
	_embers = CPUParticles3D.new()
	_embers.amount = 220
	_embers.lifetime = 6.0
	_embers.preprocess = 6.0
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(9.0, 0.2, 5.0)
	_embers.direction = Vector3(0, 1, 0)
	_embers.spread = 25.0
	_embers.initial_velocity_min = 0.3
	_embers.initial_velocity_max = 0.9
	_embers.gravity = Vector3(0.1, 0.05, 0)
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.3
	var em := QuadMesh.new()
	em.size = Vector2(0.09, 0.09)
	var emm := StandardMaterial3D.new()
	emm.albedo_texture = _dot_tex()
	emm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	emm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	emm.albedo_color = Color(1.0, 0.6, 0.25, 0.9)
	em.material = emm
	_embers.mesh = em
	add_child(_embers)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.position = _cam_from
	add_child(cam)
	cam.look_at(_look)

static var _beam: Texture2D
static var _dot: Texture2D

## A soft round spark.
static func _dot_tex() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	_dot = t
	return t

static func _beam_tex() -> Texture2D:
	if _beam:
		return _beam
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 64:
			var u := absf(float(x) / 63.0 - 0.5) * 2.0
			var v := float(y) / 255.0
			var a := pow(1.0 - u, 3.0) * pow(sin(v * PI), 0.8) * (0.6 + 0.4 * (1.0 - v))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_beam = ImageTexture.create_from_image(img)
	return _beam

## Where a team's i-th hero stands (side 0 left, 1 right) and the way it faces (toward the other team, turned a little
## toward the camera).
static func spot(side: int, index: int) -> Vector3:
	var f: Vector2 = FORMATION[clampi(index, 0, 4)]
	return Vector3(-f.x if side == 0 else f.x, 0.0, f.y)

## Put a hero on the field (its look from GameSettings for you, the default look for bots).
func add_hero(id: String, hero: String, side: int, index: int) -> void:
	if heroes.has(id) or hero == "":
		return
	var look: Dictionary = GameSettings.look_for(hero) if id == "me" else GameSettings.default_look(hero)
	var holder := Node3D.new()
	holder.position = spot(side, index)
	add_child(holder)
	var built := HeroStage.make_hero(hero, look, holder)
	var model: Node3D = built.model
	model.position.y = float(built.lift)
	holder.rotation.y = (PI * 0.5 - 0.62) if side == 0 else (-PI * 0.5 + 0.62)
	# the team's ring under the hero
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.7
	tm.rings = 48
	ring.mesh = tm
	ring.scale = Vector3(1, 0.08, 1)
	var rm := StandardMaterial3D.new()
	var col := BLUE if side == 0 else RED
	rm.albedo_color = col
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 3.0
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position.y = 0.02
	holder.add_child(ring)
	built["holder"] = holder
	built["side"] = side
	built["index"] = index
	built["hero"] = hero
	heroes[id] = built
	# stand ready until the shot starts
	_play_idle(built)

func _play_idle(b: Dictionary) -> void:
	var anim: AnimationPlayer = b.anim
	if anim == null:
		return
	var idle := ModelCatalog.anim(b.cfg, String(HeroStage.IDLE.get(String(b.hero), "idle")))
	if anim.has_animation(idle):
		anim.get_animation(idle).loop_mode = Animation.LOOP_LINEAR
		anim.play(idle)
		anim.seek(randf() * 2.0, true)

## Start the shot: the camera pushes in; every hero plays its flourish (a little apart), then stands ready.
func begin() -> void:
	_t = 0.0
	var i := 0
	for id in heroes:
		var b: Dictionary = heroes[id]
		var anim: AnimationPlayer = b.anim
		if anim == null:
			continue
		var fl := ModelCatalog.anim(b.cfg, String(HeroStage.FLOURISH.get(String(b.hero), "")))
		var idle := ModelCatalog.anim(b.cfg, String(HeroStage.IDLE.get(String(b.hero), "idle")))
		if anim.has_animation(fl):
			var delay := 0.6 + 0.18 * float(i)
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(anim):
					anim.get_animation(fl).loop_mode = Animation.LOOP_NONE
					anim.play(fl, 0.2)
					if anim.has_animation(idle):
						anim.queue(idle))
		i += 1

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _process(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	var k := 1.0 - pow(1.0 - clampf(_t / 4.5, 0.0, 1.0), 3.0)
	var p := _cam_from.lerp(_cam_to, k)
	p.x += sin(_t * 0.35) * 0.5
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 2.0)
		p += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.12 * _shake
	cam.position = p
	cam.look_at(_look + Vector3(sin(_t * 0.35) * 0.2, 0, 0))

## The point over a hero's head (world), for its name plate.
func head_point(id: String) -> Vector3:
	var b: Dictionary = heroes.get(id, {})
	if b.is_empty():
		return Vector3.ZERO
	var holder: Node3D = b.holder
	var sk: Skeleton3D = b.skeleton
	if sk != null and is_instance_valid(sk):
		for bn in ["head", "Head", "mixamorig_Head", "mixamorig:Head", "DEF-head"]:
			var bi := sk.find_bone(bn)
			if bi >= 0:
				return sk.global_transform * sk.get_bone_global_pose(bi).origin + Vector3(0, 0.42, 0)
	return holder.global_position + Vector3(0, 2.3 + float(b.lift), 0)
