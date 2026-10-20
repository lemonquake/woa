class_name IconBorder
extends RefCounted
## The border drawn round skill and item icons, from a border pack (tools/icon_borders.py explains the format).
## Packs live in res://assets/ui/borders/<id>/ (shipped with the game) and user://borders/<id>/ (added later, such as
## bought or downloaded ones: a user pack with the same id replaces the shipped one). Options "icon_border" picks the
## pack; changing it at any time takes effect on the next frame drawn.
##
## Kinds: "skill" (an active ability), "passive" (passive and innate abilities), "item", "ultimate" (if a pack has
## one; otherwise skill). A kind the pack lacks falls back to skill, then to no frame.
##
## Use draw_icon() to draw a whole framed icon (backing, art, shine, frame), or draw() for the frame alone over an
## icon you drew yourself. IconFrame (icon_frame.gd) is the same as a Control for menu screens.

const DEFAULT := "default"
const DIRS := ["res://assets/ui/borders/", "user://borders/"]

static var _packs := {}                     # id -> {name, scale, ref, min, max, pieces: {kind: {tex, shine, margins, outset}}}
static var _scanned := false
static var _ids: Array = []

## The ids of every pack found, the default first.
static func ids() -> Array:
	_scan()
	return _ids

## A pack's display name (its border.json "name").
static func pack_name(id: String) -> String:
	var p := _pack(id)
	return String(p.get("name", id.capitalize())) if not p.is_empty() else id.capitalize()

## The pack in use (Options "icon_border"; the default when that pack is missing).
static func current() -> String:
	var id := String(Options.get_value("icon_border"))
	return id if not _pack(id).is_empty() else DEFAULT

## Forget loaded packs (after a pack is added or replaced on disk).
static func reload() -> void:
	_packs.clear()
	_ids.clear()
	_scanned = false

## The border kind for an ability: passive and innate abilities get the passive frame.
static func ability_kind(aid: String) -> String:
	var b := String(SimData.ability(aid).get("behavior", ""))
	return "passive" if b == "passive" or b == "innate" else "skill"

## Draw a framed icon into `r` (the icon fills r; the frame reaches a little outside it). `col` tints the art (greyed
## when unlearned, blue without mana, dim in the backpack); `frame_col` tints the frame (brighter on hover).
static func draw_icon(ci: CanvasItem, tex: Texture2D, r: Rect2, kind := "skill", col := Color.WHITE,
		frame_col := Color.WHITE) -> void:
	ci.draw_rect(r, Color(0.03, 0.035, 0.05))
	if tex:
		ci.draw_texture_rect(tex, r, false, col)
	draw(ci, r, kind, frame_col)

## Where an item's art goes in a slot: the whole slot when it is near square (the art is cropped to fill it, as Dota's
## item tiles), a centred square in a long, low slot (the backpack) so the art is not cut in half.
static func item_rect(slot: Rect2) -> Rect2:
	if slot.size.y >= slot.size.x * 0.7:
		return slot
	var s := minf(slot.size.x, slot.size.y)
	return Rect2(slot.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))

## Draw `tex` filling `r`, cropped to r's shape around the middle (never stretched).
static func draw_cover(ci: CanvasItem, tex: Texture2D, r: Rect2, col := Color.WHITE) -> void:
	if tex == null:
		return
	var ts := tex.get_size()
	var want := r.size.x / maxf(1.0, r.size.y)
	var src := Rect2(Vector2.ZERO, ts)
	if ts.x / ts.y > want:
		src.size.x = ts.y * want
		src.position.x = (ts.x - src.size.x) * 0.5
	else:
		src.size.y = ts.x / want
		src.position.y = (ts.y - src.size.y) * 0.5
	ci.draw_texture_rect_region(tex, r, src, col)

