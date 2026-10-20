extends Control
## Hotkeys: shown after Play on Hero Select, before the match loads. Every rebindable key is listed by group; click a
## key, then press the new key (or Mouse 4 / Mouse 5). A key already in use swaps with the old one, so no action is
## left without a key. Templates: load a built-in or saved layout, save the current one under a name, delete it.
## "Good to go" saves and starts the match; Back returns to Game Setup.

const U = preload("res://src/ui/ui_kit.gd")
const MATCH := "res://src/game/main.tscn"
const HERO_SELECT := "res://src/ui/game_setup.tscn"

var _buttons := {}                         # action -> Button
var _listening := ""
var _msg: Label
var _templates: OptionButton
var _name: LineEdit
var _delete: Button
var _starting := false
var _back_btn: Button

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Keybinds.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.32, 0.22, 0.08, 0.5))
	gr.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 0.9)
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := _label("Are you good to go?", 44, U.GOLD, "title")
	root.add_child(title)
	var sub := _label("These are your hotkeys for the match. Click a key and press a new one to change it (Esc cancels); hold Ctrl and / or Alt for a combination such as Ctrl + Q or Alt + 1. A key that is already taken swaps places. Shift + any hotkey queues the order.", 17, U.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(sub)

	# templates row
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	root.add_child(trow)
	trow.add_child(_label("Template", 18, U.TEXT, "bold"))
	_templates = OptionButton.new()
	_templates.custom_minimum_size = Vector2(260, 42)
	_templates.item_selected.connect(func(_i): _refresh_template_buttons())
	trow.add_child(_templates)
	trow.add_child(_button("Load", _load_template, 100))
	_delete = _button("Delete", _delete_template, 100)
	trow.add_child(_delete)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	trow.add_child(gap)
	_name = LineEdit.new()
	_name.placeholder_text = "Template name"
	_name.custom_minimum_size = Vector2(240, 42)
	_name.max_length = 32
	trow.add_child(_name)
	trow.add_child(_button("Save as template", _save_template, 190))
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(gap2)
	trow.add_child(_button("Reset to default", func():
		Keybinds.apply_template("Default (Dota)")
		_refresh_keys()
		_say("Default keys restored", U.TEXT), 190))

	# groups of keys
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var cols := GridContainer.new()
	cols.columns = 3
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("h_separation", 16)
	cols.add_theme_constant_override("v_separation", 16)
	scroll.add_child(cols)
	var groups := {}
	var order: Array = []
	for a in Keybinds.ACTIONS:
		if not groups.has(a[2]):
			groups[a[2]] = []
			order.append(a[2])
		groups[a[2]].append(a)
	for g in order:
		cols.add_child(_group_panel(g, groups[g]))

	var fixed := _label("Fixed keys:  Ctrl + ability key learns it (unless bound)   ·   Shift queues orders (hold it to see the queue)   ·   Alt + click pings   ·   Ctrl + 1-9 sets a control group, 1-9 recalls it   ·   Esc or F10 opens the menu   ·   Hold right click to repeat the order", 15, U.TEXT_DIM)
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(fixed)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	root.add_child(bottom)
	_back_btn = _button("Back", func():
		Keybinds.save()
		Options.go(get_tree(), HERO_SELECT), 160)
	bottom.add_child(_back_btn)
	_msg = _label("", 18, U.TEXT)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_msg)
	var go := Button.new()
	go.text = "Good to go"
	go.custom_minimum_size = Vector2(300, 62)
	go.add_theme_font_override("font", U.font("title"))
	go.add_theme_font_size_override("font_size", 30)
	go.pressed.connect(_start)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.55, 0.4, 0.14), "hover": Color(0.7, 0.52, 0.18), "pressed": Color(0.45, 0.32, 0.1), "focus": Color(0.55, 0.4, 0.14)}[st]
		sb.border_color = Color(1.0, 0.85, 0.5)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		go.add_theme_stylebox_override(st, sb)
	go.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	go.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	go.add_theme_color_override("font_focus_color", Color(1.0, 0.97, 0.88))
	bottom.add_child(go)
	_fill_templates()
	_refresh_keys()
	go.grab_focus.call_deferred()

