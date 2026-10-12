shader_type spatial;
// Ground fissures left by a stomp or a landing: jagged cracks running out from the point of impact, forking once,
// thick near the centre and hairline at their tips, glowing hot at first and cooling to dark, then fading away.

render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec4 glow : source_color = vec4(0.65, 0.25, 1.0, 1.0);
uniform float age = 0.0;            // 0 .. 1 over the decal's life
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f) * 2.0 - 1.0;
}

// distance (in radians times radius, i.e. roughly world-proportional) from point (a, r) to a jagged spoke
float spoke(float a, float r, float base_a, float id) {
	float wobble = vnoise(r * 9.0 + id * 7.0) * 0.16 + vnoise(r * 23.0 + id * 3.0) * 0.06;
	float d = a - (base_a + wobble);
	d = mod(d + 3.14159, 6.28318) - 3.14159;
	return abs(d) * r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float crack = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float base_a = fi / 9.0 * 6.28318 + hash(fi) * 0.5;
		float reach = 0.55 + hash(fi + 20.0) * 0.45;
		float w = mix(0.035, 0.004, clamp(r / reach, 0.0, 1.0));
		float d = spoke(a, r, base_a, fi);
		float line = (1.0 - smoothstep(w * 0.4, w, d)) * step(r, reach);
		// one fork per spoke, starting part way out
		float fork_at = 0.25 + hash(fi + 40.0) * 0.3;
		float fork_a = base_a + (hash(fi + 60.0) - 0.5) * 0.9;
		float wf = mix(0.02, 0.003, clamp((r - fork_at) / (reach * 0.8), 0.0, 1.0));
		float df = spoke(a, r, fork_a + (r - fork_at) * 0.6, fi + 100.0);
		float fork = (1.0 - smoothstep(wf * 0.4, wf, df)) * step(fork_at, r) * step(r, fork_at + reach * 0.6);
		crack = max(crack, max(line, fork));
	}
	float centre = 1.0 - smoothstep(0.0, 0.22, r);
	float scorch = (1.0 - smoothstep(0.1, 0.55, r)) * 0.35;
	float alpha = max(max(crack, centre * 0.85), scorch) * (1.0 - smoothstep(0.55, 1.0, age));
	float hot = (1.0 - smoothstep(0.0, 0.4, age)) * max(crack, centre) * (1.0 - r * 0.8);
	ALBEDO = mix(vec3(0.025, 0.02, 0.03), glow.rgb * 1.8, hot);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
