class_name NetMatch
extends RefCounted
## One player's side of a multiplayer match (NetServer explains the scheme). Main calls physics_tick() 30 times a
## second; it steps the world through `step_world` once per frame from the server (more when catching up, none while
## waiting for one). Commands are SimCommands dictionaries; in a frame each is [slot, command], slot -1 for the
## server's own system commands (a bot takes over a dropped player's hero, the player comes back).

const HASH_EVERY := 30
const MAX_CATCH_UP := 6

var net                                     # the Net autoload
var world: SimWorld
var running := false
var slot_heroes := {}                       # slot -> hero unit id
var slot_peer := {}                         # slot -> peer id (human players)
var slot_name := {}                         # slot -> player name
var my_slot := -1
var frame := 0                              # the next frame to step
var step_world: Callable                    # Main: one simulation tick with its events and views
var on_world_replaced: Callable             # Main: a snapshot replaced the world (repair, rejoin)
var on_system: Callable                     # Main: a system command ran (for messages)

var _frames := {}                           # frame -> commands, received and not yet stepped
var target_buffer := 0                      # frames kept in hand against network jitter (adjusts itself)
var _stalls: Array = []                     # times (ms) a frame was wanted and none was there
var _last_stall := 0
var _starved_since := 0
var _last_arrival := 0                      # when the newest frame arrived (ms)
const LATE_MS := 50                         # no frame for this long (1.5 frames) is a stall, not just the gap between two
var bot_slots := {}                         # slot -> true while a bot plays a disconnected player's hero
var status := ""                            # shown by the HUD: "Waiting for the server", "Catching up"
var resyncs := 0
var latency_ms := 0.0                       # smoothed time from sending a command to running it here
var _seq := 0
var _sent := {}                             # seq -> send time (usec)
var frames_stepped := 0
## Tests only: pretend the connection is slow (each way: sim_lag_ms / 2 plus up to sim_jitter_ms, order kept).
var sim_lag_ms := 0
var sim_jitter_ms := 0
var _in_q: Array = []                       # [release ms, frame, cmds]
var _out_q: Array = []                      # [release ms, command]
var _in_last := 0
var _out_last := 0
var _lag_rng := RandomNumberGenerator.new()

## The heroes of a multiplayer match, in slot order, so every machine makes the same units with the same ids. Every
## human hero counts as a player's (the bots leave their lanes alone); bots never learn in multiplayer, so every
## machine's bots decide alike. look_of(slot) gives a hero's appearance (presentation only). Returns
## {slot_heroes: {slot: hero id}, mine: this machine's hero id}.
static func spawn_heroes(w: SimWorld, cfg: Dictionary, me: int, look_of: Callable) -> Dictionary:
	BotMemory.active = false
	var slot_heroes := {}
	var mine := -1
	for s in cfg.slots:
		var team := int(s.team)
		var h := w.spawn_hero(String(s.hero), team, look_of.call(s))
		slot_heroes[int(s.slot)] = h.id
		if String(s.kind) == "human":
			h.player = true
			w.brain(team).player_pref[h.id] = String(s.get("lane", ""))
			if int(s.peer) == me:
				mine = h.id
		else:
			w.bots.append(SimBot.new(w, h.id, "mid", String(s.name), String(s.get("skill", "hard"))))
	if mine < 0 and not w.heroes.is_empty():
		mine = w.heroes[0].id
	return {"slot_heroes": slot_heroes, "mine": mine}

# ---- Commands -------------------------------------------------------------------------------------------------------

func send_command(c: Dictionary) -> void:
	_seq += 1
	var cc := c.duplicate(true)
	cc["seq"] = _seq
	_sent[_seq] = Time.get_ticks_usec()
	if _sent.size() > 256:
		_sent.erase(_sent.keys()[0])
	if sim_lag_ms > 0:
		_out_last = maxi(_out_last, Time.get_ticks_msec() + sim_lag_ms / 2 + _lag_rng.randi_range(0, sim_jitter_ms))
		_out_q.append([_out_last, cc])
	else:
		net.send_command(cc)

func _apply(cmds: Array) -> void:
	for e in cmds:
		if not (e is Array) or e.size() < 2 or not (e[1] is Dictionary):
			continue
		var slot := int(e[0])
		var c: Dictionary = e[1]
		if slot < 0:
			_system(c)
			continue
		var hid := int(slot_heroes.get(slot, -1))
		if hid < 0:
			continue
		SimCommands.apply(world, hid, c, true)
		if slot == my_slot and c.has("seq") and _sent.has(int(c.seq)):
			var ms := (Time.get_ticks_usec() - int(_sent[int(c.seq)])) / 1000.0
			_sent.erase(int(c.seq))
			latency_ms = ms if latency_ms <= 0.0 else lerpf(latency_ms, ms, 0.2)

