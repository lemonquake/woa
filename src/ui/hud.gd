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
var portrait_vp: SubViewport
var portrait_cam: Camera3D
var _msg := ""
var _msg_t := 0.0
var _announce := ""
var _announce_sub := ""
var _announce_t := 0.0
var _tip_lines: Array = []                 # [[text, size, color, kind]]
var _tip_at := Vector2.ZERO

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
	tip = Tip.new()
	tip.hud = self
	add_child(tip)
	_portrait()

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

func _process(dt: float) -> void:
	_msg_t = maxf(0.0, _msg_t - dt)
	_announce_t = maxf(0.0, _announce_t - dt)
	var vs := get_viewport_rect().size
	bottom.position = Vector2(roundf((vs.x - BottomPanel.W) * 0.5), vs.y - BottomPanel.H)
	minimap.position = Vector2(6, vs.y - Minimap.S - 6)
	topbar.position = Vector2(roundf((vs.x - TopBar.W) * 0.5), 0)
	shop.position = Vector2(vs.x - ShopPanel.W - 10, vs.y - BottomPanel.H - ShopPanel.H - 8)
	_update_portrait()
	_tip_lines = []
	queue_redraw()
	for c in [bottom, minimap, topbar, shop, tip]:
		c.queue_redraw()

func _update_portrait() -> void:
	var h := hero()
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
		U.text_c(self, _msg, Vector2(vs.x * 0.5, vs.y - BottomPanel.H - 40), 22, Color(1.0, 0.35, 0.3, a), "bold")
	if _announce_t > 0.0:
		var a2 := clampf(_announce_t / 0.8, 0.0, 1.0)
		U.text_c(self, _announce, Vector2(vs.x * 0.5, 150), 40, Color(1.0, 0.86, 0.5, a2), "title")
		if _announce_sub != "":
			U.text_c(self, _announce_sub, Vector2(vs.x * 0.5, 184), 20, Color(0.95, 0.95, 0.95, a2), "bold")
	var h := hero()
	if h and not h.alive:
		var t := maxf(0.0, h.respawn_at - game.world.time)
		U.text_c(self, "Respawning in %d" % ceili(t), Vector2(vs.x * 0.5, vs.y * 0.42), 34, Color(1, 1, 1, 0.92), "title")
	if game.input and game.input.targeting != "":
		var lab: String = "Attack" if game.input.targeting == "attack" else "Choose a target"
		U.text(self, lab, get_viewport().get_mouse_position() + Vector2(22, 30), 16, Color(1, 0.9, 0.6), "bold")

func error(msg: String) -> void:
	_msg = msg
	_msg_t = 2.0

func announce(title: String, sub := "") -> void:
	_announce = title
	_announce_sub = sub
	_announce_t = 3.5

func on_kill(e: Dictionary) -> void:
	var w: SimWorld = game.world
	var victim := w.get_unit(e.victim)
	var killer := w.get_unit(e.u)
	var vn := _name(victim)
	if e.get("first_blood", false):
		announce("First Blood!", "%s drew first blood on %s" % [_name(killer), vn])
	elif killer:
		announce("%s killed %s" % [_name(killer), vn])
	else:
		announce("%s was killed" % vn)

func _name(u: SimUnit) -> String:
	if u == null:
		return "?"
	return String(u.look.get("display_name", u.name))

func toggle_shop() -> void:
	shop.visible = not shop.visible

## Tooltip content for this frame (drawn by Tip).
func show_tip(at: Vector2, lines: Array) -> void:
	_tip_lines = lines
	_tip_at = at

# ======================================================================================================================

