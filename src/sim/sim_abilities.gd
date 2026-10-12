class_name SimAbilities
extends RefCounted
## Hero abilities and item actives: learning, cast rules (level, cooldown, mana, silence, range), effects, the
## attack modifier (orb) logic and timed effects such as linear projectiles and arrow volleys.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

var w: SimWorld

func _init(world: SimWorld) -> void:
	w = world

# ---- Learning ---------------------------------------------------------------------------------------------------------

func can_learn(u: SimUnit, aid: String) -> bool:
	if u.ability_points <= 0 or not u.ability_level.has(aid):
		return false
	var a := SimData.ability(aid)
	if String(a.get("behavior", "")) == "innate":
		return false
	var lv := u.ability_level_of(aid)
	if lv >= int(a.max_level):
		return false
	if a.has("required_level"):
		return u.level >= int(a.required_level[lv])
	# basic abilities: level n requires hero level 2n - 1
	return u.level >= 2 * lv + 1

func learn(u: SimUnit, aid: String) -> bool:
	if not can_learn(u, aid):
		return false
	u.ability_level[aid] = u.ability_level_of(aid) + 1
	u.ability_points -= 1
	if SimData.ability(aid).behavior == "autocast_attack" and u.ability_level[aid] == 1 and u.bot:
		u.autocast[aid] = true
	u.refresh_stats()
	w.events.append({"t": "learn", "u": u.id, "ability": aid, "level": u.ability_level[aid]})
	return true

## Talents: tier 0..3 opens at hero level 10 / 15 / 20 / 25 and costs one ability point; one of two per tier.
func can_learn_talent(u: SimUnit, tier: int) -> bool:
	var tree: Array = u.def.get("talents", [])
	return tier >= 0 and tier < tree.size() and tier < C.TALENT_LEVELS.size() and not u.talents.has(tier) \
		and u.ability_points > 0 and u.level >= int(C.TALENT_LEVELS[tier])

func learn_talent(u: SimUnit, tier: int, side: int) -> bool:
	if not can_learn_talent(u, tier) or side < 0 or side > 1:
		return false
	u.talents[tier] = String(u.def.talents[tier][side])
	u.ability_points -= 1
	rebuild_perm_stats(u)
	w.events.append({"t": "learn_talent", "u": u.id, "tier": tier, "talent": u.talents[tier]})
	return true

## Stats that outlive death: Growing Gut's strength and the talents' flat bonuses.
func rebuild_perm_stats(u: SimUnit) -> void:
	var perm := {}
	if u.ability_level.has("growing_gut"):
		perm["str"] = float(u.stacks.get("growing_gut", 0)) * val(u, "growing_gut", "str_per_stack")
	for tier in u.talents:
		var tal := SimData.talent(String(u.talents[tier]))
		for k in tal.get("stats", {}):
			perm[k] = float(perm.get(k, 0.0)) + float(tal.stats[k])
	u.perm_stats = perm
	u.refresh_stats()

func toggle_autocast(u: SimUnit, aid: String) -> void:
	if SimData.ability(aid).get("behavior", "") == "autocast_attack" and u.ability_level_of(aid) > 0:
		u.autocast[aid] = not bool(u.autocast.get(aid, false))

# ---- Cast rules ---------------------------------------------------------------------------------------------------------

func _lvl_val(a: Dictionary, key: String, lv: int) -> float:
	var arr: Array = a[key] if a.has(key) else a.values[key]
	return float(arr[clampi(lv - 1, 0, arr.size() - 1)])

## An ability value for this hero right now: the level's value plus the Upgrade Staff and Upgrade Gem bonuses, then
## talents (added, then multiplied). Works for per-level keys in `values` and for "mana", "cooldown", "range".
func val(u: SimUnit, aid: String, key: String) -> float:
	var a := SimData.ability(aid)
	if a.is_empty():
		return 0.0
	var v := 0.0
	if a.has(key) and a[key] is Array or (a.get("values", {}) as Dictionary).has(key):
		v = _lvl_val(a, key, maxi(1, u.ability_level_of(aid)))
	elif a.has(key):
		v = float(a[key])
	if a.has("scepter") and (a.scepter as Dictionary).has(key) and u.has_scepter():
		v += float(a.scepter[key])
	if a.has("shard") and (a.shard as Dictionary).has(key) and u.shard:
		v += float(a.shard[key])
	for tier in u.talents:
		for m in SimData.talent(String(u.talents[tier])).get("mods", []):
			if String(m.ability) == aid:
				v += float((m.get("add", {}) as Dictionary).get(key, 0.0))
				v *= float((m.get("mult", {}) as Dictionary).get(key, 1.0))
	return v

func ability_mana(u: SimUnit, aid: String) -> float:
	return val(u, aid, "mana")

func ability_cooldown(u: SimUnit, aid: String) -> float:
	return maxf(0.0, val(u, aid, "cooldown"))

func cooldown_left(u: SimUnit, aid: String) -> float:
	return maxf(0.0, float(u.ability_ready.get(aid, C.LONG_AGO)) - w.time)

func item_cooldown_left(u: SimUnit, slot: int) -> float:
	var it = u.inventory[slot]
	if it == null:
		return 0.0
	return maxf(0.0, float(it.get("ready", C.LONG_AGO)) - w.time)

func cast_error(u: SimUnit, aid: String, slot: int, target: SimUnit, point: Vector2, at_cast := false) -> String:
	if slot >= 0:
		return _item_error(u, slot, target, point)
	if aid == "tp":
		if u.tp_charges <= 0:
			return "No Teleport Scroll"
		if cooldown_left(u, "tp") > 0.0:
			return "Teleport on cooldown"
		if u.mana < C.TP_MANA:
			return "Not enough mana"
		if u.is_stunned():
			return "Stunned"
		return ""
	var a := SimData.ability(aid)
	if a.is_empty() or not u.ability_level.has(aid):
		return "Unknown ability"
	var lv := u.ability_level_of(aid)
	if lv <= 0:
		return "Ability not learned"
	if a.behavior == "passive":
		return "Ability is passive"
	if u.is_silenced():
		return "Silenced"
	if cooldown_left(u, aid) > 0.0:
		return "Ability on cooldown"
	if u.mana < ability_mana(u, aid):
		return "Not enough mana"
	if a.behavior == "unit":
		var te := _target_error(u, a, target)
		if te != "":
			return te
	if aid == "leap_strike":
		if u.is_rooted():
			return "Rooted"
		if leap_target(u, lv) == null:
			return "No enemy in sight"
	if a.behavior == "autocast_attack":
		if target == null or target.team == u.team or target.is_building():
			return "Must target an enemy unit"
	return ""

