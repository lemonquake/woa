class_name SimWorld
extends RefCounted
## The whole match, stepped at a fixed 30 Hz. Deterministic for a given seed and order stream: no wall-clock time,
## no engine physics, its own RNG. Presentation reads `units`, `projectiles`, `vision` and drains `events`.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var map: SimMap
var time := C.PREGAME_TIME
var tick := 0
var rng := RandomNumberGenerator.new()
var units: Array[SimUnit] = []
var by_id := {}
var next_id := 1
var projectiles: Array = []
var effects: Array = []                    # timed ability effects (SimAbilities)
var events: Array = []
var heroes: Array[SimUnit] = []
var wave := 0
var next_wave_at := 0.0
var next_neutral_at := C.NEUTRAL_FIRST_SPAWN
var glyph_ready_at := [C.GLYPH_INITIAL_COOLDOWN, C.GLYPH_INITIAL_COOLDOWN]
var rax_dead := {}                         # "team:lane:melee" -> true
var first_blood := false
var winner := -1
var paused := false
var _gold_acc := {}
var _grid := {}
const GRID := 512.0

var orders: SimOrders
var combat: SimCombat
var ai: SimAI
var vision: SimVision
var shop: SimShop
var abilities: SimAbilities
var bots: Array = []                       # SimBot instances

func _init(p_seed := 1, p_map: SimMap = null) -> void:
	rng.seed = p_seed
	if p_map == null:
		p_map = SimMap.new()
		p_map.build(p_seed)
	map = p_map
	orders = SimOrders.new(self)
	combat = SimCombat.new(self)
	ai = SimAI.new(self)
	vision = SimVision.new(self)
	shop = SimShop.new(self)
	abilities = SimAbilities.new(self)

func dispose() -> void:
	for b in bots:
		b.w = null
	bots.clear()
	for h in [orders, combat, ai, vision, shop, abilities]:
		h.w = null
	units.clear()
	by_id.clear()
	heroes.clear()
	projectiles.clear()

## Place every building and the fountain guards. Call once before stepping.
func setup_match() -> void:
	for b in map.buildings:
		var u := spawn(b.unit, b.team, b.pos)
		u.building_lane = b.lane
		u.lane_tier = b.tier
		u.facing = (Vector2.ZERO - u.pos).angle()
	_update_invulnerability()
	vision.update()

func spawn(def_id: String, team: int, p: Vector2) -> SimUnit:
	var def := SimData.unit(def_id)
	assert(not def.is_empty(), "unknown unit " + def_id)
	var u := SimUnit.new()
	u.setup(next_id, def, team, p, time)
	next_id += 1
	units.append(u)
	by_id[u.id] = u
	var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	if _grid.has(key):
		_grid[key].append(u)
	else:
		_grid[key] = [u]
	if u.is_hero():
		heroes.append(u)
		_gold_acc[u.id] = 0.0
	events.append({"t": "spawn", "u": u.id})
	return u

func spawn_hero(def_id: String, team: int, look := {}) -> SimUnit:
	var u := spawn(def_id, team, map.fountains[team] + Vector2(300, 300) * (1.0 if team == C.DAWN else -1.0))
	u.look = look
	u.facing = PI * 0.25 if team == C.DAWN else -PI * 0.75
	var c := spawn("courier", team, map.fountains[team] + Vector2(150, 420) * (1.0 if team == C.DAWN else -1.0))
	c.owner_id = u.id
	u.courier_id = c.id
	return u

## Buy back a dead hero: 200 + net worth / 13 gold (reliable first), 8 minute cooldown.
func buyback_cost(h: SimUnit) -> int:
	return C.BUYBACK_BASE + int(h.networth() / C.BUYBACK_NETWORTH_DIVISOR)

func buyback(h: SimUnit) -> String:
	if h.alive:
		return "Not dead"
	if time < h.buyback_ready:
		return "Buyback on cooldown"
	var cost := buyback_cost(h)
	if h.gold() < cost:
		return "Not enough gold"
	var from_rel := mini(cost, h.gold_reliable)
	h.gold_reliable -= from_rel
	h.gold_unreliable -= cost - from_rel
	h.buyback_ready = time + C.BUYBACK_COOLDOWN
	respawn(h)
	events.append({"t": "buyback", "u": h.id})
	return ""

## Order the hero's courier to fly to a point and wait there.
func courier_move(h: SimUnit, p: Vector2) -> String:
	var c := get_unit(h.courier_id)
	if c == null or not c.alive:
		return "Courier is dead"
	c.courier_state = "move"
	c.courier_goal = p
	return ""

