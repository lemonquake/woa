extends Control
## The match HUD, laid out like Dota's: bottom panel (portrait, stats, abilities, health / mana, inventory, gold),
## minimap with fog and camera frame, top bar (clock, day / night, kills), shop, tooltips and announcements.
## It reads the simulation and issues the same commands as the keyboard (InputController).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order
const K = C.Kind
const U = preload("res://src/ui/ui_kit.gd")

var game: Node
var bottom: Control
var minimap: Control
var topbar: Control
var shop: Control
var tip: Control
var to_buy: Control
var kill_feed: KillFeed
var scoreboard: Scoreboard
var debug: DebugPanel
var chat: ChatPanel
var portrait_vp: SubViewport
var portrait_cam: Camera3D
var _msg := ""
var _msg_t := 0.0
var _announce := ""
var _announce_sub := ""
var _announce_t := 0.0
var _tip_lines: Array = []                 # [[text, size, color, kind]]
var card_rect := Rect2()                   # the selected unit's card (screen), while shown
var _tip_at := Vector2.ZERO
var _redraw_t := 0.0
var _last_tip: Array = []
var _portrait_down := -1.0                 # when the portrait was pressed (click: centre camera, hold: follow)
const PORTRAIT_HOLD := 0.3

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom = BottomPanel.new()
	bottom.hud = self
	add_child(bottom)
	minimap = Minimap.new()
	minimap.hud = self
	add_child(minimap)
	topbar = TopBar.new()
	topbar.hud = self
	add_child(topbar)
	shop = ShopPanel.new()
	shop.hud = self
	shop.visible = false
	add_child(shop)
	to_buy = ToBuyPanel.new()
	to_buy.hud = self
	add_child(to_buy)
	kill_feed = KillFeed.new()
	kill_feed.hud = self
	add_child(kill_feed)
	scoreboard = Scoreboard.new()
	scoreboard.hud = self
	add_child(scoreboard)
	debug = DebugPanel.new()
	debug.game = game
	add_child(debug)
	chat = ChatPanel.new()
	chat.hud = self
	add_child(chat)
	tip = Tip.new()
	tip.hud = self
	add_child(tip)
	_portrait()
	bottom.make_overlay()

func _portrait() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.size = Vector2(166, 170)
	bottom.add_child(svc)
	bottom.portrait_box = svc
	portrait_vp = SubViewport.new()
	portrait_vp.size = Vector2i(166, 170)
	portrait_vp.own_world_3d = false
	portrait_vp.transparent_bg = false
	portrait_vp.msaa_3d = Viewport.MSAA_4X
	portrait_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	svc.add_child(portrait_vp)
	portrait_cam = Camera3D.new()
	portrait_cam.fov = 26.0
	portrait_cam.near = 0.05
	portrait_cam.far = 14.0
	# the portrait sees only the shown unit's model (its own render layer), not the whole map: it used to draw the
	# world a second time each frame, about 460 draw calls and 2 ms in a teamfight
	portrait_cam.cull_mask = PORTRAIT_LAYER
	var env: Environment = game.atmosphere.env.duplicate() if game and game.get("atmosphere") else Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if env.sky != null else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	portrait_cam.environment = env
	portrait_vp.add_child(portrait_cam)

## The render layer only the portrait camera draws (layer 20); the shown unit's meshes carry it as well as layer 1.
const PORTRAIT_LAYER := 1 << 19
var _portrait_view: Node3D = null
var _portrait_flip := false
var _portrait_layer_t := 0.0

## Put the shown unit's meshes on the portrait layer (and take the last one's off). Rechecked every half second, so
## meshes added later (a new weapon, a hat) join it.
func _portrait_layers(v: Node3D, dt: float) -> void:
	_portrait_layer_t -= dt
	if v == _portrait_view and _portrait_layer_t > 0.0:
		return
	_portrait_layer_t = 0.5
	if _portrait_view != v and is_instance_valid(_portrait_view):
		for n in _portrait_view.find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers &= ~PORTRAIT_LAYER
	_portrait_view = v
	if v != null:
		for n in v.find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers |= PORTRAIT_LAYER

func hero() -> SimUnit:
	return game.world.get_unit(game.player_hero_id) if game and game.world else null

## The unit the bottom panel shows: the selected unit of any kind and team (a hero, creep, neutral, building, ward),
## otherwise your own hero. Your own courier shows through your hero's panel (its commands, see courier_shown).
func shown() -> SimUnit:
	if game == null or game.world == null:
		return null
	var s: SimUnit = game.world.get_unit(game.selected_id)
	var h := hero()
	if s != null and (s.alive or s.is_hero()) and s.kind != K.FOUNTAIN and not (h != null and s.id == h.courier_id):
		return s
	return h

## Portrait: a click selects your hero and centres the camera on it; holding it keeps the camera on the hero.
func portrait_press() -> void:
	_portrait_down = Time.get_ticks_msec() / 1000.0
	game.input.select([game.player_hero_id])

func portrait_release() -> void:
	if _portrait_down < 0.0:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _portrait_down
	_portrait_down = -1.0
	var h := hero()
	if held < PORTRAIT_HOLD and h and h.alive:
		game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))

func _follow_portrait(dt: float) -> void:
	if _portrait_down < 0.0:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		portrait_release()
		return
	if Time.get_ticks_msec() / 1000.0 - _portrait_down >= PORTRAIT_HOLD:
		var h := hero()
		if h and h.alive:
			var p := View.to3(h.pos, game.terrain.height_at(h.pos))
			game.camera.target = game.camera.target.lerp(p, 1.0 - exp(-dt * 14.0))

func _process(dt: float) -> void:
	_follow_portrait(dt)
	_msg_t = maxf(0.0, _msg_t - dt)
	_announce_t = maxf(0.0, _announce_t - dt)
	var vs := get_viewport_rect().size
	bottom.position = Vector2(roundf((vs.x - bottom.size.x) * 0.5), vs.y - BottomPanel.H)
	minimap.position = Vector2(20, vs.y - Minimap.S - 20)
	chat.position = Vector2(14, minimap.position.y - chat.size.y - 76)
	topbar.position = Vector2(roundf((vs.x - TopBar.W) * 0.5), 0)
	shop.position = Vector2(vs.x - ShopPanel.W - 10, vs.y - BottomPanel.H - ShopPanel.H - 8)
	# To Buy: at the right edge above the bottom panel, or left of the shop while it is open
	to_buy.visible = to_buy.wanted()
	var tbx: float = shop.position.x - ToBuyPanel.W - 8 if shop.visible else vs.x - ToBuyPanel.W - 10
	to_buy.position = Vector2(tbx, vs.y - BottomPanel.H - 72 - to_buy.size.y)
	_update_portrait(dt)
	_tip_lines = []
	queue_redraw()
	# panels redraw at 20 Hz (their contents change slowly); the tooltip follows the mouse every frame
	_redraw_t -= dt
	if _redraw_t <= 0.0:
		_redraw_t = 0.05
		for c in [bottom, minimap, topbar, shop]:
			c.queue_redraw()
	tip.queue_redraw()

func _update_portrait(dt: float) -> void:
	var h := shown()
	if h == null:
		return
	var v = game.views.get(h.id)
	if v == null or not (v is Node3D):
		return
	_portrait_layers(v, dt)
	# the portrait renders every other frame (its shadow pass still costs ~200 draw calls); a 166 px face at 30+ fps
	# looks the same
	_portrait_flip = not _portrait_flip
	if _portrait_flip and not game.args.has("noportrait"):
		portrait_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var sk: Skeleton3D = v.get("skeleton") if v is UnitView else null
	var bi := sk.find_bone("head") if sk != null else -1
	if bi < 0 and sk != null:
		bi = sk.find_bone("Head")                       # the Universal rig (Roydo, Blau)
	if bi < 0:
		_frame_portrait(v)
		return
	var head: Vector3 = (sk.global_transform * sk.get_bone_global_pose(bi)).origin + Vector3(0, 0.06, 0)
	var fwd: Vector3 = -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	portrait_cam.global_position = head + fwd * 1.15 + side * 0.25 + Vector3(0, 0.02, 0)
	portrait_cam.look_at(head - Vector3(0, 0.05, 0), Vector3.UP)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	UiKit.draw_cost("hud", t0)

func _draw_body() -> void:
	var vs := get_viewport_rect().size
	if _msg_t > 0.0:
		var a := clampf(_msg_t / 0.5, 0.0, 1.0)
		U.text_c(self, _msg, Vector2(vs.x * 0.5, vs.y - BottomPanel.H - 40), 22, Color(_msg_col, a), "bold")
	var h := hero()
	if h and not h.alive:
		var t := maxf(0.0, h.respawn_at - game.world.time)
		U.text_c(self, "Respawning in %d" % ceili(t), Vector2(vs.x * 0.5, vs.y * 0.42), 34, Color(1, 1, 1, 0.92), "title")
	if h and h.alive and not h.channel.is_empty():
		_channel_bar(h, vs)
	if game.multiplayer_match:
		_net_overlay(vs)
	if h and h.alive and (Input.is_key_pressed(KEY_SHIFT) or game.args.has("showqueue")) and game.input and game.input.hero_selected():
		_queue_waypoints(h)
	if game.input and game.input.targeting != "":
		var team: String = game.input.targeting_team()
		var lab: String = "Attack" if game.input.targeting == "attack" else ("Choose an enemy" if team == "enemy" else ("Choose a target" if team == "any" else "Choose an ally or a place"))
		var tcol := Color(1.0, 0.55, 0.5) if team == "enemy" else Color(0.6, 1.0, 0.6)
		U.text(self, lab, get_viewport().get_mouse_position() + Vector2(26, 34), 15, tcol, "bold")

## Multiplayer: the round trip to the server under the clock, the connection's state when it is not smooth, and who
## paused the game.
func _net_overlay(vs: Vector2) -> void:
	var n = game.net
	if n != null and NetSession.inst != null:
		var ping: int = NetSession.inst.my_ping()
		var pc := Color(0.55, 0.95, 0.55) if ping < 90 else (Color(1.0, 0.85, 0.35) if ping < 170 else Color(1.0, 0.45, 0.4))
		var txt := "Hosting" if NetSession.inst.is_server() else "Ping %d ms" % ping
		U.text_c(self, txt, Vector2(vs.x * 0.5, 100), 13, pc if not NetSession.inst.is_server() else U.TEXT_DIM, "bold")
		var st := String(n.status)
		if st != "":
			var f := U.font("bold")
			var tw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			var r := Rect2(vs.x * 0.5 - tw * 0.5 - 24, 116, tw + 48, 40)
			U.skin(self, "panel_tip", r)
			U.text_c(self, st, r.get_center() + Vector2(0, 7), 20, Color(1.0, 0.85, 0.45), "bold")
	if game.world.paused:
		var r2 := Rect2(vs.x * 0.5 - 260, vs.y * 0.3, 520, 96)
		U.skin(self, "panel_card", r2)
		U.text_c(self, "Game Paused", r2.position + Vector2(260, 44), 34, U.GOLD, "title")
		var by := "Paused by %s. " % game.paused_by if game.paused_by != "" else ""
		U.text_c(self, by + "Esc opens the menu to unpause.", r2.position + Vector2(260, 76), 16, U.TEXT, "body")

## Shift held: the hero's current order and its queue as waypoints joined by a line, as in Dota (green move,
## red attack, blue spell or item, gold hold), numbered in the order they will run.
func _queue_waypoints(h: SimUnit) -> void:
	var w: SimWorld = game.world
	var cam: Camera3D = game.camera.cam
	var orders: Array = []
	if h.order != O.NONE:
		orders.append({"type": h.order, "target": h.order_target, "point": h.order_point, "ability": h.order_ability})
	orders.append_array(h.order_queue)
	if orders.is_empty():
		return
	var prev := h.pos
	var prev_s := cam.unproject_position(View.to3(h.pos, game.terrain.height_at(h.pos)))
	var n := 0
	for o in orders:
		var type := int(o.get("type", O.NONE))
		var p := prev
		var t := w.get_unit(int(o.get("target", -1)))
		if type in [O.ATTACK_UNIT, O.MOVE_TO_UNIT, O.CAST_UNIT] and t:
			p = t.pos
		elif type in [O.MOVE, O.ATTACK_MOVE, O.CAST_POINT]:
			p = o.get("point", prev)
		var col := Color(0.35, 1.0, 0.45)
		if type in [O.ATTACK_UNIT, O.ATTACK_MOVE]:
			col = Color(1.0, 0.35, 0.3)
		elif type in [O.CAST_NO_TARGET, O.CAST_POINT, O.CAST_UNIT]:
			col = Color(0.4, 0.7, 1.0)
		elif type == O.HOLD:
			col = Color(1.0, 0.82, 0.3)
		var wp := View.to3(p, game.terrain.height_at(p))
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		n += 1
		if sp.distance_to(prev_s) > 4.0:
			draw_dashed_line(prev_s, sp, Color(col, 0.9), 3.0, 10.0)
		draw_circle(sp, 13.0, Color(0, 0, 0, 0.55))
		draw_arc(sp, 13.0, 0, TAU, 24, col, 3.0)
		var aid := String(o.get("ability", ""))
		var ic: Texture2D = U.ability_icon(aid) if aid != "" and aid != "tp" else null
		if ic:
			draw_texture_rect(ic, Rect2(sp + Vector2(10, -26), Vector2(20, 20)), false)
		U.text_c(self, str(n), sp + Vector2(0, 6), 15, Color(1, 1, 1), "bold")
		prev = p
		prev_s = sp

## Dota's channel bar: the ability being channelled and the time left, just above the bottom panel.
func _channel_bar(h: SimUnit, vs: Vector2) -> void:
	var aid := String(h.channel.ability)
	var total := C.TP_CHANNEL if aid == "tp" else float(h.channel.get("dur", 1.0))
	var left := maxf(0.0, float(h.channel.until) - game.world.time)
	var name := "Teleport" if aid == "tp" else String(SimData.ability(aid).get("name", aid))
	var r := Rect2(vs.x * 0.5 - 160, vs.y - BottomPanel.H - 58, 320, 18)
	U.panel(self, r.grow(4), U.GOLD_DIM, 4)
	U.bar(self, r, 1.0 - left / maxf(0.01, total), Color(0.95, 0.78, 0.3))
	U.text_c(self, "%s   %.1f" % [name, left], r.get_center() + Vector2(0, 6), 14, U.TEXT, "bold")

func error(msg: String) -> void:
	_msg = msg
	_msg_col = Color(1.0, 0.35, 0.3)
	_msg_t = 2.0

## A neutral message in the same place as errors.
func notice(msg: String) -> void:
	_msg = msg
	_msg_col = Color(0.75, 0.95, 0.75)
	_msg_t = 2.0

var _msg_col := Color(1.0, 0.35, 0.3)

func announce(title: String, sub := "", col := U.GOLD) -> void:
	kill_feed.banner(title, sub, col)

## A team chat line (bots and you), from the world's "chat" event.
func on_chat(e: Dictionary) -> void:
	chat.add(e)

func on_kill(e: Dictionary) -> void:
	kill_feed.on_hero_kill(e, game.world, game.player_team)

func _name(u: SimUnit) -> String:
	if u == null:
		return "?"
	if u.is_hero():
		return u.who()
	return String(u.look.get("display_name", u.name))

func toggle_shop() -> void:
	shop.visible = not shop.visible

## The shop closes when you click anywhere else (the world, the minimap, the top bar) or press Esc, as in Dota. Clicks
## on the bottom panel (items, stash, the Shop button) and the To Buy list keep it open, since they work with the shop.
## The click itself still does its usual job (a right click on the ground still moves the hero).
func _input(e: InputEvent) -> void:
	# the item menu closes on a click anywhere else, or Esc
	if bottom and bottom.item_menu_open():
		if e is InputEventMouseButton and e.pressed:
			var mp := (e as InputEventMouseButton).position
			if not bottom.item_menu_rect().has_point(mp - bottom.global_position):
				bottom.close_item_menu()
		elif e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
			bottom.close_item_menu()
			get_viewport().set_input_as_handled()
			return
	if shop == null or not shop.visible:
		return
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var p := (e as InputEventMouseButton).position
		var on_shop := shop.get_global_rect().has_point(p) or (to_buy.visible and to_buy.get_global_rect().has_point(p))
		if on_shop or bottom.get_global_rect().has_point(p) or bottom.covers_extra(p - bottom.global_position):
			return
		shop.visible = false
	elif e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		shop.visible = false
		get_viewport().set_input_as_handled()

func toggle_debug() -> void:
	debug.toggle()

## Whether a screen point is over a HUD element (the held right click does not order through it).
func over_hud(p: Vector2) -> bool:
	for c: Control in [bottom, minimap, topbar]:
		if c.get_global_rect().has_point(p):
			return true
	if minimap._has_point(p - minimap.global_position):
		return true
	if bottom.covers_extra(p - bottom.global_position):
		return true
	if shop.visible and shop.get_global_rect().has_point(p):
		return true
	if to_buy.visible and to_buy.get_global_rect().has_point(p):
		return true
	return debug.covers(p)

## A unit without a head bone (buildings, wards, some creeps): the camera frames its height from the front of the
## game camera's view, a little above.
func _frame_portrait(v: Node3D) -> void:
	var hgt := maxf(0.6, float(v.get("bar_height")) if v.get("bar_height") != null else 2.0)
	var base := v.global_position
	var target := base + Vector3(0, hgt * 0.55, 0)
	var fwd: Vector3 = -game.camera.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var dist := hgt * 1.9 + 0.6
	portrait_cam.global_position = target - fwd * dist + Vector3(0, hgt * 0.35, 0)
	portrait_cam.look_at(target, Vector3.UP)

