class_name TitleCard
extends Control
## The animated title screen (run 2026-10-15 g), shown once when the game starts, over the Main Menu.
##
## A night sky over dark hills where the game's two sides meet: the gold sun of Ancient Light rises on the left, the
## black sun of Black Sun with its crimson corona on the right, their light clashing in a bright seam in the middle,
## sparks drifting up (gold on one side, crimson on the other). The title burns in from the centre with a glowing
## edge and settles; a light sweeps across it; "by Aljay Leodones" is written out under it between two gold rules;
## then "Press any key" breathes at the foot of the screen. Any key or click during the intro skips to its end; one
## more leaves: the card fades and the menu comes in (signal `finished`).

signal finished

const U = preload("res://src/ui/ui_kit.gd")

const INTRO := 4.2                         # seconds until the prompt shows
const LEAVE := 0.9                         # the fade into the menu

const SKY := """
shader_type canvas_item;
uniform float t = 0.0;
uniform float rise = 0.0;      // 0..1 the suns come up
uniform float fade = 1.0;      // 0 black .. 1 full
uniform vec2 look = vec2(0.0); // parallax from the mouse
float h1(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float n2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * n2(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
// rising sparks: one per grid cell, drifting up and swaying
float sparks(vec2 p, float scale, float speed, float seed) {
	vec2 q = p * scale;
	q.y += t * speed;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float r = h1(id + seed);
	if (r < 0.55) return 0.0;
	vec2 c = vec2(h1(id + seed + 3.1) - 0.5, h1(id + seed + 7.7) - 0.5) * 0.6;
	c.x += sin(t * 1.3 + r * 30.0) * 0.12;
	float d = length(f - c);
	float tw = 0.6 + 0.4 * sin(t * 6.0 + r * 50.0);
	return smoothstep(0.06, 0.0, d) * tw;
}
void fragment() {
	vec2 uv = UV;
	vec2 p = (uv - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	p += look * 0.015;
	float y = 1.0 - uv.y;
	// the night: deep blue at the top, warm and crimson haze toward the horizon at each side
	vec3 col = mix(vec3(0.02, 0.025, 0.05), vec3(0.006, 0.008, 0.016), uv.y * 0.2);
	vec2 gpos = vec2(-0.62, 0.10 - rise * 0.22);       // gold sun (Ancient Light)
	vec2 bpos = vec2(0.62, 0.10 - rise * 0.22);        // black sun (Black Sun)
	float side = smoothstep(-0.25, 0.25, p.x);          // 0 left .. 1 right
	vec3 warm = vec3(1.0, 0.68, 0.26);
	vec3 crim = vec3(0.95, 0.12, 0.10);
	col += mix(warm * 0.22, crim * 0.16, side) * smoothstep(0.75, 0.0, uv.y * 0.9) * rise;
	// clouds lit by the two suns
	vec2 q = vec2(fbm(p * 2.0 + vec2(t * 0.012, 0.0)), fbm(p * 2.0 + vec2(4.3, -t * 0.01)));
	float cl = fbm(p * 1.7 + q * 1.5 + vec2(t * 0.008, 0.0));
	float lit_g = exp(-pow(length(p - gpos) * 1.4, 2.0));
	float lit_b = exp(-pow(length(p - bpos) * 1.4, 2.0));
	vec3 cloud_col = vec3(0.08, 0.09, 0.14) + warm * lit_g * 0.7 * rise + crim * lit_b * 0.55 * rise;
	col = mix(col, cloud_col, smoothstep(0.42, 0.9, cl) * 0.85);
	// stars where the sky is clear
	float st = pow(h1(floor(uv * vec2(900.0, 500.0))), 60.0) * (0.6 + 0.4 * sin(t * 2.0 + uv.x * 40.0));
	col += vec3(0.8, 0.85, 1.0) * st * (1.0 - smoothstep(0.35, 0.8, cl)) * (1.0 - rise * 0.5);
	// the gold sun: a white-hot disc, a gold halo, slow rays
	float dg = length(p - gpos);
	float ag = atan(p.y - gpos.y, p.x - gpos.x);
	float rays_g = pow(0.5 + 0.5 * sin(ag * 18.0 + t * 0.15 + fbm(vec2(cos(ag), sin(ag)) * 2.0 + t * 0.05) * 4.0), 5.0);
	col += warm * exp(-dg * 3.6) * 0.7 * rise;
	col += warm * rays_g * exp(-dg * 2.2) * 0.35 * rise;
	col = mix(col, vec3(1.0, 0.95, 0.8), smoothstep(0.105, 0.095, dg) * rise);
	// the black sun: a black disc, a crimson corona flickering round it, dark rays
	float db = length(p - bpos);
	float ab = atan(p.y - bpos.y, p.x - bpos.x);
	float flick = fbm(vec2(cos(ab), sin(ab)) * 3.0 + t * 0.4) * 0.03;
	float corona = exp(-pow((db - 0.105 - flick) * 28.0, 2.0));
	float rays_b = pow(0.5 + 0.5 * sin(ab * 14.0 - t * 0.12 + fbm(vec2(cos(ab), sin(ab)) * 2.0 - t * 0.05) * 4.0), 6.0);
	col += crim * exp(-db * 3.4) * 0.65 * rise;
	col += crim * rays_b * exp(-db * 2.4) * 0.3 * rise;
	col += vec3(1.0, 0.35, 0.2) * corona * 1.6 * rise;
	col = mix(col, vec3(0.0, 0.0, 0.0), smoothstep(0.1, 0.092, db) * rise);
	// where the two lights meet: a bright seam behind the title
	float seam = exp(-pow(p.x * 9.0, 2.0)) * exp(-pow((p.y + 0.06) * 2.2, 2.0));
	col += mix(warm, crim, 0.5 + 0.5 * sin(t * 0.7 + p.y * 6.0)) * seam * 0.35 * rise;
	col += vec3(1.0, 0.85, 0.6) * exp(-pow(length(p - vec2(0.0, -0.08)) * 2.4, 2.0)) * 0.16 * rise;
	// hills: three ridges, rim-lit by the sun on their side
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float hgt = 0.27 - fi * 0.07 + 0.06 * fbm(vec2(uv.x * (2.5 + fi * 1.5) + fi * 7.0 + look.x * 0.01 * (fi + 1.0), fi));
		hgt += 0.03 * sin(uv.x * (5.0 + fi * 3.0) + fi);
		float m = smoothstep(hgt + 0.003, hgt - 0.003, y);
		vec3 hc = vec3(0.012, 0.014, 0.022) * (1.4 - fi * 0.4);
		float rim = smoothstep(hgt - 0.012, hgt, y) * m;
		hc += mix(warm, crim, side) * rim * 0.35 * rise * (1.0 - fi * 0.3);
		col = mix(col, hc, m);
	}
	// sparks: gold to the left, crimson to the right
	float sp = sparks(p, 9.0, 0.35, 1.0) + sparks(p + 3.7, 14.0, 0.5, 5.0) * 0.7 + sparks(p + 9.1, 22.0, 0.7, 9.0) * 0.45;
	col += mix(vec3(1.0, 0.75, 0.35), vec3(1.0, 0.3, 0.2), side) * sp * (0.3 + 0.7 * rise) * smoothstep(0.0, 0.6, y + 0.2);
	// vignette and the fade from black
	col *= 1.0 - 0.6 * pow(length(uv - 0.5) * 1.25, 2.4);
	COLOR = vec4(col * fade, 1.0);
}
"""

