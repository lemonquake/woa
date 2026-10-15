extends SceneTree
## The buff bar (src/ui/buff_bar.gd) in a real match window (PASS / FAIL lines, captures):
##   godot --path . -s tests/tools/buff_probe.gd -- --out=work/lemondev/2026-10-15e-buff-bar/shots [--4k] [--hero=azrin]
## * Your hero with buffs (potion, orb, ally aura) and debuffs from enemies (two Stench clouds, silence, break, enemy
##   aura, Kragg's Charges, two burns): one icon each, buffs left of debuffs, all above the skills, inside the screen,
##   clear of the type chips and the stash, none overlapping.
## * Hover: the icon's tooltip names it; the point counts as HUD (a click there gives no order).
## * Timers: a timed icon's time left drops while its total stays.
## * Many effects wrap upward into rows; an enemy creep's effects show when it is selected.

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var out := "work/lemondev/2026-10-15e-buff-bar/shots"
var tag := ""
var fails := 0
var passes := 0
var real_mouse := true                      # false when the frame is larger than the monitor (hover checks skipped)

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

## A hover check: skipped (not passed) when the OS cursor cannot reach the point.
func mcheck(ok: bool, what: String) -> void:
	if not real_mouse:
		print("SKIP ", what, " (frame larger than the monitor)")
		return
	check(ok, what)

func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)

