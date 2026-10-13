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
	"tp_scroll": "ui/teleport", "bottle": "items/elixir_rejuvenation", "reveal_ward": "status/spirit_ward", "reveal_dust": "items/mat_arcane_dust", "tango": "status/regen", "salve": "items/potion_health", "clarity": "items/potion_mana", "mango": "status/vigor",
	"faerie_fire": "items/aether_shard", "observer_ward": "status/keen", "branch": "items/wand_2", "slippers": "items/boots_cloth",
	"gauntlets": "items/gloves_plate", "mantle": "items/helm_hood", "circlet": "ui/crown", "boots_elves": "items/boots_cloth_2",
	"belt_str": "items/charm", "robe": "items/armor_robe", "blade_alacrity": "items/aether_sword", "blades_attack": "items/dagger_2",
	"broadsword": "items/greatsword", "gloves": "items/gloves_cloth", "ring_protection": "items/ring", "chainmail": "items/armor_robe_2",
	"quelling_blade": "items/axe", "ring_regen": "items/ring_3", "sobi_mask": "items/amulet_3", "boots": "items/boots_plate",
	"magic_stick": "items/wand", "lifesteal": "items/amulet_2", "wraith_band": "items/aether_ring", "magic_wand": "items/aether_wand",
	"power_treads": "items/set_guardian_boots", "mask_of_madness": "items/helm_plate_3", "yasha": "items/sword_3",
	"dragon_lance": "items/bow_2",
	"giant_axe": "items/axe_2", "wizard_staff": "items/staff", "greatsword": "items/greatsword_2",
	"steel_hammer": "items/mat_iron_shard", "spear": "items/spear", "rust_stone": "status/armor_broken",
	"brass_knuckles": "items/gloves_plate_2", "plate_vest": "items/armor_plate", "big_healing_ring": "items/ring_2",
	"mana_stone": "items/frost_crystal", "health_crystal": "items/mat_ember_core", "big_gem": "items/storm_essence",
	"pointy_hat": "items/helm_hood_2", "fur_hat": "items/helm_hood_3", "sneak_charm": "items/amulet",
	"jump_knife": "items/dagger_3", "tough_band": "items/set_guardian_gloves", "smart_band": "items/set_sage_gloves",
	"mana_ring": "status/aura_clarity", "leaf_hat": "items/set_sage_hood", "steady_ring": "items/aether_amulet",
	"slip_boots": "items/boots_plate_2", "mana_boots": "items/set_sage_boots", "medic_kit": "status/aura_mending",
	"block_shield": "items/shield", "spike_armor": "items/armor_plate_3", "gold_glove": "items/gold",
	"push_staff": "items/staff_2", "spell_shield": "items/shield_3", "armor_breaker": "items/sword_2",
	"shock_hammer": "status/shocked", "cleave_axe": "items/axe_3", "sneak_blade": "items/dagger",
	"upgrade_staff": "items/aether_staff", "upgrade_gem": "items/quest_lance_shard",
	"huge_sword": "items/sword", "dodge_charm": "items/charm_2", "long_staff": "items/staff_3",
	"mana_tiara": "items/quest_crown_fragment", "heavy_sword": "items/set_guardian_shield", "spell_sword": "items/wand_3",
	"twin_swords": "items/set_guardian_armor", "battle_staff": "items/set_sage_staff", "crit_sword": "items/greatsword_3",
	"crit_bow": "items/bow_3", "stun_club": "items/mat_bone_fragment", "stun_blade": "items/set_guardian_helm",
	"sure_hit_staff": "items/spear_2", "silence_staff": "items/set_sage_robe", "root_staff": "items/spear_3",
	"halberd": "items/shield_2", "hex_staff": "items/quest_tablet", "break_blade": "items/shadow_silk",
}
const ABILITY_ICONS := {"burst_shot": "skills/multishot", "gale_impact": "skills/power_shot",
	"masterful_archery": "skills/deadeye", "blood_ranger_ult": "skills/bs_blood_eclipse", "dark_stomp": "skills/tempo_wd_quake",
	"leap_strike": "skills/leap_slam", "tainted_touch": "skills/shadow_curse", "unholy_might": "skills/dg_black_dominion",
	"shuriken_hook": "skills/crippling_star", "stench": "skills/venomcraft", "blubber": "skills/iron_skin",
	"chomp": "skills/eviscerate", "growing_gut": "skills/toughness"}

static var _fonts := {}
static var _icons := {}

static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title":
			# the imported resource (the raw .ttf is not packed in exported builds)
			var ff := load("res://assets/ui/fonts/Cinzel.ttf") as Font
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
	if id.begins_with("recipe_"):
		return icon("items/quest_letter")
	return icon(String(ITEM_ICONS.get(id, "items/charm")))

static func ability_icon(id: String) -> Texture2D:
	return icon(String(ABILITY_ICONS.get(id, "skills/keen_eye")))

## A panel: vertical gradient, inner shadow, thin gold rim.
static var _boxes := {}

static func panel(ci: CanvasItem, r: Rect2, rim := GOLD_DIM, radius := 6.0) -> void:
	var key := rim.to_html() + str(radius)
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = PANEL_BOT
		sb.set_corner_radius_all(int(radius))
		sb.border_color = rim
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 10
		_boxes[key] = sb
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
	var steps := 40
	var start := -PI * 0.5
	var col := PackedColorArray([Color(0, 0, 0, 0.66), Color(0, 0, 0, 0.66), Color(0, 0, 0, 0.66)])
	var prev := Vector2.INF
	for i in steps + 1:
		var a := start + TAU * frac * float(i) / steps
		var p := c + Vector2(cos(a), sin(a)) * rad
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.y = clampf(p.y, r.position.y, r.end.y)
		if prev != Vector2.INF:
			var area := absf((prev - c).cross(p - c))
			if area > 0.01:
				ci.draw_primitive(PackedVector2Array([c, prev, p]), col, PackedVector2Array())
		prev = p
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

