class_name SimCombat
extends RefCounted
## Attacks landing, projectiles, damage (attack classes, armor, magic resistance, backdoor protection, glyph),
## death and its rewards: last-hit gold, denies, experience sharing, hero kill and assist gold, building bounties.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var w: SimWorld
var _deaths: Array = []                    # [{u, killer}]
var _next_proj := 1

func _init(world: SimWorld) -> void:
	w = world

# ---- Attacks ----------------------------------------------------------------------------------------------------------

## The attack point was reached: melee attacks land now, ranged attacks launch a projectile.
func release_attack(u: SimUnit, t: SimUnit, mod: String) -> void:
	var snap := _snapshot(u, mod)
	if mod != "":
		w.abilities.pay_attack_modifier(u, mod)
	if u.is_ranged():
		var p := {"id": _next_proj, "src": u.id, "target": t.id, "pos": u.pos + Vector2.from_angle(u.facing) * u.hull,
			"speed": float(u.def.projectile_speed), "snap": snap, "kind": "attack", "model": u.def.model, "mod": mod}
		_next_proj += 1
		w.projectiles.append(p)
		w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": t.id, "kind": "attack", "mod": mod})
		# glyph: tier 2+ towers also fire at extra nearby enemies
		if u.kind == K.TOWER and u.lane_tier >= 2 and w.time < u.glyph_until:
			_glyph_multishot(u, t, snap)
	else:
		land_attack(snap, t)

func _glyph_multishot(u: SimUnit, main: SimUnit, snap: Dictionary) -> void:
	var n := 0
	for o: SimUnit in w.query(u.pos, u.attack_range + 200.0, true):
		if n >= C.GLYPH_EXTRA_TARGETS:
			break
		if o == main or o.team == u.team or o.is_building() or o.is_ward() or not w.vision.sees(u.team, o):
			continue
		if u.edge_distance(o) > u.attack_range:
			continue
		var p := {"id": _next_proj, "src": u.id, "target": o.id, "pos": u.pos, "speed": float(u.def.projectile_speed),
			"snap": snap, "kind": "attack", "model": u.def.model, "mod": ""}
		_next_proj += 1
		w.projectiles.append(p)
		w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": o.id, "kind": "attack", "mod": ""})
		n += 1

## What an attack carries, fixed at launch (the attacker may die before it lands).
func _snapshot(u: SimUnit, mod: String) -> Dictionary:
	return {"src": u.id, "team": u.team, "hero": u.is_hero(), "kind": u.kind, "dmg_min": u.dmg_min, "dmg_max": u.dmg_max,
		"bonus": u.bonus_damage, "class": int(u.def.attack_class), "level_h": w.map.level_at(u.pos), "mod": mod,
		"lifesteal": u.lifesteal, "ranged": u.is_ranged(), "quell": _quelling(u)}

func _quelling(u: SimUnit) -> float:
	if not u.is_hero():
		return 0.0
	for i in 6:
		var it = u.inventory[i]
		if it != null and it.id == "quelling_blade":
			var v: Dictionary = SimData.item("quelling_blade").values
			return float(v.creep_damage_ranged if u.is_ranged() else v.creep_damage_melee)
	return 0.0

func update_projectiles() -> void:
	for i in range(w.projectiles.size() - 1, -1, -1):
		var p: Dictionary = w.projectiles[i]
		var t := w.get_unit(p.target)
		if t == null or not t.alive:
			w.projectiles.remove_at(i)
			w.events.append({"t": "projectile_end", "id": p.id, "hit": false})
			continue
		var to: Vector2 = t.pos - p.pos
		var step: float = p.speed * C.DT
		if to.length() <= step + t.hull * 0.5:
			w.projectiles.remove_at(i)
			w.events.append({"t": "projectile_end", "id": p.id, "hit": true})
			land_attack(p.snap, t)
		else:
			p.pos += to.normalized() * step

