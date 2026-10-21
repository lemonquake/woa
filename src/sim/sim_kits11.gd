class_name SimKits11
extends RefCounted
## Dracoxinia's kit (the owner's hero, run 2026-10-21 b; seven skills; see docs/HANDOFF.md). Called by SimAbilities
## (cast, cast_error, change_sword), SimCombat (on_attack_released, on_attack_landed: Dragon Blade; scales_mult: Royal
## Scales; the attack element is SimUnit.atk_element) and SimWorld (tick).
##
## Her swords, in order (Change Sword, levels 1 / 2 / 3: the first 3 / 4 / 5): Pink (Lightning, her own), Gold (Light),
## Blue (Water), Red (Fire), Green (Nature). The sword's element is her attacks'.
##   Royal Scales (innate): 15% less damage from enemies whose element her sword beats (SimConst.ELEMENT_BEATS).
##   Dragon Dash (Q): she dashes to the point (up to 650, 1800 a second) through her enemies: physical damage, a slow.
##   Dragon Leap (W): she leaps to the point (500-650) over trees and cliffs, 0.55 s in the air (the owner swapped
##   her old W sweep and Dragon Breath for a mobility skill and a passive, 2026-10-22).
##   Dragon Hide (E, passive): more armor and health regeneration (SimUnit.refresh_stats).
##   Rising Slash (D): physical damage and the target thrown into the air (stunned) for 0.8-1.4 s.
##   Dragon Blade (F, passive): every 4th attack is a heavy strike (more damage) with the sword's power: Pink lightning
##   jumps to 3 more enemies (60%), Gold an All-damage Barrier as large as the strike, Blue a root and slow, Red the
##   strike on every enemy within 250 of the target and a burn on them all, Green a heal of 60% of it.
##   Change Sword (R): the next sword (1 s apart, free); the next attack after a change is a strike (once every 6-4 s).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const EL = C.Element
const CASTS := ["dragon_dash", "dragon_leap", "rising_slash"]
const SWORDS := [
	{"id": "pink", "name": "Pink Sword", "element": EL.LIGHTNING},
	{"id": "gold", "name": "Gold Sword", "element": EL.LIGHT},
	{"id": "blue", "name": "Blue Sword", "element": EL.WATER},
	{"id": "red", "name": "Red Sword", "element": EL.FIRE},
	{"id": "green", "name": "Green Sword", "element": EL.NATURE},
]
const BLADE := "dragon_blade"
const CHANGE := "change_sword"
const SCALES := "royal_scales"
const GOLD_BARRIER := "gold_sword_barrier"
const CHECK_STEP := 9                       # ticks between sword-modifier checks (0.3 s)

var w: SimWorld
var ab: SimAbilities
var sword := {}                             # hero id -> index into SWORDS
var count := {}                             # hero id -> attacks since the last strike
var forced := {}                            # hero id -> true: the next attack is a strike (a change gave it)
var next_force := {}                        # hero id -> game time a change may give a strike again
var dashes := {}                            # hero id -> {hit: {}, last: Vector2, dir}

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func _enemy(team: int, o: SimUnit) -> bool:
	return o != null and o.alive and o.team != team and not o.is_building() and not o.is_ward() \
		and o.kind != K.COURIER and not o.is_invulnerable()

func cast_error(u: SimUnit, aid: String, _t: SimUnit, _p: Vector2, _check_target: bool) -> String:
	if (aid == "dragon_dash" or aid == "dragon_leap") and u.is_rooted():
		return "Rooted"
	return ""

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"dragon_dash":
			_dash(u, aid, p)
		"dragon_leap":
			_leap(u, aid, p)
		"rising_slash":
			_rising(u, aid, lv, t)

# ---- Swords -------------------------------------------------------------------------------------------------------------

## The sword she holds now (an index into SWORDS).
func sword_of(u: SimUnit) -> int:
	return int(sword.get(u.id, 0))

func sword_id(u: SimUnit) -> String:
	return String(SWORDS[sword_of(u)].id)

## Her sword's element (her own, Lightning, with the Pink Sword).
func sword_element(u: SimUnit) -> int:
	return int(SWORDS[sword_of(u)].element)

