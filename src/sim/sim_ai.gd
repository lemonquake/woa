class_name SimAI
extends RefCounted
## Built-in unit behaviour: lane creep waves and their targeting, creep aggro and de-aggro, tower and fountain
## targeting, neutral camps (spawning, waking, leashing, stacking). Follows Liquipedia's descriptions of the Dota 2
## rules (docs/MECHANICS.md).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const AP = preload("res://src/sim/sim_unit.gd").AtkPhase

var w: SimWorld
var _pending := {}                         # unit id -> target id to switch to after the current swing

func _init(world: SimWorld) -> void:
	w = world

func think() -> void:
	for u in w.units:
		if not u.alive:
			continue
		if _pending.has(u.id) and u.atk_phase != AP.WINDUP:
			_set_target(u, _pending[u.id])
			_pending.erase(u.id)
		if u.is_lane_creep():
			if w.time >= u.think_at:
				u.think_at = w.time + C.CREEP_THINK_INTERVAL
				_lane_creep(u)
		elif u.kind == K.TOWER or u.kind == K.FOUNTAIN:
			_tower(u)
		elif u.kind == K.NEUTRAL_CREEP:
			if w.time >= u.think_at:
				u.think_at = w.time + C.CREEP_THINK_INTERVAL
				_neutral(u)

func _set_target(u: SimUnit, tid: int) -> void:
	u.atk_target = tid

## Switch target now, or after the attack that is winding up (creeps and towers finish a started attack first).
func _retarget(u: SimUnit, tid: int) -> void:
	if u.atk_target == tid:
		_pending.erase(u.id)
		return
	if u.atk_phase == AP.WINDUP:
		_pending[u.id] = tid
	else:
		_set_target(u, tid)

# ---- Waves ----------------------------------------------------------------------------------------------------------

func spawn_wave(n: int) -> void:
	var ups := int(w.time / C.CREEP_UPGRADE_INTERVAL)
	var melee_n := 3 + int(n >= 31) + int(n >= 61) + int(n >= 91)
	var ranged_n := 1 + int(n >= 81)
	var siege_n := 0
	if n >= 11 and (n - 11) % 10 == 0:
		siege_n = 1 + int(n >= 61) + int(n >= 121)
	var flag := n >= 5 and (n - 5) % 2 == 0
	for team in [C.DAWN, C.DUSK]:
		var p := "dawn_" if team == C.DAWN else "dusk_"
		for lane in ["top", "mid", "bot"]:
			var path := w.map.lane_path(lane, team)
			var start := path[0]
			var fwd := (path[1] - path[0]).normalized()
			var side := fwd.orthogonal()
			var super_melee := w.lane_rax_dead(1 - team, lane, "melee")
			var super_ranged := w.lane_rax_dead(1 - team, lane, "ranged")
			var list: Array = []
			for i in melee_n:
				var id := p + ("melee_super" if super_melee else "melee")
				if flag and i == 0:
					id = p + "flag"
				list.append([id, start + fwd * 140.0 + side * (i - (melee_n - 1) * 0.5) * 70.0])
			for i in siege_n:
				list.append([p + "siege", start + fwd * 20.0 + side * (i - (siege_n - 1) * 0.5) * 90.0])
			for i in ranged_n:
				list.append([p + ("ranged_super" if super_ranged else "ranged"), start - fwd * 90.0 + side * (i - (ranged_n - 1) * 0.5) * 70.0])
			for e in list:
				var u := w.spawn(e[0], team, e[1])
				u.facing = fwd.angle()
				u.lane = lane
				u.lane_i = 1
				u.is_super = String(e[0]).ends_with("_super")
				u.upgrade = ups
				_apply_upgrades(u, ups)
				u.order = O.ATTACK_MOVE
				u.order_point = path[1]
				u.think_at = w.time + randf_range_det(u.id) * C.CREEP_THINK_INTERVAL
	w.events.append({"t": "wave", "n": n})

func randf_range_det(i: int) -> float:
	return float((i * 7919) % 97) / 97.0

