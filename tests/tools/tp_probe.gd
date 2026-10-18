extends SceneTree
## Bots' Town Portals (run 2026-10-18 h; the owner saw nearly every bot cancel its escape teleport and die): plays bot
## games headless and reports every teleport a bot starts, whether it lands, and what broke the ones that did not
## (a stun, mute or root, or the bot's own next order, with its mode, health and the nearest enemy hero).
##   godot --headless --path . -s tests/tools/tp_probe.gd -- [--seeds=3,7] [--min=25] [--skill=hard] [--verbose]

const C = preload("res://src/sim/sim_const.gd")
const ORD := ["NONE", "MOVE", "ATTACK_UNIT", "ATTACK_MOVE", "HOLD", "STOP", "CAST_NO_TARGET", "CAST_POINT", "CAST_UNIT",
	"MOVE_TO_UNIT", "DROP_ITEM", "PICKUP_ITEM", "GIVE_ITEM", "PICKUP_ORB", "USE_SITE"]

func _init() -> void:
	var opts := {"seeds": "3,7", "min": "25", "skill": "hard", "verbose": "", "a": "sludge,ezee,blood_ranger,azrin,froster",
		"b": "caziel,kragg,tock,emelrich,feran"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var started := 0
	var landed := 0
	var broken := {}
	var escape_started := 0
	var escape_landed := 0
	var escape_died := 0
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
		var chan := {}                      # hero id -> {hp, escape, at}
		var watch_death := {}               # hero id -> time a broken escape ended
		while w.time < float(opts.min) * 60.0 and w.winner < 0:
			w.step()
			var cancelled := {}
			for e in w.events:
				if e.t == "tp_cancel":
					cancelled[int(e.u)] = true
				elif e.t == "death" and watch_death.has(int(e.u)) and w.time - float(watch_death[int(e.u)]) < 8.0:
					escape_died += 1
					watch_death.erase(int(e.u))
			w.events.clear()
			for b in w.bots:
				var h: SimUnit = b.hero()
				var on := not h.channel.is_empty() and String(h.channel.get("ability", "")) == "tp"
				if on and not chan.has(h.id):
					var esc: bool = h.hp < h.max_hp * 0.5 or b.mode == "retreat" or b.mode == "heal"
					chan[h.id] = {"hp": h.hp / h.max_hp, "escape": esc, "at": w.time, "mode": b.mode}
					started += 1
					if esc:
						escape_started += 1
				elif not on and chan.has(h.id):
					var c: Dictionary = chan[h.id]
					chan.erase(h.id)
					if not cancelled.has(h.id) and h.alive:
						landed += 1
						if c.escape:
							escape_landed += 1
						continue
					var why := "died" if not h.alive else ("stunned" if h.is_stunned() else ("muted" if h.is_muted()
						else ("rooted" if h.has_flag("root") else "own order " + String(ORD[h.order]))))
					broken[why] = int(broken.get(why, 0)) + 1
					if c.escape and h.alive:
						watch_death[h.id] = w.time
					if String(opts.verbose) != "" or c.escape:
						var fd := INF
						for u in w.heroes:
							if u.alive and u.team != h.team:
								fd = minf(fd, u.pos.distance_to(h.pos))
						print("  [%s] %s (%s) %s tp %s after %.1f s: %s; mode %s -> %s, hp %d%% -> %d%%, foe %d" % [
							w.clock_text(), b.name, h.def.id, "escape" if c.escape else "move", "broken", w.time - float(c.at),
							why, c.mode, b.mode, roundi(float(c.hp) * 100.0), roundi(h.hp / h.max_hp * 100.0), roundi(fd) if fd < INF else -1])
		print("seed %s done at %s" % [seed_s, w.clock_text()])
	print("Teleports started %d, landed %d; escapes started %d, landed %d, broken then died within 8 s %d" % [
		started, landed, escape_started, escape_landed, escape_died])
	print("Broken by: ", broken)
	quit()
