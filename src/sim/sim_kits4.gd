class_name SimKits4
extends RefCounted
## Azrael, the Death Dealer (the owner's hero and kit, 2026-10-17; see docs/HANDOFF.md). Called by SimAbilities:
## cast(), cast_error(), update_effect() for her door, tick() for Divine Darkness; by SimCombat for Soul Tap's charged
## slash (on_attack_landed) and Death Scythe (death_scythe, inside deal_damage); by SimOrders for her free flight.
##
## Soul Tap gathers the souls round a point: every unit there (enemies and allies, not her) gives her bonus damage for
## her next attack, more for heroes; that attack cleaves its full damage and spends the charge (15 s).
## Door of the End opens a spirit door near her; she and up to two allied heroes may walk in (hidden, invulnerable); a
## second cast sets the exit up to 800 away; when the door's time is up everyone inside steps out at the exit in a
## spirit blast that hits enemies around it (at the entrance if no exit was set).
## Death Scythe: her attacks and her spells sometimes strike as pure damage with bonus pure damage (1.5 s cooldown).
## Divine Darkness: her wings open for 25 s: free flight over cliffs and trees, more sight day and night, faster
## attacks; enemies within 700 lose part of their sight.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const CASTS := ["soul_tap", "door_of_the_end", "divine_darkness"]
const EFFECTS := ["azrael_door"]
const HER_KEYS := ["attack", "soul_tap", "door_of_the_end"]   # damage Death Scythe can turn pure

var w: SimWorld
var ab: SimAbilities
var _seq := 0

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func owns_effect(kind: String) -> bool:
	return kind in EFFECTS

func _enemy(team: int, o: SimUnit) -> bool:
	return o.alive and o.team != team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
		and not o.is_invulnerable()

func _land_spot(p: Vector2) -> Vector2:
	p = Vector2(clampf(p.x, -7900.0, 7900.0), clampf(p.y, -7900.0, 7900.0))
	if w.map.is_walkable(p):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

func cast(u: SimUnit, aid: String, _lv: int, _t: SimUnit, p: Vector2) -> void:
	match aid:
		"soul_tap":
			_soul_tap(u, aid, p)
		"door_of_the_end":
			_open_door(u, aid, p)
		"divine_darkness":
			_divine_darkness(u, aid)

func update_effect(e: Dictionary) -> bool:
	if String(e.kind) == "azrael_door":
		return _update_door(e)
	return true

## Cast rules beyond SimAbilities' own. "" = fine.
func cast_error(u: SimUnit, aid: String, _t: SimUnit, p: Vector2, check_target: bool) -> String:
	if in_door(u) and not (aid == "door_of_the_end" and exit_pending(u)):
		return "Inside the door"
	if aid == "door_of_the_end" and check_target and p != Vector2.INF:
		if p.x < -7900.0 or p.x > 7900.0 or p.y < -7900.0 or p.y > 7900.0:
			return "Cannot place a door there"
	return ""

# ---- Soul Tap ---------------------------------------------------------------------------------------------------------

## The units whose souls Soul Tap gathers at `p`: every living unit in the area but her, enemies and allies alike (not
## buildings, wards, couriers or units hidden in a door).
func souls_at(u: SimUnit, p: Vector2, r: float) -> Array:
	var out: Array = []
	for o: SimUnit in w.query(p, r + 40.0, true):
		if o == u or not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.has_flag("hidden"):
			continue
		if o.pos.distance_to(p) <= r + o.hull:
			out.append(o)
	return out

func _soul_tap(u: SimUnit, aid: String, p: Vector2) -> void:
	var r := ab.val(u, aid, "radius")
	var per := ab.val(u, aid, "per_unit")
	var extra := ab.val(u, aid, "per_hero")
	var bonus := 0.0
	var ids: Array = []
	var heroes := 0
	for o: SimUnit in souls_at(u, p, r):
		bonus += per + (extra if o.is_hero() else 0.0)
		if o.is_hero():
			heroes += 1
		ids.append(o.id)
	var dur := ab.val(u, aid, "duration")
	u.remove_modifier("soul_tap")
	if bonus > 0.0:
		u.add_modifier({"id": "soul_tap", "source": u.id, "expires": w.time + dur, "stats": {"damage": bonus},
			"souls": ids.size(), "fx": "soul_charge", "dispel": "basic"})
	u.refresh_stats()
	w.events.append({"t": "soul_tap", "u": u.id, "pos": p, "radius": r, "souls": ids, "heroes": heroes,
		"bonus": bonus, "dur": dur})

