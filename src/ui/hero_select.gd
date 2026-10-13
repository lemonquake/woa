extends Control
## Main menu: Hero Select. A lit stage shows the chosen hero on a pedestal (drag to turn it); the left column lists the
## heroes, the right panel their role, story, starting stats and abilities (hover an ability for its numbers). Pick
## open the Hero Creator to change your hero's look, or Play (Game Setup: the teams, the bots and their heroes).

const U = preload("res://src/ui/ui_kit.gd")
const MATCH := "res://src/game/main.tscn"
const CREATOR := "res://src/ui/hero_creator.tscn"
const HOTKEYS := "res://src/ui/hotkeys_screen.tscn"
const SETUP := "res://src/ui/game_setup.tscn"

const INFO := {
	"blood_ranger": {"title": "the Archer", "role": "Ranged  ·  Agility  ·  Carry, Nuker, Escape",
		"accent": Color(0.95, 0.22, 0.25), "flourish": "bow_1", "idle": "idle_bow",
		"story": "She hunted the Black Sun's beasts until the hunt hunted her back. Now the blood she spills keeps her standing, and every arrow she looses is a promise kept."},
	"ezee": {"title": "the Dark Paladin", "role": "Melee  ·  Strength  ·  Initiator, Disabler, Durable",
		"accent": Color(0.66, 0.3, 1.0), "flourish": "boss_roar", "idle": "idle_2h",
		"story": "Once a knight of the Ancient Light, Ezee broke his word to win a war the light was losing. The shadow he bargained with still answers when he calls, and it is always hungry."},
	"sludge": {"title": "the Butcher", "role": "Melee  ·  Strength  ·  Disabler, Initiator, Durable, Nuker",
		"accent": Color(0.55, 0.78, 0.3), "flourish": "hero_axe_smash", "idle": "idle_1h",
		"story": "Sludge works the fields after every battle, hauling the fallen away on his chain. Nothing he catches gets away, and everything he eats makes him bigger."},
}

var vp: SubViewport
var stage: Node3D
var model: Node3D
var anim: AnimationPlayer
var cam: Camera3D
var rim: SpotLight3D
var ring_mat: StandardMaterial3D
var backdrop_mat: ShaderMaterial
var _yaw := 0.35
var _drag := false
var _cards := {}
var _right: VBoxContainer
var _tip: PanelContainer
var _tip_label: RichTextLabel
var _opp: OptionButton
var _cust: Button
var _t := 0.0
var _capture_path := ""
var _frames := 0

func _ready() -> void:
	theme = U.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	_build_stage()
	_build_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture=") and not OS.get_cmdline_user_args().has("--match") and not OS.get_cmdline_args().has("--match"):
			_capture_path = a.substr(10)
		elif a.begins_with("--pick="):
			GameSettings.select(a.substr(7))
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a == "--match":
			# exported builds cannot take a scene path: this jumps straight into a match (automation, smoke tests)
			get_tree().change_scene_to_file.call_deferred(MATCH)
			return
	_select(GameSettings.selected, false)
	# the title card from the splash stays up until the stage has drawn once
	await get_tree().process_frame
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

# ---- Stage ----------------------------------------------------------------------------------------------------------

