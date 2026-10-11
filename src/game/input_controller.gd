class_name InputController
extends Node
## Dota controls for the player's hero.
##   Right click: move / attack / deny / follow.      A + left click: attack-move or attack.
##   S stop, H hold position.                          Q W E R: abilities (point / unit targeting cursor).
##   Ctrl + Q W E R: learn ability.                    Right-click an ability button: toggle autocast.
##   Z X C V B N: items.                               Shift: queue orders.
##   F1 / double-tap: centre on hero; Space: follow.   F4 or B: shop.  J: glyph.

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var targeting := ""                         # "", "attack", ability id, or "item:<slot>"
var hover_id := -1
var _last_f1 := 0.0
const ITEM_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N]
const ABILITY_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R]

func hero() -> SimUnit:
	return game.world.get_unit(game.player_hero_id)

func _process(_dt: float) -> void:
	if game.camera == null or game.camera.cam == null:
		return
	var m := game.get_viewport().get_mouse_position()
	hover_id = pick(m)
	_cursor()

func _cursor() -> void:
	var shape := Input.CURSOR_ARROW
	if targeting != "":
		shape = Input.CURSOR_CROSS
	elif hover_id >= 0:
		var u: SimUnit = game.world.get_unit(hover_id)
		if u and u.team != game.player_team:
			shape = Input.CURSOR_CROSS
		else:
			shape = Input.CURSOR_POINTING_HAND
	Input.set_default_cursor_shape(shape)

## The unit under a screen point: the closest one whose upright capsule the camera ray passes through.
func pick(screen: Vector2) -> int:
	var cam: Camera3D = game.camera.cam
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var best := -1
	var best_t := INF
	for v in game.views.values():
		if not v.visible:
			continue
		var u: SimUnit = game.world.get_unit(v.uid)
		if u == null or not u.alive or u.kind == C.Kind.FOUNTAIN:
			continue
		var base: Vector3 = v.global_position
		var height: float = v.bar_height * 0.85
		var radius := maxf(u.hull * View.S * 1.25, 0.42)
		if u.is_building():
			radius = u.hull * View.S * 0.9
		# closest approach between the ray and the vertical segment base..base+height
		var res := _ray_segment(o, d, base, base + Vector3(0, height, 0))
		if res.x <= radius and res.y < best_t:
			best_t = res.y
			best = u.id
	return best

## (distance, ray t) between a ray and a segment.
func _ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var u := b - a
	var w0 := o - a
	var aa := d.dot(d)
	var bb := d.dot(u)
	var cc := u.dot(u)
	var dd := d.dot(w0)
	var ee := u.dot(w0)
	var den := aa * cc - bb * bb
	var sc := 0.0
	var tc := 0.0
	if den > 1e-6:
		sc = (bb * ee - cc * dd) / den
		tc = clampf((aa * ee - bb * dd) / den, 0.0, 1.0)
	else:
		tc = clampf(ee / cc, 0.0, 1.0)
	sc = maxf(sc, 0.0)
	var p1 := o + d * sc
	var p2 := a + u * tc
	return Vector2(p1.distance_to(p2), sc)