## Whether her next attack carries Soul Tap's charge (set on the attack's snapshot when it is released).
func soul_charged(u: SimUnit) -> bool:
	return u.ability_level_of("soul_tap") > 0 and not u.get_modifier("soul_tap").is_empty()

## A charged attack landed: the charge is spent and the blow cleaves its full damage round the target (Dota's cleave
## cone: 150 wide at her, 360 wide 650 away), ignoring armor.
func on_attack_landed(s: Dictionary, t: SimUnit, base_dmg: float) -> void:
	if not bool(s.get("soul", false)):
		return
	var u := w.get_unit(int(s.src))
	if u == null:
		return
	var m := u.get_modifier("soul_tap")
	u.remove_modifier("soul_tap")
	u.refresh_stats()
	var dir := t.pos - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var dist := ab.val(u, "soul_tap", "cleave_distance")
	var w0 := ab.val(u, "soul_tap", "cleave_start")
	var w1 := ab.val(u, "soul_tap", "cleave_end")
	var pct := ab.val(u, "soul_tap", "cleave_pct")
	var hits: Array = []
	if not t.is_building():
		for o: SimUnit in w.query(u.pos + dir * dist * 0.5, dist * 0.5 + w1):
			if o == t or not _enemy(u.team, o):
				continue
			var rel := o.pos - u.pos
			var along := rel.dot(dir)
			if along < 0.0 or along > dist:
				continue
			if absf(rel.dot(dir.orthogonal())) > lerpf(w0, w1, along / dist) * 0.5 + o.hull:
				continue
			w.combat.deal_damage(u.id, u.team, true, o, base_dmg * pct, C.DamageType.PHYSICAL, false, "soul_tap", false,
				{"ignore_armor": true, "no_spell_lifesteal": true})
			hits.append(o.id)
	w.events.append({"t": "soul_slash", "u": u.id, "target": t.id, "dir": dir, "dist": dist, "hits": hits,
		"souls": int(m.get("souls", 0))})

# ---- Door of the End --------------------------------------------------------------------------------------------------

func _door_of(u: SimUnit) -> Dictionary:
	for e in w.effects:
		if String(e.kind) == "azrael_door" and int(e.src) == u.id:
			return e
	return {}

## The door is open and its exit not yet set: the next cast of Door of the End places the exit (no mana, no cooldown).
func exit_pending(u: SimUnit) -> bool:
	var d := _door_of(u)
	return not d.is_empty() and not bool(d.get("has_exit", false))

func in_door(u: SimUnit) -> bool:
	return not u.get_modifier("in_door").is_empty()

## The open door of this hero's team that it may still walk into (null-like {} if none).
func door_for(h: SimUnit) -> Dictionary:
	for e in w.effects:
		if String(e.kind) == "azrael_door" and int(e.team) == h.team and w.time < float(e.until):
			return e
	return {}

func _open_door(u: SimUnit, aid: String, p: Vector2) -> void:
	var old := _door_of(u)
	if not old.is_empty():
		if not bool(old.get("has_exit", false)):
			_set_exit(u, old, p)
		return
	var dur := ab.val(u, aid, "duration")
	_seq += 1
	var at := _land_spot(p)
	var e := {"kind": "azrael_door", "ability": aid, "src": u.id, "team": u.team, "pos": at, "exit": at,
		"has_exit": false, "until": w.time + dur, "start": w.time, "inside": [], "seq": _seq,
		"damage": ab.val(u, aid, "damage"), "radius": ab.val(u, aid, "radius"), "allies": int(ab.val(u, aid, "allies")),
		"enter": ab.val(u, aid, "enter_radius")}
	w.effects.append(e)
	w.events.append({"t": "door_open", "u": u.id, "pos": at, "dur": dur, "seq": _seq, "team": u.team})

