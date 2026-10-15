class_name Scoreboard
extends Control
## Match tables drawn on demand: the scoreboard (hold Tab) with each hero's level, K / D / A, last hits and denies,
## net worth, gold and experience per minute, hero damage, building damage, damage taken and healing; a damage
## breakdown by source (attacks and each ability); and the death recap shown while your hero is dead (what hit you
## in your last 20 seconds of life, by enemy and source).

const U = preload("res://src/ui/ui_kit.gd")
const C = preload("res://src/sim/sim_const.gd")

var hud
var show_board := false
var recap: Array = []                      # [{who, key, type, amount}] sorted, frozen at the moment of death
var recap_killer := ""
var _recap_total := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	show_board = Keybinds.held("scoreboard") or OS.get_cmdline_user_args().has("--board")
	# only the board (Tab) or the death recap draws anything: redraw while one shows, and once when it goes
	var h: SimUnit = hud.hero() if hud else null
	var showing := show_board or (h != null and not h.alive and not recap.is_empty())
	if showing or _was_showing:
		queue_redraw()
	_was_showing = showing

var _was_showing := true

static func source_name(key: String) -> String:
	match key:
		"attack":
			return "Attacks"
		"spell", "":
			return "Spells"
	var a := SimData.ability(key)
	if not a.is_empty():
		return String(a.name)
	var it := SimData.item(key)
	if not it.is_empty():
		return String(it.name)
	return key.capitalize()

static func type_color(dtype: int) -> Color:
	match dtype:
		C.DamageType.MAGICAL:
			return Color(0.48, 0.62, 1.0)
		C.DamageType.PURE:
			return Color(1.0, 0.84, 0.36)
	return Color(0.95, 0.52, 0.38)

static func totals(h: SimUnit) -> Dictionary:
	var hero := 0.0
	var build := 0.0
	var units := 0.0
	for k in h.dmg_out:
		var r: Array = h.dmg_out[k]
		hero += float(r[0])
		units += float(r[1])
		build += float(r[2])
	var taken := 0.0
	for k in h.dmg_in:
		taken += float(h.dmg_in[k])
	return {"hero": hero, "units": units, "building": build, "taken": taken}

## Freeze what killed the player's hero: damage from the last 20 s, grouped by enemy and source.
func capture_recap(h: SimUnit, w: SimWorld) -> void:
	var groups := {}
	_recap_total = 0.0
	for r in h.recent_in:
		if w.time - float(r.t) > 20.0:
			continue
		var su := w.get_unit(int(r.src))
		var who: String = hud._name(su) if su else "Unknown"
		var k := who + "|" + String(r.key)
		if not groups.has(k):
			groups[k] = {"who": who, "key": String(r.key), "type": int(r.type), "amount": 0.0, "team": su.team if su else 2}
		groups[k].amount += float(r.amount)
		_recap_total += float(r.amount)
	recap = groups.values()
	recap.sort_custom(func(a, b): return a.amount > b.amount)
	var k := w.get_unit(h.killer_id)
	recap_killer = hud._name(k) if k else "Unknown"

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	UiKit.draw_cost("board", t0)

func _draw_body() -> void:
	var h: SimUnit = hud.hero()
	if h == null:
		return
	if show_board:
		_board()
	elif not h.alive and not recap.is_empty():
		_recap()

