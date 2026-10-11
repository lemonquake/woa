shader_type spatial;
// Fog of war as a screen-space pass: rebuild each pixel's world position from depth, look up the team's smoothed
// visibility grid, and darken what the team cannot currently see (alpha-blended over everything, so water and
// effects drawn earlier stay visible).

render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D fog_prev : filter_linear, repeat_disable;
uniform float blend = 1.0;
uniform float map_half = 81.92;
uniform float strength = 0.72;
uniform vec3 fog_color : source_color = vec3(0.06, 0.08, 0.14);

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 uv = (world.xz + map_half) / (2.0 * map_half);
	// texture rows run with sim y (north = -z)
	uv.y = 1.0 - uv.y;
	// the grids hold 0 / 1 bytes: scale to 0..1 (filtering keeps the edges soft), then cross-fade from the last grid
	float now_v = clamp(texture(fog_tex, uv).r * 255.0, 0.0, 1.0);
	float prev_v = clamp(texture(fog_prev, uv).r * 255.0, 0.0, 1.0);
	float vis = mix(prev_v, now_v, blend);
	if (d <= 0.0) {
		discard;
	}
	ALBEDO = fog_color;
	ALPHA = (1.0 - vis) * strength;
}
