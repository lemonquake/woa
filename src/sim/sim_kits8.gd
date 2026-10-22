class_name SimKits8
extends RefCounted
## Blackfire's kit (the owner's hero, run 2026-10-21; see docs/HANDOFF.md). Called by SimAbilities (cast,
## cast_error, owns_effect), SimCombat (on_death, the Unfallen catch in kill, Fiend Edge's crit and drain) and
## SimWorld (tick).
##
## Underworld Presence (innate): every unit that dies within 1000 of him heals him 4% of his maximum health (a hero
## 150% more: 10%); a black soul flies from the body to him.
## Sacrificial Grip: an enemy unit and Blackfire are both stunned (2 / 2.2 / 2.4 / 2.6 s); the target loses 25% of its
## current health as pure damage (never lethal); after the stun both deal 30% less attack damage for 2 s. Meanwhile his
## Undead go for that target first.
## Rise Up: a roar that raises every fresh body within 1000 (lane and camp creeps; not ancients, heroes, buildings,
## summons or tamed beasts) as his Undead for 20 s. The roar's aura stays on him for 20 s and raises whatever dies
## within 1000 meanwhile; the raised stay their 20 s when it ends.
## Fiend Edge: a 10 / 15 / 20 / 25% chance of a 2x critical strike; a critical heals every ally within 800 (him too)
## for 20 / 25 / 30 / 35% of the blow's damage.
## Unfallen (ultimate, passive): a killing blow drops him for 3 s; he rises with full health and 25% more damage,
## armor, movement and attack speed for 3 / 4 / 5 s, then dies for good (sooner if killed again). As his life ends a
## blast throws every unit within 400 (allies too) 300 away; any that slams into a wall, a tree or a unit is stunned
## for 0.5 s.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const CASTS := ["sacrificial_grip", "rise_up"]
const EFFECTS: Array = []
const AURA := "rise_up"                     # on Blackfire: the roar's aura (raises what dies near him)
const UNDEAD := "undead"                    # on a raised unit (its source: Blackfire)
const MARK := "grip_mark"                   # on the gripped enemy: his Undead go for it first
const FALLEN := "unfallen_fallen"           # on Blackfire while he lies dead before rising
const RISEN := "unfallen_risen"             # on Blackfire for his last seconds
const BLAST := "unfallen_blast"             # the push's ability key (SimAbilities._impact)
const BODY_TIME := 8.0                      # a body can be raised this long after the death
const UNDEAD_THINK := 6                     # ticks between an Undead's thoughts (0.2 s)
const FOLLOW := 300.0
const LEASH := 1400.0
const PUSH_SPEED := 900.0                   # a push this fast slides about 300 (SimAbilities.update_motion)

var w: SimWorld
var ab: SimAbilities
var bodies: Array = []                      # [{def, pos, team, at, facing, hp, armor, as, dmg_add}] recent deaths
var undead := {}                            # Blackfire id -> [raised unit ids]
var _fallen := {}                           # Blackfire id -> {killer, rise_at, end_at}
var _weak := {}                             # unit id -> true while a grip's weakness waits to start

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func owns_effect(kind: String) -> bool:
	return kind in EFFECTS

func _enemy(team: int, o: SimUnit) -> bool:
	return o != null and o.alive and o.team != team and not o.is_building() and not o.is_ward() \
		and o.kind != K.COURIER and not o.is_invulnerable()

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, _p: Vector2) -> void:
	match aid:
		"sacrificial_grip":
			_grip(u, aid, t)
		"rise_up":
			_rise_up(u, aid, lv)

func update_effect(_e: Dictionary) -> bool:
	return true

func cast_error(u: SimUnit, aid: String, t: SimUnit, _p: Vector2, check_target: bool) -> String:
	if aid == "sacrificial_grip" and check_target and t != null and t.team != u.team and t.debuff_immune:
		return "Target is immune to spells"
	return ""

# ---- Underworld Presence and the bodies ----------------------------------------------------------------------------

## A body Rise Up may raise: a lane or camp creep (not an ancient), not a summon, beast or Undead.
static func raisable(t: SimUnit) -> bool:
	if t.kind == K.NEUTRAL_CREEP:
		return not bool(t.def.get("ancient", false))
	return t.is_lane_creep() and t.kind != K.CREEP_FLAG

