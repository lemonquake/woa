extends Node3D
## Warriors of Aether: one match. Builds the map and simulation, steps it at 30 Hz in _physics_process, mirrors it
## into views (terrain, foliage, buildings, units, effects, fog of war) and hosts the input controller and HUD.
##
## Capture mode for automated screenshots (window opens, renders, saves, quits):
##   godot --path . -- --capture=work/shots/x.png --t=95 --cam=-1600,-1400 --zoom=1.0 [--autoplay] [--pitch=58]

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var map: SimMap
var world: SimWorld
var terrain: TerrainBuilder
var foliage: Foliage
var atmosphere: Atmosphere
var camera: CameraRig
var fx: Fx
var status_fx: StatusFx
var targeting_fx: TargetingFx
var bars: UnitBars
var input: InputController
var audio: GameAudio
var menus: Control
var hud: Control
var views := {}                            # unit id -> UnitView | BuildingView
var player_team := C.DAWN
var player_hero_id := -1
var selected_id := -1                     # the primary selected unit (its card and portrait)
var selected: Array = []                   # every selected unit id (box select)
var fog_tex: ImageTexture
var fog_img: Image
var _fog_quad: MeshInstance3D
var args := {}
var _capture_frames := -1
var booted := false                        # _ready finished building (it yields to the loading screen between steps)
var _last_dmg := {}
var _fog_all := PackedByteArray()          # the Debug panel's revealed map

## One loading step: report it to the loading screen and let a frame draw.
func _stage(p: float, text: String) -> void:
	LoadingScreen.progress(get_tree(), p, text)
	await get_tree().process_frame

func _ready() -> void:
	_parse_args()
	Options.install(get_tree())
	Options.apply_audio()
	var t0 := Time.get_ticks_msec()
	await _stage(0.08, "Loading terrain")
	map = SimMap.new()
	map.build(1)
	world = SimWorld.new(1, map)
	world.setup_match()
	_spawn_heroes()
	await _stage(0.22, "Loading sky")
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.build()
	Options.apply_environment(atmosphere.env)
	await _stage(0.3, "Loading mountains")
	terrain = TerrainBuilder.new(map)
	terrain.build(self)
	atmosphere.materials.append(terrain.material)
	await _stage(0.5, "Loading trees")
	foliage = Foliage.new()
	add_child(foliage)
	foliage.build(map, terrain)
	await _stage(0.68, "Loading bases")
	var dressing := Dressing.new()
	dressing.foliage = foliage
	add_child(dressing)
	dressing.build(map, terrain)
	await _stage(0.84, "Loading heroes")
	fx = Fx.new()
	fx.game = self
	foliage.game_fx = fx
	add_child(fx)
	status_fx = StatusFx.new()
	status_fx.game = self
	status_fx.fx = fx
	add_child(status_fx)
	targeting_fx = TargetingFx.new()
	targeting_fx.game = self
	add_child(targeting_fx)
	camera = CameraRig.new()
	camera.edge_pan_enabled = bool(Options.get_value("edge_pan"))
	camera.edge_speed = float(Options.get_value("camera_speed"))
	add_child(camera)
	camera.height_at = func(p: Vector2) -> float: return terrain.height_at(p)
	camera.follow = func():
		var h := world.get_unit(player_hero_id)
		return View.to3(h.pos, terrain.height_at(h.pos)) if h and h.alive else null
	var hero := world.get_unit(player_hero_id)
	camera.focus(View.to3(hero.pos, terrain.height_at(hero.pos)))
	_build_fog()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var screen := ScreenFx.new()
	screen.game = self
	ui.add_child(screen)
	bars = UnitBars.new()
	bars.game = self
	ui.add_child(bars)
	hud = preload("res://src/ui/hud.gd").new()
	hud.set("game", self)
	ui.add_child(hud)
	input = InputController.new()
	input.game = self
	add_child(input)
	menus = preload("res://src/ui/match_menus.gd").new()
	menus.set("game", self)
	ui.add_child(menus)
	audio = GameAudio.new()
	audio.game = self
	add_child(audio)
	selected_id = player_hero_id
	selected = [player_hero_id]
	_sync_views()
	booted = true
	print("match ready in %d ms" % (Time.get_ticks_msec() - t0))
	await _stage(0.96, "Ready")
	# a couple of rendered frames so shaders compile behind the loading screen, then reveal the match
	for i in 3:
		await get_tree().process_frame
	LoadingScreen.close(get_tree())
	for f in String(args.get("off", "")).split(",", false):
		match f:
			"ssao": atmosphere.env.ssao_enabled = false
			"glow": atmosphere.env.glow_enabled = false
			"fog": atmosphere.env.fog_enabled = false
			"msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"fxaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"shadows": atmosphere.sun.shadow_enabled = false
			"trees", "decor":
				for c in foliage.get_children():
					var mmi := c as MultiMeshInstance3D
					if mmi and ((f == "decor") == (mmi.visibility_range_end > 0.0)):
						mmi.visible = false
			"water": get_node("River").visible = false
			"fow": _fog_quad.visible = false
			"terrain": get_node("Terrain").visible = false
			"units":
				for v in views.values():
					if v is UnitView: v.visible = false
	if args.has("noui"):
		ui.visible = false
		bars.visible = false
		hud.visible = false
	if args.has("capture"):
		_start_capture()
	elif args.has("bench"):
		_start_bench()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"

