class_name SimBot21
extends RefCounted
## How bots play Blackfire, the Unfallen and Thyrandael, the Forsaken Seraph (run 2026-10-21). Called by SimBot:
## spells() in fights and trades, escape() while running, aoe_farm() on creep packs, channel_tick() while Thyrandael
## holds Holy Beam (before SimBot's own "busy" wait), dodge_beam() for every bot. All static: `b` is the SimBot whose
## hero acts. The shared cast helpers are SimBot18's.
##
## Blackfire (an off lane or carry strength hero who wants fights where things die):
##   * Sacrificial Grip holds him too, so it goes on an enemy hero when someone can hit it meanwhile (an ally, his
##     Undead, a tower of his) or for the kill (25% of its health as pure damage), and on an enemy hitting a low ally.
##     Never when he is the one about to die and alone.
##   * Rise Up when bodies lie around him in a fight (or will: a wave or camp is dying around him), to push with the
##     raised wave and to jungle with it; never on cooldown for nothing.
##   * With Unfallen learned he stays in fights longer: his first death is not his last (the threat he fears is less).
##   * Running: Rise Up on the bodies behind him (they block and fight the chasers).
## Thyrandael (a mid or off lane caster who builds barriers by casting):
##   * Spirit Step onto the target (its silence stops the reply), Quick Flash whenever enemy heroes stand within 480
##     (cheap, stacking, and every cast is a Divine Touch charge), Holy Beam on a held, slowed or lined-up target, then
##     False Judgement once the charges are worth it (half full, or any for the kill), on the most enemy heroes.
##   * Holding the beam: he turns it onto the best target (heroes first), flashes the enemies that close in, and stops it
##     when nothing is left in reach or he must run.
##   * Running: Spirit Step toward safety, the judgement on the chasers.
## Every bot steps out of an enemy Holy Beam's line once it notices it.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const B18 = preload("res://src/sim/sim_bot18.gd")
const KITS := ["blackfire", "thyrandael"]

static func handles(kit: String) -> bool:
	return kit in KITS

