class_name UnitView
extends Node3D
## The rendered body of one simulation unit: model, weapons, animation state (idle, run with speed matched to the
## ground, attack swings timed so the blow lands exactly at the simulation's attack point, casts, death), smooth
## interpolation between the 30 Hz simulation ticks, and the selection ring.

const C = preload("res://src/sim/sim_const.gd")
const AP = preload("res://src/sim/sim_unit.gd").AtkPhase
const CP = preload("res://src/sim/sim_unit.gd").CastPhase

var uid := -1
var key := ""
var cfg := {}
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var appearance: HeroAppearance
var prev_pos := Vector2.ZERO
var cur_pos := Vector2.ZERO
var prev_facing := 0.0
var cur_facing := 0.0
var _clip := ""
var _attack_i := 0
var _dead_at := -1.0
var _base_y := 0.0
var _ring: MeshInstance3D
var _model_scale := 1.0
var terrain: TerrainBuilder
var team := 0
var is_hero := false
var bar_height := 2.0
var hidden_by_fog := false
var _flash := 0.0
var _lock_until := 0.0                    # an attack / cast clip plays to here before idle/run may take over

func setup(u: SimUnit, p_terrain: TerrainBuilder) -> void:
	uid = u.id
	terrain = p_terrain
	key = String(u.def.model)
	cfg = ModelCatalog.info(key)
	team = u.team
	is_hero = u.is_hero()
	bar_height = float(cfg.get("bar", 2.0))
	name = "Unit_%d" % uid
	prev_pos = u.pos
	cur_pos = u.pos
	prev_facing = u.facing
	cur_facing = u.facing
	if cfg.is_empty():
		return
	model = ModelCatalog.scene(key).instantiate() as Node3D
	add_child(model)
	_model_scale = float(cfg.scale)
	model.scale = Vector3.ONE * _model_scale
	# models face -Y in Blender, which imports as +Z; turn them to face the sim's facing (applied on this node)
	model.rotation.y = PI
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skeleton = sks[0] if not sks.is_empty() else null
	if key == "hero":
		appearance = HeroAppearance.new(model)
		appearance.apply(u.look.get("look", {}))
		appearance.dress(u.look.get("outfit", {}), u.look.get("dyes", {}))
	_weapons()
	if cfg.has("tint"):
		_tint(cfg.tint)
	if not is_hero and u.team < 2:
		_faction_colors(u.team)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_make_ring(u)
	_play(String(cfg.idle), true)

func _weapons() -> void:
	if skeleton == null:
		return
	for side in ["R", "L"]:
		var wname := String(cfg.get(side, ""))
		var ps := ModelCatalog.weapon(wname)
		if ps == null:
			continue
		var bone: String = "weapon." + side
		if skeleton.find_bone(bone) < 0:
			continue
		var at := BoneAttachment3D.new()
		at.bone_name = bone
		skeleton.add_child(at)
		var w := ps.instantiate() as Node3D
		at.add_child(w)

func _tint(c: Color) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				var m := src.duplicate() as BaseMaterial3D
				m.albedo_color = src.albedo_color * c
				mi.set_surface_override_material(i, m)

## Lane creeps wear their faction's colours: Dawn royal blue and gold, Dusk crimson and black.
const FACTION_COLORS := [
	{"BH_Cloth_Primary": Color(0.16, 0.34, 0.78), "BH_Cloth_Secondary": Color(0.86, 0.78, 0.58),
		"BH_Emissive": Color(1.0, 0.85, 0.42), "BH_Aether": Color(1.0, 0.85, 0.42)},
	{"BH_Cloth_Primary": Color(0.52, 0.05, 0.08), "BH_Cloth_Secondary": Color(0.12, 0.04, 0.06),
		"BH_Emissive": Color(1.0, 0.28, 0.2), "BH_Aether": Color(1.0, 0.28, 0.2)},
]
static var _faction_mats := {}

func _faction_colors(t: int) -> void:
	var table: Dictionary = FACTION_COLORS[t]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var bm := src as BaseMaterial3D
			if bm == null:
				continue
			var base := bm.resource_name.get_slice("__", 0).get_slice(".", 0)
			if not table.has(base):
				continue
			var k := "%d|%d" % [bm.get_instance_id(), t]
			if not _faction_mats.has(k):
				var m := bm.duplicate() as BaseMaterial3D
				m.albedo_color = table[base]
				if base == "BH_Emissive" or base == "BH_Aether":
					m.emission_enabled = true
					m.emission = table[base]
					m.emission_energy_multiplier = 2.5
				_faction_mats[k] = m
			mi.set_surface_override_material(i, _faction_mats[k])

