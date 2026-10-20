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
var camps: Camps
var atmosphere: Atmosphere
var camera: CameraRig
var fx: Fx
var sludge_fx: SludgeFx
var item_fx: ItemFx
var fire_fx: FireFx
var azrin_fx: AzrinFx
var froster_fx: FrosterFx
var caziel_fx: CazielFx
var hero15_fx: Hero15Fx
var hero16_fx: Hero16Fx
var azrael_fx: AzraelFx
var hero18_fx: Hero18Fx
var araki_fx: ArakiFx
var fortify_fx: FortifyFx
var status_fx: StatusFx
var orb_view: OrbView
var site_view: SiteView
var _hide_heroes := false                   # --off=heroes / --off=creeps (benchmark ablations)
var _hide_creeps := false
var targeting_fx: TargetingFx
var bars: UnitBars
var input: InputController
var audio: GameAudio
var menus: Control
var hud: Control
var views := {}                            # unit id -> UnitView | BuildingView
var player_team := C.DAWN
var player_hero_id := -1                   # your hero; while watching, the watched hero (watch())
## Watching an All-Bot match (Game Setup with no You slot, or --watch): every hero is a bot's. player_hero_id and
## player_team follow the watched hero (its HUD, portrait and orders); the Watch panel (WatchPanel) picks the hero, the
## camera, whose sight shows and whose orders and plans are drawn. Nothing the watcher clicks reaches the simulation.
var spectator := false
var ranked_match := false                   # a ranked match (Ranked screen): its result moves MMR
var casual_match := {}                      # Play with ladder players: who was here (Ranked.remember_casual afterwards)
var watching_match := false                # an All-Bot match (the Watching panel stays while you control a hero)
var controlling := -1                      # watching: the hero you took over from its bot (take_control), or -1
var vision_mode := -1                      # -1 your (the watched hero's) team; 0, 1 that team; 2 both; 3 the whole map
var cam_mode := "free"                     # watching: "free", "follow" (the watched hero), "hero" (hero view), "auto"
var show_orders := 1                       # watching: 0 off, 1 the watched hero's orders, 2 every hero's
var show_plans := true                     # watching: what each bot is doing, over its head
var watch_panel: Control
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
	var mp := NetSession.inst != null and NetSession.inst.state == NetSession.State.LOADING and not NetSession.inst.config.is_empty()
	multiplayer_match = mp
	world = SimWorld.new(_match_seed(mp), map)
	world.setup_match()
	if mp:
		_spawn_net_heroes()
	else:
		_spawn_heroes()
	if args.has("reveal"):
		SimDebug.set_flag(world, "reveal", true)
	await _stage(0.22, "Loading sky")
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.build()
	Options.apply_environment(atmosphere.env, atmosphere.sun)
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
	camps = Camps.new()
	camps.game = self
	add_child(camps)
	camps.build(map, terrain)
	await _stage(0.84, "Loading heroes")
	_prebuild_unit_meshes()
	fx = Fx.new()
	fx.game = self
	fire_fx = FireFx.new()
	add_child(fire_fx)
	fx.fire = fire_fx
	azrin_fx = AzrinFx.new()
	azrin_fx.game = self
	azrin_fx.fx = fx
	azrin_fx.fire = fire_fx
	add_child(azrin_fx)
	froster_fx = FrosterFx.new()
	froster_fx.game = self
	froster_fx.fx = fx
	froster_fx.fire = fire_fx
	add_child(froster_fx)
	caziel_fx = CazielFx.new()
	caziel_fx.game = self
	caziel_fx.fx = fx
	caziel_fx.fire = fire_fx
	add_child(caziel_fx)
	fortify_fx = FortifyFx.new()
	fortify_fx.game = self
	fortify_fx.fx = fx
	add_child(fortify_fx)
	hero15_fx = Hero15Fx.new()
	hero15_fx.game = self
	hero15_fx.fx = fx
	hero15_fx.fire = fire_fx
	add_child(hero15_fx)
	hero16_fx = Hero16Fx.new()
	hero16_fx.game = self
	hero16_fx.fx = fx
	hero16_fx.fire = fire_fx
	add_child(hero16_fx)
	azrael_fx = AzraelFx.new()
	azrael_fx.game = self
	azrael_fx.fx = fx
	azrael_fx.fire = fire_fx
	add_child(azrael_fx)
	hero18_fx = Hero18Fx.new()
	hero18_fx.game = self
	hero18_fx.fx = fx
	hero18_fx.fire = fire_fx
	add_child(hero18_fx)
	araki_fx = ArakiFx.new()
	araki_fx.game = self
	araki_fx.fx = fx
	araki_fx.fire = fire_fx
	add_child(araki_fx)
	sludge_fx = SludgeFx.new()
	sludge_fx.game = self
	sludge_fx.fx = fx
	foliage.game_fx = fx
	add_child(fx)
	add_child(sludge_fx)
	item_fx = ItemFx.new()
	item_fx.game = self
	item_fx.fx = fx
	item_fx.fire = fire_fx
	add_child(item_fx)
	status_fx = StatusFx.new()
	status_fx.game = self
	status_fx.fx = fx
	add_child(status_fx)
	orb_view = OrbView.new()
	orb_view.game = self
	orb_view.fx = fx
	add_child(orb_view)
	site_view = SiteView.new()
	site_view.game = self
	site_view.fx = fx
	add_child(site_view)
	site_view.build(world)
	targeting_fx = TargetingFx.new()
	targeting_fx.game = self
	add_child(targeting_fx)
	camera = CameraRig.new()
	camera.edge_pan_enabled = bool(Options.get_value("edge_pan"))
	camera.edge_speed = float(Options.get_value("camera_speed"))
	add_child(camera)
	camera.set_process(false)              # held still until the match is shown (edge pan while loading moved it)
	camera.height_at = func(p: Vector2) -> float: return terrain.height_at(p)
	camera.ground_top = terrain.max_height() * View.S + 0.5
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
	if watching_match:
		cam_mode = String(args.get("watch_cam", "auto"))
		vision_mode = int(args.get("watch_vision", "2"))
		watch_panel = WatchPanel.new()
		watch_panel.game = self
		ui.add_child(watch_panel)
	menus = preload("res://src/ui/match_menus.gd").new()
	menus.set("game", self)
	ui.add_child(menus)
	audio = GameAudio.new()
	audio.game = self
	add_child(audio)
	selected_id = player_hero_id
	selected = [player_hero_id]
	_sync_views()
	if mp:
		_start_net()
	elif not args.has("capture") and not args.has("bench") and (args.has("llm_endpoint")
			or LlmChat.ready_to_run() and not LlmChat.automated(get_tree())):
		# the online chat writer: single player only (every multiplayer machine must show the same lines)
		var lc := LlmChat.load_config()
		if args.has("llm_endpoint"):
			# a local stand-in (tools/llm_mock.py): your key is never read for it
			lc = {"api_key": "sk-or-mock", "provider": "openrouter", "endpoint": String(args.llm_endpoint),
				"usage_path": "user://llm_usage_probe.json"}
		if not lc.is_empty():
			llm = LlmChat.new()
			llm.name = "LlmChat"
			add_child(llm)
			llm.setup(world, player_team, lc)
			print("online bot chat on (%s)" % llm.model())
	booted = true
	print("match ready in %d ms" % (Time.get_ticks_msec() - t0))
	await _stage(0.96, "Ready")
	# a couple of rendered frames so shaders compile behind the loading screen, then reveal the match
	for i in 3:
		await get_tree().process_frame
	LoadingScreen.close(get_tree())
	# the match opens on your hero (Dota does the same)
	center_on_hero()
	camera.set_process(true)
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
			"camps": camps.visible = false
			"fow": _fog_quad.visible = false
			"terrain": get_node("Terrain").visible = false
			"units":
				_units_off = true
			"heroes":
				_hide_heroes = true
			"creeps":
				_hide_creeps = true
	for part in String(args.get("hide", "")).split(",", false):
		var hn = hud.get(part)
		if hn is CanvasItem:
			hn.visible = false
	if args.has("shadow1"):
		atmosphere.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	if args.has("scale3d"):
		get_viewport().scaling_3d_scale = float(args.scale3d)
	if args.has("noui"):
		if args.has("bars"):
			# health bars only: hide every other piece of the interface
			for c in ui.get_children():
				if c != bars and c is CanvasItem:
					c.visible = false
		else:
			ui.visible = false
			bars.visible = false
		hud.visible = false
	if args.has("capture"):
		_start_capture()
	elif args.has("bench"):
		_start_bench()

