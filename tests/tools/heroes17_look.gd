extends SceneTree
## Run 2026-10-17 e in a real match window: a hero with one of the new bodies (tools/blender/hero_body.py) standing,
## moving and attacking in the field, close up and at the game's camera distance, with captures.
##   godot --path . -s tests/tools/heroes17_look.gd -- --hero=azrin --out=work/lemondev/2026-10-17e-hero-models/shots
## --model=hero_ghorman draws the hero with another catalog model (a body whose kit is not in the game yet).
## Staged on open ground at (-900, -2900), fog lifted, bots off.

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const SPOT := Vector2(-900, -2900)

var game: Node
var out := "work/lemondev/2026-10-17e-hero-models/shots"
var hero_id := "azrin"
var model_key := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--hero="):
			hero_id = a.substr(7)
		if a.begins_with("--model="):
			model_key = a.substr(8)
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var who := model_key.trim_prefix("hero_") if model_key != "" else hero_id
	var path := ProjectSettings.globalize_path("res://" + out + "/" + who + "_" + name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path)

func sim_wait(w: SimWorld, secs: float) -> void:
	var until := w.time + secs
	var t0 := Time.get_ticks_msec()
	while w.time < until and Time.get_ticks_msec() - t0 < 20000:
		await process_frame

func look(p: Vector2, zoom := -1.0) -> void:
	game.camera.focus(View.to3(p, game.terrain.height_at(p)))
	if zoom > 0.0 and game.camera.get("zoom") != null:
		game.camera.zoom = zoom

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(1)
			return
	await frames(30)
	var w: SimWorld = game.world
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	for eh in w.heroes:
		if eh.team != h.team:
			eh.pos = w.map.fountains[eh.team]
			w.orders.clear(eh)
	w.vision.reveal_all = true
	if model_key != "":
		h.def = h.def.duplicate()
		h.def["model"] = model_key
		game.views[h.id].queue_free()
		game.views.erase(h.id)
		game._make_view(h)
	SimDebug.force_start(w)
	SimDebug.teleport(w, h, SPOT)
	h.facing = PI * 0.5
	w.orders.clear(h)
	var z0 = game.camera.get("zoom")
	look(SPOT, 0.35)
	await sim_wait(w, 1.0)
	await shot("idle_close")
	# moving across the view
	w.command(h.id, {"type": O.MOVE, "point": SPOT + Vector2(600, 0)})
	await sim_wait(w, 0.5)
	look(h.pos, 0.35)
	await frames(2)
	await shot("move_close")
	await sim_wait(w, 0.4)
	look(h.pos, 0.35)
	await frames(2)
	await shot("move_close2")
	# a turn while moving (banking for the gliders)
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(0, 600)})
	await sim_wait(w, 0.25)
	look(h.pos, 0.35)
	await frames(2)
	await shot("turn_close")
	w.orders.clear(h)
	SimDebug.teleport(w, h, SPOT)
	# attacking a training dummy
	var d := w.spawn("strider", C.DUSK, SPOT + Vector2(140 if not ("range" in h.def and float(h.def.get("range", 150)) > 300) else 450, 0))
	d.def = d.def.duplicate()
	d.def.hp = 20000.0
	d.def["can_attack"] = false
	d.refresh_stats()
	d.hp = d.max_hp
	d.order = O.HOLD
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": d.id})
	look(SPOT + Vector2(80, 0), 0.4)
	for k in 3:
		await sim_wait(w, 0.45)
		look(SPOT + Vector2(80, 0), 0.4)
		await frames(1)
		await shot("attack_%d" % k)
	w.orders.clear(h)
	# the game's own camera distance
	if z0 != null:
		look(SPOT, float(z0))
	await sim_wait(w, 0.6)
	await shot("game_view")
	quit(0)
