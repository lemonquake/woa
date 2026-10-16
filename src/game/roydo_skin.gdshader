shader_type spatial;
// Roydo's skin (run 2026-10-16): his body is a window onto deep space. Stars and drifting nebulae are drawn in screen
// space with a slow parallax tied to the body, so the sky stays put while he moves through it; a cold rim light keeps
// his silhouette readable from the game camera; faint constellation lines run along the body (object space).
// mode 0: Roydo (blue-violet sky, cyan rim). mode 1: the Anomaly (magenta-red sky, glowing cracks).

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float mode = 0.0;
uniform float star_density = 1.0;
uniform float glow = 1.0;                                 // fades with fog / death (set by the game)
uniform vec4 rim_col : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform vec4 deep_a : source_color = vec4(0.02, 0.02, 0.09, 1.0);
uniform vec4 deep_b : source_color = vec4(0.16, 0.05, 0.32, 1.0);
uniform vec4 neb_a : source_color = vec4(0.25, 0.35, 1.0, 1.0);
uniform vec4 neb_b : source_color = vec4(0.85, 0.25, 0.9, 1.0);

varying vec3 obj_pos;
varying vec3 obj_nrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// a layer of stars: one candidate per cell, twinkling
float stars(vec2 uv, float scale, float thresh, float t) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash12(id);
	if (h < thresh) {
		return 0.0;
	}
	vec2 off = vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5;
	float d = length(f - off * 0.7);
	float tw = 0.65 + 0.35 * sin(t * (1.5 + h * 3.0) + h * 40.0);
	float core = smoothstep(0.09, 0.0, d);
	float halo = smoothstep(0.35, 0.0, d) * 0.18;
	return (core + halo) * tw * (h - thresh) / (1.0 - thresh) * 2.2;
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	float t = TIME;
	// screen-space sky, scaled by depth so it does not swim when the camera zooms
	vec2 suv = SCREEN_UV * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 par = wp.xz * 0.02;
	vec2 sky = suv * 3.0 + par;
	float n1 = fbm(sky * 1.6 + vec2(t * 0.012, -t * 0.008));
	float n2 = fbm(sky * 3.4 - vec2(t * 0.02, t * 0.015) + n1 * 1.5);
	float neb = smoothstep(0.42, 0.9, n2) * smoothstep(0.2, 0.7, n1);
	vec3 deep = mix(deep_a.rgb, deep_b.rgb, smoothstep(0.25, 0.85, n1));
	vec3 nebc = mix(neb_a.rgb, neb_b.rgb, smoothstep(0.35, 0.75, n2));
	if (mode > 0.5) {
		deep = mix(vec3(0.02, 0.0, 0.025), vec3(0.13, 0.01, 0.09), smoothstep(0.25, 0.85, n1));
		nebc = mix(vec3(1.0, 0.18, 0.45), vec3(0.75, 0.2, 1.0), smoothstep(0.35, 0.75, n2));
	}
	float s = stars(sky, 38.0 * star_density, 0.86, t) + stars(sky + 17.3, 90.0 * star_density, 0.93, t * 1.3) * 0.7;
	// constellation lines in object space: thin glowing seams along the limbs
	float lines = 0.0;
	{
		vec3 q = obj_pos * 14.0;
		float a = abs(sin(q.y * 1.3 + sin(q.x * 2.1) * 0.8 + q.z * 0.7));
		lines = smoothstep(0.035, 0.0, a) * (0.5 + 0.5 * sin(t * 1.2 + obj_pos.y * 9.0));
	}
	// the Anomaly: hot cracks that pulse
	float cracks = 0.0;
	if (mode > 0.5) {
		vec2 cq = obj_pos.xy * 9.0 + vec2(obj_pos.z * 4.0, 0.0);
		float c1 = fbm(cq * 1.3);
		cracks = smoothstep(0.03, 0.0, abs(c1 - 0.5)) * (0.7 + 0.3 * sin(t * 4.0 + obj_pos.y * 6.0));
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	vec3 rim = (mode > 0.5 ? vec3(1.0, 0.3, 0.6) * 1.1 : rim_col.rgb * 1.8) * fres;
	ALBEDO = deep * (mode > 0.5 ? 0.4 : 0.55);
	ROUGHNESS = 0.32;
	METALLIC = 0.15;
	SPECULAR = 0.6;
	float neb_k = mode > 0.5 ? 0.32 : 0.9;
	vec3 e = deep * 0.35 + nebc * neb * neb_k + vec3(1.0, 0.97, 0.92) * s * 2.4 + rim;
	e += (mode > 0.5 ? vec3(1.0, 0.35, 0.75) : vec3(0.55, 0.85, 1.0)) * lines * 0.55;
	e += vec3(1.0, 0.4, 0.8) * cracks * 1.4;
	EMISSION = e * glow;
}