## What a creep, neutral, building or ward can do, as skill slots for the bottom panel: its spells (with cooldowns),
## auras, attack effects (crit, splash, on-hit disables), true sight, a building's protection. Each entry:
## {name, icon, desc, kind ("Aura", "Passive", ...), cd_key, cooldown}.
func unit_skills(u: SimUnit) -> Array:
	var out: Array = []
	var d: Dictionary = u.def
	for aid in d.get("abilities", []):
		var a := SimData.ability(String(aid))
		if a.is_empty():
			continue
		out.append({"name": String(a.name), "icon": String(U.ABILITY_ICONS.get(aid, U.NEUTRAL_SKILL_ICONS.get(aid, "skills/keen_eye"))),
			"desc": String(a.desc), "kind": "Spell", "cd_key": String(aid), "cooldown": float(a.cooldown[0])})
	for au in d.get("auras", []):
		var parts: Array = []
		for k in au.stats:
			parts.append(_stat_text(String(k), float(au.stats[k])))
		var desc := "Allies within %d get %s." % [int(au.radius), ", ".join(parts)]
		if au.has("hero_stats"):
			var hp: Array = []
			for k in au.hero_stats:
				hp.append(_stat_text(String(k), float(au.hero_stats[k])))
			desc += " Heroes get %s." % ", ".join(hp)
		out.append({"name": String(au.name), "icon": "status/aura_might", "desc": desc, "kind": "Aura"})
	if d.has("crit"):
		var cr: Dictionary = d.crit
		out.append({"name": String(cr.name), "icon": "skills/lethality", "kind": "Passive",
			"desc": "%d%% chance for an attack to deal %d%% damage." % [roundi(float(cr.chance) * 100.0), roundi(float(cr.mult) * 100.0)]})
	if d.has("splash"):
		var sp: Dictionary = d.splash
		out.append({"name": String(sp.name), "icon": "skills/cleave", "kind": "Passive",
			"desc": "Attacks hit every enemy within %d of the target for %d%% damage." % [int(sp.radius), roundi(float(sp.pct) * 100.0)]})
	if d.has("on_hit"):
		var oh: Dictionary = d.on_hit
		var what := "disarms the target (no attacks)" if oh.get("disarm", false) else "breaks the target (no passives)"
		out.append({"name": String(oh.name), "icon": "status/sundered" if oh.get("break", false) else "status/weakened",
			"kind": "Passive", "cd_key": "on_hit", "cooldown": float(oh.cooldown),
			"desc": "An attack %s for %s seconds, once every %s seconds." % [what, str(oh.dur), str(oh.cooldown)]})
	if d.has("true_sight") and float(d.true_sight) > 0.0:
		out.append({"name": "True Sight", "icon": "status/keen", "kind": "Passive",
			"desc": "Sees invisible units within %d." % int(d.true_sight)})
	if u.kind == K.WARD and float(d.vision_day) > 0.0:
		out.append({"name": "Sight", "icon": "status/spirit_ward", "kind": "Passive",
			"desc": "Gives its team sight within %d. Invisible." % int(d.vision_day)})
	if u.is_building():
		out.append({"name": "Backdoor Protection", "icon": "status/fortified", "kind": "Passive",
			"desc": "Takes much less damage and heals while no enemy creeps are near it."})
		if u.kind == K.TOWER or u.kind == K.ANCIENT or u.kind == K.BARRACKS:
			out.append({"name": "Fortify", "icon": "status/shielded", "kind": "Team",
				"desc": "When its team uses Fortify, it cannot be hurt for 7 seconds; tier 2+ towers also splash, shoot faster and mark what they hit."})
	if bool(d.get("ancient", false)):
		out.append({"name": "Ancient", "icon": "status/titan", "kind": "Passive",
			"desc": "An ancient creep: some spells and items cannot target it, and Gold Glove cannot take it."})
	if bool(d.get("flying", false)):
		out.append({"name": "Flying", "icon": "status/windstep", "kind": "Passive",
			"desc": "Flies over trees and cliffs."})
	return out.slice(0, Keybinds.MAX_ABILITIES)

func _stat_text(k: String, v: float) -> String:
	var names := {"move_speed": "move speed", "base_damage_pct": "base damage", "magic_resist": "magic resistance",
		"armor": "armor", "attack_speed": "attack speed", "hp_regen": "health regen", "mana_regen": "mana regen",
		"lifesteal": "lifesteal"}
	var nm := String(names.get(k, k.replace("_", " ")))
	if k.ends_with("_pct") or k == "magic_resist" or k == "lifesteal":
		return "%+d%% %s" % [roundi(v * 100.0), nm]
	return "%+d %s" % [roundi(v), nm] if absf(v - roundf(v)) < 0.01 else "%+.1f %s" % [v, nm]

## A plain name for what kind of unit it is (the bottom panel's side column).
func kind_name(u: SimUnit) -> String:
	match u.kind:
		K.HERO: return "Hero"
		K.CREEP_MELEE, K.CREEP_RANGED, K.CREEP_FLAG: return "Lane creep"
		K.CREEP_SIEGE: return "Siege creep"
		K.NEUTRAL_CREEP: return "Ancient creep" if bool(u.def.get("ancient", false)) else "Neutral creep"
		K.TOWER: return "Tower"
		K.BARRACKS: return "Barracks"
		K.ANCIENT: return "Throne"
		K.FILLER: return "Building"
		K.WARD: return "Ward"
		K.COURIER: return "Courier"
	return "Unit"

## Facts about a unit for the bottom panel's item well: what it is worth and how it sees.
func unit_facts(u: SimUnit) -> Array:
	var out: Array = []
	var d: Dictionary = u.def
	out.append(["Level", str(u.level)])
	if int(d.gold_max) > 0:
		out.append(["Bounty", "%d-%d gold" % [int(d.gold_min), int(d.gold_max)], U.GOLD])
	elif String(d.get("bounty_key", "")) != "":
		out.append(["Bounty", "team gold", U.GOLD])
	if float(d.xp) > 0.0:
		out.append(["Experience", str(int(d.xp)), Color(0.75, 0.6, 1.0)])
	out.append(["Sight day / night", "%d / %d" % [int(u.vision_day), int(u.vision_night)]])
	var rates: Vector4 = game.world.regen_rates(u)
	out.append(["Health regen", "%.1f" % rates.x])
	if u.max_mana > 0.0:
		out.append(["Mana regen", "%.1f" % rates.y])
	if u.is_building() and u.is_invulnerable():
		out.append(["Invulnerable", "yes", Color(1.0, 0.75, 0.4)])
	elif u.is_building() and u.backdoor_active:
		out.append(["Backdoor protection", "on", Color(0.6, 0.85, 1.0)])
	if u.kind == K.NEUTRAL_CREEP and u.upgrade > 0:
		out.append(["Grown", "x%d" % u.upgrade])
	return out

## Tooltip content for this frame (drawn by Tip).
# ---- Element, weapon and armor: chips and the unit sheet -------------------------------------------------------------

const ELEMENT_ICONS := ["ui/info", "status/burning", "status/wet", "status/frozen", "skills/ground_fissure",
	"status/shocked", "status/regen", "status/cursed", "skills/radiant_ward"]

static func pct(v: float) -> String:
	var s := snappedf(v * 100.0, 0.1)
	return ("%d%%" % int(s)) if is_equal_approx(s, roundf(s)) else ("%.1f%%" % s)

## Elements this one beats (x1.25) and is beaten by (x0.75) when attacking.
static func element_attack_text(el: int) -> Array:
	var strong: Array = []
	var weak: Array = []
	for d in range(1, C.ELEMENT_NAMES.size()):
		var m := C.element_mult(el, d)
		if m > 1.0:
			strong.append(C.ELEMENT_NAMES[d])
		elif m < 1.0:
			weak.append(C.ELEMENT_NAMES[d])
	return [strong, weak]

## Elements that hurt this one more (x1.25) and that it resists (x0.75).
static func element_defense_text(el: int) -> Array:
	var weak: Array = []
	var resist: Array = []
	for a in range(1, C.ELEMENT_NAMES.size()):
		var m := C.element_mult(a, el)
		if m > 1.0:
			weak.append(C.ELEMENT_NAMES[a])
		elif m < 1.0:
			resist.append(C.ELEMENT_NAMES[a])
	return [weak, resist]

static func _join(a: Array) -> String:
	return "none" if a.is_empty() else ", ".join(a)

## Tooltip lines wrapped to `width` pixels.
static func wrapped(text: String, size: int, col: Color, kind := "body", width := 380.0) -> Array:
	var out: Array = []
	for s in U.wrap(text, width, size, kind):
		out.append([s, size, col, kind])
	return out

func element_tip(u: SimUnit) -> Array:
	var el := u.element
	var lines: Array = [["Element: " + String(C.ELEMENT_NAMES[el]), 17, C.ELEMENT_COLORS[el], "title"]]
	if el == C.Element.NONE:
		lines.append_array(wrapped("No element: deals and takes normal damage from every element.", 13, U.TEXT))
		return lines
	var at := element_attack_text(el)
	var df := element_defense_text(el)
	lines.append_array(wrapped("Its attacks and spells deal 125%% to %s, 75%% to %s." % [_join(at[0]), _join(at[1])], 13, U.TEXT))
	lines.append_array(wrapped("It takes 125%% from %s, 75%% from %s." % [_join(df[0]), _join(df[1])], 13, U.TEXT))
	return lines

func weapon_tip(u: SimUnit) -> Array:
	var wpn := u.weapon
	var lines: Array = [["Damage type: " + String(C.WEAPON_NAMES[wpn]), 17, U.GOLD, "title"]]
	var parts: Array = []
	for a in C.ARMOR_NAMES.size():
		parts.append("%s %s" % [C.ARMOR_NAMES[a], pct(C.damage_mult(wpn, a))])
	lines.append_array(wrapped("Its attacks deal: " + ", ".join(parts) + ".", 13, U.TEXT))
	if wpn == C.Weapon.MAGIC:
		lines.append_array(wrapped("Magic attacks are reduced by magic resistance, not armor.", 12, U.TEXT_DIM))
	lines.append_array(wrapped("Spells: magic damage uses Magic, pure damage uses Aether; physical spell damage only meets armor.", 12, U.TEXT_DIM))
	return lines

func armor_tip(u: SimUnit) -> Array:
	var at := u.armor_type
	var lines: Array = [["Armor type: " + String(C.ARMOR_NAMES[at]), 17, U.GOLD, "title"]]
	var parts: Array = []
	for wp in C.WEAPON_NAMES.size():
		parts.append("%s %s" % [C.WEAPON_NAMES[wp], pct(C.damage_mult(wp, at))])
	lines.append_array(wrapped("It takes: " + ", ".join(parts) + ".", 13, U.TEXT))
	lines.append(["Armor %.1f: physical damage taken x%.2f" % [u.armor, C.armor_multiplier(u.armor)], 13, U.TEXT, "body"])
	return lines

## The full sheet for the stats hover: attack, defense, amplification.
func unit_sheet(u: SimUnit) -> Array:
	var w: SimWorld = game.world
	var lines: Array = []
	var dmg := "%d-%d" % [int(u.dmg_min), int(u.dmg_max)] + (" +%d" % int(u.bonus_damage) if u.bonus_damage > 0.0 else "")
	lines.append(["Attack", 17, U.GOLD, "title"])
	lines.append(["Damage %s   %s   %s" % [dmg, C.WEAPON_NAMES[u.weapon], C.ELEMENT_NAMES[u.element]], 14, U.TEXT, "body"])
	if u.can_attack_at_all():
		lines.append(["Attack speed %d (%.2f s)   Range %d" % [int(u.attack_speed), u.attack_interval(), int(u.attack_range)], 14, U.TEXT, "body"])
	lines.append(["Defense", 17, U.GOLD, "title"])
	lines.append(["Armor %.1f (%s): physical damage taken x%.2f" % [u.armor, C.ARMOR_NAMES[u.armor_type], C.armor_multiplier(u.armor)], 14, U.TEXT, "body"])
	var mr := "Magic resistance %s" % pct(u.magic_resist)
	if u.is_hero():
		mr += "  (intelligence %s)" % pct(u.int_total * C.INT_MAGIC_RESIST)
	lines.append([mr, 14, U.TEXT, "body"])
	if u.element != C.Element.NONE:
		var df := element_defense_text(u.element)
		lines.append(["Takes 125%% from %s" % _join(df[0]), 14, Color(1.0, 0.55, 0.45), "body"])
		lines.append(["Takes 75%% from %s" % _join(df[1]), 14, Color(0.55, 0.9, 0.6), "body"])
	if u.element_resist_loss() > 0.0:
		lines.append(["Elemental resistance -%s" % pct(u.element_resist_loss()), 14, Color(1.0, 0.45, 0.4), "body"])
	var defs: Array = []
	if u.evasion > 0.0:
		defs.append("Evasion " + pct(u.evasion))
	if u.status_resist > 0.0:
		defs.append("Status resistance " + pct(u.status_resist))
	if u.slow_resist > 0.0:
		defs.append("Slow resistance " + pct(u.slow_resist))
	if not defs.is_empty():
		lines.append(["   ".join(defs), 14, U.TEXT, "body"])
	lines.append(["Amplification", 17, U.GOLD, "title"])
	var ma := "Magic Amp %s" % pct(u.magic_amp)
	if u.is_hero():
		ma += "  (intelligence %s, items %s)" % [pct(u.magic_amp_int), pct(u.magic_amp_items)]
	lines.append([ma, 14, Color(0.6, 0.8, 1.0), "body"])
	if u.is_hero() and u.item_magic_amps().size() > 1:
		lines.append(["Magic amp from items: each one counts half as much as the one before.", 12, U.TEXT_DIM, "body"])
	var amps: Array = ["Spell Amp " + pct(u.spell_amp)]
	amps.append("Healing Amp " + pct(u.heal_amp))
	amps.append("Mana Regen Amp " + pct(u.mana_regen_amp))
	lines.append(["   ".join(amps), 14, U.TEXT, "body"])
	var more: Array = []
	if u.cast_speed > 0.0:
		more.append("Cast Speed " + pct(u.cast_speed))
	if u.mana_cost_cut > 0.0:
		more.append("Mana Cost -" + pct(u.mana_cost_cut))
	if u.cast_range_bonus > 0.0:
		more.append("Cast Range +%d" % roundi(u.cast_range_bonus))
	if u.lifesteal > 0.0 or u.lifesteal_ability > 0.0:
		more.append("Lifesteal " + pct(u.lifesteal + u.lifesteal_ability))
	if u.spell_lifesteal > 0.0:
		more.append("Spell Lifesteal " + pct(u.spell_lifesteal))
	if not more.is_empty():
		lines.append(["   ".join(more), 14, U.TEXT, "body"])
	var r: Vector4 = w.regen_rates(u)
	lines.append(["Health regen %.1f + %.1f   Mana regen %.1f + %.1f" % [r.z, r.x - r.z, r.w, r.y - r.w], 13, U.TEXT_DIM, "body"])
	var burns: Array = w.status.dots_on(u)
	if not burns.is_empty():
		var tot := 0.0
		for b in burns:
			tot += float(b.dps)
		lines.append(["Burning: %d damage per second" % int(tot), 14, Color(1.0, 0.55, 0.2), "bold"])
	return lines

