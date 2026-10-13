extends SceneTree
## Where a 5v5 bot game spends its time: runs N game minutes and prints milliseconds per tick for each part of the
## world step (bots, team brains, orders and pathing, vision...).
##   godot --headless --path . -s tests/tools/bot_profile.gd -- [--min=8]
const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var mins := 8.0
	var line := ["sludge", "ezee", "blood_ranger", "sludge", "ezee"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min="):
			mins = float(a.substr(6))
		elif a.begins_with("--heroes="):
			line = a.substr(9).split(",")
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(3, m)
	w.setup_match()
	var i := 0
	for team in [C.DAWN, C.DUSK]:
		for id in line:
			var h := w.spawn_hero(id, team)
			w.bots.append(SimBot.new(w, h.id, "mid", "B%d" % i))
			i += 1
	var tm := {}
	var add := func(k: String, t: int) -> int:
		var now := Time.get_ticks_usec()
		tm[k] = int(tm.get(k, 0)) + now - t
		return now
	var ticks := 0
	var paths := 0
	var t_all := Time.get_ticks_usec()
	while w.time < mins * 60.0:
		w.tick += 1
		w.time += C.DT
		ticks += 1
		var t := Time.get_ticks_usec()
		w._clock()
		w._rebuild_grid()
		if w.tick % 6 == 0:
			w._update_base_creeps()
		for u in w.units:
			if u.alive:
				w._pre_unit(u)
		t = add.call("pre", t)
		w.ai.think()
		t = add.call("ai", t)
		for tb in w.brains:
			if tb != null:
				tb.think()
		t = add.call("brains", t)
		for b in w.bots:
			b.think()
		t = add.call("bots", t)
		w._couriers()
		if w.tick % 6 == 0:
			for h in w.heroes:
				w.shop.auto_buy(h)
		t = add.call("couriers", t)
		for u in w.units:
			if u.alive and u.kind != C.Kind.COURIER:
				if u.path_i == 0 and not u.path.is_empty():
					paths += 0
				w.orders.update(u)
		t = add.call("orders", t)
		w.combat.update_projectiles()
		w.abilities.update_effects()
		w.items.update()
		w.combat.process_deaths()
		w._respawns()
		t = add.call("combat", t)
		if w.tick % C.VISION_UPDATE_TICKS == 0:
			w.vision.prune_sources()
			w.vision.update()
		t = add.call("vision", t)
		w._cleanup()
		w.events.clear()
	var parts := []
	for k in tm:
		parts.append("%s %.2f" % [k, tm[k] / float(ticks) / 1000.0])
	print("%d ticks, %.2f ms/tick: %s" % [ticks, (Time.get_ticks_usec() - t_all) / float(ticks) / 1000.0, ", ".join(parts)])
	quit()
