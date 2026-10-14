class_name NetServer
extends RefCounted
## A multiplayer server: the main server, a community server someone runs on a spare machine
## (`WarriorsOfAether.exe --headless -- --server`), or a server a player hosts from the Multiplayer screen while playing
## on it. Players connect to it and land in its lobby list (with a chat for everyone there); each lobby is a room of
## ten slots with a leader who starts the match.
##
## Matches are relayed, never simulated here, so one server can run many at once: the server is each match's clock.
## Every 1/30 s it closes a frame for every running match (the commands its players sent since the last one, each
## tagged with the sender's slot) and sends it to that match's players, who all step the same deterministic world with
## it. Once a second every player sends a fingerprint of its world; when one differs from the others for the same
## frame, the server asks a player whose world agrees with the majority for a snapshot and passes it on, with the frames
## after it, to the one that drifted. A player who drops is replaced by a bot until they connect again with the same
## name, when they get a snapshot and their hero back. Net (the autoload) carries every message.

const MAX_ROOMS := 40
const KEEP_FRAMES := 900                    # frames kept for repairs and late joiners (30 s)
const HASH_WAIT_MS := 2500                  # how long a frame's fingerprints are collected before they are compared
const LOAD_WAIT_MS := 120000                # a match starts without a player still loading after this
const END_GRACE_MS := 8000                  # frames keep coming this long after a player reports the end
const HUB_KEEP := 40                        # lobby-list chat lines a newcomer sees
const RESYNC_GAP_MS := 4000

var net                                     # the Net autoload
var server_name := "Server"
var motd := ""
var password := ""
var port := 27850
var max_players := 64
var dedicated := false
var started_at := 0

var players := {}                           # peer -> {name, room (-1 = the lobby list), joined (ms)}
var rooms := {}                             # id -> room (see _new_room)
var _next_room := 1
var _hub_log: Array = []                    # [name, text, system]
var _hub_dirty := true
var _hub_sent := 0
var _rng := RandomNumberGenerator.new()
var _tick_n := 0
var sid := 0                                # tells this server apart from others (the browser merges its answers)

func _init() -> void:
	_rng.randomize()
	started_at = Time.get_ticks_msec()
	sid = _rng.randi()

func log_line(s: String) -> void:
	if dedicated:
		print("[%s] %s" % [Time.get_time_string_from_system(), s])

# ---- Players ----------------------------------------------------------------------------------------------------------

## A player introduced itself. Returns "" or why it is refused.
func hello(peer: int, nm: String, fp: int, proto: int, pw: String) -> String:
	if proto != NetSession.PROTOCOL or fp != NetSession.rules_fingerprint():
		return "This server runs a different version of the game. Both need the same version."
	if password != "" and pw != password:
		return "Wrong server password" if pw != "" else "This server needs a password"
	if players.size() >= max_players:
		return "The server is full (%d players)" % max_players
	nm = NetSession.clean_name(nm)
	# a returning player (same name, their match still running) gets their hero back
	var back := _dropped_slot_of(nm)
	if back.is_empty() or _name_used(nm):
		nm = _free_name(nm)
		back = {}
	players[peer] = {"name": nm, "room": -1, "joined": Time.get_ticks_msec()}
	net.s_welcome(peer, {"name": nm, "id": peer, "server": info()})
	net.s_hub_log(peer, _hub_log)
	log_line("%s joined (%d online)" % [nm, players.size()])
	if not back.is_empty():
		_rejoin(peer, int(back.room), int(back.slot))
	else:
		_hub_chat("", "%s joined" % nm, true)
	_hub_dirty = true
	return ""

func _name_used(nm: String) -> bool:
	for p in players.values():
		if String(p.name).to_lower() == nm.to_lower():
			return true
	return false

func _free_name(nm: String) -> String:
	if not _name_used(nm):
		return nm
	var k := 2
	while _name_used("%s %d" % [nm, k]):
		k += 1
	return "%s %d" % [nm, k]