## Three chips: element, damage type, armor type (each with its own hover explanation). Returns the next x.
func draw_type_chips(ci: CanvasItem, u: SimUnit, at: Vector2, h := 22.0) -> float:
	var x := at.x
	var m := ci.get_local_mouse_position()
	var chips := [
		[ELEMENT_ICONS[u.element], String(C.ELEMENT_NAMES[u.element]), C.ELEMENT_COLORS[u.element], "element"],
		["ui/level", String(C.WEAPON_NAMES[u.weapon]) + " attack", Color(0.95, 0.75, 0.5), "weapon"],
		["status/fortified", String(C.ARMOR_NAMES[u.armor_type]) + " armor", Color(0.7, 0.8, 0.95), "armor"]]
	for c in chips:
		var tw := U.font("bold").get_string_size(String(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var r := Rect2(Vector2(x, at.y), Vector2(tw + 34.0, h))
		ci.draw_rect(r, Color(0.04, 0.045, 0.06, 0.92))
		ci.draw_rect(r, (c[2] as Color).darkened(0.25), false, 1.5)
		var ic: Texture2D = U.icon(String(c[0]))
		if ic:
			ci.draw_texture_rect(ic, Rect2(r.position + Vector2(4, 3), Vector2(h - 6, h - 6)), false, c[2])
		U.text(ci, String(c[1]), r.position + Vector2(h + 2, h - 6), 13, c[2], "bold")
		if r.has_point(m):
			var tip: Array
			match String(c[3]):
				"element":
					tip = element_tip(u)
				"weapon":
					tip = weapon_tip(u)
				_:
					tip = armor_tip(u)
			show_tip(ci.get_global_mouse_position(), tip)
		x = r.end.x + 6.0
	return x

func show_tip(at: Vector2, lines: Array) -> void:
	_tip_lines = lines
	_last_tip = lines
	_tip_at = at

# ======================================================================================================================

class BottomPanel extends Control:
	## Laid out like Dota's: the hero's name above the portrait, the level in a circle at the portrait's lower left
	## with the experience ring round it and an experience bar along the portrait's foot; stats; the talent tree
	## button left of the abilities; health and mana; six item slots, the backpack and the Teleport slot; gold, Shop,
	## Courier. The stash sits above the items (shown when it holds something, in the base, or with the shop open).
	## With your courier selected the panel shows the courier: its commands and what it carries.
	## Items: click uses, drag moves (to another slot, the stash, the ground, an ally hero or your courier), right
	## click moves to or from the backpack.
	const W := 1140.0                          # with four skill slots; wider with more (see _layout)
	const H := 206.0
	const PORTRAIT := Rect2(14, 24, 166, 170)
	const ABIL_X := 404.0
	const ABIL_STEP := 80.0
	const ABIL_SIZE := 72.0
	const ABIL_Y := 30.0
	const PIPS_Y := 107.0                      # the carved level tray under each ability (console art), 14 high
	const BARS_Y := 134.0                      # health bar; mana 30 below
	const ITEM_X := 734.0
	const SIDE_X := 986.0
	const TALENT_C := Vector2(374, 70)
	const STASH_Y := -58.0
	const CHIPS_X := 192.0                     # element / damage type / armor type, above the stats column
	const CHIPS_Y := -14.0
	const BUFF_Y := -4.0                       # the buff bar's lowest row ends here (it grows upward)
	var _chips_end := CHIPS_X
	var _buff_rects: Array = []                # the buff bar's icons (local), for hover and clicks
	# the layout for the shown unit's skill count (Keybinds.MAX_ABILITIES at most): console width, slot step and
	# size, and where the items and the gold column start
	var n_slots := 4
	var pw := W
	var abil_step := ABIL_STEP
	var abil_size := ABIL_SIZE
	var item_x := ITEM_X
	var side_x := SIDE_X
	const INNATE := Rect2(366, 126, 28, 28)    # the innate skill, between the stats and the health well
	const COURIER_CMDS := [["return", "Return to Base", "ui/back", "ability_1", "Home"], ["retrieve", "Retrieve Items", "ui/load", "ability_2", "Retrieve"],
		["stash", "Return Items to Stash", "ui/save", "ability_3", "To Stash"], ["deliver", "Deliver Items", "ui/teleport", "ability_4", "Deliver"],
		["transfer", "Transfer Items", "ui/split", "item_1", "Transfer"], ["burst", "Speed Burst", "status/haste", "item_2", "Burst"],
		["shield", "Shield", "status/shielded", "item_3", "Shield"], ["auto", "Auto Deliver", "ui/check", "item_4", "Auto"]]
	var hud
	var portrait_box: Control
	var overlay: Control                       # drawn above the 3D portrait: name, level, experience
	var _abil_rects: Array = []
	var _was_cooling := {}
	var _ready_at := {}
	var _learn_rects: Array = []
	var _item_rects: Array = []
	var _stash_rects: Array = []
	var _grab_rect := Rect2()
	var _cmd_rects: Array = []
	var _shop_rect := Rect2()
	var _tp_rect := Rect2()
	var _courier_rect := Rect2()
	var _buyback_rect := Rect2()
	var _talent_rect := Rect2()
	var talents_open := false
	var _talent_rows: Array = []               # [rect, tier, side]
	# drag and drop of items
	var _press_slot := -1                      # 0..8 inventory, 100+ stash
	var _press_at := Vector2.ZERO
	var _dragging := false

	func _ready() -> void:
		size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_layout()

	func make_overlay() -> void:
		overlay = PortraitOverlay.new()
		overlay.panel = self
		add_child(overlay)

	## Slot step and size for n skills, and how much wider than the four-slot console the panel is (the console art
	## hud_console_<n> from tools/ui_skin.py console_layout() has the same numbers).
	static func slot_layout(n: int) -> Vector3:
		n = clampi(n, 4, Keybinds.MAX_ABILITIES)
		var step: float = {7: 72.0, 8: 66.0, 9: 62.0, 10: 58.0}.get(n, 80.0)
		return Vector3(step, step - 8.0, n * step - 4.0 * ABIL_STEP)

	func _layout(n := 4) -> void:
		n_slots = clampi(n, 4, Keybinds.MAX_ABILITIES)
		var sl := slot_layout(n_slots)
		abil_step = sl.x
		abil_size = sl.y
		pw = W + sl.z
		item_x = ITEM_X + sl.z
		side_x = SIDE_X + sl.z
		size = Vector2(pw, H)
		if overlay:
			overlay.size = size
		_abil_rects.clear()
		_learn_rects.clear()
		for i in n_slots:
			var r := Rect2(ABIL_X + i * abil_step, PIPS_Y - 5.0 - abil_size, abil_size, abil_size)
			_abil_rects.append(r)
			_learn_rects.append(Rect2(r.get_center().x - minf(16.0, abil_size * 0.5 - 2.0), 3, minf(32.0, abil_size - 4.0), 22))
		_item_rects.clear()
		for i in 6:
			_item_rects.append(Rect2(item_x + (i % 3) * 80, 30 + (i / 3) * 62, 74, 56))
		for i in 3:
			_item_rects.append(Rect2(item_x + i * 80, 158, 74, 36))
		_stash_rects.clear()
		for i in 6:
			_stash_rects.append(Rect2(item_x + i * 40, STASH_Y + 14, 36, 30))
		_grab_rect = Rect2(item_x + 244, STASH_Y + 14, 64, 30)
		_cmd_rects.clear()
		for i in 8:
			_cmd_rects.append(Rect2(ABIL_X + (i % 4) * ABIL_STEP, 30 + (i / 4) * 62, ABIL_SIZE, 56))
		_shop_rect = Rect2(side_x, 132, 140, 62)
		_tp_rect = Rect2(side_x, 96, 70, 32)
		_courier_rect = Rect2(side_x + 74, 96, 66, 32)
		_buyback_rect = Rect2(ABIL_X, BARS_Y, n_slots * abil_step - 8.0, 50)
		_talent_rect = Rect2(TALENT_C - Vector2(22, 22), Vector2(44, 44))

	## The courier when it is what the player has selected (the panel then shows it).
	func courier_shown() -> SimUnit:
		var h: SimUnit = hud.hero()
		if h == null:
			return null
		var c: SimUnit = hud.game.world.get_unit(h.courier_id)
		if c != null and hud.game.selected_id == c.id:
			return c
		return null

	func stash_visible(h: SimUnit) -> bool:
		if h == null or h.id != hud.game.player_hero_id:
			return false
		if hud.shop.visible:
			return false                       # the open shop shows the stash itself
		return h.stash.any(func(x): return x != null) or hud.game.world.shop.in_shop(h)

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("BottomPanel", t0)

	func _draw_body() -> void:
		_buff_rects = []
		var h: SimUnit = hud.shown()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		var cour := courier_shown()
		var mine: bool = h.id == hud.game.player_hero_id
		var n := 4 if cour != null else slot_count(h)
		if clampi(n, 4, Keybinds.MAX_ABILITIES) != n_slots:
			_layout(n)
		# the sculpted console (an enemy's panel is tinted red, a neutral's amber)
		var tint := Color.WHITE
		if not mine and h.team != hud.game.player_team:
			tint = Color(1.0, 0.86, 0.66) if h.team == C.NEUTRAL else Color(1.0, 0.78, 0.74)
		U.art(self, "hud_console" if n_slots <= 4 else "hud_console_%d" % n_slots, Vector2.ZERO, tint)
		if portrait_box:
			portrait_box.position = PORTRAIT.position
			portrait_box.visible = cour == null
			portrait_box.modulate = Color(1, 1, 1) if h.alive else Color(0.35, 0.35, 0.38)
		if cour != null:
			_courier_panel(h, cour, w)
			_gold(h)
			_tp_and_courier(h, w)
			_buff_bar(cour, w)
			if overlay:
				overlay.queue_redraw()
			return
		if not h.is_hero():
			_unit_view(h, w)
			_buff_bar(h, w)
			if overlay:
				overlay.queue_redraw()
			return
		_stats(h)
		_talent_button(h, w)
		_innate(h)
		_abilities(h, w)
		_bars(h)
		_items(h, w)
		if mine:
			_stash(h, w)
			_gold(h)
			_tp_and_courier(h, w)
			if not h.alive:
				_buyback(h, w)
		else:
			U.text(self, "Viewing " + ("an ally" if h.team == hud.game.player_team else "the enemy"), Vector2(side_x, 70), 15, U.TEXT_DIM, "bold")
			U.text(self, Keybinds.key_name("select_hero") + " or the portrait:", Vector2(side_x, 94), 12, U.TEXT_DIM, "body")
			U.text(self, "back to your hero", Vector2(side_x, 110), 12, U.TEXT_DIM, "body")
		_buff_bar(h, w)
		if talents_open:
			_talent_tree(h, w)
		if mine:
			_draw_item_menu(h)
		if _dragging and _press_slot >= 0:
			var it = _drag_item(h)
			if it != null:
				var ic: Texture2D = U.held_item_icon(it)
				if ic:
					draw_texture_rect(ic, Rect2(get_local_mouse_position() - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.85))
		if overlay:
			overlay.queue_redraw()

	## The buff bar (BuffBar) over the skills: from the type chips' end (or the first skill) to just short of the
	## items, its lowest row resting on the console's top edge.
	func _buff_bar(u: SimUnit, w: SimWorld) -> void:
		var x0 := maxf(ABIL_X, _chips_end + 10.0)
		_buff_rects = BuffBar.draw(self, hud, u, w, x0, item_x - 20.0, BUFF_Y)

	## How many skill slots the shown unit needs: a hero's skills (its innate one sits apart), or what a creep or
	## building can do (spells, auras, attack effects, true sight).
	func slot_count(u: SimUnit) -> int:
		if u.is_hero():
			return u.abilities.size()
		return hud.unit_skills(u).size()

	## The innate skill (Growing Gut): a small slot between the stats and the health bar, with its tooltip.
	func _innate(h: SimUnit) -> void:
		var aid := String(h.def.get("innate", ""))
		if aid == "":
			return
		var ic: Texture2D = U.ability_icon(aid)
		draw_rect(INNATE.grow(-1), Color(0.04, 0.05, 0.08))
		if ic:
			draw_texture_rect(ic, INNATE.grow(-3), false)
		U.skin(self, "slot_small", INNATE.grow(2), Color.WHITE, false)
		if INNATE.has_point(get_local_mouse_position()):
			hud.show_tip(get_global_mouse_position(), _innate_tip(h, aid))

	## An innate skill's tooltip: always learned from level 1; values that grow with hero level show their value now.
	func _innate_tip(h: SimUnit, aid: String) -> Array:
		var a := SimData.ability(aid)
		var lines: Array = [[String(a.name), 20, U.GOLD, "title"], ["Innate: always learned, from level 1", 13, U.TEXT_DIM, "body"]]
		for l in U.wrap(String(a.desc), 330, 15):
			lines.append([l, 15, U.TEXT, "body"])
		var ab: SimAbilities = hud.game.world.abilities
		for k in a.values:
			if String(k).ends_with("_per_level") or not (a.values as Dictionary).has(String(k) + "_per_level"):
				continue
			var now := ab.val(h, aid, k) + ab.val(h, aid, String(k) + "_per_level") * float(h.level)
			var txt := ("%.2f%%" % (now * 100.0)) if absf(now) < 1.0 else ("%.1f" % now)
			lines.append(["%s at level %d: %s" % [String(k).replace("_", " ").capitalize(), h.level, txt], 14, Color(0.8, 0.85, 0.75), "body"])
		lines.append(["Grows with hero level" if (a.values as Dictionary).keys().any(func(x): return String(x).ends_with("_per_level"))
			else "Always on", 12, U.TEXT_DIM, "body"])
		return lines

	# ---- A unit that is not a hero (creep, neutral, building, ward, someone else's courier) ----------------------

	## Laid out like a hero: stats with the type chips and the full sheet, its skills in the ability slots, health and
	## mana with regeneration, and in place of the items what it is worth and what it can do.
	func _unit_view(u: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		# stats column
		var x := 196.0
		var y := 44.0
		var dmg := "%d-%d" % [int(u.dmg_min), int(u.dmg_max)] if u.can_attack_at_all() else "-"
		if u.can_attack_at_all() and u.bonus_damage > 0.0:
			dmg += " +%d" % int(u.bonus_damage)
		_stat_row("ui/level", dmg, Vector2(x, y))
		_stat_row("status/fortified", "%.1f" % u.armor, Vector2(x, y + 24))
		_stat_row("status/haste", str(int(u.move_speed)) if u.move_speed > 0.0 else "-", Vector2(x, y + 48))
		U.art_rect(self, "divider", Rect2(x - 2, y + 58, 160, 12), Color(1, 1, 1, 0.8))
		_chips_end = hud.draw_type_chips(self, u, Vector2(CHIPS_X, CHIPS_Y))
		var rows := []
		if u.can_attack_at_all():
			rows.append(["Range", str(int(u.attack_range))])
			rows.append(["Attacks/s", "%.2f" % (1.0 / maxf(0.01, u.attack_interval()))])
		rows.append(["Magic res.", "%d%%" % roundi(u.magic_resist * 100.0)])
		for i in rows.size():
			U.text(self, String(rows[i][0]), Vector2(x, y + 84 + i * 18), 12, U.TEXT_DIM, "body")
			U.text_r(self, String(rows[i][1]), Vector2(x + 160, y + 84 + i * 18), 13, U.TEXT, "bold")
		if Rect2(x - 4, y - 18, 170, 160).has_point(m):
			hud.show_tip(get_global_mouse_position(), hud.unit_sheet(u))
		# skills
		var skills: Array = hud.unit_skills(u)
		for i in mini(n_slots, skills.size()):
			_unit_skill(u, w, skills[i], _abil_rects[i], m)
		for i in range(skills.size(), n_slots):
			draw_rect((_abil_rects[i] as Rect2).grow(-2), Color(0.03, 0.035, 0.05, 0.6))
		_bars(u)
		# worth and status in the item well
		var ir := Rect2(item_x - 2, 28, 246, 168)
		U.skin(self, "panel_dark", ir)
		var info: Array = hud.unit_facts(u)
		var iy := ir.position.y + 22
		for line in info:
			U.text(self, String(line[0]), Vector2(ir.position.x + 12, iy), 13, U.TEXT_DIM, "body")
			U.text_r(self, String(line[1]), Vector2(ir.end.x - 12, iy), 13, line[2] if line.size() > 2 else U.TEXT, "bold")
			iy += 19
			if iy > ir.end.y - 6:
				break
		# side column: whose it is and how to get back to your hero (its effects are in the buff bar)
		var team_col := U.DAWN if u.team == C.DAWN else (U.DUSK if u.team == C.DUSK else Color(0.95, 0.8, 0.4))
		var who := "Neutral" if u.team == C.NEUTRAL else String(C.TEAM_NAMES[u.team])
		U.text(self, who, Vector2(side_x, 52), 17, team_col, "title")
		var rel := "Enemy"
		if u.team == C.NEUTRAL:
			rel = "Neutral"
		elif u.team == hud.game.player_team:
			rel = "Ally"
		U.text(self, (rel + "  ·  " if rel != who else "") + hud.kind_name(u), Vector2(side_x, 72), 12, U.TEXT_DIM, "bold")
		U.text(self, Keybinds.key_name("select_hero") + " or the portrait:", Vector2(side_x, 150), 12, U.TEXT_DIM, "body")
		U.text(self, "back to your hero", Vector2(side_x, 166), 12, U.TEXT_DIM, "body")

	## One of a unit's skills: icon, cooldown sweep, a gold frame, the tooltip.
	func _unit_skill(u: SimUnit, w: SimWorld, sk: Dictionary, r: Rect2, m: Vector2) -> void:
		draw_rect(r.grow(-2), Color(0.04, 0.05, 0.08))
		var ic: Texture2D = U.icon(String(sk.icon))
		if ic:
			draw_texture_rect(ic, r.grow(-5), false, Color(1, 1, 1) if u.alive else Color(0.4, 0.4, 0.4))
		var cd_key := String(sk.get("cd_key", ""))
		var total := float(sk.get("cooldown", 0.0))
		if cd_key != "" and total > 0.0:
			var left := maxf(0.0, float(u.ability_ready.get(cd_key, C.LONG_AGO)) - w.time)
			if left > 0.0:
				U.cooldown(self, r, clampf(left / total, 0.0, 1.0), left)
		U.skin(self, "slot_ability", r.grow(4), Color(1.25, 1.2, 1.05) if r.has_point(m) else Color.WHITE, false)
		if String(sk.get("kind", "")) != "":
			var kr := Rect2(r.position + Vector2(2, r.size.y - 16), Vector2(r.size.x - 4, 14))
			draw_rect(kr, Color(0, 0, 0, 0.55))
			U.text_c(self, String(sk.kind), kr.get_center() + Vector2(0, 4), 10, U.TEXT_DIM, "bold")
		if r.has_point(m):
			var lines: Array = [[String(sk.name), 20, U.GOLD, "title"]]
			if String(sk.get("kind", "")) != "":
				lines.append([String(sk.kind), 13, U.TEXT_DIM, "body"])
			for l in U.wrap(String(sk.desc), 330, 15):
				lines.append([l, 15, U.TEXT, "body"])
			if total > 0.0:
				lines.append(["Cooldown: %s" % str(total), 13, Color(0.6, 0.75, 1.0), "body"])
			hud.show_tip(get_global_mouse_position(), lines)

	# ---- Portrait overlay: name plate, level circle with the experience ring, experience bar -------------------

	func draw_overlay(ci: CanvasItem) -> void:
		var h: SimUnit = hud.shown()
		if h == null:
			return
		var cour := courier_shown()
		var unit: SimUnit = cour if cour != null else h
		# name plate above the portrait, like Dota's
		var nm := "Courier" if cour != null else String(h.def.get("name", h.name))
		var f := U.font("title")
		# the portrait's heavy frame, drawn over the 3D view
		U.skin(ci, "slot_ability", PORTRAIT.grow(6), Color.WHITE, false)
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var plate := Rect2(PORTRAIT.get_center().x - maxf(tw + 34, 120) * 0.5, -16, maxf(tw + 34, 120), 30)
		U.skin(ci, "btn_dark_normal", plate)
		U.text_c(ci, nm, plate.get_center() + Vector2(0, 7), 17, U.GOLD, "title")
		if cour != null:
			_courier_portrait(ci, h, cour)
			return
		if not h.is_hero():
			# a creep or building: its level in the badge, no experience
			var uc := Vector2(PORTRAIT.position.x + 24, PORTRAIT.end.y - 22)
			ci.draw_circle(uc, 23, Color(0.025, 0.028, 0.04, 0.97))
			U.art_rect(ci, "ring_level", Rect2(uc - Vector2(28, 28), Vector2(56, 56)))
			U.text_c(ci, str(h.level), uc + Vector2(0, 8), 22, U.GOLD, "title")
			if not h.alive:
				U.text_c(ci, "Dead", PORTRAIT.get_center() + Vector2(0, 8), 22, Color(1, 0.6, 0.55), "title")
			return
		# experience bar along the portrait's foot, always readable
		var need := 0.0
		var have := 0.0
		var frac := 1.0
		if h.level < C.MAX_LEVEL:
			need = float(C.XP_TABLE[h.level]) - float(C.XP_TABLE[h.level - 1])
			have = h.xp - float(C.XP_TABLE[h.level - 1])
			frac = clampf(have / maxf(1.0, need), 0.0, 1.0)
		var xr := Rect2(PORTRAIT.position.x + 50, PORTRAIT.end.y - 19, PORTRAIT.size.x - 54, 14)
		U.bar(ci, xr, frac, Color(0.65, 0.42, 1.0))
		var xt := "Max level" if h.level >= C.MAX_LEVEL else "%d / %d" % [int(have), int(need)]
		U.text_c(ci, xt, xr.get_center() + Vector2(0, 5), 11, U.TEXT, "bold")
		# level badge at the lower left: a studded gold ring with the experience arc inside
		var c := Vector2(PORTRAIT.position.x + 24, PORTRAIT.end.y - 22)
		ci.draw_circle(c, 23, Color(0.025, 0.028, 0.04, 0.97))
		ci.draw_arc(c, 18, 0, TAU, 48, Color(0.16, 0.13, 0.22), 4.0, true)
		ci.draw_arc(c, 18, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(0.72, 0.5, 1.0), 4.0, true)
		U.art_rect(ci, "ring_level", Rect2(c - Vector2(28, 28), Vector2(56, 56)))
		U.text_c(ci, str(h.level), c + Vector2(0, 8), 22, U.GOLD, "title")
		if h.ability_points > 0 and h.id == hud.game.player_hero_id:
			var bp := c + Vector2(20, -20)
			U.art_rect(ci, "glow_gold", Rect2(bp - Vector2(16, 16), Vector2(32, 32)), Color(1, 1, 1, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)))
			U.art_rect(ci, "gem_gold", Rect2(bp - Vector2(11, 11), Vector2(22, 22)))
			U.text_c(ci, str(h.ability_points), bp + Vector2(0, 5), 13, Color(0.12, 0.07, 0.0), "bold", false)
		var m := ci.get_local_mouse_position()
		if c.distance_to(m) < 24 or xr.has_point(m):
			var lines: Array = [["Level %d" % h.level, 18, U.GOLD, "title"]]
			if h.level < C.MAX_LEVEL:
				lines.append(["Experience %d / %d (%d to level %d)" % [int(have), int(need), int(need - have), h.level + 1], 14, U.TEXT, "body"])
			lines.append(["Total experience %d" % int(h.xp), 13, U.TEXT_DIM, "body"])
			if h.ability_points > 0:
				lines.append(["%d ability point%s to spend" % [h.ability_points, "" if h.ability_points == 1 else "s"], 13, Color(1.0, 0.85, 0.4), "body"])
			hud.show_tip(ci.get_global_mouse_position(), lines)

	func _courier_portrait(ci: CanvasItem, h: SimUnit, c: SimUnit) -> void:
		var r := PORTRAIT
		ci.draw_rect(r, Color(0.07, 0.08, 0.1))
		var ic: Texture2D = U.icon("status/windstep")
		if ic:
			ci.draw_texture_rect(ic, Rect2(r.get_center() - Vector2(48, 58), Vector2(96, 96)), false, U.GOLD if c.alive else Color(0.35, 0.35, 0.35))
		var state := "Dead: back in %ds" % ceili(c.respawn_at - hud.game.world.time) if not c.alive else _state_name(c.courier_state)
		U.text_c(ci, state, Vector2(r.get_center().x, r.end.y - 34), 14, U.TEXT, "bold")
		U.text_c(ci, ("Flying" if c.has_flag("flying") else "Walking") + "  speed %d" % int(c.move_speed), Vector2(r.get_center().x, r.end.y - 14), 12, U.TEXT_DIM, "body")
		var lc := Vector2(r.position.x + 22, r.position.y + 22)
		ci.draw_circle(lc, 18, Color(0.03, 0.03, 0.04, 0.96))
		ci.draw_arc(lc, 18, 0, TAU, 32, U.GOLD_DIM, 1.5, true)
		U.text_c(ci, str(h.level), lc + Vector2(0, 7), 18, U.GOLD, "bold")

	static func _state_name(s: String) -> String:
		return {"idle": "Waiting", "move": "Moving", "return": "Going home", "retrieve": "Fetching the stash",
			"fetch": "Fetching the stash", "collect": "Picking up items", "deliver": "Delivering", "transfer": "Delivering",
			"stash": "Returning items"}.get(s, s.capitalize())

	# ---- Stats, talents, abilities, bars ---------------------------------------------------------------------------

	func _stats(h: SimUnit) -> void:
		var x := 196.0
		var y := 44.0
		var dmg := "%d-%d" % [int(h.dmg_min), int(h.dmg_max)]
		if h.bonus_damage > 0.0:
			dmg += " +%d" % int(h.bonus_damage)
		_stat_row("ui/level", dmg, Vector2(x, y))
		_stat_row("status/fortified", "%.1f" % h.armor, Vector2(x, y + 24))
		_stat_row("status/haste", str(int(h.move_speed)), Vector2(x, y + 48))
		var r := Rect2(x - 4, y + 64, 152, 64)
		U.art_rect(self, "divider", Rect2(x - 2, y + 58, 160, 12), Color(1, 1, 1, 0.8))
		_chips_end = hud.draw_type_chips(self, h, Vector2(CHIPS_X, CHIPS_Y))
		var attrs := [["attributes/strength", h.str_total, Color(0.95, 0.35, 0.3)], ["attributes/agility", h.agi_total, Color(0.4, 0.95, 0.45)],
			["attributes/intelligence", h.int_total, Color(0.4, 0.7, 1.0)]]
		for i in 3:
			var a: Array = attrs[i]
			var p := Vector2(x + 2 + i * 50, y + 72)
			var ic: Texture2D = U.icon(a[0])
			if ic:
				draw_texture_rect(ic, Rect2(p, Vector2(22, 22)), false, a[2])
			U.text(self, str(int(a[1])), p + Vector2(2, 44), 16, U.TEXT, "bold")
		if Rect2(r.position + Vector2(0, -72), Vector2(150, 136)).has_point(get_local_mouse_position()):
			hud.show_tip(get_global_mouse_position(), hud.unit_sheet(h))

	func _regen_line(h: SimUnit) -> Array:
		var r: Vector4 = hud.game.world.regen_rates(h)
		return ["Health regen %.1f + %.1f bonus   Mana regen %.1f + %.1f bonus" % [r.z, r.x - r.z, r.w, r.y - r.w], 14,
			U.TEXT, "body"]

	func _stat_row(ic_path: String, val: String, p: Vector2) -> void:
		var ic: Texture2D = U.icon(ic_path)
		if ic:
			draw_texture_rect(ic, Rect2(p + Vector2(0, -15), Vector2(18, 18)), false, U.GOLD)
		U.text(self, val, p + Vector2(24, 0), 16, U.TEXT, "bold")

	## Dota's talent tree button: lit while a talent can be learned.
	func _talent_button(h: SimUnit, w: SimWorld) -> void:
		var tree: Array = h.def.get("talents", [])
		if tree.is_empty():
			return
		var can := false
		for t in tree.size():
			if w.abilities.can_learn_talent(h, t):
				can = true
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0) if can and h.id == hud.game.player_hero_id else 0.0
		if pulse > 0.0:
			U.art_rect(self, "glow_gold", Rect2(TALENT_C - Vector2(40, 40), Vector2(80, 80)), Color(1, 1, 1, pulse))
		draw_circle(TALENT_C, 21, Color(0.03, 0.035, 0.05))
		U.art_rect(self, "ring_portrait", Rect2(TALENT_C - Vector2(26, 26), Vector2(52, 52)))
		var ic: Texture2D = U.icon("ui/favorite")
		if ic:
			draw_texture_rect(ic, Rect2(TALENT_C - Vector2(13, 13), Vector2(26, 26)), false, U.GOLD if h.talents.size() > 0 or can else Color(0.55, 0.55, 0.55))
		U.text_c(self, "Talents", TALENT_C + Vector2(0, 38), 11, U.TEXT_DIM, "bold")
		if _talent_rect.has_point(get_local_mouse_position()) and not talents_open:
			var tl: Array = [["Talents", 18, U.GOLD, "title"],
				["Click to open. At levels 10, 15, 20 and 25 spend an ability point on one of two talents.", 14, U.TEXT, "body"]]
			# Dota shows the hero's innate skill with the talents
			var inn := String(h.def.get("innate", ""))
			if inn != "":
				tl.append(["", 8, U.TEXT, "body"])
				tl.append_array(_innate_tip(h, inn))
			hud.show_tip(get_global_mouse_position(), tl)

	## The open tree: level 25 at the top, each row a choice of two.
	func _talent_tree(h: SimUnit, w: SimWorld) -> void:
		var tree: Array = h.def.get("talents", [])
		_talent_rows.clear()
		if tree.is_empty():
			return
		var tw := 520.0
		var rh := 40.0
		var top := -(tree.size() * (rh + 6) + 44)
		var r := Rect2(TALENT_C.x - tw * 0.5 + 60, top, tw, tree.size() * (rh + 6) + 36)
		U.skin(self, "panel_card", r.grow(6))
		U.text(self, "Talents", r.position + Vector2(14, 22), 16, U.GOLD, "title")
		var m := get_local_mouse_position()
		for row in tree.size():
			var tier: int = tree.size() - 1 - row
			var y := r.position.y + 30 + row * (rh + 6)
			var lvl := int(C.TALENT_LEVELS[tier])
			var lc := Vector2(r.get_center().x, y + rh * 0.5)
			draw_circle(lc, 17, Color(0.05, 0.05, 0.06))
			draw_arc(lc, 17, 0, TAU, 32, U.GOLD_DIM, 1.5, true)
			U.text_c(self, str(lvl), lc + Vector2(0, 6), 15, U.GOLD if h.level >= lvl else U.TEXT_DIM, "bold")
			var can: bool = w.abilities.can_learn_talent(h, tier) and h.id == hud.game.player_hero_id
			for side in 2:
				var tid := String(tree[tier][side])
				var tr := Rect2(r.position.x + 10 + side * (tw * 0.5 + 12), y, tw * 0.5 - 32, rh)
				if side == 1:
					tr.position.x = lc.x + 22
				var picked := String(h.talents.get(tier, "")) == tid
				var other := h.talents.has(tier) and not picked
				var sk := "btn_dark_normal"
				if picked:
					sk = "btn_gold_normal"
				elif can and tr.has_point(m):
					sk = "btn_hover"
				elif can:
					sk = "btn_normal"
				U.skin(self, sk, tr, Color(1, 1, 1, 1.0) if not other else Color(0.6, 0.6, 0.6))
				var nm := String(SimData.talent(tid).get("name", tid))
				var tc := Color(0.12, 0.07, 0.0) if picked else (Color(0.45, 0.45, 0.45) if other else U.TEXT)
				U.text_c(self, nm, tr.get_center() + Vector2(0, 5), 14, tc, "bold")
				_talent_rows.append([tr, tier, side])
		# the innate skill, named at the tree's title (hover it for the full text)
		var inn := String(h.def.get("innate", ""))
		if inn != "":
			var ir := Rect2(r.end.x - 200, r.position.y + 4, 192, 24)
			var iic: Texture2D = U.ability_icon(inn)
			if iic:
				draw_texture_rect(iic, Rect2(ir.position + Vector2(0, 1), Vector2(22, 22)), false)
			U.text(self, "Innate: " + String(SimData.ability(inn).name), ir.position + Vector2(28, 17), 13, U.TEXT, "bold")
			if ir.has_point(m):
				hud.show_tip(get_global_mouse_position(), _innate_tip(h, inn))

	func _abilities(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		hud.game.input.hover_ability = ""
		var count := h.abilities.size()
		for i in mini(n_slots, count):
			var aid: String = h.abilities[i]
			var a := SimData.ability(aid)
			var r: Rect2 = _abil_rects[i]
			var lv := h.ability_level_of(aid)
			var auto := bool(h.autocast.get(aid, false))
			var toggled := bool(h.toggles.get(aid, false))
			var ic: Texture2D = U.ability_icon(aid)
			var col := Color(1, 1, 1) if lv > 0 else Color(0.32, 0.32, 0.34)
			var mana_cost := float(a.mana[maxi(lv - 1, 0)])
			if lv > 0 and h.mana < mana_cost:
				col = Color(0.45, 0.55, 1.0)
			draw_rect(r.grow(-2), Color(0.04, 0.05, 0.08))
			if ic:
				draw_texture_rect(ic, r.grow(-5), false, col)
			if lv > 0:
				var cd := w.abilities.cooldown_left(h, aid)
				var total := float(a.cooldown[lv - 1])
				if cd > 0.0 and total > 0.0:
					U.cooldown(self, r, cd / total, cd)
					_was_cooling[aid] = true
				elif _was_cooling.get(aid, false):
					_was_cooling[aid] = false
					_ready_at[aid] = Time.get_ticks_msec() / 1000.0
				var since := Time.get_ticks_msec() / 1000.0 - float(_ready_at.get(aid, -9.0))
				if since < 0.5:
					# ready again: a flash and a golden bloom round the slot
					var k := 1.0 - since / 0.5
					draw_rect(r.grow(-4), Color(1.0, 1.0, 0.9, 0.5 * k))
					U.art_rect(self, "glow_gold", r.grow(22.0 * k + 8.0), Color(1, 1, 1, k))
			# the gold frame over the icon; lit while targeting, toggled or on autocast
			var lit: bool = auto or toggled or hud.game.input.targeting == aid
			var t := Time.get_ticks_msec() / 1000.0
			if lit:
				var tcol := Color(0.55, 1.0, 0.45) if toggled else Color(1.0, 0.85, 0.3)
				U.art_rect(self, "glow_gold" if not toggled else "glow_blue", r.grow(14), Color(tcol, 0.55 + 0.35 * sin(t * 6.0)))
			U.skin(self, "slot_ability", r.grow(4), Color(1.25, 1.2, 1.05) if lit or r.has_point(m) else Color.WHITE, false)
			var kr := Rect2(r.position + Vector2(2, 2), Vector2(20, 18))
			draw_rect(kr, Color(0, 0, 0, 0.6))
			U.text_c(self, Keybinds.key_name(Keybinds.slot_action(i, count)), kr.get_center() + Vector2(0, 6), 13, Color(1, 1, 1), "bold")
			if mana_cost > 0:
				U.text_r(self, str(int(mana_cost)), r.end + Vector2(-3, -4), 12, Color(0.55, 0.75, 1.0), "bold")
			var learnable: bool = w.abilities.can_learn(h, aid) and h.id == hud.game.player_hero_id
			_level_pips(r, lv, int(a.max_level), learnable)
			if learnable:
				var lr: Rect2 = _learn_rects[i]
				var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 200.0)
				U.art_rect(self, "glow_gold", lr.grow(10), Color(1, 1, 1, pulse * 0.7))
				U.skin(self, "btn_gold_hover" if lr.has_point(m) else "btn_gold_normal", lr)
				U.text_c(self, "+", lr.get_center() + Vector2(0, 8), 22, Color(0.12, 0.07, 0.0), "bold", false)
			if r.has_point(m):
				hud.show_tip(get_global_mouse_position(), _ability_tip(h, aid, i))
				hud.game.input.hover_ability = aid

	## The level pips in the carved tray under an ability slot: one bar per level, gold when learned, the next one
	## glowing while a point can go into it, dark sockets for the rest.
	func _level_pips(r: Rect2, lv: int, mx: int, learnable: bool) -> void:
		if mx <= 0:
			return
		var tray := Rect2(r.position.x + 6, PIPS_Y + 4, r.size.x - 12, 6)
		var gap := 4.0
		var pip_w := (tray.size.x - gap * (mx - 1)) / mx
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		for k in mx:
			var p := Rect2(tray.position.x + k * (pip_w + gap), tray.position.y, pip_w, tray.size.y)
			if k < lv:
				U.art_rect(self, "glow_gold", p.grow(5), Color(1, 1, 1, 0.35))
				draw_rect(p, Color(0.86, 0.62, 0.2))
				draw_rect(Rect2(p.position, Vector2(p.size.x, 2)), Color(1.0, 0.93, 0.62))
				draw_rect(Rect2(p.position + Vector2(0, p.size.y - 1), Vector2(p.size.x, 1)), Color(0.5, 0.32, 0.08))
			elif k == lv and learnable:
				# the level a point can go into next: a dark socket with a pulsing gold rim (never filled like a
				# learned level)
				U.art_rect(self, "glow_gold", p.grow(6), Color(1, 1, 1, 0.2 + 0.45 * pulse))
				draw_rect(p, Color(0.1, 0.08, 0.04))
				draw_rect(p.grow(0.5), Color(1.0, 0.86, 0.45, 0.55 + 0.45 * pulse), false, 1.5)
			else:
				draw_rect(p, Color(0.09, 0.1, 0.13))
				draw_rect(p, Color(0.42, 0.34, 0.2, 0.9), false, 1.0)

	func _ability_tip(h: SimUnit, aid: String, slot := -1) -> Array:
		var a := SimData.ability(aid)
		var lv := h.ability_level_of(aid)
		if aid == "pilot_turret" and hud.game.world.abilities.kits3.is_piloting(h):
			# inside: the same button gets him out
			return [["Leave Turret", 20, U.GOLD, "title"], ["No target", 13, U.TEXT_DIM, "body"],
				["Blau climbs out of the turret. Moving does the same.", 15, U.TEXT, "body"]]
		var lines: Array = [[String(a.name), 20, U.GOLD, "title"]]
		var kind := {"autocast_attack": "Attack modifier (autocast)", "point": "Point target", "passive": "Passive",
			"unit": "Unit target", "no_target": "No target", "toggle": "Toggle"}
		var team := String(a.get("target_team", "enemy"))
		var aim := ""
		if String(a.behavior) in ["unit", "point", "autocast_attack"]:
			aim = "    Targets: " + ("enemies" if team == "enemy" else ("allies" if team == "ally" else "any unit"))
		lines.append([String(kind.get(a.behavior, "")) + aim + "    Level %d / %d" % [lv, int(a.max_level)], 13, U.TEXT_DIM, "body"])
		for l in U.wrap(String(a.desc), 330, 15):
			lines.append([l, 15, U.TEXT, "body"])
		for k in a.values:
			if k in a.get("hidden_values", []):
				continue                           # tuning numbers the description already covers
			var vals: Array = a.values[k]
			var parts := []
			for v in vals:
				var fv := float(v)
				parts.append(("%d%%" % roundi(fv * 100.0)) if fv > 0.0 and fv < 1.0 and (k.contains("slow") or k.ends_with("pct") or k.contains("chance") or k == "lifesteal" or k.contains("resist") or k.contains("vision")) else str(v))
			lines.append(["%s: %s" % [k.replace("_", " ").capitalize(), " / ".join(parts)], 13, Color(0.8, 0.85, 0.75), "body"])
		if String(a.behavior) in ["point", "unit"] or (String(a.behavior) == "no_target" and float(a.get("range", 0.0)) > 0.0):
			# the range the hero casts from now (talents, upgrades, Long Lens and other cast range bonuses included)
			var rng: float = hud.game.world.abilities.cast_range(h, aid, -1)
			var dist: float = hud.game.world.abilities.val(h, aid, "distance")
			var reach := "Cast range %d" % roundi(rng) if is_finite(rng) else ("Reach %d" % roundi(dist) if dist > 0.0 else "")
			if reach != "" and h.cast_range_bonus > 0.0:
				reach += "  (+%d bonus)" % roundi(h.cast_range_bonus)
			if reach != "":
				lines.append([reach, 13, Color(0.75, 0.85, 1.0), "body"])
		if a.behavior != "passive":
			lines.append(["Mana: %s    Cooldown: %s" % [" / ".join(a.mana.map(func(x): return str(x))), " / ".join(a.cooldown.map(func(x): return str(x)))], 13, Color(0.6, 0.75, 1.0), "body"])
		if a.behavior == "autocast_attack":
			lines.append(["Right-click to toggle autocast. Cast by hand on a hero to attack without drawing creep aggro.", 12, U.TEXT_DIM, "body"])
		if a.behavior == "toggle":
			lines.append(["Press again to turn it off.", 12, U.TEXT_DIM, "body"])
		var act := Keybinds.slot_action(slot if slot >= 0 else maxi(0, h.abilities.find(aid)), h.abilities.size())
		lines.append(["Ctrl + %s to learn" % Keybinds.key_name(act), 12, U.TEXT_DIM, "body"])
		return lines

	func _bars(h: SimUnit) -> void:
		var bw := n_slots * abil_step - 8
		var rates: Vector4 = hud.game.world.regen_rates(h)
		var hr := Rect2(ABIL_X, BARS_Y, bw, 24)
		U.bar(self, hr, h.hp / maxf(1.0, h.max_hp), U.HP)
		U.text_c(self, "%d / %d" % [int(h.hp), int(h.max_hp)], hr.get_center() + Vector2(0, 7), 16, U.TEXT, "bold")
		# a healing cut (Stench with the Upgrade Staff) shows as its own red term: before the cut = total / (1 - cut)
		var red := h.heal_reduction()
		var hcut := 0.0
		if red > 0.0 and red < 0.999 and rates.x > 0.0:
			hcut = rates.x / (1.0 - red) - rates.x
		_regen_text(rates.z, rates.x + hcut - rates.z, hr, 16, Color(0.8, 1.0, 0.75), Color(0.45, 1.0, 0.35), hcut)
		var m := get_local_mouse_position()
		if hr.has_point(m):
			hud.show_tip(get_global_mouse_position(), _regen_tip("Health", h.hp, h.max_hp, rates.z, rates.x + hcut - rates.z, hcut))
		var mr := Rect2(ABIL_X, BARS_Y + 30, bw, 20)
		if h.max_mana <= 0.0:
			draw_rect(mr, Color(0.03, 0.035, 0.05, 0.9))
			U.text_c(self, "No mana", mr.get_center() + Vector2(0, 5), 12, U.TEXT_DIM, "bold")
			return
		U.bar(self, mr, h.mana / maxf(1.0, h.max_mana), U.MANA)
		U.text_c(self, "%d / %d" % [int(h.mana), int(h.max_mana)], mr.get_center() + Vector2(0, 6), 14, U.TEXT, "bold")
		_regen_text(rates.w, rates.y - rates.w, mr, 14, Color(0.78, 0.9, 1.0), Color(0.45, 0.95, 1.0))
		if mr.has_point(m):
			hud.show_tip(get_global_mouse_position(), _regen_tip("Mana", h.mana, h.max_mana, rates.w, rates.y - rates.w))

	## Hovering a bar: the amount, the regen per second and how it adds up, and how long to fill up at that rate.
	func _regen_tip(what: String, cur: float, mx: float, own: float, bonus: float, cut := 0.0) -> Array:
		var total := own + bonus - cut
		var lines: Array = [["%s %d / %d" % [what, int(cur), int(mx)], 17, U.GOLD, "title"],
			["Regenerates %s per second" % _regen_num(total, false), 15, U.TEXT, "bold"],
			["Own %s %s bonus %s" % [_regen_num(own, false), "+" if bonus >= 0.0 else "-", _regen_num(absf(bonus), false)],
				14, U.TEXT_DIM, "body"]]
		if cut > 0.05:
			lines.append(["Healing cut: -%s" % _regen_num(cut, false), 14, Color(1.0, 0.45, 0.4), "body"])
		if total > 0.05 and cur < mx:
			lines.append(["Full in %d s at this rate" % ceili((mx - cur) / total), 13, Color(0.6, 0.75, 1.0), "body"])
		return lines

	## Regeneration on a bar, read at a glance: the total per second large at the right end (where Dota shows it);
	## at the left end, smaller, how it adds up: the unit's own regen + the bonus (items, auras, consumables, the
	## fountain), and - the cut in red when healing is reduced. The breakdown hides when there is nothing to add.
	func _regen_text(own: float, bonus: float, bar: Rect2, size: int, total_col: Color, bonus_col: Color, cut := 0.0) -> void:
		var total := own + bonus - cut
		var base_y := bar.position.y + bar.size.y * 0.5 + size * 0.36
		var tcol := total_col if total >= 0.0 else Color(1.0, 0.45, 0.4)
		_outlined_r(_regen_num(total, true), Vector2(bar.end.x - 5.0, base_y), size, tcol, "bold")
		if absf(bonus) < 0.05 and cut < 0.05:
			return
		var small := size - 2
		var y := bar.position.y + bar.size.y * 0.5 + small * 0.36
		var x := _outlined_l(_regen_num(own, false), Vector2(bar.position.x + 6.0, y), small, U.TEXT, "bold")
		if absf(bonus) >= 0.05:
			x = _outlined_l(" + " if bonus > 0.0 else " - ", Vector2(x, y), small, U.TEXT, "bold")
			x = _outlined_l(_regen_num(absf(bonus), false), Vector2(x, y), small, bonus_col if bonus > 0.0 else Color(1.0, 0.45, 0.4), "bold")
		if cut >= 0.05:
			x = _outlined_l(" - ", Vector2(x, y), small, U.TEXT, "bold")
			_outlined_l(_regen_num(cut, false), Vector2(x, y), small, Color(1.0, 0.45, 0.4), "bold")

	## A regen number: one decimal below 100 ("+8.3"), whole above ("+122"); `plus` puts the + in front.
	static func _regen_num(v: float, plus: bool) -> String:
		var s := ("%.1f" % absf(v)) if absf(v) < 99.95 else str(roundi(absf(v)))
		if v < -0.0001:
			return "-" + s
		return ("+" + s) if plus else s

	## Left-aligned text with a dark outline; returns its right edge.
	func _outlined_l(s: String, at: Vector2, size: int, col: Color, kind: String) -> float:
		var f := U.font(kind)
		draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
		draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		return at.x + f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	## Right-aligned text with a dark outline (readable on the coloured bars); returns its left edge.
	func _outlined_r(s: String, at: Vector2, size: int, col: Color, kind: String) -> float:
		var f := U.font(kind)
		var wd := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p := at - Vector2(wd, 0)
		draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
		draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		return p.x

	# ---- Items, stash ----------------------------------------------------------------------------------------------

	func _items(h: SimUnit, w: SimWorld) -> void:
		var keys: Array = range(6).map(func(i): return Keybinds.key_name("item_%d" % (i + 1)))
		var m := get_local_mouse_position()
		for i in 9:
			var r: Rect2 = _item_rects[i]
			U.slot(self, r, _dragging and r.has_point(m))
			var it = h.inventory[i]
			if it == null:
				if i < 6:
					U.text_c(self, keys[i], r.get_center() + Vector2(0, 5), 13, Color(0.5, 0.5, 0.53), "bold")
				continue
			_item_icon(it, r, i >= 6, h, w, i)
			if i < 6:
				_key_tag(r, keys[i])
			if r.has_point(m) and not _dragging:
				var tip: Array = hud.item_tip(it.id, h)
				if bool(it.get("locked", false)):
					tip.append(["Locked: it does not combine into other items.", 13, Color(1.0, 0.7, 0.4), "body"])
				tip.append(["Drag to move, drop on the ground or give it to an ally. Right click: Sell, Disassemble, Lock, %s." % ("Move to Inventory" if i >= 6 else "Move to Backpack"), 12, U.TEXT_DIM, "body"])
				hud.show_tip(get_global_mouse_position(), tip)
		if h.id == hud.game.player_hero_id:
			U.text(self, "Backpack", Vector2(item_x, 156), 10, U.TEXT_DIM, "body")

	func _item_icon(it: Dictionary, r: Rect2, dim: bool, h: SimUnit, w: SimWorld, slot: int) -> void:
		var ic: Texture2D = U.held_item_icon(it)
		if ic:
			var sq := minf(r.size.x, r.size.y) - 6
			draw_texture_rect(ic, Rect2(r.get_center() - Vector2(sq, sq) * 0.5, Vector2(sq, sq)), false,
				Color(0.5, 0.5, 0.5) if dim else Color(1, 1, 1, 0.35 if _dragging and _press_slot == slot else 1.0))
		var d := SimData.item(it.id)
		if slot >= 0 and slot < 9 and h != null:
			var cd := w.abilities.item_cooldown_left(h, slot) if slot < 6 else maxf(0.0, float(it.get("ready", C.LONG_AGO)) - w.time)
			var total := maxf(float(d.cooldown), C.BACKPACK_SWAP_COOLDOWN)
			if cd > 0.0:
				U.cooldown(self, r, clampf(cd / total, 0.0, 1.0), cd)
		if int(it.get("charges", 0)) > 1 or d.consumable and int(it.get("charges", 0)) > 0 or it.id == "bottle":
			U.text_r(self, str(it.charges), r.end + Vector2(-3, -3), 14, Color(1, 1, 1), "bold")
		if String(it.get("orb", "")) != "":
			# a Bottle holding an orb: a glowing dot in the orb's colour
			var oc: Color = OrbView.COLORS.get(String(it.orb), Color(1, 1, 1))
			draw_circle(r.position + Vector2(r.size.x - 9, 9), 6.0, Color(0, 0, 0, 0.85))
			draw_circle(r.position + Vector2(r.size.x - 9, 9), 4.5, oc)
		if String(d.use) == "stick" and h != null:
			U.text_r(self, str(h.stick_charges), r.end + Vector2(-3, -3), 14, Color(0.7, 0.9, 1.0), "bold")
		if bool(it.get("locked", false)):
			# a locked item (it never combines): a small padlock in the corner
			var lr := Rect2(r.position + Vector2(r.size.x - 17, 2), Vector2(15, 15))
			draw_rect(lr.grow(1), Color(0, 0, 0, 0.75))
			var li: Texture2D = U.icon("ui/lock")
			if li:
				draw_texture_rect(li, lr, false, Color(1.0, 0.72, 0.35))

	## Dota's stash above the inventory: six slots and Grab All.
	func _stash(h: SimUnit, w: SimWorld) -> void:
		if not stash_visible(h):
			return
		var m := get_local_mouse_position()
		var here := w.shop.in_shop(h)
		var r := Rect2(item_x - 10, STASH_Y - 12, 334, 62)
		U.skin(self, "panel_card", r)
		U.text(self, "Stash" + ("" if here or not h.alive else "  (courier: %s)" % Keybinds.key_name("courier_deliver")), Vector2(item_x, STASH_Y + 6), 11, U.TEXT_DIM, "bold")
		for i in 6:
			var sr: Rect2 = _stash_rects[i]
			U.slot(self, sr, sr.has_point(m) and (h.stash[i] != null or _dragging))
			var it = h.stash[i]
			if it != null:
				_item_icon(it, sr, not here and h.alive, null, w, 100 + i)
				if sr.has_point(m) and not _dragging:
					var tip: Array = hud.item_tip(it.id, h)
					tip.append(["Click: take it (in the base). Drag it to a slot. The courier (%s) brings the stash to you." % Keybinds.key_name("courier_deliver"), 12, U.TEXT_DIM, "body"])
					hud.show_tip(get_global_mouse_position(), tip)
		var can := (here or not h.alive) and h.stash.any(func(x): return x != null)
		U.skin(self, ("btn_gold_hover" if _grab_rect.has_point(m) else "btn_gold_normal") if can else "btn_disabled", _grab_rect)
		U.text_c(self, "Grab All", _grab_rect.get_center() + Vector2(0, 5), 12, Color(0.14, 0.08, 0.02) if can else U.TEXT_DIM, "bold", not can)

	func _gold(h: SimUnit) -> void:
		var gi: Texture2D = U.icon("ui/gold")
		U.art_rect(self, "glow_gold", Rect2(side_x - 10, 30, 46, 46), Color(1, 1, 1, 0.5))
		if gi:
			draw_texture_rect(gi, Rect2(side_x, 40, 26, 26), false, U.GOLD)
		U.text(self, str(h.gold()), Vector2(side_x + 32, 63), 26, U.GOLD, "title")
		U.text(self, "reliable %d" % h.gold_reliable, Vector2(side_x + 2, 86), 12, U.TEXT_DIM, "body")
		var hover := _shop_rect.has_point(get_local_mouse_position())
		U.skin(self, "btn_gold_hover" if hover else "btn_gold_normal", _shop_rect)
		var si: Texture2D = U.icon("ui/shop")
		if si:
			draw_texture_rect(si, Rect2(_shop_rect.position + Vector2(14, 15), Vector2(32, 32)), false, Color(0.2, 0.11, 0.02))
		U.text(self, "Shop", _shop_rect.position + Vector2(56, 40), 22, Color(0.16, 0.09, 0.02), "title", false)

	## A hotkey on a dark tag tucked inside a slot's top-left corner, clear of the slot's frame.
	func _key_tag(r: Rect2, key: String, size := 11) -> void:
		key = key.replace(" + ", "+")
		var f := U.font("bold")
		var tw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var tr := Rect2(r.position + Vector2(4, 4), Vector2(minf(tw + 8, r.size.x - 8), size + 4))
		draw_rect(tr, Color(0, 0, 0, 0.7))
		U.text(self, key, tr.position + Vector2(4, size + 1), size, Color(1, 1, 1), "bold")

	func _tp_and_courier(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		U.slot(self, _tp_rect, hud.game.input.targeting == "tp")
		var ti: Texture2D = U.icon("ui/teleport")
		if ti:
			draw_texture_rect(ti, Rect2(_tp_rect.position + Vector2(39, 3), Vector2(26, 26)), false, U.DAWN if h.tp_charges > 0 else Color(0.4, 0.4, 0.4))
		var cd := w.abilities.cooldown_left(h, "tp")
		if cd > 0.0:
			U.cooldown(self, _tp_rect, cd / SimConst.TP_COOLDOWN, cd)
		_key_tag(_tp_rect, Keybinds.key_name("tp"), 10)
		U.text_r(self, str(h.tp_charges), _tp_rect.end + Vector2(-3, -3), 12, Color(1, 1, 1), "bold")
		if _tp_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Teleport Scroll", 18, U.GOLD, "title"],
				["Channel 3 s, then teleport beside the allied building nearest the target point. Moving or a stun cancels it.", 14, U.TEXT, "body"],
				["Charges %d. Cooldown 80 s. Mana 75. Hotkey %s." % [h.tp_charges, Keybinds.key_name("tp")], 13, U.TEXT_DIM, "body"],
				["Buy one for 100 gold: press %s or right click here (Consumables in the shop). Away from the shop it goes to your stash." % Keybinds.key_name("buy_tp"), 13, U.GOLD, "body"]])
		var c := w.get_unit(h.courier_id)
		U.skin(self, "btn_hover" if _courier_rect.has_point(m) else "btn_normal", _courier_rect)
		var state := "Dead" if c == null or not c.alive else _state_name(c.courier_state)
		U.text_c(self, "Deliver", _courier_rect.get_center() + Vector2(0, -2), 12, U.GOLD, "bold")
		U.text_c(self, state, _courier_rect.get_center() + Vector2(0, 12), 9, U.TEXT_DIM, "body")
		if _courier_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Courier", 18, U.GOLD, "title"],
				["Click (or %s): the courier picks up your items lying in the fountain area, takes the stash and flies it all to you." % Keybinds.key_name("courier_deliver"), 14, U.TEXT, "body"],
				["%s selects the courier for its other commands." % Keybinds.key_name("select_courier"), 13, U.TEXT_DIM, "body"]])

	func _buyback(h: SimUnit, w: SimWorld) -> void:
		var cost := w.buyback_cost(h)
		var ready := w.time >= h.buyback_ready
		var can := ready and h.gold() >= cost
		var hov := _buyback_rect.has_point(get_local_mouse_position())
		U.skin(self, ("btn_red_hover" if hov else "btn_red_normal") if can else "btn_red_disabled", _buyback_rect)
		var label := "Buyback  %d gold" % cost if ready else "Buyback in %ds" % ceili(h.buyback_ready - w.time)
		U.text_c(self, label, _buyback_rect.get_center() + Vector2(0, 8), 21, Color(1.0, 0.9, 0.75) if can else U.TEXT_DIM, "title")

	# ---- Courier panel ---------------------------------------------------------------------------------------------

	func _courier_panel(h: SimUnit, c: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		# hits left (couriers count hits, not health)
		var hr := Rect2(196, 40, 190, 20)
		U.bar(self, hr, c.hp / maxf(1.0, c.max_hp), U.HP)
		U.text_c(self, "%d / %d hits" % [int(ceil(c.hp)), int(c.max_hp)], hr.get_center() + Vector2(0, 6), 13, U.TEXT, "bold")
		U.text(self, "Dies to 1 melee hero hit,", Vector2(196, 82), 12, U.TEXT_DIM, "body")
		U.text(self, "2 ranged hero hits or 6 others.", Vector2(196, 98), 12, U.TEXT_DIM, "body")
		U.text(self, "Flies from level %d." % C.COURIER_FLY_LEVEL, Vector2(196, 120), 12, U.TEXT_DIM, "body")
		for i in COURIER_CMDS.size():
			var cmd: Array = COURIER_CMDS[i]
			var r: Rect2 = _cmd_rects[i]
			var locked: bool = (cmd[0] == "burst" and h.level < C.COURIER_BURST_LEVEL) or (cmd[0] == "shield" and h.level < C.COURIER_SHIELD_LEVEL)
			var on: bool = cmd[0] == "auto" and c.courier_auto
			U.slot(self, r, r.has_point(m) or on)
			var ic: Texture2D = U.icon(cmd[2])
			if ic:
				draw_texture_rect(ic, Rect2(r.get_center() - Vector2(18, 20), Vector2(36, 36)), false,
					Color(0.35, 0.35, 0.35) if locked or not c.alive else (Color(0.55, 1.0, 0.45) if on else U.GOLD))
			var cdl := 0.0
			if cmd[0] == "burst":
				cdl = c.courier_burst_ready - w.time
				if cdl > 0.0:
					U.cooldown(self, r, cdl / C.COURIER_BURST_COOLDOWN, cdl)
			elif cmd[0] == "shield":
				cdl = c.courier_shield_ready - w.time
				if cdl > 0.0:
					U.cooldown(self, r, cdl / C.COURIER_SHIELD_COOLDOWN, cdl)
			U.text(self, Keybinds.key_name(cmd[3]), r.position + Vector2(4, 13), 11, Color(1, 1, 1), "bold")
			U.text_c(self, String(cmd[4]), Vector2(r.get_center().x, r.end.y - 3), 10, U.TEXT_DIM, "body")
			if r.has_point(m):
				var tip := {"return": "Fly back to the fountain.", "retrieve": "Pick up your items lying in the fountain area and take the stash, then wait at the fountain.",
					"stash": "Fly home and put everything it carries into your stash.", "deliver": "Pick up your items in the fountain area, take the stash and bring it all to you.",
					"transfer": "Bring what it carries to you.", "burst": "+50%% movement speed for 6 seconds. 120 second cooldown. From level %d." % C.COURIER_BURST_LEVEL,
					"shield": "Invulnerable for 2 seconds. 200 second cooldown. From level %d." % C.COURIER_SHIELD_LEVEL,
					"auto": "While on, the courier sets out by itself whenever the stash or its bags hold something."}
				hud.show_tip(get_global_mouse_position(), [[String(cmd[1]), 18, U.GOLD, "title"], [String(tip.get(cmd[0], "")), 14, U.TEXT, "body"],
					["Hotkey %s" % Keybinds.key_name(cmd[3]), 12, U.TEXT_DIM, "body"]])
		# what it carries
		for i in 6:
			var r: Rect2 = _item_rects[i]
			U.slot(self, r)
			var it = c.inventory[i]
			if it != null:
				_item_icon(it, r, not c.alive, null, w, -1)
				if r.has_point(m):
					hud.show_tip(get_global_mouse_position(), hud.item_tip(it.id, h))
		U.text(self, "Carrying", Vector2(item_x, 24), 11, U.TEXT_DIM, "bold")

	# ---- Input -----------------------------------------------------------------------------------------------------

	func _drag_item(h: SimUnit):
		if _press_slot >= 100:
			return h.stash[_press_slot - 100]
		if _press_slot >= 0:
			return h.inventory[_press_slot]
		return null

	func _slot_at(p: Vector2, h: SimUnit) -> int:
		for i in 9:
			if (_item_rects[i] as Rect2).has_point(p):
				return i
		if stash_visible(h):
			for i in 6:
				if (_stash_rects[i] as Rect2).has_point(p):
					return 100 + i
		return -1

	## Whether a point (local) is over the stash row or the open talent tree (they stick out above the panel).
	func covers_extra(p: Vector2) -> bool:
		if item_menu_open() and item_menu_rect().has_point(p):
			return true
		if Rect2(CHIPS_X, CHIPS_Y, _chips_end - CHIPS_X, 22).has_point(p):
			return true
		for r in _buff_rects:
			if (r as Rect2).has_point(p):
				return true
		var h: SimUnit = hud.hero()
		if stash_visible(h) and Rect2(item_x - 8, STASH_Y - 8, 330, 56).has_point(p):
			return true
		if talents_open and not _talent_rows.is_empty():
			for tr in _talent_rows:
				if (tr[0] as Rect2).grow(8).has_point(p):
					return true
		return false

	func _has_point(p: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).has_point(p) or covers_extra(p)

	func _gui_input(e: InputEvent) -> void:
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		if item_menu_open() and e is InputEventMouseButton and e.pressed:
			var ip := (e as InputEventMouseButton).position
			if item_menu_rect().has_point(ip):
				if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					_item_menu_click(ip, h, w)
				accept_event()
				return
			close_item_menu()
		if e is InputEventMouseMotion and _press_slot >= 0:
			if not _dragging and (e as InputEventMouseMotion).position.distance_to(_press_at) > 6.0:
				_dragging = true
			if _dragging:
				queue_redraw()
			return
		if e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hud.portrait_release()
			if _press_slot >= 0:
				_release_item((e as InputEventMouseButton).position, h, w)
				accept_event()
			return
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var p := mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and PORTRAIT.has_point(p) and courier_shown() == null:
			hud.portrait_press()
			accept_event()
			return
		if talents_open and mb.button_index == MOUSE_BUTTON_LEFT:
			for tr in _talent_rows:
				if (tr[0] as Rect2).has_point(p):
					if w.abilities.can_learn_talent(h, int(tr[1])):
						hud.game.act({"k": "talent", "tier": int(tr[1]), "side": int(tr[2])})
						if hud.game.audio:
							hud.game.audio.ui("ui_click", -2.0)
					accept_event()
					return
		if _talent_rect.has_point(p) and mb.button_index == MOUSE_BUTTON_LEFT and not (hud.shown().def.get("talents", []) as Array).is_empty():
			talents_open = not talents_open
			accept_event()
			return
		talents_open = false
		var cour := courier_shown()
		if cour != null:
			for i in COURIER_CMDS.size():
				if (_cmd_rects[i] as Rect2).has_point(p):
					hud.game.input.courier_cmd(String(COURIER_CMDS[i][0]))
					accept_event()
					return
		if hud.shown() != h and cour == null:
			accept_event()
			return
		if not h.alive and _buyback_rect.has_point(p):
			var err: String = hud.game.act({"k": "buyback"})
			if err != "":
				hud.error(err)
			accept_event()
			return
		if _tp_rect.has_point(p):
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				hud.game.input.buy_tp()
			else:
				hud.game.input.begin_tp()
			accept_event()
			return
		if _courier_rect.has_point(p):
			hud.game.input.courier_cmd("deliver")
			accept_event()
			return
		if _shop_rect.has_point(p):
			hud.toggle_shop()
			accept_event()
			return
		if stash_visible(h) and _grab_rect.has_point(p):
			var gerr: String = hud.game.act({"k": "grab_all"})
			if gerr != "":
				hud.error(gerr)
			accept_event()
			return
		if cour != null:
			accept_event()
			return
		for i in mini(n_slots, h.abilities.size()):
			var aid: String = h.abilities[i]
			if (_learn_rects[i] as Rect2).has_point(p) and w.abilities.can_learn(h, aid):
				hud.game.act({"k": "learn", "ability": aid})
				accept_event()
				return
			if (_abil_rects[i] as Rect2).has_point(p):
				if mb.button_index == MOUSE_BUTTON_RIGHT:
					hud.game.act({"k": "autocast", "ability": aid})
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					if mb.ctrl_pressed:
						hud.game.act({"k": "learn", "ability": aid})
					else:
						hud.game.input.begin_ability(aid, mb.shift_pressed)
				accept_event()
				return
		var s := _slot_at(p, h)
		if s >= 0:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				# a click uses the item (on release, so a drag can move it instead)
				if (s < 100 and h.inventory[s] != null) or (s >= 100 and h.stash[s - 100] != null):
					_press_slot = s
					_press_at = p
					_dragging = false
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				# right click: the item menu (Sell, Disassemble, Lock, Move to Backpack / Inventory)
				if (s < 100 and h.inventory[s] != null) or (s >= 100 and h.stash[s - 100] != null):
					open_item_menu(s, p)
			accept_event()
			return
		accept_event()

	# ---- Item menu (right click an item): Sell, Disassemble, Lock / Unlock, Move to Backpack / Inventory ------------

	var _menu := {}                            # {slot, at, rows: [[rect, action, enabled, label, hint]]}

	func item_menu_open() -> bool:
		return not _menu.is_empty()

	func close_item_menu() -> void:
		_menu = {}
		queue_redraw()

	func item_menu_rect() -> Rect2:
		return _menu.get("rect", Rect2())

	## The actions for the item in `slot` (0..8 bags, 100+ stash): what each does and whether it can be done now.
	func _menu_rows(h: SimUnit, w: SimWorld, slot: int) -> Array:
		var stash := slot >= 100
		var it = h.stash[slot - 100] if stash else h.inventory[slot]
		if it == null:
			return []
		var rows: Array = []
		var here: bool = w.shop.in_shop(h)
		var mine := int(it.get("owner", h.id)) == h.id
		var value: int = w.shop.sell_value(it)
		var can_sell := mine and (stash or here)
		var fresh: float = w.shop.full_refund_left(it)
		var sell_hint := ("Full price for %d more seconds" % ceili(fresh)) if fresh > 0.0 else "Half price (bought over 10 seconds ago)"
		rows.append(["sell", "Sell for %d gold" % value, can_sell, sell_hint if can_sell else ("Not your item" if not mine else "Go to a shop to sell")])
		var derr: String = w.shop.disassemble_error(h, it)
		if derr == "" or derr == "You do not own this item" or (SimData.item(it.id).components as Array).size() > 0:
			rows.append(["disassemble", "Disassemble", derr == "", derr if derr != "" else "Its parts come back locked"])
		var locked := bool(it.get("locked", false))
		rows.append(["lock", "Unlock" if locked else "Lock", true,
			"Lets it combine again" if locked else "Stops it combining into other items"])
		if not stash:
			rows.append(["move", "Move to Backpack" if slot < 6 else "Move to Inventory", true, ""])
		return rows

	func open_item_menu(slot: int, at: Vector2) -> void:
		var h: SimUnit = hud.hero()
		var rows := _menu_rows(h, hud.game.world, slot)
		if rows.is_empty():
			return
		var rw := 236.0
		var rh := 30.0
		var top := minf(at.y, 0.0) - rows.size() * rh - 34.0
		var r := Rect2(clampf(at.x - rw * 0.5, 4.0, pw - rw - 4.0), top, rw, rows.size() * rh + 34.0)
		var out: Array = []
		for i in rows.size():
			out.append([Rect2(r.position.x + 6, r.position.y + 28 + i * rh, rw - 12, rh - 3)] + rows[i])
		_menu = {"slot": slot, "rect": r, "rows": out, "item": (h.stash[slot - 100] if slot >= 100 else h.inventory[slot]).id}
		if hud.game.audio:
			hud.game.audio.ui("ui_click", -6.0)
		queue_redraw()

	func _item_menu_click(p: Vector2, h: SimUnit, w: SimWorld) -> void:
		var slot := int(_menu.slot)
		for row in _menu.rows:
			if not (row[0] as Rect2).has_point(p):
				continue
			if not bool(row[3]):
				hud.error(String(row[4]))
				return
			var stash := slot >= 100
			var idx := slot - 100 if stash else slot
			var err := ""
			match String(row[1]):
				"sell":
					err = hud.game.act({"k": "sell", "slot": idx, "stash": stash})
				"disassemble":
					err = hud.game.act({"k": "disassemble", "slot": idx, "stash": stash})
				"lock":
					err = hud.game.act({"k": "lock", "slot": idx, "stash": stash})
				"move":
					var lo := 6 if slot < 6 else 0
					var hi := 9 if slot < 6 else 6
					var dest := -1
					for k in range(lo, hi):
						if h.inventory[k] == null:
							dest = k
							break
					if dest >= 0:
						hud.game.act({"k": "swap", "a": slot, "b": dest})
					else:
						err = "Backpack is full" if slot < 6 else "Inventory is full"
			if err != "":
				hud.error(err)
			elif hud.game.audio:
				hud.game.audio.ui("ui_click", -2.0)
			close_item_menu()
			return

	func _draw_item_menu(h: SimUnit) -> void:
		if _menu.is_empty():
			return
		var slot := int(_menu.slot)
		var it = h.stash[slot - 100] if slot >= 100 else (h.inventory[slot] if slot < h.inventory.size() else null)
		if it == null or String(it.id) != String(_menu.item):
			_menu = {}
			return
		var r: Rect2 = _menu.rect
		U.skin(self, "panel_card", r.grow(4))
		var name := String(SimData.item(it.id).name)
		U.text(self, name, r.position + Vector2(12, 20), 15, U.GOLD, "title")
		if bool(it.get("locked", false)):
			U.text_r(self, "Locked", Vector2(r.end.x - 10, r.position.y + 19), 12, Color(1.0, 0.7, 0.4), "bold")
		var m := get_local_mouse_position()
		for row in _menu.rows:
			var rr: Rect2 = row[0]
			var ok := bool(row[3])
			var over := rr.has_point(m)
			U.skin(self, ("btn_hover" if over else "btn_normal") if ok else "btn_disabled", rr)
			var label := String(row[2])
			if String(row[1]) == "sell":
				# the price drops to half when the 10 s of full refund run out, maybe while the menu is open
				label = "Sell for %d gold" % hud.game.world.shop.sell_value(it)
				var left: float = hud.game.world.shop.full_refund_left(it)
				if left > 0.0:
					U.text_r(self, "full %ds" % ceili(left), rr.end + Vector2(-8, -8), 11, Color(0.6, 1.0, 0.6), "bold")
			U.text(self, label, rr.position + Vector2(10, 19), 14, U.TEXT if ok else Color(0.45, 0.45, 0.47), "bold")
			if over and String(row[4]) != "":
				hud.show_tip(get_global_mouse_position(), [[String(row[2]), 15, U.GOLD, "bold"], [String(row[4]), 13, U.TEXT, "body"]])

	## Finish a click or a drag that began on an item.
	func _release_item(p: Vector2, h: SimUnit, w: SimWorld) -> void:
		var from := _press_slot
		var dragged := _dragging
		_press_slot = -1
		_dragging = false
		queue_redraw()
		if not dragged:
			if from < 6:
				hud.game.input.use_item(from, Input.is_key_pressed(KEY_SHIFT))
			elif from >= 100:
				var err0: String = hud.game.act({"k": "from_stash", "slot": from - 100})
				if err0 != "":
					hud.error(err0)
			return
		var to := _slot_at(p, h)
		var err := ""
		if to >= 0:
			if from < 100 and to < 100:
				hud.game.act({"k": "swap", "a": from, "b": to})
			elif from < 100 and to >= 100:
				err = hud.game.act({"k": "to_stash", "slot": from})
			elif from >= 100 and to < 100:
				err = hud.game.act({"k": "from_stash", "slot": from - 100, "to": to})
		elif not _has_point(p) and from < 100 and not hud.over_hud(get_global_transform() * p):
			# dropped on the world: give it to an ally hero or your courier under the cursor, otherwise drop it there
			hud.game.input.drop_or_give(from, get_global_transform() * p)
		if err != "":
			hud.error(err)


class PortraitOverlay extends Control:
	var panel

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2.ZERO
		size = panel.size if panel else Vector2(BottomPanel.W, BottomPanel.H)

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("PortraitOverlay", t0)

	func _draw_body() -> void:
		panel.draw_overlay(self)


class ToBuyPanel extends Control:
	## The To Buy list at the side of the screen (Dota's quick buy): Shift + click an item in the shop to add it,
	## broken into the parts you still need. Shows up to 8 entries. Left click buys an entry now, right click sets it
	## to buy itself as soon as you have the gold (the courier takes it if it waits at the fountain while you are
	## away), Ctrl + click (or the x) removes it.
	const W := 236.0
	const ROW := 46.0
	var hud
	var _rows: Array = []                      # [rect, index, kind] kind: "buy" or "remove"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func wanted() -> bool:
		var h: SimUnit = hud.hero()
		return h != null and (not h.to_buy.is_empty() or hud.shop.visible)

	func _process(_dt: float) -> void:
		var h: SimUnit = hud.hero()
		var n := 0 if h == null else mini(h.to_buy.size(), C.TO_BUY_SHOWN)
		var more := h != null and h.to_buy.size() > C.TO_BUY_SHOWN
		size = Vector2(W, 40 + maxi(n, 1) * ROW + (22 if more else 0) + 30)

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("ToBuyPanel", t0)

	func _draw_body() -> void:
		_rows.clear()
		var h: SimUnit = hud.hero()
		if h == null:
			return
		var w: SimWorld = hud.game.world
		var m := get_local_mouse_position()
		U.panel(self, Rect2(Vector2.ZERO, size), U.GOLD_DIM, 6)
		U.text(self, "To Buy", Vector2(12, 24), 17, U.GOLD, "title")
		var total := 0
		for e in h.to_buy:
			total += int(SimData.item(String(e.id)).cost)
		if total > 0:
			U.text_r(self, "%d gold" % total, Vector2(W - 12, 24), 13, U.GOLD, "bold")
		if h.to_buy.is_empty():
			U.text(self, "Shift + click an item", Vector2(12, 52), 12, U.TEXT_DIM, "body")
			U.text(self, "in the shop to add it here.", Vector2(12, 68), 12, U.TEXT_DIM, "body")
		var y := 36.0
		for i in mini(h.to_buy.size(), C.TO_BUY_SHOWN):
			var e: Dictionary = h.to_buy[i]
			var id := String(e.id)
			var d := SimData.item(id)
			var r := Rect2(8, y, W - 16, ROW - 4)
			var price := w.shop.price(h, id)
			var afford := h.gold() >= price
			var auto := bool(e.auto)
			var hover := r.has_point(m)
			draw_rect(r, Color(0.08, 0.09, 0.11, 0.95) if not hover else Color(0.13, 0.13, 0.16, 0.98))
			var rim := U.GOLD_DIM
			if auto:
				var t := Time.get_ticks_msec() / 1000.0
				rim = Color(0.45, 1.0, 0.5, 0.65 + 0.35 * sin(t * 5.0))
			draw_rect(r, rim, false, 2.0 if auto else 1.0)
			var ic: Texture2D = U.item_icon(id)
			if ic:
				draw_texture_rect(ic, Rect2(r.position + Vector2(5, 4), Vector2(34, 34)), false, Color(1, 1, 1) if afford else Color(0.55, 0.55, 0.55))
			var nm := String(d.get("name", id))
			if nm.length() > 18:
				nm = nm.substr(0, 17) + "."
			U.text(self, nm, r.position + Vector2(46, 18), 13, U.TEXT if afford else U.TEXT_DIM, "bold")
			U.text(self, "%d" % price, r.position + Vector2(46, 35), 12, U.GOLD if afford else Color(0.65, 0.5, 0.4), "bold")
			if auto:
				U.text_r(self, "Auto", Vector2(r.end.x - 26, r.position.y + 35), 11, Color(0.5, 1.0, 0.55), "bold")
			var xr := Rect2(r.end.x - 22, r.position.y + 4, 18, 18)
			draw_rect(xr, Color(0.25, 0.08, 0.06) if xr.has_point(m) else Color(0.12, 0.1, 0.1))
			U.text_c(self, "x", xr.get_center() + Vector2(0, 5), 13, U.TEXT, "bold")
			_rows.append([xr, i, "remove"])
			_rows.append([r, i, "buy"])
			if hover and not xr.has_point(m):
				var tip: Array = hud.item_tip(id, h)
				tip.append(["Left click: buy now (%d gold). Right click: %s. Ctrl + click: remove." % [price,
					"stop buying it automatically" if auto else "buy it automatically when you have the gold"], 12, Color(0.75, 0.9, 0.75), "body"])
				hud.show_tip(get_global_mouse_position(), tip)
			y += ROW
		if h.to_buy.size() > C.TO_BUY_SHOWN:
			U.text(self, "+%d more" % (h.to_buy.size() - C.TO_BUY_SHOWN), Vector2(14, y + 14), 12, U.TEXT_DIM, "bold")
			y += 22
		if not h.to_buy.is_empty():
			var cr := Rect2(8, size.y - 30, W - 16, 24)
			U.slot(self, cr, cr.has_point(m))
			U.text_c(self, "Clear", cr.get_center() + Vector2(0, 5), 12, U.TEXT_DIM, "bold")
			_rows.append([cr, -1, "clear"])

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		for r in _rows:
			if not (r[0] as Rect2).has_point(mb.position):
				continue
			var i: int = r[1]
			match String(r[2]):
				"clear":
					hud.game.act({"k": "to_buy_clear"})
				"remove":
					hud.game.act({"k": "to_buy_remove", "i": i})
				"buy":
					if mb.button_index == MOUSE_BUTTON_RIGHT:
						hud.game.act({"k": "to_buy_auto", "i": i})
					elif mb.ctrl_pressed:
						hud.game.act({"k": "to_buy_remove", "i": i})
					elif mb.button_index == MOUSE_BUTTON_LEFT:
						var err: String = hud.game.act({"k": "buy_listed", "i": i})
						if err != "":
							hud.error(err)
			queue_redraw()
			accept_event()
			return
		accept_event()


const STAT_NAMES := {"str": "Strength", "agi": "Agility", "int": "Intelligence", "damage": "Damage",
	"attack_speed": "Attack Speed", "armor": "Armor", "hp": "Health", "mana": "Mana", "hp_regen": "Health Regen",
	"mana_regen": "Mana Regen", "move_speed": "Movement Speed", "boot_ms": "Movement Speed",
	"move_speed_pct": "Movement Speed", "max_mana_pct": "Max Mana", "lifesteal": "Lifesteal", "range": "Attack Range",
	"magic_resist": "Magic Resistance", "evasion": "Evasion", "status_resist_max": "Status Resistance",
	"slow_resist_max": "Slow Resistance", "heal_amp_max": "Health Restoration", "spell_amp": "Spell Amp",
	"mana_regen_amp": "Mana Regen", "range_melee": "Attack Range (melee)", "magic_amp": "Magic Amp",
	"mana_regen_amp_max": "Mana Regen Amp", "mana_cost_cut_max": "Mana Cost Reduction", "cast_speed_max": "Cast Speed",
	"cooldown_reduction_max": "Cooldown Reduction", "aoe_bonus_max": "Spell Area", "cast_range_max": "Cast Range",
	"hp_regen_pct_max": "Max Health Regen per second", "hp_regen_pct_missing": "Missing Health Regen per second",
	"base_damage_pct": "Base Damage", "cooldown_rate": "Cooldown Speed"}

const ITEM_TEXT := {"tango": "Eat a tree to regenerate 7 health per second for 16 seconds (32 seconds on a planted tree). The tree is destroyed and grows back after 3 minutes.",
	"plant": "Plant a tree within 400 range. It stands for 20 seconds. Consumes the twig.",
	"salve": "Regenerate 30 health per second for 13 seconds. Broken by damage from enemy heroes.",
	"clarity": "Regenerate 6 mana per second for 25 seconds. Broken by damage from enemy heroes.",
	"mango": "Restore 100 mana.", "faerie_fire": "Restore 85 health.", "ward": "Plant an invisible ward that sees 1600 range for 6 minutes.",
	"chop": "Chop down a tree within 350 range; it grows back after 3 minutes. Passive: bonus attack damage against creeps.",
	"stick": "Restore 15 health and mana per charge. Charges when enemy heroes cast spells nearby.",
	"berserk": "Frenzy: +100 attack speed and +6% movement speed (+12% for melee heroes), but -7 armor for 6 seconds. Costs 25 mana.",
	"switch": "Switch the bonus between strength, intelligence and agility.",
	"slip": "For 3 seconds, walk through units and move 20% faster (10% for ranged heroes). 8 second cooldown.",
	"restore": "Restore 150 mana to yourself and allies within 1200. 55 second cooldown.",
	"mend": "Heal yourself and allies within 1200 for 250. Costs 100 mana, 50 second cooldown.",
	"spikes": "For 5.5 seconds, 85% of all damage you take is sent back to whoever dealt it. Costs 25 mana, 25 second cooldown.",
	"gold": "Kill an enemy creep (not an ancient) within 600 and gain 160 gold. Two charges, one comes back every 90 seconds.",
	"push": "Push a unit 600 forward the way it faces, cutting trees in its path. Range 550 on allies (or yourself), 850 on enemies. Costs 150 mana, 19 second cooldown.",
	"shield": "Immune to debuffs (stuns, slows, pushes) and 60% magic resistance; removes slows and silences. Lasts 9 seconds, one second less each use down to 7. Costs 50 mana, 95 second cooldown.",
	"jump": "Teleport to a point up to 1200 away (a farther point jumps 960 toward it). Disabled for 3 seconds after taking damage from an enemy hero. 15 second cooldown.",
	"sneak": "Turn invisible after 0.3 seconds for 17 seconds and move 20% faster. Attacking breaks it and the attack deals 175 extra damage. Costs 75 mana, 25 second cooldown.",
	"overwhelm": "Stun an enemy within 150 for 1.6 s, even through debuff immunity. 75 mana, 35 s cooldown.",
	"silence": "Silence an enemy within 900 for 5 seconds. When it ends, 30% of the damage it took meanwhile hits it again as magic damage. Costs 125 mana, 18 second cooldown.",
	"root": "Throw a root at an enemy within 1100: it cannot move for 2 seconds (it can still attack and cast; a root also stops teleports). Costs 100 mana, 18 second cooldown.",
	"disarm": "Disarm an enemy within 750 for 3.5 seconds: it cannot attack. Only a strong dispel removes it. Costs 25 mana, 15 second cooldown.",
	"bottle": "Drink a charge: 110 health and 60 mana over 2.7 seconds (lost if an enemy hero hurts you). Refills to 3 charges at the fountain. Taking an orb while carrying it stores the orb (for up to 90 seconds); drinking lets it out.",
	"dust": "Reveal invisible enemies within 1050 of you for 12 seconds and slow them 20% while they are invisible (the effect stays 8 seconds after they leave). Invisible enemies there take 25 damage.",
	"hex": "Turn an enemy within 800 into a sheep for 2.8 seconds: it cannot attack, cast or use items, and its base speed is 140. Costs 250 mana, 20 second cooldown."}

const PASSIVE_TEXT := {"pierce": "Attacks have a 25% chance to never miss and deal 60 extra magic damage.",
	"crit": "Critical Strike.", "bash": "Bash.",
	"corruption": "Attacks lower the target's armor (the stronger of these items counts).",
	"chain": "Attacks have a 25% chance to throw lightning: 110 magic damage, jumping to 4 enemies.",
	"cleave": "Melee heroes: attacks also hit enemies in front for 60% of the damage (40% to creeps).",
	"block": "60% chance to block 50 damage from each attack (25 for ranged heroes).",
	"spikes": "Attackers take back 10 + 15% of the damage of their attacks."}

func item_tip(id: String, h: SimUnit, wrap := 320.0) -> Array:
	var d := SimData.item(id)
	var lines: Array = [[String(d.name), 20, U.GOLD, "title"]]
	lines.append(["Cost %d" % int(d.cost), 14, U.GOLD, "bold"])
	if d.has("recipe_for"):
		lines.append(["Combine with the parts of %s." % String(SimData.item(d.recipe_for).name), 14, U.TEXT, "body"])
	var melee := h == null or not h.is_ranged()
	var stats: Dictionary = d.stats.duplicate()
	for k in d.get("stats_melee" if melee else "stats_ranged", {}):
		stats[k] = float(stats.get(k, 0.0)) + float(d.get("stats_melee" if melee else "stats_ranged")[k])
	for k in stats:
		var v := float(stats[k])
		var label := String(STAT_NAMES.get(k, String(k).replace("_", " ").capitalize()))
		var pct: bool = k.ends_with("pct") or k == "lifesteal" or k == "magic_resist" or k == "evasion" \
			or (k.ends_with("_max") and not k in ["aoe_bonus_max", "cast_range_max"]) or k.ends_with("_amp") \
			or k.begins_with("hp_regen_pct")
		var vs := ("+%d%%" % roundi(v * 100.0)) if pct else "+" + str(snappedf(v, 0.01)).trim_suffix(".0")
		lines.append([vs + " " + label, 15, U.TEXT, "body"])
	if d.has("stats_melee"):
		lines.append(["(melee and ranged heroes get different amounts)", 12, U.TEXT_DIM, "body"])
	if stats.has("magic_amp"):
		lines.append(["Magic amp from several items stacks with diminishing returns: each one counts half as much as the one before.", 12, U.TEXT_DIM, "body"])
	if d.has("element"):
		var el := C.element_of(String(d.element))
		lines.append(["Element: " + String(C.ELEMENT_NAMES[el]), 14, C.ELEMENT_COLORS[el], "bold"])
	var v: Dictionary = d.values
	if d.has("attr_from"):
		var cur := ""
		if h != null:
			for it in h.inventory:
				if it != null and it.id == id:
					cur = String(it.get("attr", ""))
		lines.append(["+%d to the chosen attribute%s" % [int(v.attr_bonus), (": " + {"str": "Strength", "agi": "Agility", "int": "Intelligence"}.get(cur, "")) if cur != "" else ""], 15, U.TEXT, "body"])
	if d.has("aura"):
		var aura := "+%s mana regen" % str(v.aura_mana_regen) if d.aura == "mana" else "+%s health regen" % str(v.aura_hp_regen)
		lines.append(["Aura: %s to allies within %d" % [aura, int(v.aura_radius)], 14, Color(0.75, 0.85, 1.0), "body"])
	for au in d.get("auras", []):
		var parts: Array = []
		for k in au.stats:
			parts.append(_stat_text(String(k), float(au.stats[k])))
		var who := "enemies" if bool(au.get("enemy", false)) else "allies"
		if bool(au.get("buildings", false)):
			who += " (buildings too)"
		for l in U.wrap("%s: %s to %s within %d." % [String(au.name), ", ".join(parts), who, int(au.radius)], wrap, 14):
			lines.append([l, 14, Color(0.75, 0.85, 1.0) if not bool(au.get("enemy", false)) else Color(1.0, 0.7, 0.6), "body"])
	var use := String(d.use)
	if d.has("text") and not ITEM_TEXT.has(use):
		for l in U.wrap(String(d.text), wrap, 14):
			lines.append([l, 14, Color(0.75, 0.9, 0.75), "body"])
	if ITEM_TEXT.has(use):
		var utxt := String(ITEM_TEXT[use])
		if use == "ward" and float(v.get("true_sight", 0.0)) > 0.0:
			utxt = "Plant an invisible ward that gives your team True Sight within %d for 7 minutes: invisible enemies there can be seen where you have vision. It has no sight of its own." % int(v.true_sight)
		if use == "sneak" and float(v.get("break", 0.0)) > 0.0:
			utxt = "Turn invisible after 0.3 seconds for 17 seconds and move 20% faster. Attacking breaks it: the attack deals %d extra damage and breaks the target for %d seconds (its own passive abilities stop working). Costs 75 mana, 23 second cooldown." % [int(v.bonus_damage), int(v["break"])]
		for l in U.wrap(utxt, wrap, 14):
			lines.append([l, 14, Color(0.75, 0.9, 0.75), "body"])
	var pas := String(d.get("passive", ""))
	if PASSIVE_TEXT.has(pas):
		var txt := String(PASSIVE_TEXT[pas])
		if pas == "pierce":
			txt = "Attacks have a %d%% chance to never miss and deal %d extra magic damage (not against buildings)." % [roundi(float(v.chance) * 100.0), int(v.damage)]
		elif pas == "crit":
			txt = "Critical Strike: %d%% chance to deal %d%% damage (not on buildings). Crit items never stack." % [roundi(float(v.crit_chance) * 100.0), roundi(float(v.crit_mult) * 100.0)]
		elif pas == "bash":
			txt = "Bash: %d%% chance (%d%% ranged) to stun for %.1f s and deal %d damage; %.1f s cooldown. Only one bash item works." % [roundi(float(v.chance_melee) * 100.0), roundi(float(v.chance_ranged) * 100.0), float(v.duration), int(v.damage), float(v.bash_cooldown)]
		if pas == "corruption":
			txt = "Attacks lower the target's armor by %d for %d seconds (the stronger of these items counts)." % [int(v.armor_reduction), int(v.duration)]
			if v.has("max_damage"):
				txt += " Gains 2 damage for each corrupted enemy hero you kill (1 for an assist), up to 30."
		for l in U.wrap("Passive: " + txt, wrap, 14):
			lines.append([l, 14, Color(0.85, 0.8, 0.65), "body"])
	if String(d.get("grants", "")) == "scepter":
		lines.append(["Upgrades your hero's abilities while carried.", 14, Color(0.75, 0.9, 0.75), "body"])
	elif String(d.get("grants", "")) == "shard":
		lines.append(["Used at once: upgrades your hero's abilities for good. On sale from 15:00.", 14, Color(0.75, 0.9, 0.75), "body"])
	if not (d.components as Array).is_empty():
		var names := []
		for c in d.components:
			names.append(String(SimData.item(c).name))
		lines.append(["Made from: " + ", ".join(names) + (" + recipe %d" % int(d.recipe_cost) if int(d.recipe_cost) > 0 else ""), 12, U.TEXT_DIM, "body"])
	return lines

# ======================================================================================================================

class Minimap extends Control:
	const S := 272.0
	var hud
	var _base: ImageTexture
	var _fog_img: Image
	var _fog_tex: ImageTexture
	var _fog_t := 0.0
	var _fog_rect: TextureRect
	var _drag := false

	func _ready() -> void:
		size = Vector2(S, S)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _to_mm(p: Vector2) -> Vector2:
		return Vector2((p.x + SimMap.HALF) / (2.0 * SimMap.HALF), 1.0 - (p.y + SimMap.HALF) / (2.0 * SimMap.HALF)) * S

	func _from_mm(m: Vector2) -> Vector2:
		return Vector2(m.x / S * 2.0 * SimMap.HALF - SimMap.HALF, (1.0 - m.y / S) * 2.0 * SimMap.HALF - SimMap.HALF)

	func _build_base() -> void:
		var map: SimMap = hud.game.map
		var n := SimMap.N
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for cy in n:
			for cx in n:
				var p := map.cell_center(cx, cy)
				var l := map.level[cy * n + cx]
				var c := Color(0.27, 0.42, 0.2)
				if (p.x + p.y) > 600.0:
					c = Color(0.3, 0.3, 0.22)
				if l == SimMap.RIVER:
					c = Color(0.18, 0.42, 0.58)
				elif l == SimMap.HIGH:
					c = Color(0.52, 0.5, 0.42) if p.x + p.y < 0.0 else Color(0.36, 0.3, 0.3)
				if map.tree_cell[cy * n + cx] >= 0:
					c = Color(0.12, 0.26, 0.1) if (p.x + p.y) < 600.0 else Color(0.2, 0.14, 0.16)
				elif map.is_cliff_cell(cx, cy):
					c = Color(0.25, 0.22, 0.2)
				img.set_pixel(cx, n - 1 - cy, c)
		# lanes
		for k in map.lanes:
			for line in [map.lanes[k], _neg(map.lanes[k])]:
				for i in line.size() - 1:
					var a: Vector2 = line[i]
					var b: Vector2 = line[i + 1]
					var steps := int(a.distance_to(b) / 40.0)
					for s in steps:
						var q := a.lerp(b, float(s) / steps)
						var c2 := map.world_to_cell(q)
						for oy in range(-2, 3):
							for ox in range(-2, 3):
								var x := clampi(c2.x + ox, 0, n - 1)
								var y := clampi(n - 1 - c2.y + oy, 0, n - 1)
								img.set_pixel(x, y, Color(0.6, 0.52, 0.38))
		_base = ImageTexture.create_from_image(img)
		_fog_img = Image.create(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8)
		_fog_tex = ImageTexture.create_from_image(_fog_img)
		# the vision grid (0 / 1 bytes, south row first) is drawn through a small shader: flip, scale, darken
		_fog_rect = TextureRect.new()
		_fog_rect.texture = _fog_tex
		_fog_rect.size = Vector2(S, S)
		_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;
void fragment() { float v = clamp(texture(TEXTURE, vec2(UV.x, 1.0 - UV.y)).r * 255.0, 0.0, 1.0); COLOR = vec4(0.02, 0.03, 0.05, (1.0 - v) * 0.6); }"
		sm.shader = sh
		_fog_rect.material = sm
		_fog_rect.show_behind_parent = false
		add_child(_fog_rect)

	func _neg(a: PackedVector2Array) -> PackedVector2Array:
		var o := PackedVector2Array()
		for p in a:
			o.append(-p)
		return o

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("Minimap", t0)

	func _draw_body() -> void:
		if hud.game == null or hud.game.world == null:
			return
		if _base == null:
			_build_base()
		var w: SimWorld = hud.game.world
		var team: int = hud.game.player_team
		draw_texture_rect(_base, Rect2(Vector2.ZERO, Vector2(S, S)), false)
		_fog_t -= get_process_delta_time()
		if _fog_t <= 0.0:
			_fog_t = 0.2
			_fog_img.set_data(SimMap.VN, SimMap.VN, false, Image.FORMAT_L8, w.vision.visible[team])
			_fog_tex.update(_fog_img)
		# buildings, creeps and neutrals go into one triangle batch (one draw call instead of one per dot); heroes are
		# drawn after them, on top
		var heroes: Array[SimUnit] = []
		for u in w.units:
			if not u.alive:
				continue
			if u.is_building():
				if u.kind == K.FOUNTAIN:
					continue
				var col := U.DAWN if u.team == 0 else U.DUSK
				var sz := 7.0 if u.kind == K.TOWER else (11.0 if u.kind == K.ANCIENT else 6.0)
				var bp := _to_mm(u.pos)
				_quad(Rect2(bp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0, 0, 0, 0.8))
				_quad(Rect2(bp - Vector2(sz - 2, sz - 2) * 0.5, Vector2(sz - 2, sz - 2)), col)
				continue
			if u.team != team and not w.vision.sees(team, u):
				continue
			# Master of Shadows: gone from the enemy's minimap
			if u.team != team and u.has_flag("minimap_hidden"):
				continue
			if u.is_hero():
				heroes.append(u)
				continue
			var p := _to_mm(u.pos)
			if u.team == C.NEUTRAL:
				_quad(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.95, 0.85, 0.35))
			elif u.kind == K.WARD:
				_quad(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.9, 0.3))
			else:
				_quad(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), (U.DAWN if u.team == 0 else U.DUSK).lightened(0.1))
		_flush_tris()
		for u in heroes:
			var hp2 := _to_mm(u.pos)
			var col2 := U.DAWN if u.team == 0 else U.DUSK
			if u.id == hud.game.player_hero_id:
				col2 = Color(0.35, 1.0, 0.45)
			draw_circle(hp2, 6.5, Color(0, 0, 0, 0.9))
			draw_circle(hp2, 5.0, col2)
			if u.team != team and w.vision.revealed_to(u, team):
				draw_arc(hp2, 9.0, 0.0, TAU, 20, Color(0.75, 0.4, 1.0), 2.0)
		# neutral camps: Dota's tier marks (a triangle; one bar for medium, two for large, a triangle in a triangle for
		# ancient); with Alt held, the spawn boxes too
		var show_boxes: bool = hud.game.camps != null and hud.game.camps.boxes_wanted()
		for c in w.map.camps:
			_camp_mark(c, show_boxes)
		_flush_tris()
		if _lines.size() > 0:
			draw_multiline(_lines, Color(1.0, 0.86, 0.35, 0.95), 1.4)
			_lines.clear()
		# orbs your team can see: a dot in the orb's colour with a dark rim
		for o in w.orbs.orbs:
			if not w.vision.cell_visible(team, o.pos):
				continue
			var op := _to_mm(o.pos)
			draw_circle(op, 5.0, Color(0, 0, 0, 0.9))
			draw_circle(op, 3.6, OrbView.COLORS.get(String(o.kind), Color(1, 1, 1)))
		# map sites: Warp Gates (violet rings), Lily Ponds (pink, with the lilies there when in sight), Lookout Lamps
		# (a diamond in the holding team's colour, grey when dark or not in sight)
		for s in w.sites.sites:
			var sp := _to_mm(s.pos)
			var seen: bool = w.vision.cell_visible(team, s.pos)
			match String(s.kind):
				"gate":
					draw_circle(sp, 6.0, Color(0, 0, 0, 0.85))
					draw_arc(sp, 4.6, 0.0, TAU, 16, Color(0.72, 0.5, 1.0), 2.2)
				"pond":
					draw_circle(sp, 5.5, Color(0, 0, 0, 0.85))
					draw_circle(sp, 4.0, Color(1.0, 0.6, 0.8))
					if seen and int(s.lilies) > 0:
						U.text_c(self, str(int(s.lilies)), sp + Vector2(0, -9), 12, Color(1.0, 0.85, 0.92), "bold")
				"lamp":
					var lc := Color(0.6, 0.6, 0.6)
					if seen and int(s.team) >= 0 and w.time < float(s.until):
						lc = UiKit.team_color(int(s.team))
					var dia := PackedVector2Array([sp + Vector2(0, -5), sp + Vector2(5, 0), sp + Vector2(0, 5), sp + Vector2(-5, 0)])
					draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -6.5), sp + Vector2(6.5, 0), sp + Vector2(0, 6.5),
						sp + Vector2(-6.5, 0)]), Color(0, 0, 0, 0.85))
					draw_colored_polygon(dia, lc)
		# pings from the whole team: pulsing rings for three seconds (gold: here, red: attack or danger, green: defend)
		for pg in w.pings:
			var age: float = w.time - float(pg.t)
			if int(pg.team) != team or age >= 3.0:
				continue
			var mp := _to_mm(pg.pos)
			var k := fmod(age, 0.75) / 0.75
			var pc: Color = {"attack": Color(1.0, 0.35, 0.3), "danger": Color(1.0, 0.2, 0.2), "defend": Color(0.4, 1.0, 0.5)}.get(String(pg.kind), Color(1.0, 0.85, 0.3))
			draw_arc(mp, 4.0 + k * 14.0, 0.0, TAU, 24, Color(pc, 1.0 - k), 2.0)
			draw_circle(mp, 3.0, pc)
			if String(pg.kind) == "danger":
				U.text_c(self, "!", mp + Vector2(0, -8), 16, pc, "bold")
		# camera frame
		var cam: CameraRig = hud.game.camera
		var vs := get_viewport_rect().size
		var corners := [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y - BottomPanel.H * 0.5), Vector2(0, vs.y - BottomPanel.H * 0.5)]
		var pts := PackedVector2Array()
		for c in corners:
			pts.append(_to_mm(cam.ground_at(c)))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 1.5)
		# the frame over the map's edge, then the Fortify button above its top right corner
		U.art(self, "hud_minimap", Vector2(-14, -14))
		var gr := Rect2(S - 46, -64, 46, 46)
		var ghov := gr.has_point(get_local_mouse_position())
		U.skin(self, "btn_hover" if ghov else "btn_normal", gr)
		var gi: Texture2D = U.icon("status/fortified")
		var cd := maxf(0.0, w.glyph_ready_at[team] - w.time)
		if gi:
			draw_texture_rect(gi, gr.grow(-6), false, U.GOLD if cd <= 0.0 else Color(0.4, 0.4, 0.4))
		if cd > 0.0:
			U.text_c(self, str(ceili(cd)), gr.get_center() + Vector2(0, 6), 14, Color(1, 1, 1), "bold")
		if gr.has_point(get_local_mouse_position()):
			var tl: Array = [["Fortify", 18, U.GOLD, "title"],
				["Your buildings take no damage for 7 seconds and your lane creeps for 3.", 14, U.TEXT, "body"],
				["Tier 2+ towers meanwhile: splash within 300, shots 50% faster, and each hit marks the", 14, U.TEXT, "body"],
				["enemy for 15 s; every mark adds 50 physical damage to their shots.", 14, U.TEXT, "body"],
				["Cooldown 5 minutes. (%s)" % Keybinds.key_name("glyph"), 13, U.TEXT_DIM, "body"]]
			if cd > 0.0:
				tl.append(["Ready in %d s" % ceili(cd), 13, Color(1.0, 0.6, 0.5), "bold"])
			hud.show_tip(get_global_mouse_position(), tl)

	## Batched drawing: rectangles and triangles collect here and go to the renderer as one triangle array.
	var _tp := PackedVector2Array()
	var _tc := PackedColorArray()
	var _ti := PackedInt32Array()
	var _lines := PackedVector2Array()          # camp mark outlines, drawn as one multiline

	func _quad(r: Rect2, c: Color) -> void:
		var b := _tp.size()
		_tp.append(r.position)
		_tp.append(Vector2(r.end.x, r.position.y))
		_tp.append(r.end)
		_tp.append(Vector2(r.position.x, r.end.y))
		for k in 4:
			_tc.append(c)
		_ti.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))

	func _tri(a: Vector2, b2: Vector2, c2: Vector2, c: Color) -> void:
		var b := _tp.size()
		_tp.append(a)
		_tp.append(b2)
		_tp.append(c2)
		for k in 3:
			_tc.append(c)
		_ti.append_array(PackedInt32Array([b, b + 1, b + 2]))

	func _flush_tris() -> void:
		if not _ti.is_empty():
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _ti, _tp, _tc)
		_tp.clear()
		_tc.clear()
		_ti.clear()

	func _seg(a: Vector2, b: Vector2) -> void:
		_lines.append(a)
		_lines.append(b)

	func _camp_mark(c: Dictionary, boxes: bool) -> void:
		var p := _to_mm(c.pos)
		var sz := 5.0 if c.kind != "ancient" else 7.0
		var ta := p + Vector2(0, -sz)
		var tb := p + Vector2(sz * 0.9, sz * 0.6)
		var td := p + Vector2(-sz * 0.9, sz * 0.6)
		_tri(ta, tb, td, Color(0, 0, 0, 0.75))
		_seg(ta, tb)
		_seg(tb, td)
		_seg(td, ta)
		match String(c.kind):
			"medium":
				_seg(p + Vector2(-sz * 0.8, sz + 2.0), p + Vector2(sz * 0.8, sz + 2.0))
			"large":
				_seg(p + Vector2(-sz * 0.8, sz + 2.0), p + Vector2(sz * 0.8, sz + 2.0))
				_seg(p + Vector2(-sz * 0.8, sz + 4.5), p + Vector2(sz * 0.8, sz + 4.5))
			"ancient":
				var t0 := p + Vector2(0, -sz * 0.45)
				var t1 := p + Vector2(sz * 0.4, sz * 0.3)
				var t2 := p + Vector2(-sz * 0.4, sz * 0.3)
				_seg(t0, t1)
				_seg(t1, t2)
				_seg(t2, t0)
		if boxes:
			var b: Vector2 = c.box
			var a2 := _to_mm((c.pos as Vector2) + Vector2(-b.x, b.y))
			var b2 := _to_mm((c.pos as Vector2) + Vector2(b.x, -b.y))
			draw_rect(Rect2(a2, b2 - a2), Color(1.0, 0.86, 0.3, 0.9), false, 1.2)

	## The Fortify button sits above the map; the frame's border belongs to the map too.
	func _has_point(p: Vector2) -> bool:
		return Rect2(-14, -14, S + 28, S + 28).has_point(p) or Rect2(S - 46, -64, 46, 46).has_point(p)

	func _gui_input(e: InputEvent) -> void:
		var gr := Rect2(S - 46, -64, 46, 46)
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and gr.has_point(mb.position):
				var gerr: String = hud.game.act({"k": "glyph"})
				if gerr != "":
					hud.error(gerr)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.alt_pressed:
				hud.game.input.ping(_from_mm(mb.position), -1, mb.ctrl_pressed)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed and hud.game.input.targeting != "":
					hud.game.input.target_point(_from_mm(mb.position), mb.shift_pressed)
					accept_event()
					return
				_drag = mb.pressed
				if mb.pressed:
					_focus(mb.position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var h: SimUnit = hud.hero()
				hud.game.input.move_selected(_from_mm(mb.position), mb.shift_pressed)
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_focus((e as InputEventMouseMotion).position)
			accept_event()

	func _focus(m: Vector2) -> void:
		var p := _from_mm(Vector2(clampf(m.x, 0, S), clampf(m.y, 0, S)))
		hud.game.camera.focus(View.to3(p, hud.game.terrain.height_at(p)))

# ======================================================================================================================

class TopBar extends Control:
	## The top bar: the clock in a gold medallion (day or night, with the cycle's progress), each team's kills on a
	## plaque, and five hero tiles a side (portrait, level, health, ultimate ready, respawn time when dead).
	const W := 1200.0
	var hud

	func _ready() -> void:
		size = Vector2(W, 80)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("TopBar", t0)

	func _draw_body() -> void:
		if hud.game == null or hud.game.world == null:
			return
		var w: SimWorld = hud.game.world
		U.art(self, "hud_topbar", Vector2.ZERO)
		var cx := W * 0.5
		var night := w.is_night()
		var cyc := fposmod(w.time, C.DAY_LENGTH * 0.5) / (C.DAY_LENGTH * 0.5) if w.time >= 0.0 else 0.0
		var dn_col := Color(0.6, 0.75, 1.0) if night else Color(1.0, 0.85, 0.4)
		U.text_c(self, w.clock_text(), Vector2(cx, 33), 28, U.TEXT, "title")
		var ic: Texture2D = U.icon("status/frozen" if night else "status/empowered")
		if ic:
			draw_texture_rect(ic, Rect2(cx - 50, 40, 16, 16), false, dn_col)
		U.text(self, "Night" if night else "Day", Vector2(cx - 30, 54), 13, dn_col, "title")
		draw_arc(Vector2(cx + 46, 48), 9, 0, TAU, 24, Color(0, 0, 0, 0.7), 4.0, true)
		draw_arc(Vector2(cx + 46, 48), 9, -PI * 0.5, -PI * 0.5 + TAU * cyc, 24, dn_col, 3.0, true)
		var kills := [0, 0]
		for h in w.heroes:
			kills[h.team] += h.kills
		U.text_c(self, str(kills[0]), Vector2(470, 34), 28, U.DAWN, "title")
		U.text_c(self, str(kills[1]), Vector2(730, 34), 28, U.DUSK, "title")
		tiles.clear()
		var slot := [0, 0]
		for h in w.heroes:
			var i: int = slot[h.team]
			slot[h.team] += 1
			if i >= 5:
				continue
			var x := 346.0 - i * 70.0 if h.team == 0 else 784.0 + i * 70.0
			var r := Rect2(x + 2, 6, 60, 40)
			tiles.append([r, h.id])
			var col := U.DAWN if h.team == 0 else U.DUSK
			var seen: bool = h.team == hud.game.player_team or w.vision.sees(hud.game.player_team, h)
			var pt: Texture2D = U.hero_portrait(String(h.def.id))
			draw_rect(r, Color(0.05, 0.06, 0.08))
			if pt:
				# the face, cropped to the tile's shape
				var ts := pt.get_size()
				var src_h := ts.x * r.size.y / r.size.x
				draw_texture_rect_region(pt, r, Rect2(0, ts.y * 0.08, ts.x, src_h), Color(1, 1, 1) if h.alive else Color(0.28, 0.28, 0.3))
			U.skin(self, "slot_small", r.grow(3), col.lerp(Color.WHITE, 0.55), false)
			# health under the tile (unknown in the fog)
			var hb := Rect2(r.position.x, r.end.y + 4, r.size.x, 5)
			draw_rect(hb.grow(1), Color(0, 0, 0, 0.85))
			if seen and h.alive:
				draw_rect(Rect2(hb.position, Vector2(hb.size.x * h.hp / maxf(1.0, h.max_hp), hb.size.y)),
					Color(0.3, 0.85, 0.3) if h.team == hud.game.player_team else Color(0.9, 0.25, 0.2))
			var lr := Rect2(r.position + Vector2(0, r.size.y - 15), Vector2(17, 15))
			draw_rect(lr, Color(0, 0, 0, 0.75))
			U.text_c(self, str(h.level), lr.get_center() + Vector2(0, 5), 12, Color(1, 0.92, 0.7), "bold")
			var ult: String = SimData.ultimate_of(h.abilities)
			if ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) <= 0.0 and h.alive:
				U.art_rect(self, "gem_gold", Rect2(r.end.x - 13, r.position.y + 1, 12, 12))
			if not h.alive:
				var left := maxf(0.0, h.respawn_at - w.time)
				U.text_c(self, str(ceili(left)), r.get_center() + Vector2(0, 9), 22, Color(1, 0.9, 0.85), "title")

	var tiles: Array = []                   # [[rect, hero id]]

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			for t in tiles:
				if (t[0] as Rect2).has_point((e as InputEventMouseButton).position):
					var h: SimUnit = hud.game.world.get_unit(t[1])
					var w: SimWorld = hud.game.world
					if h and h.alive and (h.team == hud.game.player_team or w.vision.sees(hud.game.player_team, h)):
						hud.game.camera.focus(View.to3(h.pos, hud.game.terrain.height_at(h.pos)))
						hud.game.input.select([h.id])
					accept_event()
					return

