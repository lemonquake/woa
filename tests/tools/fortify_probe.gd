extends SceneTree
## Run 2026-10-15 f in a real match window (PASS / FAIL lines, captures):
##   godot --path . -s tests/tools/fortify_probe.gd -- --out=work/lemondev/2026-10-15f-regen-fortify/shots [--4k]
## * Regen readout: the total and the own + bonus breakdown on both bars, a cut shown in red, the bar's tooltip.
## * Rejuvenation Orb close up.
## * Tower shots of both teams in flight and on impact, then Fortified (bigger, splash rings).
## * Fortify's light over each team's buildings.
## * The Fortify button's tooltip stays up on every frame while hovered (it blinked).

const C = preload("res://src/sim/sim_const.gd")

var game: Node
var out := "work/lemondev/2026-10-15f-regen-fortify/shots"
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

func look(p: Vector2) -> void:
	game.camera.focus(View.to3(p, game.terrain.height_at(p)))
	await frames(12)

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

	# ---- regen readout (out of the fountain, whose regen would swamp it) ----
	h.pos += (Vector2.ZERO - h.pos).normalized() * 1800.0
	h.order = SimConst.Order.HOLD
	await look(h.pos)
	await frames(240)
	h.hp = h.max_hp * 0.6
	h.mana = h.max_mana * 0.5
	h.add_modifier({"id": "salve", "source": h.id, "expires": w.time + 60.0, "regen": 40.0, "fx": "heal"})
	h.add_modifier({"id": "clarity", "source": h.id, "expires": w.time + 60.0, "mana_regen": 3.0, "fx": "mana"})
	await frames(8)
	var r: Vector4 = w.regen_rates(h)
	check(r.x > r.z + 1.0 and r.y > r.w + 1.0, "both bars have a bonus to show (health %.1f = %.1f + %.1f)" % [r.x, r.z, r.x - r.z])
	await shot("regen_bonus")
	var bp = hud.bottom
	var hr := Rect2(bp.ABIL_X, bp.BARS_Y, bp.n_slots * bp.abil_step - 8, 24)
	await hover(bp.global_position + hr.get_center() + Vector2(-60, 0))
	var tl: Array = hud._last_tip
	mcheck(not tl.is_empty() and String(tl[0][0]).begins_with("Health") and String(tl[2][0]).begins_with("Own"),
		"hovering the health bar explains the regen (%s)" % (String(tl[1][0]) if tl.size() > 1 else ""))
	await shot("regen_tip")
	await hover(vs * Vector2(0.5, 0.3))
	h.remove_modifier("salve")
	h.add_modifier({"id": "stench", "source": 99999, "expires": w.time + 60.0, "slow": 0.2, "heal_reduction": 0.6, "debuff": true})
	h.refresh_stats()
	await frames(8)
	await shot("regen_cut")
	h.remove_modifier("stench")
	h.remove_modifier("clarity")
	h.refresh_stats()

	# ---- Rejuvenation Orb ----
	var op := h.pos + Vector2(250, 120)
	w.orbs._spawn("rejuvenation", op, "power")
	await look(op)
	await frames(10)
	check(game.orb_view._nodes.size() >= 1, "the Rejuvenation Orb is drawn")
	await shot("rejuvenation_orb")

	# ---- tower shots, both teams ----
	for team in [C.DAWN, C.DUSK]:
		var tw: SimUnit = null
		for u in w.units:
			if u.alive and u.kind == C.Kind.TOWER and u.team == team and u.lane_tier == 2 and u.building_lane == "mid":
				tw = u
		check(tw != null, "a %s tier 2 tower" % C.TEAM_NAMES[team])
		if tw == null:
			continue
		tw.glyph_until = C.LONG_AGO
		var foe := ("dusk_" if team == C.DAWN else "dawn_") + "melee"
		var dir: Vector2 = (Vector2.ZERO - tw.pos).normalized()
		var spawned: Array = []
		for i in 4:
			var cr := w.spawn(foe, 1 - team, tw.pos + dir * 520.0 + dir.orthogonal() * (i - 1.5) * 90.0)
			cr.def = cr.def.duplicate()
			cr.def.hp = 1e6
			cr.refresh_stats()
			cr.hp = cr.max_hp
			cr.order = SimConst.Order.HOLD
			spawned.append(cr)
		await look(tw.pos + dir * 300.0)
		var style := "tower_dawn" if team == C.DAWN else "tower_dusk"
		var got := await _wait_shot(style, 0.45)
		check(got, "%s tower shot in flight" % C.TEAM_NAMES[team])
		await shot("tower_shot_%s" % ("light" if team == C.DAWN else "dark"))
		await _wait_impact(style)
		await shot("tower_hit_%s" % ("light" if team == C.DAWN else "dark"))
		# Fortified: bigger shots, splash rings, the light over the buildings
		w.glyph_ready_at[team] = -1e6
		check(w.glyph(team, h.id if team == h.team else -1), "%s Fortify" % C.TEAM_NAMES[team])
		await frames(20)
		got = await _wait_shot(style, 0.45)
		check(got and bool(game.fx._proj.values().any(func(v): return String(v.style) == style and bool(v.get("big", false)))),
			"%s Fortified shot is the big one" % C.TEAM_NAMES[team])
		await shot("tower_shot_fortified_%s" % ("light" if team == C.DAWN else "dark"))
		await _wait_impact(style)
		await frames(2)
		await shot("tower_splash_%s" % ("light" if team == C.DAWN else "dark"))
		var shells: int = game.fortify_fx._shells.size()
		check(shells >= 10, "%s: a shell of light over each building (%d)" % [C.TEAM_NAMES[team], shells])
		# the base: the Ancient and the buildings round it
		var anc: SimUnit = null
		for u in w.units:
			if u.alive and u.kind == C.Kind.ANCIENT and u.team == team:
				anc = u
		if anc != null:
			game.camera.target = View.to3(anc.pos, game.terrain.height_at(anc.pos))
			await look(anc.pos + (Vector2.ZERO - anc.pos).normalized() * 500.0)
			await frames(6)
			await shot("fortify_base_%s" % ("light" if team == C.DAWN else "dark"))

	# ---- the Fortify button's tooltip is steady ----
	await look(h.pos)
	var mm = hud.minimap
	var gb: Vector2 = mm.global_position + Vector2(mm.S - 23, -41)
	await hover(gb)
	var on := 0
	for i in 60:
		await process_frame
		if hud.tip.showing:
			on += 1
	mcheck(on == 60, "the Fortify button's tooltip shows on every frame while hovered (%d of 60)" % on)
	await shot("fortify_button_tip")
	print("RESULT %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)

## Wait (up to 6 s) until a tower shot of `style` has flown `frac` of its way.
func _wait_shot(style: String, frac: float) -> bool:
	for i in 360:
		await process_frame
		for id in game.fx._proj:
			var v: Dictionary = game.fx._proj[id]
			if String(v.style) != style:
				continue
			var node: Node3D = v.node
			var start: Vector3 = v.start
			var tgt: SimUnit = game.world.get_unit(int(v.target))
			if tgt == null:
				continue
			var end := View.to3(tgt.pos, game.terrain.height_at(tgt.pos))
			var d0 := Vector2(start.x, start.z).distance_to(Vector2(end.x, end.z))
			var d1 := Vector2(node.global_position.x, node.global_position.z).distance_to(Vector2(end.x, end.z))
			if d0 > 0.1 and 1.0 - d1 / d0 >= frac:
				return true
	return false

## Wait until no shot of `style` is in the air (the last one landed), then a few frames for the impact to bloom.
func _wait_impact(style: String) -> void:
	for i in 240:
		await process_frame
		if not game.fx._proj.values().any(func(v): return String(v.style) == style):
			break
	await frames(3)
