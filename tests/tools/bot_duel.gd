extends SceneTree
## Let two laning bots play for N minutes and report the scoreline and ability use:
##   godot --headless --path . -s tests/tools/bot_duel.gd -- [--a=blood_ranger] [--b=ezee] [--min=15]
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var opts := {"a": "blood_ranger", "b": "ezee", "min": "15"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=")
			opts[kv[0]] = kv[1]
	var m := SimMap.new()
	m.build(1)
	for seed in [3, 7, 11]:
		var w := SimWorld.new(seed, m)
		w.setup_match()
		var a := w.spawn_hero(opts.a, C.DAWN)
		var b := w.spawn_hero(opts.b, C.DUSK)
		w.bots.append(SimBot.new(w, a.id, "mid", "A"))
		w.bots.append(SimBot.new(w, b.id, "mid", "B"))
		var casts := {}
		while w.time < float(opts.min) * 60.0 and w.winner < 0:
			w.step()
			for e in w.events:
				if e.t == "cast":
					var k := "%s:%s" % ["A" if e.u == a.id else "B", e.ability]
					casts[k] = int(casts.get(k, 0)) + 1
			w.events.clear()
		print("seed %d at %s: A(%s) %d/%d/%d lvl %d LH %d DN %d nw %d | B(%s) %d/%d/%d lvl %d LH %d DN %d nw %d | towers lost A %d B %d" % [seed, w.clock_text(),
			opts.a, a.kills, a.deaths, a.assists, a.level, a.last_hits, a.denies, a.networth(), opts.b, b.kills, b.deaths, b.assists, b.level, b.last_hits, b.denies, b.networth(),
			w.units.filter(func(u): return u.kind == C.Kind.TOWER and u.team == 0 and not u.alive).size(),
			w.units.filter(func(u): return u.kind == C.Kind.TOWER and u.team == 1 and not u.alive).size()])
		print("    casts: ", casts)
		w.dispose()
	quit()
