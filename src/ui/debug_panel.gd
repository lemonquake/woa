class_name DebugPanel
extends Control
## The Debug panel (F9, or the Debug button at the top right of the match): test functions for playtesting. Every
## button calls a SimDebug helper; switches stay on until turned off. Built from standard controls with the game theme.
## The Bot Log section shows what each bot did (SimBotLog): thoughts, orders and where they came from, the skills and
## items it used, time in each mode, and its latest steps; Save Bot Log writes every bot's log to user://bot_log.txt.

const U = preload("res://src/ui/ui_kit.gd")
const W := 420.0                           # content width (the frame adds its own margins round it)
const TOP := 46.0                          # below the Debug button
const GAP := 10.0

var game: Node
var panel: PanelContainer
var toggle_btn: Button
var _status: Label
var _speed_btns: Array[Button] = []
var _fps: Label
var _scroll: ScrollContainer
var _box: VBoxContainer
var _bot_pick: OptionButton
var _bot_text: Label
var _bot_ids: Array = []                   # hero id per entry of _bot_pick (-1: every bot, summaries only)
var _bot_refresh := 0.0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_btn = Button.new()
	toggle_btn.text = "Debug (%s)" % Keybinds.key_name("debug")
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.add_theme_font_size_override("font_size", 14)
	toggle_btn.custom_minimum_size = Vector2(118, 30)
	toggle_btn.pressed.connect(toggle)
	add_child(toggle_btn)
	_fps = Label.new()
	_fps.add_theme_font_size_override("font_size", 14)
	_fps.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7))
	_fps.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.visible = false
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps)
	panel = PanelContainer.new()
	# the lighter framed box: the menu frame's wide corner ornaments cost too much room for a tool panel
	panel.add_theme_stylebox_override("panel", U.box("panel_main"))
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(W, 0)
	panel.add_child(_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(W - 14, 0)      # room for the scroll bar when it shows
	_scroll.add_child(v)
	_box = v
	var title := Label.new()
	title.text = "Debug"
	title.add_theme_font_override("font", U.font("title"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", U.GOLD)
	v.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", U.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_status)

	_section(v, "Match")
	_grid(v, [
		["Force game start", func(): SimDebug.force_start(_w()); _say("The horn sounds: creeps are on their way")],
		["Force creep wave", func(): SimDebug.force_wave(_w()); _say("A wave spawned in every lane")],
		["Spawn neutral camps", func(): SimDebug.force_neutrals(_w()); _say("Neutral camps spawned")],
		["Skip 1 minute", func(): SimDebug.skip_time(_w(), 60.0); _say("Clock +60 s")],
		["Skip 5 minutes", func(): SimDebug.skip_time(_w(), 300.0); _say("Clock +5 min")],
		["Use glyph", func(): _w().glyph(game.player_team, game.player_hero_id)],
	])
	_section(v, "Your hero")
	_grid(v, [
		["Level up", func(): SimDebug.level_up(_w(), _h()); _say("Level %d" % _h().level)],
		["Level +5", func(): SimDebug.level_up(_w(), _h(), 5); _say("Level %d" % _h().level)],
		["Max level", func(): SimDebug.level_up(_w(), _h(), 30); _say("Level %d" % _h().level)],
		["+1000 gold", func(): SimDebug.gold(_w(), _h(), 1000)],
		["+10000 gold", func(): SimDebug.gold(_w(), _h(), 10000)],
		["Refresh", func(): SimDebug.refresh(_w(), _h()); _say("Health, mana and cooldowns refreshed")],
		["Respawn now", func(): SimDebug.respawn(_w(), _h())],
		["Teleport to camera", func(): SimDebug.teleport(_w(), _h(), View.to2(game.camera.target))],
	])
	_section(v, "Switches")
	var sw := GridContainer.new()
	sw.columns = 2
	sw.add_theme_constant_override("h_separation", 6)
	sw.add_theme_constant_override("v_separation", 0)
	v.add_child(sw)
	_switch(sw, "God mode", "god", "Your hero's health stays full")
	_switch(sw, "Free spells", "free_spells", "No mana costs or cooldowns")
	_switch(sw, "Reveal the map", "reveal", "Lifts the fog of war")
	_switch(sw, "Bot stands still", "passive_bot", "Enemy bots give no orders")
	var fps_box := CheckBox.new()
	fps_box.text = "Show frame rate"
	fps_box.tooltip_text = "Frames per second at the top right"
	fps_box.focus_mode = Control.FOCUS_NONE
	fps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_box.add_theme_font_size_override("font_size", 14)
	fps_box.toggled.connect(func(on): _fps.visible = on)
	sw.add_child(fps_box)
	_section(v, "Enemies")
	_grid(v, [
		["Kill enemy hero", func(): _kill_enemy_hero()],
		["Kill selected unit", func(): _kill_selected()],
		["Damage enemy hero 50%", func(): _hurt_enemy_hero()],
		["Shop: open", func(): game.hud.toggle_shop()],
	])
	_section(v, "Game speed")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for sp in [0.5, 1.0, 2.0, 4.0]:
		var b := Button.new()
		b.text = ("x%s" % str(sp)).replace(".0", "")
		b.custom_minimum_size = Vector2(0, 32)
		b.toggle_mode = true
		b.button_pressed = sp == 1.0
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_speed.bind(sp, b))
		_speed_btns.append(b)
		row.add_child(b)
	v.add_child(row)
	_section(v, "Bot Log")
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	_bot_pick = OptionButton.new()
	_bot_pick.focus_mode = Control.FOCUS_NONE
	_bot_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bot_pick.add_theme_font_size_override("font_size", 14)
	_bot_pick.item_selected.connect(func(_i): _bot_refresh = 0.0)
	brow.add_child(_bot_pick)
	var save := Button.new()
	save.text = "Save Bot Log"
	save.focus_mode = Control.FOCUS_NONE
	save.add_theme_font_size_override("font_size", 14)
	save.tooltip_text = "Writes every bot's log to bot_log.txt in the game's user folder"
	save.pressed.connect(_save_bot_log)
	brow.add_child(save)
	v.add_child(brow)
	_bot_text = Label.new()
	_bot_text.add_theme_font_size_override("font_size", 12)
	_bot_text.add_theme_color_override("font_color", U.TEXT)
	_bot_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bot_text.custom_minimum_size = Vector2(W - 20, 0)
	v.add_child(_bot_text)

func _section(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", U.GOLD)
	if v.get_child_count() > 2:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 2)
		v.add_child(sp)
	v.add_child(l)

func _grid(v: VBoxContainer, items: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(it[1])
		g.add_child(b)
	v.add_child(g)

func _switch(v: Container, text: String, flag: String, tip := "") -> void:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_font_size_override("font_size", 14)
	c.button_pressed = _w() != null and _w().debug_flags.has(flag)
	c.toggled.connect(func(on): SimDebug.set_flag(_w(), flag, on))
	v.add_child(c)

func _w() -> SimWorld:
	return game.world if game else null

func _h() -> SimUnit:
	return game.world.get_unit(game.player_hero_id)

func _say(msg: String) -> void:
	if game.hud and game.hud.has_method("notice"):
		game.hud.notice(msg)

func _enemy_hero() -> SimUnit:
	for h in _w().heroes:
		if h.team != game.player_team and h.alive:
			return h
	return null

func _kill_enemy_hero() -> void:
	var e := _enemy_hero()
	if e:
		SimDebug.kill(_w(), e, _h())
	else:
		_say("No living enemy hero")

func _hurt_enemy_hero() -> void:
	var e := _enemy_hero()
	if e:
		e.hp = maxf(1.0, e.hp - e.max_hp * 0.5)

func _kill_selected() -> void:
	var u: SimUnit = _w().get_unit(game.selected_id)
	if u == null or u.id == game.player_hero_id:
		_say("Select an enemy unit first")
		return
	SimDebug.kill(_w(), u, _h())

func _set_speed(sp: float, btn: Button) -> void:
	Engine.time_scale = sp
	for b in _speed_btns:
		b.button_pressed = b == btn
	_say("Game speed x%s" % str(sp))

func toggle() -> void:
	panel.visible = not panel.visible

## Whether a screen point is over the panel or its button (orders are not issued through it).
func covers(p: Vector2) -> bool:
	return toggle_btn.get_global_rect().has_point(p) or (panel.visible and panel.get_global_rect().has_point(p))

## Lay the panel out from its real size: the frame's margins come on top of the content width, and the height is
## capped to the room between the Debug button and the bottom panel (the rest scrolls).
func _place(vs: Vector2) -> void:
	var sb := panel.get_theme_stylebox("panel")
	var mx := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb else 0.0
	var my := sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb else 0.0
	var bottom_h := 206.0
	if game and game.get("hud") != null and game.hud.get("bottom") != null:
		bottom_h = game.hud.bottom.size.y
	var room := vs.y - TOP - bottom_h - GAP - my
	var want := _box.get_combined_minimum_size().y
	var h := clampf(want, 120.0, maxf(120.0, room))
	_scroll.custom_minimum_size = Vector2(W, h)
	panel.size = Vector2.ZERO                # shrink to the minimum again (content may have shrunk)
	panel.reset_size()
	var pw := W + mx
	panel.position = Vector2(maxf(GAP, vs.x - pw - GAP), TOP)

func _process(_dt: float) -> void:
	var vs := get_viewport_rect().size
	toggle_btn.position = Vector2(vs.x - toggle_btn.size.x - 10, 8)
	if panel.visible:
		_place(vs)
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
		_fps.position = Vector2(vs.x - 260, 12)
	if panel.visible and _w():
		var h := _h()
		_status.text = "Clock %s   Wave %d   Level %d   Gold %d" % [_w().clock_text(), _w().wave, h.level, h.gold()]
		_bot_refresh -= _dt
		if _bot_refresh <= 0.0:
			_bot_refresh = 0.5
			_update_bot_log()

## Bot Log: the bots of the match in the picker (kept in step with the world), and the chosen one's log.
func _update_bot_log() -> void:
	var w := _w()
	if w == null or _bot_pick == null:
		return
	var ids: Array = [-1]
	for b in w.bots:
		ids.append(int(b.hero_id))
	if ids != _bot_ids:
		var keep: int = _bot_ids[_bot_pick.selected] if _bot_pick.selected >= 0 and _bot_pick.selected < _bot_ids.size() else -1
		_bot_ids = ids
		_bot_pick.clear()
		_bot_pick.add_item("Every bot")
		for b in w.bots:
			var h := w.get_unit(int(b.hero_id))
			_bot_pick.add_item(h.who() if h != null else String(b.name))
		_bot_pick.select(maxi(0, _bot_ids.find(keep)))
	var pick := int(_bot_ids[_bot_pick.selected]) if _bot_pick.selected >= 0 else -1
	if w.bots.is_empty():
		_bot_text.text = "No bots in this match."
	elif pick < 0:
		var parts: Array = []
		for b in w.bots:
			parts.append(_bot_summary(b))
		_bot_text.text = "\n".join(parts)
	else:
		var b = w.bot_for(pick)
		_bot_text.text = (_bot_summary(b) + "\n\nLatest:\n" + b.botlog.recent(24)) if b != null else ""

func _bot_summary(b) -> String:
	var h: SimUnit = _w().get_unit(int(b.hero_id))
	return b.botlog.summary(String(b.name), String(h.def.name) if h != null else "?", String(b.mode), _w().time)

func _save_bot_log() -> void:
	var w := _w()
	if w == null:
		return
	var out: Array = ["Bot Log at %s" % w.clock_text(), ""]
	for b in w.bots:
		out.append(_bot_summary(b))
		out.append(b.botlog.recent(SimBotLog.MAX_ENTRIES))
		out.append("")
	var f := FileAccess.open("user://bot_log.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
		_say("Bot Log saved to " + ProjectSettings.globalize_path("user://bot_log.txt"))

func _exit_tree() -> void:
	Engine.time_scale = 1.0