static func _kill_in_reach(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	return SimBotKits.burst(b.w, h, e) + SimBotKits.dps(b.w, h, e) * 3.0 > e.hp * 1.05

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	if b.kit == "blackfire":
		_blackfire(b, h, e)
	else:
		_thyrandael(b, h, e)

# ---- Blackfire -----------------------------------------------------------------------------------------------------

## Someone of his can hit `e` while both are held: an ally hero near it, two of his Undead, an allied tower.
static func _help_on(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	if B18._allies_near(b, h, e.pos, 700.0) > 0:
		return true
	var n := 0
	for u: SimUnit in b.w.abilities.kits8.undead_of(h):
		if u.pos.distance_to(e.pos) < 600.0:
			n += 1
	if n >= 2:
		return true
	for t in b.w.units:
		if t.alive and t.kind == K.TOWER and t.team == h.team and e.pos.distance_to(t.pos) < t.attack_range + t.hull:
			return true
	return false

static func _blackfire(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	# Rise Up first: the bodies around now, or a crowd of creeps about to die near him in the fight
	if (on or kill) and ab.cast_error(h, "rise_up", -1, null, h.pos) == "":
		var bodies := ab.kits8.bodies_near(h.pos, ab.val(h, "rise_up", "radius") * 0.9)
		var dying := 0
		for o: SimUnit in w.query(h.pos, 700.0, true):
			if o.alive and SimKits8.raisable(o) and o.hp < o.max_hp * 0.5:
				dying += 1
		if bodies >= 2 or (bodies >= 1 and dying >= 2) or dying >= 4:
			if B18._cast_none(b, h, "rise_up", 0.05):
				b.say("Rise.", "rise_%d" % h.id, 90.0)
				return
	# Sacrificial Grip: a target someone can punish while both are held, or the kill
	if d < ab.cast_range(h, "sacrificial_grip", -1, e) + 120.0 and ab.cast_error(h, "sacrificial_grip", -1, e, e.pos) == "":
		var safe_me := h.hp > h.max_hp * 0.3 or B18._allies_near(b, h, h.pos, 900.0) > 0 or ab.kits8.risen_left(h) > 0.0
		var grip_dmg := e.hp * ab.val(h, "sacrificial_grip", "hp_pct")
		var worth := kill or (on and _help_on(b, h, e)) or (e.hp - grip_dmg < e.max_hp * 0.25 and on)
		if worth and safe_me and B18._cast_unit(b, h, "sacrificial_grip", e, 0.4):
			return
	# a save: an enemy hero beating on a low ally of his
	if ab.cast_error(h, "sacrificial_grip", -1, null, h.pos) == "":
		for f in b._foes:
			var t := w.get_unit(f.atk_target)
			if f.alive and t != null and t.is_hero() and t.team == h.team and t != h and t.hp < t.max_hp * 0.3 \
					and f.pos.distance_to(h.pos) < ab.cast_range(h, "sacrificial_grip", -1, f) + 80.0 \
					and B18._cast_unit(b, h, "sacrificial_grip", f, 0.4):
				b.say("Not today.", "gripsave_%d" % h.id, 60.0)
				return

# ---- Thyrandael ----------------------------------------------------------------------------------------------------

## The point for an area spell of radius `r` on `e`, pulled toward other enemy heroes it can also cover.
static func _cluster(b: SimBot, e: SimUnit, r: float, lead: float) -> Vector2:
	var c := B18._lead(b, e, lead)
	var sum := c * 2.0
	var n := 2.0
	for f in b._foes:
		if f != e and f.alive and f.pos.distance_to(c) < r * 1.4:
			sum += f.pos
			n += 1.0
	var at := sum / n
	if at.distance_to(c) > r * 0.5:
		at = c + (at - c).normalized() * r * 0.5
	return at

## Enemies (heroes count 4) a beam from `h` toward `p` would touch.
static func _beam_score(b: SimBot, h: SimUnit, p: Vector2) -> float:
	var ab := b.w.abilities
	var dir := (p - h.pos).normalized()
	var a := h.pos
	var z := h.pos + dir * ab.kits9.beam_length(h)
	var width := ab.val(h, "holy_beam", "width")
	var s := 0.0
	for o: SimUnit in b.w.query((a + z) * 0.5, a.distance_to(z) * 0.5 + width, true):
		if not o.alive or o.team == h.team or o.is_building() or o.is_ward() or o.is_invulnerable():
			continue
		if not b.w.vision.sees(h.team, o):
			continue
		if Geometry2D.get_closest_point_to_segment(o.pos, a, z).distance_to(o.pos) <= width * 0.5 + o.hull * 0.5:
			s += 4.0 if o.is_hero() else 0.5
	return s

static func _thyrandael(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var k9 := ab.kits9
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	var commit := on or kill
	var beam_mana := ab.ability_mana(h, "holy_beam") if ab.cooldown_left(h, "holy_beam") <= 0.0 else 0.0
	# 1. False Judgement once the charges are worth spending (half or more, any for the kill), on the most heroes
	if h.ability_level_of("false_judgement") > 0 and k9.judgement_charges(h) > 0 and ab.cooldown_left(h, "false_judgement") <= 0.0:
		var f := k9.judgement_frac(h)
		var low := h.hp < h.max_hp * 0.4
		if (commit and f >= 0.5) or (kill and f >= 0.2) or (low and f >= 0.3 and b._threat > 0.9) or f >= 0.99:
			var at := _cluster(b, e, ab.val(h, "false_judgement", "radius"), 0.4)
			if h.pos.distance_to(at) <= ab.cast_range(h, "false_judgement", -1) + 60.0 \
					and B18._cast_point(b, h, "false_judgement", at, 0.5):
				b.say("Judged.", "judge_%d" % h.id, 90.0)
				return
	# 2. Spirit Step onto the target: in among them, silencing; not into a tower without the kill
	if commit and h.level >= 2 and d > 220.0 and d < ab.cast_range(h, "spirit_step", -1) + 150.0 \
			and ab.cast_error(h, "spirit_step", -1, null, e.pos) == "" and h.mana >= ab.ability_mana(h, "spirit_step") + 60.0:
		var at := _cluster(b, e, ab.val(h, "spirit_step", "radius"), 0.25)
		var tower := SimBot19._tower_at(w, h.team, at)
		if (kill or not tower) and (h.hp > h.max_hp * 0.45 or kill) \
				and B18._cast_point(b, h, "spirit_step", at, 0.3):
			return
	# 3. Quick Flash on enemy heroes in reach (keeping the beam's mana when it is up)
	if d < ab.val(h, "quick_flash", "radius") - 30.0 and ab.cast_error(h, "quick_flash", -1, null, h.pos) == "" \
			and (h.mana >= ab.ability_mana(h, "quick_flash") + beam_mana or kill or commit and h.mana > h.max_mana * 0.5):
		if B18._cast_none(b, h, "quick_flash", 0.05):
			return
	# 4. Holy Beam on a held, slowed or lined-up target in reach
	if commit and d < k9.beam_length(h) - 60.0 and ab.cast_error(h, "holy_beam", -1, null, e.pos) == "":
		var held := B18._pinned(b, e, 1.5)
		if held or _beam_score(b, h, e.pos) >= 8.0 or kill or d < 450.0:
			if B18._cast_point(b, h, "holy_beam", e.pos, 0.5):
				return

## While Thyrandael holds Holy Beam (SimBot.think, before its busy wait): true when the bot handled the think.
static func channel_tick(b: SimBot, h: SimUnit) -> bool:
	if not handles(b.kit) or h.channel.is_empty() or String(h.channel.ability) != "holy_beam":
		return false
	var w := b.w
	var ab := w.abilities
	var reach := ab.kits9.beam_length(h)
	# run: low and outmatched, or nothing to burn
	var best := Vector2.INF
	var bs := 0.0
	for f in b._foes:
		if not f.alive or f.pos.distance_to(h.pos) > reach + 100.0 or not w.vision.sees(h.team, f):
			continue
		var s := _beam_score(b, h, f.pos) + (3.0 if f.hp < f.max_hp * 0.3 else 0.0)
		if s > bs:
			bs = s
			best = B18._lead(b, f, 0.25)
	if best == Vector2.INF:
		for o: SimUnit in w.query(h.pos, reach, true):
			if o.alive and o.team != h.team and (o.is_creep() or o.kind == K.SUMMON) and w.vision.sees(h.team, o):
				var s2 := _beam_score(b, h, o.pos)
				if s2 > bs:
					bs = s2
					best = o.pos
	var danger := h.hp < h.max_hp * 0.25 and b._threat > 1.0
	if best == Vector2.INF or bs < 1.0 or danger:
		b._order(h, {"type": O.STOP}, true)
		return true
	# a Quick Flash on whoever closes in does not stop the beam
	if B18._foes_near(b, h.pos, ab.val(h, "quick_flash", "radius") - 40.0) > 0 and ab.cast_error(h, "quick_flash", -1, null, h.pos) == "":
		b._order(h, {"type": O.CAST_NO_TARGET, "ability": "quick_flash"}, true)
		return true
	var aim: Vector2 = h.channel.get("point", h.pos)
	if aim.distance_to(best) > 60.0:
		w.command(h.id, {"type": O.MOVE, "point": best})
	return true

# ---- Every bot: out of an enemy beam --------------------------------------------------------------------------------

static func dodge_beam(b: SimBot, h: SimUnit) -> bool:
	if b._foes.is_empty() or h.is_stunned() or not h.channel.is_empty() or h.is_rooted():
		return false
	var ab := b.w.abilities
	for f: SimUnit in b._foes:
		if f.channel.is_empty() or String(f.channel.ability) != "holy_beam":
			continue
		if b.w.time - float(f.channel.get("started", 0.0)) < float(b.sk.react):
			continue
		var line := ab.kits9.beam_line(f)
		var a: Vector2 = line[0]
		var z: Vector2 = line[1]
		var half := ab.val(f, "holy_beam", "width") * 0.5 + h.hull + 30.0
		var cp := Geometry2D.get_closest_point_to_segment(h.pos, a, z)
		if cp.distance_to(h.pos) > half:
			continue
		# away from the beam, on the side already taken; out of its length when that is nearer
		var dir := (z - a).normalized()
		var side := dir.orthogonal()
		if (h.pos - cp).dot(side) < 0.0:
			side = -side
		for step in [half + 140.0, half + 280.0]:
			var p: Vector2 = cp + side * step
			if b.w.map.is_walkable(p):
				b._order(h, {"type": O.MOVE, "point": p})
				return true
	return false

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
	if b.kit == "blackfire":
		# the bodies behind him rise and stand between him and the chasers
		if fd < 700.0 and ab.kits8.bodies_near(h.pos, 900.0) >= 2 and B18._cast_none(b, h, "rise_up", 0.05):
			return true
		return false
	# Thyrandael: a step toward safety, then the judgement on the chasers
	if fd < 800.0 and ab.cast_error(h, "spirit_step", -1, null, h.pos) == "":
		var safe := b._safe_point(h)
		var dir := (safe - h.pos).normalized() if safe.distance_to(h.pos) > 1.0 else Vector2.from_angle(h.facing)
		var to := h.pos + dir * ab.cast_range(h, "spirit_step", -1)
		if B18._cast_point(b, h, "spirit_step", to, 0.2):
			return true
	if chaser != null and fd < 700.0 and ab.kits9.judgement_charges(h) >= 2 \
			and h.pos.distance_to(chaser.pos) <= ab.cast_range(h, "false_judgement", -1) \
			and B18._cast_point(b, h, "false_judgement", chaser.pos, 0.3):
		return true
	return false

# ---- Farming --------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], _centre: Vector2) -> bool:
	if not b._spells_ok() or ns.is_empty():
		return false
	var ab := b.w.abilities
	if b.kit == "blackfire":
		# a camp or wave died around him: raise it to push and farm with it
		if ab.kits8.bodies_near(h.pos, 900.0) >= 3 and h.mana > ab.ability_mana(h, "sacrificial_grip") + 100.0 \
				and B18._cast_none(b, h, "rise_up", 0.05):
			return true
		return false
	# Thyrandael: Quick Flash on three or more creeps close by, with mana left for a fight
	var close := 0
	for n in ns:
		if n.alive and n.pos.distance_to(h.pos) < ab.val(h, "quick_flash", "radius") - 40.0:
			close += 1
	var keep := ab.ability_mana(h, "holy_beam") + ab.ability_mana(h, "spirit_step")
	if close >= 3 and h.mana > keep + ab.ability_mana(h, "quick_flash") and B18._cast_none(b, h, "quick_flash", 0.05):
		return true
	return false