func _label(text: String, size: int, col: Color, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _button(text: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 42)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b

func _group_panel(group: String, actions: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(_label(group, 22, U.GOLD, "title"))
	for a in actions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := _label(a[1], 16, U.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 36)
		b.add_theme_font_override("font", U.font("bold"))
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_listen.bind(a[0]))
		row.add_child(b)
		_buttons[a[0]] = b
		v.add_child(row)
	return p

func _refresh_keys() -> void:
	for act in _buttons:
		var b: Button = _buttons[act]
		b.text = "Press a key" if act == _listening else Keybinds.key_name(act)
		b.add_theme_color_override("font_color", U.GOLD if act == _listening else U.TEXT)

func _listen(act: String) -> void:
	_listening = act
	_say("Press the new key for \"%s\" (Esc cancels)" % Keybinds.label(act), U.GOLD)
	_refresh_keys()

## Esc goes back, as the Back button does (fields, dropdowns and overlays get the key first).
func _unhandled_key_input(e: InputEvent) -> void:
	if U.is_esc(e) and _back_btn != null and _back_btn.is_visible_in_tree() and _listening == "" and not _starting:
		get_viewport().set_input_as_handled()
		_back_btn.pressed.emit()

func _input(e: InputEvent) -> void:
	if _listening == "":
		return
	var bind := 0
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_listening = ""
			_say("", U.TEXT)
			_refresh_keys()
			get_viewport().set_input_as_handled()
			return
		if k.keycode in Keybinds.MODIFIER_KEYS:
			# a modifier on its own: wait for the key it goes with (Shift stays the queue key)
			_say("Hold Ctrl and / or Alt, then press the key. Shift queues orders, so it is not part of a hotkey.", U.GOLD)
			get_viewport().set_input_as_handled()
			return
		bind = Keybinds.binding_of(k)
		var why := Keybinds.refuse(bind)
		if why != "":
			_say(why + ". Pick another key.", Color(1.0, 0.45, 0.4))
			get_viewport().set_input_as_handled()
			return
	elif e is InputEventMouseButton and e.pressed:
		bind = Keybinds.binding_of(e)
		if bind == 0:
			return
	else:
		return
	get_viewport().set_input_as_handled()
	var act := _listening
	_listening = ""
	var swapped := Keybinds.assign(act, bind)
	Keybinds.save()
	var learn_note := ""
	if bind & KEY_MASK_CTRL:
		var plain := Keybinds.action_for_binding(bind & ~KEY_MASK_CTRL)
		if plain.begins_with("ability_"):
			learn_note = "  (Ctrl + %s no longer learns %s: use its + button)" % [Keybinds.name_of(bind & ~KEY_MASK_CTRL), Keybinds.label(plain)]
	if swapped != "":
		_say("%s is now on %s; \"%s\" moved to %s%s" % [Keybinds.label(act), Keybinds.name_of(bind), Keybinds.label(swapped),
			Keybinds.key_name(swapped), learn_note], Color(1.0, 0.85, 0.45))
	else:
		_say("%s is now on %s%s" % [Keybinds.label(act), Keybinds.name_of(bind), learn_note], Color(0.7, 1.0, 0.7))
	_refresh_keys()

func _say(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)

func _fill_templates(select := "") -> void:
	_templates.clear()
	var i := 0
	for n in Keybinds.builtin_templates():
		_templates.add_item(n)
		_templates.set_item_metadata(i, n)
		if n == select:
			_templates.selected = i
		i += 1
	for n in Keybinds.templates:
		_templates.add_item(n + "  (saved)")
		_templates.set_item_metadata(i, n)
		if n == select:
			_templates.selected = i
		i += 1
	_refresh_template_buttons()

func _selected_template() -> String:
	if _templates.selected < 0:
		return ""
	return String(_templates.get_item_metadata(_templates.selected))

func _refresh_template_buttons() -> void:
	_delete.disabled = not Keybinds.templates.has(_selected_template())

func _load_template() -> void:
	var n := _selected_template()
	if n == "":
		return
	Keybinds.apply_template(n)
	Keybinds.save()
	_refresh_keys()
	_say("Loaded \"%s\"" % n, Color(0.7, 1.0, 0.7))

func _save_template() -> void:
	var n := _name.text.strip_edges()
	if n == "":
		_say("Type a name for the template first", Color(1.0, 0.45, 0.4))
		return
	if Keybinds.builtin_templates().has(n):
		_say("\"%s\" is a built-in template: choose another name" % n, Color(1.0, 0.45, 0.4))
		return
	Keybinds.save_template(n)
	_fill_templates(n)
	_name.text = ""
	_say("Saved template \"%s\"" % n, Color(0.7, 1.0, 0.7))

func _delete_template() -> void:
	var n := _selected_template()
	if not Keybinds.templates.has(n):
		return
	Keybinds.delete_template(n)
	_fill_templates()
	_say("Deleted \"%s\"" % n, U.TEXT)

func _start() -> void:
	if _starting:
		return
	_starting = true
	Keybinds.save()
	LoadingScreen.open(get_tree())
	LoadingScreen.progress(get_tree(), 0.02, "Loading the map")
	# let the loading screen draw before the match scene starts loading
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(MATCH)