func _build_stage() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	svc.add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.03, 0.035, 0.06)
	sm.sky_horizon_color = Color(0.14, 0.11, 0.16)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sm.ground_horizon_color = Color(0.12, 0.1, 0.12)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.03
	env.fog_light_color = Color(0.1, 0.08, 0.12)
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, -24, 0)
	key.light_energy = 2.1
	key.light_color = Color(1.0, 0.92, 0.82)
	key.shadow_enabled = true
	stage.add_child(key)
	rim = SpotLight3D.new()
	rim.position = Vector3(-1.2, 3.6, -2.6)
	rim.light_energy = 9.0
	rim.spot_range = 9.0
	rim.spot_angle = 32.0
	stage.add_child(rim)
	rim.look_at(Vector3(0, 1.0, 0))
	# a white rim from behind and above outlines the silhouette against the backdrop
	var rim2 := SpotLight3D.new()
	rim2.position = Vector3(1.6, 3.4, -2.4)
	rim2.light_energy = 7.0
	rim2.spot_range = 9.0
	rim2.spot_angle = 30.0
	rim2.light_color = Color(0.95, 0.95, 1.0)
	stage.add_child(rim2)
	rim2.look_at(Vector3(0, 1.2, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.2, 1.6, 2.4)
	fill.light_energy = 1.1
	fill.omni_range = 7.0
	fill.light_color = Color(0.7, 0.75, 1.0)
	stage.add_child(fill)
	# pedestal: a worn stone drum with a glowing rune ring
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.2
	cyl.height = 0.32
	cyl.radial_segments = 48
	ped.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.22, 0.21, 0.22)
	pm.roughness = 0.85
	ped.material_override = pm
	ped.position.y = -0.16
	stage.add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 0.98
	tm.rings = 64
	ring.mesh = tm
	ring.scale = Vector3(1, 0.15, 1)
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.emission_enabled = true
	ring_mat.emission_energy_multiplier = 3.0
	ring.material_override = ring_mat
	ring.position.y = 0.005
	stage.add_child(ring)
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(40, 40)
	floor_mi.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.06, 0.07)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	floor_mi.position.y = -0.32
	stage.add_child(floor_mi)
	# backdrop: a softly lit, accent-tinted glow behind the hero, dark at the edges
	var bd := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(16, 9)
	bd.mesh = bq
	var bsh := Shader.new()
	bsh.code = "shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 accent : source_color = vec4(0.6, 0.3, 1.0, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.55)) * vec2(1.6, 1.0);
	float g = exp(-dot(p, p) * 9.0);
	ALBEDO = mix(vec3(0.015, 0.015, 0.022), accent.rgb * 0.2 + vec3(0.035), g);
}
"
	backdrop_mat = ShaderMaterial.new()
	backdrop_mat.shader = bsh
	bd.material_override = backdrop_mat
	bd.position = Vector3(0, 2.2, -4.5)
	stage.add_child(bd)
	cam = Camera3D.new()
	cam.fov = 30.0
	stage.add_child(cam)
	cam.position = Vector3(0.0, 1.45, 5.6)
	cam.look_at(Vector3(0.0, 1.05, 0))

func _spawn_model(id: String) -> void:
	if model:
		model.queue_free()
	var cfg := ModelCatalog.info(String(SimData.unit(id).model))
	var own := id in GameSettings.OWN_BODY
	model = (load(String(cfg.scene) if own else HeroLook.MODEL) as PackedScene).instantiate()
	stage.add_child(model)
	model.rotation.y = _yaw
	model.position.x = 0.0
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	var sk: Skeleton3D = null
	if own:
		# a hero with its own body (Sludge): its skin shader and textured gear, scaled down to fit the stage
		model.scale = Vector3.ONE * 0.92
		var sks := model.find_children("*", "Skeleton3D", true, false)
		sk = sks[0] if not sks.is_empty() else null
		UnitView.dress_own_body(model, cfg)
	else:
		var app := HeroAppearance.new(model)
		var look: Dictionary = GameSettings.look_for(id).duplicate(true)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--armor="):
				look.outfit["armor"] = a.substr(8)
		app.apply(look.look)
		app.dress(look.outfit, look.dyes)
		sk = app.skeleton
	for side in ["R", "L"]:
		var ps := ModelCatalog.weapon(String(cfg.get(side, "")))
		if sk and ps and sk.find_bone("weapon." + side) >= 0:
			var at := BoneAttachment3D.new()
			at.bone_name = "weapon." + side
			sk.add_child(at)
			var wpn := ps.instantiate() as Node3D
			at.add_child(wpn)
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
	var info: Dictionary = INFO[id]
	if anim:
		_play(String(info.flourish), false)
		anim.queue(String(info.idle))
		var ia := anim.get_animation(String(info.idle))
		if ia:
			ia.loop_mode = Animation.LOOP_LINEAR

func _play(clip: String, loop: bool) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	var a := anim.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.play(clip, 0.2)

# ---- UI ---------------------------------------------------------------------------------------------------------------

func _label(text: String, size: int, col: Color, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6 if size >= 24 else 3)
	return l

