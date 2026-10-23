extends SceneTree
## Hit-effect captures (run 2026-10-23): a real match in a window; your hero (level 18) keeps attacking an enemy hero on
## open ground, both kept alive, the camera on them; saves frames every few frames once the fighting has begun.
##   godot --path . -s tests/tools/fx_probe.gd -- --hero=dracoxinia --foe=ezee --out=dir [--n=12] [--every=4]
##     [--zoom=0.42] [--spot=-2600,-2400] [--direct] (--direct: no fighting; every 24 frames a hero blow, a crit and an
##     impact are fired straight at the enemy so their look can be judged frame by frame)

const C = preload("res://src/sim/sim_const.gd")

var _out := "work/fx"
var _n := 12
var _every := 4
var _zoom := 0.42
var _spot := Vector2(-2600, -2400)
var _direct := false

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--n="):
			_n = int(a.substr(4))
		elif a.begins_with("--every="):
			_every = int(a.substr(8))
		elif a.begins_with("--zoom="):
			_zoom = float(a.substr(7))
		elif a.begins_with("--spot="):
			var p := a.substr(7).split(",")
			_spot = Vector2(float(p[0]), float(p[1]))
		elif a == "--direct":
			_direct = true
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func _run() -> void:
	var game: Node = null
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null:
			break
	DirAccess.make_dir_recursive_absolute(_out)
	var w: SimWorld = game.world
	var me: SimUnit = w.get_unit(game.player_hero_id)
	var foe: SimUnit = null
	for h in w.heroes:
		if h.team != me.team:
			foe = h
	for b in w.bots.duplicate():
		w.bots.erase(b)
	w.time = maxf(w.time, 95.0)
	w.combat.give_xp(me, float(C.XP_TABLE[17]) - me.xp)
	me.refresh_stats()
	me.pos = _spot
	foe.pos = _spot + Vector2(150, 40)
	w.orders.clear(me)
	w.orders.clear(foe)
	game.camera.zoom = _zoom
	game.camera._zoom_goal = _zoom
	var saved := 0
	var f := 0
	# saving a picture takes about a tenth of a second, longer than a hit lasts: slow the game down so the saved frames
	# land inside the blows
	Engine.time_scale = 0.1
	while saved < _n:
		await process_frame
		f += 1
		foe.hp = foe.max_hp
		me.hp = me.max_hp
		if _direct:
			w.orders.clear(me)
			if f % 24 == 0 and f > 60:
				var k := (f / 24) % 3
				if k == 2:
					game.fx.impact(game.fx._chest(foe.id, 0.55), Color(1.0, 0.85, 0.5), 0.4)
				else:
					game.fx.melee_hit(me, foe, 80.0, k == 1)
		elif me.order != C.Order.ATTACK_UNIT:
			game.order(me.id, {"type": C.Order.ATTACK_UNIT, "target": foe.id})
		var mid := me.pos.lerp(foe.pos, 0.5)
		game.camera.focus(View.to3(mid, game.terrain.height_at(mid)))
		if f > 200 and f % _every == 0:
			var img := root.get_texture().get_image()
			img.save_png(_out.path_join("f_%03d.png" % f))
			saved += 1
	quit(0)
