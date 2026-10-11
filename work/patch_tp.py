import re
def rw(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:60]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8').write(s)

rw('src/sim/sim_const.gd', [
    ('enum Kind { HERO, CREEP_MELEE, CREEP_RANGED, CREEP_SIEGE, CREEP_FLAG, NEUTRAL_CREEP, TOWER, BARRACKS, ANCIENT, FILLER, FOUNTAIN, WARD }',
     'enum Kind { HERO, CREEP_MELEE, CREEP_RANGED, CREEP_SIEGE, CREEP_FLAG, NEUTRAL_CREEP, TOWER, BARRACKS, ANCIENT, FILLER, FOUNTAIN, WARD, COURIER }'),
    ('# ---- Fountain', '''# ---- Town Portal, buyback, courier --------------------------------------------------------------------------------
const TP_CHANNEL := 3.0                     # items.txt tooltip_channel_time
const TP_COOLDOWN := 80.0                   # items.txt AbilityCooldown
const TP_MANA := 75.0                       # items.txt AbilityManaCost
const COURIER_BOUNTY := 75                  # APPROX
const COURIER_RESPAWN := 60.0               # APPROX

# ---- Fountain'''),
])

rw('src/sim/sim_unit.gd', [
    ('var knock: Dictionary = {}                 # {from, to, t, dur}',
     '''var knock: Dictionary = {}                 # {from, to, t, dur}
var channel: Dictionary = {}               # {ability, until, dest}: channelling (Town Portal)
var tp_charges := 0                        # Town Portal scrolls in the dedicated slot
var courier_id := -1                       # heroes: their courier
var owner_id := -1                         # couriers: their hero
var courier_state := "idle"'''),
    ('''		gold_reliable = 0
		gold_unreliable = C.STARTING_GOLD''', '''		gold_reliable = 0
		gold_unreliable = C.STARTING_GOLD
		tp_charges = 1
	if kind == K.COURIER:
		inventory.resize(6)
		add_modifier({"id": "flying", "source": p_id, "expires": -1.0, "flying": true})'''),
])

rw('src/sim/sim_data.gd', [
    ('''	_add("ward_observer",''', '''	_add("courier", {"name": "Courier", "kind": K.COURIER, "hull": 8.0, "hp": 75.0, "can_attack": false,
		"move_speed": 380.0, "turn_rate": 1.0, "vision_day": 500.0, "vision_night": 500.0, "model": "courier", "flying": true})
	_add("ward_observer",'''),
    ('''	_it("observer_ward", "Watcher Ward",''', '''	_it("tp_scroll", "Town Portal Scroll", 100, {"use": "tp", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"channel": SimConst.TP_CHANNEL}})
	_it("observer_ward", "Watcher Ward",'''),
])

# TP as an ability-like cast handled by SimAbilities, channel handled in SimOrders
rw('src/sim/sim_abilities.gd', [
    ('''	if slot >= 0:
		return _item_error(u, slot, target, point)
	var a := SimData.ability(aid)''', '''	if slot >= 0:
		return _item_error(u, slot, target, point)
	if aid == "tp":
		if u.tp_charges <= 0:
			return "No Town Portal Scroll"
		if cooldown_left(u, "tp") > 0.0:
			return "Town Portal on cooldown"
		if u.mana < C.TP_MANA:
			return "Not enough mana"
		if u.is_stunned():
			return "Stunned"
		return ""
	var a := SimData.ability(aid)'''),
    ('''	var a := SimData.ability(aid)
	if a.behavior == "autocast_attack":
		return u.attack_range
	return float(a.range)''', '''	if aid == "tp":
		return INF
	var a := SimData.ability(aid)
	if a.behavior == "autocast_attack":
		return u.attack_range
	return float(a.range)'''),
    ('''	if slot >= 0:
		return 0.0
	return float(SimData.ability(aid).get("cast_point", 0.0))''', '''	if slot >= 0 or aid == "tp":
		return 0.0
	return float(SimData.ability(aid).get("cast_point", 0.0))'''),
    ('''	if slot >= 0:
		_use_item(u, slot, t, p)
		return
	var a := SimData.ability(aid)
	var lv := u.ability_level_of(aid)''', '''	if slot >= 0:
		_use_item(u, slot, t, p)
		return
	if aid == "tp":
		_start_tp(u, p)
		return
	var a := SimData.ability(aid)
	var lv := u.ability_level_of(aid)'''),
    ('''# ---- Attack modifier (orb)''', '''# ---- Town Portal -----------------------------------------------------------------------------------------------------

## Teleport to the allied building nearest the chosen point after a 3 s channel. The scroll, mana and cooldown are
## spent when the channel starts; moving, stopping or being stunned cancels it.
func _start_tp(u: SimUnit, p: Vector2) -> void:
	var best: SimUnit = null
	var bd := INF
	for b in w.units:
		if not b.alive or b.team != u.team or not b.is_building():
			continue
		var d := b.pos.distance_to(p)
		if d < bd:
			bd = d
			best = b
	if best == null:
		return
	var dir := (p - best.pos)
	if dir.length() < 1.0:
		dir = (w.map.fountains[1 - u.team] - best.pos)
	var dest := best.pos + dir.normalized() * (best.hull + u.hull + 120.0)
	if not w.map.is_walkable(dest):
		var c := w.map.nearest_walkable(w.map.world_to_cell(dest))
		dest = w.map.cell_center(c.x, c.y)
	u.tp_charges -= 1
	u.mana -= C.TP_MANA
	u.ability_ready["tp"] = w.time + C.TP_COOLDOWN
	u.channel = {"ability": "tp", "until": w.time + C.TP_CHANNEL, "dest": dest, "building": best.id}
	w.events.append({"t": "tp_start", "u": u.id, "dest": dest, "until": u.channel.until})

# ---- Attack modifier (orb)'''),
])