## Every player action goes through here as a SimCommands dictionary: applied at once in single player, or sent
## through the network session to be applied on every machine at the same tick in multiplayer (its error, if any,
## then comes back later as an "error" event). Returns the error now in single player, "" in multiplayer.
var net = null                              # NetMatch while a multiplayer match runs, else null
var llm: LlmChat = null                     # the online chat writer (Options "Online bot chat" with a key), else null
var multiplayer_match := false              # this match began as a multiplayer one (stays true if the server goes)
var paused_by := ""                         # who paused the game (multiplayer)

func act(c: Dictionary) -> String:
	if spectator:
		return "You are watching this match"
	if net != null:
		net.send_command(c)
		return ""
	return SimCommands.apply(world, player_hero_id, c)

## An order for one of the player's units (the hero or its courier).
func order(uid: int, o: Dictionary) -> void:
	act({"k": "order", "u": uid, "o": o})

## Leaving the match (quit, restart, back to the menu): keep what the bots learned in fights so far.
func _exit_tree() -> void:
	if BotMemory.active and BotMemory.dirty:
		BotMemory.save()


## Centre the camera on the player's hero (start of the match, respawn, F1 twice, portrait click).
## A bot said yes to your "add me", or offered to add you (ChatSocial, event "friend"): the ladder makes it real
## (single player: a ladder player's id is known only here).
func _on_friend(e: Dictionary) -> void:
	if multiplayer_match or String(e.get("pid", "")) == "":
		return
	var pid := String(e.pid)
	var nm := String(e.get("name", Ranked.profile(pid).get("name", "")))
	if String(e.get("what", "")) == "added":
		var was: bool = pid in (Ranked.me().get("friends", []) as Array)
		Ranked.befriend(pid)
		if hud and hud.has_method("notice") and not was:
			hud.notice("You and %s are now friends" % nm)
	elif Ranked.send_request(pid, "with" if world.get_unit(int(e.get("u", -1))) != null and world.get_unit(int(e.u)).team == player_team else "vs"):
		if hud and hud.has_method("notice"):
			hud.notice("%s sent you a friend request" % nm)

func center_on_hero() -> void:
	var h := world.get_unit(player_hero_id)
	if h != null and camera != null:
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"

## The heroes from Game Setup (GameSettings.match_slots): you on either team, bots on both, any heroes (bots may pick
## the same one). Looks and outfits use the customisable hero body. Captures, benchmarks and probes play the classic
## duel (you against Bot Gerald in mid; --hero= and --bot_hero= pick the heroes) unless --bots=5v5 asks for full teams.
## Learning (BotMemory) follows Options "Bots learn from games", and is off for automated runs.
func _spawn_heroes() -> void:
	var automated := args.has("capture") or args.has("bench")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var slots: Array = []
	if automated or args.has("hero") or args.has("bot_hero") or args.has("bots"):
		slots = _scripted_slots(automated, rng)
		if args.has("xp_rate"):
			world.xp_rate = float(args.xp_rate)
		if args.has("gold_rate"):
			world.gold_rate = float(args.gold_rate)
	else:
		ranked_match = not GameSettings.ranked.is_empty()
		slots = GameSettings.match_slots(rng)
		if not ranked_match and bool(Options.get_value("ladder_bots")) and not args.has("watch"):
			casual_match = Matchmaker.casual_identities(slots, rng)
		world.xp_rate = GameSettings.xp_rate()
		world.gold_rate = GameSettings.gold_rate()
	if args.has("watch"):
		# --watch: the scripted line-up with your slot played by a bot too
		for s in slots:
			if s.kind == "you":
				s.kind = "bot"
				s.name = "Bot Pip"
	spectator = not slots.any(func(s): return String(s.kind) == "you")
	watching_match = spectator
	BotMemory.active = bool(Options.get_value("bots_learn")) and not automated and not args.has("nolearn")
	if BotMemory.active:
		BotMemory.load_data()
	var mine: SimUnit = null
	var made: Array = []
	for s in slots:
		var team := int(s.team)
		var id := String(s.hero)
		var look: Dictionary
		if s.kind == "you":
			look = (GameSettings.default_look(id) if automated else GameSettings.look_for(id)).duplicate(true)
			if ranked_match:
				look.display_name = String(Ranked.me().name)      # ranked: your player name, like everyone else's
		elif team == C.DAWN:
			look = GameSettings.default_look(id).duplicate(true)
			look.display_name = String(s.name)
		else:
			look = bot_look(id)
			look.display_name = String(s.name)
		var h := world.spawn_hero(id, team, look)
		made.append([h, s])
		if s.kind == "you" and mine == null:
			mine = h
	if mine == null:
		mine = (made[0][0] as SimUnit)
	if not spectator:
		mine.player = true
		mine.player_name = String(Ranked.me().name) if ranked_match else String(NetBrowser.load_prefs().get("name", ""))
	player_hero_id = mine.id
	player_team = mine.team
	if not spectator and not automated:
		# what the bots know of you: your rank, your last game (were you MVP?) (run 2026-10-19 e)
		world.player_cards[mine.id] = _your_card()
		world.ladder = Ranked.ladder_card(20)          # the bots know the top of the ladder (run 2026-10-20 e)
	for m in made:
		var h: SimUnit = m[0]
		var s: Dictionary = m[1]
		if h == mine and not spectator:
			if args.has("autoplay"):
				world.bots.append(SimBot.new(world, h.id, "mid", "Autoplay"))
			if ranked_match and String(s.get("role", "")) != "":
				world.brain(h.team).fixed_role[h.id] = int(s.role)       # the role you were matched into
			continue
		var bot := SimBot.new(world, h.id, "mid", String(s.name), String(s.skill))
		world.bots.append(bot)
		if s.has("rating"):
			bot.set_rating(float(s.rating), s.get("traits", {}))      # a ranked player: its own skill and manners
		elif s.has("traits"):
			bot.set_identity(s.traits)                               # a ladder player in a casual match: who it is
		if String(s.get("role", "")) != "":
			world.brain(h.team).fixed_role[h.id] = int(s.role)
	if spectator:
		return
	var br := world.brain(player_team)
	br.player_pref[mine.id] = String(_slot_of(made, mine).get("lane", ""))