## Send the hero's courier to fetch the stash and bring it to them.
func courier_deliver(h: SimUnit) -> String:
	var c := get_unit(h.courier_id)
	if c == null or not c.alive:
		return "Courier is dead"
	c.courier_state = "fetch"
	return ""

func get_unit(uid: int) -> SimUnit:
	return by_id.get(uid)

func valid(uid: int) -> bool:
	var u: SimUnit = by_id.get(uid)
	return u != null and u.alive

func is_night() -> bool:
	return C.is_night(time)

func enemies(a: int, b: int) -> bool:
	return a != b

# ---- Stepping -------------------------------------------------------------------------------------------------------

func step() -> void:
	if paused or winner >= 0:
		return
	tick += 1
	time += C.DT
	_clock()
	_rebuild_grid()
	if tick % 6 == 0:
		_update_base_creeps()
	for u in units:
		if u.alive:
			_pre_unit(u)
	ai.think()
	for b in bots:
		b.think()
	_couriers()
	for u in units:
		if u.alive:
			orders.update(u)
	combat.update_projectiles()
	abilities.update_effects()
	combat.process_deaths()
	_respawns()
	if tick % C.VISION_UPDATE_TICKS == 0:
		vision.update()
	_cleanup()

func _clock() -> void:
	# lane creep waves every 30 s from 0:00
	if time >= next_wave_at and time >= 0.0:
		wave += 1
		ai.spawn_wave(wave)
		next_wave_at = wave * C.WAVE_INTERVAL
	# neutral camps at every minute from 1:00
	if time >= next_neutral_at:
		next_neutral_at += C.NEUTRAL_SPAWN_INTERVAL
		ai.spawn_neutrals()
	# passive gold (reliable) from 0:00
	if time >= 0.0:
		var per_tick := C.passive_gpm(time) / 60.0 * C.DT
		for h in heroes:
			_gold_acc[h.id] += per_tick
			if _gold_acc[h.id] >= 1.0:
				var g := int(_gold_acc[h.id])
				_gold_acc[h.id] -= g
				h.gold_reliable += g
				h.gold_earned += g
	# trees regrow (Dota: 180 s after they fall, waiting while any unit stands within 150); planted trees wither
	if tick % 30 == 0:
		for i in map.trees.size():
			var t: Dictionary = map.trees[i]
			if t.alive:
				if t.get("planted", false) and time >= float(t.expires):
					map.destroy_tree(i, 0.0)
					vision.static_dirty = true
					events.append({"t": "tree", "i": i, "alive": false, "planted": true})
				continue
			if t.regrow <= 0.0:
				continue
			t.regrow = maxf(0.0, t.regrow - 1.0)
			if t.regrow <= 0.0:
				t.regrow = 0.001          # still waiting: checked again next second
				if map.can_regrow(i) and not _units_near(t.pos, C.TREE_REGROW_CLEAR):
					map.regrow_tree(i)
					vision.static_dirty = true
					events.append({"t": "tree", "i": i, "alive": true})

## Fell a tree (Mini-Axe, Vegan Picker, Gale Impact, a hurled unit). Natural trees regrow after 180 s; `from` is
## where the blow came from (the fall direction; INF = it was eaten and simply vanishes).
func cut_tree(i: int, from: Vector2, smashed := false) -> bool:
	if not map.destroy_tree(i, C.TREE_REGROW):
		return false
	vision.static_dirty = true
	var e := {"t": "tree", "i": i, "alive": false, "smashed": smashed}
	if from != Vector2.INF:
		e["from"] = from
	events.append(e)
	return true

## Units standing in a cell that just became blocked (a planted tree) step out to the nearest open cell.
func nudge_out(p: Vector2, r: float) -> void:
	for u in query(p, r + 40.0, true):
		if u.is_building() or u.is_ward() or u.kind == K.COURIER or map.is_walkable(u.pos):
			continue
		var c := map.nearest_walkable(map.world_to_cell(u.pos))
		u.pos = map.cell_center(c.x, c.y)
		u.path = PackedVector2Array()

func _units_near(p: Vector2, r: float) -> bool:
	for u in query(p, r):
		if u.alive and not u.is_building() and not u.is_ward() and u.kind != K.COURIER:
			return true
	return false

