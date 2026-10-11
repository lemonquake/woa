shader_type spatial;
// Unholy Might's aura: dark flame licking up around the hero. A faint smoky body, bright violet tongues of flame that
// rise and break up towards the top, and a soft silhouette (no hard outline) so it reads as fire, not a glass tube.

render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled, unshaded;

uniform vec4 core : source_color = vec4(0.06, 0.0, 0.1, 1.0);
uniform vec4 rim : source_color = vec4(0.66, 0.24, 1.0, 1.0);
uniform float strength = 1.0;       // fades the whole aura in and out

float hash(vec3 p) { return fract(sin(dot(p, vec3(17.1, 113.3, 71.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = hash(i), n100 = hash(i + vec3(1, 0, 0)), n010 = hash(i + vec3(0, 1, 0)), n110 = hash(i + vec3(1, 1, 0));
	float n001 = hash(i + vec3(0, 0, 1)), n101 = hash(i + vec3(1, 0, 1)), n011 = hash(i + vec3(0, 1, 1)), n111 = hash(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	mat3 rot = mat3(vec3(0.8, 0.6, 0.0), vec3(-0.6, 0.8, 0.0), vec3(0.0, 0.0, 1.0)) * mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.8, 0.6), vec3(0.0, -0.6, 0.8));
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = rot * p * 2.07; a *= 0.5; }
	return v;
}

varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
	// the shell breathes a little
	VERTEX.xz *= 1.0 + 0.04 * sin(TIME * 3.0 + VERTEX.y * 2.0);
}

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float h = clamp((lpos.y + 1.45) / 2.9, 0.0, 1.0);          // 0 feet .. 1 top
	vec3 q = vec3(lpos.x * 2.6, lpos.y * 1.1 - TIME * 2.2, lpos.z * 2.6);
	float n = fbm(q);
	float n2 = fbm(q * 2.3 + vec3(0.0, -TIME * 1.3, 3.1));
	// tongues of flame thin out with height
	float tongue = smoothstep(0.3 + h * 0.32, 0.6 + h * 0.2, n * 0.72 + n2 * 0.48);
	float body = 0.26 * (1.0 - h * 0.8) * (1.0 - smoothstep(0.6, 1.0, fres));
	float edge_soft = 1.0 - smoothstep(0.82, 1.0, fres);
	float alpha = (tongue * (1.0 - h * 0.4) * edge_soft + body) * strength;
	alpha *= smoothstep(0.0, 0.08, h);                      // no hard ring at the feet
	vec3 col = mix(core.rgb, rim.rgb * 2.4, clamp(tongue * (0.6 + n2 * 0.8), 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.9);
}
