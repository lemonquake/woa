class_name HeroStage
extends Node3D
## The lit stage the menus show a hero on (Main Menu, Hero Select, the lobby, the portrait baker): a stone pedestal
## with a glowing ring in the hero's colour, a soft backdrop glow, key, rim and fill lights, fog, and the hero in its
## own look with its weapons, idle and a flourish when chosen. Floating heroes hover over their fire; Froster stands in
## drifting snow, Caziel in shadow smoke. Put it in a SubViewport with own_world_3d.
##
## framing(): "select" (the hero in the middle, full height), "menu" (to the right, the camera further back),
## "portrait" (the head and shoulders, for the HUD's hero tiles).

const ACCENTS := {
	"blood_ranger": Color(0.95, 0.22, 0.25), "ezee": Color(0.66, 0.3, 1.0), "azrin": Color(1.0, 0.5, 0.15),
	"sludge": Color(0.55, 0.78, 0.3), "froster": Color(0.45, 0.82, 1.0), "caziel": Color(0.66, 0.36, 1.0),
	"tock": Color(1.0, 0.8, 0.38), "kragg": Color(0.4, 0.65, 1.0), "roydo": Color(0.62, 0.42, 1.0),
	"blau": Color(0.35, 0.82, 1.0), "azrael": Color(0.92, 0.12, 0.16)}
const FLOURISH := {"blood_ranger": "bow_1", "ezee": "boss_roar", "azrin": "cast_area", "sludge": "hero_axe_smash",
	"froster": "cast_area", "caziel": "dual_heavy", "tock": "wand_heavy", "kragg": "shield_bash",
	"roydo": "roydo_cast_shoot", "blau": "blau_reload", "azrael": "gs_heavy"}
const IDLE := {"blood_ranger": "idle_bow", "ezee": "idle_2h", "azrin": "idle_staff", "sludge": "idle_1h",
	"froster": "idle_staff", "caziel": "idle_shadowblade", "tock": "idle_wand", "kragg": "idle_shield",
	"roydo": "roydo_idle_fold", "blau": "blau_idle", "azrael": "idle_staff"}

