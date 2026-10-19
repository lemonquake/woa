class_name OptionsPanel
extends Control
## The Options screen: a full-screen overlay with Audio, Video, Game and Controls tabs. Every change applies at once
## and is saved; "Reset to defaults" restores everything; Back (or Esc) closes it. Used from Hero Select and from
## the pause menu (`game` is the match, so camera options apply live).

signal closed

const U = preload("res://src/ui/ui_kit.gd")
const HOTKEYS := "res://src/ui/hotkeys_screen.tscn"

var game: Node                              # the match, when opened from the pause menu
var _tabs: TabContainer
var _refresh := []                          # callables that re-read Options after a reset

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 600)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", U.font("title"))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", U.GOLD)
	col.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 20)
	_tabs.add_theme_constant_override("side_margin", 0)
	col.add_child(_tabs)
	_audio_tab()
	_video_tab()
	_game_tab()
	_controls_tab()
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	bottom.add_child(_button("Reset to defaults", _reset, 230))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	bottom.add_child(_button("Back", close, 200))

func close() -> void:
	Options.save()
	closed.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode in [KEY_ESCAPE, KEY_F10]:
		get_viewport().set_input_as_handled()
		close()

# ---- tabs ---------------------------------------------------------------------------------------------------------

func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v

func _audio_tab() -> void:
	var v := _page("Audio")
	_percent(v, "Master volume", "master", Options.apply_audio)
	_percent(v, "Effects", "effects", Options.apply_audio)
	_percent(v, "Interface", "interface", Options.apply_audio)
	_percent(v, "Ambience", "ambience", Options.apply_audio)
	_check(v, "Mute when the game is in the background", "mute_unfocused", Options.apply_audio)
	_note(v, "Volume follows your ear: 50% sounds half as loud as 100%.")

func _video_tab() -> void:
	var v := _page("Video")
	var apply := func(): Options.apply_video(get_tree())
	var monitors := Options.monitor_names()
	if int(Options.get_value("monitor")) >= monitors.size():
		Options.set_value("monitor", 0)    # that monitor is unplugged: back to the main one
	_choice(v, "Monitor", "monitor", monitors, apply)
	_choice(v, "Window mode", "window_mode", Options.WINDOW_MODES, apply)
	_choice(v, "Window size", "resolution", Options.RESOLUTIONS, apply)
	_check(v, "V-Sync", "vsync", apply)
	var limits := []
	for f in Options.FRAME_LIMITS:
		limits.append("Unlimited" if f == 0 else "%d FPS" % f)
	_choice(v, "Frame limit", "frame_limit", limits, apply)
	_choice(v, "Quality", "quality", Options.QUALITIES, func():
		Options.apply_video(get_tree())
		if game and game.get("atmosphere"):
			Options.apply_environment(game.atmosphere.env, game.atmosphere.sun))
	_slider(v, "Render scale", "render_scale", 0.5, 1.0, 0.05, func(x): return "%d%%" % roundi(x * 100.0), apply)
	_check(v, "Show FPS", "show_fps", Callable())
	_note(v, "Monitor picks the screen the game opens on. Window size applies in Windowed mode. Borderless and Fullscreen keep the cursor inside the game. Quality sets shadows, anti-aliasing, ambient occlusion and glow.")

func _game_tab() -> void:
	var v := _page("Game")
	var cam := func():
		if game and game.get("camera"):
			game.camera.edge_pan_enabled = bool(Options.get_value("edge_pan"))
			game.camera.edge_speed = float(Options.get_value("camera_speed"))
	_check(v, "Pan the camera at the screen edges", "edge_pan", cam)
	_check(v, "Lock cursor to window (Windowed)", "lock_cursor", Options.apply_cursor)
	_slider(v, "Camera speed", "camera_speed", 12.0, 60.0, 1.0, func(x): return str(roundi(x)), cam)
	_check(v, "Quick cast", "quick_cast", Callable())
	_note(v, "Quick cast: a spell or item key casts at once where the mouse points (on the unit under it), with no second click.")
	_check(v, "Center camera on hero at respawn", "center_on_respawn", Callable())
	_check(v, "Screen shake", "screen_shake", Callable())
	_check(v, "Damage numbers", "damage_numbers", Callable())
	_check(v, "Show bot chat", "bot_chat", Callable())
	_check(v, "Bot trash talk", "bot_trash_talk", Callable())
	_note(v, "Bots talk like players: they all chat their kills, mock missed spells and roast teammates (you too) who feed or fall behind, in English, Filipino and Taglish. Turn it off to keep only their plain team calls.")
	_check(v, "Online bot chat", "llm_chat", Callable())
	var used := LlmChat.usage_total()
	var lc := LlmChat.load_config()
	var or_key := String(lc.get("provider", "")) == "openrouter"
	var state := "Ready (%s)." % String(lc.get("model", LlmChat.OR_MODEL if or_key else LlmChat.MODEL)) if not lc.is_empty() \
		else "No API key yet: put {\"api_key\": \"...\"} in llm.json in the game's data folder, or set OPENROUTER_API_KEY."
	if not used.is_empty():
		state += " So far: %d lines, $%.3f." % [int(used.get("calls", 0)), float(used.get("usd", 0.0))]
	_note(v, "Single player only. An online language model (DeepSeek V4.1 Flash through OpenRouter) writes the bots' lines in their own voice; the bots still decide what to say about, so chat works the same without it. Well under a cent a match (docs/LLM_CHAT.md). " + state)
	_check(v, "Bots learn from games", "bots_learn", func():
		BotMemory.active = bool(Options.get_value("bots_learn")) and game != null)
	_note(v, "Bots learn what worked: their fights and teamfights, their ganks, where they died, which items won, how far their skill shots land and which lane you like. It is saved on this computer.")
	var learned := Label.new()
	learned.text = "