func _set_exit(u: SimUnit, e: Dictionary, p: Vector2) -> void:
	e.exit = _land_spot(p)
	e.has_exit = true
	w.events.append({"t": "door_exit_set", "u": u.id, "pos": e.exit, "from": e.pos, "seq": int(e.seq),
		"until": float(e.until), "team": int(e.team)})

## Called by SimAbilities.execute before mana and cooldown are paid: the exit cast is free.
func try_exit_cast(u: SimUnit, p: Vector2) -> bool:
	var d := _door_of(u)
	if d.is_empty() or bool(d.get("has_exit", false)):
		return false
	_set_exit(u, d, p)
	return true

## Who may step in: Azrael herself, and allied heroes (two at most) that were told to go to the door.
func _wants_in(o: SimUnit, e: Dictionary) -> bool:
	if not o.alive or o.team != int(e.team) or not o.is_hero() or in_door(o) or o.is_stunned():
		return false
	if o.pos.distance_to(e.pos) > float(e.enter) + o.hull:
		return false
	# walking onto it (a move order that ends at the door), or standing in it with no order
	if o.order == O.MOVE and (o.order_point as Vector2).distance_to(e.pos) < float(e.enter) + 80.0:
		return true
	return o.order == O.NONE or o.order == O.HOLD

func _update_door(e: Dictionary) -> bool:
	var src := w.get_unit(int(e.src))
	# stepping in
	if w.time < float(e.until):
		var allies := 0
		for id in e.inside:
			if int(id) != int(e.src):
				allies += 1
		for o: SimUnit in w.query(e.pos, float(e.enter) + 60.0, true):
			if not _wants_in(o, e):
				continue
			var her := o.id == int(e.src)
			if not her and allies >= int(e.allies):
				continue
			if not her:
				allies += 1
			_enter(o, e)
		return false
	# time is up: everyone inside comes out at the exit in a spirit blast
	var exit_p: Vector2 = e.exit
	var k := 0
	for id in e.inside:
		var o := w.get_unit(int(id))
		if o == null:
			continue
		o.remove_modifier("in_door")
		o.refresh_stats()
		if not o.alive:
			continue
		var off := Vector2.ZERO if k == 0 else Vector2.from_angle(TAU * float(k) / 3.0 + 0.5) * 110.0
		o.pos = _land_spot(exit_p + off)
		o.path = PackedVector2Array()
		o.facing = (exit_p - (e.pos as Vector2)).angle() if exit_p.distance_to(e.pos) > 1.0 else o.facing
		k += 1
		w.events.append({"t": "door_out", "u": o.id, "pos": o.pos, "seq": int(e.seq)})
	var hits: Array = []
	for o: SimUnit in w.query(exit_p, float(e.radius) + 40.0, true):
		if not _enemy(int(e.team), o) or o.pos.distance_to(exit_p) > float(e.radius) + o.hull:
			continue
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false,
			"door_of_the_end")
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP and src != null:
			w.ai.neutral_provoked(o, src)
	w.vision.add_source(int(e.team), exit_p, float(e.radius) + 150.0, 2.0)
	w.events.append({"t": "door_blast", "u": int(e.src), "pos": exit_p, "from": e.pos, "radius": float(e.radius),
		"hits": hits, "seq": int(e.seq), "brought": e.inside.size()})
	return true

func _enter(o: SimUnit, e: Dictionary) -> void:
	w.orders.cancel_channel(o)
	w.orders.clear(o)
	o.add_modifier({"id": "in_door", "source": int(e.src), "expires": float(e.until) + 1.0, "invulnerable": true,
		"hidden": true, "phased": true, "root": true, "disarm": true, "mute": true, "in_door": true, "fx": "in_door"})
	o.pos = e.pos
	o.path = PackedVector2Array()
	o.refresh_stats()
	w.combat.disjoint(o)
	(e.inside as Array).append(o.id)
	w.events.append({"t": "door_in", "u": o.id, "pos": e.pos, "seq": int(e.seq)})

