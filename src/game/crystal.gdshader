shader_type spatial;
// Glowing faction crystal: faceted, Fresnel-bright edges, a slow pulse and an inner shimmer.

render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float energy = 3.0;
uniform float pulse_speed = 1.4;
uniform float dim = 0.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + lpos.y * 2.0);
	float shimmer = 0.5 + 0.5 * sin(lpos.y * 18.0 + TIME * 3.0) * sin(lpos.x * 14.0 - TIME * 2.0);
	vec3 base = color * (0.55 + 0.45 * shimmer);
	ALBEDO = base * 0.4;
	EMISSION = (base * (0.8 + fres * 2.5) * pulse) * energy * (1.0 - dim);
	ROUGHNESS = 0.08;
	METALLIC = 0.2;
	SPECULAR = 0.9;
	RIM = 0.6;
	RIM_TINT = 0.2;
}
