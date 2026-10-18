extends SceneTree
## Which skills bots cast in real games (run 2026-10-18 f): plays 5 v 5 bot games and counts every cast of every
## hero's skills, Burak's axe leaps and Ghorman's beasts, and prints a line per hero with any skill never cast.
##   godot --headless --path . -s tests/tools/kit_casts.gd -- [--a=airah,burak,emelrich,feran,ghorman]
##       [--b=ezee,azrin,kragg,blau,tock] [--min=25] [--seeds=3,7] [--skill=hard]

const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var opts := {"a": "airah,burak,emelrich,feran,ghorman", "b": "ezee,azrin,kragg,blau,tock", "min": "25",
		"seeds": "3,7", "skill": "hard"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var total := {}
	var missing_any := false
	for seed_s in String(opts.seeds).split(","):
		var m := SimMap.new()
		m.build(1)
		var w := SimWorld.new(int(seed_s), m)
		w.setup_match()
		var n := 0
		for team in [C.DAWN, C.DUSK]:
			for id in String(opts.a if team == C.DAWN else opts.b).split(",", false):
				var h := w.spawn_hero(id, team)
				w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % n, String(opts.skill)))
				n += 1
		var casts := {}
		var extra := {}
		var t0 := Time.get_ticks_msec()
		var errors_before := 0
		while w.time < float(opts.min) * 60.0 and w.winner < 0:
			w.step()
			for e in w.events:
				var u := w.get_unit(int(e.get("u", -1)))
				if u == null or not u.is_hero():
					continue
				var hid := String(u.def.id) + "#" + str(u.team)
				match String(e.t):
					"cast", "toggle":
						if String(e.t) == "toggle" and not bool(e.get("on", false)):
							continue
						casts[hid] = casts.get(hid, {})
						casts[hid][String(e.ability)] = int(casts[hid].get(String(e.ability), 0)) + 1
					"axe_leap", "tame", "maul", "unstoppable", "windup", "joke_box_pop", "hurricane_end", "berserk_cleared":
						extra[hid + ":" + String(e.t)] = int(extra.get(hid + ":" + String(e.t), 0)) + 1
			w.events.clear()
		print("seed %s: %s at %s, %d ms" % [seed_s, "winner " + C.TEAM_NAMES[w.winner] if w.winner >= 0 else "no winner",
			w.clock_text(), Time.get_ticks_msec() - t0])
		for h in w.heroes:
			var hid := String(h.def.id) + "#" + str(h.team)
			var got: Dictionary = casts.get(hid, {})
			var miss: Array = []
			for aid in h.abilities:
				var a := SimData.ability(String(aid))
				if String(a.behavior) in ["passive", "innate"]:
					continue
				if not got.has(aid):
					miss.append(aid)
			var ex: Array = []
			for k in extra:
				if String(k).begins_with(hid + ":"):
					ex.append("%s %d" % [String(k).split(":")[1], extra[k]])
			print("  %-10s L%2d K/D/A %d/%d/%d LH %3d  casts %s%s%s" % [String(h.def.id), h.level, h.kills, h.deaths,
				h.assists, h.last_hits, str(got), ("  | " + ", ".join(ex)) if not ex.is_empty() else "",
				("  | NEVER: " + ", ".join(miss)) if not miss.is_empty() else ""])
			if h.team == C.DAWN and not miss.is_empty():
				missing_any = true
	quit(1 if missing_any else 0)