## The world's seed: fixed for captures and benchmarks (comparable runs), the host's in multiplayer, else random.
func _match_seed(mp: bool) -> int:
	if mp:
		return int(NetSession.inst.config.seed)
	if args.has("capture") or args.has("bench") or args.has("seed"):
		return int(args.get("seed", "1"))
	return randi_range(1, 2000000000)

# ---- Multiplayer ------------------------------------------------------------------------------------------------

var _net_slot_heroes := {}                  # lobby slot -> hero unit id

## The heroes of a multiplayer match, in slot order (the same ids on every machine). Every human hero counts as a
## player's (the bots leave their lanes alone); this machine's player gets the camera and the controls. Bots never
## learn in multiplayer, so every machine's bots decide alike.
func _spawn_net_heroes() -> void:
	var me := int(NetSession.inst.config.get("me", 1))
	var look_of := func(sl: Dictionary) -> Dictionary:
		var id := String(sl.hero)
		var lk: Dictionary
		if String(sl.kind) == "human" and not (sl.get("look", {}) as Dictionary).is_empty():
			lk = (sl.look as Dictionary).duplicate(true)
		elif String(sl.kind) == "human" or int(sl.team) == C.DAWN:
			lk = GameSettings.default_look(id).duplicate(true)
		else:
			lk = bot_look(id)
		lk.display_name = String(sl.name)
		return lk
	var r := NetMatch.spawn_heroes(world, NetSession.inst.config, me, look_of)
	_net_slot_heroes = r.slot_heroes
	player_hero_id = int(r.mine)
	player_team = world.get_unit(player_hero_id).team

func _start_net() -> void:
	multiplayer_match = true
	net = NetSession.inst.match_loaded(world, _net_slot_heroes)
	net.step_world = _step
	net.on_world_replaced = _on_world_replaced
	net.on_system = _on_net_system
	NetSession.inst.left.connect(_on_net_left)

## A snapshot replaced the world (desync repair or rejoin): views follow the new units and trees.
func _on_world_replaced(w2: SimWorld) -> void:
	world = w2
	foliage.resync_trees()
	_sync_views()
	if hud and hud.has_method("notice"):
		hud.notice("Your game was brought back in step with the server")

func _on_net_system(c: Dictionary) -> void:
	if hud == null or not hud.has_method("notice"):
		return
	var nm := String(c.get("name", ""))
	match String(c.get("k", "")):
		"sys_bot":
			hud.notice("%s disconnected: a bot plays their hero until they come back" % nm if nm != "" else "A player disconnected")
		"sys_human":
			hud.notice("A player is back")

## The session ended during the match: without the server the game goes on here, the other players' heroes played by
## bots.
func _on_net_left(reason: String) -> void:
	if net == null:
		return
	net = null
	world.paused = false
	if hud and hud.has_method("announce"):
		hud.announce(reason, "The game goes on here: bots play the other players' heroes")

static func _slot_of(made: Array, h: SimUnit) -> Dictionary:
	for m in made:
		if m[0] == h:
			return m[1]
	return {}

func _scripted_slots(automated: bool, rng: RandomNumberGenerator) -> Array:
	var my_id := String(args.get("hero", GameSettings.selected))
	if not (my_id in GameSettings.HEROES):
		my_id = "blood_ranger"
	var bot_id := String(args.get("bot_hero", "blood_ranger" if automated else GameSettings.opponent_hero(rng)))
	if not (bot_id in GameSettings.HEROES):
		bot_id = "blood_ranger"
	var out := [{"team": C.DAWN, "kind": "you", "hero": my_id, "skill": "hard", "name": "", "lane": "mid"},
		{"team": C.DUSK, "kind": "bot", "hero": bot_id, "skill": "hard", "name": "Bot Gerald", "lane": ""}]
	if args.has("lineup"):
		# --lineup=a,b,...: ten heroes, Ancient Light's five then Black Sun's five; the first is yours
		var ids := String(args.lineup).split(",")
		out[0].hero = ids[0]
		out[1].hero = ids[5] if ids.size() > 5 else bot_id
		for i in range(1, 5):
			if i < ids.size():
				out.append({"team": C.DAWN, "kind": "bot", "hero": ids[i], "skill": "hard", "name": GameSettings.BOT_NAMES[i], "lane": ""})
			if i + 5 < ids.size():
				out.append({"team": C.DUSK, "kind": "bot", "hero": ids[i + 5], "skill": "hard", "name": GameSettings.BOT_NAMES[i + 4], "lane": ""})
	elif String(args.get("bots", "")) == "5v5":
		var pool := ["sludge", "ezee", "blood_ranger", "azrin", "azrin", "blood_ranger", "sludge", "ezee"]
		for i in 4:
			out.append({"team": C.DAWN, "kind": "bot", "hero": pool[i], "skill": "hard", "name": GameSettings.BOT_NAMES[i + 1], "lane": ""})
			out.append({"team": C.DUSK, "kind": "bot", "hero": pool[i + 4], "skill": "hard", "name": GameSettings.BOT_NAMES[i + 5], "lane": ""})
	return out

## An enemy bot's appearance: the hero's default look in Black Sun colours.
static func bot_look(id: String) -> Dictionary:
	if id == "azrin":
		# Black Sun's Azrin: the same fire, darker robes and ash-dark hair with red ends
		var az := GameSettings.default_look("azrin")
		az.display_name = "Bot Gerald"
		az.look["hair_color"] = "4a1008"
		for slot in az.dyes:
			if (az.dyes[slot] as Dictionary).has("cloth"):
				az.dyes[slot]["cloth"] = "2a0a0a"
		return az
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
	if net != null:
		net.physics_tick()
	else:
		_step()

func _step() -> void:
	var t := Time.get_ticks_usec()
	world.step()
	t = _tm("sim", t)
	_drain_events()
	t = _tm("events", t)
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
			v.fog_ok = sees(u)
			if not u.alive and not own_team(u.team):
				v.fog_ok = sees_cell(u.pos)
			v.tick(u)
		else:
			v.update_state(u)
	_sync_ground_items()

## Items lying on the ground: the item's icon floating over a gold ring and a soft shadow, bobbing gently; hidden in
## the fog for the other team.
var _ground_views := {}                     # gid -> Node3D

func _sync_ground_items() -> void:
	var want := {}
	for g in world.ground_items:
		want[int(g.gid)] = g
	for gid in _ground_views.keys():
		if not want.has(gid):
			(_ground_views[gid] as Node3D).queue_free()
			_ground_views.erase(gid)
	var t := Time.get_ticks_msec() / 1000.0
	for gid in want:
		var g: Dictionary = want[gid]
		if not _ground_views.has(gid):
			_ground_views[gid] = _make_ground_item(g)
		var n: Node3D = View.live(_ground_views[gid])
		var p := View.to3(g.pos, terrain.height_at(g.pos))
		n.global_position = p
		n.visible = fx._seen(g.pos)
		var spr: Node3D = n.get_child(0)
		spr.position.y = 0.55 + 0.08 * sin(t * 2.4 + float(gid))

