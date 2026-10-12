class_name InputController
extends Node
## Dota controls for the player's units.
##   Left click: select. Left drag: box select (your own units first; otherwise the one unit nearest the box centre).
##   Right click: move / attack / deny / follow.      A + left click: attack-move or attack (allies: deny when able).
##   S stop (the hero still auto-attacks enemies in range); hold S: hard stop, no auto-attack until the next order.
##   H hold position.                                 Q W E R: abilities (point / unit targeting cursor).
##   Ctrl + Q W E R: learn ability.                    Right-click an ability button: toggle autocast.
##   Z X C V B N: items.                               Shift: queue orders.
##   F1 / double-tap: centre on hero; Space: follow.   F4 or B: shop.  J: glyph.  F9: debug panel.
##   Hold right click: the move / attack order repeats towards the cursor (auto right-click).
## Every key above is the default: the player rebinds them on the Hotkeys screen (Keybinds).
## Orders go to the selected units you control (your hero and courier), as in Dota: with only an enemy or a creep
## selected, right clicks do nothing until you select your hero again (F1, the portrait, or a click on it).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const DRAG_PX := 6.0
const HARD_STOP_HOLD := 0.35

var game: Node
var targeting := ""                         # "", "attack", ability id, or "item:<slot>"
var hover_id := -1
var hover_ability := ""                     # the ability button under the mouse (its radius is previewed)
var drag_rect := Rect2()                    # the green selection box while dragging (screen space)
var _last_f1 := 0.0
var _last_f2 := 0.0
var _press_at := Vector2.ZERO
var _pressing := false
var _dragging := false
var _s_down := -1.0
var _s_hard := false
var _groups := {}                           # control group key (1..9) -> unit ids
var _group_tap := {}                        # key -> time of the last recall (double tap centres the camera)
const ITEM_ACTIONS := ["item_1", "item_2", "item_3", "item_4", "item_5", "item_6"]
const ABILITY_ACTIONS := ["ability_1", "ability_2", "ability_3", "ability_4"]
## Holding right click repeats the order: first repeat after RMB_DELAY, then every RMB_REPEAT seconds.
const RMB_DELAY := 0.22
const RMB_REPEAT := 0.1
var _rmb_held := false
var _rmb_next := 0.0
var _rmb_shift := false

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
	_rmb_repeat()
	# S held long enough: a hard stop
	if _s_down >= 0.0 and not _s_hard:
		if not Keybinds.held("stop"):
			_s_down = -1.0
		elif Time.get_ticks_msec() / 1000.0 - _s_down >= HARD_STOP_HOLD:
			_s_hard = true
			if hero_selected():
				game.world.command(game.player_hero_id, {"type": O.STOP, "hard": true})
				if game.hud and game.hud.has_method("error"):
					game.hud.notice("Hard stop: no auto-attack until your next order")

## Auto right-click: while the right button stays down (and the press began in the world, not on the HUD), keep
## re-issuing the right-click order at the cursor so the hero tracks it, as holding right click does in Dota.
func _rmb_repeat() -> void:
	if not _rmb_held:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or targeting != "":
		_rmb_held = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _rmb_next:
		return
	_rmb_next = now + RMB_REPEAT
	var m := game.get_viewport().get_mouse_position()
	if game.hud and game.hud.has_method("over_hud") and game.hud.over_hud(m):
		return
	_right_click(m, _rmb_shift, true)

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
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			var act := Keybinds.action_for(mb)
			if act != "":
				_action(act, h, mb.ctrl_pressed)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			_rmb_held = false
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if targeting != "":
				targeting = ""
				return
			_right_click(mb.position, mb.shift_pressed)
			_rmb_held = true
			_rmb_shift = mb.shift_pressed
			_rmb_next = Time.get_ticks_msec() / 1000.0 + RMB_DELAY
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
				if not _dragging and mb.alt_pressed:
					ping(game.camera.ground_at(mb.position))
					drag_rect = Rect2()
					return
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
	var act := Keybinds.action_for(k)
	# control groups: Ctrl+1..9 stores your selected units, 1..9 recalls them (unless the digit is a hotkey),
	# a double tap centres on them
	if k.keycode >= KEY_1 and k.keycode <= KEY_9 and (k.ctrl_pressed or act == ""):
		var g := int(k.keycode - KEY_0)
		if k.ctrl_pressed:
			var ids: Array = game.selected.filter(func(x): return _owned(w.get_unit(x)))
			if not ids.is_empty():
				_groups[g] = ids
				if game.hud and game.hud.has_method("notice"):
					game.hud.notice("Control group %d set" % g)
		elif _groups.has(g):
			var ids2: Array = (_groups[g] as Array).filter(func(x): return w.get_unit(x) != null)
			if not ids2.is_empty():
				select(ids2)
				var now2 := Time.get_ticks_msec() / 1000.0
				if now2 - float(_group_tap.get(g, -9.0)) < 0.4:
					var u0: SimUnit = w.get_unit(ids2[0])
					if u0 and u0.alive:
						game.camera.focus(View.to3(u0.pos, game.terrain.height_at(u0.pos)))
				_group_tap[g] = now2
		return
	if k.keycode == KEY_ESCAPE:
		if targeting != "":
			targeting = ""
			get_viewport().set_input_as_handled()
		return
	if act != "":
		_action(act, h, k.ctrl_pressed)

