class_name RankedNum
extends RefCounted
## Number and time wording for the ranked screens (run 2026-10-19 b): 1,043; 2:05; "3 min ago"; role names.

static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

static func ago(t: int) -> String:
	var d := Ranked.now() - t
	if d < 90:
		return "just now"
	if d < 3600:
		return "%d min ago" % (d / 60)
	if d < 86400:
		return "%d h ago" % (d / 3600)
	return "%d days ago" % (d / 86400)

static func role(r: int) -> String:
	return String(Ranked.ROLE_NAMES[clampi(r - 1, 0, 4)]) if r >= 1 else "Any role"

## "1 win", "3 wins".
static func count(n: int, one: String, many: String) -> String:
	return "%s %s" % [num(n), one if n == 1 else many]

## A flat rounded panel style (the ranked screens' panels and glows).
static func flat(bg: Color, border: Color, rad := 8, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(rad)
	s.anti_aliasing = true
	return s

## "MVP last game": a small gold tag whose right edge is at `at` (top right corner), with a light sweeping across.
static func mvp_tag(ci: CanvasItem, at: Vector2, a: float, t: float) -> void:
	var txt := "MVP last game"
	var f := UiKit.font("bold")
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var r := Rect2(at.x - tw - 18, at.y, tw + 18, 21)
	ci.draw_style_box(RankedNum.flat(Color(0.95, 0.75, 0.3, 0.95 * a), Color(1.0, 0.95, 0.7, a), 10, 1), r)
	var sweep := fposmod(t * 0.6, 1.6) - 0.3
	if sweep >= 0.0 and sweep <= 1.0:
		ci.draw_rect(Rect2(r.position.x + r.size.x * sweep - 4, r.position.y + 1, 8, r.size.y - 2), Color(1, 1, 1, 0.35 * a))
	ci.draw_string(f, r.position + Vector2(9, 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.18, 0.11, 0.02, a))
