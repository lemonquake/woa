extends SceneTree
## Render every hero's portrait (head and shoulders on the menu stage, in its default look) to
## assets/ui/portraits/<hero>.png, 512 x 512. Needs the GPU (run with a window, not --headless):
##   godot --path . -s tests/tools/bake_portraits.gd [-- --only=froster]
const OUT := "res://assets/ui/portraits/"

var vp: SubViewport
var stage: HeroStage
var queue: Array = []
var frames := 0

func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for id in GameSettings.HEROES:
		if only == "" or id == only:
			queue.append(id)
	vp = SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(vp)
	stage = HeroStage.new()
	stage.scenery = false
	stage.mode = "portrait"
	stage.spin = 0.0
	stage.yaw = -0.32
	vp.add_child(stage)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 3 and not queue.is_empty():
		stage.show_hero(String(queue[0]), GameSettings.default_look(String(queue[0])), false)
	if frames == 40 and not queue.is_empty():
		var img := vp.get_texture().get_image()
		var path := ProjectSettings.globalize_path(OUT + String(queue[0]) + ".png")
		img.save_png(path)
		print("portrait ", path)
		queue.pop_front()
		frames = 0
		if queue.is_empty():
			return true
	return false
