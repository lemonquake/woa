class_name SimKits10
extends RefCounted
## Gancho's and Lord Kaileh's kits (the owner's heroes, run 2026-10-21 b; see docs/HANDOFF.md). Called by
## SimAbilities (cast, cast_error, update_effect), SimCombat (on_attack_landed: Thorn Barbs; War Banner's hits) and
## SimWorld (tick). Tree Walk lives in SimMap (the tree walkers' grid) and SimOrders; Momentum in SimUnit.refresh_stats.
##
## Gancho, the Nature Whisperer
##   Tree Walk (innate): he walks through trees; 20% evasion within 250 of a tree.
##   Root Snare: a vine flies 1100 (1500 a second); the first enemy it touches takes magic damage and is rooted.
##   Seed Bomb: a seed bursts 0.6 s after landing: magic damage and a slow round it, and a young tree grows there
##   for 15 s (it blocks like any tree; Gancho walks through it).
##   Thorn Barbs: each attack leaves a thorn (up to 5 for 5 s, renewed together): magic damage a second and 4% slow each.
##   Angry Forest: for 7 s, every second each tree within 1000 lashes the nearest enemy within 350 of it (magic damage
##   and a short root, at most once per 1.5 s a unit; at most two lashes a unit a second); he attacks faster.
## Lord Kaileh, the Grand Cavalier
##   Momentum (innate): 30% of his bonus movement speed as attack damage (SimUnit).
##   Lance Charge: he charges to the point (up to its range, 1100 a second); the first enemy hero he meets rides the
##   lance to the end (held, as a hook holds) and is stunned there; others in the way take the damage and are pushed
##   aside.
##   Lance Sweep: physical damage round him, pushed 150 away and slowed.
##   War Banner: a banner (a ward that four attacks bring down) gives allies within 600 armor and attack speed and
##   slows enemies within 600 by 10% for 12 s.
##   Cavalry Charge: after the cast he charges up to 1600 at 1400 a second with six ghost riders, felling the trees in
##   his way; enemies in the 400 wide path take magic damage, are pushed aside and stunned. Nothing moves him meanwhile.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const CASTS := ["root_snare", "seed_bomb", "angry_forest", "lance_charge", "lance_sweep", "war_banner", "cavalry_charge"]
const EFFECTS := ["root_snare", "seed_bomb"]
const THORNS := "thorn_barbs"               # the slow on a unit carrying thorns (source: Gancho)
const WALK := "tree_walk"                   # his evasion near trees
const FOREST := "angry_forest"              # his attack speed while the forest is awake
const BANNER_UNIT := "war_banner"
const BANNER_BUFF := "war_banner"
const BANNER_SLOW := "war_banner_slow"
const UNSTOPPABLE := "cavalry_charge"
const THORN_STEP := 15                      # ticks between thorn damage (0.5 s)
const AURA_STEP := 8                        # ticks between aura and tree checks (~0.27 s)

var w: SimWorld
var ab: SimAbilities
var thorns := {}                            # target id -> {src, team, n, until}
var forests := {}                           # Gancho id -> {until, next, lv}
var lashed := {}                            # unit id -> game time of its last forest root
var charges := {}                           # Kaileh id -> {aid, dir, hit: {}, carried, lv, last}
var banners := {}                           # banner unit id -> {owner, team, radius, armor, attack_speed, slow}
var _seq := 0

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

func cast_error(u: SimUnit, aid: String, _t: SimUnit, _p: Vector2, _check_target: bool) -> String:
	if aid in ["lance_charge", "cavalry_charge"] and u.is_rooted():
		return "Rooted"
	return ""

func cast(u: SimUnit, aid: String, lv: int, _t: SimUnit, p: Vector2) -> void:
	match aid:
		"root_snare":
			_snare(u, aid, lv, p)
		"seed_bomb":
			_seed(u, aid, lv, p)
		"angry_forest":
			_forest(u, aid, lv)
		"lance_charge", "cavalry_charge":
			_charge(u, aid, lv, p)
		"lance_sweep":
			_sweep(u, aid)
		"war_banner":
			_banner(u, aid, p)

func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"root_snare":
			return _update_snare(e)
		"seed_bomb":
			return _update_seed(e)
	return true

