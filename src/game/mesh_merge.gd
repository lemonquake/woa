class_name MeshMerge
extends RefCounted
## Fewer draw calls and skin updates for units. A hero is a body plus a dozen worn pieces, each its own skinned mesh
## with its own skin and up to four materials; a creep is one mesh of 7-16 flat-coloured surfaces. Every surface is a
## draw in the depth pass, the colour pass and both shadow cascades, and every skin is a skeleton the engine updates
## each frame: ten heroes cost ~6.7 ms of a 19.5 ms teamfight frame on the test PC.
##
## merge() puts a unit's skinned meshes into ONE skinned mesh with ONE skin (bind poses unified by bone), bakes the
## shape keys the look set (they never change in a match) and joins every gear or flat-coloured surface into ONE
## surface drawn with gear_merged.gdshader (colour and material numbers per vertex, detail sets from texture arrays).
## Surfaces with any other material (the hero skin shader, textured materials) stay surfaces of their own in the same
## mesh. Levels of detail are kept (each source surface's levels joined level by level). Anything it cannot read
## exactly (mixed primitive types, a piece whose bind poses disagree, a moved mesh node) is left as it was.
##
## Creeps of one kind and team share one merged mesh (cached); a hero's is its own.

const SHADER := preload("res://src/game/gear_merged.gdshader")
## GearMaterials' detail sets, in texture array order.
const SETS := ["storm_wool", "cloth", "leather_worn", "chainmail", "engraved_plate", "forsaken_iron", "metal_iron"]
const ARRAY_SIZE := 512                     # detail texels per side in the arrays (the sets tile 2-8 times a piece)

static var _material: ShaderMaterial
static var _cache := {}                     # signature -> [ArrayMesh, Skin]
static var enabled := true
static var debug := OS.get_cmdline_user_args().has("--merge_debug")

## The one material for merged surfaces.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("detail_albedo", _array("albedo"))
		_material.set_shader_parameter("detail_normal", _array("normal"))
		_material.set_shader_parameter("detail_rough", _array("rough"))
	return _material

static func _array(kind: String) -> Texture2DArray:
	var imgs: Array[Image] = []
	for s in SETS:
		var tex := load(GearMaterials.TEX + s + "_" + kind + ".png") as Texture2D
		var img: Image = tex.get_image() if tex else null
		if img == null:
			img = Image.create(ARRAY_SIZE, ARRAY_SIZE, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 1.0) if kind == "normal" else Color(0.5, 0.5, 0.5))
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		if kind == "normal" and img.get_format() in [Image.FORMAT_RG8, Image.FORMAT_LA8]:
			img = _normal_rgb(img)
		img.convert(Image.FORMAT_RGBA8)
		img.resize(ARRAY_SIZE, ARRAY_SIZE, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		imgs.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr

## A two-channel normal map (as the importer stores them) with its third channel rebuilt.
static func _normal_rgb(img: Image) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var two := img.get_format() == Image.FORMAT_LA8
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var nx := c.r * 2.0 - 1.0
			var ny := (c.a if two else c.g) * 2.0 - 1.0
			var nz := sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny))
			out.set_pixel(x, y, Color(c.r, c.a if two else c.g, nz * 0.5 + 0.5))
	return out

