extends Control
## The Main Menu (remade in run 2026-10-15 g): your hero on the lit stage, and on the left a hanging banner with the
## title and the menu as blade-shaped plates: Ranked (the main mode and the first, gold plate since 2026-10-20 b, the
## owner: "Remove the PLAY button at the main menu because RANKED will always be the PLAY button now"), Forums,
## Multiplayer, Hero Creator, Options, Credits, Quit. A nameplate shows the hero on the stage, with Choose Hero. Along
## the bottom: the credit and a tip.
## Drag the hero to turn it. Up / Down and Enter work the menu too.
##
## The first time the menu opens after the game starts, the animated title (TitleCard) plays over it; when it is
## dismissed the banner drops in, the plates slide in one after another and the nameplate fades up.
## Automation: `--capture=path` saves a frame (no title); `--title` with it shows the title, `--title-at=s` seeks it;
## `--4k` opens a 3840 x 2160 window; `--focus=n` puts plate n in focus (its hover look).

const U = preload("res://src/ui/ui_kit.gd")
const HERO_SELECT := "res://src/ui/hero_select.tscn"
const CREATOR := "res://src/ui/hero_creator.tscn"
const NET_MENU := "res://src/ui/net_menu.tscn"
const RANKED := "res://src/ui/ranked_menu.tscn"
const FORUMS := "res://src/ui/forums.tscn"
const MATCH := "res://src/game/main.tscn"

const BANNER_X := 64.0
const PLATE_W := 372.0
const TIPS := [
	"Hold Alt in a match to see tower ranges and camp spawn boxes.",
	"Kragg's attacks put Charges on enemies: each one makes his spells hit harder.",
	"Blau's Bounce Shot ricochets off trees and boulders: shoot it into a forest to hit an enemy twice.",
	"Roydo's Grip of the Ruler always picks an enemy hero first if one stands in the area.",
	"Boulders block every unit for 10 seconds, even phased ones: wall an enemy in, then shoot.",
	"Bots buy Spell Cloaks and Spell Shields when your team's spells keep killing them.",
	"Running through trees breaks the chaser's sight. Then a Teleport Scroll takes you home.",
	"Random picks keep each team varied: no hero twice on one side.",
	"Fade Cape hides an ally for 5 seconds and blocks 375 magic damage.",
	"Press F9 in a match for the Debug panel.",
	"Hold S for a hard stop: no auto-attacks until your next order.",
]

static var title_shown := false            # the title plays once per run of the game

var stage: HeroStage
var _banner: Control
var _logo: TextureRect
var _plates: Array = []                    # MenuPlate, top to bottom
var _plate_box: Control
var _name_box: Control
var _change: MenuPlate
var _footer: Control
var _title: TitleCard
var _capture_path := ""
var _capture_title := false
var _title_at := -1.0
var _frames := 0
var _t := 0.0
var _intro := -1.0                         # seconds since the menu started coming in (-1: waiting for the title)
var _focus := 0
var _tip_i := 0
var _tip_t := 0.0
var _capture_focus := false

func _ready() -> void:
	theme = U.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_path = a.substr(10)
		elif a == "--title":
			_capture_title = true
		elif a.begins_with("--title-at="):
			_title_at = float(a.substr(11))
		elif a.begins_with("--focus="):
			_focus = int(a.substr(8))
			_capture_focus = true
		elif a == "--4k":
			# a real 3840 x 2160 window (UI checks at 4K)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(3840, 2160))
		elif a == "--match":
			get_tree().change_scene_to_file.call_deferred(MATCH)
			return
	_tip_i = randi() % TIPS.size()
	_build_stage()
	_build_ui()
	var want_title := not title_shown and (_capture_path == "" or _capture_title)
	if want_title:
		title_shown = true
		_title = TitleCard.new()
		add_child(_title)
		_title.finished.connect(func(): _intro = 0.0)
		if _title_at >= 0.0:
			_title.seek(_title_at)
	else:
		_intro = 0.0 if _capture_path == "" else 10.0
	if _capture_focus and _focus < _plates.size():
		(_plates[_focus] as MenuPlate).focused = true
	_place(0.0)
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

