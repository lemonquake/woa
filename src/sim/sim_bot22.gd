class_name SimBot22
extends RefCounted
## How bots play Gancho, Lord Kaileh and Dracoxinia (run 2026-10-21 b). Called by SimBot: spells() in fights and
## trades, escape() while running, aoe_farm() on creep packs, tick() every think (Dracoxinia picks her sword). All
## static: `b` is the SimBot whose hero acts. The shared cast helpers are SimBot18's.
##
## Gancho (a ranged agility carry who fights from the trees):
##   * Root Snare at the target when no creep stands in the vine's way, leading a runner; then Seed Bomb on the held
##     target (it cannot step out of the burst); Seed Bomb also where a runner will be.
##   * Angry Forest when the fight is beside trees (enemies within reach of several), on the most heroes it can touch.
##   * Running: Seed Bomb on the chaser's way (the young tree blocks him, not Gancho), Root Snare on the chaser, and
##     into the trees (he walks through them; SimBot's safe spot does the rest).
## Lord Kaileh (an off lane or carry knight who starts fights):
##   * Lance Charge through a lone enemy hero toward his own team or tower (it rides the lance there and is stunned),
##     for the kill, or to close in; Lance Sweep with enemies round him; War Banner in fights and pushes, between his
##     team and the enemy; Cavalry Charge along the line that crosses the most enemy heroes (two or more, one for the
##     kill or a pick).
##   * Running: Lance Charge and then Cavalry Charge toward safety.
## Dracoxinia (a strength carry with five swords):
##   * Her sword (tick): Gold when she is low in a fight (barriers), Green to sustain, Red against crowds, Blue to hold a
##     runner, else the sword whose element beats the target's (Royal Scales also cuts its damage), Pink by default.
##   * Dragon Dash in onto the target, Rising Slash on a hero in reach (to hold it, or to break a channel), Dragon Leap
##     after a runner the dash cannot reach.
##   * Running: Dragon Dash, then Dragon Leap toward safety (over trees and cliffs).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const B18 = preload("res://src/sim/sim_bot18.gd")
const KITS := ["gancho", "kaileh", "dracoxinia"]

static func handles(kit: String) -> bool:
	return kit in KITS

