extends Control
## In-match menus: the pause menu (Esc / F10: Resume, Options, Hero Select, Quit) and the end-of-match screen
## (winner, then each hero's level, kills / deaths / assists, last hits / denies, net worth). In a multiplayer match the
## menu never stops the game here (the other players play on): Pause Game pauses it for everyone, Leave Game hands the
## hero to a bot and goes back to the server's lobby list, and the end screen leads back to the lobby.

const U = preload("res://src/ui/ui_kit.gd")
const NET_MENU := "res://src/ui/net_menu.tscn"
const RANKED := "res://src/ui/ranked_menu.tscn"
const MAIN_MENU := "res://src/ui/main_menu.tscn"

var game: Node
var _pause: PanelContainer
var _options: OptionsPanel
var _end: PanelContainer
var _end_shown := false
var _pause_btn: Button
var _ranked_result := {}                   # a ranked match's MMR result (Ranked.finish_match)

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mp: bool = game != null and bool(game.get("multiplayer_match"))
	_pause = _panel("Menu" if mp else "Paused")
	var col: VBoxContainer = _pause.get_child(0)
	if mp:
		col.add_child(_button("Resume", _resume))
		_pause_btn = _button("Pause Game", _toggle_game_pause)
		col.add_child(_pause_btn)
		col.add_child(_button("Options", _open_options))
		col.add_child(_button("Leave Game", _leave_game))
		col.add_child(_button("Quit to desktop", func(): get_tree().quit()))
	elif _ranked():
		# a ranked match: leaving counts as a loss (Ranked.abandon_pending), as in Dota
		for b in [["Resume", _resume], ["Options", _open_options], ["Leave match", _leave_ranked],
				["Quit to desktop", func():
					Ranked.abandon_pending()
					get_tree().quit()]]:
			col.add_child(_button(b[0], b[1]))
		var warn := Label.new()
		warn.text = "Leaving a ranked match counts as a loss."
		warn.theme_type_variation = "DimLabel"
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(warn)
	else:
		for b in [["Resume", _resume], ["Options", _open_options], ["Hero Select", _to_creator], ["Quit to desktop", func(): get_tree().quit()]]:
			col.add_child(_button(b[0], b[1]))
	_end = _panel("")
	for p in [_pause, _end]:
		p.visible = false

func _panel(title: String) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	if title != "":
		var l := Label.new()
		l.text = title
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", U.font("title"))
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", U.GOLD)
		v.add_child(l)
	center.add_child(p)
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

func is_open() -> bool:
	return _pause.visible or (_options != null and is_instance_valid(_options))

func toggle() -> void:
	if _end.visible:
		return
	if is_open():
		_resume()
	else:
		_pause.visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		if game.net == null and not game.multiplayer_match:
			game.world.paused = true
		_refresh_pause_btn()

func _resume() -> void:
	_pause.visible = false
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if game.net == null and not game.multiplayer_match:
		game.world.paused = false

func _open_options() -> void:
	_pause.visible = false
	_options = OptionsPanel.new()
	_options.game = game
	_options.closed.connect(func():
		_options = null
		_pause.visible = true)
	add_child(_options)

## Multiplayer: pause or unpause the game for every player (a command every machine runs at the same tick).
func _toggle_game_pause() -> void:
	if game.net != null:
		game.act({"k": "resume" if game.world.paused else "pause"})
	else:
		game.world.paused = not game.world.paused
	_resume()

func _refresh_pause_btn() -> void:
	if _pause_btn:
		_pause_btn.text = "Unpause Game" if game.world.paused else "Pause Game"

## Multiplayer: a bot takes the hero over (you can come back from the lobby list while the match runs) and you go back
## to the server's lobby list.
func _leave_game() -> void:
	get_tree().paused = false
	var n := NetSession.inst
	if n != null and n.active():
		n.leave_room()
		n.back_from_match()
	get_tree().change_scene_to_file(NET_MENU)

func _back_to_lobby() -> void:
	get_tree().paused = false
	var n := NetSession.inst
	if n != null:
		n.back_from_match()
	get_tree().change_scene_to_file(NET_MENU)

