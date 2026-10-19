extends "res://tests/tools/ranked_probe.gd"
func _run() -> void:
	change_scene_to_file("res://src/ui/ranked_menu.tscn")
	await wait(1.5)
	menu = current_scene
	await click(menu._find_btn)
	var t := 0.0
	while menu.mm.state == "searching" and t < 40.0:
		await wait(0.25)
		t += 0.25
	print("state ", menu.mm.state, " offer ", menu._offer.visible)
	var mcards: Array = find_where(menu._offer, func(n): return n.get("hero") != null and n.get("right") != null, [])
	var c: Control = mcards[6]
	print("card rect ", c.get_global_rect(), " root final ", root.get_final_transform())
	move_to(c.get_global_rect().get_center())
	await wait(0.3)
	print("hovered: ", root.gui_get_hovered_control(), " card vis ", menu._card.visible, " pos ", menu._card.position)
	var d := button_named("Decline")
	print("decline rect ", d.get_global_rect())
	move_to(d.get_global_rect().get_center())
	await wait(0.2)
	print("hovered: ", root.gui_get_hovered_control())
	await click(d)
	await wait(0.3)
	print("state after decline ", menu.mm.state)
	quit()
