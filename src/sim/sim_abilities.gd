class_name SimAbilities
extends RefCounted
## Hero abilities and item actives: learning, cast rules (level, cooldown, mana, silence, range), effects, the
## attack modifier (orb) logic and timed effects such as linear projectiles and arrow volleys.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

var w: SimWorld

var hook_hits := {}                        # caster id -> [game time, caught unit id] of its last hook catch (bots learn aim)

var kits2: SimKits2                         # Tock's and Kragg's kits (run 2026-10-15 b)
var kits3: SimKits3                         # Roydo's and Blau's kits (run 2026-10-16)
var kits4: SimKits4                         # Azrael's kit (2026-10-17)
var kits5: SimKits5                         # Airah's, Burak's and Ser Emelrich's kits (run 2026-10-18 f)
var kits6: SimKits6                         # Feran Mock's and Ghorman's kits (run 2026-10-18 f)
var kits7: SimKits7                         # Araki's kit (run 2026-10-19 c)
var kits8: SimKits8                         # Blackfire's kit (run 2026-10-21)
var kits9: SimKits9                         # Thyrandael's kit (run 2026-10-21)

## Units hero `h` commands besides itself and its courier: Ghorman's beasts, Blackfire's Undead.
func commands(h: SimUnit, o: SimUnit) -> bool:
	return kits6.is_beast_of(h, o) or kits8.is_undead_of(h, o)

func _init(world: SimWorld = null) -> void:
	w = world
	kits2 = SimKits2.new(world, self)
	kits3 = SimKits3.new(world, self)
	kits4 = SimKits4.new(world, self)
	kits5 = SimKits5.new(world, self)
	kits6 = SimKits6.new(world, self)
	kits7 = SimKits7.new(world, self)
	kits8 = SimKits8.new(world, self)
	kits9 = SimKits9.new(world, self)

# ---- Learning ---------------------------------------------------------------------------------------------------------

func can_learn(u: SimUnit, aid: String) -> bool:
	if u.ability_points <= 0 or not u.ability_level.has(aid):
		return false
	var a := SimData.ability(aid)
	if String(a.get("behavior", "")) == "innate" or a.has("granted"):
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
	# remembered per unit until its stats change, for this ability level and number of talents
	var ck := aid + "|" + key
	var lvl := u.ability_level_of(aid)
	var got = u._val_cache.get(ck)
	if got != null and int(got[0]) == lvl and int(got[1]) == u.talents.size():
		return float(got[2])
	var v := _val(u, aid, key)
	u._val_cache[ck] = [lvl, u.talents.size(), v]
	return v

func _val(u: SimUnit, aid: String, key: String) -> float:
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
	# cast range bonuses also lengthen line shots that always fly their full distance (as Dota's Meat Hook)
	if key == "distance" and u.cast_range_bonus > 0.0 and bool(a.get("line", false)) and v > 0.0:
		v += u.cast_range_bonus
	# Wide Stone family: spell areas grow (not sight radii)
	if u.aoe_bonus > 0.0 and v > 0.0 and (key == "radius" or key.ends_with("_radius")) and not key.begins_with("vision") 			and not key.begins_with("curse"):
		v += u.aoe_bonus
	return v

func ability_mana(u: SimUnit, aid: String) -> float:
	return val(u, aid, "mana") * SimOrbs.mana_mult(u)

func ability_cooldown(u: SimUnit, aid: String) -> float:
	return maxf(0.0, val(u, aid, "cooldown")) * SimOrbs.cooldown_mult(u) * kits7.cooldown_mult(u, aid)

func cooldown_left(u: SimUnit, aid: String) -> float:
	return maxf(0.0, float(u.ability_ready.get(aid, C.LONG_AGO)) - w.time)

func item_cooldown_left(u: SimUnit, slot: int) -> float:
	var it = u.inventory[slot]
	if it == null:
		return 0.0
	return maxf(0.0, float(it.get("ready", C.LONG_AGO)) - w.time)

## check_target false: everything but the target (a hotkey press, before the player has picked one).
func cast_error(u: SimUnit, aid: String, slot: int, target: SimUnit, point: Vector2, at_cast := false,
		check_target := true) -> String:
	if slot >= 0:
		return _item_error(u, slot, target, point, check_target)
	if aid == "tp":
		if u.tp_charges <= 0 and travel_boots(u).is_empty():
			return "No Teleport Scroll"
		if cooldown_left(u, "tp") > 0.0:
			return "Teleport on cooldown"
		if u.mana < C.TP_MANA:
			return "Not enough mana"
		if u.is_stunned():
			return "Stunned"
		# an item (muted units cannot use it) that roots disable, as in Dota
		if u.is_muted():
			return "Muted"
		if u.has_flag("root"):
			return "Rooted"
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
	if kits4.in_door(u) or kits4.handles(aid):
		var k4 := kits4.cast_error(u, aid, target, point, check_target)
		if k4 != "":
			return k4
		if aid == "door_of_the_end" and kits4.exit_pending(u):
			return ""                              # the exit: no mana, no cooldown
	if aid == "axe_throw" and kits5.axe_recast_ready(u):
		return "Rooted" if u.is_rooted() else ""     # the leap to his axe: no mana, no cooldown
	if cooldown_left(u, aid) > 0.0:
		return "Ability on cooldown"
	if String(a.behavior) != "toggle" and u.mana < ability_mana(u, aid):
		return "Not enough mana"
	if kits3.handles(aid):
		var ke := kits3.cast_error(u, aid, target, point, check_target)
		if ke != "":
			return ke
		if aid == "pilot_turret" and kits3.is_piloting(u):
			return ""
	if kits5.handles(aid):
		var k5 := kits5.cast_error(u, aid, target, point, check_target)
		if k5 != "":
			return k5
	if kits6.handles(aid):
		var k6 := kits6.cast_error(u, aid, target, point, check_target)
		if k6 != "":
			return k6
	if kits7.handles(aid):
		var k7 := kits7.cast_error(u, aid, target, point, check_target)
		if k7 != "":
			return k7
	if kits8.handles(aid):
		var k8 := kits8.cast_error(u, aid, target, point, check_target)
		if k8 != "":
			return k8
	if kits9.handles(aid):
		var k9 := kits9.cast_error(u, aid, target, point, check_target)
		if k9 != "":
			return k9
	if a.behavior == "unit" and check_target:
		var te := _target_error(u, a, target)
		if te != "":
			return te
	if aid == "leap_strike":
		if u.is_rooted():
			return "Rooted"
		if leap_target(u, lv) == null:
			return "No enemy in sight"
	if aid == "spirit_of_fire" and spirits(u) <= 0:
		return "No spirits of fire"
	if a.behavior == "autocast_attack" and check_target:
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

func _item_error(u: SimUnit, slot: int, target: SimUnit, point: Vector2, check_target := true) -> String:
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
	if u.is_muted():
		return "Muted"
	if u.mana < float(d.get("mana", 0.0)) * SimOrbs.mana_mult(u):
		return "Not enough mana"
	if not check_target and item_target(it.id) != "none":
		match String(d.use):
			"gold":
				if int(it.get("charges", 0)) <= 0:
					return "No charges"
			"jump":
				return w.items.error(u, it, d, null, point)
		return ""
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
		_:
			return w.items.error(u, it, d, target, point)
	return ""