func _build_ui() -> void:
	var title := _label("Warriors of Aether", 46, U.GOLD, "title")
	title.position = Vector2(40, 24)
	add_child(title)
	var sub := _label("Choose your hero", 22, U.TEXT_DIM, "title")
	sub.position = Vector2(44, 84)
	add_child(sub)
	var col := VBoxContainer.new()
	col.position = Vector2(40, 150)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	for id in GameSettings.HEROES:
		var card := _card(id)
		col.add_child(card)
		_cards[id] = card
	var hint := _label("Drag the hero to turn it", 15, U.TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.offset_left = -90
	hint.offset_top = 40
	add_child(hint)
	# right panel
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -600
	panel.offset_right = -36
	panel.offset_top = 36
	panel.offset_bottom = -120
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 10)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right)
	# bottom bar
	var bar := HBoxContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 40
	bar.offset_right = -36
	bar.offset_top = -92
	bar.offset_bottom = -30
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var opts := Button.new()
	opts.text = "Options"
	opts.custom_minimum_size = Vector2(160, 54)
	opts.add_theme_font_size_override("font_size", 20)
	opts.pressed.connect(func():
		Options.click()
		add_child(OptionsPanel.new()))
	bar.add_child(opts)
	var cust := Button.new()
	cust.text = "Customize look"
	cust.custom_minimum_size = Vector2(200, 54)
	cust.add_theme_font_size_override("font_size", 20)
	cust.pressed.connect(func():
		Options.click()
		GameSettings.save()
		get_tree().change_scene_to_file(CREATOR))
	bar.add_child(cust)
	_cust = cust
	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(260, 58)
	play.add_theme_font_override("font", U.font("title"))
	play.add_theme_font_size_override("font_size", 30)
	play.pressed.connect(func():
		Options.click()
		_on_play())
	bar.add_child(play)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(380, 0)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.custom_minimum_size = Vector2(380, 0)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_font_override("normal_font", U.font("body"))
	_tip_label.add_theme_font_override("bold_font", U.font("bold"))
	_tip_label.add_theme_font_size_override("normal_font_size", 15)
	_tip_label.add_theme_font_size_override("bold_font_size", 17)
	_tip.add_child(_tip_label)
	add_child(_tip)

func _card(id: String) -> Button:
	var d := SimData.unit(id)
	var info: Dictionary = INFO[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(380, 112)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _select(id, true))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	b.add_child(row)
	var attr := TextureRect.new()
	var ap := {"str": "attributes/strength", "agi": "attributes/agility", "int": "attributes/intelligence"}
	attr.texture = U.icon(String(ap.get(String(d.primary), "attributes/strength")))
	attr.custom_minimum_size = Vector2(54, 54)
	attr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	attr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	attr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	attr.modulate = info.accent
	attr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(attr)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var n := _label(String(d.name), 30, U.GOLD, "title")
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var t := _label(String(info.title), 17, info.accent, "bold")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	return b

func _select(id: String, flourish: bool) -> void:
	GameSettings.select(id)
	GameSettings.save()
	for k in _cards:
		(_cards[k] as Button).button_pressed = k == id
	var info: Dictionary = INFO[id]
	rim.light_color = info.accent
	backdrop_mat.set_shader_parameter("accent", info.accent)
	ring_mat.albedo_color = info.accent
	ring_mat.emission = info.accent
	_spawn_model(id)
	_fill_right(id)
	if _cust:
		_cust.disabled = id in GameSettings.OWN_BODY
		_cust.tooltip_text = "%s has his own body and cannot be customized" % String(SimData.unit(id).name) if _cust.disabled else ""

