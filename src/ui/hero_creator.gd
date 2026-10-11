extends Control
## Main menu and Hero Creator: a lit 3D stage with your hero, and tabs to shape every part of it.
## Body, face, hair, colours and markings, the outfit piece in each of 10 slots with per-slot dyes, presets and
## randomisers. Play saves the hero (user://hero.json) and starts the match with it.

const U = preload("res://src/ui/ui_kit.gd")
const MATCH := "res://src/game/main.tscn"

const LABELS := {
	"female": "Feminine", "height": "Height", "head": "Head size", "hands": "Hand size", "feet": "Foot size",
	"muscle": "Muscle", "belly": "Belly", "build": "Build", "rear": "Hips and seat",
	"nose_size": "Nose size", "nose_long": "Nose length", "nose_wide": "Nose width", "nose_up": "Nose tip",
	"ears_size": "Ear size", "ears_point": "Pointed ears", "ears_out": "Ears outward", "lips_full": "Full lips",
	"mouth_wide": "Mouth width", "mouth_smile": "Smile", "jaw_wide": "Jaw width", "chin_long": "Chin length",
	"cheeks": "Cheeks", "brow_heavy": "Heavy brow", "eyes_pop": "Eye depth",
	"eye_size": "Eye size", "eye_spacing": "Eye spacing", "eye_height": "Eye height", "eye_tilt": "Eye tilt",
	"eye_glow": "Eye glow", "brow_thick": "Brow thickness", "brow_tilt": "Brow tilt", "brow_height": "Brow height",
	"hair_length": "Hair length", "beard_length": "Beard length", "stubble": "Stubble", "lip_amount": "Lip colour",
	"pattern_amount": "Pattern strength", "pattern_scale": "Pattern scale",
}
const BODY := ["female", "height", "muscle", "build", "belly", "rear", "head", "hands", "feet"]
const FACE := ["nose_size", "nose_long", "nose_wide", "nose_up", "ears_size", "ears_point", "ears_out", "lips_full",
	"mouth_wide", "mouth_smile", "jaw_wide", "chin_long", "cheeks", "brow_heavy", "eyes_pop", "eye_size", "eye_spacing",
	"eye_height", "eye_tilt", "eye_glow", "brow_thick", "brow_tilt", "brow_height"]
const SLOT_NAMES := {"inner_garment": "Shirt", "armor": "Armour / coat", "leggings": "Leggings", "helm": "Helm",
	"gloves": "Gloves", "boots": "Boots", "accessory_1": "Accessory 1", "accessory_2": "Accessory 2",
	"accessory_3": "Accessory 3", "accessory_4": "Accessory 4"}
const DYES := [["cloth", "Cloth"], ["trim", "Trim"], ["leather", "Leather"], ["metal", "Metal"], ["gold", "Gold"]]
const ANIMS := [["Idle", "idle_bow"], ["Walk", "walk"], ["Run", "run"], ["Shoot", "bow_1"], ["Cast", "cast_quick"],
	["Victory", "war_cry"], ["Taunt", "taunt"]]

var hero := {}
var vp: SubViewport
var stage: Node3D
var model: Node3D
var app: HeroAppearance
var anim: AnimationPlayer
var cam: Camera3D
var _yaw := 0.4
var _zoom_face := false
var _cam_t := 0.0
var _dragging := false
var _anim := "idle_bow"
var _controls := {}                       # look key -> control, refreshed by _sync_controls
var _name_edit: LineEdit
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	theme = U.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	hero = GameSettings.load_hero().duplicate(true)
	_rng.randomize()
	_build_stage()
	_build_ui()
	_rebuild_model()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_path = a.substr(10)
		elif a.begins_with("--preset="):
			hero.look = HeroLook.preset(a.substr(9))
			_after_change(true)
		elif a == "--face":
			_zoom_face = true
			_cam_t = 1.0
		elif a == "--random":
			_rng.seed = 11
			hero.look = HeroLook.random(_rng, 0.4)
			_random_outfit()
			_after_change(true)