var hero_id := ""
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var cam: Camera3D
var env: Environment
var yaw := 0.35
var spin := 0.12                           # radians a second while not dragged
var dragging := false
var mode := "select"
var _rim: SpotLight3D
var _ring_mat: StandardMaterial3D
var _backdrop_mat: ShaderMaterial
var _aura: Node3D
var _aura_parts := {}                      # bone name -> emitter (fire on Azrin's hands and hair)
var _fire_fx: FireFx
var _lift := 0.0
var _t := 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.025, 0.03, 0.05)
	sm.sky_horizon_color = Color(0.12, 0.1, 0.14)
	sm.ground_bottom_color = Color(0.015, 0.015, 0.02)
	sm.ground_horizon_color = Color(0.1, 0.085, 0.1)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.1
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.028
	env.fog_light_color = Color(0.09, 0.075, 0.11)
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, -24, 0)
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.92, 0.82)
	key.shadow_enabled = true
	add_child(key)
	_rim = SpotLight3D.new()
	_rim.position = Vector3(-1.2, 3.6, -2.6)
	_rim.light_energy = 9.0
	_rim.spot_range = 9.0
	_rim.spot_angle = 32.0
	add_child(_rim)
	_rim.look_at(Vector3(0, 1.0, 0))
	var rim2 := SpotLight3D.new()
	rim2.position = Vector3(1.6, 3.4, -2.4)
	rim2.light_energy = 7.0
	rim2.spot_range = 9.0
	rim2.spot_angle = 30.0
	rim2.light_color = Color(0.95, 0.95, 1.0)
	add_child(rim2)
	rim2.look_at(Vector3(0, 1.2, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.2, 1.6, 2.4)
	fill.light_energy = 1.1
	fill.omni_range = 7.0
	fill.light_color = Color(0.7, 0.75, 1.0)
	add_child(fill)
	# the pedestal: a worn stone drum with a glowing ring
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.2
	cyl.height = 0.32
	cyl.radial_segments = 48
	ped.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.19, 0.2)
	pm.roughness = 0.85
	ped.material_override = pm
	ped.position.y = -0.16
	add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 0.98
	tm.rings = 64
	ring.mesh = tm
	ring.scale = Vector3(1, 0.15, 1)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.emission_enabled = true
	_ring_mat.emission_energy_multiplier = 3.0
	ring.material_override = _ring_mat
	ring.position.y = 0.005
	add_child(ring)
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(40, 40)
	floor_mi.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.05, 0.06)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	floor_mi.position.y = -0.32
	add_child(floor_mi)
	var bd := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(22, 12)
	bd.mesh = bq
	var bsh := Shader.new()
	bsh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 accent : source_color = vec4(0.6, 0.3, 1.0, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.55)) * vec2(1.6, 1.0);
	float g = exp(-dot(p, p) * 8.0);
	float g2 = exp(-dot(p, p) * 30.0);
	ALBEDO = mix(vec3(0.006, 0.006, 0.01), accent.rgb * 0.08 + vec3(0.01), g) + accent.rgb * g2 * 0.05;
}
"""
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = bsh
	bd.material_override = _backdrop_mat
	bd.position = Vector3(0, 3.5, -30.0)
	bd.scale = Vector3(6.0, 4.0, 1.0)
	add_child(bd)
	_scenery()
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	framing(mode)

## The place the hero stands in: a polished stone floor and a carved pedestal, an arch behind the hero, a ring of
## columns fading into lit fog, burning braziers either side, cliffs far behind, dust drifting in the light.
func _scenery() -> void:
	if not scenery:
		return
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.026
	env.volumetric_fog_albedo = Color(0.42, 0.4, 0.46)
	env.volumetric_fog_emission = Color(0.012, 0.01, 0.016)
	env.volumetric_fog_length = 40.0
	env.fog_density = 0.012
	_rim.light_volumetric_fog_energy = 2.2
	_rim.shadow_enabled = true
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = load("res://assets/textures/building/ph_medieval_blocks_02_albedo.png")
	floor_mat.normal_enabled = true
	floor_mat.normal_texture = load("res://assets/textures/building/ph_medieval_blocks_02_normal.png")
	floor_mat.roughness_texture = load("res://assets/textures/building/ph_medieval_blocks_02_rough.png")
	floor_mat.albedo_color = Color(0.2, 0.19, 0.21)
	floor_mat.roughness = 0.42
	floor_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	floor_mat.uv1_triplanar = true
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 40.0
	dm.bottom_radius = 40.0
	dm.height = 0.1
	dm.radial_segments = 64
	disc.mesh = dm
	disc.material_override = floor_mat
	disc.position.y = -0.37
	add_child(disc)
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_texture = load("res://assets/textures/building/ph_rough_block_wall_albedo.png")
	ped_mat.normal_enabled = true
	ped_mat.normal_texture = load("res://assets/textures/building/ph_rough_block_wall_normal.png")
	ped_mat.albedo_color = Color(0.42, 0.4, 0.42)
	ped_mat.uv1_triplanar = true
	ped_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh and c != disc:
			(c as MeshInstance3D).material_override = ped_mat
	# a second, wider step under the pedestal
	var step := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 1.55
	sm.bottom_radius = 1.65
	sm.height = 0.14
	sm.radial_segments = 48
	step.mesh = sm
	step.material_override = ped_mat
	step.position.y = -0.31
	add_child(step)
	# behind the hero: a light in its colour deep in the fog, a haze that glows round its silhouette
	var halo := OmniLight3D.new()
	halo.position = Vector3(0.0, 2.6, -5.5)
	halo.omni_range = 12.0
	halo.light_energy = 2.0
	halo.light_volumetric_fog_energy = 2.6
	halo.shadow_enabled = false
	add_child(halo)
	_halo = halo
	# a shaft of light from high above onto the pedestal
	var shaft := SpotLight3D.new()
	shaft.position = Vector3(0.4, 10.0, 0.8)
	shaft.spot_range = 14.0
	shaft.spot_angle = 14.0
	shaft.light_energy = 6.0
	shaft.light_volumetric_fog_energy = 4.0
	shaft.light_color = Color(1.0, 0.94, 0.84)
	shaft.shadow_enabled = true
	add_child(shaft)
	shaft.look_at(Vector3(0, 0, 0))
	_shaft = shaft
	# the engraved emblem round the pedestal, glowing in the hero's colour
	var emb := MeshInstance3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(5.2, 5.2)
	eq.orientation = PlaneMesh.FACE_Y
	emb.mesh = eq
	var esh := Shader.new()
	esh.code = EMBLEM_CODE
	_emblem_mat = ShaderMaterial.new()
	_emblem_mat.shader = esh
	emb.material_override = _emblem_mat
	emb.position.y = -0.315
	add_child(emb)
	for side in [-1.0, 1.0]:
		var br := _prop("res://assets/props/brazier.glb", 1.15)
		if br:
			br.position = Vector3(side * 2.9, -0.32, -1.4)
			var fl := FireFx.flames(0.16, 0.5, 26.0, 0.55, 1.2, "fire", 1.3)
			fl.position = br.position + Vector3(0, 1.12, 0)
			add_child(fl)
			var em := FireFx.embers(0.2, 6.0, 1.6, 1.2)
			em.position = fl.position
			add_child(em)
			var bl := FireFx.light(Color(1.0, 0.55, 0.22), 1.8, 5.0)
			bl.position = fl.position + Vector3(0, 0.3, 0)
			bl.light_volumetric_fog_energy = 1.5
			add_child(bl)
			_braziers.append(bl)
	var dust := FireFx.embers(6.0, 14.0, 6.0, 0.15, 0.025, Color(1.0, 0.86, 0.6))
	dust.position = Vector3(0, 2.0, -1.0)
	(dust.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(dust.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(6, 2.5, 2)
	dust.position = Vector3(0, 2.0, -3.0)
	add_child(dust)

var scenery := true
var _braziers: Array = []
var _shaft: SpotLight3D
var _halo: OmniLight3D
var _emblem_mat: ShaderMaterial

const EMBLEM_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 accent : source_color = vec4(1.0, 0.6, 0.2, 1.0);
float ring(float r, float c, float w) { return smoothstep(w, 0.0, abs(r - c)); }
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float t = TIME * 0.15;
	// two inlaid rings, a band of ticks between them that turns slowly, and eight spokes
	float g = ring(r, 0.92, 0.012) + ring(r, 0.78, 0.008) * 0.8;
	float ticks = step(0.6, fract((a + t) * 48.0 / 6.2831853)) * step(0.8, r) * step(r, 0.9);
	float spokes = smoothstep(0.03, 0.0, abs(sin((a - t * 0.5) * 4.0))) * step(0.62, r) * step(r, 0.77);
	float glow = (g + ticks * 0.6 + spokes * 0.5) * (1.0 - smoothstep(0.95, 1.0, r));
	ALBEDO = accent.rgb * 1.6 * glow;
	ALPHA = clamp(glow * 0.8, 0.0, 1.0);
}
"""