func _pre_unit(u: SimUnit) -> void:
	u.expire_modifiers(time)
	if u.stats_dirty:
		u.refresh_stats()
	# regeneration (fountain aura, consumables)
	var regen := u.hp_regen
	var mregen := u.mana_regen
	for m in u.modifiers:
		regen += float(m.get("regen", 0.0))
		mregen += float(m.get("mana_regen", 0.0))
	if u.is_hero() and u.pos.distance_to(map.fountains[u.team]) < C.FOUNTAIN_AURA_RADIUS:
		regen += u.max_hp * C.FOUNTAIN_HP_REGEN_PCT
		mregen += u.max_mana * C.FOUNTAIN_MANA_REGEN_PCT
	if u.is_building():
		_backdoor(u)
		if u.backdoor_active and u.backdoor_pool > 0.0:
			var heal := minf(C.BACKDOOR_REGEN * C.DT, u.backdoor_pool)
			u.backdoor_pool -= heal
			regen += heal / C.DT
	u.hp = minf(u.max_hp, u.hp + regen * C.DT)
	u.mana = minf(u.max_mana, u.mana + mregen * C.DT)
	if u.is_hero() and tick % 15 == 0:
		shop.update(u)
	if u.kind == K.WARD and time >= u.ward_expires:
		combat.kill(u, null)
	# pushes and leaps
	if not u.knock.is_empty() or not u.leap.is_empty() or not u.hop.is_empty():
		abilities.update_motion(u)

## Backdoor protection: a building takes half damage and heals what enemies did unless enemy lane creeps are near.
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

var _ancient_cache := {}

func _ancient_pos(team: int) -> Vector2:
	if _ancient_cache.has(team):
		return _ancient_cache[team]
	for b in map.buildings:
		if b.team == team and b.unit == "ancient":
			_ancient_cache[team] = b.pos
			return b.pos
	return Vector2.ZERO

func _respawns() -> void:
	for h in heroes:
		if not h.alive and h.respawn_at >= 0.0 and time >= h.respawn_at:
			respawn(h)

func respawn(h: SimUnit) -> void:
	h.alive = true
	h.respawn_at = -1.0
	h.pos = map.fountains[h.team] + Vector2(250, 250) * (1.0 if h.team == C.DAWN else -1.0)
	h.modifiers.clear()
	h.knock = {}
	h.leap = {}
	h.refresh_stats()
	h.hp = h.max_hp
	h.mana = h.max_mana
	orders.clear(h)
	events.append({"t": "respawn", "u": h.id})

func _cleanup() -> void:
	# corpses stay a moment for the death animation, then leave the unit list (heroes and buildings stay)
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		if not u.alive and not u.is_hero() and not u.is_building() and time - u.spawn_time > 0.0 and u.removed:
			units.remove_at(i)
			by_id.erase(u.id)

# ---- Couriers ------------------------------------------------------------------------------------------------------

## Couriers fly straight (no pathing): fetch the owner's stash at the fountain, carry it to the owner, return home.
func _couriers() -> void:
	for c in units:
		if c.kind != K.COURIER:
			continue
		if not c.alive:
			if c.respawn_at >= 0.0 and time >= c.respawn_at:
				c.alive = true
				c.removed = false
				c.respawn_at = -1.0
				c.hp = c.max_hp
				c.pos = map.fountains[c.team] + Vector2(150, 420) * (1.0 if c.team == C.DAWN else -1.0)
				c.courier_state = "idle"
				events.append({"t": "respawn", "u": c.id})
			continue
		var h := get_unit(c.owner_id)
		if h == null:
			continue
		var home: Vector2 = map.fountains[c.team]
		var goal := c.pos
		match c.courier_state:
			"fetch":
				goal = home
				if c.pos.distance_to(home) < 500.0:
					for i in h.stash.size():
						if h.stash[i] != null:
							for k in c.inventory.size():
								if c.inventory[k] == null:
									c.inventory[k] = h.stash[i]
									h.stash[i] = null
									break
					c.courier_state = "deliver" if c.inventory.any(func(x): return x != null) else "idle"
			"deliver":
				if not h.alive:
					c.courier_state = "return"
				else:
					goal = h.pos
					if c.pos.distance_to(h.pos) < 220.0:
						for k in c.inventory.size():
							var it = c.inventory[k]
							if it == null:
								continue
							for s in 9:
								if h.inventory[s] == null:
									h.inventory[s] = it
									c.inventory[k] = null
									break
						shop._combine_all(h)
						h.refresh_stats()
						events.append({"t": "delivered", "u": h.id})
						c.courier_state = "return"
			"return":
				goal = home
				if c.pos.distance_to(home) < 300.0:
					c.courier_state = "idle"
			"move":
				goal = c.courier_goal
				if c.pos.distance_to(goal) < 40.0:
					c.courier_state = "idle"
		var to := goal - c.pos
		var step := c.move_speed * C.DT
		c.moving = to.length() > 30.0
		if c.moving:
			c.facing = to.angle()
			c.pos += to.normalized() * minf(step, to.length())