func _gradient(offsets: Array, colors: Array, vertical: bool) -> TextureRect:
	var tr := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	gt.gradient = g
	if vertical:
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 256
	else:
		gt.width = 256
		gt.height = 4
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr

func _build_ui() -> void:
	# shade from the left (behind the banner) and from the bottom, so the menu and the footer stand clear
	_gradient([0.0, 0.3, 0.6], [Color(0.0, 0.005, 0.015, 0.85), Color(0.0, 0.005, 0.015, 0.4), Color(0, 0, 0, 0)], false)
	_gradient([0.0, 0.72, 1.0], [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.8)], true)
	# the banner with the title at its head
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.size = U.art_size("menu_banner")
	add_child(_banner)
	var cloth := TextureRect.new()
	cloth.texture = U.skin_tex("menu_banner")
	cloth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloth.size = _banner.size
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(cloth)
	_logo = TextureRect.new()
	_logo.texture = U.skin_tex("logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ls := U.art_size("logo")
	var k := (_banner.size.x - 40.0) / ls.x
	_logo.size = ls * k
	_logo.position = Vector2((_banner.size.x - _logo.size.x) * 0.5, 56)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_logo)
	# the menu plates
	_plate_box = Control.new()
	_plate_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate_box)
	var y := 0.0
	for e in [["Ranked", "ui/crown", true, func(): _go(RANKED), 70.0],
			["Forums", "ui/quest", false, func(): _go(FORUMS), 54.0],
			["Multiplayer", "ui/talk", false, func(): _go(NET_MENU), 54.0],
			["Hero Creator", "ui/repair", false, _on_creator, 54.0],
			["Options", "ui/settings", false, func(): add_child(OptionsPanel.new()), 54.0],
			["Credits", "ui/info", false, func(): add_child(CreditsPanel.new()), 50.0],
			["Quit", "ui/close", false, func(): get_tree().quit(), 50.0]]:
		var p := MenuPlate.new()
		p.text = String(e[0])
		p.icon_path = String(e[1])
		p.gold = bool(e[2])
		p.action = e[3]
		p.size = Vector2(PLATE_W, float(e[4]))
		p.base_y = y
		p.font_size = 30 if p.gold else 22
		p.hovered.connect(_on_plate_hover.bind(_plates.size()))
		_plate_box.add_child(p)
		_plates.append(p)
		y += float(e[4]) + 10.0
	_plate_box.size = Vector2(PLATE_W + 40.0, y)
	# the hero on the stage: a framed nameplate with its name and title, and Choose Hero under it
	_name_box = Control.new()
	_name_box.size = Vector2(520, 132)
	_name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_box.draw.connect(_draw_nameplate)
	add_child(_name_box)
	_change = MenuPlate.new()
	_change.text = "Choose Hero"
	_change.icon_path = "ui/compare"
	_change.size = Vector2(300, 56)
	_change.font_size = 21
	_change.action = func(): _go(HERO_SELECT)
	add_child(_change)
	# the footer: the credit on the left, a tip on the right
	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	add_child(_footer)
	resized.connect(func(): _place(0.0))

