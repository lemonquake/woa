class_name NetSession
extends Node
## Multiplayer (autoload "Net"; scripts reach it as NetSession.inst). This machine can be a player connected to a
## server, a server (a dedicated one with `--server`, or one a player hosts from the Multiplayer screen and plays on),
## or both. NetServer holds the server's side (the lobby list, rooms, the relayed lockstep); this node carries every
## message between the two over ENet (UDP) and keeps the player's side: the server's lobby list and chat, the room the
## player is in, and, during a match, the NetMatch that steps the world with the server's frames.
##
## A server also answers small UDP queries one port above its game port (name, players, lobbies, version), which is
## how the Multiplayer screen shows servers on the local network and the ping, players and lobbies of saved ones.

signal connected                            # the server accepted us (we are on its lobby list)
signal hub_changed                          # the server's lobby list, players or card changed
signal room_changed                         # the room we are in changed (or we got one)
signal room_left(reason: String)            # out of the room, back on the lobby list (reason "" when we chose to)
signal chat_received(channel: String, name: String, text: String, system: bool)
signal notice(text: String)                 # a short message from the server ("That lobby is full")
signal status_changed(text: String)         # connection progress, router port
signal left(reason: String)                 # the session ended (we left, kicked, server gone, refused)
signal match_starting

static var inst: NetSession

const PORT := 27850                         # game port; queries go to PORT + 1
const PROTOCOL := 2
const MAX_SLOTS := 10
const CONNECT_TIMEOUT_MS := 8000

enum State { OFF, CONNECTING, HUB, ROOM, LOADING, PLAYING }

var state := State.OFF
var server: NetServer                       # when this machine is a server
var local_player := false                   # a hosted server with its host playing on it
var my_name := "Player"
var my_id := 0
var address := ""                           # where we connected ("" when hosting)
var server_info := {}                       # the server's card (name, motd, players, lobbies...)
var hub := {}                               # {server, rooms: [...], players: [...]}
var room := {}                              # the room we are in, as the server sends it
var hub_log: Array = []                     # [name, text, system], newest last
var room_log: Array = []
var config := {}                            # the match being played: {seed, slots, room, me}
var m: NetMatch
var headless_test := false                  # tests/tools/net_test.gd: no scene changes, the test runs the world
var upnp_status := ""

var _peer: ENetMultiplayerPeer
var _upnp: UPNP
var _query: PacketPeerUDP
var _deadline := 0
var _password := ""
var _signals_done := false

func _enter_tree() -> void:
	inst = self

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# ---- Rules identity and slots (shared by both sides) ----------------------------------------------------------------

static var _fp := 0

## A fingerprint of the protocol and every unit, ability and item number: builds that differ in any rule refuse to play
## together instead of drifting apart.
static func rules_fingerprint() -> int:
	if _fp == 0:
		SimData.unit("dawn_melee")
		_fp = hash(var_to_bytes([PROTOCOL, SimData._units, SimData._abilities, SimData._items, SimData._talents]))
	return _fp

static func clean_name(s: String) -> String:
	var t := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32:
			t += ch
	t = t.strip_edges().left(20)
	return t if t != "" else "Player"

## Slots 0-4 are Ancient Light, 5-9 Black Sun.
static func slot_team(i: int) -> int:
	return 0 if i < 5 else 1

static func open_slot() -> Dictionary:
	return {"kind": "open", "peer": 0, "name": "", "hero": "random", "skill": "hard", "lane": "", "ready": false,
		"look": {}}

## Why a room cannot start yet ("" when it can).
static func start_problem(slots: Array) -> String:
	var teams := [0, 0]
	for i in slots.size():
		var s: Dictionary = slots[i]
		if String(s.kind) == "human" and not bool(s.ready):
			return "Waiting for %s to be ready" % String(s.name)
		if String(s.kind) in ["human", "bot"]:
			teams[slot_team(i)] += 1
	if teams[0] == 0 or teams[1] == 0:
		return "Each team needs at least one player or bot"
	return ""

func active() -> bool:
	return state != State.OFF

func is_server() -> bool:
	return server != null

## The slot I sit in, or -1.
func my_slot() -> int:
	if room.is_empty():
		return -1
	for i in room.slots.size():
		if String(room.slots[i].kind) == "human" and int(room.slots[i].peer) == my_id:
			return i
	return -1

