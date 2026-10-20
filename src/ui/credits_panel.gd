class_name CreditsPanel
extends Control
## The Credits screen: who made the models, sounds, textures and fonts the game uses (assets/ui/credits.txt, written
## by tools/build_credits.py from docs/ASSET_CREDITS.md). Back, Esc or a click outside closes it.

signal closed

const U = preload("res://src/ui/ui_kit.gd")
const TEXT_FILE := "res://assets/ui/credits.txt"

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# a click outside the panel closes it
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			close())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 640)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Credits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", U.font("title"))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", U.GOLD)
	col.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(860, 520)
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.add_theme_color_override("default_color", U.TEXT)
	var body := FileAccess.get_file_as_string(TEXT_FILE)
	text.text = body if body != "" else "The credits list is missing (run tools/build_credits.py)."
	col.add_child(text)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bottom)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 44)
	back.pressed.connect(close)
	bottom.add_child(back)
	U.pop_in(self)

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
