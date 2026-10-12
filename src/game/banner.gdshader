shader_type spatial;
// Hanging faction banners: a cloth strip that ripples in the wind (more at the free bottom edge), with a gold trim
// border and a round emblem. UV.y = 0 at the pole.

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 cloth : source_color = vec3(0.16, 0.32, 0.78);
uniform vec3 trim : source_color = vec3(0.95, 0.76, 0.36);
uniform float wind = 1.0;

varying float seed;

void vertex() {
	seed = fract(MODEL_MATRIX[3].x * 3.17 + MODEL_MATRIX[3].z * 1.91);
	float hang = UV.y;
	float w = sin(TIME * 2.3 + UV.y * 5.0 + seed * 12.0) * 0.07 + sin(TIME * 3.7 + UV.x * 4.0 + seed * 6.0) * 0.03;
	VERTEX.z += w * hang * wind;
	VERTEX.x += sin(TIME * 1.3 + seed * 7.0) * 0.03 * hang * wind;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = cloth;
	// cloth weave and shading towards the folds
	col *= 0.9 + 0.1 * sin(uv.y * 160.0) * sin(uv.x * 120.0);
	float border = step(min(min(uv.x, 1.0 - uv.x), 1.0 - uv.y), 0.07);
	// swallowtail: cut a notch at the bottom
	if (uv.y > 0.86 && abs(uv.x - 0.5) < (uv.y - 0.86) * 2.6) {
		discard;
	}
	vec2 e = (uv - vec2(0.5, 0.42)) * vec2(1.0, 0.55);
	float emb = 1.0 - smoothstep(0.17, 0.18, length(e));
	float emb_in = 1.0 - smoothstep(0.11, 0.12, length(e));
	col = mix(col, trim, max(border, emb - emb_in * 0.6));
	ALBEDO = col * (FRONT_FACING ? 1.0 : 0.8);
	ROUGHNESS = 0.85;
	BACKLIGHT = cloth * 0.3;
}