class BottomPanel extends Control:
	const W := 1080.0
	const H := 206.0
	var hud
	var portrait_box: Control
	var _abil_rects: Array = []
	var _learn_rects: Array = []
	var _item_rects: Array = []
	var _shop_rect := Rect2()

	func _ready() -> void:
		size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _layout() -> void:
		_abil_rects.clear()
		_learn_rects.clear()
		for i in 4:
			var r := Rect2(352 + i * 84, 34, 76, 76)
			_abil_rects.append(r)
			_learn_rects.append(Rect2(r.position.x + 22, 8, 32, 22))
		_item_rects.clear()
		for i in 6:
			_item_rects.append(Rect2(706 + (i % 3) * 80, 30 + (i / 3) * 62, 74, 56))
		for i in 3:
			_item_rects.append(Rect2(706 + i * 80, 158, 74, 36))
		_shop_rect = Rect2(956, 132, 112, 62)

	func _draw() -> void:
		_layout()
		var h: SimUnit = hud.hero()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		U.panel(self, Rect2(0, 10, W, H - 10))
		# portrait frame and level ring
		if portrait_box:
			portrait_box.position = Vector2(14, 24)
			portrait_box.modulate = Color(1, 1, 1) if h.alive else Color(0.35, 0.35, 0.38)
		draw_rect(Rect2(12, 22, 170, 174), U.GOLD_DIM, false, 2.0)
		_level_ring(h, Vector2(22, 32))
		var nm: String = hud._name(h)
		U.text(self, nm, Vector2(24, 190), 15, U.GOLD, "title")
		_stats(h)
		_abilities(h, w)
		_bars(h)
		_items(h, w)
		_gold(h)

	func _level_ring(h: SimUnit, c: Vector2) -> void:
		draw_circle(c, 20, Color(0.04, 0.04, 0.05, 0.95))
		var need := float(C.XP_TABLE[mini(h.level, C.MAX_LEVEL - 1)]) - float(C.XP_TABLE[h.level - 1])
		var have := h.xp - float(C.XP_TABLE[h.level - 1])
		var frac := 1.0 if h.level >= C.MAX_LEVEL else clampf(have / maxf(1.0, need), 0.0, 1.0)
		draw_arc(c, 18, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(0.25, 0.22, 0.15), 4.0, true)
		draw_arc(c, 18, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(0.65, 0.4, 1.0), 4.0, true)
		U.text_c(self, str(h.level), c + Vector2(0, 7), 19, U.GOLD, "bold")
		if h.ability_points > 0:
			draw_circle(c + Vector2(16, 14), 7, Color(1.0, 0.82, 0.3))
			U.text_c(self, str(h.ability_points), c + Vector2(16, 18.5), 11, Color(0, 0, 0), "bold", false)

	func _stats(h: SimUnit) -> void:
		var x := 196.0
		var y := 44.0
		var dmg := "%d-%d" % [int(h.dmg_min), int(h.dmg_max)]
		if h.bonus_damage > 0.0:
			dmg += " +%d" % int(h.bonus_damage)
		_stat_row("ui/level", "Damage", dmg, Vector2(x, y))
		_stat_row("status/fortified", "Armor", "%.1f" % h.armor, Vector2(x, y + 24))
		_stat_row("status/haste", "Speed", str(int(h.move_speed)), Vector2(x, y + 48))
		var r := Rect2(x - 4, y + 64, 148, 64)
		draw_rect(r, Color(0, 0, 0, 0.35))
		var attrs := [["attributes/strength", h.str_total, Color(0.95, 0.35, 0.3)], ["attributes/agility", h.agi_total, Color(0.4, 0.95, 0.45)],
			["attributes/intelligence", h.int_total, Color(0.4, 0.7, 1.0)]]
		for i in 3:
			var a: Array = attrs[i]
			var p := Vector2(x + 2 + i * 48, y + 72)
			var ic: Texture2D = U.icon(a[0])
			if ic:
				draw_texture_rect(ic, Rect2(p, Vector2(22, 22)), false, a[2])
			U.text(self, str(int(a[1])), p + Vector2(2, 44), 16, U.TEXT, "bold")
		if Rect2(r.position + Vector2(0, -72), Vector2(150, 136)).has_point(get_local_mouse_position()):
			hud.show_tip(get_global_mouse_position(), [
				["Attack speed %d (%.2f s per attack)" % [int(h.attack_speed), h.attack_interval()], 14, U.TEXT, "body"],
				["Attack range %d" % int(h.attack_range), 14, U.TEXT, "body"],
				["Magic resistance %d%%" % int(h.magic_resist * 100.0), 14, U.TEXT, "body"],
				["Health regen %.1f  Mana regen %.1f" % [h.hp_regen, h.mana_regen], 14, U.TEXT, "body"],
				["Physical damage taken x%.2f" % C.armor_multiplier(h.armor), 14, U.TEXT_DIM, "body"]])

	func _stat_row(ic_path: String, label: String, val: String, p: Vector2) -> void:
		var ic: Texture2D = U.icon(ic_path)
		if ic:
			draw_texture_rect(ic, Rect2(p + Vector2(0, -15), Vector2(18, 18)), false, U.GOLD)
		U.text(self, val, p + Vector2(24, 0), 16, U.TEXT, "bold")

	func _abilities(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		for i in mini(4, h.abilities.size()):
			var aid: String = h.abilities[i]
			var a := SimData.ability(aid)
			var r: Rect2 = _abil_rects[i]
			var lv := h.ability_level_of(aid)
			var auto := bool(h.autocast.get(aid, false))
			U.slot(self, r.grow(2), auto or hud.game.input.targeting == aid)
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
			if auto:
				var t := Time.get_ticks_msec() / 1000.0
				draw_rect(r.grow(1), Color(1.0, 0.85, 0.3, 0.6 + 0.4 * sin(t * 6.0)), false, 3.0)
			U.text(self, String(a.key), r.position + Vector2(4, 15), 14, Color(1, 1, 1), "bold")
			if mana_cost > 0:
				U.text_r(self, str(int(mana_cost)), r.end + Vector2(-3, -4), 12, Color(0.55, 0.75, 1.0), "bold")
			# level pips
			var mx := int(a.max_level)
			for k in mx:
				var px := r.position.x + r.size.x * 0.5 + (k - (mx - 1) * 0.5) * 12.0
				draw_rect(Rect2(px - 4, r.end.y + 6, 8, 5), U.GOLD if k < lv else Color(0.2, 0.2, 0.22))
			if w.abilities.can_learn(h, aid):
				var lr: Rect2 = _learn_rects[i]
				var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 200.0)
				draw_rect(lr, Color(0.95, 0.75, 0.25, pulse))
				U.text_c(self, "+", lr.get_center() + Vector2(0, 8), 22, Color(0.1, 0.06, 0.0), "bold", false)
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), _ability_tip(h, aid))

	func _ability_tip(h: SimUnit, aid: String) -> Array:
		var a := SimData.ability(aid)
		var lv := h.ability_level_of(aid)
		var lines: Array = [[String(a.name), 20, U.GOLD, "title"]]
		var kind := {"autocast_attack": "Attack modifier (autocast)", "point": "Point target", "passive": "Passive",
			"unit": "Unit target", "no_target": "No target"}
		lines.append([String(kind.get(a.behavior, "")) + "    Level %d / %d" % [lv, int(a.max_level)], 13, U.TEXT_DIM, "body"])
		for l in U.wrap(String(a.desc), 330, 15):
			lines.append([l, 15, U.TEXT, "body"])
		for k in a.values:
			var vals: Array = a.values[k]
			var parts := []
			for v in vals:
				var fv := float(v)
				parts.append(("%d%%" % roundi(fv * 100.0)) if fv > 0.0 and fv < 1.0 and (k.contains("slow") or k.ends_with("pct")) else str(v))
			lines.append(["%s: %s" % [k.replace("_", " ").capitalize(), " / ".join(parts)], 13, Color(0.8, 0.85, 0.75), "body"])
		if a.behavior != "passive":
			lines.append(["Mana: %s    Cooldown: %s" % [" / ".join(a.mana.map(func(x): return str(x))), " / ".join(a.cooldown.map(func(x): return str(x)))], 13, Color(0.6, 0.75, 1.0), "body"])
		if a.behavior == "autocast_attack":
			lines.append(["Right-click to toggle autocast. Cast by hand on a hero to attack without drawing creep aggro.", 12, U.TEXT_DIM, "body"])
		lines.append(["Ctrl + %s to learn" % a.key, 12, U.TEXT_DIM, "body"])
		return lines

	func _bars(h: SimUnit) -> void:
		var hr := Rect2(352, 132, 330, 24)
		U.bar(self, hr, h.hp / maxf(1.0, h.max_hp), U.HP)
		U.text_c(self, "%d / %d" % [int(h.hp), int(h.max_hp)], hr.get_center() + Vector2(0, 7), 16, U.TEXT, "bold")
		U.text_r(self, "+%.1f" % h.hp_regen, Vector2(hr.end.x - 4, hr.position.y + 17), 12, Color(0.8, 1.0, 0.8), "body")
		var mr := Rect2(352, 162, 330, 20)
		U.bar(self, mr, h.mana / maxf(1.0, h.max_mana), U.MANA)
		U.text_c(self, "%d / %d" % [int(h.mana), int(h.max_mana)], mr.get_center() + Vector2(0, 6), 14, U.TEXT, "bold")
		U.text_r(self, "+%.1f" % h.mana_regen, Vector2(mr.end.x - 4, mr.position.y + 15), 12, Color(0.8, 0.88, 1.0), "body")

	func _items(h: SimUnit, w: SimWorld) -> void:
		var keys := ["Z", "X", "C", "V", "B", "N"]
		var m := get_local_mouse_position()
		for i in 9:
			var r: Rect2 = _item_rects[i]
			U.slot(self, r)
			var it = h.inventory[i]
			if it == null:
				if i < 6:
					U.text(self, keys[i], r.position + Vector2(4, 14), 11, Color(0.5, 0.5, 0.5), "bold")
				continue
			var ic: Texture2D = U.item_icon(it.id)
			var dim := Color(1, 1, 1) if i < 6 else Color(0.5, 0.5, 0.5)
			if ic:
				var sq := minf(r.size.x, r.size.y) - 6
				draw_texture_rect(ic, Rect2(r.get_center() - Vector2(sq, sq) * 0.5, Vector2(sq, sq)), false, dim)
			if i < 6:
				var cd := w.abilities.item_cooldown_left(h, i)
				var d := SimData.item(it.id)
				if cd > 0.0 and float(d.cooldown) > 0.0:
					U.cooldown(self, r, cd / float(d.cooldown), cd)
				U.text(self, keys[i], r.position + Vector2(4, 14), 11, Color(1, 1, 1), "bold")
			if int(it.get("charges", 0)) > 1 or SimData.item(it.id).consumable and int(it.get("charges", 0)) > 0:
				U.text_r(self, str(it.charges), r.end + Vector2(-3, -3), 14, Color(1, 1, 1), "bold")
			if String(SimData.item(it.id).use) == "stick":
				U.text_r(self, str(h.stick_charges), r.end + Vector2(-3, -3), 14, Color(0.7, 0.9, 1.0), "bold")
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), hud.item_tip(it.id, h))

	func _gold(h: SimUnit) -> void:
		var gi: Texture2D = U.icon("ui/gold")
		if gi:
			draw_texture_rect(gi, Rect2(960, 40, 26, 26), false, U.GOLD)
		U.text(self, str(h.gold()), Vector2(992, 62), 24, U.GOLD, "bold")
		U.text(self, "reliable %d" % h.gold_reliable, Vector2(960, 86), 12, U.TEXT_DIM, "body")
		var hover := _shop_rect.has_point(get_local_mouse_position())
		U.panel(self, _shop_rect, U.GOLD if hover else U.GOLD_DIM, 4)
		var si: Texture2D = U.icon("ui/shop")
		if si:
			draw_texture_rect(si, Rect2(_shop_rect.position + Vector2(8, 14), Vector2(32, 32)), false, U.GOLD)
		U.text(self, "Shop", _shop_rect.position + Vector2(48, 38), 18, U.GOLD, "title")

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		var p := mb.position
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
						hud.game.input.begin_ability(aid)
				accept_event()
				return
		for i in 9:
			if (_item_rects[i] as Rect2).has_point(p):
				if mb.button_index == MOUSE_BUTTON_LEFT and i < 6:
					hud.game.input.use_item(i)
				elif mb.button_index == MOUSE_BUTTON_RIGHT:
					# right-click moves an item between the inventory and the backpack
					var dest := -1
					var lo := 6 if i < 6 else 0
					var hi := 9 if i < 6 else 6
					for k in range(lo, hi):
						if h.inventory[k] == null:
							dest = k
							break
					if dest >= 0:
						w.shop.swap(h, i, dest)
				accept_event()
				return
		if _shop_rect.has_point(p):
			hud.toggle_shop()
			accept_event()

