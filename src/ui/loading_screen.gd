class_name LoadingScreen
extends CanvasLayer
## The loading screen: a dark aether sky with slow-moving light, the title "Warriors of Aether" with a gold sheen
## sweeping across it, "by Aljay Leodones", and a progress bar with what is loading. It lives on the scene tree's
## root, so it stays up across a scene change and covers the new scene until that scene calls LoadingScreen.close().
##
##   LoadingScreen.open(get_tree())          # show (or keep) the screen
##   LoadingScreen.progress(tree, 0.4, "Raising the mountains")
##   LoadingScreen.close(tree)               # fade out and free

const U = preload("res://src/ui/ui_kit.gd")
const GROUP := "loading_screen"

const SKY := """
shader_type canvas_item;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * n(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	vec2 p = (uv - 0.5) * vec2(1.78, 1.0);
	// deep night gradient
	vec3 col = mix(vec3(0.015, 0.02, 0.04), vec3(0.05, 0.035, 0.07), uv.y);
	// slow aether clouds, warped
	vec2 q = vec2(fbm(p * 2.2 + vec2(0.0, t * 0.02)), fbm(p * 2.2 + vec2(5.2, -t * 0.015)));
	float c = fbm(p * 1.6 + q * 1.4 + vec2(t * 0.01, 0.0));
	vec3 aether = mix(vec3(0.10, 0.22, 0.42), vec3(0.62, 0.42, 0.16), smoothstep(0.35, 0.8, q.x));
	col += aether * smoothstep(0.38, 0.95, c) * 0.55;
	// a warm glow behind the title
	float g = exp(-pow(length(p - vec2(0.0, -0.06)) * 1.9, 2.0));
	col += vec3(0.55, 0.38, 0.14) * g * 0.45;
	// god rays falling from above
	float ang = atan(p.x, p.y + 1.4);
	float rays = pow(0.5 + 0.5 * sin(ang * 26.0 + t * 0.12 + fbm(vec2(ang * 3.0, t * 0.05)) * 3.0), 6.0);
	col += vec3(0.9, 0.75, 0.45) * rays * g * 0.12;
	// mountain silhouettes along the bottom
	float ridge1 = 0.18 + 0.07 * fbm(vec2(uv.x * 3.0, 1.0)) + 0.05 * sin(uv.x * 7.0);
	float ridge2 = 0.10 + 0.06 * fbm(vec2(uv.x * 5.0 + 3.0, 2.0));
	float y = 1.0 - uv.y;
	col = mix(col, vec3(0.03, 0.035, 0.05), smoothstep(ridge1 + 0.004, ridge1 - 0.004, y) * 0.85);
	col = mix(col, vec3(0.012, 0.014, 0.02), smoothstep(ridge2 + 0.004, ridge2 - 0.004, y));
	// vignette
	col *= 1.0 - 0.55 * pow(length(uv - 0.5) * 1.3, 2.2);
	COLOR = vec4(col, 1.0);
}
"""

const SHEEN := """
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// a bright band sweeping left to right every few seconds
	float x = UV.x - UV.y * 0.25;
	float band = fract(t * 0.22) * 1.8 - 0.4;
	float s = exp(-pow((x - band) * 9.0, 2.0));
	c.rgb += vec3(1.0, 0.92, 0.7) * s * 0.75 * c.a;
	COLOR = c;
}
"""

var _sky: ColorRect
var _title: Label
var _by: Label
var _bar_bg: Panel
var _bar: ColorRect
var _status: Label
var _tip: Label
var _t := 0.0
var _shown := 0.0                          # displayed progress (eases towards _target)
var _target := 0.0
var _closing := false
var _root: Control

const TIPS := [
	"Spells, items and attacks work from the first second: the pre-game is fair game for a kill.",
	"Hold right click to keep your hero chasing the cursor.",
	"Press F9 in a match for the Debug panel.",
	"Gale Impact always flies its full range: aim it by direction.",
	"Hold S for a hard stop: no auto-attacks until your next order.",
	"High ground hides you from enemies below it. Ramps lead up.",
	"Trees fall to the Mini-Axe and grow back three minutes later.",
]