func _board() -> void:
	var w: SimWorld = hud.game.world
	var vs := get_viewport_rect().size
	var cols := [["Hero", 210], ["Lvl", 50], ["K / D / A", 100], ["LH / DN", 90], ["Net worth", 100], ["GPM", 64],
		["XPM", 64], ["Hero dmg", 92], ["Building dmg", 112], ["Taken", 80], ["Healing", 80]]
	var width := 0.0
	for c in cols:
		width += float(c[1])
	width += 40.0
	var heroes: Array = w.heroes.duplicate()
	heroes.sort_custom(func(a, b): return a.team < b.team)
	var rows := heroes.size()
	var bar_rows := 1
	for hh: SimUnit in heroes:
		bar_rows = maxi(bar_rows, mini(5, hh.dmg_out.size()))
	var r := Rect2(vs.x * 0.5 - width * 0.5, 120, width, 150 + rows * 34 + 70 + bar_rows * 24)
	U.panel(self, r, U.GOLD_DIM, 8)
	U.text(self, "Scoreboard", r.position + Vector2(20, 36), 26, U.GOLD, "title")
	U.text_r(self, "Game time " + w.clock_text(), Vector2(r.end.x - 20, r.position.y + 34), 16, U.TEXT_DIM, "bold")
	var x := r.position.x + 20.0
	var y := r.position.y + 76.0
	for c in cols:
		U.text(self, String(c[0]), Vector2(x, y), 14, U.GOLD, "bold")
		x += float(c[1])
	y += 12.0
	var minutes := maxf(w.time / 60.0, 0.25)
	for hh: SimUnit in heroes:
		y += 34.0
		var t := totals(hh)
		var band := Rect2(r.position.x + 12, y - 24, width - 24, 34)
		draw_rect(band, Color(U.DAWN if hh.team == 0 else U.DUSK, 0.10))
		draw_rect(Rect2(band.position, Vector2(4, band.size.y)), U.DAWN if hh.team == 0 else U.DUSK)
		var vals := [hud._name(hh) + "  (" + String(hh.def.name) + ")", str(hh.level),
			"%d / %d / %d" % [hh.kills, hh.deaths, hh.assists], "%d / %d" % [hh.last_hits, hh.denies],
			str(hh.networth()), str(int(_earned(hh) / minutes)), str(int(hh.xp / minutes)), str(int(t.hero)),
			str(int(t.building)), str(int(t.taken)), str(int(hh.healed))]
		x = r.position.x + 20.0
		for i in vals.size():
			U.text(self, String(vals[i]), Vector2(x, y), 15, U.TEXT if i > 0 else (U.DAWN if hh.team == 0 else U.DUSK), "bold")
			x += float(cols[i][1])
	# damage by source for every hero, as bars
	y += 40.0
	U.text(self, "Damage by source (to heroes, units and buildings)", Vector2(r.position.x + 20, y), 16, U.GOLD, "bold")
	y += 12.0
	var colw := (width - 60.0) / maxf(1.0, heroes.size())
	for i in heroes.size():
		var hh: SimUnit = heroes[i]
		_breakdown(hh, Vector2(r.position.x + 20 + i * (colw + 20.0), y + 8), colw)

func _earned(h: SimUnit) -> float:
	return float(h.gold_earned)

## Up to five bars: the hero's damage dealt by source, longest first.
func _breakdown(h: SimUnit, at: Vector2, width: float) -> void:
	var keys := h.dmg_out.keys()
	var sums := {}
	var best := 1.0
	for k in keys:
		var r: Array = h.dmg_out[k]
		sums[k] = float(r[0]) + float(r[1]) + float(r[2])
		best = maxf(best, sums[k])
	keys.sort_custom(func(a, b): return sums[a] > sums[b])
	U.text(self, hud._name(h), at + Vector2(0, 14), 15, U.DAWN if h.team == 0 else U.DUSK, "bold")
	var y := at.y + 26.0
	for k in keys.slice(0, 5):
		var frac: float = sums[k] / best
		var a := SimData.ability(k)
		var dt := C.DamageType.PHYSICAL
		if not a.is_empty():
			dt = {"magical": C.DamageType.MAGICAL, "pure": C.DamageType.PURE}.get(String(a.get("damage_type", "")), C.DamageType.MAGICAL)
		var bar := Rect2(at.x, y, (width - 10.0) * frac, 18)
		draw_rect(Rect2(at.x, y, width - 10.0, 18), Color(0, 0, 0, 0.35))
		draw_rect(bar, Color(type_color(dt), 0.75))
		U.text(self, "%s  %d" % [source_name(k), int(sums[k])], Vector2(at.x + 6, y + 14), 13, U.TEXT, "bold")
		y += 24.0

func _recap() -> void:
	var vs := get_viewport_rect().size
	var n := mini(recap.size(), 7)
	var r := Rect2(vs.x - 430, 260, 410, 96 + n * 30)
	U.panel(self, r, Color(0.6, 0.2, 0.18), 8)
	U.text(self, "Killed by " + recap_killer, r.position + Vector2(18, 34), 22, U.DUSK, "title")
	U.text_r(self, "%d damage taken in your last 20 s" % int(_recap_total), Vector2(r.end.x - 18, r.position.y + 58), 13, U.TEXT_DIM, "body")
	var y := r.position.y + 90.0
	for i in n:
		var g: Dictionary = recap[i]
		var frac := float(g.amount) / maxf(1.0, _recap_total)
		draw_rect(Rect2(r.position.x + 16, y - 16, (r.size.x - 32) * frac, 22), Color(type_color(int(g.type)), 0.35))
		U.text(self, "%s  %s" % [String(g.who), source_name(String(g.key))], Vector2(r.position.x + 22, y), 15,
			U.DAWN if int(g.team) == 0 else (U.DUSK if int(g.team) == 1 else U.TEXT), "bold")
		U.text_r(self, str(int(g.amount)), Vector2(r.end.x - 22, y), 15, type_color(int(g.type)), "bold")
		y += 30.0
