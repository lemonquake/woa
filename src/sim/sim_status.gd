class_name SimStatus
extends RefCounted
## Status effects the Dota way (Dota 2 wiki: Pseudo-random distribution, Stun, Status Resistance, Dispel, Hex, Root,
## Silence, Break; see docs/MECHANICS.md "Status effects"):
##   * Pseudo-random procs: a chance effect (critical strike, bash, evasion, pierce, chain lightning, damage block)
##     starts at a lower chance C and gains C after every roll that fails, so streaks are rare; the average stays the
##     listed chance. Each unit keeps its own counter per effect.
##   * Debuffs from enemies: refused by debuff immunity unless they pierce it, shortened by status resistance, and
##     stuns of one group refresh each other to the longer time instead of stacking.
##   * Dispels: basic removes slows, silences, roots, disarms and the like; strong also removes stuns and hexes.
##   * The timed disable a unit is under, for the bar the HUD draws over its health.
## Kinds of debuff (flags on the modifier): stun, hex (silence + mute + disarm, speed 140), silence, root, disarm,
## mute, break (hero passives off), slow.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

## Dota's modifier groups: every regular stun shares one modifier, every bash another (they refresh, not stack).
const STUN_GROUPS := ["stunned", "bashed"]

var w: SimWorld
var burns: Array = []                      # Silence Staff: [{t, src, team, until, pct, taken}]
var dusts: Array = []                      # Reveal Dust: [{team, src, pos, until, radius, linger, slow}]

func _init(world: SimWorld) -> void:
	w = world

# ---- Pseudo-random distribution ---------------------------------------------------------------------------------------

static var _c_cache := {}