func gone(peer: int) -> void:
	if not players.has(peer):
		return
	var nm := String(players[peer].name)
	_leave_room(peer, true)
	players.erase(peer)
	_hub_chat("", "%s left" % nm, true)
	log_line("%s left (%d online)" % [nm, players.size()])
	_hub_dirty = true

## The server's card in the browser and on the lobby list.
func info() -> Dictionary:
	var open := 0
	for r in rooms.values():
		if String(r.state) == "lobby" and _free_slot(r) >= 0 and String(r.password) == "":
			open += 1
	return {"name": server_name, "motd": motd, "players": players.size(), "max": max_players, "rooms": rooms.size(),
		"open": open, "locked": password != "", "port": port, "p": NetSession.PROTOCOL, "fp": NetSession.rules_fingerprint(),
		"dedicated": dedicated, "up": (Time.get_ticks_msec() - started_at) / 1000, "sid": sid}

# ---- Chat -------------------------------------------------------------------------------------------------------------

func chat(peer: int, text: String) -> void:
	if not players.has(peer):
		return
	text = text.strip_edges().left(SimConst.CHAT_MAX_LEN)
	if text == "":
		return
	var nm := String(players[peer].name)
	var rid := int(players[peer].room)
	if rid >= 0 and rooms.has(rid):
		_room_chat(rooms[rid], nm, text, false)
	else:
		_hub_chat(nm, text, false)

func _hub_chat(nm: String, text: String, system: bool) -> void:
	_hub_log.append([nm, text, system])
	if _hub_log.size() > HUB_KEEP:
		_hub_log.pop_front()
	for peer in players:
		if int(players[peer].room) < 0:
			net.s_chat(int(peer), "hub", nm, text, system)

func _room_chat(r: Dictionary, nm: String, text: String, system: bool) -> void:
	for peer in _members(r):
		net.s_chat(peer, "room", nm, text, system)

# ---- Rooms ------------------------------------------------------------------------------------------------------------

func _new_room(nm: String, pw: String, leader: int) -> Dictionary:
	var slots := []
	for i in NetSession.MAX_SLOTS:
		slots.append(NetSession.open_slot())
	var r := {"id": _next_room, "name": nm, "password": pw, "leader": leader, "slots": slots,
		"seed": _rng.randi_range(1, 2000000000), "state": "lobby", "started_ms": 0, "m": {}}
	_next_room += 1
	rooms[r.id] = r
	return r

## Peers in a room (humans in its slots who are connected).
func _members(r: Dictionary) -> Array:
	var out := []
	for s in r.slots:
		if String(s.kind) == "human" and int(s.peer) > 0 and players.has(int(s.peer)):
			out.append(int(s.peer))
	return out

func _humans(r: Dictionary) -> int:
	return _members(r).size()

func _slot_of(r: Dictionary, peer: int) -> int:
	for i in r.slots.size():
		if String(r.slots[i].kind) == "human" and int(r.slots[i].peer) == peer:
			return i
	return -1

func _free_slot(r: Dictionary, prefer_team := -1) -> int:
	var counts := [0, 0]
	for i in r.slots.size():
		if String(r.slots[i].kind) in ["human", "bot"]:
			counts[NetSession.slot_team(i)] += 1
	var team := prefer_team
	if team < 0:
		team = 0 if counts[0] <= counts[1] else 1
	for t in [team, 1 - team]:
		for i in range(t * 5, t * 5 + 5):
			if String(r.slots[i].kind) == "open":
				return i
	return -1

func create_room(peer: int, nm: String, pw: String, preset: String) -> void:
	if not players.has(peer):
		return
	if rooms.size() >= MAX_ROOMS:
		net.s_notice(peer, "This server already has %d lobbies. Join one of them." % MAX_ROOMS)
		return
	_leave_room(peer, false)
	nm = nm.strip_edges().left(32)
	if nm == "":
		nm = "%s's game" % players[peer].name
	var r := _new_room(nm, pw.left(32), peer)
	if preset == "1v1":
		for i in NetSession.MAX_SLOTS:
			if i != 0 and i != 5:
				r.slots[i].kind = "closed"
	_seat(peer, r, 0)
	log_line("%s made the lobby \"%s\"" % [players[peer].name, nm])

