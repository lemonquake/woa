class_name UiKit
extends RefCounted

## Shared look for the HUD: fonts, colours, icon lookup and drawing helpers (panels, bevels, bars, cooldown sweeps).

## Benchmarks: microseconds each interface panel spent in _draw (UiKit.draw_cost at the end of each _draw).
static var draw_us := {}

static func draw_cost(panel: String, t0: int) -> void:
	draw_us[panel] = int(draw_us.get(panel, 0)) + Time.get_ticks_usec() - t0

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
## Player colours by team and slot (Dota's: blue, teal, purple, yellow, orange; pink, olive, light blue, green, brown).
const PLAYER_COLORS := [
	[Color8(51, 117, 255), Color8(102, 255, 191), Color8(191, 0, 191), Color8(243, 240, 11), Color8(255, 107, 0)],
	[Color8(254, 134, 194), Color8(161, 180, 71), Color8(101, 217, 247), Color8(0, 131, 33), Color8(164, 105, 0)]]

static func team_color(team: int) -> Color:
	return DAWN if team == 0 else (DUSK if team == 1 else Color(0.95, 0.8, 0.4))

## A hero's player colour (its team colour for anything else).
static func player_color(u: SimUnit) -> Color:
	if u == null or not u.is_hero() or u.team < 0 or u.team > 1 or u.color_slot < 0:
		return team_color(u.team if u else 2)
	return PLAYER_COLORS[u.team][u.color_slot % 5]

## A hero's name as coloured parts for the kill feed and labels: the player in their colour, the hero in its team's.
static func who_parts(u: SimUnit) -> Array:
	if u == null:
		return [["?", TEXT]]
	if not u.is_hero():
		return [[String(u.look.get("display_name", u.name)), team_color(u.team)]]
	var hero := String(u.def.get("name", u.name))
	var p := u.player_label()
	if p == "" or p == hero:
		return [[hero, player_color(u)]]
	return [[p, player_color(u)], ["(%s)" % hero, team_color(u.team)]]

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
	"kugmo_atuli": "items/aether_greatsword", "igit_atuli": "items/armor_robe_3",
}
const ABILITY_FALLBACKS := {"burst_shot": "skills/multishot", "gale_impact": "skills/power_shot",
	"masterful_archery": "skills/deadeye", "blood_ranger_ult": "skills/bs_blood_eclipse", "dark_stomp": "skills/tempo_wd_quake",
	"leap_strike": "skills/leap_slam", "tainted_touch": "skills/shadow_curse", "unholy_might": "skills/dg_black_dominion",
	"shuriken_hook": "skills/crippling_star", "stench": "skills/venomcraft", "blubber": "skills/iron_skin",
	"chomp": "skills/eviscerate", "growing_gut": "skills/toughness", "fiery_javelin": "skills/storm_javelin",
	"touch_of_ember": "skills/inner_fire", "spirit_of_fire": "skills/flame_sentinel", "divine_smite": "skills/blessed_hammer",
	"breath_of_cold": "skills/frost_nova", "ice_pulse": "skills/frost_orb", "frost_heart": "skills/frost_mastery",
	"endless_winter": "skills/blizzard", "swift_dagger": "skills/ns_umbral_lunge", "sweet_poison": "skills/venom_strike",
	"master_of_shadows": "skills/ns_gloom_veil", "death_order": "skills/ns_marked_execution",
	"time_bolt": "skills/gen/time_bolt", "fast_forward": "skills/gen/fast_forward", "rewind": "skills/gen/rewind",
	"slow_field": "skills/gen/slow_field", "quick_hands": "skills/gen/quick_hands", "stop_time": "skills/gen/stop_time",
	"iron_grip": "skills/gen/iron_grip", "repel": "skills/gen/repel", "magnetize": "skills/gen/magnetize",
	"overload": "skills/gen/overload", "magnet_field": "skills/gen/magnet_field",
	"grip_of_the_ruler": "skills/gen/grip_of_the_ruler", "void_rush": "skills/gen/void_rush",
	"dark_matter_skin": "skills/gen/dark_matter_skin", "anomaly": "skills/gen/anomaly", "bounce_shot": "skills/gen/bounce_shot",
	"summon_boulders": "skills/gen/summon_boulders", "lay_trap": "skills/gen/lay_trap", "place_turret": "skills/gen/place_turret",
	"pilot_turret": "skills/gen/pilot_turret", "soul_tap": "skills/gen/soul_tap",
	"door_of_the_end": "skills/gen/door_of_the_end", "death_scythe": "skills/gen/death_scythe",
	"divine_darkness": "skills/gen/divine_darkness",
	# the five heroes of hero_ideas.txt (run 2026-10-18 f)
	"gust": "skills/gen/gust", "tailwind": "skills/gen/tailwind", "wind_wall": "skills/gen/wind_wall",
	"hurricane": "skills/gen/hurricane", "rage": "skills/gen/rage", "axe_throw": "skills/gen/axe_throw",
	"reckless_swing": "skills/gen/reckless_swing", "unstoppable": "skills/gen/unstoppable",
	"berserk": "skills/gen/berserk", "overhead_cut": "skills/gen/overhead_cut", "sweep": "skills/gen/sweep",
	"steel_stance": "skills/gen/steel_stance", "giant_swing": "skills/gen/giant_swing",
	"knife_juggle": "skills/gen/knife_juggle", "joke_box": "skills/gen/joke_box", "swap": "skills/gen/swap",
	"shuffle": "skills/gen/shuffle", "tame": "skills/gen/tame", "roar": "skills/gen/roar",
	"pack_leader": "skills/gen/pack_leader", "blessing_of_the_beast_king": "skills/gen/blessing_of_the_beast_king",
	"beast_form": "skills/gen/beast_form", "senryukai": "skills/gen/senryukai", "blur_strike": "skills/gen/blur_strike",
	"djin_bomb": "skills/gen/djin_bomb", "ghosts_of_the_will": "skills/gen/ghosts_of_the_will",
	"the_blur": "skills/gen/the_blur"}