## Unit-target spells (Chomp): the target must be alive, on the right team, a hero or creep, visible and not
## invulnerable.
func _target_error(u: SimUnit, a: Dictionary, t: SimUnit) -> String:
	if t == null or not t.alive:
		return "Must target a unit"
	var team := String(a.get("target_team", "enemy"))
	if team == "enemy" and t.team == u.team:
		return "Must target an enemy"
	if team == "ally" and t.team != u.team:
		return "Must target an ally"
	if t.is_building() or t.is_ward() or t.kind == K.COURIER:
		return "Must target a hero or creep"
	if t.is_invulnerable():
		return "Target is invulnerable"
	if not w.vision.sees(u.team, t):
		return "Target not visible"
	return ""

func _item_error(u: SimUnit, slot: int, target: SimUnit, point: Vector2) -> String:
	if slot < 0 or slot >= 6 or u.inventory[slot] == null:
		return "No item"
	var it: Dictionary = u.inventory[slot]
	var d := SimData.item(it.id)
	if String(d.use) == "":
		return "Item has no active ability"
	if item_cooldown_left(u, slot) > 0.0:
		return "Item on cooldown"
	if u.is_stunned():
		return "Stunned"
	if u.has_flag("mute"):
		return "Muted"
	match String(d.use):
		"stick":
			if u.stick_charges <= 0:
				return "No charges"
		"berserk":
			if u.mana < float(d.values.mana):
				return "Not enough mana"
		"tango", "chop":
			if w.map.tree_at(point, 140.0) < 0:
				return "Must target a tree"
		"plant":
			if not w.map.can_plant(point):
				return "Cannot plant a tree there"
	return ""

## Happens at once without a cast point or interrupting anything: no-target items, toggles (Stench) and immediate
## spells (Blubber).
func is_instant(u: SimUnit, aid: String, slot: int) -> bool:
	if slot >= 0:
		return u.inventory[slot] != null and item_target(u.inventory[slot].id) == "none"
	if aid == "" or aid == "tp":
		return false
	var a := SimData.ability(aid)
	return String(a.get("behavior", "")) == "toggle" or bool(a.get("immediate", false))

## "none", "point" (ground / tree) or "unit".
func item_target(item_id: String) -> String:
	match String(SimData.item(item_id).get("use", "")):
		"tango", "chop", "ward", "plant":
			return "point"
	return "none"

func cast_range(u: SimUnit, aid: String, slot: int) -> float:
	if slot >= 0:
		var it = u.inventory[slot]
		if it == null:
			return 0.0
		match String(SimData.item(it.id).use):
			"tango":
				return 165.0
			"chop":
				return 350.0
			"ward":
				return 500.0
			"plant":
				return C.PLANT_RANGE
		return 0.0
	if aid == "tp":
		return INF
	var a := SimData.ability(aid)
	if a.behavior == "autocast_attack":
		return u.attack_range
	if a.get("direction", false):
		return INF                               # aimed by direction only: cast from where the hero stands
	return float(a.range)

func cast_point(aid: String, slot: int) -> float:
	if slot >= 0 or aid == "tp":
		return 0.0
	return float(SimData.ability(aid).get("cast_point", 0.0))

# ---- Executing ------------------------------------------------------------------------------------------------------

func execute(u: SimUnit, aid: String, slot: int, t: SimUnit, p: Vector2) -> void:
	if slot >= 0:
		_use_item(u, slot, t, p)
		return
	if aid == "tp":
		_start_tp(u, p)
		return
	var a := SimData.ability(aid)
	var lv := u.ability_level_of(aid)
	if String(a.behavior) == "toggle":
		set_toggle(u, aid, not bool(u.toggles.get(aid, false)))
		return
	u.mana -= ability_mana(u, aid)
	u.ability_ready[aid] = w.time + ability_cooldown(u, aid)
	w.events.append({"t": "cast", "u": u.id, "ability": aid, "point": p, "target": t.id if t else -1})
	_charge_sticks(u)
	match aid:
		"burst_shot":
			_start_burst(u, a, lv, p)
		"gale_impact":
			var dir := (p - u.pos).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.from_angle(u.facing)
			var reach := _v(a, "distance", lv)       # always the full range, wherever the player clicked
			_cast_seq += 1
			w.effects.append({"kind": "line", "ability": aid, "src": u.id, "team": u.team, "pos": u.pos, "dir": dir,
				"speed": _v(a, "speed", lv), "left": reach, "width": _v(a, "width", lv), "damage": _v(a, "damage", lv),
				"push_speed": _v(a, "push_speed", lv), "lv": lv, "seq": _cast_seq, "hit": {}})
			w.events.append({"t": "gale_impact", "u": u.id, "from": u.pos, "dir": dir, "dist": reach,
				"speed": _v(a, "speed", lv), "width": _v(a, "width", lv)})
		"blood_ranger_ult":
			var dur := _v(a, "duration", lv)
			u.add_modifier({"id": "blood_ranger", "source": u.id, "expires": w.time + dur, "fx": "blood",
				"stats": {"lifesteal_ability": _v(a, "lifesteal", lv), "range": _v(a, "bonus_range", lv)},
				"leap_chance": _v(a, "leap_chance", lv), "leap_distance": _v(a, "leap_distance", lv),
				"leap_time": _v(a, "leap_time", lv), "leap_cooldown": _v(a, "leap_cooldown", lv)})
			u.refresh_stats()
			w.events.append({"t": "blood_ranger_start", "u": u.id, "dur": dur})
		"dark_stomp":
			_dark_stomp(u, a, lv)
		"leap_strike":
			var lt := leap_target(u, lv)
			if lt != null:
				u.leap = {"target": lt.id, "from": u.pos, "to": lt.pos, "t": 0.0, "dur": _v(a, "leap_time", lv), "lv": lv,
					"z": 0.0, "height": 150.0 + 0.12 * u.pos.distance_to(lt.pos)}
				u.facing = (lt.pos - u.pos).angle()
				w.events.append({"t": "leap_start", "u": u.id, "target": lt.id, "dur": u.leap.dur})
		"shuriken_hook":
			_start_hook(u, aid, lv, p)
		"blubber":
			var bdur := val(u, aid, "duration")
			u.add_modifier({"id": "blubber", "source": u.id, "expires": w.time + bdur, "block_all": val(u, aid, "block"),
				"fx": "blubber"})
			w.events.append({"t": "blubber", "u": u.id, "dur": bdur})
		"chomp":
			_start_chomp(u, aid, lv, t)
		"tainted_touch":
			u.add_modifier({"id": "tainted_touch", "source": u.id, "expires": w.time + _v(a, "duration", lv), "tainted": lv,
				"fx": "taint"})
			w.events.append({"t": "taint_cast", "u": u.id, "dur": _v(a, "duration", lv)})
		"unholy_might":
			var dur := _v(a, "duration", lv)
			u.add_modifier({"id": "unholy_might", "source": u.id, "expires": w.time + dur, "chance": _v(a, "chance", lv),
				"radius": _v(a, "reflect_radius", lv), "fx": "unholy"})
			w.effects.append({"kind": "delayed", "what": "unholy_end", "unit": u.id, "at": w.time + dur, "cast_t": w.time,
				"slow": _v(a, "fatigue_slow", lv), "slow_t": _v(a, "fatigue_duration", lv)})
			w.events.append({"t": "unholy_start", "u": u.id, "dur": dur})