var _capture_path := ""
var _frames := 0

func _physics_process(_dt: float) -> void:
	if _capture_path == "":
		return
	_frames += 1
	if _frames == 60:
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://" + _capture_path)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("captured ", path)
		get_tree().quit()

# ---- 3D stage ---------------------------------------------------------------------------------------------------------

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
	sm.sky_top_color = Color(0.05, 0.07, 0.12)
	sm.sky_horizon_color = Color(0.22, 0.18, 0.2)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sm.ground_horizon_color = Color(0.18, 0.15, 0.15)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.02
	env.fog_light_color = Color(0.12, 0.1, 0.12)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.92, 0.8)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.6, 2.4, -1.8)
	rim.light_color = Color(0.45, 0.65, 1.0)
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	stage.add_child(rim)
	var warm := OmniLight3D.new()
	warm.position = Vector3(1.8, 0.6, 1.4)
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 1.6
	warm.omni_range = 5.0
	stage.add_child(warm)
	# pedestal and floor
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 1.05
	cyl.height = 0.18
	cyl.radial_segments = 48
	ped.mesh = cyl
	ped.position.y = -0.09
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.28, 0.26, 0.24)
	pm.roughness = 0.6
	pm.metallic = 0.2
	ped.material_override = pm
	stage.add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.98
	tm.outer_radius = 1.02
	tm.rings = 64
	ring.mesh = tm
	ring.scale = Vector3(1, 0.3, 1)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.78, 0.4)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.72, 0.3)
	rmat.emission_energy_multiplier = 2.5
	ring.material_override = rmat
	stage.add_child(ring)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor.mesh = plane
	floor.position.y = -0.18
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.075, 0.08)
	fm.roughness = 0.9
	floor.material_override = fm
	stage.add_child(floor)
	cam = Camera3D.new()
	cam.fov = 32.0
	stage.add_child(cam)

func _rebuild_model() -> void:
	if model:
		model.queue_free()
	model = (load(HeroLook.MODEL) as PackedScene).instantiate()
	stage.add_child(model)
	model.rotation.y = _yaw
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	app = HeroAppearance.new(model)
	var sk := app.skeleton
	if sk and sk.find_bone("weapon.L") >= 0:
		var at := BoneAttachment3D.new()
		at.bone_name = "weapon.L"
		sk.add_child(at)
		at.add_child((load("res://assets/weapons/bow.glb") as PackedScene).instantiate())
	_apply()
	_play(_anim)

func _apply() -> void:
	if app == null:
		return
	app.apply(hero.look)
	app.dress(hero.outfit, hero.dyes)

func _play(clip: String) -> void:
	_anim = clip
	if anim == null:
		return
	if not anim.has_animation(clip):
		clip = "idle"
	var a := anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR
	anim.play(clip, 0.2)

func _process(dt: float) -> void:
	_cam_t = move_toward(_cam_t, 1.0 if _zoom_face else 0.0, dt * 2.5)
	var t := smoothstep(0.0, 1.0, _cam_t)
	var h := float(hero.look.get("height", 1.0))
	var focus := Vector3(0, lerpf(0.95, 1.62, t) * h, 0)
	var dist := lerpf(4.6, 1.15, t)
	# the stage is shown to the right of the panel: offset the camera to keep the hero in the open area
	cam.position = focus + Vector3(-0.9 * (1.0 - t) - 0.18 * t, 0.15, dist)
	cam.look_at(focus + Vector3(-0.9 * (1.0 - t) - 0.18 * t, 0, 0), Vector3.UP)
	if model and not _dragging:
		_yaw += dt * 0.15
	if model:
		model.rotation.y = _yaw

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_face = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_face = false
	elif e is InputEventMouseMotion and _dragging:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01

