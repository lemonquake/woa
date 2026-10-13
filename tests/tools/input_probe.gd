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
		inp._action("ability_%d" % (i + 1), h)
		var beh := String(a.behavior)
		if beh in ["unit", "point", "autocast_attack"]:
			check(inp.targeting == aid, "%s: key starts targeting (targeting=%s)" % [aid, inp.targeting])
			await process_frame
			var sp: Vector2 = game.camera.cam.unproject_position(View.to3(foe.pos, game.terrain.height_at(foe.pos)) + Vector3(0, 0.9, 0))
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
				inp._action("ability_%d" % (i + 1), h)
				await frames(3)
				check(not bool(h.toggles.get("stench", false)), "stench: W again turns it off")
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
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