# ---- Death Scythe -----------------------------------------------------------------------------------------------------

## Death Scythe on a blow from Azrael (her attacks and her spells): -1 when it does not strike, else the bonus pure
## damage to add (the blow itself turns pure). Pseudo-random like every chance passive, 1.5 s apart.
func death_scythe(src: SimUnit, t: SimUnit, key: String) -> float:
	if src == null or not (key in HER_KEYS) or src.ability_level_of("death_scythe") <= 0 or src.is_broken():
		return -1.0
	if t.is_building() or t.is_ward() or t.kind == K.COURIER or t.team == src.team:
		return -1.0
	if w.time < float(src.ability_ready.get("death_scythe", C.LONG_AGO)):
		return -1.0
	if not w.status.roll(src, "death_scythe", ab.val(src, "death_scythe", "chance")):
		return -1.0
	src.ability_ready["death_scythe"] = w.time + ab.val(src, "death_scythe", "proc_cooldown")
	var bonus := ab.val(src, "death_scythe", "bonus")
	w.events.append({"t": "death_scythe", "u": src.id, "target": t.id, "bonus": bonus, "key": key})
	return bonus

# ---- Divine Darkness --------------------------------------------------------------------------------------------------

func _divine_darkness(u: SimUnit, aid: String) -> void:
	var dur := ab.val(u, aid, "duration")
	u.remove_modifier("divine_darkness")
	u.add_modifier({"id": "divine_darkness", "source": u.id, "expires": w.time + dur, "fx": "divine_darkness",
		"stats": {"attack_speed": ab.val(u, aid, "attack_speed"), "vision_pct": ab.val(u, aid, "vision_bonus")},
		"day_vision": true, "flying": true, "free_flight": true, "radius": ab.val(u, aid, "radius"),
		"vision_cut": ab.val(u, aid, "vision_cut")})
	u.refresh_stats()
	w.events.append({"t": "divine_darkness", "u": u.id, "dur": dur})

## Free flight (SimOrders): straight over cliffs, trees and units while Divine Darkness lasts.
func flies(u: SimUnit) -> bool:
	return u.has_flag("free_flight")

func tick() -> void:
	if w.tick % 6 != 0:
		return
	for h in w.heroes:
		if String(h.def.id) != "azrael":
			continue
		var m := h.get_modifier("divine_darkness")
		var flying_last := _flying.has(h.id)
		if m.is_empty() or not h.alive:
			if flying_last:
				_flying.erase(h.id)
				_land(h)
			continue
		_flying[h.id] = true
		# the darkness round her: enemies within the radius lose part of their sight (refreshed every 0.2 s)
		var r := float(m.radius)
		for o: SimUnit in w.query(h.pos, r + 40.0, true):
			if not o.alive or o.team == h.team or o.is_building() or o.is_ward() or o.pos.distance_to(h.pos) > r + o.hull:
				continue
			var cur := o.get_modifier("darkness_blind")
			if cur.is_empty():
				o.add_modifier({"id": "darkness_blind", "source": h.id, "expires": w.time + 0.5, "debuff": true,
					"stats": {"vision_pct": -float(m.vision_cut)}, "day_vision": false, "fx": "blinded"})
				o.refresh_stats()
			else:
				cur.expires = w.time + 0.5

var _flying := {}                              # Azrael ids flying last check (to land them when it ends)

## The wings fold: she lands where she is, or on the nearest open ground; trees she lands among come down.
func _land(h: SimUnit) -> void:
	for ti in range(3):
		var t := w.map.tree_at(h.pos, 120.0)
		if t < 0:
			break
		w.cut_tree(t, h.pos, true)
	if not w.map.is_walkable(h.pos):
		h.pos = _land_spot(h.pos)
	h.path = PackedVector2Array()
	w.events.append({"t": "darkness_end", "u": h.id, "pos": h.pos})
