extends Control
## The Ranked screen (run 2026-10-19 b; the owner's request: a professional matchmaking client). Four tabs:
##   * Play: your rank and your best heroes, the five roles to tick (Carry, Mid, Off Lane, Soft Support, Hard Support),
##     the big Find Match button (no hero is chosen before matchmaking: heroes are picked after everyone accepts,
##     ranked_draft.gd); while searching a panel with the time, a progress bar, what the search is doing, the
##     players found so far and Cancel. When a match is found: a dialog with a big green ACCEPT and Decline, a
##     15 second ring, ten lights that fill as players accept, and your team and the enemy team at the sides (hover a
##     player for wins and losses, MMR, behaviour score, favourite heroes and recent games). Then the hero pick.
##   * Profile: your picture (Change picture uploads one), your name, the 3D emblem of your rank (drag to turn it),
##     MMR and the way to the next rank, your numbers, an MMR graph and your recent matches. Any player's profile
##     opens from the leaderboard the same way.
##   * Leaderboard: everyone by MMR; the top ten in Aetherium are Aetherium+; your row is marked. Heroes: each hero's
##     ranking across every player by mastery XP (Ranked.hero_board): medals Bronze to Diamond with stars, the five best
##     Diamonds are its Top 5 .. Top 1 Players (HeroBadge).
##   * Players (run 2026-10-19 d): your friends and friend requests (Accept, Ignore), the players you met in ranked
##     (with you / against you, what they think of you), the ladder's activity (ranks reached, streaks, medals, heroes
##     being learned, new Top 1 players) and who is online now (in a match as which hero, or free).
##   * Guilds: coming soon (from Licensed rank).
## Automation: --capture=path [--tab=play|profile|leaderboard|guilds] [--state=search|found|ready] [--hover=n]
## [--profile=<id>] [--view=heroes] [--board=heroes --hero=<id>] [--4k] [--frames=n] saves a frame and quits; the profile's
## states: [--view_as=public|<id>] [--side=wall|heroes|mmr|visitors] [--open_match=n] [--compare] [--menu=<id>].

const U = preload("res://src/ui/ui_kit.gd")
const MAIN_MENU := "res://src/ui/main_menu.tscn"
const DRAFT := "res://src/ui/ranked_draft.tscn"
const W := 1920.0
const H := 1080.0

const GREEN := Color(0.24, 0.74, 0.33)
const GREEN_HI := Color(0.42, 0.95, 0.5)
const RED := Color(0.92, 0.36, 0.32)
const BLUE := Color(0.4, 0.72, 1.0)
const GLASS := Color(0.055, 0.07, 0.105, 0.9)
const GLASS_HI := Color(0.09, 0.11, 0.16, 0.95)
const RIM := Color(0.55, 0.43, 0.2, 0.6)
const ROLE_LINES := ["Farms the safe lane and wins the late game.", "Holds the middle lane alone and ganks.",
	"Takes the hard lane and starts fights.", "Roams, ganks, stacks and places wards.",
	"Keeps the carry alive and buys for the team."]
const TABS := [["play", "Play"], ["profile", "Profile"], ["leaderboard", "Leaderboard"], ["players", "Players"], ["guilds", "Guilds"]]

var mm := Matchmaker.new()
var _frame: Control
var _strip_top: ColorRect
var _strip_bot: ColorRect
var _tab := "play"
var _pages := {}
var _tab_btns := {}
var _chip: Control
var _toast: Label
var _toast_t := 0.0
var _footer: Label
var _card: PlayerCard
# Play
var _roles := {}                           # role -> RoleCard
var _heroes_box: VBoxContainer
var _find_btn: BigButton
var _search_box: Control
var _wait_lbl: Label
var _mini_board: VBoxContainer
var _recent_box: VBoxContainer
var _rank_view: EmblemView
var _rank_lbl: Label
var _rank_sub: Label
var _rank_bar: Bar
# Match found
var _offer: Control
var _back_btn: Button
var _accept_btn: BigButton
var _decline_btn: Button
var _offer_cols: Array = []
var _offer_title: Label
var _offer_sub: Label
var _lineup_t := -1.0
var _launching := false
# Profile
var _profile_id := "me"
var _profile_view := "overview"            # overview, heroes
var _profile_page: Control
# Leaderboard
var _board_list: VBoxContainer
var _players_page: Control
var _friend_filter := "all"                # Players: All, online, match, offline, requests
var _middle := "chat"                      # Players' middle panel: chat or activity
var _right := "online"                     # Players' right panel: online, recent, top, find
var _chat_id := ""                         # the friend whose conversation is open
var _find_text := ""
var _chat_draft := ""                      # what you are typing to a friend (kept when the tab redraws)
var _chat_scroll: ScrollContainer
var _chat_t := 0.0
var _board_filter := "all"
var _board_hero := ""
var _hero_strip: HBoxContainer
var _board_head: Control
var _board_you: Control
# capture
var _capture := ""
var _cap_frames := 45
var _frames := 0
var _hover_i := -1
var _baked_seen := -1

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	Ranked.load_data()
	var left := Ranked.abandon_pending()          # a ranked match left without an end (closed game, crash)
	Ranked.catch_up()
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("4k"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(3840, 2160))
	_capture = String(args.get("capture", ""))
	_cap_frames = int(args.get("frames", "45"))
	_build_background()
	_strip_top = ColorRect.new()
	_strip_top.color = Color(0.03, 0.04, 0.07, 0.92)
	_strip_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip_top)
	_strip_bot = ColorRect.new()
	_strip_bot.color = Color(0.02, 0.03, 0.05, 0.9)
	_strip_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip_bot)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_build_top()
	_build_play()
	_build_profile_page()
	_build_board()
	_build_players()
	_build_guilds()
	_build_footer()
	_build_offer()
	_card = PlayerCard.new()
	_card.visible = false
	add_child(_card)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_override("font", U.font("bold"))
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.1, 0.15, 0.96), Color(U.GOLD, 0.7), 8, 18))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	resized.connect(_layout)
	_layout()
	_profile_view = String(args.get("view", "overview"))
	_board_filter = String(args.get("board", "all"))
	_board_hero = String(args.get("hero", ""))
	# captures of the Players tab (run 2026-10-20 e): --filter=online|match|offline|requests --right=online|recent|top|find
	# --find=text --middle=chat|activity --chat=<friend id>|first --chat_say=text (answered at once) --accounts
	_friend_filter = String(args.get("filter", _friend_filter))
	_right = String(args.get("right", _right))
	_find_text = String(args.get("find", ""))
	_middle = String(args.get("middle", _middle))
	if args.has("chat"):
		var fr: Array = Ranked.me().get("friends", [])
		_chat_id = String(fr[0]) if String(args.chat) == "first" and not fr.is_empty() else String(args.chat)
		if args.has("chat_say"):
			for line in String(args.chat_say).split("|"):
				FriendChat.send(_chat_id, line)
				for q in Ranked.me().get("typing", []):
					q["at"] = 0
				FriendChat.tick()
	_show_tab(String(args.get("tab", "play")))
	if args.has("accounts"):
		AccountsPanel.open(self)
	if not left.is_empty():
		_notice("Your last ranked match was left before it ended: a loss (%+d MMR)." % int(left.delta))
	if args.has("profile"):
		_open_profile(String(args.profile))
	match String(args.get("state", "")):
		"search":
			_find()
			mm.t = 6.0
			mm.expect = 14.0
		"found", "ready":
			_find()
			mm.t = 99.0
			mm.step(0.1)
			if String(args.state) == "ready":
				mm.you_accepted = true
				mm.lineup.fails = {}
				mm.accept_t = 14.0
				mm.step(0.1)
				_launching = true                   # a capture never starts the match
			else:
				mm.lineup.fails = {}
				mm.accept_t = 3.2
	if args.has("hover"):
		_hover_i = int(args.hover)
	# captures of the profile's states (run 2026-10-20): --view_as=public|<id>, --side=wall|heroes|mmr|visitors,
	# --open_match=n, --compare, --menu=<id> (the player menu at the screen's centre)
	if args.has("view_as"):
		_ppage.view_as = String(args.view_as)
		_ppage.refresh()
	if args.has("side"):
		_ppage.side_tab = String(args.side)
		_ppage.refresh()
	if args.has("open_match"):
		_ppage._open = int(args.open_match)
		_ppage.refresh()
	if args.has("compare"):
		_ppage.open_compare()
	if args.has("menu"):
		await get_tree().process_frame
		PlayerMenu.open(self, String(args.menu), size * 0.5)
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

# ---- Building blocks ------------------------------------------------------------------------------------------------

