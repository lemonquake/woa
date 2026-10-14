extends SceneTree
## Every unit is drawn where the simulation has it: plays a 5 v 5 with the camera parked over the river (the map's
## centre) and checks that no unit view, on or off screen, stands away from its unit (camps and waves spawn off screen).
## Prints PASS / FAIL.
##   godot --path . -s tests/tools/view_place_probe.gd -- --hero=froster --bots=5v5 --autoplay --nolearn [--min=4]

var game: Node

func _init() -> void:
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func _run() -> void:
	var mins := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min="):
			mins = float(a.substr(6))
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null:
			break
	Engine.time_scale = 4.0
	var bad := 0
	var checks := 0
	var worst := 0.0
	while game.world.time < mins * 60.0:
		game.camera.focus(Vector3.ZERO)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw     # sample what was drawn (after Main._process), not mid-frame
		var w: SimWorld = game.world
		for id in game.views:
			var v = game.views[id]
			if not (v is UnitView):
				continue
			var u := w.get_unit(id)
			if u == null or not u.alive or not u.knock.is_empty() or not u.leap.is_empty():
				continue
			var want := View.to3(u.pos, 0.0)
			var d := Vector2(v.position.x - want.x, v.position.z - want.z).length()
			# drawn between its last two ticks (a blink or a Teleport jumps in one tick): either end is right
			var prev := View.to3(v.prev_pos, 0.0)
			d = minf(d, Vector2(v.position.x - prev.x, v.position.z - prev.z).length() + 0.0 if v.prev_pos.distance_to(u.pos) > 200.0 else d)
			checks += 1
			# a moving unit is drawn between its last two ticks: allow a tick of movement at 4x speed
			if d > 2.0:
				bad += 1
				worst = maxf(worst, d)
				if bad <= 5:
					print("misplaced: %s id %d at %s, unit at %s, %.1f m off, offscreen %s" % [u.name, id, v.position, want, d, v.offscreen])
	print("%s: %d unit checks over %s game time, %d misplaced (worst %.1f m)" % ["PASS" if bad == 0 else "FAIL", checks,
		game.world.clock_text(), bad, worst])
	quit(0 if bad == 0 else 1)