## Where a dash from `from` along `dir` for `dist` ends: the farthest walkable spot on the line before the first
## blocked one (a charge stops at a tree, cliff or building).
func dash_end(from: Vector2, dir: Vector2, dist: float) -> Vector2:
	var d := 25.0
	var last := from
	while d <= dist:
		var q := from + dir * d
		if absf(q.x) >= SimMap.EDGE or absf(q.y) >= SimMap.EDGE or not w.map.is_walkable(q):
			break
		last = q
		d += 25.0
	if d > dist and w.map.is_walkable(from + dir * dist):
		last = from + dir * dist
	return last

# ---- Tree Walk ----------------------------------------------------------------------------------------------------------

## His evasion near trees, checked a few times a second.
func _tree_walk(h: SimUnit) -> void:
	var near := h.alive and not h.is_broken() and w.map.tree_at(h.pos, ab.val(h, WALK, "radius")) >= 0
	var has := not h.get_modifier(WALK).is_empty()
	if near and not has:
		h.add_modifier({"id": WALK, "source": h.id, "expires": INF, "stats": {"evasion": ab.val(h, WALK, "evasion")},
			"fx": "tree_walk"})
	elif not near and has:
		h.remove_modifier(WALK)

# ---- Root Snare ---------------------------------------------------------------------------------------------------------

