class_name SimKits2
extends RefCounted
## The kits of Tock, the Clockmaker and Kragg, the Magnet Knight (run 2026-10-15 b). Called by SimAbilities: cast(),
## update_effect() for their effects, on_cast() (Quick Hands), on_attack_landed() (Magnetize) and tick() (Rewind's
## memory of where Tock stood).
##
## Tock bends time through the cooldown rate (SimWorld._shift_cooldowns): Time Bolt makes enemies' cooldowns run
## slower, Fast Forward makes an ally's run faster, Stop Time freezes enemies and their cooldowns; Quick Hands winds his
## own cooldowns forward on every spell; Rewind takes him back 3 seconds.
## Kragg puts Charges on enemies (one modifier per unit, up to 4, 8 s; his innate Magnetize): Iron Grip snaps him and
## a target together, Repel throws enemies further per Charge, Overload bursts around him every few attacks, Magnet
## Field drags enemies in (harder per Charge) and stuns them at the end. Each Charge makes the unit take more of his
## spell damage, more as he levels.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const CASTS := ["time_bolt", "fast_forward", "rewind", "slow_field", "stop_time", "iron_grip", "repel", "magnet_field"]
const CHARGE_SRC := -61                     # one Charge counter per unit, whichever Kragg put it there
const HISTORY_EVERY := 3                    # Rewind samples where Tock is every 3 ticks (0.1 s)

var w: SimWorld
var ab: SimAbilities
var _seq := 0

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func _can_hit(team: int, o: SimUnit) -> bool:
	return o.alive and o.team != team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
		and not o.is_invulnerable()

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"time_bolt":
			_time_bolt(u, aid, p)
		"fast_forward":
			if t == null or not t.alive:
				return
			var dur := ab.val(u, aid, "duration")
			# flat seconds off the basic spells' cooldowns (owner's rule 2026-10-15: not the ultimate, not items)
			var cut := ab.val(u, aid, "cut")
			for other in basic_spells(t):
				var r := float(t.ability_ready.get(other, C.LONG_AGO))
				if r > w.time:
					t.ability_ready[other] = maxf(w.time, r - cut)
			t.add_modifier({"id": "fast_forward", "source": u.id, "expires": w.time + dur,
				"stats": {"move_speed_pct": ab.val(u, aid, "move_pct")}, "fx": "fast_forward"})
			t.refresh_stats()
			w.events.append({"t": "fast_forward", "u": u.id, "target": t.id, "dur": dur, "cut": cut})
		"rewind":
			_rewind(u, aid)
		"slow_field":
			var dur2 := ab.val(u, aid, "duration")
			w.effects.append({"kind": "slow_field", "ability": aid, "src": u.id, "team": u.team, "pos": p,
				"radius": ab.val(u, aid, "radius"), "until": w.time + dur2, "slow": ab.val(u, aid, "slow"),
				"attack_slow": ab.val(u, aid, "attack_slow")})
			w.events.append({"t": "slow_field", "u": u.id, "pos": p, "radius": ab.val(u, aid, "radius"), "dur": dur2})
		"stop_time":
			_stop_time(u, aid, p)
		"iron_grip":
			_iron_grip(u, aid, t)
		"repel":
			_repel(u, aid, lv)
		"magnet_field":
			var dur3 := ab.val(u, aid, "duration")
			w.effects.append({"kind": "magnet_field", "ability": aid, "src": u.id, "team": u.team,
				"until": w.time + dur3, "radius": ab.val(u, aid, "radius"), "next_charge": w.time + 1.0})
			u.add_modifier({"id": "magnet_field", "source": u.id, "expires": w.time + dur3, "fx": "magnet_field"})
			w.events.append({"t": "magnet_field", "u": u.id, "radius": ab.val(u, aid, "radius"), "dur": dur3})