## How many swords Change Sword has open at its level (Pink alone before it is learned).
func swords_open(u: SimUnit) -> int:
	var lv := u.ability_level_of(CHANGE)
	return 1 if lv <= 0 else int(ab.val(u, CHANGE, "swords"))

## Change Sword (SimAbilities.execute): the next open sword.
func change_sword(u: SimUnit) -> void:
	set_sword(u, (sword_of(u) + 1) % maxi(1, swords_open(u)))
	if w.time >= float(next_force.get(u.id, C.LONG_AGO)):
		forced[u.id] = true
		next_force[u.id] = w.time + ab.val(u, CHANGE, "strike_wait")

## Hold sword `i` (bots and tests may pick one directly through Change Sword's cycle; this sets it).
func set_sword(u: SimUnit, i: int) -> void:
	sword[u.id] = clampi(i, 0, SWORDS.size() - 1)
	u.atk_element = sword_element(u)
	_mark(u)
	w.events.append({"t": "sword_change", "u": u.id, "sword": sword_of(u), "id": sword_id(u),
		"name": String(SWORDS[sword_of(u)].name)})

## The sword shows on her buff bar as its own modifier ("Pink Sword" and so on).
func _mark(u: SimUnit) -> void:
	var want := "sword_" + sword_id(u)
	for s in SWORDS:
		var mid := "sword_" + String(s.id)
		if mid != want and not u.get_modifier(mid).is_empty():
			u.remove_modifier(mid)
	if u.get_modifier(want).is_empty():
		u.add_modifier({"id": want, "source": u.id, "expires": INF, "fx": "sword"})

## How many more attacks until the next Dragon Blade strike (0: the next one is).
func strike_in(u: SimUnit) -> int:
	if bool(forced.get(u.id, false)):
		return 0
	if u.ability_level_of(BLADE) <= 0:
		return -1
	return maxi(0, int(ab.val(u, BLADE, "every")) - 1 - int(count.get(u.id, 0)))

# ---- Royal Scales -------------------------------------------------------------------------------------------------------

## The share of a blow from `src` that reaches her (SimCombat.deal_damage).
func scales_mult(t: SimUnit, src: SimUnit) -> float:
	if src == null or src.team == t.team or t.is_broken():
		return 1.0
	var mine := sword_element(t)
	for pair in C.ELEMENT_BEATS:
		if int(pair[0]) == mine and int(pair[1]) == src.element:
			return maxf(0.0, 1.0 - ab.val(t, SCALES, "reduction"))
	return 1.0

# ---- Dragon Blade -------------------------------------------------------------------------------------------------------

## An attack leaves her (SimCombat.release_attack): every 4th, or the first after a sword change, is a strike.
func on_attack_released(u: SimUnit, snap: Dictionary, t: SimUnit) -> void:
	if not u.ability_level.has(BLADE) or u.is_broken():
		return
	if t == null or t.is_building() or t.is_ward() or t.team == u.team:
		return
	var lv := u.ability_level_of(BLADE)
	var strike := false
	if bool(forced.get(u.id, false)):
		forced.erase(u.id)
		strike = true
	elif lv > 0:
		var n := int(count.get(u.id, 0)) + 1
		if n >= int(ab.val(u, BLADE, "every")):
			strike = true
		else:
			count[u.id] = n
	if not strike:
		return
	count[u.id] = 0
	snap["blade"] = ab.val(u, BLADE, "damage") if lv > 0 else 0.0
	snap["blade_sword"] = sword_of(u)
	w.events.append({"t": "dragon_blade_swing", "u": u.id, "sword": sword_of(u), "id": sword_id(u)})

