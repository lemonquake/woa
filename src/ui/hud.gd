extends Control
## The match HUD, laid out like Dota's: bottom panel (portrait, stats, abilities, health / mana, inventory, gold),
## minimap with fog and camera frame, top bar (clock, day / night, kills), shop, tooltips and announcements.
## It reads the simulation and issues the same commands as the keyboard (InputController).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const K = C.Kind
const U = preload("res://src/ui/ui_kit.gd")

var game: Node
var bottom: Control
var minimap: Control
var topbar: Control
var shop: Control
var tip: Control
var to_buy: Control
var kill_feed: KillFeed
var scoreboard: Scoreboard
var debug: DebugPanel
var chat: ChatPanel
var portrait_vp: SubViewport
var portrait_cam: Camera3D
var _msg := ""
var _msg_t := 0.0
var _announce := ""
var _announce_sub := ""
var _announce_t := 0.0
var _tip_lines: Array = []                 # [[text, size, color, kind]]
var _tip_at := Vector2.ZERO
var _redraw_t := 0.0
var _last_tip: Array = []
var _portrait_down := -1.0                 # when the portrait was pressed (click: centre camera, hold: follow)
const PORTRAIT_HOLD := 0.3

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom = BottomPanel.new()
	bottom.hud = self
	add_child(bottom)
	minimap = Minimap.new()
	minimap.hud = self
	add_child(minimap)
	topbar = TopBar.new()
	topbar.hud = self
	add_child(topbar)
	shop = ShopPanel.new()
	shop.hud = self
	shop.visible = false
	add_child(shop)
	to_buy = ToBuyPanel.new()
	to_buy.hud = self
	add_child(to_buy)
	kill_feed = KillFeed.new()
	kill_feed.hud = self
	add_child(kill_feed)
	scoreboard = Scoreboard.new()
	scoreboard.hud = self
	add_child(scoreboard)
	debug = DebugPanel.new()
	debug.game = game
	add_child(debug)
	chat = ChatPanel.new()
	chat.hud = self
	add_child(chat)
	tip = Tip.new()
	tip.hud = self
	add_child(tip)
	_portrait()
	bottom.make_overlay()

func _portrait() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.size = Vector2(166, 170)
	bottom.add_child(svc)
	bottom.portrait_box = svc
	portrait_vp = SubViewport.new()
	portrait_vp.size = Vector2i(166, 170)
	portrait_vp.own_world_3d = false
	portrait_vp.transparent_bg = false
	portrait_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(portrait_vp)
	portrait_cam = Camera3D.new()
	portrait_cam.fov = 26.0
	portrait_cam.near = 0.05
	portrait_cam.far = 30.0
	portrait_cam.cull_mask = 1
	portrait_vp.add_child(portrait_cam)

func hero() -> SimUnit:
	return game.world.get_unit(game.player_hero_id) if game and game.world else null

## The hero the bottom panel shows: the selected hero (any team), otherwise your own.
func shown() -> SimUnit:
	if game == null or game.world == null:
		return null
	var s: SimUnit = game.world.get_unit(game.selected_id)
	if s != null and s.is_hero():
		return s
	return hero()

## Portrait: a click selects your hero and centres the camera on it; holding it keeps the camera on the hero.
func portrait_press() -> void:
	_portrait_down = Time.get_ticks_msec() / 1000.0
	game.input.select([game.player_hero_id])

func portrait_release() -> void:
	if _portrait_down < 0.0:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _portrait_down
	_portrait_down = -1.0
	var h := hero()
	if held < PORTRAIT_HOLD and h and h.alive:
		game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))

func _follow_portrait(dt: float) -> void:
	if _portrait_down < 0.0:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		portrait_release()
		return
	if Time.get_ticks_msec() / 1000.0 - _portrait_down >= PORTRAIT_HOLD:
		var h := hero()
		if h and h.alive:
			var p := View.to3(h.pos, game.terrain.height_at(h.pos))
			game.camera.target = game.camera.target.lerp(p, 1.0 - exp(-dt * 14.0))

func _process(dt: float) -> void:
	_follow_portrait(dt)
	_msg_t = maxf(0.0, _msg_t - dt)
	_announce_t = maxf(0.0, _announce_t - dt)
	var vs := get_viewport_rect().size
	bottom.position = Vector2(roundf((vs.x - BottomPanel.W) * 0.5), vs.y - BottomPanel.H)
	minimap.position = Vector2(6, vs.y - Minimap.S - 6)
	chat.position = Vector2(14, minimap.position.y - chat.size.y - 56)
	topbar.position = Vector2(roundf((vs.x - TopBar.W) * 0.5), 0)
	shop.position = Vector2(vs.x - ShopPanel.W - 10, vs.y - BottomPanel.H - ShopPanel.H - 8)
	# To Buy: at the right edge above the bottom panel, or left of the shop while it is open
	to_buy.visible = to_buy.wanted()
	var tbx: float = shop.position.x - ToBuyPanel.W - 8 if shop.visible else vs.x - ToBuyPanel.W - 10
	to_buy.position = Vector2(tbx, vs.y - BottomPanel.H - 72 - to_buy.size.y)
	_update_portrait()
	_tip_lines = []
	queue_redraw()
	# panels redraw at 20 Hz (their contents change slowly); the tooltip follows the mouse every frame
	_redraw_t -= dt
	if _redraw_t <= 0.0:
		_redraw_t = 0.05
		for c in [bottom, minimap, topbar, shop]:
			c.queue_redraw()
	tip.queue_redraw()

func _update_portrait() -> void:
	var h := shown()
	if h == null:
		return
	var v = game.views.get(h.id)
	if v == null or not (v is UnitView) or v.skeleton == null:
		return
	var sk: Skeleton3D = v.skeleton
	var bi := sk.find_bone("head")
	if bi < 0:
		return
	var head: Vector3 = (sk.global_transform * sk.get_bone_global_pose(bi)).origin + Vector3(0, 0.06, 0)
	var fwd: Vector3 = -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	portrait_cam.global_position = head + fwd * 1.15 + side * 0.25 + Vector3(0, 0.02, 0)
	portrait_cam.look_at(head - Vector3(0, 0.05, 0), Vector3.UP)

func _draw() -> void:
	var vs := get_viewport_rect().size
	if _msg_t > 0.0:
		var a := clampf(_msg_t / 0.5, 0.0, 1.0)
		U.text_c(self, _msg, Vector2(vs.x * 0.5, vs.y - BottomPanel.H - 40), 22, Color(_msg_col, a), "bold")
	_unit_card()
	var h := hero()
	if h and not h.alive:
		var t := maxf(0.0, h.respawn_at - game.world.time)
		U.text_c(self, "Respawning in %d" % ceili(t), Vector2(vs.x * 0.5, vs.y * 0.42), 34, Color(1, 1, 1, 0.92), "title")
	if h and h.alive and not h.channel.is_empty():
		_channel_bar(h, vs)
	if h and h.alive and (Input.is_key_pressed(KEY_SHIFT) or game.args.has("showqueue")) and game.input and game.input.hero_selected():
		_queue_waypoints(h)
	if game.input and game.input.targeting != "":
		var team: String = game.input.targeting_team()
		var lab: String = "Attack" if game.input.targeting == "attack" else ("Choose an enemy" if team == "enemy" else ("Choose a target" if team == "any" else "Choose an ally or a place"))
		var tcol := Color(1.0, 0.55, 0.5) if team == "enemy" else Color(0.6, 1.0, 0.6)
		U.text(self, lab, get_viewport().get_mouse_position() + Vector2(26, 34), 15, tcol, "bold")

## Shift held: the hero's current order and its queue as waypoints joined by a line, as in Dota (green move,
## red attack, blue spell or item, gold hold), numbered in the order they will run.
func _queue_waypoints(h: SimUnit) -> void:
	var w: SimWorld = game.world
	var cam: Camera3D = game.camera.cam
	var orders: Array = []
	if h.order != O.NONE:
		orders.append({"type": h.order, "target": h.order_target, "point": h.order_point, "ability": h.order_ability})
	orders.append_array(h.order_queue)
	if orders.is_empty():
		return
	var prev := h.pos
	var prev_s := cam.unproject_position(View.to3(h.pos, game.terrain.height_at(h.pos)))
	var n := 0
	for o in orders:
		var type := int(o.get("type", O.NONE))
		var p := prev
		var t := w.get_unit(int(o.get("target", -1)))
		if type in [O.ATTACK_UNIT, O.MOVE_TO_UNIT, O.CAST_UNIT] and t:
			p = t.pos
		elif type in [O.MOVE, O.ATTACK_MOVE, O.CAST_POINT]:
			p = o.get("point", prev)
		var col := Color(0.35, 1.0, 0.45)
		if type in [O.ATTACK_UNIT, O.ATTACK_MOVE]:
			col = Color(1.0, 0.35, 0.3)
		elif type in [O.CAST_NO_TARGET, O.CAST_POINT, O.CAST_UNIT]:
			col = Color(0.4, 0.7, 1.0)
		elif type == O.HOLD:
			col = Color(1.0, 0.82, 0.3)
		var wp := View.to3(p, game.terrain.height_at(p))
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		n += 1
		if sp.distance_to(prev_s) > 4.0:
			draw_dashed_line(prev_s, sp, Color(col, 0.9), 3.0, 10.0)
		draw_circle(sp, 13.0, Color(0, 0, 0, 0.55))
		draw_arc(sp, 13.0, 0, TAU, 24, col, 3.0)
		var aid := String(o.get("ability", ""))
		var ic: Texture2D = U.ability_icon(aid) if aid != "" and aid != "tp" else null
		if ic:
			draw_texture_rect(ic, Rect2(sp + Vector2(10, -26), Vector2(20, 20)), false)
		U.text_c(self, str(n), sp + Vector2(0, 6), 15, Color(1, 1, 1), "bold")
		prev = p
		prev_s = sp

## Dota's channel bar: the ability being channelled and the time left, just above the bottom panel.
func _channel_bar(h: SimUnit, vs: Vector2) -> void:
	var aid := String(h.channel.ability)
	var total := C.TP_CHANNEL if aid == "tp" else float(h.channel.get("dur", 1.0))
	var left := maxf(0.0, float(h.channel.until) - game.world.time)
	var name := "Teleport" if aid == "tp" else String(SimData.ability(aid).get("name", aid))
	var r := Rect2(vs.x * 0.5 - 160, vs.y - BottomPanel.H - 58, 320, 18)
	U.panel(self, r.grow(4), U.GOLD_DIM, 4)
	U.bar(self, r, 1.0 - left / maxf(0.01, total), Color(0.95, 0.78, 0.3))
	U.text_c(self, "%s   %.1f" % [name, left], r.get_center() + Vector2(0, 6), 14, U.TEXT, "bold")

