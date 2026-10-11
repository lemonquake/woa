p='src/sim/sim_map.gd'; s=open(p,encoding='utf-8').read()
old_fp=s[s.index('## A path for a ground unit from a to b'):s.index('func is_walkable_cell(')]
new_fp='''## A path for a ground unit from a to b (world points). Grid A* with collinear points removed; units smooth the
## corners as they walk (SimOrders looks ahead along the path). Empty if unreachable.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := world_to_cell(a)
	var cb := world_to_cell(b)
	if not is_walkable_cell(ca):
		ca = nearest_walkable(ca)
	if not is_walkable_cell(cb):
		cb = nearest_walkable(cb)
		b = cell_center(cb.x, cb.y)
	if ca == cb:
		return PackedVector2Array([b])
	if a.distance_squared_to(b) < 2000.0 * 2000.0 and line_walkable(a, b):
		return PackedVector2Array([b])
	var ids := astar.get_id_path(ca, cb, true)
	if ids.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	var prev_dir := Vector2i.ZERO
	for i in range(1, ids.size()):
		var d: Vector2i = ids[i] - ids[i - 1]
		if d != prev_dir and i > 1:
			out.append(cell_center(ids[i - 1].x, ids[i - 1].y))
		prev_dir = d
	out.append(b)
	return out

'''
s=s.replace(old_fp,new_fp)
old_lw=s[s.index('## Whether a straight walk from a to b crosses only walkable cells'):s.index('# ---- Vision grid')]
new_lw='''## Whether a straight walk from a to b crosses only walkable cells (exact grid traversal).
func line_walkable(a: Vector2, b: Vector2) -> bool:
	var fx := (a.x + HALF) / CELL
	var fy := (a.y + HALF) / CELL
	var tx := (b.x + HALF) / CELL
	var ty := (b.y + HALF) / CELL
	var x := int(floor(fx))
	var y := int(floor(fy))
	var ex := int(floor(tx))
	var ey := int(floor(ty))
	var dx := tx - fx
	var dy := ty - fy
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var tdx := absf(1.0 / dx) if dx != 0.0 else INF
	var tdy := absf(1.0 / dy) if dy != 0.0 else INF
	var tmx := INF
	var tmy := INF
	if dx != 0.0:
		tmx = ((floor(fx) + 1.0 - fx) if dx > 0.0 else (fx - floor(fx))) * tdx
	if dy != 0.0:
		tmy = ((floor(fy) + 1.0 - fy) if dy > 0.0 else (fy - floor(fy))) * tdy
	var guard := 0
	while guard < 1024:
		guard += 1
		if x < 0 or y < 0 or x >= N or y >= N or walkable[y * N + x] == 0:
			return false
		if x == ex and y == ey:
			return true
		if tmx < tmy:
			tmx += tdx
			x += sx
		else:
			tmy += tdy
			y += sy
	return true

'''
s=s.replace(old_lw,new_lw)
open(p,'w',encoding='utf-8').write(s)

p='src/sim/sim_orders.gd'; s=open(p,encoding='utf-8').read()
s=s.replace('''	if u.path_i >= u.path.size():
		u.path = PackedVector2Array()
		return true
	var nxt := u.path[u.path_i]''','''	if u.path_i >= u.path.size():
		u.path = PackedVector2Array()
		return true
	# corner cutting: skip ahead while the next-but-one point is in a straight walkable line
	if u.path_i + 1 < u.path.size() and (w.tick + u.id) % 4 == 0 and w.map.line_walkable(u.pos, u.path[u.path_i + 1]):
		u.path_i += 1
	var nxt := u.path[u.path_i]''')
old_res=s[s.index('## Unit collision: try the step'):]
new_res='''## Unit collision: try the step, then sidesteps of increasing angle; walls block, other units push sideways.
func _resolve(u: SimUnit, np: Vector2, move: Vector2, chase: SimUnit) -> Vector2:
	var near := w.query(u.pos, u.hull + 190.0)
	if _free(u, np, chase, near):
		return np
	for a in [0.5, -0.5, 1.0, -1.0, 1.4, -1.4]:
		var m := move.rotated(a) * (0.85 if absf(a) > 1.2 else 1.0)
		var p := u.pos + m
		if _free(u, p, chase, near):
			return p
	# squeeze: a short step that tolerates slight overlap so crowds keep flowing
	var p2 := u.pos + move * 0.25
	if _free(u, p2, chase, near, true):
		return p2
	return u.pos

func _free(u: SimUnit, p: Vector2, chase: SimUnit, near: Array, loose := false) -> bool:
	if not w.map.is_walkable(p):
		return false
	for o: SimUnit in near:
		if o == u or o == chase or o.is_ward():
			continue
		var min_d := u.hull + o.hull - (8.0 if loose else 2.0)
		if o.is_building():
			min_d = u.hull + o.hull * 0.85
		var new_d2 := p.distance_squared_to(o.pos)
		if new_d2 < min_d * min_d and new_d2 < u.pos.distance_squared_to(o.pos):
			return false
	return true
'''
s=s.replace(old_res,new_res)
open(p,'w',encoding='utf-8').write(s)