## A strike that landed (SimCombat.land_attack): the sword's power.
func on_attack_landed(s: Dictionary, t: SimUnit, dealt: float) -> void:
	var u := w.get_unit(int(s.src))
	if u == null:
		return
	var sid := String(SWORDS[int(s.get("blade_sword", 0))].id)
	var amount := maxf(dealt, 0.0)
	var extra := {}
	match sid:
		"pink":
			# lightning jumps from the target to 3 more enemies within 500, each from the last, for 60% of the strike
			var hops: Array = []
			var from := t
			var done := {t.id: true}
			for i in int(ab.val(u, BLADE, "chain")):
				var best: SimUnit = null
				var bd := INF
				for o: SimUnit in w.query(from.pos, ab.val(u, BLADE, "chain_radius"), true):
					if not _enemy(u.team, o) or done.has(o.id):
						continue
					var d := o.pos.distance_to(from.pos)
					if d <= ab.val(u, BLADE, "chain_radius") + o.hull and d < bd:
						bd = d
						best = o
				if best == null:
					break
				done[best.id] = true
				hops.append(best.id)
				w.combat.deal_damage(u.id, u.team, true, best, amount * ab.val(u, BLADE, "chain_pct"),
					C.DamageType.MAGICAL, false, BLADE, false, {"element": EL.LIGHTNING})
				if best.kind == K.NEUTRAL_CREEP and best.alive:
					w.ai.neutral_provoked(best, u)
				from = best
			extra["chain"] = hops
		"gold":
			var m := u.get_modifier(GOLD_BARRIER)
			var left := float(m.get("barrier_all", 0.0)) if not m.is_empty() else 0.0
			var add := amount * ab.val(u, BLADE, "barrier_pct")
			if add > 0.0:
				SimBarrier.give(w, u, GOLD_BARRIER, u.id, "all", minf(left + add, add * 2.0),
					ab.val(u, BLADE, "barrier_duration"))
		"blue":
			if t.alive and ab.can_debuff(t, u.team):
				w.status.apply(t, u.id, u.team, {"id": "blue_sword_root", "root": true, "dur": ab.val(u, BLADE, "root"),
					"fx": "rooted", "dispel": "basic"})
				w.status.apply(t, u.id, u.team, {"id": "blue_sword_slow", "slow": ab.val(u, BLADE, "slow"),
					"dur": ab.val(u, BLADE, "slow_duration"), "fx": "slowed", "dispel": "basic"})
		"red":
			var hit: Array = [t]
			var r := ab.val(u, BLADE, "splash_radius")
			for o: SimUnit in w.query(t.pos, r, true):
				if o == t or not _enemy(u.team, o) or o.pos.distance_to(t.pos) > r + o.hull:
					continue
				hit.append(o)
				w.combat.deal_damage(u.id, u.team, true, o, amount, C.DamageType.PHYSICAL, false, BLADE, false,
					{"element": EL.FIRE})
				if o.kind == K.NEUTRAL_CREEP and o.alive:
					w.ai.neutral_provoked(o, u)
			var ids: Array = []
			for o: SimUnit in hit:
				ids.append(o.id)
				if o.alive:
					w.status.add_dot(o, u, "red_sword_burn", ab.val(u, BLADE, "burn"), ab.val(u, BLADE, "burn_duration"),
						EL.FIRE)
			extra["splash"] = ids
		"green":
			if amount > 0.0:
				w.combat.heal(u, amount * ab.val(u, BLADE, "heal_pct"), u)
	var e := {"t": "dragon_blade", "u": u.id, "target": t.id, "sword": int(s.get("blade_sword", 0)), "id": sid,
		"amount": amount}
	e.merge(extra)
	w.events.append(e)

# ---- Dragon Dash --------------------------------------------------------------------------------------------------------

func _dash(u: SimUnit, aid: String, p: Vector2) -> void:
	var from := u.pos
	var dir := p - from
	var dist := clampf(dir.length(), 150.0, ab.cast_range(u, aid, -1))
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var to := ab.kits10.dash_end(from, dir, dist)
	var dur := maxf(0.08, from.distance_to(to) / ab.val(u, aid, "speed"))
	u.facing = dir.angle()
	u.path = PackedVector2Array()
	u.moving = false
	u.knock = {"from": from, "to": to, "t": 0.0, "dur": dur, "disable": false, "charge": aid}
	dashes[u.id] = {"hit": {}, "last": from, "dir": dir}
	w.events.append({"t": "dragon_dash", "u": u.id, "from": from, "to": to, "dur": dur, "sword": sword_of(u)})

