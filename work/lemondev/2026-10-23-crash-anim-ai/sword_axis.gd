extends SceneTree
## The held sword's extent in its weapon bone's space (which axis the blade runs along, how long, where the grip is).

func _init() -> void:
	for wname in ["heavy_greatsword"]:
		var path: String = "res://assets/weapons/" + wname + ".glb"
		if not ResourceLoader.exists(path):
			print(wname, " missing")
			continue
		var n: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(n)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var pts := PackedVector3Array()
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var xf := n.global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var p := xf * v
					lo = lo.min(p)
					hi = hi.max(p)
					pts.append(p)
		print(wname, " aabb lo ", lo, " hi ", hi, " verts ", pts.size())
		# where along y the cross-section is narrow (the grip) vs wide (the blade)
		var bins := {}
		for p in pts:
			var b := int(floor(p.y / 0.05))
			var r: Vector2 = bins.get(b, Vector2(0, 0))
			bins[b] = Vector2(maxf(r.x, absf(p.x)), maxf(r.y, absf(p.z)))
		var ks := bins.keys()
		ks.sort()
		for b in ks:
			print("  y %.2f  |x| %.3f  |z| %.3f" % [b * 0.05, bins[b].x, bins[b].y])
		n.queue_free()
	quit()
