shader_type spatial;
// Warriors of Aether terrain: nine texture layers in two arrays (albedo + roughness in alpha, normal), blended by a
// baked splat map (R road, G forest floor, B base paving, A Dusk blight), terrain slope (cliffs, triplanar) and
// height (river bed). Height-aware blending keeps transitions crisp; a macro colour pass breaks up tiling.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D splat_tex : filter_linear, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float map_half = 81.92;
uniform float river_height = 0.55;
uniform float level_height = 1.28;
uniform vec3 grass_tint : source_color = vec3(0.74, 0.93, 0.62);
uniform vec3 dusk_tint : source_color = vec3(0.92, 0.78, 0.74);
uniform float saturation = 1.1;
uniform float night = 0.0;
// painterly look: sample albedo a couple of mips down so photographic grain becomes broad painted tone
uniform float paint_bias = 1.8;
uniform float normal_bias = 1.0;

varying vec3 wpos;
varying vec3 wnorm;
varying float mtn;                         // 0..1 mountain (vertex colour red, from the terrain builder)

const int L_GRASS = 0;
const int L_GRASS2 = 1;
const int L_ROAD = 2;
const int L_FOREST = 3;
const int L_CLIFF = 4;
const int L_PLAZA = 5;
const int L_DUSK = 6;
const int L_RIVER = 7;
const int L_DUSK_PLAZA = 8;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mtn = COLOR.r;
}

vec4 tex(int layer, vec2 uv) {
	return texture(albedo_tex, vec3(uv, float(layer)), paint_bias);
}

vec3 nrm(int layer, vec2 uv) {
	return texture(normal_tex, vec3(uv, float(layer)), normal_bias).rgb;
}

// Tiling with a rotated second sample at another scale, blended by a macro noise, so repeats do not show.
vec4 tex2(int layer, vec2 uv, float m) {
	vec4 a = tex(layer, uv);
	vec2 r = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.17);
	vec4 b = tex(layer, r);
	return mix(a, b, smoothstep(0.35, 0.65, m));
}

vec3 sat(vec3 c, float s) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(l), c, s);
}

