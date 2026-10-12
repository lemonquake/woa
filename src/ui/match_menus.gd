extends Control
## In-match menus: the pause menu (Esc / F10: Resume, Options, Hero Select, Quit) and the end-of-match screen
## (winner, then each hero's level, kills / deaths / assists, last hits / denies, net worth).

const U = preload("res://src/ui/ui_kit.gd")

var game: Node
var _pause: PanelContainer
var _options: OptionsPanel
var _end: PanelContainer
var _end_shown := false

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause = _panel("Paused")
	var col: VBoxContainer = _pause.get_child(0)
	for b in [["Resume", _resume], ["Options", _open_options], ["Hero Select", _to_creator], ["Quit to desktop", func(): get_tree().quit()]]:
		col.add_child(_button(b[0], b[1]))
	_end = _panel("")
	for p in [_pause, _end]:
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
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

func is_open() -> bool:
	return _pause.visible or (_options != null and is_instance_valid(_options))

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
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.world.paused = false

func _open_options() -> void:
	_pause.visible = false
	_options = OptionsPanel.new()
	_options.game = game
	_options.closed.connect(func():
		_options = null
		_pause.visible = true)
	add_child(_options)

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
	sub.text = "%s wins at %s" % [SimConst.TEAM_NAMES[w.winner], w.clock_text()]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_end.custom_minimum_size = Vector2(1180, 0)
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 22)
	for hdr in ["Hero", "Team", "Level", "K / D / A", "LH / DN", "Net worth", "GPM", "XPM", "Hero dmg", "Building dmg", "Taken", "Healing"]:
		var l := Label.new()
		l.text = hdr
		l.add_theme_color_override("font_color", U.GOLD)
		grid.add_child(l)
	var minutes := maxf(w.time / 60.0, 0.25)
	for h in w.heroes:
		var tot := Scoreboard.totals(h)
		for val in [String(h.look.get("display_name", h.name)), SimConst.TEAM_NAMES[h.team], str(h.level),
				"%d / %d / %d" % [h.kills, h.deaths, h.assists], "%d / %d" % [h.last_hits, h.denies], str(h.networth()),
				str(int(h.gold_earned / minutes)), str(int(h.xp / minutes)), str(int(tot.hero)), str(int(tot.building)),
				str(int(tot.taken)), str(int(h.healed))]:
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
