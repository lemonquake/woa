class_name SimBotTactics
extends RefCounted
## Escape craft for bots (run 2026-10-15 g): where to run so the chasers lose sight, and when a chase is over.
##
## A bot on the run does not just walk the straight road home. Every half second it looks at spots 350-800 away,
## roughly away from its chasers and toward safety, and prefers one that a tree line or higher ground hides from every
## chaser, that stands among trees (the fog closes behind it there) and that the enemy team does not see now. Once
## the enemy has not seen it for 2 seconds and no chaser is in sight, it has juked them: it teleports home from the
## fog, where they cannot follow it to cancel the channel.

const JUKE_RADII := [350.0, 550.0, 800.0]
const JUKE_DIRS := 14

## The spot to run to now: a juke spot when one is clearly better than the straight way to `safe`, else `safe`.
## `chasers`: where the chasers are (or were last seen: no peeking into the fog).
static func juke_point(w: SimWorld, h: SimUnit, chasers: PackedVector2Array, safe: Vector2) -> Vector2:
	if chasers.is_empty():
		return safe
	var from := Vector2.ZERO
	for c in chasers:
		from += c
	from /= float(chasers.size())
	var away := h.pos - from
	away = away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var home := safe - h.pos
	home = home.normalized() if home.length() > 1.0 else away
	# mostly away from them, partly toward safety
	var want := (away * 0.6 + home * 0.4).normalized()
	var enemy := 1 - h.team
	var best := safe
	var best_s := _score(w, h, chasers, enemy, h.pos + home * 600.0, want, false) + 0.4
	for k in JUKE_DIRS:
		var d := Vector2.from_angle(TAU * k / float(JUKE_DIRS))
		if d.dot(want) < -0.15:
			continue                       # never back toward them
		for r in JUKE_RADII:
			var q: Vector2 = h.pos + d * r
			if not w.map.is_walkable(q) or not w.map.line_walkable(h.pos, q):
				continue
			var s := _score(w, h, chasers, enemy, q, want, true)
			if s > best_s:
				best_s = s
				best = q
	return best

static func _score(w: SimWorld, h: SimUnit, chasers: PackedVector2Array, enemy: int, q: Vector2, want: Vector2,
		check: bool) -> float:
	var s := (q - h.pos).normalized().dot(want) * 1.2
	var hidden := 0
	var closest := INF
	var mine := INF
	for cp in chasers:
		closest = minf(closest, cp.distance_to(q))
		mine = minf(mine, cp.distance_to(h.pos))
		if check and w.map.sight_blocked(cp, q):
			hidden += 1
	s += 2.0 * float(hidden) / float(chasers.size())
	if check:
		s += minf(6.0, float(w.map.tree_cover(q))) * 0.15
		if not w.vision.cell_visible(enemy, q):
			s += 0.8
	# do not run into reach of a chaser
	if closest < 300.0:
		s -= 3.0
	elif closest < mine:
		s -= 1.0
	return s
