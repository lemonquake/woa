class_name HeroAppearance
extends RefCounted
## The customisable hero body (the player's own model from beyond-heroes): applies a look (HeroLook: skin shader,
## 20 shape keys incl. the female figure, hair, beard, head / hand / foot size, height) and dresses it in any of the
## 143 worn pieces (assets/characters/hero/wear) by slot, each dyeable (cloth, trim, leather, metal, gold).
##
## Outfit: {slot: wear id}. Slots: inner_garment, armor, leggings, helm, gloves, boots, accessory_1..4.
## Dyes: {slot: {"cloth": "hex", "leather": "hex", "metal": "hex", "trim": "hex", "gold": "hex"}}.

const SKIN_SHADER := preload("res://src/hero/hero_skin.gdshader")
const HAIR_SHADER := preload("res://src/hero/hero_hair.gdshader")
const SKIN_TEX := "res://assets/characters/hero/hero_skin.png"
const MASK_TEX := "res://assets/characters/hero/hero_masks.png"
const WEAR_DIR := "res://assets/characters/hero/wear/"
const SIZED_BONES := {"head": ["head"], "hands": ["hand.L", "hand.R"], "feet": ["foot.L", "foot.R"]}
const NO_HIDE := Vector2(9.0, 9.0)
const SLOTS := ["inner_garment", "armor", "leggings", "helm", "gloves", "boots", "accessory_1", "accessory_2",
	"accessory_3", "accessory_4"]
const SKIRT_HIP := 0.80
const SKIRT_KNEE := 0.45

var root: Node3D                           # the instanced hero.glb
var skeleton: Skeleton3D
var body: MeshInstance3D
var skin: ShaderMaterial
var look := {}
var outfit := {}
var dyes := {}
var base_scale := 1.0
var _head: BoneAttachment3D
var _hair: MeshInstance3D
var _beard: MeshInstance3D
var _hair_path := ""
var _beard_path := ""
var _hair_mat: ShaderMaterial
var _beard_mat: ShaderMaterial
var _wear: Array[MeshInstance3D] = []
var _wear_sig := "-"
var _hide_hair := false

static var _catalog := {}
static var _manifest := {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(WEAR_DIR + "catalog.json"))
		_catalog = d if d is Dictionary else {}
		var m = JSON.parse_string(FileAccess.get_file_as_string(WEAR_DIR + "manifest.json"))
		_manifest = (m as Dictionary).get("items", {}) if m is Dictionary else {}
	return _catalog

## Wear ids that fit a slot ("gloves", "boots", "accessory" for the accessory slots), sorted by name.
static func pieces_for(slot: String) -> Array:
	var want := "accessory" if slot.begins_with("accessory") else slot
	var out: Array = []
	for id in catalog():
		var e: Dictionary = _catalog[id]
		if e.slot == want and not bool(e.get("base", false)):
			out.append(id)
	out.sort_custom(func(a, b): return String(_catalog[a].name) < String(_catalog[b].name))
	return out

static func piece_name(id: String) -> String:
	return String(catalog().get(id, {}).get("name", id))

func _init(model_root: Node3D) -> void:
	root = model_root
	skeleton = root.find_children("*", "Skeleton3D", true, false)[0] if not root.find_children("*", "Skeleton3D", true, false).is_empty() else null
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) \
				and mi.mesh.surface_get_material(0).resource_name.begins_with("BH_HeroSkin"):
			body = mi
			break
	if body == null:
		return
	skin = ShaderMaterial.new()
	skin.shader = SKIN_SHADER
	skin.set_shader_parameter(&"skin_tex", load(SKIN_TEX))
	skin.set_shader_parameter(&"mask_tex", load(MASK_TEX))
	body.set_surface_override_material(0, skin)
	body.extra_cull_margin = 1.2
	base_scale = root.scale.x
	apply({})

func ok() -> bool:
	return body != null

# ---- Look ------------------------------------------------------------------------------------------------------------

