shader_type spatial;
// A flat expanding ring for stomps, landings and roars: a soft band that thins and fades as it grows, with a little
// angular breakup so it reads as force rather than a perfect circle.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.25, 1.0, 1.0);
uniform float progress = 0.0;       // 0 start .. 1 end
uniform float thickness = 0.18;     // band width as a fraction of the radius
uniform float energy = 2.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float front = mix(0.15, 0.98, sqrt(progress));
	float th = thickness * (1.0 - progress * 0.6);
	float band = smoothstep(front - th, front, r) * (1.0 - smoothstep(front, front + th * 0.35, r));
	float wob = 0.65 + 0.35 * noise(vec2(a * 6.0, progress * 4.0));
	float fill = (1.0 - smoothstep(0.0, front, r)) * 0.18 * (1.0 - progress);
	float alpha = (band * wob + fill) * (1.0 - progress) * (1.0 - smoothstep(0.98, 1.0, r));
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(alpha * color.a, 0.0, 1.0);
}
