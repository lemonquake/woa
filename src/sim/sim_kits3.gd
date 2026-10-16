class_name SimKits3
extends RefCounted
## The kits of Roydo, the Anomaly and Blau, the Master Tactician (run 2026-10-16; the owner's kits, see
## docs/HANDOFF.md). Called by SimAbilities: cast(), update_effect() for their effects, tick() for boulders, turrets and
## the Upgrade Staff's Pilot Turret, and by SimCombat for Dark Matter Skin (on_damaged) and turret shots
## (turret_snapshot).
##
## Roydo: Grip of the Ruler throws one unit (enemy heroes first) to the middle of an area over 0.8 s, then the area is
## hit and stunned; Void Rush weakens enemies (status resistance and damage dealt) and strengthens allies (armor and
## speed) around him; Dark Matter Skin sometimes returns part of a hit to every enemy near him; Anomaly turns him into a
## ranged monster with a shorter base attack time and more damage.
## Blau: Bounce Shot's bullet passes through enemies and ricochets off trees, walls, boulders and other units; Summon
## Boulders rolls rocks that knock enemies back and then block every unit (phased ones too) for 10 s; Lay Trap leaps
## back and leaves a hidden snare; Place Turret builds a turret that shoots with a share of his attack (its procs too);
## with the Upgrade Staff, Pilot Turret puts him inside one.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const CASTS := ["grip_of_the_ruler", "void_rush", "anomaly", "bounce_shot", "summon_boulders", "lay_trap",
	"place_turret", "pilot_turret"]
const EFFECTS := ["grip", "bounce_shot", "blau_trap"]
const BOULDER_R := 58.0                     # boulder radius (game units)
const BULLET_R := 30.0                      # Bounce Shot's bullet radius against units
const SUBSTEP := 20.0                       # the bullet moves in steps this long so it never skips a thin obstacle
const TOSS_HEIGHT := 260.0                  # Grip of the Ruler's arc height at its middle
const TURRET_ID := "blau_turret"

var w: SimWorld
var ab: SimAbilities
var boulders: Array = []                    # {id, pos, vel, r, rest_at, until, team, src, cast, resting, cells}
var _boulder_hits := {}                     # cast id -> {unit id: true}: a unit is hurt once per cast
var _next_boulder := 1
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

func _movable(o: SimUnit) -> bool:
	return o.alive and not o.is_building() and not o.is_ward() and o.kind != K.COURIER and bool(o.def.can_move) \
		and float(o.def.move_speed) > 0.0 and not o.is_invulnerable()

func _land_spot(p: Vector2) -> Vector2:
	if w.map.is_walkable(p) and not blocks(p, 16.0):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"grip_of_the_ruler":
			_grip(u, aid, p)
		"void_rush":
			_void_rush(u, aid)
		"anomaly":
			var dur := ab.val(u, aid, "duration")
			u.add_modifier({"id": "anomaly", "source": u.id, "expires": w.time + dur, "fx": "anomaly",
				"stats": {"damage": ab.val(u, aid, "damage"), "range_form": ab.val(u, aid, "attack_range") - float(u.def.range)},
				"ranged_form": true, "proj_speed": ab.val(u, aid, "projectile_speed"), "bat_cut": ab.val(u, aid, "bat_cut")})
			u.refresh_stats()
			w.events.append({"t": "anomaly", "u": u.id, "dur": dur})
		"bounce_shot":
			_bounce_shot(u, aid, p)
		"summon_boulders":
			_summon_boulders(u, aid, p)
		"lay_trap":
			_lay_trap(u, aid)
		"place_turret":
			_place_turret(u, aid, p)
		"pilot_turret":
			if is_piloting(u):
				leave_turret(u)
			elif t != null:
				enter_turret(u, t)

## Effects owned by this kit; returns true when the effect is over.
func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"grip":
			return _update_grip(e)
		"bounce_shot":
			return _update_bullet(e)
		"blau_trap":
			return _update_trap(e)
	return true

## Cast rules beyond SimAbilities' own (the target and place checks). "" = fine.
func cast_error(u: SimUnit, aid: String, t: SimUnit, p: Vector2, check_target: bool) -> String:
	match aid:
		"pilot_turret":
			if not u.has_scepter():
				return "Needs the Upgrade Staff"
			if is_piloting(u):
				return ""
			if check_target:
				if t == null or not t.alive or String(t.def.id) != TURRET_ID or t.owner_id != u.id:
					return "Must target one of your turrets"
		"lay_trap":
			if u.is_rooted() or is_piloting(u):
				return "Rooted"
		"place_turret":
			if check_target and p != Vector2.INF and not w.map.is_walkable(p):
				return "Cannot build there"
	return ""

# ---- Roydo -------------------------------------------------------------------------------------------------------------

