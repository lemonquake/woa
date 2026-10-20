class_name SimBot18
extends RefCounted
## How bots play the five heroes of hero_ideas.txt (run 2026-10-18 f): Airah, Burak, Ser Emelrich, Feran Mock and
## Ghorman. Called by SimBot: spells() in fights and trades, escape() while running, aoe_farm() on creep packs, tick()
## every think (Burak's leap to his axe, Steel Stance, Ghorman's taming and Blessing). All static: `b` is the SimBot
## whose hero acts.
##
## Airah: Gust through the target (leading a runner) and toward a wall when one is close behind it; Hurricane on two or
## more enemies or a disabled one; Tailwind on an ally in trouble (slowed, chased, low) or on herself to run; the Wind
## Wall between a ranged enemy hero and the ally it shoots.
## Burak: Axe Throw at a hero it can follow up on, the leap only when the fight is in its favour (its threat measure)
## or the target is low; Reckless Swing in melee reach of heroes and on creep waves; Berserk when a fight starts with the
## enemy not already winning.
## Ser Emelrich: the wind-ups (Overhead Cut, Giant Swing) only on a target that cannot step out in time: stunned, rooted,
## slowed, hexed or with its escape on cooldown, or close and slow-turning toward him; Sweep with enemies in front,
## best with a tree, cliff or unit on his left; Steel Stance on when a ranged hero is in front of him and he is not
## chasing.
## Feran: Knife Juggle at point blank (more knives hit); Joke Box on a group or a fleeing hero; Swap a chased enemy into
## his allies, or swap out a stunned ally; Shuffle on three or more enemies when his team is there.
## Ghorman: tames a camp creep with a spell (Ogre's Smash, the Warlord's Stomp, the wolf's Snarl) first, then any
## neutral or an enemy lane creep up to his limit; Roar when he engages; Blessing on a hurt beast in a fight; Beast Form
## when the team fights. His beasts follow their own orders (SimKits6._beast_ai).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const KITS := ["airah", "burak", "emelrich", "feran", "ghorman"]
## Escape skills a target may still use to step out of a wind-up (Leap Strike, the door, the trap leap, the dagger,
## Rewind, Tailwind's speed, Swap, the axe leap).
const ESCAPES := ["leap_strike", "door_of_the_end", "lay_trap", "swift_dagger", "rewind", "back_leap", "tailwind",
	"swap", "void_rush"]

static func handles(kit: String) -> bool:
	return kit in KITS

# ---- Shared helpers -------------------------------------------------------------------------------------------------

static func _cast_point(b: SimBot, h: SimUnit, aid: String, p: Vector2, hold: float) -> bool:
	if b.w.abilities.cast_error(h, aid, -1, null, p) != "":
		return false
	b._order(h, {"type": O.CAST_POINT, "ability": aid, "point": p}, true)
	b._cast_deadline = b.w.time + hold
	b._spent()
	return true

static func _cast_none(b: SimBot, h: SimUnit, aid: String, hold: float) -> bool:
	if b.w.abilities.cast_error(h, aid, -1, null, h.pos) != "":
		return false
	b._order(h, {"type": O.CAST_NO_TARGET, "ability": aid}, true)
	b._cast_deadline = b.w.time + hold
	b._spent()
	return true

static func _cast_unit(b: SimBot, h: SimUnit, aid: String, t: SimUnit, hold: float) -> bool:
	if t == null or b.w.abilities.cast_error(h, aid, -1, t, t.pos) != "":
		return false
	if h.pos.distance_to(t.pos) > b.w.abilities.cast_range(h, aid, -1, t) + 300.0:
		return false
	b._order(h, {"type": O.CAST_UNIT, "ability": aid, "target": t.id}, true)
	b._cast_deadline = b.w.time + hold
	b._spent()
	return true

static func _foes_near(b: SimBot, p: Vector2, r: float) -> int:
	var n := 0
	for f in b._foes:
		if f.alive and f.pos.distance_to(p) < r:
			n += 1
	return n

static func _allies_near(b: SimBot, h: SimUnit, p: Vector2, r: float) -> int:
	var n := 0
	for a in b._allies:
		if a != h and a.alive and a.pos.distance_to(p) < r:
			n += 1
	return n

