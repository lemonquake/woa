extends SceneTree
## The Multiplayer screens through real mouse clicks and typing, two game windows on this computer:
##   godot --path . -s tests/tools/net_ui_probe.gd -- --role=host [--out=dir] [--4k]
##   godot --path . -s tests/tools/net_ui_probe.gd -- --role=guest [--out=dir]
## The host names itself, hosts a server (Host Server), creates a lobby, chats, picks a hero, fills the slots with bots,
## readies and starts the match once the guest is ready; in the match it pauses the game for both from the menu,
## unpauses, leaves the game and stops hosting. The guest finds the server under Local Network, joins it, joins the
## lobby with a double click, chats, picks a hero, readies, plays until the host pauses and unpauses, and stays in the
## match after the server goes (bots take the other players' heroes). Each prints PASS / FAIL lines and saves captures.
## (Drop-down choices and the leader's slot menu are chosen through their signals: the rest are real clicks.)

const PORT := 27880

var role := "host"
var out := "work/lemondev/2026-10-15-multiplayer/shots"
var big := false
var net: NetSession
var _passes := 0
var _fails := 0
var _t0 := 0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--4k":
			big = true
	_t0 = Time.get_ticks_msec()
	change_scene_to_file.call_deferred("res://src/ui/net_menu.tscn")
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("%s PASS %s" % [role.to_upper(), msg])
	else:
		_fails += 1
		print("%s FAIL %s" % [role.to_upper(), msg])

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Wait until cond() is true (or the time runs out); returns whether it came true.
func until(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func shot(name: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(dir)
	var tag := "_4k" if big else ""
	root.get_texture().get_image().save_png(dir + "/" + name + tag + ".png")
	print("saved ", name + tag)

# ---- Real input -------------------------------------------------------------------------------------------------------

func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p

func move_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _to_window(p)
	ev.global_position = ev.position
	root.push_input(ev)

func click_at(p: Vector2, double := false) -> void:
	move_to(p)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.double_click = double and pressed
		ev.position = _to_window(p)
		ev.global_position = ev.position
		root.push_input(ev)
		await process_frame

func click(c: Control) -> void:
	if c == null:
		check(false, "a control to click is missing")
		return
	await click_at(c.get_global_rect().get_center())

func key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame

func type_text(s: String) -> void:
	for ch in s:
		var ev := InputEventKey.new()
		ev.unicode = ch.unicode_at(0)
		ev.keycode = KEY_NONE
		ev.pressed = true
		root.push_input(ev)
		var up := ev.duplicate()
		up.pressed = false
		root.push_input(up)
		await process_frame

## Click a text field, clear it and type.
func fill(f: LineEdit, s: String) -> void:
	await click(f)
	await key(KEY_A, true)
	await key(KEY_BACKSPACE)
	await type_text(s)

func menu() -> Control:
	return current_scene

func find_button(text: String) -> Button:
	for b in menu().find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null

func find_field(placeholder: String) -> LineEdit:
	for f in menu().find_children("*", "LineEdit", true, false):
		if (f as LineEdit).placeholder_text == placeholder and (f as LineEdit).is_visible_in_tree():
			return f
	return null

## A row of a NetList by its data key: its centre on screen.
func row_point(list: NetList, key) -> Vector2:
	var y := 0.0
	for r in list.rows:
		var h := list._h_of(r)
		if not r.has("section") and r.get("data") is Dictionary and r.data.get("key") == key:
			return list._body.get_global_rect().position + Vector2(list._body.size.x * 0.4, y + h * 0.5)
		y += h + 4.0
	return Vector2(-1, -1)

func page():
	return menu().page

# ---- The run ------------------------------------------------------------------------------------------------------------

func _run() -> void:
	await frames(20)
	if big:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		await frames(20)
	else:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_position(Vector2i(0 if role == "host" else 60, 0))
		await frames(10)
	net = root.get_node("Net")
	if role == "host":
		await _host()
	else:
		await _guest()
	print("%s RESULT %d passed, %d failed (%.0f s)" % [role.to_upper(), _passes, _fails, (Time.get_ticks_msec() - _t0) / 1000.0])
	quit(0 if _fails == 0 else 1)

func _host() -> void:
	check(menu().page_kind == "servers", "the Multiplayer screen opens on the server list")
	await fill(find_field("Your name"), "Ada")
	check(NetBrowser.prefs.name == "Ada", "typing a name keeps it")
	await fill(page().h_name, "Probe server")
	await fill(page().h_port, str(PORT))
	await shot("net_servers")
	await click(find_button("Host Server"))
	check(await until(func(): return menu().page_kind == "hub", 5.0), "Host Server opens the server's lobby list")
	check(menu().title_label.text == "Probe server", "the title is the server's name")
	await frames(30)
	await shot("net_hub_empty")
	# a lobby
	await click(find_button("Create Lobby"))
	check(menu().dialog_open(), "Create Lobby opens its dialog")
	await type_text("Friday game")
	await shot("net_create_dialog")
	await click(find_button("Create"))
	check(await until(func(): return menu().page_kind == "room", 5.0), "Create puts you in your new lobby")
	check(net.am_leader(), "and you lead it")
	check(net.my_slot() == 0, "in Ancient Light's first slot")
	# wait for the guest
	check(await until(func(): return net.room.slots.filter(func(s): return String(s.kind) == "human").size() >= 2, 90.0),
		"the guest joins the lobby")
	await frames(20)
	# chat
	await click(page().chat.field)
	await type_text("Hello Bea")
	await key(KEY_ENTER)
	check(await until(func(): return net.room_log.any(func(l): return String(l[1]) == "Hello Bea"), 5.0), "a chat line reaches the lobby")
	check(await until(func(): return net.room_log.any(func(l): return String(l[1]) == "Hi Ada"), 30.0), "and the guest's line comes back")
	if not net.room_log.any(func(l): return String(l[1]) == "Hi Ada"):
		print("HOST room log: ", net.room_log)
	# my hero and lane
	var froster = page().cards.filter(func(c): return c.hero == "froster")[0]
	await click(froster)
	check(await until(func(): return String(net.room.slots[0].hero) == "froster", 5.0), "clicking a hero card picks that hero")
	page().lane_opt.select(2)
	page().lane_opt.item_selected.emit(2)
	check(await until(func(): return String(net.room.slots[0].lane) == "mid", 5.0), "the lane choice reaches the lobby")
	# the leader's slot menu: a bot in slot 1, then close slot 4
	await click(page().rows[1].more)
	var pm: PopupMenu = null
	for c in page().get_children():
		if c is PopupMenu:
			pm = c
	check(pm != null and pm.visible, "the slot button opens the slot menu")
	if pm:
		pm.id_pressed.emit(0)
	check(await until(func(): return String(net.room.slots[1].kind) == "bot", 5.0), "Add Bot puts a bot in the slot")
	await click(find_button("Fill with Bots"))
	check(await until(func(): return net.room.slots.filter(func(s): return String(s.kind) == "open").is_empty(), 5.0), "Fill with Bots fills every open slot")
	check(page().start_btn.disabled, "Start waits while someone is not ready")
	await click(page().ready_btn)
	check(await until(func(): return bool(net.room.slots[0].ready), 5.0), "Ready marks you ready")
	check(await until(func(): return NetSession.start_problem(net.room.slots) == "", 60.0), "everyone is ready")
	await frames(20)
	await shot("net_room_ready")
	check(not page().start_btn.disabled, "Start Match is enabled once everyone is ready")
	await click(page().start_btn)
	# the match
	check(await until(func(): return current_scene != null and current_scene.get("booted") == true, 90.0), "Start Match loads the match")
	var game = current_scene
	check(await until(func(): return game.net != null and game.net.running, 60.0), "the match runs once both have loaded")
	await until(func(): return game.world.time > -80.0, 20.0)
	await shot("net_match")
	await key(KEY_ESCAPE)
	await frames(10)
	var pause_btn: Button = null
	for b in game.menus.find_children("*", "Button", true, false):
		if (b as Button).text == "Pause Game" and b.is_visible_in_tree():
			pause_btn = b
	check(pause_btn != null, "the in-match menu offers Pause Game")
	check(not game.world.paused, "opening the menu does not stop the game in multiplayer")
	await shot("net_match_menu")
	await click(pause_btn)
	check(await until(func(): return game.world.paused, 5.0), "Pause Game pauses the match")
	await frames(30)
	await shot("net_match_paused")
	await frames(90)
	await key(KEY_ESCAPE)
	await frames(10)
	var unpause: Button = null
	for b in game.menus.find_children("*", "Button", true, false):
		if (b as Button).text == "Unpause Game" and b.is_visible_in_tree():
			unpause = b
	check(unpause != null, "the menu then offers Unpause Game")
	await click(unpause)
	check(await until(func(): return not game.world.paused, 5.0), "Unpause Game resumes it")
	await frames(120)
	await key(KEY_ESCAPE)
	await frames(10)
	var leave: Button = null
	for b in game.menus.find_children("*", "Button", true, false):
		if (b as Button).text == "Leave Game" and b.is_visible_in_tree():
			leave = b
	await click(leave)
	check(await until(func(): return current_scene != null and current_scene.has_method("toast") and current_scene.page_kind == "hub", 30.0),
		"Leave Game goes back to the server's lobby list")
	await frames(40)
	await shot("net_hub_match_running")
	var rid := -1
	for r in net.hub.get("rooms", []):
		rid = int(r.id)
	check(rid >= 0 and String(net.hub.rooms[0].state) == "playing", "the match goes on without you (a bot plays your hero)")
	check(String(page().lobbies.rows[0].cells[3].text) == "Your hero waits", "the lobby list says your hero waits for you")
	await click_at(row_point(page().lobbies, rid), false)
	await click_at(row_point(page().lobbies, rid), true)
	check(await until(func(): return current_scene != null and current_scene.get("booted") == true, 90.0), "joining it again loads the running match")
	var g2 = current_scene
	check(await until(func(): return g2.net != null and g2.net.running and g2.net.resyncs > 0, 60.0), "you get the match as it stands (a snapshot) and play on")
	check(g2.world.get_unit(g2.player_hero_id) != null and not g2.world.get_unit(g2.player_hero_id).bot, "your hero is yours again, no longer a bot's")
	await frames(60)
	await shot("net_rejoined")
	await key(KEY_ESCAPE)
	await frames(10)
	for b in g2.menus.find_children("*", "Button", true, false):
		if (b as Button).text == "Leave Game" and b.is_visible_in_tree():
			leave = b
	await click(leave)
	await until(func(): return current_scene != null and current_scene.has_method("toast") and current_scene.page_kind == "hub", 30.0)
	await frames(60)
	await click(find_button("Stop Hosting"))
	check(menu().dialog_open(), "Stop Hosting asks first")
	await shot("net_stop_dialog")
	var stop: Button = null
	for b in menu().find_children("*", "Button", true, false):
		if (b as Button).text == "Stop Hosting" and b.is_visible_in_tree() and b.theme_type_variation == "RedButton":
			stop = b
	await click(stop)
	check(await until(func(): return menu().page_kind == "servers" and not net.active(), 5.0), "and closes the server, back to the server list")
	await frames(30)

func _guest() -> void:
	await fill(find_field("Your name"), "Bea")
	# the host's server appears under Local Network
	var found = func():
		for s in page().browser.servers:
			if s.online and String(s.info.get("name", "")) == "Probe server":
				return s
		return null
	check(await until(func(): return found.call() != null, 90.0), "the hosted server shows up under Local Network")
	var srv = found.call()
	await frames(30)
	await shot("net_servers_found")
	var p := row_point(page().list, srv.key)
	await click_at(p)
	check(page().list.selected_data() != null and page().list.selected_data().key == srv.key, "clicking a server selects it")
	await click(find_button("Join Server"))
	check(await until(func(): return menu().page_kind == "hub", 10.0), "Join Server opens its lobby list")
	check(await until(func(): return not net.hub.get("rooms", []).is_empty(), 30.0), "the host's lobby is listed")
	await frames(20)
	await shot("net_hub_lobby")
	var rid := int(net.hub.rooms[0].id)
	await click_at(row_point(page().lobbies, rid), false)
	await click_at(row_point(page().lobbies, rid), true)
	check(await until(func(): return menu().page_kind == "room", 10.0), "double-clicking a lobby joins it")
	check(net.my_slot() == 5, "a newcomer gets the smaller team (Black Sun)")
	check(await until(func(): return net.room_log.any(func(l): return String(l[1]) == "Hello Bea"), 30.0), "the host's chat line arrives")
	await click(page().chat.field)
	await type_text("Hi Ada")
	print("GUEST chat field holds \"%s\", focus %s" % [page().chat.field.text, page().chat.field.has_focus()])
	await click(find_button("Send"))
	check(await until(func(): return net.room_log.any(func(l): return String(l[1]) == "Hi Ada"), 10.0), "Send puts the guest's line in the lobby chat")
	var caz = page().cards.filter(func(c): return c.hero == "caziel")[0]
	await click(caz)
	check(await until(func(): return String(net.room.slots[5].hero) == "caziel", 5.0), "a hero card click picks the hero")
	check(page().start_btn.visible == false, "only the leader sees Start Match")
	await until(func(): return net.room.slots.filter(func(s): return String(s.kind) == "open").is_empty(), 60.0)
	await click(page().ready_btn)
	check(await until(func(): return bool(net.room.slots[5].ready), 5.0), "Ready marks the guest ready")
	await frames(30)
	await shot("net_room_guest")
	check(await until(func(): return current_scene != null and current_scene.get("booted") == true, 120.0), "the match starts for the guest")
	var game = current_scene
	check(await until(func(): return game.net != null and game.net.running, 60.0), "and runs")
	check(await until(func(): return game.world.paused, 120.0), "the host's pause reaches the guest")
	await frames(20)
	await shot("net_match_paused_guest")
	check(await until(func(): return not game.world.paused, 60.0), "and so does the unpause")
	check(await until(func(): return game.net == null, 180.0), "when the server closes the guest plays on")
	var t0: float = game.world.time
	await frames(90)
	check(game.world.time > t0, "the match keeps running here, bots in the others' places")
	await shot("net_match_server_gone")
