class_name SimKits5
extends RefCounted
## The kits of Airah, Burak and Ser Emelrich (hero_ideas.txt, run 2026-10-18 f; see docs/HANDOFF.md). Called by
## SimAbilities: cast(), cast_error(), update_effect() for their effects, tick() every tick, the wind-up channels
## (Overhead Cut, Giant Swing) and Steel Stance's toggle; by SimCombat for Rage, Reckless Swing's cleave, Berserk's held
## damage, Steel Stance's block, Tailwind's miss and the Wind Wall; by SimStatus for Unstoppable.
##
## Airah moves everyone: Gust drags the enemies it hits along toward its head (out 900, then back to her); Tailwind
## speeds an ally, lets it walk through units and blows ranged attacks aside; the Wind Wall stops enemy ranged attacks
## and slows walkers; Hurricane drags enemies to its middle, then throws them all out (a crash stuns).
## Burak fills with Rage (hurt, and hitting heroes) for attack speed; Axe Throw sticks an axe he can leap to;
## Reckless Swing cleaves and heals but he takes more; Unstoppable spends Rage to shorten a stun, root or hex; Berserk
## holds half the damage back and returns it later, unless he takes a hero down.
## Ser Emelrich's big hits have wind-ups everyone can see (a locked channel: orders wait, a stun, hex or silence breaks
## Overhead Cut's); Sweep shoves enemies to his left so they pile up; Steel Stance blocks from the front. While he winds
## up Giant Swing he is spell immune: no debuff lands or stays on him (SWING_GUARD_PIERCE lists the exceptions), so
## nothing stops the blow but his death.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const CASTS := ["gust", "tailwind", "wind_wall", "hurricane", "axe_throw", "reckless_swing", "berserk",
	"overhead_cut", "sweep", "giant_swing"]
const EFFECTS := ["gust", "wind_wall", "hurricane", "giant_swing_back"]
const WINDUPS := ["overhead_cut", "giant_swing"]
## Debuffs that still land on Ser Emelrich (and may break the swing) while he winds up Giant Swing. Each entry is a
## modifier id ("stunned", "hex", "silenced"...) or the id of the ability or item that puts it on ("shuriken_hook").
## Everything else is ignored while the guard lasts. Empty on purpose: the owner fills it.
const SWING_GUARD_PIERCE: Array[String] = []
const SWING_GUARD := "swing_guard"          # the modifier on him for the wind-up (flag "swing_guard", debuff immune)
## Pushes whose crash this kit scores (SimAbilities._impact): [damage key, stun key].
const CRASHES := {"hurricane": ["", "crash_stun"], "sweep": ["impact_damage", "impact_stun"]}
const WALL_BAND := 60.0                     # the Wind Wall slows walkers within this of its line
const AXE_PICKUP := 110.0                   # walking this close to a dropped axe picks it up
## Berserk's modifier ("berserk" is the Frenzy Mask's active, an item effect of its own)
const BERSERK := "burak_berserk"

var w: SimWorld
var ab: SimAbilities
var walls: Array = []                       # live Wind Walls: {a, b, team, until, seq} (projectiles test against them)
var axes: Array = []                        # Burak's thrown axes: {id, owner, team, pos, dir, left, state, on, ...}
var returns: Array = []                     # Berserk's held damage coming back: {u, by, left, per, next_at, until}
var _next_axe := 1
var _leaps := {}                            # Burak id -> {target, axe}: his leap to an axe lands with an attack
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
	p = Vector2(clampf(p.x, -SimMap.EDGE, SimMap.EDGE), clampf(p.y, -SimMap.EDGE, SimMap.EDGE))
	if w.map.is_walkable(p):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

static func _aim(u: SimUnit, p: Vector2) -> Vector2:
	var d := p - u.pos
	return Vector2.from_angle(u.facing) if d.length() < 1.0 else d.normalized()

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"gust":
			_gust(u, aid, p)
		"tailwind":
			_tailwind(u, aid, t)
		"wind_wall":
			_wind_wall(u, aid, p)
		"hurricane":
			_hurricane(u, aid, lv, p)
		"axe_throw":
			_axe_throw(u, aid, p)
		"reckless_swing":
			_reckless_swing(u, aid)
		"berserk":
			_berserk(u, aid)
		"overhead_cut", "giant_swing":
			_start_windup(u, aid, lv, p)
		"sweep":
			_sweep(u, aid, lv)

func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"gust":
			return _update_gust(e)
		"wind_wall":
			return _update_wall(e)
		"hurricane":
			return _update_hurricane(e)
		"giant_swing_back":
			if w.time < float(e.at):
				return false
			var u := w.get_unit(int(e.src))
			if u != null and u.alive:
				_cone_cut(u, "giant_swing", e.dir, float(e.distance), float(e.angle), float(e.damage), float(e.stun),
					float(e.armor_ignore), int(e.seq), true)
			return true
	return true

## Cast rules beyond SimAbilities' own. "" = fine.
func cast_error(u: SimUnit, aid: String, _t: SimUnit, _p: Vector2, _check_target: bool) -> String:
	match aid:
		"axe_throw":
			if axe_recast_ready(u):
				return ""
	return ""

# ---- Per tick -------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not walls.is_empty():
		for i in range(walls.size() - 1, -1, -1):
			if w.time >= float(walls[i].until):
				walls.remove_at(i)
	if not axes.is_empty():
		_update_axes()
	if not _leaps.is_empty():
		_update_leaps()
	if not returns.is_empty():
		_update_returns()
	for h in w.heroes:
		if not h.channel.is_empty() and String(h.channel.get("ability", "")) == "giant_swing":
			guard_sweep(h)
		if h.ability_level.has("rage"):
			_rage_tick(h)
		if h.stacks.has("berserk_until"):
			_berserk_tick(h)

# ---- Airah: Gust ----------------------------------------------------------------------------------------------------------

