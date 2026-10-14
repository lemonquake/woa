extends SceneTree
## Multiplayer over real UDP on this computer, headless, one process per machine. Roles:
##   --role=server                      a dedicated server (no player); quits when its last player leaves
##   --role=host                        a server hosted by a player who plays on it and leads the lobby
##   --role=client [--lead]             a player connecting to --addr (127.0.0.1); --lead makes the lobby and starts
## Players play a 5 v 5 (bots in the other slots) for --min game minutes at --speed times real time, each issuing
## random commands (moves, attacks, spells, buying, learning, chat). Each prints its world's fingerprint at the last
## frame (`HASH@<frame> <value>`): every player must print the same one.
##   --corrupt=<frame>   this player's world drifts on purpose at that frame (a creep moves): it must be repaired
##   --drop=<frame>      this player disconnects at that frame and connects again 3 s later (a bot plays meanwhile)
##   --lag=<ms> [--jitter=<ms>]  simulated distance for this player's packets
## Example (three shells): server; client --lead --name=A; client --name=B --corrupt=900 --drop=1800
const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var opts := {"role": "client", "min": "4", "speed": "4", "port": "27860", "corrupt": "-1", "drop": "-1", "name": "",
	"addr": "127.0.0.1", "lag": "0", "jitter": "0"}
var net: NetSession
var world: SimWorld
var m: NetMatch
var rng := RandomNumberGenerator.new()
var me_hero := -1
var _next_cmd := 0
var _done := false
var _t0 := 0
var _corrupted := false
var _dropped := false
var _reconnect_at := 0
var _lat: PackedFloat32Array = PackedFloat32Array()
var _driver: Node
var _goal := 0
var _hash_at_goal := 0
var _hash_said := false
var _started := false
var _lobby_made := false
var _ready_sent := false
var _seen_match := false
var _resyncs := 0
var _replaced := 0

class Driver extends Node:
	var t
	func _physics_process(_dt: float) -> void:
		t.physics()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if opts.name == "":
		opts.name = String(opts.role).capitalize()
	rng.seed = hash(opts.name)
	Engine.physics_ticks_per_second = int(30 * float(opts.speed))
	Engine.max_physics_steps_per_frame = 16
	_goal = int(float(opts.min) * 60.0 * 30.0)
	_driver = Driver.new()
	_driver.t = self
	root.add_child.call_deferred(_driver)
	_t0 = Time.get_ticks_msec()

func _say(s: String) -> void:
	print("%s %s" % [String(opts.name).to_upper(), s])

var _opened := false

func physics() -> void:
	if not _opened:
		_opened = true
		net = root.get_node("Net") as NetSession
		net.headless_test = true
		net.match_starting.connect(_on_start)
		net.notice.connect(func(t): _say("notice: " + t))
		net.left.connect(func(r): _say("left: " + r))
		var port := int(opts.port)
		match String(opts.role):
			"server":
				var e := net.host_server({"name": "Test server", "port": port, "dedicated": true})
				_say("listening: " + (e if e != "" else "ok"))
			"host":
				var e2 := net.host_server({"name": "Host's server", "port": port}, opts.name)
				_say("hosting: " + (e2 if e2 != "" else "ok"))
			_:
				var e3 := net.connect_to(String(opts.addr), opts.name, "", port)
				_say("connecting: " + (e3 if e3 != "" else "ok"))
		return
	if opts.role == "server":
		if net.server != null and net.server.players.is_empty() and _seen_match:
			_say("all players left: done")
			quit(0)
		if net.server != null and not net.server.rooms.is_empty():
			_seen_match = true
		_timeout_check()
		return
	if _reconnect_at > 0 and Time.get_ticks_msec() >= _reconnect_at:
		_reconnect_at = 0
		var e4 := net.connect_to(String(opts.addr), opts.name, "", int(opts.port))
		_say("reconnecting: " + (e4 if e4 != "" else "ok"))
	_lobby()
	if m != null and not _done:
		m.physics_tick()
		_random_commands()
		if not _corrupted and int(opts.corrupt) >= 0 and m.frame >= int(opts.corrupt):
			_corrupted = true
			for u in m.world.units:
				if u.alive and u.is_lane_creep():
					u.pos += Vector2(37, 11)
					_say("corrupted its world at frame %d" % m.frame)
					break
		if not _dropped and int(opts.drop) >= 0 and m.frame >= int(opts.drop):
			_dropped = true
			_say("dropping at frame %d" % m.frame)
			m = null
			net.leave_server("")
			_reconnect_at = Time.get_ticks_msec() + 3000
			return
		if _hash_said and m.frame >= _goal:
			_finish()
	_timeout_check()

func _timeout_check() -> void:
	if Time.get_ticks_msec() - _t0 > 1000 * 60 * 20:
		_say("TIMEOUT")
		quit(2)

