extends SceneTree
## Screenshot any scene (menus, loading screen): godot --path . -s tests/tools/shot.gd -- --scene=res://... --out=x.png
## [--frames=60] [--loading=0.4] (shows the loading screen at that progress on top instead).

var _out := "work/shots/shot.png"
var _frames := 60
var _n := 0

func _init() -> void:
	var scene := ""
	var loading := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.substr(8)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--loading="):
			loading = float(a.substr(10))
	if scene != "":
		change_scene_to_file.call_deferred(scene)
	if loading >= 0.0:
		var ls = load("res://src/ui/loading_screen.gd").new()
		root.add_child.call_deferred(ls)
		(func(): ls.set_progress(loading, "Raising the mountains")).call_deferred()
	process_frame.connect(_tick)

func _tick() -> void:
	_n += 1
	if _n == _frames:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
