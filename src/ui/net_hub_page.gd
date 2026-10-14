extends VBoxContainer
## Multiplayer, on a server: its lobbies (create one, join one, quick join), who is online and where, and a chat for
## everyone on the lobby list.

const U = preload("res://src/ui/ui_kit.gd")

var menu                                    # net_menu.gd
var net: NetSession
var lobbies: NetList
var people: NetList
var chat: NetChat
var join_btn: Button
var people_title: Label
var hint: Label

func _ready() -> void:
	net = menu.net
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	# lobbies
	var ls: Array = menu.section("Lobbies")
	ls[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls[0].size_flags_stretch_ratio = 1.7
	cols.add_child(ls[0])
	var lv: VBoxContainer = ls[1]
	lobbies = NetList.new([{"title": "Lobby", "width": 0}, {"title": "Leader", "width": 200},
		{"title": "Players", "width": 140, "align": "center"}, {"title": "Status", "width": 220}], 62.0)
	lobbies.empty_text = "No lobbies yet"
	lobbies.empty_sub = "Create one and your friends can join it from this list."
	lobbies.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobbies.selected.connect(func(_d): _update_buttons())
	lobbies.activated.connect(func(d): _join(d))
	lv.add_child(lobbies)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 12)
	lv.add_child(acts)
	acts.add_child(menu.button("Create Lobby", _create_dialog, 200))
	acts.add_child(menu.button("Quick Join", func(): net.quick_join(), 170))
	acts.add_child(menu.spacer())
	join_btn = menu.button("Join Lobby", func(): _join(lobbies.selected_data()), 240, "GoldButton", 56)
	acts.add_child(join_btn)
	# players and chat
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	var ps: Array = menu.section("Players Online")
	people_title = menu.section_head(ps[1]).get_child(0)
	right.add_child(ps[0])
	people = NetList.new([{"title": "Name", "width": 0}, {"title": "Where", "width": 220}, {"title": "Ping", "width": 80, "align": "center"}], 42.0)
	people.custom_minimum_size = Vector2(0, 250)
	ps[1].add_child(people)
	var cs: Array = menu.section("Server Chat")
	cs[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(cs[0])
	chat = NetChat.new("Say something to everyone on the lobby list")
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.send = func(t): net.say(t)
	cs[1].add_child(chat)
	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	bottom.add_child(menu.button("Stop Hosting" if net.is_server() else "Leave Server", func(): back(), 200, "DarkButton"))
	hint = menu.label("", 16, U.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	bottom.add_child(menu.spacer(200, false))
	chat.my_name = net.my_name
	chat.set_lines(net.hub_log)
	refresh()

func back() -> void:
	if net.is_server():
		menu.dialog("Stop Hosting", ["Close your server? Everyone on it is disconnected, matches included."],
			[["Cancel", menu.close_dialog], ["Stop Hosting", func():
				menu.close_dialog()
				net.leave_server("")
				menu.sync()
				menu.toast("Your server is closed"), "RedButton"]], 560)
	else:
		net.leave_server("")
		menu.sync()

func on_chat(channel: String, nm: String, text: String, system: bool) -> void:
	if channel == "hub":
		chat.add_line(nm, text, system)

func refresh() -> void:
	if lobbies == null:
		return
	var info: Dictionary = net.server_info
	var sname := String(info.get("name", "Server"))
	var sub := String(info.get("motd", ""))
	if sub == "":
		sub = "You are hosting this server on port %d." % int(info.get("port", NetSession.PORT)) if net.is_server() \
			else "Connected to %s" % net.address
	var online := int(info.get("players", (net.hub.get("players", []) as Array).size()))
	var chips := [["%d online" % online, U.TEXT, "ui/talk"]]
	if net.is_server():
		chips.append(["Hosting", U.GOLD, "ui/crown"])
	else:
		var p := net.my_ping()
		chips.append(["Ping %d ms" % p, Color(0.55, 0.95, 0.55) if p < 90 else (Color(1.0, 0.85, 0.35) if p < 170 else Color(1.0, 0.5, 0.45))])
	menu.set_header(sname, sub, chips)
	var rows := []
	var mine := net.my_name.to_lower()
	for r in net.hub.get("rooms", []):
		var st := String(r.state)
		var status := {"text": "Waiting for players", "color": Color(0.6, 0.95, 0.6)}
		var back_in := false
		for d in r.get("dropped", []):
			if String(d).to_lower() == mine:
				back_in = true
		if st == "loading":
			status = {"text": "Starting", "color": U.GOLD}
		elif st == "playing":
			status = {"text": "In a match", "sub": "%d:%02d" % [int(r.time) / 60, int(r.time) % 60], "color": U.GOLD}
			if back_in:
				status = {"text": "Your hero waits", "sub": "Join to play on", "color": Color(0.55, 0.85, 1.0)}
		var free := int(r.seats) - int(r.humans) - int(r.bots)
		rows.append({"cells": [{"text": String(r.name), "sub": "%d open slot%s" % [free, "" if free == 1 else "s"] if st == "lobby" else "Match running", "lock": bool(r.locked)},
				{"text": String(r.leader), "color": Color(0.9, 0.88, 0.8)},
				{"text": "%d / %d" % [int(r.humans), int(r.seats)], "sub": "%d bot%s" % [int(r.bots), "" if int(r.bots) == 1 else "s"] if int(r.bots) > 0 else ""},
				status],
			"data": {"key": int(r.id), "room": r}, "dim": st != "lobby" and not back_in,
			"tip": "Needs a password." if bool(r.locked) else ""})
	lobbies.set_rows(rows)
	var prow := []
	var ppl: Array = net.hub.get("players", [])
	for p in ppl:
		var pg := int(p.ping)
		prow.append({"cells": [{"text": String(p.name), "size": 16, "color": Color(0.55, 0.78, 1.0) if String(p.name) == net.my_name else U.TEXT},
			{"text": String(p.where) if String(p.where) != "" else "Lobby list", "size": 14, "color": U.TEXT_DIM, "kind": "body"},
			{"text": "Host" if pg <= 0 else str(pg), "size": 14, "color": U.TEXT_DIM}], "data": {"key": String(p.name)}})
	people.set_rows(prow)
	_update_buttons()

func _update_buttons() -> void:
	var d = lobbies.selected_data()
	join_btn.disabled = d == null
	if (net.hub.get("rooms", []) as Array).is_empty():
		hint.text = "Create a lobby, or wait for one to appear. Quick Join makes one for you."
	else:
		hint.text = "Double-click a lobby to join it. Quick Join picks the fullest open lobby."

func _join(d) -> void:
	if d == null:
		return
	var r: Dictionary = d.room
	if bool(r.locked):
		var pw: LineEdit = menu.field("Password", "", true, 32)
		menu.dialog("Lobby Password", ["%s needs a password." % String(r.name), pw],
			[["Cancel", menu.close_dialog], ["Join", func():
				menu.close_dialog()
				net.join_room(int(r.id), pw.text), "GoldButton"]])
		return
	net.join_room(int(r.id), "")

func _create_dialog() -> void:
	var nm: LineEdit = menu.field("%s's game" % net.my_name, "", false, 32)
	var pw: LineEdit = menu.field("None", "", true, 32)
	var mode := OptionButton.new()
	mode.custom_minimum_size = Vector2(0, 44)
	mode.add_item("5 vs 5")
	mode.add_item("1 vs 1 mid")
	menu.dialog("Create Lobby", [menu.labelled("Lobby name", nm), menu.labelled("Password", pw, "optional"),
		menu.labelled("Teams", mode, "the leader can change slots later")],
		[["Cancel", menu.close_dialog], ["Create", func():
			menu.close_dialog()
			net.create_room(nm.text, pw.text, "1v1" if mode.selected == 1 else "5v5"), "GoldButton"]])