## The lobby: the leader makes it, waits for a second player, fills bots, starts; the other picks a hero and readies.
func _lobby() -> void:
	if _started or net.state == NetSession.State.OFF or net.state == NetSession.State.CONNECTING:
		return
	var lead: bool = opts.role == "host" or opts.has("lead")
	if net.state == NetSession.State.HUB:
		if lead and not _lobby_made:
			_lobby_made = true
			net.create_room("Test lobby", "", "5v5")
		elif not lead and not net.hub.get("rooms", []).is_empty() and not _lobby_made:
			_lobby_made = true
			net.quick_join()
		return
	if net.state != NetSession.State.ROOM or net.room.is_empty():
		return
	var slots: Array = net.room.slots
	if not lead:
		if not _ready_sent:
			_ready_sent = true
			net.set_mine("hero", "azrin")
			net.set_mine("ready", true)
		return
	var humans := slots.filter(func(s): return String(s.kind) == "human").size()
	if humans < 2:
		return
	if not _ready_sent:
		_ready_sent = true
		net.set_mine("hero", "sludge")
		net.set_mine("ready", true)
		net.fill_bots()
		return
	var heroes := ["ezee", "blood_ranger", "froster", "caziel", "ezee", "sludge", "blood_ranger", "azrin"]
	var k := 0
	var all_set := true
	for i in slots.size():
		if String(slots[i].kind) == "bot":
			if String(slots[i].hero) != heroes[k % heroes.size()]:
				net.leader_slot(i, "hero", heroes[k % heroes.size()])
				all_set = false
			k += 1
		elif String(slots[i].kind) == "open":
			all_set = false
	if not all_set or NetSession.start_problem(slots) != "":
		return
	_started = true
	net.start_match()
	_say("start sent")

func _on_start() -> void:
	_started = true
	var map := SimMap.new()
	map.build(1)
	world = SimWorld.new(int(net.config.seed), map)
	world.setup_match()
	var r := NetMatch.spawn_heroes(world, net.config, int(net.config.me), func(_s): return {})
	me_hero = int(r.mine)
	m = net.match_loaded(world, r.slot_heroes)
	m.sim_lag_ms = int(opts.lag)
	m.sim_jitter_ms = int(opts.jitter)
	m.step_world = func():
		m.world.step()
		m.world.events.clear()
		if m.frame == _goal - 1:
			_hash_at_goal = m.world.state_hash()
			_hash_said = true
			print("%s HASH@%d %d" % [String(opts.name).to_upper(), _goal, _hash_at_goal])
	m.on_world_replaced = func(w2):
		world = w2
		_replaced += 1
		_say("world replaced by a snapshot at frame %d" % m.frame)
	_say("match loaded: %d heroes, me %d" % [world.heroes.size(), me_hero])

func _random_commands() -> void:
	if not m.running or m.frame < _next_cmd:
		return
	_next_cmd = m.frame + rng.randi_range(8, 40)
	var w := m.world
	var h := w.get_unit(me_hero)
	if h == null:
		return
	var p := Vector2(rng.randf_range(-6000, 6000), rng.randf_range(-6000, 6000))
	var c := {}
	match rng.randi_range(0, 7):
		0, 1, 2:
			c = {"k": "order", "u": me_hero, "o": {"type": O.MOVE, "point": p, "queue": rng.randf() < 0.2}}
		3:
			c = {"k": "order", "u": me_hero, "o": {"type": O.ATTACK_MOVE, "point": p}}
		4:
			if not h.abilities.is_empty():
				var aid: String = h.abilities[rng.randi_range(0, h.abilities.size() - 1)]
				c = {"k": "learn", "ability": aid} if h.ability_points > 0 else \
					{"k": "order", "u": me_hero, "o": {"type": O.CAST_POINT, "ability": aid, "point": h.pos + Vector2(300, 200)}}
		5:
			c = {"k": "buy", "item": ["branch", "tango", "boots", "circlet", "salve"][rng.randi_range(0, 4)]}
		6:
			c = {"k": "courier", "cmd": "deliver"}
		7:
			c = {"k": "chat", "text": "hello %d" % m.frame}
	if not c.is_empty():
		m.send_command(c)
		if m.latency_ms > 0.0:
			_lat.append(m.latency_ms)

func _finish() -> void:
	_done = true
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	_say("DONE frame %d in %.1f s, repairs %d, buffer %d, game time %s" % [m.frame, secs, _replaced, m.target_buffer,
		m.world.clock_text()])
	var a := Array(_lat)
	a.sort()
	if not a.is_empty():
		_say("command latency mean %.1f ms p95 %.1f ms over %d samples (speed x%s)" % [
			a.reduce(func(x, y): return x + y, 0.0) / a.size(), a[int(a.size() * 0.95)], a.size(), opts.speed])
	# give the others a moment to reach the last frame, then leave
	await create_timer(6.0).timeout
	net.leave_server("")
	await create_timer(0.5).timeout
	quit(0)
