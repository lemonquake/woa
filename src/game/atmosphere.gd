class_name Atmosphere
extends Node3D
## Sun, moon, sky and post-processing, blended between day and night as the simulation's clock turns.

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var night := 0.0                           # 0 day .. 1 night (smoothed)
var materials: Array[ShaderMaterial] = []  # shaders with a "night" uniform

const DAY_SUN := Color(1.0, 0.93, 0.8)
const NIGHT_SUN := Color(0.62, 0.72, 1.0)

func build() -> void:
	name = "Atmosphere"
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.55
	sun.light_color = DAY_SUN
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 42.0
	sun.directional_shadow_split_1 = 0.45
	sun.light_angular_distance = 1.2
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.86)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.86)
	sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.15)
	sky_mat.ground_horizon_color = Color(0.68, 0.7, 0.72)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 2.4
	env.ssao_intensity = 3.6
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.6)
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.0
	we.environment = env
	add_child(we)

func update(is_night: bool, dt: float) -> void:
	var goal := 1.0 if is_night else 0.0
	night = move_toward(night, goal, dt / 6.0)
	var n := smoothstep(0.0, 1.0, night)
	sun.light_color = DAY_SUN.lerp(NIGHT_SUN, n)
	sun.light_energy = lerpf(1.55, 1.0, n)
	sun.rotation_degrees.x = lerpf(-52.0, -62.0, n)
	env.ambient_light_energy = lerpf(0.75, 0.62, n)
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.86).lerp(Color(0.16, 0.22, 0.42), n)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.86).lerp(Color(0.34, 0.4, 0.58), n)
	env.fog_light_color = Color(0.72, 0.8, 0.9).lerp(Color(0.3, 0.36, 0.55), n)
	env.adjustment_saturation = lerpf(1.12, 0.96, n)
	for m in materials:
		m.set_shader_parameter("night", n)