## Move the mouse to a canvas point (the canvas is stretched: convert to window pixels).
func hover(at: Vector2) -> void:
	var vp := root.get_viewport()
	var win: Vector2 = vp.get_final_transform() * at
	vp.warp_mouse(at)
	var e := InputEventMouseMotion.new()
	e.position = win
	e.global_position = win
	Input.parse_input_event(e)
	await frames(8)

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
	var bp = game.hud.bottom
	# two enemy heroes far away supply the debuffs (their names show in the tooltips)
	var e1 := w.spawn_hero("sludge", 1 - h.team)
	var e2 := w.spawn_hero("kragg", 1 - h.team)
	e1.pos = Vector2(6000, 6000)
	e2.pos = Vector2(6200, 6000)
	var ally := w.spawn_hero("froster", h.team)
	ally.pos = h.pos + Vector2(200, 0)
	_load(w, h, e1, e2)
	game.input.select([h.id])
	await frames(10)
	var ents: Array = BuffBar.entries(h, w)
	var rects: Array = bp._buff_rects.duplicate()
	print("entries: ", ents.map(func(e): return "%s%s" % [e.id, "(-)" if e.debuff else "(+)"]))
	check(rects.size() == ents.size() and ents.size() >= 10, "one icon per effect (%d icons, %d effects)" % [rects.size(), ents.size()])
	_layout_checks(bp, rects, vs, "hero")
	var nb: int = ents.filter(func(e): return not e.debuff).size()
	var row_y: float = (rects[0] as Rect2).position.y if not rects.is_empty() else 0.0
	var bx := -INF
	var dx := INF
	for i in rects.size():
		var r: Rect2 = rects[i]
		if not is_equal_approx(r.position.y, row_y):
			continue
		if i < nb:
			bx = maxf(bx, r.end.x)
		else:
			dx = minf(dx, r.position.x)
	check(bx < dx, "on the bottom row the buffs sit left of the debuffs")
	await shot("buffs_hero")
	# hover the first debuff (not in a 4K frame on a smaller monitor: the cursor cannot reach it)
	real_mouse = DisplayServer.screen_get_size().x >= int(root.get_viewport().get_final_transform().x.x * vs.x)
	var di := nb
	var dr: Rect2 = rects[di]
	var gp: Vector2 = bp.global_position + dr.get_center()
	await hover(gp)
	var lines: Array = game.hud._last_tip
	var first := String(lines[0][0]) if not lines.is_empty() else ""
	var dents: Array = ents.filter(func(e): return e.debuff)
	mcheck(first == String(dents[0].name), "hovering a debuff shows its tooltip (%s, expected %s)" % [first, dents[0].name])
	check(game.hud.over_hud(gp), "the icon counts as HUD: a click there orders nothing")
	await shot("buffs_tip_debuff")
	var br: Rect2 = rects[0]
	await hover(bp.global_position + br.get_center())
	lines = game.hud._last_tip
	mcheck(not lines.is_empty() and String(lines[0][0]) == String(ents[0].name), "hovering a buff shows its tooltip")
	await shot("buffs_tip_buff")
	# timers run
	var salve: Dictionary = {}
	for e in ents:
		if e.id == "salve":
			salve = e
	var left0 := float(salve.get("left", 0.0))
	for i in 45:
		await process_frame
	var salve2: Dictionary = {}
	for e in BuffBar.entries(h, w):
		if e.id == "salve":
			salve2 = e
	check(float(salve2.get("left", 0.0)) < left0 - 0.3 and is_equal_approx(float(salve2.total), float(salve.total)),
		"a timer runs down (%.1f -> %.1f of %.1f)" % [left0, float(salve2.get("left", 0.0)), float(salve2.get("total", 0.0))])
	await hover(Vector2(vs.x * 0.5, vs.y * 0.3))
	# many effects: rows grow upward and stay inside
	for i in 14:
		h.add_modifier({"id": "salve", "source": 9000 + i, "expires": w.time + 20.0 + i, "regen": 10.0, "fx": "heal"})
	await frames(10)
	rects = bp._buff_rects.duplicate()
	var rows := {}
	for r in rects:
		rows[roundi((r as Rect2).position.y)] = true
	check(rows.size() >= 2 and rows.size() <= BuffBar.MAX_ROWS, "many effects wrap into %d rows" % rows.size())
	var n_all := BuffBar.entries(h, w).size()
	check((rects[0] as Rect2).size.x < BuffBar.SIZE, "a crowded bar uses smaller icons (%d px)" % roundi((rects[0] as Rect2).size.x))
	var counted := 0
	for r in rects:
		var t := _tip_at(bp, r)
		counted += int(t.split(" ")[0]) if t.ends_with(" more") else 1
	check(counted == n_all, "every one of the %d effects shows or is counted by a +N slot (%d slots, %d counted)" % [n_all, rects.size(), counted])
	# far too many: the last slot of each side counts the rest
	for i in 30:
		h.add_modifier({"id": "stench", "source": 9100 + i, "expires": w.time + 30.0, "slow": 0.1, "debuff": true, "fx": "slow"})
	await frames(10)
	var r2: Array = bp._buff_rects.duplicate()
	check(r2.size() < BuffBar.entries(h, w).size(), "overflow: %d slots for %d effects" % [r2.size(), BuffBar.entries(h, w).size()])
	_layout_checks(bp, r2, vs, "overflow")
	await hover(bp.global_position + (r2[r2.size() - 1] as Rect2).get_center())
	var ml: Array = game.hud._last_tip
	mcheck(not ml.is_empty() and String(ml[0][0]).ends_with("more debuffs"), "the +N slot lists the rest (%s)" % (String(ml[0][0]) if not ml.is_empty() else ""))
	await shot("buffs_overflow")
	await hover(Vector2(vs.x * 0.5, vs.y * 0.3))
	for i in 30:
		h.remove_modifier("stench")

	_layout_checks(bp, rects, vs, "many")
	await shot("buffs_many")
	# an enemy creep with effects
	# before 0:00 there are no waves: put an enemy melee creep in mid next to an ally hero (so it is seen)
	var creep: SimUnit = w.spawn(("dusk_" if h.team == C.DAWN else "dawn_") + "melee", 1 - h.team, Vector2(0, 0))
	ally.pos = Vector2(-150, 0)
	check(creep != null, "an enemy creep to select")
	if creep != null:
		w.status.apply(creep, h.id, h.team, {"id": "stunned", "stun": true, "dur": 30.0, "fx": "stun"})
		w.status.apply(creep, h.id, h.team, {"id": "crash_knife", "slow": 0.3, "dur": 30.0, "fx": "slow"})
		creep.add_modifier({"id": "war_drum_aura", "source": SimItems.AURA_SRC, "expires": w.time + 1e5,
			"stats": {"move_speed": 15.0, "hp_regen": 2.5}, "aura": true, "by": -1})
		game.input.select([creep.id])
		game.camera.focus(View.to3(creep.pos, game.terrain.height_at(creep.pos)))
		await frames(12)
		rects = bp._buff_rects.duplicate()
		check(rects.size() == BuffBar.entries(creep, w).size() and rects.size() >= 3, "a selected enemy creep's effects show (%d)" % rects.size())
		_layout_checks(bp, rects, vs, "creep")
		await shot("buffs_creep")
	print("RESULT %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)

## The first tooltip line BuffBar gives for a slot (drawn off screen, no mouse needed).
func _tip_at(bp, r: Rect2) -> String:
	var h: SimUnit = game.hud.shown()
	var w: SimWorld = game.world
	var all := BuffBar.entries(h, w)
	var buffs: Array = all.filter(func(e): return not e.debuff)
	var debuffs: Array = all.filter(func(e): return e.debuff)
	var x0: float = maxf(bp.ABIL_X, bp._chips_end + 10.0)
	var rs := BuffBar.fit(buffs.size(), debuffs.size(), x0, bp.item_x - 20.0, bp.BUFF_Y)
	for side in 2:
		var list: Array = buffs if side == 0 else debuffs
		var rects: Array = rs[side]
		for i in rects.size():
			if (rects[i] as Rect2).is_equal_approx(r):
				if i == rects.size() - 1 and list.size() > rects.size():
					return "%d more" % (list.size() - i)
				return String(list[i].name)
	return ""

func _layout_checks(bp, rects: Array, vs: Vector2, what: String) -> void:
	var ok_in := true
	var ok_above := true
	var ok_chips := true
	var ok_overlap := true
	var chips := Rect2(bp.CHIPS_X, bp.CHIPS_Y, bp._chips_end - bp.CHIPS_X, 22)
	var stash := Rect2(bp.item_x - 8, bp.STASH_Y - 8, 330, 56)
	for i in rects.size():
		var r: Rect2 = rects[i]
		var g := Rect2(bp.global_position + r.position, r.size)
		if g.position.x < 0 or g.position.y < 0 or g.end.x > vs.x or g.end.y > vs.y:
			ok_in = false
		if r.end.y > 0.0:
			ok_above = false
		if r.intersects(chips) or r.intersects(stash):
			ok_chips = false
		for j in range(i + 1, rects.size()):
			if r.intersects(rects[j]):
				ok_overlap = false
	check(ok_in, "%s: every icon inside the screen" % what)
	check(ok_above, "%s: every icon above the panel's top edge" % what)
	check(ok_chips, "%s: clear of the type chips and the stash" % what)
	check(ok_overlap, "%s: no two icons overlap" % what)

## Buffs: Healing Paste, Damage Orb, an ally's Armor Aura, Spell Shield. Debuffs: Stench from two Sludges (one is a
## stand-in source id), Silence Staff, Break Blade, Armor Loss Aura, Kragg's Charges (3), two burns.
func _load(w: SimWorld, h: SimUnit, e1: SimUnit, e2: SimUnit) -> void:
	h.add_modifier({"id": "salve", "source": h.id, "expires": w.time + 12.0, "regen": 40.0, "fx": "heal"})
	h.add_modifier({"id": "orb_damage", "source": -60, "expires": w.time + 45.0, "fx": "orb_damage",
		"stats": {"base_damage_pct": 0.8, "spell_amp": 0.15}, "dispel": "basic"})
	h.add_modifier({"id": "small_shield_aura", "source": SimItems.AURA_SRC, "expires": w.time + 1e5,
		"stats": {"armor": 2.0}, "aura": true, "by": h.id})
	h.add_modifier({"id": "spell_shield", "source": h.id, "expires": w.time + 9.0, "debuff_immune": false, "fx": "spell_shield",
		"stats": {"magic_resist": 0.6}})
	h.add_modifier({"id": "stench", "source": e1.id, "expires": w.time + 40.0, "slow": 0.2, "heal_reduction": 0.4, "debuff": true, "fx": "slow"})
	h.add_modifier({"id": "stench", "source": e2.id, "expires": w.time + 30.0, "slow": 0.2, "debuff": true, "fx": "slow"})
	w.status.apply(h, e1.id, e1.team, {"id": "silence_staff", "silence": true, "dur": 25.0, "fx": "silence"})
	w.status.apply(h, e2.id, e2.team, {"id": "break_blade", "break": true, "dur": 20.0, "fx": "break"})
	h.add_modifier({"id": "battle_armor_curse", "source": SimItems.AURA_SRC, "expires": w.time + 1e5,
		"stats": {"armor": -5.0}, "aura": true, "by": e1.id, "debuff": true})
	h.add_modifier({"id": "magnet_charge", "source": -61, "expires": w.time + 30.0, "charges": 3, "by": e2.id,
		"fx": "magnet", "debuff": true})
	w.status.add_dot(h, e1, "fiery_javelin", 20.0, 25.0, C.Element.FIRE)
	w.status.add_dot(h, e2, "sweet_poison", 15.0, 18.0, C.Element.NATURE)
	h.hp = h.max_hp
	h.refresh_stats()