## Info card for a selected unit that is not your hero (creeps, towers, neutrals, enemy heroes).
func _unit_card() -> void:
	var w: SimWorld = game.world
	var sel: SimUnit = w.get_unit(game.selected_id)
	if sel == null or sel.id == game.player_hero_id or not sel.alive or sel.is_hero():
		return
	var mh := hero()
	if mh and sel.id == mh.courier_id:
		return
	var vs := get_viewport_rect().size
	var r := Rect2(vs.x * 0.5 - 230, vs.y - BottomPanel.H - 92, 460, 80)
	U.panel(self, r, U.GOLD_DIM, 6)
	var col := U.DAWN if sel.team == 0 else (U.DUSK if sel.team == 1 else Color(0.95, 0.8, 0.4))
	U.text(self, String(sel.look.get("display_name", sel.name)), r.position + Vector2(14, 26), 18, col, "title")
	var lvl := " level %d" % sel.level if sel.is_hero() else ""
	U.text_r(self, SimConst.TEAM_NAMES[sel.team] + lvl, Vector2(r.end.x - 14, r.position.y + 24), 13, U.TEXT_DIM, "body")
	U.bar(self, Rect2(r.position + Vector2(14, 36), Vector2(200, 14)), sel.hp / maxf(1.0, sel.max_hp), U.HP)
	U.text_c(self, "%d / %d" % [int(sel.hp), int(sel.max_hp)], r.position + Vector2(114, 48), 11, U.TEXT, "bold")
	if sel.max_mana > 0.0:
		U.bar(self, Rect2(r.position + Vector2(14, 54), Vector2(200, 10)), sel.mana / maxf(1.0, sel.max_mana), U.MANA)
	var dmg := "%d-%d" % [int(sel.dmg_min + sel.bonus_damage), int(sel.dmg_max + sel.bonus_damage)] if sel.can_attack_at_all() else "-"
	U.text(self, "Damage %s   Armor %.0f   Range %d   Speed %d" % [dmg, sel.armor, int(sel.attack_range), int(sel.move_speed)],
		r.position + Vector2(228, 50), 13, U.TEXT, "body")
	var sx := r.position.x + 228.0
	var shown := {}
	for m in sel.modifiers:
		var key := String(m.get("fx", ""))
		if key == "" and float(m.get("slow", 0.0)) > 0.0:
			key = "slow"
		if key == "" or shown.has(key) or not UnitBars.STATUS_ICONS.has(key):
			continue
		shown[key] = true
		var ic: Texture2D = U.icon(UnitBars.STATUS_ICONS[key])
		if ic:
			draw_texture_rect(ic, Rect2(sx, r.position.y + 58, 18, 18), false)
			var left := float(m.get("expires", INF)) - w.time
			if left > 0.0 and is_finite(left):
				U.text(self, "%.0f" % ceilf(left), Vector2(sx + 20, r.position.y + 72), 11, U.TEXT_DIM, "bold")
			sx += 44.0
	if sel.is_building() and sel.is_invulnerable():
		U.text(self, "Invulnerable", r.position + Vector2(228, 70), 12, Color(1.0, 0.75, 0.4), "bold")
	elif sel.is_building() and sel.backdoor_active:
		U.text(self, "Backdoor protection", r.position + Vector2(228, 70), 12, Color(0.6, 0.85, 1.0), "bold")

func error(msg: String) -> void:
	_msg = msg
	_msg_col = Color(1.0, 0.35, 0.3)
	_msg_t = 2.0

## A neutral message in the same place as errors.
func notice(msg: String) -> void:
	_msg = msg
	_msg_col = Color(0.75, 0.95, 0.75)
	_msg_t = 2.0

var _msg_col := Color(1.0, 0.35, 0.3)

func announce(title: String, sub := "", col := U.GOLD) -> void:
	kill_feed.banner(title, sub, col)

## A team chat line (bots and you), from the world's "chat" event.
func on_chat(e: Dictionary) -> void:
	chat.add(e)

func on_kill(e: Dictionary) -> void:
	kill_feed.on_hero_kill(e, game.world, game.player_team)

func _name(u: SimUnit) -> String:
	if u == null:
		return "?"
	return String(u.look.get("display_name", u.name))

func toggle_shop() -> void:
	shop.visible = not shop.visible

func toggle_debug() -> void:
	debug.toggle()

## Whether a screen point is over a HUD element (the held right click does not order through it).
func over_hud(p: Vector2) -> bool:
	for c: Control in [bottom, minimap, topbar]:
		if c.get_global_rect().has_point(p):
			return true
	if bottom.covers_extra(p - bottom.global_position):
		return true
	if shop.visible and shop.get_global_rect().has_point(p):
		return true
	if to_buy.visible and to_buy.get_global_rect().has_point(p):
		return true
	return debug.covers(p)

## Tooltip content for this frame (drawn by Tip).
func show_tip(at: Vector2, lines: Array) -> void:
	_tip_lines = lines
	_last_tip = lines
	_tip_at = at

# ======================================================================================================================

