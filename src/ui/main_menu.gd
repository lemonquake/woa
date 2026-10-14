extends Control
## The Main Menu: your hero on the lit stage, the game's title, and Play (Hero Select, then Game Setup), Multiplayer
## (games on the network), Hero Creator, Options and Quit. Drag the hero to turn it.

const U = preload("res://src/ui/ui_kit.gd")
const HERO_SELECT := "res://src/ui/hero_select.tscn"
const CREATOR := "res://src/ui/hero_creator.tscn"
const NET_MENU := "res://src/ui/net_menu.tscn"
const MATCH := "res://src/game/main.tscn"

var stage: HeroStage
var _plate: Control
var _capture_path := ""
var _frames := 0
var _t := 0.0
var _buttons: Array = []

func _ready() -> void:
	theme = U.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_path = a.substr(10)
		elif a == "--match":
			get_tree().change_scene_to_file.call_deferred(MATCH)
			return
	_build_stage()
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

func _build_stage() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	svc.add_child(vp)
	stage = HeroStage.new()
	stage.mode = "menu"
	stage.spin = 0.08
	stage.yaw = -0.25
	vp.add_child(stage)
	stage.show_hero.call_deferred(GameSettings.selected, {}, true)

func _build_ui() -> void:
	# a dark veil from the left edge so the title and buttons stand clear of the stage
	var veil := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.75])
	g.colors = PackedColorArray([Color(0.01, 0.012, 0.02, 0.92), Color(0.01, 0.012, 0.02, 0.55), Color(0, 0, 0, 0)])
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	veil.texture = gt
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var shade := TextureRect.new()
	var gt2 := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g2.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.75)])
	gt2.gradient = g2
	gt2.fill_from = Vector2(0, 0)
	gt2.fill_to = Vector2(0, 1)
	gt2.width = 4
	gt2.height = 256
	shade.texture = gt2
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var logo := TextureRect.new()
	logo.texture = U.skin_tex("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var ls := U.art_size("logo")
	logo.size = ls * 1.05
	logo.position = Vector2(70, 46)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var col := VBoxContainer.new()
	col.position = Vector2(118, 430)
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	_menu_button(col, "Play", "GoldButton", _on_play, 78)
	_menu_button(col, "Multiplayer", "", func(): _go(NET_MENU), 64)
	_menu_button(col, "Hero Creator", "", _on_creator, 64)
	_menu_button(col, "Options", "", func():
		var op := OptionsPanel.new()
		add_child(op), 64)
	_menu_button(col, "Quit", "DarkButton", func(): get_tree().quit(), 56)
	# the hero on the stage: name and title on a plaque, with a way to choose another
	_plate = Control.new()
	_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_plate.position = Vector2(-560, -190)
	_plate.size = Vector2(500, 150)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.draw.connect(_draw_plate)
	add_child(_plate)
	var change := Button.new()
	change.text = "Choose hero"
	change.custom_minimum_size = Vector2(220, 52)
	change.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	change.position = Vector2(-290, -96)
	change.pressed.connect(func():
		Options.click()
		_go(HERO_SELECT))
	add_child(change)

func _menu_button(parent: Control, text: String, variation: String, cb: Callable, h: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, h)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	if variation == "":
		b.add_theme_font_override("font", U.font("title"))
		b.add_theme_font_size_override("font_size", 24)
	elif variation == "GoldButton":
		b.add_theme_font_size_override("font_size", 32)
	b.pressed.connect(func():
		Options.click()
		cb.call())
	parent.add_child(b)
	_buttons.append(b)
	return b

func _draw_plate() -> void:
	var id := GameSettings.selected
	var d := SimData.unit(id)
	var r := Rect2(Vector2.ZERO, _plate.size)
	var col: Color = HeroStage.ACCENTS.get(id, U.GOLD)
	U.art_rect(_plate, "glow_gold", Rect2(r.size.x - 360, -20, 360, 120), Color(col, 0.18))
	var name := String(d.get("name", id)).to_upper()
	var f := U.font("title")
	var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	U.text(_plate, name, Vector2(r.size.x - tw - 20, 44), 44, U.GOLD, "title")
	var title := String(d.get("title", ""))
	var t2 := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	U.text(_plate, title, Vector2(r.size.x - t2 - 22, 74), 20, col.lightened(0.15), "title")

func _go(path: String) -> void:
	GameSettings.save()
	get_tree().change_scene_to_file(path)

func _on_play() -> void:
	_go(HERO_SELECT)

func _on_creator() -> void:
	if GameSettings.selected in GameSettings.OWN_BODY:
		GameSettings.select("blood_ranger")
	_go(CREATOR)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		stage.dragging = e.pressed
	elif e is InputEventMouseMotion and stage.dragging:
		stage.drag((e as InputEventMouseMotion).relative.x)

func _process(dt: float) -> void:
	_t += dt
	if _capture_path != "":
		_frames += 1
		if _frames == int(OS.get_environment("WOA_FRAMES") if OS.get_environment("WOA_FRAMES") != "" else "70"):
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture_path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()