## An attack connects: miss chance (evasion, uphill), damage, lifesteal and attack modifiers.
func land_attack(s: Dictionary, t: SimUnit) -> void:
	if not t.alive:
		return
	var src := w.get_unit(s.src)
	var miss := false
	if t.evasion > 0.0 and w.rng.randf() < t.evasion:
		miss = true
	elif int(s.level_h) < w.map.level_at(t.pos) and w.rng.randf() < C.UPHILL_MISS:
		miss = true
	if miss:
		w.events.append({"t": "miss", "u": s.src, "target": t.id})
		return
	var dmg: float = w.rng.randf_range(s.dmg_min, s.dmg_max) + float(s.bonus)
	if s.mod != "":
		dmg += w.abilities.attack_modifier_damage(s, t)
	if t.is_creep() and t.team != s.team:
		dmg += float(s.quell)
	dmg *= attack_class_multiplier(s, t)
	var dealt := deal_damage(s.src, s.team, bool(s.hero), t, dmg, C.DamageType.PHYSICAL, true)
	if dealt > 0.0 and float(s.lifesteal) > 0.0 and src != null and src.alive and not t.is_building():
		src.hp = minf(src.max_hp, src.hp + dealt * float(s.lifesteal))
	if s.mod != "" and t.alive:
		w.abilities.attack_modifier_hit(s, t)

func attack_class_multiplier(s: Dictionary, t: SimUnit) -> float:
	var dc := t.defense_class()
	var cls := int(s.class)
	var m: float
	if cls == C.AttackClass.DEFAULT and dc == C.DefenseClass.STRUCTURE:
		m = C.HERO_VS_STRUCTURE if s.hero else 0.7
	else:
		m = C.ATTACK_MATRIX[cls][dc]
	if t.kind == K.CREEP_SIEGE:
		m *= C.SIEGE_TAKEN_FROM_HERO if s.hero else C.SIEGE_TAKEN_FROM_BASIC
	return m

# ---- Damage ---------------------------------------------------------------------------------------------------------------

## Apply damage after armor / magic resistance and building protections. Returns the health removed.
func deal_damage(src_id: int, src_team: int, src_hero: bool, t: SimUnit, amount: float, dtype: int, is_attack := false) -> float:
	if not t.alive or amount <= 0.0:
		return 0.0
	if t.is_invulnerable():
		return 0.0
	if w.time < t.glyph_until:
		w.events.append({"t": "damage", "u": t.id, "src": src_id, "amount": 0.0, "blocked": true})
		return 0.0
	match dtype:
		C.DamageType.PHYSICAL:
			amount *= C.armor_multiplier(t.armor)
		C.DamageType.MAGICAL:
			if t.is_building():
				return 0.0
			amount *= 1.0 - t.magic_resist
	if t.is_building() and t.backdoor_active and src_team != t.team:
		amount *= 1.0 - C.BACKDOOR_DAMAGE_REDUCTION
		t.backdoor_pool += amount
	amount = minf(amount, t.hp)
	t.hp -= amount
	var src := w.get_unit(src_id)
	if src_hero and t.is_hero() and src_team != t.team:
		t.hero_damage_log[src_id] = w.time
	if t.is_hero() and src_hero and src_team != t.team:
		for i in range(t.modifiers.size() - 1, -1, -1):
			if t.modifiers[i].get("break_on_damage", false):
				t.modifiers.remove_at(i)
				t.stats_dirty = true
	# neutrals wake up and fight back when hurt
	if t.kind == K.NEUTRAL_CREEP and src != null:
		w.ai.neutral_provoked(t, src)
	w.events.append({"t": "damage", "u": t.id, "src": src_id, "amount": amount, "type": dtype, "attack": is_attack})
	if t.hp <= 0.001:
		t.hp = 0.0
		kill(t, src)
	return amount

func heal(t: SimUnit, amount: float) -> void:
	if t.alive:
		t.hp = minf(t.max_hp, t.hp + amount)

# ---- Death --------------------------------------------------------------------------------------------------------------

