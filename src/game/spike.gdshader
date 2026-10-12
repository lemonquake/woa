shader_type spatial;
// Dark Stomp's stone spikes, painted rather than photographed: a slate base glowing violet where it tore out of the
// ground, lilac stone through the middle and a pale, almost bone-white tip; facets catch the light crisply.

render_mode diffuse_toon, specular_toon, cull_back;

uniform vec3 base_col : source_color = vec3(0.16, 0.12, 0.2);
uniform vec3 mid_col : source_color = vec3(0.52, 0.46, 0.62);
uniform vec3 tip_col : source_color = vec3(0.9, 0.86, 0.96);
uniform vec3 glow : source_color = vec3(0.6, 0.28, 1.0);

varying float h;

void vertex() {
	h = VERTEX.y;                          // the shard mesh runs 0 (root) .. 1 (tip)
}

void fragment() {
	vec3 c = mix(base_col, mid_col, smoothstep(0.0, 0.45, h));
	c = mix(c, tip_col, smoothstep(0.55, 1.0, h));
	// painterly banding across the facets
	c *= 0.9 + 0.1 * sin(h * 23.0 + NORMAL.x * 4.0);
	ALBEDO = c;
	ROUGHNESS = 0.5;
	SPECULAR = 0.35;
	RIM = 0.5;
	RIM_TINT = 0.6;
	EMISSION = glow * (1.0 - smoothstep(0.0, 0.22, h)) * 1.6;
}
