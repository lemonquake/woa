extends Control
## The Multiplayer screens, one scene that follows the session's state:
##   * Servers (not connected): the server list (the main server, your saved servers, servers on your local network)
##     with players, lobbies and ping; join by address; host a server on this computer.
##   * Server lobby (connected): the server's lobbies, who is online, and a chat for everyone there; create a lobby,
##     join one, or quick join.
##   * Lobby (in a room): the two teams' slots, your hero, lane and ready state, the lobby chat; the leader fills
##     slots with bots, removes players and starts the match.
## Dialogs (add a server, create a lobby, passwords, lobby settings), notices from the server and the connecting
## overlay are drawn over the page. Esc steps back (closing a dialog first).

const U = preload("res://src/ui/ui_kit.gd")
const MAIN_MENU := "res://src/ui/main_menu.tscn"
const ServersPage = preload("res://src/ui/net_servers_page.gd")
const HubPage = preload("res://src/ui/net_hub_page.gd")
const RoomPage = preload("res://src/ui/net_room_page.gd")

var net: NetSession
var title_label: Label
var sub_label: Label
var chips: HBoxContainer
var page_box: MarginContainer
var page: Control
var page_kind := ""
var _layer: Control                          # dialogs, the connecting overlay
var _dialog: Control
var _dialog_ok: Callable
var _busy: Control
var _busy_label: Label
var _spin: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_t := 0.0
var _capture_path := ""
var _frames := 0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	net = NetSession.inst
	NetBrowser.load_prefs()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_path = a.substr(10)
	_build()
	net.connected.connect(_sync_page)
	net.hub_changed.connect(func(): _refresh())
	net.room_changed.connect(func():
		_sync_page()
		_refresh())
	net.room_left.connect(func(reason):
		_sync_page()
		if reason != "":
			toast(reason, true))
	net.chat_received.connect(func(ch, nm, text, sys):
		if page and page.has_method("on_chat"):
			page.on_chat(ch, nm, text, sys))
	net.notice.connect(func(t): toast(t, true))
	net.status_changed.connect(_on_status)
	net.left.connect(func(reason):
		close_busy()
		_sync_page()
		if reason != "":
			message("Disconnected", reason))
	_sync_page()
	if net.state == NetSession.State.CONNECTING and net.server == null:
		busy("Connecting to %s" % net.address)
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

# ---- Layout ---------------------------------------------------------------------------------------------------------

func _build() -> void:
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
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	# header: the page's title and subtitle, its chips on the right
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	title_label = label("", 44, U.GOLD, "title")
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(title_label)
	sub_label = label("", 17, U.TEXT_DIM)
	sub_label.clip_text = true
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(sub_label)
	chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chips)
	page_box = MarginContainer.new()
	page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(page_box)
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", U.box("panel_tip", 22))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = label("", 18, U.TEXT, "bold")
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	add_child(_toast)

## The header: title, subtitle and chips ([text, colour, icon path] each), before any controls a page put there.
## Chips are updated in place when their number stays the same (pings change every second).
func set_header(title: String, sub: String, chip_list: Array = []) -> void:
	title_label.text = title
	sub_label.text = sub
	var old := chips.get_children().filter(func(c): return c.has_meta("chip") and not c.is_queued_for_deletion())
	if old.size() == chip_list.size():
		for i in old.size():
			var l: Label = old[i].get_meta("label")
			var cd: Array = chip_list[i]
			l.text = String(cd[0])
			l.add_theme_color_override("font_color", cd[1] if cd.size() > 1 else U.TEXT)
			var ic: TextureRect = old[i].get_meta("icon") if old[i].has_meta("icon") else null
			if ic:
				ic.modulate = cd[1] if cd.size() > 1 else U.TEXT
		return
	for c in old:
		c.queue_free()
	var k := 0
	for c in chip_list:
		var ch := chip(String(c[0]), c[1] if c.size() > 1 else U.TEXT, String(c[2]) if c.size() > 2 else "")
		chips.add_child(ch)
		chips.move_child(ch, k)
		k += 1

