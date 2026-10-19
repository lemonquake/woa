shader_type spatial;
// The rank emblems' metal and crystal (run 2026-10-19 b): polished metal with a band of light that sweeps across
// the emblem every few seconds, a warm rim, brushed micro detail, and for the top ranks a rainbow film that shifts
// with the view angle (iridescence).

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.9, 0.7, 0.3);
uniform float metallic = 1.0;
uniform float roughness = 0.22;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float sheen = 1.0;                 // strength of the sweeping band of light
uniform float sheen_speed = 0.35;
uniform float iridescence = 0.0;           // 0 none .. 1 full rainbow film
uniform float brushed = 0.4;               // micro scratches in the roughness
uniform float sweep_at = -9.0;           // a fixed place for the band (icons); -9: it moves

varying vec3 obj_pos;
varying vec3 world_pos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 hue(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (t + vec3(0.0, 0.33, 0.67)));
}

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 base = albedo;
	if (iridescence > 0.0) {
		vec3 film = hue(fres * 1.4 + world_pos.x * 0.35 + world_pos.y * 0.25 + TIME * 0.05);
		base = mix(base, base * 0.35 + film * 0.9, iridescence);
	}
	ALBEDO = base;
	METALLIC = metallic;
	// brushed: fine streaks along x in the roughness
	float streak = h2(vec2(floor(obj_pos.y * 260.0), floor(obj_pos.x * 8.0)));
	ROUGHNESS = clamp(roughness + (streak - 0.5) * 0.12 * brushed, 0.03, 1.0);
	SPECULAR = 0.6;
	// the sweep: a soft diagonal band running across the emblem
	float s = world_pos.x * 0.7 + world_pos.y * 0.7;
	float ph = sweep_at > -5.0 ? sweep_at : fract(TIME * sheen_speed) * 5.0 - 2.5;
	float band = exp(-pow((s - ph) * 3.2, 2.0));
	vec3 glint = mix(vec3(1.0, 0.95, 0.85), base, 0.35) * band * sheen * (0.35 + 0.65 * fres + 0.4);
	EMISSION = emission * emission_energy + glint * 0.55 + base * fres * 0.18 * metallic;
}