static func _flat(bg: Color, border: Color, radius := 6, pad := 0, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

func _label(text: String, size_px: int, col := U.TEXT, kind := "body", parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l

func _glass(r: Rect2, parent: Node, title := "") -> Glass:
	var g := Glass.new()
	g.position = r.position
	g.size = r.size
	g.title = title
	parent.add_child(g)
	return g

func _button(text: String, cb: Callable, variation := "DarkButton", min_size := Vector2(0, 44)) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

static func num(n: int) -> String:
	return RankedNum.num(n)

static func ago(t: int) -> String:
	return RankedNum.ago(t)

static func role_name(r: int) -> String:
	return RankedNum.role(r)

# ---- Background, top bar, footer ------------------------------------------------------------------------------------

func _build_background() -> void:
	SocialUi.backdrop(self)

func _build_top() -> void:
	var bar := TopBar.new()
	bar.position = Vector2.ZERO
	bar.size = Vector2(W, 92)
	_frame.add_child(bar)
	var back := _button("Back", func(): _leave(), "DarkButton", Vector2(110, 46))
	_back_btn = back
	back.position = Vector2(30, 23)
	bar.add_child(back)
	var title := _label("Ranked", 38, U.GOLD, "title", bar)
	title.position = Vector2(166, 18)
	var x := 400.0
	for tdef in TABS:
		var tb := TabButton.new()
		tb.text = String(tdef[1])
		tb.soon = String(tdef[0]) == "guilds"
		tb.position = Vector2(x, 20)
		tb.size = Vector2(170 if tb.soon else 150, 56)
		var id := String(tdef[0])
		tb.pressed.connect(func(): _show_tab(id))
		bar.add_child(tb)
		_tab_btns[id] = tb
		x += tb.size.x + 8.0
	# your accounts: log in to another, log out, make a new one (run 2026-10-20 e)
	var acc := _button("Accounts", func(): AccountsPanel.open(self), "DarkButton", Vector2(150, 46))
	acc.position = Vector2(W - 640, 23)
	acc.tooltip_text = "Log in to another account, log out, or make a new account"
	bar.add_child(acc)
	_chip = ProfileChip.new()
	_chip.position = Vector2(W - 470, 12)
	_chip.size = Vector2(440, 68)
	_chip.clicked.connect(func(): _open_profile("me"))
	bar.add_child(_chip)

func _build_footer() -> void:
	var f := FooterBar.new()
	f.position = Vector2(0, H - 44)
	f.size = Vector2(W, 44)
	_frame.add_child(f)
	_footer = _label("", 15, U.TEXT_DIM, "body", f)
	_footer.position = Vector2(30, 11)
	_refresh_footer()

func _refresh_footer() -> void:
	var near := 0
	var my := int(Ranked.me().mmr)
	for b in Ranked.bots():
		if absi(int(b.mmr) - my) <= 400:
			near += 1
	var on := Ranked.online_counts()
	_footer.text = "Season 1   ·   %d players on the ladder   ·   %d online, %d in a match   ·   %d near your MMR   ·   Ladder updated %s   ·   Leaving a ranked match counts as a loss" % [
		Ranked.leaderboard().size(), int(on[0]), int(on[1]), near, ago(int(Ranked.data.get("last_sim", Ranked.now())))]

func _layout() -> void:
	var vs := size
	var k := minf(vs.x / W, vs.y / H)
	_frame.scale = Vector2(k, k)
	_frame.position = ((vs - Vector2(W, H) * k) * 0.5).floor()
	_strip_top.position = Vector2(0, _frame.position.y)
	_strip_top.size = Vector2(vs.x, 92.0 * k)
	_strip_bot.position = Vector2(0, _frame.position.y + (H - 44.0) * k)
	_strip_bot.size = Vector2(vs.x, 44.0 * k)
	_toast.size = Vector2(760, 0)
	_toast.position = Vector2((vs.x - 760.0) * 0.5, 104.0 * k)
	if _offer:
		_offer.size = vs

func _show_tab(id: String) -> void:
	if not _pages.has(id):
		id = "play"
	if id == "profile" and _tab != "profile":
		_profile_id = "me" if _profile_id == "" else _profile_id
	_tab = id
	for k in _pages:
		(_pages[k] as Control).visible = k == id
	for k in _tab_btns:
		(_tab_btns[k] as TabButton).active = k == id
	if id == "profile":
		_fill_profile(_profile_id)
	elif id == "leaderboard":
		_fill_board()
	elif id == "players":
		_fill_players()
	elif id == "play":
		_refresh_play()

## Esc goes back, as the Back button does (fields, dropdowns and overlays get the key first).
func _unhandled_key_input(e: InputEvent) -> void:
	if U.is_esc(e) and _back_btn != null and _back_btn.is_visible_in_tree() and not (_offer != null and _offer.visible):
		get_viewport().set_input_as_handled()
		_back_btn.pressed.emit()

func _leave() -> void:
	if mm.state in ["searching", "found"]:
		mm.cancel()
	GameSettings.save()
	Options.go(get_tree(), MAIN_MENU)

func _notice(text: String) -> void:
	_toast.text = text
	_toast.size = Vector2(760, 0)
	_toast_t = 4.5

# ---- Play ---------------------------------------------------------------------------------------------------------

func _build_play() -> void:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = Vector2(W, H)
	_frame.add_child(page)
	_pages["play"] = page
	# left: your rank and your heroes
	var rank := _glass(Rect2(40, 118, 430, 520), page, "Your rank")
	_rank_view = EmblemView.new(300)
	_rank_view.position = Vector2(65, 50)
	_rank_view.size = Vector2(300, 300)
	rank.add_child(_rank_view)
	_rank_lbl = _label("", 30, U.GOLD, "title", rank)
	_rank_lbl.position = Vector2(0, 346)
	_rank_lbl.size = Vector2(430, 0)
	_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_sub = _label("", 17, U.TEXT, "bold", rank)
	_rank_sub.position = Vector2(0, 390)
	_rank_sub.size = Vector2(430, 0)
	_rank_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_bar = Bar.new()
	_rank_bar.position = Vector2(24, 444)
	_rank_bar.size = Vector2(382, 58)
	rank.add_child(_rank_bar)
	var heroes := _glass(Rect2(40, 656, 430, 368), page, "Your heroes")
	_heroes_box = VBoxContainer.new()
	_heroes_box.position = Vector2(18, 56)
	_heroes_box.size = Vector2(394, 300)
	_heroes_box.add_theme_constant_override("separation", 6)
	heroes.add_child(_heroes_box)
	# centre: roles and Find Match
	var mid := _glass(Rect2(500, 118, 920, 906), page, "")
	var h1 := _label("Choose your roles", 34, U.GOLD, "title", mid)
	h1.position = Vector2(36, 26)
	var h2 := _label("Tick every role you are happy to play. More roles find a match sooner. Bots on your team keep to the lanes they are given (most of them).", 17, U.TEXT_DIM, "body", mid)
	h2.position = Vector2(38, 80)
	h2.autowrap_mode = TextServer.AUTOWRAP_WORD
	h2.custom_minimum_size = Vector2(850, 0)
	h2.size = Vector2(850, 0)
	var mine: Array = Ranked.me().get("roles", [1, 2, 3, 4, 5])
	for i in 5:
		var rc := RoleCard.new()
		rc.role = i + 1
		rc.title = String(Ranked.ROLE_NAMES[i])
		rc.lane = String(Ranked.ROLE_LANES[i])
		rc.desc = String(ROLE_LINES[i])
		rc.on = (i + 1) in mine
		rc.position = Vector2(36 + i * 172, 150)
		rc.size = Vector2(160, 330)
		rc.toggled.connect(_on_role_toggled)
		mid.add_child(rc)
		_roles[i + 1] = rc
	var all := _button("All roles", func():
		for r in _roles:
			(_roles[r] as RoleCard).on = true
		_on_role_toggled(), "DarkButton", Vector2(150, 40))
	all.position = Vector2(36, 500)
	mid.add_child(all)
	_wait_lbl = _label("", 17, U.TEXT, "body", mid)
	_wait_lbl.position = Vector2(206, 509)
	_find_btn = BigButton.new()
	_find_btn.text = "Find Match"
	_find_btn.position = Vector2(36, 576)
	_find_btn.size = Vector2(848, 112)
	_find_btn.pressed.connect(_find)
	mid.add_child(_find_btn)
	_search_box = SearchPanel.new()
	_search_box.position = Vector2(36, 556)
	_search_box.size = Vector2(848, 300)
	_search_box.visible = false
	(_search_box as SearchPanel).mm = mm
	(_search_box as SearchPanel).cancel.connect(func():
		mm.cancel()
		_refresh_play())
	mid.add_child(_search_box)
	var hint := _label("Matches are 5 against 5 with experience and gold at 150%. A win gives 23 to 41 MMR, a loss takes 23 to 41: kills, assists, last hits and few deaths decide how many.", 15, U.TEXT_DIM, "body", mid)
	hint.position = Vector2(38, 712)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.size = Vector2(800, 0)
	hint.custom_minimum_size = Vector2(800, 0)
	hint.name = "Hint"
	# right: the top of the ladder and your recent games
	var top := _glass(Rect2(1450, 118, 430, 520), page, "Top of the ladder")
	_mini_board = VBoxContainer.new()
	_mini_board.position = Vector2(18, 54)
	_mini_board.size = Vector2(394, 440)
	_mini_board.add_theme_constant_override("separation", 4)
	top.add_child(_mini_board)
	var rec := _glass(Rect2(1450, 656, 430, 368), page, "Your recent matches")
	_recent_box = VBoxContainer.new()
	_recent_box.position = Vector2(18, 54)
	_recent_box.size = Vector2(394, 300)
	_recent_box.add_theme_constant_override("separation", 6)
	rec.add_child(_recent_box)

func _chosen_roles() -> Array:
	var out: Array = []
	for r in _roles:
		if (_roles[r] as RoleCard).on:
			out.append(int(r))
	out.sort()
	return out

func _on_role_toggled() -> void:
	var rs := _chosen_roles()
	if rs.is_empty():
		_notice("Pick at least one role.")
	else:
		Ranked.set_roles(rs)
	_refresh_play()

func _refresh_play() -> void:
	var me := Ranked.me()
	var tier := Ranked.tier_for(me)
	_rank_view.show_rank(tier, Ranked.stars(int(me.mmr)))
	_rank_lbl.text = Ranked.rank_label(me)
	_rank_sub.text = "%s MMR   ·   %s  ·  %s" % [num(int(me.mmr)), RankedNum.count(int(me.wins), "win", "wins"),
		RankedNum.count(int(me.losses), "loss", "losses")]
	for c in _heroes_box.get_children():
		c.queue_free()
	var played := Ranked.heroes_played(me)
	if played.is_empty():
		var e0 := _label("Your heroes show here once you play ranked matches: wins and losses on each, and your place in each hero's ranking.", 16, U.TEXT_DIM, "body", _heroes_box)
		e0.autowrap_mode = TextServer.AUTOWRAP_WORD
		e0.custom_minimum_size = Vector2(394, 0)
	for i in mini(4, played.size()):
		var hr := HeroRow.new()
		hr.p = me
		hr.hero = String(played[i][0])
		hr.custom_minimum_size = Vector2(394, 62)
		_heroes_box.add_child(hr)
	_rank_bar.set_rank(int(me.mmr), tier)
	var rs := _chosen_roles()
	var est := 8.0 + (6.0 if rs.size() <= 1 else (3.0 if rs.size() <= 2 else 0.0))
	if rs.size() > 0 and rs.all(func(r): return r <= 2):
		est += 5.0
	_wait_lbl.text = "Estimated wait: %s   ·   %s" % [_mmss(est), ", ".join(rs.map(func(r): return role_name(int(r)))) if not rs.is_empty() else "no role picked"]
	_find_btn.disabled = rs.is_empty()
	var searching := mm.state == "searching" or mm.state == "found" or mm.state == "ready"
	_find_btn.visible = not searching
	_search_box.visible = searching
	var hint := _find_btn.get_parent().get_node_or_null("Hint")
	if hint:
		hint.visible = not searching
	for r in _roles:
		(_roles[r] as RoleCard).locked = searching
	# the top of the ladder
	for c in _mini_board.get_children():
		c.queue_free()
	var board := Ranked.leaderboard()
	for i in mini(6, board.size()):
		_mini_board.add_child(_mini_row(board[i], i + 1))
	var you_at := Ranked.place_of("me")
	if you_at > 6:
		var gap := _label("·  ·  ·", 16, U.TEXT_DIM, "bold", _mini_board)
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mini_board.add_child(_mini_row(me, you_at))
	var all_btn := _button("Full leaderboard", func(): _show_tab("leaderboard"), "DarkButton", Vector2(394, 40))
	_mini_board.add_child(all_btn)
	# your recent games
	for c in _recent_box.get_children():
		c.queue_free()
	var hist: Array = me.get("history", [])
	if hist.is_empty():
		var e := _label("No ranked matches yet. Find a match to get started: you begin at 1,000 MMR.", 16, U.TEXT_DIM, "body", _recent_box)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD
		e.custom_minimum_size = Vector2(394, 0)
	for i in mini(5, hist.size()):
		var row := HistoryRow.new()
		row.e = hist[i]
		row.custom_minimum_size = Vector2(394, 48)
		_recent_box.add_child(row)
	_chip.queue_redraw()
	_refresh_footer()

func _mini_row(p: Dictionary, place: int) -> Control:
	var r := BoardRow.new()
	r.p = p
	r.place = place
	r.compact = true
	r.custom_minimum_size = Vector2(394, 50)
	r.clicked.connect(func(): _open_profile(String(p.id)))
	r.hover_card.connect(_hover_player)
	return r

static func _mmss(s: float) -> String:
	return RankedNum.mmss(s)

func _find() -> void:
	var rs := _chosen_roles()
	if rs.is_empty():
		_notice("Pick at least one role.")
		return
	Ranked.catch_up()
	mm.start(rs)
	(_search_box as SearchPanel).mm = mm
	_refresh_play()

func _process(dt: float) -> void:
	if RankEmblem.baked != _baked_seen:
		_baked_seen = RankEmblem.baked             # new emblem pictures: draw the rows and cards again
		propagate_call("queue_redraw")
	var was := mm.state
	var note_before := mm.note
	if mm.state == "searching" or mm.state == "found":
		mm.step(dt)
	if (mm.state == "found" or mm.state == "ready") and not _offer.visible:
		_open_offer()
	if mm.state == "ready" and _lineup_t < 0.0:
		_lineup()
	if was == "found" and not (mm.state in ["found", "ready"]):
		_close_offer()
		if mm.state == "failed":
			mm.cancel()
		_refresh_play()
	if mm.note != note_before and mm.note != "":
		_notice(mm.note)
	if _offer.visible:
		_update_offer(dt)
	# friend chat (run 2026-10-20 e): answers arrive while you are on this screen
	_chat_t += dt
	if _chat_t >= 1.0:
		_chat_t = 0.0
		var got := FriendChat.tick()
		if not got.is_empty():
			if _tab == "players":
				_fill_players()
			for gid in got:
				if not (_tab == "players" and _middle == "chat" and _chat_id == String(gid)):
					var gp := Ranked.profile(String(gid))
					var ms := FriendChat.messages(String(gid))
					if not ms.is_empty():
						_notice("%s: %s" % [String(gp.get("name", "")), String(ms[ms.size() - 1].x)])
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(minf(_toast_t, 4.5 - _toast_t) / 0.3, 0.0, 1.0)
	if _hover_i >= 0 and _frames == 20:
		_force_hover()
	if _capture != "":
		_frames += 1
		if _frames == _cap_frames:
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

# ---- The match offer ------------------------------------------------------------------------------------------------

func _build_offer() -> void:
	_offer = Control.new()
	_offer.visible = false
	_offer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_offer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.95)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_offer.add_child(dim)
	var inner := Control.new()
	inner.name = "Inner"
	inner.size = Vector2(W, H)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offer.add_child(inner)
	var box := OfferBox.new()
	box.name = "Box"
	box.position = Vector2(W * 0.5 - 420, 210)
	box.size = Vector2(840, 600)
	box.mm = mm
	inner.add_child(box)
	_offer_title = _label("Your match is ready", 44, U.GOLD, "title", box)
	_offer_title.position = Vector2(0, 34)
	_offer_title.size = Vector2(840, 0)
	_offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offer_sub = _label("", 18, U.TEXT, "body", box)
	_offer_sub.position = Vector2(0, 100)
	_offer_sub.size = Vector2(840, 0)
	_offer_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_accept_btn = BigButton.new()
	_accept_btn.text = "Accept"
	_accept_btn.big = true
	_accept_btn.position = Vector2(170, 330)
	_accept_btn.size = Vector2(500, 120)
	_accept_btn.pressed.connect(func():
		mm.accept()
		_accept_btn.disabled = true
		_accept_btn.text = "Accepted")
	box.add_child(_accept_btn)
	_decline_btn = _button("Decline", func():
		_close_offer()
		mm.decline()
		_refresh_play(), "DarkButton", Vector2(220, 50))
	_decline_btn.position = Vector2(310, 480)
	_decline_btn.size = Vector2(220, 50)
	box.add_child(_decline_btn)
	for t in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.position = Vector2(36 if t == 0 else W - 36 - 420, 190)
		col.size = Vector2(420, 700)
		inner.add_child(col)
		_offer_cols.append(col)

func _open_offer() -> void:
	_offer.visible = true
	_offer.size = size
	_accept_btn.disabled = false
	_accept_btn.text = "Accept"
	_decline_btn.disabled = false
	_offer_title.text = "Your match is ready"
	_lineup_t = -1.0
	var l := mm.lineup
	var mine := int(l.mine)
	_offer_sub.text = "Ranked 5 vs 5  ·  your role: %s  ·  heroes are picked next" % role_name(int(l.my_role))
	for t in 2:
		var col: VBoxContainer = _offer_cols[t]
		for c in col.get_children():
			c.queue_free()
		var team_i := mine if t == 0 else 1 - mine
		var head := _label("Your team  ·  %s" % SimConst.TEAM_NAMES[team_i] if t == 0 else "Enemy team  ·  %s" % SimConst.TEAM_NAMES[team_i],
			20, BLUE if t == 0 else RED, "title", col)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if t == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var avg := _label("Average MMR %s" % num(int(l.avg[team_i])), 15, U.TEXT_DIM, "body", col)
		avg.horizontal_alignment = head.horizontal_alignment
		for p in l.teams[team_i]:
			var pc := MatchCard.new()
			pc.p = p
			pc.role = int(l.roles.get(String(p.id), 0))
			pc.right = t == 1
			pc.mm = mm
			pc.custom_minimum_size = Vector2(420, 92)
			pc.hover_card.connect(_hover_player)
			col.add_child(pc)
	Options.click()

func _update_offer(dt: float) -> void:
	_offer.size = size
	var inner: Control = _offer.get_node("Inner")
	var k := minf(size.x / W, size.y / H)
	inner.scale = Vector2(k, k)
	inner.position = ((size - Vector2(W, H) * k) * 0.5).floor()
	(_offer.get_node("Inner/Box") as Control).queue_redraw()
	for col in _offer_cols:
		for c in (col as Control).get_children():
			if c is MatchCard:
				c.queue_redraw()
	if _lineup_t >= 0.0:
		_lineup_t += dt
		if _lineup_t > 2.6 and not _launching:
			_launch()

func _close_offer() -> void:
	_offer.visible = false
	_card.visible = false

func _lineup() -> void:
	_offer_title.text = "Match ready"
	_offer_sub.text = "Everyone accepted. Next: the hero pick (you play %s)." % role_name(int(mm.lineup.my_role))
	_accept_btn.text = "Everyone accepted"
	_accept_btn.disabled = true
	_decline_btn.disabled = true
	_lineup_t = 0.0

func _launch() -> void:
	_launching = true
	Matchmaker.accepted_match = mm.lineup.duplicate(true)
	Options.go(get_tree(), DRAFT)

func _hover_player(p: Dictionary, at: Rect2, on: bool) -> void:
	if not on:
		_card.visible = false
		return
	_card.show_for(p)
	var k := minf(size.x / W, size.y / H)
	var cs := _card.size * k
	_card.scale = Vector2(k, k)
	var pos := Vector2(at.end.x + 12.0, at.position.y)
	if _offer.visible:
		pos.x = at.position.x + (at.size.x - cs.x) * 0.5
		pos.y = at.end.y + 6.0 if at.end.y + 6.0 + cs.y <= size.y - 8.0 else at.position.y - cs.y - 6.0
	elif pos.x + cs.x > size.x - 8.0:
		pos.x = at.position.x - cs.x - 12.0
	pos.x = clampf(pos.x, 8.0, size.x - cs.x - 8.0)
	pos.y = clampf(pos.y, 8.0, size.y - cs.y - 8.0)
	_card.position = pos
	_card.visible = true
	move_child(_card, get_child_count() - 1)

func _force_hover() -> void:
	# captures: show the card of the n-th player on the offer (or the leaderboard)
	var cards: Array = []
	for col in _offer_cols:
		for c in (col as Control).get_children():
			if c is MatchCard:
				cards.append(c)
	if cards.is_empty() and _board_list != null:
		for c in _board_list.get_children():
			if c is BoardRow:
				cards.append(c)
	if _hover_i < cards.size():
		var c: Control = cards[_hover_i]
		_hover_player(c.p, c.get_global_rect(), true)

# ---- Profile --------------------------------------------------------------------------------------------------------

func _build_profile_page() -> void:
	_profile_page = Control.new()
	_profile_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_page.size = Vector2(W, H)
	_frame.add_child(_profile_page)
	_pages["profile"] = _profile_page
	# the profile (run 2026-10-20: ProfilePage; yours and everyone's)
	_ppage = ProfilePage.new()
	_ppage.position = Vector2(40, 104)
	_profile_page.add_child(_ppage)
	_ppage.back_pressed.connect(func(): _show_tab("players" if _came_from == "players" else "leaderboard"))
	_ppage.changed.connect(func():
		_chip.queue_redraw()
		_refresh_footer())

func _open_profile(id: String) -> void:
	if _tab != "profile":
		_came_from = _tab
	_profile_id = id
	_show_tab("profile")

var _came_from := ""
var _ppage: ProfilePage

## A line about a player's games with you: "With you 3 (2 won)  ·  Against 1 (1 lost)  ·  Likes you".
static func _with_you(p: Dictionary) -> String:
	var y: Dictionary = p.get("you", {})
	if y.is_empty() or int(y.get("games", 0)) == 0:
		return "Never played with you"
	var parts: Array = []
	if int(y.get("with", 0)) > 0:
		parts.append("With you %d (%d won)" % [int(y.with), int(y.get("with_w", 0))])
	if int(y.get("vs", 0)) > 0:
		parts.append("Against %d (you won %d)" % [int(y.vs), int(y.vs) - int(y.get("vs_w", 0))])
	parts.append(Persona.feeling(float(y.get("rep", 0.0))))
	return "  ·  ".join(parts)

static func _feeling(rep: float) -> String:
	return Persona.feeling(rep)

func _fill_profile(id: String) -> void:
	var from := ""
	if id != "me":
		from = {"players": "Players", "leaderboard": "Leaderboard", "play": "Play"}.get(_came_from, "Leaderboard")
	if _ppage.pid != id or _ppage.came_from != from or _ppage.view_as != "":
		_ppage.show_id(id, from)
	else:
		_ppage.refresh()
	if _profile_view == "heroes" and _ppage.side_tab != "heroes":
		_ppage.side_tab = "heroes"
		_ppage.refresh()

# ---- The player menu's host (PlayerMenu: right-click a player anywhere) ------------------------------------------------

func notice(text: String) -> void:
	_notice(text)

## What the player menu asks for: a profile, its history, a comparison, a comment, View As, a hero's ranking.
func player_action(action: String, id: String) -> void:
	_card.visible = false
	if action.begins_with("hero:"):
		_board_filter = "heroes"
		_board_hero = action.substr(5)
		_show_tab("leaderboard")
		return
	_open_profile(id)
	match action:
		"compare":
			_ppage.open_compare()
		"write":
			_ppage.side_tab = "wall"
			_ppage.refresh()
		"view_as":
			_ppage.view_as = "public"
			_ppage.refresh()

## After a menu action (friend, commend, block): the open tab shows it.
func refresh_social() -> void:
	_show_tab(_tab)

func _your_heroes() -> Array:
	var count := {}
	for e in Ranked.me().get("history", []):
		var h := String(e.get("h", ""))
		if h != "":
			count[h] = int(count.get(h, 0)) + 1
	var ids := count.keys()
	ids.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	return ids

static func _streak(s: int) -> String:
	if s > 0:
		return "%d won" % s
	if s < 0:
		return "%d lost" % -s
	return "-"

# ---- Leaderboard ----------------------------------------------------------------------------------------------------

func _build_board() -> void:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = Vector2(W, H)
	_frame.add_child(page)
	_pages["leaderboard"] = page
	var g := _glass(Rect2(40, 118, 1840, 906), page, "")
	var t := _label("Leaderboard", 36, U.GOLD, "title", g)
	t.position = Vector2(36, 24)
	var sub := _label("Everyone on the ladder by MMR. The top ten Aetherium players are Aetherium+. It changes as players finish matches.", 17, U.TEXT_DIM, "body", g)
	sub.position = Vector2(38, 80)
	var x := 1840.0 - 36.0
	for f in [["heroes", "Heroes"], ["near", "Near me"], ["top", "Top 100"], ["all", "Everyone"]]:
		var fid := String(f[0])
		var b := _button(String(f[1]), func():
			_board_filter = fid
			_fill_board(), "DarkButton", Vector2(150, 42))
		x -= 160.0
		b.position = Vector2(x, 30)
		b.name = "F_" + fid
		g.add_child(b)
	var head := BoardHead.new()
	head.position = Vector2(30, 122)
	head.size = Vector2(1780, 40)
	g.add_child(head)
	_board_head = head
	_hero_strip = HBoxContainer.new()
	_hero_strip.position = Vector2(30, 112)
	_hero_strip.add_theme_constant_override("separation", 6)
	_hero_strip.visible = false
	g.add_child(_hero_strip)
	for h in GameSettings.random_pool():
		var hb := HeroPickChip.new()
		hb.hero = String(h)
		hb.custom_minimum_size = Vector2(56, 56)
		var hid := String(h)
		hb.pressed.connect(func():
			_board_hero = hid
			_fill_board())
		_hero_strip.add_child(hb)
	var sc := ScrollContainer.new()
	sc.position = Vector2(30, 166)
	sc.size = Vector2(1780, 620)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.add_child(sc)
	_board_list = VBoxContainer.new()
	_board_list.custom_minimum_size = Vector2(1764, 0)
	_board_list.add_theme_constant_override("separation", 4)
	sc.add_child(_board_list)
	_board_you = Control.new()
	_board_you.position = Vector2(30, 820)
	_board_you.size = Vector2(1780, 62)
	g.add_child(_board_you)

func _fill_board() -> void:
	for c in _board_list.get_children():
		c.queue_free()
	for c in _board_you.get_children():
		c.queue_free()
	var hero_mode := _board_filter == "heroes"
	_hero_strip.visible = hero_mode
	var sc: Control = _board_list.get_parent()
	sc.position.y = 230.0 if hero_mode else 166.0
	sc.size.y = 558.0 if hero_mode else 620.0
	_board_head.position.y = 186.0 if hero_mode else 122.0
	(_board_head as BoardHead).hero_mode = hero_mode
	_board_head.queue_redraw()
	if hero_mode:
		if _board_hero == "":
			_board_hero = String(GameSettings.random_pool()[0])
		for c in _hero_strip.get_children():
			c.selected = c.hero == _board_hero
			c.queue_redraw()
		var hb := Ranked.hero_board(_board_hero)
		for i in hb.size():
			var r := BoardRow.new()
			r.p = Ranked.profile(String(hb[i].id))
			r.place = i + 1
			r.hero = _board_hero
			r.hero_entry = hb[i]
			r.custom_minimum_size = Vector2(1764, 58)
			var pid := String(hb[i].id)
			r.clicked.connect(func(): _open_profile(pid))
			_board_list.add_child(r)
		var you_h := Ranked.hero_place("me", _board_hero)
		var mine_r := BoardRow.new()
		mine_r.p = Ranked.me()
		mine_r.place = you_h
		mine_r.hero = _board_hero
		mine_r.hero_entry = hb[you_h - 1] if you_h > 0 else {}
		mine_r.pinned = true
		mine_r.size = Vector2(1780, 62)
		mine_r.clicked.connect(func(): _open_profile("me"))
		_board_you.add_child(mine_r)
		return
	var board := Ranked.leaderboard()
	var you := Ranked.place_of("me")
	var from := 0
	var to := board.size()
	if _board_filter == "top":
		to = mini(100, board.size())
	elif _board_filter == "near":
		from = maxi(0, you - 1 - 12)
		to = mini(board.size(), you + 12)
	for i in range(from, to):
		var r := BoardRow.new()
		r.p = board[i]
		r.place = i + 1
		r.custom_minimum_size = Vector2(1764, 58)
		var pid := String(board[i].id)
		r.clicked.connect(func(): _open_profile(pid))
		r.hover_card.connect(_hover_player)
		_board_list.add_child(r)
	var mine := BoardRow.new()
	mine.p = Ranked.me()
	mine.place = you
	mine.pinned = true
	mine.size = Vector2(1780, 62)
	mine.clicked.connect(func(): _open_profile("me"))
	_board_you.add_child(mine)

# ---- Players --------------------------------------------------------------------------------------------------------

func _build_players() -> void:
	_players_page = Control.new()
	_players_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_players_page.size = Vector2(W, H)
	_frame.add_child(_players_page)
	_pages["players"] = _players_page

func _list_in(g: Control, top: float, h: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.position = Vector2(16, top)
	sc.size = Vector2(g.size.x - 32, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(g.size.x - 46, 0)
	list.add_theme_constant_override("separation", 5)
	sc.add_child(list)
	return list

func _hint(text: String, parent: Control) -> void:
	var l := _label(text, 16, U.TEXT_DIM, "body", parent)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(parent.custom_minimum_size.x, 0)

func _person(p: Dictionary, sub: String, right := "", right_col := U.TEXT_DIM) -> PersonRow:
	var r := PersonRow.new()
	r.p = p
	r.sub = sub
	r.right = right
	r.right_col = right_col
	r.custom_minimum_size = Vector2(540, 64)
	var pid := String(p.id)
	r.clicked.connect(func(): _open_profile(pid))
	r.hover_card.connect(_hover_player)
	return r

## The Players tab (run 2026-10-20 e; the owner: "Overhaul and GREATLY ENHANCE ... the PLAYERS UI, like showing how many
## friends and online friends and offline friends and others, Friend chat"). Three panels:
##   * Friends: how many, online, in a match, offline, requests; filters (All, Online, In a match, Offline, Requests);
##     each friend with presence, status, rank, unread messages and a Chat button; requests with Accept and Ignore.
##   * Chat (a conversation with a friend: their messages and yours, typing, Send; the conversations list) or Ladder
##     activity.
##   * Online now, Recently played with, Top 20 (the ladder as every player knows it) and Find player (anyone by name).
func _fill_players() -> void:
	for c in _players_page.get_children():
		c.queue_free()
	Ranked.catch_up()
	FriendChat.tick()
	var you := Ranked.me()
	var t := Ranked.now()
	var friends: Array = (you.get("friends", []) as Array).map(func(id): return Ranked.profile(String(id))).filter(func(x): return not x.is_empty())
	friends.sort_custom(func(a, b): return _presence_rank(a, t) * 1000 - FriendChat.unread(String(a.id)) < _presence_rank(b, t) * 1000 - FriendChat.unread(String(b.id)))
	var n_on := 0
	var n_match := 0
	for fp in friends:
		var st := String(Persona.presence(fp, t).state)
		n_on += 1 if st == "online" else 0
		n_match += 1 if st == "match" else 0
	var n_off := friends.size() - n_on - n_match
	var reqs: Array = you.get("requests", [])
	# ---- friends
	var fr := _glass(Rect2(40, 118, 600, 906), _players_page, "Friends")
	var counts := FriendCounts.new()
	counts.position = Vector2(20, 60)
	counts.size = Vector2(560, 64)
	counts.vals = [friends.size(), n_on, n_match, n_off, reqs.size()]
	fr.add_child(counts)
	var fx := 20.0
	for fdef in [["all", "All"], ["online", "Online"], ["match", "In a match"], ["offline", "Offline"], ["requests", "Requests"]]:
		var key := String(fdef[0])
		var lbl := String(fdef[1]) + ("  %d" % reqs.size() if key == "requests" and not reqs.is_empty() else "")
		var fb := _button(lbl, func():
			_friend_filter = key
			_fill_players(), "DarkButton", Vector2(0, 38))
		if _friend_filter == key:
			_chip_on(fb)
		fb.add_theme_font_size_override("font_size", 15)
		fb.position = Vector2(fx, 134)
		fr.add_child(fb)
		fb.reset_size()
		fx += fb.size.x + 8.0
	var fl := _list_in(fr, 186, 704)
	if _friend_filter in ["all", "requests"]:
		for q in reqs:
			var qp := Ranked.profile(String(q.get("id", "")))
			if qp.is_empty():
				continue
			var row := _person(qp, "Wants to be friends  ·  after a game %s you" % ("with" if String(q.get("after", "")) == "with" else "against"))
			row.request = true
			var qid := String(qp.id)
			row.accept.connect(func():
				Ranked.accept_request(qid)
				_notice("You and %s are now friends." % String(Ranked.profile(qid).get("name", "")))
				_fill_players())
			row.ignore.connect(func():
				Ranked.ignore_request(qid)
				_fill_players())
			fl.add_child(row)
	var shown := 0
	if _friend_filter != "requests":
		for fp in friends:
			var pr := Persona.presence(fp, t)
			if _friend_filter != "all" and String(pr.state) != _friend_filter:
				continue
			var fid := String(fp.id)
			var row2 := _person(fp, "%s  ·  %s" % [String(pr.label), Persona.status(fp) if bool(fp.get("bot", false)) else "Your account"], Ranked.rank_label(fp))
			row2.chat = true
			row2.unread = FriendChat.unread(fid)
			row2.open_chat.connect(func(): _open_chat(fid))
			if fid == _chat_id and _middle == "chat":
				row2.lit = true
			fl.add_child(row2)
			shown += 1
	if shown == 0 and (_friend_filter != "all" or reqs.is_empty()) and not (_friend_filter in ["all", "requests"] and not reqs.is_empty()):
		var none := {"all": "No friends yet. Players who enjoy a game with you send friend requests, and they show here. Add anyone from Find player or their profile.",
			"online": "None of your friends is online and free right now.", "match": "None of your friends is in a match right now.",
			"offline": "All your friends are on.", "requests": "No friend requests."}
		_hint(String(none.get(_friend_filter, "")), fl)
	# ---- the middle: friend chat or the ladder's news
	var mid := _glass(Rect2(660, 118, 600, 906), _players_page, "")
	var mx := 20.0
	var unread_all := FriendChat.unread_total()
	for mdef in [["chat", "Chat" + ("  %d" % unread_all if unread_all > 0 else "")], ["activity", "Ladder activity"]]:
		var mkey := String(mdef[0])
		var mb := _button(String(mdef[1]), func():
			_middle = mkey
			_fill_players(), "DarkButton", Vector2(0, 42))
		if _middle == mkey:
			_chip_on(mb)
		mb.position = Vector2(mx, 18)
		mid.add_child(mb)
		mb.reset_size()
		mx += mb.size.x + 10.0
	if _middle == "chat":
		_fill_chat(mid)
	else:
		var al := _list_in(mid, 76, 814)
		var feed: Array = Ranked.data.get("feed", [])
		var n_feed := 0
		for fe in feed:
			if n_feed >= 50:
				break
			var txt := Ranked.feed_text(fe)
			if txt == "":
				continue
			var frow := FeedRow.new()
			frow.p = Ranked.profile(String(fe.get("id", "")))
			frow.text = txt
			frow.when = ago(int(fe.get("t", t)))
			frow.kind = String(fe.get("k", ""))
			frow.custom_minimum_size = Vector2(540, 54)
			var feid := String(fe.get("id", ""))
			frow.clicked.connect(func(): _open_profile(feid))
			al.add_child(frow)
			n_feed += 1
		if n_feed == 0:
			_hint("What happens on the ladder shows here: ranks reached, streaks, medals, heroes being learned.", al)
	# ---- the right: who is on, who you met, the top 20, anyone by name
	var rt := _glass(Rect2(1280, 118, 600, 906), _players_page, "")
	var rx := 20.0
	for rdef in [["online", "Online now"], ["recent", "Recent"], ["top", "Top 20"], ["find", "Find player"]]:
		var rkey := String(rdef[0])
		var rb := _button(String(rdef[1]), func():
			_right = rkey
			_fill_players(), "DarkButton", Vector2(0, 42))
		if _right == rkey:
			_chip_on(rb)
		rb.add_theme_font_size_override("font_size", 16)
		rb.position = Vector2(rx, 18)
		rt.add_child(rb)
		rb.reset_size()
		rx += rb.size.x + 8.0
	match _right:
		"online":
			var oc := Ranked.online_counts()
			var cl := _label("%s online  ·  %s in a match  ·  %s on the ladder" % [num(int(oc[0])), num(int(oc[1])), num(Ranked.leaderboard().size())],
				16, U.TEXT, "bold", rt)
			cl.position = Vector2(20, 74)
			var ol := _list_in(rt, 106, 784)
			var mine := int(you.mmr)
			var online: Array = Ranked.bots().filter(func(bp): return Persona.online(bp, t))
			online.sort_custom(func(x, y): return absi(int(x.mmr) - mine) < absi(int(y.mmr) - mine))
			for op in online.slice(0, 40):
				var pr2 := Persona.presence(op, t)
				ol.add_child(_person(op, String(pr2.label), Ranked.rank_label(op)))
		"recent":
			var rl := _list_in(rt, 76, 814)
			var met := Ranked.recent_players(30)
			for e in met:
				var mp: Dictionary = e[0]
				var y: Dictionary = mp.get("you", {})
				var side := "With you" if String(y.get("last_side", "")) == "with" else "Against you"
				var res := ("won" if String(y.get("last_res", "")) == "W" else "lost") if String(y.get("last_side", "")) == "with" else \
					("you lost" if String(y.get("last_res", "")) == "W" else "you won")
				var feel := _feeling(float(y.get("rep", 0.0)))
				var fc := GREEN_HI if float(y.get("rep", 0.0)) > 0.15 else (RED if float(y.get("rep", 0.0)) < -0.15 else U.TEXT_DIM)
				rl.add_child(_person(mp, "%s (%s)  ·  %d games  ·  %s" % [side, res, int(y.get("games", 0)), ago(int(e[1]))], feel, fc))
			if met.is_empty():
				_hint("The players from your ranked matches show here, with what they think of you.", rl)
		"top":
			var tl := _list_in(rt, 76, 814)
			for e in Ranked.ladder_card(20):
				var tp := Ranked.profile(String(e.id))
				var sub := "#%d  ·  %s MMR  ·  %s avg  ·  %s" % [int(e.place), num(int(e.mmr)), String(e.kda), String(e.hero)]
				tl.add_child(_person(tp, sub, Ranked.rank_label(tp), U.GOLD if int(e.place) <= Ranked.TOP else U.TEXT_DIM))
		"find":
			var box := LineEdit.new()
			box.placeholder_text = "Type a name (2 letters or more)"
			box.text = _find_text
			box.position = Vector2(20, 76)
			box.size = Vector2(560, 46)
			rt.add_child(box)
			var res_list := _list_in(rt, 136, 754)
			var fill_find := func(q: String):
				for c in res_list.get_children():
					c.queue_free()
				_find_text = q
				var ql := q.strip_edges().to_lower()
				if ql.length() < 2:
					_hint("Find anyone on the ladder by name: see their profile, add them, or write to them once you are friends.", res_list)
					return
				var hits: Array = Ranked.all_profiles().filter(func(fp2): return String(fp2.get("name", "")).to_lower().contains(ql))
				hits.sort_custom(func(x, y): return int(String(x.name).to_lower().begins_with(ql)) > int(String(y.name).to_lower().begins_with(ql)) \
					if String(x.name).to_lower().begins_with(ql) != String(y.name).to_lower().begins_with(ql) else int(x.mmr) > int(y.mmr))
				for hp in hits.slice(0, 30):
					var friend := String(hp.id) in (Ranked.me().get("friends", []) as Array)
					var tag := "You" if String(hp.id) == "me" else ("Your account" if Ranked.is_account(String(hp.id)) else ("Friend" if friend else ""))
					res_list.add_child(_person(hp, "%s  ·  %s MMR  ·  #%s" % [String(Persona.presence(hp, t).label), num(int(hp.mmr)),
						num(Ranked.place_of(String(hp.id)))], tag if tag != "" else Ranked.rank_label(hp), U.GOLD if tag != "" else U.TEXT_DIM))
				if hits.is_empty():
					_hint("Nobody on the ladder has a name like that.", res_list)
			box.text_changed.connect(func(q: String): fill_find.call(q))
			fill_find.call(_find_text)
			box.grab_focus.call_deferred()

## A chip that is on: the lit tab skin and gold words.
func _chip_on(b: Button) -> void:
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, U.box("soc_tab_on", 8.0))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, U.GOLD)

## Open a conversation with a friend (middle panel).
func _open_chat(id: String) -> void:
	_chat_id = id
	_middle = "chat"
	FriendChat.mark_read(id)
	_fill_players()

## The middle panel's chat: the conversation with the chosen friend, or the list of conversations.
func _fill_chat(mid: Control) -> void:
	var friends: Array = Ranked.me().get("friends", [])
	if _chat_id != "" and not (_chat_id in friends):
		_chat_id = ""
	if _chat_id == "":
		var cl := _list_in(mid, 76, 814)
		var convs := FriendChat.recent()
		for c in convs:
			var cp := Ranked.profile(String(c[0]))
			var last: Dictionary = c[1]
			var who := "You: " if String(last.f) == "y" else ""
			var row := PersonRow.new()
			row.p = cp
			row.sub = who + String(last.x)
			row.right = ago(int(last.t))
			row.custom_minimum_size = Vector2(540, 64)
			row.unread = FriendChat.unread(String(c[0]))
			var cid := String(c[0])
			row.clicked.connect(func(): _open_chat(cid))
			cl.add_child(row)
		if convs.is_empty():
			_hint("Your conversations show here. Press Chat on a friend to write to them: online friends answer in seconds, friends in a match after it, away friends when they are back.", cl)
		return
	FriendChat.mark_read(_chat_id)
	var p := Ranked.profile(_chat_id)
	var head := ChatHead.new()
	head.p = p
	head.position = Vector2(20, 72)
	head.size = Vector2(560, 72)
	head.back.connect(func():
		_chat_id = ""
		_fill_players())
	head.profile.connect(func(): _open_profile(String(p.id)))
	mid.add_child(head)
	var sc := ScrollContainer.new()
	sc.position = Vector2(20, 154)
	sc.size = Vector2(560, 650)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sc)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(540, 0)
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var ms := FriendChat.messages(_chat_id)
	for m in ms:
		var bub := Bubble.new()
		bub.mine = String(m.f) == "y"
		bub.text = String(m.x)
		bub.when = ago(int(m.t))
		bub.custom_minimum_size = Vector2(540, Bubble.height_for(String(m.x)))
		list.add_child(bub)
	if ms.is_empty():
		_hint("Say hi to %s." % String(p.get("name", "")), list)
	if FriendChat.typing(_chat_id):
		_label("%s is typing..." % String(p.get("name", "")), 14, U.TEXT_DIM, "body", list)
	_chat_scroll = sc
	(func(): sc.scroll_vertical = int(list.size.y) + 1000).call_deferred()
	var edit := LineEdit.new()
	edit.placeholder_text = "Write to %s (Enter)" % String(p.get("name", ""))
	edit.max_length = 300
	edit.text = _chat_draft
	edit.caret_column = _chat_draft.length()
	edit.text_changed.connect(func(x: String): _chat_draft = x)
	edit.position = Vector2(20, 822)
	edit.size = Vector2(440, 48)
	mid.add_child(edit)
	var send := func():
		var x := edit.text.strip_edges()
		if x == "":
			return
		FriendChat.send(_chat_id, x)
		_chat_draft = ""
		_fill_players()
	edit.text_submitted.connect(func(_s): send.call())
	var sb := _button("Send", send, "GoldButton", Vector2(110, 48))
	sb.position = Vector2(470, 822)
	mid.add_child(sb)
	edit.grab_focus.call_deferred()

