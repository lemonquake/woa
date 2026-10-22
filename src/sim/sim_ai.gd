class_name SimAI
extends RefCounted
## Built-in unit behaviour: lane creep waves and their targeting, creep aggro and de-aggro, tower and fountain
## targeting, neutral camps (spawning, waking, leashing, stacking) and the neutrals' own abilities (auras, on-hit
## effects, splash, and the spells they cast while fighting). Follows Liquipedia's descriptions of the Dota 2 rules
## (docs/MECHANICS.md).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const AP = preload("res://src/sim/sim_unit.gd").AtkPhase

var w: SimWorld
var _pending := {}                         # unit id -> target id to switch to after the current swing

func _init(world: SimWorld = null) -> void:
	w = world

func think() -> void:
	var auras := w.tick % 6 == 0
	for u in w.units:
		if not u.alive:
			continue
		if auras and u.kind != K.HERO and not (u.def.get("auras", []) as Array).is_empty():
			_unit_auras(u)
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
			# super creeps where that lane's enemy barracks fell, mega creeps in every lane once all six are down
			var mega := w.all_rax_dead(1 - team)
			var super_melee := w.lane_rax_dead(1 - team, lane, "melee")
			var super_ranged := w.lane_rax_dead(1 - team, lane, "ranged")
			var melee_id := p + ("melee_mega" if mega else ("melee_super" if super_melee else "melee"))
			var ranged_id := p + ("ranged_mega" if mega else ("ranged_super" if super_ranged else "ranged"))
			var list: Array = []
			for i in melee_n:
				var id := melee_id
				if flag and i == 0:
					id = p + "flag"            # flagbearers stay as they are (Dota spawns only the plain one)
				list.append([id, start + fwd * 140.0 + side * (i - (melee_n - 1) * 0.5) * 70.0])
			for i in siege_n:
				list.append([p + ("siege_super" if super_ranged or mega else "siege"), start + fwd * 20.0 + side * (i - (siege_n - 1) * 0.5) * 90.0])
			for i in ranged_n:
				list.append([ranged_id, start - fwd * 90.0 + side * (i - (ranged_n - 1) * 0.5) * 70.0])
			for e in list:
				# never inside a building's footprint (the top tier 3 tower stands on the lane line)
				var sp: Vector2 = e[1]
				if not w.map.is_walkable(sp):
					var nc := w.map.nearest_walkable(w.map.world_to_cell(sp))
					sp = w.map.cell_center(nc.x, nc.y)
				var u := w.spawn(e[0], team, sp)
				u.facing = fwd.angle()
				u.lane = lane
				u.lane_i = 1
				u.is_super = String(e[0]).ends_with("_super")
				u.is_mega = String(e[0]).ends_with("_mega")
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
			key = "mega_melee" if u.is_mega else ("super_melee" if u.is_super else "melee")
		K.CREEP_RANGED:
			key = "mega_ranged" if u.is_mega else ("super_ranged" if u.is_super else "ranged")
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
	# past the last waypoint (the enemy base's gate): into the base and on to the Ancient, for good. lane_i ==
	# path.size() marks it (run 2026-10-18 h: the goal went back to the gate as soon as a creep stepped 220 past it, so
	# top and bottom creeps paced at the gate after the tier 3 tower fell; mid's gate is close enough to the Ancient
	# that its buildings came into reach)
	if u.lane_i >= path.size() - 1 and (u.lane_i >= path.size() or u.pos.distance_to(path[path.size() - 1]) < 220.0):
		u.lane_i = path.size()
		u.order = O.ATTACK_MOVE
		u.order_point = _base_goal(u)
		return
	u.order = O.ATTACK_MOVE
	u.order_point = path[u.lane_i]

## Inside the enemy base: the standing building nearest the creep on its way in (a barracks, a tier 4 tower, the
## Ancient last), so a wave walks the base as Dota's do instead of standing at an invulnerable Ancient.
func _base_goal(u: SimUnit) -> Vector2:
	var anc := w._ancient_pos(1 - u.team)
	var best := anc
	var best_d := INF
	for b in w.units:
		if not b.alive or b.team != 1 - u.team or not b.is_building() or b.kind == K.FOUNTAIN or b.kind == K.FILLER:
			continue
		if b.pos.distance_to(anc) > 2600.0:
			continue                           # outside the base
		if b.kind != K.ANCIENT and b.is_invulnerable():
			continue
		var d := b.pos.distance_to(u.pos) + (1500.0 if b.kind == K.ANCIENT else 0.0)
		if d < best_d:
			best_d = d
			best = b.pos
	return best

func _note_leave(u: SimUnit) -> void:
	if u.lane_return.x == INF:
		var path := w.map.lane_path(u.lane, u.team)
		if path.size() >= 2 and SimMap._polyline_distance(u.pos, path) < 200.0:
			u.lane_return = u.pos

