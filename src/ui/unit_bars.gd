class_name UnitBars
extends Control
## Health bars above every visible unit, drawn in screen space like Dota: thin dark frames, green for your side,
## red for enemies, gold-brown for neutrals; heroes get a wider bar with 250-health ticks, a mana bar and a level
## badge; buildings a long bar. Also draws floating combat text (gold, denies, misses).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var game: Node                             # Main
var font: Font
var popups: Array = []                     # [{text, pos3, t, color, size, rise}]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func popup(text: String, at: Vector3, color: Color, size := 18, rise := 1.2) -> void:
	popups.append({"text": text, "pos": at, "t": 0.0, "color": color, "size": size, "rise": rise})

func _process(dt: float) -> void:
	for p in popups:
		p.t += dt
	popups = popups.filter(func(p): return p.t < 1.4)
	queue_redraw()

func _draw() -> void:
	if game == null or game.world == null:
		return
	var cam: Camera3D = game.camera.cam
	var w: SimWorld = game.world
	var my_team: int = game.player_team
	var vp := get_viewport_rect().size
	for v in game.views.values():
		var u: SimUnit = w.get_unit(v.uid)
		if u == null or not u.alive or not v.visible:
			continue
		if u.kind == K.WARD:
			continue
		var top: Vector3 = v.global_position + Vector3(0, v.bar_height, 0)
		if cam.is_position_behind(top):
			continue
		var s := cam.unproject_position(top)
		if s.x < -100 or s.y < -50 or s.x > vp.x + 100 or s.y > vp.y + 50:
			continue
		_bar(u, s, my_team)
	for p in popups:
		var pos: Vector3 = p.pos + Vector3(0, p.t * p.rise, 0)
		if cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos)
		var a := clampf(1.6 - p.t * 1.2, 0.0, 1.0)
		var col: Color = p.color
		col.a = a
		var sz: int = p.size
		var tw := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string_outline(font, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, a * 0.85))
		draw_string(font, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _bar(u: SimUnit, s: Vector2, my_team: int) -> void:
	var width := 46.0
	var height := 5.0
	if u.is_hero():
		width = 92.0
		height = 9.0
	elif u.is_building():
		width = 120.0 if u.kind != K.ANCIENT else 170.0
		height = 9.0
	elif u.kind == K.CREEP_SIEGE:
		width = 60.0
	var frac := clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0)
	var col: Color
	if u.team == C.NEUTRAL:
		col = Color(0.85, 0.62, 0.22)
	elif u.team == my_team:
		col = Color(0.32, 0.86, 0.26) if not (u.is_hero() and u.player) else Color(0.2, 0.95, 0.3)
	else:
		col = Color(0.92, 0.2, 0.16)
	var r := Rect2(s.x - width * 0.5, s.y - height, width, height)
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.85))
	draw_rect(r, Color(0.12, 0.1, 0.1, 0.9))
	var fill := Rect2(r.position, Vector2(width * frac, height))
	draw_rect(fill, col)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, height * 0.35)), Color(1, 1, 1, 0.18))
	if u.is_hero():
		# a tick every 250 health
		var ticks := int(u.max_hp / 250.0)
		for i in range(1, ticks + 1):
			var x := r.position.x + width * (i * 250.0 / u.max_hp)
			if x < r.end.x - 1:
				draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + height * (0.5 if i % 4 else 1.0)), Color(0, 0, 0, 0.7), 1.0)
		var mr := Rect2(r.position.x, r.end.y + 2, width, 4)
		draw_rect(mr.grow(1.0), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(mr.position, Vector2(width * clampf(u.mana / maxf(1.0, u.max_mana), 0.0, 1.0), 4)), Color(0.25, 0.5, 1.0))
		var lv := str(u.level)
		var badge := Rect2(r.position.x - 20, r.position.y - 4, 18, 17)
		draw_rect(badge, Color(0.05, 0.05, 0.07, 0.95))
		draw_rect(badge, Color(0.85, 0.7, 0.35), false, 1.0)
		var tw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(badge.position.x + 9 - tw * 0.5, badge.position.y + 13), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.92, 0.7))
		var nm := u.name if u.look.get("display_name", "") == "" else String(u.look.display_name)
		var nf := UiKit.font("bold")
		var nw := nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(nf, Vector2(s.x - nw * 0.5, r.position.y - 7), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
		draw_string(nf, Vector2(s.x - nw * 0.5, r.position.y - 7), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.lightened(0.45))