## Friends first online and free, then in a match, then away.
static func _presence_rank(p: Dictionary, t: int) -> int:
	var st := String(Persona.presence(p, t).state)
	return 0 if st == "online" else (1 if st == "match" else 2)

# ---- Guilds ---------------------------------------------------------------------------------------------------------

func _build_guilds() -> void:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = Vector2(W, H)
	_frame.add_child(page)
	_pages["guilds"] = page
	var g := _glass(Rect2(W * 0.5 - 520, 230, 1040, 560), page, "")
	var crest := GuildCrest.new()
	crest.position = Vector2(420, 50)
	crest.size = Vector2(200, 200)
	g.add_child(crest)
	var t := _label("Guilds", 50, U.GOLD, "title", g)
	t.position = Vector2(0, 270)
	t.size = Vector2(1040, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var soon := _label("Coming soon", 26, U.TEXT, "bold", g)
	soon.position = Vector2(0, 340)
	soon.size = Vector2(1040, 0)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := _label("Players of Licensed rank (1,200 MMR) and above will be able to start a guild or join one, play together and climb the guild ladder.", 18, U.TEXT_DIM, "body", g)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size = Vector2(800, 0)
	d.size = Vector2(800, 0)
	d.position = Vector2(120, 396)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := _button("Coming soon", func(): pass, "DarkButton", Vector2(260, 50))
	b.disabled = true
	b.position = Vector2(390, 476)
	g.add_child(b)

# =====================================================================================================================
# Widgets
# =====================================================================================================================

## A glass panel: dark translucent body, a thin gold rim, a light line along the top, gold corner marks, a title.
class Glass extends Control:
	var title := ""
	var quiet := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# the generated skin (tools/ui_skin_social.py): gold-rimmed enamel, a quiet inset for small boxes
		U.skin(self, "soc_card" if quiet else "soc_panel", r)
		if title != "":
			U.text(self, title, Vector2(26, 40), 22, U.GOLD, "title")
			draw_line(Vector2(26, 50), Vector2(size.x - 26, 50), Color(U.GOLD, 0.2), 1.0)
	static func _box(bg: Color, border: Color, rad: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(rad)
		s.anti_aliasing = true
		return s

class TopBar extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		U.art_rect(self, "soc_topbar", Rect2(Vector2.ZERO, Vector2(size.x, size.y + 4)))

class FooterBar extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.9))
		draw_line(Vector2(0, 0), Vector2(size.x, 0), Color(U.GOLD, 0.3), 1.0)

