extends SceneTree
## Right-click a leaderboard row and report the player menu (debug for the live probe).
var menu: Node

func _init() -> void:
	OS.set_environment("WOA_RANKED_FILE", "user://cap_after.json")
	change_scene_to_file("res://src/ui/ranked_menu.tscn")
	await process_frame
	await process_frame
	for i in 30:
		await process_frame
	menu = current_scene
	menu._show_tab("leaderboard")
	for i in 10:
		await process_frame
	var rows: Array = []
	_find(menu._board_list, rows)
	var c: Vector2 = (rows[5] as Control).get_global_rect().get_center()
	print("row centre ", c, " final ", root.get_final_transform(), " vp ", root.get_visible_rect())
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = root.get_final_transform() * c
		ev.global_position = ev.position
		root.push_input(ev)
		await process_frame
	for i in 5:
		await process_frame
	for m in get_nodes_in_group("player_menu"):
		var pm = m.get_child(0)
		print("menu ", pm, " panel ", pm._panel, " size ", pm.size, " visible ", pm.is_visible_in_tree(), " items ", pm.items.size())
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://work/lemondev/2026-10-20-profile/ui/menu_probe.png"))
	quit()

func _find(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch.get("pinned") != null:
			out.append(ch)
		_find(ch, out)
