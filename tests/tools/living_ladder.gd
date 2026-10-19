extends SceneTree
## A ladder for captures and probes of the Players screen (run 2026-10-19 d): plays `--games` ranked matches for you
## on its own file (wins and losses, kills between you and the bots, a flame now and then), accepts the first
## friend requests, leaves one waiting, and lets the ladder play on. Your own ladder (user://ranked.json) is untouched.
##   godot --headless --path . -s tests/tools/living_ladder.gd -- [--file=user://ranked_cap.json] [--games=8] [--fresh]
## then: set WOA_RANKED_FILE=user://ranked_cap.json and open the Ranked screen (--tab=players, --profile=<id>).

func _initialize() -> void:
	var opts := {"file": "user://ranked_cap.json", "games": "8", "fresh": ""}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Ranked.reset(String(opts.file))
	if String(opts.fresh) != "" and FileAccess.file_exists(Ranked.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Ranked.path))
	Ranked.load_data()
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var pool := GameSettings.random_pool()
	for g in int(opts.games):
		var l := Matchmaker.build_lineup(Ranked.bots().filter(func(b): return absi(int(b.mmr) - int(Ranked.me().mmr)) < 600), Ranked.me(), [2], r)
		var teams := [[], []]
		var heroes := {}
		var i := 0
		for t in 2:
			for p in l.teams[t]:
				teams[t].append(String(p.id))
				heroes[String(p.id)] = String(pool[(i + g * 3) % pool.size()])
				i += 1
		Ranked.begin_match({"teams": teams, "mine": l.mine, "heroes": heroes, "roles": l.roles})
		var won := r.randf() < 0.6
		var rel := {}
		for t in 2:
			for id in teams[t]:
				if id == "me":
					continue
				var e := {}
				if t != l.mine:
					e["kills_on_you"] = r.randi_range(0, 4)
					e["deaths_to_you"] = r.randi_range(0, 3)
				elif r.randf() < 0.3:
					e["praised"] = 1
				if r.randf() < 0.12:
					e["flamed"] = 1
				rel[id] = e
		var k := r.randi_range(2, 12)
		var x := r.randi_range(1, 8)
		var res := Ranked.finish_match(won, false, {"perf": r.randf_range(0.3, 0.9), "k": k, "x": x, "a": r.randi_range(4, 18),
			"len": r.randi_range(1500, 2700), "rel": rel})
		print("game %d: %s %+d MMR, requests %s" % [g + 1, "won" if won else "lost", int(res.delta), str(res.get("requests", []))])
	var req: Array = (Ranked.me().requests as Array).duplicate()
	for i in maxi(0, req.size() - 1):
		Ranked.accept_request(String(req[i].id))
	Ranked.simulate_rounds(6)
	Ranked.save()
	print("ladder %s: %d players, %d friends, %d requests waiting, %d met, feed %d" % [Ranked.path, Ranked.bots().size() + 1,
		(Ranked.me().friends as Array).size(), (Ranked.me().requests as Array).size(), (Ranked.me().met as Dictionary).size(),
		(Ranked.data.feed as Array).size()])
	var met := Ranked.recent_players(1)
	if not met.is_empty():
		print("a player you met: %s" % String(met[0][0].id))
	quit()
