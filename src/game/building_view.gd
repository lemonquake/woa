class_name BuildingView
extends Node3D
## A tower, barracks, Ancient, effigy or fountain: the faction's Blender model with game materials (triplanar stone,
## metal trim, glowing crystal), a light in its crystal, damage darkening and a rubble state once destroyed.

const BUILDING_SHADER := preload("res://src/game/building.gdshader")
const CRYSTAL_SHADER := preload("res://src/game/crystal.gdshader")
const TEX := "res://assets/textures/building/"

## material name -> [texture set, tint, triplanar scale]
const STONE := {
	"WOA_StoneLight": ["ph_castle_brick_02_white", Color(1.0, 0.97, 0.9), 0.75],
	"WOA_StoneWarm": ["ph_medieval_blocks_02", Color(0.98, 0.9, 0.78), 0.6],
	"WOA_StoneDark": ["ph_dark_rock", Color(0.62, 0.55, 0.6), 0.55],
	"WOA_StoneAsh": ["ph_volcanic_rock_tiles", Color(0.7, 0.6, 0.6), 0.65],
	"WOA_RoofBlue": ["ph_clay_roof_tiles_02", Color(0.42, 0.62, 1.0), 1.2],
	"WOA_RoofDark": ["ph_clay_roof_tiles_02", Color(0.45, 0.2, 0.28), 1.2],
	"WOA_Wood": ["ph_weathered_planks", Color(0.85, 0.7, 0.55), 1.0],
	"WOA_Bone": ["ph_rough_block_wall", Color(1.0, 0.95, 0.85), 1.2],
}

static var _mats := {}
static var _scenes := {}

var uid := -1
var unit_kind := 0
var team := 0
var model: Node3D
var light: OmniLight3D
var bar_height := 7.0
var _shaders: Array[ShaderMaterial] = []
var _crystals: Array[ShaderMaterial] = []
var _dead := false
var _rubble: Node3D

static func model_name(def_id: String, team: int) -> String:
	var f := "dawn" if team == 0 else "dusk"
	match def_id:
		"tower1", "tower2", "tower3", "tower4":
			return "tower_" + f
		"melee_rax":
			return "rax_melee_" + f
		"ranged_rax":
			return "rax_ranged_" + f
		"ancient":
			return "ancient_" + f
		"filler":
			return "effigy_" + f
		"fountain":
			return "fountain_" + f
	return "effigy_" + f

func setup(u: SimUnit, terrain: TerrainBuilder) -> void:
	uid = u.id
	unit_kind = u.kind
	team = u.team
	name = "Building_%d" % uid
	var mname := model_name(String(u.def.id), u.team)
	var path := "res://assets/buildings/%s.glb" % mname
	if not _scenes.has(path):
		_scenes[path] = load(path)
	model = (_scenes[path] as PackedScene).instantiate()
	add_child(model)
	var h := terrain.height_at(u.pos)
	# sit on the lowest corner of the footprint so no edge floats over a slope
	for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		h = minf(h, terrain.height_at(u.pos + o * u.hull * 0.8))
	position = View.to3(u.pos, h - 6.0)
	rotation.y = View.yaw(u.facing) + PI
	var s := 1.0
	match u.kind:
		SimConst.Kind.TOWER:
			s = 1.0 + 0.04 * (u.lane_tier - 1)
			bar_height = 8.6 * s
		SimConst.Kind.BARRACKS:
			bar_height = 4.6
		SimConst.Kind.ANCIENT:
			s = 0.78
			bar_height = 7.2
		SimConst.Kind.FILLER:
			bar_height = 4.8
		SimConst.Kind.FOUNTAIN:
			bar_height = 5.5
	model.scale = Vector3.ONE * s
	_materials(position.y)
	var col := Color(1.0, 0.8, 0.45) if team == 0 else Color(1.0, 0.25, 0.25)
	light = OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.6 if u.kind != SimConst.Kind.ANCIENT else 2.4
	light.omni_range = 6.0 if u.kind != SimConst.Kind.ANCIENT else 9.0
	light.position.y = 5.8 * s if u.kind == SimConst.Kind.TOWER else (4.6 * s if u.kind == SimConst.Kind.ANCIENT else 4.0)
	light.shadow_enabled = false
	add_child(light)

func _materials(base_y: float) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var m := _material_for(nm, src)
			if m:
				mi.set_surface_override_material(i, m)
				if m is ShaderMaterial and (m as ShaderMaterial).shader == BUILDING_SHADER:
					(m as ShaderMaterial).set_shader_parameter("base_y", base_y)

## Shared per-material instances would share damage tint; each building gets its own copies (few dozen total).
func _material_for(nm: String, src: Material) -> Material:
	if STONE.has(nm):
		var d: Array = STONE[nm]
		var m := ShaderMaterial.new()
		m.shader = BUILDING_SHADER
		m.set_shader_parameter("albedo_tex", _tex(d[0] + "_albedo.png"))
		m.set_shader_parameter("normal_tex", _tex(d[0] + "_normal.png"))
		m.set_shader_parameter("rough_tex", _tex(d[0] + "_rough.png"))
		m.set_shader_parameter("tint", d[1])
		m.set_shader_parameter("scale", d[2])
		_shaders.append(m)
		return m
	if nm.begins_with("WOA_Crystal") or nm == "WOA_Water":
		var c := ShaderMaterial.new()
		c.shader = CRYSTAL_SHADER
		var col := Color(1.0, 0.8, 0.4)
		if nm == "WOA_CrystalDusk":
			col = Color(1.0, 0.15, 0.2)
		elif nm == "WOA_Water":
			col = Color(0.25, 0.65, 0.85)
		c.set_shader_parameter("color", col)
		c.set_shader_parameter("energy", 2.4 if nm != "WOA_Water" else 0.6)
		_crystals.append(c)
		return c
	if src is BaseMaterial3D:
		var m2 := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		if nm == "WOA_Gold":
			m2.metallic = 1.0
			m2.roughness = 0.28
			m2.albedo_color = Color(1.0, 0.78, 0.36)
		elif nm == "WOA_IronRed":
			m2.metallic = 0.85
			m2.roughness = 0.4
		return m2
	return null

static func _tex(file: String) -> Texture2D:
	if not _mats.has(file):
		_mats[file] = load(TEX + file)
	return _mats[file]

func update_state(u: SimUnit) -> void:
	var frac := u.hp / maxf(1.0, u.max_hp)
	for m in _shaders:
		m.set_shader_parameter("damage", 1.0 - frac)
	if not u.alive and not _dead:
		_dead = true
		_destroy()

func _destroy() -> void:
	# collapse into rubble: sink and flatten the model, kill the light and the crystal glow
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(model.scale.x * 1.15, model.scale.y * 0.22, model.scale.z * 1.15), 1.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model, "rotation:z", 0.12, 1.6)
	if light:
		tw.parallel().tween_property(light, "light_energy", 0.0, 0.8)
	for c in _crystals:
		c.set_shader_parameter("dim", 0.92)