func apply(src: Dictionary) -> void:
	if body == null:
		return
	look = HeroLook.sanitize(src)
	var l := look
	skin.set_shader_parameter(&"skin_color", HeroLook.rgb(l, "skin"))
	skin.set_shader_parameter(&"underwear_color", HeroLook.rgb(l, "underwear"))
	skin.set_shader_parameter(&"top_wrap", smoothstep(0.25, 0.6, float(l["female"])))
	skin.set_shader_parameter(&"pattern", HeroLook.choice_index("pattern", l["pattern"]))
	skin.set_shader_parameter(&"pattern_color", HeroLook.rgb(l, "pattern_color"))
	skin.set_shader_parameter(&"pattern_amount", l["pattern_amount"])
	skin.set_shader_parameter(&"pattern_scale", l["pattern_scale"])
	skin.set_shader_parameter(&"hair_color", HeroLook.rgb(l, "hair_color"))
	skin.set_shader_parameter(&"scalp_shade", HeroLook.scalp_shade(l))
	skin.set_shader_parameter(&"stubble", l["stubble"])
	skin.set_shader_parameter(&"lip_color", HeroLook.rgb(l, "lip_color"))
	skin.set_shader_parameter(&"lip_amount", l["lip_amount"])
	skin.set_shader_parameter(&"eye_style", HeroLook.choice_index("eye", l["eye"]))
	skin.set_shader_parameter(&"eye_color", HeroLook.rgb(l, "eye_color"))
	for k in ["eye_size", "eye_spacing", "eye_height", "eye_tilt", "eye_glow", "brow_thick", "brow_tilt", "brow_height"]:
		skin.set_shader_parameter(StringName(k), l[k])
	skin.set_shader_parameter(&"brow_style", HeroLook.choice_index("brow", l["brow"]))
	skin.set_shader_parameter(&"brow_color", HeroLook.rgb(l, "brow_color"))
	skin.set_shader_parameter(&"marking", HeroLook.choice_index("marking", l["marking"]))
	skin.set_shader_parameter(&"marking_color", HeroLook.rgb(l, "marking_color"))
	for k in HeroLook.SHAPE_KEYS:
		var i := body.find_blend_shape_by_name(StringName(k))
		if i >= 0:
			body.set_blend_shape_value(i, l[k])
	_apply_body_keys()
	_apply_sizes()
	_set_hair(false, HeroLook.hair_model(l), HeroLook.rgb(l, "hair_color"), l["hair_length"])
	_set_hair(true, HeroLook.beard_model(l), HeroLook.rgb(l, "beard_color"), l["beard_length"])
	_refresh_hair_visibility()

func _apply_body_keys() -> void:
	for m in _wear:
		if not is_instance_valid(m):
			continue
		for k in HeroLook.BODY_KEYS:
			var i := m.find_blend_shape_by_name(StringName(k))
			if i >= 0:
				m.set_blend_shape_value(i, look[k])

func _apply_sizes() -> void:
	if skeleton == null:
		return
	for key in SIZED_BONES:
		var s := float(look[key])
		for bn in SIZED_BONES[key]:
			var i := skeleton.find_bone(bn)
			if i >= 0:
				skeleton.set_bone_pose_scale(i, Vector3.ONE * s)
		if key == "hands":
			for bn in ["weapon.L", "weapon.R"]:
				var wi := skeleton.find_bone(bn)
				if wi >= 0:
					skeleton.set_bone_pose_scale(wi, Vector3.ONE / s)
	root.scale = Vector3.ONE * base_scale * float(look["height"])

func _head_attachment() -> BoneAttachment3D:
	if _head == null or not is_instance_valid(_head):
		_head = BoneAttachment3D.new()
		_head.name = "HeroHead"
		_head.bone_name = "head"
		skeleton.add_child(_head)
	return _head

func _set_hair(beard: bool, path: String, col: Vector3, length: float) -> void:
	var cur := _beard if beard else _hair
	var cur_path := _beard_path if beard else _hair_path
	if path != cur_path:
		if cur and is_instance_valid(cur):
			cur.queue_free()
		cur = null
		if path != "" and skeleton:
			var src := _hair_src(path)
			if not src.is_empty():
				cur = MeshInstance3D.new()
				cur.mesh = src[0]
				var at := _head_attachment()
				at.add_child(cur)
				var rest := skeleton.get_bone_global_rest(skeleton.find_bone("head"))
				cur.transform = rest.affine_inverse() * (src[1] as Transform3D)
				cur.name = "Beard" if beard else "Hair"
				cur.extra_cull_margin = 2.0
				var mat := ShaderMaterial.new()
				mat.shader = HAIR_SHADER
				cur.material_override = mat
				if beard:
					_beard_mat = mat
				else:
					_hair_mat = mat
		if beard:
			_beard = cur
			_beard_path = path
		else:
			_hair = cur
			_hair_path = path
	if cur and is_instance_valid(cur):
		var mat := _beard_mat if beard else _hair_mat
		mat.set_shader_parameter(&"hair_color", col)
		var i := cur.find_blend_shape_by_name(&"length")
		if i >= 0:
			cur.set_blend_shape_value(i, length)

