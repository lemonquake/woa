class_name CameraRig
extends Node3D
## Dota-style camera: a fixed-pitch perspective view of a ground point, panned by the screen edges, arrow keys or
## a middle-mouse drag, zoomed a little with the wheel, snapped to the hero with Space (held: follow).

@export var pitch_deg := 55.0
@export var distance := 13.6
@export var fov := 46.0
@export var edge_speed := 32.0             # m/s
@export var edge_px := 6

var cam: Camera3D
var target := Vector3.ZERO                 # ground point under the screen centre
var zoom := 1.0
var _zoom_goal := 1.0
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_target := Vector3.ZERO
var follow: Callable                       # returns the hero position (Vector3) or null
var height_at: Callable                    # Vector2 sim -> height (game units)
var edge_pan_enabled := true
var _shake := 0.0                          # current shake strength (metres of jitter at the start)
var _shake_left := 0.0
var _shake_dur := 0.0

## Shake the view: strength in metres of jitter, decaying over `dur` seconds (the stronger shake wins).
func shake(strength: float, dur: float) -> void:
	if not bool(Options.get_value("screen_shake")):
		return
	var cur := _shake * (_shake_left / maxf(0.001, _shake_dur)) if _shake_left > 0.0 else 0.0
	if strength >= cur:
		_shake = strength
		_shake_dur = dur
		_shake_left = dur

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_apply()

func focus(p: Vector3) -> void:
	target = p
	_apply()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_goal = clampf(_zoom_goal - 0.08, 0.72, 1.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_goal = clampf(_zoom_goal + 0.08, 0.72, 1.25)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
			_drag_from = mb.position
			_drag_target = target
	elif e is InputEventMouseMotion and _drag:
		var d := (e as InputEventMouseMotion).position - _drag_from
		var k := distance * zoom / get_viewport().get_visible_rect().size.y * 1.6
		target = _drag_target + Vector3(-d.x * k, 0, -d.y * k)

func _process(dt: float) -> void:
	var move := Vector2.ZERO
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	var focused := DisplayServer.window_is_focused()
	# edge pan only with the cursor inside the window: outside it the position runs past the edges (negative on the
	# left and top) and would scroll the view on its own
	var inside := Rect2(Vector2.ZERO, size).has_point(m)
	if edge_pan_enabled and focused and inside and not _drag and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if m.x <= edge_px: move.x -= 1
		if m.x >= size.x - edge_px: move.x += 1
		if m.y <= edge_px: move.y -= 1
		if m.y >= size.y - edge_px: move.y += 1
	if focused:
		if Keybinds.held("camera_left"): move.x -= 1
		if Keybinds.held("camera_right"): move.x += 1
		if Keybinds.held("camera_up"): move.y -= 1
		if Keybinds.held("camera_down"): move.y += 1
	if move != Vector2.ZERO:
		target += Vector3(move.x, 0, move.y).normalized() * edge_speed * dt * zoom
	if focused and Keybinds.held("follow_hero") and follow.is_valid():
		var p = follow.call()
		if p != null:
			target = target.lerp(p, 1.0 - exp(-dt * 12.0))
	var lim := View.MAP_HALF_M - 6.0
	target.x = clampf(target.x, -lim, lim)
	target.z = clampf(target.z, -lim + 4.0, lim + 4.0)
	if height_at.is_valid():
		var h: float = height_at.call(View.to2(target)) * View.S
		target.y = lerpf(target.y, h, 1.0 - exp(-dt * 6.0))
	zoom = lerpf(zoom, _zoom_goal, 1.0 - exp(-dt * 10.0))
	_apply()
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - dt)
		var k := _shake * pow(_shake_left / maxf(0.001, _shake_dur), 1.5)
		var t := Time.get_ticks_msec() / 1000.0
		cam.h_offset = (sin(t * 71.0) + sin(t * 43.0) * 0.6) * 0.5 * k
		cam.v_offset = (cos(t * 63.0) + sin(t * 37.0) * 0.6) * 0.5 * k
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

func _apply() -> void:
	if cam == null:
		return
	var p := deg_to_rad(pitch_deg)
	var d := distance * zoom
	cam.position = target + Vector3(0, sin(p) * d, cos(p) * d)
	cam.look_at(target, Vector3.UP)

## The ground point (sim coordinates) under a screen position, intersecting the terrain by marching the ray.
func ground_at(screen: Vector2) -> Vector2:
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var t := 0.0
	var last := o
	for i in 240:
		t += 0.25
		var p := o + dir * t
		var h := 0.0
		if height_at.is_valid():
			h = float(height_at.call(View.to2(p))) * View.S
		if p.y <= h:
			# refine between last and p
			var lo := last
			var hi := p
			for k in 8:
				var mid := (lo + hi) * 0.5
				var hm: float = float(height_at.call(View.to2(mid))) * View.S if height_at.is_valid() else 0.0
				if mid.y <= hm:
					hi = mid
				else:
					lo = mid
			return View.to2(hi)
		last = p
	return View.to2(o + dir * t)
