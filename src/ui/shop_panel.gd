class_name ShopPanel
extends Control
## The shop, laid out like Dota's: Basics and Upgrades tabs with item columns, a search box, and a pane that shows
## the selected item (price, bonuses, what it is made from and what it builds into) with Buy, or Sell for an item
## the hero carries. Left click selects, right click (or double click) buys, Shift + click adds the item to the To Buy
## list broken into the parts still missing. The stash is at the bottom: click a stashed item to take it (in the
## base), right click to sell it (from anywhere).

const U = preload("res://src/ui/ui_kit.gd")
const W := 950.0
const H := 700.0
const GRID_W := 650.0
const CELL := Vector2(54, 40)
const STEP := Vector2(58, 58)

## Basics: [category, heading, column]. Several groups may share a column; they stack top to bottom.
const BASICS := [["consumables", "Consumables", 0], ["big_parts", "Big Parts", 4], ["attributes", "Attributes", 1],
	["armaments", "Armaments", 2], ["misc", "Magic", 3], ["basics", "Other", 3]]
## Big Parts sit in a fifth column of their own (BASICS_BIG_COL) so the first column keeps room for consumables.
## Upgrades in Dota-like groups: [column, heading, item ids]
const UPGRADES := [
	[0, "Accessories", ["wraith_band", "tough_band", "smart_band", "magic_wand", "power_treads", "slip_boots",
		"steady_ring", "mask_of_madness"]],
	[0, "Swords", ["heavy_sword", "yasha", "spell_sword", "twin_swords", "kugmo_atuli", "igit_atuli"]],
	[1, "Support", ["mana_ring", "leaf_hat", "mana_boots", "medic_kit", "push_staff", "gold_glove", "small_shield",
		"leech_totem", "war_drum", "team_shield"]],
	[1, "Magic", ["battle_staff", "silence_staff", "root_staff", "hex_staff"]],
	[2, "Weapons", ["crit_sword", "crit_bow", "stun_club", "stun_blade", "sure_hit_staff", "armor_breaker",
		"shock_hammer", "cleave_axe", "sneak_blade", "break_blade", "dragon_lance"]],
	[3, "Armor", ["block_shield", "spike_armor", "spell_shield", "halberd", "battle_armor", "frost_plate", "giant_heart"]],
	[3, "Abilities", ["upgrade_staff", "upgrade_gem"]],
	[4, "Casting", ["dagon", "net_staff", "long_lens", "soul_gem", "time_crystal", "refresh_stone"]],
	[4, "Big Weapons", ["storm_hammer", "burning_cape", "leech_blade", "moth_blade", "crash_knife"]],
	[4, "Boots", ["travel_boots", "guard_boots"]],
]

var hud
var tab := "basics"
var selected := ""                         # item id shown in the pane
var sell_slot := -1                        # an inventory slot picked for selling (then `selected` is its item)
var _search: LineEdit
var _rects := {}                           # item id -> Rect2 in the grid
var _pane_rects: Array = []                # [rect, action, value]
var _last_click := {"id": "", "t": 0}

func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.position = Vector2(W - 300, 58)
	_search.size = Vector2(286, 32)
	_search.theme = U.theme()
	_search.add_theme_font_size_override("font_size", 15)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): queue_redraw())
	add_child(_search)

func _hero() -> SimUnit:
	return hud.hero()

## Items shown in the grid for the current tab or search: [[x column, heading, ids], ...]
func _columns() -> Array:
	var q := _search.text.strip_edges().to_lower() if _search else ""
	if q != "":
		var hits: Array = []
		for id in SimData.items():
			var d := SimData.item(id)
			if String(d.category) == "recipe" or (int(d.cost) <= 0 and id != "observer_ward"):
				continue
			if String(d.name).to_lower().contains(q):
				hits.append(id)
		return [[-1, "Results", hits]]
	if tab == "upgrades":
		return UPGRADES
	var out: Array = []
	for cat in BASICS:
		var ids: Array = []
		for id in SimData.items():
			var d := SimData.item(id)
			if String(d.category) == cat[0] and (int(d.cost) > 0 or id == "observer_ward"):
				ids.append(id)
		if not ids.is_empty():
			out.append([int(cat[2]), cat[1], ids])
	return out

