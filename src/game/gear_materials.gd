class_name GearMaterials
extends RefCounted
## Turns the flat beyond-heroes materials (BH_<Kind>__<palette>) on worn pieces and creatures into textured game
## materials: the imported colour (or a dye) stays the base, a detail set by kind adds the surface.

const SHADER := preload("res://src/game/gear.gdshader")
const TEX := "res://assets/textures/gear/"

## kind -> [detail set, uv scale, detail amount, roughness, metallic, normal depth]
const KINDS := {
	"BH_Cloth": ["storm_wool", 5.0, 0.45, 0.92, 0.0, 0.9],
	"BH_Cloth_Primary": ["storm_wool", 5.0, 0.45, 0.92, 0.0, 0.9],
	"BH_Cloth_Secondary": ["cloth", 6.0, 0.4, 0.9, 0.0, 0.8],
	"BH_Leather": ["leather_worn", 3.0, 0.55, 0.62, 0.0, 1.1],
	"BH_Fur": ["storm_wool", 8.0, 0.7, 0.95, 0.0, 1.4],
	"BH_Mail": ["chainmail", 7.0, 0.65, 0.4, 0.9, 1.4],
	"BH_Steel": ["engraved_plate", 1.6, 0.35, 0.32, 0.95, 0.8],
	"BH_DarkSteel": ["forsaken_iron", 2.0, 0.45, 0.42, 0.9, 1.0],
	"BH_Gold": ["metal_iron", 2.5, 0.3, 0.28, 1.0, 0.6],
	"BH_Bronze": ["metal_iron", 2.5, 0.35, 0.34, 1.0, 0.7],
	"BH_Rust": ["forsaken_iron", 2.0, 0.6, 0.7, 0.4, 1.0],
	"BH_Bone": ["leather_worn", 2.0, 0.35, 0.6, 0.0, 0.6],
	"BH_Horn": ["leather_worn", 2.0, 0.35, 0.5, 0.0, 0.6],
	"BH_Wood": ["leather_worn", 2.0, 0.5, 0.75, 0.0, 0.8],
	"BH_Stone": ["forsaken_iron", 1.5, 0.6, 0.85, 0.0, 1.2],
}

static var _cache := {}
static var _tex := {}

static func _t(file: String) -> Texture2D:
	if not _tex.has(file):
		_tex[file] = load(TEX + file) if ResourceLoader.exists(TEX + file) else null
	return _tex[file]

## A game material for an imported one, or null to keep the import (skin, emissive, unknown kinds).
static func for_material(src: BaseMaterial3D, color_override = null) -> Material:
	if src == null:
		return null
	var nm := src.resource_name.get_slice(".", 0)
	var base := nm.get_slice("__", 0)
	if not KINDS.has(base):
		return null
	var col: Color = color_override if color_override != null else src.albedo_color
	var key := "%s|%s" % [base, col.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var k: Array = KINDS[base]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("base_color", Color(col.r, col.g, col.b))
	m.set_shader_parameter("detail_albedo", _t(k[0] + "_albedo.png"))
	m.set_shader_parameter("detail_normal", _t(k[0] + "_normal.png"))
	m.set_shader_parameter("detail_rough", _t(k[0] + "_rough.png"))
	m.set_shader_parameter("uv_scale", k[1])
	m.set_shader_parameter("detail_amount", k[2])
	m.set_shader_parameter("roughness", k[3])
	m.set_shader_parameter("metallic", k[4])
	m.set_shader_parameter("normal_depth", k[5])
	_cache[key] = m
	return m

## Apply to every surface of a MeshInstance3D (keeping any surface override's colour as the dye).
static func apply(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var cur := mi.get_surface_override_material(i) as BaseMaterial3D
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if cur == null:
			cur = src
		if cur == null:
			continue
		# keep the imported name (overrides made by dyeing are duplicates and keep it too)
		var m := for_material(cur)
		if m:
			mi.set_surface_override_material(i, m)