func _unhandled_input(e: InputEvent) -> void:
	var h := hero()
	if e is InputEventKey and e.pressed and not e.echo:
		_key(e as InputEventKey, h)
	elif e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if targeting != "":
				targeting = ""
				return
			_right_click(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_left_click(mb.position, mb.shift_pressed)

func _key(k: InputEventKey, h: SimUnit) -> void:
	var w: SimWorld = game.world
	match k.keycode:
		KEY_S:
			targeting = ""
			w.command(h.id, {"type": O.STOP})
		KEY_H:
			targeting = ""
			w.command(h.id, {"type": O.HOLD})
		KEY_A:
			targeting = "attack"
		KEY_ESCAPE:
			targeting = ""
		KEY_F1:
			game.selected_id = h.id
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_f1 < 0.4 and h.alive:
				game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
			_last_f1 = now
		KEY_F4:
			if game.hud and game.hud.has_method("toggle_shop"):
				game.hud.toggle_shop()
		KEY_J:
			w.glyph(game.player_team)
		KEY_T:
			begin_tp()
		KEY_F3:
			var err: String = w.courier_deliver(h)
			if err != "" and game.hud and game.hud.has_method("error"):
				game.hud.error(err)
	var ai := ABILITY_KEYS.find(k.keycode)
	if ai >= 0 and ai < h.abilities.size():
		var aid: String = h.abilities[ai]
		if k.ctrl_pressed:
			w.abilities.learn(h, aid)
		else:
			begin_ability(aid)
		return
	var ii := ITEM_KEYS.find(k.keycode)
	if ii >= 0:
		if k.keycode == KEY_B and h.inventory[4] == null:
			if game.hud and game.hud.has_method("toggle_shop"):
				game.hud.toggle_shop()
			return
		use_item(ii)

func begin_ability(aid: String) -> void:
	var h := hero()
	var a := SimData.ability(aid)
	var err: String = game.world.abilities.cast_error(h, aid, -1, null, h.pos)
	if err != "" and err != "Must target an enemy unit":
		if game.hud and game.hud.has_method("error"):
			game.hud.error(err)
		return
	match String(a.behavior):
		"no_target":
			game.world.command(h.id, {"type": O.CAST_NO_TARGET, "ability": aid})
		"point", "unit", "autocast_attack":
			targeting = aid

func begin_tp() -> void:
	var h := hero()
	var err: String = game.world.abilities.cast_error(h, "tp", -1, null, h.pos)
	if err != "":
		if game.hud and game.hud.has_method("error"):
			game.hud.error(err)
		return
	targeting = "tp"

## Issue the pending targeted order at a sim point (used by the minimap too).
func target_point(p: Vector2, shift := false) -> void:
	var h := hero()
	if targeting == "tp":
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": "tp", "point": p, "queue": shift})
	elif targeting == "attack":
		game.world.command(h.id, {"type": O.ATTACK_MOVE, "point": p, "queue": shift})
	elif targeting.begins_with("item:"):
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": int(targeting.substr(5)), "point": p, "queue": shift})
	elif targeting != "":
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": targeting, "point": p, "queue": shift})
	targeting = ""

func use_item(slot: int) -> void:
	var h := hero()
	var it = h.inventory[slot]
	if it == null:
		return
	var kind: String = game.world.abilities.item_target(it.id)
	if kind == "none":
		game.world.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": slot})
	else:
		targeting = "item:%d" % slot

func _left_click(pos: Vector2, shift: bool) -> void:
	var w: SimWorld = game.world
	var h := hero()
	if targeting == "":
		var id := pick(pos)
		if id >= 0:
			game.selected_id = id
		return
	var target_id := pick(pos)
	var ground: Vector2 = game.camera.ground_at(pos)
	var tgt := w.get_unit(target_id)
	if targeting == "tp":
		target_point(ground, shift)
		return
	if targeting == "attack":
		if tgt and tgt.id != h.id:
			w.command(h.id, {"type": O.ATTACK_UNIT, "target": tgt.id, "queue": shift})
			game.fx.marker(View.to3(tgt.pos, game.terrain.height_at(tgt.pos)), true)
		else:
			w.command(h.id, {"type": O.ATTACK_MOVE, "point": ground, "queue": shift})
			game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), true)
	elif targeting.begins_with("item:"):
		var slot := int(targeting.substr(5))
		w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": slot, "point": ground, "queue": shift})
	else:
		var a := SimData.ability(targeting)
		if String(a.behavior) == "autocast_attack" or String(a.behavior) == "unit":
			if tgt:
				w.command(h.id, {"type": O.CAST_UNIT, "ability": targeting, "target": tgt.id, "queue": shift})
		else:
			w.command(h.id, {"type": O.CAST_POINT, "ability": targeting, "point": ground, "queue": shift})
	if not shift:
		targeting = ""

func _right_click(pos: Vector2, shift: bool) -> void:
	var w: SimWorld = game.world
	var h := hero()
	if h == null or not h.alive:
		return
	var id := pick(pos)
	var tgt := w.get_unit(id)
	if tgt and tgt != h:
		if tgt.team != h.team or w.orders.can_deny(h, tgt):
			w.command(h.id, {"type": O.ATTACK_UNIT, "target": tgt.id, "queue": shift})
			game.fx.marker(View.to3(tgt.pos, game.terrain.height_at(tgt.pos)), true)
			return
		w.command(h.id, {"type": O.MOVE_TO_UNIT, "target": tgt.id, "queue": shift})
		return
	var ground: Vector2 = game.camera.ground_at(pos)
	w.command(h.id, {"type": O.MOVE, "point": ground, "queue": shift})
	game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), false)
