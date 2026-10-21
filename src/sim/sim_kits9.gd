class_name SimKits9
extends RefCounted
## Thyrandael's kit (the owner's hero, run 2026-10-21; see docs/HANDOFF.md). Called by SimAbilities (cast,
## cast_error, on_spell_cast, channel_tick, channel_cleanup, judgement_range), SimOrders (aim: a move order turns the
## beam), SimCombat (on_damaged: False Judgement's charges) and SimWorld (tick).
##
## Divine Touch (innate): every spell he casts adds a charge, each an all-damage barrier (SimBarrier) as large as his
## intelligence; up to 3 charges, 12 s after the last spell.
## Holy Beam: a channel up to 7 s: a beam 800 long (150 wide) from him the way he faces; enemies in it take 50 / 70 /
## 90 / 110 magic damage and lose 30 / 40 / 50 / 60 mana a second and are slowed 30% while it touches them. He cannot
## walk; a move order turns him (60% slower) and the beam with him; S (Stop) ends it.
## Quick Flash: instant, around him (500): 30 / 50 / 70 / 90 magic damage and a 10 s mark; each mark already on an
## enemy adds 10 / 15 / 20 / 25 more to the next Flash (the marks stack and renew).
## Spirit Step: he is there at once (400 / 580 / 760 / 940); a stomp (300) silences enemies for 1 / 1.4 / 1.8 / 2.2 s
## and slows them 40% for 1 s.
## False Judgement: damage he takes builds charges (one per 300 / 250 / 200, up to 10 / 11 / 12; shown over him); the
## cast spends them all on a light blast (400) at a point: for 5 s enemies miss up to 40 / 70 / 100% of their attacks,
## are slowed up to 55% and take up to 60 / 80 / 100 magic damage a second, each by the share of charges spent. Its
## range (up to 800 / 1200 / 1600) follows the charges too, and its cooldown runs 10 / 9 / 8 s, down to 6 / 5 / 4 s
## with every charge.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const CASTS := ["holy_beam", "quick_flash", "spirit_step", "false_judgement"]
const EFFECTS: Array = []
const TOUCH := "divine_touch"               # his barrier (charges, SimBarrier pool "barrier_all")
const FLASH := "quick_flash_mark"
const JUDGED := "false_judgement"           # the debuff (source: Thyrandael)
const BEAM_SLOW := "holy_beam_slow"
const BEAM_TURN := "holy_beam_turn"         # on him while he channels: his turn rate cut
const BEAM_STEP := 3                        # ticks between the beam's hits (0.1 s)
const JUDGE_STEP := 15                      # ticks between the judgement's burns (0.5 s)

var w: SimWorld
var ab: SimAbilities
var charges := {}                           # Thyrandael id -> False Judgement charges
var _taken := {}                            # Thyrandael id -> damage taken toward the next charge
var _judged := {}                           # target id -> {src, dps, until}

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func owns_effect(kind: String) -> bool:
	return kind in EFFECTS

func update_effect(_e: Dictionary) -> bool:
	return true

func _enemy(team: int, o: SimUnit) -> bool:
	return o != null and o.alive and o.team != team and not o.is_building() and not o.is_ward() \
		and o.kind != K.COURIER and not o.is_invulnerable()

func cast_error(u: SimUnit, aid: String, _t: SimUnit, _p: Vector2, _check_target: bool) -> String:
	if aid == "spirit_step" and u.is_rooted():
		return "Rooted"
	if aid == "false_judgement" and judgement_charges(u) <= 0:
		return "No charges yet"
	return ""

func cast(u: SimUnit, aid: String, lv: int, _t: SimUnit, p: Vector2) -> void:
	match aid:
		"holy_beam":
			_start_beam(u, aid, p)
		"quick_flash":
			_flash(u, aid)
		"spirit_step":
			_step(u, aid, p)
		"false_judgement":
			_judgement(u, aid, lv, p)