func _v(a: Dictionary, key: String, lv: int) -> float:
	return _lvl_val(a, key, lv)

## Every hero spell cast charges enemy Spark Rods / Wands within range.
func _charge_sticks(caster: SimUnit) -> void:
	for h in w.heroes:
		if not h.alive or h.team == caster.team or h.pos.distance_to(caster.pos) > 1200.0:
			continue
		for i in 6:
			var it = h.inventory[i]
			if it != null and String(SimData.item(it.id).use) == "stick":
				h.stick_charges = mini(h.stick_charges + 1, int(SimData.item(it.id).values.max_charges))
				break

# ---- Town Portal -----------------------------------------------------------------------------------------------------

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

# ---- Attack modifier (orb) ------------------------------------------------------------------------------------------

## The modifier riding on an attack about to start: a manual cast (stored on the unit) or autocast with mana.
func attack_modifier_for(u: SimUnit, t: SimUnit) -> String:
	if not u.is_hero() or t.is_building() or t.team == u.team:
		return ""
	for aid in u.abilities:
		var a := SimData.ability(aid)
		if a.behavior != "autocast_attack" or u.ability_level_of(aid) <= 0:
			continue
		var manual: bool = u.orb_manual == aid
		if (manual or bool(u.autocast.get(aid, false))) and u.mana >= _lvl_val(a, "mana", u.ability_level_of(aid)) and not u.is_silenced():
			return aid
	return ""

func pay_attack_modifier(u: SimUnit, aid: String) -> void:
	var a := SimData.ability(aid)
	u.mana = maxf(0.0, u.mana - _lvl_val(a, "mana", u.ability_level_of(aid)))
	u.orb_manual = ""

func attack_modifier_damage(s: Dictionary, t: SimUnit) -> float:
	var src := w.get_unit(s.src)
	if src == null:
		return 0.0
	var a := SimData.ability(s.mod)
	return _v(a, "bonus_damage", maxi(1, src.ability_level_of(s.mod)))

## An attack modifier that slows ("slow" and "duration" values) applies it when the attack lands.
func attack_modifier_hit(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(s.src)
	if src == null or t.is_building():
		return
	var a := SimData.ability(s.mod)
	var lv := maxi(1, src.ability_level_of(s.mod))
	if (a.values as Dictionary).has("slow"):
		t.add_modifier({"id": String(s.mod) + "_slow", "source": src.id, "expires": w.time + _v(a, "duration", lv),
			"slow": _v(a, "slow", lv), "fx": "slow"})

# ---- Timed effects -----------------------------------------------------------------------------------------------------

func update_effects() -> void:
	for i in range(w.effects.size() - 1, -1, -1):
		var e: Dictionary = w.effects[i]
		var done := false
		match e.kind:
			"line":
				done = _update_line(e)
			"delayed":
				done = _update_delayed(e)
			"hook":
				done = _update_hook(e)
			"pulse":
				done = _update_pulse(e)
		if done:
			w.effects.remove_at(i)

## Gale Impact's arrow, one tick: it fells the trees it passes and strikes each enemy once, hurling it sideways off
## the arrow's line (away from the side it stood on) with a little of the arrow's momentum.
func _update_line(e: Dictionary) -> bool:
	var step: float = e.speed * C.DT
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * minf(step, e.left)
	e.pos = to
	e.left -= step
	var dir: Vector2 = e.dir
	# trees in the arrow's path
	var r: float = e.width
	var c0 := w.map.world_to_cell(Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(r, r))
	var c1 := w.map.world_to_cell(Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2(r, r))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti < 0 or not w.map.trees[ti].alive:
				continue
			var tp: Vector2 = w.map.trees[ti].pos
			if Geometry2D.get_closest_point_to_segment(tp, from, to).distance_to(tp) <= r + 40.0:
				w.cut_tree(ti, tp - dir * 100.0, true)
	for o: SimUnit in w.query(to, e.width + 200.0, true):
		if o.team == e.team or o.is_building() or o.is_ward() or o.kind == K.COURIER or e.hit.has(o.id) or not o.alive:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > e.width + o.hull:
			continue
		e.hit[o.id] = true
		if o.is_invulnerable():
			continue
		w.combat.deal_damage(e.src, e.team, true, o, e.damage, C.DamageType.MAGICAL, false, String(e.ability))
		w.events.append({"t": "gale_hit", "u": o.id, "src": e.src, "pos": o.pos, "dir": dir})
		if o.alive and o.kind != K.TOWER:
			var side := dir.orthogonal()
			var off := (o.pos - cp).dot(side)
			if absf(off) < 1.0:
				off = 1.0 if w.rng.randf() < 0.5 else -1.0
			var push := (side * signf(off) + dir * 0.3).normalized() * float(e.push_speed) / mass(o)
			start_push(o, push, int(e.src), int(e.team), String(e.ability), int(e.lv), int(e.seq))
		if o.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(e.src)
			if src:
				w.ai.neutral_provoked(o, src)
	w.events.append({"t": "effect_move", "ability": e.ability, "pos": to, "src": e.src, "done": e.left <= 0.0})
	return e.left <= 0.0

func _update_delayed(e: Dictionary) -> bool:
	if w.time < float(e.at):
		return false
	var u := w.get_unit(int(e.unit))
	if e.what == "unholy_end" and u != null and u.alive and u.death_at <= float(e.cast_t):
		u.add_modifier({"id": "unholy_fatigue", "source": u.id, "expires": w.time + float(e.slow_t), "slow": float(e.slow),
			"fx": "fatigue"})
		w.events.append({"t": "unholy_end", "u": u.id})
	return true

# ---- Ezee, the Dark Paladin ---------------------------------------------------------------------------------------

## Enemies Ezee's spells may touch: living, visible or not, never buildings, wards or couriers.
func _ezee_can_hit(u: SimUnit, o: SimUnit) -> bool:
	return o.alive and o.team != u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
		and not o.is_invulnerable()

## Dark Stomp: magic damage around Ezee, then a physics push away from him. A pushed enemy that crashes into a unit,
## tree, cliff or building takes impact damage and is stunned once it comes to rest.
func _dark_stomp(u: SimUnit, a: Dictionary, lv: int) -> void:
	var r := _v(a, "radius", lv)
	_cast_seq += 1
	w.events.append({"t": "stomp", "u": u.id, "pos": u.pos, "radius": r})
	for o: SimUnit in w.query(u.pos, r, true):
		if not _ezee_can_hit(u, o) or u.edge_distance(o) > r:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, _v(a, "damage", lv), C.DamageType.MAGICAL, false, "dark_stomp")
		if not o.alive:
			continue
		var dir := o.pos - u.pos
		if dir.length() < 1.0:
			dir = Vector2.from_angle(u.facing)
		var near := clampf(1.0 - u.pos.distance_to(o.pos) / r, 0.0, 1.0)
		var speed := _v(a, "push_speed", lv) * lerpf(0.72, 1.0, near) / mass(o)
		start_push(o, dir.normalized() * speed, u.id, u.team, "dark_stomp", lv, _cast_seq)

