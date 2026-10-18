class_name CameraRig
extends Node3D
## Dota-style camera: a fixed-pitch perspective view of a ground point, panned by the screen edges, arrow keys or
## a middle-mouse drag, zoomed a little with the wheel, snapped to the hero with Space (held: follow).

@export var pitch_deg := 55.0
@export var distance := 15.6                # metres to the ground point (13.6 before 2026-10-18: raised a bit, owner's request)
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
var user_moved := false                    # the player panned (edges, keys, middle drag); Main clears it (watching: Free camera)
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
		user_moved = true

func _process(dt: float) -> void:
	var move := edge_dir() if edge_pan_enabled and not _drag else Vector2.ZERO
	var focused := DisplayServer.window_is_focused()
	if focused:
		if Keybinds.held("camera_left"): move.x -= 1
		if Keybinds.held("camera_right"): move.x += 1
		if Keybinds.held("camera_up"): move.y -= 1
		if Keybinds.held("camera_down"): move.y += 1
	if move != Vector2.ZERO:
		target += Vector3(move.x, 0, move.y).normalized() * edge_speed * dt * zoom
		user_moved = true
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

## Which screen edges the cursor touches (-1, 0, 1 on each axis). Read from the OS cursor and the window rectangle
## in real pixels every frame, so it does not depend on mouse-motion events (a cursor pinned against the edge sends
## none) or on the stretched 1080p canvas. Outside the window (Windowed without the cursor lock) nothing pans.
func edge_dir() -> Vector2:
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	if not Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED]:
		return Vector2.ZERO
	var wid := get_window().get_window_id() if get_window() else DisplayServer.MAIN_WINDOW_ID
	var wpos := DisplayServer.window_get_position(wid)
	var wsize := DisplayServer.window_get_size(wid)
	if wsize.x <= 0 or wsize.y <= 0:
		return Vector2.ZERO
	var m := DisplayServer.mouse_get_position() - wpos
	if m.x < 0 or m.y < 0 or m.x >= wsize.x or m.y >= wsize.y:
		return Vector2.ZERO
	var band := maxi(2, roundi(edge_px * wsize.y / 1080.0))
	var d := Vector2.ZERO
	if m.x < band: d.x -= 1
	if m.x >= wsize.x - band: d.x += 1
	if m.y < band: d.y -= 1
	if m.y >= wsize.y - band: d.y += 1
	return d

func _apply() -> void:
	if cam == null:
		return
	var p := deg_to_rad(pitch_deg)
	var d := distance * zoom
	cam.position = target + Vector3(0, sin(p) * d, cos(p) * d)
	cam.look_at(target, Vector3.UP)

## The ground point (sim coordinates) under a screen position, intersecting the terrain by marching the ray.
var ground_top := 60.0                     # metres: the highest ground (Main sets it from the terrain)

func ground_at(screen: Vector2) -> Vector2:
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var t := 0.0
	# start the march where the ray comes down to the highest ground the camera can look at (nothing to hit above
	# it): about 4x fewer height samples than marching from the lens
	if dir.y < -0.05 and o.y > ground_top:
		t = maxf(0.0, (o.y - ground_top) / -dir.y - 0.25)
	var last := o + dir * t
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
