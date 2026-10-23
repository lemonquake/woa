class_name StormProbe
extends Node
## Skill storm (--storm only; run 2026-10-23): a real match in a window (HUD, effects, the threaded step) where every hero is level
## 25 with its whole kit, mana and cooldowns refilled every 2 s, all ten heroes kept fighting in one spot, and your hero
## casting a random skill every few frames at a random target: the nearest enemy or ally, itself, a point inside or past
## its range, toward a cliff or the map's edge. Bots cast at you as they like. Watches for script errors (the log),
## frames that hang (STALL) and the game quitting under it (a crash leaves no "storm done" line).
## It lives in the game (not tests/) so the exported build can run it too: the release runtime is where a script
## mistake can take the whole game down.
##   godot --path . res://src/game/main.tscn -- --storm --hero=dracoxinia --lineup=dracoxinia,gancho,kaileh,blackfire,
##     thyrandael,kaileh,dracoxinia,gancho,thyrandael,blackfire [--storm_min=3] [--spot=-600,-600] [--seed=1]
##   build/WarriorsOfAether.exe -- --match --storm --hero=... (the same flags)
## Prints casts per skill and the slowest frame, then "storm done", and quits.

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var _min := 3.0
var _spot := Vector2(-600, -600)
var _rng := RandomNumberGenerator.new()
var _casts := {}                            # ability id -> orders given
var _fired := {}                            # ability id -> times its cooldown started
var _worst := 0.0

func _ready() -> void:
	_rng.seed = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--storm_min="):
			_min = float(a.substr(12))
		elif a.begins_with("--spot="):
			var p := a.substr(7).split(",")
			_spot = Vector2(float(p[0]), float(p[1]))
		elif a.begins_with("--seed="):
			_rng.seed = int(a.substr(7))
	_run.call_deferred()

func _learn(w: SimWorld, h: SimUnit) -> void:
	if h.level < 25:
		w.combat.give_xp(h, float(C.XP_TABLE[24]) - h.xp)
	for aid in h.abilities:
		var ad := SimData.ability(aid)
		h.ability_level[aid] = (ad.required_level as Array).size() if ad.has("required_level") else int(ad.max_level)
	h.ability_points = 0
	h.refresh_stats()

func _refill(w: SimWorld) -> void:
	for h in w.heroes:
		if not h.alive:
			w.respawn(h)
			h.pos = _spot + Vector2(_rng.randf_range(-500, 500), _rng.randf_range(-500, 500))
			w.nudge_out(h.pos, h.hull)
			w.orders.clear(h)
		h.mana = h.max_mana
		for aid in h.abilities:
			h.ability_ready[aid] = C.LONG_AGO
		if h.pos.distance_to(_spot) > 1600.0:
			h.pos = _spot + Vector2(_rng.randf_range(-400, 400), _rng.randf_range(-400, 400))
			w.nudge_out(h.pos, h.hull)
			w.orders.clear(h)

func _nearest(w: SimWorld, h: SimUnit, enemy: bool) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for o in w.heroes:
		if o == h or not o.alive or (o.team != h.team) != enemy:
			continue
		var d := o.pos.distance_to(h.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _cast_random(w: SimWorld, h: SimUnit) -> void:
	var opts: Array = []
	for aid in h.abilities:
		var b := String(SimData.ability(aid).get("behavior", ""))
		if b in ["passive", "innate"] or h.ability_level_of(aid) <= 0:
			continue
		opts.append(aid)
	if opts.is_empty():
		return
	var aid: String = opts[_rng.randi() % opts.size()]
	var a := SimData.ability(aid)
	var beh := String(a.get("behavior", ""))
	var o := {"ability": aid}
	match beh:
		"no_target", "toggle":
			o["type"] = O.CAST_NO_TARGET
		"unit":
			o["type"] = O.CAST_UNIT
			var team := String(a.get("target_team", "enemy"))
			var t: SimUnit = h
			if team == "enemy":
				t = _nearest(w, h, true)
			elif _rng.randf() < 0.6:
				var al := _nearest(w, h, false)
				t = al if al != null else h
			if t == null:
				return
			o["target"] = t.id
		_:
			o["type"] = O.CAST_POINT
			var r := minf(w.abilities.cast_range(h, aid, -1), 2500.0)
			var p := h.pos
			match _rng.randi() % 5:
				0:
					var e := _nearest(w, h, true)
					p = e.pos if e != null else h.pos
				1:
					p = h.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, r)
				2:
					p = h.pos + Vector2.from_angle(_rng.randf() * TAU) * r * 2.5
				3:
					p = h.pos
				4:
					p = Vector2(_rng.randf_range(-9000, 9000), _rng.randf_range(-9000, 9000))
			o["point"] = p
	_casts[aid] = int(_casts.get(aid, 0)) + 1
	game.order(h.id, o)

func _run() -> void:
	while not game.get("booted") or game.world == null or game.input == null:
		await get_tree().process_frame
	var w: SimWorld = game.world
	var me: SimUnit = w.get_unit(game.player_hero_id)
	w.time = maxf(w.time, 90.0)
	for h in w.heroes:
		_learn(w, h)
		h.pos = _spot + Vector2(_rng.randf_range(-300, 300), _rng.randf_range(-300, 300))
		w.nudge_out(h.pos, h.hull)
		w.orders.clear(h)
		h.hp = h.max_hp
	print("storm: you are ", me.def.id, "; heroes ", w.heroes.map(func(x): return x.def.id))
	var until := Time.get_ticks_msec() + int(_min * 60000.0)
	var last := Time.get_ticks_msec()
	var n := 0
	var next_refill := 0.0
	var ready_was := {}
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last) / 1000.0
		last = now
		if dt > _worst:
			_worst = dt
		if dt > 2.0:
			print("STALL %.2f s at game time %.1f" % [dt, w.time])
		n += 1
		if w.time >= next_refill:
			next_refill = w.time + 2.0
			_refill(w)
			ready_was.clear()
		game.camera.focus(View.to3(me.pos, game.terrain.height_at(me.pos)))
		for aid in me.abilities:
			var r := float(me.ability_ready.get(aid, C.LONG_AGO))
			if r > w.time and not ready_was.has(aid):
				ready_was[aid] = true
				_fired[aid] = int(_fired.get(aid, 0)) + 1
		if me.alive and n % 9 == 0:
			_cast_random(w, me)
	print("casts ordered: ", _casts)
	print("casts fired:   ", _fired)
	print("slowest frame %.3f s, game time %.1f, frames %d" % [_worst, w.time, n])
	print("storm done")
	get_tree().quit(0)
