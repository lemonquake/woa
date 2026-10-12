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
uniform float paint_bias = 1.6;
// hand-painted masonry: large staggered blocks with dark joints and lit top edges (0 = plain texture, e.g. roofs)
uniform float blocks = 1.0;
uniform float block_w = 0.62;
uniform float block_h = 0.34;
// steps and kerbs: darken vertical faces so treads and risers read apart (0 = off)
uniform float side_dark = 0.0;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 alb = (texture(albedo_tex, wpos.zy * scale, paint_bias) * w.x + texture(albedo_tex, wpos.xz * scale, paint_bias) * w.y
		+ texture(albedo_tex, wpos.xy * scale, paint_bias) * w.z).rgb;
	float r = texture(rough_tex, wpos.zy * scale).r * w.x + texture(rough_tex, wpos.xz * scale).r * w.y
		+ texture(rough_tex, wpos.xy * scale).r * w.z;
	vec3 nx = texture(normal_tex, wpos.zy * scale, 0.8).rgb;
	vec3 ny = texture(normal_tex, wpos.xz * scale, 0.8).rgb;
	vec3 nz = texture(normal_tex, wpos.xy * scale, 0.8).rgb;
	NORMAL_MAP = nx * w.x + ny * w.y + nz * w.z;
	NORMAL_MAP_DEPTH = 0.9;
	float lum = dot(alb, vec3(0.333));
	vec3 col = mix(vec3(lum), alb, 0.55) * tint * 1.25;
	if (blocks > 0.5) {
		// project on the dominant axis so blocks never smear across faces
		vec2 bp;
		if (w.y > max(w.x, w.z)) {
			bp = wpos.xz;
		} else if (w.x > w.z) {
			bp = vec2(wpos.z, wpos.y);
		} else {
			bp = vec2(wpos.x, wpos.y);
		}
		bp /= vec2(block_w, block_h);
		float row = floor(bp.y);
		bp.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(bp);
		vec2 f = fract(bp);
		float ex = min(f.x, 1.0 - f.x) * block_w;
		float ey = min(f.y, 1.0 - f.y) * block_h;
		float joint = 1.0 - smoothstep(0.012, 0.04, min(ex, ey));
		float top = 1.0 - smoothstep(0.0, 0.05, (1.0 - f.y) * block_h);
		float rnd = hash12(cell + floor(wpos.y * 0.01));
		float grain = mix(1.0, lum * 2.0, 0.3);
		vec3 painted = tint * 1.1 * mix(0.8, 1.1, rnd) * grain;
		painted = mix(painted, painted * vec3(1.04, 1.0, 0.92), hash12(cell * 1.7) * 0.5);
		painted *= 1.0 - joint * 0.6;
		painted += top * (1.0 - joint) * 0.12 * tint;
		col = painted;
	}
	float h = wpos.y - base_y;
	col *= mix(0.62, 1.0, smoothstep(0.0, 1.4, h));
	// painted light: warmer tops, cooler shaded sides
	col *= mix(vec3(0.9, 0.93, 1.02), vec3(1.06, 1.02, 0.94), clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	col *= mix(1.0 - side_dark, 1.0 + side_dark * 0.25, smoothstep(0.55, 0.85, wn.y));
	RIM = 0.25;
	RIM_TINT = 0.6;
	col = mix(col, col * vec3(0.45, 0.4, 0.38), damage * 0.6);
	ALBEDO = col;
	ROUGHNESS = clamp(r * 0.9 + 0.1, 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = 0.4;
}