## An on/off switch for CheckButton: a 56 x 30 capsule, gold with the knob on the right when on, dark with a grey
## knob on the left when off (both clearly visible on the dark panels).
static func _switch_icon(on: bool) -> ImageTexture:
	var w := 56
	var h := 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5 - 1.0
	var kx := (w - h * 0.5) if on else h * 0.5
	var track := Color(0.62, 0.48, 0.2) if on else Color(0.1, 0.1, 0.12)
	var rim := Color(0.9, 0.72, 0.36) if on else Color(0.45, 0.42, 0.38)
	var knob := Color(1.0, 0.93, 0.74) if on else Color(0.62, 0.6, 0.58)
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, h * 0.5, w - h * 0.5)
			var d := px.distance_to(Vector2(cx, h * 0.5))
			var c := Color(0, 0, 0, 0)
			if d < r + 0.5:
				c = rim if d > r - 1.6 else track
				c.a = clampf(r + 0.5 - d, 0.0, 1.0)
			var kd := px.distance_to(Vector2(kx, h * 0.5))
			if kd < r - 3.0:
				var kc := knob
				kc.a = clampf(r - 3.0 - kd, 0.0, 1.0)
				c = c.blend(kc) if c.a > 0.0 else kc
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

## The Control theme for menus: dark panels with a gold rim, Lato text, Cinzel headings, gold sliders and buttons.
static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 16
	var sb := func(bg: Color, border: Color, bw := 1, r := 4, pad := 8) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(bw)
		s.set_corner_radius_all(r)
		s.content_margin_left = pad
		s.content_margin_right = pad
		s.content_margin_top = pad * 0.6
		s.content_margin_bottom = pad * 0.6
		return s
	t.set_stylebox("panel", "PanelContainer", sb.call(Color(0.06, 0.065, 0.085, 0.94), GOLD_DIM, 2, 8, 14))
	t.set_stylebox("panel", "Panel", sb.call(Color(0.06, 0.065, 0.085, 0.94), GOLD_DIM, 2, 8, 14))
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, sb.call(Color(0.12, 0.12, 0.15), Color(0.35, 0.3, 0.22)))
		t.set_stylebox("hover", cls, sb.call(Color(0.18, 0.16, 0.13), GOLD))
		t.set_stylebox("pressed", cls, sb.call(Color(0.28, 0.22, 0.12), GOLD))
		t.set_stylebox("focus", cls, sb.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		t.set_stylebox("disabled", cls, sb.call(Color(0.08, 0.08, 0.09), Color(0.2, 0.2, 0.2)))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, GOLD)
		t.set_color("font_pressed_color", cls, GOLD)
	t.set_stylebox("hover_pressed", "Button", sb.call(Color(0.3, 0.24, 0.13), GOLD))
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false))
	for cls in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, GOLD)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, GOLD)
		var clear: StyleBoxFlat = sb.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(st, cls, clear)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 15)
	var slider_bg: StyleBoxFlat = sb.call(Color(0.02, 0.02, 0.03), Color(0.25, 0.22, 0.18), 1, 3, 0)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	var fill: StyleBoxFlat = sb.call(Color(0.62, 0.48, 0.2), Color(0.8, 0.62, 0.28), 1, 3, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 18:
			var d := Vector2(x - 8.5, y - 8.5).length()
			grab.set_pixel(x, y, Color(1.0, 0.86, 0.5, clampf(8.5 - d, 0.0, 1.0)) if d < 6.5 else Color(0.15, 0.1, 0.05, clampf(8.5 - d, 0.0, 1.0)))
	var gt := ImageTexture.create_from_image(grab)
	t.set_icon("grabber", "HSlider", gt)
	t.set_icon("grabber_highlight", "HSlider", gt)
	t.set_stylebox("tab_selected", "TabBar", sb.call(Color(0.2, 0.16, 0.1), GOLD, 1, 4, 12))
	t.set_stylebox("tab_unselected", "TabBar", sb.call(Color(0.08, 0.08, 0.1), Color(0.3, 0.27, 0.22), 1, 4, 12))
	t.set_stylebox("tab_hovered", "TabBar", sb.call(Color(0.14, 0.12, 0.1), GOLD_DIM, 1, 4, 12))
	t.set_color("font_selected_color", "TabBar", GOLD)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_stylebox("panel", "TabContainer", sb.call(Color(0.05, 0.055, 0.07, 0.92), GOLD_DIM, 1, 6, 12))
	t.set_stylebox("normal", "LineEdit", sb.call(Color(0.03, 0.03, 0.04), Color(0.35, 0.3, 0.22)))
	t.set_stylebox("focus", "LineEdit", sb.call(Color(0.03, 0.03, 0.04), GOLD))
	t.set_stylebox("panel", "PopupMenu", sb.call(Color(0.07, 0.07, 0.09, 0.98), GOLD_DIM, 1, 4, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("hover", "PopupMenu", sb.call(Color(0.2, 0.16, 0.1), Color(0, 0, 0, 0), 0))
	_theme = t
	return t
