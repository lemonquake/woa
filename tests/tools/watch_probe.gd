extends SceneTree
## Live probe of an All-Bot match you watch (spectator mode): boots a real match with every hero a bot's, plays a few
## minutes, then checks the Watch panel's hero, camera, sight, orders and plans, that nothing the watcher does reaches
## the simulation, and the Debug panel's Bots commands. Saves captures with --out.
##   godot --path . -s tests/tools/watch_probe.gd -- --watch --bots=5v5 --nolearn [--min=4] [--out=work/shots]
## Prints PASS / FAIL lines and quits.

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var _fails := 0
var _passes := 0
var _out := ""
var _min := 4.0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--min="):
			_min = float(a.substr(6))
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

func _shot(name: String) -> void:
	if _out == "":
		return
	await frames(3)
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name))

func _off_centre(h: SimUnit) -> float:
	var cam: Camera3D = game.camera.cam
	var vs: Vector2 = game.get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(View.to3(h.pos, game.terrain.height_at(h.pos)))
	return sp.distance_to(vs * 0.5)

func _ones(b: PackedByteArray) -> int:
	var n := 0
	for x in b:
		n += x
	return n

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
	await frames(30)
	var w: SimWorld = game.world
	check(bool(game.spectator), "the match is watched (no You slot)")
	check(w.heroes.size() == 10, "ten heroes (%d)" % w.heroes.size())
	check(w.heroes.all(func(h): return not h.player), "no hero is a player's")
	check(w.heroes.all(func(h): return w.bot_for(h.id) != null), "a bot plays every hero")
	check(game.watch_panel != null and game.watch_panel.visible, "the Watch panel is shown")
	check(near_rate(w.xp_rate) and near_rate(w.gold_rate), "150%% experience and gold (%.2f, %.2f)" % [w.xp_rate, w.gold_rate])
	var h0: SimUnit = w.get_unit(game.player_hero_id)
	var g0 := h0.gold()
	check(game.act({"k": "buy", "item": "branch"}) != "", "a shop order from the watcher is refused")
	game.act({"k": "order", "u": h0.id, "o": {"type": SimConst.Order.MOVE, "point": Vector2(0, 0)}})
	check(h0.gold() == g0, "the watcher's orders change nothing")
	# play some minutes (the views and events kept in step)
	var target := maxf(w.time, 0.0) + _min * 60.0
	while w.time < target:
		for i in 30:
			w.step()
		game._drain_events()
		game._sync_views()
		await process_frame
	await frames(20)
	var plans := 0
	for h in w.heroes:
		var b = w.bot_for(h.id)
		if b != null and String(b.plan_text()) != "":
			plans += 1
	check(plans == 10, "every bot says what it is doing (%d)" % plans)
	print("plans: ", ", ".join(w.heroes.map(func(h): return "%s: %s" % [h.def.name, w.bot_for(h.id).plan_text()])))
	# sight: one team, both teams, the whole map
	var n := SimMap.VN * SimMap.VN
	game.vision_mode = 0
	var a0 := _ones(game.fog_bytes())
	game.vision_mode = 1
	var a1 := _ones(game.fog_bytes())
	game.vision_mode = 2
	game.set("_fog_both_tick", -1)
	var both := _ones(game.fog_bytes())
	game.vision_mode = 3
	var all := _ones(game.fog_bytes())
	print("sight cells: Ancient Light %d, Black Sun %d, both %d, whole map %d of %d" % [a0, a1, both, all, n])
	check(both >= maxi(a0, a1) and both <= a0 + a1, "both teams' sight is the union of the two")
	check(all == n, "whole map shows every cell")
	var enemy_hidden := 0
	var shown_all := 0
	for h in w.heroes:
		game.vision_mode = 0
		if h.team == 1 and not game.sees(h):
			enemy_hidden += 1
		game.vision_mode = 3
		if game.sees(h):
			shown_all += 1
	check(shown_all == 10, "whole map shows every hero")
	print("Black Sun heroes hidden from Ancient Light's sight: ", enemy_hidden)
	# Auto camera with both teams' sight
	game.vision_mode = 2
	game.show_orders = 2
	game.show_plans = true
	game.set_cam_mode("auto")
	await frames(90)
	var hw: SimUnit = w.get_unit(game.player_hero_id)
	check(hw != null and _off_centre(hw) < 140.0, "Auto keeps the camera on the watched hero (%.0f px)" % _off_centre(hw))
	await _shot("watch_auto_both.png")
	# Follow another hero, then hero view
	var other: SimUnit = null
	for h in w.heroes:
		if h.team != hw.team and h.alive:
			other = h
			break
	if other != null:
		game.watch(other.id)
		game.set_cam_mode("follow")
		await frames(60)
		check(game.player_hero_id == other.id and game.player_team == other.team, "watching another hero switches the team shown")
		check(_off_centre(other) < 60.0, "Follow hero keeps the camera on it (%.0f px)" % _off_centre(other))
		game.set_cam_mode("hero")
		await frames(30)
		check(game.vision_mode == -1 and game.vis_team() == other.team, "Hero view shows the hero's team's sight")
		game.show_orders = 1
		await _shot("watch_hero_view.png")
		game.set_cam_mode("follow")
		check(game.vision_mode == 2, "leaving Hero view puts back the sight chosen before")
	# a pan by the player frees the camera
	game.camera.user_moved = true
	await frames(3)
	check(game.cam_mode == "free", "panning switches to the Free camera")
	# Debug panel: Bots commands
	var team1 := SimDebug.bot_heroes(w, "team1")
	check(team1.size() == 5 and team1.all(func(h): return h.team == 1), "Black Sun bots picked (%d)" % team1.size())
	var gold_before: Array = team1.map(func(h): return h.gold())
	for h in team1:
		SimDebug.gold(w, h, 1000)
	var ok_gold := true
	for i in team1.size():
		ok_gold = ok_gold and team1[i].gold() - int(gold_before[i]) == 1000
	check(ok_gold, "+1000 gold to every Black Sun bot (not scaled)")
	var all_bots := SimDebug.bot_heroes(w, "all")
	var lv: Array = all_bots.map(func(h): return h.level)
	for h in all_bots:
		SimDebug.level_up(w, h)
	var ok_lv := true
	for i in all_bots.size():
		ok_lv = ok_lv and (all_bots[i].level == mini(int(lv[i]) + 1, C.MAX_LEVEL))
	check(ok_lv, "level up every bot by one")
	var one: SimUnit = all_bots[0]
	check(SimDebug.give_item(w, one, "branch"), "give an item to one bot")
	SimDebug.set_bot_skill(w, one, "unfair")
	check(w.bot_for(one.id).skill == "unfair" and one.gold_mult == 3.0, "set one bot's skill")
	SimDebug.set_bot_still(w, one, true)
	check(w.bot_for(one.id).passive, "one bot stands still")
	SimDebug.set_bot_still(w, one, false)
	game.hud.debug.toggle()
	await frames(40)
	await _shot("watch_debug.png")
	game.hud.debug.toggle()
	print("watch_probe: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func near_rate(r: float) -> bool:
	return absf(r - 1.5) < 0.001
