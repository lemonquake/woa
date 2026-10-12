class_name UnitView
extends Node3D
## The rendered body of one simulation unit: model, weapons, animation state (idle, run with speed matched to the
## ground, attack swings timed so the blow lands exactly at the simulation's attack point, ability casts timed to
## their cast points, leaps, death), reactions (hit flinch, hit clips, stun, being hurled through the air, slamming
## into walls, getting up), smooth interpolation between the 30 Hz simulation ticks, and the selection ring.

const C = preload("res://src/sim/sim_const.gd")
const AP = preload("res://src/sim/sim_unit.gd").AtkPhase
const CP = preload("res://src/sim/sim_unit.gd").CastPhase

var uid := -1
var key := ""
var cfg := {}
var model: Node3D
var pivot: Node3D                          # leans for hit flinches; the model hangs under it
var anim: AnimationPlayer
var skeleton: Skeleton3D
var appearance: HeroAppearance
var weapons: Array[Node3D] = []
var weapon_nodes := {}                     # "R" / "L" -> the weapon in that hand
var prev_pos := Vector2.ZERO
var cur_pos := Vector2.ZERO
var prev_facing := 0.0
var cur_facing := 0.0
var prev_lift := 0.0                       # metres above the ground (pushes, leaps), interpolated like the position
var cur_lift := 0.0
var _clip := ""
var _attack_i := 0
var _dead_at := -1.0
var _ring: MeshInstance3D
var _model_scale := 1.0
var terrain: TerrainBuilder
var team := 0
var is_hero := false
var bar_height := 2.0
var hidden_by_fog := false
var _flash := 0.0
var _lock_until := 0.0                    # an attack / cast / reaction clip plays to here before idle/run take over
var _state := ""                          # "", "stun", "air", "slide", "knock", "leap", "channel", "hop"
var _redraw_at := 0.0                     # Burst Shot: when the bow is drawn again after a wave's release
var _flinch := Vector2.ZERO               # lean direction * strength (view space x/z)
var _flinch_t := 1.0
var _glow_mat: StandardMaterial3D
var _glow_on := false
var swing_trail: Trail3D                  # melee heroes: a streak off the blade tip while swinging
var _swing_until := 0.0
var swing_lit := false                    # kept lit (Tainted Touch)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

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
	pivot = Node3D.new()
	add_child(pivot)
	if cfg.has("scene_dusk") and u.team == 1:
		model = (load(String(cfg.scene_dusk)) as PackedScene).instantiate() as Node3D
	else:
		model = ModelCatalog.scene(key).instantiate() as Node3D
	pivot.add_child(model)
	_model_scale = float(cfg.scale)
	model.scale = Vector3.ONE * _model_scale
	# models face -Y in Blender, which imports as +Z; turn them to face the sim's facing (applied on this node)
	model.rotation.y = PI
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	if anim and OS.get_cmdline_user_args().has("--noanim"):
		anim.active = false
		anim = null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skeleton = sks[0] if not sks.is_empty() else null
	if cfg.get("hero", false):
		appearance = HeroAppearance.new(model)
		appearance.apply(u.look.get("look", {}))
		appearance.dress(u.look.get("outfit", {}), u.look.get("dyes", {}))
	if cfg.has("skin_shader"):
		_skin(model, String(cfg.skin_shader))
	_weapons()
	if cfg.has("tint"):
		_tint(cfg.tint)
	if not is_hero and u.team < 2:
		_faction_colors(u.team)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if not is_hero or cfg.get("gear_materials", false):
			GearMaterials.apply(mi)
	_make_ring(u)
	var shade := MeshInstance3D.new()
	shade.mesh = Dressing.blob_mesh()
	var r := maxf(u.hull, 16.0) * View.S * 3.2
	shade.scale = Vector3(r, 1.0, r)
	shade.position.y = 0.04
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shade)
	_play(String(cfg.idle), true)

## A hero with its own body (Sludge) outside a match (Hero Select): skin shader and textured gear.
static func dress_own_body(m: Node3D, c: Dictionary) -> void:
	if c.has("skin_shader"):
		_skin(m, String(c.skin_shader))
	if c.get("gear_materials", false):
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			GearMaterials.apply(mi)