# ---- Divine Touch --------------------------------------------------------------------------------------------------------

## Every spell he casts (SimAbilities.execute): one more charge of the barrier, up to the cap.
func on_spell_cast(u: SimUnit, _aid: String) -> void:
	if u.ability_level_of(TOUCH) <= 0 or u.is_broken():
		return
	var per := u.int_total * ab.val(u, TOUCH, "int_mult")
	var cap := int(ab.val(u, TOUCH, "max_charges"))
	var m := u.get_modifier(TOUCH)
	var left := float(m.get("barrier_all", 0.0)) if not m.is_empty() else 0.0
	var n := mini(cap, (int(m.get("charges", 0)) if not m.is_empty() else 0) + 1)
	var amount := minf(left + per, per * cap)
	SimBarrier.give(w, u, TOUCH, u.id, "all", amount, ab.val(u, TOUCH, "duration"), {"charges": n,
		"barrier_max": per * cap})

## Divine Touch's charges left (the barrier divided by one charge's worth, rounded up).
func touch_charges(u: SimUnit) -> int:
	var m := u.get_modifier(TOUCH)
	if m.is_empty():
		return 0
	var per := maxf(1.0, u.int_total * ab.val(u, TOUCH, "int_mult"))
	return mini(int(m.get("charges", 0)), ceili(float(m.get("barrier_all", 0.0)) / per - 0.001))

# ---- Holy Beam -----------------------------------------------------------------------------------------------------------

func _start_beam(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := p - u.pos
	if dir.length() > 1.0:
		u.facing = dir.angle()
	var dur := ab.val(u, aid, "max_channel")
	u.channel = {"ability": aid, "until": w.time + dur, "dur": dur, "point": u.pos + Vector2.from_angle(u.facing) * 400.0,
		"started": w.time, "beam": true}
	u.add_modifier({"id": BEAM_TURN, "source": u.id, "expires": w.time + dur + 0.5,
		"stats": {"turn_rate_pct": -ab.val(u, aid, "turn_slow")}})
	u.refresh_stats()
	w.events.append({"t": "holy_beam_start", "u": u.id, "dur": dur, "length": beam_length(u), "width": ab.val(u, aid, "width")})

## The beam's reach: its cast range (cast range bonuses count).
func beam_length(u: SimUnit) -> float:
	return ab.val(u, "holy_beam", "range") + u.cast_range_bonus

## Where the beam runs now: [from, to].
func beam_line(u: SimUnit) -> Array:
	var dir := Vector2.from_angle(u.facing)
	var from := u.pos + dir * (u.hull + 10.0)
	return [from, u.pos + dir * beam_length(u)]

## A move (or attack) order while the beam lasts: he turns to face it, the beam with him (SimOrders.issue).
func aim(u: SimUnit, p: Vector2) -> void:
	if u.channel.is_empty() or String(u.channel.ability) != "holy_beam":
		return
	if p.distance_to(u.pos) < 1.0:
		return
	u.channel["point"] = p
	w.events.append({"t": "holy_beam_aim", "u": u.id, "point": p})

## Every tick of the channel (SimAbilities.channel_tick).
func beam_tick(u: SimUnit) -> void:
	if w.tick % BEAM_STEP != 0:
		return
	var aid := "holy_beam"
	var line := beam_line(u)
	var a: Vector2 = line[0]
	var b: Vector2 = line[1]
	var width := ab.val(u, aid, "width")
	var step := float(BEAM_STEP) * C.DT
	var dmg := ab.val(u, aid, "damage") * step
	var burn := ab.val(u, aid, "mana_burn") * step
	var slow := ab.val(u, aid, "slow")
	var mid := (a + b) * 0.5
	for o: SimUnit in w.query(mid, a.distance_to(b) * 0.5 + width + 40.0, true):
		if not _enemy(u.team, o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, a, b)
		if cp.distance_to(o.pos) > width * 0.5 + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.MAGICAL, false, aid)
		if not o.alive:
			continue
		if o.max_mana > 0.0 and burn > 0.0:
			o.mana = maxf(0.0, o.mana - burn)
		if ab.can_debuff(o, u.team):
			w.status.apply(o, u.id, u.team, {"id": BEAM_SLOW, "dur": 0.25, "no_resist": true, "slow": slow,
				"fx": "holy_beam"})
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)

