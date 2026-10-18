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

## Toggle Soul Tap on when enough souls are within 600 of Azrael.
static func _soul_tap(b: SimBot, h: SimUnit, _focus: SimUnit, _farm: bool) -> bool:
	if h.ability_level_of("soul_tap") <= 0 or bool(h.toggles.get("soul_tap", false)):
		return false
	if soul_want(b, h) == "":
		return false
	return _cast_none(b, h, "soul_tap", 0.0)

# ---- Soul Tap planner (run 2026-10-18 h) ---------------------------------------------------------------------------------
# The owner: her bot "doesn't know how her 1st skill works", leaving it on to spend 80 mana a scan on one creep or on an
# ally walking past. The toggle scans every 4.5 s and spends its mana whenever anything (ally or enemy) stands within
# 600; the charge it gives rides on her next strike (pure damage, 100% cleave over 400, 80% slow). So it is on only
# while a charge would pay: a hero fight close by, a pack her cleave can sweep (a clumped wave or camp), or a laning
# hit on the enemy hero among its creeps; off once she holds a charge (another scan only spends more), off when
# running, short of mana (the door's mana is kept), or with nothing worth the cleave near.

## The enemy unit her cleave would hurt most if she struck it, within `reach`: [unit, enemies the slash would hit].
static func best_pack(b: SimBot, h: SimUnit, reach: float) -> Array:
	var w := b.w
	var cand: Array[SimUnit] = []
	for o: SimUnit in w.query(h.pos, reach + 450.0, true):
		if o.alive and o.team != h.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
				and not o.has_flag("hidden") and w.vision.sees(h.team, o):
			cand.append(o)
	var best: SimUnit = null
	var best_n := 0
	for t in cand:
		if t.pos.distance_to(h.pos) > reach:
			continue
		var n := 0
		for o in cand:
			if o.pos.distance_to(t.pos) <= 400.0 + o.hull:
				n += 1
		# a hero in the pack is worth two creeps
		n += 1 if t.is_hero() else 0
		if n > best_n:
			best_n = n
			best = t
	return [best, best_n]

## Why Soul Tap should be on now ("fight", "pack", "harass"), or "" for off.
static func soul_want(b: SimBot, h: SimUnit) -> String:
	var w := b.w
	var ab := w.abilities
	if h.ability_level_of("soul_tap") <= 0 or not b._spells_ok():
		return ""
	if ab.kits4.soul_charged(h):
		return ""                              # the charge waits for her next strike
	if b.mode in ["retreat", "heal"]:
		return ""
	var cost := ab.ability_mana(h, "soul_tap")
	var reserve := ab.ability_mana(h, "door_of_the_end") * 0.6 if h.ability_level_of("door_of_the_end") > 0 else 0.0
	if h.mana < cost + reserve:
		return ""
	# a hero fight close by: the pure slash and its slow on the target
	if b.mode == "fight" or b.mode == "task":
		var e := w.get_unit(b._fight_target)
		for f in b._foes:
			if f.alive and f.pos.distance_to(h.pos) < 700.0 and (e == null or f == e or not e.alive):
				return "fight"
	var pk := best_pack(b, h, 700.0)
	var n := int(pk[1])
	# a pack: three enemies in the slash with mana to spare, four when the mana runs lower
	var need := 3 if h.mana > h.max_mana * 0.5 else 4
	if n >= need and b.mode in ["lane", "farm", "clear", "task", "fight", "push", "stack"]:
		return "pack"
	# laning: the enemy hero within reach, standing among its creeps, out of its tower's reach
	if b.mode == "lane" and h.hp > h.max_hp * 0.5 and n >= 2 and pk[0] != null:
		for f in b._foes:
			if f.alive and f.pos.distance_to(h.pos) < 600.0 and w.vision.sees(h.team, f):
				var under := false
				for t in b._etowers:
					if t.alive and f.pos.distance_to(t.pos) < t.attack_range + 150.0:
						under = true
				if not under:
					return "harass"
	return ""

## Every think: the toggle follows soul_want (switching it is instant and breaks no order).
static func soul_plan(b: SimBot, h: SimUnit) -> void:
	if h.ability_level_of("soul_tap") <= 0 or b.w.abilities.kits4.in_door(h):
		return
	var on := bool(h.toggles.get("soul_tap", false))
	var want := soul_want(b, h) != ""
	if on != want and b.w.abilities.cast_error(h, "soul_tap", -1, null, h.pos) == "":
		b.w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "soul_tap"})
		if want:
			b.soul_ons += 1
		else:
			b.soul_offs += 1

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
		soul_plan(b, h)
		# the charged slash: on a hero close at hand, else on the pack it was gathered for (the cleave sweeps it)
		if k4.soul_charged(h) and b.mode in ["lane", "fight", "task", "farm", "clear", "push"] and h.hp > h.max_hp * 0.35 \
				and h.atk_phase == SimUnit.AtkPhase.NONE:
			var tgt: SimUnit = null
			for f in b._foes:
				# in lane only a hero close at hand is worth walking to; otherwise the charge cleaves the wave
				var reach := 250.0 + h.attack_range if b.mode == "lane" else 700.0
				if f.alive and h.edge_distance(f) < reach and (tgt == null or f.hp < tgt.hp):
					tgt = f
			if tgt == null:
				var pk := best_pack(b, h, 600.0)
				if pk[0] != null and int(pk[1]) >= 3:
					tgt = pk[0]
			if tgt != null and h.atk_target != tgt.id:
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
