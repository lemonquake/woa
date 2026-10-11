extends Control
## Placeholder HUD (replaced by the full HUD): clock only.

var game: Node
var _label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.position = Vector2(900, 8)
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)

func _process(_dt: float) -> void:
	if game and game.world:
		_label.text = game.world.clock_text()

func error(msg: String) -> void:
	print("error: ", msg)
