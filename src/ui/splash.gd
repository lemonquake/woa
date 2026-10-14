extends Control
## First scene: the loading screen with the title while the Main Menu loads in the background, then the Main Menu. The
## loading screen stays up over it until its stage is built (the menu closes it). `--match` (automation)
## goes straight into a match instead.

const MAIN_MENU := "res://src/ui/main_menu.tscn"
const MATCH := "res://src/game/main.tscn"
const MIN_SHOW := 2.6                      # seconds the title stays up even when loading is quicker

var _t := 0.0
var _path := MAIN_MENU
var _quick := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		_dedicated(args)
		return
	Options.apply_all(get_tree())
	if args.has("--match") or OS.get_cmdline_args().has("--match"):
		_path = MATCH
	for a in args:
		if a.begins_with("--capture="):
			_quick = true
		elif a.begins_with("--screen="):
			# automation: open another screen first (hero_select, game_setup, net_menu, lobby...)
			_path = "res://src/ui/%s.tscn" % a.substr(9)
	if _quick and _path != MATCH:
		# automated Hero Select captures: no title card
		get_tree().change_scene_to_file.call_deferred(_path)
		set_process(false)
		return
	# the root is still adding this scene during _ready, so the loading screen goes up on the next idle step
	set_process(false)
	_begin.call_deferred()

## A dedicated server (no window needed: run with --headless):
##   WarriorsOfAether.exe --headless -- --server [--port=27850] [--name="My server"] [--motd="Welcome"] [--password=x]
##   [--max=64]
## It prints who joins, the lobbies and the matches, and runs until the process is closed.
func _dedicated(args: PackedStringArray) -> void:
	set_process(false)
	var opts := {"dedicated": true, "port": NetSession.PORT, "max_players": 64}
	for a in args:
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"port":
				opts.port = int(kv[1])
			"name":
				opts.name = kv[1]
			"motd":
				opts.motd = kv[1]
			"password":
				opts.password = kv[1]
			"max":
				opts.max_players = int(kv[1])
	var why := NetSession.inst.host_server(opts)
	if why != "":
		printerr(why)
		get_tree().quit(1)

func _begin() -> void:
	LoadingScreen.open(get_tree())
	LoadingScreen.progress(get_tree(), 0.05, "Loading")
	ResourceLoader.load_threaded_request(_path)
	set_process(true)

func _process(dt: float) -> void:
	_t += dt
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(_path, prog)
	var p: float = prog[0] if prog.size() > 0 else 0.0
	var label := "Loading the map" if _path == MATCH else "Loading heroes"
	LoadingScreen.progress(get_tree(), 0.05 + 0.6 * minf(p, _t / MIN_SHOW), label)
	if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		get_tree().change_scene_to_file(_path)
		return
	if st == ResourceLoader.THREAD_LOAD_LOADED and (_t >= MIN_SHOW or _quick):
		set_process(false)
		var ps := ResourceLoader.load_threaded_get(_path) as PackedScene
		LoadingScreen.progress(get_tree(), 0.7, "Starting")
		get_tree().change_scene_to_packed(ps)
