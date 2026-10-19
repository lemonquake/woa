extends SceneTree
## The 3D versus shot with chosen heroes, captured at a few moments (which way each hero faces through its idle and
## flourish). Needs the GPU:
##   godot --path . -s tests/tools/versus_shot.gd -- --a=airah,tock,araki,ezee,feran --b=burak,blau,azrael,froster,kragg
##       [--out=dir] [--at=1.0,3.0,6.0]

var stage: VersusStage
var t := 0.0
var shots: Array = []
var out := "user://versus_shot"

func _initialize() -> void:
	var a := "airah,tock,araki,ezee,feran"
	var b := "burak,blau,azrael,froster,kragg"
	var at := "1.0,3.0,6.0"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--a="):
			a = arg.substr(4)
		elif arg.begins_with("--b="):
			b = arg.substr(4)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--at="):
			at = arg.substr(5)
	for s in at.split(","):
		shots.append(float(s))
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	stage = VersusStage.new()
	root.add_child(stage)
	var i := 0
	for h in a.split(",", false):
		stage.add_hero("a%d" % i, h, 0, i)
		i += 1
	i = 0
	for h in b.split(",", false):
		stage.add_hero("b%d" % i, h, 1, i)
		i += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("user://") else out)

func _process(dt: float) -> bool:
	if t == 0.0:
		stage.begin()
	t += dt
	if not shots.is_empty() and t >= float(shots[0]):
		var img := root.get_texture().get_image()
		var p := "%s/versus_%.1f.png" % [out, float(shots[0])]
		img.save_png(ProjectSettings.globalize_path(p) if p.begins_with("user://") else p)
		print("shot ", p)
		shots.pop_front()
	return shots.is_empty()