func kill(t: SimUnit, killer: SimUnit) -> void:
	if not t.alive:
		return
	t.alive = false
	t.hp = 0.0
	t.death_at = w.time
	t.killer_id = killer.id if killer else -1
	t.moving = false
	t.atk_phase = SimUnit.AtkPhase.NONE
	t.cast_phase = SimUnit.CastPhase.NONE
	t.order = C.Order.NONE
	t.path = PackedVector2Array()
	_deaths.append({"u": t, "killer": killer})

func process_deaths() -> void:
	# corpses are removed from the unit list a few seconds after death
	for u in w.units:
		if not u.alive and not u.removed and not u.is_hero() and w.time - u.death_at > 4.0:
			u.removed = true
	while not _deaths.is_empty():
		var d: Dictionary = _deaths.pop_front()
		var t: SimUnit = d.u
		var killer: SimUnit = d.killer
		var deny := killer != null and killer.team == t.team
		w.events.append({"t": "death", "u": t.id, "killer": killer.id if killer else -1, "deny": deny})
		if t.is_hero():
			_hero_death(t, killer)
		elif t.is_creep():
			_creep_death(t, killer, deny)
		elif t.is_building():
			_building_death(t, killer, deny)

func _creep_death(t: SimUnit, killer: SimUnit, deny: bool) -> void:
	var hero_killer := killer if killer != null and killer.is_hero() else null
	if deny:
		if hero_killer:
			hero_killer.denies += 1
			w.events.append({"t": "deny", "u": hero_killer.id, "target": t.id})
		_share_xp(t, _xp_value(t) * C.DENY_XP_FACTOR, _enemy_team_of(t, killer))
		return
	if hero_killer and hero_killer.team != t.team:
		var g := w.rng.randi_range(int(t.def.gold_min), int(t.def.gold_max)) + int(t.bounty_gold_add)
		give_gold(hero_killer, g, false, t.pos)
		hero_killer.last_hits += 1
		w.events.append({"t": "last_hit", "u": hero_killer.id, "target": t.id, "gold": g})
	# flagbearers pay their bounty to every enemy hero around them
	if t.kind == K.CREEP_FLAG and killer != null and killer.team != t.team:
		for h in w.heroes:
			if h.alive and h.team != t.team and h.pos.distance_to(t.pos) <= 700.0:
				give_gold(h, int(t.def.gold_min) + 10, false, h.pos)
	_share_xp(t, _xp_value(t), _enemy_team_of(t, killer))

func _xp_value(t: SimUnit) -> float:
	return float(t.def.xp) + t.bounty_xp_add

## Which team's heroes are rewarded with experience for this death.
func _enemy_team_of(t: SimUnit, killer: SimUnit) -> int:
	if t.team == C.NEUTRAL:
		return killer.team if killer != null else -1
	return 1 - t.team

func _share_xp(t: SimUnit, amount: float, team: int, always: SimUnit = null) -> void:
	if team < 0 or amount <= 0.0:
		return
	var near: Array[SimUnit] = []
	for h in w.heroes:
		if h.alive and h.team == team and (h.pos.distance_to(t.pos) <= C.XP_RADIUS or h == always):
			near.append(h)
	if near.is_empty():
		return
	var each := floorf(amount / near.size())
	for h in near:
		give_xp(h, each)

func give_xp(h: SimUnit, amount: float) -> void:
	if amount <= 0.0 or h.level >= C.MAX_LEVEL:
		return
	h.xp += amount
	w.events.append({"t": "xp", "u": h.id, "amount": amount})
	var lvl := C.xp_level(h.xp)
	while h.level < lvl:
		h.level += 1
		h.ability_points += 1
		h.refresh_stats()
		w.events.append({"t": "level_up", "u": h.id, "level": h.level})

func give_gold(h: SimUnit, amount: int, reliable: bool, at: Vector2) -> void:
	if amount == 0:
		return
	if reliable:
		h.gold_reliable += amount
	else:
		h.gold_unreliable += amount
	w.events.append({"t": "gold", "u": h.id, "amount": amount, "pos": at})