func beam_end(u: SimUnit, cancelled: bool) -> void:
	u.remove_modifier(BEAM_TURN)
	u.refresh_stats()
	w.events.append({"t": "holy_beam_end", "u": u.id, "cancelled": cancelled})

# ---- Quick Flash ---------------------------------------------------------------------------------------------------------

func _flash(u: SimUnit, aid: String) -> void:
	var r := ab.val(u, aid, "radius")
	var base := ab.val(u, aid, "damage")
	var per := ab.val(u, aid, "stack_damage")
	var dur := ab.val(u, aid, "mark_duration")
	var hits: Array = []
	for o: SimUnit in w.query(u.pos, r, true):
		if not _enemy(u.team, o) or u.edge_distance(o) > r:
			continue
		var m := _mark(o, u.id)
		var n := int(m.get("charges", 0)) if not m.is_empty() and w.time < float(m.get("expires", 0.0)) else 0
		w.combat.deal_damage(u.id, u.team, true, o, base + per * float(n), C.DamageType.MAGICAL, false, aid)
		hits.append(o.id)
		if o.alive:
			# the mark is not a slow or a stun: it lands on spell-immune enemies' records too (status resistance not)
			o.add_modifier({"id": FLASH, "source": u.id, "expires": w.time + dur, "charges": n + 1, "debuff": true,
				"from_team": u.team, "fx": "quick_flash"})
		if o.kind == K.NEUTRAL_CREEP and o.alive:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "quick_flash", "u": u.id, "radius": r, "hits": hits})

func _mark(o: SimUnit, src: int) -> Dictionary:
	for m in o.modifiers:
		if m.id == FLASH and int(m.get("source", -1)) == src:
			return m
	return {}

## Quick Flash marks `src` has on `o` (bots read them).
func flash_marks(src: SimUnit, o: SimUnit) -> int:
	if o == null or o.modifiers.is_empty():
		return 0
	var m := _mark(o, src.id)
	return int(m.get("charges", 0)) if not m.is_empty() and w.time < float(m.expires) else 0

# ---- Spirit Step ---------------------------------------------------------------------------------------------------------

func _step(u: SimUnit, aid: String, p: Vector2) -> void:
	var from := u.pos
	var reach := ab.cast_range(u, aid, -1)
	var to := p
	if to.distance_to(from) > reach:
		to = from + (to - from).normalized() * reach
	to = Vector2(clampf(to.x, -SimMap.EDGE, SimMap.EDGE), clampf(to.y, -SimMap.EDGE, SimMap.EDGE))
	if not w.map.is_walkable(to):
		var c := w.map.nearest_walkable(w.map.world_to_cell(to))
		to = w.map.cell_center(c.x, c.y)
	w.combat.disjoint(u)
	if (to - from).length() > 1.0:
		u.facing = (to - from).angle()
	u.pos = to
	u.path = PackedVector2Array()
	u.moving = false
	w.nudge_out(to, u.hull)
	var r := ab.val(u, aid, "radius")
	var hits: Array = []
	for o: SimUnit in w.query(to, r, true):
		if not _enemy(u.team, o) or o.pos.distance_to(to) > r + o.hull:
			continue
		hits.append(o.id)
		if ab.can_debuff(o, u.team):
			w.status.apply(o, u.id, u.team, {"id": "spirit_step_silence", "silence": true, "dur": ab.val(u, aid, "silence"),
				"fx": "silenced"})
			w.status.apply(o, u.id, u.team, {"id": "spirit_step_slow", "slow": ab.val(u, aid, "slow"),
				"dur": ab.val(u, aid, "slow_duration"), "fx": "slowed"})
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "spirit_step", "u": u.id, "from": from, "to": to, "radius": r, "hits": hits})