## Effects owned by this kit; returns true when the effect is over.
func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"time_bolt":
			return _update_bolt(e)
		"slow_field":
			return _update_field(e)
		"magnet_field":
			return _update_magnet(e)
	return true

func owns_effect(kind: String) -> bool:
	return kind in ["time_bolt", "slow_field", "magnet_field"]

# ---- Tock -----------------------------------------------------------------------------------------------------------

func _time_bolt(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := p - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	u.facing = dir.angle()
	_seq += 1
	var reach := ab.val(u, aid, "distance")
	w.effects.append({"kind": "time_bolt", "ability": aid, "src": u.id, "team": u.team, "pos": u.pos, "dir": dir,
		"left": reach, "speed": ab.val(u, aid, "speed"), "width": ab.val(u, aid, "width"),
		"damage": ab.val(u, aid, "damage"), "delay": ab.val(u, aid, "delay"), "delay_t": ab.val(u, aid, "delay_duration"),
		"hit": {}, "seq": _seq})
	w.events.append({"t": "time_bolt", "u": u.id, "from": u.pos, "dir": dir, "dist": reach,
		"speed": ab.val(u, aid, "speed"), "width": ab.val(u, aid, "width"), "seq": _seq})

func _update_bolt(e: Dictionary) -> bool:
	var step: float = float(e.speed) * C.DT
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * minf(step, float(e.left))
	e.pos = to
	e.left = float(e.left) - step
	for o: SimUnit in w.query(to, float(e.width) + 200.0, true):
		if e.hit.has(o.id) or not _can_hit(int(e.team), o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > float(e.width) + o.hull:
			continue
		e.hit[o.id] = true
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, "time_bolt")
		if o.alive and ab.can_debuff(o, int(e.team)):
			w.status.apply(o, int(e.src), int(e.team), {"id": "time_bolt", "dur": float(e.delay_t), "dispel": "basic",
				"stats": {"cooldown_rate": -float(e.delay)}, "fx": "time_slow"})
		if o.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(int(e.src))
			if src:
				w.ai.neutral_provoked(o, src)
		w.events.append({"t": "time_bolt_hit", "u": o.id, "src": e.src})
	w.events.append({"t": "time_bolt_move", "src": e.src, "seq": e.seq, "pos": to, "done": float(e.left) <= 0.0})
	return float(e.left) <= 0.0

## Rewind: back to where Tock stood `back` seconds ago (the oldest sample in his memory if he has not lived that long
## yet), with the health and mana he had then when he had more. A basic dispel; projectiles at him miss.
func _rewind(u: SimUnit, aid: String) -> void:
	var back := ab.val(u, aid, "back")
	var want := w.time - back
	var past: Array = []
	for s in u.history:
		if float(s[0]) >= want - 0.001:
			past = s
			break
	if past.is_empty():
		return
	var from := u.pos
	var to: Vector2 = past[1]
	if not w.map.is_walkable(to):
		var c := w.map.nearest_walkable(w.map.world_to_cell(to))
		to = w.map.cell_center(c.x, c.y)
	u.pos = to
	u.path = PackedVector2Array()
	u.moving = false
	u.knock = {}
	u.hp = clampf(maxf(u.hp, float(past[2])), 0.0, u.max_hp)
	# the mana he had then, less what Rewind itself costs (it is never free)
	u.mana = clampf(maxf(u.mana, float(past[3]) - ab.ability_mana(u, aid)), 0.0, u.max_mana)
	w.items._basic_dispel(u)
	w.combat.disjoint(u)
	u.history.clear()
	w.events.append({"t": "rewind", "u": u.id, "from": from, "to": to})

## Slow Field, every 6 ticks: enemies inside are slowed (move and attack) until 0.5 s after they leave.
func _update_field(e: Dictionary) -> bool:
	if w.time >= float(e.until):
		w.events.append({"t": "slow_field_end", "u": e.src, "pos": e.pos})
		return true
	if w.tick % 6 != 0:
		return false
	for o: SimUnit in w.query(e.pos, float(e.radius) + 40.0):
		if not _can_hit(int(e.team), o) or o.pos.distance_to(e.pos) > float(e.radius) + o.hull:
			continue
		if not ab.can_debuff(o, int(e.team)):
			continue
		w.status.apply(o, int(e.src), int(e.team), {"id": "slow_field", "dur": 0.5, "slow": float(e.slow),
			"stats": {"attack_speed": -float(e.attack_slow)}, "fx": "time_slow"})
	return false

## Stop Time: every enemy in the area is frozen: stunned, and its cooldowns stand still. Goes through Spell Shield.
func _stop_time(u: SimUnit, aid: String, p: Vector2) -> void:
	var r := ab.val(u, aid, "radius")
	var dur := ab.val(u, aid, "duration")
	var frozen: Array = []
	for o: SimUnit in w.query(p, r + 60.0):
		if not _can_hit(u.team, o) or o.pos.distance_to(p) > r + o.hull:
			continue
		if w.status.apply(o, u.id, u.team, {"id": "stop_time", "stun": true, "dur": dur,
				"stats": {"cooldown_rate": -1.0}, "fx": "stop_time"}, true):
			frozen.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "stop_time", "u": u.id, "pos": p, "radius": r, "dur": dur, "frozen": frozen})

