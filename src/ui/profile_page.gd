class_name ProfilePage
extends Control
## A player's profile (run 2026-10-20; the owner: "Introduce an upgraded and polished Profile UI ... Profile needs to
## include Player averages like LH/D, KDA, Fave lanes ... First Bloods, Triple Kills, Rampages ... add 'View As' in your
## player profile to view what others can see in your profile"). 1840 x 920 (the Ranked screen's page; Forums and
## other screens open it as an overlay with ProfilePage.overlay):
##   * the banner: picture, name, status, where they are, labels, what they think of you; the trophy shelf (MVPs,
##     Rampages, Triple Kills, First Bloods, Commends); the rank emblem (drag to turn it), MMR, place, the way to the next
##     rank; buttons (yours: Edit profile, View As; theirs: Add friend, Compare, Write, More);
##   * Averages over the last 20 matches or all matches: K/D/A, KDA, last hits / denies, last hits a minute, gold and
##     experience a minute, hero damage, win rate; favourite lanes as bars;
##   * Match history (All, Ranked, Unranked): result, hero, lane, K/D/A, LH / DN, GPM, MVP / Rampage / Triple Kill /
##     First Blood badges, the MMR change; click a match for every number, right-click for more;
##   * Wall (what players wrote on the profile, with yours and their answers; your recent visitors), Heroes (medals),
##     MMR (graph, peak, streaks, behaviour; behaviour and visitors are private);
##   * View As: Yourself, Public (what anyone sees) or a player you know (what they see, and what they think of you).
## Right-click any player (wall, visitors) for the player menu. Compare with me opens a side-by-side panel.

signal back_pressed
signal changed                              # your name or picture changed (the screen's chip redraws)

const U = preload("res://src/ui/ui_kit.gd")
const S = preload("res://src/ui/social_ui.gd")
const PW := 1840.0
const PH := 920.0
const TOP := 266.0

var pid := "me"
var view_as := ""                            # yours: "" yourself, "public", or a player's id
var avg_mode := "recent"                     # "recent" (last 20) or "all"
var hist_filter := ""                        # "", "ranked", "casual"
var side_tab := "wall"                       # "wall", "heroes", "mmr", "visitors"
var came_from := ""                          # shown on the Back button ("Leaderboard", "Players", "Forums")
var _root: Control
var _open := -1                              # the expanded match row
var _file_dialog: FileDialog
var _wall_edit: LineEdit
var _rng := RandomNumberGenerator.new()
var _compare: Control
var _edit: Control
var overlay_mode := false                     # opened over another screen (ProfilePage.overlay): Esc closes it