static var _hair_cache := {}

static func _hair_src(path: String) -> Array:
	if _hair_cache.has(path):
		return _hair_cache[path]
	var out: Array = []
	var ps := load(path) as PackedScene
	if ps:
		var scene: Node = ps.instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			found.append(scene)
		if not found.is_empty():
			out = [(found[0] as MeshInstance3D).mesh, _model_xf(found[0], scene)]
		scene.free()
	_hair_cache[path] = out
	return out

static func _model_xf(n: Node3D, scene_root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c and c != scene_root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	if scene_root is Node3D and n != scene_root:
		t = (scene_root as Node3D).transform * t
	return t

func _refresh_hair_visibility() -> void:
	if _hair and is_instance_valid(_hair):
		_hair.visible = not _hide_hair

# ---- Outfit -----------------------------------------------------------------------------------------------------------

## Dress in an outfit {slot: wear id}; `p_dyes` {slot: {cloth, trim, leather, metal, gold}}. Rebuilds only on change.
func dress(p_outfit: Dictionary, p_dyes := {}) -> void:
	if body == null or skeleton == null:
		return
	outfit = p_outfit.duplicate()
	dyes = p_dyes.duplicate(true)
	var plan := _plan()
	var sig: String = plan.sig + "|" + str(dyes.hash())
	if sig == _wear_sig:
		return
	_wear_sig = sig
	for m in _wear:
		if is_instance_valid(m):
			m.get_parent().remove_child(m)
			m.queue_free()
	_wear.clear()
	for piece in plan.pieces:
		for mi in _build(piece):
			_wear.append(mi)
	_apply_body_keys()
	var hide: Dictionary = plan.hide
	for k in ["sleeve", "glove_l", "glove_r", "z1", "z2", "boot_l", "boot_r"]:
		skin.set_shader_parameter(StringName("hide_" + k), hide.get(k, NO_HIDE))
	_hide_hair = bool(plan.hide_hair) and bool(look.get("show_helm", true))
	_refresh_hair_visibility()

static func _range(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and (v as Array).size() == 2 else NO_HIDE

func _plan() -> Dictionary:
	catalog()
	var pieces: Array = []
	var sig: Array[String] = []
	var spans: Array = []
	var hide := {}
	var hide_hair := false
	var clothed := false
	var legged := false
	var legs_piece := {}
	var skirt := 9.0
	var booted := {"L": false, "R": false}
	for slot in SLOTS:
		var id := String(outfit.get(slot, ""))
		if id == "" or not ResourceLoader.exists(WEAR_DIR + id + ".glb"):
			continue
		if slot == "helm" and not bool(look.get("show_helm", true)):
			continue
		var info: Dictionary = _manifest.get(id, {})
		var sides: bool = bool(info.get("sides", false))
		var side_list: Array = ["L", "R"] if sides and (slot == "gloves" or slot == "boots") else [""]
		if sides and slot.begins_with("accessory"):
			side_list = ["L" if slot in ["accessory_1", "accessory_3"] else "R"]
		for side in side_list:
			var piece := {"id": id, "side": side, "slot": slot}
			pieces.append(piece)
			sig.append("%s:%s%s" % [slot, id, side])
			_cover(info, side, spans, hide)
			if slot == "boots":
				booted[side] = true
		if slot == "armor" or slot == "inner_garment":
			clothed = true
			skirt = minf(skirt, float(info.get("skirt", 9.0)))
		elif slot == "leggings":
			legged = true
			legs_piece = pieces[-1]
		elif slot == "helm" and String(info.get("hair", "hide")) == "hide":
			hide_hair = true
	if not legs_piece.is_empty():
		var skip: Array[String] = []
		if clothed:
			skip.append("waist")
		if skirt < SKIRT_HIP:
			skip.append("hip")
		if skirt < SKIRT_KNEE:
			skip.append("knee")
		for sd in ["L", "R"]:
			if booted[sd]:
				skip.append("ankle_" + sd)
		legs_piece["skip"] = skip
	if clothed and not legged:
		pieces.append({"id": "_breeches", "side": "", "slot": "leggings"})
		_cover(_manifest.get("_breeches", {}), "", spans, hide)
		sig.append("breeches")
	if clothed or legged:
		for side in ["L", "R"]:
			if not booted[side]:
				pieces.append({"id": "_shoes", "side": side, "slot": "boots"})
				_cover(_manifest.get("_shoes", {}), side, spans, hide)
				sig.append("shoe" + side)
	spans.sort_custom(func(a, b): return a.x < b.x)
	var merged: Array = []
	for s: Vector2 in spans:
		if not merged.is_empty() and s.x <= (merged[-1] as Vector2).y + 0.005:
			merged[-1] = Vector2((merged[-1] as Vector2).x, maxf((merged[-1] as Vector2).y, s.y))
		else:
			merged.append(s)
	merged.sort_custom(func(a, b): return a.y - a.x > b.y - b.x)
	if merged.size() > 0:
		hide["z1"] = merged[0]
	if merged.size() > 1:
		hide["z2"] = merged[1]
	return {"sig": ",".join(sig), "pieces": pieces, "hide": hide, "hide_hair": hide_hair}

static func _cover(info: Dictionary, side: String, spans: Array, hide: Dictionary) -> void:
	var h: Dictionary = info.get("hide", {})
	for k in ["z", "z2"]:
		var r := _range(h.get(k))
		if r != NO_HIDE:
			spans.append(r)
	var sl := _range(h.get("sleeve"))
	if sl != NO_HIDE:
		var cur: Vector2 = hide.get("sleeve", NO_HIDE)
		hide["sleeve"] = sl if cur == NO_HIDE else Vector2(minf(cur.x, sl.x), maxf(cur.y, sl.y))
	for pair in [["glove", "glove_"], ["boot", "boot_"]]:
		var r := _range(h.get(pair[0]))
		if r != NO_HIDE and side != "":
			var key: String = pair[1] + side.to_lower()
			var cur: Vector2 = hide.get(key, NO_HIDE)
			hide[key] = r if cur == NO_HIDE else Vector2(minf(cur.x, r.x), maxf(cur.y, r.y))

static var _parts := {}

static func _part_list(id: String) -> Array:
	if _parts.has(id):
		return _parts[id]
	var out: Array = []
	var ps := load(WEAR_DIR + id + ".glb") as PackedScene
	if ps:
		var scene: Node = ps.instantiate()
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			out.append([String(mi.name), mi.mesh, mi.skin])
		scene.free()
	_parts[id] = out
	return out

func _build(piece: Dictionary) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var side := String(piece.get("side", ""))
	var skip: Array = piece.get("skip", [])
	var dye: Dictionary = dyes.get(String(piece.slot), {})
	for part in _part_list(String(piece.id)):
		var nm: String = part[0]
		if side != "" and (nm.ends_with("_L") or nm.ends_with("_R")) and not nm.ends_with("_" + side):
			continue
		if skip.any(func(t): return nm == "wear_" + String(t)):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = part[1]
		mi.skin = part[2]
		mi.name = "Wear_%s%s" % [piece.id, ("_" + side) if side != "" else ""]
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.extra_cull_margin = 0.6
		if not dye.is_empty():
			_dye(mi, dye)
		GearMaterials.apply(mi)
		out.append(mi)
	return out

## Which dye a worn surface takes: cloth (dark cloth: trim), leather, metal, gold, or none.
static func dye_key(material_name: String) -> String:
	var base := material_name.get_slice("__", 0)
	var pal := material_name.get_slice("__", 1) if "__" in material_name else ""
	if base.begins_with("BH_Cloth"):
		return "trim" if pal in ["it_hw_black", "it_hw_navy"] else "cloth"
	if base == "BH_Leather":
		return "leather"
	if base in ["BH_Steel", "BH_DarkSteel", "BH_Mail"]:
		return "metal"
	if base in ["BH_Gold", "BH_Bronze"]:
		return "gold"
	return ""

static var _dyed := {}

static func _dye(mi: MeshInstance3D, dye: Dictionary) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var key := dye_key(src.resource_name.get_slice(".", 0))
		if key == "" or not dye.has(key):
			continue
		var col := Color(String(dye[key]))
		var ck := "%d|%s|%s" % [src.get_instance_id(), key, col.to_html(false)]
		if not _dyed.has(ck):
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = src.albedo_color * col if key == "metal" or key == "gold" else col
			_dyed[ck] = m
		mi.set_surface_override_material(i, _dyed[ck])
