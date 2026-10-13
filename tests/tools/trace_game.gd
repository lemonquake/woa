extends SceneTree
## Trace bots in a 5v5 bot game: every --every seconds between --from and --to (game minutes), print each traced
## bot's mode, top desires, position, health, order and target, plus its team's plans.
##   godot --headless --path . -s tests/tools/trace_game.gd -- [--bots=Bot Ann,Bot Fay] [--from=9] [--to=12]
##       [--every=2] [--seed=3]
const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var opts := {"bots": "", "from": "9", "to": "12", "every": "2", "seed": "3",
		"a": "sludge,ezee,blood_ranger,sludge,ezee", "b": "blood_ranger,ezee,sludge,ezee,blood_ranger"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(int(opts.seed), m)
	w.setup_match()
	var names := ["Bot Ann", "Bot Bob", "Bot Cat", "Bot Dan", "Bot Eve", "Bot Fay", "Bot Gus", "Bot Hal", "Bot Ivy", "Bot Jo"]
	var n := 0
	for team in [C.DAWN, C.DUSK]:
		for id in String(opts.a if team == C.DAWN else opts.b).split(",", false):
			var h := w.spawn_hero(id, team)
			w.bots.append(SimBot.new(w, h.id, "mid", names[n]))
			n += 1
	var want := String(opts.bots).split(",", false)
	var next := float(opts.from) * 60.0
	while w.time < float(opts.to) * 60.0:
		w.step()
		for e in w.events:
			if e.t == "chat" and w.time >= float(opts.from) * 60.0:
				print("    [%s] %s: %s" % [w.clock_text(), e.name, e.text])
		w.events.clear()
		if w.time >= next:
			next += float(opts.every)
			for b in w.bots:
				if not want.is_empty() and not (b.name in want):
					continue
				var h: SimUnit = b.hero()
				var ds := []
				var keys: Array = b.desires.keys()
				keys.sort_custom(func(x, y): return float(b.desires[x]) > float(b.desires[y]))
				for k in keys.slice(0, 3):
					ds.append("%s %.2f" % [k, float(b.desires[k])])
				var tgt := w.get_unit(h.order_target)
				var task := w.brain(h.team).task_for(h.id)
				print("[%s] %-8s %-12s %-7s hp %3d%% pos %s order %d tgt %s camp %d flane %s | %s | task %s" % [w.clock_text(), b.name,
					h.def.id, b.mode, roundi(100.0 * h.hp / h.max_hp), str(h.pos.round()), h.order,
					(String(tgt.def.id) + "@" + str(tgt.pos.round())) if tgt else "-", b._camp, b._farm_lane, ", ".join(ds),
					String(task.get("kind", "-"))])
	quit()