## The player's hero (Dawn, chosen in Hero Select) and the bot's (Dusk). Looks and outfits use the customisable
## hero body. Capture and benchmark runs use default looks; --hero= and --bot_hero= pick the heroes.
func _spawn_heroes() -> void:
	var automated := args.has("capture") or args.has("bench")
	var my_id := String(args.get("hero", GameSettings.selected))
	if not (my_id in GameSettings.HEROES):
		my_id = "blood_ranger"
	var mine: Dictionary = GameSettings.default_look(my_id) if automated else GameSettings.look_for(my_id)
	var p := world.spawn_hero(my_id, C.DAWN, mine.duplicate(true))
	p.player = true
	player_hero_id = p.id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bot_id := String(args.get("bot_hero", "blood_ranger" if automated else GameSettings.opponent_hero(rng)))
	if not (bot_id in GameSettings.HEROES):
		bot_id = "blood_ranger"
	var b := world.spawn_hero(bot_id, C.DUSK, bot_look(bot_id))
	world.bots.append(SimBot.new(world, b.id, "mid", "Bot Gerald"))
	if args.has("autoplay"):
		world.bots.append(SimBot.new(world, p.id, "mid", "Autoplay"))

## The bot's appearance: the hero's default look in Dusk colours.
static func bot_look(id: String) -> Dictionary:
	if id in GameSettings.OWN_BODY:
		var o := GameSettings.default_look(id)
		o.display_name = "Bot Gerald"
		return o
	if id == "ezee":
		var e := GameSettings.default_look("ezee")
		e.display_name = "Bot Gerald"
		e.look["eye_color"] = "ff3a2a"
		e.look["hair_color"] = "2a0c0a"
		for slot in e.dyes:
			if (e.dyes[slot] as Dictionary).has("cloth"):
				e.dyes[slot]["cloth"] = "5a0c14"
			if (e.dyes[slot] as Dictionary).has("trim"):
				e.dyes[slot]["trim"] = "c03020"
			if (e.dyes[slot] as Dictionary).has("gold"):
				e.dyes[slot]["gold"] = "a02818"
		return e
	return {
		"display_name": "Bot Gerald", "look": HeroLook.preset("shade"),
		"outfit": {"inner_garment": "chain_shirt", "armor": "tc_nightstalker_leathers", "leggings": "nightweave_leggings",
			"boots": "soft_boot", "gloves": "runed_glove", "helm": "linen_hood"},
		"dyes": {"armor": {"cloth": "3a1020", "leather": "201014"}},
	}

# ---- Simulation loop -----------------------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	if not booted:
		return
	if _capture_frames >= 0 and not args.has("live"):
		return
	_step()

func _step() -> void:
	var t := Time.get_ticks_usec()
	world.step()
	t = _tm("sim", t)
	_drain_events()
	_sync_views()
	_tm("sync", t)

func _sync_views() -> void:
	if selected.size() > 0:
		var keep: Array = []
		for id in selected:
			var su := world.get_unit(id)
			if su != null and (su.alive or su.is_hero()):
				keep.append(id)
		if keep.size() != selected.size():
			selected = keep if not keep.is_empty() else [player_hero_id]
			selected_id = selected[0]
	for u in world.units:
		if not views.has(u.id):
			_make_view(u)
	for id in views.keys():
		var v = views[id]
		var u := world.get_unit(id)
		if u == null:
			v.queue_free()
			views.erase(id)
			continue
		if v is UnitView:
			v.tick(u)
		else:
			v.update_state(u)

