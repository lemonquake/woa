class_name EmblemView
extends SubViewportContainer
## A rank's 3D emblem you can turn (run 2026-10-19 b): drag with the left mouse button to turn it any way (it keeps
## spinning a little after you let go, then settles back to a slow sway). The glint sweeps across the metal and the
## top ranks' rings turn.

var tier := -1
var stars := 0
var px := 420
var _vp: SubViewport
var _em: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _vyaw := 0.0
var _vpitch := 0.0
var _drag := false
var _t := 0.0
var _idle := 0.0                          # seconds since the last drag

func _init(p_px := 420) -> void:
	px = p_px
	stretch = true
	custom_minimum_size = Vector2(p_px, p_px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = ""

func show_rank(p_tier: int, p_stars: int) -> void:
	if p_tier == tier and p_stars == stars and _vp != null:
		return
	tier = p_tier
	stars = p_stars
	if _vp != null:
		_vp.queue_free()
	_vp = RankEmblem.stage(tier, stars, px, true)
	add_child(_vp)
	_em = _vp.get_node("Emblem")

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		var rel := (e as InputEventMouseMotion).relative
		_vyaw = rel.x * 0.012                   # the turn per frame, carried on after you let go
		_vpitch = rel.y * 0.012
		_yaw += rel.x * 0.012
		_pitch = clampf(_pitch + rel.y * 0.012, -1.1, 1.1)
		_idle = 0.0
		accept_event()

func _process(dt: float) -> void:
	if _em == null:
		return
	_t += dt
	if not _drag:
		_idle += dt
		# let go: the spin carries on and slows down
		_yaw += _vyaw * dt * 60.0
		_pitch = clampf(_pitch + _vpitch * dt * 60.0, -1.1, 1.1)
		_vyaw = lerpf(_vyaw, 0.0, 1.0 - exp(-dt * 2.2))
		_vpitch = lerpf(_vpitch, 0.0, 1.0 - exp(-dt * 3.0))
		if _idle > 1.5:
			# settle into a slow sway facing you
			var rest := sin(_t * 0.6) * 0.32
			_yaw = lerp_angle(_yaw, rest, 1.0 - exp(-dt * 1.4))
			_pitch = lerpf(_pitch, sin(_t * 0.45) * 0.06, 1.0 - exp(-dt * 1.4))
	_em.rotation = Vector3(_pitch, _yaw, 0.0)