# ---- Spatial queries ----------------------------------------------------------------------------------------------

func _rebuild_grid() -> void:
	_grid.clear()
	for u in units:
		if not u.alive:
			continue
		var key := Vector2i(floori(u.pos.x / GRID), floori(u.pos.y / GRID))
		if _grid.has(key):
			_grid[key].append(u)
		else:
			_grid[key] = [u]

## Living units whose centre lies within r of p (r is extended by the unit's hull when `edge` is set).
func query(p: Vector2, r: float, edge := false) -> Array:
	var out: Array = []
	var pad := 300.0 if edge else 0.0
	var c0 := Vector2i(floori((p.x - r - pad) / GRID), floori((p.y - r - pad) / GRID))
	var c1 := Vector2i(floori((p.x + r + pad) / GRID), floori((p.y + r + pad) / GRID))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var arr = _grid.get(Vector2i(cx, cy))
			if arr == null:
				continue
			for u: SimUnit in arr:
				if not u.alive:
					continue
				var lim := r + (u.hull if edge else 0.0)
				if u.pos.distance_squared_to(p) <= lim * lim:
					out.append(u)
	return out

# ---- Player commands --------------------------------------------------------------------------------------------

## Issue an order from a player or bot. order: {type: SimConst.Order, target: unit id, point: Vector2, ability: id,
## queue: bool}. Applies the attack-order aggro rules for creeps and towers.
func command(uid: int, o: Dictionary) -> void:
	var u := get_unit(uid)
	if u == null or not u.alive:
		return
	orders.issue(u, o, true)

func glyph(team: int) -> bool:
	if time < glyph_ready_at[team]:
		return false
	glyph_ready_at[team] = time + C.GLYPH_COOLDOWN
	for u in units:
		if not u.alive or u.team != team:
			continue
		if u.is_building():
			u.glyph_until = time + C.GLYPH_BUILDING_DURATION
		elif u.is_lane_creep():
			u.glyph_until = time + C.GLYPH_CREEP_DURATION
	events.append({"t": "glyph", "team": team})
	return true

# ---- Building rules -----------------------------------------------------------------------------------------------

## Towers are invulnerable until the previous tier in their lane falls; barracks and effigies until their lane's
## tier 3; tier 4 towers until any tier 3; the Ancient until both tier 4 towers.
func _update_invulnerability() -> void:
	for u in units:
		if not u.is_building():
			continue
		u.invulnerable = _protected(u)

func _protected(u: SimUnit) -> bool:
	match u.kind:
		K.FOUNTAIN:
			return true
		K.TOWER:
			if u.lane_tier == 1:
				return false
			if u.lane_tier == 4:
				return not _any_dead(u.team, "tower3")
			return _alive_building(u.team, "tower%d" % (u.lane_tier - 1), u.building_lane)
		K.BARRACKS, K.FILLER:
			return _alive_building(u.team, "tower3", u.building_lane)
		K.ANCIENT:
			return _alive_building(u.team, "tower4", "")
	return false

func _alive_building(team: int, def_id: String, lane: String) -> bool:
	for u in units:
		if u.team == team and u.alive and u.def.id == def_id and (lane == "" or u.building_lane == lane):
			return true
	return false

func _any_dead(team: int, def_id: String) -> bool:
	for u in units:
		if u.team == team and u.def.id == def_id and not u.alive:
			return true
	return false

func on_building_destroyed(u: SimUnit) -> void:
	if u.kind == K.BARRACKS:
		var kind_s := "melee" if u.def.id == "melee_rax" else "ranged"
		rax_dead["%d:%s:%s" % [u.team, u.building_lane, kind_s]] = true
	if u.kind == K.ANCIENT:
		winner = 1 - u.team
		events.append({"t": "victory", "team": winner})
	_update_invulnerability()
	vision.static_dirty = true

func lane_rax_dead(team: int, lane: String, kind_s: String) -> bool:
	return rax_dead.has("%d:%s:%s" % [team, lane, kind_s])

# ---- Clock helpers ---------------------------------------------------------------------------------------------------

func clock_text() -> String:
	var t := absf(time)
	var s := "%d:%02d" % [int(t) / 60, int(t) % 60]
	return ("-" + s) if time < 0.0 else s