## Draw an item framed in its slot (see item_rect); returns where the art went.
static func draw_item(ci: CanvasItem, tex: Texture2D, slot: Rect2, col := Color.WHITE, frame_col := Color.WHITE) -> Rect2:
	var r := item_rect(slot)
	ci.draw_rect(r, Color(0.03, 0.035, 0.05))
	draw_cover(ci, tex, r, col)
	draw(ci, r, "item", frame_col)
	return r

## Draw only the frame (and its shine) over an icon already drawn in `r`.
static func draw(ci: CanvasItem, r: Rect2, kind := "skill", frame_col := Color.WHITE, shine := true) -> void:
	var p := _pack(current())
	if p.is_empty():
		return
	var pc: Dictionary = p.pieces.get(kind, p.pieces.get("skill", {}))
	if pc.is_empty():
		return
	var k := clampf(minf(r.size.x, r.size.y) / float(p.ref), float(p.min), float(p.max))
	if shine and pc.shine != null:
		ci.draw_texture_rect(pc.shine, r, false, Color(1, 1, 1, frame_col.a))
	var m: Vector4 = pc.margins * k
	var o: float = float(pc.outset) * k
	SkinBox.draw_nine(ci.get_canvas_item(), r.grow(o), pc.tex, m, float(p.scale) / k, frame_col, true)

## How far a kind's frame reaches outside the icon at this icon size (for layouts and hover rects).
static func outset(kind: String, size: float) -> float:
	var p := _pack(current())
	if p.is_empty():
		return 0.0
	var pc: Dictionary = p.pieces.get(kind, p.pieces.get("skill", {}))
	if pc.is_empty():
		return 0.0
	return float(pc.outset) * clampf(size / float(p.ref), float(p.min), float(p.max))

# ---- Loading ------------------------------------------------------------------------------------------------------

static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var found := {}
	for dir in DIRS:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for sub in da.get_directories():
			if FileAccess.file_exists(dir + sub + "/border.json"):
				found[sub] = true
	_ids = found.keys()
	_ids.sort()
	if _ids.has(DEFAULT):
		_ids.erase(DEFAULT)
		_ids.push_front(DEFAULT)

static func _pack(id: String) -> Dictionary:
	if _packs.has(id):
		return _packs[id]
	var p := {}
	# a user pack replaces a shipped pack with the same id
	for dir in ["user://borders/", "res://assets/ui/borders/"]:
		p = _load(dir + id + "/")
		if not p.is_empty():
			break
	_packs[id] = p
	return p

static func _load(dir: String) -> Dictionary:
	if not FileAccess.file_exists(dir + "border.json"):
		return {}
	var f := FileAccess.open(dir + "border.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if not (d is Dictionary) or not (d.get("pieces") is Dictionary):
		push_warning("icon border: bad border.json in " + dir)
		return {}
	var out := {"name": String(d.get("name", dir.get_base_dir().get_file())), "scale": maxf(0.1, float(d.get("scale", 4))),
		"ref": maxf(1.0, float(d.get("ref", 64))), "min": float(d.get("min", 0.5)), "max": float(d.get("max", 1.6)),
		"pieces": {}}
	for kind in d.pieces:
		var pc = d.pieces[kind]
		if not (pc is Dictionary):
			continue
		var tex := _texture(dir + String(pc.get("file", "")))
		if tex == null:
			continue
		var mg: Array = pc.get("margins", [12, 12, 12, 12])
		if mg.size() < 4:
			mg = [mg[0], mg[0], mg[0], mg[0]] if mg.size() > 0 else [12, 12, 12, 12]
		out.pieces[String(kind)] = {"tex": tex,
			"shine": _texture(dir + String(pc.shine)) if String(pc.get("shine", "")) != "" else null,
			"margins": Vector4(float(mg[0]), float(mg[1]), float(mg[2]), float(mg[3])),
			"outset": float(pc.get("outset", 0))}
	return out if not (out.pieces as Dictionary).is_empty() else {}

## An imported texture (res://) or a PNG read straight from disk (user://, where nothing is imported).
static func _texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path) if ResourceLoader.exists(path) else null
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