## Gust: the wind's head rushes 900 out, then turns back to Airah wherever she is, felling the trees it touches. Every
## enemy it touches takes the damage once and is caught: while the head is within reach it drags them toward itself,
## hardest close by (650 a second at the head, nothing at 420), so walking away pulls free and walking with it goes
## faster. A caught enemy dragged into a tree, cliff, building or another unit takes the crash damage once.
func _gust(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := _aim(u, p)
	u.facing = dir.angle()
	_seq += 1
	var start := u.pos + dir * (u.hull + 10.0)
	w.effects.append({"kind": "gust", "ability": aid, "src": u.id, "team": u.team, "pos": start, "dir": dir,
		"out_left": ab.val(u, aid, "distance"), "back": false, "speed": ab.val(u, aid, "speed"),
		"half": ab.val(u, aid, "width") * 0.5, "damage": ab.val(u, aid, "damage"),
		"crash": ab.val(u, aid, "crash_damage"), "drag": ab.val(u, aid, "drag"), "reach": ab.val(u, aid, "drag_reach"),
		"hit": {}, "crashed": {}, "t": 0.0, "seq": _seq})
	w.events.append({"t": "gust", "u": u.id, "from": start, "dir": dir, "seq": _seq, "speed": ab.val(u, aid, "speed"),
		"width": ab.val(u, aid, "width")})

func _update_gust(e: Dictionary) -> bool:
	var u := w.get_unit(int(e.src))
	e.t = float(e.t) + C.DT
	var step := float(e.speed) * C.DT
	var from: Vector2 = e.pos
	var to: Vector2
	var done := false
	if not bool(e.back):
		to = from + (e.dir as Vector2) * minf(step, float(e.out_left))
		e.out_left = float(e.out_left) - step
		if float(e.out_left) <= 0.0:
			e.back = true
	else:
		if u == null or not u.alive:
			done = true
			to = from
		else:
			var dv := u.pos - from
			if dv.length() <= step + u.hull:
				to = u.pos
				done = true
			else:
				e.dir = dv.normalized()
				to = from + (e.dir as Vector2) * step
	if float(e.t) > 3.0:
		done = true                                    # a guard: Airah outran her own wind
	e.pos = to
	var half := float(e.half)
	ab.fell_trees_on(from, to, half)
	for o: SimUnit in w.query(to, half + 200.0, true):
		if not _enemy(int(e.team), o) or (e.hit as Dictionary).has(o.id):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > half + o.hull:
			continue
		e.hit[o.id] = true
		w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.damage), C.DamageType.MAGICAL, false, "gust")
		w.events.append({"t": "gust_hit", "u": o.id, "src": int(e.src), "seq": int(e.seq)})
		if o.kind == K.NEUTRAL_CREEP and u != null:
			w.ai.neutral_provoked(o, u)
	# the drag on everyone it caught
	for id in e.hit:
		var o := w.get_unit(int(id))
		if o == null or not o.alive or not _movable(o) or not ab.can_debuff(o, int(e.team)):
			continue
		if not o.knock.is_empty() or not o.leap.is_empty() or not o.hop.is_empty():
			continue
		var d := to - o.pos
		var dist := d.length()
		if dist < 8.0 or dist > float(e.reach):
			continue
		var pull := float(e.drag) * (1.0 - dist / float(e.reach))
		var np := o.pos + d / dist * minf(pull * C.DT, dist)
		var what := _drag_block(o, np)
		if what == "":
			o.pos = np
		elif not (e.crashed as Dictionary).has(o.id):
			e.crashed[o.id] = true
			w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.crash), C.DamageType.MAGICAL, false, "gust")
			w.events.append({"t": "impact", "u": o.id, "what": what, "other": -1, "pos": np, "speed": pull})
			if what == "tree":
				var ti := w.map.tree_at(np, 110.0)
				if ti >= 0:
					w.cut_tree(ti, o.pos, true)
	w.events.append({"t": "gust_move", "seq": int(e.seq), "pos": to, "done": done, "back": bool(e.back)})
	return done

## What a unit dragged to `np` runs into: "tree", "cliff", "building", "unit" or "" (clear).
func _drag_block(o: SimUnit, np: Vector2) -> String:
	if not w.map.is_walkable(np):
		return "tree" if w.map.tree_at(np, 110.0) >= 0 else "cliff"
	for b: SimUnit in w.query(np, o.hull + 160.0):
		if b == o or not b.alive or b.is_ward() or b.kind == K.COURIER:
			continue
		var reach := (b.hull * 0.85 if b.is_building() else b.hull) + o.hull
		if np.distance_to(b.pos) < reach and o.pos.distance_to(b.pos) >= np.distance_to(b.pos):
			return "building" if b.is_building() else "unit"
	return ""

# ---- Airah: Tailwind, Wind Wall ---------------------------------------------------------------------------------------

