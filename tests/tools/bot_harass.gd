extends SceneTree
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(7, m)
	w.setup_match()
	var a := w.spawn_hero("galewarden", C.DAWN)
	var b := w.spawn_hero("galewarden", C.DUSK)
	w.bots.append(SimBot.new(w, a.id, "mid", "A"))
	w.bots.append(SimBot.new(w, b.id, "mid", "B"))
	var dmg := {"a2b": 0.0, "b2a": 0.0, "creep2a": 0.0, "tower2a": 0.0}
	var minhp := [1.0, 1.0]
	var near_t := 0.0
	var casts := {}
	while w.time < 600.0:
		w.step()
		for e in w.events:
			if e.t == "damage":
				var s := w.get_unit(e.src)
				if s == null: continue
				if e.u == b.id and s == a: dmg.a2b += e.amount
				elif e.u == a.id and s == b: dmg.b2a += e.amount
				elif e.u == a.id and s.is_lane_creep(): dmg.creep2a += e.amount
				elif e.u == a.id and s.kind == C.Kind.TOWER: dmg.tower2a += e.amount
			elif e.t == "cast":
				casts[e.ability] = casts.get(e.ability, 0) + 1
		w.events.clear()
		minhp[0] = minf(minhp[0], a.hp / a.max_hp)
		minhp[1] = minf(minhp[1], b.hp / b.max_hp)
		if a.alive and b.alive and a.pos.distance_to(b.pos) < 900.0:
			near_t += C.DT
	print(dmg, " min hp ", minhp, " seconds within 900: ", near_t, " casts ", casts, " A lvl ", a.level, " abil ", a.ability_level)
	quit()
