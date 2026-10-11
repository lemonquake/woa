extends Node3D
## Warriors of Aether: one match. Builds the map and simulation, steps it at 30 Hz in _physics_process, mirrors it
## into views (terrain, foliage, buildings, units, effects, fog of war) and hosts the input controller and HUD.
##
## Capture mode for automated screenshots (window opens, renders, saves, quits):
##   godot --path . -- --capture=work/shots/x.png --t=95 --cam=-1600,-1400 --zoom=1.0 [--autoplay] [--pitch=58]

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var map: SimMap
var world: SimWorld
var terrain: TerrainBuilder
var foliage: Foliage
var atmosphere: Atmosphere
var camera: CameraRig
var fx: Fx
var bars: UnitBars
var input: InputController
var audio: GameAudio
var hud: Control
var views := {}                            # unit id -> UnitView | BuildingView
var player_team := C.DAWN
var player_hero_id := -1
var selected_id := -1
var fog_tex: ImageTexture
var fog_img: Image
var _fog_quad: MeshInstance3D
var args := {}
var _capture_frames := -1

func _ready() -> void:
	_parse_args()
	var t0 := Time.get_ticks_msec()
	map = SimMap.new()
	map.build(1)
	world = SimWorld.new(1, map)
	world.setup_match()
	_spawn_heroes()
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.build()
	terrain = TerrainBuilder.new(map)
	terrain.build(self)
	atmosphere.materials.append(terrain.material)
	foliage = Foliage.new()
	add_child(foliage)
	foliage.build(map, terrain)
	fx = Fx.new()
	fx.game = self
	add_child(fx)
	camera = CameraRig.new()
	add_child(camera)
	camera.height_at = func(p: Vector2) -> float: return terrain.height_at(p)
	camera.follow = func():
		var h := world.get_unit(player_hero_id)
		return View.to3(h.pos, terrain.height_at(h.pos)) if h and h.alive else null
	var hero := world.get_unit(player_hero_id)
	camera.focus(View.to3(hero.pos, terrain.height_at(hero.pos)))
	_build_fog()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	bars = UnitBars.new()
	bars.game = self
	ui.add_child(bars)
	hud = preload("res://src/ui/hud.gd").new()
	hud.set("game", self)
	ui.add_child(hud)
	input = InputController.new()
	input.game = self
	add_child(input)
	audio = GameAudio.new()
	audio.game = self
	add_child(audio)
	selected_id = player_hero_id
	_sync_views()
	print("match ready in %d ms" % (Time.get_ticks_msec() - t0))
	for f in String(args.get("off", "")).split(",", false):
		match f:
			"ssao": atmosphere.env.ssao_enabled = false
			"glow": atmosphere.env.glow_enabled = false
			"fog": atmosphere.env.fog_enabled = false
			"msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"fxaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"shadows": atmosphere.sun.shadow_enabled = false
			"trees", "decor":
				for c in foliage.get_children():
					var mmi := c as MultiMeshInstance3D
					if mmi and ((f == "decor") == (mmi.visibility_range_end > 0.0)):
						mmi.visible = false
			"water": get_node("River").visible = false
			"fow": _fog_quad.visible = false
			"terrain": get_node("Terrain").visible = false
			"units":
				for v in views.values():
					if v is UnitView: v.visible = false
	if args.has("noui"):
		ui.visible = false
		bars.visible = false
		hud.visible = false
	if args.has("capture"):
		_start_capture()
	elif args.has("bench"):
		_start_bench()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"

