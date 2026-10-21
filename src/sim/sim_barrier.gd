class_name SimBarrier
extends RefCounted
## Barriers (run 2026-10-21; the owner: "a new feature that works like HP but yellow in color ... a buffer HP that
## blocks certain types of damage. There is a Magic Barrier, All-damage Barrier, Physical Barrier"). As Dota's
## barriers: a pool on a modifier that damage of its kind drains before health. A blow meets the barrier that only
## takes its kind first (physical, magic), then the all-damage ones (which take pure damage too). They sit after armor,
## resistances and flat block, before health; health bars draw them past the health (UnitBars, the HUD).
##
## A modifier carries one or more pools: "barrier_all", "barrier_phys", "barrier_magic" (what is left) and
## "barrier_max" (what it held when given, for the bar). One with "barrier_only" is removed once its pools are empty.
## The Shield Orb's "barrier" (all damage) and the Fade Cape's "magic_barrier" are older pools of the same kind, still
## drained by SimOrbs.absorb; total() counts them so the bars show them too.

const C = preload("res://src/sim/sim_const.gd")
const KEYS := ["barrier_phys", "barrier_magic", "barrier_all"]

## The pools that take `dtype` damage, in the order they are drained.
static func keys_for(dtype: int) -> Array:
	match dtype:
		C.DamageType.PHYSICAL:
			return ["barrier_phys", "barrier_all"]
		C.DamageType.MAGICAL:
			return ["barrier_magic", "barrier_all"]
	return ["barrier_all"]

## Give `u` a barrier: a modifier `id` from `src` holding `amount` of kind "all", "phys" or "magic" for `dur` seconds
## (INF: until spent). A second one with the same id and source replaces the first (as any modifier).
static func give(w: SimWorld, u: SimUnit, id: String, src: int, kind: String, amount: float, dur: float,
		extra := {}) -> Dictionary:
	var m := {"id": id, "source": src, "expires": w.time + dur if is_finite(dur) else INF, "barrier_only": true,
		"barrier_" + kind: amount, "barrier_max": amount, "barrier_kind": kind, "fx": "barrier_" + kind}
	m.merge(extra, true)
	u.add_modifier(m)
	w.events.append({"t": "barrier_gain", "u": u.id, "kind": kind, "amount": amount, "src": src})
	return m

## Damage `amount` of `dtype` about to land on `t` (after reductions): the barriers drain first. Returns what is left
## for health.
static func absorb(w: SimWorld, t: SimUnit, amount: float, dtype: int) -> float:
	if amount <= 0.0 or t.modifiers.is_empty():
		return amount
	var took := 0.0
	for key in keys_for(dtype):
		for i in range(t.modifiers.size() - 1, -1, -1):
			var m: Dictionary = t.modifiers[i]
			var b := float(m.get(key, 0.0))
			if b <= 0.0:
				continue
			var d := minf(b, amount)
			m[key] = b - d
			amount -= d
			took += d
			if bool(m.get("barrier_only", false)) and left_on(m) <= 0.01:
				t.modifiers.remove_at(i)
				t.stats_dirty = true
				w.events.append({"t": "barrier_break", "u": t.id, "id": String(m.id)})
			if amount <= 0.0:
				break
		if amount <= 0.0:
			break
	if took > 0.0:
		w.events.append({"t": "barrier", "u": t.id, "amount": took, "type": dtype})
	return amount

## What a modifier's pools hold.
static func left_on(m: Dictionary) -> float:
	var s := 0.0
	for k in KEYS:
		s += maxf(0.0, float(m.get(k, 0.0)))
	return s

## The barriers on `u` by kind: Vector3(all, physical, magic), the Shield Orb's and the Fade Cape's included.
static func total(u: SimUnit) -> Vector3:
	var v := Vector3.ZERO
	if u.modifiers.is_empty():
		return v
	for m in u.modifiers:
		v.x += maxf(0.0, float(m.get("barrier_all", 0.0))) + maxf(0.0, float(m.get("barrier", 0.0)))
		v.y += maxf(0.0, float(m.get("barrier_phys", 0.0)))
		v.z += maxf(0.0, float(m.get("barrier_magic", 0.0))) + maxf(0.0, float(m.get("magic_barrier", 0.0)))
	return v