func _hero_death(t: SimUnit, killer: SimUnit) -> void:
	t.deaths += 1
	t.respawn_at = w.time + float(C.RESPAWN_TIME[t.level - 1])
	var loss := mini(t.gold_unreliable, int(t.networth() / C.DEATH_GOLD_DIVISOR))
	t.gold_unreliable -= loss
	if loss > 0:
		w.events.append({"t": "gold", "u": t.id, "amount": -loss, "pos": t.pos})
	var victim_streak := t.streak
	t.streak = 0
	if killer != null and killer.team == t.team:
		return                                # denied hero: no rewards
	# kill credit: an enemy hero who struck the killing blow, else the last enemy hero to damage us recently
	var credit: SimUnit = killer if killer != null and killer.is_hero() else null
	if credit == null:
		var best_t := -INF
		for hid in t.hero_damage_log:
			var tt: float = t.hero_damage_log[hid]
			if w.time - tt <= C.KILL_TIME_WINDOW and tt > best_t:
				var h := w.get_unit(hid)
				if h != null:
					best_t = tt
					credit = h
	var enemy_team := 1 - t.team
	var assisters: Array[SimUnit] = []
	for h in w.heroes:
		if h.team != enemy_team or not h.alive and h != credit:
			continue
		var recent: bool = t.hero_damage_log.has(h.id) and w.time - float(t.hero_damage_log[h.id]) <= C.KILL_TIME_WINDOW
		if h == credit or h.pos.distance_to(t.pos) <= C.ASSIST_RADIUS or recent:
			assisters.append(h)
	var base := C.HERO_KILL_GOLD_BASE + C.HERO_KILL_GOLD_PER_LEVEL * t.level + _streak_gold(victim_streak)
	if credit != null:
		credit.kills += 1
		credit.streak += 1
		var fb := 0
		if not w.first_blood:
			w.first_blood = true
			fb = C.FIRST_BLOOD_GOLD
		give_gold(credit, int(base) + fb, false, t.pos)
		w.events.append({"t": "hero_kill", "u": credit.id, "victim": t.id, "first_blood": fb > 0})
	else:
		# no hero involved: the kill gold is split among the whole enemy team
		var team_heroes := w.heroes.filter(func(h): return h.team == enemy_team)
		for h in team_heroes:
			give_gold(h, int(base / maxf(1.0, team_heroes.size())), false, h.pos)
		w.events.append({"t": "hero_kill", "u": -1, "victim": t.id, "first_blood": false})
	# assist (area) gold, shared equally including the killer
	if not assisters.is_empty():
		var nw_v := 0.0
		var nw_k := 0.0
		for h in w.heroes:
			if h.team == t.team:
				nw_v += h.networth()
			else:
				nw_k += h.networth()
		var f := C.ASSIST_GOLD_BASE + (C.ASSIST_GOLD_SCALING + t.networth() * C.ASSIST_GOLD_NETWORTH) / assisters.size()
		var ratio := clampf(nw_v / maxf(1.0, nw_k), 0.5, 2.0)
		for h in assisters:
			give_gold(h, int(f * ratio), false, h.pos)
			if h != credit:
				h.assists += 1
	# experience: shared by heroes in range; the killer always gets a share
	var xp := C.HERO_KILL_XP_BASE + C.HERO_KILL_XP_FACTOR * t.xp
	_share_xp(t, xp, enemy_team, credit)
	t.hero_damage_log.clear()

func _streak_gold(streak: int) -> float:
	if streak < 3:
		return 0.0
	return minf(60.0 * (streak - 2), 480.0)       # APPROX shutdown bounty

func _building_death(t: SimUnit, killer: SimUnit, deny: bool) -> void:
	var key := String(t.def.bounty_key)
	if C.BUILDING_BOUNTY.has(key):
		var b: Array = C.BUILDING_BOUNTY[key]
		if deny:
			for h in w.heroes:
				give_gold(h, int(b[0] * C.TOWER_DENY_FACTOR), false, h.pos)
		else:
			for h in w.heroes:
				if h.team != t.team:
					give_gold(h, int(b[0]), false, h.pos)
			if killer != null and killer.is_hero() and killer.team != t.team:
				give_gold(killer, w.rng.randi_range(int(b[1]), int(b[2])), false, t.pos)
	w.on_building_destroyed(t)