func join_room(peer: int, rid: int, pw: String) -> void:
	if not players.has(peer):
		return
	if not rooms.has(rid):
		net.s_notice(peer, "That lobby is gone")
		return
	var r: Dictionary = rooms[rid]
	if String(r.password) != "" and pw != String(r.password):
		net.s_notice(peer, "Wrong lobby password" if pw != "" else "This lobby needs a password")
		return
	if String(r.state) != "lobby":
		# a player who left this match may go back to their hero
		var nm := String(players[peer].name).to_lower()
		for sl in r.m.get("dropped", {}):
			if String(r.m.slot_name.get(sl, "")).to_lower() == nm:
				_rejoin(peer, rid, int(sl))
				return
		net.s_notice(peer, "That lobby's match has already started")
		return
	var slot := _free_slot(r)
	if slot < 0:
		net.s_notice(peer, "That lobby is full")
		return
	_leave_room(peer, false)
	_seat(peer, r, slot)

## Into the fullest open lobby without a password, or a new one.
func quick_join(peer: int) -> void:
	var best: Dictionary = {}
	for r in rooms.values():
		if String(r.state) != "lobby" or String(r.password) != "" or _free_slot(r) < 0:
			continue
		if best.is_empty() or _humans(r) > _humans(best):
			best = r
	if best.is_empty():
		create_room(peer, "", "", "5v5")
	else:
		join_room(peer, int(best.id), "")

func _seat(peer: int, r: Dictionary, slot: int) -> void:
	var s := NetSession.open_slot()
	s.kind = "human"
	s.peer = peer
	s.name = String(players[peer].name)
	r.slots[slot] = s
	players[peer].room = int(r.id)
	_room_chat(r, "", "%s joined the lobby" % s.name, true)
	_send_room(r)
	_hub_dirty = true

func leave_room(peer: int) -> void:
	_leave_room(peer, false)
	if players.has(peer):
		net.s_room_left(peer, "")
		net.s_hub_log(peer, _hub_log)

## Out of the room (left on purpose, or disconnected): in a running match a bot takes the hero over.
func _leave_room(peer: int, disconnected: bool) -> void:
	if not players.has(peer):
		return
	var rid := int(players[peer].room)
	players[peer].room = -1
	if rid < 0 or not rooms.has(rid):
		return
	var r: Dictionary = rooms[rid]
	var slot := _slot_of(r, peer)
	var nm := String(players[peer].name)
	if slot >= 0:
		if String(r.state) == "lobby":
			r.slots[slot] = NetSession.open_slot()
		else:
			r.slots[slot].peer = 0                  # the slot keeps the name: they can come back
			_match_drop(r, slot, nm)
	if _humans(r) == 0:
		rooms.erase(rid)
		log_line("lobby \"%s\" closed" % r.name)
		_hub_dirty = true
		return
	if int(r.leader) == peer:
		r.leader = _members(r)[0]
		_room_chat(r, "", "%s leads the lobby now" % players[int(r.leader)].name, true)
	if String(r.state) == "lobby":
		_room_chat(r, "", "%s left the lobby" % nm, true)
	else:
		_room_chat(r, "", "%s %s: a bot plays their hero until they come back" % [nm, "disconnected" if disconnected else "left"], true)
	_send_room(r)
	_hub_dirty = true

## The room's state as its players see it.
func _room_view(r: Dictionary) -> Dictionary:
	var pings := {}
	for p in _members(r):
		pings[p] = net.peer_ping(p)
	return {"id": r.id, "name": r.name, "locked": String(r.password) != "", "leader": r.leader, "slots": r.slots,
		"state": r.state, "pings": pings, "time": _room_time(r)}

