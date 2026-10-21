extends SceneTree

func _init() -> void:
	var map := SimMap.new()
	map.build(1)
	var w := SimWorld.new(1, map)
	w.elements = false
	w.next_neutral_at = INF
	w.time = 5.0
	var o := Vector2(-2000, -4000)
	var b := w.spawn("blackfire", 0, o)
	b.level = 18
	for aid in b.abilities:
		b.ability_level[aid] = int(SimData.ability(aid).max_level)
	b.refresh_stats()
	b.auto_attack = false
	var f := w.spawn("froster", 1, o + Vector2(-200, 0))
	f.auto_attack = false
	for i in 3:
		w.step()
	print("walk:", w.map.is_walkable(o + Vector2(-500, 0)), " tree:", w.map.tree_at(o + Vector2(-450, 0), 200.0))
	w.combat.deal_damage(f.id, f.team, true, b, 1e6, 3, false, "test")
	var p0 := f.pos
	for i in 300:
		w.events.clear()
		w.step()
		if w.time > 13.0 and w.time < 14.0:
			print(w.time, " knock=", f.knock.get("stun", -1), " imp=", f.knock.get("impacted", "-"), " stunned=", f.get_modifier("stunned"))
		for e in w.events:
			if String(e.t) in ["impact", "knockback", "unfallen_blast", "push_land"] :
				print(w.time, " ", e.t, " alive=", b.alive, " hp=", b.hp, " risen=", not b.get_modifier("unfallen_risen").is_empty(), " fallen=", w.abilities.kits8._fallen)
	print("moved ", f.pos.distance_to(p0), " stunned ", f.is_stunned())
	quit()