## Neutral creeps' spells (the HUD's unit panel and the buff bar).
const NEUTRAL_SKILL_FALLBACKS := {"snarl": "skills/war_cry", "stomp": "skills/tempo_wd_quake", "smash": "skills/heavens_fist"}
const UNIT_SKILL_FALLBACKS := {"weapon_grab": "status/weakened", "pace_aura": "status/aura_might",
	"pack_aura": "status/aura_might", "magic_armor_aura": "status/aura_might", "break_strike": "status/sundered",
	"thick_hide_aura": "status/aura_might", "neutral_crit": "skills/lethality", "neutral_splash": "skills/cleave",
	"ancient": "status/titan", "flying": "status/windstep", "true_sight": "status/keen",
	"sight": "status/spirit_ward", "backdoor_protection": "status/fortified", "fortify": "status/shielded"}

## Keep each skill's identity in paths passed through the HUD. Dark Stomp and Stomp shared an old SVG.
static var ABILITY_ICONS := _skill_paths(ABILITY_FALLBACKS)
static var NEUTRAL_SKILL_ICONS := _skill_paths(NEUTRAL_SKILL_FALLBACKS)
static var UNIT_SKILL_ICONS := _skill_paths(UNIT_SKILL_FALLBACKS)

static func _skill_paths(fallbacks: Dictionary) -> Dictionary:
	var paths := {}
	for id in fallbacks:
		# Owner chose to retain Death Order's existing icon after the small-size review.
		paths[id] = fallbacks[id] if id == "death_order" else "art/skills/" + String(id)
	return paths

static var _fonts := {}
static var _icons := {}

## Fade an overlay, dialog or menu in over `dur` seconds (also while the game is paused); at once with "Menu
## animations" off.
static func pop_in(c: CanvasItem, dur := 0.14) -> void:
	if not bool(Options.get_value("ui_motion")) or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## An Esc key press (not a repeat): every screen's Back and every overlay's Close.
static func is_esc(e: InputEvent) -> bool:
	return e is InputEventKey and (e as InputEventKey).pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE

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
	var full := icon_path(path)
	var t: Texture2D = load(full) if full != "" else null
	_icons[path] = t
	return t