static func _kill_in_reach(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	return SimBotKits.burst(b.w, h, e) + SimBotKits.dps(b.w, h, e) * 3.0 > e.hp * 1.05

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	match b.kit:
		"gancho":
			_gancho(b, h, e)
		"kaileh":
			_kaileh(b, h, e)
		"dracoxinia":
			_dracoxinia(b, h, e)

## Enemy units (heroes and creeps) on the segment a-b within `r`, nearest to `a` first.
static func _in_line(b: SimBot, h: SimUnit, a: Vector2, z: Vector2, r: float) -> Array:
	var out: Array = []
	for o: SimUnit in b.w.query((a + z) * 0.5, a.distance_to(z) * 0.5 + r + 60.0, true):
		if not o.alive or o.team == h.team or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.is_invulnerable():
			continue
		if Geometry2D.get_closest_point_to_segment(o.pos, a, z).distance_to(o.pos) <= r + o.hull:
			out.append(o)
	out.sort_custom(func(x, y): return a.distance_squared_to(x.pos) < a.distance_squared_to(y.pos))
	return out

static func _heroes_in(arr: Array) -> int:
	var n := 0
	for o in arr:
		if (o as SimUnit).is_hero():
			n += 1
	return n

# ---- Gancho ---------------------------------------------------------------------------------------------------------

static func _gancho(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	var commit := on or kill
	# 1. Angry Forest beside trees: enemies within reach of trees round him
	if commit and h.ability_level_of("angry_forest") > 0 and ab.cast_error(h, "angry_forest", -1, null, h.pos) == "":
		var reach := ab.val(h, "angry_forest", "reach")
		var touched := 0
		for f in b._foes:
			if f.alive and f.pos.distance_to(h.pos) < ab.val(h, "angry_forest", "radius") - 100.0 \
					and w.map.tree_at(f.pos, reach - 60.0) >= 0:
				touched += 1
		if touched >= 2 or (touched >= 1 and (kill or B18._foes_near(b, h.pos, 1100.0) == 1)):
			if B18._cast_none(b, h, "angry_forest", 0.5):
				b.say("The forest is angry.", "forest_%d" % h.id, 120.0)
				return
	# 2. Root Snare: nothing between him and the target
	if d < ab.val(h, "root_snare", "distance") - 80.0 and ab.cast_error(h, "root_snare", -1, null, e.pos) == "" \
			and (commit or h.mana > h.max_mana * 0.6):
		var aim := B18._lead(b, e, 0.3 + d / ab.val(h, "root_snare", "speed"))
		var line := _in_line(b, h, h.pos, aim, ab.val(h, "root_snare", "width") * 0.5)
		if not line.is_empty() and line[0] == e and B18._cast_point(b, h, "root_snare", aim, 0.4):
			return
	# 3. Seed Bomb: on a held target, or where a runner will be
	if d < ab.cast_range(h, "seed_bomb", -1) + 100.0 and ab.cast_error(h, "seed_bomb", -1, null, e.pos) == "" \
			and (commit or h.mana > h.max_mana * 0.7):
		var held := B18._pinned(b, e, 1.0)
		if held or kill or not e.moving:
			var at := e.pos if held else B18._lead(b, e, 0.95)
			if at.distance_to(h.pos) <= ab.cast_range(h, "seed_bomb", -1) and B18._cast_point(b, h, "seed_bomb", at, 0.4):
				return

# ---- Lord Kaileh ----------------------------------------------------------------------------------------------------

## Where a charge from `h` through `e` should end: past it, toward his own team when they stand that way.
static func _charge_point(b: SimBot, h: SimUnit, e: SimUnit, reach: float) -> Vector2:
	var dir := (e.pos - h.pos).normalized()
	var d := h.pos.distance_to(e.pos)
	return h.pos + dir * minf(reach, d + 260.0)

static func _kaileh(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	var commit := on or kill
	if ab.kits10.charging(h) != "":
		return
	# 1. Cavalry Charge along the line through the most enemy heroes
	if commit and h.ability_level_of("cavalry_charge") > 0 and ab.cast_error(h, "cavalry_charge", -1, null, e.pos) == "":
		var reach := ab.cast_range(h, "cavalry_charge", -1)
		var best := Vector2.INF
		var bn := 0
		for f in b._foes:
			if not f.alive or f.pos.distance_to(h.pos) > reach - 100.0:
				continue
			var z := h.pos + (B18._lead(b, f, 0.6) - h.pos).normalized() * reach
			var n := _heroes_in(_in_line(b, h, h.pos, z, ab.val(h, "cavalry_charge", "width") * 0.5))
			if n > bn:
				bn = n
				best = z
		if best != Vector2.INF and (bn >= 2 or (bn >= 1 and (kill or b._foes.size() == 1))) \
				and B18._cast_point(b, h, "cavalry_charge", best, 0.7):
			b.say("Charge!", "cavalry_%d" % h.id, 90.0)
			return
	# 2. War Banner between him and the fight
	if commit and d < 900.0 and ab.cast_error(h, "war_banner", -1, null, h.pos) == "" \
			and (B18._allies_near(b, h, h.pos, 1000.0) > 0 or kill or d < 500.0):
		var at := h.pos + (e.pos - h.pos).normalized() * minf(250.0, d * 0.4)
		if B18._cast_point(b, h, "war_banner", at, 0.3):
			return
	# 3. Lance Charge through the target (toward his team), never into an enemy tower without the kill
	if commit and d > 260.0 and d < ab.cast_range(h, "lance_charge", -1) - 60.0 \
			and ab.cast_error(h, "lance_charge", -1, null, e.pos) == "":
		var to := _charge_point(b, h, e, ab.cast_range(h, "lance_charge", -1))
		var line := _in_line(b, h, h.pos, to, ab.val(h, "lance_charge", "width") * 0.5)
		var first_hero: SimUnit = null
		for o in line:
			if (o as SimUnit).is_hero():
				first_hero = o
				break
		var tower := SimBot19._tower_at(w, h.team, to)
		if first_hero == e and (kill or not tower) and B18._cast_point(b, h, "lance_charge", to, 0.4):
			return
	# 4. Lance Sweep with enemies round him
	if ab.cast_error(h, "lance_sweep", -1, null, h.pos) == "":
		var r := ab.val(h, "lance_sweep", "radius") - 30.0
		if (d < r and commit) or B18._foes_near(b, h.pos, r) >= 2:
			if B18._cast_none(b, h, "lance_sweep", 0.4):
				return

# ---- Dracoxinia -----------------------------------------------------------------------------------------------------

## The sword she wants for this fight (an index into SimKits11.SWORDS), among those open.
static func want_sword(b: SimBot, h: SimUnit, e: SimUnit) -> int:
	var k11 := b.w.abilities.kits11
	var open := k11.swords_open(h)
	var fight := e != null and e.alive and h.pos.distance_to(e.pos) < 900.0
	if fight and h.hp < h.max_hp * 0.35 and open > 1:
		return 1                                              # Gold: barriers
	if fight and h.hp < h.max_hp * 0.55 and open > 4:
		return 4                                              # Green: heals
	if e != null and open > 3:
		var crowd := 0
		for o: SimUnit in b.w.query(e.pos, 260.0, true):
			if o.alive and o.team != h.team and not o.is_building() and not o.is_ward():
				crowd += 1
		if crowd >= 3:
			return 3                                          # Red: the strike splashes
	if e != null and e.is_hero() and e.moving and open > 2 and h.pos.distance_to(e.pos) > 250.0:
		return 2                                              # Blue: roots a runner
	if e != null:
		for i in open:
			var el := int(SimKits11.SWORDS[i].element)
			for pair in C.ELEMENT_BEATS:
				if int(pair[0]) == el and int(pair[1]) == e.element:
					return i
	return 0

## Every think: change toward the wanted sword (one click a second).
static func tick(b: SimBot, h: SimUnit) -> bool:
	if b.kit != "dracoxinia" or not bool(b.sk.spells) or h.ability_level_of("change_sword") <= 0:
		return false
	var ab := b.w.abilities
	if ab.cast_error(h, "change_sword", -1, null, h.pos) != "":
		return false
	var e: SimUnit = null
	var bd := 1200.0
	for f in b._foes:
		if f.alive and f.pos.distance_to(h.pos) < bd:
			bd = f.pos.distance_to(h.pos)
			e = f
	if e == null:
		for o: SimUnit in b.w.query(h.pos, 700.0, true):
			if o.alive and o.team != h.team and o.is_creep():
				e = o
				break
	if e == null:
		return false
	if ab.kits11.sword_of(h) == want_sword(b, h, e):
		return false
	# a click is free and instant (no order is dropped): it does not take the think
	b.w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "change_sword"})
	return false

static func _dracoxinia(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	var commit := on or kill
	if ab.kits11.dashes.has(h.id):
		return
	# 1. Rising Slash on a hero in reach: to hold it (or break its channel)
	if e.is_hero() and d < ab.cast_range(h, "rising_slash", -1, e) + h.hull + e.hull + 40.0 \
			and ab.cast_error(h, "rising_slash", -1, e, e.pos) == "" and (commit or not e.channel.is_empty()):
		if B18._cast_unit(b, h, "rising_slash", e, 0.4):
			return
	# 2. Dragon Dash in onto the target
	if commit and d > 280.0 and d < ab.cast_range(h, "dragon_dash", -1) + 60.0 \
			and ab.cast_error(h, "dragon_dash", -1, null, e.pos) == "":
		var to := h.pos + (e.pos - h.pos).normalized() * minf(ab.cast_range(h, "dragon_dash", -1), d + 80.0)
		var tower := SimBot19._tower_at(w, h.team, to)
		if (kill or not tower) and B18._cast_point(b, h, "dragon_dash", to, 0.3):
			return
	# 3. Dragon Leap after a runner the dash cannot reach (or when the dash is down), never under an enemy tower
	if commit and d > 350.0 and d < ab.cast_range(h, "dragon_leap", -1) + 250.0 \
			and ab.cast_error(h, "dragon_leap", -1, null, e.pos) == "" \
			and (ab.cast_error(h, "dragon_dash", -1, null, e.pos) != "" or d > ab.cast_range(h, "dragon_dash", -1) + 60.0):
		var to2 := h.pos + (e.pos - h.pos).normalized() * minf(ab.cast_range(h, "dragon_leap", -1), d - 120.0)
		if (kill or not SimBot19._tower_at(w, h.team, to2)) and B18._cast_point(b, h, "dragon_leap", to2, 0.3):
			return

# ---- Running --------------------------------------------------------------------------------------------------------

static func escape(b: SimBot, h: SimUnit, fd: float) -> bool:
	if not b._spells_ok():
		return false
	var w := b.w
	var ab := w.abilities
	var chaser: SimUnit = null
	for f in b._foes:
		if f.alive and (chaser == null or f.pos.distance_to(h.pos) < chaser.pos.distance_to(h.pos)):
			chaser = f
	var safe := b._safe_point(h)
	var away := (safe - h.pos).normalized() if safe.distance_to(h.pos) > 1.0 else Vector2.from_angle(h.facing)
	match b.kit:
		"gancho":
			if chaser == null or fd > 900.0:
				return false
			# a young tree on the chaser's way (Gancho walks through it, the chaser must go round)
			if ab.cast_error(h, "seed_bomb", -1, null, chaser.pos) == "":
				var at := chaser.pos + (h.pos - chaser.pos).normalized() * minf(150.0, fd * 0.4)
				if at.distance_to(h.pos) <= ab.cast_range(h, "seed_bomb", -1) and B18._cast_point(b, h, "seed_bomb", at, 0.3):
					return true
			if fd < 900.0 and ab.cast_error(h, "root_snare", -1, null, chaser.pos) == "":
				var line := _in_line(b, h, h.pos, chaser.pos, ab.val(h, "root_snare", "width") * 0.5)
				if not line.is_empty() and line[0] == chaser and B18._cast_point(b, h, "root_snare", chaser.pos, 0.3):
					return true
			return false
		"kaileh":
			if fd > 800.0:
				return false
			if ab.cast_error(h, "lance_charge", -1, null, h.pos) == "" \
					and B18._cast_point(b, h, "lance_charge", h.pos + away * ab.cast_range(h, "lance_charge", -1), 0.3):
				return true
			if h.hp < h.max_hp * 0.25 and ab.cast_error(h, "cavalry_charge", -1, null, h.pos) == "" \
					and B18._cast_point(b, h, "cavalry_charge", h.pos + away * ab.cast_range(h, "cavalry_charge", -1), 0.6):
				return true
			return false
		"dracoxinia":
			if fd > 800.0:
				return false
			if ab.cast_error(h, "dragon_dash", -1, null, h.pos) == "" \
					and B18._cast_point(b, h, "dragon_dash", h.pos + away * ab.cast_range(h, "dragon_dash", -1), 0.2):
				return true
			# over the trees or a cliff, away from the chaser
			if ab.cast_error(h, "dragon_leap", -1, null, h.pos) == "" \
					and B18._cast_point(b, h, "dragon_leap", h.pos + away * ab.cast_range(h, "dragon_leap", -1), 0.2):
				return true
			return false
	return false

# ---- Farming --------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], centre: Vector2) -> bool:
	if not b._spells_ok() or ns.is_empty():
		return false
	var ab := b.w.abilities
	var keep := 0.0
	match b.kit:
		"gancho":
			keep = ab.ability_mana(h, "root_snare")
			var c := 0
			for n in ns:
				if n.alive and n.pos.distance_to(centre) < ab.val(h, "seed_bomb", "radius"):
					c += 1
			if c >= 3 and h.mana > keep + ab.ability_mana(h, "seed_bomb") and centre.distance_to(h.pos) < ab.cast_range(h, "seed_bomb", -1) \
					and B18._cast_point(b, h, "seed_bomb", centre, 0.4):
				return true
		"kaileh":
			keep = ab.ability_mana(h, "lance_charge")
			var near := 0
			for n in ns:
				if n.alive and n.pos.distance_to(h.pos) < ab.val(h, "lance_sweep", "radius") - 30.0:
					near += 1
			if near >= 3 and h.mana > keep + ab.ability_mana(h, "lance_sweep") and B18._cast_none(b, h, "lance_sweep", 0.4):
				return true
	return false