## The numbers of a surface material that can join a merged surface, or {} (keep the surface as it is).
static func params(m: Material) -> Dictionary:
	if m is ShaderMaterial and (m as ShaderMaterial).shader == GearMaterials.SHADER:
		var sm := m as ShaderMaterial
		var tex = sm.get_shader_parameter("detail_albedo")
		var layer := -1
		if tex is Texture2D:
			var f := String((tex as Texture2D).resource_path.get_file())
			for i in SETS.size():
				if f.begins_with(SETS[i] + "_"):
					layer = i
		if layer < 0:
			return {}
		var col: Color = _c(sm.get_shader_parameter("base_color"), Color(0.5, 0.5, 0.5))
		var ec: Color = _c(sm.get_shader_parameter("emission_color"), Color.BLACK)
		var ee := _f(sm.get_shader_parameter("emission_energy"), 0.0)
		return {"col": col, "layer": layer, "uv": _f(sm.get_shader_parameter("uv_scale"), 4.0),
			"amt": _f(sm.get_shader_parameter("detail_amount"), 0.6), "rough": _f(sm.get_shader_parameter("roughness"), 0.8),
			"metal": _f(sm.get_shader_parameter("metallic"), 0.0), "depth": _f(sm.get_shader_parameter("normal_depth"), 1.0),
			"rim": _f(sm.get_shader_parameter("rim_amount"), 0.25), "emis": _strength(col, ec, ee)}
	if m is StandardMaterial3D:
		var b := m as StandardMaterial3D
		if b.albedo_texture != null or b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or b.normal_enabled \
				or b.blend_mode != BaseMaterial3D.BLEND_MODE_MIX or b.emission_texture != null \
				or b.next_pass != null or b.uv1_triplanar or b.metallic_texture != null or b.roughness_texture != null:
			return {}
		var e := _strength(b.albedo_color, b.emission, b.emission_energy_multiplier) if b.emission_enabled else 0.0
		return {"col": b.albedo_color, "layer": -1, "uv": 1.0, "amt": 0.0, "rough": b.roughness, "metal": b.metallic,
			"depth": 0.0, "rim": b.rim if b.rim_enabled else 0.0, "emis": e, "vcol": b.vertex_color_use_as_albedo,
			"vsrgb": b.vertex_color_is_srgb}
	return {}

static func _c(v, d: Color) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return d

static func _f(v, d: float) -> float:
	return float(v) if v != null else d

## Emission as a strength of the base colour (the merged shader glows in the surface's own colour).
static func _strength(col: Color, ec: Color, energy: float) -> float:
	var lc := maxf(0.02, col.srgb_to_linear().get_luminance())
	return ec.srgb_to_linear().get_luminance() * energy / lc

# ---- Merging --------------------------------------------------------------------------------------------------------

## Merge the skinned meshes under `skeleton` (only those directly under it with a skin). Returns the new mesh
## instance, or null when nothing was merged. cache_key: share the result between units built the same way ("" = no).
## rigid: [[MeshInstance3D, bone index, transform in the bone's space]] for meshes riding a bone (a creep's weapons):
## they join the mesh fully weighted to that bone.
static func merge(skeleton: Skeleton3D, cache_key := "", rigid: Array = []) -> MeshInstance3D:
	if not enabled or skeleton == null:
		return null
	var srcs: Array[MeshInstance3D] = []
	for c in skeleton.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null or not mi.visible or not (mi.mesh is ArrayMesh):
			continue
		if not mi.transform.is_equal_approx(Transform3D.IDENTITY):
			continue
		srcs.append(mi)
	if srcs.is_empty():
		if debug:
			print("MERGE none under ", skeleton.get_path(), " children ", skeleton.get_children().map(func(c): return "%s:%s skin=%s xf=%s" % [c.name, c.get_class(), str(c.get("skin") != null), str(c.get("transform").is_equal_approx(Transform3D.IDENTITY)) if c is Node3D else "-"]))
		return null
	var mesh: ArrayMesh = null
	var skin: Skin = null
	var key := ""
	if cache_key != "":
		key = cache_key + _sig(srcs)
		for r in rigid:
			var rm: MeshInstance3D = r[0]
			key += "#%d@%d:%s" % [rm.mesh.get_rid().get_id(), int(r[1]), str(r[2])]
			for si in rm.mesh.get_surface_count():
				key += ":" + _mat_sig(rm.get_active_material(si))
		if _cache.has(key):
			mesh = _cache[key][0]
			skin = _cache[key][1]
			var picked: Array[MeshInstance3D] = []
			for i in _cache[key][2]:
				picked.append(srcs[i])
			srcs = picked
	if mesh == null:
		var t0 := Time.get_ticks_usec()
		var built := _build(skeleton, srcs, rigid)
		if debug:
			print("MERGE built %s in %.1f ms" % [key if key != "" else skeleton.get_parent().name, (Time.get_ticks_usec() - t0) / 1000.0])
		if built.is_empty():
			if debug:
				print("MERGE build failed for ", cache_key, " ", srcs.map(func(m): return m.name))
			return null
		mesh = built.mesh
		skin = built.skin
		var idx: Array = []
		for mi in built.used:
			idx.append(srcs.find(mi))
		srcs = built.used
		# only fully merged meshes are shared (one surface, one material): a kept surface's material belongs to its unit
		if key != "" and mesh.get_surface_count() == 1:
			_cache[key] = [mesh, skin, idx]
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = mesh
	out.skin = skin
	var margin := 0.0
	for mi in srcs:
		margin = maxf(margin, mi.extra_cull_margin)
	out.extra_cull_margin = margin
	skeleton.add_child(out)
	out.skeleton = NodePath("..")
	for mi in srcs:
		_retire(mi)
	for r in rigid:
		_retire(r[0])
	return out