## Run a hotkey action (from a key or an extra mouse button). learn: Ctrl was held (Ctrl + ability key learns it).
func _action(act: String, h: SimUnit, learn := false) -> void:
	var w: SimWorld = game.world
	if h == null:
		return
	match act:
		"stop":
			targeting = ""
			_s_down = Time.get_ticks_msec() / 1000.0
			_s_hard = false
			if hero_selected():
				w.command(h.id, {"type": O.STOP})
			var cs := _courier_selected()
			if cs:
				cs.courier_state = "idle"
		"hold":
			targeting = ""
			if hero_selected():
				w.command(h.id, {"type": O.HOLD})
		"attack":
			if hero_selected():
				targeting = "attack"
		"select_hero":
			select([h.id])
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_f1 < 0.4 and h.alive:
				game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
			_last_f1 = now
		"select_courier":
			var c := w.get_unit(h.courier_id)
			if c != null and c.alive:
				var now2 := Time.get_ticks_msec() / 1000.0
				if game.selected == [c.id] and now2 - _last_f2 < 0.4:
					game.camera.focus(View.to3(c.pos, game.terrain.height_at(c.pos)))
				select([c.id])
				_last_f2 = now2
		"shop":
			if game.hud and game.hud.has_method("toggle_shop"):
				game.hud.toggle_shop()
		"glyph":
			w.glyph(game.player_team)
		"tp":
			if hero_selected():
				begin_tp()
		"courier_deliver":
			var err: String = w.courier_deliver(h)
			if err != "" and game.hud and game.hud.has_method("error"):
				game.hud.error(err)
		"debug":
			if game.hud and game.hud.has_method("toggle_debug"):
				game.hud.toggle_debug()
	var ai := ABILITY_ACTIONS.find(act)
	if ai >= 0 and ai < h.abilities.size():
		if not hero_selected():
			return
		var aid: String = h.abilities[ai]
		if learn:
			w.abilities.learn(h, aid)
		else:
			begin_ability(aid)
		return
	var ii := ITEM_ACTIONS.find(act)
	if ii >= 0:
		# the item 5 key opens the shop while that slot is empty (B in Dota)
		if ii == 4 and h.inventory[4] == null:
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

## Alt+click (ground or minimap): a ping your team sees, with a sound and a ring on the ground and minimap.
var pings: Array = []                       # [{pos: Vector2, t: game time}]

func ping(p: Vector2) -> void:
	var now: float = game.world.time
	pings = pings.filter(func(x): return now - float(x.t) < 3.0)
	if pings.size() >= 5:
		return
	pings.append({"pos": p, "t": now})
	game.fx.ping(p)
	if game.audio:
		game.audio.ui("ui_click", -2.0)

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

## repeat: re-issued by holding the button. Repeats skip the ground marker and keep an order already aimed at the
## same unit (re-issuing an attack would restart its wind-up).
func _right_click(pos: Vector2, shift: bool, repeat := false) -> void:
	var w: SimWorld = game.world
	var h := hero()
	var ground: Vector2 = game.camera.ground_at(pos)
	var cs := _courier_selected()
	if cs:
		w.courier_move(h, ground)
		if not hero_selected() and not repeat:
			game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), false)
	if h == null or not h.alive or not hero_selected():
		return
	var id := pick(pos)
	var tgt := w.get_unit(id)
	if tgt and tgt != h:
		if tgt.team != h.team or w.orders.can_deny(h, tgt):
			if repeat and h.order == O.ATTACK_UNIT and h.order_target == tgt.id:
				return
			w.command(h.id, {"type": O.ATTACK_UNIT, "target": tgt.id, "queue": shift and not repeat})
			if not repeat:
				game.fx.marker(View.to3(tgt.pos, game.terrain.height_at(tgt.pos)), true)
			return
		if repeat and h.order == O.MOVE_TO_UNIT and h.order_target == tgt.id:
			return
		w.command(h.id, {"type": O.MOVE_TO_UNIT, "target": tgt.id, "queue": shift and not repeat})
		return
	if repeat and h.order == O.MOVE and h.order_point.distance_to(ground) < 24.0:
		return
	w.command(h.id, {"type": O.MOVE, "point": ground, "queue": shift and not repeat})
	if not repeat:
		game.fx.marker(View.to3(ground, game.terrain.height_at(ground)), false)
