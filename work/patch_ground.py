def rw(p, pairs):
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if b in s:
            continue
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:70]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)

# --- contact shadows: a soft dark blob under props (Dressing) and trees (Foliage)
rw('src/game/dressing.gd', [
    ('''func _add(model: String, p: Vector2, scale: float, sink := 0.0, shadow := false, yaw := -1.0, tilt := 0.0) -> void:
	if not _ok(p):
		return''', '''## Soft contact shadows: radius in metres per placed prop, emitted as one MultiMesh of flat gradient quads per chunk.
var _blobs := {}                           # chunk -> [Transform3D]

static var _blob_mesh: QuadMesh

static func blob_mesh() -> QuadMesh:
	if _blob_mesh:
		return _blob_mesh
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			img.set_pixel(x, y, Color(0.02, 0.025, 0.015, clampf(1.0 - d, 0.0, 1.0) ** 1.6 * 0.6))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	_blob_mesh = QuadMesh.new()
	_blob_mesh.size = Vector2(1, 1)
	_blob_mesh.orientation = PlaneMesh.FACE_Y
	_blob_mesh.material = m
	return _blob_mesh

func blob(p: Vector2, radius_m: float) -> void:
	var ck := Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))
	if not _blobs.has(ck):
		_blobs[ck] = []
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(radius_m * 2.0, 1.0, radius_m * 2.0 * _rng.randf_range(0.8, 1.1))),
		View.to3(p, terrain.height_at(p)) + Vector3(0, 0.035, 0))
	_blobs[ck].append(xf)

func _add(model: String, p: Vector2, scale: float, sink := 0.0, shadow := false, yaw := -1.0, tilt := 0.0) -> void:
	if not _ok(p):
		return
	# props and clumps sit in a soft pool of contact shade
	var foot := scale * (0.9 if model.begins_with("Grass") else (0.55 if model.begins_with("kf_rocks") else 1.0))
	if not model.begins_with("RockPath") and not model.begins_with("kf_stones"):
		blob(p, clampf(foot * 0.55, 0.12, 2.2))'''),
    ('''func _emit() -> void:
	for path in _groups:''', '''func _emit() -> void:
	for ck in _blobs:
		var list: Array = _blobs[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = blob_mesh()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 70.0
		add_child(mi)
	for path in _groups:'''),
    ('''	_landmarks()
	_emit()''', '''	_landmarks()
	_tree_blobs()
	_emit()

## Every tree trunk gets a contact pool too (canopy shadows come from the sun).
func _tree_blobs() -> void:
	for t in map.trees:
		blob(t.pos, 0.75 * float(t.scale))'''),
])

# --- terrain: dirt fringe between road and grass, wet dark bank at the waterline, calmer green
rw('src/game/terrain.gdshader', [
    ('uniform vec3 grass_tint : source_color = vec3(0.78, 0.98, 0.62);', 'uniform vec3 grass_tint : source_color = vec3(0.74, 0.93, 0.62);'),
    ('uniform float saturation = 1.18;', 'uniform float saturation = 1.1;'),
    ('''	float road_w = smoothstep(0.55, 0.85, rh + (macro.g - 0.5) * 0.3);
	col = mix(col, road, road_w);''', '''	float road_w = smoothstep(0.55, 0.85, rh + (macro.g - 0.5) * 0.45 + (texture(macro_tex, wpos.xz * 0.09).r - 0.5) * 0.35);
	// a ragged fringe of packed dirt and leaf litter between grass and gravel
	float fringe = smoothstep(0.28, 0.5, rh + (macro.b - 0.5) * 0.5) * (1.0 - road_w);
	col = mix(col, forest * vec4(0.95, 0.9, 0.82, 1.0), fringe * 0.75);
	col = mix(col, road, road_w);'''),
    ('''	float riv_w = 1.0 - smoothstep(river_height - 0.15, river_height + 0.35, h + (riv.r - 0.5) * 0.3);
	col = mix(col, riv, riv_w);''', '''	float riv_w = 1.0 - smoothstep(river_height - 0.15, river_height + 0.35, h + (riv.r - 0.5) * 0.3);
	col = mix(col, riv, riv_w);
	// wet, darkened bank just above the waterline
	float wet = 1.0 - smoothstep(river_height - 0.02, river_height + 0.3, h + (macro.r - 0.5) * 0.12);
	wet *= smoothstep(river_height - 0.25, river_height - 0.02, h);
	col.rgb *= 1.0 - wet * 0.45;
	col.a = mix(col.a, 0.25, wet);'''),
])
rw('src/game/water.gdshader', [
    ('''	float foam_line = 1.0 - smoothstep(0.0, 0.07, depth_diff);''', '''	float foam_line = (1.0 - smoothstep(0.0, 0.05, depth_diff)) * 0.6;'''),
    ('''	col = mix(col, foam_color, foam * 0.55);''', '''	col = mix(col, foam_color, foam * 0.3);
	// the water darkens and thins at the shore instead of drawing a bright outline
	col = mix(col * 0.75, col, smoothstep(0.0, 0.12, depth_diff));'''),
])

# --- readability: closer camera, bolder hero names
rw('src/game/camera_rig.gd', [('@export var distance := 15.5', '@export var distance := 13.6')])
rw('src/ui/unit_bars.gd', [
    ('''		var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(font, Vector2(s.x - nw * 0.5, r.position.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(s.x - nw * 0.5, r.position.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.35))''',
     '''		var nf := UiKit.font("bold")
		var nw := nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(nf, Vector2(s.x - nw * 0.5, r.position.y - 7), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
		draw_string(nf, Vector2(s.x - nw * 0.5, r.position.y - 7), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.lightened(0.45))'''),
])
print("ok")
