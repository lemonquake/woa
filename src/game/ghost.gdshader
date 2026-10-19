// A see-through spirit (Araki's ghosts, run 2026-10-19 c): bright at its outline, faint inside, a slow flicker
// running up the body. Added light, so it glows over the ground and never hides what is behind it.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 col : source_color = vec4(0.45, 1.0, 0.55, 1.0);
uniform float fade = 1.0;

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float flick = 0.8 + 0.2 * sin(TIME * 7.0 - height * 5.0);
	ALBEDO = col.rgb * (0.35 + rim * 1.8) * flick;
	ALPHA = clamp((0.16 + rim * 0.75) * fade, 0.0, 1.0);
}