func _make_ground_item(g: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var spr := Sprite3D.new()
	spr.texture = UiKit.held_item_icon(g.item)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = false
	spr.shaded = false
	spr.pixel_size = 0.55 / maxf(1.0, float(spr.texture.get_width())) if spr.texture else 0.01
	n.add_child(spr)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.3
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.82, 0.35)
	ring.material_override = rm
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	var sh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.orientation = PlaneMesh.FACE_Y
	sh.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0)])
	gt.gradient = gr
	sm.albedo_texture = gt
	sh.material_override = sm
	sh.position.y = 0.03
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(sh)
	return n

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
		var eye_col := Color(1.0, 0.85, 0.3) if u.team == 0 else Color(1.0, 0.3, 0.3)
		if String(u.def.id) == "ward_sentry":
			eye_col = Color(0.4, 0.75, 1.0)            # Reveal Ward: a blue eye
		var eye := fx._sphere(0.16, fx._glow(eye_col, 4.0))
		eye.position.y = 1.2
		wv.add_child(eye)
		wv.place()
	else:
		var v := UnitView.new()
		add_child(v)
		v.setup(u, terrain)
		views[u.id] = v
		v.place()                                  # where it stands from the start, before its first frame()

## Every creep and neutral model is built once while loading (both teams' colours), so the merged meshes
## (MeshMerge) are ready before the first of each kind walks on: building one costs ~65 ms, a hitch mid-match.
func _prebuild_unit_meshes() -> void:
	var kinds := [K.CREEP_MELEE, K.CREEP_RANGED, K.CREEP_SIEGE, K.CREEP_FLAG, K.NEUTRAL_CREEP, K.SUMMON]
	var t0 := Time.get_ticks_msec()
	var n := 0
	for id in SimData.units():
		var def := SimData.unit(id)
		if not (int(def.get("kind", -1)) in kinds) or ModelCatalog.info(String(def.get("model", ""))).is_empty():
			continue
		for team in ([C.DAWN, C.DUSK] if int(def.kind) != K.NEUTRAL_CREEP else [C.NEUTRAL]):
			var u := SimUnit.new()
			u.setup(-1000 - n, def, team, Vector2.ZERO, 0.0)
			var v := UnitView.new()
			add_child(v)
			v.setup(u, terrain)
			v.queue_free()
			n += 1
	print("unit meshes prebuilt: %d models in %d ms" % [n, Time.get_ticks_msec() - t0])

## Events the item effects draw (a lookup, not a list built for every event).
const ITEM_EVENTS := {"jump": 1, "chain": 1, "spell_shield": 1, "gold_glove": 1, "mana_burst": 1, "mend": 1, "knockback": 1,
	"sneak_end": 1, "combine": 1, "spikes_return": 1, "blocked": 1, "cleave": 1, "item_use": 1, "blast_rod": 1, "net_staff": 1,
	"static_charge": 1, "frost_blast": 1, "refresh": 1, "team_guard": 1, "war_drum": 1, "crash_knife": 1}

func _drain_events() -> void:
	for e in world.events:
		if audio and _capture_frames < 0:
			audio.event(e, world)
		if ITEM_EVENTS.has(e.t):
			item_fx.event(e)
		if e.t in AzrinFx.EVENTS:
			azrin_fx.event(e)
		elif e.t in FrosterFx.EVENTS:
			froster_fx.event(e)
		elif e.t in CazielFx.EVENTS:
			caziel_fx.event(e)
		elif e.t in Hero15Fx.EVENTS:
			hero15_fx.event(e)
		elif e.t in Hero16Fx.EVENTS:
			hero16_fx.event(e)
		elif e.t in AzraelFx.EVENTS:
			azrael_fx.event(e)
		elif e.t in Hero18Fx.EVENTS:
			hero18_fx.event(e)
		elif e.t in ArakiFx.EVENTS:
			araki_fx.event(e)
		match e.t:
			"damage":
				_on_damage(e)
			"paused":
				var pu := world.get_unit(int(e.u))
				paused_by = String(pu.look.get("display_name", pu.name)) if pu != null and bool(e.on) else ""
			"respawn":
				if int(e.u) == player_hero_id and bool(Options.get_value("center_on_respawn")) and _capture_frames < 0 and not spectator:
					center_on_hero()
			"cast_start":
				var cv = views.get(e.u)
				var aid := String(e.ability)
				if cv is UnitView and int(e.get("slot", -1)) < 0 and aid != "tp":
					var cp := world.abilities.cast_point(aid, -1)
					var cu := world.get_unit(int(e.u))
					if aid in SimKits5.WINDUPS and cu != null:
						cp += world.abilities.val(cu, aid, "windup")     # Ser Emelrich's blow lands as the wind-up ends
					cv.on_cast_start(aid, cp)
				if aid == "smash":
					# the Ogre's Smash: its area glows red on the ground through the 2.8 s wind-up
					fx.smash_warning(e.point, float(SimData.ability("smash").values.radius[0]), world.abilities.cast_point(aid, -1))
			"neutral_spell":
				fx.neutral_spell(e)
			"dust":
				fx.dust(e)
			"orb_taken":
				_on_orb(e)
			"site":
				_on_site(e)
			"glyph":
				_on_glyph(e)
			"fortify_splash":
				fortify_fx.on_splash(e)
			"crit":
				# Dota: a red number with the critical damage (before the target's reductions) over the target
				var ct := world.get_unit(int(e.target))
				if ct and sees(ct):
					_crit_hit[int(e.target)] = int(e.u)
					var cvw = views.get(ct.id)
					var chh: float = (cvw.bar_height + 0.6) if cvw is UnitView else 2.4
					bars.popup("%d!" % int(round(float(e.amount))), _head(ct.pos, chh), Color(1.0, 0.18, 0.12), 30, 0.9, 1.1,
						Vector2(randf_range(-20.0, 20.0), 0), true)
			"bash":
				fx.bash_hit(int(e.target))
			"item_debuff":
				fx.debuff_hit(int(e.target), String(e.kind))
			"overwhelm":
				fx.debuff_hit(int(e.target), "overwhelm")
				fx.bash_hit(int(e.target))
			"soul_burst":
				fx.soul_burst(int(e.u))
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
			"hook_launch":
				sludge_fx.hook_launch(e)
			"hook_latch":
				sludge_fx.hook_latch(e)
			"hook_kill":
				sludge_fx.hook_kill(e)
			"toggle":
				sludge_fx.toggle(e)
			"blubber":
				sludge_fx.blubber(e)
			"chomp_bite":
				sludge_fx.chomp_bite(e)
			"growing_gut":
				sludge_fx.growing_gut(e)
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
				if e.has("site"):
					site_view.on_channel(int(e.site), float(e.until), int(e.u))
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
				if String(e.get("ability", "")).begins_with("site_"):
					site_view.on_channel_end(int(e.u))
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
				if tu and sees(tu):
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
					if spectator:
						side = SimConst.TEAM_NAMES[du.team] + "'s"
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
					var title := "Victory!" if int(e.team) == player_team else "Defeat"
					if spectator:
						title = "%s wins" % SimConst.TEAM_NAMES[int(e.team)]
					hud.announce(title, "The Throne has been destroyed")
				# the bots score this game into what they learned (Options: Bots learn from games)
				SimTeamAI.match_over(world)
			"chat":
				if hud and hud.has_method("on_chat") and (int(e.team) == player_team or bool(e.get("all", false)) or spectator):
					hud.on_chat(e)
			"chat_intent":
				if llm != null:
					llm.want(e)
			"friend":
				_on_friend(e)
			"save":
				var sa := world.get_unit(int(e.get("ally", -1)))
				if int(e.u) == player_hero_id and sa != null:
					bars.popup("Saved", _head(sa.pos, 2.6), Color(0.55, 1.0, 0.6), 24, 1.4, 1.6, Vector2.ZERO, true)
			"ping":
				if int(e.team) == player_team and int(e.u) != player_hero_id:
					fx.ping(e.pos)
			"error":
				if e.u == player_hero_id and hud and hud.has_method("error"):
					hud.error(String(e.msg))
	world.events.clear()

