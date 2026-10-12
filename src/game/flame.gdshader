shader_type spatial;
// Torch and brazier flames: an upright camera-facing quad (keeps its instance scale) with a flickering tongue of
// fire drawn from scrolling value noise. Additive, unlit; the bloom pass gives it its glow.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 core : source_color = vec3(1.0, 0.86, 0.5);
uniform vec3 edge : source_color = vec3(1.0, 0.36, 0.08);
uniform float energy = 2.4;

varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = fract(origin.x * 7.13 + origin.z * 3.71);
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 wp = origin + right * VERTEX.x * sc.x + vec3(0.0, VERTEX.y * sc.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);         // y = 0 at the base of the flame
	float t = TIME * 1.7 + seed * 13.0;
	float x = (uv.x - 0.5) * 2.0;
	float wob = (vnoise(vec2(uv.x * 3.0 + seed * 9.0, uv.y * 3.5 - t * 2.3)) - 0.5) * 0.7 * uv.y;
	float width = mix(0.95, 0.12, pow(uv.y, 0.8));
	float body = 1.0 - smoothstep(width * 0.35, width, abs(x + wob));
	float tongues = vnoise(vec2(uv.x * 5.0, uv.y * 4.0 - t * 3.1));
	float top = 1.0 - smoothstep(0.35, 1.0, uv.y + (tongues - 0.5) * 0.45);
	float a = body * top * smoothstep(0.0, 0.1, uv.y);
	float hot = smoothstep(0.35, 0.95, a) * (1.0 - uv.y * 0.7);
	vec3 col = mix(edge, core, hot);
	float flick = 0.85 + 0.15 * sin(t * 9.0 + seed * 20.0);
	ALBEDO = col * a * energy * flick;
}