## The player's Galewarden (Dawn) and the bot's (Dusk). Looks and outfits use the customisable hero body.
func _spawn_heroes() -> void:
	# the hero built in the Hero Creator (or the default Galewarden)
	var mine: Dictionary = GameSettings.load_hero() if not args.has("capture") and not args.has("bench") else GameSettings.default_hero()
	var p := world.spawn_hero("galewarden", C.DAWN, mine.duplicate(true))
	p.player = true
	player_hero_id = p.id
	var blook := HeroLook.preset("shade")
	var b := world.spawn_hero("galewarden", C.DUSK, {
		"display_name": "Bot Gerald", "look": blook,
		"outfit": {"inner_garment": "chain_shirt", "armor": "tc_nightstalker_leathers", "leggings": "nightweave_leggings",
			"boots": "soft_boot", "gloves": "runed_glove", "helm": "linen_hood"},
		"dyes": {"armor": {"cloth": "3a1020", "leather": "201014"}},
	})
	world.bots.append(SimBot.new(world, b.id, "mid", "Bot Gerald"))
	if args.has("autoplay"):
		world.bots.append(SimBot.new(world, p.id, "mid", "Autoplay"))

# ---- Simulation loop -----------------------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	if _capture_frames >= 0:
		return
	_step()

func _step() -> void:
	var t := Time.get_ticks_usec()
	world.step()
	t = _tm("sim", t)
	_drain_events()
	_sync_views()
	_tm("sync", t)

func _sync_views() -> void:
	for u in world.units:
		if not views.has(u.id):
			_make_view(u)
	for id in views.keys():
		var v = views[id]
		var u := world.get_unit(id)
		if u == null:
			v.queue_free()
			views.erase(id)
			continue
		if v is UnitView:
			v.tick(u)
		else:
			v.update_state(u)

func _make_view(u: SimUnit) -> void:
	if u.is_building():
		var b := BuildingView.new()
		add_child(b)
		b.setup(u, terrain)
		views[u.id] = b
	elif u.kind == K.WARD:
		var wv := UnitView.new()
		add_child(wv)
		views[u.id] = wv
		wv.uid = u.id
		wv.terrain = terrain
		wv.prev_pos = u.pos
		wv.cur_pos = u.pos
		var eye := fx._sphere(0.16, fx._glow(Color(1.0, 0.85, 0.3) if u.team == 0 else Color(1.0, 0.3, 0.3), 4.0))
		eye.position.y = 1.2
		wv.add_child(eye)
	else:
		var v := UnitView.new()
		add_child(v)
		v.setup(u, terrain)
		views[u.id] = v