## Where everything sits for this window size, eased in by `_intro` (the menu's entrance).
func _place(_dt: float) -> void:
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var it := _intro if _intro >= 0.0 else -1.0
	# the banner drops from above with a little bounce
	var kb := _back_out(clampf(it / 0.7, 0.0, 1.0)) if it >= 0.0 else 0.0
	_banner.position = Vector2(BANNER_X, lerpf(-_banner.size.y - 20.0, -14.0, kb))
	# the plates slide in from the left, one after another
	var top := clampf(vs.y * 0.205, 210.0, 270.0)
	_plate_box.position = Vector2(BANNER_X + (_banner.size.x - PLATE_W) * 0.5 - 6.0, top)
	for i in _plates.size():
		var p: MenuPlate = _plates[i]
		var kp := _ease(clampf((it - 0.35 - i * 0.08) / 0.45, 0.0, 1.0)) if it >= 0.0 else 0.0
		p.enter = kp
		p.position = Vector2(lerpf(-PLATE_W - 120.0, 0.0, kp) + p.slide, p.base_y)
	var kn := _ease(clampf((it - 0.6) / 0.6, 0.0, 1.0)) if it >= 0.0 else 0.0
	_name_box.position = Vector2(vs.x - _name_box.size.x - 56.0, vs.y - 280.0 + (1.0 - kn) * 30.0)
	_name_box.modulate.a = kn
	_change.position = Vector2(vs.x - _change.size.x - 96.0 + _change.slide, _name_box.position.y + _name_box.size.y + 14.0)
	_change.enter = kn
	_change.modulate.a = kn
	var kf := _ease(clampf((it - 0.2) / 0.5, 0.0, 1.0)) if it >= 0.0 else 0.0
	_footer.size = Vector2(vs.x, 46)
	_footer.position = Vector2(0, vs.y - 46.0 * kf)
	_footer.modulate.a = kf

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func _back_out(x: float) -> float:
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

func _draw_nameplate() -> void:
	var id := GameSettings.selected
	var d := SimData.unit(id)
	var r := Rect2(Vector2.ZERO, _name_box.size)
	var col: Color = HeroStage.ACCENTS.get(id, U.GOLD)
	U.art_rect(_name_box, "glow_gold", Rect2(-60, -50, r.size.x + 120, r.size.y + 100), Color(col, 0.16))
	U.skin(_name_box, "menu_nameplate", r)
	var name := String(d.get("name", id)).to_upper()
	U.text_c(_name_box, name, Vector2(r.size.x * 0.5, 66), 46, U.GOLD, "title")
	var title := String(d.get("title", ""))
	U.text_c(_name_box, title, Vector2(r.size.x * 0.5, 100), 21, col.lightened(0.2), "title")

func _draw_footer() -> void:
	var r := Rect2(Vector2.ZERO, _footer.size)
	U.skin(_footer, "menu_footer", r)
	U.text(_footer, "by Aljay Leodones", Vector2(28, 31), 18, Color(0.95, 0.82, 0.55), "title")
	var tip := "Tip: " + String(TIPS[_tip_i])
	var a := clampf(minf(_tip_t, 9.0 - _tip_t) / 0.6, 0.0, 1.0)
	var f := U.font("body")
	var tw := f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	U.text(_footer, tip, Vector2(r.size.x - tw - 28.0, 30), 16, Color(0.86, 0.86, 0.84, a), "body")

func _on_plate_hover(i: int) -> void:
	_focus = i

func _go(path: String) -> void:
	GameSettings.save()
	Options.go(get_tree(), path)

func _on_creator() -> void:
	if GameSettings.selected in GameSettings.OWN_BODY:
		GameSettings.select("blood_ranger")
	_go(CREATOR)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		stage.dragging = e.pressed
	elif e is InputEventMouseMotion and stage.dragging:
		stage.drag((e as InputEventMouseMotion).relative.x)

## Up / Down move between the plates, Enter or Space uses the one in focus.
func _unhandled_key_input(e: InputEvent) -> void:
	if _title != null and is_instance_valid(_title) or _intro < 0.5 or not (e is InputEventKey) or not e.pressed:
		return
	# Options or Credits is open over the menu: the keys are theirs
	for c in get_children():
		if c is OptionsPanel or c is CreditsPanel:
			return
	var k := (e as InputEventKey).keycode
	if k == KEY_DOWN or k == KEY_UP:
		_focus = posmod(_focus + (1 if k == KEY_DOWN else -1), _plates.size())
		for i in _plates.size():
			(_plates[i] as MenuPlate).focused = i == _focus
		Options.click()
		get_viewport().set_input_as_handled()
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		(_plates[_focus] as MenuPlate).press()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_t += dt
	if _intro >= 0.0:
		_intro += dt
	_tip_t += dt
	if _tip_t > 9.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
	_place(dt)
	_footer.queue_redraw()
	if _capture_path != "":
		_frames += 1
		if _frames == int(OS.get_environment("WOA_FRAMES") if OS.get_environment("WOA_FRAMES") != "" else "70"):
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture_path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