func _valid_target(u: SimUnit, t: SimUnit) -> bool:
	if not t.alive or t.team == u.team or t.kind == K.FOUNTAIN:
		return false
	if t.team == C.NEUTRAL and t.kind == K.NEUTRAL_CREEP:
		# towers never attack neutrals; lane creeps leave a calm camp alone and fight a neutral only while it is
		# aggressive (fighting anyone, or in the 5 s after)
		if u.is_building() or w.time >= t.hostile_until:
			return false
	if t.is_invulnerable():
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
# Dota 2's rules (research/camps.md of run 2026-10-13-camps-ai-setup): camps spawn at 1:00 and on every minute when
# nothing stands in their spawn box; each spawn picks one of the camp kind's groups (never the same twice in a row);
# by day an enemy within 240 wakes a camp (they sleep at night); damage wakes the neutral and its campmates within 500;
# a neutral chases until it has been outside its 400 guard radius for 5 s, then walks home and cannot be woken by
# damage for 3 s. Neutrals grow every 7:30. A stack's new creeps give 20% less, and their stacker gets 30% of an ally's
# bounty from them.

var camp_group := {}                       # camp id -> index of the group it spawned last
var camp_puller := {}                      # camp id -> hero id who first woke its current creeps (stack credit)

## The creep ids a camp spawns next (or spawned last).
func camp_units(camp_id: int) -> Array:
	var c: Dictionary = w.map.camps[camp_id]
	var groups: Array = SimMap.CAMP_GROUPS[c.kind]
	return groups[int(camp_group.get(camp_id, camp_id % groups.size()))]

func spawn_neutrals() -> void:
	var ups := mini(int(maxf(0.0, w.time) / C.NEUTRAL_UPGRADE_INTERVAL), C.NEUTRAL_MAX_UPGRADES)
	# camps that still have living creeps (one pass over the units, not one per camp)
	var alive_in := {}
	for o in w.units:
		if o.alive and o.kind == K.NEUTRAL_CREEP and o.camp_id >= 0:
			alive_in[o.camp_id] = true
	for c in w.map.camps:
		if _camp_occupied(c):
			continue
		var groups: Array = SimMap.CAMP_GROUPS[c.kind]
		var gi := int(c.id) % groups.size()
		if camp_group.has(c.id) and groups.size() > 1:
			# a random group, but never the one it spawned last
			gi = (int(camp_group[c.id]) + 1 + w.rng.randi_range(0, groups.size() - 2)) % groups.size()
		camp_group[c.id] = gi
		# creeps of this camp still alive outside the box: this spawn is a stack
		var stacker := -1
		var stacking := alive_in.has(c.id)
		if stacking:
			stacker = int(camp_puller.get(c.id, -1))
		else:
			camp_puller.erase(c.id)
		var list: Array = groups[gi]
		var n := list.size()
		var box: Vector2 = c.box
		for i in n:
			var a := TAU * float(i) / n + float(c.id)
			var r := (0.0 if n == 1 else minf(box.x, box.y) * 0.45) * (0.75 + 0.25 * float(i % 2))
			var p: Vector2 = c.pos + Vector2.from_angle(a) * r
			var u := w.spawn(list[i], C.NEUTRAL, p)
			u.camp_id = c.id
			u.home = p
			u.home_facing = (Vector2.ZERO - p).angle() + float(i) * 0.7
			u.facing = u.home_facing
			u.stacked = stacking
			u.stacker_id = stacker
			if ups > 0:
				_grow(u, ups)
				u.hp = u.max_hp
		w.events.append({"t": "camp_spawn", "camp": c.id, "stack": stacking})

func _grow(u: SimUnit, ups: int) -> void:
	u.upgrade = ups
	u.creep_dmg_add = C.NEUTRAL_UPGRADE[2] * ups
	u.bounty_gold_add = C.NEUTRAL_UPGRADE[4] * ups
	u.bounty_xp_add = C.NEUTRAL_UPGRADE[5] * ups
	u.refresh_stats()

## Grow every living neutral at each 7:30 mark (new spawns get the current count).
func upgrade_neutrals() -> void:
	var ups := mini(int(maxf(0.0, w.time) / C.NEUTRAL_UPGRADE_INTERVAL), C.NEUTRAL_MAX_UPGRADES)
	for u in w.units:
		if u.alive and u.kind == K.NEUTRAL_CREEP and u.upgrade < ups:
			var before := u.max_hp
			var hp := u.hp
			_grow(u, ups)
			u.hp = minf(u.max_hp, hp + u.max_hp - before)

## A camp only spawns when nothing stands inside its spawn box: heroes, creeps, wards and its own neutrals block it,
## couriers do not.
func _camp_occupied(c: Dictionary) -> bool:
	return not box_units(c).is_empty()

