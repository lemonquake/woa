class_name AccountsPanel
extends Control
## Your accounts (run 2026-10-20 e; the owner: "Allow the player to create Multiple accounts (fresh 1500 MMR and fresh
## profile, with the same player database and others) ... The player can Login/Logout to their accounts anytime. Can
## create at least 10 accounts"). A popup over the Ranked screen: every account with its picture, rank, MMR and record,
## Log in on the others, Log out on the one in use (then pick one), and New account with a name. Up to
## Ranked.MAX_ACCOUNTS. Logging in rebuilds the Ranked screen for the new account (Ranked.login swaps the ids).
## Closes on a click outside and on Esc.

const U = preload("res://src/ui/ui_kit.gd")
const S = preload("res://src/ui/social_ui.gd")
const RANKED := "res://src/ui/ranked_menu.tscn"
const PW := 720.0
const ROW_H := 72.0

var _layer: CanvasLayer
var _panel: Control
var _list: VBoxContainer
var _name_edit: LineEdit
var _note: Label
var _count: Label
var _out := false                          # logged out: pick an account to log in to

## Open the panel over `host`'s screen (one at a time).
static func open(host: Node) -> AccountsPanel:
	var tree := host.get_tree()
	for old in tree.get_nodes_in_group("accounts_panel"):
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 45
	layer.add_to_group("accounts_panel")
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(layer)
	var p := AccountsPanel.new()
	p._layer = layer
	layer.add_child(p)
	return p

## After a login: the Ranked screen again, as the new account.
static func after_login(tree: SceneTree) -> void:
	for old in tree.get_nodes_in_group("accounts_panel"):
		old.queue_free()
	for old in tree.get_nodes_in_group("profile_overlay"):
		old.queue_free()
	Options.go(tree, RANKED)

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", U.box("soc_panel", 22.0))
	_panel.custom_minimum_size = Vector2(PW, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("Accounts", 30, U.GOLD, "title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = _label("", 16, U.TEXT_DIM, "body")
	head.add_child(_count)
	v.add_child(_label("Every account plays on the same ladder with the same players. A new account starts at %s MMR with a fresh profile." % RankedNum.num(Ranked.ACCOUNT_START),
		15, U.TEXT_DIM, "body", true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PW - 44, ROW_H * 6.2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var made := HBoxContainer.new()
	made.add_theme_constant_override("separation", 10)
	v.add_child(made)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New account name"
	_name_edit.max_length = 20
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.text_submitted.connect(func(_t): _create())
	made.add_child(_name_edit)
	made.add_child(_button("New account", _create, "GoldButton", Vector2(190, 44)))
	_note = _label("", 16, U.GOLD, "body", true)
	v.add_child(_note)
	resized.connect(_place)
	_fill()
	_place()
	U.pop_in(self)

func _place() -> void:
	var vs := get_viewport_rect().size
	var k := clampf(minf(vs.x / 1920.0, vs.y / 1080.0), 0.5, 2.0)
	_panel.scale = Vector2(k, k)
	_panel.reset_size()
	_panel.position = ((vs - _panel.size * k) * 0.5).floor()

func _gui_input(e: InputEvent) -> void:
	# a click on the dimmed screen outside the panel closes it
	if S.is_left(e) and not _panel.get_global_rect().has_point(get_global_transform() * (e as InputEventMouseButton).position):
		accept_event()
		close()

func _unhandled_key_input(e: InputEvent) -> void:
	if U.is_esc(e):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if _out:
		_out = false
		Ranked.save()
	if is_instance_valid(_layer):
		_layer.queue_free()

func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var accs := Ranked.accounts()
	_count.text = "%d of %d" % [accs.size(), Ranked.MAX_ACCOUNTS]
	for p: Dictionary in accs:
		_list.add_child(_row(p))
	if _out:
		_note.text = "Logged out. Choose an account to log in."

func _row(p: Dictionary) -> Control:
	var current := String(p.id) == "me" and not _out
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", U.box("soc_card_gold" if current else "soc_card", 8.0))
	row.custom_minimum_size = Vector2(0, ROW_H)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(54, 54)
	av.set_spec(p.get("avatar", {"k": "none"}))
	h.add_child(av)
	var em := TextureRect.new()
	em.texture = RankEmblem.icon(Ranked.tier_for(p))
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.custom_minimum_size = Vector2(50, 50)
	h.add_child(em)
	if em.texture == null:
		# the emblem pictures bake on first use: try again a moment later
		var tier := Ranked.tier_for(p)
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(em):
				em.texture = RankEmblem.icon(tier))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(_label(String(p.get("name", "?")), 20, U.GOLD if current else U.TEXT, "bold"))
	var games := int(p.get("wins", 0)) + int(p.get("losses", 0))
	var sub := "%s  ·  %s MMR  ·  %d won, %d lost" % [Ranked.rank_label(p), RankedNum.num(int(p.get("mmr", 0))),
		int(p.get("wins", 0)), int(p.get("losses", 0))]
	if games == 0:
		sub = "%s  ·  %s MMR  ·  no matches yet" % [Ranked.rank_label(p), RankedNum.num(int(p.get("mmr", 0)))]
	info.add_child(_label(sub, 15, U.TEXT_DIM, "body"))
	if current:
		var tag := _label("Logged in", 16, S.GREEN_HI, "bold")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tag)
		var lo := _button("Log out", func():
			_out = true
			_note.text = ""
			_fill(), "DarkButton", Vector2(120, 42))
		lo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lo)
	else:
		var id := String(p.id)
		var li := _button("Log in", func(): _login(id), "GoldButton", Vector2(120, 42))
		li.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(li)
	return row

func _login(id: String) -> void:
	if id == "me":
		# logged out and back in to the same account
		_out = false
		close()
		return
	if not Ranked.login(id):
		_note.text = "Finish your ranked match first."
		return
	after_login(get_tree())

func _create() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		_note.text = "Type a name for the new account."
		return
	if Ranked.accounts().size() >= Ranked.MAX_ACCOUNTS:
		_note.text = "You have %d accounts, the most there can be." % Ranked.MAX_ACCOUNTS
		return
	if Ranked.name_taken(nm):
		_note.text = "Someone on the ladder already has that name."
		return
	var id := Ranked.create_account(nm)
	if id == "":
		_note.text = "The account could not be made."
		return
	_name_edit.text = ""
	_note.text = "Made %s. Log in to play on it." % nm
	_fill()

func _label(text: String, px: int, col: Color, kind := "body", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PW - 44, 0)
	return l

func _button(text: String, cb: Callable, variation := "DarkButton", min_size := Vector2(0, 44)) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