class TabButton extends Control:
	signal pressed
	var text := ""
	var soon := false
	var active := false:
		set(v):
			active = v
			queue_redraw()
	var _hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			pressed.emit()
			accept_event()
	func _draw() -> void:
		var col := U.GOLD if active else (Color(1.0, 0.92, 0.75) if _hover else U.TEXT_DIM)
		if active:
			U.skin(self, "soc_tab_on", Rect2(Vector2.ZERO, size))
		elif _hover:
			U.skin(self, "soc_tab_hover", Rect2(Vector2.ZERO, size))
		var f := U.font("title")
		var fs := 22
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (size.x - tw) * 0.5 - (28.0 if soon else 0.0)
		draw_string(f, Vector2(x, size.y * 0.5 + 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if soon:
			var pr := Rect2(x + tw + 8, size.y * 0.5 - 12, 48, 22)
			draw_rect(pr, Color(0.3, 0.3, 0.36, 0.95))
			draw_string(U.font("bold"), Vector2(pr.position.x + 6, pr.position.y + 16), "Soon", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT)

## Your picture, name, rank and MMR at the top right (opens your profile).
class ProfileChip extends Control:
	signal clicked
	var _av: Avatar
	var _hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_av = Avatar.new()
		_av.position = Vector2(size.x - 66, 6)
		_av.size = Vector2(56, 56)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_av)
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e):
			PlayerMenu.open(self, "me", SocialUi.at(self, e))
			accept_event()
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			clicked.emit()
			accept_event()
	func _draw() -> void:
		var me := Ranked.me()
		_av.set_spec(me.get("avatar", {"k": "none"}))
		if _hover:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.5, 0.06))
		var tier := Ranked.tier_for(me)
		var ic := RankEmblem.icon(tier)
		if ic:
			draw_texture_rect(ic, Rect2(size.x - 140, 0, 68, 68), false)
		var right := size.x - 150.0
		var f := U.font("bold")
		var nm := String(me.name)
		var nw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(f, Vector2(right - nw, 30), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, U.TEXT)
		var sub := "%s  ·  %s MMR" % [Ranked.rank_label(me), RankedNum.num(int(me.mmr))]
		var sw := U.font("body").get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(U.font("body"), Vector2(right - sw, 54), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.GOLD)