## A prop scaled to `height` metres, added to the stage (null if missing).
func _prop(path: String, height: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	add_child(n)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.get_aabb()
		b = mi.transform * b
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.01:
		n.scale = Vector3.ONE * height / box.size.y
	return n

## Where the camera stands (see the class notes).
func framing(m: String) -> void:
	mode = m
	if cam == null:
		return
	match m:
		"menu":
			cam.fov = 34.0
			cam.position = Vector3(-1.55, 1.5 + _lift, 6.3)
			cam.look_at(Vector3(-1.55, 1.15 + _lift, 0))
		"portrait":
			cam.fov = 18.0
			_aim_portrait()
		_:
			cam.fov = 30.0
			cam.position = Vector3(0.0, 1.45 + _lift, 5.6)
			cam.look_at(Vector3(0.0, 1.05 + _lift, 0))

func _aim_portrait() -> void:
	var head := Vector3(0, 1.62 + _lift, 0)
	if skeleton:
		var bi := skeleton.find_bone("head")
		if bi < 0:
			bi = skeleton.find_bone("Head")             # the Universal rig (Roydo, Blau)
		if bi >= 0:
			head = (skeleton.global_transform * skeleton.get_bone_global_pose(bi)).origin + Vector3(0, 0.05, 0)
	cam.position = head + Vector3(0.0, 0.05, 1.9)
	cam.look_at(head - Vector3(0, 0.04, 0))

func accent() -> Color:
	return ACCENTS.get(hero_id, Color(0.9, 0.75, 0.4))

## Put hero `id` on the stage in `look` (the saved look when empty). flourish: play its flourish first.
func show_hero(id: String, look := {}, flourish := true) -> void:
	hero_id = id
	if model:
		model.queue_free()
	model = null
	anim = null
	skeleton = null
	var col := accent()
	_rim.light_color = col
	_backdrop_mat.set_shader_parameter("accent", col)
	_ring_mat.albedo_color = col
	_ring_mat.emission = col
	if _emblem_mat:
		_emblem_mat.set_shader_parameter("accent", col)
	if _halo:
		_halo.light_color = col
	var cfg := ModelCatalog.info(String(SimData.unit(id).model))
	var own := id in GameSettings.OWN_BODY
	model = (load(String(cfg.scene) if own else HeroLook.MODEL) as PackedScene).instantiate()
	RepairedClips.patch(model)
	add_child(model)
	model.rotation.y = yaw
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	if own:
		model.scale = Vector3.ONE * 0.92
		var sks := model.find_children("*", "Skeleton3D", true, false)
		skeleton = sks[0] if not sks.is_empty() else null
		UnitView.dress_own_body(model, cfg)
	else:
		var app := HeroAppearance.new(model)
		var lk: Dictionary = (look if not look.is_empty() else GameSettings.look_for(id)).duplicate(true)
		app.apply(lk.get("look", {}))
		app.dress(lk.get("outfit", {}), lk.get("dyes", {}))
		if cfg.has("spirit"):
			app.set_spirit(cfg.spirit)
		skeleton = app.skeleton
	for side in ["R", "L"]:
		var ps := ModelCatalog.weapon(String(cfg.get(side, "")))
		if skeleton and ps and skeleton.find_bone("weapon." + side) >= 0:
			var at := BoneAttachment3D.new()
			at.bone_name = "weapon." + side
			skeleton.add_child(at)
			var wpn := ps.instantiate() as Node3D
			at.add_child(wpn)
			wpn.transform = ModelCatalog.prop_transform(cfg, side)
			if cfg.has("weapon_tint"):
				for mi: MeshInstance3D in wpn.find_children("*", "MeshInstance3D", true, false):
					for i in mi.mesh.get_surface_count():
						var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
						if src:
							var m := src.duplicate() as BaseMaterial3D
							m.albedo_color = src.albedo_color * (cfg.weapon_tint as Color)
							m.metallic = 0.85
							m.roughness = 0.3
							mi.set_surface_override_material(i, m)
	_lift = 0.38 if cfg.has("float") and skeleton != null else 0.0
	model.position.y = _lift
	_stage_aura(id, cfg)
	framing(mode)
	if anim:
		var idle := String(IDLE.get(id, "idle"))
		if flourish and anim.has_animation(String(FLOURISH.get(id, ""))):
			_play(String(FLOURISH[id]), false)
			anim.queue(idle)
		else:
			_play(idle, true)
		var ia := anim.get_animation(idle)
		if ia:
			ia.loop_mode = Animation.LOOP_LINEAR

func _play(clip: String, loop: bool) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	var a := anim.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.play(clip, 0.2)

## The element round the hero on the stage.
func _stage_aura(id: String, cfg: Dictionary) -> void:
	if _aura and is_instance_valid(_aura):
		_aura.queue_free()
	_aura = Node3D.new()
	add_child(_aura)
	_aura_parts = {}
	if _fire_fx == null:
		_fire_fx = FireFx.new()
		add_child(_fire_fx)
	match id:
		"azrin":
			if not cfg.has("float") or skeleton == null:
				return
			var pyre := FireFx.flames(0.3, 0.7, 30.0, 0.6, 1.3, "fire", 1.0)
			_aura.add_child(pyre)
			pyre.position = Vector3(0, 0.12, 0)
			var pe := FireFx.embers(0.35, 12.0, 1.8, 1.4)
			_aura.add_child(pe)
			pe.position = Vector3(0, 0.2, 0)
			for k in ["hand.L", "hand.R"]:
				var hf := FireFx.flames(0.05, 0.42, 40.0, 0.4, 1.0, "fire", 1.5)
				_aura.add_child(hf)
				_aura_parts[k] = hf
			var hair := FireFx.flames(0.12, 0.4, 28.0, 0.45, 1.0, "fire", 1.15)
			_aura.add_child(hair)
			_aura_parts["head"] = hair
			var l := FireFx.light(Color(1.0, 0.55, 0.22), 1.6, 4.0)
			_aura.add_child(l)
			l.position = Vector3(0, 0.5, 0.4)
			_fire_fx.flicker(l)
		"froster":
			var sn := FrosterFx.snow(2.4, 3.4, 18.0, 2.8, 0.1)
			sn.position.z = -1.2
			_aura.add_child(sn)
			var mist := FrosterFx.mist(0.9, 12.0, 0.9, 2.2, 0.08, 0.3)
			mist.position.y = 0.1
			_aura.add_child(mist)
			var l2 := FireFx.light(Color(0.55, 0.8, 1.0), 0.45, 4.0)
			l2.position = Vector3(0, 1.0, 0.8)
			_aura.add_child(l2)
		"tock":
			var gm := FireFx.embers(0.9, 8.0, 2.4, 0.5, 0.03, Color(1.0, 0.82, 0.4))
			gm.position.y = 0.6
			_aura.add_child(gm)
			var dial := MeshInstance3D.new()
			var dq := QuadMesh.new()
			dq.size = Vector2(2.2, 2.2)
			dq.orientation = PlaneMesh.FACE_Y
			dial.mesh = dq
			var dm := Hero15Fx.dial_material(Color(1.0, 0.8, 0.4), 12.0)
			dm.set_shader_parameter("fade", 0.55)
			dial.material_override = dm
			dial.position.y = 0.04
			_aura.add_child(dial)
			var lt := FireFx.light(Color(1.0, 0.8, 0.45), 0.5, 4.0)
			lt.position = Vector3(0, 1.0, 0.8)
			_aura.add_child(lt)
		"kragg":
			var bm := CazielFx.motes(0.7, 16.0, Color(0.45, 0.7, 1.0), 0.8, 1.2, 0.03)
			bm.position.y = 0.6
			_aura.add_child(bm)
			var lk := FireFx.light(Color(0.4, 0.65, 1.0), 0.8, 4.0)
			lk.position = Vector3(0.4, 1.1, 0.6)
			_aura.add_child(lk)
			_fire_fx.flicker(lk)
		"roydo":
			# stars drifting up round him, a violet glow, his own skin is the night sky
			var st := FireFx.embers(0.8, 14.0, 2.6, 0.45, 0.03, Color(0.7, 0.55, 1.0))
			st.position.y = 0.5
			_aura.add_child(st)
			var lr := FireFx.light(Color(0.6, 0.4, 1.0), 0.9, 4.0)
			lr.position = Vector3(0.3, 1.2, 0.7)
			_aura.add_child(lr)
		"azrael":
			# white soul flame round her hem, pale motes, a cold light and a red one low behind her
			var sf := FireFx.flames(0.26, 0.26, 34.0, 0.55, 0.6, "soul", 0.55)
			sf.position.y = 0.3
			_aura.add_child(sf)
			var sm2 := FireFx.embers(0.6, 10.0, 1.8, 0.5, 0.035, Color(0.85, 0.92, 1.0))
			sm2.position.y = 0.9
			_aura.add_child(sm2)
			var la := FireFx.light(Color(0.8, 0.88, 1.0), 0.9, 4.0)
			la.position = Vector3(0.3, 1.3, 0.7)
			_aura.add_child(la)
			var lr2 := FireFx.light(Color(1.0, 0.1, 0.1), 0.7, 3.0)
			lr2.position = Vector3(-0.4, 0.6, -0.6)
			_aura.add_child(lr2)
		"blau":
			var bm2 := CazielFx.motes(0.7, 10.0, Color(0.4, 0.85, 1.0), 1.4, 0.6, 0.03)
			bm2.position.y = 0.5
			_aura.add_child(bm2)
			var lb := FireFx.light(Color(0.4, 0.8, 1.0), 0.6, 4.0)
			lb.position = Vector3(-0.3, 1.2, 0.7)
			_aura.add_child(lb)
		"caziel":
			var sm := CazielFx.shadow_smoke(0.7, 14.0, 0.9, 1.8, 0.35, 0.45)
			sm.position.y = 0.05
			_aura.add_child(sm)
			var mo := CazielFx.motes(0.8, 10.0, Color(0.66, 0.34, 1.0), 1.6, 0.5, 0.035)
			mo.position.y = 0.4
			_aura.add_child(mo)
		_:
			var mo2 := FireFx.embers(0.9, 6.0, 2.0, 0.6, 0.035, accent())
			mo2.position.y = 0.3
			_aura.add_child(mo2)

func _process(dt: float) -> void:
	_t += dt
	for i in _braziers.size():
		var bl: OmniLight3D = View.live(_braziers[i])
		bl.light_energy = 1.8 * (0.82 + 0.12 * sin(_t * 11.0 + i * 2.0) + 0.06 * sin(_t * 23.0 + i))
	if not dragging:
		yaw += dt * spin
	if model:
		model.rotation.y = yaw
		if _lift > 0.0:
			model.position.y = _lift + sin(_t * 2.5) * 0.04
	if skeleton and not _aura_parts.is_empty():
		for k in _aura_parts:
			var bi := skeleton.find_bone("weapon." + k.get_slice(".", 1) if k.begins_with("hand") else k)
			if bi < 0:
				continue
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(bi).origin
			(_aura_parts[k] as Node3D).global_position = p + (Vector3(0, 0.14, 0) if k == "head" else Vector3.ZERO)
	if mode == "portrait":
		_aim_portrait()

## Turn the hero by a mouse drag (pixels).
func drag(dx: float) -> void:
	yaw += dx * 0.01