func _dash_tick(u: SimUnit, d: Dictionary) -> void:
	var aid := "dragon_dash"
	var going: bool = u.alive and not u.knock.is_empty() and String(u.knock.get("charge", "")) == aid
	var a: Vector2 = d.last
	var b := u.pos
	d.last = b
	var r := ab.val(u, aid, "width") * 0.5
	for o: SimUnit in w.query(b, r + u.hull + 150.0, true):
		if not _enemy(u.team, o) or d.hit.has(o.id):
			continue
		if Geometry2D.get_closest_point_to_segment(o.pos, a, b).distance_to(o.pos) > r + o.hull:
			continue
		d.hit[o.id] = true
		w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage"), C.DamageType.PHYSICAL, false, aid)
		w.events.append({"t": "dragon_dash_hit", "u": u.id, "target": o.id, "sword": sword_of(u)})
		if o.alive and ab.can_debuff(o, u.team):
			w.status.apply(o, u.id, u.team, {"id": "dragon_dash_slow", "slow": ab.val(u, aid, "slow"),
				"dur": ab.val(u, aid, "slow_duration"), "fx": "slowed", "dispel": "basic"})
		if o.kind == K.NEUTRAL_CREEP and o.alive:
			w.ai.neutral_provoked(o, u)
	if not going:
		dashes.erase(u.id)
		w.events.append({"t": "dragon_dash_end", "u": u.id, "pos": u.pos})

# ---- Dragon Leap --------------------------------------------------------------------------------------------------------

## She leaps to the point on an arc (over trees and cliffs; SimAbilities.update_motion's air flight lands her on open
## ground) and plays her leap while in the air (the knock's "charge").
func _leap(u: SimUnit, aid: String, p: Vector2) -> void:
	var from := u.pos
	var dir := p - from
	var dist := clampf(dir.length(), 100.0, ab.cast_range(u, aid, -1))
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var to := from + dir * dist
	var dur := ab.val(u, aid, "leap_time")
	u.facing = dir.angle()
	u.path = PackedVector2Array()
	u.moving = false
	u.knock = {"from": from, "to": to, "t": 0.0, "dur": dur, "disable": false, "air": true,
		"height": ab.val(u, aid, "height"), "charge": aid}
	w.events.append({"t": "dragon_leap", "u": u.id, "from": from, "to": to, "dur": dur, "sword": sword_of(u)})

# ---- Rising Slash -------------------------------------------------------------------------------------------------------

func _rising(u: SimUnit, aid: String, _lv: int, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	w.combat.deal_damage(u.id, u.team, true, t, ab.val(u, aid, "damage"), C.DamageType.PHYSICAL, false, aid)
	var air := ab.val(u, aid, "air")
	if t.alive and ab.can_debuff(t, u.team):
		w.orders.cancel_channel(t)
		if t.knock.is_empty() and t.leap.is_empty() and not t.has_flag("unstoppable"):
			t.knock = {"from": t.pos, "to": t.pos, "t": 0.0, "dur": air, "air": true, "height": ab.val(u, aid, "height")}
			t.path = PackedVector2Array()
		w.status.apply(t, u.id, u.team, {"id": "stunned", "stun": true, "dur": air, "fx": "stun"})
	if t.kind == K.NEUTRAL_CREEP and t.alive:
		w.ai.neutral_provoked(t, u)
	w.events.append({"t": "rising_slash", "u": u.id, "target": t.id, "dur": air, "sword": sword_of(u)})

# ---- Per tick ---------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not dashes.is_empty():
		for id in dashes.keys():
			var u := w.get_unit(int(id))
			if u == null:
				dashes.erase(id)
				continue
			_dash_tick(u, dashes[id])
	if w.tick % CHECK_STEP == 0:
		for h in w.heroes:
			if h.ability_level.has(CHANGE):
				if h.atk_element != sword_element(h):
					h.atk_element = sword_element(h)
				if h.get_modifier("sword_" + sword_id(h)).is_empty():
					_mark(h)
