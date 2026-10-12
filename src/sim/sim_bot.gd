class_name SimBot
extends RefCounted
## A laning bot for one hero. It thinks five times a second and acts only through the same orders a player issues
## (SimWorld.command, buy, learn), so it obeys every rule a player does.
##
## Laning: stand behind its creep wave, last-hit with damage prediction, deny, harass with its spells, respect enemy
## tower range, retreat to heal, buy its build at the fountain.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

var w: SimWorld
var hero_id := -1
var lane := "mid"
var name := "Bot"
var state := "lane"
var passive := false                       # Debug panel: the bot stands still (a training dummy)
var _next_think := C.LONG_AGO
var _last_order := {}
var skill_order := ["masterful_archery", "gale_impact", "burst_shot", "masterful_archery", "burst_shot",
	"blood_ranger_ult", "burst_shot", "burst_shot", "masterful_archery", "masterful_archery", "blood_ranger_ult",
	"gale_impact", "gale_impact", "gale_impact", "blood_ranger_ult"]
var build := ["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "branch",
	"branch", "magic_wand", "boots", "gloves", "boots_elves", "power_treads", "blade_alacrity", "yasha",
	"broadsword", "lifesteal", "mask_of_madness"]
var _build_i := 0

const EZEE_SKILLS := ["dark_stomp", "tainted_touch", "leap_strike", "dark_stomp", "dark_stomp", "unholy_might",
	"dark_stomp", "leap_strike", "leap_strike", "leap_strike", "unholy_might", "tainted_touch", "tainted_touch",
	"tainted_touch", "unholy_might"]
const EZEE_BUILD := ["tango", "salve", "gauntlets", "quelling_blade", "circlet", "branch", "branch", "magic_stick",
	"boots", "magic_wand", "belt_str", "ring_regen", "chainmail", "broadsword", "lifesteal", "mask_of_madness"]

var kit := "blood_ranger"

func _init(world: SimWorld, hid: int, p_lane := "mid", p_name := "Bot") -> void:
	w = world
	hero_id = hid
	lane = p_lane
	name = p_name
	var h := hero()
	if h != null:
		kit = String(h.def.id)
	if kit == "ezee":
		skill_order = EZEE_SKILLS
		build = EZEE_BUILD

func hero() -> SimUnit:
	return w.get_unit(hero_id)

func think() -> void:
	if w == null or w.time < _next_think or passive:
		return
	_next_think = w.time + 0.2
	var h := hero()
	if h == null or not h.alive:
		return
	h.bot = true
	h.auto_attack = false
	_learn(h)
	_shop(h)
	if h.hp < h.max_hp * 0.22 and state != "retreat":
		state = "retreat"
	if state == "retreat":
		if h.hp >= h.max_hp * 0.92 and h.mana >= h.max_mana * 0.6:
			state = "lane"
		else:
			_go(h, w.map.fountains[h.team])
			return
	if w.time < 0.0 and not _enemy_hero_near(h, 1300.0):
		# before the horn: wait by the tier 1 tower, but fight any hero that comes looking for a kill
		_go(h, _waiting_spot(h))
		return
	_lane(h)

# ---- Skills and items -------------------------------------------------------------------------------------------

func _learn(h: SimUnit) -> void:
	var guard := 0
	while h.ability_points > 0 and guard < 4:
		guard += 1
		var done := false
		for aid in skill_order:
			if w.abilities.can_learn(h, aid) and _wants(h, aid):
				w.abilities.learn(h, aid)
				done = true
				break
		if not done:
			for aid in h.abilities:
				if w.abilities.learn(h, aid):
					done = true
					break
		if not done:
			break

func _wants(h: SimUnit, aid: String) -> bool:
	# follow the skill order: count how many times this ability appears before the current level
	var want := 0
	for i in mini(h.level, skill_order.size()):
		if skill_order[i] == aid:
			want += 1
	return h.ability_level_of(aid) < want

func _shop(h: SimUnit) -> void:
	var guard := 0
	while _build_i < build.size() and guard < 6:
		guard += 1
		var id: String = build[_build_i]
		var cost := w.shop.price(h, id)
		if h.gold() < cost:
			break
		var err := w.shop.buy(h, id)
		if err != "" and err != "Not enough gold":
			_build_i += 1
			continue
		if err == "":
			_build_i += 1
	# away from the shop, the courier brings what is waiting in the stash
	if h.stash.any(func(x): return x != null) and not w.shop.in_shop(h):
		var c := w.get_unit(h.courier_id)
		if c and c.alive and c.courier_state == "idle":
			w.courier_deliver(h)
	if h.tp_charges == 0 and h.gold() >= 100 + w.shop.price(h, build[mini(_build_i, build.size() - 1)]) * 0:
		w.shop.buy(h, "tp_scroll")
	# drink a salve when hurt and not in the fountain
	if h.hp < h.max_hp * 0.55:
		_use_item(h, "salve")

