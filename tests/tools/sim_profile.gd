extends SceneTree
## Where the simulation spends its time in a 5 v 5 bot game: milliseconds per tick for each part of the world step,
## printed for each window of game time, with the worst tick of the window.
##   godot --headless --path . -s tests/tools/sim_profile.gd -- [--min=20] [--window=5] [--seed=3]
##       [--a=sludge,ezee,blood_ranger,azrin,sludge] [--b=...]
const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var opts := {"min": "20", "window": "5", "seed": "3", "a": "sludge,ezee,blood_ranger,azrin,sludge",
		"b": "blood_ranger,ezee,sludge,azrin,ezee", "deep": "", "fight": ""}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(int(opts.seed), m)
	w.setup_match()
	var n := 0
	for team in [C.DAWN, C.DUSK]:
		for id in String(opts.a if team == C.DAWN else opts.b).split(",", false):
			var h := w.spawn_hero(id, team)
			w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % n, "hard"))
			n += 1
	if opts.fight != "":
		# --fight=T: play to T seconds, then stage a level 16 teamfight in mid every 20 s (SimDebug.stage_fight)
		while w.time < float(opts.fight):
			w.step()
			w.events.clear()
	var fight_next := w.time if opts.fight != "" else INF
	var first_fight := true
	w.profiling = true
	var win := float(opts.window) * 60.0
	var next := win
	var ticks := 0
	var worst := 0.0
	var all_t := 0.0
	var all_n := 0
	var tick_times := PackedFloat32Array()
	while w.time < float(opts.min) * 60.0 and w.winner < 0:
		if w.time >= fight_next:
			SimDebug.stage_fight(w, Vector2(-150, -150), 16, first_fight)
			first_fight = false
			fight_next = w.time + 20.0
		var before := w.prof.duplicate()
		var t0 := Time.get_ticks_usec()
		w.step()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		if dt > 15.0:
			# a slow tick: what it was made of
			var spk := []
			for k in w.prof:
				var dk := float(w.prof[k]) - float(before.get(k, 0.0))
				if dk > 0.5 and not String(k).contains("n_"):
					spk.append("%s %.1f" % [k, dk])
			print("  slow tick %.1f ms at %s: %s" % [dt, w.clock_text(), ", ".join(spk)])
		w.events.clear()
		ticks += 1
		worst = maxf(worst, dt)
		all_t += dt
		all_n += 1
		tick_times.append(dt)
		if w.time >= next:
			var parts := []
			var keys := w.prof.keys()
			keys.sort_custom(func(a, b): return w.prof[a] > w.prof[b])
			var sum := 0.0
			for k in keys:
				sum += w.prof[k]
				parts.append("%s %.2f" % [k, w.prof[k] / ticks])
			var a := Array(tick_times)
			a.sort()
			print("[%s] units %d  tick mean %.2f ms p95 %.2f max %.2f | %s" % [w.clock_text(), w.units.size(), sum / ticks,
				a[int(a.size() * 0.95)], worst, ", ".join(parts)])
			w.prof.clear()
			ticks = 0
			worst = 0.0
			tick_times.clear()
			next += win
	print("ALL mean %.2f ms/tick over %d ticks, winner %d at %s" % [all_t / maxf(1, all_n), all_n, w.winner, w.clock_text()])
	var kinds := {}
	for u in w.units:
		var k := "%s%s" % [u.def.id, "" if u.alive else "(dead)"]
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("units by kind: ", kinds)
	var blocked := 0
	for u in w.units:
		if u.alive and u.blocked_time > 0.0:
			blocked += 1
	print("blocked now: ", blocked)
	for lane in ["top", "mid", "bot"]:
		var pts := []
		for u in w.units:
			if u.alive and u.is_lane_creep() and u.lane == lane:
				pts.append("%d:(%d,%d)" % [u.team, int(u.pos.x / 100) * 100, int(u.pos.y / 100) * 100])
		pts.sort()
		print(lane, " creeps ", pts.size(), ": ", " ".join(pts.slice(0, 60)))
	quit()
