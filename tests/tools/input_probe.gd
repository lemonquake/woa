extends SceneTree
## Live input probe: boots a real match (window, HUD, input controller) and drives the hero through the same calls a
## key press or click makes, then checks the simulation. Prints PASS / FAIL lines and quits.
##   godot --path . -s tests/tools/input_probe.gd -- --hero=sludge --lvl=18 --nobot
## Checks every active ability of the chosen hero against an enemy hero placed beside it.

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var _fails := 0
var _passes := 0

func _init() -> void:
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
		await physics_frame

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
	await frames(20)
	var w: SimWorld = game.world
	var h: SimUnit = w.get_unit(game.player_hero_id)
	var foe: SimUnit = null
	for u in w.heroes:
		if u.team != h.team:
			foe = u
	# stage: open ground near the middle, foe 150 away, both full, the clock past the horn
	w.time = maxf(w.time, 1.0)
	w.combat.give_xp(h, float(C.XP_TABLE[17]) - h.xp)
	for aid in h.abilities:
		var ad := SimData.ability(aid)
		h.ability_level[aid] = (ad.required_level as Array).size() if ad.has("required_level") else int(ad.max_level)
	h.ability_points = 0
	h.refresh_stats()
	var spot := Vector2(-600, -600)
	h.pos = spot
	foe.pos = spot + Vector2(150, 0)
	w.orders.clear(h)
	w.orders.clear(foe)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	h.mana = h.max_mana
	foe.hp = foe.max_hp
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(10)
	var inp: InputController = game.input
	print("hero ", h.def.id, " level ", h.level, " abilities ", h.ability_level)
	for i in h.abilities.size():
		var aid: String = h.abilities[i]
		var a := SimData.ability(aid)
		if String(a.behavior) == "passive" or h.ability_level_of(aid) <= 0:
			continue
		h.mana = h.max_mana
		h.ability_ready[aid] = C.LONG_AGO
		h.channel = {}
		w.orders.clear(h)
		if not foe.alive:
			w.respawn(foe)
		w.orders.clear(foe)
		foe.modifiers.clear()
		foe.pos = h.pos + Vector2(150, 0)
		foe.hp = foe.max_hp
		foe.refresh_stats()
		await frames(3)
		var mana0 := h.mana
		var events_before := w.events.size()
		inp._action(Keybinds.slot_action(i, h.abilities.size()), h)
		var beh := String(a.behavior)
		if beh in ["unit", "point", "autocast_attack"]:
			check(inp.targeting == aid, "%s: key starts targeting (targeting=%s)" % [aid, inp.targeting])
			await process_frame
			var aim: SimUnit = h if String(a.get("target_team", "enemy")) == "ally" else foe
			var sp: Vector2 = game.camera.cam.unproject_position(View.to3(aim.pos, game.terrain.height_at(aim.pos)) + Vector3(0, 0.9, 0))
			print("  foe on screen at ", sp, " pick=", inp.pick(sp), " foe id ", foe.id)
			inp._left_click(sp, false)
			check(inp.targeting == "", "%s: click on the enemy ends targeting" % aid)
		await frames(45)
		var fired := false
		match aid:
			"stench":
				fired = bool(h.toggles.get("stench", false))
				check(fired, "stench: W turns it on")
				var hp0 := foe.hp
				await frames(30)
				check(foe.hp < hp0, "stench: damages the enemy beside him (%.0f -> %.0f)" % [hp0, foe.hp])
				inp._action(Keybinds.slot_action(i, h.abilities.size()), h)
				await frames(3)
				check(not bool(h.toggles.get("stench", false)), "stench: W again turns it off")
				continue
			"soul_tap":
				fired = bool(h.toggles.get("soul_tap", false))
				check(fired, "soul_tap: Q turns it on")
				inp._action(Keybinds.slot_action(i, h.abilities.size()), h)
				await frames(3)
				check(not bool(h.toggles.get("soul_tap", false)), "soul_tap: Q again turns it off")
				continue
			"blubber":
				fired = not h.get_modifier("blubber").is_empty()
				check(fired, "blubber: E puts the modifier on")
			"chomp":
				fired = not h.channel.is_empty() and String(h.channel.ability) == "chomp" or h.mana < mana0
				check(fired, "chomp: R + click starts the channel (channel=%s)" % str(h.channel))
			_:
				fired = h.mana < mana0 or w.abilities.cooldown_left(h, aid) > 0.0
				check(fired, "%s: cast (mana %.0f -> %.0f, cd %.1f)" % [aid, mana0, h.mana, w.abilities.cooldown_left(h, aid)])
		var errs: Array = []
		for k in range(events_before, w.events.size()):
			if String(w.events[k].get("t", "")) == "error":
				errs.append(w.events[k].msg)
		if not errs.is_empty():
			print("  errors: ", errs)
	await _quick_cast_check(h, foe)
	await _grip_empty_check(h, foe)
	await _self_cast_check(h)
	await _tp_double_tap_check(h)
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