## The title burning in: pixels appear outward from the centre through noise, with a hot edge; then a light sweeps.
const LOGO := """
shader_type canvas_item;
uniform float reveal = 0.0;
uniform float sweep = -1.0;
float h1(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float n2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length((UV - 0.5) * vec2(1.0, 0.45)) * 1.6 + n2(UV * 18.0) * 0.25;
	float edge = reveal * 1.3;
	float shown = smoothstep(edge, edge - 0.08, d);
	float rim = smoothstep(edge - 0.12, edge - 0.02, d) * shown;
	c.rgb += vec3(1.0, 0.7, 0.3) * rim * 2.0 * c.a;
	float x = UV.x - UV.y * 0.3;
	c.rgb += vec3(1.0, 0.93, 0.72) * exp(-pow((x - sweep) * 8.0, 2.0)) * 0.8 * c.a;
	COLOR = vec4(c.rgb, c.a * shown) * COLOR;
}
"""

var _t := 0.0
var _leaving := -1.0
var _sky: ColorRect
var _sky_mat: ShaderMaterial
var _logo: TextureRect
var _logo_mat: ShaderMaterial
var _by: Label
var _rules: Control
var _prompt: Label
var _flash: ColorRect
var _sounds := {}
var _played := {}
var look := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sky = ColorRect.new()
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky_mat = _shader(SKY)
	_sky.material = _sky_mat
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)
	_logo = TextureRect.new()
	_logo.texture = U.skin_tex("logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_mat = _shader(LOGO)
	_logo.material = _logo_mat
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	_rules = Control.new()
	_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules.draw.connect(_draw_rules)
	add_child(_rules)
	_by = _label("by Aljay Leodones", 34, Color(0.97, 0.86, 0.6), 6)
	_prompt = _label("Press any key", 24, Color(0.9, 0.88, 0.82), 3)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.9, 0.7, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_layout()
	resized.connect(_layout)
	Options.ensure_buses()
	_apply(0.0)

func _shader(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = code
	m.shader = s
	return m

func _label(text: String, size: int, col: Color, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fv := FontVariation.new()
	fv.base_font = U.font("title")
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.01))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _layout() -> void:
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var ls := U.art_size("logo") * 1.35
	_logo.size = ls
	_logo.pivot_offset = ls * 0.5
	_logo.position = Vector2((vs.x - ls.x) * 0.5, vs.y * 0.36 - ls.y * 0.5)
	_by.size = Vector2(vs.x, 50)
	_by.position = Vector2(0, _logo.position.y + ls.y + 6)
	_rules.size = vs
	_prompt.size = Vector2(vs.x, 40)
	_prompt.position = Vector2(0, vs.y - 150)

## The two gold rules either side of the credit, drawn out from it as it is written.
func _draw_rules() -> void:
	var k := clampf((_t - 2.5) / 0.9, 0.0, 1.0)
	if k <= 0.0:
		return
	var y := _by.position.y + 27.0
	var cx := size.x * 0.5
	var gap := 240.0
	var ln := 260.0 * _ease(k)
	var col := Color(0.95, 0.76, 0.38, 0.85 * k)
	for s in [-1.0, 1.0]:
		var a := Vector2(cx + s * gap, y)
		var b := Vector2(cx + s * (gap + ln), y)
		_rules.draw_line(a, b, col, 2.0, true)
		_rules.draw_line(a + Vector2(0, 4), b - Vector2(s * ln * 0.25, -4), Color(col, col.a * 0.4), 1.0, true)
		var d := 7.0
		var c := a + Vector2(-s * 12.0, 0)
		_rules.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d),
			c + Vector2(-d, 0)]), col)

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