## A fight worth committing to: the target is low, friends are with us, or we are healthy and not outmatched.
static func _fight_on(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	return e.hp < e.max_hp * 0.55 or _allies_near(b, h, e.pos, 1100.0) > 0 \
		or (h.hp > h.max_hp * 0.6 and b._threat < 1.2)

## Where a moving target will be in `t` seconds (scaled by the bot's aim skill).
static func _lead(b: SimBot, e: SimUnit, t: float) -> Vector2:
	if not e.moving:
		return e.pos
	return e.pos + Vector2.from_angle(e.facing) * e.move_speed * t * float(b.sk.aim)

## Whether `e` cannot step out of a wind-up of `dur` seconds: held in place, slowed, or its escapes spent.
static func _pinned(b: SimBot, e: SimUnit, dur: float) -> bool:
	if e.is_stunned() or e.has_flag("hex"):
		var m := e.get_modifier("stunned")
		if m.is_empty() or float(m.get("expires", 0.0)) - b.w.time > dur * 0.5:
			return true
	if e.is_rooted() or e.move_speed < float(e.def.move_speed) * 0.75:
		return true
	if not e.channel.is_empty():
		return true                                     # channelling: it stands still
	for aid in ESCAPES:
		if e.ability_level_of(aid) > 0 and b.w.abilities.cooldown_left(e, aid) <= 0.0:
			return false
	for i in e.inventory.size():
		var it = e.inventory[i]
		if it != null and String(it.get("id", "")) in ["jump_knife", "crash_knife", "slip_boots"] \
				and b.w.abilities.item_cooldown_left(e, i) <= 0.0:
			return false
	return true

## What lies just beyond `p` going `dir` (a tree, cliff, building or unit to crash into within `reach`).
static func _wall_behind(w: SimWorld, p: Vector2, dir: Vector2, reach: float, ignore: SimUnit) -> bool:
	var step := 40.0
	var d := step
	while d <= reach:
		var q := p + dir * d
		if not w.map.is_walkable(q):
			return true
		for o: SimUnit in w.query(q, 60.0):
			if o != ignore and o.alive and not o.is_ward() and o.pos.distance_to(q) < o.hull + 20.0:
				return true
		d += step
	return false

# ---- Fights ------------------------------------------------------------------------------------------------------------

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	match b.kit:
		"airah":
			_airah(b, h, e)
		"burak":
			_burak(b, h, e)
		"emelrich":
			_emelrich(b, h, e)
		"feran":
			_feran(b, h, e)
		"ghorman":
			_ghorman(b, h, e)

static func _airah(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := _fight_on(b, h, e)
	# Hurricane: two or more enemies, or one that cannot walk out, within her reach
	if on and d < ab.cast_range(h, "hurricane", -1) + 150.0:
		var c := _lead(b, e, 0.4)
		var n := _foes_near(b, c, ab.val(h, "hurricane", "radius"))
		if (n >= 2 or e.is_stunned() or e.is_rooted() or e.hp < e.max_hp * 0.4) and _cast_point(b, h, "hurricane", c, 0.6):
			b.say("Hold on to something.", "hurricane_%d" % h.id, 40.0)
			return
	# Tailwind: an ally in trouble (slowed, low, or chased), or herself when a melee hero is on her
	var save: SimUnit = null
	for a in b._allies:
		if not a.alive or a.pos.distance_to(h.pos) > ab.cast_range(h, "tailwind", -1, a) + 100.0:
			continue
		var trouble := a.hp < a.max_hp * 0.35 or a.move_speed < float(a.def.move_speed) * 0.7
		if trouble and (save == null or a.hp < save.hp):
			save = a
	if save == null and h.edge_distance(e) < 250.0 and not e.is_ranged():
		save = h
	if save != null and _cast_unit(b, h, "tailwind", save, 0.3):
		return
	# the Wind Wall: a ranged enemy hero shooting at her or a nearby ally
	if e.is_ranged() and d < 1000.0:
		var guard: SimUnit = h
		for a in b._allies:
			if a.alive and e.atk_target == a.id:
				guard = a
		if e.atk_target == guard.id or d < 700.0:
			var wp := guard.pos + (e.pos - guard.pos).normalized() * minf(250.0, guard.pos.distance_to(e.pos) * 0.4)
			if h.pos.distance_to(wp) < ab.cast_range(h, "wind_wall", -1) + 50.0 and _cast_point(b, h, "wind_wall", wp, 0.4):
				return
	# Gust: through the target (leading it); best when it stands in front of a wall
	if d < ab.val(h, "gust", "distance") - 100.0 and ab.cast_error(h, "gust", -1, null, e.pos) == "":
		var aim := _lead(b, e, 0.25 + d / 1600.0)
		var dir := (aim - h.pos).normalized() if aim.distance_to(h.pos) > 1.0 else Vector2.from_angle(h.facing)
		if on or e.hp < e.max_hp * 0.5 or _wall_behind(w, e.pos, dir, 250.0, e):
			_cast_point(b, h, "gust", h.pos + dir * ab.val(h, "gust", "distance"), 0.5)

static func _burak(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var k5 := ab.kits5
	var d := h.edge_distance(e)
	var on := _fight_on(b, h, e)
	# Berserk when a fight starts, not when it is losing
	if on and d < 500.0 and b._threat < 1.3 and h.hp > h.max_hp * 0.4 and _cast_none(b, h, "berserk", 0.3):
		b.say("RAAAH!", "berserk_%d" % h.id, 40.0)
		return
	# the leap to an axe stuck in a hero (tick does it too)
	if _leap(b, h):
		return
	# Axe Throw at a hero it can follow up on
	if not k5.axe_recast_ready(h) and d > 200.0 and d < ab.val(h, "axe_throw", "distance") - 150.0 and (on or d < 400.0):
		var aim := _lead(b, e, h.pos.distance_to(e.pos) / maxf(1.0, ab.val(h, "axe_throw", "speed")) + 0.3)
		if _cast_point(b, h, "axe_throw", aim, 0.4):
			return
	# Reckless Swing with a hero in reach
	if d < h.attack_range + 120.0 and h.hp > h.max_hp * 0.3 and _cast_none(b, h, "reckless_swing", 0.2):
		return

## Burak leaps to his axe when it hit a hero and the fight there is in his favour, or the hero is low.
static func _leap(b: SimBot, h: SimUnit) -> bool:
	var k5 := b.w.abilities.kits5
	if not k5.axe_recast_ready(h) or h.is_rooted():
		return false
	var a := k5.leap_axe(h)
	var on := b.w.get_unit(int(a.get("on", -1)))
	if on == null or not on.alive or not on.is_hero() or on.team == h.team:
		return false
	var favour := b._threat < 1.0 or on.hp < on.max_hp * 0.4 or _allies_near(b, h, on.pos, 1000.0) > 0
	if not favour or h.hp < h.max_hp * 0.35:
		return false
	if _foes_near(b, on.pos, 900.0) > 1 + _allies_near(b, h, on.pos, 1100.0):
		return false
	return _cast_none(b, h, "axe_throw", 0.4)

static func _emelrich(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.edge_distance(e)
	var on := _fight_on(b, h, e)
	# Giant Swing: a cone 700 long; on a pinned target or several enemies in it
	var gs_w := ab.val(h, "giant_swing", "windup") + ab.cast_point("giant_swing", -1)
	if on and h.pos.distance_to(e.pos) < ab.val(h, "giant_swing", "distance") - 80.0 \
			and ab.cast_error(h, "giant_swing", -1, null, e.pos) == "":
		var n := 0
		var dir := (e.pos - h.pos).normalized()
		for f in b._foes:
			if f.alive and SimKits5.in_cone(h.pos, dir, ab.val(h, "giant_swing", "distance") - 60.0,
					deg_to_rad(ab.val(h, "giant_swing", "angle")) * 0.4, f.pos, f.hull):
				n += 1
		if (n >= 2 or _pinned(b, e, gs_w)) and _cast_point(b, h, "giant_swing", e.pos, gs_w + 0.2):
			b.say("Stand still.", "swing_%d" % h.id, 40.0)
			return
	# Overhead Cut: a line 450 long
	var oc_w := ab.val(h, "overhead_cut", "windup") + ab.cast_point("overhead_cut", -1)
	if h.pos.distance_to(e.pos) < ab.val(h, "overhead_cut", "distance") + 30.0 and _pinned(b, e, oc_w) \
			and _cast_point(b, h, "overhead_cut", e.pos, oc_w + 0.2):
		return
	# Sweep: enemies in the half circle in front
	if d < ab.val(h, "sweep", "radius") - 40.0 and absf(angle_difference(h.facing, (e.pos - h.pos).angle())) < 1.2:
		var left := Vector2.from_angle(h.facing + PI * 0.5)
		if on or _wall_behind(w, e.pos, left, ab.val(h, "sweep", "shove"), e) or _foes_near(b, h.pos, 320.0) >= 2:
			if _cast_none(b, h, "sweep", 0.4):
				return

static func _feran(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := _fight_on(b, h, e)
	# Shuffle: three or more enemies (heroes count most) and his team is there
	if on and d < ab.cast_range(h, "shuffle", -1) + 200.0:
		var c := _lead(b, e, 0.5)
		var r := ab.val(h, "shuffle", "radius")
		var heroes := _foes_near(b, c, r)
		var creeps := 0
		for o: SimUnit in w.query(c, r):
			if o.alive and o.team != h.team and o.is_creep():
				creeps += 1
		# three or more enemies (creeps count; a hero among them), with his team there or the target low
		var ready := _allies_near(b, h, c, 1400.0) > 0 or e.hp < e.max_hp * 0.4
		if heroes >= 1 and heroes + creeps >= 3 and (heroes >= 2 or creeps >= 3) and ready \
				and _cast_point(b, h, "shuffle", c, 0.7):
			b.say("Everybody move!", "shuffle_%d" % h.id, 40.0)
			return
	# Swap: an ally stunned in danger comes out (Feran takes its place only when healthy)
	for a in b._allies:
		if a.alive and (a.is_stunned() or a.is_rooted()) and a.hp < a.max_hp * 0.4 and h.hp > h.max_hp * 0.6 \
				and _foes_near(b, a.pos, 600.0) > 0 and _cast_unit(b, h, "swap", a, 0.4):
			return
	# Swap: a fleeing enemy into his allies (his team is behind him)
	if on and e.moving and d > 400.0 and _allies_near(b, h, h.pos, 700.0) > 0 and e.hp < e.max_hp * 0.6 \
			and _foes_near(b, h.pos, 700.0) == 0 and _cast_unit(b, h, "swap", e, 0.4):
		b.say("Come here.", "swap_%d" % h.id, 30.0)
		return
	# Joke Box: on a group, or a fleeing hero
	var jb := _lead(b, e, ab.val(h, "joke_box", "fuse") * 0.6 + ab.val(h, "joke_box", "throw_time"))
	if h.pos.distance_to(jb) < ab.cast_range(h, "joke_box", -1) + 50.0 \
			and (on or _foes_near(b, e.pos, 400.0) >= 2 or e.moving) and _cast_point(b, h, "joke_box", jb, 0.5):
		return
	# Knife Juggle at point blank: more knives hit
	if d < 450.0 and _cast_point(b, h, "knife_juggle", e.pos, 0.4):
		return

static func _ghorman(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var k6 := ab.kits6
	var d := h.edge_distance(e)
	var on := _fight_on(b, h, e)
	if on and d < 600.0 and (b._threat < 1.4 or _allies_near(b, h, h.pos, 1200.0) > 0) \
			and _cast_none(b, h, "beast_form", 0.5):
		b.say("The beast is out.", "form_%d" % h.id, 40.0)
		return
	if d < ab.val(h, "roar", "radius") - 60.0 and (on or h.hp < h.max_hp * 0.5) and _cast_none(b, h, "roar", 0.4):
		return
	# Blessing on his most hurt beast in the fight
	var worst: SimUnit = null
	for bst: SimUnit in k6.beasts_of(h):
		if bst.hp < bst.max_hp * 0.45 and bst.pos.distance_to(h.pos) < 650.0 and (worst == null or bst.hp < worst.hp):
			worst = bst
	if worst != null and _cast_unit(b, h, "blessing_of_the_beast_king", worst, 0.3):
		return

# ---- Running -------------------------------------------------------------------------------------------------------------

static func escape(b: SimBot, h: SimUnit, fd: float) -> bool:
	if not b._spells_ok():
		return false
	var ab := b.w.abilities
	var chaser: SimUnit = null
	for f in b._foes:
		if f.alive and (chaser == null or f.pos.distance_to(h.pos) < chaser.pos.distance_to(h.pos)):
			chaser = f
	match b.kit:
		"airah":
			if fd < 700.0 and _cast_unit(b, h, "tailwind", h, 0.2):
				return true
			if chaser != null and chaser.is_ranged() and fd < 800.0:
				var wp := h.pos + (chaser.pos - h.pos).normalized() * 200.0
				if _cast_point(b, h, "wind_wall", wp, 0.3):
					return true
			if chaser != null and fd < 500.0:
				var away := (h.pos - chaser.pos).normalized()
				# a Gust drags the chaser along away from her... aimed back at it, it slows its walk toward her
				if _cast_point(b, h, "gust", h.pos - away * 900.0, 0.3):
					return true
		"burak":
			if h.hp < h.max_hp * 0.3 and chaser != null and fd < 400.0 and _cast_none(b, h, "reckless_swing", 0.1):
				return false                               # the lifesteal while it still hits back
		"emelrich":
			if chaser != null and fd < 300.0 and _cast_none(b, h, "sweep", 0.3):
				return true
		"feran":
			# swap with an ally further from danger
			if fd < 600.0 and h.hp < h.max_hp * 0.35:
				var best: SimUnit = null
				for a in b._allies:
					if a.alive and a.hp > a.max_hp * 0.6 and a.pos.distance_to(h.pos) > 500.0 \
							and (best == null or a.pos.distance_to(chaser.pos if chaser else h.pos) > best.pos.distance_to(chaser.pos if chaser else h.pos)):
						best = a
				if best != null and _cast_unit(b, h, "swap", best, 0.3):
					return true
			if chaser != null and fd < 500.0 and _cast_point(b, h, "joke_box", chaser.pos, 0.3):
				return true
		"ghorman":
			if fd < 450.0 and _cast_none(b, h, "roar", 0.3):
				return true
	return false

# ---- Farming -------------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], centre: Vector2) -> bool:
	if not b._spells_ok() or ns.is_empty():
		return false
	var ab := b.w.abilities
	var mid := Vector2.ZERO
	for n in ns:
		mid += n.pos
	mid /= ns.size()
	var close := 0
	for n in ns:
		if n.pos.distance_to(h.pos) < 350.0:
			close += 1
	match b.kit:
		"burak":
			if close >= 2 and h.mana > h.max_mana * 0.4 and _cast_none(b, h, "reckless_swing", 0.2):
				return true
		"emelrich":
			if close >= 3 and h.mana > h.max_mana * 0.55 and absf(angle_difference(h.facing, (mid - h.pos).angle())) < 1.0 \
					and _cast_none(b, h, "sweep", 0.4):
				return true
		"feran":
			if ns.size() >= 3 and h.mana > h.max_mana * 0.6 and h.pos.distance_to(mid) < 500.0 \
					and _cast_point(b, h, "knife_juggle", mid, 0.4):
				return true
		"airah":
			if ns.size() >= 3 and h.mana > h.max_mana * 0.65 and h.pos.distance_to(mid) < 700.0 \
					and _cast_point(b, h, "gust", h.pos + (mid - h.pos).normalized() * 900.0, 0.4):
				return true
		"ghorman":
			if _tame_from(b, h, ns):
				return true
	return false

# ---- Every think -----------------------------------------------------------------------------------------------------------

## True when it gave an order that should stand this think.
static func tick(b: SimBot, h: SimUnit) -> bool:
	if not handles(b.kit) or not b._spells_ok():
		return false
	match b.kit:
		"burak":
			if b.mode in ["fight", "lane", "task"] and _leap(b, h):
				return true
		"emelrich":
			_stance(b, h)
		"ghorman":
			return _ghorman_tick(b, h)
	return false

## Every bot (whatever its hero) that stands where an enemy Ser Emelrich's wind-up will land (Giant Swing's cone,
## Overhead Cut's line) and sees him steps out of it, after its reaction time: the red marks are there to be dodged.
## Returns true while it is getting out (nothing else this think).
static func dodge_windups(b: SimBot, h: SimUnit) -> bool:
	if b._foes.is_empty() or h.is_stunned() or not h.channel.is_empty():
		return false
	var ab := b.w.abilities
	for f: SimUnit in b._foes:
		if f.channel.is_empty() or not bool(f.channel.get("locked", false)):
			continue
		var aid := String(f.channel.ability)
		if not aid in SimKits5.WINDUPS:
			continue
		var left := float(f.channel.until) - b.w.time
		var spent := ab.val(f, aid, "windup") - left
		if left < 0.12 or spent < float(b.sk.react) * 0.6:
			continue
		var aim: Vector2 = f.channel.aim
		var from: Vector2 = f.channel.get("from", f.pos)
		if not _in_windup(ab, f, aid, from, aim, h.pos, h.hull + 40.0):
			continue
		# out to the side it is already on, else straight back out of reach; the nearest open spot wins
		var rel := h.pos - from
		var side := aim.orthogonal() * (1.0 if rel.dot(aim.orthogonal()) >= 0.0 else -1.0)
		var best := Vector2.INF
		for d: Vector2 in [side, (side + aim * 0.5).normalized(), (side - aim * 0.3).normalized(), aim, -side]:
			for step in [250.0, 400.0, 600.0]:
				var p: Vector2 = h.pos + d * step
				if b.w.map.is_walkable(p) and not _in_windup(ab, f, aid, from, aim, p, h.hull + 60.0):
					if best == Vector2.INF or p.distance_to(h.pos) < best.distance_to(h.pos):
						best = p
					break
		if best != Vector2.INF:
			b._order(h, {"type": O.MOVE, "point": best})
			return true
	return false

## Whether a circle at `p` of radius `r` is inside the area a wind-up will strike.
static func _in_windup(ab: SimAbilities, f: SimUnit, aid: String, from: Vector2, aim: Vector2, p: Vector2, r: float) -> bool:
	var dist := ab.val(f, aid, "distance")
	if aid == "giant_swing":
		return SimKits5.in_cone(from, aim, dist, deg_to_rad(ab.val(f, aid, "angle")) * 0.5, p, r)
	var to := from + aim * (dist + f.hull)
	var cp := Geometry2D.get_closest_point_to_segment(p, from, to)
	return cp.distance_to(p) <= ab.val(f, aid, "width") * 0.5 + r

## Steel Stance on when a ranged or line-shot hero stands in front of him and he is not chasing; off to move.
static func _stance(b: SimBot, h: SimUnit) -> void:
	var ab := b.w.abilities
	if h.ability_level_of("steel_stance") <= 0 or ab.cooldown_left(h, "steel_stance") > 0.0:
		return
	var on := bool(h.toggles.get("steel_stance", false))
	var want := false
	if b.mode == "fight" or b.mode == "lane":
		for f in b._foes:
			if not f.alive or f.pos.distance_to(h.pos) > 900.0:
				continue
			var front := absf(angle_difference(h.facing, (f.pos - h.pos).angle())) < deg_to_rad(60.0)
			if front and f.is_ranged():
				want = true
	if b.mode == "retreat":
		want = false
	# chasing: the 20% slow costs too much
	var t := b.w.get_unit(h.order_target)
	if want and t != null and t.is_hero() and t.moving and h.edge_distance(t) > h.attack_range + 50.0:
		want = false
	if want != on:
		_cast_none(b, h, "steel_stance", 0.05)

## Ghorman: tame whenever he has room (a camp creep with a spell first), and Bless a hurt beast.
static func _ghorman_tick(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var ab := w.abilities
	# a badly hurt beast near him gets the Blessing (in the jungle too), while mana allows
	if h.mana > ab.ability_mana(h, "blessing_of_the_beast_king") + ab.ability_mana(h, "roar"):
		for bst: SimUnit in ab.kits6.beasts_of(h):
			if bst.hp < bst.max_hp * 0.35 and bst.pos.distance_to(h.pos) < 600.0 \
					and _cast_unit(b, h, "blessing_of_the_beast_king", bst, 0.3):
				return true
	if ab.cast_error(h, "tame", -1, null, h.pos, false, false) != "" or b.mode == "retreat":
		return false
	var cap := int(ab.val(h, "tame", "max_beasts"))
	var have := ab.kits6.beasts_of(h).size()
	if have >= cap:
		return false
	var cands: Array[SimUnit] = []
	for o: SimUnit in w.query(h.pos, 1000.0):
		if o.alive and (o.kind == K.NEUTRAL_CREEP or (o.is_lane_creep() and o.team != h.team)) and w.vision.sees(h.team, o):
			cands.append(o)
	return _tame_from(b, h, cands)

static func _tame_from(b: SimBot, h: SimUnit, cands: Array[SimUnit]) -> bool:
	var ab := b.w.abilities
	if ab.cast_error(h, "tame", -1, null, h.pos, false, false) != "":
		return false
	if ab.kits6.beasts_of(h).size() >= int(ab.val(h, "tame", "max_beasts")):
		return false
	var best: SimUnit = null
	var best_key := -INF
	for o in cands:
		if ab.kits6.tame_error(h, o) != "":
			continue
		var key := o.max_hp * (1.0 + 0.3 * o.abilities.size()) - o.pos.distance_to(h.pos) * 0.5
		if o.kind == K.NEUTRAL_CREEP:
			key += 300.0
		if key > best_key:
			best_key = key
			best = o
	if best == null:
		return false
	if _cast_unit(b, h, "tame", best, 0.5):
		b.botlog.add(b.w.time, "think", "tame %s" % String(best.def.id))
		return true
	return false