## The PRD constant C for a nominal chance p: the chance on the N-th roll since the last proc is C * N. Found by
## bisection on the average proc rate 1 / E[rolls], which matches Valve's table (25% -> 0.0847, 30% -> 0.1189).
static func prd_c(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	var key := snappedf(p, 0.0001)
	if _c_cache.has(key):
		return _c_cache[key]
	var lo := 0.0
	var hi := p
	for i in 60:
		var mid := (lo + hi) * 0.5
		if _rate(mid) > p:
			hi = mid
		else:
			lo = mid
	var c := (lo + hi) * 0.5
	_c_cache[key] = c
	return c

static func _rate(c: float) -> float:
	if c <= 0.0:
		return 0.0
	var expect := 0.0
	var none := 1.0                           # chance that no proc happened before roll n
	var n := 1
	while none > 1e-12:
		var pn := minf(1.0, c * n)
		expect += n * none * pn
		none *= 1.0 - pn
		n += 1
	return 1.0 / expect

## Roll a pseudo-random effect for `u` (its own counter under `key`). True on a proc.
func roll(u: SimUnit, key: String, chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	var n := int(u.prd.get(key, 0)) + 1
	if w.rng.randf() < prd_c(chance) * n:
		u.prd[key] = 0
		return true
	u.prd[key] = n
	return false

# ---- Debuffs ----------------------------------------------------------------------------------------------------------

## Put a debuff from (src_id, src_team) on `t`. m: {id, dur, and flags: stun, hex, silence, root, disarm, mute,
## break, slow, stats, fx, dispel ("basic" or "strong")}. Enemy debuffs are refused by debuff immunity unless `pierce`
## and by invulnerability, and last (1 - status resistance) as long. A stun joins its group (Dota's "stunned" or
## "bashed" modifier) and keeps the longer of the old and new times. Returns false when refused.
func apply(t: SimUnit, src_id: int, src_team: int, m: Dictionary, pierce := false) -> bool:
	if t == null or not t.alive:
		return false
	var enemy := src_team != t.team
	if enemy and (t.is_invulnerable() or (t.debuff_immune and not pierce)):
		return false
	var dur := float(m.get("dur", 0.0))
	if enemy and not m.get("no_resist", false):
		dur *= 1.0 - t.status_resist
	if dur <= 0.0:
		return false
	m["source"] = int(m.get("source", src_id))
	m["dur"] = dur
	m["expires"] = w.time + dur
	m["debuff"] = enemy
	m["from_team"] = src_team
	if not m.has("dispel"):
		m["dispel"] = "strong" if (m.get("stun", false) or m.get("hex", false)) else "basic"
	if m.get("stun", false):
		var gid := String(m.get("id", "stunned"))
		if gid in STUN_GROUPS:
			# one modifier per group whoever applied it; a shorter stun never cuts a longer one
			for o in t.modifiers:
				if String(o.id) == gid and float(o.get("expires", 0.0)) > float(m.expires):
					m["expires"] = o.expires
					m["dur"] = o.dur
			t.remove_modifier(gid)
			m["source"] = -20 - STUN_GROUPS.find(gid)
	t.add_modifier(m)
	t.stats_dirty = true
	if not t.channel.is_empty():
		# stuns and hexes end every channel at once; a silence ends spell channels (Burst Shot, Chomp) but not the
		# Teleport Scroll, which is an item (mutes and roots end that one)
		var tp := String(t.channel.get("ability", "")) == "tp"
		if m.get("stun", false) or m.get("hex", false) or (m.get("silence", false) and not tp) \
				or (tp and (m.get("mute", false) or m.get("root", false))):
			w.orders.cancel_channel(t)
	var kind := disable_kind(m)
	w.events.append({"t": "debuff", "u": t.id, "src": src_id, "id": String(m.id), "kind": kind, "dur": dur,
		"bash": String(m.id) == "bashed"})
	return true

## Remove debuffs (applied by enemies) from `t`: a basic dispel takes everything marked "basic", a strong one also
## stuns and hexes. Auras and channels are never dispelled. by_team: the team of whoever dispels; an enemy dispel
## takes the unit's buffs instead (only those marked dispellable).
func dispel(t: SimUnit, strong: bool, by_team: int) -> int:
	var n := 0
	for i in range(t.modifiers.size() - 1, -1, -1):
		var m: Dictionary = t.modifiers[i]
		var d := String(m.get("dispel", ""))
		if d == "" or (d == "strong" and not strong):
			continue
		var is_debuff := bool(m.get("debuff", false))
		if (by_team == t.team) != is_debuff:
			continue
		t.modifiers.remove_at(i)
		t.stats_dirty = true
		n += 1
	return n

# ---- Queries ------------------------------------------------------------------------------------------------------------

## The disable a modifier puts on its unit, for labels and the timer bar ("" = none).
static func disable_kind(m: Dictionary) -> String:
	if m.get("stun", false):
		return "Stunned"
	if m.get("hex", false):
		return "Hexed"
	if m.get("silence", false):
		return "Silenced"
	if m.get("root", false):
		return "Rooted"
	if m.get("disarm", false):
		return "Disarmed"
	if m.get("break", false):
		return "Broken"
	if m.get("mute", false):
		return "Muted"
	return ""

const _ORDER := ["Stunned", "Hexed", "Silenced", "Rooted", "Disarmed", "Muted", "Broken"]

## The strongest timed disable on `u` for the bar over its health: {kind, left, total} or {} when none. Stuns beat
## hexes beat silences and so on; among equals the one that lasts longest is shown.
func disable_info(u: SimUnit) -> Dictionary:
	var best := {}
	var best_rank := 99
	for m in u.modifiers:
		var kind := disable_kind(m)
		if kind == "":
			continue
		var e := float(m.get("expires", INF))
		if not is_finite(e) or not m.has("dur"):
			continue
		var rank := _ORDER.find(kind)
		var left := e - w.time
		if left <= 0.0:
			continue
		if rank < best_rank or (rank == best_rank and left > float(best.left)):
			best_rank = rank
			best = {"kind": kind, "left": left, "total": maxf(float(m.dur), left), "bash": String(m.id) == "bashed"}
	# a push or drag that disables counts as a stun with no set time
	return best

# ---- Per tick -------------------------------------------------------------------------------------------------------------

## Damage dealt to a unit under a Silence Staff burn is counted (after reductions) for the burst when it ends.
func on_damage(t: SimUnit, amount: float) -> void:
	if burns.is_empty() or amount <= 0.0:
		return
	for b in burns:
		if b.t == t.id:
			b.taken = float(b.taken) + amount

func add_burn(t: SimUnit, src: SimUnit, until: float, pct: float) -> void:
	for b in burns:
		if b.t == t.id and b.src == src.id:
			b.until = until
			return
	burns.append({"t": t.id, "src": src.id, "team": src.team, "until": until, "pct": pct, "taken": 0.0})

## Reveal Dust (Dota's Dust of Appearance): for 12 s, enemies within 1050 of where it was thrown are seen through
## invisibility by the thrower's team (where it has vision) and, while invisible, slowed 20%; the debuff lingers 8 s
## after leaving the area. Units invisible when it is thrown take 25 magic damage.
func dust(u: SimUnit, v: Dictionary) -> void:
	var r := float(v.radius)
	for o: SimUnit in w.query(u.pos, r + 40.0, true):
		if not o.alive or o.team == u.team or o.is_ward() or o.is_building():
			continue
		if o.has_flag("invisible") and o.pos.distance_to(u.pos) <= r:
			w.combat.deal_damage(u.id, u.team, true, o, float(v.damage), C.DamageType.MAGICAL, false, "reveal_dust")
	dusts.append({"team": u.team, "src": u.id, "pos": u.pos, "until": w.time + float(v.duration), "radius": r,
		"linger": float(v.linger), "slow": float(v.slow)})
	w.events.append({"t": "dust", "u": u.id, "pos": u.pos, "radius": r})
	_dust_tick()

func _dust_tick() -> void:
	for i in range(dusts.size() - 1, -1, -1):
		var z: Dictionary = dusts[i]
		if w.time >= float(z.until):
			dusts.remove_at(i)
			continue
		for o: SimUnit in w.query(z.pos, float(z.radius) + 40.0, true):
			if not o.alive or o.team == int(z.team) or o.is_ward() or o.is_building():
				continue
			if o.pos.distance_to(z.pos) > float(z.radius):
				continue
			var m := {"id": "reveal_dust", "source": -50 - int(z.team), "expires": w.time + float(z.linger),
				"truesight_by": int(z.team), "dispel": "basic", "debuff": true, "fx": "dust"}
			if o.has_flag("invisible"):
				m["slow"] = float(z.slow)
			o.add_modifier(m)

func update() -> void:
	if not dusts.is_empty() and w.tick % 6 == 0:
		_dust_tick()
	for i in range(burns.size() - 1, -1, -1):
		var b: Dictionary = burns[i]
		if w.time < float(b.until):
			continue
		burns.remove_at(i)
		var t := w.get_unit(int(b.t))
		var dmg := float(b.taken) * float(b.pct)
		if t != null and t.alive and dmg > 0.0:
			w.events.append({"t": "soul_burst", "u": t.id, "amount": dmg})
			w.combat.deal_damage(int(b.src), int(b.team), true, t, dmg, C.DamageType.MAGICAL, false, "silence_staff",
				false, {"no_amp": true})
