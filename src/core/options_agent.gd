extends CanvasLayer
## Lives under the root for the whole session (added by Options.apply_all): mutes the game while its window is in
## the background (when that option is on) and draws the FPS counter.

var unfocused := false
var _fps: Label
var _click: AudioStreamPlayer

func _ready() -> void:
	name = "OptionsAgent"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fps = Label.new()
	_fps.position = Vector2(8, 4)
	_fps.add_theme_font_size_override("font_size", 14)
	_fps.add_theme_color_override("font_color", Color(0.75, 1.0, 0.6))
	_fps.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps)
	Options.ensure_buses()
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/audio/sfx/ui_click.wav")
	_click.bus = "Interface"
	_click.volume_db = -8.0
	add_child(_click)

func click() -> void:
	if _click.stream:
		_click.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		unfocused = true
		Options.apply_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		unfocused = false
		Options.apply_audio()

func _process(_dt: float) -> void:
	var on := bool(Options.get_value("show_fps"))
	_fps.visible = on
	if on:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