func _apply_upgrades(u: SimUnit, ups: int) -> void:
	var key := ""
	match u.kind:
		K.CREEP_MELEE:
			key = "super_melee" if u.is_super else "melee"
		K.CREEP_RANGED:
			key = "super_ranged" if u.is_super else "ranged"
	if key == "":
		return
	var up: Array = C.CREEP_UPGRADE[key]
	var capped := mini(ups, C.CREEP_MAX_UPGRADES)
	u.creep_dmg_add = float(up[1]) * capped
	u.bounty_gold_add = float(up[2]) * ups
	u.bounty_xp_add = float(up[3]) * ups
	u.refresh_stats()
	u.hp = u.max_hp

# ---- Lane creeps --------------------------------------------------------------------------------------------------

func _lane_creep(u: SimUnit) -> void:
	if u.is_disarmed():
		return
	var path := w.map.lane_path(u.lane, u.team)
	# forced aggro (a hero attack-ordered one of our heroes): chase that hero no matter what
	if u.aggro_forced:
		if w.time < u.aggro_until and w.valid(u.aggro_target) and w.vision.sees(u.team, w.get_unit(u.aggro_target)):
			_retarget(u, u.aggro_target)
			_note_leave(u)
			return
		u.aggro_forced = false
	var cur := w.get_unit(u.atk_target)
	if cur != null and not _valid_target(u, cur):
		cur = null
		u.atk_target = -1
	if cur != null:
		var in_range := u.edge_distance(cur) <= u.attack_range
		if u.atk_phase != AP.WINDUP:
			# a higher-priority unit type inside attack range takes over at once
			var best := _pick(u, u.attack_range)
			if best != null and _type_rank(u, best) < _type_rank(u, cur):
				_retarget(u, best.id)
				cur = best
			elif not in_range:
				# forced to move: prefer something already in attack range
				if best != null:
					_retarget(u, best.id)
					cur = best
		_note_leave(u)
		return
	var t := _pick(u, u.acquire_range)
	if t != null:
		_retarget(u, t.id)
		_note_leave(u)
		return
	# nothing to fight: back to the lane spot we left, then on along the lane
	if path.size() < 2:
		return
	if u.lane_return.x != INF:
		u.order = O.ATTACK_MOVE
		u.order_point = u.lane_return
		if u.pos.distance_to(u.lane_return) < 80.0 or SimMap._polyline_distance(u.pos, path) < 120.0:
			u.lane_return = Vector2(INF, INF)
		return
	while u.lane_i < path.size() - 1 and u.pos.distance_to(path[u.lane_i]) < 200.0:
		u.lane_i += 1
	# past the last waypoint: march on the enemy Ancient
	var goal := path[u.lane_i]
	if u.lane_i >= path.size() - 1 and u.pos.distance_to(goal) < 220.0:
		goal = w._ancient_pos(1 - u.team)
	u.order = O.ATTACK_MOVE
	u.order_point = goal

func _note_leave(u: SimUnit) -> void:
	if u.lane_return.x == INF:
		var path := w.map.lane_path(u.lane, u.team)
		if path.size() >= 2 and SimMap._polyline_distance(u.pos, path) < 200.0:
			u.lane_return = u.pos

func _valid_target(u: SimUnit, t: SimUnit) -> bool:
	if not t.alive or t.team == u.team or t.kind == K.FOUNTAIN:
		return false
	if t.is_building() and t.is_invulnerable():
		return false
	if t.has_flag("invisible"):
		return false
	return w.vision.sees(u.team, t)

## Unit-type rank (lower attacks first). Siege creeps prefer buildings, then units, siege, heroes, wards.
func _type_rank(u: SimUnit, t: SimUnit) -> int:
	if u.kind == K.CREEP_SIEGE:
		if t.is_building():
			return 1
		if t.is_ward():
			return 5
		if t.is_hero():
			return 4
		if t.kind == K.CREEP_SIEGE:
			return 3
		return 2
	return t.type_priority()

## Threat level: 1 attacking this unit, 2 attacking one of its allies, 3 anything else.
func _threat(u: SimUnit, t: SimUnit) -> int:
	if t.atk_target == u.id and (t.atk_phase != AP.NONE or t.order == O.ATTACK_UNIT):
		return 1
	var tt := w.get_unit(t.atk_target)
	if tt != null and tt.team == u.team and t.atk_phase != AP.NONE:
		return 2
	return 3