func am_leader() -> bool:
	return not room.is_empty() and int(room.leader) == my_id

# ---- Hosting a server -------------------------------------------------------------------------------------------------

## Start a server on this machine. opts: name, motd, password, port, max_players, open_router (UPnP), dedicated.
## A hosted (not dedicated) server puts this player straight onto its lobby list. Returns "" or what went wrong.
func host_server(opts: Dictionary, player_name := "") -> String:
	leave_server("")
	var port := int(opts.get("port", PORT))
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, int(opts.get("max_players", 64)))
	if err != OK:
		_peer = null
		return "Could not open port %d. Another program (or another server) may be using it." % port
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	_connect_signals()
	server = NetServer.new()
	server.net = self
	server.server_name = String(opts.get("name", "")).strip_edges().left(40)
	if server.server_name == "":
		server.server_name = "%s's server" % clean_name(player_name) if player_name != "" else "Server"
	server.motd = String(opts.get("motd", "")).strip_edges().left(120)
	server.password = String(opts.get("password", "")).left(32)
	server.port = port
	server.max_players = clampi(int(opts.get("max_players", 64)), 2, 256)
	server.dedicated = bool(opts.get("dedicated", false))
	_query_start(port + 1)
	server_port_hint = port
	if bool(opts.get("open_router", false)):
		_open_router(port)
	address = ""
	my_id = 1
	if server.dedicated:
		local_player = false
		state = State.HUB
		server.log_line("server \"%s\" on port %d (queries on %d)%s" % [server.server_name, port, port + 1,
			", password set" if server.password != "" else ""])
		return ""
	local_player = true
	state = State.CONNECTING
	var why := server.hello(1, player_name, rules_fingerprint(), PROTOCOL, server.password)
	if why != "":
		leave_server("")
		return why
	return ""

## Join a server. address may carry a port ("1.2.3.4:27860").
func connect_to(addr: String, player_name: String, pw := "", port := PORT) -> String:
	leave_server("")
	addr = addr.strip_edges()
	if addr.contains(":") and not addr.begins_with("["):
		var parts := addr.rsplit(":", true, 1)
		if parts[1].is_valid_int():
			addr = parts[0]
			port = int(parts[1])
	if addr == "":
		return "Type the server's address"
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(addr, port)
	if err != OK:
		_peer = null
		return "Could not reach %s" % addr
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	_connect_signals()
	my_name = clean_name(player_name)
	_password = pw
	address = "%s:%d" % [addr, port] if port != PORT else addr
	state = State.CONNECTING
	_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	status_changed.emit("Connecting to %s" % address)
	return ""

## Leave the server (or stop hosting). reason "" = quietly (starting another session).
func leave_server(reason := "You left the server") -> void:
	_query_stop()
	if _upnp != null:
		_close_router()
	if _peer != null:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_peer.close()
	_peer = null
	var was := state
	state = State.OFF
	server = null
	local_player = false
	room = {}
	hub = {}
	server_info = {}
	hub_log = []
	room_log = []
	m = null
	my_id = 0
	if reason != "" and was != State.OFF:
		left.emit(reason)

func _connect_signals() -> void:
	if _signals_done:
		return
	_signals_done = true
	multiplayer.peer_connected.connect(func(_id): pass)   # a newcomer introduces itself (hello) first
	multiplayer.peer_disconnected.connect(func(id):
		if server != null:
			server.gone(id))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func():
		if state == State.CONNECTING:
			leave_server("Could not reach the server. Check the address, and that its port is open."))
	multiplayer.server_disconnected.connect(_on_server_gone)

func _on_connected() -> void:
	status_changed.emit("Connected, joining")
	_r_hello.rpc_id(1, my_name, rules_fingerprint(), PROTOCOL, _password)

func _on_server_gone() -> void:
	if (state == State.PLAYING or state == State.LOADING) and m != null:
		# the match goes on here, the other players' heroes played by bots
		var mm := m
		mm.host_lost()
		_peer = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		state = State.OFF
		server = null
		left.emit("Lost the connection to the server")
		return
	leave_server("The server closed the connection")