## Quick cast (Options > Game, not saved here): with the mouse over the enemy, the key alone casts the first point or
## unit spell at it, without a click.
func _quick_cast_check(h: SimUnit, foe: SimUnit) -> void:
	var w: SimWorld = game.world
	var inp: InputController = game.input
	var slot := -1
	for i in h.abilities.size():
		var a := SimData.ability(h.abilities[i])
		if String(a.behavior) in ["unit", "point"] and String(a.get("target_team", "enemy")) == "enemy" and h.ability_level_of(h.abilities[i]) > 0:
			slot = i
			break
	if slot < 0:
		print("quick cast: no enemy-target spell on this hero, skipped")
		return
	var aid: String = h.abilities[slot]
	var was = Options.get_value("quick_cast")
	Options.set_value("quick_cast", true)
	w.effects.clear()
	h.modifiers.clear()
	h.refresh_stats()
	h.mana = h.max_mana
	h.ability_ready[aid] = C.LONG_AGO
	h.channel = {}
	w.orders.clear(h)
	if not foe.alive:
		w.respawn(foe)
	foe.pos = h.pos + Vector2(250, 0)
	foe.hp = foe.max_hp
	w.orders.clear(foe)
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(3)
	var sp: Vector2 = game.camera.cam.unproject_position(View.to3(foe.pos, game.terrain.height_at(foe.pos)) + Vector3(0, 0.9, 0))
	game.get_viewport().warp_mouse(sp)
	await process_frame
	await process_frame
	var m: Vector2 = game.get_viewport().get_mouse_position()
	if m.distance_to(sp) > 20.0:
		var gp: Vector2 = game.camera.ground_at(m)
		foe.pos = Vector2(clampf(gp.x, -6000.0, 6000.0), clampf(gp.y, -6000.0, 6000.0))
		h.pos = foe.pos - Vector2(200, 0)
		await frames(2)
	var mana0 := h.mana
	inp._action(Keybinds.slot_action(slot, h.abilities.size()), h)
	check(inp.targeting == "", "quick cast: %s needs no click (targeting=%s)" % [aid, inp.targeting])
	await frames(45)
	check(h.mana < mana0 or w.abilities.cooldown_left(h, aid) > 0.0, "quick cast: %s went off at the mouse (mana %.0f -> %.0f)" % [aid, mana0, h.mana])
	Options.set_value("quick_cast", was)

## Roydo: Grip of the Ruler clicked on empty ground says "No valid target", keeps the cursor and spends nothing.
func _grip_empty_check(h: SimUnit, foe: SimUnit) -> void:
	var slot := h.abilities.find("grip_of_the_ruler")
	if slot < 0:
		return
	var w: SimWorld = game.world
	var inp: InputController = game.input
	h.mana = h.max_mana
	h.ability_ready["grip_of_the_ruler"] = C.LONG_AGO
	w.orders.clear(h)
	foe.pos = h.pos + Vector2(-1500, 0)
	await frames(3)
	var empty_spot := h.pos + Vector2(450, 300)
	var sp: Vector2 = game.camera.cam.unproject_position(View.to3(empty_spot, game.terrain.height_at(empty_spot)))
	var mana0 := h.mana
	inp._action(Keybinds.slot_action(slot, h.abilities.size()), h)
	inp._left_click(sp, false)
	check(inp.targeting == "grip_of_the_ruler", "grip on empty ground keeps the cursor (targeting=%s)" % inp.targeting)
	check(String(game.hud.get("_msg")) == "No valid target", "and the HUD says No valid target (%s)" % str(game.hud.get("_msg")))
	await frames(30)
	check(h.mana == mana0 and w.abilities.cooldown_left(h, "grip_of_the_ruler") == 0.0, "grip on empty ground spends nothing")
	inp.targeting = ""

