class_name SwingArc
extends Trail3D
## A melee weapon's swing (run 2026-10-23): the band the blade sweeps between its middle and its tip, drawn as a glowing
## sheet that fades from the newest edge back along the arc and from the tip in toward the grip, its outer rim brightest.
## It replaces the thin ribbon that followed the tip alone. Between the frames' samples the sweep is smoothed (a
## Catmull-Rom curve through them), so a fast swing reads as a clean arc instead of a fan of straight wedges.
## Same use as Trail3D: `emitting` while swinging, `color`, `stop()`.

const SUB := 4                              # smoothed steps between two samples

var base: Node3D
var _pairs: Array = []                      # [base position, tip position, age]
var _was_emitting := false

static func make_arc(p_base: Node3D, p_tip: Node3D, p_color: Color, p_life := 0.16) -> SwingArc:
	var t := SwingArc.new()
	t.base = p_base
	t.target = p_tip
	t.color = p_color
	t.life = p_life
	t._mat = StandardMaterial3D.new()
	t._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t._mat.vertex_color_use_as_albedo = true
	t._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	t._mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	t._mat.no_depth_test = false
	t.material_override = t._mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.mesh = t._im
	t.top_level = true
	return t

func _step(dt: float) -> void:
	for p in _pairs:
		p[2] += dt
	while not _pairs.is_empty() and float(_pairs[0][2]) > life:
		_pairs.pop_front()
	var live := target != null and is_instance_valid(target) and base != null and is_instance_valid(base)
	if live and not _stopping and emitting:
		if not _was_emitting:
			_pairs.clear()                       # a new swing starts its own sheet
		var bp := base.global_position
		var tp := target.global_position
		if not _pairs.is_empty() and (_pairs[-1][1] as Vector3).distance_to(tp) > JUMP:
			_pairs.clear()
		if _pairs.is_empty() or (_pairs[-1][1] as Vector3).distance_to(tp) > 0.02:
			_pairs.append([bp, tp, 0.0])
	elif _pairs.is_empty() and (_stopping or not live):
		queue_free()
		return
	_was_emitting = live and emitting and not _stopping
	_build_arc()

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _build_arc() -> void:
	_im.clear_surfaces()
	var n := _pairs.size()
	if n < 2:
		return
	global_transform = Transform3D.IDENTITY
	var rows: Array = []                       # [base, tip, age]
	for i in n - 1:
		var a: Array = _pairs[maxi(i - 1, 0)]
		var b: Array = _pairs[i]
		var c: Array = _pairs[i + 1]
		var d: Array = _pairs[mini(i + 2, n - 1)]
		for k in SUB:
			var t := float(k) / SUB
			rows.append([_cr(a[0], b[0], c[0], d[0], t), _cr(a[1], b[1], c[1], d[1], t), lerpf(b[2], c[2], t)])
	rows.append([_pairs[n - 1][0], _pairs[n - 1][1], _pairs[n - 1][2]])
	var m := rows.size()
	var hot := color.lerp(Color(1, 1, 1, color.a), 0.45)
	# inner band: from the blade's middle (clear) out to its rim (the colour)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in m:
		var r: Array = rows[i]
		var k := float(i) / float(m - 1)
		var a := color.a * clampf(1.0 - float(r[2]) / life, 0.0, 1.0) * pow(k, 0.7)
		var mid: Vector3 = (r[0] as Vector3).lerp(r[1], 0.8)
		_im.surface_set_color(Color(color.r, color.g, color.b, 0.0))
		_im.surface_add_vertex(r[0])
		_im.surface_set_color(Color(color.r, color.g, color.b, a * 0.85))
		_im.surface_add_vertex(mid)
	_im.surface_end()
	# outer band: the hot rim near the tip
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in m:
		var r: Array = rows[i]
		var k := float(i) / float(m - 1)
		var a := color.a * clampf(1.0 - float(r[2]) / life, 0.0, 1.0) * pow(k, 0.7)
		var mid: Vector3 = (r[0] as Vector3).lerp(r[1], 0.8)
		_im.surface_set_color(Color(color.r, color.g, color.b, a * 0.85))
		_im.surface_add_vertex(mid)
		_im.surface_set_color(Color(hot.r, hot.g, hot.b, a))
		_im.surface_add_vertex(r[1])
	_im.surface_end()