func _ready() -> void:
	theme = U.theme()
	size = Vector2(PW, PH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.title = "Choose a picture"
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	_file_dialog.file_selected.connect(func(path: String):
		var err := Avatar.import_picture(path)
		if err != "":
			_notice(err)
		else:
			Ranked.set_avatar({"k": "custom", "file": Avatar.custom_path(Ranked.account_id())})
			_notice("Picture changed.")
		changed.emit()
		refresh())
	add_child(_file_dialog)

## Show a player's profile (resets the view to its start).
func show_id(id: String, from := "") -> void:
	pid = id if not Ranked.profile(id).is_empty() else "me"
	came_from = from
	view_as = ""
	_open = -1
	hist_filter = ""
	if side_tab == "visitors" and pid != "me":
		side_tab = "wall"
	refresh()

## Whether the page shows your own editable profile (not another's, not a View As).
func own_edit() -> bool:
	return pid == "me" and view_as == ""

## Private parts (behaviour score, visitors, reports) show only on your own profile, not in a View As.
func private_ok() -> bool:
	return own_edit()

func refresh() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.size = Vector2(PW, PH)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var p := Ranked.profile(pid)
	if bool(p.get("bot", false)):
		ProfileTalk.wall_of(p)                  # a ladder player's wall is made the first time it is looked at
	_build_banner(p)
	_build_averages(p)
	_build_history(p)
	_build_side(p)

func _notice(t: String) -> void:
	var host := get_tree().current_scene if is_inside_tree() else null
	if host != null and host.has_method("notice"):
		host.call("notice", t)

func _label(text: String, px: int, col := U.TEXT, kind := "body", parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l

func _button(text: String, cb: Callable, variation := "DarkButton", min_size := Vector2(0, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

# ---- Banner ----------------------------------------------------------------------------------------------------------

func _build_banner(p: Dictionary) -> void:
	var b := Banner.new()
	b.page = self
	b.p = p
	b.position = Vector2.ZERO
	b.size = Vector2(PW, 250)
	_root.add_child(b)
	var av := Avatar.new()
	av.position = Vector2(42, 34)
	av.size = Vector2(182, 182)
	av.frame = Color(0, 0, 0, 0)
	av.set_spec(p.get("avatar", {"k": "none"}))
	av.mouse_filter = Control.MOUSE_FILTER_STOP
	av.gui_input.connect(func(e: InputEvent):
		if S.is_right(e):
			PlayerMenu.open(self, pid, SocialUi.at(av, e))
		elif S.is_left(e) and own_edit():
			_open_edit())
	if own_edit():
		av.tooltip_text = "Change picture"
		av.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_child(av)
	var fr := TextureRect.new()
	fr.texture = U.skin_tex("soc_avatar")
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.position = Vector2(26, 18)
	fr.size = Vector2(214, 214)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fr)
	# buttons
	var row := HBoxContainer.new()
	row.position = Vector2(262, 186)
	row.add_theme_constant_override("separation", 10)
	b.add_child(row)
	if came_from != "" and pid != "me":
		row.add_child(_button("Back", func(): back_pressed.emit(), "DarkButton", Vector2(96, 40)))
	if pid == "me":
		if own_edit():
			row.add_child(_button("Edit profile", _open_edit, "DarkButton", Vector2(150, 40)))
		var va := _button("View As: %s" % _view_as_name() + "  ▾", func(): pass, "GoldButton" if view_as != "" else "DarkButton", Vector2(220, 40))
		va.pressed.connect(func(): _view_as_menu(va))
		row.add_child(va)
		if view_as != "":
			row.add_child(_button("Back to my view", func():
				view_as = ""
				refresh(), "DarkButton", Vector2(170, 40)))
	else:
		var friend := pid in (Ranked.me().get("friends", []) as Array)
		row.add_child(_button("Remove friend" if friend else "Add friend", func():
			if pid in (Ranked.me().get("friends", []) as Array):
				Ranked.remove_friend(pid)
				_notice("Removed from your friends.")
			elif Ranked.ask_friend(pid):
				_notice("%s accepted your friend request." % String(Ranked.profile(pid).get("name", "")))
			else:
				_notice("%s did not answer your friend request." % String(Ranked.profile(pid).get("name", "")))
			refresh(), "DarkButton", Vector2(150, 40)))
		row.add_child(_button("Compare", func(): open_compare(), "DarkButton", Vector2(116, 40)))
		row.add_child(_button("Write", func():
			side_tab = "wall"
			refresh()
			if _wall_edit:
				_wall_edit.grab_focus(), "DarkButton", Vector2(90, 40)))
		var more := _button("More  ▾", func(): pass, "DarkButton", Vector2(100, 40))
		more.pressed.connect(func(): PlayerMenu.open(self, pid, more.get_global_rect().position + Vector2(0, more.get_global_rect().size.y)))
		row.add_child(more)
	# trophies
	var mo := Career.moments(p)
	var tx := 770.0
	for t in [["mvp", int(mo.mvp), "MVPs"], ["rampage", int(mo.rp), "Rampages"], ["triple", int(mo.tr), "Triple Kills"],
			["fb", int(mo.fb), "First Bloods"], ["commend", int(p.get("commends", 0)), "Commends"]]:
		var tr := S.Trophy.new()
		tr.key = String(t[0])
		tr.count = int(t[1])
		tr.title = String(t[2])
		tr.position = Vector2(tx, 40)
		tr.size = Vector2(100, 130)
		tr.tooltip_text = _trophy_tip(String(t[0]), p)
		b.add_child(tr)
		tx += 104.0
	# rank
	var ev := EmblemView.new(220)
	ev.position = Vector2(1300, 18)
	ev.size = Vector2(210, 210)
	ev.show_rank(Ranked.tier_for(p), Ranked.stars(int(p.mmr)))
	ev.tooltip_text = "Drag to turn"
	b.add_child(ev)
	var bar := RankBar.new()
	bar.mmr = int(p.mmr)
	bar.tier = Ranked.tier_for(p)
	bar.position = Vector2(1518, 150)
	bar.size = Vector2(290, 58)
	b.add_child(bar)

func _trophy_tip(k: String, p: Dictionary) -> String:
	var c := Career.career(p)
	match k:
		"mvp":
			return "Most valuable player of the match, %d times in %s" % [int(p.get("mvps", 0)), RankedNum.count(int(c.g), "match", "matches")]
		"rampage":
			return "Five heroes in one fight: %d rampages, %d ultra kills, %d triple kills, %d double kills" % [int(c.rp), int(c.ul), int(c.tr), int(c.db)]
		"triple":
			return "Three heroes in one fight"
		"fb":
			return "The first kill of the match"
		"commend":
			return "Players who commended them after a match or from the player menu"
	return ""

func _view_as_name() -> String:
	if view_as == "":
		return "Yourself"
	if view_as == "public":
		return "Public"
	return String(Ranked.profile(view_as).get("name", "?"))

## The View As choices: yourself, public, your friends and the players you met lately.
func _view_as_menu(from: Control) -> void:
	var entries: Array = [["", "Yourself", "profile"], ["public", "Public: anyone", "visitor"]]
	var seen := {}
	for id in (Ranked.me().get("friends", []) as Array).slice(0, 4):
		if not Ranked.profile(String(id)).is_empty():
			entries.append([String(id), "As %s (friend)" % String(Ranked.profile(String(id)).name), "friend"])
			seen[String(id)] = true
	for e in Ranked.recent_players(12):
		var id2 := String(e[0].id)
		if seen.has(id2) or entries.size() >= 10:
			continue
		entries.append([id2, "As %s" % String(e[0].name), "history"])
	PlayerMenu.open_list(self, from.get_global_rect().position + Vector2(0, from.get_global_rect().size.y), "View As",
		"See your profile the way others do", entries, func(a: String):
			view_as = a
			refresh())

## Esc closes what is on top: Compare, then Edit profile (as Cancel), then the page itself when it is an overlay.
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE):
		return
	if not is_visible_in_tree():
		return
	if _compare != null and is_instance_valid(_compare):
		_compare.queue_free()
		_compare = null
	elif _edit != null and is_instance_valid(_edit):
		_edit.queue_free()
		_edit = null
		refresh()
	elif overlay_mode:
		back_pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()

# ---- Edit profile ------------------------------------------------------------------------------------------------------

func _open_edit() -> void:
	if _edit != null:
		_edit.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(PW, PH)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_edit = dim
	var pan := PanelBox.new()
	pan.position = Vector2((PW - 620) * 0.5, 120)
	pan.size = Vector2(620, 500)
	pan.title = "Edit profile"
	dim.add_child(pan)
	_label("Name", 15, U.TEXT_DIM, "bold", pan).position = Vector2(40, 70)
	var ne := LineEdit.new()
	ne.text = String(Ranked.me().name)
	ne.max_length = 20
	ne.position = Vector2(40, 96)
	ne.size = Vector2(540, 46)
	ne.add_theme_font_size_override("font_size", 20)
	pan.add_child(ne)
	_label("Picture", 15, U.TEXT_DIM, "bold", pan).position = Vector2(40, 162)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 188)
	row.add_theme_constant_override("separation", 12)
	pan.add_child(row)
	row.add_child(_button("Upload a picture", func(): _file_dialog.popup_file_dialog(), "DarkButton", Vector2(200, 44)))
	row.add_child(_button("Use my hero", func():
		var played := Ranked.heroes_played(Ranked.me())
		Ranked.set_avatar({"k": "hero", "id": String(played[0][0]) if not played.is_empty() else GameSettings.selected})
		changed.emit()
		_notice("Picture changed."), "DarkButton", Vector2(160, 44)))
	row.add_child(_button("None", func():
		Ranked.set_avatar({"k": "none"})
		changed.emit(), "DarkButton", Vector2(100, 44)))
	# your record from before your matches were counted (shown in your totals)
	_label("Earlier record (matches before 20 October 2026)", 15, U.TEXT_DIM, "bold", pan).position = Vector2(40, 254)
	var base: Dictionary = Ranked.me().get("career_base", {})
	var spins := {}
	var sx := 40.0
	for k in [["rp", "Rampages"], ["tr", "Triple Kills"], ["fb", "First Bloods"]]:
		_label(String(k[1]), 14, U.TEXT, "body", pan).position = Vector2(sx, 280)
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 9999
		sp.value = int(base.get(String(k[0]), 0))
		sp.position = Vector2(sx, 304)
		sp.size = Vector2(160, 44)
		pan.add_child(sp)
		spins[String(k[0])] = sp
		sx += 180.0
	var row2 := HBoxContainer.new()
	row2.position = Vector2(40, 410)
	row2.add_theme_constant_override("separation", 12)
	pan.add_child(row2)
	var save := _button("Save", func():
		Ranked.set_player_name(ne.text)
		Career.set_base(int((spins.rp as SpinBox).value), int((spins.tr as SpinBox).value), int((spins.fb as SpinBox).value))
		_notice("Profile saved.")
		changed.emit()
		dim.queue_free()
		_edit = null
		refresh(), "GoldButton", Vector2(160, 46))
	row2.add_child(save)
	row2.add_child(_button("Cancel", func():
		dim.queue_free()
		_edit = null
		refresh(), "DarkButton", Vector2(140, 46)))
	ne.text_submitted.connect(func(_t): save.pressed.emit())

# ---- Averages ----------------------------------------------------------------------------------------------------------

func _build_averages(p: Dictionary) -> void:
	var pan := PanelBox.new()
	pan.position = Vector2(0, TOP)
	pan.size = Vector2(560, PH - TOP)
	pan.title = "Averages"
	_root.add_child(pan)
	var tabs := S.Tabs.new()
	tabs.items = [["recent", "Last 20"], ["all", "All matches"]]
	tabs.active = avg_mode
	tabs.position = Vector2(290, 14)
	tabs.size = Vector2(250, 40)
	tabs.changed.connect(func(id: String):
		avg_mode = id
		refresh())
	pan.add_child(tabs)
	var av := Career.averages(p) if avg_mode == "recent" else Career.lifetime(p)
	var n := int(av.get("n", 0))
	var cards := [
		["kill", "K / D / A", Career.kda_text(av), "kills, deaths, assists a match"],
		["streak", "KDA", S.dec(float(av.get("kda", -1.0)), 2), "(kills + assists) / deaths"],
		["lh", "Last hits / denies", "%s / %s" % [S.whole(float(av.get("lh", -1.0))), S.whole(float(av.get("dn", -1.0)))], "a match"],
		["deny", "Last hits a minute", S.dec(float(av.get("lhm", -1.0))), "creeps you finished"],
		["gpm", "Gold a minute", S.whole(float(av.get("gpm", -1.0))), "GPM"],
		["xpm", "Experience a minute", S.whole(float(av.get("xpm", -1.0))), "XPM"],
		["damage", "Hero damage", S.whole(float(av.get("hd", -1.0))), "a match"],
		["win", "Win rate", ("%.0f%%" % (float(av.get("wr", 0.0)) * 100.0)) if n > 0 else "-", "%s counted" % RankedNum.count(n, "match", "matches")]]
	for i in cards.size():
		var c := S.StatCard.new()
		c.key = String(cards[i][0])
		c.title = String(cards[i][1])
		c.value = String(cards[i][2])
		c.sub = String(cards[i][3])
		c.position = Vector2(22 + (i % 2) * 262, 62 + (i / 2) * 92)
		c.size = Vector2(254, 84)
		if i == 0:
			var wr := float(av.get("kda", -1.0))
			c.value_col = S.GREEN_HI if wr >= 3.5 else (S.RED if wr >= 0.0 and wr < 1.6 else U.TEXT)
		pan.add_child(c)
	var lanes := LaneBars.new()
	lanes.shares = Career.fav_lanes(p, avg_mode == "recent")
	lanes.counts = Career.career(p).lanes
	lanes.position = Vector2(22, 440)
	lanes.size = Vector2(516, PH - TOP - 460)
	pan.add_child(lanes)

# ---- Match history ----------------------------------------------------------------------------------------------------

func _build_history(p: Dictionary) -> void:
	var pan := PanelBox.new()
	pan.position = Vector2(576, TOP)
	pan.size = Vector2(700, PH - TOP)
	pan.title = "Match history"
	_root.add_child(pan)
	var tabs := S.Tabs.new()
	tabs.items = [["", "All"], ["ranked", "Ranked"], ["casual", "Unranked"]] if p.has("unranked") else [["", "All"]]
	tabs.active = hist_filter
	tabs.position = Vector2(700 - 24 - (290 if p.has("unranked") else 70), 14)
	tabs.size = Vector2(290, 40)
	tabs.changed.connect(func(id: String):
		hist_filter = id
		_open = -1
		refresh())
	pan.add_child(tabs)
	var ms := Career.matches(p, hist_filter)
	var form := FormStrip.new()
	form.form = ""
	for e in ms.slice(0, 10):
		form.form += "W" if String(e.get("r", "L")) == "W" else "L"
	form.position = Vector2(24, 62)
	form.size = Vector2(652, 30)
	pan.add_child(form)
	var sc := ScrollContainer.new()
	sc.position = Vector2(18, 102)
	sc.size = Vector2(664, PH - TOP - 120)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pan.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(650, 0)
	list.add_theme_constant_override("separation", 5)
	sc.add_child(list)
	for i in ms.size():
		var r := MatchRow.new()
		r.e = ms[i]
		r.idx = i
		r.open = i == _open
		r.custom_minimum_size = Vector2(650, MatchRow.open_height(ms[i], 650.0) if i == _open else 58.0)
		r.toggled.connect(func(ix: int):
			_open = -1 if _open == ix else ix
			refresh())
		r.menu.connect(func(ix: int, at: Vector2): _match_menu(ms[ix], ix, at))
		list.add_child(r)
	if ms.is_empty():
		var none := _label("No matches yet." if pid != "me" else "No matches yet. Every match you finish shows here: ranked and unranked.", 16, U.TEXT_DIM, "body", list)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		none.custom_minimum_size = Vector2(640, 0)

func _match_menu(e: Dictionary, ix: int, at: Vector2) -> void:
	var hero := String(e.get("h", ""))
	var entries: Array = [["details", "Hide details" if _open == ix else "Show details", "history"], ["copy", "Copy this match", "copy"]]
	if hero != "":
		entries.append(["hero", "%s ranking" % HeroDraft.hero_name(hero), "board"])
	PlayerMenu.open_list(self, at, "%s on %s" % [{"W": "Won", "L": "Lost", "A": "Left"}.get(String(e.get("r", "L")), "Match"), HeroDraft.hero_name(hero) if hero != "" else "?"],
		RankedNum.ago(int(e.get("t", 0))), entries, func(a: String): _match_pick(a, e, ix))

func _match_pick(a: String, e: Dictionary, ix: int) -> void:
	match a:
		"details":
			_open = -1 if _open == ix else ix
			refresh()
		"copy":
			DisplayServer.clipboard_set(MatchRow.line_text(e))
			_notice("Match copied.")
		"hero":
			var host := get_tree().current_scene
			if host != null and host.has_method("player_action"):
				host.call("player_action", "hero:" + String(e.get("h", "")), pid)

# ---- Wall, heroes, MMR, visitors ---------------------------------------------------------------------------------------

func _build_side(p: Dictionary) -> void:
	var pan := PanelBox.new()
	pan.position = Vector2(1292, TOP)
	pan.size = Vector2(548, PH - TOP)
	_root.add_child(pan)
	var tabs := S.Tabs.new()
	tabs.items = [["wall", "Wall"], ["heroes", "Heroes"], ["mmr", "MMR"]]
	if private_ok():
		tabs.items.append(["visitors", "Visitors"])
	if side_tab == "visitors" and not private_ok():
		side_tab = "wall"
	tabs.active = side_tab
	tabs.position = Vector2(20, 12)
	tabs.size = Vector2(508, 42)
	tabs.px = 19
	tabs.changed.connect(func(id: String):
		side_tab = id
		refresh())
	pan.add_child(tabs)
	var body := Control.new()
	body.position = Vector2(18, 62)
	body.size = Vector2(512, PH - TOP - 80)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(body)
	match side_tab:
		"heroes":
			_fill_heroes(body, p)
		"mmr":
			_fill_mmr(body, p)
		"visitors":
			_fill_visitors(body, p)
		_:
			_fill_wall(body, p)

func _fill_wall(body: Control, p: Dictionary) -> void:
	var y := 0.0
	# viewing your profile as someone: what they think of you
	if pid == "me" and view_as != "" and view_as != "public":
		var them := Ranked.profile(view_as)
		var card := TheirTake.new()
		card.p = them
		card.text = ProfileTalk.line_about(them, Ranked.me(), _rng)
		card.position = Vector2(0, 0)
		card.size = Vector2(512, 118)
		body.add_child(card)
		y = 128.0
	elif pid != "me":
		var card2 := TheirTake.new()
		card2.p = p
		card2.text = ""
		card2.position = Vector2(0, 0)
		card2.size = Vector2(512, 64)
		body.add_child(card2)
		y = 74.0
	# write
	if view_as == "" :
		var row := HBoxContainer.new()
		row.position = Vector2(0, y)
		row.size = Vector2(512, 44)
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		_wall_edit = LineEdit.new()
		_wall_edit.placeholder_text = "Write on your wall (Enter)" if pid == "me" else "Write a comment (Enter)"
		_wall_edit.max_length = 140
		_wall_edit.custom_minimum_size = Vector2(404, 44)
		_wall_edit.add_theme_font_size_override("font_size", 16)
		row.add_child(_wall_edit)
		var post := _button("Post", func(): _post_wall(), "GoldButton", Vector2(100, 44))
		row.add_child(post)
		_wall_edit.text_submitted.connect(func(_t): _post_wall())
		y += 54.0
	else:
		_wall_edit = null
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, y)
	sc.size = Vector2(512, body.size.y - y)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(500, 0)
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var wall: Array = ProfileTalk.wall_of(p)
	var shown := 0
	for c in wall:
		var who := String(c.get("id", ""))
		if who != "me" and Ranked.blocked(who):
			continue
		var wr := WallRow.new()
		wr.c = c
		wr.custom_minimum_size = Vector2(500, WallRow.height_for(String(c.get("text", "")), 500))
		wr.menu.connect(func(id: String, at: Vector2): PlayerMenu.open(self, id, at))
		list.add_child(wr)
		shown += 1
	if shown == 0:
		var none := _label("Nothing here yet. Players leave comments after matches and when they look you up." if pid == "me" else "Nothing here yet. Be the first to write.", 15, U.TEXT_DIM, "body", list)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		none.custom_minimum_size = Vector2(490, 0)