var _frame_no := 0
var _units_off := false                     # --off=units (benchmarks): unit views stay hidden

## The part of the ground the camera shows, in simulation units, grown by a margin (units outside it are not animated).
func _view_rect() -> Rect2:
	var cam := camera.cam
	var vs := get_viewport().get_visible_rect().size
	var y := camera.target.y
	var r := Rect2()
	var first := true
	for c in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs, Vector2(vs.x * 0.5, 0)]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		var p := o + d * 120.0
		if d.y < -0.01:
			p = o + d * minf((o.y - y) / -d.y, 200.0)
		var q := View.to2(p)
		if first:
			r = Rect2(q, Vector2.ZERO)
			first = false
		else:
			r = r.expand(q)
	return r.grow(500.0)

## Damage: hit reactions, melee sparks and floating numbers (yours, on you, and enemy hero spells you can see).
## Fortify: the light over the buildings; the allies are told who pressed it (the kill feed and a note over the
## bottom panel). The enemy sees the light only where it has vision.
func _on_glyph(e: Dictionary) -> void:
	fortify_fx.on_glyph(e)
	if int(e.team) != player_team or hud == null:
		return
	var by := world.get_unit(int(e.get("by", -1)))
	var who := "Your team"
	if by != null:
		who = "You" if by.id == player_hero_id else (by.bot_name if by.bot_name != "" else String(by.look.get("display_name", by.name)))
	var col := UiKit.DAWN if player_team == 0 else UiKit.DUSK
	hud.kill_feed.add_line([[who, col], [" used Fortify", UiKit.GOLD]], "status/fortified")
	hud.notice("%s used Fortify: buildings protected for %d s" % [who, int(SimConst.GLYPH_BUILDING_DURATION)])

## An orb was taken: everyone hears of it in the kill feed (Dota's rune message); your team sees the gold or
## experience it gave over the heroes.
func _on_orb(e: Dictionary) -> void:
	var h := world.get_unit(int(e.u))
	if h == null:
		return
	if hud and hud.get("kill_feed") != null:
		var col := UiKit.DAWN if h.team == 0 else UiKit.DUSK
		var who := String(h.look.get("display_name", h.name))
		if h.bot_name != "":
			who = h.bot_name
		hud.kill_feed.add_line([[who, col], [" took a ", UiKit.TEXT], [String(e.name), OrbView.COLORS.get(String(e.kind), UiKit.GOLD)]], "status/keen")
	if h.team != player_team:
		return
	var hv = views.get(h.id)
	var hh: float = (hv.bar_height + 0.9) if hv is UnitView else 2.6
	if e.has("gold"):
		for a in world.heroes:
			if a.team == h.team and a.alive:
				bars.popup("+%d" % int(e.gold), _head(a.pos, hh), Color(1.0, 0.82, 0.2), 22, 1.4, 1.6)
	if e.has("xp"):
		bars.popup("+%d XP" % int(e.xp), _head(h.pos, hh), Color(0.75, 0.55, 1.0), 22, 1.4, 1.6)
		var other := world.get_unit(int(e.get("also", -1)))
		if other and other.alive:
			bars.popup("+%d XP" % int(e.xp), _head(other.pos, hh), Color(0.75, 0.55, 1.0), 22, 1.4, 1.6)

## Map sites (SimSites): a Warp Gate's flash at both ends, a lily's heal, a lamp lit or put out (a line in the kill feed
## when it is your team's or in sight).
func _on_site(e: Dictionary) -> void:
	var s := world.sites.get_site(int(e.id))
	if s.is_empty():
		return
	var h := world.get_unit(int(e.get("u", -1)))
	var seen := sees_cell(s.pos)
	match String(e.what):
		"warp":
			var hv = views.get(int(e.u))
			if hv is UnitView:
				hv.prev_pos = e.to
				hv.cur_pos = e.to
			var col := Color(0.62, 0.42, 1.0)
			if seen:
				fx.shockwave(fx.ground3(e.from, 0.1), 2.2, col, 0.6)
			if sees_cell(e.to) or (h and own_team(h.team)):
				fx.shockwave(fx.ground3(e.to, 0.1), 2.2, col, 0.6)
			site_view.on_channel(int(e.id), -1.0)
		"lily_taken":
			if h and (h.team == player_team or seen):
				var hv2 = views.get(h.id)
				var hh: float = (hv2.bar_height + 0.9) if hv2 is UnitView else 2.6
				bars.popup("+%d" % int(e.hp), _head(h.pos, hh), Color(0.45, 1.0, 0.45), 22, 1.2, 1.4)
				fx.shockwave(fx.ground3(h.pos, 0.1), 1.0, Color(1.0, 0.65, 0.85), 0.45)
		"lamp_lit", "lamp_out":
			if h and hud and hud.get("kill_feed") != null and (h.team == player_team or seen):
				var who := String(h.bot_name) if h.bot_name != "" else String(h.look.get("display_name", h.name))
				var col2 := UiKit.DAWN if h.team == 0 else UiKit.DUSK
				var what := " lit a Lookout Lamp" if String(e.what) == "lamp_lit" else " put out a Lookout Lamp"
				hud.kill_feed.add_line([[who, col2], [what, UiKit.TEXT]], "status/keen")