# ---- UI ---------------------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var title := Label.new()
	title.text = "Warriors of Aether"
	title.add_theme_font_override("font", U.font("title"))
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", U.GOLD)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	title.position = Vector2(34, 18)
	add_child(title)
	var sub := Label.new()
	sub.text = "Hero Creator"
	sub.add_theme_font_override("font", U.font("title"))
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", U.TEXT_DIM)
	sub.position = Vector2(38, 76)
	add_child(sub)

	var panel := PanelContainer.new()
	panel.position = Vector2(28, 112)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -96
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var name_row := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Name"
	nl.custom_minimum_size = Vector2(70, 0)
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = String(hero.display_name)
	_name_edit.max_length = 24
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t): hero.display_name = t)
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	tabs.add_child(_tab("Body", _body_tab()))
	tabs.add_child(_tab("Face", _face_tab()))
	tabs.add_child(_tab("Hair", _hair_tab()))
	tabs.add_child(_tab("Colours", _colour_tab()))
	tabs.add_child(_tab("Outfit", _outfit_tab()))
	tabs.add_child(_tab("Presets", _preset_tab()))

	# bottom bar: animation preview and actions
	var bar := HBoxContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.offset_top = -78
	bar.offset_bottom = -22
	bar.offset_left = 28
	bar.offset_right = -28
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	for a in ANIMS:
		var b := Button.new()
		b.text = a[0]
		b.custom_minimum_size = Vector2(84, 46)
		var clip: String = a[1]
		b.pressed.connect(func(): _play(clip))
		bar.add_child(b)
	var face := Button.new()
	face.text = "Face / body"
	face.custom_minimum_size = Vector2(120, 46)
	face.pressed.connect(func(): _zoom_face = not _zoom_face)
	bar.add_child(face)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(110, 46)
	reset.pressed.connect(func():
		hero = GameSettings.default_hero()
		_name_edit.text = hero.display_name
		_after_change(true))
	bar.add_child(reset)
	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(220, 52)
	play.add_theme_font_override("font", U.font("title"))
	play.add_theme_font_size_override("font_size", 26)
	play.pressed.connect(_on_play)
	bar.add_child(play)

func _tab(title: String, content: Control) -> Control:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc

func _vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	return v

func _header(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font("title"))
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", U.GOLD)
	v.add_child(l)

func _slider(v: VBoxContainer, key: String) -> void:
	var s: Array = HeroLook.SLIDERS[key]
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = LABELS.get(key, key)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = s[1]
	sl.max_value = s[2]
	sl.step = (float(s[2]) - float(s[1])) / 400.0
	sl.value = float(hero.look.get(key, s[0]))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 26)
	sl.value_changed.connect(func(val):
		hero.look[key] = val
		_after_change())
	row.add_child(sl)
	var rb := Button.new()
	rb.text = "↺"
	rb.tooltip_text = "Default"
	rb.custom_minimum_size = Vector2(32, 0)
	rb.pressed.connect(func(): sl.value = float(s[0]))
	row.add_child(rb)
	v.add_child(row)
	_controls[key] = sl

func _choice(v: VBoxContainer, key: String, label: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids := HeroLook.choice_ids(key)
	for i in ids.size():
		ob.add_item(HeroLook.choice_label(key, ids[i]), i)
	ob.selected = maxi(0, ids.find(String(hero.look.get(key, ids[0]))))
	ob.item_selected.connect(func(i):
		hero.look[key] = ids[i]
		_after_change())
	row.add_child(ob)
	v.add_child(row)
	_controls[key] = ob

func _colour(v: VBoxContainer, key: String, label: String, swatches: Array) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(56, 30)
	pick.edit_alpha = false
	pick.color = HeroLook.color(hero.look, key)
	pick.color_changed.connect(func(c):
		hero.look[key] = c.to_html(false)
		_after_change())
	row.add_child(pick)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for hex in swatches:
		var b := Button.new()
		b.custom_minimum_size = Vector2(24, 24)
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = Color(hex)
		sbx.set_corner_radius_all(4)
		sbx.border_color = Color(0, 0, 0, 0.6)
		sbx.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sbx)
		var hov := sbx.duplicate()
		hov.border_color = U.GOLD
		hov.set_border_width_all(2)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		var hx: String = hex
		b.pressed.connect(func():
			hero.look[key] = hx
			pick.color = Color(hx)
			_after_change())
		flow.add_child(b)
	row.add_child(flow)
	v.add_child(row)
	_controls[key] = pick

