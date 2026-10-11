class_name Trail3D
extends MeshInstance3D
## A ribbon that follows a node: the last few positions become a camera-facing strip that tapers and fades towards
## its tail. Used for arrows, leaps and spell bolts. Lives in world space (top level); call `stop()` to let the tail
## fade out and free itself.

var target: Node3D
var width := 0.06
var life := 0.18                           # seconds a point lasts
var color := Color(1, 1, 1, 0.6)
var _pts: Array = []                       # [[position, age]]
var _im := ImmediateMesh.new()
var _stopping := false
var _mat: StandardMaterial3D

static func make(p_target: Node3D, p_color: Color, p_width := 0.06, p_life := 0.18, additive := true) -> Trail3D:
	var t := Trail3D.new()
	t.target = p_target
	t.color = p_color
	t.width = p_width
	t.life = p_life
	t._mat = StandardMaterial3D.new()
	t._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t._mat.vertex_color_use_as_albedo = true
	t._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		t._mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	t.material_override = t._mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.mesh = t._im
	t.top_level = true
	return t

func stop() -> void:
	_stopping = true
	target = null

static var cost_us := 0                     # benchmark: total time spent rebuilding trails

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(dt)
	cost_us += Time.get_ticks_usec() - t0

func _step(dt: float) -> void:
	for p in _pts:
		p[1] += dt
	while not _pts.is_empty() and _pts[0][1] > life:
		_pts.pop_front()
	if target != null and is_instance_valid(target) and not _stopping:
		var gp := target.global_position
		if _pts.is_empty() or (_pts[-1][0] as Vector3).distance_to(gp) > 0.04:
			_pts.append([gp, 0.0])
	elif _pts.is_empty():
		queue_free()
		return
	_build()

func _build() -> void:
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	global_transform = Transform3D.IDENTITY
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pts.size()
	for i in n:
		var p: Vector3 = _pts[i][0]
		var nxt: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var prv: Vector3 = _pts[maxi(i - 1, 0)][0]
		var along := (nxt - prv)
		if along.length() < 0.0001:
			along = Vector3.FORWARD
		var side := along.cross(eye - p).normalized()
		var k := float(i) / float(n - 1)                      # 0 tail .. 1 head
		var fade := clampf(1.0 - float(_pts[i][1]) / life, 0.0, 1.0)
		var wdt := width * (0.15 + 0.85 * k)
		var c := Color(color.r, color.g, color.b, color.a * fade * k)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * wdt)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * wdt)
	_im.surface_end()