func _make_view(u: SimUnit) -> void:
	if u.is_building():
		var b := BuildingView.new()
		add_child(b)
		b.setup(u, terrain)
		views[u.id] = b
	elif u.kind == K.WARD:
		var wv := UnitView.new()
		add_child(wv)
		views[u.id] = wv
		wv.uid = u.id
		wv.terrain = terrain
		wv.prev_pos = u.pos
		wv.cur_pos = u.pos
		var eye := fx._sphere(0.16, fx._glow(Color(1.0, 0.85, 0.3) if u.team == 0 else Color(1.0, 0.3, 0.3), 4.0))
		eye.position.y = 1.2
		wv.add_child(eye)
	else:
		var v := UnitView.new()
		add_child(v)
		v.setup(u, terrain)
		views[u.id] = v

func _drain_events() -> void:
	for e in world.events:
		if audio and _capture_frames < 0:
			audio.event(e, world)
		match e.t:
			"damage":
				_on_damage(e)
			"cast_start":
				var cv = views.get(e.u)
				var aid := String(e.ability)
				if cv is UnitView and int(e.get("slot", -1)) < 0 and aid != "tp":
					cv.on_cast_start(aid, world.abilities.cast_point(aid, -1))
			"leap_start":
				var lv = views.get(e.u)
				if lv is UnitView:
					lv.on_leap(float(e.dur))
				fx.leap_start(e.u)
			"leap_land":
				var lv2 = views.get(e.u)
				if lv2 is UnitView:
					lv2.on_leap_land()
				fx.leap_land(e)
			"impact":
				var iv = views.get(e.u)
				if iv is UnitView:
					iv.on_impact(String(e.what))
				fx.push_impact(e)
			"stomp":
				fx.stomp(e.pos, float(e.radius))
			"push_land":
				if float(e.speed) > 300.0:
					fx.push_land(e.u)
			"taint_cast":
				fx.taint_cast(e.u)
			"curse":
				fx.curse_hit(e.u)
			"unholy_start":
				fx.unholy_start(e.u)
			"unholy_end":
				fx.unholy_end(e.u)
			"unholy_reflect":
				fx.unholy_reflect(e.u, int(e.target))
			"attack_start":
				var v = views.get(e.u)
				if v is UnitView:
					v.on_attack_start(float(e.point))
			"attack_cancel":
				var v2 = views.get(e.u)
				if v2 is UnitView:
					v2.on_attack_cancel()
			"projectile":
				fx.projectile(e, world)
			"projectile_end":
				fx.projectile_end(e)
			"last_hit":
				if e.u == player_hero_id:
					var t := world.get_unit(e.target)
					if t:
						bars.popup("+%d" % int(e.gold), _head(t.pos, 1.6), Color(1.0, 0.82, 0.2), 20)
			"deny":
				var t2 := world.get_unit(e.target)
				if t2:
					bars.popup("!", _head(t2.pos, 2.0), Color(1.0, 1.0, 1.0), 26, 0.6)
			"miss":
				var t3 := world.get_unit(e.target)
				if t3 and (e.u == player_hero_id or t3.id == player_hero_id):
					bars.popup("miss", _head(t3.pos, 2.2), Color(0.85, 0.85, 0.9), 15)
			"level_up":
				var h := world.get_unit(e.u)
				if h:
					fx.level_up(View.to3(h.pos, terrain.height_at(h.pos)))
			"effect_move":
				if String(e.get("ability", "")) == "gale_impact":
					fx.gale_move(int(e.get("src", -1)), e.pos, bool(e.get("done", false)))
			"gale_impact":
				fx.gale_launch(e)
			"gale_hit":
				fx.gale_hit(e)
			"masterful_hit":
				fx.masterful_hit(e)
				var mt := world.get_unit(int(e.target))
				if mt and (int(e.u) == player_hero_id or mt.id == player_hero_id):
					var mv = views.get(mt.id)
					var mh: float = (mv.bar_height + 0.9) if mv is UnitView else 2.6
					bars.popup("+%d!" % int(e.amount), _head(mt.pos, mh), Color(1.0, 0.3, 0.22), 24, 0.7, 1.0, Vector2(-36, 0), true)
			"lifesteal":
				fx.lifesteal(int(e.u))
			"channel_start":
				var chv = views.get(e.u)
				if chv is UnitView:
					chv.on_channel_start(String(e.ability))
				if String(e.ability) == "burst_shot":
					fx.burst_start(e)
			"burst_wave":
				var bwv = views.get(e.u)
				if bwv is UnitView:
					bwv.on_burst_wave()
				fx.burst_wave(e)
			"channel_end":
				var cev = views.get(e.u)
				if cev is UnitView:
					cev.on_channel_end()
				if String(e.get("ability", "")) == "burst_shot":
					fx.burst_end(int(e.u))
			"blood_ranger_start":
				fx.blood_ranger_start(int(e.u))
			"back_leap":
				var blv = views.get(e.u)
				if blv is UnitView:
					blv.on_back_leap(float(e.dur))
				fx.back_leap(e)
			"back_leap_land":
				fx.back_leap_land(e)
			"tango":
				var ti := int(e.get("tree", -1))
				if ti >= 0:
					fx.tango_eat(int(e.u), map.trees[ti].pos)
			"tp_start":
				var tu := world.get_unit(e.u)
				if tu and (tu.team == player_team or world.vision.sees(player_team, tu)):
					fx.tp_start(e.u, View.to3(tu.pos, terrain.height_at(tu.pos)), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
				elif tu:
					# enemies still see where a Town Portal is going to land
					fx.tp_start(e.u, Vector3(0, -50, 0), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
			"tp_end":
				fx.tp_end(e.u, true)
				var v3 = views.get(e.u)
				if v3 is UnitView:
					v3.prev_pos = e.pos
					v3.cur_pos = e.pos
			"tp_cancel":
				fx.tp_end(e.u)
			"tree":
				# felled (topples away from the blow), eaten or withered (shrinks away), regrown or planted (grows in)
				var tidx := int(e.i)
				if bool(e.alive):
					foliage.grow_tree(tidx)
				elif e.has("from"):
					fx.tree_fell(tidx, e.from)
					foliage.set_tree_alive(tidx, false)
				else:
					foliage.shrink_tree(tidx)
			"hero_kill":
				if hud and hud.has_method("on_kill"):
					hud.on_kill(e)
				var kv2 := world.get_unit(e.victim)
				if kv2 and int(e.u) == player_hero_id:
					bars.popup("+%d" % int(e.get("gold", 0)), _head(kv2.pos, 2.6), Color(1.0, 0.82, 0.2), 30, 1.6, 2.0, Vector2.ZERO, true)
			"death":
				var kv = views.get(e.u)
				var killer := world.get_unit(e.killer)
				var dead := world.get_unit(e.u)
				if kv is UnitView and killer and dead and dead.is_lane_creep() and killer.is_hero():
					kv.death_knock(killer.pos, float(_last_dmg.get(e.u, 0.0)))
				var du := world.get_unit(e.u)
				if du and du.is_building() and hud and hud.has_method("announce"):
					var side := "Your" if du.team == player_team else "The enemy's"
					var what := {"tower1": "tier 1 tower", "tower2": "tier 2 tower", "tower3": "tier 3 tower", "tower4": "tier 4 tower",
						"melee_rax": "melee barracks", "ranged_rax": "ranged barracks", "filler": "statue", "ancient": "Throne"}
					var wname := String(what.get(String(du.def.id), "building"))
					var verb := "was denied" if e.get("deny", false) else "has fallen"
					var lane_name: String = {"top": "Top", "mid": "Middle", "bot": "Bottom"}.get(du.building_lane, "")
					hud.announce("%s %s %s" % [side, wname, verb], (lane_name + " lane") if lane_name != "" else "",
						UiKit.GOLD if du.team != player_team else UiKit.DUSK)
					hud.kill_feed.on_building(du, killer, bool(e.get("deny", false)), player_team,
						(lane_name + " " if lane_name != "" else "") + wname)
				if du and du.kind == C.Kind.COURIER and hud:
					hud.kill_feed.on_courier(du, killer)
				if du and du.id == player_hero_id and hud:
					hud.scoreboard.capture_recap(du, world)
				if du and du.is_hero() and killer and killer.team == du.team and du.id != killer.id and hud:
					hud.kill_feed.on_deny_hero(du)
			"victory":
				if hud and hud.has_method("announce"):
					hud.announce("Victory!" if int(e.team) == player_team else "Defeat", "The Throne has been destroyed")
			"error":
				if e.u == player_hero_id and hud and hud.has_method("error"):
					hud.error(String(e.msg))
	world.events.clear()

## Damage: hit reactions, melee sparks and floating numbers (yours, on you, and enemy hero spells you can see).
func _on_damage(e: Dictionary) -> void:
	var amt := float(e.amount)
	_last_dmg[e.u] = amt
	var tu := world.get_unit(e.u)
	if tu == null or amt <= 0.0:
		return
	var su := world.get_unit(e.src)
	var dv = views.get(e.u)
	var atk := bool(e.get("attack", false))
	if dv is UnitView:
		# Burst Shot's arrows flash and jolt the body like attacks do
		dv.on_hit(su.pos if su else tu.pos, amt, tu.max_hp, atk or String(e.get("key", "")) == "burst_shot")
		if atk and su and not su.is_ranged() and dv.visible:
			fx.melee_hit(su, tu, amt)
	if not (tu.team == player_team or world.vision.sees(player_team, tu)):
		return
	var style := ""
	if bool(e.get("reflected", false)):
		style = "reflect"
	elif su and su.id == player_hero_id:
		style = "out"
	elif tu.id == player_hero_id:
		style = "in"
	elif su and su.is_hero() and not atk:
		style = "spell"
	if style != "":
		var hgt: float = (dv.bar_height + 0.35) if dv is UnitView else 2.2
		bars.damage_number(amt, int(e.get("type", 0)), _head(tu.pos, hgt), style, tu.id, String(e.get("key", "")))
	if float(e.get("halved", 0.0)) > 0.0:
		var hv = views.get(e.u)
		bars.popup("½", _head(tu.pos, (hv.bar_height if hv is UnitView else 2.2) + 0.6), Color(0.8, 0.5, 1.0), 26, 0.8, 0.8, Vector2(30, 0), true)

func _head(p: Vector2, extra: float) -> Vector3:
	return View.to3(p, terrain.height_at(p)) + Vector3(0, extra, 0)

func _tm(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if _bench_until > 0.0:
		_bench_acc[key] = _bench_acc.get(key, 0.0) + (t1 - t0) / 1000.0
	return t1

func _process(dt: float) -> void:
	if not booted:
		return
	var _t := Time.get_ticks_usec()
	var alpha := Engine.get_physics_interpolation_fraction()
	if _capture_frames >= 0:
		alpha = 1.0
	for v in views.values():
		if v is UnitView:
			v.frame(alpha, dt, camera.cam)
			var u := world.get_unit(v.uid)
			if u:
				v.visible = u.team == player_team or world.vision.sees(player_team, u) or not u.alive and false
				if u.team != player_team and not u.alive:
					v.visible = world.vision.cell_visible(player_team, u.pos)
	_t = _tm("views", _t)
	fx.frame(world, alpha, dt)
	_t = _tm("fx", _t)
	status_fx.frame(dt)
	_t = _tm("status", _t)
	targeting_fx.frame()
	_t = _tm("target", _t)
	if _bench_until > 0.0:
		_bench_frame(dt)
	atmosphere.update(world.is_night(), dt if _capture_frames < 0 else 10.0)
	foliage.set_near_fade(camera.distance * camera.zoom)
	_update_fog(dt)
	_t = _tm("fog", _t)
	var hover: int = input.hover_id if input else -1
	for id in views:
		var v = views[id]
		if v is UnitView:
			var su := world.get_unit(id)
			var friendly := su != null and su.team == player_team
			if id in selected:
				v.set_selected(true, Color(0.3, 1.0, 0.4, 0.9) if friendly else Color(1.0, 0.3, 0.25, 0.9))
			elif id == hover:
				v.set_selected(true, Color(1.0, 1.0, 1.0, 0.55) if friendly else Color(1.0, 0.55, 0.3, 0.7))
			else:
				v.set_selected(false, Color.WHITE)
	fx.tower_ranges(world, world.get_unit(player_hero_id), player_team)
	if _capture_frames >= 0:
		_capture_frames += 1
		_demo_casts()
		var fl := String(args.get("frames", "45")).split(",")
		if _capture_frames == int(fl[0]) - 6 and args.has("marker"):
			var mv := String(args.marker).split(",")
			var mp := Vector2(float(mv[0]), float(mv[1]))
			fx.marker(View.to3(mp, terrain.height_at(mp)), false)
		if str(_capture_frames) in fl:
			_save_capture()

# ---- Fog of war -------------------------------------------------------------------------------------------------------

func _build_fog() -> void:
	var n := SimMap.VN
	fog_img = Image.create(n, n, false, Image.FORMAT_L8)
	fog_tex = ImageTexture.create_from_image(fog_img)
	_fog_prev = ImageTexture.create_from_image(fog_img)
	_fog_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_fog_quad.mesh = q
	_fog_quad.extra_cull_margin = 16384.0
	_fog_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = preload("res://src/game/fog_of_war.gdshader")
	_fog_mat.set_shader_parameter("fog_tex", fog_tex)
	_fog_mat.set_shader_parameter("fog_prev", _fog_prev)
	_fog_mat.set_shader_parameter("map_half", View.MAP_HALF_M)
	_fog_mat.render_priority = 100
	_fog_quad.material_override = _fog_mat
	camera.cam.add_child(_fog_quad)
	_fog_quad.position = Vector3(0, 0, -1)

var _fog_prev: ImageTexture
var _fog_mat: ShaderMaterial
var _fog_tick := -1
var _fog_blend := 1.0
var _fog_prev_img: Image

## The vision grid (0/1 bytes) goes to the GPU as-is whenever it changes; the shader scales it and cross-fades from
## the previous grid, so cells fade in and out smoothly without a per-cell loop here.
func _update_fog(dt: float) -> void:
	var vtick: int = world.tick / C.VISION_UPDATE_TICKS
	if vtick != _fog_tick:
		_fog_tick = vtick
		if _fog_prev_img == null:
			_fog_prev_img = Image.create(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8)
		_fog_prev_img.copy_from(fog_img)
		_fog_prev.update(_fog_prev_img)
		var n := SimMap.VN
		var vis: PackedByteArray = world.vision.visible[player_team]
		if world.vision.reveal_all:
			if _fog_all.size() != n * n:
				_fog_all.resize(n * n)
				_fog_all.fill(1)
			vis = _fog_all
		fog_img.set_data(n, n, false, Image.FORMAT_L8, vis)
		fog_tex.update(fog_img)
		_fog_blend = 0.0 if _capture_frames < 0 else 1.0
	_fog_blend = minf(1.0, _fog_blend + dt / 0.25)
	_fog_mat.set_shader_parameter("blend", _fog_blend)

# ---- Benchmark ------------------------------------------------------------------------------------------------------

var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_until := -1.0
var _bench_warm := 0.0
var _bench_acc := {}

## Fast-forward to --t, then play normally for --bench seconds, following the player hero, and report frame times.
func _start_bench() -> void:
	var t := float(args.get("t", "120"))
	camera.edge_pan_enabled = false
	while world.time < t:
		world.step()
		_drain_events()
		if world.tick % 30 == 0:
			_sync_views()
	_sync_views()
	_bench_warm = 3.0
	_bench_until = float(args.bench)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _bench_frame(dt: float) -> void:
	var h := world.get_unit(player_hero_id)
	if h:
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))
	if _bench_warm > 0.0:
		_bench_warm -= dt
		Trail3D.cost_us = 0
		UnitBars.cost_us = 0
		return
	_bench_frames.append(dt * 1000.0)
	var vrid := get_viewport().get_viewport_rid()
	_bench_acc["gpu"] = _bench_acc.get("gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_bench_acc["rcpu"] = _bench_acc.get("rcpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vrid)
	_bench_acc["proc"] = _bench_acc.get("proc", 0.0) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_bench_acc["phys"] = _bench_acc.get("phys", 0.0) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_bench_acc["draws"] = _bench_acc.get("draws", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_acc["prims"] = _bench_acc.get("prims", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_bench_until -= dt
	if _bench_until <= 0.0:
		var a := Array(_bench_frames)
		a.sort()
		var n := a.size()
		var avg := 0.0
		for v in a:
			avg += v
		avg /= n
		var line := "BENCH frames %d avg %.2f ms (%.0f fps) p50 %.2f p95 %.2f p99 %.2f max %.2f over16.7 %d units %d" % [
			n, avg, 1000.0 / avg, a[n / 2], a[int(n * 0.95)], a[int(n * 0.99)], a[n - 1], a.filter(func(v): return v > 16.7).size(), world.units.size()]
		_bench_acc["trails"] = Trail3D.cost_us / 1000.0
		_bench_acc["bars"] = UnitBars.cost_us / 1000.0
		var parts := []
		for k in _bench_acc:
			parts.append("%s %.2f" % [k, _bench_acc[k] / n])
		line += "
  per-frame means: " + ", ".join(parts)
		print(line)
		var f := FileAccess.open("res://work/bench.txt", FileAccess.WRITE)
		f.store_line(line)
		get_tree().quit()

# ---- Capture ---------------------------------------------------------------------------------------------------------

func _start_capture() -> void:
	var t := float(args.get("t", "5"))
	camera.edge_pan_enabled = false
	while world.time < t:
		world.step()
		_drain_events()
		if world.tick % 30 == 0:
			_sync_views()
	_demo_setup()
	_sync_views()
	for v in views.values():
		if v is UnitView:
			v.tick(world.get_unit(v.uid))
	if args.has("cam"):
		var c := String(args.cam).split(",")
		var p := Vector2(float(c[0]), float(c[1]))
		camera.focus(View.to3(p, terrain.height_at(p)))
	elif _demo_cam.x != INF:
		camera.focus(View.to3(_demo_cam, terrain.height_at(_demo_cam)))
	else:
		var h := world.get_unit(player_hero_id)
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))
	if args.has("zoom"):
		camera.zoom = float(args.zoom)
		camera._zoom_goal = camera.zoom
	if args.has("pitch"):
		camera.pitch_deg = float(args.pitch)
	if args.has("dist"):
		camera.distance = float(args.dist)
	camera._apply()
	if args.has("select"):
		selected_id = int(args.select)
		selected = [selected_id]
	if args.has("drag"):
		var dv := String(args.drag).split(",")
		input.drag_rect = Rect2(float(dv[0]), float(dv[1]), float(dv[2]), float(dv[3]))
		input._box_select(input.drag_rect, false)
	if args.has("showqueue"):
		# a Shift-queue demo: move, attack-move, a spell, then move back; the waypoints are drawn as if Shift were held
		var qh := world.get_unit(player_hero_id)
		var o0 := qh.pos
		world.command(qh.id, {"type": C.Order.MOVE, "point": o0 + Vector2(500, 150)})
		world.command(qh.id, {"type": C.Order.ATTACK_MOVE, "point": o0 + Vector2(900, 500), "queue": true})
		world.command(qh.id, {"type": C.Order.CAST_POINT, "ability": qh.abilities[1], "point": o0 + Vector2(1300, 600), "queue": true})
		world.command(qh.id, {"type": C.Order.MOVE, "point": o0 + Vector2(200, 650), "queue": true})
		world.command(qh.id, {"type": C.Order.HOLD, "queue": true})
	if args.has("pause"):
		menus.toggle()
	if args.has("endscreen"):
		world.winner = player_team
		menus._end_shown = true
		menus._show_end()
	_capture_frames = 0

## Capture demos: --lvl=N levels the player's hero and learns its abilities, --at=x,y moves it, --cast=a,b@F issues
## each ability at capture frame F (no-target abilities at once, point abilities at the nearest enemy).
var _demo_cam := Vector2(INF, INF)

func _demo_setup() -> void:
	var h := world.get_unit(player_hero_id)
	if args.has("nobot"):
		# the enemy hero waits in its fountain (ability captures without it walking into the shot)
		for b in world.bots.duplicate():
			if b.hero_id != player_hero_id:
				world.bots.erase(b)
		for eh in world.heroes:
			if eh.team != h.team:
				eh.pos = map.fountains[eh.team]
				world.orders.clear(eh)
	if args.has("lvl"):
		var lv := int(args.lvl)
		world.combat.give_xp(h, float(C.XP_TABLE[lv - 1]) - h.xp)
		for aid in h.abilities:
			var a := SimData.ability(aid)
			var mx := int(a.max_level)
			var want := mini(mx, (lv + 1) / 2) if not a.has("required_level") else (a.required_level as Array).filter(func(r): return lv >= int(r)).size()
			h.ability_level[aid] = want
		h.ability_points = 0
		h.refresh_stats()
		h.hp = h.max_hp
		h.mana = h.max_mana
		for b in world.bots:
			if b.hero_id == player_hero_id:
				world.bots.erase(b)
				break
	if args.has("treedemo"):
		_tree_demo_setup(h)
	if args.has("at"):
		var av := String(args.at).split(",")
		if av[0] == "tree":
			# a creep standing between the hero and a tree: for impact / stun captures
			for i in map.trees.size():
				var tr: Dictionary = map.trees[i]
				if not tr.alive or tr.pos.length() > 4000.0:
					continue
				var found := false
				for k in 8:
					var d := Vector2.from_angle(k * TAU / 8.0)
					var ok := true
					for s in range(2, 9):
						if not map.is_walkable(tr.pos + d * (s * 64.0)):
							ok = false
							break
					if ok:
						var cp: Vector2 = tr.pos + d * 190.0
						var c := world.spawn("dusk_melee", C.DUSK, cp)
						c.order = C.Order.HOLD
						var c2 := world.spawn("dusk_ranged", C.DUSK, cp + d.orthogonal() * 120.0)
						c2.order = C.Order.HOLD
						h.pos = cp + d * 170.0
						h.facing = (-d).angle()
						_demo_cam = cp + d * 120.0 if args.has("center_caster") else cp - d * 60.0
						found = true
						break
				if found:
					break
		elif av[0] == "hero":
			# beside the enemy hero, which can be weakened (--weaken=0.15) for kill captures
			for eh in world.heroes:
				if eh.team != h.team:
					var off2 := float(av[1]) if av.size() > 1 else 500.0
					h.pos = eh.pos + Vector2(-off2, -off2 * 0.3)
					if args.has("weaken"):
						eh.hp = eh.max_hp * float(args.weaken)
					_demo_cam = (h.pos + eh.pos) * 0.5
					break
		elif av[0] == "wave":
			# beside the enemy mid wave: the Dusk lane creep nearest the map centre
			var best: SimUnit = null
			for u in world.units:
				if u.alive and u.team == C.DUSK and u.is_lane_creep() and (best == null or u.pos.length() < best.pos.length()):
					best = u
			var off := float(av[1]) if av.size() > 1 else 200.0
			h.pos = best.pos + Vector2(-off, -off * 0.6) if best else Vector2.ZERO
		else:
			h.pos = Vector2(float(av[0]), float(av[1]))
		var v = views.get(h.id)
		if v is UnitView:
			v.prev_pos = h.pos
			v.cur_pos = h.pos
		if args.has("face"):
			h.facing = deg_to_rad(float(args.face))
		world.vision.update()

## --treedemo: the hero stands by the forest edge with a Mini-Axe and an Ironwood Twig. At capture frame 4 it chops the
## nearest tree and plants a twig; a third tree that fell earlier grows back during the capture.
var _tree_demo := {}

func _tree_demo_setup(h: SimUnit) -> void:
	var best := -1
	var dir := Vector2.ZERO
	for i in map.trees.size():
		var tr: Dictionary = map.trees[i]
		if not tr.alive or tr.pos.distance_to(Vector2(-2400, -3600)) > 2500.0:
			continue
		for k in 8:
			var d := Vector2.from_angle(k * TAU / 8.0)
			var ok := true
			for st in range(2, 9):
				if not map.is_walkable(tr.pos + d * (st * 64.0)):
					ok = false
					break
			if ok:
				best = i
				dir = d
				break
		if best >= 0:
			break
	if best < 0:
		return
	var tp: Vector2 = map.trees[best].pos
	h.pos = tp + dir * 260.0
	h.facing = (-dir).angle()
	h.inventory[0] = {"id": "quelling_blade", "charges": 0}
	h.inventory[1] = {"id": "branch", "charges": 0}
	h.refresh_stats()
	# a neighbour of the chopped tree fell a while ago and is about to grow back
	var other := map.tree_at(tp + dir.orthogonal() * 140.0, 130.0)
	if other == best or other < 0:
		other = map.tree_at(tp - dir.orthogonal() * 140.0, 130.0)
	if other >= 0 and other != best:
		world.cut_tree(other, Vector2.INF)
		map.trees[other].regrow = 1.6
		foliage.set_tree_alive(other, false)
	_tree_demo = {"tree": best, "dir": dir, "plant": h.pos + dir * 230.0}
	_demo_cam = h.pos - dir * 120.0
	world.events.clear()

func _demo_casts() -> void:
	if not _tree_demo.is_empty() and _capture_frames == 4:
		var h0 := world.get_unit(player_hero_id)
		world.command(h0.id, {"type": C.Order.CAST_POINT, "ability": "", "item_slot": 0, "point": map.trees[int(_tree_demo.tree)].pos})
		world.command(h0.id, {"type": C.Order.CAST_POINT, "ability": "", "item_slot": 1, "point": _tree_demo.plant, "queue": true})
	if not args.has("cast"):
		return
	var spec := String(args.cast).split("@")
	var at_frame := int(spec[1]) if spec.size() > 1 else 3
	if _capture_frames != at_frame:
		return
	var h := world.get_unit(player_hero_id)
	var near: SimUnit = null
	var nd := INF
	for u in world.units:
		if u.alive and u.team != h.team and not u.is_building() and u.pos.distance_to(h.pos) < nd:
			nd = u.pos.distance_to(h.pos)
			near = u
	for aid in spec[0].split(","):
		if aid == "attack" and near:
			world.command(h.id, {"type": C.Order.ATTACK_UNIT, "target": near.id})
			continue
		var a := SimData.ability(aid)
		if a.is_empty():
			continue
		match String(a.behavior):
			"no_target":
				world.command(h.id, {"type": C.Order.CAST_NO_TARGET, "ability": aid})
			"point":
				var pt: Vector2 = near.pos if near else h.pos
				if args.has("aim") and near:
					pt = h.pos + (near.pos - h.pos).normalized() * float(args.aim)
				world.command(h.id, {"type": C.Order.CAST_POINT, "ability": aid, "point": pt})
			_:
				if near:
					world.command(h.id, {"type": C.Order.ATTACK_UNIT, "target": near.id, "queue": true})

func _save_capture() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := String(args.capture)
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var fl := String(args.get("frames", "45")).split(",")
	if fl.size() > 1:
		path = path.get_basename() + "_%d.png" % _capture_frames
	img.save_png(path)
	print("captured ", path, " at game time ", world.clock_text())
	if str(_capture_frames) == fl[fl.size() - 1]:
		get_tree().quit()