func _make_ring(u: SimUnit) -> void:
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r := maxf(u.hull, 20.0) * View.S * 1.6
	tm.inner_radius = r * 0.86
	tm.outer_radius = r
	tm.rings = 32
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.scale = Vector3(1, 0.05, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.3, 1.0, 0.4, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

func set_selected(on: bool, color: Color) -> void:
	if _ring:
		_ring.visible = on
		(_ring.material_override as StandardMaterial3D).albedo_color = color

# ---- Simulation sync ------------------------------------------------------------------------------------------------

## Called after every simulation tick.
func tick(u: SimUnit) -> void:
	prev_pos = cur_pos
	prev_facing = cur_facing
	cur_pos = u.pos
	cur_facing = u.facing
	if not u.alive:
		if _dead_at < 0.0:
			_dead_at = Time.get_ticks_msec() / 1000.0
			_play(String(cfg.get("death", "death")), false, 1.0, 0.1)
		return
	if _dead_at >= 0.0:
		# respawned
		_dead_at = -1.0
		prev_pos = u.pos
		model.position.y = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if u.cast_phase == CP.WINDUP and _clip != String(cfg.get("cast", "cast_quick")):
		var cc := String(cfg.get("cast", "cast_quick"))
		_play(cc, false, 1.0, 0.08)
		_lock_until = now + float(ModelCatalog.clip(cc).get("length", 0.5)) * 0.8
		return
	if now < _lock_until and u.moving == false:
		return
	if u.moving:
		_lock_until = 0.0
		var run := String(cfg.get("run", "run"))
		var gs := float(ModelCatalog.clip(run).get("ground_speed", 5.0)) * _model_scale
		var spd := clampf(u.move_speed * View.S / maxf(gs, 0.1), 0.4, 2.5)
		_play(run, true, spd, 0.12)
	elif now >= _lock_until:
		_play(String(cfg.idle), true, 1.0, 0.25)

## The simulation started an attack: swing so the blow lands at the attack point.
func on_attack_start(point_time: float) -> void:
	var clips: Array = cfg.get("attack", ["sword_1"])
	var clip := String(clips[_attack_i % clips.size()])
	_attack_i += 1
	if anim and not anim.has_animation(clip):
		for c in clips:
			if anim.has_animation(c):
				clip = c
				break
	var strike := ModelCatalog.strike_time(clip)
	var spd := clampf(strike / maxf(point_time, 0.05), 0.35, 3.0)
	_play(clip, false, spd, 0.06, true)
	var length := float(ModelCatalog.clip(clip).get("length", 0.6))
	_lock_until = Time.get_ticks_msec() / 1000.0 + length / spd

func on_attack_cancel() -> void:
	_lock_until = 0.0

func flash() -> void:
	_flash = 1.0

func _play(clip: String, loop: bool, speed := 1.0, blend := 0.15, restart := false) -> void:
	if anim == null:
		return
	if not anim.has_animation(clip):
		if clip == String(cfg.idle) and anim.has_animation("idle"):
			clip = "idle"
		elif anim.has_animation("idle"):
			if clip.begins_with("run") or clip == "walk":
				clip = "walk" if anim.has_animation("walk") else "idle"
			else:
				return
		else:
			return
	var a := anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if clip == _clip and not restart and anim.is_playing():
		anim.speed_scale = speed
		return
	_clip = clip
	anim.play(clip, blend, 1.0)
	anim.speed_scale = speed
	if restart:
		anim.seek(0.0, true)

## Called every rendered frame with the interpolation fraction between the last two ticks.
func frame(alpha: float, delta: float) -> void:
	var p := prev_pos.lerp(cur_pos, alpha)
	var h := terrain.height_at(p)
	position = View.to3(p, h)
	rotation.y = View.yaw(lerp_angle(prev_facing, cur_facing, alpha))
	if _dead_at >= 0.0 and model:
		var t := Time.get_ticks_msec() / 1000.0 - _dead_at
		if t > 2.5 and not is_hero:
			model.position.y = -(t - 2.5) * 0.7
	if _ring and _ring.visible:
		_ring.position.y = 0.04
