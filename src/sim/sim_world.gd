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
var next_neutral_upgrade_at := C.NEUTRAL_UPGRADE_INTERVAL
var glyph_ready_at := [C.GLYPH_INITIAL_COOLDOWN, C.GLYPH_INITIAL_COOLDOWN]
var rax_dead := {}                         # "team:lane:melee" -> true
var first_blood := false
var winner := -1
var paused := false
## The element table (SimConst.element_mult) is on. Mechanics tests of other rules turn it off to check Dota's numbers
## on their own; matches always play with it.
var elements := true
var debug_flags := {}                      # Debug panel switches (SimDebug): god, free_spells, reveal, passive_bot
var _gold_acc := {}
var _grid := {}
const GRID := 512.0

var orders: SimOrders
var combat: SimCombat
var ai: SimAI
var vision: SimVision
var shop: SimShop
var abilities: SimAbilities
var items: SimItems
var status: SimStatus
var orbs: SimOrbs
var bots: Array = []                       # SimBot instances
var brains := [null, null]                 # SimTeamAI per team (made when the team's first bot joins)
var chat_log: Array = []                   # [{team, u, name, text, t}] team chat, newest last (all teams)
var pings: Array = []                      # [{id, team, pos, kind, target, from, t}] newest last
var _next_ping := 1

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
	items = SimItems.new(self)
	status = SimStatus.new(self)
	orbs = SimOrbs.new(self)

func dispose() -> void:
	for b in bots:
		b.w = null
	bots.clear()
	for tb in brains:
		if tb != null:
			tb.w = null
	brains = [null, null]
	for h in [orders, combat, ai, vision, shop, abilities, items, status, orbs]:
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
	u.courier_items = c.inventory
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
	var c := _courier_of(h)
	if c == null:
		return "Courier is dead"
	c.courier_state = "move"
	c.courier_goal = p
	c.courier_next = ""
	return ""

func _courier_of(h: SimUnit) -> SimUnit:
	if h == null:
		return null
	var c := get_unit(h.courier_id)
	if c == null or not c.alive:
		return null
	return c

## The courier's commands, as in Dota (abilities.txt courier_*): "return" (Return to Base), "retrieve" (Retrieve
## Items: take the stash and the owner's items lying in the fountain area, then wait at base), "stash" (Return Items
## to Stash), "transfer" (Transfer Items: carry what it holds to the hero), "deliver" (take the stash, then transfer),
## "burst" (Speed Burst, from level 10), "shield" (Shield, from level 20), "auto" (Auto Deliver on / off).
func courier_command(h: SimUnit, cmd: String) -> String:
	if h == null:
		return "No hero"
	if cmd == "auto":
		var cc := get_unit(h.courier_id)
		if cc == null:
			return "No courier"
		cc.courier_auto = not cc.courier_auto
		events.append({"t": "courier_auto", "u": cc.id, "on": cc.courier_auto})
		return ""
	var c := _courier_of(h)
	if c == null:
		return "Courier is dead"
	match cmd:
		"return":
			c.courier_state = "return"
		"stash", "transfer":
			if not _has_items(c.inventory):
				return "The courier carries nothing"
			c.courier_state = cmd
		"retrieve", "deliver":
			c.courier_state = "collect"
			c.courier_next = cmd
		"burst":
			if h.level < C.COURIER_BURST_LEVEL:
				return "Speed Burst needs level %d" % C.COURIER_BURST_LEVEL
			if time < c.courier_burst_ready:
				return "Speed Burst on cooldown"
			c.courier_burst_ready = time + C.COURIER_BURST_COOLDOWN
			c.add_modifier({"id": "courier_burst", "source": c.id, "expires": time + C.COURIER_BURST_TIME, "fx": "slip"})
			events.append({"t": "courier_burst", "u": c.id})
		"shield":
			if h.level < C.COURIER_SHIELD_LEVEL:
				return "Shield needs level %d" % C.COURIER_SHIELD_LEVEL
			if time < c.courier_shield_ready:
				return "Shield on cooldown"
			c.courier_shield_ready = time + C.COURIER_SHIELD_COOLDOWN
			c.add_modifier({"id": "courier_shield", "source": c.id, "expires": time + C.COURIER_SHIELD_TIME,
				"invulnerable": true, "fx": "spell_shield"})
			events.append({"t": "courier_shield", "u": c.id})
		_:
			return "Unknown command"
	if cmd in ["return", "stash", "transfer", "retrieve", "deliver"]:
		events.append({"t": "courier_order", "u": c.id, "cmd": cmd})
	return ""