func _post_wall() -> void:
	if _wall_edit == null:
		return
	var t := _wall_edit.text.strip_edges()
	if t == "":
		return
	var p := Ranked.profile(pid)
	var back := ProfileTalk.write_on(p, t, _rng)
	Ranked.save()
	if not back.is_empty():
		_notice("%s answered on the wall." % String(p.get("name", "")))
	refresh()

func _fill_heroes(body: Control, p: Dictionary) -> void:
	var sc := ScrollContainer.new()
	sc.size = body.size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(500, 0)
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for e in Ranked.heroes_played(p):
		var hl := HeroLine.new()
		hl.p = p
		hl.hero = String(e[0])
		hl.custom_minimum_size = Vector2(500, 66)
		list.add_child(hl)
	if Ranked.heroes_played(p).is_empty():
		_label("No ranked matches yet.", 15, U.TEXT_DIM, "body", list)

func _fill_mmr(body: Control, p: Dictionary) -> void:
	var g := MmrGraph.new()
	g.values = p.get("graph", [])
	g.position = Vector2(0, 0)
	g.size = Vector2(512, 250)
	body.add_child(g)
	var tiles: Array = [["win", "Highest MMR", RankedNum.num(int(p.get("peak", 0)))],
		["streak", "Streak", _streak(int(p.get("streak", 0)))], ["streak", "Best streak", RankedNum.count(int(p.get("best_streak", 0)), "win", "wins")],
		["time", "Left matches", str(int(p.get("abandons", 0)))]]
	if private_ok():
		var bs := int(p.get("behavior", 10000))
		tiles.append(["commend", "Behaviour score", "%s  (%s)" % [RankedNum.num(bs), "Good" if bs >= 8000 else ("Fair" if bs >= 4500 else "Poor")]])
		tiles.append(["report", "Reports this season", str(int(p.get("reports", 0)))])
	else:
		tiles.append(["commend", "Behaviour score", "Private"])
		tiles.append(["board", "Leaderboard", "#%d of %d" % [Ranked.place_of(pid), Ranked.leaderboard().size()]])
	for i in tiles.size():
		var c := S.StatCard.new()
		c.key = String(tiles[i][0])
		c.title = String(tiles[i][1])
		c.value = String(tiles[i][2])
		c.position = Vector2((i % 2) * 258, 266 + (i / 2) * 88)
		c.size = Vector2(250, 80)
		body.add_child(c)

