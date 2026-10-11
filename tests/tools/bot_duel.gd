extends SceneTree
## Let two laning bots play for N minutes and report the scoreline: godot --headless --path . -s tests/tools/bot_duel.gd
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	for seed in [3, 7, 11]:
		var w := SimWorld.new(seed, m)
		w.setup_match()
		var a := w.spawn_hero("galewarden", C.DAWN)
		var b := w.spawn_hero("galewarden", C.DUSK)
		w.bots.append(SimBot.new(w, a.id, "mid", "A"))
		w.bots.append(SimBot.new(w, b.id, "mid", "B"))
		while w.time < 900.0 and w.winner < 0:
			w.step()
			w.events.clear()
		print("seed %d at %s: A %d/%d/%d lvl %d LH %d DN %d nw %d | B %d/%d/%d lvl %d LH %d DN %d nw %d | towers lost A %d B %d" % [seed, w.clock_text(),
			a.kills, a.deaths, a.assists, a.level, a.last_hits, a.denies, a.networth(), b.kills, b.deaths, b.assists, b.level, b.last_hits, b.denies, b.networth(),
			w.units.filter(func(u): return u.kind == C.Kind.TOWER and u.team == 0 and not u.alive).size(),
			w.units.filter(func(u): return u.kind == C.Kind.TOWER and u.team == 1 and not u.alive).size()])
		w.dispose()
	quit()
