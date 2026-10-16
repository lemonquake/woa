extends SceneTree
## Finds sim stalls: runs one bot duel and prints every game-time step that takes over 50 ms of real time, with the
## heroes' state and the last events, plus a line per game minute:
##   godot --headless --path . -s tests/tools/stall_probe.gd -- [--a=roydo] [--b=ezee] [--min=12] [--seed=3] [--trace=348]
## --trace prints both heroes' state before every step from that game second (the last line is the step that hangs).
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var opts := {"a": "roydo", "b": "ezee", "min": "12", "seed": "3"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=")
			opts[kv[0]] = kv[1]
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(int(opts.seed), m)
	w.setup_match()
	var a := w.spawn_hero(opts.a, C.DAWN)
	var b := w.spawn_hero(opts.b, C.DUSK)
	w.bots.append(SimBot.new(w, a.id, "mid", "A"))
	w.bots.append(SimBot.new(w, b.id, "mid", "B"))
	var minute := 0
	var start := Time.get_ticks_msec()
	var slow := 0
	while w.time < float(opts.min) * 60.0 and w.winner < 0:
		var t0 := Time.get_ticks_usec()
		if opts.has("trace") and w.time >= float(opts.trace):
			print("step %.3f | %s lvl %d hp %d pos %s order %s mods %s abil %s | %s hp %d pos %s" % [w.time, opts.a,
				a.level, int(a.hp), str(a.pos), str(a.order), str(a.modifiers.map(func(md): return md.id)),
				str(a.ability_level), opts.b, int(b.hp), str(b.pos)])
		w.step()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		if dt > 50.0 and slow < 40:
			slow += 1
			var evs := w.events.map(func(e): return "%s:%s" % [e.t, e.get("ability", "")])
			print("SLOW %.1f ms at %s | %s lvl %d hp %d pos %s mods %s | %s lvl %d hp %d | units %d | events %s" % [dt,
				w.clock_text(), opts.a, a.level, int(a.hp), str(a.pos), str(a.modifiers.map(func(md): return md.id)),
				opts.b, b.level, int(b.hp), w.units.size(), str(evs.slice(0, 8))])
		w.events.clear()
		if int(w.time / 60.0) > minute:
			minute = int(w.time / 60.0)
			print("min %d real %.1f s units %d %s lvl %d" % [minute, (Time.get_ticks_msec() - start) / 1000.0,
				w.units.size(), opts.a, a.level])
	w.dispose()
	quit()
