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
// Spirit mode (Azrael, 2026-10-17): a soul of white flame. The texture's light and dark stay (the face keeps its
// features) but in pale blue-white; light glows from within and along the edges and flickers upward; her eyes burn
// red; below `fade_z` she thins into flame.
uniform float spirit = 0.0;
uniform vec3 spirit_col = vec3(0.92, 0.95, 1.0);
uniform vec3 eye_col = vec3(1.0, 0.08, 0.06);
uniform vec2 eye_pos = vec2(0.035, 1.672);            // rest (|x|, height) of the eyes, metres
uniform float fade_z = 0.95;

varying vec2 rest;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

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
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	if (spirit > 0.5) {
		// the texture's shading kept with more contrast (brows, lids, lips, the hollows of the face), cool and pale
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float g = pow(clamp(lum * 1.35, 0.0, 1.0), 1.7);
		vec3 pale = spirit_col * (0.1 + 0.42 * g) + vec3(0.015, 0.02, 0.04);
		// flame rising through her: slow upward noise, stronger toward the edges and the lower body
		float h = rest.y;
		float fl = vnoise(vec2(rest.x * 14.0, h * 7.0 - TIME * 1.3)) * 0.6 + vnoise(vec2(rest.x * 30.0, h * 16.0 - TIME * 2.4)) * 0.4;
		float low = 1.0 - smoothstep(fade_z - 0.4, fade_z, h);
		if (low > 0.0 && fl < low * 0.9 - 0.1) {
			discard;                                  // the legs thin into flame
		}
		// the eyes: red embers in darkened sockets (the back of the head is under her hair and hood)
		float de = length(vec2(abs(rest.x) - eye_pos.x, (h - eye_pos.y) * 1.6));
		float eg = exp(-de * de * 4200.0);
		float socket = exp(-de * de * 700.0);
		pale *= 1.0 - 0.55 * socket;
		ALBEDO = mix(pale, eye_col * 0.6, eg);
		ROUGHNESS = 0.55;
		SPECULAR = 0.25;
		EMISSION = spirit_col * (0.03 + g * 0.05 + rim * 0.45 + fl * rim * 0.3 + low * fl * 0.35) * (1.0 - 0.6 * socket)
			+ eye_col * (eg * 9.0 + socket * 0.15);
		BACKLIGHT = spirit_col * 0.2;
	} else {
		ALBEDO = c;
		ROUGHNESS = roughness_v;
		SPECULAR = 0.35;
		EMISSION = glow_color * rim * glow;
	}
}
