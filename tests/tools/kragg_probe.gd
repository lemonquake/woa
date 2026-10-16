extends SceneTree
## Run 2026-10-15 g in a real match window (PASS / FAIL lines, captures):
##   godot --path . -s tests/tools/kragg_probe.gd -- --hero=kragg --out=work/lemondev/2026-10-15g-kragg-bots-menu/shots [--4k]
## * Kragg has four skill slots (Q W E R) and Magnetize in the small innate slot, learned at level 1.
## * Hovering the Talents button shows the innate with its value at his level; so does the innate slot and the open
##   tree's head.
## * Overload bursts on his 3rd attack at level 4 (no script errors from its effect), slows and hurts the enemies
##   round him, and its count shows in his buff bar.

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var out := "work/lemondev/2026-10-15g-kragg-bots-menu/shots"
var tag := ""
var fails := 0
var passes := 0
var real_mouse := true

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
	await frames(3)
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

func mcheck(ok: bool, what: String) -> void:
	if not real_mouse:
		print("SKIP ", what, " (frame larger than the monitor)")
		return
	check(ok, what)

func hover(at: Vector2) -> void:
	var vp := root.get_viewport()
	vp.warp_mouse(at)
	var e := InputEventMouseMotion.new()
	e.position = vp.get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)
	await frames(6)

func _tip_text(hud) -> String:
	var t := ""
	for l in hud._last_tip:
		t += String(l[0]) + " | "
	return t

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
	w.vision.reveal_all = true
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	real_mouse = DisplayServer.screen_get_size().x >= int(root.get_viewport().get_final_transform().x.x * vs.x)
	var hud = game.hud
	var bp = hud.bottom
	check(String(h.def.id) == "kragg", "playing Kragg")
	check(h.ability_level_of("magnetize") == 1, "Magnetize learned at level 1")
	await frames(10)
	check(bp.n_slots == 4, "four skill slots (%d)" % bp.n_slots)
	# level 12, Overload at 4
	SimDebug.level_up(w, h, 11)
	h.ability_level["overload"] = 4
	h.ability_level["iron_grip"] = 2
	h.refresh_stats()
	h.hp = h.max_hp
	await frames(10)
	await hover(bp.global_position + bp.TALENT_C)
	var tt := _tip_text(hud)
	mcheck(tt.contains("Magnetize") and tt.contains("Innate"), "hovering Talents shows the innate (%s)" % tt.left(120))
	mcheck(tt.contains("level 12"), "with its value at his level")
	await shot("kragg_talent_tip")
	await hover(bp.global_position + bp.INNATE.get_center())
	tt = _tip_text(hud)
	mcheck(tt.contains("Magnetize") and tt.contains("Grows with hero level"), "the innate slot's tooltip")
	await shot("kragg_innate_tip")
	await hover(vs * Vector2(0.5, 0.3))
	# Overload in the field: three attacks on an enemy hero beside him, a second enemy next to it
	h.pos += (Vector2.ZERO - h.pos).normalized() * 2600.0
	h.order = SimConst.Order.HOLD
	var e1 := w.spawn("ezee", C.DUSK, h.pos + Vector2(140, 0))
	var e2 := w.spawn("sludge", C.DUSK, h.pos + Vector2(0, 150))
	for e in [e1, e2]:
		e.order = SimConst.Order.HOLD
		e.def = e.def.duplicate()
		e.def["can_attack"] = false
		e.refresh_stats()
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(30)
	var hp2 := e2.hp
	var bursts := 0
	for i in 3:
		w.combat.land_attack(w.combat.attack_snapshot(h, ""), e1)
		for ev in w.events:
			if String(ev.get("t", "")) == "overload":
				bursts += 1
		await frames(2)
	check(bursts >= 1 or e2.hp < hp2, "the 3rd attack bursts in an Overload")
	check(e2.hp < hp2, "the enemy beside him is hurt (%d)" % int(hp2 - e2.hp))
	check(not e2.get_modifier("overload_slow").is_empty(), "and slowed")
	await frames(4)
	await shot("kragg_overload")
	# the count in his buff bar
	game.selected_id = h.id
	w.combat.land_attack(w.combat.attack_snapshot(h, ""), e1)
	await frames(10)
	var en: Array = BuffBar.entries(h, w).filter(func(x): return String(x.id) == "overload")
	# (on Hold he also hits the enemy beside him on his own, so the count is read from his record)
	var n := int(h.stacks.get("overload", 0))
	check(en.size() == 1 and int(en[0].count) == n, "his buff bar counts toward the next Overload (%s of 3, record %d)" % [str(en.map(func(x): return x.count)), n])
	var ch: Array = BuffBar.entries(e1, w).filter(func(x): return String(x.id) == "magnet_charge")
	check(ch.size() == 1 and int(ch[0].count) == 4, "the enemy carries 4 Charges at most")
	await shot("kragg_buffbar")
	print("RESULT %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