class BottomPanel extends Control:
	## Laid out like Dota's: the hero's name above the portrait, the level in a circle at the portrait's lower left
	## with the experience ring round it and an experience bar along the portrait's foot; stats; the talent tree
	## button left of the abilities; health and mana; six item slots, the backpack and the Teleport slot; gold, Shop,
	## Courier. The stash sits above the items (shown when it holds something, in the base, or with the shop open).
	## With your courier selected the panel shows the courier: its commands and what it carries.
	## Items: click uses, drag moves (to another slot, the stash, the ground, an ally hero or your courier), right
	## click moves to or from the backpack.
	const W := 1140.0
	const H := 206.0
	const PORTRAIT := Rect2(14, 24, 166, 170)
	const ABIL_X := 404.0
	const ABIL_STEP := 80.0
	const ABIL_SIZE := 72.0
	const ITEM_X := 734.0
	const SIDE_X := 986.0
	const TALENT_C := Vector2(374, 70)
	const STASH_Y := -58.0
	const COURIER_CMDS := [["return", "Return to Base", "ui/back", "ability_1", "Home"], ["retrieve", "Retrieve Items", "ui/load", "ability_2", "Retrieve"],
		["stash", "Return Items to Stash", "ui/save", "ability_3", "To Stash"], ["deliver", "Deliver Items", "ui/teleport", "ability_4", "Deliver"],
		["transfer", "Transfer Items", "ui/split", "item_1", "Transfer"], ["burst", "Speed Burst", "status/haste", "item_2", "Burst"],
		["shield", "Shield", "status/shielded", "item_3", "Shield"], ["auto", "Auto Deliver", "ui/check", "item_4", "Auto"]]
	var hud
	var portrait_box: Control
	var overlay: Control                       # drawn above the 3D portrait: name, level, experience
	var _abil_rects: Array = []
	var _was_cooling := {}
	var _ready_at := {}
	var _learn_rects: Array = []
	var _item_rects: Array = []
	var _stash_rects: Array = []
	var _grab_rect := Rect2()
	var _cmd_rects: Array = []
	var _shop_rect := Rect2()
	var _tp_rect := Rect2()
	var _courier_rect := Rect2()
	var _buyback_rect := Rect2()
	var _talent_rect := Rect2()
	var talents_open := false
	var _talent_rows: Array = []               # [rect, tier, side]
	# drag and drop of items
	var _press_slot := -1                      # 0..8 inventory, 100+ stash
	var _press_at := Vector2.ZERO
	var _dragging := false

	func _ready() -> void:
		size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_layout()

	func make_overlay() -> void:
		overlay = PortraitOverlay.new()
		overlay.panel = self
		add_child(overlay)

	func _layout() -> void:
		_abil_rects.clear()
		_learn_rects.clear()
		for i in 4:
			var r := Rect2(ABIL_X + i * ABIL_STEP, 34, ABIL_SIZE, ABIL_SIZE)
			_abil_rects.append(r)
			_learn_rects.append(Rect2(r.position.x + 20, 8, 32, 22))
		_item_rects.clear()
		for i in 6:
			_item_rects.append(Rect2(ITEM_X + (i % 3) * 80, 30 + (i / 3) * 62, 74, 56))
		for i in 3:
			_item_rects.append(Rect2(ITEM_X + i * 80, 158, 74, 36))
		_stash_rects.clear()
		for i in 6:
			_stash_rects.append(Rect2(ITEM_X + i * 40, STASH_Y + 14, 36, 30))
		_grab_rect = Rect2(ITEM_X + 244, STASH_Y + 14, 64, 30)
		_cmd_rects.clear()
		for i in 8:
			_cmd_rects.append(Rect2(ABIL_X + (i % 4) * ABIL_STEP, 30 + (i / 4) * 62, ABIL_SIZE, 56))
		_shop_rect = Rect2(SIDE_X, 132, 140, 62)
		_tp_rect = Rect2(SIDE_X, 96, 60, 32)
		_courier_rect = Rect2(SIDE_X + 64, 96, 76, 32)
		_buyback_rect = Rect2(ABIL_X, 132, 312, 50)
		_talent_rect = Rect2(TALENT_C - Vector2(22, 22), Vector2(44, 44))

	## The courier when it is what the player has selected (the panel then shows it).
	func courier_shown() -> SimUnit:
		var h: SimUnit = hud.hero()
		if h == null:
			return null
		var c: SimUnit = hud.game.world.get_unit(h.courier_id)
		if c != null and hud.game.selected_id == c.id:
			return c
		return null

	func stash_visible(h: SimUnit) -> bool:
		if h == null or h.id != hud.game.player_hero_id:
			return false
		if hud.shop.visible:
			return false                       # the open shop shows the stash itself
		return h.stash.any(func(x): return x != null) or hud.game.world.shop.in_shop(h)

	func _draw() -> void:
		var h: SimUnit = hud.shown()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		var cour := courier_shown()
		var mine: bool = h.id == hud.game.player_hero_id
		U.panel(self, Rect2(0, 10, W, H - 10), U.GOLD_DIM if mine or h.team == hud.game.player_team else Color(0.6, 0.22, 0.2))
		if portrait_box:
			portrait_box.position = PORTRAIT.position
			portrait_box.visible = cour == null
			portrait_box.modulate = Color(1, 1, 1) if h.alive else Color(0.35, 0.35, 0.38)
		draw_rect(PORTRAIT.grow(2), U.GOLD_DIM, false, 2.0)
		if cour != null:
			_courier_panel(h, cour, w)
			_gold(h)
			_tp_and_courier(h, w)
			if overlay:
				overlay.queue_redraw()
			return
		_stats(h)
		_talent_button(h, w)
		_abilities(h, w)
		_bars(h)
		_items(h, w)
		if mine:
			_stash(h, w)
			_gold(h)
			_tp_and_courier(h, w)
			if not h.alive:
				_buyback(h, w)
		else:
			U.text(self, "Viewing " + ("an ally" if h.team == hud.game.player_team else "the enemy"), Vector2(SIDE_X, 70), 15, U.TEXT_DIM, "bold")
			U.text(self, Keybinds.key_name("select_hero") + " or the portrait:", Vector2(SIDE_X, 94), 12, U.TEXT_DIM, "body")
			U.text(self, "back to your hero", Vector2(SIDE_X, 110), 12, U.TEXT_DIM, "body")
		if talents_open:
			_talent_tree(h, w)
		if _dragging and _press_slot >= 0:
			var it = _drag_item(h)
			if it != null:
				var ic: Texture2D = U.item_icon(it.id)
				if ic:
					draw_texture_rect(ic, Rect2(get_local_mouse_position() - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.85))
		if overlay:
			overlay.queue_redraw()

	# ---- Portrait overlay: name plate, level circle with the experience ring, experience bar -------------------

	func draw_overlay(ci: CanvasItem) -> void:
		var h: SimUnit = hud.shown()
		if h == null:
			return
		var cour := courier_shown()
		var unit: SimUnit = cour if cour != null else h
		# name plate above the portrait, like Dota's
		var nm := "Courier" if cour != null else String(h.def.get("name", h.name))
		var f := U.font("title")
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var plate := Rect2(PORTRAIT.position.x - 2, -12, maxf(tw + 26, 110), 26)
		U.panel(ci, plate, U.GOLD_DIM, 4)
		U.text(ci, nm, plate.position + Vector2(13, 19), 17, U.GOLD, "title")
		if cour != null:
			_courier_portrait(ci, h, cour)
			return
		# experience bar along the portrait's foot, always readable
		var need := 0.0
		var have := 0.0
		var frac := 1.0
		if h.level < C.MAX_LEVEL:
			need = float(C.XP_TABLE[h.level]) - float(C.XP_TABLE[h.level - 1])
			have = h.xp - float(C.XP_TABLE[h.level - 1])
			frac = clampf(have / maxf(1.0, need), 0.0, 1.0)
		var xr := Rect2(PORTRAIT.position.x + 46, PORTRAIT.end.y - 18, PORTRAIT.size.x - 48, 16)
		ci.draw_rect(xr, Color(0, 0, 0, 0.72))
		ci.draw_rect(Rect2(xr.position, Vector2(xr.size.x * frac, xr.size.y)), Color(0.55, 0.36, 0.95, 0.9))
		var xt := "Max level" if h.level >= C.MAX_LEVEL else "%d / %d XP" % [int(have), int(need)]
		U.text_c(ci, xt, xr.get_center() + Vector2(4, 5.5), 12, U.TEXT, "bold")
		# level circle at the lower left, with the experience ring round it
		var c := Vector2(PORTRAIT.position.x + 22, PORTRAIT.end.y - 20)
		ci.draw_circle(c, 23, Color(0.03, 0.03, 0.04, 0.96))
		ci.draw_arc(c, 20, 0, TAU, 48, Color(0.22, 0.2, 0.26), 4.0, true)
		ci.draw_arc(c, 20, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(0.65, 0.42, 1.0), 4.0, true)
		ci.draw_arc(c, 23, 0, TAU, 48, U.GOLD_DIM, 1.5, true)
		U.text_c(ci, str(h.level), c + Vector2(0, 7.5), 21, U.GOLD, "bold")
		if h.ability_points > 0 and h.id == hud.game.player_hero_id:
			var bp := c + Vector2(18, -18)
			ci.draw_circle(bp, 9, Color(1.0, 0.82, 0.3))
			U.text_c(ci, str(h.ability_points), bp + Vector2(0, 4.5), 12, Color(0, 0, 0), "bold", false)
		var m := ci.get_local_mouse_position()
		if c.distance_to(m) < 24 or xr.has_point(m):
			var lines: Array = [["Level %d" % h.level, 18, U.GOLD, "title"]]
			if h.level < C.MAX_LEVEL:
				lines.append(["Experience %d / %d (%d to level %d)" % [int(have), int(need), int(need - have), h.level + 1], 14, U.TEXT, "body"])
			lines.append(["Total experience %d" % int(h.xp), 13, U.TEXT_DIM, "body"])
			if h.ability_points > 0:
				lines.append(["%d ability point%s to spend" % [h.ability_points, "" if h.ability_points == 1 else "s"], 13, Color(1.0, 0.85, 0.4), "body"])
			hud.show_tip(ci.get_global_mouse_position(), lines)

	func _courier_portrait(ci: CanvasItem, h: SimUnit, c: SimUnit) -> void:
		var r := PORTRAIT
		ci.draw_rect(r, Color(0.07, 0.08, 0.1))
		var ic: Texture2D = U.icon("status/windstep")
		if ic:
			ci.draw_texture_rect(ic, Rect2(r.get_center() - Vector2(48, 58), Vector2(96, 96)), false, U.GOLD if c.alive else Color(0.35, 0.35, 0.35))
		var state := "Dead: back in %ds" % ceili(c.respawn_at - hud.game.world.time) if not c.alive else _state_name(c.courier_state)
		U.text_c(ci, state, Vector2(r.get_center().x, r.end.y - 34), 14, U.TEXT, "bold")
		U.text_c(ci, ("Flying" if c.has_flag("flying") else "Walking") + "  speed %d" % int(c.move_speed), Vector2(r.get_center().x, r.end.y - 14), 12, U.TEXT_DIM, "body")
		var lc := Vector2(r.position.x + 22, r.position.y + 22)
		ci.draw_circle(lc, 18, Color(0.03, 0.03, 0.04, 0.96))
		ci.draw_arc(lc, 18, 0, TAU, 32, U.GOLD_DIM, 1.5, true)
		U.text_c(ci, str(h.level), lc + Vector2(0, 7), 18, U.GOLD, "bold")

	static func _state_name(s: String) -> String:
		return {"idle": "Waiting", "move": "Moving", "return": "Going home", "retrieve": "Fetching the stash",
			"fetch": "Fetching the stash", "collect": "Picking up items", "deliver": "Delivering", "transfer": "Delivering",
			"stash": "Returning items"}.get(s, s.capitalize())

	# ---- Stats, talents, abilities, bars ---------------------------------------------------------------------------

	func _stats(h: SimUnit) -> void:
		var x := 196.0
		var y := 44.0
		var dmg := "%d-%d" % [int(h.dmg_min), int(h.dmg_max)]
		if h.bonus_damage > 0.0:
			dmg += " +%d" % int(h.bonus_damage)
		_stat_row("ui/level", dmg, Vector2(x, y))
		_stat_row("status/fortified", "%.1f" % h.armor, Vector2(x, y + 24))
		_stat_row("status/haste", str(int(h.move_speed)), Vector2(x, y + 48))
		var r := Rect2(x - 4, y + 64, 152, 64)
		draw_rect(r, Color(0, 0, 0, 0.35))
		var attrs := [["attributes/strength", h.str_total, Color(0.95, 0.35, 0.3)], ["attributes/agility", h.agi_total, Color(0.4, 0.95, 0.45)],
			["attributes/intelligence", h.int_total, Color(0.4, 0.7, 1.0)]]
		for i in 3:
			var a: Array = attrs[i]
			var p := Vector2(x + 2 + i * 50, y + 72)
			var ic: Texture2D = U.icon(a[0])
			if ic:
				draw_texture_rect(ic, Rect2(p, Vector2(22, 22)), false, a[2])
			U.text(self, str(int(a[1])), p + Vector2(2, 44), 16, U.TEXT, "bold")
		if Rect2(r.position + Vector2(0, -72), Vector2(150, 136)).has_point(get_local_mouse_position()):
			hud.show_tip(get_global_mouse_position(), [
				["Damage %s   Armor %.1f   Speed %d" % [dmg, h.armor, int(h.move_speed)], 14, U.TEXT, "body"],
				["Attack speed %d (%.2f s per attack)" % [int(h.attack_speed), h.attack_interval()], 14, U.TEXT, "body"],
				["Attack range %d" % int(h.attack_range), 14, U.TEXT, "body"],
				["Magic resistance %d%%" % int(h.magic_resist * 100.0), 14, U.TEXT, "body"],
				["Health regen %.1f  Mana regen %.1f" % [h.hp_regen, h.mana_regen], 14, U.TEXT, "body"],
				["Physical damage taken x%.2f" % C.armor_multiplier(h.armor), 14, U.TEXT_DIM, "body"]])

	func _stat_row(ic_path: String, val: String, p: Vector2) -> void:
		var ic: Texture2D = U.icon(ic_path)
		if ic:
			draw_texture_rect(ic, Rect2(p + Vector2(0, -15), Vector2(18, 18)), false, U.GOLD)
		U.text(self, val, p + Vector2(24, 0), 16, U.TEXT, "bold")

	## Dota's talent tree button: lit while a talent can be learned.
	func _talent_button(h: SimUnit, w: SimWorld) -> void:
		var tree: Array = h.def.get("talents", [])
		if tree.is_empty():
			return
		var can := false
		for t in tree.size():
			if w.abilities.can_learn_talent(h, t):
				can = true
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0) if can and h.id == hud.game.player_hero_id else 0.0
		draw_circle(TALENT_C, 22, Color(0.05, 0.05, 0.06))
		draw_arc(TALENT_C, 22, 0, TAU, 40, U.GOLD if can else U.GOLD_DIM, 2.0 + 2.0 * pulse, true)
		var ic: Texture2D = U.icon("ui/favorite")
		if ic:
			draw_texture_rect(ic, Rect2(TALENT_C - Vector2(13, 13), Vector2(26, 26)), false, U.GOLD if h.talents.size() > 0 or can else Color(0.55, 0.55, 0.55))
		U.text_c(self, "Talents", TALENT_C + Vector2(0, 38), 11, U.TEXT_DIM, "bold")
		if _talent_rect.has_point(get_local_mouse_position()) and not talents_open:
			hud.show_tip(get_global_mouse_position(), [["Talents", 18, U.GOLD, "title"],
				["Click to open. At levels 10, 15, 20 and 25 spend an ability point on one of two talents.", 14, U.TEXT, "body"]])

	## The open tree: level 25 at the top, each row a choice of two.
	func _talent_tree(h: SimUnit, w: SimWorld) -> void:
		var tree: Array = h.def.get("talents", [])
		_talent_rows.clear()
		if tree.is_empty():
			return
		var pw := 520.0
		var rh := 40.0
		var top := -(tree.size() * (rh + 6) + 44)
		var r := Rect2(TALENT_C.x - pw * 0.5 + 60, top, pw, tree.size() * (rh + 6) + 36)
		U.panel(self, r, U.GOLD, 6)
		U.text(self, "Talents", r.position + Vector2(14, 22), 16, U.GOLD, "title")
		var m := get_local_mouse_position()
		for row in tree.size():
			var tier: int = tree.size() - 1 - row
			var y := r.position.y + 30 + row * (rh + 6)
			var lvl := int(C.TALENT_LEVELS[tier])
			var lc := Vector2(r.get_center().x, y + rh * 0.5)
			draw_circle(lc, 17, Color(0.05, 0.05, 0.06))
			draw_arc(lc, 17, 0, TAU, 32, U.GOLD_DIM, 1.5, true)
			U.text_c(self, str(lvl), lc + Vector2(0, 6), 15, U.GOLD if h.level >= lvl else U.TEXT_DIM, "bold")
			var can: bool = w.abilities.can_learn_talent(h, tier) and h.id == hud.game.player_hero_id
			for side in 2:
				var tid := String(tree[tier][side])
				var tr := Rect2(r.position.x + 10 + side * (pw * 0.5 + 12), y, pw * 0.5 - 32, rh)
				if side == 1:
					tr.position.x = lc.x + 22
				var picked := String(h.talents.get(tier, "")) == tid
				var other := h.talents.has(tier) and not picked
				var col := Color(0.12, 0.1, 0.06) if picked else Color(0.07, 0.07, 0.09)
				draw_rect(tr, col)
				var rim := U.GOLD if picked else (Color(1.0, 0.85, 0.4, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)) if can else U.GOLD_DIM)
				if can and tr.has_point(m):
					rim = Color(1, 1, 1)
				draw_rect(tr, rim, false, 2.0)
				var nm := String(SimData.talent(tid).get("name", tid))
				var tc := U.GOLD if picked else (Color(0.45, 0.45, 0.45) if other else U.TEXT)
				U.text_c(self, nm, tr.get_center() + Vector2(0, 5), 14, tc, "bold")
				_talent_rows.append([tr, tier, side])

	func _abilities(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		hud.game.input.hover_ability = ""
		for i in mini(4, h.abilities.size()):
			var aid: String = h.abilities[i]
			var a := SimData.ability(aid)
			var r: Rect2 = _abil_rects[i]
			var lv := h.ability_level_of(aid)
			var auto := bool(h.autocast.get(aid, false))
			var toggled := bool(h.toggles.get(aid, false))
			U.slot(self, r.grow(2), auto or toggled or hud.game.input.targeting == aid)
			var ic: Texture2D = U.ability_icon(aid)
			var col := Color(1, 1, 1) if lv > 0 else Color(0.32, 0.32, 0.34)
			var mana_cost := float(a.mana[maxi(lv - 1, 0)])
			if lv > 0 and h.mana < mana_cost:
				col = Color(0.45, 0.55, 1.0)
			draw_rect(r, Color(0.08, 0.1, 0.14))
			if ic:
				draw_texture_rect(ic, r.grow(-6), false, col)
			if lv > 0:
				var cd := w.abilities.cooldown_left(h, aid)
				var total := float(a.cooldown[lv - 1])
				if cd > 0.0 and total > 0.0:
					U.cooldown(self, r, cd / total, cd)
					_was_cooling[aid] = true
				elif _was_cooling.get(aid, false):
					_was_cooling[aid] = false
					_ready_at[aid] = Time.get_ticks_msec() / 1000.0
				var since := Time.get_ticks_msec() / 1000.0 - float(_ready_at.get(aid, -9.0))
				if since < 0.45:
					var k := 1.0 - since / 0.45
					draw_rect(r, Color(1.0, 1.0, 0.9, 0.55 * k))
					draw_rect(r.grow(3.0 * k), Color(1.0, 0.9, 0.5, k), false, 2.0)
			if auto or toggled:
				var t := Time.get_ticks_msec() / 1000.0
				var tcol := Color(0.55, 1.0, 0.45) if toggled else Color(1.0, 0.85, 0.3)
				draw_rect(r.grow(1), Color(tcol, 0.6 + 0.4 * sin(t * 6.0)), false, 3.0)
			U.text(self, Keybinds.key_name("ability_%d" % (i + 1)), r.position + Vector2(4, 15), 14, Color(1, 1, 1), "bold")
			if mana_cost > 0:
				U.text_r(self, str(int(mana_cost)), r.end + Vector2(-3, -4), 12, Color(0.55, 0.75, 1.0), "bold")
			var mx := int(a.max_level)
			for k in mx:
				var px := r.position.x + r.size.x * 0.5 + (k - (mx - 1) * 0.5) * 12.0
				draw_rect(Rect2(px - 4, r.end.y + 6, 8, 5), U.GOLD if k < lv else Color(0.2, 0.2, 0.22))
			if w.abilities.can_learn(h, aid) and h.id == hud.game.player_hero_id:
				var lr: Rect2 = _learn_rects[i]
				var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 200.0)
				draw_rect(lr, Color(0.95, 0.75, 0.25, pulse))
				U.text_c(self, "+", lr.get_center() + Vector2(0, 8), 22, Color(0.1, 0.06, 0.0), "bold", false)
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), _ability_tip(h, aid))
				hud.game.input.hover_ability = aid

	func _ability_tip(h: SimUnit, aid: String) -> Array:
		var a := SimData.ability(aid)
		var lv := h.ability_level_of(aid)
		var lines: Array = [[String(a.name), 20, U.GOLD, "title"]]
		var kind := {"autocast_attack": "Attack modifier (autocast)", "point": "Point target", "passive": "Passive",
			"unit": "Unit target", "no_target": "No target", "toggle": "Toggle"}
		var team := String(a.get("target_team", "enemy"))
		var aim := ""
		if String(a.behavior) in ["unit", "point", "autocast_attack"]:
			aim = "    Targets: " + ("enemies" if team == "enemy" else ("allies" if team == "ally" else "any unit"))
		lines.append([String(kind.get(a.behavior, "")) + aim + "    Level %d / %d" % [lv, int(a.max_level)], 13, U.TEXT_DIM, "body"])
		for l in U.wrap(String(a.desc), 330, 15):
			lines.append([l, 15, U.TEXT, "body"])
		for k in a.values:
			var vals: Array = a.values[k]
			var parts := []
			for v in vals:
				var fv := float(v)
				parts.append(("%d%%" % roundi(fv * 100.0)) if fv > 0.0 and fv < 1.0 and (k.contains("slow") or k.ends_with("pct") or k.contains("chance") or k == "lifesteal") else str(v))
			lines.append(["%s: %s" % [k.replace("_", " ").capitalize(), " / ".join(parts)], 13, Color(0.8, 0.85, 0.75), "body"])
		if a.behavior != "passive":
			lines.append(["Mana: %s    Cooldown: %s" % [" / ".join(a.mana.map(func(x): return str(x))), " / ".join(a.cooldown.map(func(x): return str(x)))], 13, Color(0.6, 0.75, 1.0), "body"])
		if a.behavior == "autocast_attack":
			lines.append(["Right-click to toggle autocast. Cast by hand on a hero to attack without drawing creep aggro.", 12, U.TEXT_DIM, "body"])
		if a.behavior == "toggle":
			lines.append(["Press again to turn it off.", 12, U.TEXT_DIM, "body"])
		lines.append(["Ctrl + %s to learn" % Keybinds.ability_key_name(String(a.key)), 12, U.TEXT_DIM, "body"])
		return lines

	func _bars(h: SimUnit) -> void:
		var bw := 4 * ABIL_STEP - 8
		var hr := Rect2(ABIL_X, 132, bw, 24)
		U.bar(self, hr, h.hp / maxf(1.0, h.max_hp), U.HP)
		U.text_c(self, "%d / %d" % [int(h.hp), int(h.max_hp)], hr.get_center() + Vector2(0, 7), 16, U.TEXT, "bold")
		U.text_r(self, "+%.1f" % h.hp_regen, Vector2(hr.end.x - 4, hr.position.y + 17), 12, Color(0.8, 1.0, 0.8), "body")
		var mr := Rect2(ABIL_X, 162, bw, 20)
		U.bar(self, mr, h.mana / maxf(1.0, h.max_mana), U.MANA)
		U.text_c(self, "%d / %d" % [int(h.mana), int(h.max_mana)], mr.get_center() + Vector2(0, 6), 14, U.TEXT, "bold")
		U.text_r(self, "+%.1f" % h.mana_regen, Vector2(mr.end.x - 4, mr.position.y + 15), 12, Color(0.8, 0.88, 1.0), "body")

	# ---- Items, stash ----------------------------------------------------------------------------------------------

	func _items(h: SimUnit, w: SimWorld) -> void:
		var keys: Array = range(6).map(func(i): return Keybinds.key_name("item_%d" % (i + 1)))
		var m := get_local_mouse_position()
		for i in 9:
			var r: Rect2 = _item_rects[i]
			U.slot(self, r, _dragging and r.has_point(m))
			var it = h.inventory[i]
			if it == null:
				if i < 6:
					U.text(self, keys[i], r.position + Vector2(4, 14), 11, Color(0.5, 0.5, 0.5), "bold")
				continue
			_item_icon(it, r, i >= 6, h, w, i)
			if i < 6:
				U.text(self, keys[i], r.position + Vector2(4, 14), 11, Color(1, 1, 1), "bold")
			if r.has_point(m) and not _dragging:
				var tip: Array = hud.item_tip(it.id, h)
				tip.append(["Drag to move, drop on the ground or give it to an ally. Right click: %s." % ("to the inventory" if i >= 6 else "to the backpack"), 12, U.TEXT_DIM, "body"])
				hud.show_tip(get_global_mouse_position(), tip)
		if h.id == hud.game.player_hero_id:
			U.text(self, "Backpack", Vector2(ITEM_X, 156), 10, U.TEXT_DIM, "body")

	func _item_icon(it: Dictionary, r: Rect2, dim: bool, h: SimUnit, w: SimWorld, slot: int) -> void:
		var ic: Texture2D = U.item_icon(it.id)
		if ic:
			var sq := minf(r.size.x, r.size.y) - 6
			draw_texture_rect(ic, Rect2(r.get_center() - Vector2(sq, sq) * 0.5, Vector2(sq, sq)), false,
				Color(0.5, 0.5, 0.5) if dim else Color(1, 1, 1, 0.35 if _dragging and _press_slot == slot else 1.0))
		var d := SimData.item(it.id)
		if slot >= 0 and slot < 9 and h != null:
			var cd := w.abilities.item_cooldown_left(h, slot) if slot < 6 else maxf(0.0, float(it.get("ready", C.LONG_AGO)) - w.time)
			var total := maxf(float(d.cooldown), C.BACKPACK_SWAP_COOLDOWN)
			if cd > 0.0:
				U.cooldown(self, r, clampf(cd / total, 0.0, 1.0), cd)
		if int(it.get("charges", 0)) > 1 or d.consumable and int(it.get("charges", 0)) > 0:
			U.text_r(self, str(it.charges), r.end + Vector2(-3, -3), 14, Color(1, 1, 1), "bold")
		if String(d.use) == "stick" and h != null:
			U.text_r(self, str(h.stick_charges), r.end + Vector2(-3, -3), 14, Color(0.7, 0.9, 1.0), "bold")

	## Dota's stash above the inventory: six slots and Grab All.
	func _stash(h: SimUnit, w: SimWorld) -> void:
		if not stash_visible(h):
			return
		var m := get_local_mouse_position()
		var here := w.shop.in_shop(h)
		var r := Rect2(ITEM_X - 8, STASH_Y - 8, 330, 56)
		U.panel(self, r, U.GOLD_DIM, 4)
		U.text(self, "Stash" + ("" if here or not h.alive else "  (courier: %s)" % Keybinds.key_name("courier_deliver")), Vector2(ITEM_X, STASH_Y + 6), 11, U.TEXT_DIM, "bold")
		for i in 6:
			var sr: Rect2 = _stash_rects[i]
			U.slot(self, sr, sr.has_point(m) and (h.stash[i] != null or _dragging))
			var it = h.stash[i]
			if it != null:
				_item_icon(it, sr, not here and h.alive, null, w, 100 + i)
				if sr.has_point(m) and not _dragging:
					var tip: Array = hud.item_tip(it.id, h)
					tip.append(["Click: take it (in the base). Drag it to a slot. The courier (%s) brings the stash to you." % Keybinds.key_name("courier_deliver"), 12, U.TEXT_DIM, "body"])
					hud.show_tip(get_global_mouse_position(), tip)
		var can := (here or not h.alive) and h.stash.any(func(x): return x != null)
		U.panel(self, _grab_rect, U.GOLD if can and _grab_rect.has_point(m) else U.GOLD_DIM, 3)
		U.text_c(self, "Grab All", _grab_rect.get_center() + Vector2(0, 5), 12, U.GOLD if can else U.TEXT_DIM, "bold")

	func _gold(h: SimUnit) -> void:
		var gi: Texture2D = U.icon("ui/gold")
		if gi:
			draw_texture_rect(gi, Rect2(SIDE_X, 40, 26, 26), false, U.GOLD)
		U.text(self, str(h.gold()), Vector2(SIDE_X + 32, 62), 24, U.GOLD, "bold")
		U.text(self, "reliable %d" % h.gold_reliable, Vector2(SIDE_X, 86), 12, U.TEXT_DIM, "body")
		var hover := _shop_rect.has_point(get_local_mouse_position())
		U.panel(self, _shop_rect, U.GOLD if hover else U.GOLD_DIM, 4)
		var si: Texture2D = U.icon("ui/shop")
		if si:
			draw_texture_rect(si, Rect2(_shop_rect.position + Vector2(10, 14), Vector2(32, 32)), false, U.GOLD)
		U.text(self, "Shop", _shop_rect.position + Vector2(54, 38), 18, U.GOLD, "title")

	func _tp_and_courier(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		U.slot(self, _tp_rect, hud.game.input.targeting == "tp")
		var ti: Texture2D = U.icon("ui/teleport")
		if ti:
			draw_texture_rect(ti, Rect2(_tp_rect.position + Vector2(14, 2), Vector2(28, 28)), false, U.DAWN if h.tp_charges > 0 else Color(0.4, 0.4, 0.4))
		var cd := w.abilities.cooldown_left(h, "tp")
		if cd > 0.0:
			U.cooldown(self, _tp_rect, cd / SimConst.TP_COOLDOWN, cd)
		U.text(self, Keybinds.key_name("tp"), _tp_rect.position + Vector2(3, 12), 10, Color(1, 1, 1), "bold")
		U.text_r(self, str(h.tp_charges), _tp_rect.end + Vector2(-3, -3), 12, Color(1, 1, 1), "bold")
		if _tp_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Teleport Scroll", 18, U.GOLD, "title"],
				["Channel 3 s, then teleport beside the allied building nearest the target point. Moving or a stun cancels it.", 14, U.TEXT, "body"],
				["Charges %d. Cooldown 80 s. Mana 75. Buy more in the shop (100 gold). Hotkey %s." % [h.tp_charges, Keybinds.key_name("tp")], 13, U.TEXT_DIM, "body"]])
		var c := w.get_unit(h.courier_id)
		U.slot(self, _courier_rect, c != null and c.courier_state != "idle")
		var state := "Dead" if c == null or not c.alive else _state_name(c.courier_state)
		U.text_c(self, "Deliver", _courier_rect.get_center() + Vector2(0, -2), 12, U.GOLD, "bold")
		U.text_c(self, state, _courier_rect.get_center() + Vector2(0, 12), 9, U.TEXT_DIM, "body")
		if _courier_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Courier", 18, U.GOLD, "title"],
				["Click (or %s): the courier picks up your items lying in the fountain area, takes the stash and flies it all to you." % Keybinds.key_name("courier_deliver"), 14, U.TEXT, "body"],
				["%s selects the courier for its other commands." % Keybinds.key_name("select_courier"), 13, U.TEXT_DIM, "body"]])

	func _buyback(h: SimUnit, w: SimWorld) -> void:
		var cost := w.buyback_cost(h)
		var ready := w.time >= h.buyback_ready
		var can := ready and h.gold() >= cost
		draw_rect(_buyback_rect, Color(0.05, 0.04, 0.03, 0.92))
		draw_rect(_buyback_rect, U.GOLD if can else Color(0.4, 0.35, 0.3), false, 2.0)
		var label := "Buyback  %d gold" % cost if ready else "Buyback in %ds" % ceili(h.buyback_ready - w.time)
		U.text_c(self, label, _buyback_rect.get_center() + Vector2(0, 8), 20, U.GOLD if can else U.TEXT_DIM, "title")

	# ---- Courier panel ---------------------------------------------------------------------------------------------

	func _courier_panel(h: SimUnit, c: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		# hits left (couriers count hits, not health)
		var hr := Rect2(196, 40, 190, 20)
		U.bar(self, hr, c.hp / maxf(1.0, c.max_hp), U.HP)
		U.text_c(self, "%d / %d hits" % [int(ceil(c.hp)), int(c.max_hp)], hr.get_center() + Vector2(0, 6), 13, U.TEXT, "bold")
		U.text(self, "Dies to 1 melee hero hit,", Vector2(196, 82), 12, U.TEXT_DIM, "body")
		U.text(self, "2 ranged hero hits or 6 others.", Vector2(196, 98), 12, U.TEXT_DIM, "body")
		U.text(self, "Flies from level %d." % C.COURIER_FLY_LEVEL, Vector2(196, 120), 12, U.TEXT_DIM, "body")
		for i in COURIER_CMDS.size():
			var cmd: Array = COURIER_CMDS[i]
			var r: Rect2 = _cmd_rects[i]
			var locked: bool = (cmd[0] == "burst" and h.level < C.COURIER_BURST_LEVEL) or (cmd[0] == "shield" and h.level < C.COURIER_SHIELD_LEVEL)
			var on: bool = cmd[0] == "auto" and c.courier_auto
			U.slot(self, r, r.has_point(m) or on)
			var ic: Texture2D = U.icon(cmd[2])
			if ic:
				draw_texture_rect(ic, Rect2(r.get_center() - Vector2(18, 20), Vector2(36, 36)), false,
					Color(0.35, 0.35, 0.35) if locked or not c.alive else (Color(0.55, 1.0, 0.45) if on else U.GOLD))
			var cdl := 0.0
			if cmd[0] == "burst":
				cdl = c.courier_burst_ready - w.time
				if cdl > 0.0:
					U.cooldown(self, r, cdl / C.COURIER_BURST_COOLDOWN, cdl)
			elif cmd[0] == "shield":
				cdl = c.courier_shield_ready - w.time
				if cdl > 0.0:
					U.cooldown(self, r, cdl / C.COURIER_SHIELD_COOLDOWN, cdl)
			U.text(self, Keybinds.key_name(cmd[3]), r.position + Vector2(4, 13), 11, Color(1, 1, 1), "bold")
			U.text_c(self, String(cmd[4]), Vector2(r.get_center().x, r.end.y - 3), 10, U.TEXT_DIM, "body")
			if r.has_point(m):
				var tip := {"return": "Fly back to the fountain.", "retrieve": "Pick up your items lying in the fountain area and take the stash, then wait at the fountain.",
					"stash": "Fly home and put everything it carries into your stash.", "deliver": "Pick up your items in the fountain area, take the stash and bring it all to you.",
					"transfer": "Bring what it carries to you.", "burst": "+50%% movement speed for 6 seconds. 120 second cooldown. From level %d." % C.COURIER_BURST_LEVEL,
					"shield": "Invulnerable for 2 seconds. 200 second cooldown. From level %d." % C.COURIER_SHIELD_LEVEL,
					"auto": "While on, the courier sets out by itself whenever the stash or its bags hold something."}
				hud.show_tip(get_global_mouse_position(), [[String(cmd[1]), 18, U.GOLD, "title"], [String(tip.get(cmd[0], "")), 14, U.TEXT, "body"],
					["Hotkey %s" % Keybinds.key_name(cmd[3]), 12, U.TEXT_DIM, "body"]])
		# what it carries
		for i in 6:
			var r: Rect2 = _item_rects[i]
			U.slot(self, r)
			var it = c.inventory[i]
			if it != null:
				_item_icon(it, r, not c.alive, null, w, -1)
				if r.has_point(m):
					hud.show_tip(get_global_mouse_position(), hud.item_tip(it.id, h))
		U.text(self, "Carrying", Vector2(ITEM_X, 24), 11, U.TEXT_DIM, "bold")

	# ---- Input -----------------------------------------------------------------------------------------------------

	func _drag_item(h: SimUnit):
		if _press_slot >= 100:
			return h.stash[_press_slot - 100]
		if _press_slot >= 0:
			return h.inventory[_press_slot]
		return null

	func _slot_at(p: Vector2, h: SimUnit) -> int:
		for i in 9:
			if (_item_rects[i] as Rect2).has_point(p):
				return i
		if stash_visible(h):
			for i in 6:
				if (_stash_rects[i] as Rect2).has_point(p):
					return 100 + i
		return -1

	## Whether a point (local) is over the stash row or the open talent tree (they stick out above the panel).
	func covers_extra(p: Vector2) -> bool:
		var h: SimUnit = hud.hero()
		if stash_visible(h) and Rect2(ITEM_X - 8, STASH_Y - 8, 330, 56).has_point(p):
			return true
		if talents_open and not _talent_rows.is_empty():
			for tr in _talent_rows:
				if (tr[0] as Rect2).grow(8).has_point(p):
					return true
		return false

	func _has_point(p: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).has_point(p) or covers_extra(p)

	func _gui_input(e: InputEvent) -> void:
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		if e is InputEventMouseMotion and _press_slot >= 0:
			if not _dragging and (e as InputEventMouseMotion).position.distance_to(_press_at) > 6.0:
				_dragging = true
			if _dragging:
				queue_redraw()
			return
		if e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hud.portrait_release()
			if _press_slot >= 0:
				_release_item((e as InputEventMouseButton).position, h, w)
				accept_event()
			return
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var p := mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and PORTRAIT.has_point(p) and courier_shown() == null:
			hud.portrait_press()
			accept_event()
			return
		if talents_open and mb.button_index == MOUSE_BUTTON_LEFT:
			for tr in _talent_rows:
				if (tr[0] as Rect2).has_point(p):
					if w.abilities.learn_talent(h, int(tr[1]), int(tr[2])) and hud.game.audio:
						hud.game.audio.ui("ui_click", -2.0)
					accept_event()
					return
		if _talent_rect.has_point(p) and mb.button_index == MOUSE_BUTTON_LEFT and not (hud.shown().def.get("talents", []) as Array).is_empty():
			talents_open = not talents_open
			accept_event()
			return
		talents_open = false
		var cour := courier_shown()
		if cour != null:
			for i in COURIER_CMDS.size():
				if (_cmd_rects[i] as Rect2).has_point(p):
					hud.game.input.courier_cmd(String(COURIER_CMDS[i][0]))
					accept_event()
					return
		if hud.shown() != h and cour == null:
			accept_event()
			return
		if not h.alive and _buyback_rect.has_point(p):
			var err := w.buyback(h)
			if err != "":
				hud.error(err)
			accept_event()
			return
		if _tp_rect.has_point(p):
			hud.game.input.begin_tp()
			accept_event()
			return
		if _courier_rect.has_point(p):
			hud.game.input.courier_cmd("deliver")
			accept_event()
			return
		if _shop_rect.has_point(p):
			hud.toggle_shop()
			accept_event()
			return
		if stash_visible(h) and _grab_rect.has_point(p):
			var gerr: String = w.shop.grab_all(h)
			if gerr != "":
				hud.error(gerr)
			accept_event()
			return
		if cour != null:
			accept_event()
			return
		for i in 4:
			if i >= h.abilities.size():
				break
			var aid: String = h.abilities[i]
			if (_learn_rects[i] as Rect2).has_point(p) and w.abilities.can_learn(h, aid):
				w.abilities.learn(h, aid)
				accept_event()
				return
			if (_abil_rects[i] as Rect2).has_point(p):
				if mb.button_index == MOUSE_BUTTON_RIGHT:
					w.abilities.toggle_autocast(h, aid)
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					if mb.ctrl_pressed:
						w.abilities.learn(h, aid)
					else:
						hud.game.input.begin_ability(aid, mb.shift_pressed)
				accept_event()
				return
		var s := _slot_at(p, h)
		if s >= 0:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				# a click uses the item (on release, so a drag can move it instead)
				if (s < 100 and h.inventory[s] != null) or (s >= 100 and h.stash[s - 100] != null):
					_press_slot = s
					_press_at = p
					_dragging = false
			elif mb.button_index == MOUSE_BUTTON_RIGHT and s < 9:
				# right-click moves an item between the inventory and the backpack
				var dest := -1
				var lo := 6 if s < 6 else 0
				var hi := 9 if s < 6 else 6
				for k in range(lo, hi):
					if h.inventory[k] == null:
						dest = k
						break
				if dest >= 0:
					w.shop.swap(h, s, dest)
			accept_event()
			return
		accept_event()

	## Finish a click or a drag that began on an item.
	func _release_item(p: Vector2, h: SimUnit, w: SimWorld) -> void:
		var from := _press_slot
		var dragged := _dragging
		_press_slot = -1
		_dragging = false
		queue_redraw()
		if not dragged:
			if from < 6:
				hud.game.input.use_item(from, Input.is_key_pressed(KEY_SHIFT))
			elif from >= 100:
				var err0: String = w.shop.from_stash(h, from - 100)
				if err0 != "":
					hud.error(err0)
			return
		var to := _slot_at(p, h)
		var err := ""
		if to >= 0:
			if from < 100 and to < 100:
				w.shop.swap(h, from, to)
			elif from < 100 and to >= 100:
				err = w.shop.to_stash(h, from)
			elif from >= 100 and to < 100:
				err = w.shop.from_stash(h, from - 100, to)
		elif not _has_point(p) and from < 100 and not hud.over_hud(get_global_transform() * p):
			# dropped on the world: give it to an ally hero or your courier under the cursor, otherwise drop it there
			hud.game.input.drop_or_give(from, get_global_transform() * p)
		if err != "":
			hud.error(err)


class PortraitOverlay extends Control:
	var panel

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2.ZERO
		size = Vector2(BottomPanel.W, BottomPanel.H)

	func _draw() -> void:
		panel.draw_overlay(self)


class ToBuyPanel extends Control:
	## The To Buy list at the side of the screen (Dota's quick buy): Shift + click an item in the shop to add it,
	## broken into the parts you still need. Shows up to 8 entries. Left click buys an entry now, right click sets it
	## to buy itself as soon as you have the gold (the courier takes it if it waits at the fountain while you are
	## away), Ctrl + click (or the x) removes it.
	const W := 236.0
	const ROW := 46.0
	var hud
	var _rows: Array = []                      # [rect, index, kind] kind: "buy" or "remove"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func wanted() -> bool:
		var h: SimUnit = hud.hero()
		return h != null and (not h.to_buy.is_empty() or hud.shop.visible)

	func _process(_dt: float) -> void:
		var h: SimUnit = hud.hero()
		var n := 0 if h == null else mini(h.to_buy.size(), C.TO_BUY_SHOWN)
		var more := h != null and h.to_buy.size() > C.TO_BUY_SHOWN
		size = Vector2(W, 40 + maxi(n, 1) * ROW + (22 if more else 0) + 30)

	func _draw() -> void:
		_rows.clear()
		var h: SimUnit = hud.hero()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		var m := get_local_mouse_position()
		U.panel(self, Rect2(Vector2.ZERO, size), U.GOLD_DIM, 6)
		U.text(self, "To Buy", Vector2(12, 24), 17, U.GOLD, "title")
		var total := 0
		for e in h.to_buy:
			total += int(SimData.item(String(e.id)).cost)
		if total > 0:
			U.text_r(self, "%d gold" % total, Vector2(W - 12, 24), 13, U.GOLD, "bold")
		if h.to_buy.is_empty():
			U.text(self, "Shift + click an item", Vector2(12, 52), 12, U.TEXT_DIM, "body")
			U.text(self, "in the shop to add it here.", Vector2(12, 68), 12, U.TEXT_DIM, "body")
		var y := 36.0
		for i in mini(h.to_buy.size(), C.TO_BUY_SHOWN):
			var e: Dictionary = h.to_buy[i]
			var id := String(e.id)
			var d := SimData.item(id)
			var r := Rect2(8, y, W - 16, ROW - 4)
			var price := w.shop.price(h, id)
			var afford := h.gold() >= price
			var auto := bool(e.auto)
			var hover := r.has_point(m)
			draw_rect(r, Color(0.08, 0.09, 0.11, 0.95) if not hover else Color(0.13, 0.13, 0.16, 0.98))
			var rim := U.GOLD_DIM
			if auto:
				var t := Time.get_ticks_msec() / 1000.0
				rim = Color(0.45, 1.0, 0.5, 0.65 + 0.35 * sin(t * 5.0))
			draw_rect(r, rim, false, 2.0 if auto else 1.0)
			var ic: Texture2D = U.item_icon(id)
			if ic:
				draw_texture_rect(ic, Rect2(r.position + Vector2(5, 4), Vector2(34, 34)), false, Color(1, 1, 1) if afford else Color(0.55, 0.55, 0.55))
			var nm := String(d.get("name", id))
			if nm.length() > 18:
				nm = nm.substr(0, 17) + "."
			U.text(self, nm, r.position + Vector2(46, 18), 13, U.TEXT if afford else U.TEXT_DIM, "bold")
			U.text(self, "%d" % price, r.position + Vector2(46, 35), 12, U.GOLD if afford else Color(0.65, 0.5, 0.4), "bold")
			if auto:
				U.text_r(self, "Auto", Vector2(r.end.x - 26, r.position.y + 35), 11, Color(0.5, 1.0, 0.55), "bold")
			var xr := Rect2(r.end.x - 22, r.position.y + 4, 18, 18)
			draw_rect(xr, Color(0.25, 0.08, 0.06) if xr.has_point(m) else Color(0.12, 0.1, 0.1))
			U.text_c(self, "x", xr.get_center() + Vector2(0, 5), 13, U.TEXT, "bold")
			_rows.append([xr, i, "remove"])
			_rows.append([r, i, "buy"])
			if hover and not xr.has_point(m):
				var tip: Array = hud.item_tip(id, h)
				tip.append(["Left click: buy now (%d gold). Right click: %s. Ctrl + click: remove." % [price,
					"stop buying it automatically" if auto else "buy it automatically when you have the gold"], 12, Color(0.75, 0.9, 0.75), "body"])
				hud.show_tip(get_global_mouse_position(), tip)
			y += ROW
		if h.to_buy.size() > C.TO_BUY_SHOWN:
			U.text(self, "+%d more" % (h.to_buy.size() - C.TO_BUY_SHOWN), Vector2(14, y + 14), 12, U.TEXT_DIM, "bold")
			y += 22
		if not h.to_buy.is_empty():
			var cr := Rect2(8, size.y - 30, W - 16, 24)
			U.slot(self, cr, cr.has_point(m))
			U.text_c(self, "Clear", cr.get_center() + Vector2(0, 5), 12, U.TEXT_DIM, "bold")
			_rows.append([cr, -1, "clear"])

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		for r in _rows:
			if not (r[0] as Rect2).has_point(mb.position):
				continue
			var i: int = r[1]
			match String(r[2]):
				"clear":
					h.to_buy.clear()
				"remove":
					w.shop.remove_to_buy(h, i)
				"buy":
					if mb.button_index == MOUSE_BUTTON_RIGHT:
						w.shop.toggle_auto_buy(h, i)
					elif mb.ctrl_pressed:
						w.shop.remove_to_buy(h, i)
					elif mb.button_index == MOUSE_BUTTON_LEFT:
						var err: String = w.shop.buy_listed(h, i)
						if err != "":
							hud.error(err)
			queue_redraw()
			accept_event()
			return
		accept_event()


const STAT_NAMES := {"str": "Strength", "agi": "Agility", "int": "Intelligence", "damage": "Damage",
	"attack_speed": "Attack Speed", "armor": "Armor", "hp": "Health", "mana": "Mana", "hp_regen": "Health Regen",
	"mana_regen": "Mana Regen", "move_speed": "Movement Speed", "boot_ms": "Movement Speed",
	"move_speed_pct": "Movement Speed", "max_mana_pct": "Max Mana", "lifesteal": "Lifesteal", "range": "Attack Range",
	"magic_resist": "Magic Resistance", "evasion": "Evasion"}

const ITEM_TEXT := {"tango": "Eat a tree to regenerate 7 health per second for 16 seconds (32 seconds on a planted tree). The tree is destroyed and grows back after 3 minutes.",
	"plant": "Plant a tree within 400 range. It stands for 20 seconds. Consumes the twig.",
	"salve": "Regenerate 30 health per second for 13 seconds. Broken by damage from enemy heroes.",
	"clarity": "Regenerate 6 mana per second for 25 seconds. Broken by damage from enemy heroes.",
	"mango": "Restore 100 mana.", "faerie_fire": "Restore 85 health.", "ward": "Plant an invisible ward that sees 1600 range for 6 minutes.",
	"chop": "Chop down a tree within 350 range; it grows back after 3 minutes. Passive: bonus attack damage against creeps.",
	"stick": "Restore 15 health and mana per charge. Charges when enemy heroes cast spells nearby.",
	"berserk": "Frenzy: +100 attack speed and +6% movement speed (+12% for melee heroes), but -7 armor for 6 seconds. Costs 25 mana.",
	"switch": "Switch the bonus between strength, intelligence and agility.",
	"slip": "For 3 seconds, walk through units and move 20% faster (10% for ranged heroes). 8 second cooldown.",
	"restore": "Restore 150 mana to yourself and allies within 1200. 55 second cooldown.",
	"mend": "Heal yourself and allies within 1200 for 250. Costs 100 mana, 50 second cooldown.",
	"spikes": "For 5.5 seconds, 85% of all damage you take is sent back to whoever dealt it. Costs 25 mana, 25 second cooldown.",
	"gold": "Kill an enemy creep (not an ancient) within 600 and gain 160 gold. Two charges, one comes back every 90 seconds.",
	"push": "Push a unit 600 forward the way it faces, cutting trees in its path. Range 550 on allies (or yourself), 850 on enemies. Costs 150 mana, 19 second cooldown.",
	"shield": "Immune to debuffs (stuns, slows, pushes) and 60% magic resistance; removes slows and silences. Lasts 9 seconds, one second less each use down to 7. Costs 50 mana, 95 second cooldown.",
	"jump": "Teleport to a point up to 1200 away (a farther point jumps 960 toward it). Disabled for 3 seconds after taking damage from an enemy hero. 15 second cooldown.",
	"sneak": "Turn invisible after 0.3 seconds for 17 seconds and move 20% faster. Attacking breaks it and the attack deals 175 extra damage. Costs 75 mana, 25 second cooldown."}

const PASSIVE_TEXT := {"pierce": "Attacks have a 25% chance to never miss and deal 60 extra magic damage.",
	"corruption": "Attacks lower the target's armor (the stronger of these items counts).",
	"chain": "Attacks have a 25% chance to throw lightning: 110 magic damage, jumping to 4 enemies.",
	"cleave": "Melee heroes: attacks also hit enemies in front for 60% of the damage (40% to creeps).",
	"block": "60% chance to block 50 damage from each attack (25 for ranged heroes).",
	"spikes": "Attackers take back 10 + 15% of the damage of their attacks."}

func item_tip(id: String, h: SimUnit, wrap := 320.0) -> Array:
	var d := SimData.item(id)
	var lines: Array = [[String(d.name), 20, U.GOLD, "title"]]
	lines.append(["Cost %d" % int(d.cost), 14, U.GOLD, "bold"])
	if d.has("recipe_for"):
		lines.append(["Combine with the parts of %s." % String(SimData.item(d.recipe_for).name), 14, U.TEXT, "body"])
	var melee := h == null or not h.is_ranged()
	var stats: Dictionary = d.stats.duplicate()
	for k in d.get("stats_melee" if melee else "stats_ranged", {}):
		stats[k] = float(stats.get(k, 0.0)) + float(d.get("stats_melee" if melee else "stats_ranged")[k])
	for k in stats:
		var v := float(stats[k])
		var label := String(STAT_NAMES.get(k, String(k).replace("_", " ").capitalize()))
		var pct: bool = k.ends_with("pct") or k == "lifesteal" or k == "magic_resist" or k == "evasion"
		var vs := ("+%d%%" % roundi(v * 100.0)) if pct else "+" + str(snappedf(v, 0.01)).trim_suffix(".0")
		lines.append([vs + " " + label, 15, U.TEXT, "body"])
	if d.has("stats_melee"):
		lines.append(["(melee and ranged heroes get different amounts)", 12, U.TEXT_DIM, "body"])
	var v: Dictionary = d.values
	if d.has("attr_from"):
		var cur := ""
		if h != null:
			for it in h.inventory:
				if it != null and it.id == id:
					cur = String(it.get("attr", ""))
		lines.append(["+%d to the chosen attribute%s" % [int(v.attr_bonus), (": " + {"str": "Strength", "agi": "Agility", "int": "Intelligence"}.get(cur, "")) if cur != "" else ""], 15, U.TEXT, "body"])
	if d.has("aura"):
		var aura := "+%s mana regen" % str(v.aura_mana_regen) if d.aura == "mana" else "+%s health regen" % str(v.aura_hp_regen)
		lines.append(["Aura: %s to allies within %d" % [aura, int(v.aura_radius)], 14, Color(0.75, 0.85, 1.0), "body"])
	var use := String(d.use)
	if ITEM_TEXT.has(use):
		for l in U.wrap(String(ITEM_TEXT[use]), wrap, 14):
			lines.append([l, 14, Color(0.75, 0.9, 0.75), "body"])
	var pas := String(d.get("passive", ""))
	if PASSIVE_TEXT.has(pas):
		var txt := String(PASSIVE_TEXT[pas])
		if pas == "corruption":
			txt = "Attacks lower the target's armor by %d for %d seconds (the stronger of these items counts)." % [int(v.armor_reduction), int(v.duration)]
			if v.has("max_damage"):
				txt += " Gains 2 damage for each corrupted enemy hero you kill (1 for an assist), up to 30."
		for l in U.wrap("Passive: " + txt, wrap, 14):
			lines.append([l, 14, Color(0.85, 0.8, 0.65), "body"])
	if String(d.get("grants", "")) == "scepter":
		lines.append(["Upgrades your hero's abilities while carried.", 14, Color(0.75, 0.9, 0.75), "body"])
	elif String(d.get("grants", "")) == "shard":
		lines.append(["Used at once: upgrades your hero's abilities for good. On sale from 15:00.", 14, Color(0.75, 0.9, 0.75), "body"])
	if not (d.components as Array).is_empty():
		var names := []
		for c in d.components:
			names.append(String(SimData.item(c).name))
		lines.append(["Made from: " + ", ".join(names) + (" + recipe %d" % int(d.recipe_cost) if int(d.recipe_cost) > 0 else ""), 12, U.TEXT_DIM, "body"])
	return lines

# ======================================================================================================================

class Minimap extends Control:
	const S := 272.0
	var hud
	var _base: ImageTexture
	var _fog_img: Image
	var _fog_tex: ImageTexture
	var _fog_t := 0.0
	var _fog_rect: TextureRect
	var _drag := false

	func _ready() -> void:
		size = Vector2(S, S)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _to_mm(p: Vector2) -> Vector2:
		return Vector2((p.x + SimMap.HALF) / (2.0 * SimMap.HALF), 1.0 - (p.y + SimMap.HALF) / (2.0 * SimMap.HALF)) * S

	func _from_mm(m: Vector2) -> Vector2:
		return Vector2(m.x / S * 2.0 * SimMap.HALF - SimMap.HALF, (1.0 - m.y / S) * 2.0 * SimMap.HALF - SimMap.HALF)

	func _build_base() -> void:
		var map: SimMap = hud.game.map
		var n := SimMap.N
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for cy in n:
			for cx in n:
				var p := map.cell_center(cx, cy)
				var l := map.level[cy * n + cx]
				var c := Color(0.27, 0.42, 0.2)
				if (p.x + p.y) > 600.0:
					c = Color(0.3, 0.3, 0.22)
				if l == SimMap.RIVER:
					c = Color(0.18, 0.42, 0.58)
				elif l == SimMap.HIGH:
					c = Color(0.52, 0.5, 0.42) if p.x + p.y < 0.0 else Color(0.36, 0.3, 0.3)
				if map.tree_cell[cy * n + cx] >= 0:
					c = Color(0.12, 0.26, 0.1) if (p.x + p.y) < 600.0 else Color(0.2, 0.14, 0.16)
				elif map.is_cliff_cell(cx, cy):
					c = Color(0.25, 0.22, 0.2)
				img.set_pixel(cx, n - 1 - cy, c)
		# lanes
		for k in map.lanes:
			for line in [map.lanes[k], _neg(map.lanes[k])]:
				for i in line.size() - 1:
					var a: Vector2 = line[i]
					var b: Vector2 = line[i + 1]
					var steps := int(a.distance_to(b) / 40.0)
					for s in steps:
						var q := a.lerp(b, float(s) / steps)
						var c2 := map.world_to_cell(q)
						for oy in range(-2, 3):
							for ox in range(-2, 3):
								var x := clampi(c2.x + ox, 0, n - 1)
								var y := clampi(n - 1 - c2.y + oy, 0, n - 1)
								img.set_pixel(x, y, Color(0.6, 0.52, 0.38))
		_base = ImageTexture.create_from_image(img)
		_fog_img = Image.create(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8)
		_fog_tex = ImageTexture.create_from_image(_fog_img)
		# the vision grid (0 / 1 bytes, south row first) is drawn through a small shader: flip, scale, darken
		_fog_rect = TextureRect.new()
		_fog_rect.texture = _fog_tex
		_fog_rect.size = Vector2(S, S)
		_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;
void fragment() { float v = clamp(texture(TEXTURE, vec2(UV.x, 1.0 - UV.y)).r * 255.0, 0.0, 1.0); COLOR = vec4(0.02, 0.03, 0.05, (1.0 - v) * 0.6); }"
		sm.shader = sh
		_fog_rect.material = sm
		_fog_rect.show_behind_parent = false
		add_child(_fog_rect)

	func _neg(a: PackedVector2Array) -> PackedVector2Array:
		var o := PackedVector2Array()
		for p in a:
			o.append(-p)
		return o

	func _draw() -> void:
		if hud.game == null or hud.game.world == null:
			return
		if _base == null:
			_build_base()
		var w: SimWorld = hud.game.world
		var team: int = hud.game.player_team
		U.panel(self, Rect2(-6, -6, S + 12, S + 12), U.GOLD_DIM, 4)
		draw_texture_rect(_base, Rect2(Vector2.ZERO, Vector2(S, S)), false)
		_fog_t -= get_process_delta_time()
		if _fog_t <= 0.0:
			_fog_t = 0.2
			_fog_img.set_data(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8, w.vision.visible[team])
			_fog_tex.update(_fog_img)
		for u in w.units:
			if not u.alive:
				continue
			var p := _to_mm(u.pos)
			var seen := u.team == team or w.vision.sees(team, u)
			if u.is_building():
				var col := U.DAWN if u.team == 0 else U.DUSK
				var sz := 7.0 if u.kind == K.TOWER else (11.0 if u.kind == K.ANCIENT else 6.0)
				if u.kind == K.FOUNTAIN:
					continue
				draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0, 0, 0, 0.8))
				draw_rect(Rect2(p - Vector2(sz - 2, sz - 2) * 0.5, Vector2(sz - 2, sz - 2)), col)
				continue
			if not seen:
				continue
			if u.is_hero():
				var col2 := U.DAWN if u.team == 0 else U.DUSK
				if u.player:
					col2 = Color(0.35, 1.0, 0.45)
				draw_circle(p, 6.5, Color(0, 0, 0, 0.9))
				draw_circle(p, 5.0, col2)
				if u.team != team and w.vision.revealed_to(u, team):
					draw_arc(p, 9.0, 0.0, TAU, 20, Color(0.75, 0.4, 1.0), 2.0)
			elif u.team == C.NEUTRAL:
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.95, 0.85, 0.35))
			elif u.kind == K.WARD:
				draw_circle(p, 3.0, Color(1.0, 0.9, 0.3))
			else:
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), (U.DAWN if u.team == 0 else U.DUSK).lightened(0.1))
		# neutral camps: Dota's tier marks (a triangle; one bar for medium, two for large, a triangle in a triangle for
		# ancient); with Shift held, the spawn boxes too
		var show_boxes: bool = hud.game.camps != null and hud.game.camps.boxes_wanted()
		for c in w.map.camps:
			_camp_mark(c, show_boxes)
		# pings from the whole team: pulsing rings for three seconds (gold: here, red: attack or danger, green: defend)
		for pg in w.pings:
			var age: float = w.time - float(pg.t)
			if int(pg.team) != team or age >= 3.0:
				continue
			var mp := _to_mm(pg.pos)
			var k := fmod(age, 0.75) / 0.75
			var pc: Color = {"attack": Color(1.0, 0.35, 0.3), "danger": Color(1.0, 0.2, 0.2), "defend": Color(0.4, 1.0, 0.5)}.get(String(pg.kind), Color(1.0, 0.85, 0.3))
			draw_arc(mp, 4.0 + k * 14.0, 0.0, TAU, 24, Color(pc, 1.0 - k), 2.0)
			draw_circle(mp, 3.0, pc)
			if String(pg.kind) == "danger":
				U.text_c(self, "!", mp + Vector2(0, -8), 16, pc, "bold")
		# camera frame
		var cam: CameraRig = hud.game.camera
		var vs := get_viewport_rect().size
		var corners := [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y - BottomPanel.H * 0.5), Vector2(0, vs.y - BottomPanel.H * 0.5)]
		var pts := PackedVector2Array()
		for c in corners:
			pts.append(_to_mm(cam.ground_at(c)))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 1.5)
		# glyph button
		var gr := Rect2(S - 38, -46, 38, 38)
		U.panel(self, gr, U.GOLD_DIM, 4)
		var gi: Texture2D = U.icon("status/fortified")
		var cd := maxf(0.0, w.glyph_ready_at[team] - w.time)
		if gi:
			draw_texture_rect(gi, gr.grow(-6), false, U.GOLD if cd <= 0.0 else Color(0.4, 0.4, 0.4))
		if cd > 0.0:
			U.text_c(self, str(ceili(cd)), gr.get_center() + Vector2(0, 6), 14, Color(1, 1, 1), "bold")
		if gr.has_point(get_local_mouse_position()):
			hud.show_tip(get_global_mouse_position(), [["Fortify", 18, U.GOLD, "title"],
				["Your buildings take no damage for 7 seconds and your lane creeps for 3.", 14, U.TEXT, "body"],
				["Tier 2+ towers attack 5 extra targets. Cooldown 5 minutes. (%s)" % Keybinds.key_name("glyph"), 13, U.TEXT_DIM, "body"]])

	func _camp_mark(c: Dictionary, boxes: bool) -> void:
		var p := _to_mm(c.pos)
		var col := Color(1.0, 0.86, 0.35, 0.95)
		var sz := 5.0 if c.kind != "ancient" else 7.0
		var tri := PackedVector2Array([p + Vector2(0, -sz), p + Vector2(sz * 0.9, sz * 0.6), p + Vector2(-sz * 0.9, sz * 0.6)])
		draw_colored_polygon(tri, Color(0, 0, 0, 0.75))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), col, 1.4)
		match String(c.kind):
			"medium":
				draw_line(p + Vector2(-sz * 0.8, sz + 2.0), p + Vector2(sz * 0.8, sz + 2.0), col, 1.4)
			"large":
				draw_line(p + Vector2(-sz * 0.8, sz + 2.0), p + Vector2(sz * 0.8, sz + 2.0), col, 1.4)
				draw_line(p + Vector2(-sz * 0.8, sz + 4.5), p + Vector2(sz * 0.8, sz + 4.5), col, 1.4)
			"ancient":
				var t2 := PackedVector2Array([p + Vector2(0, -sz * 0.45), p + Vector2(sz * 0.4, sz * 0.3), p + Vector2(-sz * 0.4, sz * 0.3), p + Vector2(0, -sz * 0.45)])
				draw_polyline(t2, col, 1.2)
		if boxes:
			var b: Vector2 = c.box
			var a2 := _to_mm((c.pos as Vector2) + Vector2(-b.x, b.y))
			var b2 := _to_mm((c.pos as Vector2) + Vector2(b.x, -b.y))
			draw_rect(Rect2(a2, b2 - a2), Color(1.0, 0.86, 0.3, 0.9), false, 1.2)

	func _gui_input(e: InputEvent) -> void:
		var gr := Rect2(S - 38, -46, 38, 38)
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and gr.has_point(mb.position):
				hud.game.world.glyph(hud.game.player_team)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.alt_pressed:
				hud.game.input.ping(_from_mm(mb.position), -1, mb.ctrl_pressed)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed and hud.game.input.targeting != "":
					hud.game.input.target_point(_from_mm(mb.position), mb.shift_pressed)
					accept_event()
					return
				_drag = mb.pressed
				if mb.pressed:
					_focus(mb.position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var h: SimUnit = hud.hero()
				hud.game.input.move_selected(_from_mm(mb.position), mb.shift_pressed)
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_focus((e as InputEventMouseMotion).position)
			accept_event()

	func _focus(m: Vector2) -> void:
		var p := _from_mm(Vector2(clampf(m.x, 0, S), clampf(m.y, 0, S)))
		hud.game.camera.focus(View.to3(p, hud.game.terrain.height_at(p)))

# ======================================================================================================================

class TopBar extends Control:
	const W := 1040.0
	var hud

	func _ready() -> void:
		size = Vector2(W, 70)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		if hud.game == null or hud.game.world == null:
			return
		var w: SimWorld = hud.game.world
		U.panel(self, Rect2(W * 0.5 - 90, -8, 180, 66), U.GOLD_DIM, 8)
		U.text_c(self, w.clock_text(), Vector2(W * 0.5, 30), 26, U.TEXT, "bold")
		var night := w.is_night()
		var ic: Texture2D = U.icon("status/frozen" if night else "status/empowered")
		var cyc := fposmod(w.time, C.DAY_LENGTH * 0.5) / (C.DAY_LENGTH * 0.5) if w.time >= 0.0 else 0.0
		U.text_c(self, ("Night" if night else "Day"), Vector2(W * 0.5, 50), 13, Color(0.6, 0.75, 1.0) if night else Color(1.0, 0.85, 0.4), "title")
		draw_rect(Rect2(W * 0.5 - 60, 54, 120, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(W * 0.5 - 60, 54, 120 * cyc, 3), Color(0.6, 0.75, 1.0) if night else Color(1.0, 0.85, 0.4))
		var kills := [0, 0]
		for h in w.heroes:
			kills[h.team] += h.kills
		U.panel(self, Rect2(W * 0.5 - 220, 0, 120, 46), Color(0.25, 0.4, 0.6), 6)
		U.panel(self, Rect2(W * 0.5 + 100, 0, 120, 46), Color(0.6, 0.25, 0.22), 6)
		U.text_c(self, SimConst.TEAM_NAMES[0], Vector2(W * 0.5 - 160, 15), 11, U.DAWN, "title")
		U.text_c(self, str(kills[0]), Vector2(W * 0.5 - 160, 41), 22, U.TEXT, "bold")
		U.text_c(self, SimConst.TEAM_NAMES[1], Vector2(W * 0.5 + 160, 15), 11, U.DUSK, "title")
		U.text_c(self, str(kills[1]), Vector2(W * 0.5 + 160, 41), 22, U.TEXT, "bold")
		tiles.clear()
		var slot := [0, 0]
		for h in w.heroes:
			var i: int = slot[h.team]
			slot[h.team] += 1
			var x := W * 0.5 - 300 - i * 72 if h.team == 0 else W * 0.5 + 236 + i * 72
			var r := Rect2(x, 4, 64, 42)
			tiles.append([r, h.id])
			var col := U.DAWN if h.team == 0 else U.DUSK
			var seen: bool = h.team == hud.game.player_team or w.vision.sees(hud.game.player_team, h)
			draw_rect(r.grow(2), Color(0, 0, 0, 0.85))
			draw_rect(r, Color(0.08, 0.08, 0.1))
			var ult: String = h.abilities[3] if h.abilities.size() > 3 else ""
			var uic: Texture2D = U.ability_icon(ult) if ult != "" else null
			if uic:
				draw_texture_rect(uic, r.grow(-2), false, Color(1, 1, 1) if h.alive else Color(0.3, 0.3, 0.32))
			draw_rect(r, col, false, 2.0)
			# health under the tile (unknown in the fog)
			var hb := Rect2(r.position.x, r.end.y + 3, r.size.x, 5)
			draw_rect(hb, Color(0, 0, 0, 0.8))
			if seen and h.alive:
				draw_rect(Rect2(hb.position, Vector2(hb.size.x * h.hp / maxf(1.0, h.max_hp), hb.size.y)), Color(0.3, 0.85, 0.3) if h.team == hud.game.player_team else Color(0.9, 0.25, 0.2))
			U.text(self, str(h.level), r.position + Vector2(3, 14), 13, Color(1, 1, 1), "bold")
			if ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) <= 0.0 and h.alive:
				draw_circle(r.position + Vector2(r.size.x - 7, 7), 4.5, Color(0, 0, 0, 0.8))
				draw_circle(r.position + Vector2(r.size.x - 7, 7), 3.0, Color(1.0, 0.85, 0.35))
			if not h.alive:
				var left := maxf(0.0, h.respawn_at - w.time)
				U.text_c(self, str(ceili(left)), r.get_center() + Vector2(0, 9), 22, Color(1, 0.9, 0.85), "bold")

	var tiles: Array = []                   # [[rect, hero id]]

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			for t in tiles:
				if (t[0] as Rect2).has_point((e as InputEventMouseButton).position):
					var h: SimUnit = hud.game.world.get_unit(t[1])
					var w: SimWorld = hud.game.world
					if h and h.alive and (h.team == hud.game.player_team or w.vision.sees(hud.game.player_team, h)):
						hud.game.camera.focus(View.to3(h.pos, hud.game.terrain.height_at(h.pos)))
						hud.game.input.select([h.id])
					accept_event()
					return

# ======================================================================================================================

# ======================================================================================================================

class Tip extends Control:
	var hud

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var lines: Array = hud._tip_lines
		# panels only redraw at 20 Hz: keep showing the last tooltip while the mouse stays over them
		if lines.is_empty() and hud._last_tip.size() > 0:
			var m := get_viewport().get_mouse_position()
			for c in [hud.bottom, hud.minimap, hud.shop]:
				if c.visible and Rect2(c.global_position, c.size).has_point(m):
					lines = hud._last_tip
					break
		if lines.is_empty():
			hud._last_tip = []
		if lines.is_empty():
			return
		var wmax := 0.0
		var hsum := 14.0
		for l in lines:
			wmax = maxf(wmax, U.font(l[3]).get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x)
			hsum += float(l[1]) + 6.0
		var vs := get_viewport_rect().size
		var p: Vector2 = hud._tip_at + Vector2(18, -hsum - 10)
		p.x = clampf(p.x, 4, vs.x - wmax - 34)
		p.y = clampf(p.y, 4, vs.y - hsum - 4)
		U.panel(self, Rect2(p, Vector2(wmax + 28, hsum)), U.GOLD, 6)
		var y := p.y + 8.0
		for l in lines:
			y += float(l[1]) + 2.0
			U.text(self, l[0], Vector2(p.x + 14, y), l[1], l[2], l[3])
			y += 4.0