## How well you played, 0..1, for your hero XP (Ranked.hero_xp_gain): kills and assists against deaths (35%), your
## net worth's place among the ten (25%), your share of your team's hero damage (25%), last hits for the time (15%).
static func _performance(w: SimWorld, h: SimUnit) -> float:
	var kda := clampf((float(h.kills) + float(h.assists) * 0.6) / maxf(1.0, float(h.deaths)) / 5.0, 0.0, 1.0)
	var better := 0
	var team_dmg := 0.0
	for o in w.heroes:
		if o != h and o.networth() > h.networth():
			better += 1
		if o.team == h.team:
			team_dmg += float(Scoreboard.totals(o).hero)
	var nw := 1.0 - float(better) / maxf(1.0, float(w.heroes.size() - 1))
	var dmg := clampf(float(Scoreboard.totals(h).hero) / maxf(1.0, team_dmg) * 2.5, 0.0, 1.0)
	var lh := clampf(float(h.last_hits) / maxf(1.0, w.time / 60.0 * 5.0), 0.0, 1.0)
	return clampf(0.35 * kda + 0.25 * nw + 0.25 * dmg + 0.15 * lh, 0.0, 1.0)

func _ranked() -> bool:
	return game != null and bool(game.get("ranked_match"))

## Leave a ranked match: a loss (and a little behaviour score), back to the Ranked screen.
func _leave_ranked() -> void:
	Ranked.abandon_pending()
	GameSettings.ranked = []
	get_tree().paused = false
	get_tree().change_scene_to_file(RANKED)

func _to_creator() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/hero_select.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_F10 or (k.keycode == KEY_ESCAPE and game.input and game.input.targeting == ""):
			toggle()
			get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if _pause.visible:
		_refresh_pause_btn()
	if game and game.world and game.world.winner >= 0 and not _end_shown:
		_end_shown = true
		if game.net != null and NetSession.inst != null:
			NetSession.inst.report_match_over()
		if _ranked() and Ranked.has_pending():
			var me_h: SimUnit = game.world.get_unit(game.player_hero_id)
			var ex := {}
			if me_h != null:
				ex = {"k": me_h.kills, "x": me_h.deaths, "a": me_h.assists, "nw": me_h.networth(),
					"len": maxi(0, int(game.world.time)), "perf": _performance(game.world, me_h),
					"rel": game.world.botchat.relations()}
			_ranked_result = Ranked.finish_match(game.world.winner == game.player_team, false, ex)
			GameSettings.ranked = []
		get_tree().create_timer(3.0).timeout.connect(_show_end)

func _show_end() -> void:
	var w: SimWorld = game.world
	var v: VBoxContainer = _end.get_child(0)
	_end.custom_minimum_size = Vector2(760, 0)
	var won: bool = w.winner == game.player_team or bool(game.get("spectator"))
	var t := Label.new()
	t.text = ("%s wins" % SimConst.TEAM_NAMES[w.winner]) if bool(game.get("spectator")) else ("Victory" if won else "Defeat")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", U.font("title"))
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", U.GOLD if won else U.DUSK)
	v.add_child(t)
	var sub := Label.new()
	sub.text = "%s wins at %s" % [SimConst.TEAM_NAMES[w.winner], w.clock_text()]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_end.custom_minimum_size = Vector2(1180, 0)
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 22)
	for hdr in ["Hero", "Team", "Level", "K / D / A", "LH / DN", "Net worth", "GPM", "XPM", "Hero dmg", "Building dmg", "Taken", "Healing"]:
		var l := Label.new()
		l.text = hdr
		l.add_theme_color_override("font_color", U.GOLD)
		grid.add_child(l)
	var minutes := maxf(w.time / 60.0, 0.25)
	for h in w.heroes:
		var tot := Scoreboard.totals(h)
		for val in [String(h.look.get("display_name", h.name)), SimConst.TEAM_NAMES[h.team], str(h.level),
				"%d / %d / %d" % [h.kills, h.deaths, h.assists], "%d / %d" % [h.last_hits, h.denies], str(h.networth()),
				str(int(h.gold_earned / minutes)), str(int(h.xp / minutes)), str(int(tot.hero)), str(int(tot.building)),
				str(int(tot.taken)), str(int(h.healed))]:
			var l2 := Label.new()
			l2.text = val
			grid.add_child(l2)
	v.add_child(grid)
	if not _ranked_result.is_empty():
		v.add_child(_mmr_panel(_ranked_result))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	if game.multiplayer_match:
		var online := NetSession.inst != null and NetSession.inst.active()
		row.add_child(_button("Back to Lobby" if online else "Multiplayer", _back_to_lobby))
	elif _ranked() or not _ranked_result.is_empty():
		row.add_child(_button("Find Match", func():
			get_tree().paused = false
			get_tree().change_scene_to_file(RANKED)))
		row.add_child(_button("Main Menu", func():
			get_tree().paused = false
			get_tree().change_scene_to_file(MAIN_MENU)))
	else:
		row.add_child(_button("Play again", func(): get_tree().reload_current_scene()))
		row.add_child(_button("Hero Select", _to_creator))
	row.add_child(_button("Quit", func(): get_tree().quit()))
	v.add_child(row)
	_end.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

