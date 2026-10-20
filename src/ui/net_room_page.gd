extends VBoxContainer
## Multiplayer, in a lobby: the two teams' slots (players with their hero, lane, ping and ready state; bots; open and
## closed slots), your hero, lane and Ready, and the lobby chat. Click an open slot to move there. The leader (crown)
## sets slots (Add Bot, Open, Close, Remove Player) and bots' heroes and skills, fills the lobby with bots, changes
## its name or password, and starts the match once everyone is ready.

const U = preload("res://src/ui/ui_kit.gd")

var menu                                    # net_menu.gd
var net: NetSession
var rows: Array = []                        # 10 SlotRow
var cards: Array = []                       # HeroCard per choice
var counts: Array = []                      # the "n / 5" label of each team
var lane_opt: OptionButton
var ready_btn: Button
var ready_note: Label
var start_btn: Button
var fill_btn: Button
var settings_btn: Button
var status: Label
var chat: NetChat
var hero_name: Label
var hero_title: Label
var hero_kind: Label
var abil_row: HBoxContainer
var _about_for := ""
var _last_room_id := -1

func _ready() -> void:
	net = menu.net
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# the teams
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 22)
	add_child(teams)
	for t in 2:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", menu.frame("panel_main" if t == 0 else "panel_dusk", 56, 26, 56, 32))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		teams.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		p.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		v.add_child(head)
		head.add_child(menu.label(SimConst.TEAM_NAMES[t], 28, U.DAWN if t == 0 else U.DUSK, "title"))
		var side: Label = menu.label("bottom left" if t == 0 else "top right", 15, U.TEXT_DIM)
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(side)
		head.add_child(menu.spacer())
		var cnt: Label = menu.label("", 17, U.TEXT, "bold")
		cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(cnt)
		counts.append(cnt)
		for i in 5:
			var r := SlotRow.new()
			r.page = self
			r.slot = t * 5 + i
			v.add_child(r)
			rows.append(r)
	# your hero and the chat
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 22)
	low.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(low)
	var hs: Array = menu.section("Your Hero")
	hs[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs[0].size_flags_stretch_ratio = 1.45
	low.add_child(hs[0])
	var hv: VBoxContainer = hs[1]
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 26)
	hv.add_child(pick_row)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	pick_row.add_child(grid)
	for id in ["random"] + GameSettings.HEROES:
		var c := HeroCard.new()
		c.hero = id
		c.pressed.connect(func(): _pick(id))
		grid.add_child(c)
		cards.append(c)
	# the chosen hero: name, title, what it is, its abilities
	var about := VBoxContainer.new()
	about.add_theme_constant_override("separation", 2)
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_row.add_child(about)
	hero_name = menu.label("", 30, U.GOLD, "title")
	about.add_child(hero_name)
	hero_title = menu.label("", 17, Color(0.9, 0.86, 0.76), "title")
	about.add_child(hero_title)
	hero_kind = menu.label("", 15, U.TEXT_DIM, "bold")
	about.add_child(hero_kind)
	abil_row = HBoxContainer.new()
	abil_row.add_theme_constant_override("separation", 8)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	about.add_child(gap)
	about.add_child(abil_row)
	var mine := HBoxContainer.new()
	mine.add_theme_constant_override("separation", 14)
	hv.add_child(mine)
	lane_opt = OptionButton.new()
	lane_opt.custom_minimum_size = Vector2(210, 50)
	for n in GameSettings.LANE_NAMES:
		lane_opt.add_item(n)
	lane_opt.item_selected.connect(func(k): net.set_mine("lane", GameSettings.LANES[k]))
	mine.add_child(menu.labelled("Your lane", lane_opt))
	mine.add_child(menu.spacer())
	ready_note = menu.label("", 17, U.TEXT, "bold")
	ready_note.size_flags_vertical = Control.SIZE_SHRINK_END
	ready_note.custom_minimum_size = Vector2(0, 50)
	ready_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mine.add_child(ready_note)
	ready_btn = menu.button("Ready", _toggle_ready, 240, "GoldButton", 58)
	ready_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	mine.add_child(ready_btn)
	var cs: Array = menu.section("Lobby Chat")
	cs[0].custom_minimum_size = Vector2(560, 0)
	low.add_child(cs[0])
	chat = NetChat.new("Say something to the lobby")
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.send = func(t): net.say(t)
	chat.my_name = net.my_name
	cs[1].add_child(chat)
	chat.set_lines(net.room_log)
	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	bottom.add_child(menu.button("Leave Lobby", func(): back(), 190, "DarkButton"))
	status = menu.label("", 17, U.TEXT, "bold")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(status)
	fill_btn = menu.button("Fill with Bots", func(): net.fill_bots(), 190)
	bottom.add_child(fill_btn)
	start_btn = menu.button("Start Match", func(): net.start_match(), 260, "GoldButton", 56)
	bottom.add_child(start_btn)
	refresh()

