extends SceneTree
## Live probe of talking with the bots (run 2026-10-19 d): a 5 v 5 match in a window; the lane calls come in players'
## words, and lines typed into the real chat box (team chat, then all chat with Shift + Enter) get answers in the HUD:
## a greeting, "what rank", "where is <enemy>", an insult, "are you a bot". Prints PASS / FAIL and the lines.
##   godot --path . -s tests/tools/talk_probe.gd -- --bots=5v5 --nolearn [--out=dir]

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
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_texture().get_image().save_png(_out.path_join(name))

## Type `text` into the chat box (all: Shift + Enter), wait `sec` seconds of play, return the bot lines that came.
func _say(text: String, all := false, sec := 5.0) -> Array:
	var chat: ChatPanel = game.hud.chat
	chat.open(all)
	await frames(2)
	chat.input.text = text
	chat.input.text_submitted.emit(text)
	var before := chat.lines.size()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await physics_frame
	var got: Array = chat.lines.slice(before).filter(func(l): return not bool(l.me))
	print("  you%s: %s" % [" (all)" if all else "", text])
	for l in got:
		print("    %s: %s" % [l.name, l.text])
	return got

## The old robotic lane calls ("I'll farm the bottom lane (safe lane).").
func _formal(l: Dictionary) -> bool:
	var t := String(l.text)
	return t.begins_with("I'll farm the") or t.begins_with("I'll support") or (t.begins_with("I'll go") and t.ends_with("."))

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.input != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("FAIL boot timeout")
			quit(1)
			return
	var w: SimWorld = game.world
	var me: SimUnit = w.get_unit(game.player_hero_id)
	await frames(60)
	var chat: ChatPanel = game.hud.chat
	var formal: Array = chat.lines.filter(_formal)
	print("lane calls:")
	for l in chat.lines.slice(0, 6):
		print("    %s: %s" % [l.name, l.text])
	check(chat.lines.size() >= 3 and formal.is_empty(), "the lane calls come in players' words (%d lines, %d formal)" % [chat.lines.size(), formal.size()])
	var mate: SimUnit = null
	var foe: SimUnit = null
	for h in w.heroes:
		if h.team == me.team and h != me and mate == null:
			mate = h
		if h.team != me.team and foe == null:
			foe = h
	var got := await _say("hi guys glhf")
	check(not got.is_empty(), "a greeting gets an answer")
	got = await _say("%s what rank are u" % SimTeamAI.hero_label(mate).to_lower())
	check(got.any(func(l): return String(l.hero) == SimTeamAI.hero_label(mate)), "the teammate asked by its hero answers")
	got = await _say("where is %s" % SimTeamAI.hero_label(foe).to_lower())
	check(not got.is_empty(), "asked where an enemy is, a teammate answers")
	me.deaths = 6
	got = await _say("noob team")
	check(not got.is_empty(), "an insult gets an answer")
	got = await _say("are you a bot lol", true)
	check(got.any(func(l): return String(l.name).begins_with("(All)")), "all chat gets an all chat answer")
	chat.open(false)
	await _shot("talk_chat_open.png")
	chat.close()
	print("talk probe: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