## Resolve art first while retaining the original SVGs for incomplete art sets and existing callers.
static func icon_path(path: String) -> String:
	if path == ABILITY_FALLBACKS["death_order"] or path == "art/skills/death_order":
		return "res://assets/ui/%s.svg" % ABILITY_FALLBACKS["death_order"]
	var art_path := path
	var fallback := path
	if path.begins_with("art/skills/"):
		var id := path.get_file()
		fallback = String(ABILITY_FALLBACKS.get(id, NEUTRAL_SKILL_FALLBACKS.get(id, UNIT_SKILL_FALLBACKS.get(id, "skills/keen_eye"))))
	elif path.begins_with("art/items/"):
		fallback = _item_fallback(path.get_file())
	elif path.begins_with("items/gen/"):
		art_path = "art/items/" + path.get_file()
	elif path == "ui/teleport":
		art_path = "art/items/tp_scroll"
	elif path == "items/quest_letter":
		art_path = "art/items/recipe"
	else:
		# Legacy aliases have no identity when two skills shared an SVG. Current maps above retain it.
		for id in ABILITY_FALLBACKS:
			if ABILITY_FALLBACKS[id] == path:
				art_path = "art/skills/" + String(id)
				break
		if art_path == path:
			for id in NEUTRAL_SKILL_FALLBACKS:
				if NEUTRAL_SKILL_FALLBACKS[id] == path:
					art_path = "art/skills/" + String(id)
					break
	var png := "res://assets/ui/%s.png" % art_path
	if ResourceLoader.exists(png):
		return png
	var svg := "res://assets/ui/%s.svg" % fallback
	return svg if ResourceLoader.exists(svg) else ""

## An item's painted art, then its generated SVG, then its original SVG.
static func item_icon(id: String) -> Texture2D:
	return icon(item_icon_path(id))

## The icon of an item someone holds: Switch Boots show the attribute they are set to (power_treads_str / _agi / _int).
static func held_item_icon(it: Dictionary) -> Texture2D:
	var id := String(it.get("id", ""))
	if id == "bottle" and int(it.get("charges", 3)) <= 0 and String(it.get("orb", "")) == "":
		return icon(item_icon_path("bottle_empty"))
	if id == "power_treads" and it.has("attr"):
		var t := icon(item_icon_path("power_treads_" + String(it.attr)))
		if t:
			return t
	return item_icon(id)

static var _gen_icons := {}
static var _art_icons := {}

static func item_icon_path(id: String) -> String:
	if id.begins_with("recipe_") or id == "recipe":
		return "art/items/recipe"
	if not _art_icons.has(id):
		_art_icons[id] = ResourceLoader.exists("res://assets/ui/art/items/%s.png" % id)
	if _art_icons[id]:
		return "art/items/" + id
	return _item_fallback(id)

static func _item_fallback(id: String) -> String:
	if id == "recipe" or id.begins_with("recipe_"):
		return "items/quest_letter"
	if id == "bottle_empty":
		return _item_fallback("bottle")
	if not _gen_icons.has(id):
		_gen_icons[id] = ResourceLoader.exists("res://assets/ui/items/gen/%s.svg" % id)
	if _gen_icons[id]:
		return "items/gen/" + id
	return String(ITEM_ICONS.get(id, "items/charm"))

## A hero's face (assets/ui/portraits, rendered from the 3D model by tests/tools/bake_portraits.gd), or its
## ultimate's icon before the portraits exist.
static func hero_portrait(id: String) -> Texture2D:
	var key := "portrait:" + id
	if _icons.has(key):
		return _icons[key]
	var path := "res://assets/ui/portraits/%s.png" % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if t == null:
		var abil: Array = SimData.unit(id).get("abilities", [])
		t = ability_icon(SimData.ultimate_of(abil)) if not abil.is_empty() else null
	_icons[key] = t
	return t

static func ability_icon(id: String) -> Texture2D:
	return icon(String(ABILITY_ICONS.get(id, NEUTRAL_SKILL_ICONS.get(id, UNIT_SKILL_ICONS.get(id, "skills/keen_eye")))))

# ---- The generated skin (tools/ui_skin.py: assets/ui/skin, described by skin.json) ---------------------------------

const SKIN_DIR := "res://assets/ui/skin/"
static var _skin := {}
static var _skin_tex := {}
static var _skin_boxes := {}