p='src/sim/sim_vision.gd'; s=open(p,encoding='utf-8').read()
s=s.replace('''	for team in 2:
		var vis := _static[team].duplicate()
		for u in w.units:
			if not u.alive or u.team != team or u.is_building():
				continue
			var r := u.vision_night if night else u.vision_day
			if r <= 0.0:
				continue
			_cast(vis, u.pos, r, u.has_flag("flying"))
		visible[team] = vis''','''	for team in 2:
		var vis := _static[team].duplicate()
		var done := {}                     # vision cell -> largest radius already cast from it
		for u in w.units:
			if not u.alive or u.team != team or u.is_building():
				continue
			var r := u.vision_night if night else u.vision_day
			if r <= 0.0:
				continue
			var c := w.map.world_to_vcell(u.pos)
			var key := c.y * VN + c.x
			if float(done.get(key, 0.0)) >= r:
				continue
			done[key] = r
			_cast(vis, u.pos, r, u.has_flag("flying"))
		visible[team] = vis''')
s=s.replace('''	var count := maxi(16, int(TAU * rc * 1.6))''','''	var count := maxi(16, int(TAU * rc * 1.15))''')
open(p,'w',encoding='utf-8').write(s)

p='src/sim/sim_world.gd'; s=open(p,encoding='utf-8').read()
old_bd=s[s.index('## Backdoor protection: a building takes half damage'):s.index('func _ancient_pos(')]
new_bd='''## Backdoor protection: a building takes half damage and heals what enemies did unless enemy lane creeps are near.
## Tier 2 towers watch their own surroundings; every in-base building shares the Ancient's large area.
func _backdoor(u: SimUnit) -> void:
	if u.kind == K.FOUNTAIN or (u.kind == K.TOWER and u.lane_tier == 1):
		u.backdoor_active = false
		return
	if tick % 6 != 0:
		return
	var creeps_near := false
	if u.kind == K.TOWER and u.lane_tier == 2:
		creeps_near = _enemy_creeps_near(u.team, u.pos, C.BACKDOOR_T2_RADIUS)
	else:
		creeps_near = _base_creeps[u.team]
	if creeps_near:
		u.backdoor_off_until = time + C.BACKDOOR_LINGER
	u.backdoor_active = time >= u.backdoor_off_until
	if not u.backdoor_active:
		u.backdoor_pool = 0.0

var _base_creeps := [false, false]

func _update_base_creeps() -> void:
	for team in 2:
		_base_creeps[team] = _enemy_creeps_near(team, _ancient_pos(team), C.BACKDOOR_BASE_RADIUS)

func _enemy_creeps_near(team: int, p: Vector2, r: float) -> bool:
	for o in query(p, r):
		if o.alive and o.team != team and o.team != C.NEUTRAL and o.is_lane_creep():
			return true
	return false

'''
s=s.replace(old_bd,new_bd)
s=s.replace('''	_rebuild_grid()
	for u in units:
		if u.alive:
			_pre_unit(u)''','''	_rebuild_grid()
	if tick % 6 == 0:
		_update_base_creeps()
	for u in units:
		if u.alive:
			_pre_unit(u)''')
s=s.replace('''func _ancient_pos(team: int) -> Vector2:
	for b in map.buildings:
		if b.team == team and b.unit == "ancient":
			return b.pos
	return Vector2.ZERO''','''var _ancient_cache := {}

func _ancient_pos(team: int) -> Vector2:
	if _ancient_cache.has(team):
		return _ancient_cache[team]
	for b in map.buildings:
		if b.team == team and b.unit == "ancient":
			_ancient_cache[team] = b.pos
			return b.pos
	return Vector2.ZERO''')
open(p,'w',encoding='utf-8').write(s)
print("ok")
