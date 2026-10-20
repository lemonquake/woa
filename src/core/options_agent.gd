extends CanvasLayer
## Lives under the root for the whole session (added by Options.apply_all): mutes the game while its window is in
## the background (when that option is on), keeps the cursor locked to the window after Alt + Tab, draws the FPS
## counter, plays the menu click for every button, and fades between screens (go()).

const MATCH := "res://src/game/main.tscn"
const FADE_OUT := 0.12
const FADE_IN := 0.2

var unfocused := false
var _fps: Label
var _click: AudioStreamPlayer
var _fade: ColorRect
var _going := false

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
	_fade = ColorRect.new()
	_fade.color = Color(0.015, 0.018, 0.026, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	move_child(_fade, 0)
	# every button anywhere clicks when pressed (screens that call Options.click() themselves play it once: the
	# player restarts the same sound)
	get_tree().node_added.connect(_on_node_added)

func click() -> void:
	if _click.stream:
		_click.play()

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		(n as BaseButton).pressed.connect(click)

## Change to another screen: a quick fade to dark, the new screen, a fade back in (clicks wait meanwhile). The match
## gets the loading screen instead. "Menu animations" off, or an automated run: at once.
func go(path: String) -> void:
	if _going:
		return
	var tree := get_tree()
	tree.paused = false
	if path == MATCH:
		LoadingScreen.open(tree)
		LoadingScreen.progress(tree, 0.02, "Loading the map")
		tree.change_scene_to_file.call_deferred(path)
		return
	if not bool(Options.get_value("ui_motion")) or Options.automated():
		tree.change_scene_to_file(path)
		return
	_going = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_OUT)
	await tw.finished
	tree.change_scene_to_file(path)
	await tree.process_frame
	await tree.process_frame
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, FADE_IN).set_ease(Tween.EASE_OUT)
	await tw.finished
	_going = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		unfocused = true
		Options.apply_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		unfocused = false
		Options.apply_audio()
		Options.apply_cursor()

func _process(_dt: float) -> void:
	var on := bool(Options.get_value("show_fps"))
	_fps.visible = on
	if on:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
