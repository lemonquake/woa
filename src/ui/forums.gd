extends Control
## The Forums screen (run 2026-10-19 e): Main Menu > Forums. Threads on the left (Hot or New, a section filter, votes,
## who posted at which rank, how long ago, how many replies), the open thread on the right (the post, every reply with
## the writer's picture, name and rank, votes, Reply), a box to answer at the bottom ("Replying to ..." when you answer
## someone), "... is typing" while answers to you are on the way, and New post (title, section, text). Replies to you
## come in while the page is open (Forum.resolve every second; ForumWriter writes them with the language model when
## Online bot chat is on).
## Automation: --capture=path [--thread=n | --open=first] [--post=text] [--wait=seconds] [--4k] [--frames=n].

const U = preload("res://src/ui/ui_kit.gd")
const MAIN_MENU := "res://src/ui/main_menu.tscn"
const W := 1920.0
const H := 1080.0
const GLASS := Color(0.055, 0.07, 0.105, 0.92)
const RIM := Color(0.55, 0.43, 0.2, 0.6)
const BLUE := Color(0.4, 0.72, 1.0)

var _frame: Control
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _view: VBoxContainer
var _view_scroll: ScrollContainer
var _reply_box: LineEdit
var _reply_to_lbl: Label
var _typing: Label
var _footer: Label
var _tag := ""
var _sort := "hot"
var _open := -1                             # the thread shown
var _reply_to := -1                         # the reply you answer (-1: the thread)
var _tab_btns := {}
var _sort_btns := {}
var _dialog_dim: ColorRect
var _dialog: Control
var _d_title: LineEdit
var _d_body: TextEdit
var _d_tag: OptionButton
var _writer: ForumWriter
var _tick := 0.0
var _capture := ""
var _cap_frames := 40
var _frames := 0
var _wait := 0.0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ranked.load_data()
	Ranked.catch_up()
	Forum.load_data()
	Forum.catch_up()
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("4k"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(3840, 2160))
	_capture = String(args.get("capture", ""))
	_cap_frames = int(args.get("frames", "40"))
	_wait = float(args.get("wait", "0"))
	_build()
	resized.connect(_layout)
	_layout()
	_writer = ForumWriter.make(self)
	if _writer != null:
		var n := 0
		for th in Forum.listed("new"):
			if n >= 2:
				break
			if String(th.a) != "me" and int(th.seen) == 0 and not th.has("llm"):
				_writer.want_thread(th)
				n += 1
	_fill_list()
	if args.has("post"):
		var th := Forum.post("Need tips", String(args.post), "Help")
		_open_thread(int(th.id))
	elif args.has("thread"):
		_open_thread(int(args.thread))
	elif args.has("open") or not Forum.threads().is_empty():
		var l := Forum.listed(_sort, _tag)
		if not l.is_empty():
			_open_thread(int(l[0].id))
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

# ---- Building -------------------------------------------------------------------------------------------------------------

