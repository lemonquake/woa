extends SceneTree
## Item and courier flows through the real HUD controls (mouse events sent to the panels the player clicks):
## Shift + click in the shop, right click in To Buy (auto-buy into the waiting courier), drag an item onto the ground,
## right click to pick it up, learn a talent, a courier command button, the stash Grab All.
##   godot --path . -s tests/tools/item_flow_probe.gd -- --hero=sludge

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var _fails := 0
var _passes := 0

func _init() -> void:
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
		await physics_frame

func click(ctrl: Control, local: Vector2, button := MOUSE_BUTTON_LEFT, shift := false, pressed := true) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	e.position = local
	e.global_position = ctrl.get_global_transform() * local
	ctrl._gui_input(e)

func motion(ctrl: Control, local: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = local
	e.global_position = ctrl.get_global_transform() * local
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	ctrl._gui_input(e)

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
	var w: SimWorld = game.world
	var hud = game.hud
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	w.time = 60.0
	h.pos = Vector2(-1100, -900)
	w.orders.clear(h)
	h.gold_reliable = 0
	h.gold_unreliable = 0
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(10)
	# 1. Shift + click in the shop: Tough Band broken into its parts
	hud.toggle_shop()
	await process_frame
	hud.shop.queue_redraw()
	await process_frame
	await process_frame
	var r: Rect2 = hud.shop._rects.get("circlet", Rect2())
	check(r.size.x > 0.0, "the shop grid lists the Headband")
	hud.shop.tab = "upgrades"
	hud.shop.queue_redraw()
	await process_frame
	await process_frame
	var rb: Rect2 = hud.shop._rects.get("tough_band", Rect2())
	click(hud.shop, rb.get_center(), MOUSE_BUTTON_LEFT, true)
	var ids: Array = h.to_buy.map(func(e): return String(e.id))
	check(ids == ["circlet", "gauntlets", "recipe_tough_band"], "Shift + click Tough Band -> To Buy %s" % str(ids))
	hud.toggle_shop()
	# 2. right click the first To Buy row: auto-buy as soon as gold allows, into the courier waiting at the fountain
	await process_frame
	hud.to_buy.queue_redraw()
	await process_frame
	await process_frame
	var row: Rect2 = Rect2()
	for rr in hud.to_buy._rows:
		if int(rr[1]) == 0 and String(rr[2]) == "buy":
			row = rr[0]
	click(hud.to_buy, row.get_center(), MOUSE_BUTTON_RIGHT)
	check(bool(h.to_buy[0].auto), "right click sets the entry to auto-buy")
	await frames(20)
	check(h.to_buy.size() == 3, "no gold: still waiting")
	h.gold_unreliable = 150
	await frames(20)
	check(h.to_buy.size() == 3, "150 gold: still short of the Headband's 155")
	h.gold_unreliable = 155
	await frames(30)
	var c := w.get_unit(h.courier_id)
	check(h.to_buy.size() == 2 and c.inventory.any(func(x): return x != null and x.id == "circlet"), "auto-bought the Headband into the courier at the fountain (courier %s)" % str(c.inventory.filter(func(x): return x != null).map(func(x): return x.id)))
	# 3. drag an inventory item onto the ground: the hero walks over and drops it
	h.inventory[0] = w.shop.new_item("boots")
	h.inventory[0]["owner"] = h.id
	h.refresh_stats()
	var bp: Control = hud.bottom
	bp.queue_redraw()
	await process_frame
	var slot0: Rect2 = bp._item_rects[0]
	var target := h.pos + Vector2(250, 0)
	var scr: Vector2 = game.camera.cam.unproject_position(View.to3(target, game.terrain.height_at(target)))
	var local_target: Vector2 = bp.get_global_transform().affine_inverse() * scr
	click(bp, slot0.get_center())
	motion(bp, slot0.get_center() + Vector2(30, -30))
	motion(bp, local_target)
	click(bp, local_target, MOUSE_BUTTON_LEFT, false, false)
	await frames(90)
	check(h.inventory[0] == null and w.ground_items.size() == 1, "dragged Running Shoes onto the ground and dropped them (%d on the ground)" % w.ground_items.size())
	# 4. right click the item on the ground: picked up again
	if w.ground_items.size() == 1:
		await process_frame
		var gpos: Vector2 = w.ground_items[0].pos
		var gs: Vector2 = game.camera.cam.unproject_position(View.to3(gpos, game.terrain.height_at(gpos)) + Vector3(0, 0.35, 0))
		game.input._right_click(gs, false)
		await frames(90)
		check(w.ground_items.is_empty() and h.inventory.any(func(x): return x != null and x.id == "boots"), "right click picks it up")
	# 5. a talent from the tree (level 10, one ability point)
	w.combat.give_xp(h, float(C.XP_TABLE[9]) - h.xp)
	h.ability_points = 1
	await process_frame
	click(bp, bp._talent_rect.get_center())
	check(bp.talents_open, "the talent button opens the tree")
	bp.queue_redraw()
	await process_frame
	await process_frame
	var trow: Rect2 = Rect2()
	for tr in bp._talent_rows:
		if int(tr[1]) == 0 and int(tr[2]) == 1:
			trow = tr[0]
	click(bp, trow.get_center())
	check(String(h.talents.get(0, "")) == "sludge_armor", "clicked +5 Armor at level 10 (%s)" % str(h.talents))
	# 6. the courier panel: Deliver button
	game.input.select([c.id])
	bp.queue_redraw()
	await process_frame
	await process_frame
	click(bp, (bp._cmd_rects[3] as Rect2).get_center())
	check(c.courier_state in ["collect", "fetch", "deliver"], "courier Deliver button (state %s)" % c.courier_state)
	await frames(30 * 25)
	check(h.inventory.any(func(x): return x != null and x.id == "circlet"), "the courier delivered the Headband")
	game.input.select([h.id])
	# 7. Grab All in the base
	h.pos = w.map.fountains[0] + Vector2(200, 200)
	await frames(20)
	h.stash[0] = w.shop.new_item("clarity")
	bp.queue_redraw()
	await process_frame
	await process_frame
	click(bp, bp._grab_rect.get_center())
	check(h.stash[0] == null and h.inventory.any(func(x): return x != null and x.id == "clarity"), "Grab All took the stash")
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