func back() -> void:
	net.leave_room()

func on_chat(channel: String, nm: String, text: String, system: bool) -> void:
	if channel == "room":
		chat.add_line(nm, text, system)

func refresh() -> void:
	if rows.is_empty() or net.room.is_empty():
		return
	var room: Dictionary = net.room
	if int(room.id) != _last_room_id:
		_last_room_id = int(room.id)
		chat.set_lines(net.room_log)
	var slots: Array = room.slots
	var leader_name := ""
	for s in slots:
		if String(s.kind) == "human" and int(s.peer) == int(room.leader):
			leader_name = String(s.name)
	var lead := net.am_leader()
	var sub := "Led by %s" % leader_name
	if bool(room.get("locked", false)):
		sub += "  ·  needs a password"
	sub += "  ·  on %s" % String(net.server_info.get("name", "the server"))
	var chips := []
	if lead:
		chips.append(["You lead this lobby", U.GOLD, "ui/crown"])
	if not net.is_server():
		var p := net.my_ping()
		chips.append(["Ping %d ms" % p, Color(0.55, 0.95, 0.55) if p < 90 else (Color(1.0, 0.85, 0.35) if p < 170 else Color(1.0, 0.5, 0.45))])
	menu.set_header(String(room.name), sub, chips)
	if lead and settings_btn == null:
		settings_btn = menu.button("Lobby Settings", _settings_dialog, 190, "", 44)
		settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		menu.chips.add_child(settings_btn)
	elif not lead and settings_btn != null:
		settings_btn.queue_free()
		settings_btn = null
	var me := net.my_slot()
	for r in rows:
		r.show_slot(slots[r.slot], room, me, lead)
	for t in 2:
		var n := 0
		var seats := 0
		for i in range(t * 5, t * 5 + 5):
			if String(slots[i].kind) in ["human", "bot"]:
				n += 1
			if String(slots[i].kind) != "closed":
				seats += 1
		counts[t].text = "%d / %d" % [n, seats]
	# my choices
	var mine: Dictionary = slots[me] if me >= 0 else {}
	for c in cards:
		c.chosen = not mine.is_empty() and String(mine.hero) == c.hero
		c.queue_redraw()
	if not mine.is_empty():
		_about(String(mine.hero))
	if not mine.is_empty():
		var li := GameSettings.LANES.find(String(mine.lane))
		if li >= 0 and lane_opt.selected != li and not lane_opt.get_popup().visible:
			lane_opt.select(li)
		var ready := bool(mine.ready)
		ready_btn.text = "Not Ready" if ready else "Ready"
		ready_btn.theme_type_variation = "" if ready else "GoldButton"
		ready_btn.add_theme_font_size_override("font_size", 20 if ready else 24)
		ready_note.text = "You are ready" if ready else "Pick a hero, then Ready"
		ready_note.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if ready else U.TEXT_DIM)
	# the leader's controls and the line that says what happens next
	var problem := NetSession.start_problem(slots)
	var open := slots.filter(func(s): return String(s.kind) == "open").size()
	fill_btn.visible = lead
	fill_btn.disabled = open == 0
	start_btn.visible = lead
	start_btn.disabled = problem != ""
	start_btn.tooltip_text = problem
	if problem != "":
		status.text = problem
		status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	elif lead:
		status.text = "Everyone is ready. Start the match when you like."
		status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		status.text = "Everyone is ready. Waiting for %s to start the match." % leader_name
		status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))