## A merged-away piece lets go of its mesh, skin and materials first, then goes at the end of the frame (freed with
## its materials still on it, the renderer met materials already gone: "material is null").
static func _retire(mi: MeshInstance3D) -> void:
	mi.visible = false
	mi.material_overlay = null
	mi.material_override = null
	mi.skin = null
	mi.mesh = null
	mi.queue_free()

## A material by what it looks like (units duplicate tinted materials per unit; equal looks must share one merge).
static func _mat_sig(m: Material) -> String:
	if m == null:
		return "0"
	var p := params(m)
	if p.is_empty():
		if m is BaseMaterial3D:
			# a per-unit copy of the same look (scenes can copy their materials per instance) shares the merge
			var b := m as BaseMaterial3D
			return "%s/%s/%s/%s/%d/%d/%s" % [b.resource_name, b.albedo_color.to_html(), b.emission.to_html(), str(b.emission_enabled),
				b.transparency, b.shading_mode, str(b.albedo_texture.get_rid().get_id()) if b.albedo_texture else "-"]
		return str(m.get_instance_id())
	return "%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [(p.col as Color).to_html(), int(p.layer), float(p.uv), float(p.amt),
		float(p.rough), float(p.metal), float(p.depth), float(p.rim), float(p.emis)]

## What makes two units' merged meshes the same: the meshes, their materials and shape key weights.
static func _sig(srcs: Array[MeshInstance3D]) -> String:
	var parts: Array = []
	for mi in srcs:
		var p := str(mi.mesh.get_rid().get_id())
		for s in mi.mesh.get_surface_count():
			p += ":" + _mat_sig(mi.get_active_material(s))
		for b in (mi.mesh as ArrayMesh).get_blend_shape_count():
			p += ";%.3f" % mi.get_blend_shape_value(b)
		parts.append(p)
	return "|".join(parts)

