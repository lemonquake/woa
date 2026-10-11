shader_type spatial;
// Building stone: triplanar (the Blender models carry no UVs), tinted by the model's base colour, with a soft
// ambient-occlusion darkening towards the ground and a damage tint as the building loses health.

render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float scale = 0.9;
uniform float damage = 0.0;
uniform float metallic = 0.0;
uniform float base_y = 0.0;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 alb = (texture(albedo_tex, wpos.zy * scale) * w.x + texture(albedo_tex, wpos.xz * scale) * w.y
		+ texture(albedo_tex, wpos.xy * scale) * w.z).rgb;
	float r = texture(rough_tex, wpos.zy * scale).r * w.x + texture(rough_tex, wpos.xz * scale).r * w.y
		+ texture(rough_tex, wpos.xy * scale).r * w.z;
	vec3 nx = texture(normal_tex, wpos.zy * scale).rgb;
	vec3 ny = texture(normal_tex, wpos.xz * scale).rgb;
	vec3 nz = texture(normal_tex, wpos.xy * scale).rgb;
	NORMAL_MAP = nx * w.x + ny * w.y + nz * w.z;
	NORMAL_MAP_DEPTH = 1.2;
	float lum = dot(alb, vec3(0.333));
	vec3 col = mix(vec3(lum), alb, 0.55) * tint * 1.25;
	float h = wpos.y - base_y;
	col *= mix(0.62, 1.0, smoothstep(0.0, 1.4, h));
	col = mix(col, col * vec3(0.45, 0.4, 0.38), damage * 0.6);
	ALBEDO = col;
	ROUGHNESS = clamp(r * 0.9 + 0.1, 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = 0.4;
}