## Grip of the Ruler: one unit in the area is thrown to its middle over 0.8 s (enemy heroes first, then other enemies;
## with no enemy at all an ally, unharmed); when it lands the whole area is hit and stunned.
func _grip(u: SimUnit, aid: String, p: Vector2) -> void:
	var r := ab.val(u, aid, "radius")
	var heroes: Array = []
	var others: Array = []
	var allies: Array = []
	for o: SimUnit in w.query(p, r + 40.0):
		if o == u or not _movable(o) or o.pos.distance_to(p) > r + o.hull:
			continue
		if not o.knock.is_empty() or not o.leap.is_empty():
			continue
		if o.team != u.team:
			if not w.vision.sees(u.team, o) or not ab.can_debuff(o, u.team):
				continue
			(heroes if o.is_hero() else others).append(o)
		else:
			allies.append(o)
	var pool: Array = heroes if not heroes.is_empty() else (others if not others.is_empty() else allies)
	var center := _land_spot(p)
	var dur := ab.val(u, aid, "toss_time")
	var picked: SimUnit = null
	if not pool.is_empty():
		picked = pool[w.rng.randi_range(0, pool.size() - 1)]
		w.orders.cancel_channel(picked)
		picked.knock = {"from": picked.pos, "to": center, "t": 0.0, "dur": dur, "disable": true, "src": u.id,
			"air": true, "height": TOSS_HEIGHT, "z": 0.0}
		picked.path = PackedVector2Array()
		if picked.kind == K.NEUTRAL_CREEP and picked.team != u.team:
			w.ai.neutral_provoked(picked, u)
	_seq += 1
	w.effects.append({"kind": "grip", "ability": aid, "src": u.id, "team": u.team, "pos": center, "radius": r,
		"at": w.time + dur, "picked": picked.id if picked else -1, "ally": picked != null and picked.team == u.team,
		"damage": ab.val(u, aid, "damage"), "stun": ab.val(u, aid, "stun"), "seq": _seq})
	w.events.append({"t": "grip", "u": u.id, "target": picked.id if picked else -1, "from": picked.pos if picked else p,
		"pos": center, "radius": r, "dur": dur, "ally": picked != null and picked.team == u.team, "seq": _seq})

func _update_grip(e: Dictionary) -> bool:
	if w.time < float(e.at):
		return false
	var hits: Array = []
	for o: SimUnit in w.query(e.pos, float(e.radius) + 40.0, true):
		if not _enemy(int(e.team), o) or o.pos.distance_to(e.pos) > float(e.radius) + o.hull:
			continue
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false,
			"grip_of_the_ruler")
		if o.alive:
			w.status.apply(o, int(e.src), int(e.team), {"id": "stunned", "stun": true, "dur": float(e.stun), "fx": "stun"})
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(int(e.src))
			if src:
				w.ai.neutral_provoked(o, src)
	w.events.append({"t": "grip_slam", "u": int(e.src), "pos": e.pos, "radius": float(e.radius), "hits": hits,
		"target": int(e.picked), "seq": int(e.seq)})
	return true

## Void Rush: every enemy within 650 has lower status resistance and deals less damage; every ally (Roydo too) gains
## armor and move speed. 7 seconds.
func _void_rush(u: SimUnit, aid: String) -> void:
	var r := ab.val(u, aid, "radius")
	var dur := ab.val(u, aid, "duration")
	var foes: Array = []
	var friends: Array = []
	for o: SimUnit in w.query(u.pos, r + 40.0, true):
		if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or u.edge_distance(o) > r:
			continue
		if o.team == u.team:
			o.add_modifier({"id": "void_rush_buff", "source": u.id, "expires": w.time + dur, "fx": "void_rush_buff",
				"dispel": "basic", "stats": {"armor": ab.val(u, aid, "armor"), "move_speed_pct": ab.val(u, aid, "move_pct")}})
			o.refresh_stats()
			friends.append(o.id)
		elif not o.is_invulnerable():
			if w.status.apply(o, u.id, u.team, {"id": "void_rush", "dur": dur, "fx": "void_rush", "dispel": "basic",
					"stats": {"status_resist": -ab.val(u, aid, "status_cut"), "damage_out_pct": -ab.val(u, aid, "damage_cut")}}):
				foes.append(o.id)
			if o.kind == K.NEUTRAL_CREEP:
				w.ai.neutral_provoked(o, u)
	w.events.append({"t": "void_rush", "u": u.id, "pos": u.pos, "radius": r, "foes": foes, "friends": friends, "dur": dur})

## Dark Matter Skin (from SimCombat.deal_damage, after the blow): a chance to send part of the damage Roydo took to
## every enemy within 650 as magic damage, with a short heavy slow.
func on_damaged(t: SimUnit, amount: float) -> void:
	var lv := t.ability_level_of("dark_matter_skin")
	if lv <= 0 or t.is_broken() or amount < 1.0:
		return
	if not w.status.roll(t, "dark_matter_skin", ab.val(t, "dark_matter_skin", "chance")):
		return
	var back := amount * ab.val(t, "dark_matter_skin", "reflect")
	var r := ab.val(t, "dark_matter_skin", "radius")
	var hits: Array = []
	for o: SimUnit in w.query(t.pos, r + 40.0, true):
		if not _enemy(t.team, o) or t.edge_distance(o) > r:
			continue
		w.combat.deal_damage(t.id, t.team, t.is_hero(), o, back, C.DamageType.MAGICAL, false, "dark_matter_skin", true)
		if o.alive:
			w.status.apply(o, t.id, t.team, {"id": "dark_matter_slow", "dur": ab.val(t, "dark_matter_skin", "slow_duration"),
				"slow": ab.val(t, "dark_matter_skin", "slow"),
				"stats": {"attack_speed_pct": -ab.val(t, "dark_matter_skin", "attack_slow")}, "fx": "slow"})
		hits.append(o.id)
	w.events.append({"t": "dark_matter", "u": t.id, "pos": t.pos, "radius": r, "amount": back, "hits": hits})

