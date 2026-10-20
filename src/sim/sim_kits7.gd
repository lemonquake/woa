class_name SimKits7
extends RefCounted
## Araki's kit (the owner's hero, run 2026-10-19 c; see docs/HANDOFF.md). Called by SimAbilities: cast(),
## cast_error(), update_effect(), tick(), cooldown_mult(); by SimCombat for Senryukai's damage and The Blur's attack
## count.
##
## Senryukai (innate): Dota's Fury Swipes. Each attack of his (and his ghosts') on an enemy adds a stack; every stack
## adds 4 physical damage to his hits on that enemy; 15 s, renewed by every hit, no limit. Break turns it off.
## Blur Strike: an instant dash (up to 600) that gives every enemy within 250 of the path an attack with all its
## effects, magic damage and a 60% slow for 1 s. A cast that hits any enemy refreshes the cooldown once (6 s to use it).
## Djin Bomb: a cloud (450) for 5 s: enemies inside lose magic and status resistance and are slowed more every second.
## Ghosts of the Will: ghosts (summons with 1 health) fly out one by one at 800, phased and over terrain, strike the
## target the moment they reach it (no wind-up: a running target cannot step out of the blow) with a share of his attack
## (Senryukai included) and vanish in a puff (no death).
## The Blur: half cooldowns for Blur Strike and Djin Bomb for 19 s (running ones halved), and attack speed for a number
## of attacks.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const CASTS := ["blur_strike", "djin_bomb", "ghosts_of_the_will", "the_blur"]
const EFFECTS := ["djin_smoke", "ghost_call"]
const GHOST := "araki_ghost"
const STACKS := "senryukai"                 # the debuff on an enemy (one per Araki: its source is his id)
const AGAIN := "blur_strike_again"          # on Araki: Blur Strike was refreshed and may be cast again
const BLUR := "the_blur"                    # on Araki: halved cooldowns
const BLUR_SPEED := "the_blur_speed"        # on Araki: the attack speed, with the attacks left as charges
const HALVED := ["blur_strike", "djin_bomb"]
const GHOST_FADE := 0.2                     # after its blow a ghost follows the target this long (its swing), then is gone
const GHOST_REACH := 60.0                   # a ghost strikes from this far beyond the two hulls

var w: SimWorld
var ab: SimAbilities
var ghosts := {}                            # ghost unit id -> {owner, target, pct, speed, until, strike_at, retarget}
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

## The modifier `mid` that `src_id` put on `u` ({} when none).
static func _mod(u: SimUnit, mid: String, src_id: int) -> Dictionary:
	for m in u.modifiers:
		if m.id == mid and int(m.get("source", -1)) == src_id:
			return m
	return {}

func _land_spot(p: Vector2) -> Vector2:
	p = Vector2(clampf(p.x, -SimMap.EDGE, SimMap.EDGE), clampf(p.y, -SimMap.EDGE, SimMap.EDGE))
	if w.map.is_walkable(p):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"blur_strike":
			_blur_strike(u, aid, p)
		"djin_bomb":
			_djin_bomb(u, aid, lv, p)
		"ghosts_of_the_will":
			_call_ghosts(u, aid, t)
		"the_blur":
			_the_blur(u, aid)

func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"djin_smoke":
			return _update_smoke(e)
		"ghost_call":
			return _update_call(e)
	return true

## Cast rules beyond SimAbilities' own. "" = fine.
func cast_error(u: SimUnit, aid: String, _t: SimUnit, _p: Vector2, _check_target: bool) -> String:
	if aid == "blur_strike" and u.is_rooted():
		return "Rooted"
	return ""

## The Blur halves Blur Strike's and Djin Bomb's cooldowns (SimAbilities.ability_cooldown).
func cooldown_mult(u: SimUnit, aid: String) -> float:
	if not aid in HALVED or u.modifiers.is_empty():
		return 1.0
	var m := u.get_modifier(BLUR)
	return float(m.get("cd_pct", 1.0)) if not m.is_empty() else 1.0

# ---- Senryukai ----------------------------------------------------------------------------------------------------------

