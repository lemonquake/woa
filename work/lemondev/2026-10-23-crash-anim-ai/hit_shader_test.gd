extends SceneTree
## Renders HitFx's flare, ring and slash on a grey backdrop to check they draw at all.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 4)
	cam.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.25, 0.25)
	root.add_child(env)
	var fx := Fx.new()
	root.add_child(fx)
	var h := HitFx.new(fx)
	h.flare(Vector3(-1.4, 0, 0), Color(1.0, 0.5, 0.8), 0.5, 10.0)
	h.ring(Vector3(0, 0, 0), Color(1.0, 0.5, 0.8), 0.8, 10.0)
	h._spawn("slash", Vector3(1.4, 0, 0), 0.8, Color(1.0, 0.5, 0.8), 10.0, 0.0)
	for mi in h._live:
		(mi.node as MeshInstance3D).set_instance_shader_parameter("age", 0.25)
	for i in 10:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://work/lemondev/2026-10-23-crash-anim-ai/fx/shader_test.png")
	print("saved")
	quit()