# ---- False Judgement -----------------------------------------------------------------------------------------------------

func judgement_charges(u: SimUnit) -> int:
	return int(charges.get(u.id, 0))

func judgement_max(u: SimUnit) -> int:
	return int(ab.val(u, "false_judgement", "max_charges"))

## The share of the most charges he holds (0..1).
func judgement_frac(u: SimUnit) -> float:
	var mx := judgement_max(u)
	return clampf(float(judgement_charges(u)) / float(maxi(1, mx)), 0.0, 1.0)

## Its cast range now (SimAbilities.cast_range): the share of charges of the most, never under 300.
func judgement_range(u: SimUnit) -> float:
	return maxf(ab.val(u, "false_judgement", "min_range"), ab.val(u, "false_judgement", "range") * judgement_frac(u))

## Damage he took from an enemy (SimCombat.deal_damage, before barriers): a charge every so much.
func on_damaged(u: SimUnit, amount: float) -> void:
	if amount <= 0.0 or u.ability_level_of("false_judgement") <= 0:
		return
	var mx := judgement_max(u)
	var have := judgement_charges(u)
	if have >= mx:
		return
	var per := ab.val(u, "false_judgement", "damage_per_charge")
	var t := float(_taken.get(u.id, 0.0)) + amount
	var gained := 0
	while t >= per and have + gained < mx:
		t -= per
		gained += 1
	_taken[u.id] = t if have + gained < mx else 0.0
	if gained > 0:
		charges[u.id] = have + gained
		w.events.append({"t": "judgement_charge", "u": u.id, "charges": have + gained, "max": mx})

func _judgement(u: SimUnit, aid: String, _lv: int, p: Vector2) -> void:
	var f := judgement_frac(u)
	var n := judgement_charges(u)
	charges[u.id] = 0
	_taken[u.id] = 0.0
	# the cooldown: from its longest down to its shortest with the charges spent
	var cd := lerpf(ab.val(u, aid, "cooldown"), ab.val(u, aid, "min_cooldown"), f)
	u.ability_ready[aid] = w.time + maxf(0.0, cd) * SimOrbs.cooldown_mult(u)
	var r := ab.val(u, aid, "radius")
	var dur := ab.val(u, aid, "duration")
	var miss := ab.val(u, aid, "miss") * f
	var slow := ab.val(u, aid, "slow") * f
	var dps := ab.val(u, aid, "dps") * f
	var hits: Array = []
	for o: SimUnit in w.query(p, r, true):
		if not _enemy(u.team, o) or o.pos.distance_to(p) > r + o.hull:
			continue
		hits.append(o.id)
		if not ab.can_debuff(o, u.team):
			continue
		if w.status.apply(o, u.id, u.team, {"id": JUDGED, "dur": dur, "blind": miss, "slow": slow, "fx": "false_judgement"}):
			_judged[o.id] = {"src": u.id, "team": u.team, "dps": dps}
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "false_judgement", "u": u.id, "pos": p, "radius": r, "charges": n, "frac": f, "hits": hits})

func _burn() -> void:
	var step := float(JUDGE_STEP) * C.DT
	for id in _judged.keys():
		var o := w.get_unit(int(id))
		var d: Dictionary = _judged[id]
		if o == null or not o.alive:
			_judged.erase(id)
			continue
		var m := {}
		for mm in o.modifiers:
			if mm.id == JUDGED and int(mm.get("source", -1)) == int(d.src):
				m = mm
		if m.is_empty():
			_judged.erase(id)
			continue
		w.combat.deal_damage(int(d.src), int(d.team), true, o, float(d.dps) * step, C.DamageType.MAGICAL, false,
			"false_judgement")

# ---- Per tick ------------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not _judged.is_empty() and w.tick % JUDGE_STEP == 0:
		_burn()