## Best enemy within `r` (edge distance) by unit type, then threat, then distance.
func _pick(u: SimUnit, r: float, exclude := -1) -> SimUnit:
	var best: SimUnit = null
	var key := Vector3(INF, INF, INF)
	for o: SimUnit in w.query(u.pos, r + 160.0, true):
		if o.id == exclude or not _valid_target(u, o):
			continue
		var d := u.edge_distance(o)
		if d > r:
			continue
		var k := Vector3(_type_rank(u, o), _threat(u, o), d)
		if k < key:
			key = k
			best = o
	return best

# ---- Aggro --------------------------------------------------------------------------------------------------------

## Type 1: a hero issues an attack order on an enemy hero. Enemy lane creeps near the aggressor chase it for 2.3 s.
func attack_order_aggro(h: SimUnit) -> void:
	if w.time < h.aggro_cd_until:
		return
	h.aggro_cd_until = w.time + C.CREEP_AGGRO_COOLDOWN
	for c: SimUnit in w.query(h.pos, C.CREEP_AGGRO_RADIUS):
		if not c.is_lane_creep() or c.team == h.team or c.team == C.NEUTRAL:
			continue
		if not w.vision.sees(c.team, h):
			continue
		c.aggro_target = h.id
		c.aggro_until = w.time + C.CREEP_AGGRO_DURATION
		c.aggro_forced = true
		_retarget(c, h.id)
	w.events.append({"t": "aggro", "u": h.id})

## An attack begins (the animation starts): type 2 creep aggro and tower hero protection.
## Neutral creeps are not woken by an attack starting, only by taking damage (SimCombat.deal_damage).
func on_attack_start(a: SimUnit, t: SimUnit, manual_orb := false) -> void:
	if not (a.is_hero() and t.is_hero()) or manual_orb:
		return
	# towers protect heroes from heroes: switch to the attacker
	for tw: SimUnit in w.query(a.pos, C.TOWER_PROTECT_RADIUS + 300.0, true):
		if tw.kind != K.TOWER or tw.team == a.team or not tw.alive:
			continue
		if tw.edge_distance(a) > tw.attack_range or not w.vision.sees(tw.team, a):
			continue
		_retarget(tw, a.id)
	if w.time < a.aggro_cd_until:
		return
	for c: SimUnit in w.query(a.pos, C.CREEP_AGGRO_RADIUS):
		if not c.is_lane_creep() or c.team == a.team or c.team == C.NEUTRAL or c.aggro_forced:
			continue
		if not w.vision.sees(c.team, a):
			continue
		_retarget(c, a.id)

## A hero attack-orders an ally (a deny attempt): towers and creeps attacking it look for another target.
func deaggro(h: SimUnit, ally: SimUnit) -> void:
	for o: SimUnit in w.query(h.pos, 1400.0):
		if o.team == h.team or o.atk_target != h.id:
			continue
		if o.kind == K.TOWER or o.kind == K.FOUNTAIN:
			if w.time < o.tower_deaggro_at:
				continue
			# only works when another of our units is closer to the tower than we are
			var alt := _pick(o, o.attack_range, h.id)
			if alt != null and alt.pos.distance_to(o.pos) < h.pos.distance_to(o.pos) and _type_rank(o, alt) <= _type_rank(o, h):
				o.tower_deaggro_at = w.time + C.TOWER_DEAGGRO_COOLDOWN
				_retarget(o, alt.id)
		elif o.is_lane_creep() and not o.aggro_forced:
			var alt2 := _pick(o, o.acquire_range, h.id)
			if alt2 != null:
				_retarget(o, alt2.id)

# ---- Towers and fountains -------------------------------------------------------------------------------------------