# ---- Blau: Bounce Shot -------------------------------------------------------------------------------------------------

func _bounce_shot(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := p - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	u.facing = dir.angle()
	_seq += 1
	var start := u.pos + dir * (u.hull + 10.0)
	w.effects.append({"kind": "bounce_shot", "ability": aid, "src": u.id, "team": u.team, "pos": start, "dir": dir,
		"left": ab.val(u, aid, "distance"), "speed": ab.val(u, aid, "speed"), "bounces": int(ab.val(u, aid, "bounces")),
		"damage": ab.val(u, aid, "damage"), "max_hits": int(ab.val(u, aid, "max_hits")), "hits": {}, "inside": {},
		"touching": -1, "seq": _seq})
	w.events.append({"t": "bounce_shot", "u": u.id, "from": start, "dir": dir, "seq": _seq,
		"speed": ab.val(u, aid, "speed")})

## What the bullet at `p` (moving along `dir`) runs into: {normal, what, id} or {} when the way is clear. Units of
## the shooter's team (and his turrets) and buildings make it bounce; enemies do not (it passes through them).
func bullet_obstacle(p: Vector2, dir: Vector2, team: int, skip_unit := -1, shooter := -1) -> Dictionary:
	for b in boulders:
		var d: Vector2 = p - (b.pos as Vector2)
		if d.length() < float(b.r) + 8.0 and d.dot(dir) < 0.0:
			return {"normal": d.normalized(), "what": "boulder", "id": int(b.id)}
	var ti := w.map.tree_at(p, 52.0)
	if ti >= 0:
		var tp: Vector2 = w.map.trees[ti].pos
		var dn := p - tp
		if dn.dot(dir) < 0.0 or dn.length() < 30.0:
			return {"normal": dn.normalized() if dn.length() > 0.5 else -dir, "what": "tree", "id": ti}
	for o: SimUnit in w.query(p, 220.0):
		if not o.alive or o.id == skip_unit or o.id == shooter or o.is_ward() or o.kind == K.COURIER:
			continue
		if o.team != team and not o.is_building():
			continue                                   # enemies: passed through (hit elsewhere)
		var rr := o.hull * (0.85 if o.is_building() else 1.0) + 6.0
		var dv := p - o.pos
		if dv.length() < rr and dv.dot(dir) < 0.0:
			return {"normal": dv.normalized() if dv.length() > 0.5 else -dir, "what": "building" if o.is_building() else "unit",
				"id": o.id}
	if not w.map.is_walkable(p) and w.map.rock_at(w.map.world_to_cell(p)) == 0 and w.map.tree_at(p, 90.0) < 0:
		# a wall (cliff edge, rock, map edge): which axis of the step ran into it gives the normal (grid walls)
		var prev := p - dir * SUBSTEP
		var x_block := not _open_cell(prev + Vector2(dir.x * SUBSTEP, 0.0))
		var y_block := not _open_cell(prev + Vector2(0.0, dir.y * SUBSTEP))
		var n := -dir
		if x_block and not y_block:
			n = Vector2(-signf(dir.x), 0.0)
		elif y_block and not x_block:
			n = Vector2(0.0, -signf(dir.y))
		return {"normal": n, "what": "wall", "id": -1}
	return {}

func _open_cell(p: Vector2) -> bool:
	var c := w.map.world_to_cell(p)
	return w.map.is_walkable_cell(c) or w.map.rock_at(c) > 0

static func reflect(dir: Vector2, n: Vector2) -> Vector2:
	var r := dir - 2.0 * dir.dot(n) * n
	return r.normalized() if r.length() > 0.01 else -dir

func _update_bullet(e: Dictionary) -> bool:
	var travel: float = minf(float(e.speed) * C.DT, float(e.left))
	var moved := 0.0
	var done := false
	while moved < travel - 0.01 and not done:
		var step := minf(SUBSTEP, travel - moved)
		var dir: Vector2 = e.dir
		var np: Vector2 = (e.pos as Vector2) + dir * step
		var hit := bullet_obstacle(np, dir, int(e.team), int(e.touching), int(e.src))
		if not hit.is_empty():
			if int(e.bounces) <= 0:
				w.events.append({"t": "bounce_shot_bounce", "seq": e.seq, "pos": np, "normal": hit.normal, "what": hit.what,
					"last": true})
				done = true
				break
			e.bounces = int(e.bounces) - 1
			e.dir = reflect(dir, hit.normal)
			e.touching = int(hit.id) if hit.what == "unit" else -1
			w.events.append({"t": "bounce_shot_bounce", "seq": e.seq, "pos": np, "normal": hit.normal, "what": hit.what,
				"last": false, "dir": e.dir})
			# a step back out of the obstacle along the new direction
			e.pos = (e.pos as Vector2) + (e.dir as Vector2) * 4.0
			moved += step
			continue
		e.pos = np
		moved += step
		_bullet_hits(e)
	e.left = float(e.left) - travel
	if float(e.left) <= 0.0:
		done = true
	w.events.append({"t": "bounce_shot_move", "seq": e.seq, "pos": e.pos, "done": done})
	return done

## Enemies the bullet passes through: each takes the damage at most `max_hits` times, once per pass.
func _bullet_hits(e: Dictionary) -> void:
	var now_inside := {}
	for o: SimUnit in w.query(e.pos, BULLET_R + 120.0):
		if not _enemy(int(e.team), o) or o.pos.distance_to(e.pos) > BULLET_R + o.hull:
			continue
		now_inside[o.id] = true
		if (e.inside as Dictionary).has(o.id):
			continue
		var n := int(e.hits.get(o.id, 0))
		if n >= int(e.max_hits):
			continue
		e.hits[o.id] = n + 1
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, "bounce_shot")
		w.events.append({"t": "bounce_shot_hit", "seq": e.seq, "u": o.id, "src": e.src, "n": n + 1})
		if o.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(int(e.src))
			if src:
				w.ai.neutral_provoked(o, src)
	e.inside = now_inside

