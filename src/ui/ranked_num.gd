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
