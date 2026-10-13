extends SceneTree
## Last-hit lab: one bot alone in mid (no enemy hero) for a few minutes. Prints every enemy creep death (who killed
## it) and, around each, what the bot predicted. Use it to tune SimBot._last_hit_target.
##   godot --headless --path . -s tests/tools/lh_lab.gd -- [--hero=blood_ranger] [--min=3] [--verbose]
const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var hero := "blood_ranger"
	var mins := 3.0
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			hero = a.substr(7)
		elif a.begins_with("--min="):
			mins = float(a.substr(6))
		elif a == "--verbose":
			verbose = true
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(3, m)
	w.setup_match()
	var h := w.spawn_hero(hero, C.DAWN)
	var bot := SimBot.new(w, h.id, "mid", "Lab")
	w.bots.append(bot)
	var by := {"hero": 0, "creep": 0, "tower": 0, "other": 0}
	var last_target := -1
	while w.time < mins * 60.0:
		w.step()
		if h.order == C.Order.ATTACK_UNIT and h.order_target != last_target:
			last_target = h.order_target
			var c := w.get_unit(last_target)
			if verbose and c != null and c.is_lane_creep():
				var land := maxf(0.0, h.next_attack_at - w.time) + h.attack_point_time() + c.pos.distance_to(h.pos) / float(h.def.projectile_speed)
				print("[%.2f] attack %s hp %.0f predicted at %.2fs: %.0f (min dmg %.0f) dist %.0f" % [w.time, c.def.id, c.hp, land,
					bot._hp_when(c, land), h.dmg_min, h.edge_distance(c)])
		for e in w.events:
			if e.t == "death":
				var u := w.get_unit(int(e.u))
				if u == null or not u.is_lane_creep() or u.team == h.team or u.lane != "mid":
					continue
				var k := w.get_unit(int(e.killer))
				var kind := "other"
				if k == h:
					kind = "hero"
				elif k != null and k.is_lane_creep():
					kind = "creep"
				elif k != null and k.kind == C.Kind.TOWER:
					kind = "tower"
				by[kind] += 1
				if verbose or kind == "creep" and OS.get_cmdline_user_args().has("--misses"):
					print("[%.2f] %s died to %s (hero target %d, phase %d, cooldown %.2f, edge dist %.0f, mode %s, order %d)" % [w.time,
						u.def.id, kind, h.order_target, h.atk_phase, maxf(0.0, h.next_attack_at - w.time), h.edge_distance(u), bot.mode, h.order])
		w.events.clear()
	print("enemy creeps died to: ", by, "  LH %d DN %d" % [h.last_hits, h.denies])
	quit()
