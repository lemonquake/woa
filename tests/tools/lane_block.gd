extends SceneTree
## Where lane creeps get stuck: walks one creep of each lane from its barracks and prints the walkable grid around
## the spot where it stops moving.
const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	for lane in ["top", "mid", "bot"]:
		var pts: PackedVector2Array = m.lanes[lane]
		print(lane, " lane first points: ", pts.slice(0, 6))
	var w := SimWorld.new(3, m)
	w.setup_match()
	while w.time < 40.0:
		w.step()
		w.events.clear()
	for u in w.units:
		if u.alive and u.is_lane_creep() and u.def.id == "dawn_melee":
			print("dawn ", u.lane, " at ", u.pos, " blocked ", u.blocked_time, " path ", u.path.size(), " order ", u.order, " target ", u.order_point)
	for u in w.units:
		if u.alive and u.is_lane_creep() and u.def.id == "dusk_melee":
			print("dusk ", u.lane, " at ", u.pos, " blocked ", u.blocked_time)
	var spot := Vector2(-6500, -4200)
	var c := m.world_to_cell(spot)
	for dy in range(-8, 9):
		var row := ""
		for dx in range(-12, 13):
			var cc := Vector2i(c.x + dx, c.y - dy)
			var ch := "#" if not m.is_walkable_cell(cc) else "."
			if m.tree_cell[cc.y * SimMap.N + cc.x] >= 0:
				ch = "T"
			for u in w.units:
				if u.alive and m.world_to_cell(u.pos) == cc:
					ch = "u" if not u.is_building() else "B"
			row += ch
		print(row)
	quit()