func _room_time(r: Dictionary) -> int:
	if String(r.state) != "playing" or r.m.is_empty():
		return 0
	return int(r.m.frame / 30)

func _send_room(r: Dictionary) -> void:
	var v := var_to_bytes(_room_view(r))
	for p in _members(r):
		net.s_room(p, v)

## A player changes their own slot: hero, lane, ready, look.
func set_mine(peer: int, key: String, value) -> void:
	var r := _room_of(peer)
	if r.is_empty() or String(r.state) != "lobby":
		return
	var i := _slot_of(r, peer)
	if i < 0:
		return
	var s: Dictionary = r.slots[i]
	match key:
		"hero":
			if value is String and (value == "random" or value in GameSettings.HEROES):
				s.hero = value
		"lane":
			if value is String and value in ["", "safe", "mid", "off"]:
				s.lane = value
		"ready":
			s.ready = bool(value)
		"look":
			if value is Dictionary and var_to_bytes(value).size() < 16384:
				s.look = value
		_:
			return
	_send_room(r)

func move_to(peer: int, slot: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or String(r.state) != "lobby" or slot < 0 or slot >= NetSession.MAX_SLOTS:
		return
	if String(r.slots[slot].kind) != "open":
		return
	var i := _slot_of(r, peer)
	if i < 0:
		return
	r.slots[slot] = r.slots[i]
	r.slots[i] = NetSession.open_slot()
	_send_room(r)

## The leader changes a slot: open, bot, closed, remove a player; a bot's hero, skill or lane.
func leader_slot(peer: int, slot: int, key: String, value) -> void:
	var r := _room_of(peer)
	if r.is_empty() or int(r.leader) != peer or String(r.state) != "lobby" or slot < 0 or slot >= NetSession.MAX_SLOTS:
		return
	var s: Dictionary = r.slots[slot]
	match key:
		"kind":
			if not (String(value) in ["open", "bot", "closed"]):
				return
			if String(s.kind) == "human":
				var who := int(s.peer)
				if who == peer:
					return
				r.slots[slot] = NetSession.open_slot()
				if players.has(who):
					players[who].room = -1
					net.s_room_left(who, "The lobby leader removed you")
					net.s_hub_log(who, _hub_log)
				_room_chat(r, "", "%s was removed from the lobby" % s.name, true)
			var n := NetSession.open_slot()
			n.kind = String(value)
			if n.kind == "bot":
				n.name = _free_bot_name(r)
				n.ready = true
			r.slots[slot] = n
		"hero":
			if String(s.kind) == "bot" and value is String and (value == "random" or value in GameSettings.HEROES):
				s.hero = value
		"skill":
			if String(s.kind) == "bot" and value is String and value in GameSettings.SKILLS:
				s.skill = value
		_:
			return
	_send_room(r)
	_hub_dirty = true

func _free_bot_name(r: Dictionary) -> String:
	var used := {}
	for s in r.slots:
		used[String(s.name)] = true
	for b in GameSettings.BOT_NAMES:
		if not used.has(b):
			return b
	return "Bot"

func fill_bots(peer: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or int(r.leader) != peer:
		return
	for i in NetSession.MAX_SLOTS:
		if String(r.slots[i].kind) == "open":
			leader_slot(peer, i, "kind", "bot")

func room_settings(peer: int, nm: String, pw: String) -> void:
	var r := _room_of(peer)
	if r.is_empty() or int(r.leader) != peer:
		return
	nm = nm.strip_edges().left(32)
	if nm != "":
		r.name = nm
	r.password = pw.left(32)
	_send_room(r)
	_hub_dirty = true

func _room_of(peer: int) -> Dictionary:
	if not players.has(peer):
		return {}
	var rid := int(players[peer].room)
	return rooms.get(rid, {})

# ---- Starting a match -------------------------------------------------------------------------------------------------

func start(peer: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or int(r.leader) != peer or String(r.state) != "lobby":
		return
	var why := NetSession.start_problem(r.slots)
	if why != "":
		net.s_notice(peer, why)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r.seed)
	var slots := []
	for i in NetSession.MAX_SLOTS:
		var s: Dictionary = (r.slots[i] as Dictionary).duplicate(true)
		if not (String(s.kind) in ["human", "bot"]):
			continue
		if String(s.hero) == "random" or not (String(s.hero) in GameSettings.HEROES):
			s.hero = GameSettings.HEROES[rng.randi_range(0, GameSettings.HEROES.size() - 1)]
		s["slot"] = i
		s["team"] = NetSession.slot_team(i)
		slots.append(s)
	var cfg := {"seed": int(r.seed), "slots": slots, "room": r.id, "room_name": r.name}
	r.state = "loading"
	r.started_ms = Time.get_ticks_msec()
	var m := {"cfg": cfg, "frame": 0, "pending": [], "ring": {}, "hashes": {}, "hash_t": {}, "loaded": {},
		"running": false, "load_deadline": Time.get_ticks_msec() + LOAD_WAIT_MS, "slot_peer": {}, "slot_name": {},
		"dropped": {}, "resync_at": {}, "snap_for": [], "snap_asked": 0, "end_at": 0, "waiting": {}}
	for s in slots:
		if String(s.kind) == "human":
			m.slot_peer[int(s.slot)] = int(s.peer)
			m.slot_name[int(s.slot)] = String(s.name)
	r.m = m
	var bytes := var_to_bytes(cfg)
	for p in _members(r):
		net.s_begin(p, bytes)
	log_line("lobby \"%s\" started a match (%d players)" % [r.name, _humans(r)])
	_send_room(r)
	_hub_dirty = true

## A player's match scene is ready.
func loaded(peer: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or r.m.is_empty():
		return
	var m: Dictionary = r.m
	m.loaded[peer] = true
	if m.running:
		# joined late or came back: the world as it stands, then frames as usual
		_snapshot_for(r, peer)
		net.s_go(peer)
		return
	_check_all_loaded(r)

func _check_all_loaded(r: Dictionary) -> void:
	var m: Dictionary = r.m
	if m.running:
		return
	var waiting := false
	for p in _members(r):
		if not m.loaded.has(p):
			waiting = true
	if waiting and Time.get_ticks_msec() < int(m.load_deadline):
		return
	m.running = true
	r.state = "playing"
	for p in _members(r):
		if m.loaded.has(p):
			net.s_go(p)
	_send_room(r)
	_hub_dirty = true

# ---- Running matches --------------------------------------------------------------------------------------------------

## A player's command: into the next frame under their slot.
func command(peer: int, c) -> void:
	var r := _room_of(peer)
	if r.is_empty() or r.m.is_empty() or not (c is Dictionary):
		return
	var m: Dictionary = r.m
	for s in m.slot_peer:
		if int(m.slot_peer[s]) == peer and not m.dropped.has(s):
			m.pending.append([int(s), c])
			return

func _close_frame(r: Dictionary) -> void:
	var m: Dictionary = r.m
	var f := int(m.frame)
	var cmds: Array = m.pending
	m.pending = []
	m.ring[f] = cmds
	m.ring.erase(f - KEEP_FRAMES)
	var bytes := var_to_bytes(cmds)
	for p in _members(r):
		if m.loaded.has(p) and not m.waiting.has(p):
			net.s_frame(p, f, bytes)
	m.frame = f + 1

func hash_report(peer: int, f: int, h: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or r.m.is_empty():
		return
	var m: Dictionary = r.m
	if f < int(m.frame) - KEEP_FRAMES:
		return
	if not m.hashes.has(f):
		m.hashes[f] = {}
		m.hash_t[f] = Time.get_ticks_msec()
	m.hashes[f][peer] = h

## Compare the fingerprints of frames that everyone reported (or that waited long enough): the players whose world
## differs from the majority's get repaired from a player in the majority.
func _check_hashes(r: Dictionary) -> void:
	var m: Dictionary = r.m
	var now := Time.get_ticks_msec()
	var live := []
	for p in _members(r):
		if m.loaded.has(p) and not m.waiting.has(p):
			live.append(p)
	for f in m.hashes.keys():
		var got: Dictionary = m.hashes[f]
		var all_in := true
		for p in live:
			if not got.has(p):
				all_in = false
		if not all_in and now - int(m.hash_t[f]) < HASH_WAIT_MS:
			continue
		m.hashes.erase(f)
		m.hash_t.erase(f)
		if got.size() < 2:
			continue
		var groups := {}
		for p in got:
			var h := int(got[p])
			if not groups.has(h):
				groups[h] = []
			groups[h].append(int(p))
		if groups.size() < 2:
			continue
		# the majority is right; on a tie, the group with the leader
		var best := -1
		for h in groups:
			var g: Array = groups[h]
			if best == -1 or g.size() > (groups[best] as Array).size() \
					or (g.size() == (groups[best] as Array).size() and int(r.leader) in g):
				best = h
		for h in groups:
			if h == best:
				continue
			for p in groups[h]:
				if now - int(m.resync_at.get(p, -100000)) < RESYNC_GAP_MS:
					continue
				m.resync_at[p] = now
				log_line("desync in \"%s\" at frame %d: repairing %s" % [r.name, f, players[p].name if players.has(p) else str(p)])
				_snapshot_for(r, p, groups[best])

## Ask a player whose world is right for a snapshot to pass on to `peer` (late joiner, returning player, desync).
func _snapshot_for(r: Dictionary, peer: int, good := []) -> void:
	var m: Dictionary = r.m
	m.waiting[peer] = true
	if not (peer in m.snap_for):
		m.snap_for.append(peer)
	var ref := -1
	for p in (good if not good.is_empty() else _members(r)):
		if p != peer and m.loaded.has(p) and not m.waiting.has(p) and players.has(p):
			ref = p
			break
	if ref < 0:
		# nobody to copy from (alone in the match): carry on without a repair
		m.waiting.erase(peer)
		m.snap_for.erase(peer)
		return
	m.snap_asked = Time.get_ticks_msec()
	net.s_snap_request(ref)

## The snapshot arrived (world after frame f): to everyone waiting for one, followed by the frames after it.
func snapshot_reply(peer: int, f: int, bytes: PackedByteArray) -> void:
	var r := _room_of(peer)
	if r.is_empty() or r.m.is_empty():
		return
	var m: Dictionary = r.m
	if f < int(m.frame) - KEEP_FRAMES + 2:
		return
	for p in m.snap_for:
		if not players.has(p):
			continue
		net.s_snapshot(p, f, bytes)
		for k in range(f + 1, int(m.frame)):
			if m.ring.has(k):
				net.s_frame(p, k, var_to_bytes(m.ring[k]))
		m.waiting.erase(p)
	m.snap_for = []

func _match_drop(r: Dictionary, slot: int, nm: String) -> void:
	var m: Dictionary = r.m
	if m.is_empty():
		return
	m.slot_peer[slot] = 0
	if not m.dropped.has(slot):
		m.dropped[slot] = true
		m.pending.append([-1, {"k": "sys_bot", "slot": slot, "name": nm}])

func _dropped_slot_of(nm: String) -> Dictionary:
	for r in rooms.values():
		if r.m.is_empty() or String(r.state) == "lobby":
			continue
		for s in r.m.dropped:
			if String(r.m.slot_name.get(s, "")).to_lower() == nm.to_lower():
				return {"room": r.id, "slot": s}
	return {}

## A dropped player is back: their slot, the match's setup, then (once loaded) a snapshot and the frames.
func _rejoin(peer: int, rid: int, slot: int) -> void:
	var r: Dictionary = rooms[rid]
	var m: Dictionary = r.m
	m.dropped.erase(slot)
	m.slot_peer[slot] = peer
	r.slots[slot].peer = peer
	r.slots[slot].kind = "human"
	players[peer].room = rid
	m.loaded.erase(peer)
	m.pending.append([-1, {"k": "sys_human", "slot": slot}])
	var cfg: Dictionary = (m.cfg as Dictionary).duplicate(true)
	for s in cfg.slots:
		if int(s.slot) == slot:
			s.peer = peer
	m.cfg = cfg
	_room_chat(r, "", "%s is back" % players[peer].name, true)
	net.s_begin(peer, var_to_bytes(cfg))
	_send_room(r)

## A player saw the match end. The frames keep coming a few seconds (the others may be a little behind), then the
## room is a lobby again.
func match_over(peer: int) -> void:
	var r := _room_of(peer)
	if r.is_empty() or r.m.is_empty() or int(r.m.end_at) > 0:
		return
	r.m.end_at = Time.get_ticks_msec() + END_GRACE_MS

func _end_match(r: Dictionary) -> void:
	r.state = "lobby"
	r.m = {}
	r.seed = _rng.randi_range(1, 2000000000)
	for i in r.slots.size():
		var s: Dictionary = r.slots[i]
		if String(s.kind) == "human":
			if int(s.peer) == 0 or not players.has(int(s.peer)):
				r.slots[i] = NetSession.open_slot()
			else:
				s.ready = false
	log_line("lobby \"%s\": match over" % r.name)
	_send_room(r)
	_hub_dirty = true

# ---- The server's clock -----------------------------------------------------------------------------------------------

## 30 times a second (Net's physics tick).
func tick() -> void:
	_tick_n += 1
	var now := Time.get_ticks_msec()
	for r in rooms.values():
		if r.m.is_empty():
			continue
		var m: Dictionary = r.m
		if not m.running:
			if _tick_n % 15 == 0:
				_check_all_loaded(r)
			continue
		_close_frame(r)
		if _tick_n % 10 == 0:
			_check_hashes(r)
			if not m.snap_for.is_empty() and now - int(m.snap_asked) > 5000:
				# the snapshot never came (that player left): ask someone else
				for p in m.snap_for.duplicate():
					m.waiting.erase(p)
					_snapshot_for(r, p)
		if int(m.end_at) > 0 and now >= int(m.end_at):
			_end_match(r)
	net.flush()
	if _tick_n % 30 == 0:
		for r in rooms.values():
			_send_room(r)                         # pings and match clocks
	if _hub_dirty and now - _hub_sent > 400:
		_hub_dirty = false
		_hub_sent = now
		_send_hub()
	elif now - _hub_sent > 3000:
		_hub_sent = now
		_send_hub()

func _hub_view() -> Dictionary:
	var list := []
	for r in rooms.values():
		var humans := 0
		var bots := 0
		var seats := 0
		for s in r.slots:
			match String(s.kind):
				"human":
					humans += 1
					seats += 1
				"bot":
					bots += 1
					seats += 1
				"open":
					seats += 1
		list.append({"id": r.id, "name": r.name, "leader": String(players[int(r.leader)].name) if players.has(int(r.leader)) else "",
			"humans": humans, "bots": bots, "seats": seats, "state": r.state, "locked": String(r.password) != "",
			"time": _room_time(r), "dropped": (r.m.get("dropped", {}) as Dictionary).keys().map(func(sl): return String(r.m.slot_name.get(sl, "")))})
	var who := []
	for p in players:
		var rid := int(players[p].room)
		var where := ""
		if rid >= 0 and rooms.has(rid):
			where = ("In a match: " if String(rooms[rid].state) != "lobby" else "In ") + String(rooms[rid].name)
		who.append({"name": players[p].name, "where": where, "ping": net.peer_ping(int(p))})
	return {"server": info(), "rooms": list, "players": who}

func _send_hub() -> void:
	var targets := []
	for p in players:
		targets.append(int(p))
	if targets.is_empty():
		return
	var v := var_to_bytes(_hub_view())
	for p in targets:
		net.s_hub(p, v)
