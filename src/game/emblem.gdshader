shader_type spatial;
// The faction emblem inlaid in each base's great plaza: a gold sunburst on sea-green stone for the Dawn, a red
// crescent and eye on black stone for the Dusk. Drawn in UV space with anti-aliased edges; inlay is metallic.

render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 stone_tint : source_color = vec3(0.42, 0.6, 0.58);
uniform vec3 inlay : source_color = vec3(0.95, 0.74, 0.34);
uniform int motif = 0;                     // 0 sun (Dawn), 1 moon (Dusk)

float aa(float d) { return clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 st = texture(stone_tex, UV * 1.6, 1.5).rgb;
	float l = dot(st, vec3(0.333));
	vec3 base = stone_tint * mix(0.7, 1.2, l);
	// worn edge and a darker groove ring around the field
	base *= mix(0.78, 1.0, smoothstep(1.0, 0.8, max(abs(p.x), abs(p.y))));
	float m = 0.0;
	float ring = abs(r - 0.86) - 0.035;
	m = max(m, aa(ring));
	if (motif == 0) {
		float disc = r - 0.27;
		m = max(m, aa(disc));
		float k = fract(a / 6.28318 * 12.0);
		float tri = 1.0 - abs(k * 2.0 - 1.0);
		float ray = r - (0.3 + 0.42 * pow(tri, 2.2));
		m = max(m, aa(ray) * step(0.31, r));
		float k2 = fract(a / 6.28318 * 12.0 + 0.5);
		float tri2 = 1.0 - abs(k2 * 2.0 - 1.0);
		float ray2 = r - (0.3 + 0.24 * pow(tri2, 3.0));
		m = max(m, aa(ray2) * step(0.31, r));
		// a hollow in the sun's face
		m *= 1.0 - aa(r - 0.17) * (1.0 - aa(r - 0.1));
	} else {
		float outer = length(p - vec2(-0.06, 0.0)) - 0.52;
		float cut = length(p - vec2(0.16, 0.08)) - 0.44;
		m = max(m, aa(outer) * (1.0 - aa(cut)));
		// an eye in the crescent's hollow
		vec2 e = (p - vec2(0.2, 0.06)) * vec2(1.0, 2.2);
		m = max(m, aa(length(e) - 0.16) * (1.0 - aa(length(p - vec2(0.2, 0.06)) - 0.045)));
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398 + 0.3927;
			m = max(m, aa(length(p - vec2(cos(ang), sin(ang)) * 0.7) - 0.045));
		}
	}
	vec3 gold = inlay * mix(0.75, 1.15, l);
	ALBEDO = mix(base, gold, m);
	METALLIC = m * 0.75;
	ROUGHNESS = mix(0.85, 0.35, m);
	// grooves: a thin dark line where the inlay meets the stone
	float groove = m * (1.0 - m) * 4.0;
	ALBEDO *= 1.0 - groove * 0.5;
}
