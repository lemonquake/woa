extends Control
## Game Setup (after Hero Select's Play): who plays the match. Two teams of five slots; each slot is You, Bot or Empty,
## with a hero (or Random; bots may play the same hero as anyone else). Bots get a skill level (Dota's Passive, Easy,
## Medium, Hard, Unfair), a role if you want one (else the team shares roles out) and a name you can change; for yourself you can say which lane you will take, and your bots
## leave it to you (they also notice where you actually go). Presets fill the usual line-ups. Start goes on to the
## Hotkeys screen and the match. Saved in user://setup.json (GameSettings).

const U = preload("res://src/ui/ui_kit.gd")
const HERO_SELECT := "res://src/ui/hero_select.tscn"
const HOTKEYS := "res://src/ui/hotkeys_screen.tscn"

var _rows := [[], []]                      # per team: [{kind, hero, skill, lane, name, icon}]
var _error: Label
var _learn: Label
var _capture_path := ""
var _frames := 0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	GameSettings.load_setup()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_path = a.substr(10)
	var bg := TextureRect.new()
	bg.texture = U.skin_tex("backdrop")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.32, 0.22, 0.08, 0.5))
	gr.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 0.9)
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	root.add_child(_label("Game Setup", 44, U.GOLD, "title"))
	var sub := _label("Choose who plays on each team: you, a bot, or nobody. Bots can play the same hero as anyone else. Pick the lane you want and your bots will leave it to you.", 17, U.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(sub)

	# presets and the skill for every bot at once
	var pre := HBoxContainer.new()
	pre.add_theme_constant_override("separation", 10)
	root.add_child(pre)
	pre.add_child(_label("Presets", 18, U.TEXT, "bold"))
	pre.add_child(_button("5 vs 5", func(): _preset("5v5"), 120))
	pre.add_child(_button("1 vs 1 mid", func(): _preset("1v1"), 140))
	pre.add_child(_button("Fill with bots", func(): _preset("fill"), 160))
	pre.add_child(_button("Remove bots", func(): _preset("clear"), 160))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(30, 0)
	pre.add_child(gap)
	pre.add_child(_label("All bots", 18, U.TEXT, "bold"))
	var all := OptionButton.new()
	all.custom_minimum_size = Vector2(150, 42)
	all.add_item("Set skill")
	for n in GameSettings.SKILL_NAMES:
		all.add_item(n)
	all.item_selected.connect(func(i):
		if i > 0:
			for t in 2:
				for s in GameSettings.setup.teams[t]:
					s.skill = GameSettings.SKILLS[i - 1]
			_changed()
		all.select(0))
	pre.add_child(all)

	# the two teams
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 24)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(teams)
	for t in 2:
		teams.add_child(_team_panel(t))

	_error = _label("", 18, U.DUSK, "bold")
	root.add_child(_error)
	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	root.add_child(bottom)
	bottom.add_child(_button("Back", func():
		Options.click()
		GameSettings.save_setup()
		get_tree().change_scene_to_file(HERO_SELECT), 160))
	_learn = _label("", 16, U.TEXT_DIM)
	_learn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_learn)
	bottom.add_child(_button("Options", func():
		Options.click()
		var op := OptionsPanel.new()
		add_child(op)
		op.tree_exited.connect(_refresh), 140))
	var start := _button("Start", _start, 260)
	start.theme_type_variation = "GoldButton"
	start.add_theme_font_size_override("font_size", 26)
	start.custom_minimum_size = Vector2(260, 60)
	bottom.add_child(start)
	_refresh()
	LoadingScreen.close(get_tree())