func _process(_dt: float) -> void:
	if state == State.CONNECTING and server == null and Time.get_ticks_msec() > _deadline:
		leave_server("No answer from the server. Check the address, and that its port is open.")
	if server != null:
		_query_answer()

func _physics_process(_dt: float) -> void:
	if server != null:
		server.tick()

# ---- Messages to the server (a hosted server takes its own player's calls directly) -----------------------------------

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1

func say(text: String) -> void:
	if server != null and local_player:
		server.chat(1, text)
	elif _peer != null:
		_r_chat.rpc_id(1, text)

func create_room(nm: String, pw: String, preset := "5v5") -> void:
	if server != null and local_player:
		server.create_room(1, nm, pw, preset)
	else:
		_r_create.rpc_id(1, nm, pw, preset)

func join_room(rid: int, pw := "") -> void:
	if server != null and local_player:
		server.join_room(1, rid, pw)
	else:
		_r_join.rpc_id(1, rid, pw)

func quick_join() -> void:
	if server != null and local_player:
		server.quick_join(1)
	else:
		_r_quick.rpc_id(1)

func leave_room() -> void:
	if server != null and local_player:
		server.leave_room(1)
	else:
		_r_leave.rpc_id(1)

## My slot: hero, lane, ready, look.
func set_mine(key: String, value) -> void:
	if server != null and local_player:
		server.set_mine(1, key, value)
	else:
		_r_set.rpc_id(1, key, var_to_bytes(value))

func move_to(slot: int) -> void:
	if server != null and local_player:
		server.move_to(1, slot)
	else:
		_r_move.rpc_id(1, slot)

## Leader: a slot open, bot or closed (removes a player); a bot's hero or skill.
func leader_slot(slot: int, key: String, value) -> void:
	if server != null and local_player:
		server.leader_slot(1, slot, key, value)
	else:
		_r_slot.rpc_id(1, slot, key, var_to_bytes(value))

func fill_bots() -> void:
	if server != null and local_player:
		server.fill_bots(1)
	else:
		_r_fill.rpc_id(1)

func room_settings(nm: String, pw: String) -> void:
	if server != null and local_player:
		server.room_settings(1, nm, pw)
	else:
		_r_settings.rpc_id(1, nm, pw)

func start_match() -> void:
	if server != null and local_player:
		server.start(1)
	else:
		_r_start.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _r_hello(nm: String, fp: int, proto: int, pw: String) -> void:
	if server == null:
		return
	var id := _sender()
	var why := server.hello(id, nm, fp, proto, pw)
	if why != "":
		_r_refused.rpc_id(id, why)
		_kick_later(id)

@rpc("any_peer", "call_remote", "reliable")
func _r_chat(text: String) -> void:
	if server != null:
		server.chat(_sender(), text)

@rpc("any_peer", "call_remote", "reliable")
func _r_create(nm: String, pw: String, preset: String) -> void:
	if server != null:
		server.create_room(_sender(), nm, pw, preset)

@rpc("any_peer", "call_remote", "reliable")
func _r_join(rid: int, pw: String) -> void:
	if server != null:
		server.join_room(_sender(), rid, pw)

@rpc("any_peer", "call_remote", "reliable")
func _r_quick() -> void:
	if server != null:
		server.quick_join(_sender())

@rpc("any_peer", "call_remote", "reliable")
func _r_leave() -> void:
	if server != null:
		server.leave_room(_sender())

@rpc("any_peer", "call_remote", "reliable")
func _r_set(key: String, bytes: PackedByteArray) -> void:
	if server != null and bytes.size() < 20000:
		server.set_mine(_sender(), key, bytes_to_var(bytes))

@rpc("any_peer", "call_remote", "reliable")
func _r_move(slot: int) -> void:
	if server != null:
		server.move_to(_sender(), slot)

@rpc("any_peer", "call_remote", "reliable")
func _r_slot(slot: int, key: String, bytes: PackedByteArray) -> void:
	if server != null and bytes.size() < 1000:
		server.leader_slot(_sender(), slot, key, bytes_to_var(bytes))

@rpc("any_peer", "call_remote", "reliable")
func _r_fill() -> void:
	if server != null:
		server.fill_bots(_sender())

@rpc("any_peer", "call_remote", "reliable")
func _r_settings(nm: String, pw: String) -> void:
	if server != null:
		server.room_settings(_sender(), nm, pw)

