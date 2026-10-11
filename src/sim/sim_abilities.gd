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

func toggle_autocast(u: SimUnit, aid: String) -> void:
	if SimData.ability(aid).get("behavior", "") == "autocast_attack" and u.ability_level_of(aid) > 0:
		u.autocast[aid] = not bool(u.autocast.get(aid, false))

# ---- Cast rules ---------------------------------------------------------------------------------------------------------

func _lvl_val(a: Dictionary, key: String, lv: int) -> float:
	var arr: Array = a[key] if a.has(key) else a.values[key]
	return float(arr[clampi(lv - 1, 0, arr.size() - 1)])

func cooldown_left(u: SimUnit, aid: String) -> float:
	return maxf(0.0, float(u.ability_ready.get(aid, 0.0)) - w.time)

func item_cooldown_left(u: SimUnit, slot: int) -> float:
	var it = u.inventory[slot]
	if it == null:
		return 0.0
	return maxf(0.0, float(it.get("ready", 0.0)) - w.time)

func cast_error(u: SimUnit, aid: String, slot: int, target: SimUnit, point: Vector2, at_cast := false) -> String:
	if slot >= 0:
		return _item_error(u, slot, target, point)
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
	if u.mana < _lvl_val(a, "mana", lv):
		return "Not enough mana"
	if a.behavior == "autocast_attack":
		if target == null or target.team == u.team or target.is_building():
			return "Must target an enemy unit"
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
	return ""

func is_instant(u: SimUnit, aid: String, slot: int) -> bool:
	if slot >= 0 and u.inventory[slot] != null:
		return item_target(u.inventory[slot].id) == "none"
	return false

## "none", "point" (ground / tree) or "unit".
func item_target(item_id: String) -> String:
	match String(SimData.item(item_id).get("use", "")):
		"tango", "chop", "ward":
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
		return 0.0
	var a := SimData.ability(aid)
	if a.behavior == "autocast_attack":
		return u.attack_range
	return float(a.range)

func cast_point(aid: String, slot: int) -> float:
	if slot >= 0:
		return 0.0
	return float(SimData.ability(aid).get("cast_point", 0.0))

# ---- Executing ------------------------------------------------------------------------------------------------------

func execute(u: SimUnit, aid: String, slot: int, t: SimUnit, p: Vector2) -> void:
	if slot >= 0:
		_use_item(u, slot, t, p)
		return
	var a := SimData.ability(aid)
	var lv := u.ability_level_of(aid)
	u.mana -= _lvl_val(a, "mana", lv)
	u.ability_ready[aid] = w.time + _lvl_val(a, "cooldown", lv)
	w.events.append({"t": "cast", "u": u.id, "ability": aid, "point": p, "target": t.id if t else -1})
	_charge_sticks(u)
	match aid:
		"gale_shot":
			var dir := (p - u.pos).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.from_angle(u.facing)
			w.effects.append({"kind": "line", "ability": aid, "src": u.id, "team": u.team, "pos": u.pos, "dir": dir,
				"speed": _v(a, "speed", lv), "left": _v(a, "distance", lv), "width": _v(a, "width", lv),
				"damage": _v(a, "damage", lv), "push": _v(a, "knockback", lv), "push_t": _v(a, "knockback_time", lv), "hit": {}})
		"arrow_storm":
			w.effects.append({"kind": "volleys", "ability": aid, "src": u.id, "team": u.team, "pos": p,
				"radius": _v(a, "radius", lv), "left": int(_v(a, "volleys", lv)), "interval": _v(a, "interval", lv),
				"next": w.time + 0.25, "damage": _v(a, "damage", lv), "slow": _v(a, "slow", lv), "slow_t": _v(a, "slow_duration", lv)})

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

func attack_modifier_hit(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(s.src)
	if src == null or t.is_building():
		return
	var a := SimData.ability(s.mod)
	var lv := maxi(1, src.ability_level_of(s.mod))
	t.add_modifier({"id": "frost_quiver_slow", "source": src.id, "expires": w.time + _v(a, "duration", lv),
		"slow": _v(a, "slow", lv), "fx": "frost"})

# ---- Timed effects -----------------------------------------------------------------------------------------------------

func update_effects() -> void:
	for i in range(w.effects.size() - 1, -1, -1):
		var e: Dictionary = w.effects[i]
		var done := false
		match e.kind:
			"line":
				done = _update_line(e)
			"volleys":
				done = _update_volleys(e)
		if done:
			w.effects.remove_at(i)

func _update_line(e: Dictionary) -> bool:
	var step: float = e.speed * C.DT
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * minf(step, e.left)
	e.pos = to
	e.left -= step
	for o: SimUnit in w.query(to, e.width + 200.0, true):
		if o.team == e.team or o.is_building() or o.is_ward() or e.hit.has(o.id):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > e.width + o.hull:
			continue
		e.hit[o.id] = true
		w.combat.deal_damage(e.src, e.team, true, o, e.damage, C.DamageType.MAGICAL)
		if o.alive and o.kind != K.TOWER:
			var dest: Vector2 = o.pos + (e.dir as Vector2) * e.push
			o.knock = {"from": o.pos, "to": dest, "t": 0.0, "dur": e.push_t}
			w.events.append({"t": "knockback", "u": o.id})
		if o.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(e.src)
			if src:
				w.ai.neutral_provoked(o, src)
	w.events.append({"t": "effect_move", "ability": e.ability, "pos": to})
	return e.left <= 0.0

func _update_volleys(e: Dictionary) -> bool:
	if w.time < e.next:
		return false
	e.next = w.time + e.interval
	e.left -= 1
	w.events.append({"t": "volley", "pos": e.pos, "radius": e.radius, "src": e.src})
	for o: SimUnit in w.query(e.pos, e.radius + 60.0, true):
		if o.team == e.team or o.is_building() or o.is_ward():
			continue
		if o.pos.distance_to(e.pos) > e.radius + o.hull:
			continue
		w.combat.deal_damage(e.src, e.team, true, o, e.damage, C.DamageType.MAGICAL)
		if o.alive:
			o.add_modifier({"id": "arrow_storm_slow", "source": e.src, "expires": w.time + e.slow_t, "slow": e.slow})
	return e.left <= 0

# ---- Items --------------------------------------------------------------------------------------------------------

func _use_item(u: SimUnit, slot: int, t: SimUnit, p: Vector2) -> void:
	var it: Dictionary = u.inventory[slot]
	var d := SimData.item(it.id)
	var v: Dictionary = d.values
	it["ready"] = w.time + float(d.cooldown)
	var consumed := false
	match String(d.use):
		"tango":
			var ti := w.map.tree_at(p, 140.0)
			if ti >= 0:
				w.map.destroy_tree(ti, 240.0)
				w.vision.static_dirty = true
				w.events.append({"t": "tree", "i": ti, "alive": false})
			u.add_modifier({"id": "tango", "source": u.id, "expires": w.time + float(v.duration), "regen": float(v.health_regen), "fx": "heal"})
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
				w.map.destroy_tree(ti2, 300.0)
				w.vision.static_dirty = true
				w.events.append({"t": "tree", "i": ti2, "alive": false})
		"ward":
			var ward := w.spawn("ward_observer", u.team, p)
			ward.ward_expires = w.time + float(v.lifetime)
			ward.add_modifier({"id": "ward_invis", "source": u.id, "expires": -1.0, "invisible": true})
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