## Happens at once without a cast point or interrupting anything: no-target items, toggles (Stench) and immediate
## spells (Blubber).
func is_instant(u: SimUnit, aid: String, slot: int) -> bool:
	if slot >= 0:
		return u.inventory[slot] != null and item_target(u.inventory[slot].id) == "none"
	if aid == "" or aid == "tp":
		return false
	var a := SimData.ability(aid)
	if aid == "pilot_turret" and kits3.is_piloting(u):
		return true                              # Leave Turret: at once, no target
	if aid == "axe_throw" and kits5.axe_recast_ready(u):
		return true                              # the leap to his axe: at once, no target
	return String(a.get("behavior", "")) == "toggle" or bool(a.get("immediate", false))

## "none", "point" (ground / tree) or "unit".
func item_target(item_id: String) -> String:
	var use := String(SimData.item(item_id).get("use", ""))
	match use:
		"tango", "chop", "ward", "plant":
			return "point"
	return SimItems.target_kind(use)

func cast_range(u: SimUnit, aid: String, slot: int, t: SimUnit = null) -> float:
	if slot >= 0:
		var it = u.inventory[slot]
		if it == null:
			return 0.0
		var d := SimData.item(it.id)
		match String(d.use):
			"tango":
				return 165.0
			"chop":
				return 350.0
			"ward":
				return 500.0
			"plant":
				return C.PLANT_RANGE
		var ir: float = w.items.cast_range(u, String(d.use), d, t)
		return ir + u.cast_range_bonus if ir > 0.0 and is_finite(ir) else ir
	if aid == "tp":
		return INF
	var a := SimData.ability(aid)
	if a.behavior == "autocast_attack":
		return u.attack_range
	if a.get("direction", false):
		return INF                               # aimed by direction only: cast from where the hero stands
	if aid == "door_of_the_end" and kits4.exit_pending(u):
		return val(u, aid, "exit_range") + u.cast_range_bonus
	if aid == "false_judgement":
		return kits9.judgement_range(u) + u.cast_range_bonus      # it follows his charges
	var r := val(u, aid, "range")                # talents and upgrades that change the range count
	return r + u.cast_range_bonus if r > 0.0 else r

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
	w.items.break_sneak(u)
	if String(a.behavior) == "toggle":
		set_toggle(u, aid, not bool(u.toggles.get(aid, false)))
		if u.bot:
			var tb = w.bot_for(u.id)
			if tb != null:
				tb.botlog.on_cast(w.time, aid)       # a toggle flipped as ordered (the Bot Log counted 0 of N)
		return
	if aid == "pilot_turret" and kits3.is_piloting(u):
		kits3.leave_turret(u)                    # getting out is free and has no cooldown
		return
	if aid == "door_of_the_end" and kits4.try_exit_cast(u, p):
		return                                   # the door's exit: free
	if aid == "axe_throw" and kits5.try_axe_recast(u):
		return                                   # the leap to his axe: free
	if aid == "swap" and kits6.try_swap_mark(u, t):
		return                                   # Upgrade Staff: marking the ally to swap is free
	u.mana -= ability_mana(u, aid)
	u.ability_ready[aid] = w.time + ability_cooldown(u, aid)
	w.events.append({"t": "cast", "u": u.id, "ability": aid, "point": p, "target": t.id if t else -1})
	if u.bot:
		var bb = w.bot_for(u.id)
		if bb != null:
			bb.botlog.on_cast(w.time, aid)
	kits2.on_cast(u, aid)
	_charge_sticks(u)
	# Touch of Ember: an enemy carrying its flames sets them off by casting a spell
	if not u.get_modifier("touch_of_ember").is_empty():
		_ember_explode_on(u)
	# Spirit of Fire: every other spell Azrin casts adds a spirit
	if aid != "spirit_of_fire" and u.ability_level_of("spirit_of_fire") > 0:
		_add_spirit(u)
	# Divine Touch: every spell Thyrandael casts adds a charge of his barrier
	if u.ability_level.has("divine_touch"):
		kits9.on_spell_cast(u, aid)
	if kits2.handles(aid):
		kits2.cast(u, aid, lv, t, p)
		return
	if kits3.handles(aid):
		kits3.cast(u, aid, lv, t, p)
		return
	if kits4.handles(aid):
		kits4.cast(u, aid, lv, t, p)
		return
	if kits5.handles(aid):
		kits5.cast(u, aid, lv, t, p)
		return
	if kits6.handles(aid):
		kits6.cast(u, aid, lv, t, p)
		return
	if kits7.handles(aid):
		kits7.cast(u, aid, lv, t, p)
		return
	if kits8.handles(aid):
		kits8.cast(u, aid, lv, t, p)
		return
	if kits9.handles(aid):
		kits9.cast(u, aid, lv, t, p)
		return
	match aid:
		"fiery_javelin":
			_javelin(u, aid, lv, p)
		"touch_of_ember":
			_touch_of_ember(u, aid, lv, p)
		"spirit_of_fire":
			_shoot_spirits(u, aid, lv, p)
		"divine_smite":
			_cast_seq += 1
			var dmg := val(u, aid, "damage") + val(u, aid, "int_mult") * u.int_total
			w.effects.append({"kind": "hammer", "ability": aid, "src": u.id, "team": u.team, "target": t.id,
				"pos": u.pos, "speed": val(u, aid, "speed"), "damage": dmg, "radius": val(u, aid, "radius"),
				"extend": val(u, aid, "extend"), "seq": _cast_seq})
			w.events.append({"t": "smite_launch", "u": u.id, "target": t.id, "seq": _cast_seq,
				"speed": val(u, aid, "speed")})
		"breath_of_cold":
			_breath(u, aid, p)
		"ice_pulse":
			_ice_pulse(u, aid, t)
		"endless_winter":
			_start_winter(u, aid, lv)
		"swift_dagger":
			_swift_dagger(u, aid, t)
		"master_of_shadows":
			var md := val(u, aid, "duration")
			u.add_modifier({"id": "master_of_shadows", "source": u.id, "expires": w.time + md, "minimap_hidden": true,
				"stats": {"evasion": val(u, aid, "evasion"), "move_speed_pct": val(u, aid, "move_pct")}, "fx": "shadows"})
			u.refresh_stats()
			w.events.append({"t": "shadows_start", "u": u.id, "dur": md})
		"burst_shot":
			_start_burst(u, a, lv, p)
		"gale_impact":
			var dir := (p - u.pos).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.from_angle(u.facing)
			var reach := val(u, aid, "distance")       # always the full range, wherever the player clicked
			_cast_seq += 1
			w.effects.append({"kind": "line", "ability": aid, "src": u.id, "team": u.team, "pos": u.pos, "dir": dir,
				"speed": val(u, aid, "speed"), "left": reach, "width": val(u, aid, "width"), "damage": val(u, aid, "damage"),
				"push_speed": val(u, aid, "push_speed"), "lv": lv, "seq": _cast_seq, "hit": {}})
			w.events.append({"t": "gale_impact", "u": u.id, "from": u.pos, "dir": dir, "dist": reach,
				"speed": val(u, aid, "speed"), "width": val(u, aid, "width")})
		"blood_ranger_ult":
			var dur := val(u, aid, "duration")
			u.add_modifier({"id": "blood_ranger", "source": u.id, "expires": w.time + dur, "fx": "blood",
				"stats": {"lifesteal_ability": val(u, aid, "lifesteal"), "range": val(u, aid, "bonus_range")},
				"leap_chance": val(u, aid, "leap_chance"), "leap_distance": val(u, aid, "leap_distance"),
				"leap_time": val(u, aid, "leap_time"), "leap_cooldown": val(u, aid, "leap_cooldown")})
			u.refresh_stats()
			w.events.append({"t": "blood_ranger_start", "u": u.id, "dur": dur})
		"dark_stomp":
			_dark_stomp(u, a, lv)
		"snarl", "stomp", "smash":
			_neutral_spell(u, aid, a, p)
		"leap_strike":
			var lt := leap_target(u, lv)
			if lt != null:
				u.leap = {"target": lt.id, "from": u.pos, "to": lt.pos, "t": 0.0, "dur": val(u, aid, "leap_time"), "lv": lv,
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
			u.add_modifier({"id": "tainted_touch", "source": u.id, "expires": w.time + val(u, aid, "duration"), "tainted": lv,
				"fx": "taint"})
			w.events.append({"t": "taint_cast", "u": u.id, "dur": val(u, aid, "duration")})
		"unholy_might":
			var dur := val(u, aid, "duration")
			u.add_modifier({"id": "unholy_might", "source": u.id, "expires": w.time + dur, "chance": val(u, aid, "chance"),
				"radius": val(u, aid, "reflect_radius"), "fx": "unholy"})
			w.effects.append({"kind": "delayed", "what": "unholy_end", "unit": u.id, "at": w.time + dur, "cast_t": w.time,
				"slow": val(u, aid, "fatigue_slow"), "slow_t": val(u, aid, "fatigue_duration")})
			w.events.append({"t": "unholy_start", "u": u.id, "dur": dur})

func _v(a: Dictionary, key: String, lv: int) -> float:
	return _lvl_val(a, key, lv)

## A caster's ability value with its talents and items, for effects that outlive the cast (pushes, curses); the plain
## level value once the caster is gone or has a different level.
func _cv(src_id: int, aid: String, key: String, lv: int) -> float:
	var s := w.get_unit(src_id)
	if s != null and s.ability_level_of(aid) == lv:
		return val(s, aid, key)
	return _lvl_val(SimData.ability(aid), key, lv)

## Whether an effect from `src_team` may put a debuff (stun, push, slow, curse) on `t`: never on a debuff-immune
## enemy (Spell Shield) unless the effect pierces it (Shuriken Hook, Chomp). Ser Emelrich winding up Giant Swing is
## spared even piercing ones, unless `aid` is on SimKits5.SWING_GUARD_PIERCE.
func can_debuff(t: SimUnit, src_team: int, pierces := false, aid := "") -> bool:
	if t.team != src_team and t.debuff_immune and t.has_flag(SimKits5.SWING_GUARD):
		return aid != "" and aid in SimKits5.SWING_GUARD_PIERCE
	return pierces or t.team == src_team or not t.debuff_immune

## Every hero spell cast charges enemy Spark Rods / Wands within range.
func _charge_sticks(caster: SimUnit) -> void:
	if not caster.is_hero():
		return
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
## Travel Boots in the main slots ({} if none): they teleport without a scroll, to creeps as well as buildings.
func travel_boots(u: SimUnit) -> Dictionary:
	for i in mini(6, u.inventory.size()):
		var it = u.inventory[i]
		if it != null and bool(SimData.item(it.id).get("travel", false)):
			return it
	return {}

func _start_tp(u: SimUnit, p: Vector2) -> void:
	var boots := travel_boots(u)
	var best: SimUnit = null
	var bd := INF
	for b in w.units:
		if not b.alive or b.team != u.team:
			continue
		if not b.is_building() and not (not boots.is_empty() and b.is_creep() and b.kind != K.COURIER):
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
	u.mana -= C.TP_MANA
	if not boots.is_empty():
		var cd := float(SimData.item(boots.id).values.tp_cooldown) * SimOrbs.cooldown_mult(u)
		u.ability_ready["tp"] = w.time + cd
		boots["ready"] = u.ability_ready["tp"]
	else:
		u.tp_charges -= 1
		u.ability_ready["tp"] = w.time + C.TP_COOLDOWN * SimOrbs.cooldown_mult(u)
	u.channel = {"ability": "tp", "until": w.time + C.TP_CHANNEL, "dest": dest, "building": best.id}
	w.events.append({"t": "tp_start", "u": u.id, "dest": dest, "until": u.channel.until})
	if u.bot:
		var bb = w.bot_for(u.id)
		if bb != null:
			bb.botlog.on_cast(w.time, "tp")

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
		w.status.apply(t, src.id, src.team, {"id": String(s.mod) + "_slow", "dur": _v(a, "duration", lv),
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
			"javelin":
				done = _update_javelin(e)
			"ember":
				done = _update_ember(e)
			"spirits":
				done = _update_spirits(e)
			"hammer":
				done = _update_hammer(e)
			"cone":
				done = _update_cone(e)
			"ice_pulse":
				done = _update_ice_pulse(e)
			_:
				if kits2.owns_effect(String(e.kind)):
					done = kits2.update_effect(e)
				elif kits3.owns_effect(String(e.kind)):
					done = kits3.update_effect(e)
				elif kits4.owns_effect(String(e.kind)):
					done = kits4.update_effect(e)
				elif kits5.owns_effect(String(e.kind)):
					done = kits5.update_effect(e)
				elif kits6.owns_effect(String(e.kind)):
					done = kits6.update_effect(e)
				elif kits7.owns_effect(String(e.kind)):
					done = kits7.update_effect(e)
		if done:
			if String(e.kind) in SKILLSHOTS:
				_note_miss(e)
			w.effects.remove_at(i)

## Aimed spells that fly a line: when one ends without touching an enemy hero it passed near, that hero dodged it
## (a "skill_miss" event; the bots' chat mocks it, SimBotChat).
const SKILLSHOTS := ["line", "hook", "javelin", "gust", "time_bolt"]

func _note_miss(e: Dictionary) -> void:
	var src := w.get_unit(int(e.get("src", -1)))
	if src == null or not src.is_hero() or not (e.has("hit") or String(e.kind) == "hook"):
		return                                     # only effects that record what they hit can tell a miss
	var hit: Dictionary = e.get("hit", {}) if e.get("hit", {}) is Dictionary else {}
	for id in hit:
		var o := w.get_unit(int(id))
		if o != null and o.is_hero() and o.team != src.team:
			return
	var tgt := w.get_unit(int(e.get("target", -1)))
	if tgt != null and tgt.is_hero() and tgt.team != src.team:
		return                                     # a hook that caught a hero
	var end: Vector2 = e.get("pos", src.pos)
	var start: Vector2 = e.get("origin", e.get("from", src.pos))
	var best: SimUnit = null
	var best_d := 450.0
	for o in w.heroes:
		if not o.alive or o.team == src.team:
			continue
		var d := Geometry2D.get_closest_point_to_segment(o.pos, start, end).distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best != null:
		w.events.append({"t": "skill_miss", "u": src.id, "near": best.id, "ability": String(e.get("ability", ""))})

## Fells every tree within `r` (+40, the trunk) of the segment `from`-`to`; each falls away along the line (Gale
## Impact's arrow, Fiery Javelin).
func fell_trees_on(from: Vector2, to: Vector2, r: float) -> void:
	var dir := (to - from).normalized()
	var c0 := w.map.world_to_cell(Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(r, r))
	var c1 := w.map.world_to_cell(Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2(r, r))
	for cy in range(maxi(c0.y, 0), mini(c1.y, SimMap.N - 1) + 1):
		for cx in range(maxi(c0.x, 0), mini(c1.x, SimMap.N - 1) + 1):
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti < 0 or not w.map.trees[ti].alive:
				continue
			var tp: Vector2 = w.map.trees[ti].pos
			if Geometry2D.get_closest_point_to_segment(tp, from, to).distance_to(tp) <= r + 40.0:
				w.cut_tree(ti, tp - dir * 100.0, true)

## Gale Impact's arrow, one tick: it fells the trees it passes and strikes each enemy once, hurling it sideways off
## the arrow's line (away from the side it stood on) with a little of the arrow's momentum.
func _update_line(e: Dictionary) -> bool:
	var step: float = e.speed * C.DT
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * minf(step, e.left)
	e.pos = to
	e.left -= step
	var dir: Vector2 = e.dir
	fell_trees_on(from, to, e.width)
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
		if o.alive and o.kind != K.TOWER and can_debuff(o, int(e.team)):
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
	var r := val(u, "dark_stomp", "radius")
	_cast_seq += 1
	w.events.append({"t": "stomp", "u": u.id, "pos": u.pos, "radius": r})
	for o: SimUnit in w.query(u.pos, r, true):
		if not _ezee_can_hit(u, o) or u.edge_distance(o) > r:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, val(u, "dark_stomp", "damage"), C.DamageType.MAGICAL, false, "dark_stomp")
		if not o.alive:
			continue
		var dir := o.pos - u.pos
		if dir.length() < 1.0:
			dir = Vector2.from_angle(u.facing)
		var near := clampf(1.0 - u.pos.distance_to(o.pos) / r, 0.0, 1.0)
		var speed := val(u, "dark_stomp", "push_speed") * lerpf(0.72, 1.0, near) / mass(o)
		if can_debuff(o, u.team):
			start_push(o, dir.normalized() * speed, u.id, u.team, "dark_stomp", lv, _cast_seq)

## The neutral creeps' spells. Snarl: enemies nearby deal 60% less attack damage for 4 s. Stomp: magic damage and a
## stun around the caster (1.6 s heroes, 3 s others). Smash: the same at the target point after its long wind-up.
func _neutral_spell(u: SimUnit, aid: String, a: Dictionary, p: Vector2) -> void:
	var r := _v(a, "radius", 1)
	var center := u.pos if aid != "smash" else p
	w.events.append({"t": "neutral_spell", "u": u.id, "ability": aid, "pos": center, "radius": r})
	for o: SimUnit in w.query(center, r + 40.0, true):
		if not o.alive or o.team == u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		if o.pos.distance_to(center) > r + o.hull:
			continue
		match aid:
			"snarl":
				w.status.apply(o, u.id, u.team, {"id": "snarl", "dur": _v(a, "duration", 1),
					"stats": {"attack_out_pct": -_v(a, "damage_reduction", 1)}, "fx": "weakened"})
			"stomp", "smash":
				w.combat.deal_damage(u.id, u.team, false, o, _v(a, "damage", 1), C.DamageType.MAGICAL, false, aid)
				if o.alive:
					var dur := _v(a, "hero_stun", 1) if o.is_hero() else _v(a, "stun", 1)
					w.status.apply(o, u.id, u.team, {"id": "stunned", "stun": true, "dur": dur, "fx": "stun"})

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
		if k.get("air", false):
			# thrown through the air (Grip of the Ruler): over trees and cliffs on an arc, landing on open ground
			u.pos = np
			k["z"] = sin(f * PI) * float(k.get("height", 200.0))
			if f >= 1.0 and not w.map.is_walkable(u.pos):
				var lc := w.map.nearest_walkable(w.map.world_to_cell(u.pos))
				u.pos = w.map.cell_center(lc.x, lc.y)
		elif w.map.is_walkable(np):
			u.pos = np
		if f >= 1.0:
			u.knock = {}
			u.path = PackedVector2Array()
			if k.get("air", false):
				w.events.append({"t": "push_land", "u": u.id, "speed": 600.0})
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
			var ks := w.get_unit(int(k.src))
			if w.status.apply(u, int(k.src), ks.team if ks else C.NEUTRAL, {"id": "stunned", "stun": true,
					"dur": float(k.stun), "fx": "stun"}):
				w.events.append({"t": "stunned", "u": u.id, "dur": float(u.get_modifier("stunned").get("dur", k.stun))})

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
	if aid == SimKits8.BLAST:
		# Unfallen's last blast: whoever slams into something is stunned, allies too; no damage
		k.stun = kits8.blast_stun(int(k.src))
		return
	var crash: Array = SimKits5.CRASHES.get(aid, SimKits6.CRASHES.get(aid, []))
	if u.team == int(k.team) or not (aid in ["dark_stomp", "gale_impact", "repel"] or not crash.is_empty()):
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
	if not crash.is_empty():
		# the new heroes' crashes (Sweep, Hurricane, the Joke Box's Spring): their own damage and stun keys
		if String(crash[0]) != "":
			w.combat.deal_damage(int(k.src), int(k.team), true, u, _cv(int(k.src), aid, String(crash[0]), lv),
				C.DamageType.PHYSICAL if String(a.get("damage_type", "")) == "physical" else C.DamageType.MAGICAL, false, aid)
		k.stun = _cv(int(k.src), aid, String(crash[1]), lv)
		return
	if aid == "gale_impact":
		# Gale Impact: the crash deals another 20% of the arrow's damage, no stun
		w.combat.deal_damage(int(k.src), int(k.team), true, u, _cv(int(k.src), aid, "damage", lv) * _cv(int(k.src), aid, "impact_pct", lv),
			C.DamageType.MAGICAL, false, "gale_impact")
		return
	w.combat.deal_damage(int(k.src), int(k.team), true, u, _cv(int(k.src), aid, "impact_damage", lv), C.DamageType.MAGICAL, false, aid)
	k.stun = _cv(int(k.src), aid, "impact_stun", lv)

## Leap Strike's target: the visible enemy in range with the lowest health fraction, the nearest if none is hurt.
func leap_target(u: SimUnit, lv: int) -> SimUnit:
	var rng := cast_range(u, "leap_strike", -1)
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
			var dmg := val(u, "leap_strike", "damage") + val(u, "leap_strike", "str_mult") * u.str_total
			w.combat.deal_damage(u.id, u.team, true, t, dmg, C.DamageType.PURE, false, "leap_strike")
			if t.alive and can_debuff(t, u.team):
				w.status.apply(t, u.id, u.team, {"id": "leap_strike_slow", "dur": val(u, "leap_strike", "slow_duration"),
					"slow": val(u, "leap_strike", "slow"), "fx": "slow"})
				if u.order == O.NONE:
					w.orders.issue(u, {"type": O.ATTACK_UNIT, "target": t.id}, false)
		return
	u.pos = np

## Tainted Touch on an attack that landed: bonus magic damage and the curse (revealed, sight around it).
func tainted_hit(s: Dictionary, t: SimUnit) -> void:
	var a := SimData.ability("tainted_touch")
	var lv := int(s.taint)
	w.combat.deal_damage(s.src, s.team, bool(s.hero), t, _cv(int(s.src), "tainted_touch", "bonus_damage", lv), C.DamageType.MAGICAL, false, "tainted_touch")
	if t.alive and can_debuff(t, int(s.team)):
		w.status.apply(t, int(s.src), int(s.team), {"id": "tainted_curse", "dur": _cv(int(s.src), "tainted_touch", "curse_duration", lv),
			"reveal": int(s.team), "reveal_r": _cv(int(s.src), "tainted_touch", "curse_vision", lv), "fx": "curse"})
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
	var waves := int(val(u, "burst_shot", "waves"))
	var total := int(val(u, "burst_shot", "arrows"))
	var split := burst_split(total, waves, int(val(u, "burst_shot", "wave_min")), int(val(u, "burst_shot", "wave_max")))
	var interval := val(u, "burst_shot", "wave_interval")
	u.channel = {"ability": "burst_shot", "until": w.time + interval * waves, "start": w.time, "dur": interval * waves,
		"point": p, "radius": val(u, "burst_shot", "radius"),
		"waves": split, "next_wave": 0, "next_at": w.time, "interval": interval, "pct": val(u, "burst_shot", "attack_pct"),
		"speed": val(u, "burst_shot", "arrow_speed")}
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
	if lv <= 0 or t.is_building() or t.team == u.team or u.is_broken():
		return 0.0
	if w.time < float(u.ability_ready.get("masterful_archery", C.LONG_AGO)):
		return 0.0
	# pseudo-random like every chance-on-attack passive in Dota; no roll while it cools down
	var a := SimData.ability("masterful_archery")
	if not w.status.roll(u, "masterful_archery", val(u, "masterful_archery", "chance")):
		return 0.0
	u.ability_ready["masterful_archery"] = w.time + val(u, "masterful_archery", "proc_cooldown")
	return u.agi_total * val(u, "masterful_archery", "agility_pct")

## Blood Ranger: an attack that hit her may make her leap back, away from the attacker (1 s apart at most).
func on_attacked(t: SimUnit, attacker: SimUnit) -> void:
	if not t.alive or attacker == null:
		return
	var m := t.get_modifier("blood_ranger")
	if m.is_empty() or not t.hop.is_empty() or t.is_stunned() or t.is_leaping():
		return
	if w.time < float(t.get_meta("hop_ready", C.LONG_AGO)):
		return
	if not w.status.roll(t, "blood_ranger_leap", float(m.leap_chance)):
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
	H.z = sin(f * PI) * float(H.get("height", 70.0))
	if f >= 1.0:
		u.hop = {}
		w.events.append({"t": "back_leap_land", "u": u.id, "pos": u.pos})

# ---- Channels ---------------------------------------------------------------------------------------------------

## One tick of an ability channel (Burst Shot's waves, Chomp's bites).
func channel_tick(u: SimUnit) -> void:
	match String(u.channel.ability):
		"site_gate", "site_lamp":
			pass
		"burst_shot":
			update_burst(u)
		"chomp":
			_update_chomp(u)
		"endless_winter":
			_update_winter(u)
		"overhead_cut", "giant_swing":
			pass                                 # a wind-up: the blow lands when it ends (SimKits5.windup_done)
		"holy_beam":
			kits9.beam_tick(u)

## A channel ended (finished, or cancelled by an order, stun, silence, push or death): undo what it holds.
func channel_cleanup(u: SimUnit, ch: Dictionary, _cancelled: bool) -> void:
	match String(ch.ability):
		"site_gate", "site_lamp":
			w.sites.channel_end(u, ch, _cancelled)
		"chomp":
			var t := w.get_unit(int(ch.get("target", -1)))
			if t != null:
				_remove_mod(t, "chomp", u.id)
		"overhead_cut", "giant_swing":
			kits5.windup_done(u, ch, _cancelled)
		"holy_beam":
			kits9.beam_end(u, _cancelled)

func _remove_mod(t: SimUnit, mid: String, source: int) -> void:
	for i in range(t.modifiers.size() - 1, -1, -1):
		if t.modifiers[i].id == mid and int(t.modifiers[i].get("source", -1)) == source:
			t.modifiers.remove_at(i)
			t.stats_dirty = true

# ---- Sludge, the Butcher (Dota 2's Pudge) -----------------------------------------------------------------------

# ---- Azrin, the Flamemander ---------------------------------------------------------------------------------------

## Enemies Azrin's spells touch: living heroes and creeps (not buildings, wards or couriers), not invulnerable.
func _azrin_can_hit(team: int, o: SimUnit) -> bool:
	return o.alive and o.team != team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
		and not o.is_invulnerable()

func spirits(u: SimUnit) -> int:
	return int(u.stacks.get("spirits", 0))

func _add_spirit(u: SimUnit) -> void:
	var mx := int(val(u, "spirit_of_fire", "max_spirits"))
	var n := spirits(u)
	if n < mx:
		u.stacks["spirits"] = n + 1
		w.events.append({"t": "spirit_gain", "u": u.id, "n": n + 1})

## Fiery Javelin: flies from Azrin toward the point (300 to 1000 away). Every enemy within its width is caught once:
## it starts burning, and unless it is debuff-immune it is dragged along with the javelin to where it lands.
func _javelin(u: SimUnit, aid: String, _lv: int, p: Vector2) -> void:
	var dir := p - u.pos
	var dist := clampf(dir.length(), val(u, aid, "min_distance"), val(u, aid, "distance"))
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	u.facing = dir.angle()
	_cast_seq += 1
	var from := u.pos + dir * u.hull
	w.effects.append({"kind": "javelin", "ability": aid, "src": u.id, "team": u.team, "pos": from, "dir": dir,
		"left": dist, "speed": val(u, aid, "speed"), "width": val(u, aid, "width"), "dps": val(u, aid, "burn_dps"),
		"dur": val(u, aid, "burn_duration"), "seq": _cast_seq, "hit": {}, "caught": {}})
	w.events.append({"t": "javelin_launch", "u": u.id, "from": from, "dir": dir, "dist": dist,
		"speed": val(u, aid, "speed"), "seq": _cast_seq})

func _update_javelin(e: Dictionary) -> bool:
	var src := w.get_unit(int(e.src))
	var dir: Vector2 = e.dir
	var step := minf(float(e.speed) * C.DT, float(e.left))
	var from: Vector2 = e.pos
	var to := from + dir * step
	e.pos = to
	e.left = float(e.left) - step
	fell_trees_on(from, to, float(e.width))         # the javelin knocks down the trees it passes
	for o: SimUnit in w.query(to, float(e.width) + step + 80.0, true):
		if e.hit.has(o.id) or not _azrin_can_hit(int(e.team), o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > float(e.width) + o.hull:
			continue
		e.hit[o.id] = true
		if src != null:
			w.status.add_dot(o, src, String(e.ability), float(e.dps), float(e.dur), C.Element.FIRE)
		if o.kind == K.NEUTRAL_CREEP and src != null:
			w.ai.neutral_provoked(o, src)
		if can_debuff(o, int(e.team)) and o.alive:
			w.orders.cancel_channel(o)
			o.leap = {}
			o.hop = {}
			o.path = PackedVector2Array()
			o.knock = {"drag": true, "seq": int(e.seq), "disable": true, "src": int(e.src)}
			# it rides beside the tip, keeping a little of its sideways offset
			var side := clampf((o.pos - cp).dot(dir.orthogonal()), -60.0, 60.0)
			e.caught[o.id] = side
			w.events.append({"t": "javelin_catch", "u": o.id, "src": e.src, "seq": e.seq})
	var done := float(e.left) <= 0.001
	for id in e.caught.keys():
		var o := w.get_unit(int(id))
		if o == null or not o.alive or int(o.knock.get("seq", -1)) != int(e.seq):
			e.caught.erase(id)
			continue
		var np: Vector2 = to + dir.orthogonal() * float(e.caught[id]) - dir * o.hull
		o.pos = np
		if done:
			_hook_release(o, np)
	w.events.append({"t": "javelin_move", "src": e.src, "seq": e.seq, "pos": to, "done": done})
	return done

## Touch of Ember: 100 magic damage over the area, then each enemy hit carries spirit flames for 4 s; they explode when
## it casts a spell or when the time runs out (more magic damage and a stun).
func _touch_of_ember(u: SimUnit, aid: String, _lv: int, p: Vector2) -> void:
	var r := val(u, aid, "radius")
	w.events.append({"t": "ember_cast", "u": u.id, "pos": p, "radius": r})
	for o: SimUnit in w.query(p, r + 80.0, true):
		if not _azrin_can_hit(u.team, o) or o.pos.distance_to(p) > r + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, val(u, aid, "damage"), C.DamageType.MAGICAL, false, aid)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
		if not o.alive:
			continue
		var delay := val(u, aid, "delay")
		if w.status.apply(o, u.id, u.team, {"id": "touch_of_ember", "dur": delay, "dispel": "", "fx": "ember_mark",
				"no_resist": true}):
			w.effects.append({"kind": "ember", "ability": aid, "src": u.id, "team": u.team, "target": o.id,
				"at": w.time + delay, "damage": val(u, aid, "explode_damage"), "stun": val(u, aid, "stun")})

func _update_ember(e: Dictionary) -> bool:
	var t := w.get_unit(int(e.target))
	if t == null or not t.alive:
		return true
	if bool(e.get("now", false)) or w.time >= float(e.at):
		_ember_explode(e, t)
		return true
	return false

## The target cast a spell: its flames go off at once (this tick).
func _ember_explode_on(t: SimUnit) -> void:
	for e in w.effects:
		if String(e.kind) == "ember" and int(e.target) == t.id:
			e["now"] = true
			_ember_explode(e, t)
			e["at"] = -INF
			e["spent"] = true

func _ember_explode(e: Dictionary, t: SimUnit) -> void:
	if bool(e.get("spent", false)):
		return
	e["spent"] = true
	t.remove_modifier("touch_of_ember")
	w.events.append({"t": "ember_explode", "u": t.id, "src": e.src})
	var src := w.get_unit(int(e.src))
	if src == null:
		return
	w.combat.deal_damage(src.id, int(e.team), true, t, float(e.damage), C.DamageType.MAGICAL, false, String(e.ability))
	if t.alive:
		w.status.apply(t, src.id, int(e.team), {"id": "stunned", "stun": true, "dur": float(e.stun), "fx": "stun"})

## Spirit of Fire: every spirit flies to the area; each burns the enemies there (its damage spread over the duration)
## and slows them while they burn.
func _shoot_spirits(u: SimUnit, aid: String, _lv: int, p: Vector2) -> void:
	var n := spirits(u)
	u.stacks["spirits"] = 0
	var speed := val(u, aid, "speed")
	w.effects.append({"kind": "spirits", "ability": aid, "src": u.id, "team": u.team, "n": n, "point": p,
		"at": w.time + u.pos.distance_to(p) / speed, "radius": val(u, aid, "radius"), "burn": val(u, aid, "burn"),
		"dur": val(u, aid, "duration"), "slow": val(u, aid, "slow")})
	w.events.append({"t": "spirits_launch", "u": u.id, "n": n, "point": p, "speed": speed})

func _update_spirits(e: Dictionary) -> bool:
	if w.time < float(e.at):
		return false
	var src := w.get_unit(int(e.src))
	var p: Vector2 = e.point
	var r := float(e.radius)
	w.events.append({"t": "spirits_hit", "u": e.src, "pos": p, "radius": r, "n": e.n})
	if src == null:
		return true
	var dps := float(e.burn) * int(e.n) / float(e.dur)
	for o: SimUnit in w.query(p, r + 80.0, true):
		if not _azrin_can_hit(int(e.team), o) or o.pos.distance_to(p) > r + o.hull:
			continue
		w.status.add_dot(o, src, String(e.ability), dps, float(e.dur), C.Element.FIRE)
		w.status.apply(o, src.id, int(e.team), {"id": "spirit_of_fire_slow", "dur": float(e.dur), "slow": float(e.slow),
			"fx": "slow"})
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, src)
	return true

## Divine Smite: the hammer homes on its target. On arrival: every Fire burn on enemies within the radius lasts longer,
## then its burst of magic damage.
func _update_hammer(e: Dictionary) -> bool:
	var t := w.get_unit(int(e.target))
	if t == null or not t.alive:
		w.events.append({"t": "smite_hit", "u": e.src, "target": -1, "pos": e.pos, "radius": e.radius, "seq": e.seq})
		return true
	var to: Vector2 = t.pos - (e.pos as Vector2)
	var step := float(e.speed) * C.DT
	if to.length() > step + t.hull * 0.5:
		e.pos = (e.pos as Vector2) + to.normalized() * step
		w.events.append({"t": "smite_move", "src": e.src, "seq": e.seq, "pos": e.pos})
		return false
	var src := w.get_unit(int(e.src))
	var n := 0
	for o: SimUnit in w.query(t.pos, float(e.radius) + 80.0, true):
		if o.alive and o.team != int(e.team) and o.pos.distance_to(t.pos) <= float(e.radius) + o.hull:
			n += w.status.extend_dots(o, int(e.team), C.Element.FIRE, float(e.extend))
	w.events.append({"t": "smite_hit", "u": e.src, "target": t.id, "pos": t.pos, "radius": e.radius, "seq": e.seq,
		"extended": n})
	if src != null and not t.is_invulnerable():
		w.combat.deal_damage(src.id, int(e.team), true, t, float(e.damage), C.DamageType.MAGICAL, false,
			String(e.ability))
	return true

## Growing Gut: an enemy hero died. Every Sludge on the other team within 450 (alive) or credited with the kill grows.
func on_hero_death(t: SimUnit, killer: SimUnit, credit: SimUnit) -> void:
	t.stacks.erase("spirits")                         # the spirits of fire die with Azrin
	kits5.on_hero_death(t, killer, credit)
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
	hook_hits[int(e.src)] = [w.time, o.id]
	var caster := w.get_unit(int(e.src))
	if caster != null:
		caster.remove_modifier("hook_lock")
	w.vision.add_source(int(e.team), e.pos, float(e.vision_r), float(e.vision_t))
	var ally := o.team == int(e.team)
	e["hit"] = {o.id: true}                        # what it caught (a dodge check at its end, _note_miss)
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
	if aid == "steel_stance":
		kits5.on_stance(u, on)
	elif on:
		if aid == "soul_tap":
			kits4.on_soul_tap_toggle(u)
		else:
			var exists := false
			for e in w.effects:
				if e.kind == "pulse" and int(e.src) == u.id and String(e.ability) == aid:
					exists = true
			if not exists:
				w.effects.append({"kind": "pulse", "ability": aid, "src": u.id, "next_tick": w.tick})
	w.events.append({"t": "toggle", "u": u.id, "ability": aid, "on": on})

## Stench, every 0.2 s while on: magic damage and a lingering slow to enemies around Sludge (a debuff-immune enemy
## takes the damage but not the slow), and the same damage to Sludge himself, which never kills him. Keeps working while he is stunned or channelling.
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
		if o.is_invulnerable() or o.pos.distance_to(u.pos) > r + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.MAGICAL, false, aid)
		if o.alive and can_debuff(o, u.team):
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