func _use_item(h: SimUnit, item_id: String) -> bool:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == item_id and h.get_meta("used_" + item_id, -99.0) + 13.0 < w.time:
			h.set_meta("used_" + item_id, w.time)
			w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": i})
			return true
	return false

# ---- Laning -------------------------------------------------------------------------------------------------------

func _enemy_hero_near(h: SimUnit, r: float) -> bool:
	for u: SimUnit in w.query(h.pos, r):
		if u.alive and u.is_hero() and u.team != h.team and w.vision.sees(h.team, u):
			return true
	return false

func _waiting_spot(h: SimUnit) -> Vector2:
	var t1 := _own_tower(h, 1)
	if t1 == null:
		return w.map.fountains[h.team]
	var path := w.map.lane_path(lane, h.team)
	return t1.pos + (path[0] - t1.pos).normalized() * 250.0

func _own_tower(h: SimUnit, tier: int) -> SimUnit:
	for u in w.units:
		if u.alive and u.team == h.team and u.kind == K.TOWER and u.lane_tier == tier and u.building_lane == lane:
			return u
	return null

var _next_tango := C.LONG_AGO

## Casting, channelling or walking to a cast target: let it finish rather than interrupt it.
func _busy(h: SimUnit) -> bool:
	return h.cast_phase != SimUnit.CastPhase.NONE or not h.channel.is_empty() 		or h.order in [O.CAST_POINT, O.CAST_NO_TARGET] and w.time < _cast_deadline

var _cast_deadline := C.LONG_AGO
var _lh_id := -1
var _lh_until := C.LONG_AGO
var _trade_id := -1
var _trade_until := C.LONG_AGO
var _next_trade := C.LONG_AGO

func _lane(h: SimUnit) -> void:
	if _busy(h):
		return
	var path := w.map.lane_path(lane, h.team)
	var allies: Array[SimUnit] = []
	var foes: Array[SimUnit] = []
	var enemy_heroes: Array[SimUnit] = []
	var enemy_towers: Array[SimUnit] = []
	for u: SimUnit in w.query(h.pos, 1600.0):
		if not u.alive:
			continue
		if u.is_lane_creep():
			if u.team == h.team:
				allies.append(u)
			elif w.vision.sees(h.team, u):
				foes.append(u)
		elif u.is_hero() and u.team != h.team and w.vision.sees(h.team, u):
			enemy_heroes.append(u)
		elif u.kind == K.TOWER and u.team != h.team:
			enemy_towers.append(u)
	# use a salve / tango when chipped (and nothing is about to die in front of us)
	if h.hp < h.max_hp * 0.6 and not _has_mod(h, "salve") and not _has_mod(h, "tango") and w.time >= _next_tango:
		if h.hp < h.max_hp * 0.45 and _use_item(h, "salve"):
			_next_tango = w.time + 2.0
		elif _tango(h):
			_next_tango = w.time + 18.0
			_cast_deadline = w.time + 4.0
			return
	# 1. go for the kill when ahead: the enemy is low, or clearly weaker than us and away from their tower
	for e in enemy_heroes:
		var mine := h.hp / h.max_hp
		var theirs := e.hp / e.max_hp
		var safe := not _under_enemy_tower(h, e.pos, enemy_towers)
		var winning := theirs < 0.3 and mine > 0.4 or theirs < mine - 0.3 and mine > 0.55 and h.level >= e.level
		if winning and (safe or theirs < 0.15) and h.pos.distance_to(e.pos) < 1100.0:
			_spells_on(h, e)
			if not _busy(h):
				_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
	# 2. last hit / deny (melee heroes commit to the walk-up instead of second-guessing it every think)
	var committed := w.get_unit(_lh_id)
	if committed != null and committed.alive and w.time < _lh_until and h.order == O.ATTACK_UNIT and h.order_target == _lh_id:
		return
	var lh := _last_hit_target(h, foes, allies)
	if lh != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": lh.id})
		_lh_id = lh.id
		_lh_until = w.time + (1.3 if not h.is_ranged() else 0.0)
		return
	# 3. harass: Ezee trades blows when the enemy hero wanders into reach; Blood Ranger pokes from range
	if kit == "ezee":
		for e in enemy_heroes:
			var safe := not _under_enemy_tower(h, e.pos, enemy_towers) and not _under_enemy_tower(h, h.pos, enemy_towers)
			var healthy := h.hp > h.max_hp * 0.55 and h.hp / h.max_hp >= e.hp / e.max_hp - 0.15
			var trading := w.time < _trade_until and w.get_unit(_trade_id) == e
			# commit to a trade for a few seconds, then back off and let the cooldown run
			if safe and healthy and (trading or (h.edge_distance(e) <= 650.0 and w.time >= _next_trade)):
				if not trading:
					_trade_id = e.id
					_trade_until = w.time + 3.5
					_next_trade = w.time + 9.0
				_spells_on(h, e)
				if not _busy(h):
					_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
				return
	for e in enemy_heroes:
		var exposed := _under_enemy_tower(h, h.pos, enemy_towers)
		# a free right click when the enemy hero stands in range and nothing needs last-hitting
		if not exposed and h.edge_distance(e) <= h.attack_range and h.atk_phase == SimUnit.AtkPhase.NONE 				and w.time >= _next_trade and h.hp > h.max_hp * 0.5:
			_next_trade = w.time + 2.5
			_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
		if h.edge_distance(e) <= 1100.0 and h.mana > h.max_mana * 0.6:
			_spells_on(h, e)
			if _busy(h):
				return
	# 4. push the tower when our creeps are tanking it
	for tw in enemy_towers:
		if tw.is_invulnerable():
			continue
		var tanking := w.get_unit(tw.atk_target)
		if tanking != null and tanking.team == h.team and not tanking.is_hero() and allies.size() >= 2:
			_order(h, {"type": O.ATTACK_UNIT, "target": tw.id})
			return
	# 5. stand behind the wave, just outside the enemies' reach
	var front := _front(h, allies, path)
	var spot := front
	var nearest_foe: SimUnit = null
	var nd := INF
	for f in foes:
		var d := f.pos.distance_to(h.pos)
		if d < nd:
			nd = d
			nearest_foe = f
	var back := (path[0] - front).normalized()
	if nearest_foe != null:
		var keep := maxf(h.attack_range * 0.85, 330.0) if not h.is_ranged() else h.attack_range * 0.85
		spot = nearest_foe.pos + (h.pos - nearest_foe.pos).normalized() * keep
		spot = spot.lerp(front + back * 300.0, 0.3)
	else:
		spot = front + back * 300.0
	for tw in enemy_towers:
		if tw.pos.distance_to(spot) < tw.attack_range + tw.hull + 160.0:
			spot = tw.pos + (spot - tw.pos).normalized() * (tw.attack_range + tw.hull + 180.0)
	if h.pos.distance_to(spot) > 120.0:
		_go(h, spot)