## One menu entry: the blade plate (steel, or gold for Ranked) with its icon in the socket and its name. Hover lifts
## it toward the right with a warm glow and a light that runs along the blade; pressing pushes it in.
class MenuPlate extends Control:
	signal hovered
	var text := ""
	var icon_path := ""
	var gold := false
	var action: Callable
	var font_size := 24
	var base_y := 0.0
	var enter := 1.0                       # 0..1 the entrance (set by the menu)
	var slide := 0.0                       # hover offset to the right
	var focused := false
	var _hover := 0.0
	var _down := false
	var _run := -1.0                       # the light running along the blade (0..1), -1 none
	var _was_hot := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hovered.emit())

	func _hot() -> bool:
		return (get_global_rect().has_point(get_global_mouse_position()) or focused) and enter > 0.95

	func _process(dt: float) -> void:
		var hot := _hot()
		if hot and not _was_hot:
			_run = 0.0
			Options.click()
		_was_hot = hot
		_hover = move_toward(_hover, 1.0 if hot else 0.0, dt * 6.0)
		slide = 14.0 * (1.0 - pow(1.0 - _hover, 3.0))
		if _run >= 0.0:
			_run += dt * 1.8
			if _run > 1.2:
				_run = -1.0
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_down = true
			elif _down:
				_down = false
				if get_global_rect().has_point(get_global_mouse_position()):
					press()
			accept_event()

	func press() -> void:
		if enter < 0.95 or not action.is_valid():
			return
		Options.click()
		action.call()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var base := "menu_plate_gold" if gold else "menu_plate"
		U.skin(self, base + ("_pressed" if _down else "_normal"), r)
		if _hover > 0.0 and not _down:
			U.skin(self, base + "_hover", r, Color(1, 1, 1, _hover))
		# the icon in the socket
		var sc := Vector2(size.y * 0.5 + 3.0, size.y * 0.5)
		var ir := size.y * 0.34
		if _hover > 0.0:
			U.art_rect(self, "glow_gold", Rect2(sc - Vector2(ir * 2.2, ir * 2.2), Vector2(ir * 4.4, ir * 4.4)), Color(1, 1, 1, 0.55 * _hover))
		var ic: Texture2D = U.icon(icon_path)
		if ic:
			var is_ := ir * 1.25
			draw_texture_rect(ic, Rect2(sc - Vector2(is_, is_) * 0.5, Vector2(is_, is_)), false,
				U.GOLD.lerp(Color(1.0, 0.95, 0.8), _hover))
		# the light running along the blade toward the tip
		if _run >= 0.0:
			var x := lerpf(size.y * 1.1, size.x - size.y * 0.3, clampf(_run, 0.0, 1.0))
			var a := sin(clampf(_run, 0.0, 1.0) * PI)
			U.art_rect(self, "glow_gold", Rect2(x - 60.0, size.y * 0.5 - 30.0, 120.0, 60.0), Color(1, 0.95, 0.8, 0.5 * a))
		# the name
		var tc := Color(0.16, 0.09, 0.02) if gold else U.TEXT.lerp(Color(1.0, 0.9, 0.62), _hover)
		var f := U.font("title")
		var ty := size.y * 0.5 + font_size * 0.36
		var tx := size.y * 1.08 + 14.0
		if gold:
			draw_string(f, Vector2(tx, ty + 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.9, 0.6, 0.5))
			draw_string(f, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tc)
		else:
			U.text(self, text, Vector2(tx, ty), font_size, tc, "title")
