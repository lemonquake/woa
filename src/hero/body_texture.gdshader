shader_type spatial;
// A textured hero body (Azrin's: the owner's female_generic model, tools/blender/azrin_body.py). Same clothing
// cut-outs as hero_skin.gdshader: the mesh supplies its rest pose in UV2 = (x, z) in metres, and whatever the
// worn pieces cover is discarded so skin never pokes through them. (The glTF export flips V, so the height arrives as
// UV2.y = z.)
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float roughness_v = 0.55;
uniform vec3 glow_color = vec3(1.0, 0.45, 0.15);
uniform float glow = 0.0;                     // a warm rim, as if lit from within (fire heroes)
uniform vec2 hide_sleeve = vec2(9.0, 9.0);
uniform vec2 hide_glove_l = vec2(9.0, 9.0);
uniform vec2 hide_glove_r = vec2(9.0, 9.0);
uniform vec2 hide_z1 = vec2(9.0, 9.0);
uniform vec2 hide_z2 = vec2(9.0, 9.0);
uniform vec2 hide_boot_l = vec2(9.0, 9.0);
uniform vec2 hide_boot_r = vec2(9.0, 9.0);

varying vec2 rest;

void vertex() {
	rest = UV2;
}

void fragment() {
	float ax = abs(rest.x);
	vec2 glove = rest.x > 0.0 ? hide_glove_l : hide_glove_r;
	if ((ax > hide_sleeve.x && ax < hide_sleeve.y) || (ax > glove.x && ax < glove.y)) {
		discard;
	}
	if (ax < 0.27) {
		vec2 boot = rest.x > 0.0 ? hide_boot_l : hide_boot_r;
		if ((rest.y > hide_z1.x && rest.y < hide_z1.y) || (rest.y > hide_z2.x && rest.y < hide_z2.y) || (rest.y > boot.x && rest.y < boot.y)) {
			discard;
		}
	}
	vec3 c = texture(albedo_tex, UV).rgb * tint;
	ALBEDO = c;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow_color * rim * glow;
}