static func _build(skeleton: Skeleton3D, srcs: Array[MeshInstance3D], rigid: Array = []) -> Dictionary:
	# one bind per bone: the first source that binds a bone sets its pose; a source whose poses disagree by more than a
	# hair is left out
	var binds := {}                        # bone index -> [new bind index, pose]
	var skin := Skin.new()
	var used: Array[MeshInstance3D] = []
	var remaps: Array = []
	for mi in srcs:
		var sk := mi.skin
		var remap := PackedInt32Array()
		var ok := true
		var adds: Array = []
		for i in sk.get_bind_count():
			var bone := sk.get_bind_bone(i)
			if bone < 0:
				bone = skeleton.find_bone(sk.get_bind_name(i))
			if bone < 0:
				ok = false
				break
			var pose := sk.get_bind_pose(i)
			if binds.has(bone):
				if not (binds[bone][1] as Transform3D).is_equal_approx(pose):
					var a: Transform3D = binds[bone][1]
					if a.origin.distance_to(pose.origin) > 0.002 or not a.basis.is_equal_approx(pose.basis):
						ok = false
						break
				remap.append(int(binds[bone][0]))
			else:
				var found := -1
				for ad in adds:
					if int(ad[0]) == bone:
						found = int(ad[1])
				if found < 0:
					found = binds.size() + adds.size()
					adds.append([bone, found, pose])
				remap.append(found)
		if not ok:
			continue
		for ad in adds:
			binds[int(ad[0])] = [int(ad[1]), ad[2]]
		used.append(mi)
		remaps.append(remap)
	if used.is_empty():
		return {}
	var order: Array = []
	order.resize(binds.size())
	for bone in binds:
		order[int(binds[bone][0])] = [bone, binds[bone][1]]
	# a rigid part rides its bone: a bind with no offset, its vertices moved into the bone's space
	var rigid_bind: Array = []
	for r in rigid:
		rigid_bind.append(order.size())
		order.append([int(r[1]), Transform3D.IDENTITY])
	for e in order:
		skin.add_bind(int(e[0]), e[1])
	# 8 bone weights anywhere: every surface gets 8
	var eight := false
	for mi in used:
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
				eight = true
	var nb := 8 if eight else 4
	var merged := _Acc.new()
	var keep: Array = []                   # [arrays, lods, material, flags]
	for k in used.size():
		var mi := used[k]
		var mesh := mi.mesh as ArrayMesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return {}
			var arrays := mesh.surface_get_arrays(s)
			_bake_shapes(mi, mesh, s, arrays)
			_remap_bones(arrays, remaps[k], nb)
			var lods := _lods(mesh, s)
			var mat := mi.get_active_material(s)
			var p := params(mat)
			if p.is_empty():
				keep.append([arrays, lods, _own(mat)])
			else:
				merged.add(arrays, lods, p, nb)
	for k in rigid.size():
		var rmi: MeshInstance3D = rigid[k][0]
		var rmesh := rmi.mesh
		for s in rmesh.get_surface_count():
			if rmesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return {}
			var arrays := rmesh.surface_get_arrays(s)
			_place(arrays, rigid[k][2], int(rigid_bind[k]), nb)
			var lods := _lods(rmesh as ArrayMesh, s) if rmesh is ArrayMesh else {}
			var mat := rmi.get_active_material(s)
			var p := params(mat)
			if p.is_empty():
				keep.append([arrays, lods, _own(mat)])
			else:
				merged.add(arrays, lods, p, nb)
	var out := ArrayMesh.new()
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight else 0
	if merged.count > 0:
		var cf := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.arrays(), [], merged.lods(), flags | cf)
		out.surface_set_material(out.get_surface_count() - 1, material())
	for kp in keep:
		var arr: Array = kp[0]
		_strip(arr)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], kp[1], flags)
		out.surface_set_material(out.get_surface_count() - 1, kp[2])
	return {"mesh": out, "skin": skin, "used": used}