## A hero with its own body (Sludge): its skin surfaces get the hero's skin shader.
static func _skin(model: Node3D, path: String) -> void:
	var sh := load(path) as Shader
	if sh == null:
		return
	var m := ShaderMaterial.new()
	m.shader = sh
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with("SludgeSkin"):
				mi.set_surface_override_material(i, m)

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
		weapons.append(w)
		weapon_nodes[side] = w
		if cfg.has("weapon_tint"):
			_tint_node(w, cfg.weapon_tint, 0.85)
		if cfg.get("swing_trail", false) and side == "R":
			var tip := Node3D.new()
			w.add_child(tip)
			tip.position = Vector3(0, 0.95, 0)
			swing_trail = Trail3D.make(tip, Color(0.92, 0.92, 1.0, 0.45), 0.06, 0.14)
			swing_trail.emitting = false
			add_child(swing_trail)

## Darken a weapon to blackened steel (Ezee's greatsword).
func _tint_node(n: Node3D, c: Color, metal := -1.0) -> void:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				var m := src.duplicate() as BaseMaterial3D
				m.albedo_color = src.albedo_color * c
				if metal >= 0.0:
					m.metallic = metal
					m.roughness = 0.32
				mi.set_surface_override_material(i, m)

## The weapon's enchantment glow (Tainted Touch): an additive overlay that flickers.
func set_weapon_glow(on: bool, col := Color(0.6, 0.2, 1.0)) -> void:
	if on == _glow_on:
		return
	_glow_on = on
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.albedo_color = col
	for w in weapons:
		for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = _glow_mat if on else null

## Where a hand's weapon is held (the grip), in world space; the chest if that hand is empty.
## Read from the skeleton's current pose (a BoneAttachment3D can trail the pose by a frame).
func hand_point(side: String) -> Vector3:
	if skeleton:
		var bi := skeleton.find_bone("weapon." + side)
		if bi >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bi).origin
	var w: Node3D = weapon_nodes.get(side)
	if w and is_instance_valid(w):
		return w.global_position
	return global_position + Vector3(0, bar_height * 0.5, 0)

var _big := false
var _faded := false

## Lasting item states: Spell Shield makes the hero 30% bigger (as in Dota); an invisible unit of the player's team is
## drawn faded (enemies never see it at all).
func _item_states(u: SimUnit) -> void:
	var big := not u.get_modifier("spell_shield").is_empty()
	if big != _big:
		_big = big
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3.ONE * _model_scale * (1.3 if big else 1.0), 0.25)
	var faded := u.has_flag("invisible")
	if faded != _faded:
		_faded = faded
		for gi: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
			gi.transparency = 0.6 if faded else 0.0

## Hide a hand's weapon while it is away (Sludge's shuriken is flying on its chain).
func hide_weapon(side: String, hidden: bool) -> void:
	var w: Node3D = weapon_nodes.get(side)
	if w and is_instance_valid(w):
		w.visible = not hidden