func _fill_visitors(body: Control, p: Dictionary) -> void:
	var sub := _label("Players who looked at your profile lately (only you see this).", 15, U.TEXT_DIM, "body", body)
	sub.position = Vector2(0, 0)
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, 32)
	sc.size = Vector2(512, body.size.y - 32)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(500, 0)
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for v in p.get("visitors", []):
		var vp := Ranked.profile(String(v.get("id", "")))
		if vp.is_empty():
			continue
		var r := VisitorRow.new()
		r.p = vp
		r.t = int(v.get("t", 0))
		r.custom_minimum_size = Vector2(500, 58)
		r.menu.connect(func(id: String, at: Vector2): PlayerMenu.open(self, id, at))
		r.clicked.connect(func(id: String):
			var host := get_tree().current_scene
			if host != null and host.has_method("player_action"):
				host.call("player_action", "profile", id))
		list.add_child(r)
	if (p.get("visitors", []) as Array).is_empty():
		_label("No visitors yet.", 15, U.TEXT_DIM, "body", list)

static func _streak(s: int) -> String:
	if s > 0:
		return "%d won" % s
	if s < 0:
		return "%d lost" % -s
	return "-"

# ---- Compare -----------------------------------------------------------------------------------------------------------

func open_compare() -> void:
	if _compare != null:
		_compare.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(PW, PH)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_compare = dim
	var cp := ComparePanel.new()
	cp.a = Ranked.me()
	cp.b = Ranked.profile(pid)
	cp.position = Vector2((PW - 980) * 0.5, 20)
	cp.size = Vector2(980, 880)
	dim.add_child(cp)
	var close := _button("Close", func():
		dim.queue_free()
		_compare = null, "DarkButton", Vector2(130, 42))
	close.position = Vector2(cp.size.x - 160, 22)
	cp.add_child(close)
	dim.gui_input.connect(func(e: InputEvent):
		if S.is_left(e) and not Rect2(cp.position, cp.size).has_point((e as InputEventMouseButton).position):
			dim.queue_free()
			_compare = null)

# ---- As an overlay -------------------------------------------------------------------------------------------------------

## Open a profile over any screen (Forums, the hero pick): a dimmed screen, the page scaled to fit, Close.
static func overlay(host: Node, id: String, action := "profile") -> ProfilePage:
	var tree := host.get_tree()
	for old in tree.get_nodes_in_group("profile_overlay"):
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.add_to_group("profile_overlay")
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var frame := Control.new()
	frame.size = Vector2(1920, 1080)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(frame)
	var page := ProfilePage.new()
	page.position = Vector2(40, 96)
	page.overlay_mode = true
	frame.add_child(page)
	# a click on the dimmed screen outside the page closes it
	dim.gui_input.connect(func(e: InputEvent):
		if S.is_left(e) and not page.get_global_rect().has_point(dim.get_global_transform() * (e as InputEventMouseButton).position):
			layer.queue_free())
	var close := Button.new()
	close.text = "Close"
	close.theme = U.theme()
	close.theme_type_variation = "DarkButton"
	close.focus_mode = Control.FOCUS_NONE
	close.position = Vector2(1880 - 130, 30)
	close.size = Vector2(130, 44)
	close.pressed.connect(func():
		Options.click()
		layer.queue_free())
	frame.add_child(close)
	var fit := func():
		var vs := dim.get_viewport_rect().size
		var k := minf(vs.x / 1920.0, vs.y / 1080.0)
		frame.scale = Vector2(k, k)
		frame.position = ((vs - Vector2(1920, 1080) * k) * 0.5).floor()
	dim.resized.connect(fit)
	fit.call()
	U.pop_in(dim)
	page.back_pressed.connect(func(): layer.queue_free())
	page.show_id(id, "")
	match action:
		"compare":
			page.open_compare()
		"write":
			page.side_tab = "wall"
			page.refresh()
		"view_as":
			page.view_as = "public"
			page.refresh()
	return page

# ---- Pieces ------------------------------------------------------------------------------------------------------------