## A role to tick: its icon, a small map with its lane, name, lane, a line about it, and a check mark.
class RoleCard extends Control:
	signal toggled
	var role := 1
	var title := ""
	var lane := ""
	var desc := ""
	var on := true:
		set(v):
			on = v
			queue_redraw()
	var locked := false:
		set(v):
			locked = v
			queue_redraw()
	var _hover := 0.0
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hot = true)
		mouse_exited.connect(func(): _hot = false)
	func _process(dt: float) -> void:
		var want := 1.0 if _hot and not locked else 0.0
		if absf(_hover - want) > 0.001:
			_hover = move_toward(_hover, want, dt * 6.0)
			queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if locked:
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			on = not on
			Options.click()
			toggled.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var lift := -4.0 * _hover
		r.position.y += lift
		var bg := Color(0.09, 0.11, 0.16, 0.95) if on else Color(0.05, 0.06, 0.09, 0.85)
		var rim := U.GOLD if on else Color(1, 1, 1, 0.12 + 0.2 * _hover)
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = rim
		s.set_border_width_all(2 if on else 1)
		s.set_corner_radius_all(8)
		s.anti_aliasing = true
		if on:
			s.shadow_color = Color(U.GOLD, 0.22)
			s.shadow_size = 10
		draw_style_box(s, r)
		var a := 1.0 if on else 0.55 + 0.3 * _hover
		var ic := r.position + Vector2(size.x * 0.5, 64)
		_icon(ic, 34.0, Color(U.GOLD, a) if on else Color(0.75, 0.75, 0.78, a))
		_map(Rect2(r.position + Vector2(size.x * 0.5 - 30, 118), Vector2(60, 60)), a)
		var f := U.font("title")
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		draw_string(f, r.position + Vector2((size.x - tw) * 0.5, 210), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(U.TEXT, a))
		var lf := U.font("bold")
		var lw := lf.get_string_size(lane, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(lf, r.position + Vector2((size.x - lw) * 0.5, 232), lane, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(U.GOLD_DIM.lightened(0.3), a))
		var lines := U.wrap(desc, size.x - 24.0, 14)
		for i in lines.size():
			var ln := String(lines[i])
			var w := U.font("body").get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(U.font("body"), r.position + Vector2((size.x - w) * 0.5, 262 + i * 19), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(U.TEXT_DIM, a))
		# the check box
		var cb := Rect2(r.position + Vector2(size.x - 32, 10), Vector2(22, 22))
		draw_rect(cb, Color(0, 0, 0, 0.5))
		draw_rect(cb, U.GOLD if on else Color(1, 1, 1, 0.3), false, 1.5)
		if on:
			draw_polyline(PackedVector2Array([cb.position + Vector2(4, 11), cb.position + Vector2(9, 16), cb.position + Vector2(18, 5)]), U.GOLD, 3.0, true)
	func _icon(c: Vector2, s: float, col: Color) -> void:
		match role:
			1:
				# a sword
				draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 14), c + Vector2(5, 14), c + Vector2(5, -s * 0.8), c + Vector2(0, -s), c + Vector2(-5, -s * 0.8)]), col)
				draw_rect(Rect2(c + Vector2(-18, 14), Vector2(36, 7)), col)
				draw_rect(Rect2(c + Vector2(-4, 21), Vector2(8, 16)), col)
				draw_circle(c + Vector2(0, 40), 6, col)
			2:
				# a target
				for k in 3:
					draw_arc(c, s * (1.0 - k * 0.32), 0, TAU, 40, col, 4.0, true)
				draw_circle(c, 6, col)
			3:
				# a shield
				var p := PackedVector2Array()
				for i in 13:
					var t := float(i) / 12.0
					p.append(c + Vector2(lerpf(-s * 0.8, s * 0.8, t), -s * 0.75 - sin(t * PI) * 5.0))
				for i in 13:
					var t := float(i) / 12.0
					var y := lerpf(-s * 0.75, s, t)
					p.append(c + Vector2(s * 0.8 * (1.0 - t * t), y))
				for i in range(12, -1, -1):
					var t := float(i) / 12.0
					var y := lerpf(-s * 0.75, s, t)
					p.append(c + Vector2(-s * 0.8 * (1.0 - t * t), y))
				draw_colored_polygon(p, col)
				draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.6), Color(0.08, 0.1, 0.15), 4.0)
			4:
				# an eye (wards)
				var e := PackedVector2Array()
				for i in 25:
					var a := TAU * float(i) / 24.0
					e.append(c + Vector2(cos(a) * s, sin(a) * s * 0.55 * (1.0 if sin(a) > 0 else 1.0)))
				draw_colored_polygon(e, col)
				draw_circle(c, s * 0.38, Color(0.08, 0.1, 0.15))
				draw_circle(c, s * 0.18, col)
			5:
				# a cross (healing)
				draw_rect(Rect2(c + Vector2(-s * 0.28, -s), Vector2(s * 0.56, s * 2.0)), col)
				draw_rect(Rect2(c + Vector2(-s, -s * 0.28), Vector2(s * 2.0, s * 0.56)), col)
	func _map(r: Rect2, a: float) -> void:
		draw_rect(r, Color(0.05, 0.12, 0.08, 0.9 * a))
		draw_rect(r, Color(1, 1, 1, 0.15 * a), false, 1.0)
		var dim := Color(0.6, 0.55, 0.45, 0.45 * a)
		var lit := Color(U.GOLD, a)
		var m := 10.0
		var bl := r.position + Vector2(m, r.size.y - m)
		var tl := r.position + Vector2(m, m)
		var tr := r.position + Vector2(r.size.x - m, m)
		var br := r.position + Vector2(r.size.x - m, r.size.y - m)
		var lane_i: int = {1: 2, 2: 1, 3: 0, 4: 0, 5: 2}[role]
		var lanes := [[bl, tl, tr], [bl, tr], [bl, br, tr]]
		for i in 3:
			if i != lane_i:
				draw_polyline(PackedVector2Array(lanes[i]), dim, 2.0)
		draw_polyline(PackedVector2Array(lanes[lane_i]), lit, 5.0)
		draw_circle(bl, 4, Color(0.4, 0.75, 1.0, a))
		draw_circle(tr, 4, Color(1.0, 0.36, 0.3, a))

## The big green button (Find Match, Accept): a lit gradient, a glow on hover, a light running across it.
class BigButton extends Control:
	signal pressed
	var text := ""
	var big := false
	var disabled := false:
		set(v):
			disabled = v
			queue_redraw()
	var _hot := false
	var _hover := 0.0
	var _t := 0.0
	var _down := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hot = true)
		mouse_exited.connect(func():
			_hot = false
			_down = false)
	func _process(dt: float) -> void:
		_t += dt
		_hover = move_toward(_hover, 1.0 if _hot and not disabled else 0.0, dt * 5.0)
		if is_visible_in_tree():
			queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if disabled:
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_down = true
			elif _down:
				_down = false
				Options.click()
				pressed.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _down:
			r = r.grow(-3)
		var base := GREEN if not disabled else Color(0.22, 0.26, 0.24)
		var pulse := 0.5 + 0.5 * sin(_t * (5.0 if big else 2.2))
		# glow
		if not disabled:
			for i in 4:
				var g := StyleBoxFlat.new()
				g.bg_color = Color(GREEN_HI, (0.06 + 0.07 * _hover + (0.05 * pulse if big else 0.0)) * (1.0 - i * 0.22))
				g.set_corner_radius_all(14 + i * 6)
				g.anti_aliasing = true
				draw_style_box(g, r.grow(4 + i * 7))
		var s := StyleBoxFlat.new()
		s.bg_color = base.darkened(0.15)
		s.border_color = GREEN_HI.lerp(Color.WHITE, 0.3 * _hover) if not disabled else Color(1, 1, 1, 0.15)
		s.set_border_width_all(2)
		s.set_corner_radius_all(10)
		s.anti_aliasing = true
		draw_style_box(s, r)
		# the lighter top half
		var top := StyleBoxFlat.new()
		top.bg_color = Color(base.lightened(0.18 + 0.12 * _hover), 0.9)
		top.corner_radius_top_left = 9
		top.corner_radius_top_right = 9
		top.anti_aliasing = true
		draw_style_box(top, Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, r.size.y * 0.5 - 2)))
		# the running light
		if not disabled:
			var ph := fmod(_t * 0.45, 1.6) - 0.3
			var x := r.position.x + ph * r.size.x
			for i in 16:
				var a := (1.0 - absf(float(i) - 7.5) / 8.0) * 0.12
				draw_rect(Rect2(x + i * 6.0, r.position.y + 2, 6.0, r.size.y - 4), Color(1, 1, 1, a))
		var f := U.font("title")
		var fs := 46 if big else 38
		var label := text.to_upper()
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while tw > r.size.x - 48.0 and fs > 14:
			fs -= 2
			tw = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := r.position + Vector2((r.size.x - tw) * 0.5, r.size.y * 0.5 + fs * 0.36)
		draw_string(f, p + Vector2(0, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0.12, 0.02, 0.6))
		draw_string(f, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96 if not disabled else 0.5))