## A unit's basic spells: its abilities but the ultimate (the one with hero level requirements).
static func basic_spells(t: SimUnit) -> Array:
	var ult := SimData.ultimate_of(t.abilities) if t.is_hero() else ""
	return t.abilities.filter(func(a): return String(a) != ult)

## Quick Hands: a spell Tock casts takes seconds off the cooldowns of his other spells.
func on_cast(u: SimUnit, aid: String) -> void:
	if u.ability_level_of("quick_hands") <= 0 or u.is_broken():
		return
	var cut := ab.val(u, "quick_hands", "cut")
	var any := false
	for other in u.abilities:
		if other == aid:
			continue
		var r := float(u.ability_ready.get(other, C.LONG_AGO))
		if r > w.time:
			u.ability_ready[other] = maxf(w.time, r - cut)
			any = true
	if any:
		w.events.append({"t": "quick_hands", "u": u.id})

## Every 0.1 s: where heroes with Rewind stand (kept for 4 s).
func tick() -> void:
	if w.tick % HISTORY_EVERY != 0:
		return
	for h in w.heroes:
		if not h.alive or h.ability_level_of("rewind") <= 0:
			if not h.history.is_empty() and not h.alive:
				h.history.clear()
			continue
		h.history.append([w.time, h.pos, h.hp, h.mana])
		while h.history.size() > 0 and w.time - float(h.history[0][0]) > 4.0:
			h.history.pop_front()

# ---- Kragg ----------------------------------------------------------------------------------------------------------

## Charges a unit carries (0 when none or expired).
func charges(t: SimUnit) -> int:
	var m := t.get_modifier("magnet_charge")
	if m.is_empty() or w.time >= float(m.expires):
		return 0
	return int(m.charges)

## Adds Charges from Kragg (up to his maximum), refreshing their 8 s. Not on debuff-immune enemies.
func add_charges(t: SimUnit, src: SimUnit, n: int) -> void:
	if n <= 0 or not _can_hit(src.team, t) or not ab.can_debuff(t, src.team):
		return
	var mx := int(ab.val(src, "magnetize", "max_charges")) if src.ability_level_of("magnetize") > 0 else 4
	var dur := ab.val(src, "magnetize", "duration") if src.ability_level_of("magnetize") > 0 else 8.0
	var c := mini(mx, charges(t) + n)
	t.add_modifier({"id": "magnet_charge", "source": CHARGE_SRC, "expires": w.time + dur, "charges": c, "by": src.id,
		"fx": "magnet", "debuff": true})
	w.events.append({"t": "magnet_charge", "u": t.id, "charges": c})