func _fill_right(id: String) -> void:
	for c in _right.get_children():
		c.queue_free()
	var d := SimData.unit(id)
	var info: Dictionary = INFO[id]
	_right.add_child(_label(String(d.name), 44, U.GOLD, "title"))
	_right.add_child(_label(String(info.title), 22, info.accent, "title"))
	_right.add_child(_label(String(info.role), 16, U.TEXT, "bold"))
	var story := Label.new()
	story.text = String(info.story)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(520, 0)
	story.add_theme_font_size_override("font_size", 16)
	story.add_theme_color_override("font_color", U.TEXT_DIM)
	_right.add_child(story)
	_right.add_child(HSeparator.new())
	# starting stats (level 1)
	var str0 := float(d.str)
	var agi0 := float(d.agi)
	var int0 := float(d["int"])
	var prim: float = {"str": str0, "agi": agi0, "int": int0}[String(d.primary)]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	var stats := [
		["Strength", "%d  +%.1f" % [int(str0), float(d.str_gain)], Color(0.95, 0.4, 0.35)],
		["Health", str(int(float(d.hp) + str0 * SimConst.STR_HP)), U.TEXT],
		["Agility", "%d  +%.1f" % [int(agi0), float(d.agi_gain)], Color(0.45, 0.95, 0.5)],
		["Mana", str(int(float(d.mana) + int0 * SimConst.INT_MANA)), U.TEXT],
		["Intelligence", "%d  +%.1f" % [int(int0), float(d.int_gain)], Color(0.45, 0.7, 1.0)],
		["Damage", "%d - %d" % [int(float(d.dmg_min) + prim), int(float(d.dmg_max) + prim)], U.TEXT],
		["Armor", "%.1f" % (float(d.armor) + agi0 * SimConst.AGI_ARMOR), U.TEXT],
		["Attack range", str(int(d.range)) + ("  (melee)" if float(d.projectile_speed) <= 0.0 else ""), U.TEXT],
		["Move speed", str(int(d.move_speed)), U.TEXT],
		["Attack time", "%.1f s" % float(d.bat), U.TEXT],
	]
	for s in stats:
		grid.add_child(_label(String(s[0]), 15, U.TEXT_DIM, "bold"))
		grid.add_child(_label(String(s[1]), 16, s[2], "bold"))
	_right.add_child(grid)
	_right.add_child(HSeparator.new())
	_right.add_child(_label("Abilities", 22, U.GOLD, "title"))
	for aid in d.abilities:
		_right.add_child(_ability_row(String(aid)))

func _ability_row(aid: String) -> Control:
	var a := SimData.ability(aid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var ic := TextureRect.new()
	ic.texture = U.ability_icon(aid)
	ic.custom_minimum_size = Vector2(60, 60)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var kind := {"autocast_attack": "Attack modifier", "point": "Point target", "passive": "Passive", "unit": "Unit target",
		"no_target": "No target"}
	var head := _label("%s   [%s]   %s%s" % [String(a.name), String(a.key), String(kind.get(String(a.behavior), "")),
		"   Ultimate" if a.has("required_level") else ""], 17, U.GOLD, "bold")
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var desc := Label.new()
	desc.text = String(a.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(440, 0)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", U.TEXT)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)
	row.mouse_entered.connect(func(): _show_tip(aid))
	row.mouse_exited.connect(func(): _tip.visible = false)
	return row

func _show_tip(aid: String) -> void:
	var a := SimData.ability(aid)
	var lines := ["[b]%s[/b]" % String(a.name)]
	for k in a.values:
		var parts := []
		for val in a.values[k]:
			var fv := float(val)
			parts.append(("%d%%" % roundi(fv * 100.0)) if fv > 0.0 and fv < 1.0 and (String(k).contains("slow") or String(k).contains("chance") or String(k).contains("mult") or String(k).ends_with("pct") or String(k) == "lifesteal") else str(val))
		lines.append("%s: [color=#e8d9a8]%s[/color]" % [String(k).replace("_", " ").capitalize(), " / ".join(parts)])
	if String(a.behavior) != "passive":
		lines.append("[color=#8fb0ff]Mana %s   Cooldown %s s[/color]" % [" / ".join(a.mana.map(func(x): return str(x))),
			" / ".join(a.cooldown.map(func(x): return str(x)))])
	var dt := String(a.get("damage_type", ""))
	if dt != "":
		lines.append("Damage type: " + dt.capitalize())
	_tip_label.text = "\n".join(lines)
	_tip.visible = true

func _process(dt: float) -> void:
	_t += dt
	if not _drag:
		_yaw += dt * 0.12
	if model:
		model.rotation.y = _yaw
	if _tip.visible:
		_tip.position = get_viewport().get_mouse_position() + Vector2(-400, 18)
	if _capture_path != "":
		_frames += 1
		if _frames == 3:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--options"):
					var op := OptionsPanel.new()
					add_child(op)
					var tab := a.get_slice("=", 1)
					if tab != "" and tab != "--options":
						(func(): op.get_child(1).get_child(0).get_child(0).get_child(1).current_tab = int(tab)).call_deferred()
		if _frames == int(OS.get_environment("WOA_FRAMES") if OS.get_environment("WOA_FRAMES") != "" else "70"):
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture_path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01

## Play: Game Setup comes next (who plays on each team), then the Hotkeys screen ("Are you good to go?") and the match.
func _on_play() -> void:
	GameSettings.save()
	get_tree().change_scene_to_file(SETUP)
