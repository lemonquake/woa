extends SceneTree
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var m := SimMap.new(); m.build(1)
	var w := SimWorld.new(3, m); w.setup_match()
	var o := Vector2(-900, -2900)
	var h := w.spawn("blau", C.DAWN, o); h.level = 10
	for a in h.abilities: h.ability_level[a] = mini(4, int(SimData.ability(a).max_level))
	h.refresh_stats(); h.mana = h.max_mana
	var e := w.spawn("ezee", C.DUSK, o + Vector2(700, 100))
	for i in 12:
		w.spawn("dusk_melee", C.DUSK, o + Vector2(500 + 40 * (i % 4), -150 + 60 * (i / 4)))
		w.spawn("dawn_melee", C.DAWN, o + Vector2(250 + 40 * (i % 4), -150 + 60 * (i / 4)))
	w.step()
	var b := SimBot.new(w, h.id, "mid", "T")
	b._foes.clear(); b._foes.append(e)
	var t0 := Time.get_ticks_usec()
	var n := 10
	var aim := {}
	for i in n:
		aim = SimBot16.best_bounce(b, h, e, false)
	print("best_bounce: %.2f ms per call (units near %d) -> %s" % [(Time.get_ticks_usec() - t0) / 1000.0 / n, w.query(o, 1500.0).size(), str(aim)])
	quit()
