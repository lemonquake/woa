shader_type spatial;
// River water: depth-tinted, refracting, scrolling normals, Fresnel sky reflection and shoreline foam.

render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.36, 0.66, 0.6);
uniform vec3 deep : source_color = vec3(0.07, 0.3, 0.36);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float clarity = 0.55;
uniform float night = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.7 + TIME * 1.3) * 0.015 + cos(wpos.z * 0.9 + TIME * 1.1) * 0.015;
}

void fragment() {
	vec2 flow = vec2(0.035, -0.035);
	vec3 n1 = texture(normal_tex, wpos.xz * 0.11 + flow * TIME).rgb;
	vec3 n2 = texture(normal_tex, wpos.xz * 0.23 - flow.yx * TIME * 1.4).rgb;
	vec3 n = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;

	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	world.xyz /= world.w;
	float depth_diff = clamp(-world.z - (-VERTEX.z), 0.0, 10.0);

	vec2 refr = SCREEN_UV + n.xy * 0.02 * clamp(depth_diff, 0.0, 1.0);
	vec3 below = textureLod(screen_tex, refr, 1.0).rgb;
	float t = clamp(depth_diff / 1.6, 0.0, 1.0);
	vec3 water = mix(shallow, deep, t);
	vec3 col = mix(below * mix(vec3(1.0), shallow * 1.5, 0.5), water, clamp(t * clarity + 0.08, 0.0, 1.0));

	float foam_line = 1.0 - smoothstep(0.0, 0.07, depth_diff);
	float foam_noise = texture(normal_tex, wpos.xz * 0.6 + vec2(TIME * 0.05)).r;
	float foam = foam_line * smoothstep(0.35, 0.65, foam_noise + foam_line * 0.4);
	col = mix(col, foam_color, foam * 0.55);
	col *= mix(vec3(1.0), vec3(0.55, 0.65, 0.95), night * 0.4);

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.4, foam);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = 1.0;
}
