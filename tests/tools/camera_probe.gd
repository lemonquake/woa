extends SceneTree
## Live camera probe: boots a real match and checks that the camera starts centred on the player's hero, and that it
## centres on the hero again when the hero respawns (Options "Center camera on respawn", on by default).
##   godot --path . -s tests/tools/camera_probe.gd -- [--out=work/shots]
## Prints PASS / FAIL lines and quits.

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var _fails := 0
var _passes := 0
var _out := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS ", msg)
	else:
		_fails += 1
		print("FAIL ", msg)

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Distance in pixels from the screen centre (of the area above the bottom HUD) to the hero's feet.
func _off_centre(h: SimUnit) -> float:
	var cam: Camera3D = game.camera.cam
	var vs: Vector2 = game.get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(View.to3(h.pos, game.terrain.height_at(h.pos)))
	return sp.distance_to(vs * 0.5)

func _shot(name: String) -> void:
	if _out == "":
		return
	await frames(2)
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name))

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.input != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("FAIL boot timeout")
			quit(1)
			return
	# the loading screen closes a few frames after boot: measure once the match is shown
	await frames(30)
	var w: SimWorld = game.world
	var h: SimUnit = w.get_unit(game.player_hero_id)
	var vs: Vector2 = game.get_viewport().get_visible_rect().size
	var off := _off_centre(h)
	print("start: hero at ", h.pos, " off centre ", snappedf(off, 0.1), " px of ", vs)
	check(off < vs.y * 0.05, "camera starts centred on the hero (%.0f px off)" % off)
	await _shot("camera_start.png")
	# move the camera away, kill the hero, let it respawn
	game.camera.focus(View.to3(Vector2(3000, 3000), game.terrain.height_at(Vector2(3000, 3000))))
	w.time = maxf(w.time, 10.0)
	w.combat.kill(h, null)
	h.respawn_at = w.time + 0.5
	t0 = Time.get_ticks_msec()
	while not h.alive and Time.get_ticks_msec() - t0 < 10000:
		await physics_frame
	await frames(10)
	off = _off_centre(h)
	check(h.alive, "hero respawned")
	check(off < vs.y * 0.05, "camera centres on the hero at respawn (%.0f px off)" % off)
	await _shot("camera_respawn.png")
	# the option off: the camera stays where it was
	Options.set_value("center_on_respawn", false)
	game.camera.focus(View.to3(Vector2(3000, 3000), game.terrain.height_at(Vector2(3000, 3000))))
	w.combat.kill(h, null)
	h.respawn_at = w.time + 0.5
	t0 = Time.get_ticks_msec()
	while not h.alive and Time.get_ticks_msec() - t0 < 10000:
		await physics_frame
	await frames(10)
	off = _off_centre(h)
	check(off > vs.y * 0.2, "option off: the camera stays put at respawn (%.0f px off)" % off)
	Options.set_value("center_on_respawn", true)
	print("camera probe: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