func weapon_tip() -> Vector3:
	if weapons.is_empty():
		return global_position + Vector3(0, 1.4, 0)
	var w := weapons[0]
	return w.global_transform * Vector3(0, 0.9, 0)

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
	m.render_priority = 15
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
	prev_lift = cur_lift
	cur_pos = u.pos
	cur_facing = u.facing
	cur_lift = 0.0
	if not u.knock.is_empty() and u.knock.get("phys", false):
		cur_lift = float(u.knock.z) * View.S
	elif not u.leap.is_empty():
		cur_lift = float(u.leap.z) * View.S
	elif not u.hop.is_empty():
		cur_lift = float(u.hop.z) * View.S
	if not u.alive:
		if _knock_t >= 0.0:
			return
		if _dead_at < 0.0:
			_dead_at = _now()
			_state = ""
			_play(_death_clip(), false, 1.0, 0.1)
		return
	if _dead_at >= 0.0:
		# respawned
		_dead_at = -1.0
		prev_pos = u.pos
		model.position.y = 0.0
		_state = ""
	var now := _now()
	# --- forced motion and disables come first
	if not u.leap.is_empty():
		_state = "leap"
		return
	if _state == "leap":
		_state = ""
	_item_states(u)
	if not u.knock.is_empty() and not bool(u.knock.get("disable", true)) and not u.knock.get("phys", false):
		pass                                     # a Push Staff slide is not a disable: no stagger
	elif not u.knock.is_empty():
		if u.knock.get("drag", false):
			# caught by a Shuriken Hook: hauled along, limbs trailing
			if _state != "drag":
				_state = "drag"
				_play("knockback", false, 0.5, 0.06, true)
			return
		if u.knock.get("phys", false):
			var airborne: bool = float(u.knock.z) > 0.0 or float(u.knock.vz) > 0.0
			if now < _lock_until and _state == "wall":
				return
			if airborne and _state != "air":
				_state = "air"
				_play("launch", true, 1.2, 0.06)
			elif not airborne and _state == "air":
				_state = "slide"
				_play("knockback", false, 1.6, 0.08, true)
		elif _state != "knock":
			_state = "knock"
			_play("knockback", false, 1.2 / maxf(0.2, float(u.knock.dur)) * 0.55, 0.06, true)
		return
	# Burst Shot: the bow stays drawn while the channel lasts; each wave is a snap release, then a fresh draw
	if not u.channel.is_empty() and String(u.channel.ability) == "chomp":
		_state = "channel"
		return
	if not u.channel.is_empty() and String(u.channel.ability) == "burst_shot":
		_state = "channel"
		if now >= _redraw_at and _clip != "bow_draw_hold":
			_play("bow_draw_hold", true, 1.6, 0.08)
		return
	if _state == "channel":
		_state = ""
	if not u.hop.is_empty():
		_state = "hop"
		return
	if _state == "hop":
		_state = ""
		_lock_until = maxf(_lock_until, now + 0.12)
	if _state in ["air", "slide", "knock", "wall", "drag"]:
		_state = ""
		if not u.has_flag("stun"):
			# back on its feet
			_play("getup", false, 2.4, 0.08, true)
			_lock_until = now + 0.36
	if u.has_flag("stun"):
		if _state != "stun":
			_state = "stun"
			_play("hit_heavy", false, 1.3, 0.06, true)
			_stun_loop_at = now + 0.4
		elif now >= _stun_loop_at and _clip != _stun_clip():
			_play(_stun_clip(), true, 0.75, 0.2)
		return
	if _state == "stun":
		_state = ""
		_lock_until = 0.0
	if now < _lock_until and u.moving == false:
		return
	if u.moving:
		_lock_until = 0.0
		var run := String(cfg.get("run", "run"))
		if cfg.has("run_female") and float(u.look.get("look", {}).get("female", 0.0)) >= 0.5:
			run = String(cfg.run_female)
		var gs := float(ModelCatalog.clip(run).get("ground_speed", 5.0)) * _model_scale
		var spd := clampf(u.move_speed * View.S / maxf(gs, 0.1), float(cfg.get("run_min", 0.4)), 2.5)
		_play(run, true, spd, 0.12)
	elif now >= _lock_until:
		_play(String(cfg.idle), true, 1.0, 0.25)

var _stun_loop_at := 0.0

func _stun_clip() -> String:
	if anim and anim.has_animation("idle_hurt"):
		return "idle_hurt"
	return String(cfg.idle)

func _death_clip() -> String:
	var base := String(cfg.get("death", "death"))
	if is_hero and anim:
		var opts := [base, "death_back", "death_fwd", "death_crumple"].filter(func(c): return anim.has_animation(c))
		if not opts.is_empty():
			return opts[randi() % opts.size()]
	return base

## The simulation started an attack: swing so the blow lands at the attack point.
func on_attack_start(point_time: float) -> void:
	if _state != "":
		return
	var clips: Array = cfg.get("attack", ["sword_1"])
	if clips.is_empty():
		return
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
	_lock_until = _now() + length / spd
	_swing_until = _now() + (strike / spd) * 1.35

func on_attack_cancel() -> void:
	_lock_until = 0.0