func _label(text: String, size: int, col: Color, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _button(text: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 42)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b

func _team_panel(t: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var head := HBoxContainer.new()
	var nm := _label(SimConst.TEAM_NAMES[t], 28, U.DAWN if t == 0 else U.DUSK, "title")
	head.add_child(nm)
	var side := _label("  (bottom left)" if t == 0 else "  (top right)", 16, U.TEXT_DIM)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(side)
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	for c in [["", 56], ["Player", 110], ["Hero", 190], ["Skill or lane", 140], ["Role", 160], ["Name", 140]]:
		var l := _label(c[0], 14, U.TEXT_DIM, "bold")
		l.custom_minimum_size = Vector2(c[1], 0)
		cols.add_child(l)
	v.add_child(cols)
	for i in 5:
		v.add_child(_slot_row(t, i))
	return p

func _slot_row(t: int, i: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 76)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var kind := OptionButton.new()
	kind.custom_minimum_size = Vector2(110, 52)
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in GameSettings.KIND_NAMES:
		kind.add_item(n)
	kind.item_selected.connect(func(k): _set_kind(t, i, GameSettings.KINDS[k]))
	row.add_child(kind)
	var hero := OptionButton.new()
	hero.custom_minimum_size = Vector2(190, 52)
	hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero.add_item("Random")
	for id in GameSettings.HEROES:
		hero.add_item(String(SimData.unit(id).name))
	hero.item_selected.connect(func(k): _set_hero(t, i, "random" if k == 0 else GameSettings.HEROES[k - 1]))
	row.add_child(hero)
	var skill := OptionButton.new()
	skill.custom_minimum_size = Vector2(140, 52)
	skill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in GameSettings.SKILL_NAMES:
		skill.add_item(n)
	skill.item_selected.connect(func(k):
		GameSettings.setup.teams[t][i].skill = GameSettings.SKILLS[k]
		_changed())
	row.add_child(skill)
	var lane := OptionButton.new()
	lane.custom_minimum_size = Vector2(140, 52)
	lane.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in GameSettings.LANE_NAMES:
		lane.add_item(n)
	lane.item_selected.connect(func(k):
		GameSettings.setup.teams[t][i].lane = GameSettings.LANES[k]
		_changed())
	row.add_child(lane)
	var name := LineEdit.new()
	var role := OptionButton.new()
	role.custom_minimum_size = Vector2(160, 52)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in GameSettings.ROLE_NAMES:
		role.add_item(n)
	role.item_selected.connect(func(k):
		GameSettings.setup.teams[t][i].role = GameSettings.ROLES[k]
		_changed())
	row.add_child(role)
	name.custom_minimum_size = Vector2(140, 52)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.max_length = 20
	name.text_changed.connect(func(s):
		GameSettings.setup.teams[t][i].name = s
		GameSettings.save_setup())
	row.add_child(name)
	for ctl in [kind, hero, skill, lane, role, name]:
		ctl.add_theme_font_size_override("font_size", 17)
	_rows[t].append({"kind": kind, "hero": hero, "skill": skill, "lane": lane, "role": role, "name": name, "icon": icon})
	return row

func _set_kind(t: int, i: int, kind: String) -> void:
	var s: Dictionary = GameSettings.setup.teams[t][i]
	if kind == "you":
		# only one of you: the old slot becomes a bot
		for tt in 2:
			for o in GameSettings.setup.teams[tt]:
				if o.kind == "you":
					o.kind = "bot"
					o.hero = "random"
					if String(o.name) == "":
						o.name = _free_name()
		s.hero = GameSettings.selected
	elif s.kind == "you":
		_error.text = "Choose another slot as You first."
		_refresh()
		return
	if kind == "bot" and String(s.name) == "":
		s.name = _free_name()
	s.kind = kind
	_changed()

func _set_hero(t: int, i: int, id: String) -> void:
	var s: Dictionary = GameSettings.setup.teams[t][i]
	if s.kind == "you":
		if id == "random":
			id = GameSettings.HEROES[randi() % GameSettings.HEROES.size()]
		GameSettings.select(id)
		GameSettings.save()
	s.hero = id
	_changed()

func _free_name() -> String:
	var used := {}
	for t in 2:
		for o in GameSettings.setup.teams[t]:
			used[String(o.name)] = true
	for n in GameSettings.BOT_NAMES:
		if not used.has(n):
			return n
	return "Bot"

func _preset(which: String) -> void:
	var you := GameSettings.your_slot()
	match which:
		"5v5":
			GameSettings.setup = GameSettings.default_setup()
			# keep you where you were
			if you != [0, 0]:
				GameSettings.setup.teams[0][0].kind = "bot"
				GameSettings.setup.teams[0][0].hero = "random"
				GameSettings.setup.teams[0][0].name = _free_name()
				GameSettings.setup.teams[you[0]][you[1]].kind = "you"
				GameSettings.setup.teams[you[0]][you[1]].hero = GameSettings.selected
		"1v1":
			GameSettings.setup = GameSettings.duel_setup()
		"fill":
			for t in 2:
				for o in GameSettings.setup.teams[t]:
					if o.kind == "empty":
						o.kind = "bot"
						o.name = _free_name()
		"clear":
			for t in 2:
				for o in GameSettings.setup.teams[t]:
					if o.kind == "bot":
						o.kind = "empty"
	_changed()

func _changed() -> void:
	_error.text = ""
	GameSettings.save_setup()
	_refresh()

func _refresh() -> void:
	for t in 2:
		for i in 5:
			var s: Dictionary = GameSettings.setup.teams[t][i]
			var r: Dictionary = _rows[t][i]
			var k := GameSettings.KINDS.find(String(s.kind))
			(r.kind as OptionButton).select(k)
			var hid := String(s.hero)
			(r.hero as OptionButton).select(0 if hid == "random" else GameSettings.HEROES.find(hid) + 1)
			(r.skill as OptionButton).select(maxi(0, GameSettings.SKILLS.find(String(s.skill))))
			(r.lane as OptionButton).select(maxi(0, GameSettings.LANES.find(String(s.lane))))
			(r.role as OptionButton).select(maxi(0, GameSettings.ROLES.find(String(s.get("role", "")))))
			(r.role as OptionButton).visible = s.kind == "bot"
			var nm := r.name as LineEdit
			if nm.text != String(s.name):
				nm.text = String(s.name)
			var empty: bool = s.kind == "empty"
			(r.hero as OptionButton).disabled = empty
			(r.hero as OptionButton).modulate.a = 0.35 if empty else 1.0
			(r.skill as OptionButton).visible = s.kind == "bot"
			(r.lane as OptionButton).visible = s.kind == "you"
			nm.visible = s.kind == "bot"
			nm.editable = s.kind == "bot"
			var icon := r.icon as TextureRect
			var ult := "" if hid == "random" or empty else String((SimData.unit(hid).abilities as Array)[3])
			icon.texture = U.ability_icon(ult) if ult != "" else null
			(r.kind as OptionButton).add_theme_color_override("font_color", Color(0.55, 1.0, 0.55) if s.kind == "you" else (U.TEXT_DIM if empty else U.TEXT))
	var counts := [0, 0]
	for t in 2:
		for s in GameSettings.setup.teams[t]:
			if s.kind != "empty":
				counts[t] += 1
	_learn.text = "%d vs %d  ·  Bots learn from games: %s (Options > Game)" % [counts[0], counts[1],
		"on" if bool(Options.get_value("bots_learn")) else "off"]

func _start() -> void:
	for t in 2:
		var n := 0
		for s in GameSettings.setup.teams[t]:
			if s.kind != "empty":
				n += 1
		if n == 0:
			_error.text = "Each team needs at least one hero."
			return
	Options.click()
	GameSettings.save_setup()
	GameSettings.save()
	get_tree().change_scene_to_file(HOTKEYS)

func _process(_dt: float) -> void:
	if _capture_path == "":
		return
	_frames += 1
	if _frames == 2 and OS.get_cmdline_user_args().has("--4k"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
	if _frames == 30:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_capture_path)
		get_tree().quit()
