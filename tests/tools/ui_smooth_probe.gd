extends SceneTree
## The interface's open-and-close behaviour through real input events (pushed into the window, so they pass every
## _input, GUI and _unhandled_input handler as a player's would): the talent tree closes on a click away, Esc or another
## unit; the item menu ignores the wheel and closes on a click away; the pause menu takes the keys and resumes on a
## click outside; Options closes on a click outside; screens go back on Esc with a fade; the right-click player menu
## passes a right click on and swallows a left click; border packs switch, fall back and load from user://.
##   WOA_RANKED_FILE=user://probe_ranked.json godot --path . -s tests/tools/ui_smooth_probe.gd -- --hero=sludge [--out=dir]

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var _fails := 0
var _passes := 0
var _out := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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

## A press and release at a point on the screen (canvas coordinates) through the whole input path.
func mouse(at: Vector2, button := MOUSE_BUTTON_LEFT, release := true) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	root.push_input(m, true)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	e.global_position = at
	if button == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	if release and button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var u := e.duplicate() as InputEventMouseButton
		u.pressed = false
		u.button_mask = 0
		root.push_input(u, true)

func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	root.push_input(e, true)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	root.push_input(u, true)

func at_ctrl(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local

func shot(name: String) -> void:
	if _out == "":
		return
	await frames(3)
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("FAIL the match never booted")
			quit(1)
			return
	await frames(20)
	var w: SimWorld = game.world
	var hud = game.hud
	var bp = hud.bottom
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	w.time = 60.0
	h.pos = Vector2(-1100, -900)
	w.orders.clear(h)
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	w.combat.give_xp(h, float(C.XP_TABLE[9]) - h.xp)
	h.ability_points = 1
	var ids := ["boots", "circlet", "clarity"]
	for id in SimData.items():
		if ids.size() >= 6:
			break
		if not SimData.item(id).is_empty() and not String(id).begins_with("recipe") and not ids.has(id) and int(SimData.item(id).get("cost", 0)) > 400:
			ids.append(id)
	for i in 6:
		h.inventory[i] = w.shop.new_item(ids[i])
	await frames(10)
	var vs: Vector2 = root.get_visible_rect().size
	var world_pt := Vector2(vs.x * 0.5, vs.y * 0.35)

	# ---- the talent tree ----------------------------------------------------------------------------------------
	mouse(at_ctrl(bp, bp._talent_rect.get_center()))
	await frames(3)
	check(bp.talents_open, "the talent button opens the tree")
	await shot("talents_open")
	mouse(at_ctrl(bp, bp._talent_panel.position + Vector2(20, 8)))
	await frames(3)
	check(bp.talents_open, "a click on the tree's own panel keeps it open")
	mouse(world_pt)
	await frames(3)
	check(not bp.talents_open, "a click on the world closes the tree")
	mouse(at_ctrl(bp, bp._talent_rect.get_center()))
	await frames(3)
	mouse(at_ctrl(hud.minimap, hud.minimap.size * 0.5))
	await frames(3)
	check(not bp.talents_open, "a click on the minimap closes the tree")
	mouse(at_ctrl(bp, bp._talent_rect.get_center()))
	await frames(3)
	key(KEY_ESCAPE)
	await frames(3)
	check(not bp.talents_open, "Esc closes the tree")
	check(not game.menus.is_open(), "the same Esc does not open the pause menu")
	mouse(at_ctrl(bp, bp._talent_rect.get_center()))
	await frames(3)
	var creep: SimUnit = null
	for u in w.units:
		if u.alive and not u.is_hero() and u.team != h.team:
			creep = u
			break
	if creep != null:
		game.input.select([creep.id])
		await frames(4)
		check(not bp.talents_open and bp._talent_rows.is_empty(), "showing another unit closes the tree and clears its click area")
		game.input.select([h.id])
		await frames(3)
	mouse(at_ctrl(bp, bp._talent_rect.get_center()))
	await frames(3)
	var trow := Rect2()
	for tr in bp._talent_rows:
		if int(tr[1]) == 0 and int(tr[2]) == 0:
			trow = tr[0]
	mouse(at_ctrl(bp, trow.get_center()))
	await frames(3)
	check(h.talents.has(0), "a talent is still learned by clicking its row (%s)" % str(h.talents))
	mouse(world_pt)
	await frames(2)

	# ---- the item menu --------------------------------------------------------------------------------------------
	mouse(at_ctrl(bp, (bp._item_rects[0] as Rect2).get_center()), MOUSE_BUTTON_RIGHT)
	await frames(3)
	check(bp.item_menu_open(), "a right click on an item opens its menu")
	await shot("item_menu")
	mouse(world_pt, MOUSE_BUTTON_WHEEL_UP, false)
	await frames(2)
	check(bp.item_menu_open(), "the mouse wheel leaves the item menu open")
	mouse(world_pt)
	await frames(3)
	check(not bp.item_menu_open(), "a click away closes the item menu")

	# ---- the shop and framed icons --------------------------------------------------------------------------------
	hud.toggle_shop()
	await frames(4)
	await shot("shop")
	mouse(world_pt)
	await frames(3)
	check(not hud.shop.visible, "a click on the world closes the shop")

	# ---- the pause menu -------------------------------------------------------------------------------------------
	key(KEY_ESCAPE)
	await frames(3)
	check(game.menus.is_open() and w.paused, "Esc opens the pause menu and pauses")
	await shot("pause")
	key(KEY_ENTER)
	await frames(3)
	check(not hud.chat.is_open(), "game keys wait while the pause menu is open (Enter opens no chat)")
	mouse(Vector2(30, vs.y * 0.5))
	await frames(4)
	check(not game.menus.is_open() and not w.paused, "a click outside the pause menu resumes")
	key(KEY_ESCAPE)
	await frames(3)
	game.menus._open_options()
	await frames(4)
	check(game.menus._options != null, "Options opens from the pause menu")
	mouse(Vector2(20, 20))
	await frames(4)
	check(game.menus._options == null and game.menus._pause.visible, "a click outside Options closes it, back to the pause menu")
	key(KEY_ESCAPE)
	await frames(3)
	check(not game.menus.is_open(), "Esc resumes")

	# ---- border packs ---------------------------------------------------------------------------------------------
	check(IconBorder.ids().has("default") and IconBorder.ids().has("plain"), "both shipped border packs are found (%s)" % str(IconBorder.ids()))
	check(IconBorder.current() == "default", "the default border is in use")
	Options.set_value("icon_border", "plain")
	check(IconBorder.current() == "plain", "switching to Plain takes effect at once")
	Options.set_value("icon_border", "no_such_pack")
	check(IconBorder.current() == "default", "a missing pack falls back to the default")
	var udir := "user://borders/probe_pack/"
	DirAccess.make_dir_recursive_absolute(udir)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 64:
		for j in 4:
			img.set_pixel(i, j, Color.RED)
			img.set_pixel(i, 63 - j, Color.RED)
			img.set_pixel(j, i, Color.RED)
			img.set_pixel(63 - j, i, Color.RED)
	img.save_png(udir + "skill.png")
	var f := FileAccess.open(udir + "border.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "Probe Red", "scale": 1, "ref": 64, "pieces": {"skill": {"file": "skill.png", "margins": [8, 8, 8, 8], "outset": 2}}}))
	f.close()
	IconBorder.reload()
	Options.set_value("icon_border", "probe_pack")
	check(IconBorder.current() == "probe_pack" and IconBorder.pack_name("probe_pack") == "Probe Red", "a pack dropped in user://borders loads")
	check(IconBorder.outset("item", 64) == 2.0, "a kind the pack lacks (item) falls back to its skill frame")
	bp.queue_redraw()
	await frames(3)
	await shot("user_pack")
	Options.set_value("icon_border", "default")
	for fn in ["skill.png", "border.json"]:
		DirAccess.remove_absolute(udir + fn)
	DirAccess.remove_absolute(udir)
	IconBorder.reload()

	# ---- screens: fades and Esc -----------------------------------------------------------------------------------
	Options.go(self, "res://src/ui/main_menu.tscn")
	await frames(2)
	var agent: CanvasLayer = root.get_node_or_null("OptionsAgent")
	check(agent != null and agent._going, "leaving the match fades out")
	await _wait_scene("main_menu")
	await frames(30)
	check(agent != null and not agent._going and agent._fade.color.a < 0.01, "the main menu fades back in")
	var mm := current_scene
	mm.add_child(OptionsPanel.new())
	await frames(3)
	var focus_before: int = mm._focus
	key(KEY_DOWN)
	await frames(2)
	check(mm._focus == focus_before, "the menu behind Options ignores the arrow keys")
	key(KEY_ESCAPE)
	await frames(3)
	check(not mm.get_children().any(func(c): return c is OptionsPanel), "Esc closes Options")
	Options.go(self, "res://src/ui/hero_select.tscn")
	await _wait_scene("hero_select")
	await frames(40)
	key(KEY_ESCAPE)
	await _wait_scene("main_menu")
	check(String(current_scene.scene_file_path).contains("main_menu"), "Esc on Hero Select goes back to the main menu")
	Options.go(self, "res://src/ui/ranked_menu.tscn")
	await _wait_scene("ranked_menu")
	await frames(40)
	var rm := current_scene
	var pid := ""
	for p in Ranked.bots():
		if String(p.get("id", "")) != "me":
			pid = String(p.id)
			break
	if pid != "":
		PlayerMenu.open(rm, pid, Vector2(600, 400))
		await frames(3)
		check(get_nodes_in_group("player_menu").size() == 1, "the player menu opens")
		mouse(Vector2(1500, 900), MOUSE_BUTTON_WHEEL_DOWN, false)
		await frames(2)
		check(get_nodes_in_group("player_menu").size() == 1, "the wheel leaves the player menu open")
		mouse(Vector2(1500, 900))
		await frames(3)
		check(get_nodes_in_group("player_menu").size() == 0, "a left click outside closes the player menu")
		PlayerMenu.open(rm, pid, Vector2(600, 400))
		await frames(3)
		key(KEY_ESCAPE)
		await frames(3)
		check(get_nodes_in_group("player_menu").size() == 0 and current_scene == rm, "Esc closes the player menu and stays on Ranked")
	key(KEY_ESCAPE)
	await _wait_scene("main_menu")
	check(String(current_scene.scene_file_path).contains("main_menu"), "Esc on Ranked goes back to the main menu")
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _wait_scene(part: String) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		if current_scene != null and String(current_scene.scene_file_path).contains(part):
			return