## Where a Bounce Shot fired from `from` along `dir` would go: the path's corners and how often each enemy would be
## passed {id: passes} (the targeting preview draws it, bots aim with it). No damage, no events. `prep` (trace_prep)
## holds the units near the path in packed arrays so many traces can share one gathering; `step` trades precision for
## speed (the bullet itself moves in SUBSTEP steps).
func trace_bullet(from: Vector2, dir: Vector2, team: int, dist: float, bounces: int, shooter := -1, step := SUBSTEP,
		prep: Dictionary = {}) -> Dictionary:
	if prep.is_empty():
		prep = trace_prep(from, dist, team, shooter)
	var bpos: PackedVector2Array = prep.bpos
	var brad: PackedFloat32Array = prep.brad
	var bid: PackedInt32Array = prep.bid
	var epos: PackedVector2Array = prep.epos
	var erad: PackedFloat32Array = prep.erad
	var eid: PackedInt32Array = prep.eid
	var pos := from
	var d := dir.normalized()
	var left := dist
	var corners: Array = [from]
	var passed := {}
	var inside := PackedByteArray()
	inside.resize(eid.size())
	var touching := -1
	while left > 0.0:
		var np := pos + d * step
		var hit := _trace_obstacle(np, d, touching, bpos, brad, bid, step)
		if not hit.is_empty():
			corners.append(np)
			if bounces <= 0:
				break
			bounces -= 1
			d = reflect(d, hit.normal)
			touching = int(hit.id) if hit.what == "unit" else -1
			pos += d * 4.0
			left -= step
			continue
		pos = np
		left -= step
		for i in eid.size():
			var near := pos.distance_squared_to(epos[i]) <= erad[i] * erad[i]
			if near and inside[i] == 0:
				passed[eid[i]] = int(passed.get(eid[i], 0)) + 1
			inside[i] = 1 if near else 0
	corners.append(pos)
	return {"corners": corners, "passed": passed}

## The units a trace from `from` can meet, gathered once: bouncers (the shooter's team, buildings; their contact
## radius) and enemies (their pass radius).
func trace_prep(from: Vector2, dist: float, team: int, shooter := -1) -> Dictionary:
	var bpos := PackedVector2Array()
	var brad := PackedFloat32Array()
	var bid := PackedInt32Array()
	var epos := PackedVector2Array()
	var erad := PackedFloat32Array()
	var eid := PackedInt32Array()
	for o: SimUnit in w.query(from, dist * 0.6 + 400.0):
		if not o.alive or o.id == shooter or o.is_ward() or o.kind == K.COURIER:
			continue
		if o.team == team or o.is_building():
			bpos.append(o.pos)
			brad.append(o.hull * (0.85 if o.is_building() else 1.0) + 6.0)
			bid.append(o.id)
		elif not o.is_invulnerable():
			epos.append(o.pos)
			erad.append(BULLET_R + o.hull)
			eid.append(o.id)
	return {"bpos": bpos, "brad": brad, "bid": bid, "epos": epos, "erad": erad, "eid": eid}

## bullet_obstacle against trace_prep's packed bouncers.
func _trace_obstacle(p: Vector2, dir: Vector2, skip_unit: int, bpos: PackedVector2Array, brad: PackedFloat32Array,
		bid: PackedInt32Array, step: float) -> Dictionary:
	for b in boulders:
		var db: Vector2 = p - (b.pos as Vector2)
		if db.length() < float(b.r) + 8.0 and db.dot(dir) < 0.0:
			return {"normal": db.normalized(), "what": "boulder", "id": int(b.id)}
	var ti := w.map.tree_at(p, 52.0)
	if ti >= 0:
		var dn := p - (w.map.trees[ti].pos as Vector2)
		if dn.dot(dir) < 0.0 or dn.length() < 30.0:
			return {"normal": dn.normalized() if dn.length() > 0.5 else -dir, "what": "tree", "id": ti}
	for i in bid.size():
		if bid[i] == skip_unit:
			continue
		var dv := p - bpos[i]
		if dv.length_squared() < brad[i] * brad[i] and dv.dot(dir) < 0.0:
			return {"normal": dv.normalized() if dv.length() > 0.5 else -dir, "what": "unit", "id": bid[i]}
	if not w.map.is_walkable(p) and w.map.rock_at(w.map.world_to_cell(p)) == 0 and w.map.tree_at(p, 90.0) < 0:
		var prev := p - dir * step
		var x_block := not _open_cell(prev + Vector2(dir.x * step, 0.0))
		var y_block := not _open_cell(prev + Vector2(0.0, dir.y * step))
		var n := -dir
		if x_block and not y_block:
			n = Vector2(-signf(dir.x), 0.0)
		elif y_block and not x_block:
			n = Vector2(0.0, -signf(dir.y))
		return {"normal": n, "what": "wall", "id": -1}
	return {}