func _body_tab() -> Control:
	var v := _vbox()
	_header(v, "Figure")
	for k in BODY:
		_slider(v, k)
	return v

func _face_tab() -> Control:
	var v := _vbox()
	_header(v, "Eyes and brows")
	_choice(v, "eye", "Eye style")
	_choice(v, "brow", "Brow style")
	for k in ["eye_size", "eye_spacing", "eye_height", "eye_tilt", "eye_glow", "brow_thick", "brow_tilt", "brow_height"]:
		_slider(v, k)
	_header(v, "Shape")
	for k in FACE:
		if k.begins_with("eye_") or k.begins_with("brow_"):
			continue
		_slider(v, k)
	return v

func _hair_tab() -> Control:
	var v := _vbox()
	_header(v, "Hair")
	_choice(v, "hair", "Style")
	_slider(v, "hair_length")
	_colour(v, "hair_color", "Hair colour", HeroLook.HAIR_TONES)
	_header(v, "Beard")
	_choice(v, "beard", "Style")
	_slider(v, "beard_length")
	_slider(v, "stubble")
	_colour(v, "beard_color", "Beard colour", HeroLook.HAIR_TONES)
	_colour(v, "brow_color", "Brow colour", HeroLook.HAIR_TONES)
	return v

func _colour_tab() -> Control:
	var v := _vbox()
	_header(v, "Skin")
	_colour(v, "skin", "Skin tone", HeroLook.SKIN_TONES)
	_choice(v, "pattern", "Skin pattern")
	_colour(v, "pattern_color", "Pattern colour", HeroLook.HAIR_TONES + HeroLook.MARK_TONES)
	_slider(v, "pattern_amount")
	_slider(v, "pattern_scale")
	_header(v, "Face paint")
	_choice(v, "marking", "Marking")
	_colour(v, "marking_color", "Marking colour", HeroLook.MARK_TONES)
	_colour(v, "lip_color", "Lip colour", HeroLook.LIP_TONES)
	_slider(v, "lip_amount")
	_colour(v, "eye_color", "Eye colour", HeroLook.EYE_TONES)
	_colour(v, "underwear", "Underwear", HeroLook.CLOTH_TONES)
	return v

func _outfit_tab() -> Control:
	var v := _vbox()
	var helm := CheckBox.new()
	helm.text = "Show helm"
	helm.button_pressed = bool(hero.look.get("show_helm", true))
	helm.toggled.connect(func(on):
		hero.look["show_helm"] = on
		_after_change())
	v.add_child(helm)
	for slot in HeroAppearance.SLOTS:
		_header(v, SLOT_NAMES[slot])
		var ob := OptionButton.new()
		var ids := HeroAppearance.pieces_for(slot)
		ob.add_item("None", 0)
		for i in ids.size():
			ob.add_item(HeroAppearance.piece_name(ids[i]), i + 1)
		var cur := String((hero.outfit as Dictionary).get(slot, ""))
		ob.selected = ids.find(cur) + 1 if cur != "" else 0
		var s2: String = slot
		ob.item_selected.connect(func(i):
			if i == 0:
				hero.outfit.erase(s2)
			else:
				hero.outfit[s2] = ids[i - 1]
			_after_change())
		v.add_child(ob)
		var dyes := HBoxContainer.new()
		dyes.add_theme_constant_override("separation", 4)
		var dl := Label.new()
		dl.text = "Dye"
		dl.add_theme_color_override("font_color", U.TEXT_DIM)
		dyes.add_child(dl)
		for d in DYES:
			var pick := ColorPickerButton.new()
			pick.custom_minimum_size = Vector2(44, 26)
			pick.edit_alpha = false
			pick.tooltip_text = d[1]
			var cur_dye := String((hero.dyes.get(slot, {}) as Dictionary).get(d[0], ""))
			pick.color = Color(cur_dye) if cur_dye != "" else Color(0.5, 0.5, 0.5)
			var key: String = d[0]
			pick.color_changed.connect(func(c):
				if not hero.dyes.has(s2):
					hero.dyes[s2] = {}
				hero.dyes[s2][key] = c.to_html(false)
				_after_change())
			var lab := Label.new()
			lab.text = d[1]
			lab.add_theme_font_size_override("font_size", 12)
			lab.add_theme_color_override("font_color", U.TEXT_DIM)
			dyes.add_child(lab)
			dyes.add_child(pick)
		var clear := Button.new()
		clear.text = "Undye"
		clear.pressed.connect(func():
			hero.dyes.erase(s2)
			_after_change())
		dyes.add_child(clear)
		v.add_child(dyes)
	return v

