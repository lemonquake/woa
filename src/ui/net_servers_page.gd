extends VBoxContainer
## Multiplayer, not connected: the server list (main server, your saved servers, the local network) with each
## server's players, lobbies and ping, kept fresh while the page is open; join by address; host a server here.

const U = preload("res://src/ui/ui_kit.gd")

var menu                                    # net_menu.gd
var browser: NetBrowser
var list: NetList
var name_field: LineEdit
var addr_field: LineEdit
var pw_field: LineEdit
var join_btn: Button
var remove_btn: Button
var h_name: LineEdit
var h_pw: LineEdit
var h_port: LineEdit
var h_max: OptionButton
var h_router: CheckBox

const MAX_CHOICES := [10, 20, 32, 64, 128]

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser = NetBrowser.new()
	browser.changed.connect(refresh)
	var prefs := NetBrowser.prefs
	menu.set_header("Multiplayer", "Play with friends on a server: the main server, one you saved, one on your local network, or your own.")
	# your name, top right
	var nb := HBoxContainer.new()
	nb.add_theme_constant_override("separation", 10)
	nb.add_child(menu.label("Your name", 16, U.TEXT_DIM, "bold"))
	name_field = menu.field("Your name", String(prefs.name), false, 20)
	name_field.custom_minimum_size = Vector2(260, 44)
	name_field.text_changed.connect(func(t):
		prefs.name = t
		NetBrowser.save_prefs())
	nb.add_child(name_field)
	nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.chips.add_child(nb)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	# the server list
	var sec: Array = menu.section("Servers")
	var sp: PanelContainer = sec[0]
	var sv: VBoxContainer = sec[1]
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.size_flags_stretch_ratio = 2.0
	cols.add_child(sp)
	menu.section_head(sv).add_child(menu.button("Refresh", func():
		browser.refresh()
		menu.toast("Asking every server again"), 130, "DarkButton", 40))
	list = NetList.new([{"title": "Server", "width": 0}, {"title": "Players", "width": 120, "align": "center"},
		{"title": "Lobbies", "width": 110, "align": "center"}, {"title": "Ping", "width": 100, "align": "center"},
		{"title": "Address", "width": 220}], 60.0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.selected.connect(func(_d): _update_buttons())
	list.activated.connect(func(d): _join(d))
	sv.add_child(list)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 12)
	sv.add_child(acts)
	acts.add_child(menu.button("Add Server", _add_dialog, 170))
	remove_btn = menu.button("Remove", _remove, 140)
	acts.add_child(remove_btn)
	acts.add_child(menu.spacer())
	join_btn = menu.button("Join Server", func(): _join(list.selected_data()), 260, "GoldButton", 56)
	acts.add_child(join_btn)

	# join by address, host a server
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.custom_minimum_size = Vector2(500, 0)
	cols.add_child(right)
	var js: Array = menu.section("Join by Address")
	right.add_child(js[0])
	var jv: VBoxContainer = js[1]
	addr_field = menu.field("e.g. 192.168.1.20 or play.example.com:27860", String(prefs.get("last_address", "")), false, 80)
	addr_field.text_submitted.connect(func(_t): _connect_address())
	jv.add_child(menu.labelled("Address", addr_field, "port %d unless you add one" % NetSession.PORT))
	pw_field = menu.field("Only if the server has one", "", true, 32)
	pw_field.text_submitted.connect(func(_t): _connect_address())
	jv.add_child(menu.labelled("Server password", pw_field))
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 12)
	jv.add_child(jr)
	jr.add_child(menu.button("Save to List", func():
		var why := browser.add_saved("", addr_field.text)
		menu.toast(why if why != "" else "Saved to your servers", why != ""), 170))
	jr.add_child(menu.spacer())
	jr.add_child(menu.button("Connect", _connect_address, 180, "GoldButton", 50))

	var hs: Array = menu.section("Host a Server")
	hs[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(hs[0])
	var hv: VBoxContainer = hs[1]
	var hp: Dictionary = prefs.host
	h_name = menu.field("%s's server" % NetSession.clean_name(name_field.text), String(hp.get("name", "")), false, 40)
	hv.add_child(menu.labelled("Server name", h_name))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 12)
	hv.add_child(hr)
	h_pw = menu.field("Optional", String(hp.get("password", "")), true, 32)
	hr.add_child(menu.labelled("Password", h_pw))
	h_port = menu.field(str(NetSession.PORT), str(int(hp.get("port", NetSession.PORT))), false, 5)
	h_port.custom_minimum_size = Vector2(110, 44)
	h_port.size_flags_horizontal = Control.SIZE_FILL
	var pl: VBoxContainer = menu.labelled("Port", h_port)
	pl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hr.add_child(pl)
	h_max = OptionButton.new()
	h_max.custom_minimum_size = Vector2(110, 44)
	for n in MAX_CHOICES:
		h_max.add_item(str(n))
	h_max.select(maxi(0, MAX_CHOICES.find(int(hp.get("max_players", 32)))))
	var ml: VBoxContainer = menu.labelled("Players", h_max)
	ml.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hr.add_child(ml)
	h_router = CheckBox.new()
	h_router.text = "Open the port on my router (UPnP)"
	h_router.button_pressed = bool(hp.get("open_router", false))
	h_router.add_theme_font_size_override("font_size", 16)
	hv.add_child(h_router)
	var help: Label = menu.label("You play on it too. Friends on your network see it under Local Network; over the internet they need your address and the port open (UDP %d and the one above it)." % NetSession.PORT, 14, U.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(440, 0)
	hv.add_child(help)
	var hb := HBoxContainer.new()
	hv.add_child(hb)
	hb.add_child(menu.spacer())
	hb.add_child(menu.button("Host Server", _host, 220, "GoldButton", 50))

	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	bottom.add_child(menu.button("Back", func(): back(), 160))
	var hint: Label = menu.label("Double-click a server to join it. Servers on your local network appear by themselves.", 16, U.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	bottom.add_child(menu.spacer(160, false))
	refresh()

func _exit_tree() -> void:
	if browser != null:
		browser.close()

func tick(_dt: float) -> void:
	browser.poll()

func back() -> void:
	menu.go_main_menu()

func _player_name() -> String:
	var n := NetSession.clean_name(name_field.text)
	NetBrowser.prefs.name = n
	NetBrowser.save_prefs()
	return n

# ---- The list -----------------------------------------------------------------------------------------------------------

func refresh() -> void:
	if list == null:
		return
	var rows := []
	var groups := {"main": [], "saved": [], "lan": []}
	for s in browser.servers:
		groups[String(s.kind)].append(s)
	rows.append({"section": "Main Server"})
	for s in groups.main:
		rows.append(_row(s))
	rows.append({"section": "Your Servers", "hint": "Add Server or Save to List keeps one here"})
	if groups.saved.is_empty():
		rows.append({"cells": [{"text": "No saved servers yet", "sub": "Add one by its address to see its players and ping here", "color": U.TEXT_DIM}], "dim": true, "note": true})
	for s in groups.saved:
		rows.append(_row(s))
	rows.append({"section": "Local Network"})
	if groups.lan.is_empty():
		rows.append({"cells": [{"text": "Looking for servers on your network...", "sub": "A server hosted on this computer or your network shows up here", "color": U.TEXT_DIM}], "dim": true, "note": true})
	for s in groups.lan:
		rows.append(_row(s))
	list.set_rows(rows)
	_update_buttons()

func _row(s: Dictionary) -> Dictionary:
	var info: Dictionary = s.info
	var nm := String(s.name)
	if nm == "" or s.kind == "lan":
		nm = String(info.get("name", nm if nm != "" else String(s.address)))
	elif s.online and String(info.get("name", "")) != "" and String(info.name) != nm and s.kind != "main":
		nm = "%s (%s)" % [nm, info.name]
	var addr := "%s:%d" % [s.address, s.port] if int(s.port) != NetSession.PORT else String(s.address)
	if String(s.address) == "":
		return {"cells": [{"text": nm, "sub": "Not set up in this build yet", "dot": Color(0.4, 0.4, 0.42)}, "-", "-", "-",
			{"text": "-", "color": U.TEXT_DIM}], "dim": true, "data": {"key": s.key, "server": s},
			"tip": "This build has no main server address (src/net/main_server.json)."}
	if not s.online:
		return {"cells": [{"text": nm, "sub": "Not answering", "dot": Color(0.45, 0.45, 0.47)}, "-", "-", "-",
			{"text": addr, "color": U.TEXT_DIM, "size": 15}], "dim": true, "data": {"key": s.key, "server": s},
			"tip": "No answer to the server list's question. It may be off, or its port may be closed. You can still try to join."}
	var same: bool = bool(s.get("same_version", true))
	var sub := String(info.get("motd", ""))
	if not same:
		sub = "Different version of the game"
	elif sub == "":
		sub = "Dedicated server" if bool(info.get("dedicated", false)) else "Hosted by a player"
	var players := "%d / %d" % [int(info.get("players", 0)), int(info.get("max", 0))]
	var ping := int(s.ping)
	var pc := Color(0.55, 0.95, 0.55) if ping < 90 else (Color(1.0, 0.85, 0.35) if ping < 170 else Color(1.0, 0.5, 0.45))
	return {"cells": [{"text": nm, "sub": sub, "dot": Color(0.4, 0.9, 0.45) if same else Color(1.0, 0.4, 0.35),
			"lock": bool(info.get("locked", false))},
		{"text": players, "color": U.TEXT},
		{"text": str(int(info.get("rooms", 0))), "sub": "%d open" % int(info.get("open", 0))},
		{"text": "%d ms" % ping, "color": pc},
		{"text": addr, "color": U.TEXT_DIM, "size": 15}],
		"data": {"key": s.key, "server": s}, "dim": not same,
		"tip": "Needs a password." if bool(info.get("locked", false)) else ""}

func _update_buttons() -> void:
	var d = list.selected_data()
	var s: Dictionary = d.server if d != null else {}
	join_btn.disabled = s.is_empty() or String(s.address) == "" or not bool(s.get("same_version", true))
	remove_btn.disabled = s.is_empty() or String(s.kind) != "saved"

# ---- Actions -----------------------------------------------------------------------------------------------------------

func _join(d) -> void:
	if d == null:
		menu.toast("Choose a server first", true)
		return
	var s: Dictionary = d.server
	if String(s.address) == "":
		menu.message("Main Server", "This build has no main server address yet. Join a saved server, one on your network, or host your own.")
		return
	if not bool(s.get("same_version", true)):
		menu.message("Different Version", "That server runs a different version of the game. Both need the same version to play together.")
		return
	if bool((s.info as Dictionary).get("locked", false)):
		var pw: LineEdit = menu.field("Password", "", true, 32)
		menu.dialog("Server Password", ["%s needs a password." % String((s.info as Dictionary).get("name", s.address)), pw],
			[["Cancel", menu.close_dialog], ["Join", func():
				menu.close_dialog()
				_connect(String(s.address), int(s.port), pw.text), "GoldButton"]])
		return
	_connect(String(s.address), int(s.port), "")

func _connect(address: String, port: int, pw: String) -> void:
	var why: String = menu.net.connect_to(address, _player_name(), pw, port)
	if why != "":
		menu.message("Could Not Connect", why)
		return
	menu.busy("Connecting to %s" % (address if port == NetSession.PORT else "%s:%d" % [address, port]))

func _connect_address() -> void:
	var ap := NetBrowser.split_address(addr_field.text)
	if String(ap[0]) == "":
		menu.toast("Type the server's address first", true)
		addr_field.grab_focus()
		return
	NetBrowser.prefs.last_address = addr_field.text.strip_edges()
	NetBrowser.save_prefs()
	_connect(String(ap[0]), int(ap[1]), pw_field.text)

func _add_dialog() -> void:
	var nm: LineEdit = menu.field("Optional: a name for your list", "", false, 40)
	var ad: LineEdit = menu.field("e.g. 192.168.1.20 or play.example.com:27860", "", false, 80)
	menu.dialog("Add Server", [menu.labelled("Address", ad), menu.labelled("Name", nm, "optional")],
		[["Cancel", menu.close_dialog], ["Add", func():
			var why := browser.add_saved(nm.text, ad.text)
			if why != "":
				menu.toast(why, true)
				return
			menu.close_dialog()
			menu.toast("Added to your servers"), "GoldButton"]])

func _remove() -> void:
	var d = list.selected_data()
	if d == null or String(d.server.kind) != "saved":
		return
	var key := String(d.key)
	var nm := String(d.server.name) if String(d.server.name) != "" else String(d.server.address)
	menu.dialog("Remove Server", ["Remove %s from your servers?" % nm],
		[["Cancel", menu.close_dialog], ["Remove", func():
			browser.remove_saved(key)
			menu.close_dialog(), "RedButton"]], 520)

func _host() -> void:
	var port := int(h_port.text) if h_port.text.strip_edges().is_valid_int() else -1
	if port < 1024 or port > 65534:
		menu.message("Port", "Choose a port between 1024 and 65534 (%d is the game's own)." % NetSession.PORT)
		return
	var nm := _player_name()
	var opts := {"name": h_name.text.strip_edges() if h_name.text.strip_edges() != "" else "%s's server" % nm,
		"password": h_pw.text, "port": port, "max_players": MAX_CHOICES[maxi(0, h_max.selected)],
		"open_router": h_router.button_pressed}
	NetBrowser.prefs.host = {"name": h_name.text.strip_edges(), "password": h_pw.text, "port": port,
		"max_players": opts.max_players, "open_router": opts.open_router, "motd": ""}
	NetBrowser.save_prefs()
	var why: String = menu.net.host_server(opts, nm)
	if why != "":
		menu.message("Could Not Host", why)
