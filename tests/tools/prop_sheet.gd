extends SceneTree
## Render a contact sheet of prop models in a grid (to choose dressing): writes --out (default work/shots/props.png).
##   godot --path . -s tests/tools/prop_sheet.gd -- --props=kd_tent,campfire,... [--out=...]
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var props := "kd_tent,campfire,kf_fire_pit,banner_torn,bones_scatter,kd_fence,kd_log,kf_crate_a,kf_barrels,kd_fire_basket,kd_stump_cut,kd_lantern_candle,brazier,kd_obelisk,basalt_column,kf_dead_branch"
	var out := "work/shots/props.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--props="):
			props = a.substr(8)
		elif a.begins_with("--out="):
			out = a.substr(6)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	var list := props.split(",")
	var cols := 4
	var cell := 4.0
	for i in list.size():
		var path := "res://assets/props/%s.glb" % list[i]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = (load(path) as PackedScene).instantiate()
		root3.add_child(n)
		var aabb := _aabb(n)
		var s := 2.4 / maxf(0.01, maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)))
		n.scale = Vector3.ONE * s
		n.position = Vector3((i % cols) * cell, -aabb.position.y * s, (i / cols) * cell)
		var l := Label3D.new()
		l.text = "%s (%.1f m)" % [list[i], maxf(aabb.size.x, aabb.size.z)]
		l.font_size = 64
		l.pixel_size = 0.004
		l.position = Vector3((i % cols) * cell, -0.1, (i / cols) * cell + 1.6)
		l.rotation_degrees = Vector3(-60, 0, 0)
		root3.add_child(l)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	floor.position = Vector3(6, 0, 6)
	root3.add_child(floor)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var rows := ceili(list.size() / float(cols))
	cam.position = Vector3((cols - 1) * cell * 0.5, 14.0, (rows - 1) * cell * 0.5 + 10.0)
	cam.look_at(Vector3((cols - 1) * cell * 0.5, 0, (rows - 1) * cell * 0.5 + 0.5))
	cam.fov = 55
	cam.current = true
	for i in 6:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	quit()

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.get_aabb()
		var xf := mi.transform
		var p := mi.get_parent()
		while p != null and p != n and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		b = xf * b
		out = b if first else out.merge(b)
		first = false
	return out
