class_name NetBrowser
extends RefCounted
## The Multiplayer screen's server list: the main server, your saved servers and servers on your local network, each
## asked every few seconds (one small UDP packet to the server's query port, its game port + 1) for its name, message,
## players, lobbies and version; the answer's round trip is the ping. Also the player's multiplayer preferences
## (name, saved servers, the last server hosted) in user://multiplayer.json.

const PREFS := "user://multiplayer.json"
const MAIN_FILE := "res://src/net/main_server.json"
const ASK_EVERY_MS := 2500
const OFFLINE_AFTER_MS := 6000
const LAN_PORTS := [27850, 27860, 27870, 27880]   # game ports a local server is looked for on

## A server in the list: {key, name, address, port, kind ("main" / "saved" / "lan"), online, info, ping, asked, seen}.
var servers: Array = []
var _udp: PacketPeerUDP
var _token := 1
var _sent := {}                             # token -> [key, usec]
var _asked_at := 0
var _resolving := {}                        # address -> resolver queue id
var _resolved := {}                         # address -> ip
signal changed

static var prefs := {}

static func load_prefs() -> Dictionary:
	if not prefs.is_empty():
		return prefs
	prefs = {"name": "", "saved": [], "host": {"name": "", "motd": "", "password": "", "port": NetSession.PORT,
		"max_players": 32, "open_router": false}, "last_address": ""}
	var f := FileAccess.open(PREFS, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				prefs[k] = d[k]
	if String(prefs.name) == "":
		prefs.name = NetSession.clean_name(OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else "Player")
	return prefs

static func save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))