func _drain_events() -> void:
	for e in world.events:
		if audio and _capture_frames < 0:
			audio.event(e, world)
		match e.t:
			"attack_start":
				var v = views.get(e.u)
				if v is UnitView:
					v.on_attack_start(float(e.point))
			"attack_cancel":
				var v2 = views.get(e.u)
				if v2 is UnitView:
					v2.on_attack_cancel()
			"projectile":
				fx.projectile(e, world)
			"projectile_end":
				fx.projectile_end(e)
			"last_hit":
				if e.u == player_hero_id:
					var t := world.get_unit(e.target)
					if t:
						bars.popup("+%d" % int(e.gold), _head(t.pos, 1.6), Color(1.0, 0.82, 0.2), 20)
			"deny":
				var t2 := world.get_unit(e.target)
				if t2:
					bars.popup("!", _head(t2.pos, 2.0), Color(1.0, 1.0, 1.0), 26, 0.6)
			"miss":
				var t3 := world.get_unit(e.target)
				if t3 and (e.u == player_hero_id or t3.id == player_hero_id):
					bars.popup("miss", _head(t3.pos, 2.2), Color(0.85, 0.85, 0.9), 15)
			"level_up":
				var h := world.get_unit(e.u)
				if h:
					fx.level_up(View.to3(h.pos, terrain.height_at(h.pos)))
			"effect_move":
				fx.gale_move(e.pos)
			"tp_start":
				var tu := world.get_unit(e.u)
				if tu and (tu.team == player_team or world.vision.sees(player_team, tu)):
					fx.tp_start(e.u, View.to3(tu.pos, terrain.height_at(tu.pos)), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
				elif tu:
					# enemies still see where a Town Portal is going to land
					fx.tp_start(e.u, Vector3(0, -50, 0), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
			"tp_end":
				fx.tp_end(e.u, true)
				var v3 = views.get(e.u)
				if v3 is UnitView:
					v3.prev_pos = e.pos
					v3.cur_pos = e.pos
			"tp_cancel":
				fx.tp_end(e.u)
			"volley":
				fx.volley(e.pos, float(e.radius))
			"tree":
				foliage.set_tree_alive(int(e.i), bool(e.alive))
			"hero_kill":
				if hud and hud.has_method("on_kill"):
					hud.on_kill(e)
			"error":
				if e.u == player_hero_id and hud and hud.has_method("error"):
					hud.error(String(e.msg))
	world.events.clear()

func _head(p: Vector2, extra: float) -> Vector3:
	return View.to3(p, terrain.height_at(p)) + Vector3(0, extra, 0)

func _tm(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if _bench_until > 0.0:
		_bench_acc[key] = _bench_acc.get(key, 0.0) + (t1 - t0) / 1000.0
	return t1

func _process(dt: float) -> void:
	var _t := Time.get_ticks_usec()
	var alpha := Engine.get_physics_interpolation_fraction()
	if _capture_frames >= 0:
		alpha = 1.0
	for v in views.values():
		if v is UnitView:
			v.frame(alpha, dt, camera.cam)
			var u := world.get_unit(v.uid)
			if u:
				v.visible = u.team == player_team or world.vision.sees(player_team, u) or not u.alive and false
				if u.team != player_team and not u.alive:
					v.visible = world.vision.cell_visible(player_team, u.pos)
	_t = _tm("views", _t)
	fx.frame(world, alpha, dt)
	_t = _tm("fx", _t)
	if _bench_until > 0.0:
		_bench_frame(dt)
	atmosphere.update(world.is_night(), dt if _capture_frames < 0 else 10.0)
	_update_fog(dt)
	_t = _tm("fog", _t)
	for id in views:
		var v = views[id]
		if v is UnitView:
			v.set_selected(id == selected_id, Color(0.3, 1.0, 0.4, 0.9) if world.get_unit(id) and world.get_unit(id).team == player_team else Color(1.0, 0.3, 0.25, 0.9))
	if _capture_frames >= 0:
		_capture_frames += 1
		if _capture_frames == int(args.get("frames", "45")):
			_save_capture()

# ---- Fog of war -------------------------------------------------------------------------------------------------------

func _build_fog() -> void:
	var n := SimMap.VN
	fog_img = Image.create(n, n, false, Image.FORMAT_L8)
	fog_tex = ImageTexture.create_from_image(fog_img)
	_fog_prev = ImageTexture.create_from_image(fog_img)
	_fog_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_fog_quad.mesh = q
	_fog_quad.extra_cull_margin = 16384.0
	_fog_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = preload("res://src/game/fog_of_war.gdshader")
	_fog_mat.set_shader_parameter("fog_tex", fog_tex)
	_fog_mat.set_shader_parameter("fog_prev", _fog_prev)
	_fog_mat.set_shader_parameter("map_half", View.MAP_HALF_M)
	_fog_mat.render_priority = 100
	_fog_quad.material_override = _fog_mat
	camera.cam.add_child(_fog_quad)
	_fog_quad.position = Vector3(0, 0, -1)

var _fog_prev: ImageTexture
var _fog_mat: ShaderMaterial
var _fog_tick := -1
var _fog_blend := 1.0
var _fog_prev_img: Image

## The vision grid (0/1 bytes) goes to the GPU as-is whenever it changes; the shader scales it and cross-fades from
## the previous grid, so cells fade in and out smoothly without a per-cell loop here.
func _update_fog(dt: float) -> void:
	var vtick: int = world.tick / C.VISION_UPDATE_TICKS
	if vtick != _fog_tick:
		_fog_tick = vtick
		if _fog_prev_img == null:
			_fog_prev_img = Image.create(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8)
		_fog_prev_img.copy_from(fog_img)
		_fog_prev.update(_fog_prev_img)
		var n := SimMap.VN
		fog_img.set_data(n, n, false, Image.FORMAT_L8, world.vision.visible[player_team])
		fog_tex.update(fog_img)
		_fog_blend = 0.0 if _capture_frames < 0 else 1.0
	_fog_blend = minf(1.0, _fog_blend + dt / 0.25)
	_fog_mat.set_shader_parameter("blend", _fog_blend)

# ---- Benchmark ------------------------------------------------------------------------------------------------------

var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_until := -1.0
var _bench_warm := 0.0
var _bench_acc := {}

## Fast-forward to --t, then play normally for --bench seconds, following the player hero, and report frame times.
func _start_bench() -> void:
	var t := float(args.get("t", "120"))
	camera.edge_pan_enabled = false
	while world.time < t:
		world.step()
		_drain_events()
		if world.tick % 30 == 0:
			_sync_views()
	_sync_views()
	_bench_warm = 3.0
	_bench_until = float(args.bench)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _bench_frame(dt: float) -> void:
	var h := world.get_unit(player_hero_id)
	if h:
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))
	if _bench_warm > 0.0:
		_bench_warm -= dt
		return
	_bench_frames.append(dt * 1000.0)
	var vrid := get_viewport().get_viewport_rid()
	_bench_acc["gpu"] = _bench_acc.get("gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_bench_acc["rcpu"] = _bench_acc.get("rcpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vrid)
	_bench_acc["proc"] = _bench_acc.get("proc", 0.0) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_bench_acc["phys"] = _bench_acc.get("phys", 0.0) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_bench_acc["draws"] = _bench_acc.get("draws", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_acc["prims"] = _bench_acc.get("prims", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_bench_until -= dt
	if _bench_until <= 0.0:
		var a := Array(_bench_frames)
		a.sort()
		var n := a.size()
		var avg := 0.0
		for v in a:
			avg += v
		avg /= n
		var line := "BENCH frames %d avg %.2f ms (%.0f fps) p50 %.2f p95 %.2f p99 %.2f max %.2f over16.7 %d units %d" % [
			n, avg, 1000.0 / avg, a[n / 2], a[int(n * 0.95)], a[int(n * 0.99)], a[n - 1], a.filter(func(v): return v > 16.7).size(), world.units.size()]
		var parts := []
		for k in _bench_acc:
			parts.append("%s %.2f" % [k, _bench_acc[k] / n])
		line += "
  per-frame means: " + ", ".join(parts)
		print(line)
		var f := FileAccess.open("res://work/bench.txt", FileAccess.WRITE)
		f.store_line(line)
		get_tree().quit()

# ---- Capture ---------------------------------------------------------------------------------------------------------

func _start_capture() -> void:
	var t := float(args.get("t", "5"))
	camera.edge_pan_enabled = false
	while world.time < t:
		world.step()
		_drain_events()
		if world.tick % 30 == 0:
			_sync_views()
	_sync_views()
	for v in views.values():
		if v is UnitView:
			v.tick(world.get_unit(v.uid))
	if args.has("cam"):
		var c := String(args.cam).split(",")
		var p := Vector2(float(c[0]), float(c[1]))
		camera.focus(View.to3(p, terrain.height_at(p)))
	else:
		var h := world.get_unit(player_hero_id)
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))
	if args.has("zoom"):
		camera.zoom = float(args.zoom)
		camera._zoom_goal = camera.zoom
	if args.has("pitch"):
		camera.pitch_deg = float(args.pitch)
	if args.has("dist"):
		camera.distance = float(args.dist)
	camera._apply()
	if args.has("select"):
		selected_id = int(args.select)
	_capture_frames = 0

func _save_capture() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := String(args.capture)
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("captured ", path, " at game time ", world.clock_text())
	get_tree().quit()