## The chosen hero beside the cards.
func _about(id: String) -> void:
	if id == _about_for:
		return
	_about_for = id
	for c in abil_row.get_children():
		c.queue_free()
	if id == "random":
		hero_name.text = "Random Hero"
		hero_title.text = "Chosen for you when the match starts"
		hero_kind.text = "Any of the %d heroes" % GameSettings.HEROES.size()
		return
	var d := SimData.unit(id)
	hero_name.text = String(d.get("name", id))
	hero_title.text = String(d.get("title", "")).capitalize()
	var attr := {"str": "Strength", "agi": "Agility", "int": "Intelligence"}
	var el: String = SimConst.ELEMENT_NAMES[clampi(int(d.get("element", 0)), 0, SimConst.ELEMENT_NAMES.size() - 1)]
	hero_kind.text = "%s  ·  %s  ·  %s" % [el, "Ranged" if float(d.get("range", 150.0)) > 300.0 else "Melee",
		attr.get(String(d.get("primary", "str")), "Strength")]
	for aid in d.get("abilities", []):
		var ic := IconFrame.make(U.ability_icon(String(aid)), IconBorder.ability_kind(String(aid)), 44)
		var a := SimData.ability(String(aid))
		ic.tooltip_text = "%s\n%s" % [String(a.get("name", aid)), String(a.get("desc", ""))]
		abil_row.add_child(ic)

func _pick(id: String) -> void:
	Options.click()
	net.set_mine("hero", id)
	var look := {}
	if id in GameSettings.HEROES:
		GameSettings.load_hero()
		if GameSettings.custom.has(id):
			look = (GameSettings.looks.get(id, {}) as Dictionary).duplicate(true)
	net.set_mine("look", look)

func _toggle_ready() -> void:
	var me := net.my_slot()
	if me < 0:
		return
	net.set_mine("ready", not bool(net.room.slots[me].ready))

func _settings_dialog() -> void:
	var nm: LineEdit = menu.field("Lobby name", String(net.room.name), false, 32)
	var pw: LineEdit = menu.field("None", "", true, 32)
	menu.dialog("Lobby Settings", [menu.labelled("Lobby name", nm),
		menu.labelled("Password", pw, "empty: anyone may join" if not bool(net.room.get("locked", false)) else "empty: removes the password")],
		[["Cancel", menu.close_dialog], ["Save", func():
			menu.close_dialog()
			net.room_settings(nm.text, pw.text)
			menu.toast("Lobby settings saved"), "GoldButton"]])

## The leader's menu for a slot.
func slot_menu(slot: int, at: Vector2) -> void:
	var s: Dictionary = net.room.slots[slot]
	var pm := PopupMenu.new()
	pm.add_theme_font_size_override("font_size", 17)
	var acts := []
	match String(s.kind):
		"human":
			acts = [["Remove Player", "open"]]
		"bot":
			acts = [["Remove Bot", "open"], ["Close Slot", "closed"]]
		"open":
			acts = [["Add Bot", "bot"], ["Close Slot", "closed"]]
		"closed":
			acts = [["Open Slot", "open"], ["Add Bot", "bot"]]
	for i in acts.size():
		pm.add_item(String(acts[i][0]), i)
	pm.id_pressed.connect(func(i):
		Options.click()
		net.leader_slot(slot, "kind", acts[i][1])
		pm.queue_free())
	pm.popup_hide.connect(func(): pm.queue_free.call_deferred())
	add_child(pm)
	pm.position = Vector2i(at)
	pm.popup()

# ---- A slot ---------------------------------------------------------------------------------------------------------

