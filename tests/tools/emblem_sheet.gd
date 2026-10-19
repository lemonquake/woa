extends SceneTree
## The twelve rank emblems side by side (run 2026-10-19 b): godot --path . -s tests/tools/emblem_sheet.gd --
## [--out=work/shots/emblems.png] [--px=300] [--stars=3] [--yaw=0.3] [--tiers=0,5,11]

func _init() -> void:
	var out := "work/shots/emblems.png"
	var px := 300
	var st := 3
	var yaw := 0.0
	var tiers: Array = range(12)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--px="):
			px = int(a.substr(5))
		elif a.begins_with("--stars="):
			st = int(a.substr(8))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--tiers="):
			tiers = Array(a.substr(8).split(",")).map(func(x): return int(x))
	var cols := mini(6, tiers.size())
	var rows := int(ceil(float(tiers.size()) / float(cols)))
	root.size = Vector2i(cols * px, rows * (px + 30))
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1)
	bg.size = Vector2(root.size)
	root.add_child(bg)
	for i in tiers.size():
		var t: int = tiers[i]
		var c := SubViewportContainer.new()
		c.position = Vector2((i % cols) * px, (i / cols) * (px + 30))
		c.size = Vector2(px, px)
		c.stretch = true
		root.add_child(c)
		var vp := RankEmblem.stage(t, st if t < 10 else 0, px, true)
		c.add_child(vp)
		(vp.get_node("Emblem") as Node3D).rotation = Vector3(0.05, yaw, 0)
		var l := Label.new()
		l.text = Ranked.tier_name(t)
		l.position = c.position + Vector2(8, px + 2)
		root.add_child(l)
	for f in 40:
		await process_frame
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path)
	quit()