## Magnetize's spell amplification per Charge for this Kragg now: 0.10% + 0.05% per hero level (it grows as he levels).
func amp_per_charge(src: SimUnit) -> float:
	return ab.val(src, "magnetize", "spell_amp") + ab.val(src, "magnetize", "spell_amp_per_level") * float(src.level)

## Kragg's spell damage on a charged enemy: Magnetize adds a share per Charge.
func spell_mult(src: SimUnit, t: SimUnit) -> float:
	if src.ability_level_of("magnetize") <= 0 or src.is_broken():
		return 1.0
	return 1.0 + amp_per_charge(src) * charges(t)

## Kragg's attacks: Magnetize gives a Charge; Overload counts the attack and bursts on every Nth one.
func on_attack_landed(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(int(s.src))
	if src == null or src.is_broken():
		return
	if src.ability_level_of("magnetize") > 0 and t.alive:
		add_charges(t, src, 1)
	if src.ability_level_of("overload") > 0 and src.alive:
		var n := int(src.stacks.get("overload", 0)) + 1
		if n >= int(ab.val(src, "overload", "every")):
			n = 0
			_overload(src, "overload")
		src.stacks["overload"] = n

## Attacks Kragg has landed toward his next Overload, and how many it takes.
func overload_count(u: SimUnit) -> Vector2i:
	if u.ability_level_of("overload") <= 0:
		return Vector2i(0, 0)
	return Vector2i(int(u.stacks.get("overload", 0)), int(ab.val(u, "overload", "every")))

func _land_spot(p: Vector2) -> Vector2:
	if w.map.is_walkable(p):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

## Iron Grip: Kragg and the enemy slide to meet halfway in 0.3 s; the enemy takes damage, is stunned (through the
## slide) and gets Charges. A debuff-immune enemy is not moved: Kragg comes to it.
func _iron_grip(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var dur := ab.val(u, aid, "pull_time")
	var dir := t.pos - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var movable := ab.can_debuff(t, u.team) and not t.has_flag("unstoppable")
	var mid := (u.pos + t.pos) * 0.5 if movable else t.pos - dir * (u.hull + t.hull + 10.0)
	var gap := (u.hull + t.hull) * 0.5 + 6.0
	var u_to := _land_spot(mid - dir * gap) if movable else _land_spot(mid)
	u.knock = {"from": u.pos, "to": u_to, "t": 0.0, "dur": dur, "disable": false, "src": u.id}
	u.path = PackedVector2Array()
	if movable:
		w.orders.cancel_channel(t)
		t.leap = {}
		t.hop = {}
		t.knock = {"from": t.pos, "to": _land_spot(mid + dir * gap), "t": 0.0, "dur": dur, "disable": true, "src": u.id}
		t.path = PackedVector2Array()
	w.combat.deal_damage(u.id, u.team, true, t, ab.val(u, aid, "damage") * spell_mult(u, t), C.DamageType.MAGICAL,
		false, "iron_grip")
	if t.alive and movable:
		w.status.apply(t, u.id, u.team, {"id": "iron_grip", "stun": true, "dur": ab.val(u, aid, "stun") + dur, "fx": "stun"})
		add_charges(t, u, int(ab.val(u, aid, "charges")))
	if t.kind == K.NEUTRAL_CREEP:
		w.ai.neutral_provoked(t, u)
	u.facing = dir.angle()
	w.events.append({"t": "iron_grip", "u": u.id, "target": t.id, "mid": mid, "dur": dur})

## Repel: damage and a physics push away from Kragg, 25% stronger per Charge; a slow; a crash stuns (SimAbilities
## _impact uses this ability's impact damage and stun); +1 Charge.
func _repel(u: SimUnit, aid: String, lv: int) -> void:
	var r := ab.val(u, aid, "radius")
	_seq += 1
	var seq := 7000000 + _seq
	w.events.append({"t": "repel", "u": u.id, "pos": u.pos, "radius": r})
	for o: SimUnit in w.query(u.pos, r + 40.0, true):
		if not _can_hit(u.team, o) or u.edge_distance(o) > r:
			continue
		var ch := charges(o)
		w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage") * spell_mult(u, o), C.DamageType.MAGICAL,
			false, "repel")
		if not o.alive or not ab.can_debuff(o, u.team):
			continue
		var dir := o.pos - u.pos
		if dir.length() < 1.0:
			dir = Vector2.from_angle(u.facing)
		var speed := ab.val(u, aid, "push_speed") * (1.0 + ab.val(u, aid, "per_charge") * ch) / ab.mass(o)
		ab.start_push(o, dir.normalized() * speed, u.id, u.team, "repel", lv, seq)
		w.status.apply(o, u.id, u.team, {"id": "repel_slow", "dur": ab.val(u, aid, "slow_duration"),
			"slow": ab.val(u, aid, "slow"), "fx": "slow"})
		add_charges(o, u, 1)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)