## Burst Shot began: draw and hold.
func on_channel_start(aid: String) -> void:
	if aid == "chomp":
		# Chomp: hold the victim and eat
		_state = "channel"
		_play("devour", true, 1.1, 0.08, true)
		return
	if aid != "burst_shot":
		return
	_state = "channel"
	_redraw_at = 0.0
	_play("bow_draw_hold", true, 1.6, 0.06, true)

## A wave left the string: a quick release, then the next draw.
func on_burst_wave() -> void:
	_play("bow_release", false, 1.8, 0.03, true)
	_redraw_at = _now() + 0.22

func on_channel_end() -> void:
	if _state == "channel":
		_state = ""
	_lock_until = _now() + 0.15

## Blood Ranger's back leap: a quick crouch-and-spring clip stretched over the leap.
func on_back_leap(dur: float) -> void:
	var clip := "dodge_step" if anim and anim.has_animation("dodge_step") else "blink"
	var length := float(ModelCatalog.clip(clip).get("length", 0.47))
	_play(clip, false, clampf(length / maxf(0.12, dur + 0.12), 0.8, 3.0), 0.04, true)
	_state = "hop"
	_lock_until = _now() + dur + 0.1

## An ability's cast point began: play its clip so the release frame meets the cast point.
func on_cast_start(aid: String, cast_point: float) -> void:
	var a := SimData.ability(aid)
	var clip := String(a.get("anim", cfg.get("cast", "cast_quick"))) if aid != "" else String(cfg.get("cast", "cast_quick"))
	if anim == null or not anim.has_animation(clip):
		clip = String(cfg.get("cast", "cast_quick"))
	var meta := ModelCatalog.clip(clip)
	var release := ModelCatalog.strike_time(clip)
	if aid == "leap_strike":
		release = float((meta.get("airborne", [0.333, 0.7]) as Array)[0])
	var spd := clampf(release / maxf(cast_point, 0.05), 0.5, 3.0) if cast_point > 0.0 else 1.6
	_play(clip, false, spd, 0.06, true)
	var length := float(meta.get("length", 0.6))
	# after the release the clip finishes at a natural pace
	_lock_until = _now() + cast_point + maxf(0.0, length - release) / maxf(1.0, spd * 0.8)
	_swing_until = _now() + cast_point + 0.25

## Leap Strike took off: stretch the airborne part of the clip so its strike frame lands with the simulation.
func on_leap(dur: float) -> void:
	if anim == null or _clip != "leap_slam":
		_play("leap_slam", false, 1.0, 0.05, true)
		anim.seek(0.333, true)
	var pos := anim.current_animation_position
	var hit := 0.62
	anim.speed_scale = clampf((hit - pos) / maxf(0.1, dur), 0.25, 2.0)
	_lock_until = _now() + dur + 0.6

func on_leap_land() -> void:
	if anim and _clip == "leap_slam":
		anim.speed_scale = 1.1
	_lock_until = _now() + 0.42

## A pushed unit slammed into a wall, tree, building or another unit.
func on_impact(what: String) -> void:
	if what == "unit":
		_play("hit_heavy", false, 1.6, 0.04, true)
		_lock_until = _now() + 0.25
		return
	_state = "wall"
	_play("wall_impact", false, 1.5, 0.04, true)
	_lock_until = _now() + 0.45

static var _flash_mat: StandardMaterial3D

## Took damage: a short white flash for attacks, a lean away from the blow and, standing still, a hit clip.
func on_hit(from: Vector2, amount: float, max_hp: float, attack: bool) -> void:
	if model == null or amount <= 0.0:
		return
	if attack:
		flash()
	var frac := amount / maxf(1.0, max_hp)
	var heavy := frac > 0.12 or (not attack and frac > 0.05)
	var dir := cur_pos - from
	if dir.length() < 1.0:
		dir = Vector2.from_angle(cur_facing + PI)
	dir = dir.normalized()
	# into this view's local space: forward is -Z, sim facing 0 = east
	var local := dir.rotated(-cur_facing)
	var strength := clampf(0.05 + frac * 1.2, 0.05, 0.22)
	_flinch = Vector2(-local.y, -local.x) * strength
	_flinch_t = 0.0
	if _state == "" and _dead_at < 0.0 and _now() >= _lock_until and heavy:
		var clip := "hit_heavy" if frac > 0.2 else ("hit_front" if local.x < 0.0 else "hit_light")
		if anim and anim.has_animation(clip):
			_play(clip, false, 1.25, 0.05, true)
			_lock_until = _now() + 0.32

