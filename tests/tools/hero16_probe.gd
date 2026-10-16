extends SceneTree
## Run 2026-10-16 in a real match window: every skill of Roydo and Blau cast in the field, with captures and PASS / FAIL
## lines for what the sim and the views must show.
##   godot --path . -s tests/tools/hero16_probe.gd -- --hero=blau --out=work/lemondev/2026-10-16-roydo-blau/shots
##   godot --path . -s tests/tools/hero16_probe.gd -- --hero=roydo --out=...
## Staged on open ground at (-900, -2900) with trees round it, fog lifted, bots off.

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const SPOT := Vector2(-900, -2900)

var game: Node
var out := "work/lemondev/2026-10-16-roydo-blau/shots"
var tag := ""
var fails := 0
var passes := 0
var only := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--4k":
			tag = "_4k"
		if a.begins_with("--only="):
			only = a.substr(7)
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://" + out + "/" + name + tag + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path)

func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)

## Wait (real frames) until the sim reaches `t` seconds after now.
func sim_wait(w: SimWorld, secs: float) -> void:
	var until := w.time + secs
	var t0 := Time.get_ticks_msec()
	while w.time < until and Time.get_ticks_msec() - t0 < 20000:
		await process_frame

func look(p: Vector2, zoom := -1.0) -> void:
	game.camera.focus(View.to3(p, game.terrain.height_at(p)))
	if zoom > 0.0 and game.camera.get("zoom") != null:
		game.camera.zoom = zoom

func stage(h: SimUnit, w: SimWorld, lvl: int) -> void:
	SimDebug.level_up(w, h, lvl - h.level)
	for aid in h.abilities:
		h.ability_level[aid] = int(SimData.ability(aid).max_level)
	h.ability_points = 0
	h.refresh_stats()
	h.hp = h.max_hp
	h.mana = h.max_mana
	SimDebug.teleport(w, h, SPOT)
	h.facing = 0.0
	w.orders.clear(h)

func dummy(w: SimWorld, id: String, p: Vector2, team := C.DUSK) -> SimUnit:
	var d := w.spawn(id, team, p)
	d.def = d.def.duplicate()
	d.def.hp = 20000.0
	d.def["can_attack"] = false
	d.refresh_stats()
	d.hp = d.max_hp
	d.order = O.HOLD
	return d

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
	for eh in w.heroes:
		if eh.team != h.team:
			eh.pos = w.map.fountains[eh.team]
			w.orders.clear(eh)
	w.vision.reveal_all = true
	SimDebug.force_start(w)
	w.next_wave_at = INF
	await frames(5)
	if String(h.def.id) == "blau":
		await _blau(w, h)
	else:
		await _roydo(w, h)
	print("\n%d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)

# ---- Blau -------------------------------------------------------------------------------------------------------------

func _blau(w: SimWorld, h: SimUnit) -> void:
	stage(h, w, 18)
	h.scepter = true
	h.auto_attack = false
	look(SPOT + Vector2(250, 0))
	await sim_wait(w, 0.6)
	await shot("blau_idle")
	var v = game.views.get(h.id)
	check(v is UnitView and v.anim != null and v.anim.has_animation("blau_shoot"), "Blau's model and clips load")
	var e := dummy(w, "ezee", SPOT + Vector2(520, 60))
	var c1 := dummy(w, "dusk_melee", SPOT + Vector2(420, -120))
	await sim_wait(w, 0.3)
	# attack: muzzle flash and tracer
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": e.id})
	await sim_wait(w, 0.33)
	await shot("blau_attack")
	await sim_wait(w, 1.2)
	check(e.hp < e.max_hp, "his shots hit")
	w.orders.clear(h)
	# Bounce Shot into the trees
	var tree := Vector2.INF
	for t in w.map.trees:
		if t.alive and (t.pos as Vector2).distance_to(SPOT) < 800.0 and (t.pos as Vector2).distance_to(SPOT) > 350.0:
			tree = t.pos
			break
	# the aiming preview: the ricochet path drawn on the ground toward the mouse
	var aim_at: Vector2 = tree if tree != Vector2.INF else e.pos
	game.input.begin_ability("bounce_shot")
	var sp: Vector2 = game.camera.cam.unproject_position(View.to3(aim_at, game.terrain.height_at(aim_at)))
	root.get_viewport().warp_mouse(sp)
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	mm.global_position = sp
	Input.parse_input_event(mm)
	await frames(8)
	await shot("blau_aim_preview")
	var pm: ImmediateMesh = game.targeting_fx._path_mesh
	print("DEBUG path surfaces ", pm.get_surface_count(), " aabb ", pm.get_aabb(), " targeting ", game.input.targeting,
		" mouse ", game.camera.ground_at(root.get_viewport().get_mouse_position()), " aim ", aim_at)
	check(game.targeting_fx._path.visible and pm.get_surface_count() > 0, "aiming Bounce Shot draws its ricochet path")
	game.input.targeting = ""
	w.events.clear()
	w.command(h.id, {"type": O.CAST_POINT, "ability": "bounce_shot", "point": aim_at})
	await sim_wait(w, 0.42)
	await shot("blau_bounce_1")
	await sim_wait(w, 0.18)
	await shot("blau_bounce_2")
	await sim_wait(w, 0.5)
	# Summon Boulders
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_POINT, "ability": "summon_boulders", "point": SPOT + Vector2(600, 0)})
	await sim_wait(w, 0.55)
	await shot("blau_boulders_roll")
	check(w.abilities.kits3.boulders.size() == 6, "six boulders roll out")
	await sim_wait(w, 1.8)
	await shot("blau_boulders_rest")
	check(w.abilities.kits3.boulders.all(func(b): return bool(b.resting)), "and settle")
	# Lay Trap
	h.mana = h.max_mana
	h.facing = 0.0
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "lay_trap"})
	await sim_wait(w, 0.32)
	await shot("blau_trap_leap")
	await sim_wait(w, 0.6)
	await shot("blau_trap_set")
	var traps := w.effects.filter(func(x): return String(x.kind) == "blau_trap")
	check(traps.size() == 1, "the trap is down")
	if not traps.is_empty():
		var walker := w.spawn("dusk_melee", C.DUSK, (traps[0].pos as Vector2) + Vector2(260, -60))
		walker.def = walker.def.duplicate()
		walker.def["can_attack"] = false
		w.orders.issue(walker, {"type": O.MOVE, "point": (traps[0].pos as Vector2) - Vector2(200, 0)}, false)
		var t1 := Time.get_ticks_msec()
		while walker.get_modifier("ensnared").is_empty() and Time.get_ticks_msec() - t1 < 6000:
			await process_frame
		await sim_wait(w, 0.1)
		await shot("blau_trap_spring")
		check(not walker.get_modifier("ensnared").is_empty(), "an enemy walking over it is caught")
	# Place Turret, it shoots
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_POINT, "ability": "place_turret", "point": h.pos + Vector2(200, 160)})
	await sim_wait(w, 0.62)
	await shot("blau_turret_build")
	var turrets := w.units.filter(func(u): return u.kind == C.Kind.SUMMON and u.alive)
	check(turrets.size() == 1, "a turret stands")
	await sim_wait(w, 1.6)
	await shot("blau_turret_shoot")
	if not turrets.is_empty():
		var tv = game.views.get(turrets[0].id)
		check(tv is UnitView and tv.anim != null and tv.anim.has_animation("turret_attack"), "the turret's model and clips load")
		w.command(h.id, {"type": O.CAST_UNIT, "ability": "pilot_turret", "target": turrets[0].id})
		await sim_wait(w, 0.8)
		await shot("blau_pilot")
		check(w.abilities.kits3.is_piloting(h), "Blau pilots it")
		check(v is UnitView and not (v as UnitView).model.visible, "and is hidden inside")
		w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(-300, 0)})
		await sim_wait(w, 0.5)
		check(not w.abilities.kits3.is_piloting(h) and (v as UnitView).model.visible, "a move order gets him out")
	look(h.pos, -1.0)
	await sim_wait(w, 0.5)
	await shot("blau_end")