static func open(tree: SceneTree) -> LoadingScreen:
	var ex := tree.get_first_node_in_group(GROUP)
	if ex:
		return ex
	var ls := LoadingScreen.new()
	tree.root.add_child(ls)
	return ls

static func progress(tree: SceneTree, value: float, text := "") -> void:
	var ls := tree.get_first_node_in_group(GROUP) as LoadingScreen
	if ls:
		ls.set_progress(value, text)

static func close(tree: SceneTree) -> void:
	var ls := tree.get_first_node_in_group(GROUP) as LoadingScreen
	if ls:
		ls.fade_out()

func _init() -> void:
	layer = 128
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_sky = ColorRect.new()
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	sm.shader = sh
	_sky.material = sm
	_root.add_child(_sky)
	_title = Label.new()
	_title.text = "WARRIORS OF AETHER"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", U.font("title"))
	_title.add_theme_font_size_override("font_size", 96)
	_title.add_theme_color_override("font_color", Color(0.98, 0.83, 0.48))
	_title.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.02))
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_constant_override("shadow_outline_size", 22)
	var tm := ShaderMaterial.new()
	var tsh := Shader.new()
	tsh.code = SHEEN
	tm.shader = tsh
	_title.material = tm
	_root.add_child(_title)
	_by = Label.new()
	_by.text = "by Aljay Leodones"
	_by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_by.add_theme_font_override("font", U.font("title"))
	_by.add_theme_font_size_override("font_size", 30)
	_by.add_theme_color_override("font_color", Color(0.86, 0.84, 0.8))
	_by.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_by.add_theme_constant_override("outline_size", 6)
	_root.add_child(_by)
	_bar_bg = Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.02, 0.02, 0.03, 0.85)
	bs.border_color = U.GOLD_DIM
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(4)
	_bar_bg.add_theme_stylebox_override("panel", bs)
	_root.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color(0.95, 0.74, 0.32)
	_bar_bg.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", U.TEXT_DIM)
	_status.text = "Loading"
	_root.add_child(_status)
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", 17)
	_tip.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	_tip.text = TIPS[randi() % TIPS.size()]
	_root.add_child(_tip)
	_layout()

func set_progress(value: float, text := "") -> void:
	_target = clampf(value, _target, 1.0)
	if text != "":
		_status.text = text

func fade_out() -> void:
	if _closing:
		return
	_closing = true
	_target = 1.0
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

func _layout() -> void:
	var vs := _root.get_viewport_rect().size
	var cy := vs.y * 0.42
	_title.size = Vector2(vs.x, 120)
	_title.position = Vector2(0, cy - 90)
	_by.size = Vector2(vs.x, 40)
	_by.position = Vector2(0, cy + 34)
	var bw := minf(720.0, vs.x - 160.0)
	_bar_bg.size = Vector2(bw, 10)
	_bar_bg.position = Vector2((vs.x - bw) * 0.5, vs.y * 0.78)
	_bar.position = Vector2(1, 1)
	_bar.size = Vector2(maxf(0.0, (bw - 2.0) * _shown), 8)
	_status.size = Vector2(vs.x, 30)
	_status.position = Vector2(0, vs.y * 0.78 + 18)
	_tip.size = Vector2(vs.x, 30)
	_tip.position = Vector2(0, vs.y - 64)

func _process(dt: float) -> void:
	_t += dt
	_shown = lerpf(_shown, _target, 1.0 - exp(-dt * 8.0))
	(_sky.material as ShaderMaterial).set_shader_parameter("t", _t)
	(_title.material as ShaderMaterial).set_shader_parameter("t", _t)
	# the title settles in on first show
	var k := clampf(_t / 1.2, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_title.modulate.a = e
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * lerpf(1.06, 1.0, e)
	_by.modulate.a = clampf((_t - 0.6) / 0.8, 0.0, 1.0)
	_layout()