static func skin_info(name: String) -> Dictionary:
	if _skin.is_empty():
		var f := FileAccess.open(SKIN_DIR + "skin.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_skin = d.get("textures", {})
	return _skin.get(name, {})

static func skin_tex(name: String) -> Texture2D:
	if _skin_tex.has(name):
		return _skin_tex[name]
	var path := SKIN_DIR + name + ".png"
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_skin_tex[name] = t
	return t

static func _margins(name: String) -> Vector4:
	var m: Array = skin_info(name).get("margins", [12, 12, 12, 12])
	return Vector4(float(m[0]), float(m[1]), float(m[2]), float(m[3]))

## A style box of a skin piece (cached), with content margins `pad` (or the piece's own margins when pad < 0).
static func box(name: String, pad := -1.0, col := Color.WHITE) -> SkinBox:
	var key := "%s|%s|%s" % [name, pad, col.to_html()]
	if _skin_boxes.has(key):
		return _skin_boxes[key]
	var sb := SkinBox.new(skin_tex(name), _margins(name), 2.0)
	sb.modulate = col
	var m := _margins(name)
	var cm: Array = skin_info(name).get("content", [])
	if not cm.is_empty():
		m = Vector4(float(cm[0]), float(cm[1]), float(cm[2]), float(cm[3]))
	sb.content_margin_left = m.x if pad < 0.0 else pad
	sb.content_margin_right = m.z if pad < 0.0 else pad
	sb.content_margin_top = m.y if pad < 0.0 else pad * 0.6
	sb.content_margin_bottom = m.w if pad < 0.0 else pad * 0.6
	_skin_boxes[key] = sb
	return sb

## Draw a nine-slice skin piece into `r` (the HUD's own drawing).
static func skin(ci: CanvasItem, name: String, r: Rect2, col := Color.WHITE, center := true) -> void:
	var t := skin_tex(name)
	if t == null:
		return
	SkinBox.draw_nine(ci.get_canvas_item(), r, t, _margins(name), 2.0, col, center)

## Draw a whole skin image (bespoke art, ornaments) at its drawn size with its top-left at `at` (or into `r`).
static func art(ci: CanvasItem, name: String, at: Vector2, col := Color.WHITE, flip_h := false, flip_v := false) -> void:
	var t := skin_tex(name)
	if t == null:
		return
	var sz := t.get_size() * 0.5
	var r := Rect2(at, sz)
	if flip_h or flip_v:
		ci.draw_set_transform(at + Vector2(sz.x if flip_h else 0.0, sz.y if flip_v else 0.0), 0.0,
			Vector2(-1.0 if flip_h else 1.0, -1.0 if flip_v else 1.0))
		ci.draw_texture_rect(t, Rect2(Vector2.ZERO, sz), false, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	ci.draw_texture_rect(t, r, false, col)

static func art_rect(ci: CanvasItem, name: String, r: Rect2, col := Color.WHITE) -> void:
	var t := skin_tex(name)
	if t:
		ci.draw_texture_rect(t, r, false, col)

static func art_size(name: String) -> Vector2:
	var t := skin_tex(name)
	return t.get_size() * 0.5 if t else Vector2.ZERO

## A panel: the ornate gold frame (large panels) or the plain one (small), dark enamel inside.
static func panel(ci: CanvasItem, r: Rect2, rim := GOLD_DIM, _radius := 6.0) -> void:
	var name := "panel_tip"
	if r.size.x >= 260.0 and r.size.y >= 150.0:
		name = "panel_main"
	elif r.size.x >= 120.0 and r.size.y >= 60.0:
		name = "panel_card"
	var col := Color.WHITE
	if rim.r > rim.g * 1.6:
		col = Color(1.0, 0.72, 0.68)         # an enemy's panel: a warmer, redder trim
	skin(ci, name, r, col)

static func slot(ci: CanvasItem, r: Rect2, lit := false) -> void:
	ci.draw_rect(r.grow(-3), Color(0.02, 0.022, 0.03, 0.96))
	skin(ci, "slot_item" if r.size.x > 44.0 else "slot_small", r, Color(1.25, 1.18, 1.0) if lit else Color.WHITE)

## Dark radial sweep over the elapsed part of a cooldown (one polygon, clipped to the slot), a bright edge where the
## sweep stands, and the seconds left.
static func cooldown(ci: CanvasItem, r: Rect2, frac: float, secs: float) -> void:
	if frac <= 0.0:
		return
	var c := r.get_center()
	var rad := r.size.length() * 0.5
	var steps := maxi(4, int(36.0 * frac))
	var start := -PI * 0.5
	var pts := PackedVector2Array([c])
	var edge := Vector2.ZERO
	for i in steps + 1:
		var a := start + TAU * frac * float(i) / steps
		var p := c + Vector2(cos(a), sin(a)) * rad
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.y = clampf(p.y, r.position.y, r.end.y)
		if pts.size() == 0 or p.distance_squared_to(pts[pts.size() - 1]) > 0.25:
			pts.append(p)
		edge = p
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, Color(0.0, 0.0, 0.02, 0.68))
	ci.draw_line(c, edge, Color(1.0, 0.85, 0.5, 0.55), 1.5)
	var s := str(ceili(secs)) if secs >= 1.0 else "%.1f" % secs
	text_c(ci, s, c + Vector2(0, 8), 22, Color(1, 1, 1), "bold")

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

## A framed bar: the gold frame, a dark well, the fill texture for the bar's colour (health, mana, experience, gold,
## enemy red) cut to the fraction.
static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	skin(ci, "bar_frame", r.grow(3))
	var fill := "bar_hp"
	if col.b > col.g * 1.3 and col.b > col.r:
		fill = "bar_mana"
	elif col.r > col.g * 1.6:
		fill = "bar_hp_enemy"
	elif col.r > 0.8 and col.g > 0.6 and col.b < 0.45:
		fill = "bar_gold"
	elif col.r > 0.5 and col.b > 0.8:
		fill = "bar_xp"
	var t := skin_tex(fill)
	var f := Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y))
	if t and f.size.x > 0.5:
		var ts := t.get_size()
		ci.draw_texture_rect_region(t, f, Rect2(0, 0, ts.x * f.size.x / maxf(1.0, r.size.x), ts.y))
	elif f.size.x > 0.5:
		ci.draw_rect(f, col)

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