var _cast_seq := 0
var _impacted := {}                         # cast seq -> {unit id: true}: impact damage lands once per unit per cast

## How hard a unit is to shove: by hull (creeps 1, heroes 1.2, big neutrals and siege golems up to 2).
func mass(o: SimUnit) -> float:
	if o.kind == K.CREEP_SIEGE:
		return 1.8
	if o.is_hero():
		return 1.2
	return clampf(o.hull / 16.0, 0.7, 2.2)

const GRAVITY := 2600.0                    # game units / s^2 for the airborne part of a push
const AIR_DRAG := 900.0                    # deceleration while airborne
const SKID := 4200.0                       # deceleration while sliding on the ground
const IMPACT_SPEED := 260.0                # slower bumps are not impacts
const RESTITUTION := 0.3

## Start a physics push (no mass applied: `vel` is the unit's own velocity). Interrupts channels and swings.
func start_push(o: SimUnit, vel: Vector2, src_id: int, team: int, aid: String, lv: int, seq: int) -> void:
	if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER:
		return
	if not o.knock.is_empty() and o.knock.get("phys", false):
		o.knock.vel = (o.knock.vel as Vector2) + vel
		return
	w.orders.cancel_channel(o)
	var vz := 520.0 * clampf(vel.length() / 1000.0, 0.35, 1.1)
	o.knock = {"phys": true, "vel": vel, "z": 0.0, "vz": vz, "t": 0.0, "src": src_id, "team": team, "ability": aid,
		"lv": lv, "seq": seq, "impacted": false, "stun": 0.0}
	o.path = PackedVector2Array()
	w.events.append({"t": "knockback", "u": o.id, "phys": true, "vel": vel})

## One tick of a push: an eased slide (Gale Shot) or ballistic flight, drag, wall bounces and unit collisions.
func update_motion(u: SimUnit) -> void:
	if not u.leap.is_empty():
		_update_leap(u)
	if not u.hop.is_empty():
		if not u.knock.is_empty() or not u.alive:
			u.hop = {}
		else:
			_update_hop(u)
	if u.knock.is_empty():
		return
	var k := u.knock
	if k.get("drag", false):
		return                                         # dragged by a Shuriken Hook: the hook moves it
	if not k.get("phys", false):
		k.t += C.DT
		var f := clampf(k.t / k.dur, 0.0, 1.0)
		var np: Vector2 = (k.from as Vector2).lerp(k.to, f)
		if w.map.is_walkable(np):
			u.pos = np
		if f >= 1.0:
			u.knock = {}
			u.path = PackedVector2Array()
		return
	k.t += C.DT
	var v: Vector2 = k.vel
	var airborne: bool = k.z > 0.0 or k.vz > 0.0
	if airborne:
		k.vz -= GRAVITY * C.DT
		k.z += k.vz * C.DT
		if k.z <= 0.0:
			k.z = 0.0
			k.vz = 0.0
			w.events.append({"t": "push_land", "u": u.id, "speed": v.length()})
	var speed := v.length()
	var slowed := maxf(0.0, speed - (AIR_DRAG if airborne else SKID) * C.DT)
	if speed > 0.0:
		v *= slowed / speed
	var step := v * C.DT
	var np := u.pos + step
	if not w.map.is_walkable(np):
		var what := _obstacle(np)
		_impact(u, k, what, -1, speed, np)
		# bounce off the wall: reverse the blocked axis, keep sliding along the free one
		var x_ok := w.map.is_walkable(u.pos + Vector2(step.x, 0.0))
		var y_ok := w.map.is_walkable(u.pos + Vector2(0.0, step.y))
		if not x_ok:
			v.x = -v.x * RESTITUTION
		if not y_ok:
			v.y = -v.y * RESTITUTION
		if x_ok and y_ok:
			v = -v * RESTITUTION
		np = u.pos + Vector2(step.x if x_ok else 0.0, step.y if y_ok else 0.0)
		if not w.map.is_walkable(np):
			np = u.pos
	else:
		for o: SimUnit in w.query(np, u.hull + 120.0):
			if o == u or not o.alive or o.is_ward() or o.kind == K.COURIER or o.is_building():
				continue
			var min_d := u.hull + o.hull
			if np.distance_to(o.pos) >= min_d:
				continue
			var n := (o.pos - u.pos).normalized()
			if n == Vector2.ZERO:
				continue
			var vn := v.dot(n)
			if vn <= 0.0:
				continue
			# a 1D collision along the line of centres (restitution 0.6), the struck unit is shoved on
			var m1 := mass(u)
			var m2 := mass(o)
			var e := 0.6
			var v1n := (m1 - e * m2) * vn / (m1 + m2)
			var v2n := (1.0 + e) * m1 * vn / (m1 + m2)
			v += n * (v1n - vn)
			if vn > IMPACT_SPEED:
				_impact(u, k, "unit", o.id, vn, (u.pos + o.pos) * 0.5)
				if v2n > 120.0:
					start_push(o, n * v2n, int(k.src), int(k.team), String(k.ability), int(k.lv), int(k.seq))
					if not o.knock.is_empty():
						_impact(o, o.knock, "unit", u.id, vn, (u.pos + o.pos) * 0.5)
			np = u.pos + v * C.DT
			break
		if not w.map.is_walkable(np):
			np = u.pos
	u.pos = np
	k.vel = v
	if (k.z <= 0.0 and v.length() < 60.0) or k.t > 1.6:
		u.knock = {}
		u.path = PackedVector2Array()
		if float(k.stun) > 0.0 and u.alive:
			u.add_modifier({"id": "stun", "source": int(k.src), "expires": w.time + float(k.stun), "stun": true, "fx": "stun"})
			w.events.append({"t": "stunned", "u": u.id, "dur": float(k.stun)})

func _obstacle(p: Vector2) -> String:
	if w.map.tree_at(p, 110.0) >= 0:
		return "tree"
	for b: SimUnit in w.query(p, 420.0):
		if b.is_building() and b.pos.distance_to(p) < b.hull + 60.0:
			return "building"
	return "cliff"

