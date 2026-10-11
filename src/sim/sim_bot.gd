class_name SimBot
extends RefCounted
## A laning bot for one hero. It thinks five times a second and acts only through the same orders a player issues
## (SimWorld.command, buy, learn), so it obeys every rule a player does.
##
## Laning: stand behind its creep wave, last-hit with damage prediction, deny, harass with the hand-cast frost orb
## (which draws no creep aggro), respect enemy tower range, retreat to heal, buy its build at the fountain.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

var w: SimWorld
var hero_id := -1
var lane := "mid"
var name := "Bot"
var state := "lane"
var _next_think := 0.0
var _last_order := {}
var skill_order := ["frost_quiver", "gale_shot", "frost_quiver", "hunters_focus", "frost_quiver", "arrow_storm",
	"frost_quiver", "gale_shot", "gale_shot", "gale_shot", "arrow_storm", "hunters_focus", "hunters_focus",
	"hunters_focus", "arrow_storm"]
var build := ["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "branch",
	"branch", "magic_wand", "boots", "gloves", "boots_elves", "power_treads", "blade_alacrity", "yasha",
	"broadsword", "lifesteal", "mask_of_madness"]
var _build_i := 0

func _init(world: SimWorld, hid: int, p_lane := "mid", p_name := "Bot") -> void:
	w = world
	hero_id = hid
	lane = p_lane
	name = p_name

func hero() -> SimUnit:
	return w.get_unit(hero_id)

func think() -> void:
	if w == null or w.time < _next_think:
		return
	_next_think = w.time + 0.2
	var h := hero()
	if h == null or not h.alive:
		return
	h.bot = true
	h.auto_attack = false
	_learn(h)
	_shop(h)
	if h.hp < h.max_hp * 0.3 and state != "retreat":
		state = "retreat"
	if state == "retreat":
		if h.hp >= h.max_hp * 0.92 and h.mana >= h.max_mana * 0.6:
			state = "lane"
		else:
			_go(h, w.map.fountains[h.team])
			return
	if w.time < 0.0:
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
	if h.ability_level_of("frost_quiver") > 0:
		h.autocast["frost_quiver"] = false

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

var _next_tango := 0.0

## Casting, channelling or walking to a cast target: let it finish rather than interrupt it.
func _busy(h: SimUnit) -> bool:
	return h.cast_phase != SimUnit.CastPhase.NONE or not h.channel.is_empty() 		or h.order in [O.CAST_POINT, O.CAST_NO_TARGET] and w.time < _cast_deadline

var _cast_deadline := 0.0

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
	# 1. kill an enemy hero that is low
	for e in enemy_heroes:
		if e.hp < e.max_hp * 0.3 and h.hp > h.max_hp * 0.5 and not _under_enemy_tower(h, e.pos, enemy_towers):
			_spells_on(h, e)
			_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
	# 2. last hit / deny
	var lh := _last_hit_target(h, foes, allies)
	if lh != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": lh.id})
		return
	# 3. harass with the hand-cast orb when the enemy hero is in reach and we're not under their tower
	for e in enemy_heroes:
		if h.edge_distance(e) <= h.attack_range and not _under_enemy_tower(h, h.pos, enemy_towers) and h.mana > h.max_mana * 0.35:
			if h.ability_level_of("frost_quiver") > 0 and h.atk_phase == SimUnit.AtkPhase.NONE:
				_order(h, {"type": O.CAST_UNIT, "ability": "frost_quiver", "target": e.id})
				return
		if h.edge_distance(e) <= 900.0 and h.mana > h.max_mana * 0.6:
			_spells_on(h, e)
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
		spot = nearest_foe.pos + (h.pos - nearest_foe.pos).normalized() * (h.attack_range * 0.85)
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
		travel += c.pos.distance_to(h.pos) / maxf(1.0, float(h.def.projectile_speed))
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

func _spells_on(h: SimUnit, e: SimUnit) -> void:
	if w.abilities.cast_error(h, "arrow_storm", -1, null, e.pos) == "" and e.hp < e.max_hp * 0.7 and h.pos.distance_to(e.pos) < 900.0:
		_order(h, {"type": O.CAST_POINT, "ability": "arrow_storm", "point": e.pos}, true)
		_cast_deadline = w.time + 1.5
		return
	if w.abilities.cast_error(h, "gale_shot", -1, null, e.pos) == "" and h.pos.distance_to(e.pos) < 900.0:
		_order(h, {"type": O.CAST_POINT, "ability": "gale_shot", "point": e.pos}, true)
		_cast_deadline = w.time + 1.5

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
