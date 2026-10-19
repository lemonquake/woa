extends SceneTree
## How Araki's bot fights and dies (run 2026-10-19 c): plays a 5 v 5 bot game and prints, for every death of an Araki,
## the last 8 seconds before it (his mode, health, mana, the nearest enemy hero and tower, every cast he made), and a
## count of his casts by situation.
##   godot --headless --path . -s tests/tools/araki_probe.gd -- [--a=araki,ezee,tock,kragg,froster]
##       [--b=caziel,azrin,sludge,roydo,blood_ranger] [--min=20] [--seed=3] [--skill=hard]

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

func _init() -> void:
	var opts := {"a": "araki,ezee,tock,kragg,froster", "b": "caziel,azrin,sludge,roydo,blood_ranger", "min": "20",
		"seed": "3", "skill": "hard"}
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
			w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % n, String(opts.skill)))
			n += 1
	var arakis: Array = w.heroes.filter(func(h): return String(h.def.id) == "araki")
	var hist := {}                                   # araki id -> [lines]
	var casts := {}
	var deaths := 0
	while w.time < float(opts.min) * 60.0 and w.winner < 0:
		w.step()
		for a: SimUnit in arakis:
			var lines: Array = hist.get(a.id, [])
			if w.tick % 15 == 0 and a.alive:
				var bot: SimBot = w.bot_for(a.id)
				var ne: SimUnit = null
				for h in w.heroes:
					if h.team != a.team and h.alive and (ne == null or h.pos.distance_to(a.pos) < ne.pos.distance_to(a.pos)):
						ne = h
				var tw := INF
				for u in w.units:
					if u.alive and u.kind == K.TOWER and u.team != a.team:
						tw = minf(tw, u.pos.distance_to(a.pos) - u.attack_range)
				var foes := 0
				for h in w.heroes:
					if h.team != a.team and h.alive and h.pos.distance_to(a.pos) < 1200.0:
						foes += 1
				lines.append("  %s %-8s hp %3d%% mana %3d%% lvl %d | %s %d away (%d%%), %d enemy heroes in 1200, tower edge %s, threat %.2f" % [
					w.clock_text(), bot.mode if bot else "-", int(100 * a.hp / a.max_hp), int(100 * a.mana / maxf(1.0, a.max_mana)),
					a.level, String(ne.def.id) if ne else "-", int(ne.pos.distance_to(a.pos)) if ne else 0,
					int(100 * ne.hp / ne.max_hp) if ne else 0, foes, str(int(tw)) if tw < INF else "-", bot._threat if bot else 0.0])
			for e in w.events:
				if int(e.get("u", -1)) == a.id and String(e.t) == "cast":
					var bot2: SimBot = w.bot_for(a.id)
					var key := "%s in %s" % [String(e.ability), bot2.mode if bot2 else "-"]
					casts[key] = int(casts.get(key, 0)) + 1
					var tgt := w.get_unit(int(e.get("target", -1)))
					lines.append("  %s CAST %s (mode %s)%s" % [w.clock_text(), String(e.ability), bot2.mode if bot2 else "-",
						(" on " + String(tgt.def.id)) if tgt else ""])
				if String(e.t) == "blur_strike" and int(e.u) == a.id:
					var hit_heroes := 0
					for id in e.hits:
						var hu := w.get_unit(int(id))
						if hu and hu.is_hero():
							hit_heroes += 1
					lines.append("  %s   dash %d hits (%d heroes)%s" % [w.clock_text(), (e.hits as Array).size(), hit_heroes, " refreshed" if bool(e.again) else ""])
				if String(e.t) == "death" and int(e.u) == a.id:
					deaths += 1
					var k := w.get_unit(int(e.killer))
					print("DEATH %d of %s at %s, killed by %s" % [deaths, String(a.def.id), w.clock_text(), String(k.def.id) if k else "?"])
					for l in lines.slice(maxi(0, lines.size() - 22)):
						print(l)
					lines.clear()
			if lines.size() > 60:
				lines = lines.slice(lines.size() - 40)
			hist[a.id] = lines
		w.events.clear()
	for a: SimUnit in arakis:
		print("%s: K/D/A %d/%d/%d LH %d lvl %d nw %d" % [String(a.def.id), a.kills, a.deaths, a.assists, a.last_hits, a.level, a.networth()])
	var keys := casts.keys()
	keys.sort()
	for k in keys:
		print("  casts %-34s %d" % [k, casts[k]])
	quit()
