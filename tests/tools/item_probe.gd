extends SceneTree
## Bots' items (run 2026-10-18 h; the owner saw gold left unspent, useless items carried late and never sold, and
## backpacks full of parts that never became an item): plays a headless bot game and prints, at set minutes, every
## bot's gold, bags (main | backpack), stash and courier, the junk it carries (SimBotBags.worth under the bar), loose
## parts that belong to nothing it still plans, and over the game its average unspent gold, sales and parts bought.
##   godot --headless --path . -s tests/tools/item_probe.gd -- [--seed=3] [--min=40] [--at=20,30,40] [--skill=hard]

const C = preload("res://src/sim/sim_const.gd")

func _bag(arr: Array, from: int, to: int) -> String:
	var out := []
	for i in range(from, mini(to, arr.size())):
		out.append("-" if arr[i] == null else String(arr[i].id))
	return ",".join(out)

func _init() -> void:
	var opts := {"seed": "3", "min": "40", "at": "20,30,40", "skill": "hard",
		"a": "sludge,ezee,blood_ranger,azrin,froster", "b": "caziel,kragg,tock,emelrich,feran"}
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
	var marks: Array = Array(String(opts.at).split(",")).map(func(x): return float(x) * 60.0)
	var gold_sum := {}
	var gold_n := 0
	var totals := {"junk": 0, "loose": 0, "rich": 0}
	while w.time < float(opts.min) * 60.0 and w.winner < 0:
		w.step()
		w.events.clear()
		if w.time > 900.0 and w.tick % 30 == 0:
			gold_n += 1
			for b in w.bots:
				gold_sum[b.name] = float(gold_sum.get(b.name, 0.0)) + float(b.hero().gold())
		if not marks.is_empty() and w.time >= float(marks[0]):
			marks.pop_front()
			print("== %s" % w.clock_text())
			for b in w.bots:
				var h: SimUnit = b.hero()
				var junk := []
				var loose := []
				for it in h.inventory:
					if it == null:
						continue
					var v := SimBotBags.worth(b, h, it)
					if v < SimBotBags.bar(w.time) or v <= float(SimData.item(String(it.id)).cost) * 0.12:
						junk.append(String(it.id))
					var d := SimData.item(String(it.id))
					if (d.components as Array).is_empty() and String(d.get("use", "")) == "" and not bool(d.consumable) \
							and not SimBotBags.is_planned_part(b, h, String(it.id)):
						for o in SimData.items():
							if String(it.id) in SimBotBags.all_parts(String(o)):
								loose.append(String(it.id))
								break
				totals.junk += junk.size()
				totals.loose += loose.size()
				var nxt: String = b.build[b._build_i] if b._build_i < b.build.size() else "-"
				var nxt_cost := w.shop.price(h, nxt) if nxt != "-" else 0
				if nxt != "-" and h.gold() >= nxt_cost:
					totals.rich += 1
				print("  %s %-12s lvl %2d gold %5d next %s (%d) | %s | %s | stash %s | courier %s | junk %s loose %s" % [
					b.name, h.def.id, h.level, h.gold(), nxt, nxt_cost, _bag(h.inventory, 0, 6), _bag(h.inventory, 6, 9),
					_bag(h.stash, 0, 6), _bag(h.courier_items, 0, 9), junk, loose])
	print("== over the game (from 15:00)")
	for b in w.bots:
		print("  %s %-12s average gold %5d, sold %d %s, parts bought ahead %d, build %d/%d" % [b.name, b.hero().def.id,
			roundi(float(gold_sum.get(b.name, 0.0)) / maxf(1.0, float(gold_n))), b.items_sold.size(), b.items_sold.slice(0, 12),
			b.parts_bought, b._build_i, b.build.size()])
	print("junk carried at the marks %d, loose parts %d, bots holding gold for their next item %d" % [totals.junk, totals.loose, totals.rich])
	quit()