func item_tip(id: String, h: SimUnit) -> Array:
	var d := SimData.item(id)
	var lines: Array = [[String(d.name), 20, U.GOLD, "title"]]
	lines.append(["Cost %d" % int(d.cost), 14, U.GOLD, "bold"])
	for k in d.stats:
		var v = d.stats[k]
		var label := String(k).replace("_", " ").capitalize()
		var vs := ("+%d%%" % int(v * 100)) if float(v) < 1.0 and (k.ends_with("pct") or k == "lifesteal") else "+" + str(v)
		lines.append([vs + " " + label, 15, U.TEXT, "body"])
	var use := String(d.use)
	var desc := {"tango": "Eat a tree to regenerate 7 health per second for 16 seconds.",
		"salve": "Regenerate 30 health per second for 13 seconds. Broken by damage from enemy heroes.",
		"clarity": "Regenerate 6 mana per second for 25 seconds. Broken by damage from enemy heroes.",
		"mango": "Restore 100 mana.", "faerie_fire": "Restore 85 health.", "ward": "Plant an invisible ward that sees 1600 range for 6 minutes.",
		"chop": "Cut down a tree. Bonus attack damage against creeps.", "stick": "Restore 15 health and mana per charge. Charges when enemy heroes cast spells nearby.",
		"berserk": "Frenzy: +100 attack speed and +6% movement speed, but -7 armor for 6 seconds."}
	if desc.has(use):
		for l in U.wrap(String(desc[use]), 320, 14):
			lines.append([l, 14, Color(0.75, 0.9, 0.75), "body"])
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
			elif u.team == C.NEUTRAL:
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.95, 0.85, 0.35))
			elif u.kind == K.WARD:
				draw_circle(p, 3.0, Color(1.0, 0.9, 0.3))
			else:
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), (U.DAWN if u.team == 0 else U.DUSK).lightened(0.1))
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
			hud.show_tip(get_global_mouse_position(), [["Glyph of Fortification", 18, U.GOLD, "title"],
				["Your buildings take no damage for 7 seconds and your lane creeps for 3.", 14, U.TEXT, "body"],
				["Tier 2+ towers attack 5 extra targets. Cooldown 5 minutes. (J)", 13, U.TEXT_DIM, "body"]])

	func _gui_input(e: InputEvent) -> void:
		var gr := Rect2(S - 38, -46, 38, 38)
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and gr.has_point(mb.position):
				hud.game.world.glyph(hud.game.player_team)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
				if mb.pressed:
					_focus(mb.position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var h: SimUnit = hud.hero()
				hud.game.world.command(h.id, {"type": O.MOVE, "point": _from_mm(mb.position)})
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_focus((e as InputEventMouseMotion).position)
			accept_event()

	func _focus(m: Vector2) -> void:
		var p := _from_mm(Vector2(clampf(m.x, 0, S), clampf(m.y, 0, S)))
		hud.game.camera.focus(View.to3(p, hud.game.terrain.height_at(p)))

# ======================================================================================================================

class TopBar extends Control:
	const W := 640.0
	var hud

	func _ready() -> void:
		size = Vector2(W, 70)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

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
		U.text_c(self, "Dawn", Vector2(W * 0.5 - 180, 18), 13, U.DAWN, "title")
		U.text_c(self, str(kills[0]), Vector2(W * 0.5 - 130, 34), 26, U.TEXT, "bold")
		U.text_c(self, "Dusk", Vector2(W * 0.5 + 140, 18), 13, U.DUSK, "title")
		U.text_c(self, str(kills[1]), Vector2(W * 0.5 + 190, 34), 26, U.TEXT, "bold")
		for h in w.heroes:
			var x := W * 0.5 - 175 if h.team == 0 else W * 0.5 + 145
			var col := U.DAWN if h.team == 0 else U.DUSK
			draw_circle(Vector2(x, 34), 9, Color(0, 0, 0, 0.8))
			draw_circle(Vector2(x, 34), 7, col if h.alive else Color(0.3, 0.3, 0.3))
			U.text_c(self, str(h.level), Vector2(x, 38), 10, Color(0, 0, 0), "bold", false)

# ======================================================================================================================

class ShopPanel extends Control:
	const W := 560.0
	const H := 600.0
	const CATS := [["consumables", "Consumables"], ["attributes", "Attributes"], ["armaments", "Armaments"],
		["misc", "Arcane"], ["upgrades", "Upgrades"], ["basics", "Basics"]]
	var hud
	var _rects := {}

	func _ready() -> void:
		size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var h: SimUnit = hud.hero()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		U.panel(self, Rect2(Vector2.ZERO, size), U.GOLD, 8)
		U.text(self, "Shop", Vector2(18, 34), 26, U.GOLD, "title")
		var here := w.shop.in_shop(h)
		U.text(self, "Items go straight to you" if here else "Not at a shop: purchases go to your stash", Vector2(110, 32), 13, Color(0.7, 0.9, 0.7) if here else Color(1.0, 0.7, 0.5), "body")
		U.text_r(self, "%d gold" % h.gold(), Vector2(W - 18, 34), 18, U.GOLD, "bold")
		_rects.clear()
		var y := 56.0
		var m := get_local_mouse_position()
		for cat in CATS:
			var ids: Array = []
			for id in SimData.items():
				var d := SimData.item(id)
				if String(d.category) == cat[0] and int(d.cost) > 0 or String(d.category) == cat[0] and id == "observer_ward":
					ids.append(id)
			if ids.is_empty():
				continue
			U.text(self, cat[1], Vector2(18, y + 16), 15, U.GOLD, "title")
			y += 24
			var x := 18.0
			for id in ids:
				if x + 62 > W - 10:
					x = 18.0
					y += 70
				var r := Rect2(x, y, 60, 46)
				_rects[id] = r
				var price := w.shop.price(h, id)
				var afford := h.gold() >= price
				U.slot(self, r, r.has_point(m))
				var ic: Texture2D = U.item_icon(id)
				if ic:
					draw_texture_rect(ic, Rect2(r.position + Vector2(10, 2), Vector2(42, 42)), false, Color(1, 1, 1) if afford else Color(0.5, 0.5, 0.5))
				U.text_c(self, str(price), Vector2(r.get_center().x, r.end.y + 15), 13, U.GOLD if afford else Color(0.6, 0.5, 0.4), "bold")
				if r.has_point(m):
					hud.show_tip(get_global_mouse_position(), hud.item_tip(id, h))
				x += 68
			y += 76
		# stash
		var stash_y := H - 66
		U.text(self, "Stash", Vector2(18, stash_y - 6), 14, U.TEXT_DIM, "title")
		for i in 6:
			var r2 := Rect2(18 + i * 66, stash_y, 60, 46)
			U.slot(self, r2)
			var it = h.stash[i]
			if it != null:
				var ic2: Texture2D = U.item_icon(it.id)
				if ic2:
					draw_texture_rect(ic2, Rect2(r2.position + Vector2(10, 2), Vector2(42, 42)), false)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var mb := e as InputEventMouseButton
			for id in _rects:
				if (_rects[id] as Rect2).has_point(mb.position):
					var err: String = hud.game.world.shop.buy(hud.hero(), id)
					if err != "":
						hud.error(err)
					accept_event()
					return
			accept_event()

# ======================================================================================================================

class Tip extends Control:
	var hud

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var lines: Array = hud._tip_lines
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
