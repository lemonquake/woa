class_name SimBot17
extends RefCounted
## How bots play Azrael (2026-10-17): aggressive, the way a good player does. Called by SimBot: spells() in fights and
## trades, escape() while running, aoe_farm() on creep packs, tick() every think (her door and every bot's use of an
## allied door). All static: `b` is the SimBot whose hero acts.
##
## Fights: Divine Darkness first when a real fight is on (she flies over the trees after the target and blinds it),
## Soul Tap placed where it gathers the most souls with the target's among them, then the charged slash; Door of the
## End to dive: the door at her feet, she steps in, and the exit goes on the enemy at the last moment so the blast lands
## where it stands. Running: a door at her feet hides her (invulnerable) and the exit takes her toward safety; the wings
## carry her over cliffs. Allies: a hurt allied bot walks into her open door. Farming: Soul Tap on a pack, then the
## slash cleaves it all.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

static func handles(kit: String) -> bool:
	return kit == "azrael"

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

static func _allies_near(b: SimBot, h: SimUnit, p: Vector2, r: float) -> int:
	var n := 0
	for a in b._allies:
		if a != h and a.alive and a.pos.distance_to(p) < r:
			n += 1
	return n

static func _foes_near(b: SimBot, p: Vector2, r: float) -> int:
	var n := 0
	for f in b._foes:
		if f.alive and f.pos.distance_to(p) < r:
			n += 1
	return n

