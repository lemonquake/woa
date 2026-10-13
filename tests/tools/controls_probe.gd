extends SceneTree
## The control and HUD changes of 2026-10-13 d, through the real game window (prints PASS / FAIL, saves captures):
## the cursor kept inside the window (Borderless / Fullscreen, or Windowed with the lock), edge panning with the cursor
## pinned at the edge, holding Stop, the shop closing on a click elsewhere, the "," key buying a Teleport Scroll,
## regeneration with its bonus, and the overhead disable timers, hex sheep and a critical strike number.
##   godot --path . -s tests/tools/controls_probe.gd -- [--out=work/shots]

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var _fails := 0
var _passes := 0
var _out := "work/shots"
var _big := false                          # --4k: a real 3840 x 2160 window (the cursor checks are skipped)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a == "--4k":
			_big = true
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS ", msg)
	else:
		_fails += 1
		print("FAIL ", msg)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func mouse(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out)
	img.save_png("%s/%s.png" % [_out, name])
	print("saved %s/%s.png" % [_out, name])

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("FAIL the match did not load")
			quit(1)
			return
	await frames(20)
	var w: SimWorld = game.world
	var hud = game.hud
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	w.time = 60.0
	DisplayServer.window_move_to_foreground()
	await frames(10)
	var focused := DisplayServer.window_is_focused()
	print("window focused: ", focused)
	if _big:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		_out = _out.path_join("4k")
		await frames(20)
		print("window ", DisplayServer.window_get_size(), " viewport ", root.get_viewport().get_texture().get_size())
		await _rest(w, hud, h)
		return

	# ---- 1. Cursor lock ----------------------------------------------------------------------------------------------
	var saved_mode := int(Options.get_value("window_mode"))
	var saved_lock := bool(Options.get_value("lock_cursor"))
	Options.set_value("window_mode", 0)
	Options.set_value("lock_cursor", false)
	Options.apply_cursor()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Windowed without the lock: the cursor is free")
	Options.set_value("lock_cursor", true)
	Options.apply_cursor()
	check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED, "Windowed with the lock: the cursor is confined")
	Options.set_value("lock_cursor", false)
	Options.set_value("window_mode", 1)
	Options.apply_cursor()
	check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED, "Borderless: the cursor is confined")
	Options.set_value("window_mode", 2)
	Options.apply_cursor()
	check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED, "Fullscreen: the cursor is confined")
	# the OS clamps the cursor into the window: warp it far outside and read where it really is
	Options.set_value("window_mode", 0)
	Options.set_value("lock_cursor", true)
	Options.apply_cursor()
	await frames(5)
	var wr := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	Input.warp_mouse(Vector2(-400, 300))
	await frames(5)
	var mp := DisplayServer.mouse_get_position()
	print("window ", wr, " cursor after warping outside: ", mp)
	if focused:
		check(wr.grow(1).has_point(mp), "a confined cursor cannot leave the window (OS clamp)")
	else:
		print("SKIP OS clamp check: the window has no focus (Windows applies the clip to the focused window only)")
	# ---- 2. Edge pan with the cursor pinned at the edge --------------------------------------------------------------
	game.camera.edge_pan_enabled = true
	game.camera.set_process(true)
	var before: Vector3 = game.camera.target
	var right := Vector2(wr.size.x - 1, wr.size.y * 0.5)
	Input.warp_mouse(right)
	await frames(2)
	var ed: Vector2 = game.camera.edge_dir()
	print("edge_dir at the right edge: ", ed)
	await frames(30)
	if focused:
		check(ed.x > 0.5, "the cursor at the right edge pans right")
		check(game.camera.target.x > before.x + 0.5, "the camera moved right (%.2f -> %.2f)" % [before.x, game.camera.target.x])
		Input.warp_mouse(right + Vector2(300, 0))
		await frames(3)
		check(game.camera.edge_dir().x > 0.5, "pushing past the edge keeps panning (the cursor stays pinned)")
	else:
		print("SKIP edge pan checks: the window has no focus")
	Input.warp_mouse(Vector2(wr.size) * 0.5)
	Options.set_value("window_mode", saved_mode)
	Options.set_value("lock_cursor", saved_lock)
	Options.apply_cursor()
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(5)

	await _rest(w, hud, h)

