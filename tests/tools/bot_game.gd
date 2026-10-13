extends SceneTree
## Bots against bots, five a side (or any line-up), headless. Reports the result, each hero's line, how the bots spent
## their time, their team chat, and any hero that got stuck.
##   godot --headless --path . -s tests/tools/bot_game.gd -- [--a=sludge,ezee,blood_ranger,sludge,ezee]
##       [--b=blood_ranger,ezee,sludge,ezee,blood_ranger] [--min=45] [--seeds=3,7,11] [--skill=hard] [--skill_b=hard]
##       [--learn=path/to/memory.json] [--chat] [--out=work/file.txt]
## --learn turns the bots' memory on with that file (it is read first and written after each game), so repeated runs
## show what learning changes. Without it the bots use their built-in values.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var lines: Array[String] = []

func out(s: String) -> void:
	print(s)
	lines.append(s)

func _init() -> void:
	var opts := {"a": "sludge,ezee,blood_ranger,sludge,ezee", "b": "blood_ranger,ezee,sludge,ezee,blood_ranger",
		"min": "45", "seeds": "3,7,11", "skill": "hard", "skill_b": "", "learn": "", "learn_teams": "1,1", "chat": "",
		"out": "", "no_save": ""}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if String(opts.learn) != "":
		BotMemory.path = String(opts.learn)
		BotMemory.active = true
		BotMemory.load_data()
		var lt := String(opts.learn_teams).split(",")
		BotMemory.teams = [lt[0] == "1", lt.size() < 2 or lt[1] == "1"]
	var m := SimMap.new()
	m.build(1)
	var wins := [0, 0]
	for seed_s in String(opts.seeds).split(","):
		var seed := int(seed_s)
		var w := SimWorld.new(seed, m)
		w.setup_match()
		var names := ["Bot Ann", "Bot Bob", "Bot Cat", "Bot Dan", "Bot Eve", "Bot Fay", "Bot Gus", "Bot Hal", "Bot Ivy", "Bot Jo"]
		var n := 0
		var heroes: Array = []
		for team in [C.DAWN, C.DUSK]:
			var list := String(opts.a if team == C.DAWN else opts.b).split(",", false)
			var skill := String(opts.skill) if team == C.DAWN or String(opts.skill_b) == "" else String(opts.skill_b)
			for id in list:
				var h := w.spawn_hero(id, team)
				w.bots.append(SimBot.new(w, h.id, "mid", names[n], skill))
				heroes.append(h)
				n += 1
		var t0 := Time.get_ticks_msec()
		var modes := {}
		var last_pos := {}
		var still := {}
		var stuck := {}
		var chat: Array = []
		var marks := {}
		while w.time < float(opts.min) * 60.0 and w.winner < 0:
			w.step()
			for mt in [600.0, 1200.0]:
				if not marks.has(mt) and w.time >= mt:
					var row := []
					var tot := [0, 0]
					for b in w.bots:
						var hh: SimUnit = b.hero()
						row.append("%s %d/%d" % [b.name.substr(4), hh.last_hits, hh.networth()])
						tot[hh.team] += hh.networth()
					marks[mt] = "  at %d:00 LH/net worth: %s | team net worth %d vs %d" % [int(mt / 60.0), ", ".join(row), tot[0], tot[1]]
			for e in w.events:
				if e.t == "chat":
					chat.append("[%s] %s %s: %s" % [w.clock_text(), C.TEAM_NAMES[int(e.team)], e.name, e.text])
			w.events.clear()
			if w.tick % 15 == 0:
				for b in w.bots:
					var h: SimUnit = b.hero()
					if not h.alive:
						continue
					var key := "%s" % b.mode
					modes[b.name] = modes.get(b.name, {})
					modes[b.name][key] = int(modes[b.name].get(key, 0)) + 1
					# stuck: alive, out of the base, barely moved for 20 s while not fighting or farming a camp
					var lp: Vector2 = last_pos.get(h.id, h.pos)
					if h.pos.distance_to(lp) < 40.0 and h.pos.distance_to(w.map.fountains[h.team]) > 2500.0 \
							and h.atk_phase == SimUnit.AtkPhase.NONE and w.time > 0.0:
						still[h.id] = float(still.get(h.id, 0.0)) + 0.5
						if float(still[h.id]) >= 20.0 and not stuck.has(h.id):
							stuck[h.id] = "%s stuck at %s (%s) from %s" % [b.name, str(h.pos.round()), b.mode, w.clock_text()]
					else:
						still[h.id] = 0.0
					last_pos[h.id] = h.pos
		if w.winner >= 0:
			wins[w.winner] += 1
		# a game cut off at the time cap still teaches (net worth decides the build scores)
		SimTeamAI.match_over(w)
		out("seed %d: %s at %s (%.1f s real)" % [seed, ("%s won" % C.TEAM_NAMES[w.winner]) if w.winner >= 0 else "no winner", w.clock_text(),
			(Time.get_ticks_msec() - t0) / 1000.0])
		for team in [C.DAWN, C.DUSK]:
			var towers := w.units.filter(func(u): return u.kind == K.TOWER and u.team == team and not u.alive).size()
			out("  %s (towers lost %d):" % [C.TEAM_NAMES[team], towers])
			for b in w.bots:
				var h: SimUnit = b.hero()
				if h.team != team:
					continue
				var md: Dictionary = modes.get(b.name, {})
				var total := 0
				for k in md:
					total += int(md[k])
				var share := []
				for k in md:
					share.append("%s %d%%" % [k, roundi(100.0 * md[k] / maxf(1.0, total))])
				out("    %-8s %-13s role %d %-4s %2d/%2d/%2d lvl %2d LH %3d DN %2d nw %5d | %s" % [b.name, h.def.id, b.role, b.lane,
					h.kills, h.deaths, h.assists, h.level, h.last_hits, h.denies, h.networth(), ", ".join(share)])
				out("             items: %s" % str(h.inventory.filter(func(i): return i != null).map(func(i): return i.id)))
		for mt in marks:
			out(marks[mt])
		var kills := [0, 0]
		var nw := [0, 0]
		for hh in w.heroes:
			kills[hh.team] += hh.kills
			nw[hh.team] += hh.networth()
		out("  totals: kills %d vs %d, net worth %d vs %d" % [kills[0], kills[1], nw[0], nw[1]])
		out("  stuck: %s" % (str(stuck.values()) if not stuck.is_empty() else "none"))
		out("  chat lines: %d" % chat.size())
		if String(opts.chat) != "":
			for c in chat:
				out("    " + c)
		else:
			for i in mini(12, chat.size()):
				out("    " + chat[i])
		w.dispose()
	out("wins: %s %d, %s %d" % [C.TEAM_NAMES[0], wins[0], C.TEAM_NAMES[1], wins[1]])
	if BotMemory.active and String(opts.no_save) == "":
		BotMemory.save()
		out("memory: " + " | ".join(BotMemory.summary()))
	if String(opts.out) != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit()
