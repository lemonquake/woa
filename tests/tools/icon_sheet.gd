extends SceneTree
## Renders item icons into a contact sheet (headless): each icon at 96 px and at 44 px (the shop and backpack size),
## old and new side by side when --old is given.
##   godot --headless --path . -s tests/tools/icon_sheet.gd -- --dir=assets/ui/items/gen --out=work/icons.png [--old]

func _init() -> void:
	var dir := "assets/ui/items/gen"
	var out := "work/icons.png"
	var old := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--old":
			old = true
	var files: Array = []
	for f in DirAccess.get_files_at("res://" + dir):
		if f.ends_with(".svg"):
			files.append(f)
	files.sort()
	var cols := 8
	var cw := 230 if old else 160
	var ch := 130
	var rows := ceili(files.size() / float(cols))
	var sheet := Image.create(cols * cw, rows * ch, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.11))
	var mapping := {}
	if old:
		# the icon each item used before (UiKit.ITEM_ICONS has the new paths now; the old map is in a text file)
		var mf := FileAccess.open("res://work/lemondev/2026-10-15b-ui-items-heroes/old_icons.txt", FileAccess.READ)
		if mf:
			for line in mf.get_as_text().split("\n"):
				var p := line.split("=")
				if p.size() == 2:
					mapping[p[0].strip_edges()] = p[1].strip_edges()
	for i in files.size():
		var f: String = files[i]
		var x := (i % cols) * cw + 6
		var y := (i / cols) * ch + 6
		var x2 := x
		if old:
			var oid := f.get_basename()
			if mapping.has(oid):
				var oi := _load("res://assets/ui/%s.svg" % mapping[oid])
				if oi:
					oi.resize(64, 64, Image.INTERPOLATE_LANCZOS)
					sheet.blend_rect(oi, Rect2i(0, 0, 64, 64), Vector2i(x, y + 16))
			x2 = x + 70
		var img := _load("res://" + dir + "/" + f)
		if img == null:
			continue
		var big := img.duplicate()
		big.resize(96, 96, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(big, Rect2i(0, 0, 96, 96), Vector2i(x2, y))
		var small := img.duplicate()
		small.resize(44, 44, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(small, Rect2i(0, 0, 44, 44), Vector2i(x2 + 100, y + 4))
	sheet.save_png(ProjectSettings.globalize_path("res://" + out))
	print("sheet: %d icons -> %s" % [files.size(), out])
	print("order: ", " ".join(files.map(func(s): return s.get_basename())))
	quit(0)

func _load(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var img := Image.new()
	if img.load_svg_from_string(f.get_as_text(), 1.0) != OK:
		return null
	return img