var _crit_hit := {}                          # target id -> attacker id: the next attack damage is a shown crit

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
			if String(su.def.model) == "hero_azrael":
				azrael_fx.scythe_hit(su, tu)
	if not sees(tu):
		return
	# the hit of a critical strike already showed its red number
	if atk and int(_crit_hit.get(tu.id, -1)) == int(e.src):
		_crit_hit.erase(tu.id)
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
	# the element told in the numbers: a strong hit gets an up arrow in the element's colour, a resisted one a down arrow
	var em := float(e.get("emult", 1.0))
	if style != "" and absf(em - 1.0) > 0.01 and int(e.get("element", 0)) > 0:
		var ev = views.get(e.u)
		var ec: Color = SimConst.ELEMENT_COLORS[int(e.element)]
		var mark := "+25%" if em > 1.0 else "-25%"
		if not bool(e.get("dot", false)) or randf() < 0.25:
			bars.popup(mark, _head(tu.pos, (ev.bar_height if ev is UnitView else 2.2) + 0.15), ec if em > 1.0 else ec.darkened(0.35),
				13 if em > 1.0 else 11, 0.7, 0.7, Vector2(-34, 0))
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
	# units hidden by the fog or far outside the camera's view are not animated or moved this frame (heroes always are:
	# effects follow them); fog visibility is decided once per tick in _sync_views
	var vr := _view_rect()
	_frame_no += 1
	for v in views.values():
		if v is UnitView:
			v.visible = v.fog_ok and not _units_off and not (v.is_hero and _hide_heroes) and not (not v.is_hero and _hide_creeps)
			if not v.visible or (not v.is_hero and not vr.has_point(v.cur_pos)):
				v.offscreen = true
				if v.anim and v.anim.active:
					v.anim.active = false
				v.place()
				continue
			v.offscreen = false
			v.frame(alpha, dt, camera.cam, _frame_no)
	_t = _tm("views", _t)
	fx.frame(world, alpha, dt)
	_t = _tm("fx", _t)
	sludge_fx.update(world, alpha, dt)
	azrin_fx.update(world, alpha, dt)
	_t = _tm("fx_azrin", _t)
	var _c0 := Time.get_ticks_usec()
	froster_fx.update(world, alpha, dt)
	UiKit.draw_cost("fro_call", _c0)
	_t = _tm("fx_froster", _t)
	caziel_fx.update(world, alpha, dt)
	hero15_fx.update(world, alpha, dt)
	hero16_fx.update(world, alpha, dt)
	azrael_fx.update(world, alpha, dt)
	hero18_fx.update(world, alpha, dt)
	araki_fx.update(world, alpha, dt)
	item_fx.frame(dt)
	_t = _tm("fx_other", _t)
	status_fx.frame(dt)
	fortify_fx.frame(dt)
	orb_view.frame(dt)
	site_view.frame(dt)
	_t = _tm("status", _t)
	targeting_fx.frame()
	_t = _tm("target", _t)
	if _bench_until > 0.0:
		_bench_frame(dt)
	if spectator:
		_watch_camera(dt)
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
	# the attack range of every tower and fountain shows only while Alt is held (as the camps' spawn boxes do)
	fx.tower_ranges(world, world.get_unit(player_hero_id), player_team, camps != null and camps.boxes_wanted() 		or args.has("ranges"))
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

## The team whose sight the screen shows (-1: both teams or the whole map, see vision_mode).
func vis_team() -> int:
	return player_team if vision_mode < 0 else (vision_mode if vision_mode < 2 else -1)

## A unit is shown: in the sight of the team (or teams) the screen shows. That team's own units always are.
func sees(u: SimUnit) -> bool:
	if vision_mode == 3:
		return true
	var t := vis_team()
	if t < 0:
		return world.vision.sees(C.DAWN, u) or world.vision.sees(C.DUSK, u)
	return world.vision.sees(t, u)

func sees_cell(p: Vector2) -> bool:
	if vision_mode == 3 or world.vision.reveal_all:
		return true
	var t := vis_team()
	if t < 0:
		return world.vision.cell_visible(C.DAWN, p) or world.vision.cell_visible(C.DUSK, p)
	return world.vision.cell_visible(t, p)

## A team whose units are always shown (its own sight): the shown team; either team with both teams' sight.
func own_team(team: int) -> bool:
	if vision_mode >= 2:
		return team == C.DAWN or team == C.DUSK
	return team == vis_team()

var _fog_both := PackedByteArray()
var _fog_both_tick := -1

## The sight grid to draw (0/1 a cell, SimMap.VN square): one team's, both teams' (the two OR'd 8 cells at a time),
## or every cell (the Debug panel's reveal, or watching with the whole map).
func fog_bytes() -> PackedByteArray:
	var n := SimMap.VN
	if world.vision.reveal_all or vision_mode == 3:
		if _fog_all.size() != n * n:
			_fog_all.resize(n * n)
			_fog_all.fill(1)
		return _fog_all
	var t := vis_team()
	if t >= 0:
		return world.vision.visible[t]
	if _fog_both_tick != world.tick or _fog_both.size() != n * n:
		_fog_both_tick = world.tick
		var a := world.vision.visible[0].to_int64_array()
		var b := world.vision.visible[1].to_int64_array()
		for i in a.size():
			a[i] = a[i] | b[i]
		_fog_both = a.to_byte_array()
		for i in range(a.size() * 8, n * n):          # the tail that does not fill 8 bytes
			_fog_both.append(world.vision.visible[0][i] | world.vision.visible[1][i])
	return _fog_both

# ---- Watching an All-Bot match ---------------------------------------------------------------------------------------

## Watch another hero: its HUD, portrait, orders and (with "Hero's team" sight) its team's view. While you control a
## hero, watching another one gives yours back to its bot first.
func watch(hid: int, move_camera := true) -> void:
	var h := world.get_unit(hid)
	if h == null or not h.is_hero():
		return
	if controlling >= 0 and hid != controlling:
		give_back()
	player_hero_id = hid
	player_team = h.team
	selected_id = hid
	selected = [hid]
	_fog_tick = -1                          # redraw the fog now (the team may have changed)
	if move_camera:
		center_on_hero()

var _auto_next := 0.0

## Watching an All-Bot match: take over a bot's hero at any time (the Watching panel's "Take control"). You play it
## with every right a player has (orders, spells, items, shop, courier, glyph, chat, its gold and items, its team's
## sight); its bot sits out until you give it back (give_back), and the bot plays on from wherever you left it.
var _vision_watching := 2
var _cam_watching := "auto"

func take_control(hid := -1) -> void:
	if not watching_match or world == null or multiplayer_match:
		return
	if controlling >= 0:
		give_back()
	var h := world.get_unit(hid if hid >= 0 else player_hero_id)
	if h == null or not h.is_hero():
		return
	var b := world.bot_for(h.id)
	if b == null:
		return
	watch(h.id, true)
	b.human = true
	h.bot = false
	h.player = true
	h.auto_attack = true
	controlling = h.id
	spectator = false
	_vision_watching = vision_mode
	_cam_watching = cam_mode
	vision_mode = -1
	cam_mode = "free"
	_fog_tick = -1
	selected_id = h.id
	selected = [h.id]
	if hud and hud.has_method("error"):
		hud.error("You control %s" % SimTeamAI.hero_label(h))
	if watch_panel != null:
		watch_panel.refresh()

## Hand the hero you took over back to its bot; you watch again.
func give_back() -> void:
	if controlling < 0 or world == null:
		return
	var h := world.get_unit(controlling)
	var b := world.bot_for(controlling)
	controlling = -1
	if b != null:
		b.human = false
	if h != null:
		h.player = false
		h.bot = true
		h.to_buy.clear()
	spectator = true
	vision_mode = _vision_watching
	cam_mode = _cam_watching
	_fog_tick = -1
	if input != null and input.get("targeting") != null:
		input.targeting = ""
	if watch_panel != null:
		watch_panel.refresh()

## Watching: the camera mode ("free", "follow", "hero", "auto"). Hero view also shows the watched hero's team's sight
## and its orders; leaving it puts back the sight chosen before.
var _vision_before_hero := 2

func set_cam_mode(m: String) -> void:
	if m == cam_mode:
		return
	if m == "hero":
		_vision_before_hero = vision_mode
		vision_mode = -1
	elif cam_mode == "hero":
		vision_mode = _vision_before_hero
	cam_mode = m
	_auto_next = 0.0
	_fog_tick = -1
	if watch_panel != null:
		watch_panel.refresh()

