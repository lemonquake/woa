extends SceneTree
## Lists every mesh surface of a model as Godot imports it: material, transparency, alpha scissor, cull mode and the
## albedo texture (checks that cut-out cards such as fur and hair survive the import).
##   godot --headless --path . -s tests/tools/model_surfaces.gd -- --model=res://assets/characters/heroes17/ghorman.glb

func _init() -> void:
	var path := "res://assets/characters/heroes17/ghorman.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			path = a.substr(8)
	var root := (load(path) as PackedScene).instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh
		print("mesh ", mi.name, " surfaces ", mesh.get_surface_count())
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			var n := (mesh as ArrayMesh).surface_get_array_len(i)
			if m is BaseMaterial3D:
				var b := m as BaseMaterial3D
				print("  %d %s verts=%d transp=%d scissor=%.2f cull=%d tex=%s" % [i, b.resource_name, n, b.transparency,
					b.alpha_scissor_threshold, b.cull_mode, b.albedo_texture.resource_path if b.albedo_texture else "-"])
			else:
				print("  %d %s verts=%d" % [i, m, n])
	root.free()
	quit(0)