## Send the hero's courier to fetch the stash (and the hero's items lying in the fountain area) and bring it to them.
func courier_deliver(h: SimUnit) -> String:
	return courier_command(h, "deliver")

static func _has_items(arr: Array) -> bool:
	for it in arr:
		if it != null:
			return true
	return false

## Whether the courier waits at its fountain (purchases made away from the shop go to it).
func courier_at_base(c: SimUnit) -> bool:
	return c != null and c.alive and c.pos.distance_to(map.fountains[c.team]) <= C.COURIER_BASE_RADIUS \
		and c.courier_state in ["idle", "retrieve", "return", "stash"]

# ---- Items on the ground --------------------------------------------------------------------------------------------

var ground_items: Array = []                # {gid, item, pos, owner}: dropped items (anyone may pick them up)
var _next_gid := 1

func drop_item(it: Dictionary, p: Vector2, owner_id: int) -> Dictionary:
	var g := {"gid": _next_gid, "item": it, "pos": p, "owner": int(it.get("owner", owner_id))}
	_next_gid += 1
	ground_items.append(g)
	events.append({"t": "item_drop", "gid": g.gid, "item": it.id, "pos": p})
	return g

func ground_item(gid: int) -> Dictionary:
	for g in ground_items:
		if int(g.gid) == gid:
			return g
	return {}

func take_ground_item(gid: int, by: SimUnit) -> Dictionary:
	for i in ground_items.size():
		if int(ground_items[i].gid) == gid:
			var g: Dictionary = ground_items[i]
			ground_items.remove_at(i)
			events.append({"t": "item_pickup", "gid": gid, "u": by.id if by else -1})
			return g
	return {}

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
	var t := Time.get_ticks_usec() if profiling else 0
	_clock()
	_rebuild_grid()
	if tick % 6 == 0:
		_update_base_creeps()
	if profiling:
		for u in units:
			if u.alive:
				var tu := Time.get_ticks_usec()
				_pre_unit(u)
				_prof("  pre:%d" % u.kind, tu)
	else:
		for u in units:
			if u.alive:
				_pre_unit(u)
	if profiling: t = _prof("pre", t)
	ai.think()
	if profiling: t = _prof("ai", t)
	for tb in brains:
		if tb != null:
			tb.think()
	if profiling: t = _prof("brains", t)
	for b in bots:
		b.think()
	if profiling: t = _prof("bots", t)
	_couriers()
	if tick % 6 == 0:
		for h in heroes:
			shop.auto_buy(h)
	if not debug_flags.is_empty():
		SimDebug.tick(self)
	if profiling: t = _prof("couriers", t)
	if profiling:
		for u in units:
			if u.alive and u.kind != K.COURIER:
				var tu := Time.get_ticks_usec()
				orders.update(u)
				_prof("  ord:%d" % u.kind, tu)
	else:
		for u in units:
			if u.alive and u.kind != K.COURIER:
				orders.update(u)
	if profiling: t = _prof("orders", t)
	combat.update_projectiles()
	if profiling: t = _prof("projectiles", t)
	abilities.kits2.tick()
	abilities.update_effects()
	items.update()
	status.update()
	orbs.update()
	if profiling: t = _prof("effects", t)
	combat.process_deaths()
	_respawns()
	if profiling: t = _prof("deaths", t)
	if tick % C.VISION_UPDATE_TICKS == 0:
		vision.prune_sources()
		vision.update()
	if profiling: t = _prof("vision", t)
	_cleanup()
	if profiling: t = _prof("cleanup", t)

## A fingerprint of the match state (multiplayer peers compare it to catch a desync): the clock, the RNG, every unit's
## place, health, mana, orders, gold, level and items, and the counts of projectiles, effects and living trees.
func state_hash() -> int:
	var n := PackedInt64Array([tick, next_id, rng.state, units.size(), projectiles.size(), effects.size(), wave,
		winner, ground_items.size()])
	var f := PackedFloat64Array([time])
	for u in units:
		n.append_array([u.id, int(u.alive), u.order, u.atk_target, u.gold_reliable, u.gold_unreliable, u.level,
			u.atk_phase, u.cast_phase, u.modifiers.size(), u.ability_points])
		f.append_array([u.pos.x, u.pos.y, u.hp, u.mana, u.facing, u.xp])
		for it in u.inventory:
			n.append(hash(String(it.id)) if it != null else 0)
	var trees := 0
	for t in map.trees:
		if t.alive:
			trees += 1
	n.append(trees)
	return hash(n.to_byte_array()) ^ (hash(f.to_byte_array()) * 31)

