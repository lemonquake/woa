class_name HeroBadge
extends Control
## A hero mastery medal (run 2026-10-19 b; the owner: stars on every hero, five to a medal, Bronze, Silver, Gold,
## Platinum, Diamond, then Top 5 .. Top 1 Player): the hero's face in a round frame of the medal's metal, laurels that
## grow with the medal, the stars under it, a ribbon with the medal's name, and for Top Players a red and gold ribbon,
## rays and a glow. HeroBadge.paint() draws one on any control; `info` is Ranked.hero_medal().

const U = preload("res://src/ui/ui_kit.gd")

var hero := ""
var info := {}
var label := true                          # "<Hero> Top 2 Player" / "<Hero>  ·  Gold 3" beside the badge
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if hero != "":
		tooltip_text = "%s: %s (%s XP)" % [HeroDraft.hero_name(hero), String(info.get("name", "")), RankedNum.num(int(info.get("xp", 0)))]

func _process(dt: float) -> void:
	_t += dt
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var s := minf(size.y, size.x)
	paint(self, Rect2(Vector2.ZERO, Vector2(s, s)), hero, info, _t)
	if label:
		var f := U.font("bold")
		var fs := int(clampf(s * 0.22, 12.0, 22.0))
		var top := int(info.get("top", 0))
		var line1 := "%s %s" % [HeroDraft.hero_name(hero), String(info.get("name", ""))] if top > 0 else HeroDraft.hero_name(hero)
		draw_string(f, Vector2(s + 10, s * 0.42), line1, HORIZONTAL_ALIGNMENT_LEFT, size.x - s - 10, fs, metal(info).lightened(0.25))
		var line2 := "%s  ·  %s XP" % [String(info.get("name", "")), RankedNum.num(int(info.get("xp", 0)))] if top == 0 else "%s XP" % RankedNum.num(int(info.get("xp", 0)))
		draw_string(U.font("body"), Vector2(s + 10, s * 0.42 + fs + 4), line2, HORIZONTAL_ALIGNMENT_LEFT, size.x - s - 10, int(fs * 0.78), U.TEXT_DIM)

## The medal's metal colour.
static func metal(m: Dictionary) -> Color:
	if int(m.get("top", 0)) > 0:
		return Color(1.0, 0.78, 0.28)
	match int(m.get("medal", 0)):
		1: return Color(0.82, 0.52, 0.3)
		2: return Color(0.8, 0.83, 0.88)
		3: return Color(1.0, 0.8, 0.32)
		4: return Color(0.62, 0.95, 0.9)
		5: return Color(0.55, 0.85, 1.0)
	return Color(0.42, 0.42, 0.46)

static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var st := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		st.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(st, col)

