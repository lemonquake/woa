shader_type spatial;
// Every flat-coloured or gear surface of a unit merged into one surface (MeshMerge): the colour and the material's
// numbers travel per vertex, the detail sets (cloth weave, worn leather, chainmail, hammered iron, engraved plate) come
// from texture arrays. Looks like gear.gdshader (detail sets) and the imported flat materials (no detail), drawn in one
// call instead of one per material.
//   CUSTOM0: detail layer (-1 none), uv scale, detail amount, roughness
//   CUSTOM1: metallic, normal depth, rim, emission strength
//   CUSTOM2: base colour (linear)

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2DArray detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_rough : filter_linear_mipmap, repeat_enable;

varying vec4 p0;
varying vec4 p1;
varying vec3 base;

void vertex() {
	p0 = CUSTOM0;
	p1 = CUSTOM1;
	base = CUSTOM2.rgb;
}

void fragment() {
	if (p0.x >= 0.0) {
		vec3 uvw = vec3(UV * p0.y, p0.x);
		vec3 d = texture(detail_albedo, uvw).rgb;
		float l = dot(d, vec3(0.333));
		ALBEDO = base * mix(1.0, l * 2.0, p0.z);
		NORMAL_MAP = texture(detail_normal, uvw).rgb;
		NORMAL_MAP_DEPTH = p1.y;
		ROUGHNESS = clamp(p0.w * mix(1.0, texture(detail_rough, uvw).r * 1.6, 0.6), 0.04, 1.0);
	} else {
		ALBEDO = base;
		ROUGHNESS = p0.w;
	}
	METALLIC = p1.x;
	EMISSION = base * p1.w;
	RIM = p1.z;
	RIM_TINT = 0.5;
}