## Double-clicking / double-tapping a point skill or a targeted item self-casts it at the hero.
func _self_cast_check(h: SimUnit) -> void:
	var w: SimWorld = game.world
	var inp: InputController = game.input
	for i in h.abilities.size():
		var aid: String = h.abilities[i]
		var a := SimData.ability(aid)
		if String(a.behavior) == "point" and aid != "grip_of_the_ruler" and h.ability_level_of(aid) > 0:
			w.effects.clear()
			h.modifiers.clear()
			h.refresh_stats()
			h.mana = h.max_mana
			h.ability_ready[aid] = C.LONG_AGO
			w.orders.clear(h)
			inp.targeting = ""
			inp.begin_ability(aid)
			check(inp.targeting == aid, "self-cast skill: first click starts targeting (%s)" % aid)
			inp.begin_ability(aid)
			check(inp.targeting == "", "self-cast skill: second click within 0.5 s self-casts (%s)" % aid)
			await frames(30)
			check(w.abilities.cooldown_left(h, aid) > 0.0 or h.mana < h.max_mana, "self-cast skill: %s went off on self" % aid)
			break
	w.effects.clear()
	h.modifiers.clear()
	h.refresh_stats()
	h.inventory[0] = {"id": "push_staff", "ready": C.LONG_AGO, "owner": h.id}
	h.mana = h.max_mana
	w.orders.clear(h)
	inp.targeting = ""
	var pos0 := h.pos
	inp.use_item(0)
	check(inp.targeting == "item:0", "self-cast item: first click starts targeting")
	inp.use_item(0)
	check(inp.targeting == "", "self-cast item: second click within 0.5 s self-casts Push Staff")
	await frames(25)
	check(h.pos.distance_to(pos0) > 200.0, "self-cast item: Push Staff pushed the hero (%d moved)" % int(h.pos.distance_to(pos0)))
	h.inventory[0] = null

## The Teleport key pressed twice quickly teleports to the fountain; pressed twice slowly it just stays targeting.
func _tp_double_tap_check(h: SimUnit) -> void:
	var w: SimWorld = game.world
	var inp: InputController = game.input
	w.effects.clear()
	h.modifiers.clear()
	h.refresh_stats()
	w.orders.clear(h)
	h.channel = {}
	h.tp_charges = maxi(h.tp_charges, 2)
	h.ability_ready["tp"] = C.LONG_AGO
	h.mana = h.max_mana
	inp.targeting = ""
	inp._action("tp", h)
	check(inp.targeting == "tp", "T starts Town Portal targeting")
	await frames(20)                                # about 0.66 s: too slow for a double tap
	inp._action("tp", h)
	check(inp.targeting == "tp", "T again after 0.6 s keeps targeting (no teleport)")
	inp._action("tp", h)                            # within 0.5 s of the last press: home
	check(inp.targeting == "", "a double tap ends targeting")
	var dest := Vector2.INF
	for k in 30:
		await frames(1)
		if not h.channel.is_empty() and String(h.channel.ability) == "tp":
			dest = h.channel.dest
			break
	var home: Vector2 = w.map.fountains[h.team]
	check(dest.distance_to(home) < 900.0,
		"a double tap teleports to the fountain (dest %s, fountain %s)" % [str(dest), str(home)])
	await frames(100)
	check(h.pos.distance_to(home) < 900.0, "and the hero arrives there (%d away)" % int(h.pos.distance_to(home)))
