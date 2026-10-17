extends SceneTree
## Lists the meshes of every unit model (ModelCatalog): parts, surfaces, materials, triangles, blend shapes, bones.
## Draw calls grow with surfaces, so models with many surfaces that share a material are worth merging.
##   godot --headless --path . -s tests/tools/mesh_census.gd [-- --keys=dawn_melee,hero]

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--keys="):
			only = a.substr(7)
	var keys: Array = ModelCatalog.MODELS.keys()
	if only != "":
		keys = only.split(",")
	var seen := {}
	for k in keys:
		var path := String(ModelCatalog.MODELS[k].scene)
		if seen.has(path):
			continue
		seen[path] = true
		var root := (load(path) as PackedScene).instantiate()
		var line := "%s (%s)" % [k, path.get_file()]
		var mats := {}
		var surf := 0
		var tris := 0
		var parts := 0
		var blend := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			parts += 1
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
				blend += 1
			for s in mi.mesh.get_surface_count():
				surf += 1
				var m := mi.get_active_material(s)
				var mn := (m.resource_name if m and m.resource_name != "" else str(m.get_instance_id() if m else 0))
				mats[mn] = int(mats.get(mn, 0)) + 1
				var arr := mi.mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var sk := root.find_children("*", "Skeleton3D", true, false)
		print("%s: parts %d surfaces %d materials %d tris %d blend-meshes %d bones %d  %s" % [line, parts, surf, mats.size(), tris,
			blend, (sk[0] as Skeleton3D).get_bone_count() if not sk.is_empty() else 0, str(mats)])
		root.free()
	quit()