## A rigid part's vertices into its bone's space, all weight on its bind.
static func _place(arrays: Array, xf: Transform3D, bind: int, nb: int) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vc := v.size()
	var nbasis := xf.basis.inverse().transposed()
	for i in vc:
		v[i] = xf * v[i]
	arrays[Mesh.ARRAY_VERTEX] = v
	var n = arrays[Mesh.ARRAY_NORMAL]
	if n != null:
		var nn: PackedVector3Array = n
		for i in nn.size():
			nn[i] = (nbasis * nn[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = nn
	var t = arrays[Mesh.ARRAY_TANGENT]
	if t != null:
		var tt: PackedFloat32Array = t
		for i in tt.size() / 4:
			var tv := (xf.basis * Vector3(tt[i * 4], tt[i * 4 + 1], tt[i * 4 + 2])).normalized()
			tt[i * 4] = tv.x
			tt[i * 4 + 1] = tv.y
			tt[i * 4 + 2] = tv.z
		arrays[Mesh.ARRAY_TANGENT] = tt
	var b := PackedInt32Array()
	b.resize(vc * nb)
	var w := PackedFloat32Array()
	w.resize(vc * nb)
	for i in vc:
		b[i * nb] = bind
		w[i * nb] = 1.0
	arrays[Mesh.ARRAY_BONES] = b
	arrays[Mesh.ARRAY_WEIGHTS] = w

## A kept surface's own copy of its material: a shared mesh must not hold a unit's material (units' scenes make
## per-instance materials; holding the first unit's caused "material is null" errors once it was gone).
static func _own(mat: Material) -> Material:
	return mat.duplicate() if mat != null else null

## Drop arrays a kept surface's material will not read differently (the merge rebuilds them consistently).
static func _strip(arr: Array) -> void:
	for i in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arr[i] = null

## The shape keys' current weights, baked into the vertices (relative shape keys: base + sum of weight x offset).
static func _bake_shapes(mi: MeshInstance3D, mesh: ArrayMesh, s: int, arrays: Array) -> void:
	var nshape := mesh.get_blend_shape_count()
	if nshape == 0:
		return
	var shapes := mesh.surface_get_blend_shape_arrays(s)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n = arrays[Mesh.ARRAY_NORMAL]
	var t = arrays[Mesh.ARRAY_TANGENT]
	var vc := v.size()
	var v2 := v.duplicate()
	var n2 = n.duplicate() if n != null else null
	var t2 = t.duplicate() if t != null else null
	for b in mini(nshape, shapes.size()):
		var wgt := mi.get_blend_shape_value(b)
		if absf(wgt) < 0.0001:
			continue
		var sh: Array = shapes[b]
		var sv: PackedVector3Array = sh[Mesh.ARRAY_VERTEX]
		if sv.size() != vc:
			continue
		var sn = sh[Mesh.ARRAY_NORMAL]
		var st = sh[Mesh.ARRAY_TANGENT]
		var delta := _is_delta(v, sv)
		for i in vc:
			v2[i] += (sv[i] if delta else sv[i] - v[i]) * wgt
		if n2 != null and sn != null and (sn as PackedVector3Array).size() == vc:
			for i in vc:
				n2[i] += (sn[i] if delta else sn[i] - n[i]) * wgt
		if t2 != null and st != null and (st as PackedFloat32Array).size() == vc * 4:
			for i in vc:
				for c in 3:
					t2[i * 4 + c] += (st[i * 4 + c] if delta else st[i * 4 + c] - t[i * 4 + c]) * wgt
	if n2 != null:
		for i in vc:
			n2[i] = (n2[i] as Vector3).normalized()
	arrays[Mesh.ARRAY_VERTEX] = v2
	if n2 != null:
		arrays[Mesh.ARRAY_NORMAL] = n2
	if t2 != null:
		arrays[Mesh.ARRAY_TANGENT] = t2

## Whether a shape key's vertices are offsets from the base (small) rather than whole positions.
static func _is_delta(base: PackedVector3Array, shape: PackedVector3Array) -> bool:
	var sb := 0.0
	var ss := 0.0
	var step := maxi(1, base.size() / 64)
	for i in range(0, base.size(), step):
		sb += base[i].length()
		ss += shape[i].length()
	return ss < sb * 0.25

## Bind indices of one source -> the merged skin's, padded to `nb` bones per vertex.
static func _remap_bones(arrays: Array, remap: PackedInt32Array, nb: int) -> void:
	var bones = arrays[Mesh.ARRAY_BONES]
	var wts = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or wts == null:
		return
	var vc := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := (bones as PackedInt32Array).size() / maxi(1, vc)
	var nbones := PackedInt32Array()
	nbones.resize(vc * nb)
	var nw := PackedFloat32Array()
	nw.resize(vc * nb)
	for i in vc:
		for j in per:
			var b: int = bones[i * per + j]
			nbones[i * nb + j] = remap[b] if b < remap.size() else 0
			nw[i * nb + j] = wts[i * per + j]
	arrays[Mesh.ARRAY_BONES] = nbones
	arrays[Mesh.ARRAY_WEIGHTS] = nw

## A surface's levels of detail as add_surface_from_arrays wants them ({edge length: indices}).
static func _lods(mesh: ArrayMesh, s: int) -> Dictionary:
	var out := {}
	var sd := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
	var lods: Array = sd.get("lods", [])
	var vc := int(sd.get("vertex_count", 0))
	for l in lods:
		var data: PackedByteArray = l.get("index_data", PackedByteArray())
		out[float(l.get("edge_length", 0.0))] = _indices(data, vc)
	return out

static func _indices(data: PackedByteArray, vertex_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if vertex_count <= 65536:
		var n := data.size() / 2
		out.resize(n)
		for i in n:
			out[i] = data.decode_u16(i * 2)
	else:
		out = data.to_int32_array()
	return out

## Gathers merged surfaces: vertices, normals, tangents, UVs, bones and weights joined, indices offset, each source's
## levels of detail joined level by level (a source with fewer levels repeats its last).
class _Acc:
	var count := 0
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var parts: Array = []                  # [vertex offset, index count, lods dict]

	func add(a: Array, lods: Dictionary, p: Dictionary, nb: int) -> void:
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var vc := sv.size()
		var off := v.size()
		v.append_array(sv)
		var sn = a[Mesh.ARRAY_NORMAL]
		if sn != null and (sn as PackedVector3Array).size() == vc:
			n.append_array(sn)
		else:
			for i in vc:
				n.append(Vector3.UP)
		var st = a[Mesh.ARRAY_TANGENT]
		if st != null and (st as PackedFloat32Array).size() == vc * 4:
			t.append_array(st)
		else:
			for i in vc:
				t.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		var su = a[Mesh.ARRAY_TEX_UV]
		if su != null and (su as PackedVector2Array).size() == vc:
			uv.append_array(su)
		else:
			uv.resize(uv.size() + vc)
		var sb = a[Mesh.ARRAY_BONES]
		var sw = a[Mesh.ARRAY_WEIGHTS]
		if sb != null and (sb as PackedInt32Array).size() == vc * nb:
			bones.append_array(sb)
			wts.append_array(sw)
		else:
			bones.resize(bones.size() + vc * nb)
			var w0 := PackedFloat32Array()
			w0.resize(vc * nb)
			for i in vc:
				w0[i * nb] = 1.0
			wts.append_array(w0)
		var si = a[Mesh.ARRAY_INDEX]
		var ind := PackedInt32Array()
		if si != null and (si as PackedInt32Array).size() > 0:
			ind = si
		else:
			ind.resize(vc)
			for i in vc:
				ind[i] = i
		for i in ind.size():
			idx.append(ind[i] + off)
		var col := (p.col as Color).srgb_to_linear()
		var q0 := PackedFloat32Array([float(p.layer), float(p.uv), float(p.amt), float(p.rough)])
		var q1 := PackedFloat32Array([float(p.metal), float(p.depth), float(p.rim), float(p.emis)])
		var q2 := PackedFloat32Array([col.r, col.g, col.b, 1.0])
		# a material that multiplies by the vertex colours: the product per vertex
		var vcols = a[Mesh.ARRAY_COLOR] if bool(p.get("vcol", false)) else null
		if vcols != null and (vcols as PackedColorArray).size() != vc:
			vcols = null
		for i in vc:
			c0.append_array(q0)
			c1.append_array(q1)
			if vcols != null:
				var vcl: Color = vcols[i]
				if bool(p.get("vsrgb", false)):
					vcl = vcl.srgb_to_linear()
				c2.append_array(PackedFloat32Array([col.r * vcl.r, col.g * vcl.g, col.b * vcl.b, 1.0]))
			else:
				c2.append_array(q2)
		parts.append([off, ind, lods])
		count += 1

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TANGENT] = t
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = wts
		a[Mesh.ARRAY_INDEX] = idx
		a[Mesh.ARRAY_CUSTOM0] = c0
		a[Mesh.ARRAY_CUSTOM1] = c1
		a[Mesh.ARRAY_CUSTOM2] = c2
		return a

	## Level k of the merged surface: every part's level k (or its last), at the parts' mean edge length.
	func lods() -> Dictionary:
		var levels := 0
		for pt in parts:
			levels = maxi(levels, (pt[2] as Dictionary).size())
		var out := {}
		for k in levels:
			var ind := PackedInt32Array()
			var edge := 0.0
			var ne := 0
			for pt in parts:
				var d: Dictionary = pt[2]
				var src: PackedInt32Array = pt[1]
				if not d.is_empty():
					var keys := d.keys()
					keys.sort()
					var key = keys[mini(k, keys.size() - 1)]
					src = d[key]
					edge += float(key)
					ne += 1
				var off: int = pt[0]
				for i in src.size():
					ind.append(src[i] + off)
			if ne > 0:
				out[edge / ne] = ind
		return out