# ======================================================================================================================

# ======================================================================================================================

class Tip extends Control:
	var hud
	var showing := false                       # whether the last draw showed a tooltip (probes read it)

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_body()
		UiKit.draw_cost("Tip", t0)

	func _draw_body() -> void:
		var lines: Array = hud._tip_lines
		# panels only redraw at 20 Hz: keep showing the last tooltip while the mouse stays over them
		if lines.is_empty() and hud._last_tip.size() > 0:
			var m := get_viewport().get_mouse_position()
			# each panel's own hit test: the Fortify button sits above the minimap's rectangle and the buff bar and
			# stash above the bottom panel's (a rectangle test let those tooltips blink between redraws)
			for c in [hud.bottom, hud.minimap, hud.shop]:
				var lp: Vector2 = m - c.global_position
				var over: bool = (Rect2(Vector2.ZERO, c.size).has_point(lp)
					or (c == hud.bottom and hud.bottom.covers_extra(lp)) or (c == hud.minimap and hud.minimap._has_point(lp)))
				if c.visible and over:
					lines = hud._last_tip
					break
			if lines.is_empty() and hud.card_rect.has_point(m):
				lines = hud._last_tip
		if lines.is_empty():
			hud._last_tip = []
		showing = not lines.is_empty()
		if lines.is_empty():
			return
		var wmax := 0.0
		var hsum := 14.0
		for l in lines:
			wmax = maxf(wmax, U.font(l[3]).get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x)
			hsum += float(l[1]) + 6.0
		var vs := get_viewport_rect().size
		var p: Vector2 = hud._tip_at + Vector2(18, -hsum - 10)
		p.x = clampf(p.x, 4, vs.x - wmax - 34)
		p.y = clampf(p.y, 4, vs.y - hsum - 4)
		U.panel(self, Rect2(p, Vector2(wmax + 28, hsum)), U.GOLD, 6)
		var y := p.y + 8.0
		for l in lines:
			y += float(l[1]) + 2.0
			U.text(self, l[0], Vector2(p.x + 14, y), l[1], l[2], l[3])
			y += 4.0