@rpc("any_peer", "call_remote", "reliable")
func _r_start() -> void:
	if server != null:
		server.start(_sender())

func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if _peer != null and server != null:
		_peer.disconnect_peer(id)

## Round trip to a player in milliseconds (server side; 0 for the host's own player).
func peer_ping(peer: int) -> int:
	if _peer == null or peer == 1:
		return 0
	var pp := _peer.get_peer(peer)
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if pp != null else 0

## My round trip to the server (0 when this machine hosts it).
func my_ping() -> int:
	if server != null or _peer == null:
		return 0
	var pp := _peer.get_peer(1)
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if pp != null else 0

# ---- Messages from the server (NetServer calls s_*; the hosting player's own arrive directly) ------------------------

func _local(peer: int) -> bool:
	return peer == 1 and server != null and local_player

## Still connected (a player whose connection is closing is skipped rather than sent to).
func _alive(peer: int) -> bool:
	if _peer == null:
		return false
	var pp := _peer.get_peer(peer)
	return pp != null and pp.get_state() == ENetPacketPeer.STATE_CONNECTED

func s_welcome(peer: int, d: Dictionary) -> void:
	if _local(peer):
		_on_welcome(d)
	elif _alive(peer):
		_r_welcome.rpc_id(peer, var_to_bytes(d))

func s_hub(peer: int, bytes: PackedByteArray) -> void:
	if _local(peer):
		_on_hub(bytes)
	elif _alive(peer):
		_r_hub.rpc_id(peer, bytes)

func s_hub_log(peer: int, lines: Array) -> void:
	if _local(peer):
		_on_hub_log(lines)
	elif _alive(peer):
		_r_hub_log.rpc_id(peer, var_to_bytes(lines))

func s_chat(peer: int, channel: String, nm: String, text: String, system: bool) -> void:
	if _local(peer):
		_on_chat(channel, nm, text, system)
	elif _alive(peer):
		_r_chat_line.rpc_id(peer, channel, nm, text, system)

func s_notice(peer: int, text: String) -> void:
	if _local(peer):
		notice.emit(text)
	elif _alive(peer):
		_r_notice.rpc_id(peer, text)

func s_room(peer: int, bytes: PackedByteArray) -> void:
	if _local(peer):
		_on_room(bytes)
	elif _alive(peer):
		_r_room.rpc_id(peer, bytes)

func s_room_left(peer: int, reason: String) -> void:
	if _local(peer):
		_on_room_left(reason)
	elif _alive(peer):
		_r_room_left.rpc_id(peer, reason)

func s_begin(peer: int, bytes: PackedByteArray) -> void:
	if _local(peer):
		_on_begin(bytes)
	elif _alive(peer):
		_r_begin.rpc_id(peer, bytes)

func s_go(peer: int) -> void:
	if _local(peer):
		_on_go()
	elif _alive(peer):
		_r_go.rpc_id(peer)

func s_frame(peer: int, f: int, bytes: PackedByteArray) -> void:
	if _local(peer):
		_on_frame(f, bytes)
	elif _alive(peer):
		_r_frame.rpc_id(peer, f, bytes)

func s_snap_request(peer: int) -> void:
	if _local(peer):
		_on_snap_request()
	elif _alive(peer):
		_r_snap_request.rpc_id(peer)

func s_snapshot(peer: int, f: int, bytes: PackedByteArray) -> void:
	if _local(peer):
		_on_snapshot(f, bytes)
	elif _alive(peer):
		_r_snapshot.rpc_id(peer, f, bytes)

@rpc("authority", "call_remote", "reliable")
func _r_refused(reason: String) -> void:
	leave_server(reason)

@rpc("authority", "call_remote", "reliable")
func _r_welcome(bytes: PackedByteArray) -> void:
	var d = bytes_to_var(bytes)
	if d is Dictionary:
		_on_welcome(d)

func _on_welcome(d: Dictionary) -> void:
	my_name = String(d.get("name", my_name))
	my_id = int(d.get("id", multiplayer.get_unique_id()))
	server_info = d.get("server", {})
	state = State.HUB
	status_changed.emit("")
	connected.emit()

@rpc("authority", "call_remote", "reliable")
func _r_hub(bytes: PackedByteArray) -> void:
	_on_hub(bytes)