## While searching: the time, a striped progress bar, what the search does, nine slots lighting as players are found,
## and Cancel.
class SearchPanel extends Control:
	signal cancel
	var mm: Matchmaker
	var _t := 0.0
	var _btn: Button
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_btn = Button.new()
		_btn.text = "Cancel"
		_btn.theme_type_variation = "RedButton"
		_btn.focus_mode = Control.FOCUS_NONE
		_btn.position = Vector2(size.x - 200, 20)
		_btn.size = Vector2(180, 52)
		_btn.pressed.connect(func():
			Options.click()
			cancel.emit())
		add_child(_btn)
	func _process(dt: float) -> void:
		_t += dt
		if is_visible_in_tree():
			_btn.visible = mm != null and mm.state == "searching"
			queue_redraw()
	func _draw() -> void:
		if mm == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.03, 0.08, 0.05, 0.9)
		s.border_color = Color(GREEN_HI, 0.55)
		s.set_border_width_all(2)
		s.set_corner_radius_all(10)
		s.anti_aliasing = true
		draw_style_box(s, r)
		var f := U.font("title")
		var dots := ".".repeat(1 + int(_t * 2.0) % 3)
		draw_string(f, Vector2(28, 58), "Finding match" + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, GREEN_HI)
		var tf := U.font("bold")
		var tt := "%s   ·   estimated %s" % [RankedNum.mmss(mm.t), RankedNum.mmss(maxf(mm.expect, mm.t))]
		draw_string(tf, Vector2(30, 92), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.TEXT)
		# the bar
		var bar := Rect2(28, 120, size.x - 56, 26)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		var fr := mm.progress()
		var fill := Rect2(bar.position, Vector2(bar.size.x * fr, bar.size.y))
		draw_rect(fill, GREEN)
		var off := fmod(_t * 40.0, 24.0)
		var x := fill.position.x - 24.0 + off
		while x < fill.end.x:
			var p := PackedVector2Array([Vector2(maxf(x, fill.position.x), fill.position.y), Vector2(minf(x + 12, fill.end.x), fill.position.y),
				Vector2(minf(x + 2, fill.end.x), fill.end.y), Vector2(maxf(x - 10, fill.position.x), fill.end.y)])
			if p[1].x > p[0].x and p[2].x > p[3].x:
				draw_colored_polygon(p, Color(1, 1, 1, 0.12))
			x += 24.0
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 5)), Color(1, 1, 1, 0.22))
		draw_rect(bar, Color(GREEN_HI, 0.5), false, 1.0)
		draw_string(tf, Vector2(30, 182), mm.stage if mm.state == "searching" else "Match found", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.TEXT)
		# nine players
		draw_string(U.font("body"), Vector2(30, 222), "Players found", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
		for i in 9:
			var c := Vector2(170 + i * 44, 216)
			var lit := i < mm.found or mm.state != "searching"
			draw_circle(c, 15, Color(0, 0, 0, 0.5))
			draw_arc(c, 15, 0, TAU, 24, GREEN_HI if lit else Color(1, 1, 1, 0.2), 2.0, true)
			if lit:
				draw_circle(c + Vector2(0, -4), 5, GREEN_HI)
				draw_arc(c + Vector2(0, 13), 9, PI + 0.3, TAU - 0.3, 10, GREEN_HI, 3.0, true)
		var roles := "Roles: " + ", ".join(mm.roles.map(func(rr): return String(Ranked.ROLE_NAMES[int(rr) - 1])))
		draw_string(U.font("body"), Vector2(30, 268), roles, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)

## The middle of the match offer: the countdown ring and ten lights (a light per player, green once accepted).
class OfferBox extends Control:
	var mm: Matchmaker
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		for i in 5:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(GREEN_HI, 0.05 * (1.0 - i * 0.18))
			g.set_corner_radius_all(16 + i * 8)
			g.anti_aliasing = true
			draw_style_box(g, r.grow(6 + i * 10))
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.04, 0.06, 0.08, 0.97)
		s.border_color = Color(GREEN_HI, 0.7)
		s.set_border_width_all(2)
		s.set_corner_radius_all(12)
		s.anti_aliasing = true
		draw_style_box(s, r)
		if mm == null or mm.lineup.is_empty():
			return
		# countdown ring
		var c := Vector2(size.x * 0.5, 210)
		var left := mm.accept_left()
		var frac := left / Matchmaker.ACCEPT_SECS
		draw_arc(c, 54, 0, TAU, 64, Color(1, 1, 1, 0.1), 8.0, true)
		var col := GREEN_HI if frac > 0.35 else (U.GOLD if frac > 0.15 else RED)
		if mm.state == "found":
			draw_arc(c, 54, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, col, 8.0, true)
		var n := str(int(ceil(left))) if mm.state == "found" else "Go"
		var f := U.font("title")
		var tw := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		draw_string(f, c + Vector2(-tw * 0.5, 16), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, U.TEXT)
		# ten lights: you first, then the others in their order
		var ids: Array = ["me"]
		for t in 2:
			for p in mm.lineup.teams[t]:
				if String(p.id) != "me":
					ids.append(String(p.id))
		var w := 10 * 52.0
		for i in ids.size():
			var pr := Rect2(size.x * 0.5 - w * 0.5 + i * 52.0 + 6, 290, 40, 18)
			var ok := mm.accepted(String(ids[i])) or mm.state == "ready"
			draw_rect(pr, Color(GREEN_HI, 0.95) if ok else Color(1, 1, 1, 0.1))
			draw_rect(pr, Color(GREEN_HI, 0.8) if ok else Color(1, 1, 1, 0.25), false, 1.0)

