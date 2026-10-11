class_name ScreenFx
extends ColorRect
## Full-screen feedback for your hero: the world drains of colour while you are dead, and a red pulse creeps in from
## the screen edges below a quarter of your health. Hidden (no cost) whenever neither applies.

const CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float desat = 0.0;
uniform float hurt = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g) * vec3(0.86, 0.9, 1.0) * 0.85, desat);
	vec2 p = SCREEN_UV * 2.0 - 1.0;
	float v = smoothstep(0.5, 1.35, length(p * vec2(1.0, 0.8)));
	c = mix(c, vec3(0.5, 0.02, 0.02), v * hurt * (0.65 + 0.35 * pulse));
	COLOR = vec4(c, 1.0);
}
"""

var game: Node
var _mat: ShaderMaterial
var _desat := 0.0
var _hurt := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	visible = false

func _process(dt: float) -> void:
	var h: SimUnit = game.world.get_unit(game.player_hero_id) if game and game.world else null
	if h == null:
		return
	var want_desat := 0.0 if h.alive else 1.0
	var frac := h.hp / maxf(1.0, h.max_hp)
	var want_hurt := clampf((0.25 - frac) / 0.25, 0.0, 1.0) if h.alive else 0.0
	_desat = move_toward(_desat, want_desat, dt / 0.6)
	_hurt = move_toward(_hurt, want_hurt, dt / 0.4)
	visible = _desat > 0.001 or _hurt > 0.001
	if visible:
		_mat.set_shader_parameter("desat", _desat)
		_mat.set_shader_parameter("hurt", _hurt)
		_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * (4.0 + _hurt * 4.0)))