func chip(text: String, col: Color, icon_path := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", U.box("btn_dark_normal", 16))
	p.set_meta("chip", true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	if icon_path != "":
		var ic := TextureRect.new()
		ic.texture = U.icon(icon_path)
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = col
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		p.set_meta("icon", ic)
	var l := label(text, 16, col, "bold")
	row.add_child(l)
	p.set_meta("label", l)
	return p

func _sync_page() -> void:
	var want := "servers"
	match net.state:
		NetSession.State.HUB:
			want = "hub"
		NetSession.State.ROOM:
			want = "room"
		NetSession.State.LOADING, NetSession.State.PLAYING:
			want = "room" if not net.room.is_empty() else "hub"
	if net.state == NetSession.State.HUB or net.state == NetSession.State.ROOM:
		close_busy()
	if want == page_kind and page != null:
		return
	close_dialog()
	if page != null:
		page.queue_free()
		page = null
	for c in chips.get_children():
		c.queue_free()
	page_kind = want
	match want:
		"servers":
			page = ServersPage.new()
		"hub":
			page = HubPage.new()
		"room":
			page = RoomPage.new()
	page.set("menu", self)
	page_box.add_child(page)
	_refresh()

## The page for the session's state now (after the player left a server or a lobby on purpose).
func sync() -> void:
	_sync_page()

func _refresh() -> void:
	if page != null and is_instance_valid(page) and page.has_method("refresh"):
		page.refresh()

func _on_status(text: String) -> void:
	if _busy != null and text != "":
		_busy_label.text = text
	elif text != "" and net.state != NetSession.State.CONNECTING:
		toast(text)

# ---- Small builders shared by the pages --------------------------------------------------------------------------------

func label(text: String, size: int, col := U.TEXT, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func button(text: String, cb: Callable, w := 0.0, variation := "", h := 46.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	if variation == "GoldButton":
		b.add_theme_font_size_override("font_size", 22)
	elif variation == "":
		b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

func field(placeholder: String, text := "", secret := false, max_len := 40) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	f.text = text
	f.secret = secret
	f.max_length = max_len
	f.custom_minimum_size = Vector2(0, 44)
	f.add_theme_font_size_override("font_size", 17)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f

## A labelled row: a caption above a control.
func labelled(caption: String, c: Control, hint := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(label(caption, 15, Color(0.85, 0.82, 0.74), "bold"))
	if hint != "":
		var hl := label(hint, 13, U.TEXT_DIM)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(hl)
	v.add_child(c)
	return v

## A frame's style box with its own content margins (the ornate frames' corners need room: titles and buttons stay
## clear of them).
static func frame(skin: String, l: float, t: float, r: float, b: float) -> StyleBox:
	var sb := SkinBox.new(U.skin_tex(skin), U._margins(skin), 2.0)
	sb.content_margin_left = l
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b
	return sb

## A framed section with a title: returns [panel, content box].
func section(title: String, skin := "panel_menu") -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(skin, 58, 30, 58, 36))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	if title != "":
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		v.add_child(head)
		var t := label(title, 24, Color(0.98, 0.86, 0.56), "title")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
	return [p, v]

## The title row of a section (for buttons beside the title).
static func section_head(v: VBoxContainer) -> HBoxContainer:
	return v.get_child(0) as HBoxContainer

func spacer(w := 0.0, expand := true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ---- Dialogs, notices, the connecting overlay ------------------------------------------------------------------------

## A modal dialog. buttons: [[text, callable, variation]]; the first gold one is the default (Enter). Returns the panel's
## content box (body controls go above the buttons).
func dialog(title: String, body: Array, buttons: Array, width := 560.0) -> VBoxContainer:
	close_dialog()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame("panel_menu", 60, 40, 60, 44))
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var t := label(title, 30, U.GOLD, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for c in body:
		if c is String:
			var l := label(String(c), 17, U.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(width - 90, 0)
			v.add_child(l)
		else:
			v.add_child(c)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_dialog_ok = Callable()
	for b in buttons:
		var variation := String(b[2]) if b.size() > 2 else ""
		var btn := button(String(b[0]), b[1], 150, variation, 50)
		row.add_child(btn)
		if variation == "GoldButton" and not _dialog_ok.is_valid():
			_dialog_ok = b[1]
	_dialog = dim
	# first text field takes the keyboard
	for c in v.find_children("*", "LineEdit", true, false):
		(c as LineEdit).grab_focus.call_deferred()
		(c as LineEdit).text_submitted.connect(func(_t):
			if _dialog_ok.is_valid():
				_dialog_ok.call())
		break
	return v

func close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
	_dialog_ok = Callable()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE if _busy == null else Control.MOUSE_FILTER_STOP

func dialog_open() -> bool:
	return _dialog != null and is_instance_valid(_dialog)

## A message with an OK button.
func message(title: String, text: String) -> void:
	dialog(title, [text], [["OK", close_dialog, "GoldButton"]], 600)

## A notice that fades by itself (red-tinted for problems).
func toast(text: String, problem := false) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.62) if problem else U.TEXT)
	_toast.visible = true
	_toast.reset_size()
	_toast_t = 4.0

## The connecting overlay with a Cancel button.
func busy(text: String) -> void:
	close_busy()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame("panel_menu", 60, 40, 60, 44))
	p.custom_minimum_size = Vector2(520, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var spin := Control.new()
	spin.custom_minimum_size = Vector2(0, 64)
	spin.draw.connect(func():
		var c := Vector2(spin.size.x * 0.5, 32)
		var a := Time.get_ticks_msec() / 1000.0 * 4.0
		spin.draw_arc(c, 24, 0, TAU, 48, Color(U.GOLD_DIM, 0.35), 4.0, true)
		spin.draw_arc(c, 24, a, a + 1.9, 24, U.GOLD, 4.0, true))
	v.add_child(spin)
	_spin = spin
	_busy_label = label(text, 20, U.TEXT, "bold")
	_busy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_busy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_busy_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(button("Cancel", func():
		net.leave_server("")
		close_busy()
		_sync_page(), 180))
	_busy = dim

func close_busy() -> void:
	if _busy != null and is_instance_valid(_busy):
		_busy.queue_free()
	_busy = null
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE if not dialog_open() else Control.MOUSE_FILTER_STOP

func go_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

# ---- Frame --------------------------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if _busy != null and is_instance_valid(_busy) and is_instance_valid(_spin):
		_spin.queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		_toast.position = Vector2(roundf((size.x - _toast.size.x) * 0.5), 112)
		if _toast_t <= 0.0:
			_toast.visible = false
	if page != null and is_instance_valid(page) and page.has_method("tick"):
		page.tick(dt)
	if _capture_path != "":
		_frames += 1
		if _frames == 40:
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture_path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _busy != null:
			return
		if dialog_open():
			close_dialog()
		elif page != null and page.has_method("back"):
			page.back()
