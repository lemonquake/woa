extends SceneTree
## The item menu and the new HUD readouts through the real HUD (mouse events sent to the bottom panel): right click
## an item opens the menu; Lock, Unlock (the parts combine again), Disassemble (the parts come back locked), Move to
## Backpack, Sell; the element / damage type / armor type chips and the stats sheet. Saves captures.
##   godot --path . -s tests/tools/menu_probe.gd -- --hero=azrin [--out=work/shots/menu]

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var _fails := 0
var _passes := 0
var _out := "work/shots/menu"
var _big := false                          # --4k: a real 3840 x 2160 frame (a borderless window larger than the screen)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--4k":
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

func click(ctrl: Control, local: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = local
		e.global_position = ctrl.get_global_transform() * local
		ctrl._gui_input(e)

func shot(name: String) -> void:
	await frames(4)
	var dir := ProjectSettings.globalize_path("res://" + _out)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + "/" + name + ".png")
	print("saved ", name)

## Hold a tooltip on screen (the HUD clears it every frame) and capture it.
func tip_shot(at: Vector2, lines: Array, name: String) -> void:
	# the HUD clears tooltips every frame: pause it while the tooltip is held for the capture
	game.hud.set_process(false)
	game.hud.show_tip(at, lines)
	for i in 4:
		game.hud.tip.queue_redraw()
		await process_frame
	var dir := ProjectSettings.globalize_path("res://" + _out)
	DirAccess.make_dir_recursive_absolute(dir)
	await process_frame
	root.get_texture().get_image().save_png(dir + "/" + name + ".png")
	game.hud.set_process(true)
	print("saved ", name)

## The menu row for an action, or an empty rect.
func row(bottom, action: String) -> Rect2:
	for rw in bottom._menu.get("rows", []):
		if String(rw[1]) == action:
			return rw[0]
	return Rect2()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(1)
			return
	await frames(20)
	if _big:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		await frames(20)
		print("window ", DisplayServer.window_get_size())
	var w: SimWorld = game.world
	var hud = game.hud
	var b = hud.bottom
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for bot in w.bots.duplicate():
		w.bots.erase(bot)
	h.pos = w.map.shops[h.team]
	w.orders.clear(h)
	h.gold_unreliable = 30000
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	check(w.shop.buy(h, "spike_armor") == "", "bought Spike Armor")
	check(w.shop.buy(h, "spell_sword") == "", "bought Atuli")
	await frames(6)
	var slot := -1
	for i in 6:
		if h.inventory[i] != null and h.inventory[i].id == "spike_armor":
			slot = i
	var sr: Rect2 = b._item_rects[slot]
	# right click: the menu
	click(b, sr.get_center(), MOUSE_BUTTON_RIGHT)
	await frames(3)
	check(b.item_menu_open(), "right click on an item opens its menu")
	check(row(b, "sell").size.x > 0 and row(b, "disassemble").size.x > 0 and row(b, "lock").size.x > 0 and row(b, "move").size.x > 0,
		"the menu offers Sell, Disassemble, Lock and Move to Backpack")
	b.queue_redraw()
	await shot("menu_open")
	# Lock
	click(b, row(b, "lock").get_center())
	await frames(2)
	check(bool(h.inventory[slot].get("locked", false)) and not b.item_menu_open(), "Lock locks it and closes the menu")
	b.queue_redraw()
	await shot("locked_badge")
	# Unlock
	click(b, sr.get_center(), MOUSE_BUTTON_RIGHT)
	await frames(2)
	click(b, row(b, "lock").get_center())
	await frames(2)
	check(not bool(h.inventory[slot].get("locked", false)), "Unlock unlocks it")
	# Disassemble
	click(b, sr.get_center(), MOUSE_BUTTON_RIGHT)
	await frames(2)
	click(b, row(b, "disassemble").get_center())
	await frames(4)
	var ids: Array = h.inventory.filter(func(x): return x != null).map(func(x): return x.id)
	check(ids.has("broadsword") and ids.has("plate_vest") and ids.has("recipe_spike_armor") and not ids.has("spike_armor"),
		"Disassemble gives back the parts and the recipe (%s)" % [ids])
	var all_locked := true
	for it in h.inventory:
		if it != null and String(it.id) in ["broadsword", "plate_vest", "recipe_spike_armor"] and not bool(it.get("locked", false)):
			all_locked = false
	check(all_locked, "the parts are locked")
	await frames(20)
	check(not w.shop.owns(h, "spike_armor"), "they stay apart in the shop")
	# Move to Backpack
	var ps := -1
	for i in 6:
		if h.inventory[i] != null and h.inventory[i].id == "spell_sword":
			ps = i
	click(b, (b._item_rects[ps] as Rect2).get_center(), MOUSE_BUTTON_RIGHT)
	await frames(2)
	click(b, row(b, "move").get_center())
	await frames(2)
	var moved := false
	for i in range(6, 9):
		if h.inventory[i] != null and h.inventory[i].id == "spell_sword":
			moved = true
	check(moved, "Move to Backpack moves it")
	# Sell (the Plate Vest)
	var vs := -1
	for i in 9:
		if h.inventory[i] != null and h.inventory[i].id == "plate_vest":
			vs = i
	var g0 := h.gold()
	click(b, (b._item_rects[vs] as Rect2).get_center(), MOUSE_BUTTON_RIGHT)
	await frames(2)
	click(b, row(b, "sell").get_center())
	await frames(2)
	check(h.gold() > g0 and (h.inventory[vs] == null or h.inventory[vs].id != "plate_vest"), "Sell sells it (+%d gold)" % (h.gold() - g0))
	# a right click elsewhere closes it
	click(b, (b._item_rects[0] as Rect2).get_center(), MOUSE_BUTTON_RIGHT)
	await frames(2)
	var was_open: bool = b.item_menu_open()
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	hud._input(e)
	await frames(2)
	check(not was_open or not b.item_menu_open(), "Esc closes the menu")
	# the chips and the sheet
	b.queue_redraw()
	await frames(3)
	check(b._chips_end > b.CHIPS_X + 100.0, "the element, damage type and armor type chips are drawn")
	var sheet: Array = hud.unit_sheet(h)
	var text := " ".join(sheet.map(func(l): return String(l[0])))
	check(text.contains("Magic Amp") and text.contains("intelligence") and text.contains("Takes 125%") and text.contains("Fire"),
		"the stats sheet shows magic amp, its sources and the element's weaknesses")
	await tip_shot(b.get_global_transform() * Vector2(230, 80), sheet, "sheet")
	await tip_shot(b.get_global_transform() * Vector2(230, -6), hud.element_tip(h), "element_tip")
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