class SlotRow extends PanelContainer:
	var page
	var slot := 0
	var data := {}
	var portrait: TextureRect
	var name_l: Label
	var sub_l: Label
	var crown: TextureRect
	var hero_opt: OptionButton
	var skill_opt: OptionButton
	var pill: PanelContainer
	var pill_l: Label
	var ping_l: Label
	var more: Button
	var _style := ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 74)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		add_child(row)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", U.box("slot_item", 3))
		frame.custom_minimum_size = Vector2(58, 58)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(frame)
		portrait = TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = Vector2(52, 52)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(portrait)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(names)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(top)
		crown = TextureRect.new()
		crown.texture = U.icon("ui/crown")
		crown.custom_minimum_size = Vector2(20, 20)
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.modulate = U.GOLD
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crown.tooltip_text = "Leads the lobby"
		top.add_child(crown)
		name_l = _label(20, U.TEXT, "bold")
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_l)
		sub_l = _label(14, U.TEXT_DIM, "body")
		sub_l.clip_text = true
		sub_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(sub_l)
		hero_opt = OptionButton.new()
		hero_opt.custom_minimum_size = Vector2(160, 44)
		hero_opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hero_opt.add_item("Random")
		for id in GameSettings.HEROES:
			hero_opt.add_item(String(SimData.unit(id).name))
		hero_opt.item_selected.connect(func(k):
			page.net.leader_slot(slot, "hero", "random" if k == 0 else GameSettings.HEROES[k - 1]))
		row.add_child(hero_opt)
		skill_opt = OptionButton.new()
		skill_opt.custom_minimum_size = Vector2(120, 44)
		skill_opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for n in GameSettings.SKILL_NAMES:
			skill_opt.add_item(n)
		skill_opt.item_selected.connect(func(k): page.net.leader_slot(slot, "skill", GameSettings.SKILLS[k]))
		row.add_child(skill_opt)
		ping_l = _label(15, U.TEXT_DIM, "bold")
		ping_l.custom_minimum_size = Vector2(66, 0)
		ping_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ping_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ping_l)
		pill = PanelContainer.new()
		pill.custom_minimum_size = Vector2(118, 34)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pill)
		pill_l = _label(15, U.TEXT, "bold")
		pill_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_child(pill_l)
		more = Button.new()
		more.text = "Slot"
		more.theme_type_variation = "DarkButton"
		more.add_theme_font_size_override("font_size", 15)
		more.custom_minimum_size = Vector2(70, 44)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		more.tooltip_text = "Slot: add a bot, open, close, remove"
		more.focus_mode = Control.FOCUS_NONE
		more.pressed.connect(func():
			Options.click()
			page.slot_menu(slot, more.get_screen_position() + Vector2(0, more.size.y)))
		row.add_child(more)
		gui_input.connect(_click)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _label(size: int, col: Color, kind: String) -> Label:
		var l := Label.new()
		l.add_theme_font_override("font", U.font(kind))
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func _set_style(name: String, col := Color.WHITE) -> void:
		var key := name + col.to_html()
		if key == _style:
			return
		_style = key
		add_theme_stylebox_override("panel", U.box(name, 14, col))

	func show_slot(s: Dictionary, room: Dictionary, me: int, lead: bool) -> void:
		data = s
		var kind := String(s.kind)
		var mine := slot == me
		var team_col: Color = U.DAWN if slot < 5 else U.DUSK
		crown.visible = kind == "human" and int(s.peer) == int(room.leader)
		hero_opt.visible = lead and kind == "bot"
		skill_opt.visible = lead and kind == "bot"
		more.visible = lead and not mine
		ping_l.visible = kind == "human"
		pill.visible = kind == "human"
		var hero := String(s.hero)
		var hname := "Random hero" if hero == "random" else String(SimData.unit(hero).get("name", hero))
		portrait.texture = U.hero_portrait(hero) if kind in ["human", "bot"] and hero != "random" else null
		portrait.modulate = Color.WHITE
		match kind:
			"human":
				name_l.text = String(s.name) + ("  (you)" if mine else "")
				name_l.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0) if mine else U.TEXT)
				var lane := String(s.lane)
				var li := GameSettings.LANES.find(lane)
				sub_l.text = hname + "  ·  " + (GameSettings.LANE_NAMES[li] if li >= 0 else "Any lane")
				var ready := bool(s.ready)
				pill_l.text = "Ready" if ready else "Not ready"
				pill_l.add_theme_color_override("font_color", Color(0.5, 1.0, 0.45) if ready else U.TEXT_DIM)
				pill.add_theme_stylebox_override("panel", U.box("btn_dark_hover" if ready else "btn_dark_normal", 8,
					Color(0.8, 1.25, 0.8) if ready else Color(1, 1, 1, 0.8)))
				var pg := int((room.get("pings", {}) as Dictionary).get(int(s.peer), 0))
				ping_l.text = "%d ms" % pg if pg > 0 else ""
				ping_l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if pg < 90 else (Color(1.0, 0.85, 0.35) if pg < 170 else Color(1.0, 0.5, 0.45)))
				_set_style("btn_dark_hover" if mine else "btn_dark_normal", Color(1.2, 1.12, 0.95) if mine else Color.WHITE)
				tooltip_text = ""
			"bot":
				name_l.text = String(s.name)
				name_l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82))
				sub_l.text = hname + "  ·  bot, " + GameSettings.SKILL_NAMES[maxi(0, GameSettings.SKILLS.find(String(s.skill)))]
				var hi := 0 if hero == "random" else GameSettings.HEROES.find(hero) + 1
				if hero_opt.selected != hi and not hero_opt.get_popup().visible:
					hero_opt.select(hi)
				var si := GameSettings.SKILLS.find(String(s.skill))
				if skill_opt.selected != si and not skill_opt.get_popup().visible:
					skill_opt.select(si)
				_set_style("btn_dark_normal", Color(0.85, 0.85, 0.85))
				tooltip_text = ""
			"open":
				name_l.text = "Open"
				name_l.add_theme_color_override("font_color", Color(team_col, 0.85))
				sub_l.text = "Click to move here" if me >= 0 and room.state == "lobby" else "Waiting for a player"
				_set_style("btn_dark_normal", Color(1, 1, 1, 0.7))
				tooltip_text = "Click to take this slot" if me >= 0 else ""
			"closed":
				name_l.text = "Closed"
				name_l.add_theme_color_override("font_color", Color(0.45, 0.45, 0.47))
				sub_l.text = "Nobody plays here"
				_set_style("btn_dark_disabled", Color(1, 1, 1, 0.6))
				tooltip_text = ""
		queue_redraw()

	func _draw() -> void:
		if String(data.get("kind", "")) == "open" and get_global_rect().has_point(get_global_mouse_position()):
			draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(1.0, 0.85, 0.45, 0.08))
		if String(data.get("kind", "")) == "human" and slot == page.net.my_slot():
			draw_rect(Rect2(Vector2(4, 10), Vector2(3, size.y - 20)), U.GOLD)
		if portrait.texture == null and String(data.get("kind", "")) in ["human", "bot"]:
			# a random hero: a question mark in the portrait's frame
			var c := portrait.get_global_rect().get_center() - get_global_rect().position
			U.text_c(self, "?", c + Vector2(0, 12), 34, U.GOLD, "title")

	func _click(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if String(data.get("kind", "")) == "open":
				Options.click()
				page.net.move_to(slot)
		elif e is InputEventMouseMotion:
			queue_redraw()

# ---- A hero to choose ---------------------------------------------------------------------------------------------

class HeroCard extends Control:
	signal pressed
	var hero := "random"
	var chosen := false

	func _init() -> void:
		custom_minimum_size = Vector2(118, 150)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_mode = Control.FOCUS_NONE

	func _ready() -> void:
		tooltip_text = "Any hero, chosen when the match starts" if hero == "random" else \
			"%s, %s" % [SimData.unit(hero).get("name", hero), SimData.unit(hero).get("title", "")]

	func _draw() -> void:
		var hover := get_global_rect().has_point(get_global_mouse_position())
		var r := Rect2(Vector2.ZERO, size)
		if chosen:
			U.art_rect(self, "glow_gold", r.grow(18), Color(1, 1, 1, 0.55))
		var pr := Rect2(8, 8, size.x - 16, size.x - 16)
		draw_rect(pr, Color(0.03, 0.035, 0.05))
		var t: Texture2D = U.hero_portrait(hero) if hero != "random" else null
		if t:
			draw_texture_rect(t, pr, false, Color.WHITE if chosen or hover else Color(0.78, 0.78, 0.8))
		else:
			U.text_c(self, "?", pr.get_center() + Vector2(0, 18), 54, U.GOLD, "title")
		U.skin(self, "slot_ability", pr.grow(5), Color(1.35, 1.25, 1.0) if chosen else (Color(1.15, 1.1, 1.0) if hover else Color.WHITE), false)
		var nm := "Random" if hero == "random" else String(SimData.unit(hero).get("name", hero))
		var f := U.font("bold")
		var sz := 16
		while sz > 12 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > size.x - 6:
			sz -= 1
		U.text_c(self, nm, Vector2(size.x * 0.5, size.y - 10), sz, U.GOLD if chosen else (U.TEXT if hover else Color(0.8, 0.8, 0.8)), "bold")

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