# ---- Froster, the Winter Master -----------------------------------------------------------------------------------

## Breath of Cold: a widening cone of cold rolls out from Froster to its full 800 (wherever the player clicked); each
## enemy it reaches is struck once for magic damage and slowed.
func _breath(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := p - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	u.facing = dir.angle()
	_cast_seq += 1
	var reach := val(u, aid, "distance")
	w.effects.append({"kind": "cone", "ability": aid, "src": u.id, "team": u.team, "origin": u.pos, "dir": dir,
		"done": 0.0, "reach": reach, "speed": val(u, aid, "speed"), "w0": val(u, aid, "start_width"),
		"w1": val(u, aid, "end_width"), "damage": val(u, aid, "damage"), "slow": val(u, aid, "slow"),
		"slow_t": val(u, aid, "slow_duration"), "seq": _cast_seq, "hit": {}})
	w.events.append({"t": "breath_cast", "u": u.id, "from": u.pos, "dir": dir, "dist": reach, "speed": val(u, aid, "speed"),
		"w0": val(u, aid, "start_width"), "w1": val(u, aid, "end_width"), "seq": _cast_seq})

func _update_cone(e: Dictionary) -> bool:
	var from := float(e.done)
	var to := minf(float(e.reach), from + float(e.speed) * C.DT)
	e.done = to
	var origin: Vector2 = e.origin
	var dir: Vector2 = e.dir
	var mid := origin + dir * ((from + to) * 0.5)
	var src := w.get_unit(int(e.src))
	for o: SimUnit in w.query(mid, (to - from) * 0.5 + float(e.w1) * 0.5 + 100.0, true):
		if e.hit.has(o.id) or not _azrin_can_hit(int(e.team), o):
			continue
		var rel := o.pos - origin
		var along := rel.dot(dir)
		if along < -o.hull or along > to + o.hull:
			continue
		var half := lerpf(float(e.w0), float(e.w1), clampf(along / float(e.reach), 0.0, 1.0)) * 0.5
		if absf(rel.dot(dir.orthogonal())) > half + o.hull:
			continue
		e.hit[o.id] = true
		if src != null:
			w.combat.deal_damage(src.id, int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, String(e.ability))
			if o.kind == K.NEUTRAL_CREEP:
				w.ai.neutral_provoked(o, src)
		if o.alive and can_debuff(o, int(e.team)):
			w.status.apply(o, int(e.src), int(e.team), {"id": "breath_of_cold_slow", "dur": float(e.slow_t),
				"slow": float(e.slow), "fx": "chill"})
		w.events.append({"t": "breath_hit", "u": o.id, "src": e.src})
	w.events.append({"t": "breath_move", "src": e.src, "seq": e.seq, "dist": to, "done": to >= float(e.reach) - 0.01})
	return to >= float(e.reach) - 0.01

## Ice Pulse: the target's defense drops for 3.5 s (SimUnit.defense_loss raises the physical and magic damage it takes
## after armor and resistances); then the curse bursts: magic damage to it and every enemy within 300.
func _ice_pulse(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var dur := val(u, aid, "duration")
	if not w.status.apply(t, u.id, u.team, {"id": "ice_pulse", "dur": dur, "defense_loss": val(u, aid, "defense_loss"),
			"dispel": "basic", "fx": "ice_curse"}):
		return                                       # refused (Spell Shield): no curse, no blast
	w.effects.append({"kind": "ice_pulse", "ability": aid, "src": u.id, "team": u.team, "target": t.id, "pos": t.pos,
		"at": w.time + dur, "damage": val(u, aid, "blast_damage"), "radius": val(u, aid, "blast_radius")})
	w.events.append({"t": "ice_pulse_cast", "u": u.id, "target": t.id, "dur": dur})

func _update_ice_pulse(e: Dictionary) -> bool:
	var t := w.get_unit(int(e.target))
	if t != null and t.alive:
		e.pos = t.pos
	if w.time < float(e.at):
		return false
	var p: Vector2 = e.pos
	var r := float(e.radius)
	var src := w.get_unit(int(e.src))
	w.events.append({"t": "ice_pulse_blast", "u": e.src, "target": e.target, "pos": p, "radius": r})
	if src == null:
		return true
	for o: SimUnit in w.query(p, r + 80.0, true):
		if not _azrin_can_hit(int(e.team), o) or o.pos.distance_to(p) > r + o.hull:
			continue
		w.combat.deal_damage(src.id, int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, String(e.ability))
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, src)
	return true

## Frost Heart: damage Froster deals to enemies (not buildings) builds hearts; called by SimCombat.deal_damage.
func frost_heart_charge(src: SimUnit, t: SimUnit, amount: float) -> void:
	if amount <= 0.0 or t.is_building() or t.is_ward() or t.team == src.team or src.is_broken():
		return
	var per := val(src, "frost_heart", "per_heart")
	var mx := int(val(src, "frost_heart", "max_hearts"))
	var hearts := int(src.stacks.get("frost_hearts", 0))
	if hearts >= mx:
		return
	var acc := float(src.stacks.get("frost_dmg", 0.0)) + amount
	while acc >= per and hearts < mx:
		acc -= per
		hearts += 1
		w.events.append({"t": "frost_heart_gain", "u": src.id, "n": hearts})
	src.stacks["frost_dmg"] = acc if hearts < mx else 0.0
	src.stacks["frost_hearts"] = hearts

func frost_hearts(u: SimUnit) -> int:
	return int(u.stacks.get("frost_hearts", 0))

## An attack about to be released spends a heart on an enemy unit (true: the attack carries the burst).
func frost_heart_spend(u: SimUnit, t: SimUnit) -> bool:
	if u.ability_level_of("frost_heart") <= 0 or u.is_broken() or t.is_building() or t.is_ward() or t.team == u.team:
		return false
	var n := frost_hearts(u)
	if n <= 0:
		return false
	u.stacks["frost_hearts"] = n - 1
	return true

## The attack with a heart landed: the burst of magic damage and the slow.
func frost_heart_hit(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(int(s.src))
	if src == null:
		return
	w.events.append({"t": "frost_heart_hit", "u": src.id, "target": t.id})
	w.combat.deal_damage(src.id, src.team, true, t, val(src, "frost_heart", "burst"), C.DamageType.MAGICAL, false,
		"frost_heart")
	if t.alive and can_debuff(t, src.team):
		w.status.apply(t, src.id, src.team, {"id": "frost_heart_slow", "dur": val(src, "frost_heart", "slow_duration"),
			"slow": val(src, "frost_heart", "slow"), "fx": "chill"})

## Endless Winter: a 7 s channel; mana and cooldown are spent when it begins. Every second (from the start) enemies
## within 600 take magic damage; one that has stood inside for 2 s without a break is Frosted (a 2 s stun), and may be
## Frosted again only 1.5 s after that ends.
func _start_winter(u: SimUnit, aid: String, lv: int) -> void:
	var dur := val(u, aid, "duration")
	u.channel = {"ability": aid, "until": w.time + dur, "start": w.time, "dur": dur, "lv": lv, "next_pulse": w.time,
		"inside": {}, "ready": {}, "radius": val(u, aid, "radius")}
	w.events.append({"t": "channel_start", "u": u.id, "ability": aid, "until": u.channel.until, "radius": u.channel.radius})

func _update_winter(u: SimUnit) -> void:
	var ch := u.channel
	var aid := String(ch.ability)
	var r := float(ch.radius)
	var pulse := w.time + 1e-6 >= float(ch.next_pulse) and float(ch.next_pulse) < float(ch.until) - 1e-4
	if pulse:
		ch.next_pulse = float(ch.next_pulse) + val(u, aid, "pulse")
		w.events.append({"t": "winter_pulse", "u": u.id, "pos": u.pos, "radius": r})
	var inside: Dictionary = ch.inside
	var ready: Dictionary = ch.ready
	var seen := {}
	for o: SimUnit in w.query(u.pos, r + 80.0, true):
		if not _azrin_can_hit(u.team, o) or o.pos.distance_to(u.pos) > r + o.hull:
			continue
		seen[o.id] = true
		if pulse:
			w.combat.deal_damage(u.id, u.team, true, o, val(u, aid, "dps") * val(u, aid, "pulse"), C.DamageType.MAGICAL,
				false, aid)
			if o.kind == K.NEUTRAL_CREEP:
				w.ai.neutral_provoked(o, u)
			if not o.alive:
				continue
		# the count runs while it stays inside (frozen or not); a Frost needs 2 s inside and the 1.5 s pause after the last
		inside[o.id] = float(inside.get(o.id, 0.0)) + C.DT
		if float(inside[o.id]) >= val(u, aid, "frost_after") - 1e-6 and w.time >= float(ready.get(o.id, -INF)):
			inside[o.id] = 0.0
			var st := val(u, aid, "frost_stun")
			ready[o.id] = w.time + st + val(u, aid, "frost_cooldown")
			if w.status.apply(o, u.id, u.team, {"id": "frosted", "stun": true, "dur": st, "fx": "frozen"}):
				w.events.append({"t": "frosted", "u": o.id, "src": u.id, "dur": st})
	# leaving the blizzard starts the count again
	for id in inside.keys():
		if not seen.has(id):
			inside.erase(id)

# ---- Caziel, the Void Assassin --------------------------------------------------------------------------------------

## Swift Dagger: Caziel flashes beside the target (on his side of it), its armor drops, and he stabs at once: an attack
## with the bonus damage that can crit and poison like any other. Then he fights on against it.
func _swift_dagger(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var from := u.pos
	var dir := t.pos - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var dest := t.pos - dir * (t.hull + u.hull + 4.0)
	if not w.map.is_walkable(dest):
		var c := w.map.nearest_walkable(w.map.world_to_cell(dest))
		dest = w.map.cell_center(c.x, c.y)
	u.pos = dest
	u.facing = (t.pos - dest).angle() if t.pos.distance_to(dest) > 1.0 else dir.angle()
	u.path = PackedVector2Array()
	w.events.append({"t": "swift_dagger", "u": u.id, "from": from, "to": dest, "target": t.id})
	if can_debuff(t, u.team):
		w.status.apply(t, u.id, u.team, {"id": "swift_dagger_armor", "dur": val(u, aid, "armor_duration"),
			"stats": {"armor": -val(u, aid, "armor_cut")}, "fx": "armor_cut"})
		t.refresh_stats()
	var snap := w.combat.attack_snapshot(u, "")
	snap.bonus = float(snap.bonus) + val(u, aid, "bonus_damage")
	snap.crit = w.combat.roll_crit(u, t)
	snap["stab"] = true
	w.combat.land_attack(snap, t)
	if t.alive:
		u.atk_target = t.id

## Sweet Poison: an attack that landed on an enemy unit may poison it (pseudo-random); a new poison from Caziel renews
## the one already running instead of adding to it.
func sweet_poison_hit(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(int(s.src))
	if src == null or src.ability_level_of("sweet_poison") <= 0 or src.is_broken() or t.is_building() or t.is_ward():
		return
	if t.team == src.team or not t.alive:
		return
	if not w.status.roll(src, "sweet_poison", val(src, "sweet_poison", "chance")):
		return
	if w.status.add_dot(t, src, "sweet_poison", val(src, "sweet_poison", "dps"), val(src, "sweet_poison", "duration"),
			C.Element.NATURE, true):
		w.events.append({"t": "poison_blow", "u": src.id, "target": t.id})

## Death Order: Caziel's attack on an enemy (not a building) below the threshold of its health deals pure damage.
func death_order(s: Dictionary, t: SimUnit) -> bool:
	if not bool(s.get("hero", false)):
		return false
	var src := w.get_unit(int(s.src))
	if src == null or src.ability_level_of("death_order") <= 0 or src.is_broken():
		return false
	if t.is_building() or t.is_ward() or t.team == src.team:
		return false
	return t.hp < t.max_hp * val(src, "death_order", "threshold")

# ---- Items --------------------------------------------------------------------------------------------------------

func _use_item(u: SimUnit, slot: int, t: SimUnit, p: Vector2) -> void:
	var it: Dictionary = u.inventory[slot]
	var d := SimData.item(it.id)
	var v: Dictionary = d.values
	it["ready"] = w.time + float(d.cooldown) * SimOrbs.cooldown_mult(u)
	u.mana -= float(d.get("mana", 0.0)) * SimOrbs.mana_mult(u)
	if String(d.use) != "sneak":
		w.items.break_sneak(u)
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
			var ward := w.spawn(String(v.get("unit", "ward_observer")), u.team, p)
			ward.ward_expires = w.time + float(v.lifetime)
			u.wards_placed += 1
			ward.add_modifier({"id": "ward_invis", "source": u.id, "expires": INF, "invisible": true})
			if ward.def.get("true_sight", 0.0) > 0.0:
				# a Reveal Ward gives 150 ground sight around itself for its first 12 s
				w.vision.add_source(u.team, p, 150.0, 12.0)
			consumed = true
		"dust":
			w.status.dust(u, v)
			consumed = true
		"berserk":
			u.mana -= float(v.mana)
			var bms := float(v.get("move_speed_pct_melee", v.move_speed_pct)) if not u.is_ranged() else float(v.move_speed_pct)
			u.add_modifier({"id": "berserk", "source": u.id, "expires": w.time + float(v.duration),
				"stats": {"attack_speed": float(v.attack_speed), "move_speed_pct": bms, "armor": -float(v.armor_reduction)}, "fx": "berserk"})
		_:
			consumed = w.items.use(u, it, d, t, p)
	w.events.append({"t": "item_use", "u": u.id, "item": it.id})
	if u.bot:
		var bb = w.bot_for(u.id)
		if bb != null:
			bb.botlog.on_item(w.time, String(it.id))
	if consumed:
		it.charges = int(it.get("charges", 1)) - 1
		if it.charges <= 0:
			u.inventory[slot] = null
	u.refresh_stats()
