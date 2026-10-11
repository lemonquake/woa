def rw(p, pairs):
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if b in s:
            continue
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:70]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)

rw('src/game/unit_view.gd', [
    ('''func flash() -> void:
	_flash = 1.0''', '''static var _flash_mat: StandardMaterial3D

## A brief white flash when hit.
func flash() -> void:
	if model == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.28)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if _flash <= 0.0:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = _flash_mat
	_flash = 0.09

## Lane creeps killed by a big enough blow are thrown back up to 200 units in a short arc (Dota's death knockback).
var _knock_from := Vector2.ZERO
var _knock_to := Vector2.ZERO
var _knock_t := -1.0
var _knock_dur := 0.5
var _knock_h := 0.0

func death_knock(from: Vector2, damage: float) -> void:
	if damage < 100.0:
		return
	var dir := (cur_pos - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(randf() * TAU)
	var dist := clampf(damage, 100.0, 500.0) / 500.0 * 200.0 * randf_range(0.6, 1.0)
	_knock_from = cur_pos
	_knock_to = cur_pos + dir * dist
	_knock_dur = randf_range(0.4, 0.6)
	_knock_h = dist / 200.0 * 0.5
	_knock_t = 0.0'''),
    ('''	var p := prev_pos.lerp(cur_pos, alpha)
	# skeletons off screen do not need animating''', '''	var p := prev_pos.lerp(cur_pos, alpha)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and model:
			for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mi.material_overlay = null
	var lift := 0.0
	if _knock_t >= 0.0:
		_knock_t += delta
		var f := clampf(_knock_t / _knock_dur, 0.0, 1.0)
		p = _knock_from.lerp(_knock_to, f)
		lift = sin(f * PI) * _knock_h
		if f >= 1.0:
			cur_pos = _knock_to
			prev_pos = _knock_to
			_knock_t = -1.0
	# skeletons off screen do not need animating'''),
    ('''	var h := terrain.height_at(p)
	position = View.to3(p, h)''', '''	var h := terrain.height_at(p)
	position = View.to3(p, h) + Vector3(0, lift, 0)'''),
    ('''	if not u.alive:
		if _dead_at < 0.0:''', '''	if not u.alive:
		if _knock_t >= 0.0:
			return
		if _dead_at < 0.0:'''),
])

rw('src/game/main.gd', [
    ('''		match e.t:
			"attack_start":''', '''		match e.t:
			"damage":
				_last_dmg[e.u] = float(e.amount)
				var dv = views.get(e.u)
				if dv is UnitView and float(e.amount) > 0.0 and e.get("attack", false):
					dv.flash()
			"attack_start":'''),
    ('''			"death":
				var du := world.get_unit(e.u)''', '''			"death":
				var kv = views.get(e.u)
				var killer := world.get_unit(e.killer)
				var dead := world.get_unit(e.u)
				if kv is UnitView and killer and dead and dead.is_lane_creep() and (killer.is_hero() or killer.team != C.NEUTRAL):
					kv.death_knock(killer.pos, float(_last_dmg.get(e.u, 0.0)))
				var du := world.get_unit(e.u)'''),
    ('''var _capture_frames := -1''', '''var _capture_frames := -1
var _last_dmg := {}'''),
])
print("ok")
