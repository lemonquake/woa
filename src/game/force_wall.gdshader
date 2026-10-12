shader_type spatial;
// The rising wall of a shockwave: an open cylinder whose band of force is brightest at its base and frays into
// noise towards the top, fading as it expands. Gives ground blasts real height instead of a flat ring.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.25, 1.0, 1.0);
uniform float progress = 0.0;
uniform float energy = 2.2;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float h = UV.y;                        // 0 top .. 1 bottom on Godot's cylinder
	float up = 1.0 - h;
	float n = noise(vec2(UV.x * 40.0, up * 6.0 - progress * 8.0)) * 0.65 + noise(vec2(UV.x * 90.0, up * 14.0)) * 0.35;
	float body = smoothstep(1.0, 0.15, up + n * 0.45);     // tongues licking up from the base
	float base = smoothstep(0.25, 0.0, up);                 // hot line along the ground
	float a = (body * 0.7 + base * 0.8) * (1.0 - progress) * (1.0 - progress * 0.4);
	ALBEDO = mix(color.rgb, vec3(1.0, 0.92, 1.0), base * 0.6) * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