# ---- Blau: boulders ------------------------------------------------------------------------------------------------------

## Summon Boulders: 3-6 boulders roll out ahead at random angles for 1-2 s. They bounce off each other, walls, trees and
## units; an enemy they run into is hurt (once per cast, whichever boulder) and knocked 200 back. Resting boulders block
## every walking unit, phased ones too, for 10 s.
func _summon_boulders(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := p - u.pos
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	u.facing = dir.angle()
	var n := int(ab.val(u, aid, "count"))
	var spread := ab.val(u, aid, "spread")
	_seq += 1
	var cast := _seq
	_boulder_hits[cast] = {}
	var made: Array = []
	for i in n:
		var base := -spread + 2.0 * spread * (float(i) + 0.5) / float(n)
		var a := dir.angle() + base + w.rng.randf_range(-0.12, 0.12)
		var bd := Vector2.from_angle(a)
		var roll := w.rng.randf_range(ab.val(u, aid, "roll_min"), ab.val(u, aid, "roll_max"))
		var speed := w.rng.randf_range(ab.val(u, aid, "speed_min"), ab.val(u, aid, "speed_max"))
		var at := u.pos + bd * (u.hull + BOULDER_R + 16.0 + 24.0 * float(i % 2))
		if not w.map.is_walkable(at):
			at = u.pos + bd * (u.hull + 8.0)
		var b := {"id": _next_boulder, "pos": at, "vel": bd * speed, "r": BOULDER_R, "decel": speed / roll,
			"rest_at": w.time + roll, "until": w.time + ab.val(u, aid, "duration"), "team": u.team, "src": u.id,
			"cast": cast, "resting": false, "cells": [], "damage": ab.val(u, aid, "damage"),
			"push": ab.val(u, aid, "push"), "spin": 0.0}
		_next_boulder += 1
		boulders.append(b)
		made.append({"id": b.id, "pos": at, "vel": b.vel})
	w.events.append({"t": "boulders", "u": u.id, "made": made, "dur": ab.val(u, aid, "duration")})

## Whether a circle at `p` with radius `r` overlaps a resting boulder (walking units cannot enter them).
func blocks(p: Vector2, r: float) -> bool:
	for b in boulders:
		if b.resting and p.distance_squared_to(b.pos) < pow(float(b.r) + r - 2.0, 2.0):
			return true
	return false

func _update_boulders() -> void:
	for i in range(boulders.size() - 1, -1, -1):
		var b: Dictionary = boulders[i]
		if w.time >= float(b.until):
			_unrest(b)
			boulders.remove_at(i)
			w.events.append({"t": "boulder_end", "id": b.id, "pos": b.pos})
			continue
		if b.resting:
			continue
		var v: Vector2 = b.vel
		var sp := v.length()
		sp = maxf(0.0, sp - float(b.decel) * C.DT)
		v = v.normalized() * sp if sp > 0.0 else Vector2.ZERO
		var np: Vector2 = (b.pos as Vector2) + v * C.DT
		# walls and trees
		if not _open_for_boulder(np, float(b.r) * 0.6):
			var x_ok := _open_for_boulder(Vector2(np.x, b.pos.y), float(b.r) * 0.6)
			var y_ok := _open_for_boulder(Vector2(b.pos.x, np.y), float(b.r) * 0.6)
			if not x_ok:
				v.x = -v.x * 0.5
			if not y_ok:
				v.y = -v.y * 0.5
			if x_ok and y_ok:
				v = -v * 0.5
			np = b.pos
			w.events.append({"t": "boulder_bump", "id": b.id, "pos": b.pos, "what": "wall"})
		# other boulders: push apart and trade the speed along the line between them
		for o in boulders:
			if o == b:
				continue
			var dv: Vector2 = np - (o.pos as Vector2)
			var min_d := float(b.r) + float(o.r)
			var dl := dv.length()
			if dl < min_d and dl > 0.01:
				var nrm := dv / dl
				var over := min_d - dl
				if o.resting:
					np += nrm * over
					var vn := v.dot(nrm)
					if vn < 0.0:
						v -= nrm * vn * 1.6
				else:
					np += nrm * over * 0.5
					o.pos = (o.pos as Vector2) - nrm * over * 0.5
					var rel := v - (o.vel as Vector2)
					var vn2 := rel.dot(nrm)
					if vn2 < 0.0:
						var imp := nrm * vn2 * 0.8
						v -= imp
						o.vel = (o.vel as Vector2) + imp
				w.events.append({"t": "boulder_bump", "id": b.id, "pos": np, "what": "boulder"})
		# units in the way: enemies hurt once per cast and knocked back; everyone shoved out of the boulder's way
		for o: SimUnit in w.query(np, float(b.r) + 100.0):
			if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or bool(o.def.flying):
				continue
			var dv2 := o.pos - np
			var reach := float(b.r) + o.hull
			if dv2.length() >= reach:
				continue
			var nrm2 := dv2.normalized() if dv2.length() > 0.5 else Vector2.from_angle(v.angle() + PI * 0.5)
			var enemy := _enemy(int(b.team), o)
			var hits: Dictionary = _boulder_hits.get(int(b.cast), {})
			if enemy and not hits.has(o.id):
				hits[o.id] = true
				w.combat.deal_damage(int(b.src), int(b.team), true, o, float(b.damage), C.DamageType.MAGICAL, false,
					"summon_boulders")
				if o.alive and ab.can_debuff(o, int(b.team)) and _movable(o):
					w.orders.cancel_channel(o)
					var to := _push_spot(o.pos, nrm2, float(b.push))
					o.knock = {"from": o.pos, "to": to, "t": 0.0, "dur": 0.3, "disable": true, "src": int(b.src)}
					o.path = PackedVector2Array()
				w.events.append({"t": "boulder_hit", "id": b.id, "u": o.id, "pos": o.pos})
				if o.kind == K.NEUTRAL_CREEP:
					var src := w.get_unit(int(b.src))
					if src:
						w.ai.neutral_provoked(o, src)
			elif o.knock.is_empty() and _movable(o):
				var side := o.pos + nrm2 * (reach - dv2.length() + 2.0)
				if w.map.is_walkable(side):
					o.pos = side
			# the boulder itself is slowed a little by the unit
			var vn3 := v.dot(-nrm2)
			if vn3 > 0.0:
				v -= -nrm2 * vn3 * 0.35
		b.pos = np
		b.vel = v
		b.spin = float(b.spin) + v.length() * C.DT / float(b.r)
		if sp <= 15.0 or w.time >= float(b.rest_at):
			_rest(b)

func _open_for_boulder(p: Vector2, r: float) -> bool:
	for off in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var q: Vector2 = p + off
		var c := w.map.world_to_cell(q)
		if not w.map.is_walkable_cell(c) and w.map.rock_at(c) == 0:
			return false
	for o: SimUnit in w.query(p, 420.0):
		if o.is_building() and o.pos.distance_to(p) < o.hull * 0.85 + r:
			return false
	return true

func _push_spot(from: Vector2, dir: Vector2, dist: float) -> Vector2:
	var best := from
	var d := 16.0
	while d <= dist:
		var q := from + dir * d
		if not w.map.is_walkable(q) or blocks(q, 16.0):
			break
		best = q
		d += 16.0
	return best

## A boulder comes to rest: its cells become unwalkable (paths go round it) and anyone inside steps out.
func _rest(b: Dictionary) -> void:
	b.resting = true
	b.vel = Vector2.ZERO
	b.cells = w.map.add_rock(b.pos, float(b.r) - 6.0)
	for o: SimUnit in w.query(b.pos, float(b.r) + 80.0):
		if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or bool(o.def.flying):
			continue
		var dv := o.pos - (b.pos as Vector2)
		var reach := float(b.r) + o.hull
		if dv.length() < reach:
			var nrm := dv.normalized() if dv.length() > 0.5 else Vector2.RIGHT
			var out := _land_spot((b.pos as Vector2) + nrm * (reach + 2.0))
			o.pos = out
			o.path = PackedVector2Array()
	w.events.append({"t": "boulder_rest", "id": b.id, "pos": b.pos})

func _unrest(b: Dictionary) -> void:
	if b.resting:
		w.map.remove_rock(b.cells)
		b.cells = []

# ---- Blau: Lay Trap ------------------------------------------------------------------------------------------------------

## Lay Trap: Blau leaps 400 back (over trees and units, landing on open ground) and leaves a snare where he stood. Once
## armed it is hidden from enemies (True Sight shows it); the first enemy to step on it is caught and rooted.
func _lay_trap(u: SimUnit, aid: String) -> void:
	var back := Vector2.from_angle(u.facing + PI)
	var dist := ab.val(u, aid, "leap")
	var to := u.pos + back * dist
	if not w.map.is_walkable(to) or blocks(to, u.hull):
		# the furthest open spot along the way, else the nearest open ground to the target
		var best := Vector2.INF
		var d := dist
		while d >= 80.0:
			var q := u.pos + back * d
			if w.map.is_walkable(q) and not blocks(q, u.hull):
				best = q
				break
			d -= 32.0
		to = best if best != Vector2.INF else _land_spot(to)
	var at := u.pos
	w.orders.cancel_channel(u)
	u.hop = {"from": u.pos, "to": to, "t": 0.0, "dur": ab.val(u, aid, "leap_time"), "z": 0.0, "height": 150.0,
		"ease": "out"}
	u.path = PackedVector2Array()
	_seq += 1
	w.effects.append({"kind": "blau_trap", "ability": aid, "src": u.id, "team": u.team, "pos": at,
		"arm_at": w.time + ab.val(u, aid, "arm_time"), "until": w.time + ab.val(u, aid, "trap_duration"),
		"radius": ab.val(u, aid, "trigger_radius"), "root": ab.val(u, aid, "root"), "seq": _seq})
	w.events.append({"t": "lay_trap", "u": u.id, "pos": at, "to": to, "dur": ab.val(u, aid, "leap_time"), "seq": _seq})

func _update_trap(e: Dictionary) -> bool:
	if w.time >= float(e.until):
		w.events.append({"t": "trap_end", "seq": e.seq, "pos": e.pos, "sprung": false})
		return true
	if w.time < float(e.arm_at) or w.tick % 2 != 0:
		return false
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(e.pos, float(e.radius) + 40.0):
		if not _enemy(int(e.team), o) or bool(o.def.flying) or not bool(o.def.can_move):
			continue
		var d := o.pos.distance_to(e.pos) - o.hull
		if d <= float(e.radius) and d < bd:
			bd = d
			best = o
	if best == null:
		return false
	var src := w.get_unit(int(e.src))
	var held := w.status.apply(best, int(e.src), int(e.team), {"id": "ensnared", "root": true, "dur": float(e.root),
		"fx": "ensnare"})
	if held and _movable(best):
		# the jaws close: the caught unit is pulled onto the trap
		best.knock = {"from": best.pos, "to": e.pos, "t": 0.0, "dur": 0.12, "disable": false, "src": int(e.src)}
		best.path = PackedVector2Array()
	if best.kind == K.NEUTRAL_CREEP and src:
		w.ai.neutral_provoked(best, src)
	w.events.append({"t": "trap_spring", "seq": e.seq, "pos": e.pos, "u": best.id, "src": e.src, "held": held,
		"dur": float(e.root)})
	return true

## Blau's traps a team can see: its own, and armed enemy traps only under True Sight where it has vision.
func trap_visible(team: int, e: Dictionary) -> bool:
	if int(e.team) == team:
		return true
	if w.time < float(e.arm_at):
		return w.vision.cell_visible(team, e.pos)
	if not w.vision.cell_visible(team, e.pos):
		return false
	for s in w.vision.true_sight[team]:
		if (s[0] as Vector2).distance_to(e.pos) <= float(s[1]):
			return true
	return false

# ---- Blau: turrets ---------------------------------------------------------------------------------------------------------

## Place Turret: a turret at the point (open ground nearest it), with health by level and a 35 s life.
func _place_turret(u: SimUnit, aid: String, p: Vector2) -> void:
	var at := _land_spot(p)
	var t := w.spawn(TURRET_ID, u.team, at)
	t.owner_id = u.id
	t.facing = (at - u.pos).angle() if at.distance_to(u.pos) > 1.0 else u.facing
	t.ward_expires = w.time + ab.val(u, aid, "duration")
	t.perm_stats = {"hp": ab.val(u, aid, "hp") - float(t.def.hp)}
	t.refresh_stats()
	t.hp = t.max_hp
	t.stacks["dmg_pct"] = ab.val(u, aid, "damage_pct")           # a script field: multiplayer snapshots carry it
	sync_turret(t, u)
	w.nudge_out(at, t.hull)
	w.events.append({"t": "turret_placed", "u": u.id, "turret": t.id, "pos": at})

## A turret's shown attack damage follows its owner's (its shots copy his attack when they leave, see turret_snapshot).
func sync_turret(t: SimUnit, owner: SimUnit) -> void:
	if owner == null:
		return
	var pct := turret_pct(t)
	t.dmg_min = (owner.dmg_min) * pct
	t.dmg_max = (owner.dmg_max) * pct
	t.bonus_damage = owner.bonus_damage * pct

## The share of Blau's attack a turret shoots with: Place Turret's level, his talents and the Upgrade Staff (live).
func turret_pct(t: SimUnit) -> float:
	var owner := w.get_unit(t.owner_id)
	if owner == null or owner.ability_level_of("place_turret") <= 0:
		return float(t.stacks.get("dmg_pct", 0.25))
	return ab.val(owner, "place_turret", "damage_pct")

## The attack a turret shot carries: Blau's attack scaled to the turret's share, with his critical strike, lifesteal
## and item procs (SimCombat runs his on-hit effects for it); credited to Blau.
func turret_snapshot(t: SimUnit, target: SimUnit) -> Dictionary:
	var owner := w.get_unit(t.owner_id)
	if owner == null:
		return {}
	var pct := turret_pct(t)
	var s := w.combat.attack_snapshot(owner, "")
	s.dmg_min = owner.dmg_min * pct
	s.dmg_max = owner.dmg_max * pct
	s.bonus = owner.bonus_damage * pct
	s.crit = w.combat.roll_crit(owner, target)
	s.ranged = true
	s.level_h = w.map.level_at(t.pos)
	s.turret = t.id
	return s

func is_turret(u: SimUnit) -> bool:
	return u != null and u.kind == K.SUMMON and String(u.def.id) == TURRET_ID

## Turret brains, every 0.1 s: shoot the enemy hero its owner is fighting, else the weakest enemy hero in range, else
## a creep it can finish with this shot, else the weakest enemy in range.
func _turret_ai(t: SimUnit) -> void:
	var owner := w.get_unit(t.owner_id)
	sync_turret(t, owner)
	if t.atk_phase == SimUnit.AtkPhase.WINDUP:
		return
	var r := t.attack_range
	var best: SimUnit = null
	var best_key := INF
	var owner_target := owner.atk_target if owner != null and owner.alive else -1
	if owner != null and is_piloting(owner) and owner.order_target >= 0:
		owner_target = owner.order_target
	var shot := (t.dmg_min + t.dmg_max) * 0.5 + t.bonus_damage
	for o: SimUnit in w.query(t.pos, r + 140.0, true):
		if not _enemy(t.team, o) or t.edge_distance(o) > r or not w.vision.sees(t.team, o):
			continue
		var key := 0.0
		if o.id == owner_target:
			key = -100000.0
		elif o.is_hero():
			key = -50000.0 + o.hp
		elif is_turret(o):
			key = -30000.0 + o.hp
		else:
			var after := o.hp - shot * C.armor_multiplier(o.armor)
			key = (-20000.0 + o.hp) if after <= 0.0 else o.hp
		if key < best_key:
			best_key = key
			best = o
	if best == null:
		# nothing else in range: enemy buildings (towers, barracks) take its shots
		for o: SimUnit in w.query(t.pos, r + 420.0, true):
			if o.alive and o.team != t.team and o.is_building() and not o.is_invulnerable() and t.edge_distance(o) <= r:
				best = o
				break
	if best == null:
		return
	if t.order != O.ATTACK_UNIT or t.order_target != best.id:
		w.orders.issue(t, {"type": O.ATTACK_UNIT, "target": best.id}, false)

# ---- Pilot Turret (Upgrade Staff) -----------------------------------------------------------------------------------------

func is_piloting(u: SimUnit) -> bool:
	return not u.get_modifier("piloting").is_empty()

func piloted_turret(u: SimUnit) -> SimUnit:
	var m := u.get_modifier("piloting")
	return w.get_unit(int(m.get("turret", -1))) if not m.is_empty() else null

func enter_turret(u: SimUnit, t: SimUnit) -> void:
	if t == null or not t.alive or is_piloting(u):
		return
	for h in w.heroes:
		if h != u and piloted_turret(h) == t:
			return
	w.orders.cancel_channel(u)
	u.add_modifier({"id": "piloting", "source": u.id, "expires": INF, "invulnerable": true, "root": true,
		"phased": true, "hidden": true, "turret": t.id, "fx": "piloting"})
	u.pos = t.pos
	u.path = PackedVector2Array()
	u.refresh_stats()
	var bonus := ab.val(u, "pilot_turret", "hp")
	var before := t.hp
	t.add_modifier({"id": "piloted", "source": u.id, "expires": INF, "stats": {"hp": bonus}, "fx": "piloted"})
	t.refresh_stats()
	t.hp = minf(t.max_hp, before + bonus)
	w.combat.disjoint(u)
	w.events.append({"t": "pilot_in", "u": u.id, "turret": t.id})

func leave_turret(u: SimUnit, forced := false) -> void:
	var t := piloted_turret(u)
	u.remove_modifier("piloting")
	u.refresh_stats()
	if t != null:
		var before := t.hp
		t.remove_modifier("piloted")
		t.refresh_stats()
		if t.alive:
			t.hp = minf(t.max_hp, before)
	var base := t.pos if t != null else u.pos
	var out := _land_spot(base + Vector2.from_angle(u.facing + PI) * 90.0)
	u.pos = out
	u.path = PackedVector2Array()
	w.events.append({"t": "pilot_out", "u": u.id, "turret": t.id if t else -1, "forced": forced})

# ---- Per tick ---------------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not boulders.is_empty():
		_update_boulders()
	if not _boulder_hits.is_empty() and w.tick % 90 == 0:
		var live := {}
		for b in boulders:
			live[int(b.cast)] = true
		for k in _boulder_hits.keys():
			if not live.has(k):
				_boulder_hits.erase(k)
	for h in w.heroes:
		if String(h.def.id) == "blau":
			_sync_granted(h)
			if is_piloting(h):
				var t := piloted_turret(h)
				if t == null or not t.alive or not h.alive:
					if h.alive:
						leave_turret(h, true)
					else:
						h.remove_modifier("piloting")
				else:
					h.pos = t.pos
	if w.tick % 3 != 0:
		return
	for u in w.units:
		if u.alive and u.kind == K.SUMMON:
			if w.time >= u.ward_expires:
				w.events.append({"t": "turret_expired", "turret": u.id})
				w.combat.kill(u, null)
			elif is_turret(u):
				_turret_ai(u)

## Pilot Turret is on Blau's bar while he holds the Upgrade Staff, at his Place Turret's level.
func _sync_granted(h: SimUnit) -> void:
	var has := h.has_scepter()
	var on := h.abilities.has("pilot_turret")
	if has and not on:
		# before the ultimate, so Place Turret keeps its key (the last slot is always the ultimate's)
		var at := h.abilities.find("place_turret")
		if at >= 0:
			h.abilities.insert(at, "pilot_turret")
		else:
			h.abilities.append("pilot_turret")
		h.ability_ready["pilot_turret"] = maxf(float(h.ability_ready.get("pilot_turret", C.LONG_AGO)), C.LONG_AGO)
		h.autocast["pilot_turret"] = false
		w.events.append({"t": "granted", "u": h.id, "ability": "pilot_turret", "on": true})
	elif not has and on:
		if is_piloting(h):
			leave_turret(h, true)
		h.abilities.erase("pilot_turret")
		w.events.append({"t": "granted", "u": h.id, "ability": "pilot_turret", "on": false})
	if has:
		var lv := h.ability_level_of("place_turret")
		if h.ability_level_of("pilot_turret") != lv:
			h.ability_level["pilot_turret"] = lv
			h._val_cache.clear()
	elif h.ability_level.has("pilot_turret"):
		h.ability_level["pilot_turret"] = 0
