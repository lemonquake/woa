class_name UiKit
extends RefCounted
## Shared look for the HUD: fonts, colours, icon lookup and drawing helpers (panels, bevels, bars, cooldown sweeps).

const GOLD := Color(0.95, 0.78, 0.38)
const GOLD_DIM := Color(0.55, 0.43, 0.2)
const PANEL_TOP := Color(0.11, 0.12, 0.15, 0.96)
const PANEL_BOT := Color(0.05, 0.055, 0.07, 0.98)
const TEXT := Color(0.93, 0.92, 0.88)
const TEXT_DIM := Color(0.62, 0.62, 0.64)
const HP := Color(0.24, 0.72, 0.22)
const MANA := Color(0.22, 0.45, 0.95)
const DAWN := Color(0.4, 0.75, 1.0)
const DUSK := Color(1.0, 0.36, 0.3)

const ITEM_ICONS := {
	"tango": "status/regen", "salve": "items/potion_health", "clarity": "items/potion_mana", "mango": "status/vigor",
	"faerie_fire": "items/aether_shard", "observer_ward": "status/keen", "branch": "items/wand_2", "slippers": "items/boots_cloth",
	"gauntlets": "items/gloves_plate", "mantle": "items/helm_hood", "circlet": "ui/crown", "boots_elves": "items/boots_cloth_2",
	"belt_str": "items/charm", "robe": "items/armor_robe", "blade_alacrity": "items/aether_sword", "blades_attack": "items/dagger_2",
	"broadsword": "items/greatsword", "gloves": "items/gloves_cloth", "ring_protection": "items/ring", "chainmail": "items/armor_robe_2",
	"quelling_blade": "items/axe", "ring_regen": "items/ring_3", "sobi_mask": "items/amulet_3", "boots": "items/boots_plate",
	"magic_stick": "items/wand", "lifesteal": "items/amulet_2", "wraith_band": "items/aether_ring", "magic_wand": "items/aether_wand",
	"power_treads": "items/set_guardian_boots", "mask_of_madness": "items/helm_plate_3", "yasha": "items/sword_3",
	"dragon_lance": "items/bow_2",
}
const ABILITY_ICONS := {"frost_quiver": "skills/frost_arrow", "gale_shot": "skills/gale_burst",
	"hunters_focus": "skills/keen_eye", "arrow_storm": "skills/arrow_rain"}

static var _fonts := {}
static var _icons := {}

static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title":
			var ff := FontFile.new()
			ff.load_dynamic_font("res://assets/ui/fonts/Cinzel.ttf")
			var fv := FontVariation.new()
			fv.base_font = ff
			fv.variation_opentype = {"wght": 700}
			f = fv
		"bold":
			f = load("res://assets/ui/fonts/Lato-Bold.ttf")
		_:
			f = load("res://assets/ui/fonts/Lato-Regular.ttf")
	_fonts[kind] = f
	return f

static func icon(path: String) -> Texture2D:
	if _icons.has(path):
		return _icons[path]
	var full := "res://assets/ui/%s.svg" % path
	var t: Texture2D = load(full) if ResourceLoader.exists(full) else null
	_icons[path] = t
	return t

static func item_icon(id: String) -> Texture2D:
	return icon(String(ITEM_ICONS.get(id, "items/charm")))

static func ability_icon(id: String) -> Texture2D:
	return icon(String(ABILITY_ICONS.get(id, "skills/keen_eye")))

## A panel: vertical gradient, inner shadow, thin gold rim.
static func panel(ci: CanvasItem, r: Rect2, rim := GOLD_DIM, radius := 6.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BOT
	sb.set_corner_radius_all(int(radius))
	sb.border_color = rim
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	sb.draw(ci.get_canvas_item(), r)
	# top highlight band
	var hi := r.grow(-3)
	hi.size.y = minf(hi.size.y * 0.45, 46.0)
	ci.draw_rect(hi, Color(1, 1, 1, 0.035))

static func slot(ci: CanvasItem, r: Rect2, lit := false) -> void:
	ci.draw_rect(r, Color(0.02, 0.02, 0.03, 0.95))
	ci.draw_rect(r, (GOLD if lit else Color(0.32, 0.3, 0.28)), false, 1.5)
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 1, 1, 0.08), 1.0)

## Dark radial sweep over the elapsed part of a cooldown, plus remaining seconds.
static func cooldown(ci: CanvasItem, r: Rect2, frac: float, secs: float) -> void:
	if frac <= 0.0:
		return
	var c := r.get_center()
	var rad := r.size.length() * 0.5
	var pts := PackedVector2Array([c])
	var steps := 40
	var start := -PI * 0.5
	for i in steps + 1:
		var a := start + TAU * frac * float(i) / steps
		var p := c + Vector2(cos(a), sin(a)) * rad
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.y = clampf(p.y, r.position.y, r.end.y)
		pts.append(p)
	ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.66))
	var s := str(ceili(secs)) if secs >= 1.0 else "%.1f" % secs
	text_c(ci, s, c + Vector2(0, 7), 20, Color(1, 1, 1), "bold")

static func text(ci: CanvasItem, s: String, at: Vector2, size: int, col := TEXT, kind := "body", outline := true) -> void:
	var f := font(kind)
	if outline:
		ci.draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	ci.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func text_c(ci: CanvasItem, s: String, at: Vector2, size: int, col := TEXT, kind := "body", outline := true) -> void:
	var w := font(kind).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(ci, s, at - Vector2(w * 0.5, 0), size, col, kind, outline)

static func text_r(ci: CanvasItem, s: String, at: Vector2, size: int, col := TEXT, kind := "body") -> void:
	var w := font(kind).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(ci, s, at - Vector2(w, 0), size, col, kind)

static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.9))
	ci.draw_rect(r, col.darkened(0.75))
	var f := Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y))
	ci.draw_rect(f, col)
	ci.draw_rect(Rect2(f.position, Vector2(f.size.x, r.size.y * 0.4)), Color(1, 1, 1, 0.16))
	ci.draw_rect(Rect2(f.position.x, f.end.y - 2, f.size.x, 2), Color(0, 0, 0, 0.25))

static func wrap(s: String, width: float, size: int, kind := "body") -> PackedStringArray:
	var f := font(kind)
	var out := PackedStringArray()
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out