func _draw() -> void:
	var h := _hero()
	if h == null:
		return
	var w: SimWorld = hud.game.world
	var m := get_local_mouse_position()
	U.panel(self, Rect2(Vector2.ZERO, size), U.GOLD, 8)
	U.text(self, "Shop", Vector2(18, 36), 26, U.GOLD, "title")
	var here := w.shop.in_shop(h)
	U.text(self, "Items go straight to you" if here else "Not at a shop: purchases go to your stash", Vector2(108, 34), 13,
		Color(0.7, 0.9, 0.7) if here else Color(1.0, 0.7, 0.5), "body")
	U.text_r(self, "%d gold" % h.gold(), Vector2(W - 70, 36), 19, U.GOLD, "bold")
	_pane_rects.clear()
	var close := Rect2(W - 54, 14, 40, 30)
	U.slot(self, close, close.has_point(m))
	U.text_c(self, "X", close.get_center() + Vector2(0, 7), 17, U.TEXT, "bold")
	_pane_rects.append([close, "close", ""])
	# tabs
	var tx := 18.0
	for t in [["basics", "Basics"], ["upgrades", "Upgrades"]]:
		var r := Rect2(tx, 58, 120, 32)
		var on: bool = tab == t[0] and _search.text.strip_edges() == ""
		U.panel(self, r, U.GOLD if on else U.GOLD_DIM, 4)
		U.text_c(self, t[1], r.get_center() + Vector2(0, 6), 16, U.GOLD if on else U.TEXT_DIM, "title")
		_pane_rects.append([r, "tab", t[0]])
		tx += 128.0
	_draw_grid(h, w, m)
	_draw_pane(h, w, m)
	_draw_stash(h, w, m)

func _draw_grid(h: SimUnit, w: SimWorld, m: Vector2) -> void:
	_rects.clear()
	var cols := _columns()
	var col_x := [18.0, 148.0, 278.0, 408.0, 538.0]
	var col_y := [104.0, 104.0, 104.0, 104.0, 104.0]
	for c in cols:
		var ids: Array = c[2]
		var ci: int = c[0]
		var x0: float = 18.0 if ci < 0 else col_x[ci]
		var y: float = 104.0 if ci < 0 else col_y[ci]
		var per_row := 10 if ci < 0 else 2
		U.text(self, String(c[1]), Vector2(x0, y + 14), 14, U.GOLD, "title")
		y += 22.0
		for i in ids.size():
			var id: String = ids[i]
			var r := Rect2(Vector2(x0 + (i % per_row) * STEP.x, y + (i / per_row) * STEP.y), CELL)
			_rects[id] = r
			var price := w.shop.price(h, id)
			var afford := h.gold() >= price
			var sel := id == selected and sell_slot < 0
			U.slot(self, r, r.has_point(m) or sel)
			if sel:
				draw_rect(r.grow(1), U.GOLD, false, 2.0)
			var ic: Texture2D = U.item_icon(id)
			if ic:
				draw_texture_rect(ic, Rect2(r.position + Vector2((CELL.x - 36) * 0.5, 2), Vector2(36, 36)), false,
					Color(1, 1, 1) if afford else Color(0.5, 0.5, 0.5))
			U.text_c(self, str(price), Vector2(r.get_center().x, r.end.y + 15), 13, U.GOLD if afford else Color(0.6, 0.5, 0.4), "bold")
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), hud.item_tip(id, h))
		var rows := ceili(ids.size() / float(per_row))
		if ci >= 0:
			col_y[ci] = y + rows * STEP.y + 10.0
	# grid / pane divider
	draw_line(Vector2(GRID_W + 10, 100), Vector2(GRID_W + 10, H - 92), U.GOLD_DIM, 1.0)

