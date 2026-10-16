class_name SimBot16
extends RefCounted
## How bots play Roydo and Blau (run 2026-10-16), and what every bot does about Blau's turrets. Called by SimBot:
## spells() in fights and trades, escape() while running, aoe_farm() on creep packs, tick() every think (turrets,
## piloting). All static: `b` is the SimBot whose hero acts.
##
## Blau: Bounce Shot is aimed by tracing two dozen angles through the trees, walls, boulders and units around him and
## firing the one that passes enemy heroes most (twice when the bounces allow); boulders roll ahead of a fleeing target
## to wall it in, or into a melee hero on top of him; when chased he turns to face the chaser so Lay Trap's leap takes
## him away and leaves the snare in its path; turrets go down in every fight (between him and the target, within
## their 650) and in front of towers he pushes; with the Upgrade Staff he climbs into a turret when hurt and stays
## while it holds.
## Roydo: Void Rush first when enemy heroes are near (their status resistance drops, so the stun after lasts longer),
## then Grip of the Ruler with its middle between the target and him (the target is thrown to his side and the slam
## catches whoever stands near); Anomaly once a real fight is on; Void Rush's speed to run.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const KITS := ["roydo", "blau"]

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

## A fight worth committing to: the target is low, or friends are with us, or it is one on one and we are healthy.
static func _fight_on(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	return e.hp < e.max_hp * 0.6 or _allies_near(b, h, e.pos, 1100.0) > 0 or h.hp > h.max_hp * 0.7

# ---- Fights ------------------------------------------------------------------------------------------------------------

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	if b.kit == "blau":
		_blau(b, h, e)
	elif b.kit == "roydo":
		_roydo(b, h, e)

static func _roydo(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := _fight_on(b, h, e)
	# Anomaly: a real fight within reach (and not while running on empty)
	if on and d < 900.0 and h.hp > h.max_hp * 0.3 and _cast_none(b, h, "anomaly", 0.5):
		return
	# Void Rush before the grip: the enemies' lower status resistance makes the grip's stun last longer
	if d < ab.val(h, "void_rush", "radius") - 40.0 and (on or _foes_near(b, h.pos, 650.0) >= 2) \
			and ab.cooldown_left(h, "grip_of_the_ruler") <= 0.0 or (d < 500.0 and h.hp < h.max_hp * 0.5):
		if _cast_none(b, h, "void_rush", 0.5):
			return
	if ab.cast_error(h, "grip_of_the_ruler", -1, null, e.pos) == "" and not e.is_stunned() and e.knock.is_empty():
		var r := ab.val(h, "grip_of_the_ruler", "radius")
		var rng := ab.cast_range(h, "grip_of_the_ruler", -1)
		# the middle between him and the target: it lands on his side; never further out than the cast range
		var toward := (h.pos - e.pos).normalized() if d > 1.0 else Vector2.from_angle(h.facing)
		var c := e.pos + toward * minf(r * 0.85, maxf(0.0, d - 150.0))
		# more enemies in the area: aim at their middle (the slam hits them all, a hero is still picked first)
		var mid := Vector2.ZERO
		var n := 0
		for f in b._foes:
			if f.alive and f.pos.distance_to(e.pos) < r:
				mid += f.pos
				n += 1
		if n >= 2:
			c = (mid / n).lerp(c, 0.4)
		if c.distance_to(e.pos) > r - 20.0:
			c = e.pos + (c - e.pos).normalized() * (r - 20.0)
		if h.pos.distance_to(c) <= rng + 100.0 and _cast_point(b, h, "grip_of_the_ruler", c, 0.7):
			return

static func _blau(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := _fight_on(b, h, e)
	# a melee hero on top of him: trap-leap away (the snare is left at his feet, in its way), or boulders into it
	if not e.is_ranged() and h.edge_distance(e) < 200.0:
		if _trap_away(b, h, e):
			return
		if _cast_point(b, h, "summon_boulders", e.pos, 0.5):
			return
	# the turret: in every fight, between him and the target and within its reach of the target
	if on and d < 1000.0 and _place_turret(b, h, e.pos):
		return
	# the combo: boulders rolled round the target first, then the shot banks off them through it again and again
	if on and d < 650.0 and ab.cast_error(h, "summon_boulders", -1, null, e.pos) == "" 			and ab.cast_error(h, "bounce_shot", -1, null, e.pos) == "" and h.mana >= ab.ability_mana(h, "summon_boulders") 			+ ab.ability_mana(h, "bounce_shot"):
		if _cast_point(b, h, "summon_boulders", e.pos, 0.5):
			return
	# Bounce Shot: the best ricochet through the enemies around (boulders that are still rolling are waited for)
	var rolling := ab.kits3.boulders.any(func(x): return not bool(x.resting) and int(x.src) == h.id)
	if not rolling and ab.cast_error(h, "bounce_shot", -1, null, e.pos) == "" and d < 1300.0:
		var aim := best_bounce(b, h, e, false)
		if not aim.is_empty() and float(aim.score) >= 3.0 and _cast_point(b, h, "bounce_shot", aim.point, 0.45):
			return
	# boulders ahead of a target that runs (they wall it in for the shots), or at a pack of them
	if ab.cast_error(h, "summon_boulders", -1, null, e.pos) == "" and d < 750.0:
		var fleeing := e.moving and absf(angle_difference(e.facing, (e.pos - h.pos).angle())) < 1.0
		if (fleeing and e.hp < e.max_hp * 0.6) or _foes_near(b, e.pos, 350.0) >= 2:
			var lead := e.pos + (Vector2.from_angle(e.facing) * e.move_speed * 0.9 if e.moving else Vector2.ZERO)
			if _cast_point(b, h, "summon_boulders", lead, 0.5):
				return

## Blau turns to the chaser (an attack order turns him) and leaps back from it, leaving the trap in its path.
static func _trap_away(b: SimBot, h: SimUnit, chaser: SimUnit) -> bool:
	var ab := b.w.abilities
	if ab.cast_error(h, "lay_trap", -1, null, h.pos) != "":
		return false
	var want := (chaser.pos - h.pos).angle()
	if absf(angle_difference(h.facing, want)) < 0.45:
		return _cast_none(b, h, "lay_trap", 0.3)
	b._order(h, {"type": O.ATTACK_UNIT, "target": chaser.id}, true)
	return true

## A turret where it helps: near the target on Blau's side (it shoots 650), never deep under an enemy tower unless
## that tower is the target.
static func _place_turret(b: SimBot, h: SimUnit, target: Vector2, tower: SimUnit = null) -> bool:
	var w := b.w
	var ab := w.abilities
	if ab.cast_error(h, "place_turret", -1, null, h.pos) != "":
		return false
	var rng := ab.cast_range(h, "place_turret", -1)
	var back := (h.pos - target).normalized() if h.pos.distance_to(target) > 1.0 else Vector2.from_angle(h.facing + PI)
	var spot := target + back * (560.0 if tower != null else 420.0)
	if h.pos.distance_to(spot) > rng:
		spot = h.pos + (spot - h.pos).normalized() * (rng - 20.0)
	if not w.map.is_walkable(spot):
		var c := w.map.nearest_walkable(w.map.world_to_cell(spot))
		spot = w.map.cell_center(c.x, c.y)
	if tower == null:
		for t in b._etowers:
			if t.alive and t.pos.distance_to(spot) < 750.0:
				return false
	return _cast_point(b, h, "place_turret", spot, 0.8)

## The Bounce Shot direction that passes enemies most: {point, score} or {} ({} also while it is cached and stale).
## Heroes count 3 a pass (at most the bullet's hits), the focus target half again; creeps a little (more when farming).
static func best_bounce(b: SimBot, h: SimUnit, focus: SimUnit, farm: bool) -> Dictionary:
	var w := b.w
	var ab := w.abilities
	var k3 := ab.kits3
	var dist := ab.val(h, "bounce_shot", "distance")
	var bounces := int(ab.val(h, "bounce_shot", "bounces"))
	var max_hits := int(ab.val(h, "bounce_shot", "max_hits"))
	var start := h.pos
	var prep := k3.trace_prep(start, dist, h.team, h.id)
	if (prep.eid as PackedInt32Array).is_empty():
		return {}
	var score_of := func(tr: Dictionary) -> float:
		var sc := 0.0
		for id in tr.passed:
			var o := w.get_unit(int(id))
			if o == null or not w.vision.sees(h.team, o):
				continue
			var n := mini(int(tr.passed[id]), max_hits)
			if o.is_hero():
				sc += 3.0 * n * (1.5 if o == focus else 1.0)
			elif farm or o.is_creep():
				sc += (0.6 if farm else 0.15) * n
		return sc
	# 1. a coarse sweep (16 angles, half-precision steps) and straight at each enemy hero
	var coarse: Array = []
	for i in 16:
		coarse.append(Vector2.from_angle(TAU * i / 16.0))
	var exact: Array = []
	for f in b._foes:
		if f.alive and f.pos.distance_to(h.pos) < 1300.0:
			var a := (f.pos - h.pos).angle()
			for off in [-0.08, 0.0, 0.08]:
				exact.append(Vector2.from_angle(a + off))
	# 2. bank shots: off the boulders he placed and the trees near the enemies, aimed by solving the mirror point
	var mirrors: Array = []
	for bd in k3.boulders:
		if (bd.pos as Vector2).distance_to(h.pos) < 1000.0:
			mirrors.append([bd.pos, float(bd.r) + 7.0])
	for f in b._foes:
		if not f.alive or f.pos.distance_to(h.pos) > 1300.0:
			continue
		for m in mirrors:
			var sol := bank_dir(h.pos, f.pos, m[0], float(m[1]))
			if sol != Vector2.ZERO:
				exact.append(sol)
		for tp in _trees_near(w, f.pos, 520.0, 5):
			var sol2 := bank_dir(h.pos, f.pos, tp, 51.0)
			if sol2 != Vector2.ZERO:
				exact.append(sol2)
	var ranked: Array = []
	for dir: Vector2 in coarse:
		var trc := k3.trace_bullet(start + dir * (h.hull + 10.0), dir, h.team, dist, bounces, h.id, 40.0, prep)
		var sc: float = score_of.call(trc)
		if sc > 0.0:
			ranked.append([sc, dir])
	ranked.sort_custom(func(x, y): return x[0] > y[0])
	for k in mini(3, ranked.size()):
		exact.append(ranked[k][1])
	# 3. the candidates traced at the bullet's own precision; the best one wins
	var best := {}
	var best_score := 0.0
	for dir: Vector2 in exact:
		var tr := k3.trace_bullet(start + dir * (h.hull + 10.0), dir, h.team, dist, bounces, h.id, SimKits3.SUBSTEP, prep)
		var score: float = score_of.call(tr)
		if score > best_score:
			best_score = score
			best = {"point": h.pos + dir * 600.0, "score": score}
	return best

## The direction to fire from `from` so the bullet glances off a round obstacle (centre `c`, contact radius `r`) and
## flies on through `to`: the contact angle is scanned, then refined. ZERO when no glance comes within 18 of `to`.
static func bank_dir(from: Vector2, to: Vector2, c: Vector2, r: float) -> Vector2:
	var best_phi := 0.0
	var best_miss := INF
	var lo := 0.0
	var span := TAU
	for pass_i in 2:
		var n := 72 if pass_i == 0 else 24
		for k in n:
			var phi := lo + span * float(k) / float(n)
			var nrm := Vector2.from_angle(phi)
			var p := c + nrm * r
			var inc := p - from
			if inc.length() < 1.0 or inc.dot(nrm) >= 0.0:
				continue                              # that side of it cannot be reached from here
			inc = inc.normalized()
			var out := SimKits3.reflect(inc, nrm)
			var to_t := to - p
			var along := to_t.dot(out)
			if along <= 0.0:
				continue
			var miss := (to_t - out * along).length()
			if miss < best_miss:
				best_miss = miss
				best_phi = phi
		lo = best_phi - TAU / 72.0
		span = TAU / 36.0
	if best_miss > 18.0:
		return Vector2.ZERO
	return ((c + Vector2.from_angle(best_phi) * r) - from).normalized()

## Up to `n` living trees within `r` of `p`, nearest first.
static func _trees_near(w: SimWorld, p: Vector2, r: float, n: int) -> Array:
	var out: Array = []
	var c0 := w.map.world_to_cell(p - Vector2(r, r))
	var c1 := w.map.world_to_cell(p + Vector2(r, r))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if cx < 0 or cy < 0 or cx >= SimMap.N or cy >= SimMap.N:
				continue
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti >= 0 and w.map.trees[ti].alive and (w.map.trees[ti].pos as Vector2).distance_to(p) <= r:
				out.append(w.map.trees[ti].pos)
	out.sort_custom(func(a, b2): return (a as Vector2).distance_to(p) < (b2 as Vector2).distance_to(p))
	return out.slice(0, n)

# ---- Running -------------------------------------------------------------------------------------------------------------

static func escape(b: SimBot, h: SimUnit, fd: float) -> bool:
	if not b._spells_ok():
		return false
	var chaser: SimUnit = null
	for f in b._foes:
		if f.alive and (chaser == null or f.pos.distance_to(h.pos) < chaser.pos.distance_to(h.pos)):
			chaser = f
	match b.kit:
		"blau":
			# facing the chaser, the leap back takes him toward safety and leaves the snare in its way (ranged
			# chasers too: it is 400 of distance either way)
			if chaser != null and (fd < 600.0 or (fd < 900.0 and h.hp < h.max_hp * 0.35)) and _trap_away(b, h, chaser):
				return true
			# boulders between him and the chaser block its way (phased or not)
			if chaser != null and fd < 600.0 and _cast_point(b, h, "summon_boulders", chaser.pos, 0.4):
				return true
		"roydo":
			if fd < 700.0 and _cast_none(b, h, "void_rush", 0.3):
				return true
	return false

# ---- Farming -------------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], _centre: Vector2) -> bool:
	if not b._spells_ok() or ns.size() < 3:
		return false
	var w := b.w
	var ab := w.abilities
	match b.kit:
		"blau":
			if h.mana > h.max_mana * 0.55 and ab.cast_error(h, "bounce_shot", -1, null, h.pos) == "":
				var aim := best_bounce(b, h, null, true)
				if not aim.is_empty() and float(aim.score) >= 2.4 and _cast_point(b, h, "bounce_shot", aim.point, 0.45):
					return true
		"roydo":
			var mid := Vector2.ZERO
			for n in ns:
				mid += n.pos
			mid /= ns.size()
			if ns.size() >= 4 and h.mana > h.max_mana * 0.65 and h.pos.distance_to(mid) < 650.0 \
					and _cast_point(b, h, "grip_of_the_ruler", mid, 0.7):
				return true
	return false

# ---- Every think -----------------------------------------------------------------------------------------------------------

## Turret matters (every bot) and Blau's piloting. True when it gave an order that should stand this think.
static func tick(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var k3 := w.abilities.kits3
	if b.kit == "blau" and bool(b.sk.spells):
		if k3.is_piloting(h):
			return _inside(b, h)
		if _climb_in(b, h):
			return true
		# laning: Bounce Shot is his poke (the shared lane logic waits for 60% mana, more than his small pool has)
		if b.mode == "lane" and _lane_poke(b, h):
			return true
		# pushing a tower: a turret in front of it
		if b.mode == "task" and not b._etowers.is_empty() and b._foes.is_empty():
			var t: SimUnit = b._etowers[0]
			if t.alive and not t.is_invulnerable() and t.pos.distance_to(h.pos) < 1200.0 \
					and _place_turret(b, h, t.pos, t):
				return true
	# an enemy turret close and no enemy hero to fight: knock it down (it shoots, and it pays)
	if b.mode in ["lane", "farm", "task"] and h.hp > h.max_hp * 0.4:
		var best: SimUnit = null
		for u: SimUnit in w.query(h.pos, 900.0, true):
			if k3.is_turret(u) and u.alive and u.team != h.team and w.vision.sees(h.team, u):
				if best == null or u.hp < best.hp:
					best = u
		if best != null and b._foes.filter(func(f): return f.pos.distance_to(h.pos) < 900.0).is_empty():
			b._order(h, {"type": O.ATTACK_UNIT, "target": best.id})
			return true
	return false

## A ricochet into the enemy laner whenever one is found (re-aimed every second), keeping mana for Lay Trap.
static func _lane_poke(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var ab := w.abilities
	if not b._spells_ok() or w.time < b.poke_at:
		return false
	# never at the cost of a last hit, and not while losing the lane
	if b._creep_low or h.hp < h.max_hp * 0.5:
		return false
	if ab.cast_error(h, "bounce_shot", -1, null, h.pos) != "":
		return false
	var reserve := ab.ability_mana(h, "lay_trap") if h.ability_level_of("lay_trap") > 0 else 0.0
	if h.mana < ab.ability_mana(h, "bounce_shot") + reserve:
		return false
	var target: SimUnit = null
	for f in b._foes:
		if f.alive and f.pos.distance_to(h.pos) < 1150.0 and w.vision.sees(h.team, f):
			target = f
	if target == null:
		return false
	b.poke_at = w.time + 1.0
	var aim := best_bounce(b, h, target, false)
	if aim.is_empty() or float(aim.score) < 3.0:
		return false
	return _cast_point(b, h, "bounce_shot", aim.point, 0.45)

## Blau climbs into a nearby turret of his when hurt with enemies about (Upgrade Staff).
static func _climb_in(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var ab := w.abilities
	if not h.has_scepter() or h.ability_level_of("pilot_turret") <= 0 or ab.cooldown_left(h, "pilot_turret") > 0.0:
		return false
	if h.hp > h.max_hp * 0.45 or b._foes.filter(func(f): return f.pos.distance_to(h.pos) < 900.0).is_empty():
		return false
	var best: SimUnit = null
	for u: SimUnit in w.query(h.pos, 450.0, true):
		if ab.kits3.is_turret(u) and u.alive and u.owner_id == h.id and u.hp > u.max_hp * 0.35:
			if best == null or u.hp > best.hp:
				best = u
	if best == null or ab.cast_error(h, "pilot_turret", -1, best, best.pos) != "":
		return false
	b._order(h, {"type": O.CAST_UNIT, "ability": "pilot_turret", "target": best.id}, true)
	b._cast_deadline = w.time + 1.2
	b.say("Into the turret.", "pilot_%d" % h.id, 30.0)
	return true

## Inside a turret: shoot the weakest enemy in reach; get out when the turret is about to fall or the fight is over.
static func _inside(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var k3 := w.abilities.kits3
	var t := k3.piloted_turret(h)
	var foes := b._foes.filter(func(f): return f.alive and f.pos.distance_to(h.pos) < 1200.0)
	if t == null or t.hp < t.max_hp * 0.22 or foes.is_empty() or w.time >= t.ward_expires - 1.0:
		k3.leave_turret(h)
		return false
	var best: SimUnit = null
	for f in foes:
		if h.edge_distance(f) <= h.attack_range and (best == null or f.hp < best.hp):
			best = f
	if best != null:
		b._order(h, {"type": O.ATTACK_UNIT, "target": best.id})
	elif not (b._ecreeps as Array).is_empty():
		var c: SimUnit = null
		for e in b._ecreeps:
			if h.edge_distance(e) <= h.attack_range and (c == null or e.hp < c.hp):
				c = e
		if c != null:
			b._order(h, {"type": O.ATTACK_UNIT, "target": c.id})
	return true
