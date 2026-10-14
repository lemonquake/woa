class_name NetList
extends VBoxContainer
## A table for the Multiplayer screens (servers, lobbies, players): a header row, then rows on dark plates that light
## up under the mouse and turn gold when selected; section titles split the rows into groups. Click selects, double
## click (or Enter) opens. Each row is {cells: [cell], data, section (a title row when set), dim, tip}; a cell is a
## String or {text, sub, color, icon, dot (a status dot colour), align ("left" / "center" / "right")}.

const U = preload("res://src/ui/ui_kit.gd")

signal selected(data)
signal activated(data)

var columns: Array = []                     # [{title, width (0 = takes the rest), align}]
var row_h := 56.0
var empty_text := ""
var empty_sub := ""
var rows: Array = []
var sel_key = null                          # data["key"] of the selected row (kept across refreshes)
var _header: Control
var _scroll: ScrollContainer
var _body: Control
var _hover := -1

func _init(cols: Array, rh := 56.0) -> void:
	columns = cols
	row_h = rh
	add_theme_constant_override("separation", 4)
	_header = Control.new()
	_header.custom_minimum_size = Vector2(0, 26)
	_header.draw.connect(_draw_header)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = Control.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.focus_mode = Control.FOCUS_ALL
	_body.draw.connect(_draw_body)
	_body.gui_input.connect(_body_input)
	_body.mouse_exited.connect(func():
		_hover = -1
		_body.queue_redraw())
	_scroll.add_child(_body)
	resized.connect(_relayout)

func set_rows(r: Array) -> void:
	rows = r
	_relayout()

func selected_data():
	for row in rows:
		if not row.has("section") and row.get("data") is Dictionary and sel_key != null and row.data.get("key") == sel_key:
			return row.data
	return null

func select_key(k) -> void:
	sel_key = k
	_body.queue_redraw()
	selected.emit(selected_data())

func _relayout() -> void:
	_body.custom_minimum_size = Vector2(0, _content_h())
	_header.queue_redraw()
	_body.queue_redraw()

func _content_h() -> float:
	var h := 0.0
	for r in rows:
		h += _h_of(r) + 4.0
	return h

func _h_of(r: Dictionary) -> float:
	return 34.0 if r.has("section") else row_h

func _row_at(y: float) -> int:
	var at := 0.0
	for i in rows.size():
		var h := _h_of(rows[i]) + 4.0
		if y >= at and y < at + h:
			return i
		at += h
	return -1

## Column x ranges for a width w.
func _cols(w: float) -> Array:
	var fixed := 0.0
	var flex := 0
	for c in columns:
		if float(c.get("width", 0)) > 0.0:
			fixed += float(c.width)
		else:
			flex += 1
	var rest := maxf(80.0, w - fixed - 24.0)
	var out := []
	var x := 12.0
	for c in columns:
		var cw := float(c.get("width", 0))
		if cw <= 0.0:
			cw = rest / maxi(1, flex)
		out.append([x, cw])
		x += cw
	return out

func _draw_header() -> void:
	var cs := _cols(_header.size.x)
	for i in columns.size():
		var c: Dictionary = columns[i]
		_cell_text(_header, String(c.get("title", "")), cs[i][0], cs[i][1], 18, 14, U.TEXT_DIM, "bold", String(c.get("align", "left")))

func _cell_text(ci: CanvasItem, s: String, x: float, w: float, y: float, size: int, col: Color, kind: String, align: String) -> void:
	var f := U.font(kind)
	s = _fit(s, f, size, w - 16.0)
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px := x + 8.0
	if align == "center":
		px = x + (w - tw) * 0.5
	elif align == "right":
		px = x + w - tw - 8.0
	U.text(ci, s, Vector2(px, y), size, col, kind)

