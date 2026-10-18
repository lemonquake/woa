class_name WatchPanel
extends Control
## The Watch panel of an All-Bot match (Game Setup with no You slot): which hero to watch, the camera (Free, Follow
## hero, Hero view, Auto), whose sight the screen shows (the watched hero's team, either team, both, the whole map),
## the bots' orders drawn as waypoints and what each bot is doing over its head, and the game speed. Clicking a hero on
## the top bar watches it too. Every control only changes what is shown (Main: watch(), set_cam_mode(), vision_mode,
## show_orders, show_plans); the bots play on as they would.

const U = preload("res://src/ui/ui_kit.gd")
const W := 300.0
const CAMS := ["free", "follow", "hero", "auto"]
const CAM_NAMES := ["Free", "Follow hero", "Hero view", "Auto"]
const CAM_TIPS := ["Move the camera yourself (screen edges, arrow keys, minimap)",
	"The camera stays on the watched hero",
	"The watched hero's view: its team's sight, its orders, the camera on it",
	"The camera goes where the fighting is and watches the hero in it"]
const SIGHT := [-1, 0, 1, 2, 3]
const SIGHT_NAMES := ["Hero's team", "Ancient Light", "Black Sun", "Both teams", "Whole map"]
const ORDER_NAMES := ["Off", "Watched hero", "Every hero"]

var game: Node
var panel: PanelContainer
var _body: VBoxContainer
var _hide_btn: Button
var _now: Label
var _hero_pick: OptionButton
var _hero_ids: Array = []
var _cam_btns: Array[Button] = []
var _sight: OptionButton
var _orders: OptionButton
var _plans: CheckBox
var _speed_btns: Array[Button] = []
var _pause_btn: Button
var _tick := 0.0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", U.box("panel_main"))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(W, 0)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Watching"
	title.add_theme_font_override("font", U.font("title"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", U.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_hide_btn = _button("Hide", _toggle_body)
	_hide_btn.custom_minimum_size = Vector2(70, 28)
	head.add_child(_hide_btn)
	v.add_child(head)
	_now = Label.new()
	_now.add_theme_font_size_override("font_size", 15)
	_now.add_theme_color_override("font_color", U.TEXT)
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.custom_minimum_size = Vector2(W, 0)
	v.add_child(_now)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	v.add_child(_body)

	_hero_pick = OptionButton.new()
	_hero_pick.tooltip_text = "The hero to watch (or click a hero on the top bar)"
	_hero_pick.focus_mode = Control.FOCUS_NONE
	_hero_pick.add_theme_font_size_override("font_size", 15)
	_hero_pick.item_selected.connect(func(i):
		if i >= 0 and i < _hero_ids.size():
			game.watch(int(_hero_ids[i]))
			if game.cam_mode == "auto":
				game.set_cam_mode("follow"))
	_body.add_child(_hero_pick)

	_body.add_child(_caption("Camera"))
	var cams := GridContainer.new()
	cams.columns = 2
	cams.add_theme_constant_override("h_separation", 6)
	cams.add_theme_constant_override("v_separation", 6)
	for i in CAMS.size():
		var b := _button(CAM_NAMES[i], func(): game.set_cam_mode(CAMS[i]))
		b.toggle_mode = true
		b.tooltip_text = CAM_TIPS[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cam_btns.append(b)
		cams.add_child(b)
	_body.add_child(cams)

	_sight = _pick(SIGHT_NAMES)
	_sight.tooltip_text = "Whose sight the fog of war shows"
	_sight.item_selected.connect(func(i):
		if game.cam_mode == "hero":
			game.set_cam_mode("follow")
		game.vision_mode = SIGHT[i]
		game.set("_fog_tick", -1)
		refresh())
	_body.add_child(_row("Sight", _sight))
	_orders = _pick(ORDER_NAMES)
	_orders.tooltip_text = "Each bot's current order and the ones it queued, as waypoints"
	_orders.item_selected.connect(func(i): game.show_orders = i)
	_body.add_child(_row("Orders", _orders))
	_plans = CheckBox.new()
	_plans.text = "Show what each bot is doing"
	_plans.focus_mode = Control.FOCUS_NONE
	_plans.add_theme_font_size_override("font_size", 15)
	_plans.toggled.connect(func(on): game.show_plans = on)
	_body.add_child(_plans)

	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 6)
	for k in [1.0, 2.0, 4.0]:
		var b := _button("x%d" % int(k), func(): _set_speed(k))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("speed", k)
		_speed_btns.append(b)
		sp.add_child(b)
	_pause_btn = _button("Pause", _toggle_pause)
	_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.add_child(_pause_btn)
	_body.add_child(sp)
	refresh()

## A label and a control on one line.
func _row(text: String, ctl: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var l := _caption(text)
	l.custom_minimum_size = Vector2(62, 0)
	r.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctl)
	return r

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", U.GOLD)
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	return b

func _pick(names: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 15)
	for n in names:
		o.add_item(n)
	return o

func _toggle_body() -> void:
	_body.visible = not _body.visible
	_hide_btn.text = "Hide" if _body.visible else "Show"

func _set_speed(k: float) -> void:
	Engine.time_scale = k
	refresh()

func _toggle_pause() -> void:
	game.world.paused = not game.world.paused
	refresh()

## Put every control in step with Main (the camera mode changes when the player pans; Auto changes the hero).
func refresh() -> void:
	if game == null or game.world == null or _hero_pick == null:
		return
	var w: SimWorld = game.world
	var ids: Array = []
	for h in w.heroes:
		ids.append(h.id)
	if ids != _hero_ids:
		_hero_ids = ids
		_hero_pick.clear()
		for h in w.heroes:
			_hero_pick.add_item("%s  ·  %s" % [h.who(), SimConst.TEAM_NAMES[h.team]])
	_hero_pick.select(_hero_ids.find(int(game.player_hero_id)))
	for i in CAMS.size():
		_cam_btns[i].set_pressed_no_signal(String(game.cam_mode) == CAMS[i])
	_sight.select(maxi(0, SIGHT.find(int(game.vision_mode))))
	_orders.select(clampi(int(game.show_orders), 0, 2))
	_plans.set_pressed_no_signal(bool(game.show_plans))
	for b in _speed_btns:
		b.set_pressed_no_signal(is_equal_approx(float(b.get_meta("speed")), Engine.time_scale))
	_pause_btn.text = "Resume" if w.paused else "Pause"

## Whether a screen point is over the panel (orders and selection boxes are not started through it).
func covers(p: Vector2) -> bool:
	return panel.visible and panel.get_global_rect().has_point(p)

func _process(dt: float) -> void:
	if game == null or game.world == null:
		return
	panel.position = Vector2(12, 64)
	panel.size = Vector2.ZERO
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 0.25
	refresh()
	var h: SimUnit = game.world.get_unit(game.player_hero_id)
	if h != null:
		var b = game.world.bot_for(h.id)
		_now.text = "%s, %s\n%s" % [h.who(), SimConst.TEAM_NAMES[h.team], b.plan_text() if b != null else ""]

func _exit_tree() -> void:
	Engine.time_scale = 1.0
