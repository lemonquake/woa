extends SceneTree
## Live probe of a 5 v 5 match with bots on both teams (window, HUD, input): the bots' team chat shows in the HUD,
## a ping on an enemy hero gets answers, holding Alt shows the camps' spawn boxes, a typed chat line reaches the
## bots. Prints PASS / FAIL lines and quits.
##   godot --path . -s tests/tools/team_probe.gd -- [--out=work/shots]

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var _fails := 0
var _passes := 0
var _out := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS ", msg)
	else:
		_fails += 1
		print("FAIL ", msg)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	if _out == "":
		return
	await frames(3)
	root.get_texture().get_image().save_png(_out.path_join(name))

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.input != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("FAIL boot timeout")
			quit(1)
			return
	await frames(20)
	if OS.get_cmdline_user_args().has("--4k"):
		# a real 3840 x 2160 frame: a borderless window larger than the screen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		await frames(20)
		print("window ", DisplayServer.window_get_size(), " viewport ", root.get_viewport().get_texture().get_size())
		_out = _out.path_join("4k")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out)
	var w: SimWorld = game.world
	check(w.heroes.size() == 10, "ten heroes in the match (%d)" % w.heroes.size())
	check(w.bots.size() == 9, "nine bots (%d)" % w.bots.size())
	var me: SimUnit = w.get_unit(game.player_hero_id)
	# the bots announce their lanes before the horn
	await frames(30)
	var chat: ChatPanel = game.hud.chat
	check(chat.lines.size() >= 3, "bot lines in the HUD chat (%d)" % chat.lines.size())
	for l in chat.lines.slice(0, 5):
		print("    chat: %s: %s" % [l.name, l.text])
	await _shot("team_chat.png")
	# skip to 10:20 with everyone in their lanes, an enemy hero caught near our mid tower, and ping it
	w.time = 620.0
	for b in w.bots:
		var bh: SimUnit = b.hero()
		bh.pos = b._waiting_spot(bh)
		w.orders.clear(bh)
	me.pos = Vector2(-1900, -1700)
	w.vision.reveal_all = true
	var foe: SimUnit = null
	for h in w.heroes:
		if h.team != me.team and h.alive:
			foe = h
			break
	foe.pos = Vector2(-900, -700)
	w.orders.clear(foe)
	w.vision.update()
	var before := chat.lines.size()
	game.input.ping(foe.pos, foe.id)
	for i in 60:
		await physics_frame
	check(w.pings.any(func(p): return int(p.target) == foe.id and String(p.kind) == "attack"), "Alt + click on an enemy hero is an attack ping")
	check(chat.lines.size() > before, "the bots answer the ping (%d new lines)" % (chat.lines.size() - before))
	for l in chat.lines.slice(before):
		print("    reply: %s: %s" % [l.name, l.text])
	await _shot("team_ping.png")
	# Alt shows the spawn boxes
	var ev := InputEventKey.new()
	ev.keycode = KEY_ALT
	ev.physical_keycode = KEY_ALT
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(5)
	check(game.camps.boxes_wanted() and game.camps.get_node("SpawnBoxes").visible, "holding Alt shows the spawn boxes")
	game.camera.focus(View.to3(w.map.camps[1].pos, game.terrain.height_at(w.map.camps[1].pos)))
	await _shot("team_boxes.png")
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(5)
	check(not game.camps.get_node("SpawnBoxes").visible, "and letting go hides them")
	# Enter opens the chat; a typed line reaches the team and the bots act on it
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await frames(3)
	check(chat.is_open(), "Enter opens the chat line")
	chat.input.text = "push mid"
	chat.input.text_submitted.emit("push mid")
	for i in 30:
		await physics_frame
	check(not chat.is_open(), "sending closes it")
	check(w.chat_log.any(func(l): return int(l.u) == me.id and String(l.text) == "push mid"), "the line is in the team chat")
	var pushing := w.brain(me.team).plans.any(func(p): return String(p.kind) == "push")
	check(pushing, "the bots took \"push mid\" as a call")
	await _shot("team_typed.png")
	print("team probe: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