## Watching: the camera follows the watched hero (Follow hero, Hero view) or the action (Auto: every few seconds the
## hero in the biggest fight, else the one in the most danger, is watched).
func _watch_camera(dt: float) -> void:
	if camera.user_moved:
		camera.user_moved = false
		if cam_mode != "free":
			set_cam_mode("free")
	if cam_mode == "auto":
		_auto_next -= dt
		if _auto_next <= 0.0:
			_auto_next = 4.0
			var best := _auto_pick()
			if best >= 0 and best != player_hero_id:
				watch(best, false)
	if cam_mode in ["follow", "hero", "auto"]:
		var h := world.get_unit(player_hero_id)
		if h != null:
			var p := View.to3(h.pos, terrain.height_at(h.pos))
			var k := 1.0 - exp(-dt * (5.0 if cam_mode == "auto" else 12.0))
			camera.target = camera.target.lerp(p, k)

## The hero most worth watching now: living heroes of both teams near it (enemies count most), hero damage in the
## last 3 s, low health; the watched hero gets a bonus so the camera does not flit.
func _auto_pick() -> int:
	var best := -1
	var best_score := -INF
	for h in world.heroes:
		if not h.alive:
			continue
		var score := 0.0
		for o in world.heroes:
			if o != h and o.alive and o.pos.distance_to(h.pos) < 1400.0:
				score += 3.0 if o.team != h.team else 1.0
		for t in h.hero_damage_log.values():
			if world.time - float(t) < 3.0:
				score += 2.0
				break
		score += (1.0 - h.hp / maxf(1.0, h.max_hp)) * 2.0
		score += h.networth() / 20000.0
		if h.id == player_hero_id:
			score += 1.5
		if score > best_score:
			best_score = score
			best = h.id
	return best

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
		var vis := fog_bytes()
		fog_img.set_data(n, n, false, Image.FORMAT_L8, vis)
		fog_tex.update(fog_img)
		_fog_blend = 0.0 if _capture_frames < 0 else 1.0
	_fog_blend = minf(1.0, _fog_blend + dt / 0.25)
	_fog_mat.set_shader_parameter("blend", _fog_blend)

# ---- Benchmark ------------------------------------------------------------------------------------------------------

var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_ticks: PackedInt32Array = PackedInt32Array()
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
	if args.has("fight"):
		_stage_fight(true)
	_bench_warm = 3.0
	_bench_until = float(args.bench)
	# the whole script frame: one node runs first and one last in _process and _physics_process
	for pri in [-100000, 100000]:
		var probe := BenchProbe.new()
		probe.first = pri < 0
		probe.process_priority = pri
		probe.process_physics_priority = pri
		add_child(probe)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

## --fight (bench): a teamfight. Every hero levelled to --lvl (default 16, the bots learn their kits) with the last items
## of its first bot build; the two teams face each other across the mid lane by the river, so the bots fight with every
## spell. Every --restage seconds (default 20) the dead come back and both teams are lined up again. The camera
## watches the middle of the fight rather than the player's hero.
var _fight_next := 0.0

func _stage_fight(first: bool) -> void:
	SimDebug.stage_fight(world, Vector2(-150, -150), int(args.get("lvl", "16")), first)
	for h in world.heroes:
		var v = views.get(h.id)
		if v is UnitView:
			v.prev_pos = h.pos
			v.cur_pos = h.pos
	_fight_next = world.time + float(args.get("restage", "20"))

func _bench_frame(dt: float) -> void:
	if args.has("fight"):
		if world.time >= _fight_next:
			_stage_fight(false)
		camera.focus(View.to3(Vector2(-150, -150), terrain.height_at(Vector2(-150, -150))))
		if _bench_warm > 0.0 and _bench_warm + dt >= 3.0:
			camera.zoom = float(args.get("zoom", "1.0"))
	var h := world.get_unit(player_hero_id)
	if h and not args.has("fight"):
		camera.focus(View.to3(h.pos, terrain.height_at(h.pos)))
	if _bench_warm > 0.0:
		_bench_warm -= dt
		Trail3D.cost_us = 0
		UnitBars.cost_us = 0
		UiKit.draw_us.clear()
		return
	_bench_frames.append(dt * 1000.0)
	if args.has("bench_shot") and _bench_frames.size() == 300:
		# --bench_shot=path: a picture of the benchmark scene (is the fight really on?)
		get_viewport().get_texture().get_image().save_png(String(args.bench_shot))
	var ph := BenchProbe.take_phys()
	_bench_ticks.append(ph.y)
	_bench_acc["script_proc"] = _bench_acc.get("script_proc", 0.0) + BenchProbe.proc_us / 1000.0
	_bench_acc["script_phys"] = _bench_acc.get("script_phys", 0.0) + ph.x / 1000.0
	if ph.y > 0:
		_bench_acc["n_tick_frames"] = _bench_acc.get("n_tick_frames", 0.0) + 1.0
	var vrid := get_viewport().get_viewport_rid()
	_bench_acc["gpu"] = _bench_acc.get("gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_bench_acc["rcpu"] = _bench_acc.get("rcpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vrid)
	_bench_acc["setup"] = _bench_acc.get("setup", 0.0) + RenderingServer.get_frame_setup_time_cpu()
	_bench_acc["other"] = _bench_acc.get("other", 0.0) + dt * 1000.0 - BenchProbe.proc_us / 1000.0 - ph.x / 1000.0
	_bench_acc["flush"] = _bench_acc.get("flush", 0.0) + BenchProbe.flush_us / 1000.0
	_bench_acc["draw"] = _bench_acc.get("draw", 0.0) + BenchProbe.draw_us / 1000.0
	_bench_acc["gap"] = _bench_acc.get("gap", 0.0) + BenchProbe.gap_us / 1000.0
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
		for k in UiKit.draw_us:
			_bench_acc["ui_" + String(k)] = UiKit.draw_us[k] / 1000.0
		var parts := []
		for k in _bench_acc:
			parts.append("%s %.2f" % [k, _bench_acc[k] / n])
		# frames that ran a simulation tick against frames that did not (the 30 Hz tick lands in one frame)
		var with_t := 0.0
		var nw := 0
		var without_t := 0.0
		var nwo := 0
		for fi in _bench_frames.size():
			if _bench_ticks[fi] > 0:
				with_t += _bench_frames[fi]
				nw += 1
			else:
				without_t += _bench_frames[fi]
				nwo += 1
		line += "\n  frames with a tick %d avg %.2f ms, without %d avg %.2f ms" % [nw, with_t / maxf(1, nw), nwo, without_t / maxf(1, nwo)]
		line += "\n  per-frame means: " + ", ".join(parts)
		print(line)
		if args.has("bench_units"):
			_bench_unit_costs()
		var f := FileAccess.open("res://work/bench.txt", FileAccess.WRITE)
		f.store_line(line)
		f = null
		if args.has("nullmats"):
			for vv in views.values():
				if vv is UnitView and vv.model:
					for mi: MeshInstance3D in vv.model.find_children("*", "MeshInstance3D", true, false):
						for si in (mi.mesh.get_surface_count() if mi.mesh else 0):
							if mi.get_active_material(si) == null:
								print("NULLMAT %s %s surface %d of %d" % [vv.key, mi.name, si, mi.mesh.get_surface_count()])
		if args.has("orphans"):
			for oid in Node.get_orphan_node_ids():
				var on = instance_from_id(oid)
				if on is MeshInstance3D:
					var mm: Mesh = on.mesh
					print("ORPHAN mesh %s aabb %s mat %s children %d" % [mm.get_class() if mm else "-", str(mm.get_aabb().size) if mm else "",
						str(on.material_override.get("shader").resource_path if on.material_override is ShaderMaterial and on.material_override.shader else on.material_override), on.get_child_count()])
		get_tree().quit()

