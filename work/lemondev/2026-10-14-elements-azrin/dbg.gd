extends SceneTree
const C = preload("res://src/sim/sim_const.gd")
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(1, m)
	w.time = 5.0
	w.next_wave_at = INF
	w.next_neutral_at = INF
	w.elements = false
	var a := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("azrin", C.DUSK, Vector2(-1450, -3880))
	for u in [a, foe]:
		u.level = 18
		u.refresh_stats()
		u.mana = u.max_mana
		u.auto_attack = false
		for aid in u.abilities:
			u.ability_level[aid] = 3
	print("foe hp ", foe.hp)
	w.command(a.id, {"type": C.Order.CAST_POINT, "ability": "touch_of_ember", "point": Vector2(-1500, -4000)})
	for i in 15:
		w.step()
		for e in w.events:
			if e.t in ["damage", "cast", "debuff", "ember_explode", "ember_cast"]:
				print(w.tick, " ", e)
		w.events.clear()
	print("mods ", foe.modifiers)
	w.command(foe.id, {"type": C.Order.CAST_POINT, "ability": "touch_of_ember", "point": Vector2(-2000, -4000)})
	for i in 15:
		w.step()
		for e in w.events:
			if e.t in ["damage", "cast", "debuff", "ember_explode", "ember_cast"]:
				print(w.tick, " ", e)
		w.events.clear()
	quit()