## A player on the match offer: picture, name, rank emblem and rank, role and hero; hover for the quick stats.
class MatchCard extends Control:
	signal hover_card(p: Dictionary, at: Rect2, on: bool)
	var p := {}
	var role := 0
	var right := false
	var mm: Matchmaker
	var _av: Avatar
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_av = Avatar.new()
		_av.size = Vector2(72, 72)
		_av.position = Vector2(size.x - 82 if right else 10, 10)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		add_child(_av)
		resized.connect(func(): _av.position = Vector2(size.x - 82 if right else 10, 10))
		mouse_entered.connect(func():
			_hot = true
			hover_card.emit(p, get_global_rect(), true)
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			hover_card.emit(p, get_global_rect(), false)
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) and not p.is_empty():
			PlayerMenu.open(self, String(p.get("id", "")), SocialUi.at(self, e))
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var you := String(p.get("id", "")) == "me"
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.07, 0.09, 0.13, 0.95) if not _hot else Color(0.1, 0.12, 0.18, 0.98)
		s.border_color = U.GOLD if you else (Color(1, 1, 1, 0.3) if _hot else Color(1, 1, 1, 0.1))
		s.set_border_width_all(2 if you else 1)
		s.set_corner_radius_all(8)
		s.anti_aliasing = true
		draw_style_box(s, r)
		var acc := mm != null and (mm.accepted(String(p.get("id", ""))) or mm.state == "ready")
		var stripe := Rect2(0 if not right else size.x - 5, 0, 5, size.y)
		draw_rect(stripe, GREEN_HI if acc else Color(1, 1, 1, 0.12))
		var tier := Ranked.tier_for(p)
		var ic := RankEmblem.icon(tier)
		var x0 := 96.0 if not right else 14.0
		var ex := size.x - 74.0 if not right else 12.0
		if ic:
			draw_texture_rect(ic, Rect2(ex, 14, 62, 62), false)
		var nm := String(p.get("name", ""))
		var f := U.font("bold")
		var tx := x0
		var text_w := size.x - 96.0 - 84.0
		if right:
			tx = size.x - 96.0 - minf(f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, text_w)
		draw_string(f, Vector2(tx, 36), nm, HORIZONTAL_ALIGNMENT_LEFT, text_w, 20, U.GOLD if you else U.TEXT)
		var line := "%s  ·  %s" % [Ranked.rank_label(p), RankedNum.role(role)]
		var lf := U.font("body")
		var lx := x0 if not right else size.x - 96.0 - minf(lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, text_w)
		draw_string(lf, Vector2(lx, 60), line, HORIZONTAL_ALIGNMENT_LEFT, text_w, 15, U.TEXT_DIM)
		var g := int(p.get("wins", 0)) + int(p.get("losses", 0))
		var hn := "%s W - %s L" % [RankedNum.num(int(p.get("wins", 0))), RankedNum.num(int(p.get("losses", 0)))] if g > 0 else "First ranked match"
		var hx := x0 if not right else size.x - 96.0 - minf(lf.get_string_size(hn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, text_w)
		draw_string(lf, Vector2(hx, 80), hn, HORIZONTAL_ALIGNMENT_LEFT, text_w, 15, Color(0.85, 0.8, 0.65))

## A leaderboard row: place (gold, silver, bronze for the top three), picture, name, emblem and rank, MMR, wins and
## losses, win rate, the last five games' MMR. Top ten in Aetherium glow gold; your row is blue.
class BoardRow extends Control:
	signal clicked
	signal hover_card(p: Dictionary, at: Rect2, on: bool)
	var p := {}
	var place := 0
	var compact := false
	var pinned := false
	var hero := ""                         # a hero's ranking: the row shows the player's record on it
	var hero_entry := {}
	var _av: Avatar
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_av = Avatar.new()
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		add_child(_av)
		_place_av()
		resized.connect(_place_av)
		mouse_entered.connect(func():
			_hot = true
			if compact:
				hover_card.emit(p, get_global_rect(), true)
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			if compact:
				hover_card.emit(p, get_global_rect(), false)
			queue_redraw())
	func _draw_hero_row(f: Font, x: float, cy: float, nm: String, you: bool, tier: int) -> void:
		draw_string(f, Vector2(x, cy + 7), nm, HORIZONTAL_ALIGNMENT_LEFT, 420, 20, BLUE if you else U.TEXT)
		var ic := RankEmblem.icon(tier)
		if ic:
			draw_texture_rect(ic, Rect2(640, cy - 26, 52, 52), false)
		draw_string(U.font("bold"), Vector2(702, cy + 7), Ranked.tier_name(tier), HORIZONTAL_ALIGNMENT_LEFT, 260, 18, U.TEXT)
		draw_string(f, Vector2(990, cy + 7), RankedNum.num(int(p.mmr)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, U.GOLD)
		if hero_entry.is_empty():
			draw_string(U.font("body"), Vector2(1150, cy + 7), "No games on this hero yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
			return
		var w := int(hero_entry.w)
		var l := int(hero_entry.l)
		draw_string(U.font("body"), Vector2(1150, cy + 7), "%s - %s" % [RankedNum.num(w), RankedNum.num(l)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, U.TEXT)
		var wr := float(w) / maxf(1.0, float(w + l))
		draw_string(U.font("body"), Vector2(1350, cy + 7), "%.1f%%" % (wr * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			GREEN_HI if wr > 0.52 else (RED if wr < 0.48 else U.TEXT))
		draw_string(f, Vector2(1500, cy + 7), RankedNum.num(int(hero_entry.xp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, U.TEXT)
		var m := Ranked.hero_medal(p, hero)
		HeroBadge.paint(self, Rect2(1600, cy - 28, 56, 56), hero, m)
		draw_string(U.font("bold"), Vector2(1660, cy + 7), String(m.name), HORIZONTAL_ALIGNMENT_LEFT, size.x - 1668, 16, HeroBadge.metal(m))

	func _place_av() -> void:
		var s := size.y - 12.0 if not compact else 38.0
		_av.size = Vector2(s, s)
		_av.position = Vector2(56 if compact else 96, (size.y - s) * 0.5)
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) and not p.is_empty():
			# the player menu (run 2026-10-20)
			PlayerMenu.open(self, String(p.get("id", "")), SocialUi.at(self, e))
			accept_event()
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			clicked.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var you := String(p.get("id", "")) == "me"
		var tier := Ranked.tier_of(int(p.mmr), place)
		var top := tier == Ranked.TIERS - 1
		U.skin(self, "soc_row_you" if you else ("soc_row_gold" if top else ("soc_row_hover" if _hot else "soc_row")), r)
		if _hot and (you or top):
			draw_rect(r.grow(-2), Color(1, 0.9, 0.6, 0.05))
		var cy := size.y * 0.5
		var f := U.font("bold")
		# place
		var pc := [Color(1.0, 0.82, 0.3), Color(0.82, 0.85, 0.9), Color(0.85, 0.55, 0.3)]
		var ptxt := "#%d" % place if place > 0 else "-"
		if place >= 1 and place <= 3:
			draw_circle(Vector2(28 if compact else 44, cy), 17 if compact else 21, Color(pc[place - 1], 0.25))
			draw_arc(Vector2(28 if compact else 44, cy), 17 if compact else 21, 0, TAU, 32, pc[place - 1], 2.0, true)
		var pw := f.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if compact else 19).x
		draw_string(f, Vector2((28 if compact else 44) - pw * 0.5, cy + 7), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if compact else 19,
			pc[place - 1] if place >= 1 and place <= 3 else U.TEXT)
		var ic := RankEmblem.icon(tier)
		var nm := String(p.get("name", ""))
		if compact:
			draw_string(f, Vector2(104, cy - 2), nm, HORIZONTAL_ALIGNMENT_LEFT, 200, 17, BLUE if you else U.TEXT)
			draw_string(U.font("body"), Vector2(104, cy + 17), Ranked.tier_name(tier), HORIZONTAL_ALIGNMENT_LEFT, 200, 13, U.TEXT_DIM)
			if ic:
				draw_texture_rect(ic, Rect2(size.x - 128, cy - 22, 44, 44), false)
			var m := RankedNum.num(int(p.mmr))
			var mw := f.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(f, Vector2(size.x - 12 - mw, cy + 7), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, U.GOLD)
			return
		var x := 96.0 + size.y + 4.0
		var cc := String(p.get("country", ""))
		if cc != "":
			var cr := Rect2(560, cy - 11, 34, 22)
			draw_rect(cr, Color(1, 1, 1, 0.08))
			draw_string(U.font("bold"), Vector2(cr.position.x + 5, cy + 6), cc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.TEXT_DIM)
		if hero != "":
			_draw_hero_row(f, x, cy, nm, you, tier)
			return
		draw_string(f, Vector2(x, cy + 7), nm, HORIZONTAL_ALIGNMENT_LEFT, 420, 20, BLUE if you else U.TEXT)
		if you:
			draw_string(U.font("body"), Vector2(x + minf(f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 420) + 12, cy + 6), "(you)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, BLUE)
		if ic:
			draw_texture_rect(ic, Rect2(640, cy - 26, 52, 52), false)
		draw_string(U.font("bold"), Vector2(702, cy + 7), Ranked.rank_label(p) if top or tier < 10 else Ranked.tier_name(tier),
			HORIZONTAL_ALIGNMENT_LEFT, 260, 18, Color(1.0, 0.86, 0.5) if top else U.TEXT)
		draw_string(f, Vector2(990, cy + 7), RankedNum.num(int(p.mmr)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, U.GOLD)
		draw_string(U.font("body"), Vector2(1150, cy + 7), "%s - %s" % [RankedNum.num(int(p.wins)), RankedNum.num(int(p.losses))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, U.TEXT)
		var g := int(p.wins) + int(p.losses)
		var wr := Ranked.win_rate(p)
		draw_string(U.font("body"), Vector2(1350, cy + 7), "%.1f%%" % (wr * 100.0) if g > 0 else "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			GREEN_HI if wr > 0.52 else (RED if wr < 0.48 and g > 0 else U.TEXT))
		var tr := Ranked.trend(p)
		var ttx := "%+d" % tr if tr != 0 else "0"
		var tc := GREEN_HI if tr > 0 else (RED if tr < 0 else U.TEXT_DIM)
		# the last five results as small squares
		var h: Array = p.get("history", [])
		for i in 5:
			var sq := Rect2(1500 + i * 22, cy - 9, 18, 18)
			if i < h.size():
				var res := String(h[i].get("r", ""))
				draw_rect(sq, Color(GREEN, 0.9) if res == "W" else Color(RED, 0.85))
			else:
				draw_rect(sq, Color(1, 1, 1, 0.08))
		draw_string(f, Vector2(1630, cy + 7), ttx, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tc)

class BoardHead extends Control:
	var hero_mode := false
	func _draw() -> void:
		var f := U.font("bold")
		var c := U.TEXT_DIM
		var cols := [["Place", 18], ["Player", 196], ["Rank", 640], ["MMR", 990], ["Wins - losses", 1150], ["Win rate", 1350],
				["Last five", 1500], ["Change", 1630]]
		if hero_mode:
			cols = [["Place", 18], ["Player", 196], ["Rank", 640], ["MMR", 990], ["On this hero", 1150], ["Win rate", 1350],
				["Hero XP", 1500], ["Medal", 1600]]
		for e in cols:
			draw_string(f, Vector2(float(e[1]), 26), String(e[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(U.GOLD, 0.25), 1.0)

## A past match: won / lost / left, hero, role, K/D/A (yours), the MMR change and when.
class HistoryRow extends Control:
	var e := {}
	var wide := false
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var res := String(e.get("r", "L"))
		var col := GREEN if res == "W" else (RED if res == "L" else Color(0.7, 0.5, 0.2))
		U.skin(self, "soc_row_win" if res == "W" else "soc_row_loss", r)
		var cy := size.y * 0.5
		var f := U.font("bold")
		draw_string(f, Vector2(16, cy + 6), {"W": "Won", "L": "Lost", "A": "Left"}.get(res, res), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col.lightened(0.2))
		var hero := String(e.get("h", ""))
		var tex := U.hero_portrait(hero) if hero != "" else null
		if tex:
			draw_texture_rect(tex, Rect2(70, 5, size.y - 10, size.y - 10), false)
		var hn := String(SimData.unit(hero).get("name", hero)) if hero != "" else ""
		draw_string(U.font("body"), Vector2(70 + size.y, cy - 2), hn, HORIZONTAL_ALIGNMENT_LEFT, 150, 16, U.TEXT)
		draw_string(U.font("body"), Vector2(70 + size.y, cy + 16), RankedNum.role(int(e.get("o", 0))), HORIZONTAL_ALIGNMENT_LEFT, 150, 13, U.TEXT_DIM)
		var d := int(e.get("d", 0))
		var ds := "%+d" % d
		if wide:
			if e.has("k"):
				draw_string(U.font("body"), Vector2(300, cy + 6), "%d / %d / %d" % [int(e.k), int(e.get("x", 0)), int(e.get("a", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT)
			if e.has("len"):
				draw_string(U.font("body"), Vector2(400, cy + 6), RankedNum.mmss(float(e.len)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
			draw_string(U.font("body"), Vector2(470, cy + 6), "%s MMR" % RankedNum.num(int(e.get("m", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
			draw_string(U.font("body"), Vector2(580, cy + 6), RankedNum.ago(int(e.get("t", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		var dw := f.get_string_size(ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2(size.x - 14 - dw, cy + 7), ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GREEN_HI if d > 0 else RED)

## The way to the next rank: a bar from this rank's start to the next one, with both numbers.
class Bar extends Control:
	var mmr := 0
	var tier := 0
	func set_rank(m: int, t: int) -> void:
		mmr = m
		tier = t
		queue_redraw()
	func _draw() -> void:
		var f := U.font("bold")
		var lo := Ranked.tier_floor(mini(tier, Ranked.RANKS.size() - 1))
		var hi := Ranked.next_floor(mini(tier, Ranked.RANKS.size() - 1))
		var txt := ""
		var frac := 1.0
		if hi < 0:
			txt = "Top rank: climb the leaderboard" if tier < Ranked.TIERS - 1 else "Top ten of the leaderboard"
		else:
			frac = clampf(float(mmr - lo) / float(hi - lo), 0.0, 1.0)
			txt = "%s MMR to %s" % [RankedNum.num(hi - mmr), Ranked.tier_name(tier + 1)]
		draw_string(f, Vector2(0, 18), txt, HORIZONTAL_ALIGNMENT_LEFT, size.x, 16, U.TEXT)
		var bar := Rect2(0, 30, size.x, 14)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), U.GOLD)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 4)), Color(1, 1, 1, 0.3))
		draw_rect(bar, Color(U.GOLD, 0.5), false, 1.0)
		if hi > 0:
			draw_string(U.font("body"), Vector2(0, size.y - 1), RankedNum.num(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.TEXT_DIM)
			var hs := RankedNum.num(hi)
			var hw := U.font("body").get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(U.font("body"), Vector2(size.x - hw, size.y - 1), hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.TEXT_DIM)

class StatTile extends Control:
	var title := ""
	var value := ""
	func _draw() -> void:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.1, 0.14, 0.95)
		s.border_color = Color(1, 1, 1, 0.08)
		s.set_border_width_all(1)
		s.set_corner_radius_all(6)
		draw_style_box(s, Rect2(Vector2.ZERO, size))
		draw_string(U.font("body"), Vector2(14, 26), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 14, U.TEXT_DIM)
		draw_string(U.font("bold"), Vector2(14, 62), value, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 26, U.TEXT)

## A behaviour score bar (0..12,000, as Dota's): red, yellow, green.
class Behavior extends Control:
	var score := 10000
	func _draw() -> void:
		var f := U.font("bold")
		draw_string(f, Vector2(0, 16), "Behaviour score", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
		var col := GREEN_HI if score >= 8000 else (U.GOLD if score >= 4500 else RED)
		var v := RankedNum.num(score)
		var vw := f.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2(size.x - vw, 17), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		var bar := Rect2(0, 28, size.x, 10)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(score / 12000.0, 0.0, 1.0), bar.size.y)), col)
		var word := "Good" if score >= 8000 else ("Fair" if score >= 4500 else "Poor: often flames, feeds or leaves")
		draw_string(U.font("body"), Vector2(0, 60), word, HORIZONTAL_ALIGNMENT_LEFT, size.x, 14, col)

## MMR over the last matches: an area under the line, rank borders as dashed lines, the first and last values.
class Graph extends Control:
	var values: Array = []
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.04, 0.05, 0.08, 0.9))
		draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)
		if values.size() < 2:
			draw_string(U.font("body"), Vector2(20, size.y * 0.5), "Play a few matches to see your MMR here.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
			return
		var lo := INF
		var hi := -INF
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		var pad := maxf(40.0, (hi - lo) * 0.15)
		lo -= pad
		hi += pad
		var px := func(i: int) -> float: return 50.0 + (size.x - 70.0) * float(i) / float(values.size() - 1)
		var py := func(v: float) -> float: return size.y - 24.0 - (size.y - 44.0) * (v - lo) / (hi - lo)
		# rank borders in view
		for rk in Ranked.RANKS:
			var m := float(rk[1])
			if m > lo and m < hi:
				var y: float = py.call(m)
				var x := 50.0
				while x < size.x - 20.0:
					draw_line(Vector2(x, y), Vector2(minf(x + 8.0, size.x - 20.0), y), Color(U.GOLD, 0.3), 1.0)
					x += 14.0
				draw_string(U.font("body"), Vector2(size.x - 150, y - 4), String(rk[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(U.GOLD, 0.6))
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(px.call(i), py.call(float(values[i]))))
		var area := pts.duplicate()
		area.append(Vector2(pts[pts.size() - 1].x, size.y - 24.0))
		area.append(Vector2(pts[0].x, size.y - 24.0))
		draw_colored_polygon(area, Color(BLUE, 0.12))
		draw_polyline(pts, BLUE, 2.5, true)
		draw_circle(pts[pts.size() - 1], 5, BLUE)
		var f := U.font("body")
		draw_string(f, Vector2(6, py.call(hi - pad) + 5), RankedNum.num(int(hi - pad)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, U.TEXT_DIM)
		draw_string(f, Vector2(6, py.call(lo + pad) + 5), RankedNum.num(int(lo + pad)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, U.TEXT_DIM)

## The quick stats card shown on hovering a player: picture, name, rank and MMR, wins and losses, behaviour, roles,
## favourite heroes and the last ten games.
class PlayerCard extends Control:
	var p := {}
	var _av: Avatar
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(380, 520)
		_av = Avatar.new()
		_av.position = Vector2(18, 18)
		_av.size = Vector2(84, 84)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_av)
	func show_for(pp: Dictionary) -> void:
		p = pp
		_av.set_spec(p.get("avatar", {"k": "none"}))
		queue_redraw()
	func _draw() -> void:
		if p.is_empty():
			return
		var r := Rect2(Vector2.ZERO, size)
		U.skin(self, "soc_menu", r.grow(10))
		var f := U.font("bold")
		var b := U.font("body")
		draw_string(f, Vector2(116, 42), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 250, 21, U.TEXT)
		var tier := Ranked.tier_for(p)
		var ic := RankEmblem.icon(tier)
		if ic:
			draw_texture_rect(ic, Rect2(112, 50, 52, 52), false)
		draw_string(b, Vector2(168, 72), Ranked.rank_label(p), HORIZONTAL_ALIGNMENT_LEFT, 200, 16, U.GOLD)
		draw_string(b, Vector2(168, 94), "%s MMR" % RankedNum.num(int(p.mmr)), HORIZONTAL_ALIGNMENT_LEFT, 200, 16, U.TEXT)
		var g := int(p.wins) + int(p.losses)
		draw_string(f, Vector2(18, 136), "%s W  -  %s L" % [RankedNum.num(int(p.wins)), RankedNum.num(int(p.losses))], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.TEXT)
		var wr := Ranked.win_rate(p)
		draw_string(b, Vector2(230, 136), "%.1f%% wins" % (wr * 100.0) if g > 0 else "no games", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			GREEN_HI if wr > 0.52 else (RED if wr < 0.48 and g > 0 else U.TEXT_DIM))
		var bs := int(p.get("behavior", 10000))
		var bc := GREEN_HI if bs >= 8000 else (U.GOLD if bs >= 4500 else RED)
		draw_string(b, Vector2(18, 166), "Behaviour score", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
		draw_string(f, Vector2(150, 166), RankedNum.num(bs), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, bc)
		draw_rect(Rect2(220, 156, 140, 8), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(220, 156, 140 * clampf(bs / 12000.0, 0, 1), 8), bc)
		var roles: Array = p.get("roles", [])
		if not roles.is_empty() and bool(p.get("bot", false)):
			draw_string(b, Vector2(18, 192), "Plays " + " and ".join(roles.map(func(rr): return RankedNum.role(int(rr)))), HORIZONTAL_ALIGNMENT_LEFT, 344, 15, U.TEXT)
		draw_string(b, Vector2(18, 220), "Favourite heroes", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		var hx := 18.0
		for h in (p.get("heroes", []) as Array).slice(0, 4):
			var tex := U.hero_portrait(String(h))
			if tex:
				draw_texture_rect(tex, Rect2(hx, 228, 48, 48), false)
				draw_rect(Rect2(hx, 228, 48, 48), Color(1, 1, 1, 0.2), false, 1.0)
			hx += 54.0
		var tops := Ranked.top_heroes(p, 3)
		var bx := 250.0
		for i in mini(2, tops.size()):
			HeroBadge.paint(self, Rect2(bx + i * 62, 220, 58, 58), String(tops[i][0]), tops[i][1])
		if not tops.is_empty():
			draw_string(b, Vector2(250, 214), String(tops[0][1].name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HeroBadge.metal(tops[0][1]))
		draw_string(b, Vector2(18, 300), "Last ten", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		var hist: Array = p.get("history", [])
		for i in 10:
			var sq := Rect2(90 + i * 26, 287, 22, 18)
			if i < hist.size():
				var res := String(hist[i].get("r", ""))
				draw_rect(sq, Color(GREEN, 0.95) if res == "W" else Color(RED, 0.9))
				draw_string(b, sq.position + Vector2(6, 14), "W" if res == "W" else "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.75))
			else:
				draw_rect(sq, Color(1, 1, 1, 0.07))
		# averages and big moments (run 2026-10-20: averages are everything)
		draw_line(Vector2(18, 322), Vector2(size.x - 18, 322), Color(U.GOLD, 0.25), 1.0)
		var av := Career.averages(p)
		draw_string(b, Vector2(18, 346), "Averages", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		draw_string(f, Vector2(100, 346), Career.kda_text(av), HORIZONTAL_ALIGNMENT_LEFT, 150, 16, U.TEXT)
		var farm := "%s LH  ·  %s GPM" % [SocialUi.whole(float(av.get("lh", -1.0))), SocialUi.whole(float(av.get("gpm", -1.0)))]
		draw_string(b, Vector2(240, 346), farm, HORIZONTAL_ALIGNMENT_LEFT, size.x - 258, 14, U.TEXT)
		var mo := Career.moments(p)
		var tx := 18.0
		for t in [["mvp", int(mo.mvp)], ["rampage", int(mo.rp)], ["triple", int(mo.tr)], ["fb", int(mo.fb)]]:
			var ic2 := SocialUi.icon(String(t[0]))
			if ic2:
				draw_texture_rect(ic2, Rect2(tx, 360, 30, 30), false)
			draw_string(f, Vector2(tx + 34, 382), RankedNum.num(int(t[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.GOLD if int(t[1]) > 0 else U.TEXT_DIM)
			tx += 88.0
		if not bool(p.get("bot", false)):
			return
		# who they are and what they make of you (run 2026-10-19 d)
		draw_line(Vector2(18, 408), Vector2(size.x - 18, 408), Color(U.GOLD, 0.25), 1.0)
		var pres := Persona.presence(p, Ranked.now())
		PresenceLine.dot(self, Vector2(26, 430), String(pres.state))
		draw_string(b, Vector2(40, 436), String(pres.label), HORIZONTAL_ALIGNMENT_LEFT, size.x - 58, 15, U.TEXT)
		var tags := Persona.labels(p)
		draw_string(f, Vector2(18, 462), " · ".join(tags), HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 15, U.GOLD)
		draw_string(b, Vector2(18, 486), _with_you_line(p), HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 14, U.TEXT_DIM)
		draw_string(b, Vector2(18, 508), "Right-click for more", HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 12, Color(U.TEXT_DIM, 0.7))
	static func _with_you_line(pp: Dictionary) -> String:
		var y: Dictionary = pp.get("you", {})
		if y.is_empty() or int(y.get("games", 0)) == 0:
			return Persona.status(pp)
		return "%d games with or against you  ·  %s" % [int(y.games), Persona.feeling(float(y.get("rep", 0.0)))]

## Online (green), in a match (blue) or away (grey): a dot and the words.
class PresenceLine extends Control:
	var state := "online"
	var text := ""
	static func dot(c: CanvasItem, at: Vector2, st: String) -> void:
		var col := Color(0.35, 0.9, 0.45) if st == "online" else (Color(0.4, 0.7, 1.0) if st == "match" else Color(0.5, 0.52, 0.56))
		c.draw_circle(at, 6.0, col)
		c.draw_arc(at, 8.0, 0, TAU, 20, Color(col, 0.35), 2.0, true)
	func _draw() -> void:
		var f := U.font("body")
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var x0 := (size.x - tw - 22.0) * 0.5
		dot(self, Vector2(x0 + 6, size.y * 0.5), state)
		draw_string(f, Vector2(x0 + 22, size.y * 0.5 + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT)

## A player in a list (Players): picture with an online dot, name, a line under it, rank or a note at the right; a
## friend request shows Accept and Ignore.
class PersonRow extends Control:
	signal clicked
	signal accept
	signal ignore
	signal open_chat
	signal hover_card(p: Dictionary, at: Rect2, on: bool)
	var p := {}
	var sub := ""
	var right := ""
	var right_col := U.TEXT_DIM
	var request := false
	var chat := false                      # a friend: a Chat button (and the unread count)
	var unread := 0
	var lit := false                       # the friend whose conversation is open
	var _av: Avatar
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_av = Avatar.new()
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		_av.position = Vector2(8, 8)
		_av.size = Vector2(48, 48)
		add_child(_av)
		if chat:
			var cb := Button.new()
			cb.text = "Chat"
			cb.theme_type_variation = "DarkButton"
			if unread > 0:
				cb.add_theme_color_override("font_color", U.GOLD)
			cb.focus_mode = Control.FOCUS_NONE
			cb.size = Vector2(80, 38)
			cb.position = Vector2(size.x - 88, 13)
			cb.pressed.connect(func():
				Options.click()
				open_chat.emit())
			add_child(cb)
			resized.connect(func(): cb.position = Vector2(size.x - 88, 13))
		if request:
			for k in 2:
				var b := Button.new()
				b.text = "Accept" if k == 0 else "Ignore"
				b.theme_type_variation = "DarkButton"
				b.focus_mode = Control.FOCUS_NONE
				b.size = Vector2(92, 38)
				b.position = Vector2(size.x - (196 if k == 0 else 98), 13)
				var sig := accept if k == 0 else ignore
				b.pressed.connect(func():
					Options.click()
					sig.emit())
				add_child(b)
			resized.connect(func():
				var i := 0
				for c in get_children():
					if c is Button:
						(c as Button).position = Vector2(size.x - (196 if i == 0 else 98), 13)
						i += 1)
		mouse_entered.connect(func():
			_hot = true
			hover_card.emit(p, get_global_rect(), true)
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			hover_card.emit(p, get_global_rect(), false)
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) and not p.is_empty():
			# the player menu (run 2026-10-20)
			PlayerMenu.open(self, String(p.get("id", "")), SocialUi.at(self, e))
			accept_event()
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			clicked.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		U.skin(self, "soc_row_gold" if request or lit else ("soc_row_hover" if _hot else "soc_row"), r)
		var st := String(Persona.presence(p, Ranked.now()).state)
		PresenceLine.dot(self, Vector2(52, 52), st)
		var f := U.font("bold")
		var b := U.font("body")
		var cw := 96.0 if chat else 0.0
		var rw := 200.0 if request else (f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0 if right != "" else 0.0)
		draw_string(f, Vector2(68, 28), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 80 - rw - cw, 18, U.TEXT)
		draw_string(b, Vector2(68, 50), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 80 - rw - cw, 14, U.TEXT_DIM)
		if right != "" and not request:
			var tw := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(f, Vector2(size.x - 12 - tw - cw, 38), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, right_col)
		if unread > 0:
			# unread messages: a gold count on the picture's corner
			var c := Vector2(54, 12)
			draw_circle(c, 11, U.GOLD)
			var us := str(mini(unread, 99))
			draw_string(f, c + Vector2(-f.get_string_size(us, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, 5), us, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.1, 0.06, 0.02))

## The friend counts at the top of Friends: friends, online, in a match, offline, requests, each with its dot.
class FriendCounts extends Control:
	var vals: Array = [0, 0, 0, 0, 0]
	func _draw() -> void:
		U.skin(self, "soc_card", Rect2(Vector2.ZERO, size))
		var defs := [["Friends", "", U.GOLD], ["Online", "online", GREEN_HI], ["In a match", "match", BLUE], ["Offline", "offline", U.TEXT_DIM],
			["Requests", "", U.GOLD]]
		var cw := size.x / 5.0
		for i in 5:
			var cx := cw * i + cw * 0.5
			var v := int(vals[i]) if i < vals.size() else 0
			var col: Color = defs[i][2] if v > 0 or i == 0 else U.TEXT_DIM
			SocialUi.text_c(self, str(v), cx, 30, 24, col, "title")
			SocialUi.text_c(self, String(defs[i][0]), cx + (8 if String(defs[i][1]) != "" else 0), 52, 13, U.TEXT_DIM)
			if String(defs[i][1]) != "":
				var tw := U.font("body").get_string_size(String(defs[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				PresenceLine.dot(self, Vector2(cx - tw * 0.5 - 4, 47), String(defs[i][1]))
			if i > 0:
				draw_line(Vector2(cw * i, 12), Vector2(cw * i, size.y - 12), Color(U.GOLD, 0.15), 1.0)

## The head of a conversation: Back, the friend's picture, name, rank and presence; a click on the name opens the
## profile.
class ChatHead extends Control:
	signal back
	signal profile
	var p := {}
	var _av: Avatar
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		var bb := Button.new()
		bb.text = "Back"
		bb.theme_type_variation = "DarkButton"
		bb.focus_mode = Control.FOCUS_NONE
		bb.position = Vector2(0, 14)
		bb.size = Vector2(80, 44)
		bb.pressed.connect(func():
			Options.click()
			back.emit())
		add_child(bb)
		_av = Avatar.new()
		_av.position = Vector2(94, 6)
		_av.size = Vector2(60, 60)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		add_child(_av)
		var hit := Control.new()
		hit.position = Vector2(94, 0)
		hit.size = Vector2(size.x - 94, size.y)
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.tooltip_text = "Open the profile"
		hit.gui_input.connect(func(e: InputEvent):
			if SocialUi.is_left(e):
				Options.click()
				profile.emit()
			elif SocialUi.is_right(e):
				PlayerMenu.open(self, String(p.get("id", "")), SocialUi.at(hit, e)))
		add_child(hit)
	func _draw() -> void:
		var pres := Persona.presence(p, Ranked.now())
		draw_string(U.font("bold"), Vector2(168, 30), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 180, 20, U.TEXT)
		draw_string(U.font("body"), Vector2(168, 52), Ranked.rank_label(p), HORIZONTAL_ALIGNMENT_LEFT, 170, 15, U.GOLD)
		PresenceLine.dot(self, Vector2(346, 47), String(pres.state))
		draw_string(U.font("body"), Vector2(360, 52), String(pres.label), HORIZONTAL_ALIGNMENT_LEFT, size.x - 366, 14, U.TEXT_DIM)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(U.GOLD, 0.2), 1.0)

## A chat message: yours on the right in gold, theirs on the left, with when.
class Bubble extends Control:
	var mine := false
	var text := ""
	var when := ""
	const BW := 400.0
	static func height_for(t: String) -> float:
		var lines := ceili(U.font("body").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x / (BW - 28.0))
		return 34.0 + 21.0 * maxi(1, lines)
	func _draw() -> void:
		var h := size.y - 6.0
		var r := Rect2(size.x - BW if mine else 0.0, 0, BW, h)
		draw_style_box(RankedNum.flat(Color(0.2, 0.15, 0.06, 0.92) if mine else Color(0.08, 0.1, 0.14, 0.92),
			Color(U.GOLD, 0.55) if mine else Color(1, 1, 1, 0.12), 10, 1), r)
		var b := U.font("body")
		draw_multiline_string(b, r.position + Vector2(14, 24), text, HORIZONTAL_ALIGNMENT_LEFT, BW - 28, 16, -1, U.TEXT)
		draw_string(b, Vector2(r.end.x - 14 - b.get_string_size(when, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, h - 6), when,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, U.TEXT_DIM)

## A line of ladder news: the player's picture, what happened, when.
class FeedRow extends Control:
	signal clicked
	var p := {}
	var text := ""
	var when := ""
	var kind := ""
	var _av: Avatar
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_av = Avatar.new()
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		_av.position = Vector2(8, 7)
		_av.size = Vector2(40, 40)
		add_child(_av)
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) and not p.is_empty():
			# the player menu (run 2026-10-20)
			PlayerMenu.open(self, String(p.get("id", "")), SocialUi.at(self, e))
			accept_event()
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			clicked.emit()
			accept_event()
	func _draw() -> void:
		U.skin(self, "soc_row", Rect2(Vector2.ZERO, size))
		var col: Color = {"rank": U.GOLD, "top": U.GOLD, "top10": U.GOLD, "streak": GREEN_HI, "medal": Color(0.75, 0.85, 1.0),
			"friend": BLUE}.get(kind, U.TEXT)
		draw_rect(Rect2(0, 8, 3, size.y - 16), Color(col, 0.8))
		var b := U.font("body")
		var ww := b.get_string_size(when, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(U.font("bold"), Vector2(60, 33), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 84 - ww, 16, col)
		draw_string(b, Vector2(size.x - 12 - ww, 33), when, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.TEXT_DIM)

## The Guilds tab's picture: a banner on a shield, drawn.
class GuildCrest extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(U.GOLD, 0.85)
		var p := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			p.append(c + Vector2(lerpf(-70, 70, t), -80))
		for i in 13:
			var t := float(i) / 12.0
			p.append(c + Vector2(70 * (1.0 - t * t), lerpf(-80, 90, t)))
		for i in range(12, -1, -1):
			var t := float(i) / 12.0
			p.append(c + Vector2(-70 * (1.0 - t * t), lerpf(-80, 90, t)))
		draw_colored_polygon(p, Color(0.1, 0.12, 0.18))
		p.append(p[0])
		draw_polyline(p, col, 4.0, true)
		for k in 3:
			var x := -36.0 + 36.0 * k
			draw_line(c + Vector2(x, -50), c + Vector2(x, 40), col, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(x, -50), c + Vector2(x + 26, -40), c + Vector2(x, -28)]), col)

## One of a player's heroes: its face, name, games, wins - losses and win rate, and the place on its ranking (with the
## Top Player badge for a top ten place).
class HeroRow extends Control:
	var p := {}
	var hero := ""
	var wide := false
	var _t := 0.0
	func _process(dt: float) -> void:
		_t += dt
		if is_visible_in_tree():
			queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		U.skin(self, "soc_row", r)
		var tex := U.hero_portrait(hero)
		if tex:
			draw_texture_rect(tex, Rect2(6, 6, size.y - 12, size.y - 12), false)
		var hs = (p.get("hero_stats", {}) as Dictionary).get(hero, [0, 0, 0])
		var w := int(hs[0])
		var l := int(hs[1])
		var g := w + l
		var x := size.y + 8.0
		var cy := size.y * 0.5
		draw_string(U.font("bold"), Vector2(x, cy - 3), HeroDraft.hero_name(hero), HORIZONTAL_ALIGNMENT_LEFT, 150, 18, U.TEXT)
		var rec := RankedNum.count(g, "match", "matches") if wide else "%d-%d  ·  %.0f%%" % [w, l, float(w) / maxf(1.0, float(g)) * 100.0]
		draw_string(U.font("body"), Vector2(x, cy + 17), rec, HORIZONTAL_ALIGNMENT_LEFT, 150, 14, U.TEXT_DIM)
		var wr := float(w) / maxf(1.0, float(g))
		if wide:
			draw_string(U.font("bold"), Vector2(230, cy - 3), "%s W - %s L" % [RankedNum.num(w), RankedNum.num(l)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT)
			draw_string(U.font("body"), Vector2(230, cy + 17), "%.0f%% wins" % (wr * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				GREEN_HI if wr > 0.52 else (RED if wr < 0.48 else U.TEXT_DIM))
		var m := Ranked.hero_medal(p, hero)
		var bs := size.y - 4.0
		HeroBadge.paint(self, Rect2(size.x - bs - 2, 2, bs, bs), hero, m, _t)
		var col := HeroBadge.metal(m)
		var mx := size.x - bs - (230.0 if wide else 120.0)
		draw_string(U.font("bold"), Vector2(mx, cy - 3), String(m.name), HORIZONTAL_ALIGNMENT_LEFT, (220.0 if wide else 112.0), 15, col)
		# XP to the next star
		var bar := Rect2(mx, cy + 8, (210.0 if wide else 104.0), 7)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(m.frac), bar.size.y)), col)
		if wide:
			var pl := Ranked.hero_place(String(p.get("id", "")), hero)
			draw_string(U.font("body"), Vector2(mx, cy + 30), "%s / %s XP  ·  #%d on %s" % [RankedNum.num(int(m.xp)), RankedNum.num(int(m.next)), pl, HeroDraft.hero_name(hero)],
				HORIZONTAL_ALIGNMENT_LEFT, 230, 12, U.TEXT_DIM)

## A hero's face to choose a hero ranking by.
class HeroPickChip extends Control:
	signal pressed
	var hero := ""
	var selected := false
	var _hot := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = HeroDraft.hero_name(hero)
		mouse_entered.connect(func():
			_hot = true
			queue_redraw())
		mouse_exited.connect(func():
			_hot = false
			queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			pressed.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var tex := U.hero_portrait(hero)
		if tex:
			draw_texture_rect(tex, r, false, Color(1, 1, 1, 1.0 if selected or _hot else 0.6))
		draw_rect(r, U.GOLD if selected else (Color(1, 1, 1, 0.4) if _hot else Color(1, 1, 1, 0.1)), false, 2.0 if selected else 1.0)
