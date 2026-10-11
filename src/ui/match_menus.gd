extends Control
## In-match menus: the pause menu (Esc / F10: Resume, Settings, Hero Creator, Quit) and the end-of-match screen
## (winner, then each hero's level, kills / deaths / assists, last hits / denies, net worth).

const U = preload("res://src/ui/ui_kit.gd")

var game: Node
var _pause: PanelContainer
var _settings: PanelContainer
var _end: PanelContainer
var _end_shown := false

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause = _panel("Paused")
	var col: VBoxContainer = _pause.get_child(0)
	for b in [["Resume", _resume], ["Settings", _open_settings], ["Hero Select", _to_creator], ["Quit to desktop", func(): get_tree().quit()]]:
		col.add_child(_button(b[0], b[1]))
	_settings = _panel("Settings")
	var sc: VBoxContainer = _settings.get_child(0)
	_slider(sc, "Master volume", AudioServer.get_bus_volume_db(0), func(v): AudioServer.set_bus_volume_db(0, v))
	var edge := CheckBox.new()
	edge.text = "Pan the camera at the screen edges"
	edge.button_pressed = true
	edge.toggled.connect(func(on): game.camera.edge_pan_enabled = on)
	sc.add_child(edge)
	var speed_row := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Camera speed"
	sl.custom_minimum_size = Vector2(160, 0)
	speed_row.add_child(sl)
	var s := HSlider.new()
	s.min_value = 12
	s.max_value = 60
	s.value = 32
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v): game.camera.edge_speed = v)
	speed_row.add_child(s)
	sc.add_child(speed_row)
	sc.add_child(_button("Back", func():
		_settings.visible = false
		_pause.visible = true))
	_end = _panel("")
	for p in [_pause, _settings, _end]:
		p.visible = false

func _panel(title: String) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	if title != "":
		var l := Label.new()
		l.text = title
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", U.font("title"))
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", U.GOLD)
		v.add_child(l)
	center.add_child(p)
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b

func _slider(v: VBoxContainer, label: String, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = -40
	s.max_value = 6
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	row.add_child(s)
	v.add_child(row)

func is_open() -> bool:
	return _pause.visible or _settings.visible

func toggle() -> void:
	if _end.visible:
		return
	if is_open():
		_resume()
	else:
		_pause.visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		game.world.paused = true

func _resume() -> void:
	_pause.visible = false
	_settings.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.world.paused = false

func _open_settings() -> void:
	_pause.visible = false
	_settings.visible = true

func _to_creator() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/hero_select.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_F10 or (k.keycode == KEY_ESCAPE and game.input and game.input.targeting == ""):
			toggle()
			get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if game and game.world and game.world.winner >= 0 and not _end_shown:
		_end_shown = true
		get_tree().create_timer(3.0).timeout.connect(_show_end)

func _show_end() -> void:
	var w: SimWorld = game.world
	var v: VBoxContainer = _end.get_child(0)
	_end.custom_minimum_size = Vector2(760, 0)
	var won: bool = w.winner == game.player_team
	var t := Label.new()
	t.text = "Victory" if won else "Defeat"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", U.font("title"))
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", U.GOLD if won else U.DUSK)
	v.add_child(t)
	var sub := Label.new()
	sub.text = "%s wins at %s" % [["Dawn", "Dusk"][w.winner], w.clock_text()]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 22)
	for hdr in ["Hero", "Team", "Level", "K / D / A", "LH / DN", "Net worth", "Gold"]:
		var l := Label.new()
		l.text = hdr
		l.add_theme_color_override("font_color", U.GOLD)
		grid.add_child(l)
	for h in w.heroes:
		for val in [String(h.look.get("display_name", h.name)), ["Dawn", "Dusk"][h.team], str(h.level),
				"%d / %d / %d" % [h.kills, h.deaths, h.assists], "%d / %d" % [h.last_hits, h.denies], str(h.networth()), str(h.gold())]:
			var l2 := Label.new()
			l2.text = val
			grid.add_child(l2)
	v.add_child(grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.add_child(_button("Play again", func(): get_tree().reload_current_scene()))
	row.add_child(_button("Hero Select", _to_creator))
	row.add_child(_button("Quit", func(): get_tree().quit()))
	v.add_child(row)
	_end.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