rw('src/sim/sim_orders.gd', [
    ('''func update(u: SimUnit) -> void:
	if u.is_stunned():''', '''func update(u: SimUnit) -> void:
	if not u.channel.is_empty():
		if u.is_stunned():
			cancel_channel(u)
		elif w.time >= float(u.channel.until):
			var dest: Vector2 = u.channel.dest
			u.channel = {}
			u.pos = dest
			u.path = PackedVector2Array()
			u.order = O.NONE
			u.atk_target = -1
			w.events.append({"t": "tp_end", "u": u.id, "pos": dest})
			return
		else:
			return
	if u.is_stunned():'''),
    ('''func issue(u: SimUnit, o: Dictionary, from_player: bool) -> void:
	var type: int = o.get("type", O.NONE)
	if o.get("queue", false) and not u.is_idle():
		u.order_queue.append(o)
		return''', '''func cancel_channel(u: SimUnit) -> void:
	if not u.channel.is_empty():
		u.channel = {}
		w.events.append({"t": "tp_cancel", "u": u.id})

func issue(u: SimUnit, o: Dictionary, from_player: bool) -> void:
	var type: int = o.get("type", O.NONE)
	if o.get("queue", false) and (not u.is_idle() or not u.channel.is_empty()):
		u.order_queue.append(o)
		return
	# any new order breaks a channel
	if not u.channel.is_empty():
		cancel_channel(u)'''),
])

rw('src/sim/sim_shop.gd', [
    ('''	var here := in_shop(u)
	var comps: Array = d.components
	if comps.is_empty():''', '''	var here := in_shop(u)
	var comps: Array = d.components
	if item_id == "tp_scroll":
		# Town Portal scrolls live in their own slot
		u.tp_charges += 1
		_spend(u, cost)
		w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost})
		return ""
	if comps.is_empty():'''),
])

rw('src/sim/sim_world.gd', [
    ('''func spawn_hero(def_id: String, team: int, look := {}) -> SimUnit:
	var u := spawn(def_id, team, map.fountains[team] + Vector2(300, 300) * (1.0 if team == C.DAWN else -1.0))
	u.look = look
	u.facing = PI * 0.25 if team == C.DAWN else -PI * 0.75
	return u''', '''func spawn_hero(def_id: String, team: int, look := {}) -> SimUnit:
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

## Send the hero's courier to fetch the stash and bring it to them.
func courier_deliver(h: SimUnit) -> String:
	var c := get_unit(h.courier_id)
	if c == null or not c.alive:
		return "Courier is dead"
	c.courier_state = "fetch"
	return ""'''),
    ('''	ai.think()
	for b in bots:
		b.think()''', '''	ai.think()
	for b in bots:
		b.think()
	_couriers()'''),
    ('''# ---- Spatial queries''', '''# ---- Couriers ------------------------------------------------------------------------------------------------------

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
		var to := goal - c.pos
		var step := c.move_speed * C.DT
		c.moving = to.length() > 30.0
		if c.moving:
			c.facing = to.angle()
			c.pos += to.normalized() * minf(step, to.length())

# ---- Spatial queries'''),
])

rw('src/sim/sim_combat.gd', [
    ('''		if t.is_hero():
			_hero_death(t, killer)
		elif t.is_creep():''', '''		if t.is_hero():
			_hero_death(t, killer)
		elif t.kind == K.COURIER:
			t.respawn_at = w.time + C.COURIER_RESPAWN
			t.removed = false
			for i in t.inventory.size():
				t.inventory[i] = null
			if killer != null and killer.is_hero() and killer.team != t.team:
				give_gold(killer, C.COURIER_BOUNTY, false, t.pos)
		elif t.is_creep():'''),
    ('''	for u in w.units:
		if not u.alive and not u.removed and not u.is_hero() and w.time - u.death_at > 4.0:
			u.removed = true''', '''	for u in w.units:
		if not u.alive and not u.removed and not u.is_hero() and u.kind != K.COURIER and w.time - u.death_at > 4.0:
			u.removed = true'''),
])
print("patched")
