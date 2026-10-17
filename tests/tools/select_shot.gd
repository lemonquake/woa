extends SceneTree
## Hero Select with each listed hero chosen, captured (run 2026-10-17 e: the new hero bodies on the stage).
##   godot --path . -s tests/tools/select_shot.gd -- --heroes=ezee,azrin,caziel --out=work/lemondev/2026-10-17e-hero-models/shots

var out := "work/lemondev/2026-10-17e-hero-models/shots"
var heroes: Array = ["ezee", "azrin", "caziel"]

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--heroes="):
			heroes = Array(a.substr(9).split(",", false))
	_run.call_deferred()

func _run() -> void:
	var keep := GameSettings.selected
	for id in heroes:
		GameSettings.select(String(id))
		change_scene_to_file("res://src/ui/hero_select.tscn")
		for i in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://" + out + "/select_" + String(id) + ".png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("saved ", path)
	GameSettings.select(keep)
	quit(0)
