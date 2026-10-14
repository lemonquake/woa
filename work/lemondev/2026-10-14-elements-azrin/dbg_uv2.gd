extends SceneTree
func _init() -> void:
	var src := HeroAppearance._alt_src("res://assets/characters/hero/azrin_body.glb")
	var mesh: ArrayMesh = src.mesh
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var top := 0
	var low := 0
	for i in v.size():
		if v[i].y > v[top].y:
			top = i
		if v[i].y < v[low].y:
			low = i
	print("top vertex ", v[top], " uv2 ", uv2[top])
	print("low vertex ", v[low], " uv2 ", uv2[low])
	var m := (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate() as Node3D
	root.add_child(m)
	var ap := HeroAppearance.new(m)
	ap.apply(GameSettings.default_look("azrin").look)
	var plan := ap._plan() if false else {}
	ap.outfit = {"armor": "ember_dragonhide"}
	print("hide ", ap._plan().hide)
	quit()
