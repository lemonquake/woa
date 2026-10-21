class_name BarrierBar
extends RefCounted
## Barriers on a health bar (run 2026-10-21; SimBarrier): the pools drawn past the health, All-damage gold, physical
## orange, magic blue, each with a bright top edge. When health and barriers together pass the whole bar, the
## barriers sit at its end over the health (as Dota draws them). Used by UnitBars and the HUD.

const COL_ALL := Color(1.0, 0.84, 0.25)
const COL_PHYS := Color(1.0, 0.56, 0.22)
const COL_MAGIC := Color(0.42, 0.68, 1.0)

## Draw on `ci` inside bar rectangle `r` for health fraction `frac` of `max_hp`, barriers `bt` (SimBarrier.total).
static func draw(ci: CanvasItem, r: Rect2, frac: float, max_hp: float, bt: Vector3) -> void:
	if max_hp <= 0.0:
		return
	var parts := [[bt.x, COL_ALL], [bt.y, COL_PHYS], [bt.z, COL_MAGIC]]
	var total := (bt.x + bt.y + bt.z) / max_hp
	if total <= 0.0:
		return
	var w := r.size.x
	var start := clampf(frac, 0.0, 1.0)
	if start + total > 1.0:
		start = maxf(0.0, 1.0 - total)
	var x := r.position.x + w * start
	for p in parts:
		var f := float(p[0]) / max_hp
		if f <= 0.0:
			continue
		var pw := minf(w * f, r.end.x - x)
		if pw <= 0.0:
			break
		var c: Color = p[1]
		ci.draw_rect(Rect2(x, r.position.y, pw, r.size.y), Color(c, 0.92))
		ci.draw_rect(Rect2(x, r.position.y, pw, maxf(1.0, r.size.y * 0.3)), Color(1, 1, 1, 0.35))
		x += pw
	ci.draw_line(Vector2(r.position.x + w * start, r.position.y), Vector2(r.position.x + w * start, r.end.y),
		Color(1, 1, 1, 0.55), 1.0)

## "+120" for the barriers on `u` (the HUD's health text), "" when none.
static func text(bt: Vector3) -> String:
	var s := bt.x + bt.y + bt.z
	return "  +%d" % int(round(s)) if s >= 1.0 else ""