func _front(h: SimUnit, allies: Array[SimUnit], path: PackedVector2Array) -> Vector2:
	if allies.is_empty():
		return _waiting_spot(h)
	# the ally furthest along the lane
	var best := allies[0]
	var bi := -1.0
	for a in allies:
		var prog := _progress(a.pos, path)
		if prog > bi:
			bi = prog
			best = a
	return best.pos

func _progress(p: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	var acc := 0.0
	var res := 0.0
	for i in path.size() - 1:
		var cp := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		var d := cp.distance_to(p)
		if d < best:
			best = d
			res = acc + path[i].distance_to(cp)
		acc += path[i].distance_to(path[i + 1])
	return res

func _under_enemy_tower(h: SimUnit, p: Vector2, towers: Array[SimUnit]) -> bool:
	for tw in towers:
		if not tw.alive:
			continue
		if p.distance_to(tw.pos) <= tw.attack_range + tw.hull + h.hull + 60.0:
			return true
	return false

## A creep we can kill (or deny) with the next attack, accounting for its incoming damage until our hit lands.
func _last_hit_target(h: SimUnit, foes: Array[SimUnit], allies: Array[SimUnit]) -> SimUnit:
	var best: SimUnit = null
	var best_margin := INF
	var reach := h.attack_range + 250.0
	for c in foes + allies:
		if not c.alive or h.edge_distance(c) > reach:
			continue
		if c.team == h.team and c.hp >= c.max_hp * 0.5:
			continue
		var snap := {"hero": true, "class": int(h.def.attack_class)}
		var mult := w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor)
		var my_min := (h.dmg_min + h.bonus_damage + (w.combat._quelling(h) if c.team != h.team else 0.0)) * mult
		var travel := h.attack_point_time() + maxf(0.0, h.edge_distance(c) - h.attack_range) / maxf(1.0, h.move_speed)
		if h.is_ranged():
			travel += c.pos.distance_to(h.pos) / float(h.def.projectile_speed)
		var incoming := _incoming_dps(c) * travel
		var hp_then := c.hp - incoming
		if hp_then <= 0.0:
			continue
		if hp_then <= my_min:
			var margin := my_min - hp_then
			if margin < best_margin:
				best_margin = margin
				best = c
	if best != null and w.time < h.next_attack_at - h.attack_point_time():
		return null
	return best