## Shorten text to fit a width, with an ellipsis.
static func _fit(s: String, f: Font, size: int, w: float) -> String:
	if w <= 10.0 or f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= w:
		return s
	while s.length() > 1 and f.get_string_size(s + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		s = s.left(s.length() - 1)
	return s.strip_edges() + "..."

func _draw_body() -> void:
	var w := _body.size.x
	var cs := _cols(w)
	if rows.is_empty() and empty_text != "":
		U.text_c(_body, empty_text, Vector2(w * 0.5, 54), 19, U.TEXT, "bold")
		if empty_sub != "":
			U.text_c(_body, empty_sub, Vector2(w * 0.5, 82), 15, U.TEXT_DIM, "body")
		return
	var y := 0.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := _h_of(r)
		var rect := Rect2(0, y, w, h)
		if r.has("section"):
			U.text(_body, String(r.section), Vector2(12, y + 24), 17, U.GOLD, "title")
			var f := U.font("title")
			var tw := f.get_string_size(String(r.section), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_line_on(_body, Vector2(24 + tw, y + 18), Vector2(w - 8, y + 18), Color(U.GOLD_DIM, 0.5))
			if r.has("hint"):
				var hint := String(r.hint)
				var hw := U.font("body").get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				var hx := w - hw - 12
				_body.draw_rect(Rect2(hx - 8, y + 6, hw + 16, 22), Color(0.03, 0.035, 0.05))
				U.text(_body, hint, Vector2(hx, y + 22), 13, U.TEXT_DIM, "body")
			y += h + 4.0
			continue
		var is_sel: bool = sel_key != null and r.get("data") is Dictionary and r.data.get("key") == sel_key
		var sk := "btn_dark_normal"
		if is_sel:
			sk = "btn_dark_hover"
		elif i == _hover:
			sk = "btn_dark_hover"
		if r.get("note", false):
			_body.draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size - Vector2(0, 4)), Color(1, 1, 1, 0.025))
		else:
			U.skin(_body, sk, rect, Color(1, 1, 1, 0.9) if not is_sel else Color(1.15, 1.08, 0.92))
		if is_sel:
			U.art_rect(_body, "glow_gold", Rect2(rect.position.x - 30, rect.position.y - 10, 90, h + 20), Color(1, 1, 1, 0.35))
			_body.draw_rect(Rect2(rect.position + Vector2(3, 6), Vector2(3, h - 12)), U.GOLD)
		var dim := bool(r.get("dim", false))
		var cells: Array = r.cells
		for k in mini(cells.size(), cs.size()):
			var c = cells[k]
			var d: Dictionary = c if c is Dictionary else {"text": str(c)}
			var x: float = cs[k][0]
			var cw: float = cs[k][1]
			var align := String(d.get("align", columns[k].get("align", "left")))
			var tx := x
			if d.has("dot"):
				var dc: Color = d.dot
				_body.draw_circle(Vector2(x + 16, y + h * 0.5), 6.0, Color(dc, 0.25))
				_body.draw_circle(Vector2(x + 16, y + h * 0.5), 4.0, dc)
				tx += 22.0
				cw -= 22.0
			if d.get("icon") is Texture2D:
				var isz := h - 16.0
				_body.draw_texture_rect(d.icon, Rect2(tx + 8, y + 8, isz, isz), false, Color(1, 1, 1, 0.5 if dim else 1.0))
				tx += isz + 8.0
				cw -= isz + 8.0
			var col: Color = d.get("color", U.TEXT if k == 0 else Color(0.85, 0.85, 0.85))
			if dim:
				col = Color(col, 0.55)
			var main_size := int(d.get("size", 18 if k == 0 else 16))
			var kind := String(d.get("kind", "bold"))
			if d.has("sub") and String(d.sub) != "":
				_cell_text(_body, String(d.get("text", "")), tx, cw, y + h * 0.5 - 2, main_size, col, kind, align)
				_cell_text(_body, String(d.sub), tx, cw, y + h * 0.5 + 18, 13, Color(U.TEXT_DIM, 0.6 if dim else 1.0), "body", align)
			else:
				_cell_text(_body, String(d.get("text", "")), tx, cw, y + h * 0.5 + 6, main_size, col, kind, align)
			if d.get("lock", false):
				var li: Texture2D = U.icon("ui/lock")
				if li:
					var f2 := U.font(kind)
					var tw2 := f2.get_string_size(_fit(String(d.get("text", "")), f2, main_size, cw - 16.0), HORIZONTAL_ALIGNMENT_LEFT, -1, main_size).x
					_body.draw_texture_rect(li, Rect2(tx + 14 + tw2, y + h * 0.5 - (12 if d.has("sub") else 7), 16, 16), false, U.GOLD)
		y += h + 4.0

static func draw_line_on(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	ci.draw_line(a, b, col, 1.0, true)

func _body_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := _row_at((e as InputEventMouseMotion).position.y)
		if i != _hover:
			_hover = i if i >= 0 and not rows[i].has("section") and not rows[i].get("note", false) else -1
			_body.queue_redraw()
		var r = rows[_hover] if _hover >= 0 else null
		_body.tooltip_text = String(r.get("tip", "")) if r is Dictionary else ""
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		var i2 := _row_at(mb.position.y)
		if i2 < 0 or rows[i2].has("section") or not (rows[i2].get("data") is Dictionary):
			return
		_body.grab_focus()
		sel_key = rows[i2].data.get("key")
		_body.queue_redraw()
		Options.click()
		selected.emit(rows[i2].data)
		if mb.double_click:
			activated.emit(rows[i2].data)
	elif e is InputEventKey and (e as InputEventKey).pressed:
		var k := e as InputEventKey
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			var d = selected_data()
			if d != null:
				activated.emit(d)
				_body.accept_event()
		elif k.keycode == KEY_DOWN or k.keycode == KEY_UP:
			_step_sel(1 if k.keycode == KEY_DOWN else -1)
			_body.accept_event()

func _step_sel(dir: int) -> void:
	var idx := []
	for i in rows.size():
		if not rows[i].has("section") and rows[i].get("data") is Dictionary:
			idx.append(i)
	if idx.is_empty():
		return
	var cur := -1
	for j in idx.size():
		if rows[idx[j]].data.get("key") == sel_key:
			cur = j
	cur = clampi(cur + dir, 0, idx.size() - 1)
	select_key(rows[idx[cur]].data.get("key"))
