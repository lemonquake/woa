extends SceneTree
## A capture of the Options screen on one tab (run 2026-10-19 d: the Game tab's "Online bot chat").
##   godot --path . -s tests/tools/options_shot.gd -- --out=x.png [--tab=2] [--scroll=600]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var opts := {"out": "work/options.png", "tab": "2", "scroll": "0"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var p := OptionsPanel.new()
	root.add_child(p)
	for i in 10:
		await process_frame
	p._tabs.current_tab = int(opts.tab)
	for i in 5:
		await process_frame
	var page := p._tabs.get_current_tab_control()
	if page is ScrollContainer:
		(page as ScrollContainer).scroll_vertical = int(opts.scroll)
	elif page.get_parent() is ScrollContainer:
		(page.get_parent() as ScrollContainer).scroll_vertical = int(opts.scroll)
	for i in 10:
		await process_frame
	var path := ProjectSettings.globalize_path("res://" + String(opts.out))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	root.get_texture().get_image().save_png(path)
	print("captured ", path)
	quit()
