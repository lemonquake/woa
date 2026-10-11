class_name InputController
extends Node
## Dota controls for the player's units.
##   Left click: select. Left drag: box select (your own units first; otherwise the one unit nearest the box centre).
##   Right click: move / attack / deny / follow.      A + left click: attack-move or attack (allies: deny when able).
##   S stop (the hero still auto-attacks enemies in range); hold S: hard stop, no auto-attack until the next order.
##   H hold position.                                 Q W E R: abilities (point / unit targeting cursor).
##   Ctrl + Q W E R: learn ability.                    Right-click an ability button: toggle autocast.
##   Z X C V B N: items.                               Shift: queue orders.
##   F1 / double-tap: centre on hero; Space: follow.   F4 or B: shop.  J: glyph.
## Orders go to the selected units you control (your hero and courier), as in Dota: with only an enemy or a creep
## selected, right clicks do nothing until you select your hero again (F1, the portrait, or a click on it).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const DRAG_PX := 6.0
const HARD_STOP_HOLD := 0.35

var game: Node
var targeting := ""                         # "", "attack", ability id, or "item:<slot>"
var hover_id := -1
var drag_rect := Rect2()                    # the green selection box while dragging (screen space)
var _last_f1 := 0.0
var _press_at := Vector2.ZERO
var _pressing := false
var _dragging := false
var _s_down := -1.0
var _s_hard := false
const ITEM_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N]
const ABILITY_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R]

func hero() -> SimUnit:
	return game.world.get_unit(game.player_hero_id)

## Your hero is selected (abilities, items and its orders apply).
func hero_selected() -> bool:
	return game.player_hero_id in game.selected

func _courier_selected() -> SimUnit:
	var h := hero()
	if h != null and h.courier_id in game.selected:
		return game.world.get_unit(h.courier_id)
	return null

func _process(_dt: float) -> void:
	if game.camera == null or game.camera.cam == null:
		return
	var m := game.get_viewport().get_mouse_position()
	hover_id = pick(m)
	_cursor()
	# S held long enough: a hard stop
	if _s_down >= 0.0 and not _s_hard:
		if not Input.is_key_pressed(KEY_S):
			_s_down = -1.0
		elif Time.get_ticks_msec() / 1000.0 - _s_down >= HARD_STOP_HOLD:
			_s_hard = true
			if hero_selected():
				game.world.command(game.player_hero_id, {"type": O.STOP, "hard": true})
				if game.hud and game.hud.has_method("error"):
					game.hud.notice("Hard stop: no auto-attack until your next order")

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
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if targeting != "":
				targeting = ""
				return
			_right_click(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if targeting != "":
					_left_click(mb.position, mb.shift_pressed)
				else:
					_pressing = true
					_dragging = false
					_press_at = mb.position
			elif _pressing:
				_pressing = false
				if _dragging:
					_box_select(drag_rect, mb.shift_pressed)
				else:
					_click_select(mb.position, mb.shift_pressed)
				_dragging = false
				drag_rect = Rect2()
	elif e is InputEventMouseMotion and _pressing:
		var p := (e as InputEventMouseMotion).position
		if not _dragging and p.distance_to(_press_at) > DRAG_PX:
			_dragging = true
		if _dragging:
			drag_rect = Rect2(_press_at, Vector2.ZERO).expand(p)

# ---- Selection ------------------------------------------------------------------------------------------------------

func _owned(u: SimUnit) -> bool:
	var h := hero()
	return u != null and h != null and (u.id == h.id or u.id == h.courier_id)

func select(ids: Array) -> void:
	game.selected = ids.duplicate()
	game.selected_id = ids[0] if not ids.is_empty() else -1

func _click_select(pos: Vector2, shift: bool) -> void:
	var id := pick(pos)
	if id < 0:
		return
	var u: SimUnit = game.world.get_unit(id)
	if shift and _owned(u) and game.selected.all(func(x): return _owned(game.world.get_unit(x))):
		if not (id in game.selected):
			game.selected.append(id)
		return
	select([id])

## Box select: every unit of yours inside the box (your hero first); with none of yours inside, the single unit
## nearest the box centre (heroes before creeps and buildings). An empty box keeps the current selection.
func _box_select(r: Rect2, shift: bool) -> void:
	var cam: Camera3D = game.camera.cam
	var mine: Array = []
	var best := -1
	var best_score := INF
	for v in game.views.values():
		if not v.visible:
			continue
		var u: SimUnit = game.world.get_unit(v.uid)
		if u == null or not u.alive or u.kind == C.Kind.FOUNTAIN or u.is_ward():
			continue
		var inside := false
		for hgt in [0.2, v.bar_height * 0.5, v.bar_height]:
			var wp: Vector3 = v.global_position + Vector3(0, hgt, 0)
			if not cam.is_position_behind(wp) and r.grow(u.hull * 0.04 + 4.0).has_point(cam.unproject_position(wp)):
				inside = true
				break
		if not inside:
			continue
		if _owned(u):
			if u.is_hero():
				mine.push_front(u.id)
			else:
				mine.append(u.id)
			continue
		var sp := cam.unproject_position(v.global_position + Vector3(0, v.bar_height * 0.5, 0))
		var score := sp.distance_to(r.get_center()) + (0.0 if u.is_hero() else (4000.0 if u.is_building() else 2000.0))
		if score < best_score:
			best_score = score
			best = u.id
	if not mine.is_empty():
		if shift and game.selected.all(func(x): return _owned(game.world.get_unit(x))):
			for id in mine:
				if not (id in game.selected):
					game.selected.append(id)
			return
		select(mine)
	elif best >= 0:
		select([best])

# ---- Keys -----------------------------------------------------------------------------------------------------------

func _key(k: InputEventKey, h: SimUnit) -> void:
	var w: SimWorld = game.world
	match k.keycode:
		KEY_S:
			targeting = ""
			_s_down = Time.get_ticks_msec() / 1000.0
			_s_hard = false
			if hero_selected():
				w.command(h.id, {"type": O.STOP})
			var cs := _courier_selected()
			if cs:
				cs.courier_state = "idle"
		KEY_H:
			targeting = ""
			if hero_selected():
				w.command(h.id, {"type": O.HOLD})
		KEY_A:
			if hero_selected():
				targeting = "attack"
		KEY_ESCAPE:
			if targeting != "":
				targeting = ""
				get_viewport().set_input_as_handled()
		KEY_F1:
			select([h.id])
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
			if hero_selected():
				begin_tp()
		KEY_F3:
			var err: String = w.courier_deliver(h)
			if err != "" and game.hud and game.hud.has_method("error"):
				game.hud.error(err)
	var ai := ABILITY_KEYS.find(k.keycode)
	if ai >= 0 and ai < h.abilities.size():
		if not hero_selected():
			return
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
		if hero_selected():
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

## A right click on the minimap: move the selected units you control there.
func move_selected(p: Vector2, shift := false) -> void:
	if hero_selected():
		game.world.command(game.player_hero_id, {"type": O.MOVE, "point": p, "queue": shift})
	if _courier_selected():
		game.world.courier_move(hero(), p)

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
	var ground: Vector2 = game.camera.ground_at(pos)
	var cs := _courier_selected()
	if cs:
		w.courier_move(h, ground)
		if not hero_selected():
			game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), false)
	if h == null or not h.alive or not hero_selected():
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
	w.command(h.id, {"type": O.MOVE, "point": ground, "queue": shift})
	game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), false)