## Overload: a burst of electric charge around Kragg; enemies within 200 take magic damage (more with Charges) and
## are slowed by 80% for 0.8 s.
func _overload(u: SimUnit, aid: String) -> void:
	var r := ab.val(u, aid, "radius")
	var hits: Array = []
	for o: SimUnit in w.query(u.pos, r + 40.0, true):
		if not _can_hit(u.team, o) or u.edge_distance(o) > r:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage") * spell_mult(u, o), C.DamageType.MAGICAL,
			false, "overload", false, {"element": C.Element.LIGHTNING})
		if o.alive:
			w.status.apply(o, u.id, u.team, {"id": "overload_slow", "dur": ab.val(u, aid, "slow_duration"),
				"slow": ab.val(u, aid, "slow"), "fx": "slow"})
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "overload", "u": u.id, "pos": u.pos, "hits": hits, "radius": r})

## Magnet Field, each tick: enemies within the radius slide toward Kragg (not closer than 100 to him), faster with
## Charges; once a second each one gains a Charge. At the end, enemies within 300 take damage and are stunned.
func _update_magnet(e: Dictionary) -> bool:
	var u := w.get_unit(int(e.src))
	if u == null or not u.alive:
		return true
	var aid := String(e.ability)
	var add := w.time >= float(e.next_charge)
	if add:
		e.next_charge = float(e.next_charge) + 1.0
	for o: SimUnit in w.query(u.pos, float(e.radius) + 40.0):
		if not _can_hit(u.team, o) or u.pos.distance_to(o.pos) > float(e.radius) + o.hull:
			continue
		if not ab.can_debuff(o, u.team):
			continue
		var d := o.pos.distance_to(u.pos)
		if d > u.hull + o.hull + 80.0 and o.knock.is_empty():
			var speed := ab.val(u, aid, "pull") + ab.val(u, aid, "pull_per_charge") * charges(o)
			var np := o.pos + (u.pos - o.pos).normalized() * minf(speed * C.DT, d - u.hull - o.hull - 80.0)
			if w.map.is_walkable(np):
				o.pos = np
		if add:
			add_charges(o, u, 1)
	if w.time < float(e.until):
		return false
	var er := ab.val(u, aid, "end_radius")
	var stunned: Array = []
	for o: SimUnit in w.query(u.pos, er + 40.0):
		if not _can_hit(u.team, o) or u.pos.distance_to(o.pos) > er + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "end_damage") * spell_mult(u, o), C.DamageType.MAGICAL,
			false, "magnet_field")
		if o.alive and w.status.apply(o, u.id, u.team, {"id": "magnet_field_stun", "stun": true,
				"dur": ab.val(u, aid, "end_stun"), "fx": "stun"}):
			stunned.append(o.id)
	w.events.append({"t": "magnet_field_end", "u": u.id, "radius": er, "stunned": stunned})
	return true