## Tailwind: an ally (or Airah) moves faster and walks through units for 5 s, ranged attacks against it miss a share of
## the time (blown aside), and the slows on it are removed when it is cast (a basic dispel of slows only).
func _tailwind(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		t = u
	var removed := 0
	for i in range(t.modifiers.size() - 1, -1, -1):
		var m: Dictionary = t.modifiers[i]
		if bool(m.get("debuff", false)) and float(m.get("slow", 0.0)) > 0.0 and String(m.get("dispel", "")) != "" \
				and not m.get("stun", false) and not m.get("hex", false):
			t.modifiers.remove_at(i)
			removed += 1
	var dur := ab.val(u, aid, "duration")
	t.add_modifier({"id": "tailwind", "source": u.id, "expires": w.time + dur, "phased": true, "dispel": "basic",
		"ranged_miss": ab.val(u, aid, "ranged_miss"), "stats": {"move_speed_pct": ab.val(u, aid, "move_pct")},
		"fx": "tailwind"})
	t.refresh_stats()
	w.events.append({"t": "tailwind", "u": u.id, "target": t.id, "dur": dur, "cleansed": removed})

## The chance ranged attacks against `t` miss (Tailwind), 0 if none.
static func ranged_miss(t: SimUnit) -> float:
	var r := 0.0
	for m in t.modifiers:
		r = maxf(r, float(m.get("ranged_miss", 0.0)))
	return r

## Wind Wall: a wall 600 wide across Airah's aim, centred on the point. Enemy ranged attacks that touch it stop
## (SimCombat.update_projectiles asks wall_hit); enemies walking through it are slowed.
func _wind_wall(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := _aim(u, p)
	var along := dir.orthogonal()
	var half := ab.val(u, aid, "width") * 0.5
	var dur := ab.val(u, aid, "duration")
	_seq += 1
	var e := {"kind": "wind_wall", "ability": aid, "src": u.id, "team": u.team, "pos": p, "a": p - along * half,
		"b": p + along * half, "until": w.time + dur, "slow": ab.val(u, aid, "slow"), "seq": _seq}
	w.effects.append(e)
	walls.append(e)
	w.events.append({"t": "wind_wall", "u": u.id, "pos": p, "a": e.a, "b": e.b, "dur": dur, "seq": _seq})

func _update_wall(e: Dictionary) -> bool:
	if w.time >= float(e.until):
		w.events.append({"t": "wind_wall_end", "seq": int(e.seq)})
		return true
	if w.tick % 3 != 0:
		return false
	var a: Vector2 = e.a
	var b: Vector2 = e.b
	for o: SimUnit in w.query((a + b) * 0.5, a.distance_to(b) * 0.5 + WALL_BAND + 60.0):
		if not _enemy(int(e.team), o) or bool(o.def.flying) or not bool(o.def.can_move):
			continue
		if Geometry2D.get_closest_point_to_segment(o.pos, a, b).distance_to(o.pos) > WALL_BAND + o.hull:
			continue
		w.status.apply(o, int(e.src), int(e.team), {"id": "wind_wall_slow", "dur": 0.35, "slow": float(e.slow),
			"fx": "slow"})
	return false

## Whether an enemy ranged attack moving from `from` to `to` (fired by `team`) touches a Wind Wall: the point where it
## stops, else Vector2.INF.
func wall_hit(team: int, from: Vector2, to: Vector2) -> Vector2:
	for e in walls:
		if int(e.team) == team:
			continue
		var x = Geometry2D.segment_intersects_segment(from, to, e.a, e.b)
		if x != null:
			return x
	return Vector2.INF

# ---- Airah: Hurricane -------------------------------------------------------------------------------------------------

## Hurricane: 6 s at the point (not a channel). The trees inside fall when it forms; enemies inside are dragged to its
## middle and burn magic damage every half second; allies inside move faster. At the end every enemy still inside is
## thrown 450 straight out of the middle; a crash into a tree, cliff, building or unit stuns (SimAbilities._impact).
func _hurricane(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var r := ab.val(u, aid, "radius")
	var dur := ab.val(u, aid, "duration")
	_fell_in_circle(p, r)
	_seq += 1
	var seq := 8000000 + _seq
	w.effects.append({"kind": "hurricane", "ability": aid, "src": u.id, "team": u.team, "pos": p, "radius": r,
		"until": w.time + dur, "pull": ab.val(u, aid, "pull"), "dps": ab.val(u, aid, "dps"), "next_at": w.time + 0.5,
		"throw": ab.val(u, aid, "throw"), "ally_pct": ab.val(u, aid, "ally_move_pct"), "lv": lv, "seq": seq})
	w.events.append({"t": "hurricane", "u": u.id, "pos": p, "radius": r, "dur": dur, "seq": seq})

func _fell_in_circle(p: Vector2, r: float) -> void:
	var c0 := w.map.world_to_cell(p - Vector2(r, r))
	var c1 := w.map.world_to_cell(p + Vector2(r, r))
	for cy in range(maxi(c0.y, 0), mini(c1.y, SimMap.N - 1) + 1):
		for cx in range(maxi(c0.x, 0), mini(c1.x, SimMap.N - 1) + 1):
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti < 0 or not w.map.trees[ti].alive:
				continue
			var tp: Vector2 = w.map.trees[ti].pos
			if tp.distance_to(p) <= r:
				w.cut_tree(ti, p, true)

func _update_hurricane(e: Dictionary) -> bool:
	var p: Vector2 = e.pos
	var r := float(e.radius)
	var burn := w.time >= float(e.next_at)
	if burn:
		e.next_at = float(e.next_at) + 0.5
	var src := w.get_unit(int(e.src))
	for o: SimUnit in w.query(p, r + 60.0, true):
		if not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.pos.distance_to(p) > r + o.hull:
			continue
		if o.team == int(e.team):
			if o.is_hero() or o.is_creep() or o.kind == K.SUMMON:
				o.add_modifier({"id": "hurricane_wind", "source": int(e.src), "expires": w.time + 0.25,
					"stats": {"move_speed_pct": float(e.ally_pct)}, "fx": "tailwind"})
			continue
		if o.is_invulnerable():
			continue
		if burn:
			w.combat.deal_damage(int(e.src), int(e.team), true, o, float(e.dps) * 0.5, C.DamageType.MAGICAL, false,
				"hurricane")
			if o.kind == K.NEUTRAL_CREEP and src != null:
				w.ai.neutral_provoked(o, src)
		if not o.alive or not ab.can_debuff(o, int(e.team)) or not _movable(o) or not o.knock.is_empty():
			continue
		var d := p - o.pos
		if d.length() > 30.0:
			var np := o.pos + d.normalized() * minf(float(e.pull) * C.DT, d.length() - 30.0)
			if w.map.is_walkable(np):
				o.pos = np
	if w.time < float(e.until):
		return false
	var thrown: Array = []
	var v0 := push_speed_for(float(e.throw))
	for o: SimUnit in w.query(p, r + 60.0, true):
		if not _enemy(int(e.team), o) or o.pos.distance_to(p) > r + o.hull:
			continue
		if not ab.can_debuff(o, int(e.team)) or not _movable(o):
			continue
		var dir := o.pos - p
		dir = Vector2.from_angle(w.rng.randf() * TAU) if dir.length() < 1.0 else dir.normalized()
		ab.start_push(o, dir * v0, int(e.src), int(e.team), "hurricane", int(e.lv), int(e.seq))
		thrown.append(o.id)
	w.events.append({"t": "hurricane_end", "u": int(e.src), "pos": p, "radius": r, "thrown": thrown, "seq": int(e.seq)})
	return true

## The starting speed of a physics push (SimAbilities.update_motion, no obstacles) that carries a unit `dist` units.
static var _push_cache := {}

static func push_speed_for(dist: float) -> float:
	var key := roundi(dist)
	if _push_cache.has(key):
		return _push_cache[key]
	var lo := 100.0
	var hi := 4000.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _push_travel(mid) < dist:
			lo = mid
		else:
			hi = mid
	_push_cache[key] = (lo + hi) * 0.5
	return _push_cache[key]

## How far a physics push starting at `v0` slides on open ground (the same steps as SimAbilities.update_motion).
static func _push_travel(v0: float) -> float:
	var v := v0
	var z := 0.0
	var vz := 520.0 * clampf(v0 / 1000.0, 0.35, 1.1)
	var t := 0.0
	var x := 0.0
	while true:
		t += C.DT
		var air := z > 0.0 or vz > 0.0
		if air:
			vz -= SimAbilities.GRAVITY * C.DT
			z += vz * C.DT
			if z <= 0.0:
				z = 0.0
				vz = 0.0
		v = maxf(0.0, v - (SimAbilities.AIR_DRAG if air else SimAbilities.SKID) * C.DT)
		x += v * C.DT
		if (z <= 0.0 and v < 60.0) or t > 1.6:
			break
	return x

# ---- Burak: Rage ------------------------------------------------------------------------------------------------------------

## Rage a unit holds (0..100).
static func rage(u: SimUnit) -> float:
	return float(u.stacks.get("rage", 0.0))

func add_rage(u: SimUnit, amount: float) -> void:
	if amount <= 0.0 or not u.ability_level.has("rage"):
		return
	_set_rage(u, minf(ab.val(u, "rage", "max_rage"), rage(u) + amount))

func _set_rage(u: SimUnit, r: float) -> void:
	if not u.get_modifier(BERSERK).is_empty():
		r = ab.val(u, "rage", "max_rage")                 # Berserk: Rage locked at full
	u.stacks["rage"] = r
	var per10 := floorf(r / 10.0)
	var m := u.get_modifier("rage")
	var as_bonus := per10 * ab.val(u, "rage", "attack_speed_per_10")
	if m.is_empty() or int(m.get("charges", -1)) != int(r) or float((m.get("stats", {}) as Dictionary).get("attack_speed", -1.0)) != as_bonus:
		u.add_modifier({"id": "rage", "source": u.id, "expires": INF, "charges": int(r), "dispel": "",
			"stats": {"attack_speed": as_bonus}, "fx": "rage"})

## Burak was in a fight with a hero (hit one, or was hit by one): Rage waits 4 s before it drains.
func rage_fight(u: SimUnit) -> void:
	u.stacks["rage_at"] = w.time

## From SimCombat.deal_damage: the health he just lost, as Rage (1 per 1% of his health).
func on_damaged(t: SimUnit, amount: float, src: SimUnit) -> void:
	if src != null and src.is_hero() and src.team != t.team:
		rage_fight(t)
	add_rage(t, amount / maxf(1.0, t.max_hp) * 100.0 * ab.val(t, "rage", "per_health_pct"))

func _rage_tick(h: SimUnit) -> void:
	if not h.alive:
		if rage(h) > 0.0:
			_set_rage(h, 0.0)
		return
	if not h.get_modifier(BERSERK).is_empty():
		if rage(h) < ab.val(h, "rage", "max_rage"):
			_set_rage(h, ab.val(h, "rage", "max_rage"))
		return
	var r := rage(h)
	if r <= 0.0:
		if h.get_modifier("rage").is_empty():
			_set_rage(h, 0.0)
		return
	if w.time - float(h.stacks.get("rage_at", C.LONG_AGO)) < ab.val(h, "rage", "idle_time"):
		return
	_set_rage(h, maxf(0.0, r - ab.val(h, "rage", "decay") * C.DT))

# ---- Burak: attacks (Rage, Reckless Swing's cleave) -------------------------------------------------------------------------

## A hero's attack landed (SimCombat.land_attack, after the blow): Rage for Burak's hits on heroes, Reckless Swing's
## cleave.
func on_attack_landed(s: Dictionary, t: SimUnit, base_dmg: float) -> void:
	var src := w.get_unit(int(s.src))
	if src == null or t.team == src.team:
		return
	if t.is_hero() and src.ability_level.has("rage"):
		rage_fight(src)
		add_rage(src, ab.val(src, "rage", "per_hero_hit"))
	var rs := src.get_modifier("reckless_swing")
	if not rs.is_empty() and not src.is_ranged() and not t.is_building() and not t.is_ward():
		_cleave(src, t, base_dmg * float(rs.cleave), rs)

## Dota's cleave cone: from the attacker through the main target, 150 wide at the start, 360 at 650; physical damage
## that ignores armor, not on the main target, buildings, wards or couriers.
func _cleave(src: SimUnit, main: SimUnit, amount: float, m: Dictionary) -> void:
	var dir := main.pos - src.pos
	dir = Vector2.from_angle(src.facing) if dir.length() < 1.0 else dir.normalized()
	var dist := float(m.get("distance", 650.0))
	var hits: Array = []
	for o: SimUnit in w.query(src.pos + dir * dist * 0.5, dist * 0.5 + float(m.get("end_width", 360.0))):
		if o == main or not _enemy(src.team, o):
			continue
		var rel := o.pos - src.pos
		var along := rel.dot(dir)
		if along < 0.0 or along > dist:
			continue
		var half := lerpf(float(m.get("start_width", 150.0)), float(m.get("end_width", 360.0)), along / dist) * 0.5
		if absf(rel.dot(dir.orthogonal())) > half + o.hull:
			continue
		w.combat.deal_damage(src.id, src.team, true, o, amount, C.DamageType.PHYSICAL, false, "reckless_swing", false,
			{"ignore_armor": true, "no_spell_lifesteal": true})
		hits.append(o.id)
	w.events.append({"t": "cleave", "u": src.id, "target": main.id, "dir": dir, "dist": dist, "hits": hits,
		"key": "reckless_swing"})

func _reckless_swing(u: SimUnit, aid: String) -> void:
	var dur := ab.val(u, aid, "duration")
	u.add_modifier({"id": "reckless_swing", "source": u.id, "expires": w.time + dur, "cleave": ab.val(u, aid, "cleave"),
		"damage_taken": ab.val(u, aid, "damage_taken"), "start_width": ab.val(u, aid, "cleave_start"),
		"end_width": ab.val(u, aid, "cleave_end"), "distance": ab.val(u, aid, "cleave_distance"),
		"stats": {"lifesteal_ability": ab.val(u, aid, "lifesteal")}, "fx": "reckless"})
	u.refresh_stats()
	w.events.append({"t": "reckless_swing", "u": u.id, "dur": dur})

## How much more damage `t` takes from everything (Reckless Swing: +15%).
static func damage_taken(t: SimUnit) -> float:
	var r := 0.0
	for m in t.modifiers:
		r += float(m.get("damage_taken", 0.0))
	return r

# ---- Burak: Unstoppable ----------------------------------------------------------------------------------------------------

## From SimStatus.apply: a stun, root or hex from an enemy is landing on `t`. With Unstoppable ready and enough Rage it
## spends the Rage and returns the share of the effect's time it cuts (0 otherwise). Break stops it.
func unstoppable_cut(t: SimUnit, m: Dictionary) -> float:
	var aid := "unstoppable"
	if t.ability_level_of(aid) <= 0 or t.is_broken() or not t.alive:
		return 0.0
	if not (m.get("stun", false) or m.get("root", false) or m.get("hex", false)):
		return 0.0
	if ab.cooldown_left(t, aid) > 0.0:
		return 0.0
	var cost := ab.val(t, aid, "rage_cost")
	if rage(t) < cost:
		return 0.0
	_set_rage(t, rage(t) - cost)
	t.ability_ready[aid] = w.time + ab.ability_cooldown(t, aid)
	var cut := ab.val(t, aid, "cut")
	w.events.append({"t": "unstoppable", "u": t.id, "effect": String(m.get("id", "")), "cut": cut})
	return cut

# ---- Burak: Axe Throw ------------------------------------------------------------------------------------------------------

## Axe Throw: one axe (two in a 20 degree fork with the Upgrade Staff) flies 1000. The first enemy it meets takes the
## damage and the slow and the axe sticks in it; a tree or cliff catches it; at the end it drops. For 4 s Burak may
## cast again (free) to leap to it. A dropped axe is picked up by walking over it (half the cooldown left comes off);
## once the cooldown is over a lost axe is back in his hand. While an axe is gone his attacks deal 20% less.
func _axe_throw(u: SimUnit, aid: String, p: Vector2) -> void:
	var dir := _aim(u, p)
	u.facing = dir.angle()
	var dirs: Array = [dir]
	if u.has_scepter():
		var f := deg_to_rad(ab.val(u, aid, "fork")) * 0.5
		dirs = [dir.rotated(-f), dir.rotated(f)]
	_seq += 1
	var window := ab.val(u, aid, "recast_window")
	for d in dirs:
		var start: Vector2 = u.pos + (d as Vector2) * (u.hull + 8.0)
		axes.append({"id": _next_axe, "owner": u.id, "team": u.team, "pos": start, "dir": d,
			"left": ab.val(u, aid, "distance"), "speed": ab.val(u, aid, "speed"), "half": ab.val(u, aid, "width") * 0.5,
			"damage": ab.val(u, aid, "damage"), "slow": ab.val(u, aid, "slow"), "slow_t": ab.val(u, aid, "slow_duration"),
			"rage": ab.val(u, aid, "hero_rage"), "state": "fly", "on": -1, "recast_until": w.time + window,
			"cast": _seq})
		w.events.append({"t": "axe_throw", "u": u.id, "axe": _next_axe, "from": start, "dir": d,
			"speed": ab.val(u, aid, "speed")})
		_next_axe += 1
	_sync_axes(u)

## His axes away from his hands right now.
func axes_of(u: SimUnit) -> Array:
	return axes.filter(func(a): return int(a.owner) == u.id)

## An axe he may leap to now (landed, inside its recast window), or {}.
func leap_axe(u: SimUnit) -> Dictionary:
	var best := {}
	var best_key := INF
	for a in axes:
		if int(a.owner) != u.id or String(a.state) == "fly" or w.time >= float(a.recast_until):
			continue
		var on := w.get_unit(int(a.on))
		var key: float = (a.pos as Vector2).distance_to(u.pos)
		if on != null and on.alive:
			key -= 100000.0 if on.is_hero() and on.team != u.team else 50000.0
		if key < best_key:
			best_key = key
			best = a
	return best

func axe_recast_ready(u: SimUnit) -> bool:
	return u.ability_level_of("axe_throw") > 0 and not leap_axe(u).is_empty() and _leaps.get(u.id) == null

## The recast: Burak leaps to his axe (SimAbilities.execute calls this first; true when it leapt, free).
func try_axe_recast(u: SimUnit) -> bool:
	if not axe_recast_ready(u):
		return false
	if u.is_rooted():
		return true                                   # rooted: nothing happens, and nothing is spent
	var a := leap_axe(u)
	var on := w.get_unit(int(a.on))
	var to: Vector2 = a.pos
	if on != null and on.alive:
		var dv := u.pos - on.pos
		dv = Vector2.from_angle(on.facing) if dv.length() < 1.0 else dv.normalized()
		to = on.pos + dv * (u.hull + on.hull + 6.0)
	to = _land_spot(to)
	w.orders.cancel_channel(u)
	u.hop = {"from": u.pos, "to": to, "t": 0.0, "dur": ab.val(u, "axe_throw", "leap_time"), "z": 0.0, "height": 120.0}
	u.path = PackedVector2Array()
	u.facing = (to - u.pos).angle() if to.distance_to(u.pos) > 1.0 else u.facing
	_leaps[u.id] = {"target": on.id if on != null and on.alive else -1, "axe": int(a.id)}
	for o in axes:
		if int(o.owner) == u.id:
			o.recast_until = w.time                     # one leap a throw
	w.events.append({"t": "axe_leap", "u": u.id, "to": to, "target": on.id if on != null else -1,
		"dur": ab.val(u, "axe_throw", "leap_time")})
	return true

func _update_leaps() -> void:
	for id in _leaps.keys():
		var u := w.get_unit(int(id))
		var L: Dictionary = _leaps[id]
		if u == null or not u.alive:
			_leaps.erase(id)
			continue
		var t := w.get_unit(int(L.target))
		if not u.hop.is_empty():
			if t != null and t.alive:
				# the axe's target keeps moving: land beside it
				var dv := (u.hop.from as Vector2) - t.pos
				dv = Vector2.from_angle(t.facing) if dv.length() < 1.0 else dv.normalized()
				u.hop.to = _land_spot(t.pos + dv * (u.hull + t.hull + 6.0))
			continue
		_leaps.erase(id)
		_take_axe(u, int(L.axe), false)
		if t != null and t.alive and t.team != u.team and w.vision.sees(u.team, t):
			# the next attack starts at once
			w.orders.issue(u, {"type": O.ATTACK_UNIT, "target": t.id}, false)
			u.next_attack_at = minf(u.next_attack_at, w.time)
			u.facing = (t.pos - u.pos).angle()
		w.events.append({"t": "axe_leap_land", "u": u.id, "target": t.id if t != null else -1, "pos": u.pos})

func _take_axe(u: SimUnit, axe_id: int, halve: bool) -> void:
	for i in range(axes.size() - 1, -1, -1):
		if int(axes[i].id) == axe_id:
			axes[i]["gone"] = true
			axes.remove_at(i)
	if halve:
		var r := float(u.ability_ready.get("axe_throw", C.LONG_AGO))
		if r > w.time:
			u.ability_ready["axe_throw"] = w.time + (r - w.time) * 0.5
	w.events.append({"t": "axe_back", "u": u.id, "axe": axe_id, "picked": halve})
	_sync_axes(u)

## While an axe is gone his attacks deal 20% less (each axe away counts).
func _sync_axes(u: SimUnit) -> void:
	var n := axes_of(u).size()
	if n <= 0:
		if not u.get_modifier("axe_out").is_empty():
			u.remove_modifier("axe_out")
		return
	u.add_modifier({"id": "axe_out", "source": u.id, "expires": INF, "dispel": "", "charges": n,
		"stats": {"attack_out_pct": -ab.val(u, "axe_throw", "axe_out_cut") * n}, "fx": ""})

func _update_axes() -> void:
	for a in axes.duplicate():
		var u := w.get_unit(int(a.owner))
		if u == null:
			axes.erase(a)
			continue
		match String(a.state):
			"fly":
				_fly_axe(a, u)
			"stuck":
				var on := w.get_unit(int(a.on))
				if on == null or not on.alive or w.time >= float(a.recast_until):
					_drop_axe(a, on.pos if on != null else a.pos)
				else:
					a.pos = on.pos
			"tree":
				if w.time >= float(a.recast_until):
					_drop_axe(a, a.pos)
			"ground":
				if u.alive and u.pos.distance_to(a.pos) <= AXE_PICKUP and u.hop.is_empty():
					_take_axe(u, int(a.id), true)
					continue
		# once the cooldown is over a lost axe is back in his hand (not while he can still leap to it)
		if not a.has("gone") and String(a.state) != "fly" and w.time >= float(a.recast_until) \
				and w.abilities.cooldown_left(u, "axe_throw") <= 0.0 and _leaps.get(u.id) == null:
			_take_axe(u, int(a.id), false)

func _drop_axe(a: Dictionary, at: Vector2) -> void:
	a.state = "ground"
	a.on = -1
	a.pos = _land_spot(at)
	w.events.append({"t": "axe_drop", "u": int(a.owner), "axe": int(a.id), "pos": a.pos})

func _fly_axe(a: Dictionary, u: SimUnit) -> void:
	var step := minf(float(a.speed) * C.DT, float(a.left))
	var from: Vector2 = a.pos
	var to: Vector2 = from + (a.dir as Vector2) * step
	a.left = float(a.left) - step
	# the first enemy it meets
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(to, float(a.half) + 200.0, true):
		if not _enemy(int(a.team), o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > float(a.half) + o.hull:
			continue
		var d := from.distance_to(cp)
		if d < bd:
			bd = d
			best = o
	if best != null:
		w.combat.deal_damage(u.id, int(a.team), true, best, float(a.damage), C.DamageType.PHYSICAL, false, "axe_throw")
		if best.alive:
			w.status.apply(best, u.id, int(a.team), {"id": "axe_throw_slow", "dur": float(a.slow_t), "slow": float(a.slow),
				"fx": "slow"})
		if best.is_hero():
			add_rage(u, float(a.rage))
			rage_fight(u)
		if best.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(best, u)
		a.state = "stuck"
		a.on = best.id
		a.pos = best.pos
		w.events.append({"t": "axe_hit", "u": u.id, "axe": int(a.id), "target": best.id, "pos": best.pos})
		if not best.alive:
			_drop_axe(a, best.pos)
		return
	var ti := w.map.tree_at(to, 40.0)
	if ti >= 0:
		a.state = "tree"
		a.pos = to
		w.events.append({"t": "axe_stick", "u": u.id, "axe": int(a.id), "pos": to, "what": "tree"})
		return
	if not w.map.is_walkable(to) and w.map.rock_at(w.map.world_to_cell(to)) == 0:
		a.state = "tree"                                # a cliff holds it the same way
		a.pos = from
		w.events.append({"t": "axe_stick", "u": u.id, "axe": int(a.id), "pos": from, "what": "cliff"})
		return
	a.pos = to
	w.events.append({"t": "axe_move", "axe": int(a.id), "pos": to})
	if float(a.left) <= 0.0:
		_drop_axe(a, to)

# ---- Burak: Berserk ---------------------------------------------------------------------------------------------------------

## Berserk: 12 s of full Rage, bonus damage and speed, slows do nothing; half the damage he takes is held back (in his
## "berserk_held" counter) and returns as pure damage over 6 s when it ends, unless he kills or helps kill an enemy hero
## meanwhile (that clears it).
func _berserk(u: SimUnit, aid: String) -> void:
	var dur := ab.val(u, aid, "duration")
	u.add_modifier({"id": BERSERK, "source": u.id, "expires": w.time + dur, "hold": ab.val(u, aid, "held"), "dispel": "",
		"stats": {"damage": ab.val(u, aid, "damage"), "move_speed_pct": ab.val(u, aid, "move_pct"), "slow_resist": 1.0},
		"fx": "burak_berserk"})
	u.refresh_stats()
	_set_rage(u, ab.val(u, "rage", "max_rage") if u.ability_level.has("rage") else 0.0)
	u.stacks["berserk_until"] = w.time + dur
	w.events.append({"t": "burak_berserk", "u": u.id, "dur": dur})

## From SimCombat.deal_damage, the blow `amount` (after every reduction) about to land on `t`: the share Berserk holds
## back. Returns what still lands now.
func hold_damage(t: SimUnit, amount: float, key: String) -> float:
	if key == "berserk":
		return amount
	var m := t.get_modifier(BERSERK)
	if m.is_empty() or w.time >= float(m.expires):
		return amount
	var hold := amount * float(m.hold)
	t.stacks["berserk_held"] = float(t.stacks.get("berserk_held", 0.0)) + hold
	return amount - hold

## The damage Berserk holds back on `u` now (shown as a dark stretch on his health bar), and what is still coming back.
func held(u: SimUnit) -> float:
	var h := float(u.stacks.get("berserk_held", 0.0))
	for r in returns:
		if int(r.u) == u.id:
			h += float(r.left)
	return h

## Berserk's end is watched here (the modifier expires on its own): the held damage starts coming back. Dying clears it.
func _berserk_tick(h: SimUnit) -> void:
	if not h.alive:
		h.stacks.erase("berserk_until")
		h.stacks.erase("berserk_held")
		return
	if w.time < float(h.stacks.berserk_until) and not h.get_modifier(BERSERK).is_empty():
		return
	h.stacks.erase("berserk_until")
	var m := h.get_modifier(BERSERK)
	var amount := float(h.stacks.get("berserk_held", 0.0))
	h.stacks.erase("berserk_held")
	if not h.alive or amount <= 0.0:
		return
	var dur := ab.val(h, "berserk", "return_time")
	var by := -1
	var best := C.LONG_AGO
	for k in h.hero_damage_log:
		if float(h.hero_damage_log[k]) > best:
			best = float(h.hero_damage_log[k])
			by = int(k)
	returns.append({"u": h.id, "by": by, "left": amount, "per": amount / maxf(1.0, dur / 0.5), "next_at": w.time + 0.5,
		"until": w.time + dur + 0.01})
	w.events.append({"t": "berserk_return", "u": h.id, "amount": amount, "dur": dur})
	if not m.is_empty():
		h.remove_modifier(BERSERK)

func _update_returns() -> void:
	for i in range(returns.size() - 1, -1, -1):
		var r: Dictionary = returns[i]
		var u := w.get_unit(int(r.u))
		if u == null or not u.alive:
			returns.remove_at(i)
			continue
		if w.time < float(r.next_at):
			continue
		r.next_at = float(r.next_at) + 0.5
		var d := minf(float(r.per), float(r.left))
		r.left = float(r.left) - d
		var by := w.get_unit(int(r.by))
		var src_id := by.id if by != null else u.id
		var src_team := by.team if by != null else u.team
		w.combat.deal_damage(src_id, src_team, by != null, u, d, C.DamageType.PURE, false, "berserk", true,
			{"no_amp": true, "element": C.Element.NONE})
		if float(r.left) <= 0.01:
			returns.remove_at(i)

## An enemy hero died (SimAbilities.on_hero_death): every Burak in Berserk who killed it or helped (the assist rule:
## its killer, or near it, or hurt it in the last seconds) has his held damage cleared.
func on_hero_death(t: SimUnit, killer: SimUnit, credit: SimUnit) -> void:
	if killer == null or killer.team == t.team:
		return                                          # a deny is no kill
	for h in w.heroes:
		if h.team == t.team or not h.alive or h.get_modifier(BERSERK).is_empty():
			continue
		var recent: bool = t.hero_damage_log.has(h.id) and w.time - float(t.hero_damage_log[h.id]) <= C.KILL_TIME_WINDOW
		if h == killer or h == credit or recent or h.pos.distance_to(t.pos) <= C.ASSIST_RADIUS:
			var amt := float(h.stacks.get("berserk_held", 0.0))
			if amt > 0.0:
				w.events.append({"t": "berserk_cleared", "u": h.id, "amount": amt})
			h.stacks["berserk_held"] = 0.0

# ---- Ser Emelrich: wind-ups ---------------------------------------------------------------------------------------------

## Overhead Cut and Giant Swing: after the cast point (which the player can still call off) comes a wind-up everyone can
## see. It is a locked channel: orders wait until it is over (SimOrders.issue). A stun, hex or silence breaks Overhead
## Cut's; through Giant Swing's he is spell immune (the guard), so only a debuff on SWING_GUARD_PIERCE can. The blow
## lands when it ends (channel_done).
func _start_windup(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var dir := _aim(u, p)
	u.facing = dir.angle()
	var dur := maxf(0.05, ab.val(u, aid, "windup"))
	_seq += 1
	w.orders.cancel_channel(u)
	u.channel = {"ability": aid, "until": w.time + dur, "locked": true, "aim": dir, "lv": lv, "seq": _seq,
		"from": u.pos}
	if aid == "giant_swing":
		# spell immune through the wind-up: the debuffs on him go now (but the listed ones), new ones never land
		u.add_modifier({"id": SWING_GUARD, "source": u.id, "expires": w.time + dur + 0.1, SWING_GUARD: true,
			"debuff_immune": true, "fx": "spell_shield"})
		guard_sweep(u)
		u.refresh_stats()
		w.events.append({"t": "swing_guard", "u": u.id, "dur": dur})
	var ev := {"t": "windup", "u": u.id, "ability": aid, "dir": dir, "from": u.pos, "dur": dur, "seq": _seq,
		"distance": ab.val(u, aid, "distance")}
	if aid == "overhead_cut":
		ev["width"] = ab.val(u, aid, "width")
	else:
		ev["angle"] = ab.val(u, aid, "angle")
	w.events.append(ev)

## Whether a wind-up breaks now (SimOrders asks every tick).
func windup_breaks(u: SimUnit, ch: Dictionary) -> bool:
	if String(ch.ability) == "giant_swing" and u.has_flag(SWING_GUARD):
		# spell immune: only a stun, hex or silence from the owner's list gets through
		for m: Dictionary in u.modifiers:
			if (m.get("stun", false) or m.get("hex", false) or m.get("silence", false)) and pierces_guard(m):
				return true
		return false
	if u.has_flag("hex") or u.has_flag("silence"):
		return true
	if not u.is_stunned():
		return false
	return not (String(ch.ability) == "giant_swing" and bool(u.toggles.get("steel_stance", false)))

## The wind-up ended: the blow lands (cancelled: it is called off and the marks fade).
func windup_done(u: SimUnit, ch: Dictionary, cancelled: bool) -> void:
	var aid := String(ch.ability)
	if u.has_flag(SWING_GUARD):
		u.remove_modifier(SWING_GUARD)
		u.refresh_stats()
	if cancelled or not u.alive:
		w.events.append({"t": "windup_end", "u": u.id, "ability": aid, "seq": int(ch.seq), "cancelled": true})
		return
	var dir: Vector2 = ch.aim
	match aid:
		"overhead_cut":
			_overhead_cut(u, aid, dir, int(ch.seq))
		"giant_swing":
			var dmg := ab.val(u, aid, "damage")
			var stun := ab.val(u, aid, "stun")
			var ign := ab.val(u, aid, "armor_ignore")
			_cone_cut(u, aid, dir, ab.val(u, aid, "distance"), ab.val(u, aid, "angle"), dmg, stun, ign, int(ch.seq), false)
			if u.has_scepter():
				# the swing back the other way: a smaller cone, half the damage
				w.effects.append({"kind": "giant_swing_back", "src": u.id, "at": w.time + ab.val(u, aid, "back_delay"),
					"dir": dir, "distance": ab.val(u, aid, "back_distance"), "angle": ab.val(u, aid, "back_angle"),
					"damage": dmg * 0.5, "stun": stun, "armor_ignore": ign, "seq": int(ch.seq)})
	w.events.append({"t": "windup_end", "u": u.id, "ability": aid, "seq": int(ch.seq), "cancelled": false})

## Whether a debuff (a modifier, or a forced move's dictionary) gets through Giant Swing's guard: its id, or the
## ability or item that made it, is on SWING_GUARD_PIERCE.
static func pierces_guard(m: Dictionary) -> bool:
	if SWING_GUARD_PIERCE.is_empty():
		return false
	for k in ["id", "ability", "key", "item"]:
		if m.has(k) and String(m[k]) in SWING_GUARD_PIERCE:
			return true
	return false

## Giant Swing's guard: every debuff an enemy (or a neutral) put on him goes, but the listed ones, and so does an
## enemy's push, pull or throw. Runs when the wind-up starts and every tick of it (some effects add modifiers without
## asking SimStatus).
func guard_sweep(u: SimUnit) -> void:
	for i in range(u.modifiers.size() - 1, -1, -1):
		var m: Dictionary = u.modifiers[i]
		var hostile := bool(m.get("debuff", false)) or int(m.get("from_team", u.team)) != u.team
		if not hostile:
			var src := w.get_unit(int(m.get("by", m.get("source", -1))))
			hostile = src != null and src.team != u.team
		if hostile and not pierces_guard(m):
			u.modifiers.remove_at(i)
			u.stats_dirty = true
	if not u.knock.is_empty():
		var by := w.get_unit(int(u.knock.get("src", -1)))
		if by != null and by.team != u.team and not pierces_guard(u.knock):
			u.knock = {}

## His attack damage for spells that add it (the middle of his damage range plus bonus damage).
static func attack_damage(u: SimUnit) -> float:
	return (u.dmg_min + u.dmg_max) * 0.5 + u.bonus_damage

## Overhead Cut: a line 450 long and 160 wide in front of him. Physical damage plus 60% of his attack damage, a stun;
## trees on the line fall.
func _overhead_cut(u: SimUnit, aid: String, dir: Vector2, seq: int) -> void:
	var dist := ab.val(u, aid, "distance")
	var half := ab.val(u, aid, "width") * 0.5
	var from := u.pos
	var to := u.pos + dir * (dist + u.hull)
	ab.fell_trees_on(from, to, half)
	var dmg := ab.val(u, aid, "damage") + ab.val(u, aid, "attack_pct") * attack_damage(u)
	var stun := ab.val(u, aid, "stun")
	var hits: Array = []
	for o: SimUnit in w.query((from + to) * 0.5, dist * 0.5 + half + 120.0, true):
		if not _enemy(u.team, o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > half + o.hull:
			continue
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.PHYSICAL, false, aid)
		if o.alive:
			w.status.apply(o, u.id, u.team, {"id": "stunned", "stun": true, "dur": stun, "fx": "stun"})
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "overhead_cut", "u": u.id, "from": from, "to": to, "width": half * 2.0, "hits": hits, "seq": seq})

## A cone cut from Ser Emelrich (Giant Swing, and its swing back): every enemy inside takes physical damage that ignores
## a share of its armor and is knocked down; every tree inside falls.
func _cone_cut(u: SimUnit, aid: String, dir: Vector2, dist: float, angle: float, dmg: float, stun: float, ign: float,
		seq: int, back: bool) -> void:
	var half := deg_to_rad(angle) * 0.5
	var hits: Array = []
	for o: SimUnit in w.query(u.pos, dist + 120.0, true):
		if not _enemy(u.team, o) or not in_cone(u.pos, dir, dist, half, o.pos, o.hull):
			continue
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.PHYSICAL, false, aid, false, {"armor_ignore": ign})
		if o.alive:
			w.status.apply(o, u.id, u.team, {"id": "stunned", "stun": true, "dur": stun, "fx": "stun"})
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	# the trees in the cone
	var c0 := w.map.world_to_cell(u.pos - Vector2(dist, dist))
	var c1 := w.map.world_to_cell(u.pos + Vector2(dist, dist))
	for cy in range(maxi(c0.y, 0), mini(c1.y, SimMap.N - 1) + 1):
		for cx in range(maxi(c0.x, 0), mini(c1.x, SimMap.N - 1) + 1):
			var ti := w.map.tree_cell[cy * SimMap.N + cx]
			if ti >= 0 and w.map.trees[ti].alive and in_cone(u.pos, dir, dist, half, w.map.trees[ti].pos, 40.0):
				w.cut_tree(ti, u.pos, true)
	w.events.append({"t": "giant_swing", "u": u.id, "pos": u.pos, "dir": dir, "distance": dist, "angle": angle,
		"hits": hits, "back": back, "seq": seq})

## Whether a circle at `p` of radius `r` touches the cone from `o` along `dir`, `dist` long and `half` (radians) each way.
static func in_cone(o: Vector2, dir: Vector2, dist: float, half: float, p: Vector2, r: float) -> bool:
	var rel := p - o
	var d := rel.length()
	if d > dist + r:
		return false
	if d <= r + 1.0:
		return true
	var a := absf(angle_difference(dir.angle(), rel.angle()))
	if a <= half:
		return true
	# the edge of the cone may still graze the circle
	return d * sin(minf(PI * 0.5, a - half)) <= r

# ---- Ser Emelrich: Sweep, Steel Stance -----------------------------------------------------------------------------------

## Sweep: the half circle in front of him (300): his attack damage plus the bonus as physical damage, and every enemy hit
## is shoved 200 to his left (a physics push), so they pile up; a crash adds damage and a short stun.
func _sweep(u: SimUnit, aid: String, lv: int) -> void:
	var r := ab.val(u, aid, "radius")
	var fwd := Vector2.from_angle(u.facing)
	var left := Vector2.from_angle(u.facing + PI * 0.5)      # the sim's y runs north: +90 degrees is his left
	_seq += 1
	var seq := 8500000 + _seq
	var v0 := push_speed_for(ab.val(u, aid, "shove"))
	var hits: Array = []
	for o: SimUnit in w.query(u.pos, r + 120.0, true):
		if not _enemy(u.team, o) or u.edge_distance(o) > r:
			continue
		if (o.pos - u.pos).dot(fwd) < -o.hull:
			continue                                    # behind him
		var dmg := w.rng.randf_range(u.dmg_min, u.dmg_max) + u.bonus_damage + ab.val(u, aid, "damage")
		w.combat.deal_damage(u.id, u.team, true, o, dmg, C.DamageType.PHYSICAL, false, aid)
		hits.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
		if o.alive and ab.can_debuff(o, u.team) and _movable(o) and o.kind != K.TOWER:
			ab.start_push(o, left * v0, u.id, u.team, aid, lv, seq)
	w.events.append({"t": "sweep", "u": u.id, "pos": u.pos, "dir": fwd, "radius": r, "hits": hits})

## Steel Stance on or off (SimAbilities.set_toggle): armor, the front block, no slows but his own; 1 s between toggles.
func on_stance(u: SimUnit, on: bool) -> void:
	var aid := "steel_stance"
	u.ability_ready[aid] = w.time + ab.ability_cooldown(u, aid)
	if on:
		u.add_modifier({"id": aid, "source": u.id, "expires": INF, "dispel": "", "front_block": ab.val(u, aid, "block"),
			"front_angle": ab.val(u, aid, "front"),
			"stats": {"armor": ab.val(u, aid, "armor"), "move_speed_pct": -ab.val(u, aid, "move_cut"),
				"turn_rate_pct": -ab.val(u, aid, "turn_cut"), "slow_resist": 1.0}, "fx": "steel_stance"})
	else:
		u.remove_modifier(aid)
	u.refresh_stats()

## Steel Stance's block on a blow (SimCombat.deal_damage): attacks and line shots whose source stands in front of him.
## Returns the share of the damage that is kept (1 = no block).
func front_block(t: SimUnit, src: SimUnit, key: String, is_attack: bool) -> float:
	var m := t.get_modifier("steel_stance")
	if m.is_empty() or src == null or src == t:
		return 1.0
	if not is_attack:
		var a := SimData.ability(key)
		if a.is_empty() or not (bool(a.get("line", false)) or bool(a.get("bounce_path", false))):
			return 1.0
	var rel := src.pos - t.pos
	if rel.length() < 1.0:
		return 1.0
	if absf(angle_difference(t.facing, rel.angle())) > deg_to_rad(float(m.front_angle)) * 0.5:
		return 1.0
	return 1.0 - float(m.front_block)
