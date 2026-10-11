shader_type spatial;
// Worn gear and creature surfaces: the model's (dyeable) base colour, with a tiling detail set (cloth weave,
// worn leather, chainmail, hammered iron, engraved plate) for normal, roughness and tonal variation, plus a soft
// rim so silhouettes read from the top-down camera.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.5);
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 4.0;
uniform float detail_amount = 0.6;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform float normal_depth = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float rim_amount = 0.25;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 d = texture(detail_albedo, uv).rgb;
	float l = dot(d, vec3(0.333));
	// detail varies the tone around the base colour without changing its hue
	vec3 col = base_color * mix(1.0, l * 2.0, detail_amount);
	ALBEDO = col;
	NORMAL_MAP = texture(detail_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = clamp(roughness * mix(1.0, texture(detail_rough, uv).r * 1.6, 0.6), 0.04, 1.0);
	METALLIC = metallic;
	EMISSION = emission_color * emission_energy;
	RIM = rim_amount;
	RIM_TINT = 0.5;
}