".join(BotMemory.summary())
	learned.add_theme_color_override("font_color", U.TEXT_DIM)
	learned.add_theme_font_size_override("font_size", 15)
	v.add_child(learned)
	var reset := _button("Forget what bots learned", func():
		BotMemory.reset()
		learned.text = "
".join(BotMemory.summary()), 320)
	v.add_child(reset)

func _controls_tab() -> void:
	var v := _page("Controls")
	if game == null:
		_note(v, "Change any hotkey, save layouts as templates, and see the fixed keys.")
		var b := _button("Edit hotkeys", func():
			Options.save()
			get_tree().change_scene_to_file(HOTKEYS), 240)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
	else:
		_note(v, "Hotkeys can be changed on the Hotkeys screen before each match (Hero Select, then Play, or Options there).")
		for a in ["ability_1", "ability_2", "ability_3", "ability_4", "attack", "stop", "hold", "shop", "tp", "glyph"]:
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = Keybinds.label(a)
			l.custom_minimum_size = Vector2(320, 0)
			row.add_child(l)
			var k := Label.new()
			k.text = Keybinds.key_name(a)
			k.add_theme_color_override("font_color", U.GOLD)
			row.add_child(k)
			v.add_child(row)

# ---- rows ---------------------------------------------------------------------------------------------------------

func _row(v: VBoxContainer, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("font_size", 18)
	row.add_child(l)
	v.add_child(row)
	return row

func _note(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_color_override("font_color", U.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 15)
	v.add_child(l)

func _percent(v: VBoxContainer, label: String, key: String, apply: Callable) -> void:
	_slider(v, label, key, 0.0, 1.0, 0.01, func(x): return "%d%%" % roundi(x * 100.0), apply)

func _slider(v: VBoxContainer, label: String, key: String, lo: float, hi: float, step: float, fmt: Callable, apply: Callable) -> void:
	var row := _row(v, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(340, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", U.GOLD)
	row.add_child(val)
	var read := func():
		s.set_value_no_signal(float(Options.get_value(key)))
		val.text = fmt.call(s.value)
	read.call()
	_refresh.append(read)
	s.value_changed.connect(func(x):
		Options.set_value(key, x)
		val.text = fmt.call(x)
		if apply.is_valid():
			apply.call()
		Options.save())

func _check(v: VBoxContainer, label: String, key: String, apply: Callable) -> void:
	var row := _row(v, label)
	var c := CheckButton.new()
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	var read := func(): c.set_pressed_no_signal(bool(Options.get_value(key)))
	read.call()
	_refresh.append(read)
	c.toggled.connect(func(on):
		Options.set_value(key, on)
		Options.click()
		if apply.is_valid():
			apply.call()
		Options.save())

func _choice(v: VBoxContainer, label: String, key: String, items: Array, apply: Callable) -> void:
	var row := _row(v, label)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(260, 44)
	o.add_theme_font_size_override("font_size", 17)
	for it in items:
		o.add_item(String(it))
	row.add_child(o)
	var read := func(): o.select(int(Options.get_value(key)))
	read.call()
	_refresh.append(read)
	o.item_selected.connect(func(i):
		Options.set_value(key, i)
		Options.click()
		if apply.is_valid():
			apply.call()
		Options.save())

func _button(text: String, cb: Callable, w := 200) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 50)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

func _reset() -> void:
	Options.reset()
	Options.apply_all(get_tree())
	if game and game.get("atmosphere"):
		Options.apply_environment(game.atmosphere.env, game.atmosphere.sun)
	if game and game.get("camera"):
		game.camera.edge_pan_enabled = bool(Options.get_value("edge_pan"))
		game.camera.edge_speed = float(Options.get_value("camera_speed"))
	for r in _refresh:
		r.call()
	Options.save()