## A death (SimCombat.process_deaths, before its rewards): Underworld Presence heals every Blackfire near it, the body
## is kept for Rise Up, and an aura around him raises it at once.
func on_death(t: SimUnit, killer: SimUnit) -> void:
	if t.is_building() or t.is_ward() or t.kind == K.COURIER:
		return
	# a summon that runs out of time or is let go (Araki's ghosts, Undead, released beasts, turrets) is not a death
	if t.kind == K.SUMMON and (killer == null or String(t.def.id) == "araki_ghost"):
		return
	for h in w.heroes:
		if h == t or not h.alive or h.ability_level_of("underworld_presence") <= 0 or h.is_broken() \
				or not h.get_modifier(FALLEN).is_empty():
			continue
		if h.pos.distance_to(t.pos) > ab.val(h, "underworld_presence", "radius"):
			continue
		var pct := ab.val(h, "underworld_presence", "heal_pct") * (ab.val(h, "underworld_presence", "hero_mult") if t.is_hero() else 1.0)
		var got := w.combat.heal(h, h.max_hp * pct)
		w.events.append({"t": "soul_drain", "u": h.id, "from": t.pos, "victim": t.id, "hero": t.is_hero(), "amount": got})
	if not raisable(t) or t.kind == K.SUMMON:
		return
	var body := {"def": String(t.def.id), "pos": t.pos, "team": t.team, "at": w.time, "facing": t.facing,
		"hp": t.max_hp, "armor": t.armor, "as": t.attack_speed, "dmg_add": t.creep_dmg_add, "id": t.id}
	for h in w.heroes:
		if h.alive and h.team != C.NEUTRAL and not h.get_modifier(AURA).is_empty() \
				and h.pos.distance_to(t.pos) <= float(h.get_modifier(AURA).radius):
			_raise(h, body, float(h.get_modifier(AURA).life))
			return
	bodies.append(body)

func _prune_bodies() -> void:
	while not bodies.is_empty() and w.time - float(bodies[0].at) > BODY_TIME:
		bodies.pop_front()

# ---- Sacrificial Grip ----------------------------------------------------------------------------------------------

