shader_type spatial;
// Leaves and grass: alpha-cut cards with wind sway that grows with height, per-instance colour variation
// (INSTANCE_CUSTOM.r), light shining through (backlight) and a soft top-lit gradient.

render_mode cull_disabled, diffuse_burley, specular_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 tint2 : source_color = vec3(1.0);
uniform float alpha_cut = 0.42;
uniform float wind = 1.0;
uniform float sway_height = 1.0;
uniform float translucency = 0.45;
uniform float night = 0.0;

varying float hvar;
varying float vheight;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0) / sway_height;
	float t = TIME;
	float gust = sin(t * 0.6 + wp.x * 0.05 + wp.z * 0.04) * 0.5 + 0.5;
	float sway = (sin(t * 1.7 + wp.x * 0.45 + wp.z * 0.3) * 0.6 + sin(t * 3.1 + wp.x * 1.3 + wp.z * 0.9) * 0.25) * (0.5 + gust);
	vec3 local_dir = (inverse(MODEL_MATRIX) * vec4(1.0, 0.0, 0.6, 0.0)).xyz;
	VERTEX += local_dir * sway * wind * 0.035 * h * h;
	hvar = INSTANCE_CUSTOM.r;
	vheight = h;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_cut) {
		discard;
	}
	vec3 col = c.rgb * mix(tint, tint2, hvar);
	col *= mix(0.72, 1.12, clamp(vheight, 0.0, 1.0));
	col *= mix(vec3(1.0), vec3(0.6, 0.68, 0.95), night * 0.4);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	BACKLIGHT = col * translucency;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
