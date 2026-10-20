class_name PlayerMenu
extends Control
## The right-click menu for a player, anywhere a player shows (run 2026-10-20; the owner: "very very interactive like
## Rightclick functions all over especially for profiles"). A header with the player's picture, name and rank, then:
## View profile, Match history, Compare with me, Write on profile, Add / Remove friend, Commend, Report, Block, Copy
## name (your own name: View profile, View As, Copy name). Hover lights an item, a click does it, a click outside or
## Esc closes it.
##
## The screen it opens on may handle the actions that go somewhere (profile, history, compare, write, view_as) with
## `player_action(action: String, id: String)`; a screen without one gets the profile as an overlay (ProfilePage). The
## rest are done here, with a note through `notice(text)` on the screen when it has one.

const U = preload("res://src/ui/ui_kit.gd")
const ITEM_H := 38.0
const HEAD_H := 66.0
const W := 300.0

var id := ""
var items: Array = []                       # [{a: action, t: text, ic: glyph key, off: bool, red: bool}]
var _hot := -1
var _panel := Rect2()
var _av: Avatar
var _host: Node
var _cb := Callable()                         # a list menu (open_list): what a click does
var _title := ""
var _sub := ""

## Open the menu for player `id` at the mouse (global position `at`) over `from`'s screen.
static func open(from: Node, pid: String, at: Vector2) -> PlayerMenu:
	if pid == "" or Ranked.profile(pid).is_empty():
		return null
	var tree := from.get_tree()
	for old in tree.get_nodes_in_group("player_menu"):
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.add_to_group("player_menu")
	_parent(tree).add_child(layer)
	var m := PlayerMenu.new()
	m.id = pid
	m._host = tree.current_scene
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	m._build(at)
	Options.click()
	U.pop_in(m, 0.09)
	return m

## A menu of other things (a match, the View As choices): entries [[action, text, glyph key]]; cb(action) on a click.
static func open_list(from: Node, at: Vector2, title: String, sub: String, entries: Array, cb: Callable) -> PlayerMenu:
	var tree := from.get_tree()
	for old in tree.get_nodes_in_group("player_menu"):
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.add_to_group("player_menu")
	_parent(tree).add_child(layer)
	var m := PlayerMenu.new()
	m._cb = cb
	m._title = title
	m._sub = sub
	m._host = tree.current_scene
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	for e in entries:
		m.items.append({"a": String(e[0]), "t": String(e[1]), "ic": String(e[2]) if e.size() > 2 else ""})
	m._place(at)
	Options.click()
	U.pop_in(m, 0.09)
	return m

## The menu lives with the screen it opened on (a scene change takes it away).
static func _parent(tree: SceneTree) -> Node:
	return tree.current_scene if tree.current_scene != null else tree.root

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		_hot = -1
		queue_redraw())

## Only the menu's panel takes the mouse; the rest of the screen stays live (see _input).
func _has_point(p: Vector2) -> bool:
	return _panel.has_point(p)

func _build(at: Vector2) -> void:
	var p := Ranked.profile(id)
	var own := id == "me"
	items.clear()
	items.append({"a": "profile", "t": "View profile", "ic": "profile"})
	items.append({"a": "history", "t": "Match history", "ic": "history"})
	if own:
		items.append({"a": "view_as", "t": "View As someone else", "ic": "visitor"})
		items.append({"a": "accounts", "t": "Accounts", "ic": "profile"})
	else:
		items.append({"a": "compare", "t": "Compare with me", "ic": "compare"})
		items.append({"a": "write", "t": "Write on profile", "ic": "comment"})
		var friend := id in (Ranked.me().get("friends", []) as Array)
		var asked := false
		for q in Ranked.me().get("requests", []):
			if String(q.get("id", "")) == id:
				asked = true
		if asked:
			items.append({"a": "accept", "t": "Accept friend request", "ic": "friend"})
		items.append({"a": "unfriend" if friend else "friend", "t": "Remove friend" if friend else "Add friend", "ic": "friend"})
		if Ranked.is_account(id):
			items.append({"a": "login", "t": "Log in to this account", "ic": "profile"})
		else:
			items.append({"a": "commend", "t": "Commend", "ic": "commend", "off": not Ranked.can_act("commended", id)})
			items.append({"a": "report", "t": "Report", "ic": "report", "red": true, "off": not Ranked.can_act("reported", id)})
			items.append({"a": "block", "t": "Unblock" if Ranked.blocked(id) else "Block", "ic": "block", "red": not Ranked.blocked(id)})
	items.append({"a": "copy", "t": "Copy name", "ic": "copy"})
	_place(at)
	_av = Avatar.new()
	_av.set_spec(p.get("avatar", {"k": "none"}))
	_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_av.position = _panel.position + Vector2(16, 12) * _k()
	_av.size = Vector2(44, 44) * _k()
	add_child(_av)

func _place(at: Vector2) -> void:
	var h := HEAD_H + ITEM_H * items.size() + 16.0
	var vs := get_viewport_rect().size
	var k := clampf(minf(vs.x / 1920.0, vs.y / 1080.0), 0.6, 2.4)
	scale = Vector2.ONE
	var pos := at
	if pos.x + W * k > vs.x - 6:
		pos.x = at.x - W * k
	if pos.y + h * k > vs.y - 6:
		pos.y = maxf(6.0, vs.y - h * k - 6)
	pos.x = clampf(pos.x, 6.0, maxf(6.0, vs.x - W * k - 6.0))
	pos.y = clampf(pos.y, 6.0, maxf(6.0, vs.y - h * k - 6.0))
	_panel = Rect2(pos, Vector2(W, h) * k)
	queue_redraw()

