extends SceneTree
## Every buff, debuff, aura and burn seen in headless 5 v 5 bot games (all heroes), with how the HUD's buff bar shows
## it: its name, buff or debuff, timed or not. Lists anything the bar has no name for.
##   godot --headless --path . -s tests/tools/modifier_census.gd -- [--min=25] [--seeds=3,7] [--out=work/file.txt]
## Exits 1 when an effect the bar shows has no name.

const C = preload("res://src/sim/sim_const.gd")

var lines: Array[String] = []

func out(s: String) -> void:
	print(s)
	lines.append(s)

func _init() -> void:
	var opts := {"min": "25", "seeds": "3,7", "out": ""}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var heroes: Array = GameSettings.HEROES.duplicate()
	var seen := {}                             # id -> {n, keys, debuff, buff, timed, untimed, on}
	var burns := {}
	var g := 0
	for seed_s in String(opts.seeds).split(","):
		var m := SimMap.new()
		m.build(1)
		var w := SimWorld.new(int(seed_s), m)
		w.setup_match()
		# every hero plays: rotate the pool so both seeds mix them differently
		var pool: Array = []
		for i in 10:
			pool.append(heroes[(i + g * 3) % heroes.size()])
		for i in 10:
			var team := C.DAWN if i < 5 else C.DUSK
			var h := w.spawn_hero(String(pool[i]), team)
			w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % i, "hard"))
		while w.time < float(opts.min) * 60.0 and w.winner < 0:
			w.step()
			w.events.clear()
			if w.tick % 3 != 0:
				continue
			for u: SimUnit in w.units:
				if not u.alive:
					continue
				for md in u.modifiers:
					var id := String(md.id)
					var s: Dictionary = seen.get(id, {"n": 0, "keys": {}, "debuff": 0, "buff": 0, "timed": 0, "untimed": 0, "on": {}})
					s.n += 1
					for k in md.keys():
						s.keys[k] = true
					if BuffBar.is_debuff(u, md):
						s.debuff += 1
					else:
						s.buff += 1
					if BuffBar.total_time(md, w.time) > 0.0:
						s.timed += 1
					else:
						s.untimed += 1
					s.on[C.Kind.keys()[u.kind]] = true
					seen[id] = s
				for d in w.status.dots_on(u):
					burns[String(d.key)] = int(burns.get(String(d.key), 0)) + 1
		g += 1
	var ids := seen.keys()
	ids.sort()
	var unnamed: Array = []
	out("%d modifier ids seen in %d games of %s min" % [ids.size(), g, opts.min])
	for id in ids:
		var s: Dictionary = seen[id]
		var nm := BuffBar.name_of(String(id))
		if nm == "" and not BuffBar.HIDDEN.has(id):
			unnamed.append(id)
		var hidden := " HIDDEN" if BuffBar.HIDDEN.has(id) else ""
		out("  %-22s %-24s buff %5d debuff %5d timed %5d untimed %5d on %s keys %s%s" % [id, nm, s.buff, s.debuff,
			s.timed, s.untimed, ",".join(s.on.keys()), ",".join(s.keys.keys()), hidden])
	out("burns: %s" % str(burns))
	for k in burns:
		if BuffBar.name_of(String(k)) == "":
			unnamed.append("burn " + String(k))
	out("UNNAMED: %s" % (", ".join(unnamed) if not unnamed.is_empty() else "none"))
	if String(opts.out) != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit(0 if unnamed.is_empty() else 1)
