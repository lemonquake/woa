shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Sludge's skin: pale, sickly grey-green flesh with rotting blotches, bruises, a stitched gash across the gut and
// stitched seams (shoulders, chest, thigh, scalp). The mesh stores each vertex's rest position in its colour
// (tools/blender/sludge.py: r = x / 2 + 0.5, g = y / 2 + 0.5, b = z / 2), so every mark stays put while he animates.
// Sludge faces -y in that space; his gut's front is around y = -0.45.

uniform vec3 pale : source_color = vec3(0.56, 0.52, 0.46);
uniform vec3 sick : source_color = vec3(0.40, 0.45, 0.31);
uniform vec3 rot : source_color = vec3(0.27, 0.29, 0.15);
uniform vec3 bruise : source_color = vec3(0.36, 0.24, 0.32);
uniform vec3 flesh : source_color = vec3(0.42, 0.05, 0.05);
uniform vec3 thread : source_color = vec3(0.10, 0.07, 0.05);
uniform float hit_flash = 0.0;

varying vec3 rp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// A stitched seam along a segment (in the x-z plane of the rest pose, on the side facing `side_y`):
// returns (scar core, stitch thread) masks.
vec2 seam(vec3 p, vec2 a, vec2 b, float side_y, float spacing) {
	if ((p.y - side_y) * sign(side_y) < 0.0) return vec2(0.0);
	vec2 q = p.xz;
	vec2 ab = b - a;
	float t = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0);
	vec2 c = a + ab * t;
	float d = length(q - c);
	float along = t * length(ab);
	float core = 1.0 - smoothstep(0.004, 0.009, d);
	float st = (1.0 - smoothstep(0.0025, 0.005, abs(fract(along / spacing) - 0.5) * spacing)) * (1.0 - smoothstep(0.016, 0.02, d));
	return vec2(core, st);
}

void vertex() {
	rp = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0 - 1.0, COLOR.b * 2.0);
}

void fragment() {
	vec3 p = rp;
	float n1 = fbm(p * 3.2);
	float n2 = fbm(p * 7.5 + 4.0);
	float n3 = fbm(p * 18.0);
	vec3 col = mix(pale, sick, smoothstep(0.35, 0.7, n1));
	// rotting blotches and bruises
	col = mix(col, rot, smoothstep(0.58, 0.74, n2) * 0.75);
	col = mix(col, bruise, smoothstep(0.66, 0.8, fbm(p * 5.0 + 11.0)) * 0.6);
	// darker in the folds under the gut, at the armpits and the back of the neck (cheap cavity from height bands)
	float under_gut = smoothstep(0.98, 0.9, p.z) * smoothstep(0.82, 0.92, p.z) * step(p.y, -0.1);
	col *= 1.0 - 0.25 * under_gut;
	// mottled pores
	col *= 0.9 + 0.2 * n3;
	float rough = 0.48 - 0.12 * n2;
	float wound = 0.0;
	float threads = 0.0;
	// the gash across the gut: an open slit of raw flesh, stitched shut in places
	vec2 wc = vec2(0.10, 1.05);
	vec2 wq = p.xz - wc;
	float ang = 0.35;
	vec2 wr = vec2(cos(ang) * wq.x + sin(ang) * wq.y, -sin(ang) * wq.x + cos(ang) * wq.y);
	float e = length(wr / vec2(0.13, 0.03));
	if (p.y < -0.2) {
		float inside = 1.0 - smoothstep(0.75, 1.0, e);
		float rim = (1.0 - smoothstep(1.0, 1.6, e)) * (1.0 - inside);
		wound = inside;
		col = mix(col, vec3(0.62, 0.32, 0.3), rim * 0.8);              // swollen pink edge
		float cross = (1.0 - smoothstep(0.003, 0.006, abs(fract(wr.x / 0.028) - 0.5) * 0.028)) * (1.0 - smoothstep(1.25, 1.45, e));
		threads = max(threads, cross * step(abs(wr.x), 0.12));
	}
	// stitched seams: chest, right thigh, both shoulders (round the arm), across the scalp
	vec2 s1 = seam(p, vec2(-0.07, 1.30), vec2(-0.03, 1.55), -0.15, 0.03);
	vec2 s2 = seam(p, vec2(-0.20, 0.62), vec2(-0.12, 0.86), -0.05, 0.03);
	float shoulder = (1.0 - smoothstep(0.004, 0.008, abs(abs(p.x) - 0.39))) * step(1.45, p.z);
	float sh_st = (1.0 - smoothstep(0.0025, 0.005, abs(fract(atan(p.y, p.z - 1.59) * 6.0 / 3.14159) - 0.5) * 0.06))
		* (1.0 - smoothstep(0.012, 0.018, abs(abs(p.x) - 0.39))) * step(1.45, p.z);
	vec2 s3 = seam(p, vec2(-0.09, 1.86), vec2(0.06, 1.80), 0.0, 0.025);
	float core = max(max(s1.x, s2.x), max(shoulder, s3.x));
	threads = max(threads, max(max(s1.y, s2.y), max(sh_st, s3.y)));
	col = mix(col, vec3(0.45, 0.16, 0.14), core * 0.85);
	col = mix(col, flesh * (0.6 + 0.6 * n3), wound);
	col = mix(col, thread, threads);
	rough = mix(rough, 0.25, wound);                                // the open wound glistens
	col = mix(col, vec3(1.0, 0.85, 0.8), hit_flash);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	// lumpy skin: perturb the normal with the noise
	vec3 bump = vec3(fbm(p * 22.0 + 1.0), fbm(p * 22.0 + 7.0), fbm(p * 22.0 + 13.0)) - 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz * 0.18);
	// a thin cold rim, as if the flesh were damp
	RIM = 0.25;
	RIM_TINT = 0.4;
}
