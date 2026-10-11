extends SceneTree
## Trace the laning bot: for every enemy lane creep that dies near it, who got the kill and what the bot was doing.

const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(7, m)
	w.setup_match()
	var a := w.spawn_hero("galewarden", C.DAWN)
	var b := w.spawn_hero("galewarden", C.DUSK)
	var bot_a := SimBot.new(w, a.id, "mid", "A")
	w.bots.append(bot_a)
	w.bots.append(SimBot.new(w, b.id, "mid", "B"))
	var counts := {"hero_lh": 0, "creep": 0, "tower": 0, "other": 0, "far": 0}
	var reasons := {}
	while w.time < 300.0:
		w.step()
		for e in w.events:
			if e.t != "death":
				continue
			var u := w.get_unit(e.u)
			if u == null or not u.is_lane_creep() or u.team != C.DUSK:
				continue
			if u.pos.distance_to(a.pos) > 1100.0:
				counts.far += 1
				continue
			var k := w.get_unit(e.killer)
			if k == a:
				counts.hero_lh += 1
			elif k and k.is_lane_creep():
				counts.creep += 1
				var why := "order=%d atk_tgt=%s phase=%d d=%d hp%%=%d next_atk_in=%.2f" % [a.order, str(a.atk_target == u.id), a.atk_phase,
					int(a.edge_distance(u)), int(a.hp / a.max_hp * 100), maxf(0.0, a.next_attack_at - w.time)]
				if counts.creep <= 12:
					print("missed at %s: %s state=%s" % [w.clock_text(), why, bot_a.state])
			elif k and k.kind == C.Kind.TOWER:
				counts.tower += 1
			else:
				counts.other += 1
		w.events.clear()
	print(counts, " LH ", a.last_hits, " denies ", a.denies, " level ", a.level)
	quit()