func _on_hub(bytes: PackedByteArray) -> void:
	var d = bytes_to_var(bytes)
	if d is Dictionary:
		hub = d
		server_info = d.get("server", server_info)
		hub_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _r_hub_log(bytes: PackedByteArray) -> void:
	var d = bytes_to_var(bytes)
	if d is Array:
		_on_hub_log(d)

func _on_hub_log(lines: Array) -> void:
	hub_log = lines.duplicate()
	hub_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _r_chat_line(channel: String, nm: String, text: String, system: bool) -> void:
	_on_chat(channel, nm, text, system)

func _on_chat(channel: String, nm: String, text: String, system: bool) -> void:
	var log: Array = room_log if channel == "room" else hub_log
	log.append([nm, text, system])
	if log.size() > 80:
		log.pop_front()
	chat_received.emit(channel, nm, text, system)

@rpc("authority", "call_remote", "reliable")
func _r_notice(text: String) -> void:
	notice.emit(text)

@rpc("authority", "call_remote", "reliable")
func _r_room(bytes: PackedByteArray) -> void:
	_on_room(bytes)

func _on_room(bytes: PackedByteArray) -> void:
	var d = bytes_to_var(bytes)
	if not (d is Dictionary):
		return
	var fresh := room.is_empty() or int(room.get("id", -1)) != int(d.get("id", -2))
	room = d
	if fresh:
		room_log = []
	if state == State.HUB:
		state = State.ROOM
	room_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _r_room_left(reason: String) -> void:
	_on_room_left(reason)

func _on_room_left(reason: String) -> void:
	room = {}
	room_log = []
	if state != State.OFF and state != State.CONNECTING:
		state = State.HUB
	room_left.emit(reason)

# ---- The match ------------------------------------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _r_begin(bytes: PackedByteArray) -> void:
	_on_begin(bytes)

func _on_begin(bytes: PackedByteArray) -> void:
	var cfg = bytes_to_var(bytes)
	if not (cfg is Dictionary):
		return
	config = cfg
	config["me"] = my_id
	state = State.LOADING
	m = null
	match_starting.emit()
	if not headless_test:
		get_tree().paused = false
		Options.go(get_tree(), "res://src/game/main.tscn")

## The match scene finished loading here: the lockstep starts once the server says go.
func match_loaded(world: SimWorld, slot_heroes: Dictionary) -> NetMatch:
	m = NetMatch.new()
	m.net = self
	m.world = world
	m.slot_heroes = slot_heroes
	for s in config.slots:
		if String(s.kind) == "human":
			m.slot_peer[int(s.slot)] = int(s.peer)
			m.slot_name[int(s.slot)] = String(s.name)
			if int(s.peer) == my_id:
				m.my_slot = int(s.slot)
	if server != null and local_player:
		server.loaded(1)
	else:
		_r_loaded.rpc_id(1)
	return m

@rpc("any_peer", "call_remote", "reliable")
func _r_loaded() -> void:
	if server != null:
		server.loaded(_sender())

@rpc("authority", "call_remote", "reliable")
func _r_go() -> void:
	_on_go()

func _on_go() -> void:
	state = State.PLAYING
	if m != null:
		m.running = true

## The end screen showed: the room becomes a lobby again a few seconds later.
func report_match_over() -> void:
	if server != null and local_player:
		server.match_over(1)
	elif _peer != null:
		_r_over.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _r_over() -> void:
	if server != null:
		server.match_over(_sender())

## Back from the match to the room (or the lobby list if the room is gone).
func back_from_match() -> void:
	m = null
	config = {}
	if state == State.OFF:
		return
	state = State.ROOM if not room.is_empty() else State.HUB

func send_command(c: Dictionary) -> void:
	if server != null and local_player:
		server.command(1, c)
	elif _peer != null:
		_r_cmd.rpc_id(1, var_to_bytes(c))
		flush()

## Put queued packets on the wire now rather than at the next network poll (commands, a tick's frames).
func flush() -> void:
	if _peer != null and _peer.host != null:
		_peer.host.flush()

@rpc("any_peer", "call_remote", "reliable", 1)
func _r_cmd(bytes: PackedByteArray) -> void:
	if server != null and bytes.size() < 8192:
		server.command(_sender(), bytes_to_var(bytes))