func _preset_tab() -> Control:
	var v := _vbox()
	_header(v, "Starting points")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for p in HeroLook.PRESETS:
		var b := Button.new()
		b.text = p[1]
		b.custom_minimum_size = Vector2(160, 44)
		var pid: String = p[0]
		b.pressed.connect(func():
			hero.look = HeroLook.preset(pid)
			_after_change(true))
		grid.add_child(b)
	v.add_child(grid)
	_header(v, "Surprise me")
	var row := HBoxContainer.new()
	var r1 := Button.new()
	r1.text = "Random person"
	r1.custom_minimum_size = Vector2(0, 44)
	r1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.pressed.connect(func():
		hero.look = HeroLook.random(_rng, 0.15)
		_after_change(true))
	row.add_child(r1)
	var r2 := Button.new()
	r2.text = "Random anything"
	r2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.pressed.connect(func():
		hero.look = HeroLook.random(_rng, 0.95)
		_after_change(true))
	row.add_child(r2)
	v.add_child(row)
	var r3 := Button.new()
	r3.text = "Random outfit"
	r3.custom_minimum_size = Vector2(0, 44)
	r3.pressed.connect(func():
		_random_outfit()
		_after_change(true))
	v.add_child(r3)
	var r4 := Button.new()
	r4.text = "Random everything"
	r4.custom_minimum_size = Vector2(0, 44)
	r4.pressed.connect(func():
		hero.look = HeroLook.random(_rng, 0.4)
		_random_outfit()
		_after_change(true))
	v.add_child(r4)
	return v

func _random_outfit() -> void:
	var out := {}
	var dyes := {}
	for slot in HeroAppearance.SLOTS:
		var ids := HeroAppearance.pieces_for(slot)
		var chance: float = {"inner_garment": 0.6, "armor": 0.9, "leggings": 0.9, "helm": 0.35, "gloves": 0.7, "boots": 0.9}.get(slot, 0.3)
		if not ids.is_empty() and _rng.randf() < chance:
			out[slot] = ids[_rng.randi_range(0, ids.size() - 1)]
			if _rng.randf() < 0.5:
				dyes[slot] = {"cloth": HeroLook.CLOTH_TONES[_rng.randi_range(0, HeroLook.CLOTH_TONES.size() - 1)],
					"leather": ["3a2414", "5a3a20", "1e1410", "6b4423"][_rng.randi_range(0, 3)]}
	hero.outfit = out
	hero.dyes = dyes

func _after_change(rebuild_controls := false) -> void:
	_apply()
	if rebuild_controls:
		_sync_controls()

## Push the hero's values back into every control (after a preset or randomiser).
func _sync_controls() -> void:
	for key in _controls:
		var c = _controls[key]
		if c is HSlider:
			c.set_value_no_signal(float(hero.look.get(key, HeroLook.SLIDERS[key][0])))
		elif c is OptionButton:
			c.selected = maxi(0, HeroLook.choice_ids(key).find(String(hero.look.get(key, ""))))
		elif c is ColorPickerButton:
			c.color = HeroLook.color(hero.look, key)

func _on_play() -> void:
	GameSettings.hero = hero.duplicate(true)
	GameSettings.save_hero()
	get_tree().change_scene_to_file(MATCH)