## System commands (the server's, identical on every machine): a bot plays a dropped player's hero, or hands it back.
func _system(c: Dictionary) -> void:
	var slot := int(c.get("slot", -1))
	var hid := int(slot_heroes.get(slot, -1))
	var h := world.get_unit(hid)
	if h == null:
		return
	match String(c.get("k", "")):
		"sys_bot":
			if not bot_slots.has(slot):
				bot_slots[slot] = true
				world.bots.append(SimBot.new(world, hid, "mid", String(c.get("name", "Bot")), "hard"))
		"sys_human":
			if bot_slots.has(slot):
				bot_slots.erase(slot)
				for b in world.bots.duplicate():
					if b.hero_id == hid:
						world.bots.erase(b)
				h.bot = false
				h.bot_name = ""
				h.gain_mult = 1.0
				world.orders.clear(h)
	if on_system.is_valid():
		on_system.call(c)

# ---- Stepping -------------------------------------------------------------------------------------------------------

func physics_tick() -> void:
	if not running:
		status = "Waiting for every player to load"
		return
	var now := Time.get_ticks_msec()
	while not _in_q.is_empty() and int(_in_q[0][0]) <= now:
		var e: Array = _in_q.pop_front()
		_frames[int(e[1])] = e[2]
		_last_arrival = now
	while not _out_q.is_empty() and int(_out_q[0][0]) <= now:
		net.send_command(_out_q.pop_front()[1])
	var avail := 0
	while _frames.has(frame + avail):
		avail += 1
	if avail == 0:
		# nothing in hand: a stall only when the server's frame is actually late (network jitter, a slow connection),
		# not in the ordinary gap before the next frame is due
		if now - _last_arrival > LATE_MS:
			_stalls.append(now)
			_last_stall = now
		if _starved_since == 0:
			_starved_since = now
		status = "Waiting for the server" if now - _starved_since > 600 else ""
		_adjust_buffer(now)
		return
	_starved_since = 0
	# keep `target_buffer` frames in hand (they absorb jitter); step more when far behind
	if avail <= target_buffer:
		_adjust_buffer(now)
		return
	var n := 1
	if avail > target_buffer + 1:
		n = mini(avail - target_buffer, MAX_CATCH_UP)
	status = "Catching up" if avail > 15 else ""
	for i in n:
		var cmds: Array = _frames[frame]
		_frames.erase(frame)
		_run(frame, cmds)
	_adjust_buffer(now)

func _run(f: int, cmds: Array) -> void:
	_apply(cmds)
	step_world.call()
	frames_stepped += 1
	if f % HASH_EVERY == 0:
		net.send_hash(f, world.state_hash())
	frame = f + 1

func receive_frame(f: int, cmds: Array) -> void:
	if f < frame:
		return
	if sim_lag_ms > 0:
		_in_last = maxi(_in_last, Time.get_ticks_msec() + sim_lag_ms / 2 + _lag_rng.randi_range(0, sim_jitter_ms))
		_in_q.append([_in_last, f, cmds])
		return
	_frames[f] = cmds
	_last_arrival = Time.get_ticks_msec()

## More buffer after repeated stalls (three in three seconds), less after eight quiet seconds.
func _adjust_buffer(now: int) -> void:
	while not _stalls.is_empty() and now - int(_stalls[0]) > 3000:
		_stalls.pop_front()
	if _stalls.size() >= 3 and target_buffer < 4:
		target_buffer += 1
		_stalls.clear()
	elif target_buffer > 0 and now - _last_stall > 8000:
		target_buffer -= 1
		_last_stall = now

# ---- Snapshots ------------------------------------------------------------------------------------------------------

## The world after frame f from another player (a repair, a late join, a return): carry on from it. The server sends
## the frames after f again right behind it.
func receive_snapshot(f: int, bytes: PackedByteArray) -> void:
	var w2 := SimSnapshot.restore(bytes, world.map)
	if w2 == null:
		push_error("NET snapshot could not be read")
		return
	world = w2
	for k in _frames.keys():
		if int(k) <= f:
			_frames.erase(k)
	_in_q = _in_q.filter(func(e): return int(e[1]) > f)
	frame = f + 1
	resyncs += 1
	running = true
	# every system command up to f is in the snapshot's world already: re-derive which heroes bots play
	bot_slots.clear()
	for s in slot_heroes:
		for b in w2.bots:
			if b.hero_id == int(slot_heroes[s]) and slot_peer.has(s):
				bot_slots[s] = true
	if on_world_replaced.is_valid():
		on_world_replaced.call(w2)

# ---- The server is gone ----------------------------------------------------------------------------------------------

## Every other human hero gets a bot and this machine plays on alone.
func host_lost() -> void:
	running = false
	for s in slot_heroes:
		if int(s) != my_slot and not bot_slots.has(s) and slot_peer.has(s):
			_system({"k": "sys_bot", "slot": int(s), "name": String(slot_name.get(s, "Bot"))})