## The main server this build points at: {name, address, port}; address "" when this build has none.
static func main_server() -> Dictionary:
	var out := {"name": "Main server", "address": "", "port": NetSession.PORT}
	var f := FileAccess.open(MAIN_FILE, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in out:
				if d.has(k):
					out[k] = d[k]
	out.port = int(out.port)
	return out

func _init() -> void:
	load_prefs()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.bind(0)
	_rebuild()

func close() -> void:
	if _udp != null:
		_udp.close()
	_udp = null

static func split_address(addr: String, port := NetSession.PORT) -> Array:
	addr = addr.strip_edges()
	if addr.contains(":") and not addr.begins_with("["):
		var parts := addr.rsplit(":", true, 1)
		if parts[1].is_valid_int():
			return [parts[0], int(parts[1])]
	return [addr, port]

func _key(address: String, port: int) -> String:
	return "%s:%d" % [address.to_lower(), port]

## The list from the main server and the saved ones (local network servers are added as they answer).
func _rebuild() -> void:
	var old := {}
	for s in servers:
		old[s.key] = s
	servers = []
	var ms := main_server()
	_add(old, "main", String(ms.name), String(ms.address), int(ms.port))
	for e in prefs.saved:
		_add(old, "saved", String(e.get("name", "")), String(e.address), int(e.get("port", NetSession.PORT)))
	for s in old.values():
		if s.kind == "lan" and s.online:
			servers.append(s)

func _add(old: Dictionary, kind: String, nm: String, address: String, port: int) -> void:
	var key := _key(address, port) if address != "" else "main"
	var s: Dictionary = old.get(key, {"key": key, "online": false, "info": {}, "ping": 0, "asked": 0, "seen": 0})
	s.kind = kind
	s.name = nm
	s.address = address
	s.port = port
	servers.append(s)

func add_saved(nm: String, address: String) -> String:
	var ap := split_address(address)
	if String(ap[0]) == "":
		return "Type the server's address"
	for e in prefs.saved:
		if _key(String(e.address), int(e.get("port", NetSession.PORT))) == _key(ap[0], ap[1]):
			return "That server is already in your list"
	prefs.saved.append({"name": nm.strip_edges().left(40), "address": ap[0], "port": ap[1]})
	save_prefs()
	_rebuild()
	_asked_at = 0
	changed.emit()
	return ""

func remove_saved(key: String) -> void:
	prefs.saved = (prefs.saved as Array).filter(func(e): return _key(String(e.address), int(e.get("port", NetSession.PORT))) != key)
	save_prefs()
	_rebuild()
	changed.emit()

func is_saved(s: Dictionary) -> bool:
	return s.kind == "saved"

## Keep asking: call every frame while the screen is open.
func poll() -> void:
	if _udp == null:
		return
	var now := Time.get_ticks_msec()
	if now >= _asked_at:
		_asked_at = now + ASK_EVERY_MS
		_ask_all()
	_resolve_poll()
	var any := false
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if not (d is Dictionary) or String(d.get("game", "")) != "woa":
			continue
		any = _answer(ip, d) or any
	for s in servers:
		if s.online and now - int(s.seen) > OFFLINE_AFTER_MS:
			s.online = false
			any = true
	var before := servers.size()
	servers = servers.filter(func(s): return s.kind != "lan" or s.online)
	_merge()
	if any or servers.size() != before:
		changed.emit()

## One line per server: a local-network answer from a server already listed (saved, main, or the same server seen at
## another address, e.g. 127.0.0.1 and its network address) is dropped; a network address beats 127.0.0.1.
func _merge() -> void:
	var by_sid := {}
	var keep := []
	for s in servers:
		var id := int((s.info as Dictionary).get("sid", 0)) if s.online else 0
		if id == 0 or not by_sid.has(id):
			if id != 0:
				by_sid[id] = s
			keep.append(s)
			continue
		var other: Dictionary = by_sid[id]
		if s.kind == "lan" and other.kind == "lan" and _is_local(String(other.address)) and not _is_local(String(s.address)):
			keep[keep.find(other)] = s
			by_sid[id] = s
		elif s.kind != "lan" and other.kind == "lan":
			keep[keep.find(other)] = s
			by_sid[id] = s
	servers = keep

## Ask again right away (the Refresh button).
func refresh() -> void:
	_asked_at = 0

func _ask_all() -> void:
	for s in servers:
		if String(s.address) == "":
			continue
		var ip := _ip_of(String(s.address))
		if ip != "":
			_ask(ip, int(s.port) + 1, s.key)
	# the local network (and this computer)
	for p in LAN_PORTS:
		_ask("255.255.255.255", p + 1, "")
		_ask("127.0.0.1", p + 1, "")

func _ask(ip: String, qport: int, key: String) -> void:
	_token = (_token % 2000000000) + 1
	_sent[_token] = [key, Time.get_ticks_usec()]
	if _sent.size() > 400:
		_sent.erase(_sent.keys()[0])
	var pkt := "WOAQ".to_ascii_buffer()
	pkt.resize(8)
	pkt.encode_u32(4, _token)
	_udp.set_dest_address(ip, qport)
	_udp.put_packet(pkt)

func _answer(ip: String, d: Dictionary) -> bool:
	var tok := int(d.get("t", 0))
	if not _sent.has(tok):
		return false
	var key0 := String(_sent[tok][0])
	var ms := (Time.get_ticks_usec() - int(_sent[tok][1])) / 1000.0
	_sent.erase(tok)
	var port := int(d.get("port", NetSession.PORT))
	var s: Dictionary = {}
	for e in servers:
		if e.key == key0 or (key0 == "" and (_ip_of(String(e.address)) == ip or (ip == "127.0.0.1" and _is_local(String(e.address)))) and int(e.port) == port):
			s = e
			break
	if s.is_empty():
		# a server on the local network we did not know
		var shown := ip if ip != "127.0.0.1" else "127.0.0.1"
		var key := _key(shown, port)
		for e in servers:
			if e.key == key:
				s = e
		if s.is_empty():
			s = {"key": key, "kind": "lan", "name": "", "address": shown, "port": port, "online": false, "info": {}, "ping": 0,
				"asked": 0, "seen": 0}
			servers.append(s)
	s.online = true
	s.seen = Time.get_ticks_msec()
	s.info = d
	s.ping = int(ms) if int(s.ping) <= 0 else int(lerpf(float(s.ping), ms, 0.4))
	s["same_version"] = int(d.get("p", 0)) == NetSession.PROTOCOL and int(d.get("fp", 0)) == NetSession.rules_fingerprint()
	return true

func _is_local(addr: String) -> bool:
	return addr in ["127.0.0.1", "localhost", "::1"]

## Addresses may be names (play.example.com): looked up in the background, numbers used as they are.
func _ip_of(addr: String) -> String:
	if addr.is_valid_ip_address():
		return addr
	if addr == "localhost":
		return "127.0.0.1"
	if _resolved.has(addr):
		return String(_resolved[addr])
	if not _resolving.has(addr):
		_resolving[addr] = IP.resolve_hostname_queue_item(addr, IP.TYPE_IPV4)
	return ""

func _resolve_poll() -> void:
	for addr in _resolving.keys():
		var id: int = _resolving[addr]
		var st := IP.get_resolve_item_status(id)
		if st == IP.RESOLVER_STATUS_DONE:
			_resolved[addr] = IP.get_resolve_item_address(id)
			IP.erase_resolve_item(id)
			_resolving.erase(addr)
			_asked_at = 0
		elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE:
			_resolved[addr] = ""
			IP.erase_resolve_item(id)
			_resolving.erase(addr)