func _draw_pane(h: SimUnit, w: SimWorld, m: Vector2) -> void:
	var x := GRID_W + 24
	var pw := W - x - 16
	var y := 108.0
	if selected == "" or SimData.item(selected).is_empty():
		for l in U.wrap("Left click an item to see what it does and what it is made from. Right click buys it. Shift + click adds it to To Buy, broken into the parts you still need.", pw, 14):
			U.text(self, l, Vector2(x, y + 14), 14, U.TEXT_DIM, "body")
			y += 20
		_draw_bags(h, x, H - 228, m)
		return
	var d := SimData.item(selected)
	var ic: Texture2D = U.item_icon(selected)
	U.slot(self, Rect2(x, y, 60, 46))
	if ic:
		draw_texture_rect(ic, Rect2(x + 9, y + 2, 42, 42), false)
	U.text(self, String(d.name), Vector2(x + 70, y + 20), 18, U.GOLD, "title")
	U.text(self, "%d gold" % int(d.cost), Vector2(x + 70, y + 42), 14, U.GOLD_DIM, "bold")
	y += 58
	# what it is made from and builds into get their rows first; the text gets the room above them (the tooltip on
	# the grid shows all of it)
	var sets := SimShop.recipe_sets(selected)
	var into: Array = []
	for id in SimData.items():
		for s in SimShop.recipe_sets(id):
			if (s as Array).has(selected) and not into.has(id):
				into.append(id)
	var reserve := (72.0 if not sets.is_empty() else 0.0) + (72.0 if not into.is_empty() else 0.0)
	if (d.get("recipes", []) as Array).size() > 1:
		reserve += 46.0
	var text_end := H - 304.0 - reserve
	# bonuses and description, from the tooltip text
	var lines: Array = hud.item_tip(selected, h, pw)
	for i in range(2, lines.size()):
		var l: Array = lines[i]
		if String(l[0]).begins_with("Made from"):
			continue
		# keep one short line free for the "..." note
		if y + float(l[1]) + 3.0 > text_end - 15.0 and i < lines.size() - 1:
			U.text(self, "... (hover the item for the rest)", Vector2(x, y + 12), 12, U.TEXT_DIM, "body")
			y += 15.0
			break
		U.text(self, String(l[0]), Vector2(x, y + 14), int(l[1]) - 1, l[2], l[3])
		y += float(l[1]) + 3.0
	y += 6
	# made from
	if not sets.is_empty():
		U.text(self, "Made from", Vector2(x, y + 14), 13, U.TEXT_DIM, "title")
		y += 22
		var owned := _owned(h)
		var parts: Array = sets[0]
		if (d.get("recipes", []) as Array).size() > 1:
			# Switch Boots: show the shared parts, then the choice of attribute item
			parts = sets[0].slice(0, 2)
		var px := x
		for p in parts:
			var have: bool = owned.has(p)
			if have:
				owned.erase(p)
			_mini_icon(String(p), Vector2(px, y), have, m)
			px += 44
		if parts.size() < (sets[0] as Array).size():
			# Switch Boots: and one attribute item (each gives the boots that attribute)
			y += 46
			U.text(self, "and one of", Vector2(x, y + 25), 12, U.TEXT_DIM, "body")
			px = x + 74
			for s in sets:
				_mini_icon(String(s[2]), Vector2(px, y), owned.has(s[2]), m)
				px += 44
		y += 50
	# builds into
	if not into.is_empty():
		U.text(self, "Builds into", Vector2(x, y + 14), 13, U.TEXT_DIM, "title")
		y += 22
		var bx := x
		for id in into:
			if bx + 40 > W - 16:
				break
			_mini_icon(String(id), Vector2(bx, y), true, m)
			bx += 44
		y += 50
	# Buy or Sell
	var br := Rect2(x, H - 278, pw, 40)
	if sell_slot >= 0 and h.inventory[sell_slot] != null and h.inventory[sell_slot].id == selected:
		var it: Dictionary = h.inventory[sell_slot]
		var value := int(d.cost)
		if bool(d.consumable):
			value = int(float(d.cost) * float(it.charges) / maxf(1.0, float(d.charges)))
		var refund := value if w.time - float(it.get("bought", -99.0)) <= 10.0 else value / 2
		U.panel(self, br, U.GOLD if br.has_point(m) else U.GOLD_DIM, 4)
		U.text_c(self, "Sell for %d gold" % refund, br.get_center() + Vector2(0, 7), 17, U.TEXT, "title")
		_pane_rects.append([br, "sell", sell_slot])
	else:
		var price := w.shop.price(h, selected)
		var err := w.shop.buy_error(h, selected)
		var ok := err == "" and h.gold() >= price
		U.panel(self, br, U.GOLD if ok and br.has_point(m) else U.GOLD_DIM, 4)
		var label := "Buy for %d gold" % price if err == "" else err
		U.text_c(self, label, br.get_center() + Vector2(0, 7), 17, U.GOLD if ok else Color(0.65, 0.55, 0.45), "title")
		_pane_rects.append([br, "buy", selected])
		U.text_c(self, "Shift + click an item: add it to To Buy", br.position + Vector2(br.size.x * 0.5, -8), 12, U.TEXT_DIM, "body")
	_draw_bags(h, x, H - 228, m)

## The hero's nine slots, small: click one to sell it.
func _draw_bags(h: SimUnit, x: float, y: float, m: Vector2) -> void:
	U.text(self, "Your items (click to sell)", Vector2(x, y + 12), 13, U.TEXT_DIM, "title")
	y += 20
	for i in 9:
		var r := Rect2(x + (i % 5) * 52, y + (i / 5) * 46, 48, 40)
		var it = h.inventory[i]
		U.slot(self, r, r.has_point(m) or i == sell_slot)
		if it != null:
			var ic: Texture2D = U.item_icon(it.id)
			if ic:
				draw_texture_rect(ic, Rect2(r.position + Vector2(8, 2), Vector2(32, 32)), false,
					Color(1, 1, 1) if i < 6 else Color(0.7, 0.7, 0.7))
			_pane_rects.append([r, "pick", i])
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), hud.item_tip(it.id, h))