## Profiling (tools only): milliseconds spent in each part of the step, summed over ticks.
var profiling := false
var prof := {}
var _power_cache := {}                      # SimBotKits.power results of this tick (a cache, not state)
var _power_tick := -1

func _prof(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	prof[key] = float(prof.get(key, 0.0)) + (t1 - t0) / 1000.0
	return t1

func _clock() -> void:
	# lane creep waves every 30 s from 0:00
	if time >= next_wave_at and time >= 0.0:
		wave += 1
		ai.spawn_wave(wave)
		next_wave_at = wave * C.WAVE_INTERVAL
	# neutral camps at every minute from 1:00; neutrals grow every 7:30
	if time >= next_neutral_at:
		next_neutral_at += C.NEUTRAL_SPAWN_INTERVAL
		ai.spawn_neutrals()
	if time >= next_neutral_upgrade_at:
		next_neutral_upgrade_at += C.NEUTRAL_UPGRADE_INTERVAL
		ai.upgrade_neutrals()
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
	if not u.modifiers.is_empty():
		u.expire_modifiers(time)
	if u.stats_dirty:
		u.refresh_stats()
	# fast path: a creep or neutral at full health and mana (most sleeping camps, fresh waves, creeps under auras) has
	# nothing to regenerate (no modifier lowers health through "regen"); only cooldown shifts and pushes remain
	var k := u.kind
	if k != K.HERO and k != K.WARD and not (k >= K.TOWER and k <= K.FOUNTAIN) and u.hp >= u.max_hp 			and u.mana >= u.max_mana and u.hp_regen >= 0.0 and u.mana_regen >= 0.0:
		if u.cooldown_rate != 0.0:
			_shift_cooldowns(u)
		if not u.knock.is_empty() or not u.leap.is_empty() or not u.hop.is_empty():
			abilities.update_motion(u)
		return
	# regeneration (fountain aura, consumables)
	if u.is_hero() and u.pos.distance_to(map.fountains[u.team]) < C.FOUNTAIN_AURA_RADIUS:
		# the fountain's aura lingers 3 s after leaving its radius
		u.add_modifier({"id": "fountain", "source": -3, "expires": time + C.FOUNTAIN_LINGER, "fountain": true,
			"fx": "fountain"})
	if u.cooldown_rate != 0.0:
		_shift_cooldowns(u)
	var rates := regen_rates(u)
	var regen: float = rates.x
	var mregen: float = rates.y
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

## Cooldown rate (Tock's Time Bolt, Fast Forward, Stop Time): every running cooldown of the unit's abilities and
## items moves by the rate each tick: +1 runs twice as fast, -0.4 runs 40% slower, -1 stands still.
func _shift_cooldowns(u: SimUnit) -> void:
	var shift := -u.cooldown_rate * C.DT
	for aid in u.ability_ready:
		var r := float(u.ability_ready[aid])
		if r > time:
			u.ability_ready[aid] = maxf(time, r + shift)
	for it in u.inventory:
		if it != null and float(it.get("ready", C.LONG_AGO)) > time:
			it["ready"] = maxf(time, float(it.ready) + shift)

## Health and mana restored per second: (total hp, total mana, own hp, own mana). "Own" is the unit's base regen plus
## its attributes; the rest (items, auras, consumables, the fountain) is bonus, which the HUD shows separately. Health
## restoration amplification (the Heavy Sword family) scales all of it, mana regeneration amplification the mana.
func regen_rates(u: SimUnit) -> Vector4:
	var regen := u.hp_regen
	var mregen := u.mana_regen
	if u.hp_regen_pct != Vector2.ZERO:
		regen += u.max_hp * u.hp_regen_pct.x + (u.max_hp - u.hp) * u.hp_regen_pct.y
	for m in u.modifiers:
		regen += float(m.get("regen", 0.0))
		mregen += float(m.get("mana_regen", 0.0))
		if m.get("fountain", false):
			regen += u.max_hp * C.FOUNTAIN_HP_REGEN_PCT
			mregen += u.max_mana * C.FOUNTAIN_MANA_REGEN_PCT
	if u.is_hero():
		var orb := orbs.healing(u)
		regen += orb.x
		mregen += orb.y
	if regen > 0.0:
		regen *= (1.0 + u.heal_amp) * (1.0 - u.heal_reduction())
	if mregen > 0.0:
		mregen *= 1.0 + u.mana_regen_amp
	return Vector4(regen, mregen, u.hp_regen_base, u.mana_regen_base)

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
	h.was_in_shop = false                     # respawning in the fountain counts as arriving: the stash empties
	h.pos = map.fountains[h.team] + Vector2(250, 250) * (1.0 if h.team == C.DAWN else -1.0)
	h.modifiers.clear()
	h.knock = {}
	h.leap = {}
	h.toggles.clear()
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

## Couriers: their level is the owner's; they walk (with pathing) until level 4, then fly straight. Tasks:
## collect (pick up the owner's items lying in the fountain area) -> fetch / retrieve (take the stash) -> deliver /
## transfer (fly to the hero and hand over what fits) -> return; stash (put everything back in the stash); move; idle.
## Auto Deliver sends it out whenever it waits at base and the stash, its bags or the Well hold something.
func _couriers() -> void:
	for c in units:
		if c.kind != K.COURIER:
			continue
		var h := get_unit(c.owner_id)
		if not c.alive:
			if c.respawn_at >= 0.0 and time >= c.respawn_at:
				c.alive = true
				c.removed = false
				c.respawn_at = -1.0
				c.hp = c.max_hp
				c.pos = map.fountains[c.team] + Vector2(150, 420) * (1.0 if c.team == C.DAWN else -1.0)
				c.courier_state = "idle"
				c.path = PackedVector2Array()
				events.append({"t": "respawn", "u": c.id})
			continue
		if h == null:
			continue
		var lvl := h.level
		c.level = lvl
		var flying := lvl >= C.COURIER_FLY_LEVEL
		if flying != not c.get_modifier("flying").is_empty():
			c.remove_modifier("flying")
			if flying:
				c.add_modifier({"id": "flying", "source": c.id, "expires": INF, "flying": true})
				events.append({"t": "courier_fly", "u": c.id})
		c.move_speed = (C.COURIER_SPEED + C.COURIER_SPEED_PER_LEVEL * lvl) \
			* (1.0 + C.COURIER_BURST_SPEED if not c.get_modifier("courier_burst").is_empty() else 1.0)
		var home: Vector2 = map.fountains[c.team]
		# healed fully in the fountain (couriers never regenerate elsewhere)
		if c.pos.distance_to(home) < C.FOUNTAIN_AURA_RADIUS:
			c.hp = c.max_hp
		if c.courier_auto and c.courier_state == "idle" and c.pos.distance_to(home) <= C.COURIER_BASE_RADIUS \
				and h.alive and (_has_items(h.stash) or _has_items(c.inventory) or not _owner_items_in_well(h).is_empty()):
			c.courier_state = "collect"
			c.courier_next = "deliver"
		var goal := c.pos
		var stop := 30.0
		match c.courier_state:
			"collect":
				# the owner's items lying in the fountain area, nearest first, then on to the stash
				var g: Dictionary = {}
				var gd := INF
				for x in _owner_items_in_well(h):
					var d: float = c.pos.distance_to(x.pos)
					if d < gd:
						gd = d
						g = x
				if g.is_empty() or c.inventory.find(null) < 0:
					c.courier_state = "retrieve" if c.courier_next == "retrieve" else "fetch"
					goal = home
				else:
					goal = g.pos
					stop = 60.0
					if gd <= C.ITEM_REACH:
						var got := take_ground_item(int(g.gid), c)
						c.inventory[c.inventory.find(null)] = got.item
			"fetch", "retrieve":
				goal = home
				if c.pos.distance_to(home) < 500.0:
					_courier_take_stash(c, h)
					if c.courier_state == "fetch":
						c.courier_state = "deliver" if _has_items(c.inventory) else "idle"
					else:
						c.courier_state = "idle"
			"deliver", "transfer":
				if not h.alive:
					c.courier_state = "return"
				else:
					goal = h.pos
					stop = 120.0
					if c.pos.distance_to(h.pos) < C.COURIER_REACH:
						var gave := false
						for k in c.inventory.size():
							var it = c.inventory[k]
							if it != null and shop.place_in_bags(h, it):
								c.inventory[k] = null
								gave = true
						shop.combine_all(h)
						h.refresh_stats()
						if gave:
							events.append({"t": "delivered", "u": h.id})
						# anything that did not fit stays on the courier, as in Dota
						c.courier_state = "return"
			"return":
				goal = home
				if c.pos.distance_to(home) < 300.0:
					c.courier_state = "idle"
			"stash":
				goal = home
				if c.pos.distance_to(home) < 500.0:
					for k in c.inventory.size():
						if c.inventory[k] != null:
							var slot := h.stash.find(null)
							if slot >= 0:
								h.stash[slot] = c.inventory[k]
								c.inventory[k] = null
					shop.combine_all(h)
					c.courier_state = "idle"
			"move":
				goal = c.courier_goal
				if c.pos.distance_to(goal) < 40.0:
					c.courier_state = "idle"
		_courier_step(c, goal, stop, flying)

func _courier_take_stash(c: SimUnit, h: SimUnit) -> void:
	for i in h.stash.size():
		if h.stash[i] == null:
			continue
		var k := c.inventory.find(null)
		if k < 0:
			break
		c.inventory[k] = h.stash[i]
		h.stash[i] = null

## Ground items that belong to the hero and lie in its fountain area (the Well).
func _owner_items_in_well(h: SimUnit) -> Array:
	var out: Array = []
	var home: Vector2 = map.fountains[h.team]
	for g in ground_items:
		if int(g.owner) == h.id and (g.pos as Vector2).distance_to(home) <= C.WELL_RADIUS:
			out.append(g)
	return out

## Fly straight when flying; walk the pathing grid before that (ground couriers do not collide with units).
func _courier_step(c: SimUnit, goal: Vector2, stop: float, flying: bool) -> void:
	var to := goal - c.pos
	if to.length() <= stop:
		c.moving = false
		c.path = PackedVector2Array()
		return
	if flying:
		var step := c.move_speed * C.DT
		c.moving = true
		c.facing = to.angle()
		c.pos += to.normalized() * minf(step, to.length())
		return
	c.moving = false
	orders.move_toward(c, goal, stop)

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

## Fortify (Dota's glyph): the team's buildings take no damage for 7 s and its lane creeps for 3 s; its tier 2+
## towers splash, mark and shoot faster meanwhile (SimCombat.fortified_tower). `by`: the hero who pressed it (the
## allies are told who).
func glyph(team: int, by := -1) -> bool:
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
	events.append({"t": "glyph", "team": team, "by": by, "until": time + C.GLYPH_BUILDING_DURATION})
	return true

# ---- Team chat and pings -------------------------------------------------------------------------------------------

## The team's brain (lane plan, calls, ping replies), made on first use.
func brain(team: int) -> SimTeamAI:
	if team < 0 or team > 1:
		return null
	if brains[team] == null:
		brains[team] = SimTeamAI.new(self, team)
	return brains[team]

## A team chat line from a hero (or -1 for the game). Teams only read their own lines.
func chat(team: int, from_id: int, text: String) -> void:
	var u := get_unit(from_id)
	var who := ""
	if u != null:
		who = u.bot_name if u.bot_name != "" else String(u.look.get("display_name", u.def.get("name", "")))
	var line := {"team": team, "u": from_id, "name": who, "text": text, "t": time}
	chat_log.append(line)
	if chat_log.size() > 80:
		chat_log.pop_front()
	events.append({"t": "chat", "team": team, "u": from_id, "name": who, "text": text})
	if brains[team] != null and u != null and not u.bot:
		brains[team].on_player_chat(u, text)

## A ping for the team: kind "move" (ground), "attack" (an enemy unit or building), "defend" (one of ours), "danger"
## (Ctrl + Alt: get out of here). The kind is worked out from what lies under the ping when not given.
func ping(team: int, pos: Vector2, from_id: int, target_id := -1, kind := "") -> Dictionary:
	var t := get_unit(target_id)
	if kind == "":
		if t != null and t.alive:
			kind = "attack" if t.team != team else "defend"
		else:
			kind = "move"
	var pg := {"id": _next_ping, "team": team, "pos": pos, "kind": kind, "target": target_id, "from": from_id, "t": time}
	_next_ping += 1
	pings.append(pg)
	while pings.size() > 30:
		pings.pop_front()
	events.append({"t": "ping", "team": team, "pos": pos, "kind": kind, "target": target_id, "u": from_id})
	if brains[team] != null:
		brains[team].on_ping(pg)
	return pg

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
