extends Control
## First scene: the loading screen with the title while Hero Select loads in the background, then Hero Select. The
## loading screen stays up over Hero Select until its stage is built (Hero Select closes it). `--match` (automation)
## goes straight into a match instead.

const HERO_SELECT := "res://src/ui/hero_select.tscn"
const MATCH := "res://src/game/main.tscn"
const MIN_SHOW := 2.6                      # seconds the title stays up even when loading is quicker

var _t := 0.0
var _path := HERO_SELECT
var _quick := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--match") or OS.get_cmdline_args().has("--match"):
		_path = MATCH
	for a in args:
		if a.begins_with("--capture="):
			_quick = true
	if _quick and _path == HERO_SELECT:
		# automated Hero Select captures: no title card
		get_tree().change_scene_to_file.call_deferred(_path)
		set_process(false)
		return
	LoadingScreen.open(get_tree())
	LoadingScreen.progress(get_tree(), 0.05, "Loading")
	ResourceLoader.load_threaded_request(_path)

func _process(dt: float) -> void:
	_t += dt
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(_path, prog)
	var p: float = prog[0] if prog.size() > 0 else 0.0
	var label := "Loading the heroes" if _path == HERO_SELECT else "Loading the battlefield"
	LoadingScreen.progress(get_tree(), 0.05 + 0.6 * minf(p, _t / MIN_SHOW), label)
	if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		get_tree().change_scene_to_file(_path)
		return
	if st == ResourceLoader.THREAD_LOAD_LOADED and (_t >= MIN_SHOW or _quick):
		set_process(false)
		var ps := ResourceLoader.load_threaded_get(_path) as PackedScene
		LoadingScreen.progress(get_tree(), 0.7, "Setting the stage")
		get_tree().change_scene_to_packed(ps)