## Everything after the cursor checks (also run at 4K).
func _rest(w: SimWorld, hud, h: SimUnit) -> void:
	# ---- 3. Holding Stop -------------------------------------------------------------------------------------------
	h.pos = Vector2(-1100, -900)
	w.orders.clear(h)
	game.input.select([h.id])
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(1500, 0)})
	await frames(3)
	check(h.order == O.MOVE, "the hero walks")
	var skey: int = Keybinds.key("stop") & ~Keybinds.MODS
	key(skey, true)
	await frames(3)
	check(h.order == O.NONE and h.is_idle(), "Stop pressed: the hero stops")
	# a right click while Stop is held is refused
	var centre := root.get_viewport().get_visible_rect().size * 0.5
	game.input._right_click(centre + Vector2(200, 0), false)
	await frames(2)
	check(h.order == O.NONE, "orders are refused while Stop is held")
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(800, 0)})
	await frames(3)
	check(h.order == O.NONE, "an order that slipped through is stopped again the next frame")
	await frames(25)
	key(skey, false)
	await frames(3)
	check(h.no_acquire, "held over 0.35 s: a hard stop stays (no auto-attack)")
	game.input._right_click(centre + Vector2(200, 0), false)
	await frames(2)
	check(h.order == O.MOVE, "after release, orders work again")
	w.orders.clear(h)

	# ---- 4. The shop closes on a click elsewhere ---------------------------------------------------------------------
	hud.toggle_shop()
	await frames(2)
	check(hud.shop.visible, "the shop opens")
	var in_shop: Vector2 = hud.shop.get_global_rect().get_center()
	hud._input(_btn(in_shop, MOUSE_BUTTON_LEFT))
	check(hud.shop.visible, "a click inside the shop keeps it open")
	hud._input(_btn(hud.bottom.get_global_rect().get_center(), MOUSE_BUTTON_LEFT))
	check(hud.shop.visible, "a click on the inventory panel keeps it open")
	hud._input(_btn(centre + Vector2(-400, -200), MOUSE_BUTTON_LEFT))
	check(not hud.shop.visible, "a click on the world closes it")
	hud.toggle_shop()
	hud._input(_btn(centre + Vector2(-400, -200), MOUSE_BUTTON_RIGHT))
	check(not hud.shop.visible, "a right click on the world closes it too")
	hud.toggle_shop()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud._input(esc)
	check(not hud.shop.visible, "Esc closes it")

	# ---- 5. The "," key buys a Teleport Scroll --------------------------------------------------------------------
	h.gold_unreliable = 500
	var g0 := h.gold()
	var n0 := h.tp_charges
	key(KEY_COMMA, true)
	await frames(2)
	key(KEY_COMMA, false)
	await frames(2)
	check(w.shop.tp_owned(h) == n0 + 1 and h.tp_charges == n0, "comma bought a Teleport Scroll (away from the shop: into the stash)")
	check(g0 - h.gold() >= 98 and g0 - h.gold() <= 100, "for 100 gold (%d spent, passive gold aside)" % (g0 - h.gold()))
	h.pos = game.map.fountains[h.team] + Vector2(300, 300)
	await frames(60)                         # the shop looks for arrivals every half second
	check(h.tp_charges == n0 + 1, "at the base it moves into the Teleport slot")

	# ---- 6. Regeneration with its bonus, at the fountain ---------------------------------------------------------
	h.hp = h.max_hp * 0.4
	h.mana = h.max_mana * 0.3
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(10)
	var r := w.regen_rates(h)
	check(r.x - r.z > h.max_hp * 0.04, "the fountain shows as bonus health regen (+%.1f)" % (r.x - r.z))
	await shot("ctl_regen_fountain")

	# ---- 7. Disables: timer bars, sheep, critical number ---------------------------------------------------------
	h.pos = Vector2(-1100, -900)
	h.hp = h.max_hp
	var spot := h.pos + Vector2(250, 0)
	var foe_id := -1
	for u in w.heroes:
		if u.team != h.team:
			foe_id = u.id
	var foe: SimUnit = w.get_unit(foe_id)
	var creep := w.spawn("dusk_melee", 1 - h.team, spot + Vector2(0, 250))
	creep.order = O.HOLD
	if foe:
		foe.pos = spot
		w.orders.clear(foe)
		w.status.apply(foe, h.id, h.team, {"id": "bashed", "stun": true, "dur": 1.2, "fx": "stun"}, true)
	w.status.apply(creep, h.id, h.team, {"id": "hex_staff", "hex": true, "dur": 2.8, "fx": "hex"})
	game.camera.focus(View.to3(spot, game.terrain.height_at(spot)))
	await frames(12)
	var info: Dictionary = w.status.disable_info(foe) if foe else {}
	check(not info.is_empty() and String(info.kind) == "Stunned", "the enemy hero shows a stun timer")
	check(not w.status.disable_info(creep).is_empty(), "the hexed creep shows a timer")
	await shot("ctl_disable_bars")
	if foe:
		w.status.apply(foe, h.id, h.team, {"id": "root_staff", "root": true, "dur": 2.0, "fx": "root"})
		w.status.apply(foe, h.id, h.team, {"id": "halberd", "disarm": true, "dur": 3.5, "fx": "disarm"})
	# a real critical strike: the next roll procs (its pseudo-random counter is full) and the attack lands on the creep
	var crit_seen := [false]
	var it := w.shop.new_item("crit_bow")
	h.inventory[0] = it
	h.refresh_stats()
	h.prd["crit:crit_bow"] = 100
	creep.remove_modifier("hex_staff")
	creep.refresh_stats()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": creep.id})
	for i in 90:
		await process_frame
		if h.prd.get("crit:crit_bow", 100) == 0 and h.atk_phase == SimUnit.AtkPhase.BACKSWING:
			crit_seen[0] = true
			break
	check(crit_seen[0], "the hero's attack started with a critical strike and landed")
	await frames(4)
	await shot("ctl_crit_root_disarm")
	# ---- 8. Orbs: a power orb in the river, taken with a right click ------------------------------------------------
	creep.alive = false
	var spot2: Vector2 = w.orbs.spots.power[0]
	h.pos = spot2 + Vector2(-350, -150)
	w.orders.clear(h)
	w.orbs.orbs.clear()
	w.orbs._spawn("speed", spot2, "power")
	w.orbs._spawn("gold", spot2 + Vector2(250, -250), "power")
	game.camera.focus(View.to3(spot2, game.terrain.height_at(spot2)))
	await frames(20)
	await shot("ctl_orbs")
	var oid: int = w.orbs.orbs[0].id
	var o3: Vector3 = game.orb_view._nodes[oid].global_position + Vector3(0, 0.95, 0)
	var sp: Vector2 = game.camera.cam.unproject_position(o3)
	check(game.orb_view.pick(game.camera.cam, sp) == oid, "the orb is picked under the cursor")
	game.input._right_click(sp, false)
	await frames(2)
	check(h.order == O.PICKUP_ORB, "a right click on the orb orders the hero to take it")
	for i in 150:
		await process_frame
		if w.orbs.get_orb(oid).is_empty():
			break
	check(w.orbs.get_orb(oid).is_empty() and not h.get_modifier("orb_speed").is_empty(), "the hero took the Speed Orb")
	await frames(10)
	await shot("ctl_orb_taken")
	# ---- 8b. The shop with the new items -----------------------------------------------------------------------
	h.pos = game.map.fountains[h.team] + Vector2(300, 300)
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	hud.shop.visible = true
	hud.shop.tab = "upgrades"
	hud.shop.selected = "stun_blade"
	await frames(10)
	await shot("ctl_shop")
	hud.shop.visible = false
	h.pos = spot2 + Vector2(-350, -150)
	# ---- 9. The Ogre's Smash wind-up ------------------------------------------------------------------------------
	var ogre := w.spawn("ogre_brute", C.NEUTRAL, h.pos + Vector2(200, 0))
	ogre.home = ogre.pos
	ogre.neutral_state = 1
	ogre.atk_target = h.id
	w.orders.clear(h)
	h.hp = h.max_hp
	w.ai._neutral_cast(ogre, h)
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(40)
	check(String(ogre.cast_ability) == "smash", "the Ogre winds up Smash")
	await shot("ctl_smash_warning")
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _btn(pos: Vector2, button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pos
	e.global_position = pos
	return e