void fragment() {
	vec2 suv = vec2(wpos.x + map_half, wpos.z + map_half) / (2.0 * map_half);
	vec4 sp = texture(splat_tex, suv);
	vec4 macro = texture(macro_tex, wpos.xz * 0.013);
	vec4 macro2 = texture(macro_tex, wpos.xz * 0.0031 + vec2(0.4, 0.7));
	float m = macro.r;

	vec2 uv_g = wpos.xz / 3.2;
	vec2 uv_r = wpos.xz / 2.6;
	vec2 uv_p = wpos.xz / 2.4;

	// base ground: two grasses, Dusk blight, forest floor
	vec4 g1 = tex2(L_GRASS, uv_g, m);
	vec4 g2 = tex2(L_GRASS2, uv_g * 0.7, macro.g);
	float g2w = smoothstep(0.45, 0.75, macro2.r);
	vec4 col = mix(g1, g2, g2w * 0.6);
	col.rgb *= grass_tint;
	vec4 forest = tex2(L_FOREST, uv_g * 0.9, m);
	col = mix(col, forest, smoothstep(0.15, 0.85, sp.g + (macro.b - 0.5) * 0.4));
	vec4 dusk = tex2(L_DUSK, uv_g * 0.8, m);
	dusk.rgb *= dusk_tint;
	float dusk_w = smoothstep(0.2, 0.8, sp.a + (macro2.g - 0.5) * 0.35);
	col = mix(col, dusk, dusk_w);

	// roads: height-blended so stones poke through grass at the edges; large worn patches of packed dirt
	vec4 road = tex2(L_ROAD, uv_r, m);
	vec4 dirt = tex2(L_FOREST, uv_r * 0.8, macro.b);
	road = mix(road, dirt * vec4(1.05, 0.95, 0.85, 1.0), smoothstep(0.45, 0.75, macro2.r) * 0.55);
	road.rgb *= mix(0.82, 1.08, macro.g);
	float rh = road.r * 0.5 + sp.r;
	float road_w = smoothstep(0.55, 0.85, rh + (macro.g - 0.5) * 0.45 + (texture(macro_tex, wpos.xz * 0.09).r - 0.5) * 0.35);
	// a ragged fringe of packed dirt and leaf litter between grass and gravel
	float fringe = smoothstep(0.28, 0.5, rh + (macro.b - 0.5) * 0.5) * (1.0 - road_w);
	col = mix(col, forest * vec4(0.95, 0.9, 0.82, 1.0), fringe * 0.75);
	// worn paving: patches of old cobbles surface through the dirt across the lane
	vec4 cobble = tex(L_PLAZA, uv_p * 1.15);
	float paved = smoothstep(0.52, 0.68, texture(macro_tex, wpos.xz * 0.045).g + cobble.r * 0.2) * smoothstep(0.75, 0.95, road_w);
	road = mix(road, cobble * vec4(0.92, 0.9, 0.86, 1.0), paved * 0.85);
	// grass creeps into the road in ragged tongues near the edges
	float creep = smoothstep(0.6, 0.78, texture(macro_tex, wpos.xz * 0.12).b) * (1.0 - smoothstep(0.7, 1.0, rh));
	road_w *= 1.0 - creep * 0.85;
	col = mix(col, road, road_w);

	// base paving (Dawn bright stone, Dusk mossy cobbles)
	vec4 plaza = tex(L_PLAZA, uv_p);
	vec4 dplaza = tex(L_DUSK_PLAZA, uv_p);
	vec4 pl = mix(plaza, dplaza, step(0.0, wpos.x - wpos.z));
	float pedge = (macro.b - 0.5) * 0.5 + (texture(macro_tex, wpos.xz * 0.11).g - 0.5) * 0.45;
	float plaza_w = smoothstep(0.45, 0.8, sp.b + plaza.r * 0.25 + pedge);
	// grass and moss creep between the stones near the paving's edge; worn, darker flagstones in patches
	float pcreep = smoothstep(0.55, 0.75, texture(macro_tex, wpos.xz * 0.16 + vec2(0.3, 0.1)).r) * (1.0 - smoothstep(0.75, 1.0, sp.b));
	plaza_w *= 1.0 - pcreep * 0.8;
	pl.rgb *= mix(0.86, 1.06, texture(macro_tex, wpos.xz * 0.06).b);
	col = mix(col, pl, plaza_w);

	// river bed by height
	float h = wpos.y;
	vec4 riv = tex2(L_RIVER, uv_g * 0.9, m);
	float riv_w = 1.0 - smoothstep(river_height - 0.15, river_height + 0.35, h + (riv.r - 0.5) * 0.3);
	col = mix(col, riv, riv_w);
	// wet, darkened bank just above the waterline
	float wet = 1.0 - smoothstep(river_height - 0.02, river_height + 0.3, h + (macro.r - 0.5) * 0.12);
	wet *= smoothstep(river_height - 0.25, river_height - 0.02, h);
	col.rgb *= 1.0 - wet * 0.45;
	col.a = mix(col.a, 0.25, wet);

	// cliffs: triplanar on steep slopes
	vec3 an = abs(wnorm);
	float slope = 1.0 - an.y;
	vec3 bw = pow(an, vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 cx = tex(L_CLIFF, wpos.zy / 4.0);
	vec4 cy = tex(L_CLIFF, wpos.xz / 4.0);
	vec4 cz = tex(L_CLIFF, wpos.xy / 4.0);
	vec4 cliff = cx * bw.x + cy * bw.y + cz * bw.z;
	cliff.rgb *= mix(vec3(0.95, 0.9, 0.82), vec3(0.75, 0.68, 0.72), dusk_w);
	float cliff_w = smoothstep(0.3, 0.55, slope + (cliff.r - 0.5) * 0.25);
	col = mix(col, cliff, cliff_w);

	// mountains: bare rock on the slopes, mossy turf and scree on ledges, cooler and darker towards the peaks,
	// with broad strata bands so the faces do not read as one smear
	vec4 cxl = tex(L_CLIFF, wpos.zy / 9.0);
	vec4 czl = tex(L_CLIFF, wpos.xy / 9.0);
	vec4 rock = mix(cliff, cxl * bw.x + cy * bw.y + czl * bw.z, 0.45);
	float strata = 0.5 + 0.5 * sin(wpos.y * 1.7 + macro.g * 5.0);
	rock.rgb *= mix(0.84, 1.06, strata);
	// greyer, cooler stone than the sandy cliff texture (the range reads as granite, not sandstone)
	rock.rgb = mix(rock.rgb, vec3(dot(rock.rgb, vec3(0.33))), 0.55) * vec3(0.92, 0.95, 1.0);
	rock.rgb *= mix(vec3(0.9, 0.86, 0.8), vec3(0.6, 0.63, 0.7), smoothstep(4.0, 24.0, h));
	rock.rgb *= mix(vec3(1.0), vec3(0.82, 0.74, 0.76), dusk_w);
	vec4 turf = mix(g2, forest, 0.35) * vec4(0.74, 0.84, 0.62, 1.0);
	float ledge = smoothstep(0.78, 0.93, an.y + (macro.r - 0.5) * 0.25) * (1.0 - smoothstep(12.0, 26.0, h + macro.b * 4.0));
	vec4 mcol = mix(rock, turf, ledge);
	float mw = smoothstep(0.02, 0.5, mtn);
	col = mix(col, mcol, mw);
	cliff_w = max(cliff_w, mw * (1.0 - ledge));

	// normal: planar layers only (cliffs keep the geometric normal plus a little detail)
	vec3 n_ground = nrm(L_GRASS, uv_g);
	n_ground = mix(n_ground, nrm(L_ROAD, uv_r), road_w);
	n_ground = mix(n_ground, nrm(L_PLAZA, uv_p), plaza_w);
	n_ground = mix(n_ground, nrm(L_RIVER, uv_g * 0.9), riv_w);
	n_ground = mix(n_ground, vec3(0.5, 0.5, 1.0), cliff_w * 0.6);

	// macro shading: large soft colour patches like painted terrain (warm sunlit / cool shaded areas)
	col.rgb *= mix(0.82, 1.12, macro2.b);
	col.rgb = mix(col.rgb, col.rgb * vec3(1.08, 1.02, 0.9), smoothstep(0.55, 0.8, macro2.g) * 0.5);
	col.rgb = mix(col.rgb, col.rgb * vec3(0.88, 0.95, 1.06), smoothstep(0.45, 0.2, macro2.g) * 0.5);
	col.rgb = sat(col.rgb, saturation);
	col.rgb *= mix(vec3(1.0), vec3(0.78, 0.84, 1.0), night * 0.3);

	ALBEDO = col.rgb;
	ROUGHNESS = clamp(col.a * 0.9 + 0.12, 0.35, 1.0);
	NORMAL_MAP = n_ground;
	NORMAL_MAP_DEPTH = 0.7;
	SPECULAR = 0.35;
	// contact darkening where grass meets road and around the forest floor
	float edge = road_w * (1.0 - road_w) * 4.0;
	col.rgb *= 1.0 - edge * 0.22;
	AO = mix(1.0, 0.7, sp.g * (1.0 - road_w));
	AO_LIGHT_AFFECT = 0.4;
}