## A pushed unit hits something: one impact per unit per push. Enemies of the caster take impact damage and will be
## stunned for the ability's impact stun once they stop; a tree that takes the blow is smashed.
func _impact(u: SimUnit, k: Dictionary, what: String, other: int, speed: float, at: Vector2) -> void:
	if k.impacted or speed < IMPACT_SPEED:
		return
	k.impacted = true
	w.events.append({"t": "impact", "u": u.id, "what": what, "other": other, "pos": at, "speed": speed})
	if what == "tree":
		var ti := w.map.tree_at(at, 110.0)
		if ti >= 0:
			w.cut_tree(ti, u.pos, true)
	var aid := String(k.ability)
	if u.team == int(k.team) or not (aid in ["dark_stomp", "gale_impact"]):
		return
	var seq := int(k.seq)
	if not _impacted.has(seq):
		_impacted[seq] = {}
		if _impacted.size() > 16:
			_impacted.erase(_impacted.keys()[0])
	if _impacted[seq].has(u.id):
		return
	_impacted[seq][u.id] = true
	var a := SimData.ability(aid)
	var lv := int(k.lv)
	if aid == "gale_impact":
		# Gale Impact: the crash deals another 20% of the arrow's damage, no stun
		w.combat.deal_damage(int(k.src), int(k.team), true, u, _v(a, "damage", lv) * _v(a, "impact_pct", lv),
			C.DamageType.MAGICAL, false, "gale_impact")
		return
	w.combat.deal_damage(int(k.src), int(k.team), true, u, _v(a, "impact_damage", lv), C.DamageType.MAGICAL, false, "dark_stomp")
	k.stun = _v(a, "impact_stun", lv)

## Leap Strike's target: the visible enemy in range with the lowest health fraction, the nearest if none is hurt.
func leap_target(u: SimUnit, lv: int) -> SimUnit:
	var a := SimData.ability("leap_strike")
	var rng := float(a.range)
	var hurt: SimUnit = null
	var hurt_key := INF
	var near: SimUnit = null
	var near_d := INF
	for o: SimUnit in w.query(u.pos, rng + 200.0, true):
		if not _ezee_can_hit(u, o) or not w.vision.sees(u.team, o):
			continue
		var d := u.edge_distance(o)
		if d > rng:
			continue
		var frac := o.hp / maxf(1.0, o.max_hp)
		if frac < 0.999:
			var key := frac * 100000.0 + d
			if key < hurt_key:
				hurt_key = key
				hurt = o
		if d < near_d:
			near_d = d
			near = o
	return hurt if hurt != null else near

func _update_leap(u: SimUnit) -> void:
	var L := u.leap
	L.t += C.DT
	var t := w.get_unit(int(L.target))
	if t != null and t.alive:
		L.to = t.pos
	var from: Vector2 = L.from
	var to: Vector2 = L.to
	var dir := (to - from)
	var reach := u.hull + (t.hull if t else 0.0) + 6.0
	var land := to - dir.normalized() * reach if dir.length() > reach else from
	var f := clampf(L.t / L.dur, 0.0, 1.0)
	var np := from.lerp(land, f)
	L.z = sin(f * PI) * float(L.height)
	if dir.length() > 1.0:
		u.facing = dir.angle()
	if f >= 1.0:
		if not w.map.is_walkable(np):
			var c := w.map.nearest_walkable(w.map.world_to_cell(np))
			np = w.map.cell_center(c.x, c.y)
		u.pos = np
		u.leap = {}
		var hit := t != null and t.alive and t.pos.distance_to(np) < reach + 200.0
		w.events.append({"t": "leap_land", "u": u.id, "target": t.id if t else -1, "pos": np, "hit": hit})
		if hit:
			var a := SimData.ability("leap_strike")
			var lv := int(L.lv)
			var dmg := _v(a, "damage", lv) + _v(a, "str_mult", lv) * u.str_total
			w.combat.deal_damage(u.id, u.team, true, t, dmg, C.DamageType.PURE, false, "leap_strike")
			if t.alive:
				t.add_modifier({"id": "leap_strike_slow", "source": u.id, "expires": w.time + _v(a, "slow_duration", lv),
					"slow": _v(a, "slow", lv), "fx": "slow"})
				if u.order == O.NONE:
					w.orders.issue(u, {"type": O.ATTACK_UNIT, "target": t.id}, false)
		return
	u.pos = np

## Tainted Touch on an attack that landed: bonus magic damage and the curse (revealed, sight around it).
func tainted_hit(s: Dictionary, t: SimUnit) -> void:
	var a := SimData.ability("tainted_touch")
	var lv := int(s.taint)
	w.combat.deal_damage(s.src, s.team, bool(s.hero), t, _v(a, "bonus_damage", lv), C.DamageType.MAGICAL, false, "tainted_touch")
	if t.alive:
		t.add_modifier({"id": "tainted_curse", "source": s.src, "expires": w.time + _v(a, "curse_duration", lv),
			"reveal": int(s.team), "reveal_r": _v(a, "curse_vision", lv), "fx": "curse"})
		w.events.append({"t": "curse", "u": t.id, "src": s.src})

## Unholy Might: a random enemy of `t` near it to take the deflected half of a blow (null if none).
func unholy_victim(t: SimUnit, radius: float) -> SimUnit:
	var pool: Array = []
	for o: SimUnit in w.query(t.pos, radius, true):
		if _ezee_can_hit(t, o) and t.edge_distance(o) <= radius:
			pool.append(o)
	if pool.is_empty():
		return null
	return pool[w.rng.randi_range(0, pool.size() - 1)]

# ---- Blood Ranger -------------------------------------------------------------------------------------------------

## Burst Shot: mana and cooldown are spent as the channel begins (Dota); the arrows go out in waves while it lasts.
## The 30 arrows are split into 5 waves of 4-7 at random (the split always sums to 30).
func _start_burst(u: SimUnit, a: Dictionary, lv: int, p: Vector2) -> void:
	var waves := int(_v(a, "waves", lv))
	var total := int(_v(a, "arrows", lv))
	var split := burst_split(total, waves, int(_v(a, "wave_min", lv)), int(_v(a, "wave_max", lv)))
	var interval := _v(a, "wave_interval", lv)
	u.channel = {"ability": "burst_shot", "until": w.time + interval * waves, "start": w.time, "dur": interval * waves,
		"point": p, "radius": _v(a, "radius", lv),
		"waves": split, "next_wave": 0, "next_at": w.time, "interval": interval, "pct": _v(a, "attack_pct", lv),
		"speed": _v(a, "arrow_speed", lv)}
	u.facing = (p - u.pos).angle() if p.distance_to(u.pos) > 1.0 else u.facing
	w.events.append({"t": "channel_start", "u": u.id, "ability": "burst_shot", "until": u.channel.until,
		"point": p, "radius": u.channel.radius})