## A landed attack (SimCombat.land_attack): adds a stack to the target and returns the hit's bonus damage (the stack it
## adds counts, as with Fury Swipes). A ghost's hit (s.ghost = its share) adds a stack and deals its share of the bonus.
func senryukai_bonus(s: Dictionary, t: SimUnit) -> float:
	if not bool(s.get("hero", false)) or t.is_building() or t.is_ward() or t.team == int(s.team):
		return 0.0
	var src := w.get_unit(int(s.src))
	if src == null or src.ability_level_of("senryukai") <= 0 or src.is_broken():
		return 0.0
	var m := _mod(t, STACKS, src.id)
	var n := int(m.get("charges", 0)) + 1 if not m.is_empty() else 1
	t.add_modifier({"id": STACKS, "source": src.id, "by": src.id, "expires": w.time + ab.val(src, "senryukai", "duration"),
		"charges": n, "debuff": true, "from_team": src.team, "fx": "senryukai"})
	return float(n) * ab.val(src, "senryukai", "damage_per_stack") * float(s.get("ghost", 1.0))

## Senryukai stacks `src` has on `t` (bots read them).
func stacks_on(src: SimUnit, t: SimUnit) -> int:
	if t == null or t.modifiers.is_empty():
		return 0
	var m := _mod(t, STACKS, src.id)
	return int(m.get("charges", 0)) if not m.is_empty() and w.time < float(m.expires) else 0

# ---- Blur Strike --------------------------------------------------------------------------------------------------------

## Where a dash from `from` along `dir` for `dist` ends: the farthest walkable spot on the line (he flashes over trees
## and cliffs), else the nearest walkable cell.
func dash_end(from: Vector2, dir: Vector2, dist: float) -> Vector2:
	var d := dist
	while d > 0.0:
		var q := from + dir * d
		if absf(q.x) < SimMap.EDGE and absf(q.y) < SimMap.EDGE and w.map.is_walkable(q):
			return q
		d -= 25.0
	return _land_spot(from)

## The enemies a dash from `a` to `b` slashes: within `r` of the path (to their edge), nearest along it first.
func strike_targets(team: int, a: Vector2, b: Vector2, r: float) -> Array:
	var out: Array = []
	var mid := (a + b) * 0.5
	for o: SimUnit in w.query(mid, a.distance_to(b) * 0.5 + r + 40.0, true):
		if not _enemy(team, o):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, a, b)
		if cp.distance_to(o.pos) <= r + o.hull:
			out.append(o)
	out.sort_custom(func(x, y): return a.distance_squared_to(x.pos) < a.distance_squared_to(y.pos))
	return out

func _blur_strike(u: SimUnit, aid: String, p: Vector2) -> void:
	var from := u.pos
	var dir := p - from
	var dist := clampf(dir.length(), ab.val(u, aid, "min_distance"), ab.val(u, aid, "distance"))
	dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
	var to := dash_end(from, dir, dist)
	u.pos = to
	u.facing = dir.angle()
	u.path = PackedVector2Array()
	u.moving = false
	var hits := strike_targets(u.team, from, to, ab.val(u, aid, "radius"))
	var ids: Array = []
	for o: SimUnit in hits:
		if not o.alive:
			continue
		ids.append(o.id)
		var snap := w.combat.attack_snapshot(u, "")
		snap.crit = w.combat.roll_crit(u, o)
		snap["instant"] = true
		w.combat.land_attack(snap, o)
		if o.alive:
			w.combat.deal_damage(u.id, u.team, true, o, ab.val(u, aid, "damage"), C.DamageType.MAGICAL, false, aid)
		if o.alive and ab.can_debuff(o, u.team):
			w.status.apply(o, u.id, u.team, {"id": "blur_strike_slow", "dur": ab.val(u, aid, "slow_duration"),
				"slow": ab.val(u, aid, "slow"), "fx": "slowed"})
		if o.kind == K.NEUTRAL_CREEP and o.alive:
			w.ai.neutral_provoked(o, u)
	# the refresh: a cast that hits refreshes the cooldown (once a chain; twice with the talent)
	var again := u.get_modifier(AGAIN)
	var used := 0
	var resume := float(u.ability_ready.get(aid, w.time))
	if not again.is_empty():
		used = int(again.get("used", 1))
		u.remove_modifier(AGAIN)
	var refreshed := false
	if not ids.is_empty() and used < int(ab.val(u, aid, "refreshes")):
		var win := ab.val(u, aid, "refresh_window")
		u.ability_ready[aid] = w.time
		u.add_modifier({"id": AGAIN, "source": u.id, "until": w.time + win, "expires": w.time + win + 0.2,
			"used": used + 1, "resume": resume, "fx": "blur_again"})
		refreshed = true
	w.events.append({"t": "blur_strike", "u": u.id, "from": from, "to": to, "hits": ids, "again": refreshed})