func _grip(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var stun := ab.val(u, aid, "stun")
	var weak := ab.val(u, aid, "weaken")
	var weak_t := ab.val(u, aid, "weaken_duration")
	w.events.append({"t": "sacrificial_grip", "u": u.id, "target": t.id, "dur": stun})
	var landed := w.status.apply(t, u.id, u.team, {"id": "stunned", "stun": true, "dur": stun, "fx": "grip"})
	if t.alive:
		var dmg := t.hp * ab.val(u, aid, "hp_pct")
		w.combat.deal_damage(u.id, u.team, true, t, dmg, C.DamageType.PURE, false, aid, false, {"non_lethal": true})
	var held := float(t.get_modifier("stunned").get("dur", stun)) if landed else 0.0
	if t.alive:
		# weakened once the stun ends; meanwhile (and for those seconds) his Undead go for it first
		# the held stun was already shortened by status resistance: only the weakness's own seconds are now
		w.status.apply(t, u.id, u.team, {"id": "grip_weak", "dur": held + weak_t * (1.0 - t.status_resist),
			"weak_from": w.time + held, "weak_pct": weak, "fx": "grip_weak", "no_resist": true})
		t.add_modifier({"id": MARK, "source": u.id, "expires": w.time + held + weak_t, "fx": "grip_mark"})
		if t.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(t, u)
	# he holds on too: his own stun (not shortened, not a debuff), then the same weakness
	u.add_modifier({"id": "grip_hold", "source": u.id, "stun": true, "expires": w.time + stun, "fx": "grip_self"})
	u.add_modifier({"id": "grip_weak", "source": u.id, "expires": w.time + stun + weak_t, "weak_from": w.time + stun,
		"weak_pct": weak, "fx": "grip_weak"})
	u.stats_dirty = true
	_weak[u.id] = true
	_weak[t.id] = true
	if not u.channel.is_empty():
		w.orders.cancel_channel(u)

## The gripped weakness starts once the stun is over (SimKits8.tick turns the stat on).
func _weakness(o: SimUnit) -> void:
	for m in o.modifiers:
		if String(m.id) == "grip_weak" and not m.has("stats") and w.time >= float(m.weak_from):
			m["stats"] = {"attack_out_pct": -float(m.weak_pct)}
			o.stats_dirty = true

# ---- Rise Up and his Undead ------------------------------------------------------------------------------------------

func _rise_up(u: SimUnit, aid: String, _lv: int) -> void:
	var r := ab.val(u, aid, "radius")
	var life := ab.val(u, aid, "undead_duration")
	var dur := ab.val(u, aid, "duration")
	u.add_modifier({"id": AURA, "source": u.id, "expires": w.time + dur, "radius": r, "life": life, "fx": "rise_up"})
	var n := 0
	_prune_bodies()
	for i in range(bodies.size() - 1, -1, -1):
		var b: Dictionary = bodies[i]
		if (b.pos as Vector2).distance_to(u.pos) <= r:
			bodies.remove_at(i)
			_raise(u, b, life)
			n += 1
	w.events.append({"t": "rise_up", "u": u.id, "radius": r, "dur": dur, "raised": n})

## A body rises as one of `h`'s Undead: the creep it was (its health, armor, speed and damage from the clock kept), on
## his team, his to command, for `life` seconds. No bounty: it was paid for once.
func _raise(h: SimUnit, b: Dictionary, life: float) -> SimUnit:
	var at: Vector2 = b.pos
	if not w.map.is_walkable(at):
		var c := w.map.nearest_walkable(w.map.world_to_cell(at))
		at = w.map.cell_center(c.x, c.y)
	var o := w.spawn(String(b.def), h.team, at)
	o.kind = K.SUMMON
	o.owner_id = h.id
	o.name = "Undead " + String(o.def.name)
	o.facing = float(b.facing)
	o.home = at
	o.creep_dmg_add = float(b.dmg_add)
	o.ward_expires = w.time + life
	o.refresh_stats()
	o.perm_stats = {"hp": maxf(0.0, float(b.hp) - o.max_hp), "armor": float(b.armor) - o.armor,
		"attack_speed": maxf(0.0, float(b["as"]) - o.attack_speed)}
	o.add_modifier({"id": UNDEAD, "source": h.id, "expires": INF, "dispel": "", "no_bounty": true, "fx": "undead"})
	o.refresh_stats()
	o.hp = o.max_hp
	var list: Array = undead.get(h.id, [])
	list.append(o.id)
	undead[h.id] = list
	w.events.append({"t": "undead_rise", "u": h.id, "unit": o.id, "pos": at, "body": int(b.get("id", -1)), "life": life})
	return o

func is_undead(o: SimUnit) -> bool:
	return o != null and o.kind == K.SUMMON and not o.get_modifier(UNDEAD).is_empty()

func is_undead_of(h: SimUnit, o: SimUnit) -> bool:
	return is_undead(o) and o.owner_id == h.id and o.alive

## His living Undead.
func undead_of(h: SimUnit) -> Array:
	var out: Array = []
	for id in undead.get(h.id, []):
		var o := w.get_unit(int(id))
		if o != null and o.alive:
			out.append(o)
	return out

## Bodies near `p` Rise Up could raise now (bots count them).
func bodies_near(p: Vector2, r: float) -> int:
	var n := 0
	for b in bodies:
		if w.time - float(b.at) <= BODY_TIME and (b.pos as Vector2).distance_to(p) <= r:
			n += 1
	return n

## The gripped enemy his Undead go for (null if none).
func marked_for(h: SimUnit, near: Vector2) -> SimUnit:
	var best: SimUnit = null
	for o in w.units:
		if o.alive and o.team != h.team and not o.modifiers.is_empty():
			var m := o.get_modifier(MARK)
			if not m.is_empty() and int(m.source) == h.id and o.pos.distance_to(near) < 1600.0:
				best = o
	return best

## Undead every 0.2 s, as Ghorman's beasts: a player's order stands until it is done; the gripped enemy first, then
## what Blackfire fights (or what fights him), enemies close to them and to him; otherwise they keep near him.
func _undead_ai(b: SimUnit, h: SimUnit) -> void:
	if b.is_stunned() or b.cast_phase != SimUnit.CastPhase.NONE:
		return
	var marked := marked_for(h, b.pos)
	if marked != null and _enemy(b.team, marked) and not b.is_disarmed():
		if b.order != O.ATTACK_UNIT or b.order_target != marked.id:
			w.orders.issue(b, {"type": O.ATTACK_UNIT, "target": marked.id}, false)
		return
	var busy := b.order_from_player and b.order != O.NONE
	if busy and b.order != O.ATTACK_MOVE:
		return
	var tgt: SimUnit = null
	if h.alive:
		var ot := w.get_unit(h.atk_target)
		if ot != null and ot.alive and ot.team != b.team and not ot.is_ward() and w.vision.sees(b.team, ot) \
				and ot.pos.distance_to(b.pos) < LEASH and not (ot.is_building() and ot.is_invulnerable()):
			tgt = ot
	if tgt == null:
		var best_key := INF
		var around: Vector2 = h.pos if h.alive else b.pos
		for o: SimUnit in w.query(b.pos, b.acquire_range + 150.0, true):
			if not _enemy(b.team, o) or not w.vision.sees(b.team, o):
				continue
			if o.team == C.NEUTRAL and o.atk_target != b.id and o.atk_target != h.id:
				continue
			if o.pos.distance_to(around) > 1000.0:
				continue
			var key := b.edge_distance(o) - (500.0 if o.is_hero() else 0.0) - (800.0 if o.atk_target == h.id else 0.0)
			if key < best_key:
				best_key = key
				tgt = o
	if tgt != null and not b.is_disarmed():
		if not busy and (b.order != O.ATTACK_UNIT or b.order_target != tgt.id):
			w.orders.issue(b, {"type": O.ATTACK_UNIT, "target": tgt.id}, false)
		return
	if busy or not h.alive:
		return
	var d := b.pos.distance_to(h.pos)
	if d > FOLLOW:
		var i: int = (undead.get(h.id, []) as Array).find(b.id)
		var spot := h.pos + Vector2.from_angle(h.facing + PI * 0.8 + 0.5 * float(i)) * 180.0
		if not w.map.is_walkable(spot):
			spot = h.pos
		if b.order != O.MOVE or b.order_point.distance_to(spot) > 120.0:
			w.orders.issue(b, {"type": O.MOVE, "point": spot}, false)
	elif b.order == O.MOVE and not b.order_from_player and d < FOLLOW * 0.6:
		w.orders.issue(b, {"type": O.STOP}, false)

# ---- Fiend Edge ----------------------------------------------------------------------------------------------------------

## Fiend Edge as a critical strike source (SimCombat.crit_sources); off while broken.
func crit_source(u: SimUnit) -> Dictionary:
	if u.ability_level_of("fiend_edge") <= 0 or u.is_broken():
		return {}
	return {"key": "fiend_edge", "chance": ab.val(u, "fiend_edge", "chance"), "mult": ab.val(u, "fiend_edge", "crit")}

## A Fiend Edge critical landed for `dealt`: every ally within 800 of him (him too, not buildings or wards) heals a
## share of it.
func fiend_drain(u: SimUnit, t: SimUnit, dealt: float) -> void:
	if u == null or not u.alive or dealt <= 0.0:
		return
	var amt := dealt * ab.val(u, "fiend_edge", "drain")
	var r := ab.val(u, "fiend_edge", "radius")
	var healed: Array = []
	for o: SimUnit in w.query(u.pos, r, true):
		if o.team != u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.is_invulnerable():
			continue
		if w.combat.heal(o, amt, u) > 0.0 or o == u:
			healed.append(o.id)
	w.events.append({"t": "fiend_edge", "u": u.id, "target": t.id, "amount": amt, "healed": healed})

# ---- Unfallen ----------------------------------------------------------------------------------------------------------

## SimCombat.kill asks first: true when the blow does not end him yet (he falls for 3 s instead). In his last seconds
## a killing blow ends him as usual, with the blast (blast_now).
func catch_death(t: SimUnit, killer: SimUnit) -> bool:
	if not t.is_hero() or t.ability_level_of("unfallen") <= 0:
		return false
	if not t.get_modifier(RISEN).is_empty():
		_blast(t)
		t.remove_modifier(RISEN)
		_fallen.erase(t.id)
		return false
	if not t.get_modifier(FALLEN).is_empty():
		return true                              # already lying there (invulnerable): nothing more to take
	var delay := ab.val(t, "unfallen", "delay")
	t.hp = 1.0
	w.orders.clear(t)
	if not t.channel.is_empty():
		w.orders.cancel_channel(t)
	t.knock = {}
	t.leap = {}
	t.hop = {}
	t.path = PackedVector2Array()
	t.moving = false
	# what enemies put on him goes; he lies there out of reach
	for i in range(t.modifiers.size() - 1, -1, -1):
		var m: Dictionary = t.modifiers[i]
		if bool(m.get("debuff", false)) or int(m.get("from_team", t.team)) != t.team:
			t.modifiers.remove_at(i)
	t.add_modifier({"id": FALLEN, "source": t.id, "expires": w.time + delay + 1.0, "stun": true, "invulnerable": true,
		"untargetable": true, "no_regen": true, "fallen": true, "dispel": "", "fx": "unfallen_fallen"})
	t.refresh_stats()
	_fallen[t.id] = {"killer": killer.id if killer != null else -1, "rise_at": w.time + delay, "end_at": -1.0}
	w.events.append({"t": "unfallen_fall", "u": t.id, "killer": killer.id if killer != null else -1, "delay": delay})
	return true

func _rise(t: SimUnit, f: Dictionary) -> void:
	t.remove_modifier(FALLEN)
	var dur := ab.val(t, "unfallen", "duration")
	var pct := ab.val(t, "unfallen", "bonus")
	t.refresh_stats()
	t.add_modifier({"id": RISEN, "source": t.id, "expires": w.time + dur + 1.0, "dispel": "", "fx": "unfallen_risen",
		"stats": {"base_damage_pct": pct, "armor": maxf(0.0, t.armor) * pct, "move_speed_pct": pct,
		"attack_speed_pct": pct}})
	t.refresh_stats()
	t.hp = t.max_hp
	f.end_at = w.time + dur
	w.events.append({"t": "unfallen_rise", "u": t.id, "dur": dur})

## His life ends: every unit within 400, allies too, is thrown 300 away from him; a slam into a wall, tree or unit
## stuns for 0.5 s (SimAbilities._impact, ability BLAST).
func _blast(t: SimUnit) -> void:
	var r := ab.val(t, "unfallen", "radius")
	ab._cast_seq += 1
	var seq := ab._cast_seq
	var hit: Array = []
	for o: SimUnit in w.query(t.pos, r, true):
		if o == t or not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.is_invulnerable():
			continue
		if t.edge_distance(o) > r:
			continue
		if o.team != t.team and not ab.can_debuff(o, t.team):
			continue
		var dir := o.pos - t.pos
		if dir.length() < 1.0:
			dir = Vector2.from_angle(float(o.id) * 2.39996)
		ab.start_push(o, dir.normalized() * PUSH_SPEED * ab.val(t, "unfallen", "push") / 300.0, t.id, t.team, BLAST,
			t.ability_level_of("unfallen"), seq)
		hit.append(o.id)
	w.events.append({"t": "unfallen_blast", "u": t.id, "pos": t.pos, "radius": r, "hits": hit})

## The stun a slam during the blast gives (SimAbilities._impact).
func blast_stun(src_id: int) -> float:
	var s := w.get_unit(src_id)
	return ab.val(s, "unfallen", "crash_stun") if s != null else 0.5

## Lying dead (bots and the view read it).
func is_fallen(u: SimUnit) -> bool:
	return u != null and _fallen.has(u.id) and not u.get_modifier(FALLEN).is_empty()

## Seconds of his last life left (0 when not risen).
func risen_left(u: SimUnit) -> float:
	var f: Dictionary = _fallen.get(u.id, {})
	return maxf(0.0, float(f.end_at) - w.time) if not f.is_empty() and float(f.end_at) > 0.0 else 0.0

# ---- Per tick ----------------------------------------------------------------------------------------------------------

func tick() -> void:
	if w.tick % 30 == 0:
		_prune_bodies()
	for id in _fallen.keys():
		var t := w.get_unit(int(id))
		var f: Dictionary = _fallen[id]
		if t == null or not t.alive:
			_fallen.erase(id)
			continue
		if float(f.end_at) < 0.0:
			t.hp = 1.0
			if w.time >= float(f.rise_at):
				_rise(t, f)
		elif w.time >= float(f.end_at):
			var killer := w.get_unit(int(f.killer))
			w.combat.kill(t, killer)              # the blast goes off in catch_death
	for id in _weak.keys():
		var wu := w.get_unit(int(id))
		if wu == null or not wu.alive or wu.get_modifier("grip_weak").is_empty():
			_weak.erase(id)
		else:
			_weakness(wu)
	if undead.is_empty():
		return
	for hid in undead.keys():
		var h := w.get_unit(int(hid))
		var list: Array = (undead[hid] as Array).filter(func(id): return w.valid(int(id)) and w.get_unit(int(id)).alive)
		undead[hid] = list
		if h == null:
			continue
		for id in list:
			var b := w.get_unit(int(id))
			if (w.tick + b.id) % UNDEAD_THINK == 0:
				_undead_ai(b, h)