func _tower(u: SimUnit) -> void:
	var cur := w.get_unit(u.atk_target)
	if cur != null and (not _valid_target(u, cur) or u.edge_distance(cur) > u.attack_range):
		cur = null
		u.atk_target = -1
	if u.atk_phase == AP.WINDUP:
		return
	var best := _pick(u, u.attack_range)
	if cur == null:
		if best != null:
			u.atk_target = best.id
		return
	# unit-type priority is checked continuously
	if best != null and _type_rank(u, best) < _type_rank(u, cur):
		u.atk_target = best.id

# ---- Neutral camps --------------------------------------------------------------------------------------------------

func spawn_neutrals() -> void:
	for c in w.map.camps:
		if _camp_occupied(c):
			continue
		var n: int = c.units.size()
		for i in n:
			var a := TAU * float(i) / n + float(c.id)
			var p: Vector2 = c.pos + Vector2.from_angle(a) * (60.0 if n > 1 else 0.0) * (1.0 + i * 0.35)
			var u := w.spawn(c.units[i], C.NEUTRAL, p)
			u.camp_id = c.id
			u.home = p
			u.home_facing = (Vector2.ZERO - p).angle() + float(i) * 0.7
			u.facing = u.home_facing
		w.events.append({"t": "camp_spawn", "camp": c.id})

## A camp only spawns when nothing stands inside its spawn box (heroes, creeps, wards or its own neutrals).
func _camp_occupied(c: Dictionary) -> bool:
	var h: float = c.box_half
	for u: SimUnit in w.query(c.pos, h * 1.5):
		if u.is_building():
			continue
		var d: Vector2 = u.pos - c.pos
		if absf(d.x) <= h and absf(d.y) <= h:
			return true
	return false

func camp_occupied(camp_id: int) -> bool:
	return _camp_occupied(w.map.camps[camp_id])

## Attacked or damaged: this neutral and its idle campmates turn on the attacker.
func neutral_provoked(n: SimUnit, src: SimUnit) -> void:
	if src.team == C.NEUTRAL:
		return
	for m in w.units:
		if not m.alive or m.camp_id != n.camp_id or m.kind != K.NEUTRAL_CREEP:
			continue
		if m == n or m.neutral_state != 1 or not w.valid(m.atk_target):
			m.neutral_state = 1
			m.neutral_aggro_at = w.time
			_retarget(m, src.id)
			m.order = O.NONE
		elif m.atk_target == src.id:
			m.neutral_aggro_at = w.time

func _neutral(u: SimUnit) -> void:
	match u.neutral_state:
		0:
			u.atk_target = -1
		1:
			var t := w.get_unit(u.atk_target)
			var give_up := t == null or not t.alive or t.team == C.NEUTRAL
			if not give_up:
				var far := u.pos.distance_to(u.home) > C.NEUTRAL_LEASH or t.pos.distance_to(u.home) > C.NEUTRAL_LEASH + 600.0
				var stale := w.time - u.neutral_aggro_at > C.NEUTRAL_AGGRO_TIMEOUT and u.edge_distance(t) > u.acquire_range
				give_up = far or stale
			if give_up:
				# another enemy hitting the camp right now keeps the fight going
				var alt := _neutral_alt(u)
				if alt != null:
					_retarget(u, alt.id)
					u.neutral_aggro_at = w.time
				else:
					u.neutral_state = 2
					u.atk_target = -1
					u.order = O.MOVE
					u.order_point = u.home
		2:
			# home, or as close as the stack around it allows
			var close := u.pos.distance_to(u.home) < 20.0 or (u.pos.distance_to(u.home) < 160.0 and u.blocked_time > 0.0) 				or u.pos.distance_to(u.home) < 110.0
			if u.order != O.MOVE or close:
				u.order = O.NONE
				u.neutral_state = 0
				u.facing = u.home_facing

func _neutral_alt(u: SimUnit) -> SimUnit:
	for o: SimUnit in w.query(u.home, C.NEUTRAL_LEASH):
		if o.team == C.NEUTRAL or not o.alive or o.is_building() or o.is_ward():
			continue
		var tt := w.get_unit(o.atk_target)
		if tt != null and tt.kind == K.NEUTRAL_CREEP and tt.camp_id == u.camp_id and o.atk_phase != AP.NONE:
			return o
	return null