## The Control theme for every menu: the generated skin (gold-rimmed steel buttons, ornate panels, gold tabs, gem
## sliders and checkboxes, dark inset fields), Lato text, Cinzel headings.
static var _theme: Theme

## A skin image at its drawn size (half its pixels): for theme icons, which draw at their texture's size.
static func half_icon(name: String) -> Texture2D:
	var key := name + "@1x"
	if _skin_tex.has(key):
		return _skin_tex[key]
	var t := skin_tex(name)
	var out: Texture2D = null
	if t:
		var img := t.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
	_skin_tex[key] = out
	return out

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 16
	var panel_box := box("panel_menu")
	t.set_stylebox("panel", "PanelContainer", panel_box)
	t.set_stylebox("panel", "Panel", panel_box)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, box("btn_normal", 16))
		t.set_stylebox("hover", cls, box("btn_hover", 16))
		t.set_stylebox("pressed", cls, box("btn_pressed", 16))
		t.set_stylebox("hover_pressed", cls, box("btn_pressed", 16))
		t.set_stylebox("disabled", cls, box("btn_disabled", 16))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1.0, 0.9, 0.62))
		t.set_color("font_pressed_color", cls, GOLD)
		t.set_color("font_hover_pressed_color", cls, GOLD)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.45, 0.47))
		t.set_color("font_outline_color", cls, Color(0, 0, 0, 0.8))
		t.set_constant("outline_size", cls, 3)
		t.set_font("font", cls, font("bold"))
		t.set_font_size("font_size", cls, 17)
	# primary (gold), danger (red) and quiet (dark) buttons: theme_type_variation GoldButton / RedButton / DarkButton
	for v in [["GoldButton", "btn_gold", Color(0.13, 0.07, 0.02)], ["RedButton", "btn_red", TEXT], ["DarkButton", "btn_dark", TEXT]]:
		var vn: String = v[0]
		t.set_type_variation(vn, "Button")
		t.set_stylebox("normal", vn, box(String(v[1]) + "_normal", 16))
		t.set_stylebox("hover", vn, box(String(v[1]) + "_hover", 16))
		t.set_stylebox("pressed", vn, box(String(v[1]) + "_pressed", 16))
		t.set_stylebox("hover_pressed", vn, box(String(v[1]) + "_pressed", 16))
		t.set_stylebox("disabled", vn, box(String(v[1]) + "_disabled", 16))
		var fc: Color = v[2]
		t.set_color("font_color", vn, fc)
		t.set_color("font_hover_color", vn, fc if vn == "GoldButton" else Color(1.0, 0.92, 0.7))
		t.set_color("font_pressed_color", vn, fc)
		t.set_color("font_hover_pressed_color", vn, fc)
		t.set_color("font_outline_color", vn, Color(1, 0.9, 0.6, 0.35) if vn == "GoldButton" else Color(0, 0, 0, 0.8))
		t.set_constant("outline_size", vn, 1 if vn == "GoldButton" else 3)
		t.set_font("font", vn, font("title") if vn != "DarkButton" else font("bold"))
		t.set_font_size("font_size", vn, 22 if vn != "DarkButton" else 16)
	t.set_icon("checked", "CheckButton", half_icon("check_on"))
	t.set_icon("unchecked", "CheckButton", half_icon("check_off"))
	t.set_icon("checked_disabled", "CheckButton", half_icon("check_on"))
	t.set_icon("unchecked_disabled", "CheckButton", half_icon("check_off"))
	t.set_icon("checked", "CheckBox", half_icon("check_on"))
	t.set_icon("unchecked", "CheckBox", half_icon("check_off"))
	for cls in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1.0, 0.9, 0.62))
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, Color(1.0, 0.9, 0.62))
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(st, cls, StyleBoxEmpty.new())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Label", 2)
	t.set_font_size("font_size", "Label", 15)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", font("title"))
	t.set_font_size("font_size", "TitleLabel", 26)
	t.set_color("font_color", "TitleLabel", GOLD)
	t.set_constant("outline_size", "TitleLabel", 4)
	t.set_color("font_outline_color", "TitleLabel", Color(0, 0, 0, 0.85))
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", font("title"))
	t.set_font_size("font_size", "HeadingLabel", 19)
	t.set_color("font_color", "HeadingLabel", Color(0.98, 0.86, 0.56))
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 14)
	var track := box("slider_track", 0.0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := SkinBox.new(skin_tex("slider_fill"), Vector4(2, 2, 2, 2), 2.0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", half_icon("slider_grabber"))
	t.set_icon("grabber_highlight", "HSlider", half_icon("slider_grabber_hover"))
	t.set_stylebox("tab_selected", "TabBar", box("tab_on", 14))
	t.set_stylebox("tab_unselected", "TabBar", box("tab_off", 14))
	t.set_stylebox("tab_hovered", "TabBar", box("tab_off", 14, Color(1.3, 1.25, 1.15)))
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", GOLD)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_font("font", "TabBar", font("bold"))
	t.set_font_size("font_size", "TabBar", 16)
	for k in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		t.set_stylebox(k, "TabContainer", t.get_stylebox(k, "TabBar"))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", font("bold"))
	t.set_font_size("font_size", "TabContainer", 16)
	t.set_stylebox("panel", "TabContainer", box("panel_card", 16))
	t.set_stylebox("normal", "LineEdit", box("field", 10))
	t.set_stylebox("focus", "LineEdit", box("field_focus", 10))
	t.set_stylebox("read_only", "LineEdit", box("field", 10, Color(0.7, 0.7, 0.7)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.5, 0.52))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.8, 0.6, 0.2, 0.35))
	t.set_stylebox("panel", "PopupMenu", box("panel_tip", 8))
	t.set_stylebox("hover", "PopupMenu", box("btn_dark_hover", 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", box("panel_tip", 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box("scroll_track", 0.0))
		t.set_stylebox("grabber", cls, box("scroll_grabber", 0.0))
		t.set_stylebox("grabber_highlight", cls, box("scroll_grabber", 0.0, Color(1.25, 1.2, 1.1)))
		t.set_stylebox("grabber_pressed", cls, box("scroll_grabber", 0.0, Color(1.4, 1.3, 1.1)))
	t.set_stylebox("panel", "ItemList", box("field", 8))
	t.set_stylebox("selected", "ItemList", box("btn_dark_hover", 6))
	t.set_stylebox("selected_focus", "ItemList", box("btn_dark_hover", 6))
	t.set_stylebox("hovered", "ItemList", box("btn_dark_normal", 6))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", GOLD)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	_theme = t
	return t
