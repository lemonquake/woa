class_name NetChat
extends VBoxContainer
## The chat box of the Multiplayer screens: the lines so far (player names in gold, yours in blue, the server's own
## messages dimmed) and a line to type in; Enter sends. `send` is called with the text.

const U = preload("res://src/ui/ui_kit.gd")

var send: Callable
var my_name := ""
var log_label: RichTextLabel
var field: LineEdit
var _count := 0

func _init(placeholder := "Say something to everyone here") -> void:
	add_theme_constant_override("separation", 8)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", U.box("field", 12))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(frame)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.selection_enabled = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_override("normal_font", U.font("body"))
	log_label.add_theme_font_override("bold_font", U.font("bold"))
	log_label.add_theme_font_size_override("normal_font_size", 16)
	log_label.add_theme_font_size_override("bold_font_size", 16)
	log_label.add_theme_constant_override("line_separation", 3)
	frame.add_child(log_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	field = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = SimConst.CHAT_MAX_LEN
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(0, 44)
	field.add_theme_font_size_override("font_size", 16)
	field.text_submitted.connect(func(_t): _send())
	row.add_child(field)
	var b := Button.new()
	b.text = "Send"
	b.custom_minimum_size = Vector2(96, 44)
	b.pressed.connect(func():
		Options.click()
		_send())
	row.add_child(b)

func _send() -> void:
	var t := field.text.strip_edges()
	if t == "":
		return
	field.text = ""
	if send.is_valid():
		send.call(t)
	field.grab_focus()

## Show these lines ([name, text, system]), replacing what was there.
func set_lines(lines: Array) -> void:
	log_label.clear()
	_count = 0
	for l in lines:
		add_line(String(l[0]), String(l[1]), bool(l[2]))

func add_line(nm: String, text: String, system: bool) -> void:
	var safe := text.replace("[", "[lb]")
	if _count > 0:
		log_label.append_text("\n")
	_count += 1
	if system:
		log_label.append_text("[color=#%s]%s[/color]" % [Color(0.62, 0.66, 0.72).to_html(false), safe])
		return
	var nc := Color(0.55, 0.78, 1.0) if nm == my_name else U.GOLD
	log_label.append_text("[b][color=#%s]%s:[/color][/b] %s" % [nc.to_html(false), nm.replace("[", "[lb]"), safe])