## --bench_units: what each kind of unit costs to draw (mesh parts, surfaces, triangles at full detail and at the
## coarsest level of detail, shadow casters, bones), summed per model key.
func _bench_unit_costs() -> void:
	var per := {}
	for v in views.values():
		if not (v is UnitView) or (v as UnitView).model == null:
			continue
		var k := String(v.key)
		var e: Dictionary = per.get(k, {"n": 0, "parts": 0, "surf": 0, "tris": 0, "tris_low": 0, "shadow": 0, "bones": 0,
			"blend": 0})
		e.n += 1
		for mi: MeshInstance3D in (v as UnitView).model.find_children("*", "MeshInstance3D", true, false):
			if not mi.is_visible_in_tree() or mi.mesh == null:
				continue
			e.parts += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				e.shadow += 1
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
				e.blend += 1
			for s in mi.mesh.get_surface_count():
				e.surf += 1
				var sd := RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
				var idx: PackedByteArray = sd.get("index_data", PackedByteArray())
				var stride := 2 if (int(sd.get("vertex_count", 0)) <= 65535) else 4
				var tri := (idx.size() / stride) / 3 if idx.size() > 0 else int(sd.get("vertex_count", 0)) / 3
				e.tris += tri
				var lods: Array = sd.get("lods", [])
				if lods.is_empty():
					e.tris_low += tri
				else:
					var last: PackedByteArray = lods[lods.size() - 1].get("index_data", PackedByteArray())
					e.tris_low += (last.size() / stride) / 3
		if v.skeleton:
			e.bones += (v.skeleton as Skeleton3D).get_bone_count()
		per[k] = e
	for k in per:
		var e: Dictionary = per[k]
		print("UNITCOST %-22s x%3d  parts %3d  surf %3d  tris %7d  low %7d  shadow %3d  blend %2d  bones %3d" % [k, e.n,
			e.parts / e.n, e.surf / e.n, e.tris / e.n, e.tris_low / e.n, e.shadow / e.n, e.blend / e.n, e.bones / e.n])

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
	if args.has("shop"):
		# --shop=tab[,item[,search]]: the shop open in the base with some gold and a few parts owned
		var sv := String(args.shop).split(",")
		var sh := world.get_unit(player_hero_id)
		sh.pos = map.fountains[sh.team] + Vector2(250, 250) * (1.0 if sh.team == C.DAWN else -1.0)
		sh.gold_unreliable = 3200
		world.shop.buy(sh, "magic_wand")
		world.shop.buy(sh, "circlet")
		world.shop.buy(sh, "boots")
		hud.shop.visible = true
		hud.shop.tab = sv[0] if sv[0] != "" and sv[0] != "true" else "basics"
		if sv.size() > 1:
			hud.shop.selected = sv[1]
		if sv.size() > 2:
			hud.shop._search.text = sv[2]
	if args.has("endscreen"):
		world.winner = player_team
		menus._end_shown = true
		menus._show_end()
	if args.has("mvp"):
		# the MVP screen over the match as it stands (run 2026-10-19 e)
		world.winner = player_team
		menus._end_shown = true
		menus._mvp = MatchMvp.best(world)
		menus._show_mvp()
	if args.has("stats_tip"):
		hud.stats.pinned = true                  # the live stats panel's breakdown, as if hovered
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
	if args.has("items"):
		# --items=a,b,c: these items in the hero's slots (item effect captures)
		var ids := String(args.items).split(",")
		for i in mini(ids.size(), 6):
			h.inventory[i] = world.shop.new_item(String(ids[i]))
			h.inventory[i]["owner"] = h.id
		h.refresh_stats()
		h.mana = h.max_mana
	if args.has("treedemo"):
		_tree_demo_setup(h)
	if args.has("foe"):
		# --foe=x,y: the enemy hero stands still at that point (open-ground ability captures)
		var fv := String(args.foe).split(",")
		for b in world.bots.duplicate():
			if b.hero_id != player_hero_id:
				world.bots.erase(b)
		for eh in world.heroes:
			if eh.team != h.team:
				eh.pos = Vector2(float(fv[0]), float(fv[1]))
				world.orders.clear(eh)
				var ev = views.get(eh.id)
				if ev is UnitView:
					ev.prev_pos = eh.pos
					ev.cur_pos = eh.pos
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
	var first := true
	for aid in spec[0].split(","):
		var q := not first                       # later abilities in the list queue behind the first
		first = false
		if aid == "attack" and near:
			world.command(h.id, {"type": C.Order.ATTACK_UNIT, "target": near.id, "queue": q})
			continue
		if aid.begins_with("item:"):
			# item:N uses the item in slot N (on the nearest enemy when it needs a unit)
			var slot := int(aid.substr(5))
			var it = h.inventory[slot]
			if it == null:
				continue
			match world.abilities.item_target(String(it.id)):
				"unit":
					if near:
						world.command(h.id, {"type": C.Order.CAST_UNIT, "ability": "", "item_slot": slot, "target": near.id})
				"point":
					world.command(h.id, {"type": C.Order.CAST_POINT, "ability": "", "item_slot": slot, "point": near.pos if near else h.pos})
				_:
					world.command(h.id, {"type": C.Order.CAST_NO_TARGET, "ability": "", "item_slot": slot})
			continue
		var a := SimData.ability(aid)
		if a.is_empty():
			continue
		match String(a.behavior):
			"no_target", "toggle":
				world.command(h.id, {"type": C.Order.CAST_NO_TARGET, "ability": aid, "queue": q})
			"unit":
				if near:
					world.command(h.id, {"type": C.Order.CAST_UNIT, "ability": aid, "target": near.id, "queue": q})
			"point":
				var pt: Vector2 = near.pos if near else h.pos
				if args.has("aim") and near:
					pt = h.pos + (near.pos - h.pos).normalized() * float(args.aim)
				world.command(h.id, {"type": C.Order.CAST_POINT, "ability": aid, "point": pt, "queue": q})
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

## What the bots know of you (SimWorld.player_cards): your rank and MMR, your last game and whether you were its MVP.
static func _your_card() -> Dictionary:
	var me_p := Ranked.me()
	var lg: Dictionary = me_p.get("last_game", {})
	return {"rank": Ranked.rank_label(me_p), "tier": Ranked.tier_for(me_p), "mmr": int(me_p.get("mmr", 0)),
		"last_mvp": bool(lg.get("mvp", false)), "mvps": int(me_p.get("mvps", 0)),
		"last_kda": "%d/%d/%d" % [int(lg.get("k", 0)), int(lg.get("x", 0)), int(lg.get("a", 0))] if not lg.is_empty() else "",
		"games": int(me_p.get("wins", 0)) + int(me_p.get("losses", 0)), "prof": ProfileTalk.read(me_p)}
