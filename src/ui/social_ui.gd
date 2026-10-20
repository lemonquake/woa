class_name SocialUi
extends RefCounted
## Shared pieces of the social screens (run 2026-10-20: Ranked, Profile, Players, Forums): the generated skin
## (tools/ui_skin_social.py: panels, cards, rows, the menu, tabs, chips, relief icons), number text, and the controls
## every screen uses (a stat card, an icon chip, a form strip, a toast).

const U = preload("res://src/ui/ui_kit.gd")
const GREEN := Color(0.24, 0.74, 0.33)
const GREEN_HI := Color(0.42, 0.95, 0.5)
const RED := Color(0.92, 0.36, 0.32)
const BLUE := Color(0.4, 0.72, 1.0)
const DIM := Color(0.62, 0.62, 0.64)

## A relief medallion (ic_*) or a bare gold glyph (gl_*).
static func icon(key: String, bare := false) -> Texture2D:
	return U.skin_tex(("gl_" if bare else "ic_") + key)

static func panel(ci: CanvasItem, r: Rect2, blue := false) -> void:
	U.skin(ci, "soc_panel_blue" if blue else "soc_panel", r)

## Where a mouse event happened on screen (the menus open there): from the event itself, not the last known mouse
## position (which a right-click without a move before it does not update).
static func at(c: CanvasItem, e: InputEvent) -> Vector2:
	if e is InputEventMouse:
		return c.get_global_transform_with_canvas() * (e as InputEventMouse).position
	return c.get_global_mouse_position()

## A right mouse press (the context menus).
static func is_right(e: InputEvent) -> bool:
	return e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT

static func is_left(e: InputEvent) -> bool:
	return e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT

## A number with one decimal, "-" when unknown (< 0).
static func dec(v: float, places := 1) -> String:
	if v < 0.0:
		return "-"
	return ("%." + str(places) + "f") % v

static func whole(v: float) -> String:
	return "-" if v < 0.0 else RankedNum.num(int(round(v)))

## A form strip: the last results as small plates (W green, L red), newest left.
static func draw_form(ci: CanvasItem, at: Vector2, form: String, cell := 22.0, gap := 4.0) -> void:
	var f := U.font("bold")
	for i in form.length():
		var won := form[i] == "W"
		var r := Rect2(at + Vector2(i * (cell + gap), 0), Vector2(cell, cell))
		ci.draw_rect(r, Color(GREEN, 0.9) if won else Color(RED, 0.85))
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1, 1, 1, 0.25))
		var tw := f.get_string_size(form[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell * 0.6)).x
		ci.draw_string(f, r.position + Vector2((cell - tw) * 0.5, cell * 0.74), form[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell * 0.6), Color(0, 0, 0, 0.75))

## Text right-aligned at x_right.
static func text_r(ci: CanvasItem, s: String, x_right: float, y: float, px: int, col: Color, kind := "body") -> void:
	var f := U.font(kind)
	ci.draw_string(f, Vector2(x_right - f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

static func text_c(ci: CanvasItem, s: String, x_mid: float, y: float, px: int, col: Color, kind := "body") -> void:
	var f := U.font(kind)
	ci.draw_string(f, Vector2(x_mid - f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

## A stat card: a relief icon, the label, the big value, a small line under it; hover lights it and shows `tip`.
class StatCard extends Control:
	var key := ""                          # icon key (SocialUi.icon)
	var title := ""
	var value := ""
	var sub := ""
	var value_col := Color(0.93, 0.92, 0.88)
	var gold := false
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		U.skin(self, "soc_card_hi" if _hot else ("soc_card_gold" if gold else "soc_card"), r)
		var s := minf(size.y - 24.0, 52.0)
		var ic := SocialUi.icon(key)
		var x := 14.0
		if ic:
			draw_texture_rect(ic, Rect2(12, (size.y - s) * 0.5, s, s), false)
			x = 12.0 + s + 12.0
		draw_string(U.font("body"), Vector2(x, size.y * 0.5 - 12), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 14, Color(0.7, 0.7, 0.72))
		# the value shrinks to fit the card ("34.0 / 0.0 / 14.5")
		var px := 25
		while px > 15 and U.font("bold").get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x - x - 10:
			px -= 1
		draw_string(U.font("bold"), Vector2(x, size.y * 0.5 + 15), value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, value_col)
		if sub != "":
			draw_string(U.font("body"), Vector2(x, size.y * 0.5 + 35), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 13, Color(0.6, 0.6, 0.62))

## A trophy count for the banner: a big relief icon, the number, the label.
class Trophy extends Control:
	var key := ""
	var count := 0
	var title := ""
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _draw() -> void:
		var s := size.x * 0.62
		var ic := SocialUi.icon(key)
		var r := Rect2((size.x - s) * 0.5, 0, s, s)
		if _hot:
			U.art_rect(self, "glow_gold", r.grow(14), Color(1, 1, 1, 0.55))
		if ic:
			draw_texture_rect(ic, r, false)
		SocialUi.text_c(self, RankedNum.num(count), size.x * 0.5, s + 26, 24, U.GOLD if count > 0 else Color(0.75, 0.75, 0.78), "bold")
		SocialUi.text_c(self, title, size.x * 0.5, s + 46, 13, Color(0.72, 0.72, 0.74))

## A small toggle tab drawn on the skin: gold bar under the active one.
class Tabs extends Control:
	signal changed(id: String)
	var items: Array = []                  # [[id, text]]
	var active := ""
	var px := 17
	var _hot := -1
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_exited.connect(func():
			_hot = -1
			queue_redraw())
	func _widths() -> Array:
		var f := U.font("bold")
		var out: Array = []
		for it in items:
			out.append(f.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 30.0)
		return out
	func _at(x: float) -> int:
		var acc := 0.0
		var ws := _widths()
		for i in ws.size():
			if x >= acc and x < acc + float(ws[i]):
				return i
			acc += float(ws[i])
		return -1
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var h := _at((e as InputEventMouseMotion).position.x)
			if h != _hot:
				_hot = h
				queue_redraw()
		elif SocialUi.is_left(e):
			var i := _at((e as InputEventMouseButton).position.x)
			if i >= 0 and String(items[i][0]) != active:
				Options.click()
				active = String(items[i][0])
				changed.emit(active)
				queue_redraw()
			accept_event()
	func _draw() -> void:
		var ws := _widths()
		var x := 0.0
		var f := U.font("bold")
		for i in items.size():
			var on := String(items[i][0]) == active
			var r := Rect2(x, 0, float(ws[i]), size.y)
			if on:
				U.skin(self, "soc_tab_on", r)
			elif i == _hot:
				U.skin(self, "soc_tab_hover", r)
			draw_string(f, Vector2(x + 15, size.y * 0.5 + px * 0.36), String(items[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, px,
				U.GOLD if on else (Color(1, 0.92, 0.75) if i == _hot else Color(0.68, 0.68, 0.7)))
			x += float(ws[i])

## The page backdrop: the generated painting, a slow warm haze over it.
static func backdrop(parent: Control) -> void:
	var bg := TextureRect.new()
	bg.texture = U.skin_tex("soc_bg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var haze := ColorRect.new()
	haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV;
	float c = n(uv * vec2(3.0, 2.0) + vec2(TIME * 0.012, 0.0)) * n(uv * vec2(5.0, 3.5) - vec2(0.0, TIME * 0.009));
	vec3 col = vec3(0.3, 0.22, 0.08) * smoothstep(0.25, 0.75, c);
	COLOR = vec4(col, 0.16 * smoothstep(1.1, 0.2, uv.y));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	haze.material = m
	parent.add_child(haze)
