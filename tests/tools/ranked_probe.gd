extends SceneTree
## Live check of the Ranked screen through real clicks (run 2026-10-19 b), then a ranked match end to end:
##   godot --path . -s tests/tools/ranked_probe.gd -- [--out=work/shots/ranked] [--4k] [--keep]
## Uses its own ladder file (user://ranked_probe_live.json, made fresh unless --keep), never yours. Prints PASS / FAIL
## per check and saves captures along the way.

var out := "work/shots/ranked"
var big := false
var fails := 0
var passes := 0
var menu: Control

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _init() -> void:
	var keep := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--4k":
			big = true
		elif a == "--keep":
			keep = true
	OS.set_environment("WOA_RANKED_FILE", "user://ranked_probe_live.json")
	if not keep and FileAccess.file_exists("user://ranked_probe_live.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ranked_probe_live.json"))
	if big:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(3840, 2160))
	else:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	_run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await process_frame
	var dir := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + "/" + name + ("_4k" if big else "") + ".png")
	print("saved ", name)

func wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += 1.0 / 60.0

# ---- Real input -------------------------------------------------------------------------------------------------------

func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p

func move_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _to_window(p)
	ev.global_position = ev.position
	root.push_input(ev)

func button_at(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _to_window(p)
	ev.global_position = ev.position
	root.push_input(ev)

func click_at(p: Vector2) -> void:
	move_to(p)
	await process_frame
	button_at(p, true)
	await process_frame
	button_at(p, false)
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

## Every node of an inner class of ranked_menu.gd (RoleCard, BoardRow ...) by a test on it.
static func find_where(n: Node, test: Callable, out_list: Array) -> Array:
	if test.call(n):
		out_list.append(n)
	for c in n.get_children():
		find_where(c, test, out_list)
	return out_list

func button_named(text: String) -> Control:
	# buttons of the current scene and the root's overlays only (a hidden dialog's own buttons look visible)
	var found := find_where(root, func(n): return (n is Button and (n as Button).text == text and (n as Button).is_visible_in_tree()
		and not _in_window(n)), [])
	if found.is_empty():
		print("  (no visible button named %s)" % text)
	return found[0] if not found.is_empty() else null

func _in_window(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is Window:
			return true
		p = p.get_parent()
	return false

# ---- The run ----------------------------------------------------------------------------------------------------------

func _run() -> void:
	change_scene_to_file("res://src/ui/ranked_menu.tscn")
	await wait(1.5)
	menu = current_scene
	if "--only_profile" in OS.get_cmdline_user_args():
		await _profile_checks()
		print("
ranked probe: %d passed, %d failed" % [passes, fails])
		quit()
		return
	check(menu != null and menu.has_method("_find"), "the Ranked screen opens")
	check(Ranked.bots().size() >= 100, "a ladder of %d bots" % Ranked.bots().size())
	await shot("probe_play")
	# roles: untick Carry, Mid, Off Lane, Soft Support -> only Hard Support
	var cards: Array = find_where(menu, func(n): return n.get("role") != null and n.get("desc") != null, [])
	check(cards.size() == 5, "five role cards")
	for i in 4:
		await click(cards[i])
	await wait(0.2)
	check(menu._chosen_roles() == [5], "role clicks: only Hard Support ticked (%s)" % str(menu._chosen_roles()))
	check(Ranked.me().roles == [5], "your roles are saved")
	await click(cards[0])
	await click(cards[1])
	# Find Match, then Cancel
	await click(menu._find_btn)
	await wait(0.5)
	check(menu.mm.state == "searching", "Find Match starts the search")
	await shot("probe_search")
	var cancel := button_named("Cancel")
	await click(cancel)
	await wait(0.2)
	check(menu.mm.state == "idle", "Cancel stops it")
	# Find again: the offer
	await click(menu._find_btn)
	var t := 0.0
	while menu.mm.state == "searching" and t < 40.0:
		await wait(0.25)
		t += 0.25
	check(menu.mm.state == "found" and menu._offer.visible, "a match is found and offered after %.1f s" % t)
	var my_role := int(menu.mm.lineup.my_role)
	check(my_role in [1, 2, 5], "your role is one you ticked (%d)" % my_role)
	var mcards: Array = find_where(menu._offer, func(n): return n.get("role") != null and n.get("right") != null, [])
	check(mcards.size() == 10, "ten players shown on the offer")
	if mcards.size() > 6:
		move_to((mcards[6] as Control).get_global_rect().get_center())
		await wait(0.3)
		check(menu._card.visible and String(menu._card.p.get("id", "")) == String(mcards[6].p.id), "hovering a player shows their stats")
		await shot("probe_offer_hover")
		move_to(Vector2(960, 1060))
		await wait(0.1)
	var first := {}
	for side in 2:
		for p in menu.mm.lineup.teams[side]:
			first[String(p.id)] = true
	await click(button_named("Decline"))
	await wait(0.3)
	check(menu.mm.state == "searching" and not menu._offer.visible, "Decline searches again")
	t = 0.0
	while menu.mm.state == "searching" and t < 40.0:
		await wait(0.25)
		t += 0.25
	var again := 0
	for side in 2:
		for p in menu.mm.lineup.teams[side]:
			if first.has(String(p.id)) and String(p.id) != "me":
				again += 1
	check(menu.mm.state == "found" and again == 0, "the next offer has none of the declined nine (%d)" % again)
	menu.mm.lineup.fails = {}                         # every bot accepts this time (a fail would re-queue)
	await click(menu._accept_btn)
	await wait(0.2)
	check(menu.mm.you_accepted, "Accept accepts")
	var lineup: Dictionary = menu.mm.lineup.duplicate(true)
	my_role = int(lineup.my_role)                     # the offer accepted (the declined one had its own)
	t = 0.0
	while menu.mm.state == "found" and t < 20.0:
		await wait(0.25)
		t += 0.25
	check(menu.mm.state == "ready", "everyone accepted")
	await shot("probe_ready")
	# the hero pick: wait for your numbered turn, click a hero, Lock in
	t = 0.0
	while not (current_scene != null and current_scene.get("draft") != null) and t < 20.0:
		await wait(0.25)
		t += 0.25
	var dr: Node = current_scene
	check(dr != null and dr.get("draft") != null, "the hero pick opens after everyone accepts")
	await wait(2.5)
	await shot("probe_pick")
	t = 0.0
	while dr.draft.current() != "me" and not dr.draft.done() and t < 80.0:
		await wait(0.25)
		t += 0.25
	check(dr.draft.current() == "me", "your turn comes (pick %d)" % dr.draft.number_of("me"))
	var free_tiles: Array = (dr._tiles.values() as Array).filter(func(x): return not dr.draft.taken(String(x.hero)))
	if not free_tiles.is_empty():
		await click(free_tiles[0])
		await wait(0.3)
		await shot("probe_pick_mine")
		await click(dr._lock)
		await wait(0.3)
	check(dr.draft.picks.has("me") and String(dr.draft.picks.me) == String(free_tiles[0].hero), "a click on a hero and Lock in picks it")
	t = 0.0
	while String(dr.phase) != "versus" and t < 60.0:
		await wait(0.25)
		t += 0.25
	check(String(dr.phase) == "versus", "after the last pick: the versus")
	check(dr._vs_layer.stage.heroes.size() == 10, "all ten heroes stand on the field (%d)" % dr._vs_layer.stage.heroes.size())
	await wait(3.2)
	await shot("probe_versus")
	lineup["heroes"] = dr.draft.picks.duplicate()
	# the match loads with the matched players
	t = 0.0
	while not (current_scene != null and current_scene.has_method("act")) and t < 60.0:
		await wait(0.5)
		t += 0.5
	check(current_scene != null and current_scene.has_method("act"), "the match starts")
	check(String(current_scene.world.get_unit(current_scene.player_hero_id).def.id) == String(lineup.heroes.me), "you play the hero you picked")
	check(Ranked.has_pending(), "the match is remembered (leaving counts as a loss)")
	await wait(4.0)
	var game: Node = current_scene
	var w: SimWorld = game.world
	check(bool(game.ranked_match), "the match is a ranked one")
	check(w.heroes.size() == 10, "ten heroes")
	var names := {}
	for h in w.heroes:
		names[String(h.look.get("display_name", h.name)) if h.bot else "me"] = String(h.def.id)
	var ok_names := 0
	var ok_heroes := 0
	for side in 2:
		for p in lineup.teams[side]:
			var key := "me" if String(p.id) == "me" else String(p.name)
			if names.has(key):
				ok_names += 1
				if names[key] == String(lineup.heroes[String(p.id)]):
					ok_heroes += 1
	check(ok_names == 10 and ok_heroes == 10, "the matched players and heroes are in the game (%d, %d)" % [ok_names, ok_heroes])
	var rated := w.bots.filter(func(b): return b.rating >= 0.0).size()
	check(rated == 9, "the nine bots play at their own skill (%d)" % rated)
	var me_h: SimUnit = w.get_unit(game.player_hero_id)
	check(me_h != null and String(me_h.player_name) == String(Ranked.me().name), "your name is on your hero")
	var br: SimTeamAI = w.brain(game.player_team)
	await wait(3.0)
	check(int(br.roles.get(me_h.id, 0)) == my_role, "your role is kept by the team (role %d, matched %d)" % [int(br.roles.get(me_h.id, 0)), my_role])
	await shot("probe_match")
	# win it: the end screen with the MMR
	var mmr0 := int(Ranked.me().mmr)
	w.winner = game.player_team
	await wait(4.5)
	check(not Ranked.has_pending(), "the result is in")
	check(int(Ranked.me().mmr) > mmr0 and int(Ranked.me().wins) == 1, "a win raised your MMR (%d -> %d)" % [mmr0, int(Ranked.me().mmr)])
	check(Ranked.hero_xp(Ranked.me(), String(lineup.heroes.me)) >= 100, "and gave your hero XP (%d)" % Ranked.hero_xp(Ranked.me(), String(lineup.heroes.me)))
	await shot("probe_end")
	var fm := button_named("Find Match")
	check(fm != null, "the end screen offers Find Match")
	await click(fm)
	await wait(2.0)
	menu = current_scene
	check(menu != null and menu.has_method("_find"), "Find Match goes back to the Ranked screen")
	await _profile_checks()
	# leaderboard: a row opens that player's profile
	await click(menu._tab_btns["leaderboard"])
	await wait(0.5)
	var rows: Array = find_where(menu._board_list, func(n): return n.get("pinned") != null, [])
	check(rows.size() >= 100, "the leaderboard lists everyone (%d)" % rows.size())
	await shot("probe_board")
	if rows.size() > 3:
		var who := String(rows[3].p.id)
		await click(rows[3])
		await wait(0.5)
		check(menu._tab == "profile" and menu._profile_id == who, "a row opens that player's profile")
		await shot("probe_bot_profile")
	await click(menu._tab_btns["guilds"])
	await wait(0.3)
	check(menu._pages["guilds"].visible and button_named("Coming soon") != null and button_named("Coming soon").disabled, "Guilds: coming soon")
	await shot("probe_guilds")
	# leaving a ranked match counts as a loss: start one and quit from the pause menu
	await click(menu._tab_btns["play"])
	await click(menu._find_btn)
	t = 0.0
	while menu.mm.state == "searching" and t < 40.0:
		await wait(0.25)
		t += 0.25
	check(menu.mm.state == "found", "a second match is found (%s)" % menu.mm.state)
	menu.mm.lineup.fails = {}
	await click(menu._accept_btn)
	t = 0.0
	while not (current_scene != null and current_scene.has_method("act")) and t < 150.0:
		await wait(0.5)
		t += 0.5
	await wait(4.0)
	var l0 := int(Ranked.me().losses)
	game = current_scene
	if not game.has_method("act"):
		check(false, "the second match starts")
		print("
ranked probe: %d passed, %d failed" % [passes, fails])
		quit(1)
		return
	game.menus.toggle()
	await wait(0.3)
	await click(button_named("Leave match"))
	await wait(2.0)
	check(int(Ranked.me().losses) == l0 + 1 and int(Ranked.me().abandons) == 1, "Leave match is a loss")
	check(current_scene != null and current_scene.has_method("_find"), "and goes back to the Ranked screen")
	print("\nranked probe: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _profile_checks() -> void:
	# profile: name, picture choice, emblem turns
	await click(menu._tab_btns["profile"])
	await wait(0.5)
	check(menu._pages["profile"].visible, "Profile tab")
	var edits: Array = find_where(menu, func(n): return n is LineEdit and n.is_visible_in_tree(), [])
	if not edits.is_empty():
		var le: LineEdit = edits[0]
		await click(le)
		await key(KEY_A, true)
		await key(KEY_BACKSPACE)
		await type_text("Probe Name")
		await click(button_named("Save"))
		await wait(0.3)
	check(String(Ranked.me().name) == "Probe Name", "the name is saved (%s)" % Ranked.me().name)
	await click(button_named("Use hero"))
	await wait(0.3)
	check(String(Ranked.me().avatar.get("k", "")) == "hero", "Use hero sets your picture")
	var views: Array = find_where(menu, func(n): return n is EmblemView and n.is_visible_in_tree(), [])
	check(not views.is_empty(), "the 3D emblem is on the profile")
	if not views.is_empty():
		var ev: EmblemView = views[0]
		var c := ev.get_global_rect().get_center()
		var y0: float = ev._em.rotation.y
		move_to(c)
		await process_frame
		button_at(c, true)
		for i in 12:
			var mv := InputEventMouseMotion.new()
			mv.position = _to_window(c + Vector2(i * 14, 0))
			mv.global_position = mv.position
			mv.relative = Vector2(14, 0) * root.get_final_transform().get_scale()
			mv.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(mv)
			await process_frame
		button_at(c + Vector2(168, 0), false)
		await process_frame
		check(absf(ev._em.rotation.y - y0) > 0.5, "dragging turns the emblem (%.2f -> %.2f)" % [y0, ev._em.rotation.y])
	await shot("probe_profile")