func _label(text: String, px: int, col := U.TEXT, kind := "body", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

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

func _panel(r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", U.box("soc_panel"))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_frame.add_child(p)
	return p

func _build() -> void:
	SocialUi.backdrop(self)
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	# top bar
	var top := TextureRect.new()
	top.texture = U.skin_tex("soc_topbar")
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.size = Vector2(W, 96)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(top)
	var back := _button("Back", func(): Options.go(get_tree(), MAIN_MENU), "DarkButton", Vector2(110, 46))
	back.position = Vector2(30, 23)
	_frame.add_child(back)
	var title := _label("Forums", 38, U.GOLD, "title")
	title.position = Vector2(166, 18)
	_frame.add_child(title)
	var x := 360.0
	for t in [""] + Forum.TAGS:
		var tb := _button("All" if t == "" else String(t), func(): _set_tag(String(t)), "DarkButton", Vector2(0, 42))
		tb.toggle_mode = true
		tb.position = Vector2(x, 25)
		tb.add_theme_font_size_override("font_size", 16)
		_frame.add_child(tb)
		tb.size = Vector2(tb.get_minimum_size().x + 18, 42)
		_tab_btns[String(t)] = tb
		x += tb.size.x + 6.0
	for s in [["hot", "Hot"], ["new", "New"]]:
		var sb := _button(String(s[1]), func(): _set_sort(String(s[0])), "DarkButton", Vector2(70, 42))
		sb.toggle_mode = true
		sb.position = Vector2(x + 18, 25)
		sb.add_theme_font_size_override("font_size", 16)
		_frame.add_child(sb)
		_sort_btns[String(s[0])] = sb
		x += 76.0
	var np := _button("New post", _new_post, "", Vector2(170, 48))
	np.position = Vector2(W - 200, 22)
	np.add_theme_font_size_override("font_size", 19)
	_frame.add_child(np)
	# the list
	var lp := _panel(Rect2(30, 108, 780, 918))
	_list_scroll = ScrollContainer.new()
	_list_scroll.position = Vector2(18, 20)
	_list_scroll.size = Vector2(746, 880)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(730, 0)
	_list.add_theme_constant_override("separation", 6)
	_list_scroll.add_child(_list)
	# the thread
	var vp := _panel(Rect2(826, 108, 1064, 918))
	_view_scroll = ScrollContainer.new()
	_view_scroll.position = Vector2(28, 26)
	_view_scroll.size = Vector2(1012, 756)
	_view_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vp.add_child(_view_scroll)
	_view = VBoxContainer.new()
	_view.custom_minimum_size = Vector2(994, 0)
	_view.add_theme_constant_override("separation", 10)
	_view_scroll.add_child(_view)
	_typing = _label("", 15, U.TEXT_DIM, "body")
	_typing.position = Vector2(20, 790)
	vp.add_child(_typing)
	_reply_to_lbl = _label("", 15, U.GOLD, "bold")
	_reply_to_lbl.position = Vector2(20, 812)
	vp.add_child(_reply_to_lbl)
	_reply_box = LineEdit.new()
	_reply_box.placeholder_text = "Write a reply (Enter to post)"
	_reply_box.max_length = 500
	_reply_box.position = Vector2(16, 846)
	_reply_box.size = Vector2(880, 52)
	_reply_box.add_theme_font_size_override("font_size", 18)
	_reply_box.text_submitted.connect(func(_t): _send_reply())
	vp.add_child(_reply_box)
	var post := _button("Reply", _send_reply, "", Vector2(140, 52))
	post.position = Vector2(908, 846)
	vp.add_child(post)
	_footer = _label("", 15, U.TEXT_DIM, "body")
	_footer.position = Vector2(34, 1040)
	_frame.add_child(_footer)
	_build_dialog()
	_set_tag("", false)
	_set_sort("hot", false)

func _build_dialog() -> void:
	# the dimmed screen behind the dialog takes the clicks; a click on it puts the dialog away (the draft stays for
	# next time; Cancel throws it away)
	_dialog_dim = ColorRect.new()
	_dialog_dim.color = Color(0, 0, 0, 0.5)
	_dialog_dim.size = Vector2(W, H)
	_dialog_dim.visible = false
	_dialog_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_child(_dialog_dim)
	_dialog_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_hide_dialog())
	_dialog = Panel.new()
	_dialog.add_theme_stylebox_override("panel", U.box("soc_panel"))
	_dialog.position = Vector2(W * 0.5 - 460, 200)
	_dialog.size = Vector2(920, 600)
	_dialog.visible = false
	_frame.add_child(_dialog)
	var t := _label("New post", 30, U.GOLD, "title")
	t.position = Vector2(30, 22)
	_dialog.add_child(t)
	var l1 := _label("Title", 16, U.TEXT_DIM, "bold")
	l1.position = Vector2(30, 84)
	_dialog.add_child(l1)
	_d_title = LineEdit.new()
	_d_title.max_length = 90
	_d_title.position = Vector2(30, 108)
	_d_title.size = Vector2(620, 48)
	_d_title.add_theme_font_size_override("font_size", 18)
	_dialog.add_child(_d_title)
	_d_tag = OptionButton.new()
	for tg in Forum.TAGS:
		_d_tag.add_item(String(tg))
	_d_tag.position = Vector2(670, 108)
	_d_tag.size = Vector2(220, 48)
	_dialog.add_child(_d_tag)
	var l2 := _label("Text", 16, U.TEXT_DIM, "bold")
	l2.position = Vector2(30, 172)
	_dialog.add_child(l2)
	_d_body = TextEdit.new()
	_d_body.position = Vector2(30, 196)
	_d_body.size = Vector2(860, 300)
	_d_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_d_body.add_theme_font_size_override("font_size", 18)
	_dialog.add_child(_d_body)
	var ok := _button("Post", _post_thread, "", Vector2(160, 50))
	ok.position = Vector2(730, 520)
	_dialog.add_child(ok)
	var cancel := _button("Cancel", func():
		_d_title.text = ""
		_d_body.text = ""
		_hide_dialog(), "DarkButton", Vector2(140, 50))
	cancel.position = Vector2(574, 520)
	_dialog.add_child(cancel)

func _layout() -> void:
	var k := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(k, k)
	_frame.position = ((size - Vector2(W, H) * k) * 0.5).floor()

# ---- Filling ---------------------------------------------------------------------------------------------------------------

func _set_tag(t: String, refill := true) -> void:
	_tag = t
	for k in _tab_btns:
		(_tab_btns[k] as Button).button_pressed = k == t
	if refill:
		_fill_list()

func _set_sort(s: String, refill := true) -> void:
	_sort = s
	for k in _sort_btns:
		(_sort_btns[k] as Button).button_pressed = k == s
	if refill:
		_fill_list()

func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var items := Forum.listed(_sort, _tag).filter(func(x): return not Ranked.blocked(String(x.a)))
	for th in items:
		var row := ThreadRow.new()
		row.th = th
		row.selected = int(th.id) == _open
		row.custom_minimum_size = Vector2(730, 96)
		var tid := int(th.id)
		row.clicked.connect(func(): _open_thread(tid))
		row.voted.connect(func():
			Forum.vote_thread(Forum.thread(tid))
			_refresh_rows())
		row.author_menu.connect(func(id: String, at: Vector2): PlayerMenu.open(self, id, at))
		_list.add_child(row)
	if items.is_empty():
		var l := _label("Nothing here yet. Be the first to post.", 18, U.TEXT_DIM)
		_list.add_child(l)
	var on := Ranked.online_counts()
	_footer.text = "%d threads   ·   %d players online" % [Forum.threads().size(), int(on[0])]

func _refresh_rows() -> void:
	for c in _list.get_children():
		if c is ThreadRow:
			(c as ThreadRow).selected = int((c as ThreadRow).th.id) == _open
			c.queue_redraw()

func _open_thread(id: int) -> void:
	var th := Forum.thread(id)
	if th.is_empty():
		return
	if _open != id:
		_reply_to = -1
	_open = id
	th["seen"] = Ranked.now()
	_fill_view(th, true)
	_refresh_rows()
	_ask_writer(th)

func _fill_view(th: Dictionary, to_top := false) -> void:
	for c in _view.get_children():
		c.queue_free()
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_view.add_child(head)
	var tl := _label(String(th.title), 30, U.GOLD, "title", true)
	tl.custom_minimum_size = Vector2(980, 0)
	head.add_child(tl)
	head.add_child(_author_line(String(th.a), int(th.t), String(th.tag)))
	var body := _label(String(th.body), 19, U.TEXT, "body", true)
	body.custom_minimum_size = Vector2(980, 0)
	head.add_child(body)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 12)
	var vb := _button(("Voted  " if bool(th.voted) else "Upvote  ") + str(int(th.votes)), func():
		Forum.vote_thread(th)
		_fill_view(th)
		_refresh_rows(), "DarkButton", Vector2(140, 38))
	vrow.add_child(vb)
	var rb := _button("Reply", func(): _set_reply_to(th, -1), "DarkButton", Vector2(110, 38))
	vrow.add_child(rb)
	vrow.add_child(_label("%d replies" % (th.replies as Array).size(), 16, U.TEXT_DIM, "body"))
	head.add_child(vrow)
	var sep := ColorRect.new()
	sep.color = Color(U.GOLD, 0.2)
	sep.custom_minimum_size = Vector2(1000, 1)
	_view.add_child(sep)
	var rs: Array = th.replies
	var hidden := 0
	for i in rs.size():
		if Ranked.blocked(String(rs[i].a)):
			hidden += 1
			continue
		_view.add_child(_reply_row(th, i))
	if hidden > 0:
		_view.add_child(_label("%d %s from players you blocked hidden" % [hidden, "reply" if hidden == 1 else "replies"], 14, U.TEXT_DIM, "body"))
	_update_typing(th)
	if to_top:
		_view_scroll.scroll_vertical = 0