## Units standing inside a camp's spawn box (the ones that would block its spawn).
func box_units(c: Dictionary) -> Array:
	var box: Vector2 = c.box
	var out: Array = []
	for u: SimUnit in w.query(c.pos, box.length() + 10.0):
		if u.is_building() or u.kind == K.COURIER:
			continue
		var d: Vector2 = u.pos - c.pos
		if absf(d.x) <= box.x and absf(d.y) <= box.y:
			out.append(u)
	return out

func camp_occupied(camp_id: int) -> bool:
	return _camp_occupied(w.map.camps[camp_id])

## Whether a point lies in a camp's spawn box.
static func in_box(c: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - c.pos
	return absf(d.x) <= (c.box as Vector2).x and absf(d.y) <= (c.box as Vector2).y

## Attacked or damaged: this neutral and its campmates within 500 turn on the attacker (not for 3 s after a leash).
func neutral_provoked(n: SimUnit, src: SimUnit) -> void:
	if src.team == C.NEUTRAL or n.kind != K.NEUTRAL_CREEP:
		return
	if w.time < n.no_reaggro_until:
		return
	_wake(n, src)

func _wake(n: SimUnit, src: SimUnit) -> void:
	if src.is_hero() and not camp_puller.has(n.camp_id):
		camp_puller[n.camp_id] = src.id
	for m: SimUnit in w.query(n.pos, C.NEUTRAL_CAMPMATE_RADIUS + 10.0):
		if not m.alive or m.camp_id != n.camp_id or m.kind != K.NEUTRAL_CREEP or m.is_disarmed():
			continue
		if m != n and w.time < m.no_reaggro_until:
			continue
		if m == n or m.neutral_state != 1 or not w.valid(m.atk_target):
			if m.neutral_state == 2:
				# woken again on the way home: it gives up 3 s after leaving its guard radius
				m.leash_since = w.time - (C.NEUTRAL_CHASE_TIME - C.NEUTRAL_REAGGRO_CHASE) \
					if m.pos.distance_to(m.home) > C.NEUTRAL_GUARD_RADIUS else -1.0
			elif m.neutral_state == 0:
				m.leash_since = -1.0
			m.neutral_state = 1
			m.neutral_aggro_at = w.time
			m.hostile_until = w.time + C.NEUTRAL_HOSTILE_TIME
			_retarget(m, src.id)
			m.order = O.NONE
		elif m.atk_target == src.id:
			m.neutral_aggro_at = w.time

## A creep's auras (Alpha Wolf, Goblin Boss, Orc, Lava Golem): allies within the radius (itself too) get the bonus,
## refreshed every 6 ticks and lingering 0.5 s; two copies of one aura do not stack. Off while the creep is broken.
func _unit_auras(u: SimUnit) -> void:
	if u.is_broken():
		return
	for a in u.def.auras:
		for o: SimUnit in w.query(u.pos, float(a.radius)):
			if not o.alive or o.team != u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
				continue
			var st: Dictionary = a.get("hero_stats", a.stats) if o.is_hero() else a.stats
			o.add_modifier({"id": String(a.id), "source": -40, "expires": w.time + 0.5 + 6.0 * C.DT, "stats": st,
				"aura": true, "by": u.id})

## A creep's attack landed on `t` for `dmg` (before armor): its on-hit effect (Goblin Digger's disarm, Swamp Troll's
## break; each with its own cooldown) and splash (Lava Golem: full damage to enemies around the target). Off while
## the attacker is broken.
func on_creep_hit(src: SimUnit, t: SimUnit, dmg: float) -> void:
	if src.is_broken():
		return
	var oh: Dictionary = src.def.get("on_hit", {})
	if not oh.is_empty() and t.alive and t.team != src.team and not t.is_building() and not t.is_ward() \
			and w.time >= float(src.ability_ready.get("on_hit", C.LONG_AGO)):
		var m := {"id": String(oh.id), "dur": float(oh.dur), "fx": "disarm" if oh.get("disarm", false) else "break"}
		for k in ["disarm", "break"]:
			if oh.get(k, false):
				m[k] = true
		if w.status.apply(t, src.id, src.team, m):
			src.ability_ready["on_hit"] = w.time + float(oh.cooldown)
	var sp: Dictionary = src.def.get("splash", {})
	if not sp.is_empty():
		for o: SimUnit in w.query(t.pos, float(sp.radius) + 40.0, true):
			if o == t or not o.alive or o.team == src.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
				continue
			if o.pos.distance_to(t.pos) > float(sp.radius) + o.hull:
				continue
			var sdt := C.DamageType.MAGICAL if src.weapon == C.Weapon.MAGIC else C.DamageType.PHYSICAL
			w.combat.deal_damage(src.id, src.team, false, o, dmg * float(sp.pct), sdt, false, "splash",
				false, {"no_amp": true})

## A fighting neutral uses its spell when it is worth it: Stomp with an enemy hero (or two enemies) in reach, Snarl
## with an enemy hero close, Smash on its target (the long wind-up gives the target time to step away).
func _neutral_cast(u: SimUnit, t: SimUnit) -> void:
	if u.abilities.is_empty() or u.is_silenced() or u.cast_phase != SimUnit.CastPhase.NONE or u.order != O.NONE:
		return
	for aid in u.abilities:
		if w.abilities.cast_error(u, aid, -1, null, u.pos, false, false) != "":
			continue
		var a := SimData.ability(aid)
		var r := float(a.values.radius[0])
		match String(aid):
			"stomp", "snarl":
				var heroes := 0
				var others := 0
				for o: SimUnit in w.query(u.pos, r + 40.0, true):
					if not o.alive or o.team == u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER \
							or o.is_invulnerable() or o.pos.distance_to(u.pos) > r + o.hull:
						continue
					if o.is_hero():
						heroes += 1
					else:
						others += 1
				if heroes > 0 or (aid == "stomp" and others >= 2):
					w.orders.issue(u, {"type": O.CAST_NO_TARGET, "ability": aid}, false)
					return
			"smash":
				if t != null and t.alive and u.edge_distance(t) <= float(a.range) + 40.0:
					w.orders.issue(u, {"type": O.CAST_POINT, "ability": aid, "point": t.pos}, false)
					return

func _neutral(u: SimUnit) -> void:
	match u.neutral_state:
		0:
			u.atk_target = -1
			# by day an enemy walking within 240 wakes the camp (they sleep at night); looked at twice a second
			if not w.is_night() and not u.is_disarmed() and (w.tick + u.id) % 15 < 3:
				var near := _neutral_nearest(u, C.NEUTRAL_PROXIMITY_AGGRO)
				if near != null:
					_wake(u, near)
		1:
			u.hostile_until = w.time + C.NEUTRAL_HOSTILE_TIME
			var t := w.get_unit(u.atk_target)
			var give_up := t == null or not t.alive or t.team == C.NEUTRAL or t.is_invulnerable() \
				or t.has_flag("invisible") and not w.vision.sees(C.NEUTRAL, t)
			if u.pos.distance_to(u.home) > C.NEUTRAL_GUARD_RADIUS:
				if u.leash_since < 0.0:
					u.leash_since = w.time
				elif w.time - u.leash_since >= C.NEUTRAL_CHASE_TIME:
					give_up = true
			else:
				u.leash_since = -1.0
			if give_up and u.leash_since < 0.0:
				# the target is gone while we are home: the next enemy fighting the camp, or the closest one in reach
				var alt := _neutral_alt(u)
				if alt == null:
					alt = _neutral_nearest(u, minf(u.acquire_range, C.NEUTRAL_PROXIMITY_AGGRO))
				if alt != null:
					_retarget(u, alt.id)
					u.neutral_aggro_at = w.time
					return
			if give_up:
				u.neutral_state = 2
				u.atk_target = -1
				u.leash_since = -1.0
				u.no_reaggro_until = w.time + C.NEUTRAL_REAGGRO_LOCK
				u.order = O.MOVE
				u.order_point = u.home
			else:
				_neutral_cast(u, t)
		2:
			# home, or as close as the stack around it allows
			var close := u.pos.distance_to(u.home) < 20.0 or (u.pos.distance_to(u.home) < 160.0 and u.blocked_time > 0.0) \
				or u.pos.distance_to(u.home) < 110.0
			if u.order != O.MOVE or close:
				u.order = O.NONE
				u.neutral_state = 0
				u.facing = u.home_facing

## The closest enemy a neutral may attack within r (heroes and lane creeps; not wards, couriers or buildings).
func _neutral_nearest(u: SimUnit, r: float) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(u.pos, r + 60.0, true):
		if o.team == C.NEUTRAL or not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		if o.is_invulnerable() or o.has_flag("invisible"):
			continue
		var d := u.edge_distance(o)
		if d <= r and d < bd:
			bd = d
			best = o
	return best

func _neutral_alt(u: SimUnit) -> SimUnit:
	for o: SimUnit in w.query(u.home, C.NEUTRAL_GUARD_RADIUS + 600.0):
		if o.team == C.NEUTRAL or not o.alive or o.is_building() or o.is_ward():
			continue
		var tt := w.get_unit(o.atk_target)
		if tt != null and tt.kind == K.NEUTRAL_CREEP and tt.camp_id == u.camp_id and o.atk_phase != AP.NONE:
			return o
	return null