## Draw a medal into rect r of ci. t: time (the glint moves, a Top Player's rays turn).
static func paint(ci: CanvasItem, r: Rect2, h: String, m: Dictionary, t := 0.0) -> void:
	var medal := int(m.get("medal", 0))
	var top := int(m.get("top", 0))
	var stars := int(m.get("stars", 0))
	var c := r.get_center() + Vector2(0, -r.size.y * 0.06)
	var R := r.size.x * 0.3
	var gold := metal(m)
	# a Top Player's rays and glow
	if top > 0:
		for i in 16:
			var a := TAU * float(i) / 16.0 + t * 0.4
			var l := R * (1.75 if i % 2 == 0 else 1.45)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a - 0.07), sin(a - 0.07)) * R * 0.9, c + Vector2(cos(a), sin(a)) * l,
				c + Vector2(cos(a + 0.07), sin(a + 0.07)) * R * 0.9]), Color(1.0, 0.6, 0.2, 0.45))
		ci.draw_circle(c, R * 1.4, Color(1.0, 0.45, 0.15, 0.18))
	elif medal >= 4:
		ci.draw_circle(c, R * 1.35, Color(gold, 0.16))
	# laurels: more leaves for higher medals
	var leaves: int = [0, 2, 3, 4, 5, 6][medal] if top == 0 else 7
	for side: float in [-1.0, 1.0]:
		for i in leaves:
			var a := lerpf(0.45, 2.2, float(i) / maxf(1.0, float(leaves - 1)))
			var pos := c + Vector2(side * sin(a), cos(a)) * R * 1.3
			var ang := atan2(-sin(a), side * cos(a)) * -1.0
			var leaf := PackedVector2Array()
			for k in 9:
				var u := float(k) / 8.0
				leaf.append(Vector2((u - 0.5) * R * 0.5, sin(PI * u) * R * 0.13))
			for k in range(7, 0, -1):
				var u := float(k) / 8.0
				leaf.append(Vector2((u - 0.5) * R * 0.5, -sin(PI * u) * R * 0.1))
			ci.draw_colored_polygon(Transform2D(ang + side * 0.9, pos) * leaf, gold.darkened(0.15 + 0.08 * float(i % 2)))
	# the face in a round frame
	var tex := U.hero_portrait(h)
	var circ := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		circ.append(c + Vector2(cos(a), sin(a)) * R)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	if tex:
		ci.draw_colored_polygon(circ, Color(1, 1, 1, 1) if medal > 0 or top > 0 else Color(0.6, 0.6, 0.6), uvs, tex)
	else:
		ci.draw_colored_polygon(circ, Color(0.1, 0.1, 0.14))
	ci.draw_arc(c, R, 0, TAU, 48, Color(0, 0, 0, 0.6), R * 0.16, true)
	ci.draw_arc(c, R * 1.03, 0, TAU, 48, gold, R * (0.13 if medal >= 3 or top > 0 else 0.1), true)
	if top > 0:
		ci.draw_arc(c, R * 1.15, 0, TAU, 48, Color(0.8, 0.12, 0.1), R * 0.06, true)
	if medal > 0 or top > 0:
		var g := fmod(t * 0.8, TAU)
		ci.draw_arc(c, R * 1.03, g, g + 0.6, 10, Color(1, 1, 0.92, 0.7), R * 0.08, true)
	# a Diamond's gem on top; a Top Player's big star
	if top > 0:
		_star(ci, c + Vector2(0, -R * 1.28), R * 0.36, Color(1.0, 0.86, 0.4))
	elif medal == 5:
		var gp := c + Vector2(0, -R * 1.22)
		ci.draw_colored_polygon(PackedVector2Array([gp + Vector2(0, -R * 0.28), gp + Vector2(R * 0.22, 0), gp + Vector2(0, R * 0.22),
			gp + Vector2(-R * 0.22, 0)]), Color(0.7, 0.95, 1.0))
		ci.draw_line(gp + Vector2(-R * 0.22, 0), gp + Vector2(R * 0.22, 0), Color(1, 1, 1, 0.7), 1.0)
	# the ribbon: the medal's name, or TOP n
	if medal == 0 and top == 0:
		return
	var rb := Rect2(c + Vector2(-R * 1.05, R * 0.7), Vector2(R * 2.1, R * 0.52))
	var rcol := Color(0.7, 0.1, 0.08) if top > 0 else gold.darkened(0.25)
	for sd in [-1.0, 1.0]:
		var e := rb.position.x if sd < 0 else rb.end.x
		ci.draw_colored_polygon(PackedVector2Array([Vector2(e, rb.position.y), Vector2(e + sd * R * 0.3, rb.position.y + rb.size.y * 0.1),
			Vector2(e + sd * R * 0.15, rb.position.y + rb.size.y * 0.5), Vector2(e + sd * R * 0.3, rb.end.y - rb.size.y * 0.1), Vector2(e, rb.end.y)]),
			rcol.darkened(0.3))
	ci.draw_rect(rb, rcol)
	ci.draw_rect(Rect2(rb.position, Vector2(rb.size.x, rb.size.y * 0.35)), Color(1, 1, 1, 0.18))
	var f := U.font("title")
	var txt := "TOP %d" % top if top > 0 else String(Ranked.MEDALS[medal]).to_upper()
	var fs := int(rb.size.y * 0.7)
	while f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rb.size.x - 4 and fs > 6:
		fs -= 1
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, Vector2(c.x - tw * 0.5, rb.position.y + rb.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(1, 0.92, 0.7) if top > 0 else Color(0.12, 0.07, 0.02))
	# the stars under the ribbon
	if top == 0 and stars > 0:
		var sr := R * 0.17
		for i in stars:
			var x := c.x + (float(i) - float(stars - 1) * 0.5) * sr * 2.3
			_star(ci, Vector2(x, rb.end.y + sr * 1.2), sr, gold.lightened(0.25))