func _author_line(id: String, t: int, tag := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var p: Dictionary = Ranked.me() if id == "me" else Forum.person(id)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(40, 40)
	av.set_spec(p.get("avatar", {"k": "none"}))
	row.add_child(av)
	var tagline := "  (you)" if id == "me" else ("  (your account)" if Ranked.is_account(id) else "")
	var nm := _label(String(p.get("name", "?")) + tagline, 18, U.GOLD if Ranked.is_yours(id) else U.TEXT, "bold")
	row.add_child(nm)
	# the picture and name open the profile (click) or the player menu (right-click) (run 2026-10-20)
	for c in [av, nm]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		(c as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		(c as Control).tooltip_text = "Click: profile  ·  Right-click: more"
		(c as Control).gui_input.connect(func(e: InputEvent):
			if SocialUi.is_right(e):
				PlayerMenu.open(self, id, SocialUi.at(c, e))
			elif SocialUi.is_left(e):
				Options.click()
				ProfilePage.overlay(self, id))
	var tier := Ranked.tier_for(p)
	var em := TextureRect.new()
	em.texture = RankEmblem.icon(tier)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.custom_minimum_size = Vector2(34, 34)
	row.add_child(em)
	var info := Ranked.rank_label(p)
	if not Ranked.is_yours(id):
		var labels: Array = Persona.labels(p)
		if not labels.is_empty():
			info += "  ·  " + ", ".join(labels)
	# on this forum averages are everything: the writer's average K/D/A and MVPs
	var avg := ProfileTalk.fill(ProfileTalk.read(p))
	if avg.has("kda"):
		info += "  ·  %s avg" % String(avg.kda)
	if int(avg.get("mvps", 0)) > 0:
		info += "  ·  %d MVP" % int(avg.mvps)
	info += "  ·  " + RankedNum.ago(t)
	if tag != "":
		info += "  ·  " + tag
	row.add_child(_label(info, 15, U.TEXT_DIM, "body"))
	return row

func _reply_row(th: Dictionary, i: int) -> Control:
	var r: Dictionary = th.replies[i]
	var box := PanelContainer.new()
	var mine := String(r.a) == "me"
	box.add_theme_stylebox_override("panel", U.box("soc_card_gold" if mine else "soc_card", 6.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	v.add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	margin.add_child(inner)
	inner.add_child(_author_line(String(r.a), int(r.t)))
	var txt := _label(String(r.text), 18, U.TEXT, "body", true)
	txt.custom_minimum_size = Vector2(940, 0)
	inner.add_child(txt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var vb := _button(("Voted  " if bool(r.voted) else "Upvote  ") + str(int(r.votes)), func():
		Forum.vote_reply(r)
		_fill_view(th), "DarkButton", Vector2(120, 32))
	vb.add_theme_font_size_override("font_size", 14)
	row.add_child(vb)
	# you may answer anyone, yourself included (a post of another of your accounts, or your own)
	var rb := _button("Reply", func(): _set_reply_to(th, i), "DarkButton", Vector2(90, 32))
	rb.add_theme_font_size_override("font_size", 14)
	row.add_child(rb)
	inner.add_child(row)
	return box

func _set_reply_to(th: Dictionary, i: int) -> void:
	_reply_to = i
	if i < 0:
		_reply_to_lbl.text = "Replying to the post"
	else:
		var a := String(th.replies[i].a)
		_reply_to_lbl.text = "Replying to %s" % Forum.name_of(a)
	_reply_box.grab_focus()

func _update_typing(th: Dictionary) -> void:
	var who: Array = Forum.typing(th)
	if who.is_empty():
		_typing.text = ""
	elif who.size() == 1:
		_typing.text = "%s is typing..." % String(who[0])
	else:
		_typing.text = "%s and %d %s typing..." % [String(who[0]), who.size() - 1, "other is" if who.size() == 2 else "others are"]

# ---- Posting -----------------------------------------------------------------------------------------------------------------

func _send_reply() -> void:
	var text := _reply_box.text.strip_edges()
	if text == "" or _open < 0:
		return
	var th := Forum.thread(_open)
	if th.is_empty():
		return
	Forum.reply(th, text, _reply_to)
	_reply_box.text = ""
	_reply_to = -1
	_reply_to_lbl.text = ""
	_fill_view(th)
	await get_tree().process_frame
	_view_scroll.scroll_vertical = int(_view_scroll.get_v_scroll_bar().max_value)
	_ask_writer(th)

func _new_post() -> void:
	_dialog_dim.visible = true
	_dialog.visible = true
	U.pop_in(_dialog_dim)
	U.pop_in(_dialog)
	_d_title.grab_focus()

func _hide_dialog() -> void:
	_dialog.visible = false
	_dialog_dim.visible = false

func _post_thread() -> void:
	var title := _d_title.text.strip_edges()
	if title == "":
		_d_title.grab_focus()
		return
	var th := Forum.post(title, _d_body.text, String(Forum.TAGS[_d_tag.selected]))
	_d_title.text = ""
	_d_body.text = ""
	_hide_dialog()
	_set_sort("new", false)
	_fill_list()
	_open_thread(int(th.id))

func _ask_writer(th: Dictionary) -> void:
	if _writer == null:
		return
	var t := Ranked.now()
	for q in th.pending:
		if int(q.at) - t < 40:
			_writer.want_reply(th, q)

func _process(dt: float) -> void:
	_tick -= dt
	if _wait > 0.0:
		_wait -= dt
	if _tick <= 0.0:
		_tick = 1.0
		var n := Forum.resolve()
		if _open >= 0:
			var th := Forum.thread(_open)
			if not th.is_empty():
				_ask_writer(th)
				if n > 0:
					var at_end: bool = _view_scroll.scroll_vertical >= int(_view_scroll.get_v_scroll_bar().max_value - _view_scroll.size.y - 40)
					_fill_view(th)
					if at_end:
						await get_tree().process_frame
						_view_scroll.scroll_vertical = int(_view_scroll.get_v_scroll_bar().max_value)
				else:
					_update_typing(th)
		if n > 0:
			_fill_list()
	if _capture != "" and _wait <= 0.0:
		_frames += 1
		if _frames == _cap_frames:
			var img := get_viewport().get_texture().get_image()
			var p := ProjectSettings.globalize_path("res://" + _capture)
			DirAccess.make_dir_recursive_absolute(p.get_base_dir())
			img.save_png(p)
			print("captured ", p)
			get_tree().quit()

# ---- The player menu's host (PlayerMenu) ------------------------------------------------------------------------------

var _toast: Label
var _toast_t := 0.0

## A short note at the top (the player menu's answers).
func notice(text: String) -> void:
	if _toast == null:
		_toast = _label("", 19, U.TEXT, "bold")
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_theme_stylebox_override("normal", U.box("soc_card_gold", 16.0))
		_toast.size = Vector2(760, 0)
		_toast.position = Vector2((W - 760) * 0.5, 104)
		_frame.add_child(_toast)
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = 4.0
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)

## After a friend, commend or block from the menu: blocked players' posts disappear.
func refresh_social() -> void:
	_fill_list()
	if _open >= 0:
		_fill_view(Forum.thread(_open))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		if _dialog.visible:
			_hide_dialog()
		else:
			Options.go(get_tree(), MAIN_MENU)
		get_viewport().set_input_as_handled()

# =====================================================================================================================

## A thread in the list: votes (click the arrow), the title, the section, who posted (rank), when, replies.
class ThreadRow extends Control:
	signal clicked
	signal voted
	signal author_menu(id: String, at: Vector2)
	var th := {}
	var selected := false
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
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e):
			author_menu.emit(String(th.get("a", "")), SocialUi.at(self, e))
			accept_event()
			return
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			if (e as InputEventMouseButton).position.x < 64:
				voted.emit()
			else:
				clicked.emit()
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var mine := String(th.get("a", "")) == "me"
		U.skin(self, "soc_row_hover" if selected or _hot else ("soc_row_gold" if mine else "soc_row"), r)
		if selected:
			draw_rect(Rect2(2, 2, 4, size.y - 4), U.GOLD)
		# votes
		var vc := U.GOLD if bool(th.get("voted", false)) else U.TEXT_DIM
		var ax := 32.0
		draw_colored_polygon(PackedVector2Array([Vector2(ax, 18), Vector2(ax - 11, 32), Vector2(ax + 11, 32)]), vc)
		var vs := str(int(th.get("votes", 0)))
		var vf := U.font("bold")
		draw_string(vf, Vector2(ax - vf.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, 56), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, vc)
		# title
		var tf := U.font("bold")
		var title := String(th.get("title", ""))
		draw_string(tf, Vector2(72, 32), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 20, U.GOLD if mine else U.TEXT)
		# section chip
		var tag := String(th.get("tag", ""))
		var bf := U.font("body")
		var cw := bf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16
		draw_style_box(RankedNum.flat(Color(0.2, 0.3, 0.45, 0.5), Color(0.4, 0.72, 1.0, 0.5), 9), Rect2(72, 44, cw, 20))
		draw_string(bf, Vector2(80, 59), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.88, 1.0))
		# who, rank, when, replies
		var a := String(th.get("a", ""))
		var p: Dictionary = Ranked.me() if a == "me" else Forum.person(a)
		var ic := RankEmblem.icon(Ranked.tier_for(p))
		var x := 72.0 + cw + 10.0
		if ic:
			draw_texture_rect(ic, Rect2(x, 40, 26, 26), false)
			x += 30.0
		var who := "%s  ·  %s  ·  %s" % [String(p.get("name", "?")), Ranked.tier_name(Ranked.tier_for(p)), RankedNum.ago(int(th.get("t", 0)))]
		draw_string(bf, Vector2(x, 59), who, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 120, 14, U.TEXT_DIM)
		var n := (th.get("replies", []) as Array).size()
		var rt := "%d %s" % [n, "reply" if n == 1 else "replies"]
		draw_string(bf, Vector2(size.x - 14 - bf.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, 59), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		# the last reply
		if n > 0:
			var lr: Dictionary = th.replies[n - 1]
			var who2 := "you" if String(lr.a) == "me" else Forum.name_of(String(lr.a))
			draw_string(bf, Vector2(72, 84), "%s: %s" % [who2, String(lr.text)], HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 14, Color(U.TEXT_DIM, 0.85))