## The ranked result under the scoreboard: MMR before and after, the change, and the rank (with "Rank up" or "Rank
## down" when it changed) beside its emblem.
func _mmr_panel(r: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	var em := RankEmblem.Icon.new()
	em.custom_minimum_size = Vector2(96, 96)
	em.tier = int(r.new_tier)
	box.add_child(em)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var d := int(r.delta)
	var head := Label.new()
	head.text = "Ranked: %s MMR" % ("%+d" % d)
	if bool(r.get("abandon", false)):
		head.text += " (left the match)"
	head.add_theme_font_override("font", U.font("title"))
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Color(0.45, 0.95, 0.5) if d > 0 else Color(1.0, 0.45, 0.4))
	col.add_child(head)
	var line := Label.new()
	line.text = "%d  ->  %d MMR    %s" % [int(r.old), int(r.new), Ranked.rank_label(Ranked.me())]
	col.add_child(line)
	if int(r.new_tier) != int(r.old_tier):
		var up := Label.new()
		up.text = ("Rank up: " if int(r.new_tier) > int(r.old_tier) else "Rank down: ") + Ranked.tier_name(int(r.new_tier))
		up.theme_type_variation = "HeadingLabel"
		col.add_child(up)
	# your hero's XP and medal
	if String(r.get("hero", "")) != "" and r.has("hero_new"):
		var hn: Dictionary = r.hero_new
		var ho: Dictionary = r.get("hero_old", {})
		var hb := HeroBadge.new()
		hb.hero = String(r.hero)
		hb.info = hn
		hb.label = false
		hb.custom_minimum_size = Vector2(96, 96)
		box.add_child(hb)
		var hc := VBoxContainer.new()
		hc.add_theme_constant_override("separation", 2)
		box.add_child(hc)
		var hl := Label.new()
		hl.text = "%s  +%d hero XP" % [HeroDraft.hero_name(String(r.hero)), int(r.get("hero_xp", 0))]
		hl.add_theme_font_override("font", U.font("title"))
		hl.add_theme_font_size_override("font_size", 24)
		hl.add_theme_color_override("font_color", HeroBadge.metal(hn))
		hc.add_child(hl)
		var hl2 := Label.new()
		hl2.text = "%s  ·  %s / %s XP to the next star" % [String(hn.name), RankedNum.num(int(hn.xp)), RankedNum.num(int(hn.next))]
		hc.add_child(hl2)
		if int(hn.level) > int(ho.get("level", 0)):
			var st := Label.new()
			st.theme_type_variation = "HeadingLabel"
			st.text = ("New medal: " + String(Ranked.MEDALS[int(hn.medal)])) if int(hn.medal) > int(ho.get("medal", 0)) else "New star: " + String(hn.name)
			hc.add_child(st)
	return box