func _process(dt: float) -> void:
	_t += dt
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var m := get_local_mouse_position() / maxf(1.0, vs.x) - Vector2(0.5, 0.5 * vs.y / maxf(1.0, vs.x))
	look = look.lerp(m * 2.0, minf(1.0, dt * 2.0))
	_apply(dt)
	if _leaving >= 0.0:
		_leaving += dt
		modulate.a = 1.0 - _ease(_leaving / LEAVE)
		if _leaving >= LEAVE:
			finished.emit()
			queue_free()

## The intro timeline: fade from black (0-0.8 s), the suns rise (0.3-3 s), the title burns in (0.9-2.4 s) with a flash
## and a light sweep, the credit is written (2.5-3.5 s), the prompt from 4.2 s.
func _apply(dt: float) -> void:
	var t := _t
	_sky_mat.set_shader_parameter("t", t)
	_sky_mat.set_shader_parameter("fade", _ease(t / 0.8))
	_sky_mat.set_shader_parameter("rise", _ease((t - 0.3) / 2.7))
	_sky_mat.set_shader_parameter("look", look)
	var r := clampf((t - 0.9) / 1.5, 0.0, 1.0)
	_logo_mat.set_shader_parameter("reveal", r)
	var sc := 1.12 - 0.12 * _ease(r)
	_logo.scale = Vector2(sc, sc)
	# a light sweeps across the title after it lands, then again every 7 s
	var sw := fmod(maxf(0.0, t - 2.3), 7.0)
	_logo_mat.set_shader_parameter("sweep", -0.4 + sw * 1.1)
	if t > 2.3 and not _played.has("land"):
		_played["land"] = true
		_flash.color.a = 0.22
		_play("holy_strike", -8.0)
	if t > 0.9 and not _played.has("burn"):
		_played["burn"] = true
		_play("fire_whoosh", -10.0)
	_flash.color.a = maxf(0.0, _flash.color.a - dt * 0.6)
	# the credit is written out letter by letter, the rules drawn out beside it
	_by.visible_ratio = clampf((t - 2.5) / 1.0, 0.0, 1.0)
	_by.modulate.a = clampf((t - 2.5) / 0.4, 0.0, 1.0)
	_rules.queue_redraw()
	# the prompt breathes
	var pk := clampf((t - INTRO) / 0.6, 0.0, 1.0)
	_prompt.modulate.a = pk * (0.75 + 0.25 * sin((t - INTRO) * 2.6))

func _play(n: String, vol: float) -> void:
	var st: AudioStream = load("res://assets/audio/sfx/%s.wav" % n) if ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % n) else null
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = vol
	p.bus = "Interface"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

## A key or click: during the intro, jump to its end; after it, leave.
func skip() -> void:
	if _leaving >= 0.0:
		return
	if _t < INTRO:
		_t = INTRO
		_played["land"] = true
		_played["burn"] = true
		return
	_leaving = 0.0
	_play("teleport_whoosh", -12.0)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		skip()
		accept_event()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		skip()
		get_viewport().set_input_as_handled()

## Jump the intro to a time (automated captures).
func seek(t: float) -> void:
	_t = t
	_played["land"] = t > 2.3
	_played["burn"] = t > 0.9
	_apply(0.0)