func _snare(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var dir := (p - u.pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(u.facing)
	_seq += 1
	var dist := ab.val(u, aid, "distance")
	w.effects.append({"kind": "root_snare", "ability": aid, "src": u.id, "team": u.team, "pos": u.pos, "origin": u.pos,
		"dir": dir, "speed": ab.val(u, aid, "speed"), "left": dist, "width": ab.val(u, aid, "width"),
		"damage": ab.val(u, aid, "damage"), "root": ab.val(u, aid, "root"), "lv": lv, "seq": _seq, "hit": {}})
	w.events.append({"t": "root_snare", "u": u.id, "from": u.pos, "dir": dir, "dist": dist,
		"speed": ab.val(u, aid, "speed"), "seq": _seq})

func _update_snare(e: Dictionary) -> bool:
	var step: float = float(e.speed) * C.DT
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * minf(step, float(e.left))
	e.pos = to
	e.left = float(e.left) - step
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(to, float(e.width) + 200.0, true):
		if not _enemy(int(e.team), o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > float(e.width) * 0.5 + o.hull:
			continue
		var d := from.distance_squared_to(cp)
		if d < bd:
			bd = d
			best = o
	if best != null:
		e.hit[best.id] = true
		var src := w.get_unit(int(e.src))
		w.combat.deal_damage(int(e.src), int(e.team), true, best, float(e.damage), C.DamageType.MAGICAL, false, "root_snare")
		if best.alive and ab.can_debuff(best, int(e.team)):
			w.status.apply(best, int(e.src), int(e.team), {"id": "root_snare", "root": true, "dur": float(e.root),
				"fx": "rooted", "dispel": "basic"})
		if best.kind == K.NEUTRAL_CREEP and src != null:
			w.ai.neutral_provoked(best, src)
		w.events.append({"t": "root_snare_end", "u": int(e.src), "pos": best.pos, "target": best.id, "seq": int(e.seq),
			"dur": float(e.root)})
		return true
	if float(e.left) <= 0.0:
		w.events.append({"t": "root_snare_end", "u": int(e.src), "pos": to, "target": -1, "seq": int(e.seq)})
		return true
	return false

# ---- Seed Bomb ----------------------------------------------------------------------------------------------------------

func _seed(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var reach := ab.cast_range(u, aid, -1)
	if p.distance_to(u.pos) > reach:
		p = u.pos + (p - u.pos).normalized() * reach
	var delay := ab.val(u, aid, "delay")
	w.effects.append({"kind": "seed_bomb", "ability": aid, "src": u.id, "team": u.team, "pos": p, "at": w.time + delay,
		"radius": ab.val(u, aid, "radius"), "damage": ab.val(u, aid, "damage"), "slow": ab.val(u, aid, "slow"),
		"slow_t": ab.val(u, aid, "slow_duration"), "tree_t": ab.val(u, aid, "tree_duration"), "lv": lv})
	w.events.append({"t": "seed_bomb", "u": u.id, "from": u.pos, "pos": p, "delay": delay})

func _update_seed(e: Dictionary) -> bool:
	if w.time < float(e.at):
		return false
	var p: Vector2 = e.pos
	var r := float(e.radius)
	var src := w.get_unit(int(e.src))
	var hits: Array = []
	for o: SimUnit in w.query(p, r, true):
		if not _enemy(int(e.team), o) or o.pos.distance_to(p) > r + o.hull:
			continue
		hits.append(o.id)
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, "seed_bomb")
		if o.alive and ab.can_debuff(o, int(e.team)):
			w.status.apply(o, int(e.src), int(e.team), {"id": "seed_bomb_slow", "slow": float(e.slow),
				"dur": float(e.slow_t), "fx": "slowed", "dispel": "basic"})
		if o.kind == K.NEUTRAL_CREEP and o.alive and src != null:
			w.ai.neutral_provoked(o, src)
	# the young tree: blocks like any tree for its time (planted trees never regrow)
	var ti := w.map.plant_tree(p, w.time + float(e.tree_t))
	if ti >= 0:
		w.map.trees[ti]["seed"] = true
		w.vision.static_dirty = true
		w.nudge_out(w.map.trees[ti].pos, SimMap.CELL * 0.75)
		w.events.append({"t": "tree", "i": ti, "alive": true, "planted": true, "seed": true})
	w.events.append({"t": "seed_bomb_burst", "u": int(e.src), "pos": p, "radius": r, "hits": hits, "tree": ti})
	return true

# ---- Thorn Barbs --------------------------------------------------------------------------------------------------------

## A hero attack that landed (SimCombat.land_attack): Gancho's leaves a thorn.
func on_attack_landed(s: Dictionary, t: SimUnit) -> void:
	var src := w.get_unit(int(s.src))
	if src == null or src.ability_level_of(THORNS) <= 0 or src.is_broken() or s.has("ghost"):
		return
	if not t.alive or t.team == src.team or t.is_building() or t.is_ward() or t.kind == K.COURIER:
		return
	if not ab.can_debuff(t, src.team):
		return
	var rec: Dictionary = thorns.get(t.id, {})
	if rec.is_empty() or int(rec.src) != src.id or w.time >= float(rec.until):
		rec = {"src": src.id, "team": src.team, "n": 0, "until": 0.0}
	var dur := ab.val(src, THORNS, "duration")
	rec.n = mini(int(ab.val(src, THORNS, "max_thorns")), int(rec.n) + 1)
	rec.until = w.time + dur
	thorns[t.id] = rec
	w.status.apply(t, src.id, src.team, {"id": THORNS, "dur": dur, "slow": ab.val(src, THORNS, "slow") * float(rec.n),
		"fx": "thorns", "dispel": "basic", "charges": int(rec.n)})

## Thorns `src` has in `t` now (bots and the HUD read them).
func thorns_on(t: SimUnit) -> int:
	if t == null:
		return 0
	var rec: Dictionary = thorns.get(t.id, {})
	return int(rec.n) if not rec.is_empty() and w.time < float(rec.until) else 0

func _thorn_tick() -> void:
	var step := float(THORN_STEP) * C.DT
	for id in thorns.keys():
		var t := w.get_unit(int(id))
		var rec: Dictionary = thorns[id]
		if t == null or not t.alive or w.time >= float(rec.until) or t.get_modifier(THORNS).is_empty():
			thorns.erase(id)
			continue
		var src := w.get_unit(int(rec.src))
		var dps := ab.val(src, THORNS, "dps") if src != null else 0.0
		w.combat.deal_damage(int(rec.src), int(rec.team), true, t, dps * float(rec.n) * step, C.DamageType.MAGICAL,
			false, THORNS)

# ---- Angry Forest -------------------------------------------------------------------------------------------------------

func _forest(u: SimUnit, aid: String, lv: int) -> void:
	var dur := ab.val(u, aid, "duration")
	forests[u.id] = {"until": w.time + dur, "next": w.time + 0.35, "lv": lv}
	u.add_modifier({"id": FOREST, "source": u.id, "expires": w.time + dur,
		"stats": {"attack_speed": ab.val(u, aid, "attack_speed")}, "fx": "angry_forest"})
	u.refresh_stats()
	w.events.append({"t": "angry_forest", "u": u.id, "radius": ab.val(u, aid, "radius"), "dur": dur})

## Trees standing within `r` of `p` (indices).
func trees_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var c0 := w.map.world_to_cell(p - Vector2(r, r))
	var c1 := w.map.world_to_cell(p + Vector2(r, r))
	for cy in range(maxi(0, c0.y), mini(SimMap.N - 1, c1.y) + 1):
		for cx in range(maxi(0, c0.x), mini(SimMap.N - 1, c1.x) + 1):
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti >= 0 and w.map.trees[ti].alive and (w.map.trees[ti].pos as Vector2).distance_to(p) <= r:
				out.append(ti)
	return out

## Whether Gancho's forest is awake.
func forest_on(u: SimUnit) -> bool:
	return forests.has(u.id) and w.time < float(forests[u.id].until)

func _lash(u: SimUnit) -> void:
	var aid := "angry_forest"
	var reach := ab.val(u, aid, "reach")
	var dmg := ab.val(u, aid, "damage")
	var root := ab.val(u, aid, "root")
	var wait := ab.val(u, aid, "root_wait")
	var cap := int(ab.val(u, aid, "max_lashes"))
	var got := {}
	var shown := 0
	for ti in trees_near(u.pos, ab.val(u, aid, "radius")):
		var tp: Vector2 = w.map.trees[ti].pos
		var best: SimUnit = null
		var bd := INF
		for o: SimUnit in w.query(tp, reach, true):
			if not _enemy(u.team, o) or int(got.get(o.id, 0)) >= cap:
				continue
			var d := o.pos.distance_to(tp) - o.hull
			if d <= reach and d < bd:
				bd = d
				best = o
		if best == null:
			continue
		got[best.id] = int(got.get(best.id, 0)) + 1
		w.combat.deal_damage(u.id, u.team, true, best, dmg, C.DamageType.MAGICAL, false, aid)
		if best.alive and ab.can_debuff(best, u.team) and w.time - float(lashed.get(best.id, C.LONG_AGO)) >= wait:
			if w.status.apply(best, u.id, u.team, {"id": "forest_root", "root": true, "dur": root, "fx": "rooted",
					"dispel": "basic"}):
				lashed[best.id] = w.time
		if best.kind == K.NEUTRAL_CREEP and best.alive:
			w.ai.neutral_provoked(best, u)
		if shown < 40:
			shown += 1
			w.events.append({"t": "forest_lash", "u": u.id, "from": tp, "target": best.id})

# ---- Lance Charge and Cavalry Charge --------------------------------------------------------------------------------------

func _charge(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var from := u.pos
	var dir := p - from
	var reach := ab.cast_range(u, aid, -1)
	var dist := clampf(dir.length(), 250.0 if aid == "lance_charge" else 400.0, reach)
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var cavalry := aid == "cavalry_charge"
	if cavalry:
		ab.fell_trees_on(from, from + dir * dist, 150.0)        # the riders trample the trees in the way
	var to := dash_end(from, dir, dist)
	var speed := ab.val(u, aid, "speed")
	var dur := maxf(0.1, from.distance_to(to) / speed)
	u.facing = dir.angle()
	u.path = PackedVector2Array()
	u.moving = false
	u.knock = {"from": from, "to": to, "t": 0.0, "dur": dur, "disable": false, "charge": aid}
	charges[u.id] = {"aid": aid, "dir": dir, "hit": {}, "carried": -1, "lv": lv, "last": from}
	if cavalry:
		u.add_modifier({"id": UNSTOPPABLE, "source": u.id, "expires": w.time + dur + 0.1, "unstoppable": true,
			"stats": {"slow_resist": 1.0}, "fx": "cavalry_charge"})
		u.refresh_stats()
	w.events.append({"t": aid, "u": u.id, "from": from, "to": to, "dur": dur, "width": ab.val(u, aid, "width"),
		"riders": int(ab.val(u, aid, "riders")) if cavalry else 0})

## One tick of a charge: who it meets, who rides the lance, the end.
func _charge_tick(u: SimUnit, c: Dictionary) -> void:
	var aid := String(c.aid)
	var going: bool = u.alive and not u.knock.is_empty() and String(u.knock.get("charge", "")) == aid
	var dir: Vector2 = c.dir
	var carried := w.get_unit(int(c.carried))
	if going:
		var a: Vector2 = c.last
		var b := u.pos
		c.last = b
		var r := ab.val(u, aid, "width") * 0.5
		for o: SimUnit in w.query(b, r + u.hull + 120.0, true):
			if not _enemy(u.team, o) or c.hit.has(o.id) or o == carried:
				continue
			var cp := Geometry2D.get_closest_point_to_segment(o.pos, a, b)
			if cp.distance_to(o.pos) > r + o.hull:
				continue
			c.hit[o.id] = true
			if aid == "lance_charge" and o.is_hero() and int(c.carried) < 0 and ab.can_debuff(o, u.team) \
					and o.knock.is_empty() and o.leap.is_empty():
				# rides the lance to the end, held as a hook holds its catch
				c.carried = o.id
				carried = o
				w.orders.cancel_channel(o)
				o.knock = {"drag": true, "src": u.id}
				o.path = PackedVector2Array()
				w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage"), C.DamageType.PHYSICAL, false, aid)
				w.events.append({"t": "lance_charge_hit", "u": u.id, "target": o.id, "carried": true})
				continue
			_hit_aside(u, aid, o, cp, dir)
		if carried != null and carried.alive:
			var hold := u.pos + dir * (u.hull + carried.hull + 8.0)
			carried.pos = hold if w.map.is_walkable(hold) else u.pos
		return
	# the end: the rider comes off the lance in front of him and is stunned
	charges.erase(u.id)
	if aid == "cavalry_charge":
		u.remove_modifier(UNSTOPPABLE)
		u.refresh_stats()
	if carried != null:
		if not carried.knock.is_empty() and carried.knock.get("drag", false) and int(carried.knock.get("src", -1)) == u.id:
			carried.knock = {}
		if carried.alive:
			var front := u.pos + dir * (u.hull + carried.hull + 8.0)
			if w.map.is_walkable(front):
				carried.pos = front
			w.nudge_out(carried.pos, carried.hull)
			if ab.can_debuff(carried, u.team):
				w.status.apply(carried, u.id, u.team, {"id": "stunned", "stun": true, "dur": ab.val(u, aid, "stun"), "fx": "stun"})
			if carried.kind == K.NEUTRAL_CREEP:
				w.ai.neutral_provoked(carried, u)
	w.events.append({"t": aid + "_end", "u": u.id, "pos": u.pos, "target": carried.id if carried != null else -1})

## Someone in a charge's way: the damage, pushed off the line, and Cavalry Charge's stun.
func _hit_aside(u: SimUnit, aid: String, o: SimUnit, cp: Vector2, dir: Vector2) -> void:
	var cavalry := aid == "cavalry_charge"
	w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage"),
		C.DamageType.MAGICAL if cavalry else C.DamageType.PHYSICAL, false, aid)
	w.events.append({"t": aid + "_hit" if cavalry else "lance_charge_hit", "u": u.id, "target": o.id, "carried": false})
	if not o.alive:
		return
	if o.kind == K.NEUTRAL_CREEP:
		w.ai.neutral_provoked(o, u)
	if not ab.can_debuff(o, u.team):
		return
	var side := dir.orthogonal()
	var off := (o.pos - cp).dot(side)
	if absf(off) < 1.0:
		off = 1.0 if (o.id % 2) == 0 else -1.0
	slide(o, (side * signf(off) + dir * 0.35).normalized(), ab.val(u, aid, "push"), 0.3)
	if cavalry:
		w.status.apply(o, u.id, u.team, {"id": "stunned", "stun": true, "dur": ab.val(u, aid, "stun"), "fx": "stun"})

## An eased push (a stagger, as Gale Shot's slide): `dist` along `dir` over `dur`, shortened to open ground.
func slide(o: SimUnit, dir: Vector2, dist: float, dur: float) -> void:
	if not o.knock.is_empty() or not o.leap.is_empty() or o.has_flag("unstoppable"):
		return
	var to := o.pos
	var d := 20.0
	while d <= dist:
		var q := o.pos + dir * d
		if not w.map.is_walkable(q):
			break
		to = q
		d += 20.0
	if to.distance_to(o.pos) < 5.0:
		return
	w.orders.cancel_channel(o)
	o.knock = {"from": o.pos, "to": to, "t": 0.0, "dur": dur}
	o.path = PackedVector2Array()
	w.events.append({"t": "knockback", "u": o.id, "phys": false})

## Whether `u` is charging now (bots wait; the view plays the charge).
func charging(u: SimUnit) -> String:
	return String(charges[u.id].aid) if charges.has(u.id) else ""

# ---- Lance Sweep --------------------------------------------------------------------------------------------------------

func _sweep(u: SimUnit, aid: String) -> void:
	var r := ab.val(u, aid, "radius")
	var hits: Array = []
	for o: SimUnit in w.query(u.pos, r, true):
		if not _enemy(u.team, o) or u.edge_distance(o) > r:
			continue
		hits.append(o.id)
		w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage"), C.DamageType.PHYSICAL, false, aid)
		if not o.alive:
			continue
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
		if not ab.can_debuff(o, u.team):
			continue
		var away := o.pos - u.pos
		if away.length() < 1.0:
			away = Vector2.from_angle(u.facing)
		slide(o, away.normalized(), ab.val(u, aid, "push"), 0.25)
		w.status.apply(o, u.id, u.team, {"id": "lance_sweep_slow", "slow": ab.val(u, aid, "slow"),
			"dur": ab.val(u, aid, "slow_duration"), "fx": "slowed", "dispel": "basic"})
	w.events.append({"t": "lance_sweep", "u": u.id, "radius": r, "hits": hits, "facing": u.facing})

# ---- War Banner ---------------------------------------------------------------------------------------------------------

func _banner(u: SimUnit, aid: String, p: Vector2) -> void:
	var reach := ab.cast_range(u, aid, -1)
	if p.distance_to(u.pos) > reach:
		p = u.pos + (p - u.pos).normalized() * reach
	if not w.map.is_walkable(p):
		var c := w.map.nearest_walkable(w.map.world_to_cell(p))
		p = w.map.cell_center(c.x, c.y)
	var b := w.spawn(BANNER_UNIT, u.team, p)
	b.owner_id = u.id
	b.ward_expires = w.time + ab.val(u, aid, "duration")
	b.facing = u.facing
	banners[b.id] = {"owner": u.id, "team": u.team, "radius": ab.val(u, aid, "radius"), "armor": ab.val(u, aid, "armor"),
		"attack_speed": ab.val(u, aid, "attack_speed"), "slow": ab.val(u, aid, "slow")}
	w.events.append({"t": "war_banner", "u": u.id, "banner": b.id, "pos": p, "radius": ab.val(u, aid, "radius"),
		"dur": ab.val(u, aid, "duration")})

func _banner_tick() -> void:
	for id in banners.keys():
		var b := w.get_unit(int(id))
		if b == null or not b.alive or w.time >= b.ward_expires:
			banners.erase(id)
			continue
		var d: Dictionary = banners[id]
		var until_t := w.time + float(AURA_STEP) * C.DT + 0.15
		for o: SimUnit in w.query(b.pos, float(d.radius), true):
			if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER:
				continue
			if o.pos.distance_to(b.pos) > float(d.radius) + o.hull:
				continue
			if o.team == int(d.team):
				o.add_modifier({"id": BANNER_BUFF, "source": b.id, "expires": until_t, "aura": true, "fx": "war_banner",
					"stats": {"armor": float(d.armor), "attack_speed": float(d.attack_speed)}})
			elif not o.is_invulnerable() and not o.debuff_immune:
				o.add_modifier({"id": BANNER_SLOW, "source": b.id, "expires": until_t, "aura": true, "debuff": true,
					"slow": float(d.slow), "from_team": int(d.team)})

## Banners of `team` standing now (bots).
func banners_of(team: int) -> Array:
	var out: Array = []
	for id in banners:
		var b := w.get_unit(int(id))
		if b != null and b.alive and b.team == team:
			out.append(b)
	return out

# ---- Per tick ---------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not charges.is_empty():
		for id in charges.keys():
			var u := w.get_unit(int(id))
			if u == null:
				charges.erase(id)
				continue
			_charge_tick(u, charges[id])
	if not thorns.is_empty() and w.tick % THORN_STEP == 0:
		_thorn_tick()
	if not forests.is_empty():
		for id in forests.keys():
			var g := w.get_unit(int(id))
			var f: Dictionary = forests[id]
			if g == null or not g.alive or w.time >= float(f.until):
				forests.erase(id)
				continue
			if w.time >= float(f.next):
				f.next = float(f.next) + 1.0
				_lash(g)
	if w.tick % AURA_STEP == 0:
		if not banners.is_empty():
			_banner_tick()
		for h in w.heroes:
			if h.ability_level.has(WALK):
				_tree_walk(h)