## A brief white flash when hit.
func flash() -> void:
	if model == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.28)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if _flash <= 0.0:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mi.material_overlay == null or mi.material_overlay == _flash_mat:
				mi.material_overlay = _flash_mat
	_flash = 0.09

## Lane creeps killed by a big enough blow are thrown back up to 200 units in a short arc (Dota's death knockback).
var _knock_from := Vector2.ZERO
var _knock_to := Vector2.ZERO
var _knock_t := -1.0
var _knock_dur := 0.5
var _knock_h := 0.0

func death_knock(from: Vector2, damage: float) -> void:
	if damage < 100.0:
		return
	var dir := (cur_pos - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(randf() * TAU)
	var dist := clampf(damage, 100.0, 500.0) / 500.0 * 200.0 * randf_range(0.6, 1.0)
	_knock_from = cur_pos
	_knock_to = cur_pos + dir * dist
	_knock_dur = randf_range(0.4, 0.6)
	_knock_h = dist / 200.0 * 0.5
	_knock_t = 0.0

func _play(clip: String, loop: bool, speed := 1.0, blend := 0.15, restart := false) -> void:
	if anim == null:
		return
	if not anim.has_animation(clip):
		if clip == String(cfg.idle) and anim.has_animation("idle"):
			clip = "idle"
		elif anim.has_animation("idle"):
			if clip.begins_with("run") or clip == "walk" or clip.ends_with("_run"):
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
func frame(alpha: float, delta: float, cam: Camera3D = null) -> void:
	var p := prev_pos.lerp(cur_pos, alpha)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and model:
			for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				if mi.material_overlay == _flash_mat:
					mi.material_overlay = null
	var lift := lerpf(prev_lift, cur_lift, alpha)
	if _knock_t >= 0.0:
		_knock_t += delta
		var f := clampf(_knock_t / _knock_dur, 0.0, 1.0)
		p = _knock_from.lerp(_knock_to, f)
		lift = sin(f * PI) * _knock_h
		if f >= 1.0:
			cur_pos = _knock_to
			prev_pos = _knock_to
			_knock_t = -1.0
	# skeletons off screen do not need animating
	if anim and cam:
		var on := visible and cam.is_position_in_frustum(position + Vector3(0, 1.0, 0))
		if not on and position.distance_to(cam.global_position) > 6.0:
			on = cam.is_position_in_frustum(position) or cam.is_position_in_frustum(position + Vector3(0, 2.4, 0))
		if anim.active != on:
			anim.active = on
	var h := terrain.height_at(p)
	position = View.to3(p, h) + Vector3(0, lift, 0)
	rotation.y = View.yaw(lerp_angle(prev_facing, cur_facing, alpha))
	# hit flinch: snap away from the blow, spring back
	if pivot:
		if _flinch_t < 1.0:
			_flinch_t = minf(1.0, _flinch_t + delta / 0.3)
			var k := sin(minf(_flinch_t / 0.18, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.18, 1.0, _flinch_t))
			pivot.rotation = Vector3(_flinch.x * k, 0.0, _flinch.y * k)
		elif pivot.rotation != Vector3.ZERO:
			pivot.rotation = Vector3.ZERO
	if swing_trail:
		swing_trail.emitting = swing_lit or _now() < _swing_until or _state == "leap"
	if _glow_on and _glow_mat:
		var t := _now()
		_glow_mat.albedo_color.a = 0.55 + 0.25 * sin(t * 13.0) + 0.15 * sin(t * 31.0)
	if _dead_at >= 0.0 and model:
		var t := _now() - _dead_at
		if t > 2.5 and not is_hero:
			model.position.y = -(t - 2.5) * 0.7
	if _ring and _ring.visible:
		_ring.position.y = 0.04 - lift
	if cfg.has("float") and model:
		model.position.y = float(cfg.float) + sin(_now() / 0.4 + uid) * 0.15