## Where an item is on screen (the live probe clicks it).
func item_center(action: String) -> Vector2:
	for i in items.size():
		if String(items[i].a) == action:
			return _panel.position + Vector2(W * 0.5, HEAD_H + 4.0 + (float(i) + 0.5) * ITEM_H) * _k()
	return Vector2(-1, -1)

func _k() -> float:
	return _panel.size.x / W

func _item_at(pos: Vector2) -> int:
	if not _panel.has_point(pos):
		return -1
	var y := (pos.y - _panel.position.y) / _k() - HEAD_H - 4.0
	var i := int(floor(y / ITEM_H))
	return i if i >= 0 and i < items.size() else -1

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := _item_at((e as InputEventMouseMotion).position)
		if i != _hot:
			_hot = i
			queue_redraw()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
		var i := _item_at(mb.position)
		if i >= 0:
			if not bool(items[i].get("off", false)):
				_do(String(items[i].a))
		accept_event()

## A click outside closes the menu: a left click ends there (it never presses what lies under the menu by accident);
## a right click goes on, so right-clicking another player opens their menu at once. Esc closes it too.
func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not _panel.has_point(mb.position):
			_close()
			if mb.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
	elif e is InputEventKey and (e as InputEventKey).pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	var layer := get_parent()
	if layer and not layer.is_queued_for_deletion():
		layer.queue_free()
		set_process_input(false)

func _note(t: String) -> void:
	if _host != null and _host.has_method("notice"):
		_host.call("notice", t)

func _do(a: String) -> void:
	Options.click()
	if _cb.is_valid():
		_close()
		_cb.call(a)
		return
	var nm := String(Ranked.profile(id).get("name", ""))
	match a:
		"friend":
			if Ranked.ask_friend(id):
				_note("%s accepted your friend request." % nm)
			else:
				_note("%s did not answer your friend request." % nm)
		"accept":
			Ranked.accept_request(id)
			_note("You and %s are now friends." % nm)
		"unfriend":
			Ranked.remove_friend(id)
			_note("Removed %s from your friends." % nm)
		"commend":
			_note(("You commended %s." % nm) if Ranked.commend(id) else "You already commended this player today.")
		"report":
			_note(("You reported %s. Thank you." % nm) if Ranked.report(id) else "You already reported this player today.")
		"block":
			_note(("You blocked %s: their posts and comments are hidden." % nm) if Ranked.toggle_block(id) else ("You unblocked %s." % nm))
		"copy":
			DisplayServer.clipboard_set(nm)
			_note("Name copied.")
		"accounts":
			_close()
			AccountsPanel.open(_host if _host != null else self)
			return
		"login":
			_close()
			if Ranked.login(id):
				AccountsPanel.after_login(get_tree())
			else:
				_note("Finish your ranked match first.")
			return
		_:
			_close()
			if _host != null and _host.has_method("player_action"):
				_host.call("player_action", a, id)
			elif _host != null:
				ProfilePage.overlay(_host, id, a)
			return
	_close()
	if _host != null and _host.has_method("refresh_social"):
		_host.call("refresh_social")

func _draw() -> void:
	if _panel.size.x <= 0:
		return
	var k := _k()
	draw_set_transform(_panel.position, 0.0, Vector2(k, k))
	var r := Rect2(Vector2(-10, -10), Vector2(W + 20, _panel.size.y / k + 20))
	U.skin(self, "soc_menu", r)
	if id == "":
		draw_string(U.font("title"), Vector2(18, 32), _title, HORIZONTAL_ALIGNMENT_LEFT, W - 30, 18, U.GOLD)
		draw_string(U.font("body"), Vector2(18, 54), _sub, HORIZONTAL_ALIGNMENT_LEFT, W - 30, 13, U.TEXT_DIM)
	else:
		var p := Ranked.profile(id)
		draw_string(U.font("bold"), Vector2(72, 32), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, W - 84, 18, U.TEXT)
		var ic := RankEmblem.icon(Ranked.tier_for(p))
		if ic:
			draw_texture_rect(ic, Rect2(70, 36, 24, 24), false)
		draw_string(U.font("body"), Vector2(98, 54), "%s  ·  %s MMR" % [Ranked.rank_label(p), RankedNum.num(int(p.get("mmr", 0)))],
			HORIZONTAL_ALIGNMENT_LEFT, W - 110, 13, U.GOLD)
	draw_line(Vector2(14, HEAD_H), Vector2(W - 14, HEAD_H), Color(U.GOLD, 0.25), 1.0)
	for i in items.size():
		var it: Dictionary = items[i]
		var y := HEAD_H + 4.0 + i * ITEM_H
		var off := bool(it.get("off", false))
		if i == _hot and not off:
			U.skin(self, "soc_menu_hi", Rect2(8, y + 2, W - 16, ITEM_H - 4))
		var g := SocialUi.icon(String(it.ic), true)
		if g:
			draw_texture_rect(g, Rect2(18, y + 8, 22, 22), false, Color(1, 1, 1, 0.35 if off else 1.0))
		var col := U.TEXT
		if off:
			col = Color(0.5, 0.5, 0.52)
		elif bool(it.get("red", false)):
			col = Color(1.0, 0.55, 0.5)
		elif i == _hot:
			col = Color(1.0, 0.94, 0.8)
		draw_string(U.font("bold" if i == _hot else "body"), Vector2(52, y + 25), String(it.t), HORIZONTAL_ALIGNMENT_LEFT, W - 70, 16, col)
		if off:
			SocialUi.text_r(self, "today", W - 18, y + 25, 12, Color(0.5, 0.5, 0.52))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