@rpc("authority", "call_remote", "reliable", 1)
func _r_frame(f: int, bytes: PackedByteArray) -> void:
	_on_frame(f, bytes)

func _on_frame(f: int, bytes: PackedByteArray) -> void:
	if m == null:
		return
	var cmds = bytes_to_var(bytes)
	if cmds is Array:
		m.receive_frame(f, cmds)

func send_hash(f: int, h: int) -> void:
	if server != null and local_player:
		server.hash_report(1, f, h)
	elif _peer != null:
		_r_hash.rpc_id(1, f, h)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _r_hash(f: int, h: int) -> void:
	if server != null:
		server.hash_report(_sender(), f, h)

@rpc("authority", "call_remote", "reliable", 1)
func _r_snap_request() -> void:
	_on_snap_request()

## The server wants my world (it agrees with the majority) for a player who needs it.
func _on_snap_request() -> void:
	if m == null or not m.running:
		return
	var f := m.frame - 1
	var bytes := SimSnapshot.capture(m.world)
	if server != null and local_player:
		server.snapshot_reply(1, f, bytes)
	else:
		_r_snap.rpc_id(1, f, bytes)

@rpc("any_peer", "call_remote", "reliable", 1)
func _r_snap(f: int, bytes: PackedByteArray) -> void:
	if server != null:
		server.snapshot_reply(_sender(), f, bytes)

@rpc("authority", "call_remote", "reliable", 1)
func _r_snapshot(f: int, bytes: PackedByteArray) -> void:
	_on_snapshot(f, bytes)

func _on_snapshot(f: int, bytes: PackedByteArray) -> void:
	if m != null:
		m.receive_snapshot(f, bytes)

# ---- Server queries (the browser's view of a server, over plain UDP) ------------------------------------------------

func _query_start(qport: int) -> void:
	_query = PacketPeerUDP.new()
	if _query.bind(qport) != OK:
		_query = null

func _query_stop() -> void:
	if _query != null:
		_query.close()
	_query = null

## Answer "WOAQ" + token with the server's card (as JSON, with the token back so the asker can time the round trip).
func _query_answer() -> void:
	if _query == null:
		return
	var n := 0
	while _query.get_available_packet_count() > 0 and n < 64:
		n += 1
		var pkt := _query.get_packet()
		if pkt.size() < 8 or pkt.slice(0, 4).get_string_from_ascii() != "WOAQ":
			continue
		var d := server.info()
		d["game"] = "woa"
		d["t"] = pkt.decode_u32(4)
		_query.set_dest_address(_query.get_packet_ip(), _query.get_packet_port())
		_query.put_packet(JSON.stringify(d).to_utf8_buffer())

# ---- Router port (UPnP), for servers reached over the internet --------------------------------------------------------

func _open_router(port: int) -> void:
	upnp_status = "Asking your router to open the port"
	status_changed.emit(upnp_status)
	var th := Thread.new()
	th.start(func():
		var u := UPNP.new()
		var r := u.discover(2000, 2)
		var msg := ""
		var ok := false
		if r != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
			msg = "Your router did not answer. Players outside your network need UDP ports %d and %d forwarded to this computer." % [port, port + 1]
		elif u.add_port_mapping(port, port, "Warriors of Aether", "UDP") != UPNP.UPNP_RESULT_SUCCESS:
			msg = "Your router refused to open UDP port %d." % port
		else:
			u.add_port_mapping(port + 1, port + 1, "Warriors of Aether queries", "UDP")
			msg = "Port %d is open. Players can join at %s" % [port, u.query_external_address()]
			ok = true
		call_deferred("_router_done", msg, th, u if ok else null))

func _router_done(msg: String, th: Thread, u: UPNP) -> void:
	th.wait_to_finish()
	if server == null:
		if u != null:
			u.delete_port_mapping(server_port_hint, "UDP")
		return
	_upnp = u
	upnp_status = msg
	status_changed.emit(msg)

var server_port_hint := PORT

func _close_router() -> void:
	var u := _upnp
	_upnp = null
	if u != null:
		u.delete_port_mapping(server_port_hint, "UDP")
		u.delete_port_mapping(server_port_hint + 1, "UDP")