func _mini_icon(id: String, p: Vector2, lit: bool, m: Vector2) -> void:
	var r := Rect2(p, Vector2(40, 40))
	U.slot(self, r, r.has_point(m))
	var ic: Texture2D = U.item_icon(id)
	if ic:
		draw_texture_rect(ic, Rect2(p + Vector2(4, 4), Vector2(32, 32)), false, Color(1, 1, 1) if lit else Color(0.45, 0.45, 0.45))
	_pane_rects.append([r, "select", id])
	if r.has_point(m):
		hud.show_tip(get_global_mouse_position(), hud.item_tip(id, _hero()))

func _draw_stash(h: SimUnit, w: SimWorld, m: Vector2) -> void:
	var y := H - 76
	draw_line(Vector2(14, y - 10), Vector2(W - 14, y - 10), U.GOLD_DIM, 1.0)
	U.text(self, "Stash", Vector2(18, y + 26), 15, U.TEXT_DIM, "title")
	var here := w.shop.in_shop(h)
	for i in 6:
		var r := Rect2(90 + i * 66, y, 60, 46)
		U.slot(self, r, r.has_point(m) and h.stash[i] != null and here)
		var it = h.stash[i]
		if it != null:
			var ic: Texture2D = U.item_icon(it.id)
			if ic:
				draw_texture_rect(ic, Rect2(r.position + Vector2(10, 2), Vector2(42, 42)), false)
			_pane_rects.append([r, "stash", i])
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), hud.item_tip(it.id, h))
	U.text(self, ("The courier (%s) brings the stash to you. " % Keybinds.key_name("courier_deliver")) if not here else "Click: take it. ",
		Vector2(494, y + 18), 13, U.TEXT_DIM, "body")
	U.text(self, "Right click: sell it.", Vector2(494, y + 36), 13, U.TEXT_DIM, "body")

func _owned(h: SimUnit) -> Array:
	var out: Array = []
	for arr in [h.inventory, h.stash]:
		for it in arr:
			if it != null:
				out.append(it.id)
	return out

func _buy(id: String) -> void:
	var err: String = hud.game.act({"k": "buy", "item": id})
	if err != "":
		hud.error(err)

## Shift + click: put the item's missing parts on the To Buy list.
func _to_buy(id: String) -> void:
	var h := _hero()
	var n: int = h.to_buy.size()
	var err: String = hud.game.act({"k": "to_buy_add", "item": id})
	if err != "":
		hud.error(err)
	else:
		hud.notice("To Buy: %s (%d part%s)" % [String(SimData.item(id).name), h.to_buy.size() - n, "" if h.to_buy.size() - n == 1 else "s"])

func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var mb := e as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		accept_event()
		return
	var right := mb.button_index == MOUSE_BUTTON_RIGHT
	var h := _hero()
	var w: SimWorld = hud.game.world
	for id in _rects:
		if (_rects[id] as Rect2).has_point(mb.position):
			var now := Time.get_ticks_msec()
			var dbl: bool = _last_click.id == id and now - int(_last_click.t) < 350
			_last_click = {"id": id, "t": now}
			if mb.shift_pressed:
				_to_buy(id)
			elif right or dbl or mb.double_click:
				_buy(id)
			selected = id
			sell_slot = -1
			queue_redraw()
			accept_event()
			return
	for pr in _pane_rects:
		if not (pr[0] as Rect2).has_point(mb.position):
			continue
		match String(pr[1]):
			"close":
				visible = false
			"tab":
				tab = String(pr[2])
				_search.text = ""
			"buy":
				if mb.shift_pressed:
					_to_buy(String(pr[2]))
				else:
					_buy(String(pr[2]))
			"sell":
				var err: String = hud.game.act({"k": "sell", "slot": int(pr[2]), "stash": false})
				if err != "":
					hud.error(err)
				sell_slot = -1
			"pick":
				var it = h.inventory[int(pr[2])]
				if it != null:
					selected = it.id
					sell_slot = int(pr[2])
			"select":
				if mb.shift_pressed:
					_to_buy(String(pr[2]))
				elif right:
					_buy(String(pr[2]))
				else:
					selected = String(pr[2])
					sell_slot = -1
			"stash":
				var serr := ""
				if right:
					serr = hud.game.act({"k": "sell", "slot": int(pr[2]), "stash": true})
				else:
					serr = hud.game.act({"k": "from_stash", "slot": int(pr[2])})
				if serr != "":
					hud.error(serr)
		queue_redraw()
		accept_event()
		return
	accept_event()