## A fight worth committing to (she is bold: lower bars than the shared fight logic).
static func _fight_on(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	return e.hp < e.max_hp * 0.7 or _allies_near(b, h, e.pos, 1200.0) > 0 or h.hp > h.max_hp * 0.55

# ---- Fights ------------------------------------------------------------------------------------------------------------

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var k4 := ab.kits4
	if k4.in_door(h):
		return
	var d := h.pos.distance_to(e.pos)
	var on := _fight_on(b, h, e)
	# the wings: a real fight within reach, or a target running over ground she cannot walk
	var worth := e.hp < e.max_hp * 0.75 or _allies_near(b, h, e.pos, 1200.0) > 0
	if on and worth and d < 1100.0 and h.hp > h.max_hp * 0.25 and _cast_none(b, h, "divine_darkness", 0.5):
		b.say("No escape from me.", "dd_%d" % h.id, 40.0)
		return
	# Soul Tap: where it gathers the most souls, the target's among them, then the charged slash on the target
	if not k4.soul_charged(h) and d < 900.0 and _soul_tap(b, h, e, false):
		return
	# Door of the End to dive on a target out of reach (the exit is placed at the last moment, see tick): only once the
	# door is short enough (level 3: 5 s) and the target is in sight within the exit's reach; early on it is her escape
	var dive_ok := h.ability_level_of("door_of_the_end") >= 3 and w.vision.sees(h.team, e) \
		and d < ab.val(h, "door_of_the_end", "exit_range") - 50.0
	if on and dive_ok and d > 450.0 and not k4.exit_pending(h) and h.hp > h.max_hp * 0.6 \
			and _cast_point(b, h, "door_of_the_end", h.pos + (e.pos - h.pos).normalized() * 60.0, 0.4):
		b.say("Opening the door.", "door_%d" % h.id, 30.0)
		return

## The best Soul Tap centre near `focus` (in cast range): the most souls (heroes count double for the score), the
## focus inside when given. True when it was cast.
static func _soul_tap(b: SimBot, h: SimUnit, focus: SimUnit, farm: bool) -> bool:
	var w := b.w
	var ab := w.abilities
	if ab.cast_error(h, "soul_tap", -1, null, h.pos) != "":
		return false
	var r := ab.val(h, "soul_tap", "radius")
	var rng := ab.cast_range(h, "soul_tap", -1)
	var cands: Array = []
	var anchor: Vector2 = focus.pos if focus != null else h.pos
	cands.append(anchor)
	for o: SimUnit in w.query(anchor, r * 1.6, true):
		if o.alive and not o.is_building() and o != h:
			cands.append(anchor.lerp(o.pos, 0.5))
	var best := Vector2.INF
	var best_s := 0.0
	var best_n := 0
	for c: Vector2 in cands:
		if h.pos.distance_to(c) > rng + 150.0:
			continue
		var souls := ab.kits4.souls_at(h, c, r)
		if focus != null and not (focus in souls):
			continue
		var s := 0.0
		for o in souls:
			s += 2.0 if o.is_hero() else 1.0
		if s > best_s:
			best_s = s
			best = c
			best_n = souls.size()
	var need := 4 if farm else 2
	if best == Vector2.INF or best_n < need:
		return false
	return _cast_point(b, h, "soul_tap", best, 0.4)

# ---- Running -------------------------------------------------------------------------------------------------------------

static func escape(b: SimBot, h: SimUnit, fd: float) -> bool:
	if not b._spells_ok():
		return false
	var ab := b.w.abilities
	if ab.kits4.in_door(h):
		return true
	# a door at her feet: hidden and unharmed while the chasers wait, the exit toward safety (tick)
	if fd < 700.0 and h.hp < h.max_hp * 0.4 and not ab.kits4.exit_pending(h) \
			and _cast_point(b, h, "door_of_the_end", h.pos + Vector2.from_angle(h.facing) * 40.0, 0.3):
		b.say("Into the door.", "door_run_%d" % h.id, 30.0)
		return true
	# the wings: over the cliffs and trees, away
	if fd < 800.0 and h.hp < h.max_hp * 0.35 and _cast_none(b, h, "divine_darkness", 0.3):
		return true
	return false

# ---- Farming -------------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], _centre: Vector2) -> bool:
	if not b._spells_ok() or ns.size() < 4 or h.mana < h.max_mana * 0.45:
		return false
	if b.w.abilities.kits4.soul_charged(h):
		return false
	var near: SimUnit = null
	for n in ns:
		if near == null or n.pos.distance_to(h.pos) < near.pos.distance_to(h.pos):
			near = n
	return near != null and _soul_tap(b, h, near, true)

# ---- Every think -----------------------------------------------------------------------------------------------------------

## Her door (stepping in, placing the exit at the last moment) and every bot's use of an allied door. True when it gave
## an order that should stand this think.
static func tick(b: SimBot, h: SimUnit) -> bool:
	var w := b.w
	var k4 := w.abilities.kits4
	if b.kit == "azrael":
		var door := _own_door(w, h)
		if not door.is_empty():
			if k4.in_door(h):
				# the exit at the last moment (the cast takes 0.3 s); never re-ordered while it is being cast
				var casting := h.order == O.CAST_POINT and h.order_ability == "door_of_the_end"
				if k4.exit_pending(h) and not casting and w.time >= float(door.until) - 0.9:
					_place_exit(b, h, door)
				return true
			# walk into her own fresh door when she opened it to run or to dive
			if w.time < float(door.until) - 0.4 and h.pos.distance_to(door.pos) < 700.0:
				b._order(h, {"type": O.MOVE, "point": door.pos})
				return true
		# laning: Soul Tap on the enemy laner standing among creeps (three souls or more), keeping mana for the door
		if b.mode == "lane" and b._spells_ok() and not k4.soul_charged(h) and h.hp > h.max_hp * 0.5 \
				and h.mana >= w.abilities.ability_mana(h, "soul_tap") + w.abilities.ability_mana(h, "door_of_the_end") * 0.6:
			for f in b._foes:
				if f.alive and f.pos.distance_to(h.pos) < 650.0 and w.vision.sees(h.team, f):
					var under := false
					for t in b._etowers:
						if t.alive and f.pos.distance_to(t.pos) < t.attack_range + 150.0:
							under = true
					if not under and _soul_tap(b, h, f, false):
						return true
					break
		# the charged slash: go and spend it on a hero, or on the creeps it was gathered for
		if k4.soul_charged(h) and not b._foes.is_empty() and b.mode in ["lane", "fight", "task"]:
			var tgt: SimUnit = null
			for f in b._foes:
				# in lane only a hero close at hand is worth walking to; otherwise the charge cleaves the wave
				var reach := 250.0 + h.attack_range if b.mode == "lane" else 700.0
				if f.alive and h.edge_distance(f) < reach and (tgt == null or f.hp < tgt.hp):
					tgt = f
			if tgt != null and h.hp > h.max_hp * 0.35:
				b._order(h, {"type": O.ATTACK_UNIT, "target": tgt.id})
				return true
		return false
	# an ally: a hurt bot steps into an open allied door close by (hidden and safe until it opens elsewhere)
	if b.mode == "retreat" and not k4.in_door(h):
		var dd := k4.door_for(h)
		if not dd.is_empty() and w.time < float(dd.until) - 0.6 and h.pos.distance_to(dd.pos) < 650.0:
			var room := int(dd.allies)
			for id in dd.inside:
				if int(id) != int(dd.src):
					room -= 1
			if room > 0:
				b._order(h, {"type": O.MOVE, "point": dd.pos})
				return true
	return false

static func _own_door(w: SimWorld, h: SimUnit) -> Dictionary:
	for e in w.effects:
		if String(e.kind) == "azrael_door" and int(e.src) == h.id:
			return e
	return {}

## The exit: onto the weakest enemy hero within reach of the door when she is healthy enough to fight there,
## otherwise toward her fountain (as far as the exit reaches).
static func _place_exit(b: SimBot, h: SimUnit, door: Dictionary) -> void:
	var w := b.w
	var ab := w.abilities
	var reach := ab.val(h, "door_of_the_end", "exit_range") - 20.0
	var from: Vector2 = door.pos
	var spot := Vector2.INF
	if h.hp > h.max_hp * 0.4:
		var best: SimUnit = null
		for e in w.heroes:
			if e.team == h.team or not e.alive or not w.vision.sees(h.team, e) or e.pos.distance_to(from) > reach:
				continue
			if _foes_around(w, h.team, e.pos, 900.0) > 2 + _allies_around(w, h.team, e.pos, 1100.0):
				continue
			if best == null or e.hp < best.hp:
				best = e
		if best != null:
			spot = best.pos + (Vector2.from_angle(best.facing) * best.move_speed * 0.3 if best.moving else Vector2.ZERO)
	if spot == Vector2.INF:
		var home: Vector2 = w.map.fountains[h.team]
		spot = from + (home - from).normalized() * minf(reach, from.distance_to(home))
	if spot.distance_to(from) > reach:
		spot = from + (spot - from).normalized() * reach
	b._order(h, {"type": O.CAST_POINT, "ability": "door_of_the_end", "point": spot}, true)
	b._cast_deadline = w.time + 0.4
	b.botlog.add(w.time, "think", "door exit at (%d, %d)" % [int(spot.x), int(spot.y)])

static func _foes_around(w: SimWorld, team: int, p: Vector2, r: float) -> int:
	var n := 0
	for e in w.heroes:
		if e.team != team and e.alive and e.pos.distance_to(p) < r:
			n += 1
	return n

static func _allies_around(w: SimWorld, team: int, p: Vector2, r: float) -> int:
	var n := 0
	for e in w.heroes:
		if e.team == team and e.alive and e.pos.distance_to(p) < r:
			n += 1
	return n