# ---- Roydo ------------------------------------------------------------------------------------------------------------

func _roydo(w: SimWorld, h: SimUnit) -> void:
	stage(h, w, 18)
	h.auto_attack = false
	look(SPOT + Vector2(250, 0))
	await sim_wait(w, 0.6)
	await shot("roydo_idle")
	var v = game.views.get(h.id)
	check(v is UnitView and v.anim != null and v.anim.has_animation("roydo_punch_jab"), "Roydo's model and clips load")
	var e := dummy(w, "ezee", SPOT + Vector2(560, 220))
	var c1 := dummy(w, "dusk_melee", SPOT + Vector2(470, -150))
	var c2 := dummy(w, "dusk_ranged", SPOT + Vector2(380, 80))
	await sim_wait(w, 0.2)
	# Grip of the Ruler
	w.command(h.id, {"type": O.CAST_POINT, "ability": "grip_of_the_ruler", "point": SPOT + Vector2(420, 0)})
	await sim_wait(w, 0.75)
	await shot("roydo_grip_toss")
	check(not e.knock.is_empty(), "the enemy hero is in the air")
	await sim_wait(w, 0.5)
	await shot("roydo_grip_slam")
	check(e.is_stunned() and e.hp < e.max_hp, "it lands hurt and stunned")
	# punch
	h.pos = e.pos - Vector2(140, 0)
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": e.id})
	await sim_wait(w, 0.35)
	await shot("roydo_punch")
	w.orders.clear(h)
	# Void Rush
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "void_rush"})
	await sim_wait(w, 0.45)
	await shot("roydo_void_rush")
	check(not e.get_modifier("void_rush").is_empty(), "Void Rush weakens the enemy")
	await sim_wait(w, 0.6)
	await shot("roydo_void_rush_after")
	# Dark Matter Skin: hits until it bursts back
	var procs := 0
	for i in 60:
		var before := c1.hp
		w.combat.deal_damage(e.id, e.team, true, h, 80.0, C.DamageType.PHYSICAL, true, "attack")
		if c1.hp < before:
			procs += 1
			break
	await frames(2)
	await shot("roydo_dark_matter")
	check(procs > 0, "Dark Matter Skin bursts back")
	# Anomaly
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "anomaly"})
	await sim_wait(w, 0.42)
	await shot("roydo_anomaly_burst")
	await sim_wait(w, 0.5)
	check(v is UnitView and String(v.key) == "hero_anomaly", "the Anomaly model replaces his")
	await shot("roydo_anomaly")
	h.pos = e.pos - Vector2(520, 0)
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": e.id})
	await sim_wait(w, 0.75)
	await shot("roydo_anomaly_attack")
	check(h.is_ranged() and h.attack_range > 600.0, "he attacks from range")
	h.remove_modifier("anomaly")
	h.refresh_stats()
	await sim_wait(w, 0.5)
	check(String(v.key) == "hero_roydo", "and turns back")
	await shot("roydo_back")
