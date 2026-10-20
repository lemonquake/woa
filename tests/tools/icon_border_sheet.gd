extends SceneTree
## Every border pack drawn by the game (IconBorder) round real skill and item icons at the sizes the screens use, in an
## offscreen viewport at 1080p or 4K scale, saved as one picture (for checking a new or changed pack).
##   godot --path . -s tests/tools/icon_border_sheet.gd -- --out=x.png [--scale=2]

const U = preload("res://src/ui/ui_kit.gd")

func _init() -> void:
	var out := "work/shots/icon_borders.png"
	var k := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--scale="):
			k = float(a.substr(8))
	var ids := IconBorder.ids()
	var sizes := [22, 32, 44, 60, 74]
	var vp := SubViewport.new()
	vp.size = Vector2i(Vector2(80 + 5 * 3 * 96, 50 + ids.size() * 120) * k)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var c := Control.new()
	c.scale = Vector2(k, k)
	c.size = Vector2(vp.size) / k
	vp.add_child(c)
	var samples := [["skill", U.ability_icon("chomp")], ["passive", U.ability_icon("blubber")], ["item", U.item_icon("battle_armor")]]
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.07, 0.08, 0.11))
		for pi in ids.size():
			Options.set_value("icon_border", String(ids[pi]))
			var y := 40.0 + pi * 120.0
			U.text(c, IconBorder.pack_name(String(ids[pi])), Vector2(10, y + 50), 14, U.GOLD, "bold")
			for ki in samples.size():
				for si in sizes.size():
					var s: float = sizes[si]
					var x := 80.0 + (ki * sizes.size() + si) * 96.0
					if samples[ki][0] == "item":
						IconBorder.draw_item(c, samples[ki][1], Rect2(x, y, s, s * 0.76))
					else:
						IconBorder.draw_icon(c, samples[ki][1], Rect2(x, y, s, s), samples[ki][0])
				U.text(c, String(samples[ki][0]), Vector2(80.0 + ki * sizes.size() * 96.0, 24), 14, U.TEXT, "bold"))
	_save.call_deferred(vp, out)

func _save(vp: SubViewport, out: String) -> void:
	for i in 6:
		await process_frame
	Options.set_value("icon_border", "default")
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
