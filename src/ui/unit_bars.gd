class_name UnitBars
extends Control
## Health bars above every visible unit, drawn in screen space like Dota: thin dark frames, green for your side,
## red for enemies, gold-brown for neutrals; heroes get a wider bar with 250-health ticks, a mana bar and a level
## badge; buildings a long bar. Also draws floating combat text (gold, denies, misses).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var game: Node                             # Main
var font: Font
var popups: Array = []                     # [{text, pos, t, color, size, rise, life, drift, pop}]
var _texts: Array = []                     # deferred labels: [font, pos, text, size, outline, colour]
var _ghost := {}                           # unit id -> [shown health fraction, time it last dropped]
var _icons: Array = []                     # deferred status icons: [texture, rect, remaining fraction]
var _mod_seen := {}                        # "unit:modifier:expiry" -> game time first seen (icon timers)

const STATUS_ICONS := {"stun": "status/stunned", "slow": "status/slowed", "frost": "status/chilled",
	"curse": "status/cursed", "taint": "status/empowered", "unholy": "status/titan", "fatigue": "status/weakened",
	"heal": "status/regen", "mana": "status/arcane_charge", "berserk": "status/frenzy"}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func popup(text: String, at: Vector3, color: Color, size := 18, rise := 1.2, life := 1.3, drift := Vector2.ZERO,
		pop := false) -> void:
	popups.append({"text": text, "pos": at, "t": 0.0, "color": color, "size": size, "rise": rise, "life": life,
		"drift": drift, "pop": pop})
	if popups.size() > 90:
		popups.pop_front()

const DMG_COLORS := [Color(1.0, 0.86, 0.62), Color(0.5, 0.68, 1.0), Color(1.0, 0.86, 0.32)]

## Floating damage numbers. style: "out" (dealt by your hero), "in" (taken by your hero), "spell" (other heroes'
## spells you can see), "reflect" (Unholy Might's deflected half).
func damage_number(amount: float, dtype: int, at: Vector3, style: String) -> void:
	if amount < 0.5:
		return
	var n := int(round(amount))
	var size := int(clampf(15.0 + log(amount + 1.0) * 2.6, 16.0, 32.0))
	var col: Color = DMG_COLORS[clampi(dtype, 0, 2)]
	var drift := Vector2(randf_range(-26.0, 26.0), 0.0)
	var text := str(n)
	match style:
		"in":
			col = Color(1.0, 0.32, 0.26)
			size = int(size * 0.85)
			drift = Vector2(randf_range(-48.0, -18.0), 6.0)
			text = "-" + text
		"spell":
			size = int(size * 0.85)
		"reflect":
			col = Color(0.78, 0.45, 1.0)
	popup(text, at, col, size, 1.1, 1.05, drift, true)

func _process(dt: float) -> void:
	for p in popups:
		p.t += dt
	popups = popups.filter(func(p): return p.t < p.life)
	queue_redraw()

func _draw() -> void:
	if game == null or game.world == null:
		return
	var cam: Camera3D = game.camera.cam
	var w: SimWorld = game.world
	var my_team: int = game.player_team
	var vp := get_viewport_rect().size
	_texts.clear()
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
	for ic in _icons:
		var rr: Rect2 = ic[1]
		draw_rect(rr.grow(1.0), Color(0, 0, 0, 0.8))
		draw_texture_rect(ic[0], rr, false, Color(1, 1, 1))
		if float(ic[2]) < 1.0:
			draw_rect(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * (1.0 - float(ic[2])))), Color(0, 0, 0, 0.55))
	_icons.clear()
	# text after every rectangle, so the renderer can batch each kind together
	for t in _texts:
		draw_string_outline(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[4], Color(0, 0, 0, 0.9))
	for t in _texts:
		draw_string(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[5])
	var dr: Rect2 = game.input.drag_rect if game.input else Rect2()
	if dr.size.x > 1.0 and dr.size.y > 1.0:
		draw_rect(dr, Color(0.25, 1.0, 0.35, 0.10))
		draw_rect(dr, Color(0.35, 1.0, 0.45, 0.9), false, 1.5)
	var pf := UiKit.font("bold")
	for p in popups:
		var k: float = p.t / p.life
		# rise fast then settle (ease out), pop in big, fade over the last third
		var pos: Vector3 = p.pos + Vector3(0, (1.0 - pow(1.0 - k, 2.2)) * p.rise, 0)
		if cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos) + (p.drift as Vector2) * k
		var a := 1.0 - smoothstep(0.62, 1.0, k)
		var col: Color = p.color
		col.a = a
		var scale := 1.0 + (0.55 * exp(-p.t * 16.0) if p.pop else 0.0)
		var sz := int(round(p.size * scale))
		var tw := pf.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string_outline(pf, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, a * 0.9))
		draw_string(pf, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

## Small icons under a hero's bars for what affects it, darkened as their time runs out.
func _status_icons(u: SimUnit, at: Vector2) -> void:
	var x := at.x
	var shown := {}
	var now: float = game.world.time
	for m in u.modifiers:
		var key := String(m.get("fx", ""))
		if key == "" and float(m.get("slow", 0.0)) > 0.0:
			key = "slow"
		if key == "" or shown.has(key) or not STATUS_ICONS.has(key):
			continue
		shown[key] = true
		var tex: Texture2D = UiKit.icon(STATUS_ICONS[key])
		if tex == null:
			continue
		var left := 1.0
		var exp_t := float(m.get("expires", -1.0))
		if exp_t > 0.0:
			var mk := "%d:%s:%.2f" % [u.id, String(m.id), exp_t]
			if not _mod_seen.has(mk):
				if _mod_seen.size() > 400:
					_mod_seen.clear()
				_mod_seen[mk] = now
			var total := maxf(0.1, exp_t - float(_mod_seen[mk]))
			left = clampf((exp_t - now) / total, 0.0, 1.0)
		_icons.append([tex, Rect2(x, at.y, 16, 16), left])
		x += 19.0

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
	# recent damage lingers as a pale chunk, then drains away
	var now := Time.get_ticks_msec() / 1000.0
	var g: Array = _ghost.get(u.id, [frac, now])
	if frac < float(g[0]):
		if now - float(g[1]) > 0.45:
			g[0] = maxf(frac, float(g[0]) - get_process_delta_time() * 0.9)
	else:
		g[0] = frac
		g[1] = now
	if frac < float(g[0]) - 0.002 and now - float(g[1]) <= 0.02:
		g[1] = now
	_ghost[u.id] = g
	if float(g[0]) > frac:
		draw_rect(Rect2(r.position.x + width * frac, r.position.y, width * (float(g[0]) - frac), height), Color(1.0, 0.93, 0.7, 0.85))
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
		_texts.append([font, Vector2(badge.position.x + 9 - tw * 0.5, badge.position.y + 13), lv, 12, 0, Color(1, 0.92, 0.7)])
		_status_icons(u, Vector2(r.position.x, r.end.y + 9))
		var nm := u.name if u.look.get("display_name", "") == "" else String(u.look.display_name)
		var nf := UiKit.font("bold")
		var nw := nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_texts.append([nf, Vector2(s.x - nw * 0.5, r.position.y - 7), nm, 16, 5, col.lightened(0.45)])