## A skinned panel with a title.
class PanelBox extends Control:
	var title := ""
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		U.skin(self, "soc_panel", Rect2(Vector2.ZERO, size))
		if title != "":
			draw_string(U.font("title"), Vector2(26, 42), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.55, 23, U.GOLD)

## The banner art and its text (the controls on it are children).
class Banner extends Control:
	var page: ProfilePage
	var p := {}
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		U.art_rect(self, "soc_banner", Rect2(Vector2.ZERO, size))
		# the main hero's portrait faded into the banner's right half, behind the rank
		var heroes := Ranked.heroes_played(p)
		var hero := String(heroes[0][0]) if not heroes.is_empty() else (String((p.get("heroes", []) as Array)[0]) if not (p.get("heroes", []) as Array).is_empty() else "")
		var tex := U.hero_portrait(hero) if hero != "" else null
		if tex:
			# faded in from the left behind the rank words
			var r := Rect2(size.x - 250, 14, 222, 222)
			var n := 16
			for i in n:
				var a0 := float(i) / float(n)
				var src := Rect2(tex.get_size().x * a0, 0, tex.get_size().x / float(n), tex.get_size().y)
				var dst := Rect2(r.position.x + r.size.x * a0, r.position.y, r.size.x / float(n) + 0.5, r.size.y)
				draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 0.26 * smoothstep(0.0, 0.7, a0)))
		var own := String(p.get("id", "")) == "me"
		var nm := String(p.get("name", ""))
		var tf := U.font("title")
		draw_string(tf, Vector2(262, 76), nm, HORIZONTAL_ALIGNMENT_LEFT, 480, 42, Color(1.0, 0.95, 0.85))
		var nw := minf(tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x, 480.0)
		if own and page != null and page.view_as == "":
			draw_string(U.font("bold"), Vector2(262 + nw + 14, 72), "(you)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, SocialUi.BLUE)
		# status, presence and place
		var st := Persona.status(p) if bool(p.get("bot", false)) else _your_status(p)
		draw_string(U.font("body"), Vector2(262, 110), st, HORIZONTAL_ALIGNMENT_LEFT, 480, 18, U.TEXT)
		var parts: Array = []
		if bool(p.get("bot", false)):
			var pres := Persona.presence(p, Ranked.now())
			PlayerMenuDot.dot(self, Vector2(270, 136), String(pres.state))
			parts.append(String(pres.label))
		var where := Ranked.country_name(String(p.get("country", "")))
		if where != "":
			parts.append(where)
		parts.append("Playing since %s" % Time.get_date_string_from_unix_time(int(p.get("created", Ranked.now()))))
		draw_string(U.font("body"), Vector2(284 if bool(p.get("bot", false)) else 262, 142), "  ·  ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, 470, 15, Color(0.7, 0.7, 0.72))
		# labels and the relation
		var chips: Array = []
		if bool(p.get("bot", false)):
			chips.append_array(Persona.labels(p))
			var y: Dictionary = p.get("you", {})
			if bool(y.get("friend", false)) or String(p.id) in (Ranked.me().get("friends", []) as Array):
				chips.append("Friend")
			if int(y.get("games", 0)) > 0:
				chips.append(Persona.feeling(float(y.get("rep", 0.0))))
			if Ranked.blocked(String(p.id)):
				chips.append("Blocked")
		else:
			var main := Career.fav_lanes(p)
			if not main.is_empty():
				chips.append("%s player" % String(Career.LANE_SHORT.get(String(main[0][0]), "")))
			var fame_names := {"rampage": "Rampage", "godlike": "Godlike streak", "mvp": "MVP", "feeder": "Feeding", "flamer": "Flaming", "carry": "Carrying"}
			for k in Ranked.fame_of(p).slice(0, 2):
				chips.append("Known for: %s" % String(fame_names.get(k, k)))
		var cx := 262.0
		for c in chips.slice(0, 4):
			var cw := U.font("bold").get_string_size(String(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
			if cx + cw > 760:
				break
			U.skin(self, "soc_chip_gold" if String(c) in ["Friend", "Known for: MVP", "Known for: Rampage"] else "soc_chip", Rect2(cx, 152, cw, 26))
			draw_string(U.font("bold"), Vector2(cx + 12, 170), String(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(0.12, 0.08, 0.02) if String(c) in ["Friend", "Known for: MVP", "Known for: Rampage"] else U.TEXT)
			cx += cw + 8.0
		# rank words
		draw_string(tf, Vector2(1518, 70), Ranked.rank_label(p), HORIZONTAL_ALIGNMENT_LEFT, 300, 28, U.GOLD)
		draw_string(U.font("bold"), Vector2(1518, 106), "%s MMR" % RankedNum.num(int(p.mmr)), HORIZONTAL_ALIGNMENT_LEFT, 300, 25, U.TEXT)
		var place := Ranked.place_of(String(p.get("id", "")))
		draw_string(U.font("body"), Vector2(1518, 132), "#%s of %s on the leaderboard" % [RankedNum.num(place), RankedNum.num(Ranked.leaderboard().size())],
			HORIZONTAL_ALIGNMENT_LEFT, 300, 15, Color(0.7, 0.7, 0.72))
# View As ribbon
		if page != null and page.view_as != "":
			var who := "Public: this is what any player sees" if page.view_as == "public" else "Viewing as %s: this is what they see" % String(Ranked.profile(page.view_as).get("name", ""))
			var tw := U.font("bold").get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 40.0
			U.skin(self, "ribbon_gold", Rect2((size.x - tw) * 0.5 - 40, -6, tw + 80, 36))
			draw_string(U.font("bold"), Vector2((size.x - tw) * 0.5 + 20, 17), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.06, 0.0))
	static func _your_status(p: Dictionary) -> String:
		var s := int(p.get("streak", 0))
		if s >= 3:
			return "On a %d win streak" % s
		if s <= -3:
			return "Lost %d in a row" % -s
		var c := Career.career(p)
		return "%s counted  ·  %d ranked" % [RankedNum.count(int(c.g), "match", "matches"), int(p.get("wins", 0)) + int(p.get("losses", 0))]

## Online / in a match / away dot (the same colours as the Players tab).
class PlayerMenuDot:
	static func dot(c: CanvasItem, at: Vector2, st: String) -> void:
		var col := Color(0.35, 0.9, 0.45) if st == "online" else (Color(0.4, 0.7, 1.0) if st == "match" else Color(0.5, 0.52, 0.56))
		c.draw_circle(at, 5.0, col)
		c.draw_arc(at, 7.0, 0, TAU, 20, Color(col, 0.35), 2.0, true)

## The way to the next rank on the banner.
class RankBar extends Control:
	var mmr := 0
	var tier := 0
	func _draw() -> void:
		var lo := Ranked.tier_floor(mini(tier, Ranked.RANKS.size() - 1))
		var hi := Ranked.next_floor(mini(tier, Ranked.RANKS.size() - 1))
		var txt := ""
		var frac := 1.0
		if hi < 0:
			txt = "Top rank: climb the leaderboard"
		else:
			frac = clampf(float(mmr - lo) / float(hi - lo), 0.0, 1.0)
			txt = "%s MMR to %s" % [RankedNum.num(hi - mmr), Ranked.tier_name(tier + 1)]
		draw_string(U.font("bold"), Vector2(0, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, size.x, 14, U.TEXT)
		U.bar(self, Rect2(0, 26, size.x, 18), frac, U.GOLD)
		if hi > 0:
			draw_string(U.font("body"), Vector2(0, size.y), RankedNum.num(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.62))
			SocialUi.text_r(self, RankedNum.num(hi), size.x, size.y, 12, Color(0.6, 0.6, 0.62))

## The favourite lanes: a bar for each lane played, its share and count.
class LaneBars extends Control:
	var shares: Array = []
	var counts := {}
	func _draw() -> void:
		var ic := SocialUi.icon("lane")
		if ic:
			draw_texture_rect(ic, Rect2(0, 0, 40, 40), false)
		draw_string(U.font("title"), Vector2(52, 28), "Favourite lanes", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.GOLD)
		if shares.is_empty():
			draw_string(U.font("body"), Vector2(0, 76), "Shows after a few matches.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.62))
			return
		var y := 58.0
		var cols := {"safe": Color(0.35, 0.75, 1.0), "mid": Color(0.95, 0.78, 0.38), "off": Color(1.0, 0.45, 0.35), "roam": Color(0.6, 0.85, 0.5),
			"jungle": Color(0.6, 0.85, 0.5)}
		for e in shares.slice(0, 4):
			var ln := String(e[0])
			var sh := float(e[1])
			var col: Color = cols.get(ln, U.TEXT)
			draw_string(U.font("bold"), Vector2(0, y + 17), String(Career.LANE_NAMES.get(ln, ln)), HORIZONTAL_ALIGNMENT_LEFT, 130, 16, U.TEXT)
			var bar := Rect2(136, y + 3, size.x - 230, 18)
			draw_rect(bar, Color(0, 0, 0, 0.45))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * sh, bar.size.y)), Color(col, 0.85))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * sh, 5)), Color(1, 1, 1, 0.22))
			draw_rect(bar, Color(col, 0.4), false, 1.0)
			SocialUi.text_r(self, "%d%%" % int(round(sh * 100.0)), size.x, y + 18, 16, col, "bold")
			y += 34.0