## Blur Strike's refresh left unused: the skill goes back on the cooldown its first cast started.
func _lapse(u: SimUnit) -> void:
	var m := u.get_modifier(AGAIN)
	if m.is_empty() or w.time < float(m.get("until", 0.0)):
		return
	u.remove_modifier(AGAIN)
	u.ability_ready["blur_strike"] = maxf(float(u.ability_ready.get("blur_strike", w.time)), float(m.resume))

## Blur Strike may be cast again (refreshed and not yet used).
func strike_again(u: SimUnit) -> bool:
	return not u.get_modifier(AGAIN).is_empty()

# ---- Djin Bomb ----------------------------------------------------------------------------------------------------------

func _djin_bomb(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var at := _land_spot(p)
	_seq += 1
	var land := w.time + ab.val(u, aid, "throw_time")
	var dur := ab.val(u, aid, "duration")
	w.effects.append({"kind": "djin_smoke", "ability": aid, "src": u.id, "team": u.team, "pos": at, "lv": lv,
		"start": land, "end": land + dur, "radius": ab.val(u, aid, "radius"), "mr": ab.val(u, aid, "magic_resist_cut"),
		"sr": ab.val(u, aid, "status_resist_cut"), "slow": ab.val(u, aid, "slow_per_second"), "max": ceili(dur),
		"linger": ab.val(u, aid, "linger"), "inside": {}, "seq": _seq})
	w.events.append({"t": "djin_bomb", "u": u.id, "from": u.pos, "pos": at, "land": land - w.time, "dur": dur,
		"radius": ab.val(u, aid, "radius"), "seq": _seq})

func _update_smoke(e: Dictionary) -> bool:
	if w.time < float(e.start):
		return false
	if not e.has("popped"):
		e["popped"] = true
		w.events.append({"t": "djin_smoke", "u": int(e.src), "pos": e.pos, "radius": float(e.radius),
			"dur": float(e.end) - float(e.start), "seq": int(e.seq)})
	if w.time >= float(e.end):
		w.events.append({"t": "djin_smoke_end", "seq": int(e.seq), "pos": e.pos})
		return true
	if w.tick % 3 != 0:
		return false
	var inside: Dictionary = e.inside
	var team := int(e.team)
	for o: SimUnit in w.query(e.pos, float(e.radius) + 40.0, true):
		if not _enemy(team, o) or o.pos.distance_to(e.pos) > float(e.radius) + o.hull * 0.5:
			continue
		var secs := float(inside.get(o.id, 0.0)) + 0.1
		inside[o.id] = secs
		if not ab.can_debuff(o, team):
			continue
		var n := mini(int(secs + 0.001) + 1, int(e.max))
		w.status.apply(o, int(e.src), team, {"id": "djin_bomb", "dur": float(e.linger), "no_resist": true,
			"slow": float(e.slow) * n, "charges": n, "fx": "djin_smoke",
			"stats": {"magic_resist": -float(e.mr), "status_resist": -float(e.sr)}})
	return false

## Where Djin Bomb's clouds are now (bots: do not throw a second one on the first): [[pos, radius, team], ...].
func clouds() -> Array:
	var out: Array = []
	for e in w.effects:
		if String(e.kind) == "djin_smoke":
			out.append([e.pos, float(e.radius), int(e.team)])
	return out

# ---- Ghosts of the Will -------------------------------------------------------------------------------------------------

func _call_ghosts(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null:
		return
	_seq += 1
	w.effects.append({"kind": "ghost_call", "src": u.id, "team": u.team, "target": t.id,
		"left": int(ab.val(u, aid, "ghosts")), "next_at": w.time, "interval": ab.val(u, aid, "interval"),
		"pct": ab.val(u, aid, "damage_pct"), "speed": ab.val(u, aid, "speed"), "lifetime": ab.val(u, aid, "lifetime"),
		"retarget": ab.val(u, aid, "retarget"), "n": 0, "seq": _seq})
	w.events.append({"t": "ghosts_call", "u": u.id, "target": t.id, "count": int(ab.val(u, aid, "ghosts"))})

func _update_call(e: Dictionary) -> bool:
	var u := w.get_unit(int(e.src))
	if u == null or not u.alive:
		return true
	while int(e.left) > 0 and w.time + 1e-6 >= float(e.next_at):
		e.left = int(e.left) - 1
		e.next_at = float(e.next_at) + float(e.interval)
		e.n = int(e.n) + 1
		var fwd := Vector2.from_angle(u.facing)
		var side := 1.0 if int(e.n) % 2 == 0 else -1.0
		var at := u.pos + fwd * 30.0 + fwd.orthogonal() * side * (26.0 + 10.0 * float(int(e.n) % 3))
		var g := w.spawn(GHOST, u.team, at)
		g.owner_id = u.id
		g.facing = u.facing
		g.ward_expires = w.time + float(e.lifetime) + 1.0     # summons die at this time (SimKits3.tick); ours is sooner
		g.add_modifier({"id": "ghost_form", "source": u.id, "phased": true})
		g.refresh_stats()
		ghosts[g.id] = {"owner": u.id, "target": int(e.target), "pct": float(e.pct), "speed": float(e.speed),
			"until": w.time + float(e.lifetime), "strike_at": -1.0, "retarget": float(e.retarget)}
		w.events.append({"t": "ghost_spawn", "u": u.id, "ghost": g.id, "target": int(e.target), "n": int(e.n)})
	return int(e.left) <= 0

func is_ghost(o: SimUnit) -> bool:
	return o != null and ghosts.has(o.id)

func _valid_target(t: SimUnit, team: int) -> bool:
	return _enemy(team, t) and w.vision.sees(team, t)

## The nearest enemy a ghost can go for once its target is gone: a hero first, else any unit.
func _retarget(g: SimUnit, r: float) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(g.pos, r, true):
		if not _valid_target(o, g.team) or is_ghost(o):
			continue
		var d := g.pos.distance_to(o.pos) - (2000.0 if o.is_hero() else 0.0)
		if d < bd:
			bd = d
			best = o
	return best

func _poof(g: SimUnit) -> void:
	ghosts.erase(g.id)
	if g.alive:
		w.events.append({"t": "ghost_poof", "ghost": g.id, "pos": g.pos})
		w.combat.kill(g, null)

func _ghost_hit(g: SimUnit, owner: SimUnit, t: SimUnit, pct: float) -> void:
	var s := w.combat.attack_snapshot(owner, "")
	s.dmg_min = owner.dmg_min * pct
	s.dmg_max = owner.dmg_max * pct
	s.bonus = owner.bonus_damage * pct
	s.crit = 1.0
	s.lifesteal = 0.0
	s.lifesteal_ab = 0.0
	s.quell = 0.0
	s.taint = 0
	s.level_h = w.map.level_at(g.pos)
	s["ghost"] = pct
	w.events.append({"t": "ghost_hit", "ghost": g.id, "u": owner.id, "target": t.id})
	w.combat.land_attack(s, t)

func _update_ghost(gid: int) -> void:
	var g := w.get_unit(gid)
	var d: Dictionary = ghosts[gid]
	if g == null or not g.alive:
		# destroyed by a hit: it goes up in a puff like the rest, never a body on the ground
		if g != null:
			w.events.append({"t": "ghost_poof", "ghost": g.id, "pos": g.pos})
		ghosts.erase(gid)
		return
	var owner := w.get_unit(int(d.owner))
	if owner == null or w.time >= float(d.until):
		_poof(g)
		return
	var t := w.get_unit(int(d.target))
	# its own target it hunts like a homing blow: out of sight too, but not invisible (unless seen through it)
	var locked := t != null and _enemy(g.team, t) and (not t.has_flag("invisible") or w.vision.sees(g.team, t))
	if not locked:
		t = _retarget(g, float(d.retarget))
		if t == null:
			_poof(g)
			return
		d.target = t.id
		d.strike_at = -1.0
	var reach := g.hull + t.hull + GHOST_REACH
	var to := t.pos - g.pos
	if float(d.strike_at) >= 0.0:
		# the blow has landed: it clings to the target through its swing, then puffs away
		if to.length() > reach:
			g.pos += to.normalized() * minf(float(d.speed) * C.DT, to.length() - reach + 1.0)
		g.facing = to.angle() if to.length() > 1.0 else g.facing
		if w.time + 1e-6 >= float(d.strike_at):
			_poof(g)
		return
	# fly, then strike in the same tick it gets close, moving target or not (stopping at the edge of reach and checking
	# next tick let a runner step out of it every time: the ghosts trailed behind and never struck)
	if to.length() > reach:
		g.pos += to.normalized() * minf(float(d.speed) * C.DT, to.length() - reach + 1.0)
		g.moving = true
	g.facing = to.angle() if to.length() > 1.0 else g.facing
	if g.pos.distance_to(t.pos) <= reach + 1e-3:
		d.strike_at = w.time + GHOST_FADE
		g.moving = false
		w.events.append({"t": "ghost_strike", "ghost": g.id, "target": t.id})
		_ghost_hit(g, owner, t, float(d.pct))

# ---- The Blur -----------------------------------------------------------------------------------------------------------

func _the_blur(u: SimUnit, aid: String) -> void:
	var dur := ab.val(u, aid, "duration")
	var pct := ab.val(u, aid, "cooldown_pct")
	u.add_modifier({"id": BLUR, "source": u.id, "expires": w.time + dur, "cd_pct": pct, "fx": "the_blur"})
	u.add_modifier({"id": BLUR_SPEED, "source": u.id, "expires": w.time + dur, "charges": int(ab.val(u, aid, "attacks")),
		"stats": {"attack_speed": ab.val(u, aid, "attack_speed")}})
	u.refresh_stats()
	for a in HALVED:
		var left := ab.cooldown_left(u, a)
		if left > 0.0:
			u.ability_ready[a] = w.time + left * pct
	var again := u.get_modifier(AGAIN)
	if not again.is_empty() and float(again.resume) > w.time:
		again.resume = w.time + (float(again.resume) - w.time) * pct
	w.events.append({"t": "the_blur", "u": u.id, "dur": dur})

## Every attack Araki releases spends one of The Blur's fast attacks (SimCombat.release_attack); Blur Strike's slashes
## and the ghosts' blows do not.
func on_attack_released(u: SimUnit) -> void:
	if u.modifiers.is_empty():
		return
	var m := u.get_modifier(BLUR_SPEED)
	if m.is_empty():
		return
	m.charges = int(m.charges) - 1
	if int(m.charges) <= 0:
		u.remove_modifier(BLUR_SPEED)
		u.refresh_stats()

## The Blur's fast attacks left (0 when none).
func blur_attacks(u: SimUnit) -> int:
	var m := u.get_modifier(BLUR_SPEED)
	return int(m.get("charges", 0)) if not m.is_empty() else 0

func tick() -> void:
	if not ghosts.is_empty():
		for gid in ghosts.keys():
			_update_ghost(int(gid))
	if w.tick % 3 == 0:
		for h in w.heroes:
			if h.alive and not h.modifiers.is_empty() and h.ability_level.has("blur_strike"):
				_lapse(h)
