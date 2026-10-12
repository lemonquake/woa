shader_type spatial;
// Leaves and grass: alpha-cut cards with wind sway that grows with height, per-instance colour variation
// (INSTANCE_CUSTOM.r), light shining through (backlight) and a soft top-lit gradient.

render_mode cull_disabled, diffuse_burley, specular_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float bleach = 0.0;               // 0..1: grey the leaf texture before tinting (blossom trees)
uniform vec3 tint2 : source_color = vec3(1.0);
uniform float alpha_cut = 0.42;
uniform float wind = 1.0;
uniform float sway_height = 1.0;
uniform float translucency = 0.45;
uniform float night = 0.0;
uniform float near_fade = 8.5;            // foliage closer to the camera than this dithers away (foreground canopies)

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

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_cut) {
		discard;
	}
	float keep = smoothstep(near_fade - 3.0, near_fade, length(VERTEX));
	if (keep < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 leaf = mix(c.rgb, vec3(dot(c.rgb, vec3(0.3, 0.55, 0.15))), bleach);
	vec3 col = leaf * mix(tint, tint2, hvar) * vec3(0.92, 0.94, 0.96);
	col *= mix(0.55, 1.12, clamp(vheight, 0.0, 1.0));
	// darker towards the inside of a canopy: cards facing away from the sky are shaded
	col *= mix(0.68, 1.0, clamp(NORMAL.y * 0.5 + 0.6, 0.0, 1.0));
	col *= mix(vec3(1.0), vec3(0.78, 0.84, 1.0), night * 0.3);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	BACKLIGHT = col * translucency;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
