extends SceneTree
## Fire look check (needs a window and the GPU): renders FireFx's flames, burst, burning ground and a fireball on a
## dark plane under the match's glow settings, and saves frames.
##   godot --path . -s tests/tools/fire_preview.gd -- --out=work/shots/fire [--frames=40,70]

var _out := "work/shots/fire"
var _frames: Array = [45, 90]
var _n := 0
var fire: FireFx
var _ball: Node3D
var _t := 0.0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = Array(a.substr(9).split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out))
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.6)
	env.ambient_light_color = Color(0.3, 0.32, 0.4)
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.25
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.2, 0.17)
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4.2, 6.5), Vector3(0, 0.9, 0), Vector3.UP)
	fire = FireFx.new()
	world.add_child(fire)
	# a standing fire (a burning unit), a burst, burning ground, a fireball and spirit flames
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.7
	body.mesh = cap
	world.add_child(body)
	body.position = Vector3(-4.5, 0.85, 0)
	var f := FireFx.flames(0.32, 1.1, 50.0, 0.8, 1.4)
	world.add_child(f)
	f.position = Vector3(-4.5, 0.2, 0)
	var e := FireFx.embers(0.4, 14.0)
	world.add_child(e)
	e.position = Vector3(-4.5, 0.6, 0)
	var s := FireFx.smoke(0.3, 3.0)
	world.add_child(s)
	s.position = Vector3(-4.5, 1.6, 0)
	fire.ground_fire(Vector3(0, 0.05, 0), 2.0, 99.0)
	_ball = FireFx.fireball(1.4)
	world.add_child(_ball)
	_ball.position = Vector3(4.0, 1.5, 0)
	var sp := FireFx.flames(0.1, 0.4, 40.0, 0.5, 0.9, "spirit")
	world.add_child(sp)
	sp.position = Vector3(4.0, 0.6, 2.5)

func _process(dt: float) -> bool:
	_n += 1
	_t += dt
	if _ball:
		_ball.position = Vector3(4.0 + sin(_t * 3.0) * 1.5, 1.5, cos(_t * 3.0) * 1.5)
	if _n == 20:
		fire.burst(Vector3(-2.0, 0.6, 2.5), 1.0)
	if _n in _frames:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://%s/fire_%d.png" % [_out, _n]))
		print("saved fire_%d" % _n)
	return _n > int(_frames.max())
