extends SceneTree
## Run 2026-10-15 b checks in a real match window (PASS / FAIL lines, captures):
##   godot --path . -s tests/tools/hud15_probe.gd -- --out=work/lemondev/2026-10-15b-ui-items-heroes/shots [--4k]
##     [--hero=sludge]
## * Debug panel (F9): fully on screen, every control inside the screen or reachable by its scroll bar.
## * Auto-select: with an enemy creep selected, a right click on the ground selects the hero and moves it; the same
##   for the Stop key and an ability key.
## * Unit panel: a lane creep, a neutral with spells and an aura, a tower and the Throne are shown in the bottom
##   panel with their skills (captures).
## * Skill bar: the hero given 6 and 10 skills; the console widens, every slot sits inside the panel and the panel
##   inside the screen; each slot's hotkey matches Keybinds.slot_action (captures).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var out := "work/lemondev/2026-10-15b-ui-items-heroes/shots"
var tag := ""
var fails := 0
var passes := 0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--4k":
			tag = "_4k"
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://" + out + "/" + name + tag + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path, " ", img.get_size())

func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)

func _right_click(at: Vector2) -> void:
	var vp := root.get_viewport()
	# the canvas is stretched: convert canvas coordinates to window pixels for the event
	var xf := vp.get_final_transform()
	var win := xf * at
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.position = win
	e.global_position = win
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(1)
			return
	await frames(30)
	if tag == "_4k":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		await frames(20)
	var w: SimWorld = game.world
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	var vs: Vector2 = root.get_viewport().get_visible_rect().size

	# ---- Debug panel ----
	var dbg: DebugPanel = game.hud.debug
	dbg.toggle()
	await frames(6)
	var pr := dbg.panel.get_global_rect()
	check(pr.position.x >= 0.0 and pr.end.x <= vs.x + 0.5 and pr.position.y >= 0.0 and pr.end.y <= vs.y - 200.0,
		"debug panel inside the screen and above the bottom panel: %s in %s" % [pr, vs])
	var outside := 0
	var total := 0
	for c in _all(dbg.panel):
		if c is BaseButton and c.is_visible_in_tree():
			total += 1
			var r: Rect2 = c.get_global_rect()
			if r.end.x > vs.x + 0.5 or r.position.x < -0.5 or r.size.x < 40.0:
				outside += 1
				print("  cut: ", c.get("text"), " ", r)
	check(total >= 20 and outside == 0, "every debug control is inside the screen horizontally (%d controls, %d cut)" % [total, outside])
	var sc := dbg._scroll
	var content_h := dbg._box.get_combined_minimum_size().y
	check(content_h <= sc.size.y + 1.0 or sc.get_v_scroll_bar().visible,
		"the rest of the debug panel scrolls (content %d, view %d)" % [int(content_h), int(sc.size.y)])
	await shot("debug_panel")
	dbg.toggle()
	await frames(4)

	# ---- Auto-select ----
	var creep: SimUnit = null
	w.time = 120.0
	for i in 200:
		await frames(1)
		w.step()
	for u in w.units:
		if u.alive and u.is_lane_creep() and u.team != h.team:
			creep = u
			break
	if creep != null:
		game.input.select([creep.id])
		await frames(2)
		var ground: Vector2 = h.pos + Vector2(300, 200)
		var screen: Vector2 = game.camera.cam.unproject_position(View.to3(ground, game.terrain.height_at(ground)))
		game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
		await frames(4)
		screen = game.camera.cam.unproject_position(View.to3(ground, game.terrain.height_at(ground)))
		await _right_click(screen)
		await frames(2)
		check(game.selected == [h.id], "right click with an enemy creep selected selects the hero (%s)" % str(game.selected))
		check(h.order == O.MOVE or h.moving, "and the hero takes the move order (order %d)" % h.order)
		game.input.select([creep.id])
		await frames(2)
		await _key(Keybinds.key("stop") as Key)
		check(game.selected == [h.id], "Stop with a creep selected selects the hero")
		game.input.select([])
		await frames(2)
		await _key(Keybinds.key("hold") as Key)
		check(game.selected == [h.id], "Hold with nothing selected selects the hero")

	# ---- Unit panel ----
	var picks := {"creep": func(u: SimUnit): return u.is_lane_creep(),
		"neutral": func(u: SimUnit): return u.kind == C.Kind.NEUTRAL_CREEP and not (u.def.get("auras", []) as Array).is_empty(),
		"tower": func(u: SimUnit): return u.kind == C.Kind.TOWER,
		"throne": func(u: SimUnit): return u.kind == C.Kind.ANCIENT}
	SimDebug.force_neutrals(w)
	for i in 4:
		w.step()
	for nm in picks:
		var found: SimUnit = null
		for u in w.units:
			if u.alive and picks[nm].call(u):
				found = u
				break
		if found == null:
			check(false, "found a %s to select" % nm)
			continue
		game.input.select([found.id])
		game.camera.focus(View.to3(found.pos, game.terrain.height_at(found.pos)))
		await frames(8)
		var bp: Control = game.hud.bottom
		var n_sk: int = game.hud.unit_skills(found).size()
		check(game.hud.shown() == found, "%s (%s) shows in the bottom panel with %d skills" % [nm, found.name, n_sk])
		await shot("unit_" + nm)

	# ---- Skill bar with 6 and 10 skills ----
	game.input.select([h.id])
	var orig: Array = h.abilities.duplicate()
	var pool := ["shuriken_hook", "stench", "blubber", "fiery_javelin", "touch_of_ember", "breath_of_cold", "ice_pulse",
		"swift_dagger", "master_of_shadows", "chomp"]
	for n in [6, 10]:
		h.abilities = pool.slice(0, n - 1)
		h.abilities.append("chomp")
		for aid in h.abilities:
			h.ability_level[aid] = 1
		h.ability_points = 3
		game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
		await frames(8)
		var bp2 = game.hud.bottom
		var r: Rect2 = bp2.get_global_rect()
		check(bp2.n_slots == n and r.position.x >= 0.0 and r.end.x <= vs.x + 0.5,
			"%d skills: %d slots, panel %s inside %s" % [n, bp2.n_slots, r, vs])
		var inside := true
		for i in n:
			var sr: Rect2 = bp2._abil_rects[i]
			if sr.position.x < 0.0 or sr.end.x > bp2.size.x or sr.end.x > bp2.item_x - 4.0:
				inside = false
		check(inside, "%d skills: every slot sits in the ability section" % n)
		var keys := []
		for i in n:
			keys.append(Keybinds.key_name(Keybinds.slot_action(i, n)))
		check(Keybinds.ability_slot("ability_4", n) == n - 1 and keys[n - 1] == Keybinds.key_name("ability_4"),
			"%d skills: keys %s, the ultimate on %s" % [n, " ".join(keys), keys[n - 1]])
		await shot("skills_%d" % n)
	h.abilities = orig
	print("RESULT %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)

func _all(n: Node) -> Array:
	var outv: Array = []
	for c in n.get_children():
		outv.append(c)
		outv.append_array(_all(c))
	return outv