## A random split of `total` into `n` parts each within [lo, hi] (falls back to an even split if impossible).
func burst_split(total: int, n: int, lo: int, hi: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	if total < lo * n or total > hi * n:
		for k in n:
			out.append(total / n + (1 if k < total % n else 0))
		return out
	var left := total
	for k in n:
		var rest := n - k - 1
		var a := maxi(lo, left - hi * rest)
		var b := mini(hi, left - lo * rest)
		var take := w.rng.randi_range(a, b)
		out.append(take)
		left -= take
	return out

## One tick of a Burst Shot channel: fire the next wave when it is due. Each arrow picks a random enemy in the area
## (heroes and creeps alike, never buildings or wards) or, with none there, a random spot on the ground.
func update_burst(u: SimUnit) -> void:
	var ch := u.channel
	var waves: Array = ch.waves
	if int(ch.next_wave) >= waves.size() or w.time + 0.0001 < float(ch.next_at):
		return
	var n := int(waves[int(ch.next_wave)])
	ch.next_wave = int(ch.next_wave) + 1
	ch.next_at = float(ch.next_at) + float(ch.interval)
	var center: Vector2 = ch.point
	var r: float = ch.radius
	var pool: Array = []
	for o: SimUnit in w.query(center, r, true):
		if o.alive and o.team != u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER 				and not o.is_invulnerable() and o.pos.distance_to(center) <= r + o.hull:
			pool.append(o)
	var dmg := ((u.dmg_min + u.dmg_max) * 0.5 + u.bonus_damage) * float(ch.pct)
	var targets: Array = []
	for k in n:
		if pool.is_empty():
			var spot := center + Vector2.from_angle(w.rng.randf() * TAU) * sqrt(w.rng.randf()) * r
			targets.append(spot)
			w.combat.launch_spell_arrow(u, null, spot, dmg, float(ch.speed), "burst_shot")
		else:
			var t: SimUnit = pool[w.rng.randi_range(0, pool.size() - 1)]
			targets.append(t.id)
			w.combat.launch_spell_arrow(u, t, t.pos, dmg, float(ch.speed), "burst_shot")
	w.events.append({"t": "burst_wave", "u": u.id, "wave": int(ch.next_wave), "count": n, "point": center, "radius": r})

## Masterful Archery: rolled when an attack is released (so the arrow can show it); 0.8 s cooldown after a burst.
func masterful_bonus(u: SimUnit, t: SimUnit) -> float:
	var lv := u.ability_level_of("masterful_archery")
	if lv <= 0 or t.is_building() or t.team == u.team:
		return 0.0
	if w.time < float(u.ability_ready.get("masterful_archery", C.LONG_AGO)):
		return 0.0
	var a := SimData.ability("masterful_archery")
	if w.rng.randf() >= _v(a, "chance", lv):
		return 0.0
	u.ability_ready["masterful_archery"] = w.time + _v(a, "proc_cooldown", lv)
	return u.agi_total * _v(a, "agility_pct", lv)

## Blood Ranger: an attack that hit her may make her leap back, away from the attacker (1 s apart at most).
func on_attacked(t: SimUnit, attacker: SimUnit) -> void:
	if not t.alive or attacker == null:
		return
	var m := t.get_modifier("blood_ranger")
	if m.is_empty() or not t.hop.is_empty() or t.is_stunned() or t.is_leaping():
		return
	if w.time < float(t.get_meta("hop_ready", C.LONG_AGO)):
		return
	if w.rng.randf() >= float(m.leap_chance):
		return
	var away := t.pos - attacker.pos
	if away.length() < 1.0:
		away = Vector2.from_angle(t.facing + PI)
	away = away.normalized()
	# the leap stops short of cliffs, trees and buildings
	var dist := float(m.leap_distance)
	var dest := t.pos
	var step := 16.0
	var d := step
	while d <= dist:
		var q := t.pos + away * d
		if not w.map.is_walkable(q) or _building_at(q, t.hull):
			break
		dest = q
		d += step
	if dest.distance_to(t.pos) < 40.0:
		return
	t.set_meta("hop_ready", w.time + float(m.leap_cooldown))
	t.hop = {"from": t.pos, "to": dest, "t": 0.0, "dur": float(m.leap_time) * dest.distance_to(t.pos) / dist, "z": 0.0}
	t.path = PackedVector2Array()
	w.events.append({"t": "back_leap", "u": t.id, "from": t.pos, "to": dest, "dur": float(t.hop.dur)})

func _building_at(p: Vector2, hull: float) -> bool:
	for b: SimUnit in w.query(p, 420.0):
		if b.is_building() and b.pos.distance_to(p) < b.hull * 0.85 + hull:
			return true
	return false

## The back leap: a quick arc that keeps her orders (she may keep turning and attacking, but not walk).
func _update_hop(u: SimUnit) -> void:
	var H := u.hop
	H.t = float(H.t) + C.DT
	var f := clampf(float(H.t) / maxf(0.05, float(H.dur)), 0.0, 1.0)
	var e := 1.0 - (1.0 - f) * (1.0 - f)
	u.pos = (H.from as Vector2).lerp(H.to, e)
	H.z = sin(f * PI) * 70.0
	if f >= 1.0:
		u.hop = {}
		w.events.append({"t": "back_leap_land", "u": u.id, "pos": u.pos})

# ---- Channels ---------------------------------------------------------------------------------------------------

## One tick of an ability channel (Burst Shot's waves, Chomp's bites).
func channel_tick(u: SimUnit) -> void:
	match String(u.channel.ability):
		"burst_shot":
			update_burst(u)
		"chomp":
			_update_chomp(u)

## A channel ended (finished, or cancelled by an order, stun, silence, push or death): undo what it holds.
func channel_cleanup(u: SimUnit, ch: Dictionary, _cancelled: bool) -> void:
	match String(ch.ability):
		"chomp":
			var t := w.get_unit(int(ch.get("target", -1)))
			if t != null:
				_remove_mod(t, "chomp", u.id)

func _remove_mod(t: SimUnit, mid: String, source: int) -> void:
	for i in range(t.modifiers.size() - 1, -1, -1):
		if t.modifiers[i].id == mid and int(t.modifiers[i].get("source", -1)) == source:
			t.modifiers.remove_at(i)
			t.stats_dirty = true

# ---- Sludge, the Butcher (Dota 2's Pudge) -----------------------------------------------------------------------

## Growing Gut: an enemy hero died. Every Sludge on the other team within 450 (alive) or credited with the kill grows.
func on_hero_death(t: SimUnit, killer: SimUnit, credit: SimUnit) -> void:
	for h in w.heroes:
		if h.team == t.team or not h.ability_level.has("growing_gut"):
			continue
		var near := h.alive and h.pos.distance_to(t.pos) <= val(h, "growing_gut", "radius")
		if near or h == killer or h == credit:
			h.stacks["growing_gut"] = int(h.stacks.get("growing_gut", 0)) + 1
			rebuild_perm_stats(h)
			w.events.append({"t": "growing_gut", "u": h.id, "stacks": h.stacks.growing_gut,
				"gain": val(h, "growing_gut", "str_per_stack")})

## Shuriken Hook: the chain always flies its full range toward the target point. While it flies out Sludge is rooted,
## disarmed, muted and cannot turn, for (range / speed) x 65% seconds, unless it catches something first.
func _start_hook(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var dir := p - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var reach := val(u, aid, "distance")
	var speed := val(u, aid, "speed")
	_cast_seq += 1
	u.facing = dir.angle()
	u.add_modifier({"id": "hook_lock", "source": u.id, "expires": w.time + reach / speed * val(u, aid, "lock_pct"),
		"root": true, "disarm": true, "mute": true, "face_lock": true})
	w.effects.append({"kind": "hook", "ability": aid, "src": u.id, "team": u.team, "origin": u.pos, "pos": u.pos,
		"dir": dir, "left": reach, "speed": speed, "width": val(u, aid, "width"), "damage": val(u, aid, "damage"),
		"drag_pct": val(u, aid, "drag_damage_pct") if u.shard else 0.0,
		"vision_r": val(u, aid, "vision_radius"), "vision_t": val(u, aid, "vision_duration"), "lv": lv,
		"seq": _cast_seq, "state": "out", "target": -1, "src_hull": u.hull})
	w.events.append({"t": "hook_launch", "u": u.id, "from": u.pos, "dir": dir, "dist": reach, "speed": speed,
		"seq": _cast_seq})

## The first unit the hook's tip touches between `from` and `to` (nearest along the flight, ties by id): living heroes
## and creeps of either team, never buildings, wards, couriers, ancient creeps or invulnerable units. Fog, cliffs and
## trees do not stop it.
func hook_first_hit(team_src: int, origin: Vector2, dir: Vector2, from: Vector2, to: Vector2, width: float) -> SimUnit:
	var best: SimUnit = null
	var best_t := INF
	var mid := (from + to) * 0.5
	for o: SimUnit in w.query(mid, from.distance_to(to) * 0.5 + width + 80.0, true):
		if not o.alive or o.id == team_src or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		if bool(o.def.get("ancient", false)) or o.is_invulnerable():
			continue
		if (o.pos - origin).dot(dir) < -o.hull:
			continue                                   # behind the thrower
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > width + o.hull:
			continue
		var along := (cp - from).length()
		if along < best_t - 0.01 or (absf(along - best_t) <= 0.01 and best != null and o.id < best.id):
			best_t = along
			best = o
	return best

func _update_hook(e: Dictionary) -> bool:
	var step: float = float(e.speed) * C.DT
	var dir: Vector2 = e.dir
	if e.state == "out":
		var from: Vector2 = e.pos
		var adv := minf(step, float(e.left))
		var to: Vector2 = from + dir * adv
		var hit := hook_first_hit(int(e.src), e.origin, dir, from, to, float(e.width))
		if hit != null:
			e.pos = from + dir * clampf((hit.pos - from).dot(dir), 0.0, adv)
			_hook_latch(e, hit)
		else:
			e.pos = to
			e.left = float(e.left) - adv
			if float(e.left) <= 0.001:
				e.state = "back"
		w.events.append({"t": "hook_move", "src": e.src, "seq": e.seq, "pos": e.pos, "state": e.state, "target": e.target})
		return false
	# reeling in: the tip (and whatever it caught) returns to where Sludge threw it
	var t := w.get_unit(int(e.target))
	if t != null and (not t.alive or int(t.knock.get("seq", -1)) != int(e.seq) or not bool(t.knock.get("drag", false))):
		t = null                                       # it died, or another push took it
		e.target = -1
	var origin: Vector2 = e.origin
	var goal := origin + dir * ((float(e.src_hull) + t.hull) if t != null else 0.0)
	var left := (e.pos as Vector2).distance_to(goal)
	if left <= step:
		e.pos = goal
		if t != null:
			_hook_release(t, goal)
		w.events.append({"t": "hook_end", "src": e.src, "seq": e.seq, "pos": goal, "target": e.target})
		return true
	e.pos = (e.pos as Vector2) + (goal - (e.pos as Vector2)).normalized() * step
	if t != null:
		t.pos = e.pos
	w.events.append({"t": "hook_move", "src": e.src, "seq": e.seq, "pos": e.pos, "state": e.state, "target": e.target})
	return false

## The tip catches `o`: sight there, Sludge is free to act again, and the catch is dragged back. Enemy heroes (and
## ancient-free enemy units other than creeps) take pure damage and are stunned while dragged; enemy creeps die at
## once; allies are pulled without harm (with the Upgrade Gem the hook's cooldown is halved).
func _hook_latch(e: Dictionary, o: SimUnit) -> void:
	e.state = "back"
	e.target = o.id
	var caster := w.get_unit(int(e.src))
	if caster != null:
		caster.remove_modifier("hook_lock")
	w.vision.add_source(int(e.team), e.pos, float(e.vision_r), float(e.vision_t))
	var ally := o.team == int(e.team)
	w.events.append({"t": "hook_latch", "u": o.id, "src": e.src, "pos": e.pos, "seq": e.seq, "ally": ally})
	if not ally and o.is_creep():
		e.target = -1
		w.events.append({"t": "hook_kill", "u": o.id, "src": e.src})
		w.combat.kill(o, caster)
		return
	w.orders.cancel_channel(o)
	o.leap = {}
	o.hop = {}
	o.path = PackedVector2Array()
	o.knock = {"drag": true, "seq": int(e.seq), "disable": not ally, "src": int(e.src)}
	if ally:
		if caster != null and caster.shard:
			var aid := String(e.ability)
			var left := float(caster.ability_ready.get(aid, w.time)) - w.time
			caster.ability_ready[aid] = w.time + maxf(0.0, left) * val(caster, aid, "ally_cooldown_pct")
		return
	var dmg := float(e.damage) + float(e.drag_pct) * (e.pos as Vector2).distance_to(e.origin)
	w.combat.deal_damage(int(e.src), int(e.team), true, o, dmg, C.DamageType.PURE, false, String(e.ability))

func _hook_release(t: SimUnit, at: Vector2) -> void:
	t.knock = {}
	var p := at
	if not w.map.is_walkable(p):
		var c := w.map.nearest_walkable(w.map.world_to_cell(p))
		p = w.map.cell_center(c.x, c.y)
	t.pos = p
	t.path = PackedVector2Array()
	w.events.append({"t": "hook_release", "u": t.id, "pos": p})

## Toggle abilities (Stench): on adds a pulse effect that ticks while it stays on; off ends it.
func set_toggle(u: SimUnit, aid: String, on: bool) -> void:
	u.toggles[aid] = on
	if on:
		var exists := false
		for e in w.effects:
			if e.kind == "pulse" and int(e.src) == u.id and String(e.ability) == aid:
				exists = true
		if not exists:
			w.effects.append({"kind": "pulse", "ability": aid, "src": u.id, "next_tick": w.tick})
	w.events.append({"t": "toggle", "u": u.id, "ability": aid, "on": on})

## Stench, every 0.2 s while on: magic damage and a lingering slow to enemies around Sludge (not debuff-immune ones),
## and the same damage to Sludge himself, which never kills him. Keeps working while he is stunned or channelling.
func _update_pulse(e: Dictionary) -> bool:
	var u := w.get_unit(int(e.src))
	var aid := String(e.ability)
	if u == null or not u.alive or not bool(u.toggles.get(aid, false)):
		if u != null:
			u.toggles[aid] = false
		return true
	if w.tick < int(e.next_tick):
		return false
	var tick := val(u, aid, "tick")
	e.next_tick = int(e.next_tick) + maxi(1, roundi(tick * C.TICK_RATE))
	var r := val(u, aid, "radius")
	var dmg := val(u, aid, "dps") * tick
	var slow := val(u, aid, "slow")
	var linger := val(u, aid, "linger")
	var hr := val(u, aid, "heal_reduction")
	for o: SimUnit in w.query(u.pos, r + 120.0, true):
		if o == u or not o.alive or o.team == u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		if o.is_invulnerable() or o.debuff_immune or o.pos.distance_to(u.pos) > r + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.MAGICAL, false, aid)
		if o.alive:
			o.add_modifier({"id": "stench", "source": u.id, "expires": w.time + linger, "slow": slow, "heal_reduction": hr,
				"debuff": true, "fx": "stench"})
	w.combat.deal_damage(u.id, u.team, true, u, dmg, C.DamageType.MAGICAL, false, aid, false, {"non_lethal": true})
	return false

## Chomp: the victim is stunned for as long as Sludge channels; bites land evenly from the start.
func _start_chomp(u: SimUnit, aid: String, lv: int, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var dur := val(u, aid, "duration")
	var ticks := maxi(1, roundi(val(u, aid, "ticks")))
	u.channel = {"ability": aid, "until": w.time + dur, "start": w.time, "dur": dur, "target": t.id, "lv": lv,
		"next_tick": w.tick + 1, "interval": maxi(1, roundi(dur / ticks * C.TICK_RATE)), "left": ticks, "ticks": ticks}
	u.facing = (t.pos - u.pos).angle() if t.pos.distance_to(u.pos) > 1.0 else u.facing
	w.orders.cancel_channel(t)
	t.add_modifier({"id": "chomp", "source": u.id, "expires": INF, "stun": true, "debuff": true, "fx": "chomp"})
	w.events.append({"t": "channel_start", "u": u.id, "ability": aid, "until": u.channel.until, "target": t.id})

func _update_chomp(u: SimUnit) -> void:
	var ch := u.channel
	var aid := String(ch.ability)
	var t := w.get_unit(int(ch.target))
	if t == null or not t.alive or t.is_invulnerable() or u.pos.distance_to(t.pos) > 900.0:
		u.channel = {}
		channel_cleanup(u, ch, false)
		u.order = O.NONE
		w.events.append({"t": "channel_end", "u": u.id, "ability": aid, "cancelled": false})
		return
	var to := t.pos - u.pos
	if to.length() > 1.0:
		u.facing = to.angle()
	# pull the victim in at 75 per second until 125 apart
	var pull_min := val(u, aid, "pull_min")
	if to.length() > pull_min and t.knock.is_empty():
		var np := t.pos - to.normalized() * minf(val(u, aid, "pull_speed") * C.DT, to.length() - pull_min)
		if w.map.is_walkable(np):
			t.pos = np
	if int(ch.left) > 0 and w.tick >= int(ch.next_tick):
		ch.left = int(ch.left) - 1
		ch.next_tick = int(ch.next_tick) + int(ch.interval)
		var bite := (val(u, aid, "dps") + val(u, aid, "str_mult") * u.str_total) * float(ch.dur) / float(ch.ticks) \
			* val(u, aid, "damage_mult")
		w.combat.deal_damage(u.id, u.team, true, t, bite, C.DamageType.MAGICAL, false, aid)
		var healed := w.combat.heal(u, bite)
		w.events.append({"t": "chomp_bite", "u": u.id, "target": t.id, "amount": bite, "healed": healed})

# ---- Items --------------------------------------------------------------------------------------------------------

func _use_item(u: SimUnit, slot: int, t: SimUnit, p: Vector2) -> void:
	var it: Dictionary = u.inventory[slot]
	var d := SimData.item(it.id)
	var v: Dictionary = d.values
	it["ready"] = w.time + float(d.cooldown)
	var consumed := false
	match String(d.use):
		"tango":
			# eat the tree: 7 hp/s for 16 s, 32 s if it was a planted tree; a new one refreshes the old
			var ti := w.map.tree_at(p, 140.0)
			var dur := float(v.duration)
			if ti >= 0:
				if w.map.trees[ti].get("planted", false):
					dur = float(v.planted_duration)
				w.cut_tree(ti, Vector2.INF)
			u.add_modifier({"id": "tango", "source": u.id, "expires": w.time + dur, "regen": float(v.health_regen), "fx": "heal"})
			w.events.append({"t": "tango", "u": u.id, "tree": ti})
			consumed = true
		"salve":
			u.add_modifier({"id": "salve", "source": u.id, "expires": w.time + float(v.duration), "regen": float(v.health_regen),
				"break_on_damage": true, "fx": "heal"})
			consumed = true
		"clarity":
			u.add_modifier({"id": "clarity", "source": u.id, "expires": w.time + float(v.duration), "mana_regen": float(v.mana_regen),
				"break_on_damage": true, "fx": "mana"})
			consumed = true
		"mango":
			u.mana = minf(u.max_mana, u.mana + float(v.mana))
			consumed = true
		"faerie_fire":
			w.combat.heal(u, float(v.heal))
			consumed = true
		"stick":
			var amt := float(v.restore_per_charge) * u.stick_charges
			w.combat.heal(u, amt)
			u.mana = minf(u.max_mana, u.mana + amt)
			u.stick_charges = 0
		"chop":
			var ti2 := w.map.tree_at(p, 140.0)
			if ti2 >= 0:
				w.cut_tree(ti2, u.pos)
		"plant":
			var ti3 := w.map.plant_tree(p, w.time + float(v.tree_duration))
			if ti3 >= 0:
				w.vision.static_dirty = true
				w.nudge_out(w.map.trees[ti3].pos, SimMap.CELL * 0.75)
				w.events.append({"t": "tree", "i": ti3, "alive": true, "planted": true})
				consumed = true
		"ward":
			var ward := w.spawn("ward_observer", u.team, p)
			ward.ward_expires = w.time + float(v.lifetime)
			ward.add_modifier({"id": "ward_invis", "source": u.id, "expires": INF, "invisible": true})
			consumed = true
		"berserk":
			u.mana -= float(v.mana)
			u.add_modifier({"id": "berserk", "source": u.id, "expires": w.time + float(v.duration),
				"stats": {"attack_speed": float(v.attack_speed), "move_speed_pct": float(v.move_speed_pct), "armor": -float(v.armor_reduction)}, "fx": "berserk"})
	w.events.append({"t": "item_use", "u": u.id, "item": it.id})
	if consumed:
		it.charges = int(it.get("charges", 1)) - 1
		if it.charges <= 0:
			u.inventory[slot] = null
	u.refresh_stats()