func _incoming_dps(c: SimUnit) -> float:
	var dps := 0.0
	for o: SimUnit in w.query(c.pos, 900.0):
		if o.alive and o.atk_target == c.id and o.team != c.team or o.alive and o.atk_target == c.id and o.is_hero():
			var avg := (o.dmg_min + o.dmg_max) * 0.5 + o.bonus_damage
			var snap := {"hero": o.is_hero(), "class": int(o.def.attack_class)}
			dps += avg * w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor) / o.attack_interval()
	return dps

func _ezee_spells(h: SimUnit, e: SimUnit) -> void:
	var d := h.edge_distance(e)
	var ab := w.abilities
	# the ultimate when a real fight is on
	if ab.cast_error(h, "unholy_might", -1, null, h.pos) == "" and d < 450.0 and (e.hp < e.max_hp * 0.75 or h.hp < h.max_hp * 0.6):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "unholy_might"}, true)
		_cast_deadline = w.time + 1.0
		return
	# leap in when the leap would pick the hero
	var keen := e.hp < e.max_hp * 0.6 or h.hp > h.max_hp * 0.75
	if keen and ab.cast_error(h, "leap_strike", -1, null, h.pos) == "" and ab.leap_target(h, h.ability_level_of("leap_strike")) == e and d > 150.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "leap_strike"}, true)
		_cast_deadline = w.time + 1.2
		return
	if ab.cast_error(h, "dark_stomp", -1, null, h.pos) == "" and d < 260.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"}, true)
		_cast_deadline = w.time + 0.9
		return
	if ab.cast_error(h, "tainted_touch", -1, null, h.pos) == "" and d < 400.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "tainted_touch"}, true)
		_cast_deadline = w.time + 0.8

func _spells_on(h: SimUnit, e: SimUnit) -> void:
	if kit == "ezee":
		_ezee_spells(h, e)
		return
	_ranger_spells(h, e)

## Blood Ranger: the ultimate when a fight is on, Gale Impact through the enemy (leading a running target), and
## Burst Shot into the enemy hero when few creeps stand around it to soak the arrows.
func _ranger_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	if ab.cast_error(h, "blood_ranger_ult", -1, null, h.pos) == "" and d < h.attack_range + 350.0 			and (e.hp < e.max_hp * 0.6 or h.hp < h.max_hp * 0.5):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"}, true)
		_cast_deadline = w.time + 0.8
		return
	if ab.cast_error(h, "gale_impact", -1, null, e.pos) == "" and d < 1300.0:
		var lead := e.pos
		if e.moving:
			lead += Vector2.from_angle(e.facing) * e.move_speed * (0.3 + d / 2400.0)
		var aim := h.pos + (lead - h.pos).normalized() * minf(2000.0, h.pos.distance_to(lead) + 250.0)
		_order(h, {"type": O.CAST_POINT, "ability": "gale_impact", "point": aim}, true)
		_cast_deadline = w.time + 1.0
		return
	var a := SimData.ability("burst_shot")
	if ab.cast_error(h, "burst_shot", -1, null, e.pos) == "" and d < float(a.range) + 100.0 and e.hp < e.max_hp * 0.85:
		var crowd := 0
		for o: SimUnit in w.query(e.pos, 400.0):
			if o.alive and o.team == e.team and not o.is_building() and o != e:
				crowd += 1
		if crowd <= 2 or e.hp < e.max_hp * 0.35:
			_order(h, {"type": O.CAST_POINT, "ability": "burst_shot", "point": e.pos}, true)
			_cast_deadline = w.time + 2.6

func _tango(h: SimUnit) -> bool:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == "tango" and not _has_mod(h, "tango"):
			var ti := w.map.tree_at(h.pos, 700.0)
			if ti >= 0:
				w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": i, "point": w.map.trees[ti].pos})
				return true
			return false
	return false

func _has_mod(h: SimUnit, mid: String) -> bool:
	for m in h.modifiers:
		if m.id == mid:
			return true
	return false

func _go(h: SimUnit, p: Vector2) -> void:
	_order(h, {"type": O.MOVE, "point": p})

## Re-issue an order only when it differs from the last one (players do not spam either).
func _order(h: SimUnit, o: Dictionary, force := false) -> void:
	var same: bool = not _last_order.is_empty() and _last_order.get("type") == o.get("type") and _last_order.get("target", -1) == o.get("target", -1)
	if same and o.get("type") == O.MOVE:
		same = (_last_order.point as Vector2).distance_to(o.point) < 100.0 and h.order == O.MOVE
	if same and o.get("type") == O.ATTACK_UNIT:
		same = h.order == O.ATTACK_UNIT and h.order_target == o.target
	if same and not force:
		return
	_last_order = o
	w.command(h.id, o)