## The last results as plates, with the count.
class FormStrip extends Control:
	var form := ""
	func _draw() -> void:
		draw_string(U.font("bold"), Vector2(0, 21), "Last %d" % form.length() if form != "" else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.7, 0.72))
		SocialUi.draw_form(self, Vector2(70, 2), form, 24.0, 5.0)
		var w := form.count("W")
		if form != "":
			SocialUi.text_r(self, "%d won, %d lost" % [w, form.length() - w], size.x, 21, 15, Color(0.7, 0.7, 0.72), "bold")

## A match in the history: click for every number, right-click for more.
class MatchRow extends Control:
	signal toggled(idx: int)
	signal menu(idx: int, at: Vector2)
	var e := {}
	var idx := 0
	var open := false
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _gui_input(ev: InputEvent) -> void:
		if SocialUi.is_left(ev):
			Options.click()
			toggled.emit(idx)
			accept_event()
		elif SocialUi.is_right(ev):
			menu.emit(idx, SocialUi.at(self, ev))
			accept_event()
	static func line_text(m: Dictionary) -> String:
		var s := "%s %s %d/%d/%d" % [{"W": "Won", "L": "Lost", "A": "Left"}.get(String(m.get("r", "L")), "?"),
			HeroDraft.hero_name(String(m.get("h", ""))), int(m.get("k", 0)), int(m.get("x", 0)), int(m.get("a", 0))]
		if m.has("lh"):
			s += ", %d/%d LH/DN, %d GPM" % [int(m.lh), int(m.get("dn", 0)), int(m.get("gpm", 0))]
		if m.has("d"):
			s += ", %+d MMR" % int(m.d)
		return s
	func _draw() -> void:
		var res := String(e.get("r", "L"))
		var won := res == "W"
		var base := "soc_row_win" if won else "soc_row_loss"
		U.skin(self, base + ("_hover" if _hot or open else ""), Rect2(Vector2.ZERO, size))
		var col := SocialUi.GREEN_HI if won else (SocialUi.RED if res == "L" else Color(0.85, 0.6, 0.3))
		var f := U.font("bold")
		var b := U.font("body")
		var cy := 29.0
		draw_string(f, Vector2(16, cy + 6), {"W": "Won", "L": "Lost", "A": "Left"}.get(res, res), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		var hero := String(e.get("h", ""))
		var tex := U.hero_portrait(hero) if hero != "" else null
		if tex:
			draw_texture_rect(tex, Rect2(66, 7, 44, 44), false)
			draw_rect(Rect2(66, 7, 44, 44), Color(1, 1, 1, 0.18), false, 1.0)
		draw_string(f, Vector2(120, cy - 2), HeroDraft.hero_name(hero) if hero != "" else "?", HORIZONTAL_ALIGNMENT_LEFT, 130, 16, U.TEXT)
		var sub := String(Career.LANE_SHORT.get(String(e.get("ln", "")), "")) if e.has("ln") else RankedNum.role(int(e.get("o", 0)))
		var kind := "Unranked" if String(e.get("kind", "")) == "casual" else "Ranked"
		draw_string(b, Vector2(120, cy + 17), ("%s  ·  %s" % [kind, sub]) if sub != "" else kind, HORIZONTAL_ALIGNMENT_LEFT, 134, 12, Color(0.62, 0.62, 0.64))
		if e.has("k"):
			draw_string(f, Vector2(258, cy + 6), "%d / %d / %d" % [int(e.k), int(e.get("x", 0)), int(e.get("a", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, U.TEXT)
		if e.has("lh"):
			draw_string(b, Vector2(360, cy - 2), "%d / %d" % [int(e.lh), int(e.get("dn", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT)
			draw_string(b, Vector2(360, cy + 16), "LH / DN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.55, 0.58))
			draw_string(b, Vector2(432, cy - 2), str(int(e.get("gpm", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.GOLD)
			draw_string(b, Vector2(432, cy + 16), "GPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.55, 0.58))
		# badges
		var bx := 484.0
		var badges: Array = []
		if bool(e.get("mvp", false)):
			badges.append(["mvp", "MVP"])
		if int(e.get("rp", 0)) > 0:
			badges.append(["rampage", "Rampage x%d" % int(e.rp) if int(e.rp) > 1 else "Rampage"])
		if int(e.get("tr", 0)) > 0:
			badges.append(["triple", "Triple Kill"])
		if int(e.get("fb", 0)) > 0:
			badges.append(["fb", "First Blood"])
		for bd in badges.slice(0, 3):
			var ic := SocialUi.icon(String(bd[0]))
			if ic:
				draw_texture_rect(ic, Rect2(bx, cy - 13, 26, 26), false)
			bx += 27.0
		if e.has("d") and String(e.get("kind", "")) != "casual":
			var d := int(e.d)
			SocialUi.text_r(self, "%+d" % d, size.x - 14, cy - 1, 19, SocialUi.GREEN_HI if d > 0 else SocialUi.RED, "bold")
		SocialUi.text_r(self, RankedNum.ago(int(e.get("t", 0))), size.x - 14, cy + 17, 12, Color(0.55, 0.55, 0.58))
		if not open:
			return
		# every number of the match
		draw_line(Vector2(16, 60), Vector2(size.x - 16, 60), Color(U.GOLD, 0.2), 1.0)
		var y := 76.0
		for pc in _layout(e, size.x):
			draw_string(b, Vector2(float(pc[2]), float(pc[3])), String(pc[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.58, 0.58, 0.6))
			draw_string(f, Vector2(float(pc[2]), float(pc[3]) + 20), String(pc[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT)
			y = float(pc[3])
	## The height of an opened match: its rows of numbers (they wrap at the row's width).
	static func open_height(m: Dictionary, w: float) -> float:
		var last := 76.0
		for pc in _layout(m, w):
			last = maxf(last, float(pc[3]))
		return last + 40.0
	## The match's numbers placed in rows: [[label, value, x, y]].
	static func _layout(e: Dictionary, w: float) -> Array:
		var cells: Array = []
		if e.has("len"):
			cells.append(["Length", RankedNum.mmss(float(e.len))])
		if e.has("nw"):
			cells.append(["Net worth", RankedNum.num(int(e.nw))])
		if e.has("xpm"):
			cells.append(["XPM", str(int(e.xpm))])
		if e.has("hd"):
			cells.append(["Hero damage", RankedNum.num(int(e.hd))])
		if e.has("bd"):
			cells.append(["Building damage", RankedNum.num(int(e.bd))])
		if int(e.get("heal", 0)) > 0:
			cells.append(["Healing", RankedNum.num(int(e.heal))])
		if int(e.get("wd", 0)) > 0:
			cells.append(["Wards", str(int(e.wd))])
		if e.has("m"):
			cells.append(["MMR after", RankedNum.num(int(e.m))])
		if e.has("perf"):
			cells.append(["Your game", "%d%%" % int(round(float(e.perf) * 100.0))])
		var multi: Array = []
		for k in [["db", "Double"], ["tr", "Triple"], ["ul", "Ultra"], ["rp", "Rampage"]]:
			if int(e.get(String(k[0]), 0)) > 0:
				multi.append("%s x%d" % [String(k[1]), int(e[k[0]])])
		if not multi.is_empty():
			cells.append(["Multi-kills", ", ".join(multi)])
		var out: Array = []
		var x := 16.0
		var y := 76.0
		for c in cells:
			var cw := maxf(96.0, U.font("bold").get_string_size(String(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22.0)
			if x + cw > w - 10:
				x = 16.0
				y += 44.0
			out.append([String(c[0]), String(c[1]), x, y])
			x += cw
		return out

## A comment on a wall: picture, name, rank, when, the words; mood: a green or red edge for +rep / -rep.
class WallRow extends Control:
	signal menu(id: String, at: Vector2)
	var c := {}
	var _av: Avatar
	var _hot := false
	static func height_for(text: String, w: float) -> float:
		var lines := U.wrap(text, w - 76.0, 16).size()
		return 50.0 + 21.0 * maxi(1, lines)
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var p := Ranked.profile(String(c.get("id", "")))
		_av = Avatar.new()
		_av.set_spec(p.get("avatar", {"k": "none"}))
		_av.position = Vector2(10, 10)
		_av.size = Vector2(44, 44)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_av)
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) or (SocialUi.is_left(e) and (e as InputEventMouseButton).position.x < 260 and (e as InputEventMouseButton).position.y < 34):
			menu.emit(String(c.get("id", "")), SocialUi.at(self, e))
			accept_event()
	func _draw() -> void:
		var mood := int(c.get("mood", 0))
		U.skin(self, ("soc_row_win" if mood > 0 else ("soc_row_loss" if mood < 0 else ("soc_row_you" if String(c.get("id", "")) == "me" else "soc_row"))) + \
			("_hover" if _hot and mood != 0 else ""), Rect2(Vector2.ZERO, size))
		var p := Ranked.profile(String(c.get("id", "")))
		var nm := String(p.get("name", "?"))
		var f := U.font("bold")
		draw_string(f, Vector2(66, 26), nm, HORIZONTAL_ALIGNMENT_LEFT, 220, 16, SocialUi.BLUE if String(c.get("id", "")) == "me" else U.TEXT)
		var nw := minf(f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 220.0)
		var ic := RankEmblem.icon(Ranked.tier_for(p))
		if ic:
			draw_texture_rect(ic, Rect2(66 + nw + 8, 9, 22, 22), false)
		draw_string(U.font("body"), Vector2(66 + nw + 34, 26), Ranked.rank_label(p), HORIZONTAL_ALIGNMENT_LEFT, 150, 13, Color(0.66, 0.6, 0.45))
		SocialUi.text_r(self, RankedNum.ago(int(c.get("t", 0))), size.x - 12, 26, 12, Color(0.55, 0.55, 0.58))
		var lines := U.wrap(String(c.get("text", "")), size.x - 76.0, 16)
		var y := 50.0
		for ln in lines:
			draw_string(U.font("body"), Vector2(66, y), ln, HORIZONTAL_ALIGNMENT_LEFT, size.x - 76.0, 16, U.TEXT)
			y += 21.0

## What a player thinks of you: their picture, feeling, your record together, and (View As) their read of your profile.
class TheirTake extends Control:
	var p := {}
	var text := ""
	func _draw() -> void:
		U.skin(self, "soc_card_gold", Rect2(Vector2.ZERO, size))
		var y: Dictionary = p.get("you", {})
		var ic := SocialUi.icon("friend")
		if ic:
			draw_texture_rect(ic, Rect2(12, 10, 42, 42), false)
		var head := "%s: %s" % [String(p.get("name", "")), Persona.feeling(float(y.get("rep", 0.0)))]
		draw_string(U.font("bold"), Vector2(66, 28), head, HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, 17, U.GOLD)
		var rec := "Never played with you" if int(y.get("games", 0)) == 0 else "%d with you (%d won), %d against you" % [
			int(y.get("with", 0)), int(y.get("with_w", 0)), int(y.get("vs", 0))]
		draw_string(U.font("body"), Vector2(66, 50), rec, HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, 14, Color(0.72, 0.72, 0.74))
		if text != "":
			var lines := U.wrap("\"%s\"" % text, size.x - 32.0, 16)
			var yy := 78.0
			for ln in lines.slice(0, 2):
				draw_string(U.font("body"), Vector2(16, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 16, U.TEXT)
				yy += 21.0

## A recent visitor of your profile.
class VisitorRow extends Control:
	signal menu(id: String, at: Vector2)
	signal clicked(id: String)
	var p := {}
	var t := 0
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var av := Avatar.new()
		av.set_spec(p.get("avatar", {"k": "none"}))
		av.position = Vector2(8, 7)
		av.size = Vector2(44, 44)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(av)
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e):
			menu.emit(String(p.id), SocialUi.at(self, e))
			accept_event()
		elif SocialUi.is_left(e):
			clicked.emit(String(p.id))
			accept_event()
	func _draw() -> void:
		U.skin(self, "soc_row_hover" if _hot else "soc_row", Rect2(Vector2.ZERO, size))
		draw_string(U.font("bold"), Vector2(64, 25), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 260, 16, U.TEXT)
		draw_string(U.font("body"), Vector2(64, 45), "%s  ·  %s" % [Ranked.rank_label(p), Persona.feeling(float((p.get("you", {}) as Dictionary).get("rep", 0.0)))],
			HORIZONTAL_ALIGNMENT_LEFT, 300, 13, Color(0.66, 0.66, 0.68))
		SocialUi.text_r(self, "looked %s" % RankedNum.ago(t), size.x - 12, 35, 13, Color(0.6, 0.6, 0.62))

## One hero: face, name, record, medal and XP.
class HeroLine extends Control:
	var p := {}
	var hero := ""
	func _draw() -> void:
		U.skin(self, "soc_row", Rect2(Vector2.ZERO, size))
		var tex := U.hero_portrait(hero)
		if tex:
			draw_texture_rect(tex, Rect2(8, 8, size.y - 16, size.y - 16), false)
		var hs = (p.get("hero_stats", {}) as Dictionary).get(hero, [0, 0, 0])
		var w := int(hs[0])
		var l := int(hs[1])
		var x := size.y + 4.0
		draw_string(U.font("bold"), Vector2(x, 28), HeroDraft.hero_name(hero), HORIZONTAL_ALIGNMENT_LEFT, 150, 17, U.TEXT)
		var wr := float(w) / maxf(1.0, float(w + l))
		draw_string(U.font("body"), Vector2(x, 50), "%s W - %s L  ·  %.0f%%" % [RankedNum.num(w), RankedNum.num(l), wr * 100.0], HORIZONTAL_ALIGNMENT_LEFT, 200, 14,
			SocialUi.GREEN_HI if wr > 0.52 else (SocialUi.RED if wr < 0.48 else Color(0.7, 0.7, 0.72)))
		var m := Ranked.hero_medal(p, hero)
		HeroBadge.paint(self, Rect2(size.x - size.y, 2, size.y - 4, size.y - 4), hero, m)
		SocialUi.text_r(self, String(m.name), size.x - size.y - 8, 28, 15, HeroBadge.metal(m), "bold")
		var bar := Rect2(size.x - size.y - 150, 40, 142, 7)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(m.frac), bar.size.y)), HeroBadge.metal(m))

## MMR over the last matches.
class MmrGraph extends Control:
	var values: Array = []
	func _draw() -> void:
		U.skin(self, "soc_card", Rect2(Vector2.ZERO, size))
		draw_string(U.font("title"), Vector2(16, 30), "MMR over the last %d matches" % maxi(0, values.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, U.GOLD)
		if values.size() < 2:
			draw_string(U.font("body"), Vector2(16, size.y * 0.55), "Play a few ranked matches to see your MMR here.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.62))
			return
		var lo := INF
		var hi := -INF
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		var pad := maxf(30.0, (hi - lo) * 0.15)
		lo -= pad
		hi += pad
		var x0 := 56.0
		var y0 := 46.0
		var w := size.x - x0 - 18.0
		var h := size.y - y0 - 20.0
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(x0 + w * float(i) / float(values.size() - 1), y0 + h - h * (float(values[i]) - lo) / (hi - lo)))
		var area := pts.duplicate()
		area.append(Vector2(pts[pts.size() - 1].x, y0 + h))
		area.append(Vector2(pts[0].x, y0 + h))
		draw_colored_polygon(area, Color(0.95, 0.78, 0.38, 0.1))
		draw_polyline(pts, U.GOLD, 2.5, true)
		draw_circle(pts[pts.size() - 1], 5, U.GOLD)
		draw_string(U.font("body"), Vector2(8, y0 + 10), RankedNum.num(int(hi - pad)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.62))
		draw_string(U.font("body"), Vector2(8, y0 + h), RankedNum.num(int(lo + pad)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.62))

## You and them side by side: the better number of each row is lit.
class ComparePanel extends Control:
	var a := {}
	var b := {}
	var _avs: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		for i in 2:
			var av := Avatar.new()
			av.set_spec(([a, b][i] as Dictionary).get("avatar", {"k": "none"}))
			av.size = Vector2(96, 96)
			av.position = Vector2(60 if i == 0 else size.x - 156, 70)
			av.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(av)
	func _rows() -> Array:
		var aa := Career.averages(a)
		var ba := Career.averages(b)
		var am := Career.moments(a)
		var bm := Career.moments(b)
		var ga := int(a.wins) + int(a.losses)
		var gb := int(b.wins) + int(b.losses)
		return [["MMR", float(a.mmr), float(b.mmr), "num"], ["Ranked matches", float(ga), float(gb), "num"],
			["Win rate", Ranked.win_rate(a) * 100.0, Ranked.win_rate(b) * 100.0, "pct"],
			["Kills a match", float(aa.k), float(ba.k), "dec"], ["Deaths a match", float(aa.x), float(ba.x), "low"],
			["Assists a match", float(aa.a), float(ba.a), "dec"], ["KDA", float(aa.kda), float(ba.kda), "dec2"],
			["Last hits a match", float(aa.lh), float(ba.lh), "num"], ["Last hits a minute", float(aa.lhm), float(ba.lhm), "dec"],
			["Gold a minute", float(aa.gpm), float(ba.gpm), "num"], ["Experience a minute", float(aa.xpm), float(ba.xpm), "num"],
			["Hero damage", float(aa.hd), float(ba.hd), "num"], ["MVPs", float(am.mvp), float(bm.mvp), "num"],
			["Rampages", float(am.rp), float(bm.rp), "num"], ["Triple Kills", float(am.tr), float(bm.tr), "num"],
			["First Bloods", float(am.fb), float(bm.fb), "num"], ["Commends", float(a.get("commends", 0)), float(b.get("commends", 0)), "num"]]
	func _fmt(v: float, kind: String) -> String:
		if v < 0.0:
			return "-"
		match kind:
			"pct":
				return "%.1f%%" % v
			"dec", "low":
				return "%.1f" % v
			"dec2":
				return "%.2f" % v
		return RankedNum.num(int(round(v)))
	func _draw() -> void:
		U.skin(self, "soc_panel", Rect2(Vector2.ZERO, size))
		draw_string(U.font("title"), Vector2(30, 46), "Compare", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, U.GOLD)
		var f := U.font("bold")
		draw_string(f, Vector2(170, 112), String(a.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 280, 22, SocialUi.BLUE)
		draw_string(U.font("body"), Vector2(170, 138), Ranked.rank_label(a), HORIZONTAL_ALIGNMENT_LEFT, 280, 15, U.GOLD)
		SocialUi.text_r(self, String(b.get("name", "")), size.x - 170, 112, 22, U.TEXT, "bold")
		SocialUi.text_r(self, Ranked.rank_label(b), size.x - 170, 138, 15, U.GOLD)
		var y := 196.0
		var mid := size.x * 0.5
		for r in _rows():
			var va := float(r[1])
			var vb := float(r[2])
			var low := String(r[3]) == "low"
			var a_best := va >= 0.0 and vb >= 0.0 and ((va < vb) if low else (va > vb))
			var b_best := va >= 0.0 and vb >= 0.0 and ((vb < va) if low else (vb > va))
			U.skin(self, "soc_row", Rect2(40, y - 26, size.x - 80, 36))
			SocialUi.text_c(self, String(r[0]), mid, y - 2, 15, Color(0.72, 0.72, 0.74))
			var tot := maxf(0.001, absf(va) + absf(vb))
			if va >= 0.0 and vb >= 0.0:
				var wa := 220.0 * (va / tot if not low else vb / tot)
				var wb := 220.0 * (vb / tot if not low else va / tot)
				draw_rect(Rect2(mid - 130 - wa, y - 14, wa, 6), Color(SocialUi.BLUE, 0.55 if a_best else 0.25))
				draw_rect(Rect2(mid + 130, y - 14, wb, 6), Color(U.GOLD, 0.55 if b_best else 0.25))
			draw_string(f, Vector2(64, y - 2), _fmt(va, String(r[3])), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, SocialUi.GREEN_HI if a_best else U.TEXT)
			SocialUi.text_r(self, _fmt(vb, String(r[3])), size.x - 64, y - 2, 18, SocialUi.GREEN_HI if b_best else U.TEXT, "bold")
			y += 39.0
