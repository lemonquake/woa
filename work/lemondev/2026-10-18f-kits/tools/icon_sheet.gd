extends SceneTree
## Renders SVG icons into one PNG with Godot's own SVG loader (the one the game uses).
func _init() -> void:
	var ids := OS.get_cmdline_user_args()[0].split(",")
	var out := OS.get_cmdline_user_args()[1]
	var cols := 6
	var cell := 136
	var rows := int(ceil(ids.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.17))
	for i in ids.size():
		var img := Image.new()
		var err := img.load_svg_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/skills/gen/%s.svg" % ids[i]), 1.0)
		if err != OK:
			print("fail ", ids[i])
			continue
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i((i % cols) * cell + 4, (i / cols) * cell + 4))
	sheet.save_png(out)
	quit()
