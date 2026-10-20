class_name PlayerPeek
extends Control
## A player's quick stats on hover in the hero pick (run 2026-10-20 e; the owner: "in the hero pick phase, you should be
## able to hover into player profiles to view a pop up of their quick stats and best heroes so you can have info on
## which heroes they are good at, their latest W/L in 5 games, etc."). Drawn, no input: picture, name, rank emblem,
## rank, MMR and place on the ladder; record and win rate, streak; the last five games (hero, won or lost, K/D/A, MVP);
## best heroes (most played, with wins, win rate and mastery medal); averages over the last 20 (K/D/A, KDA, last hits
## a minute, gold a minute); MVPs, Rampages, Triple Kills; for ladder players what they are known for and think of you.

const U = preload("res://src/ui/ui_kit.gd")
const S = preload("res://src/ui/social_ui.gd")
const PW := 470.0
const PH := 664.0

var p := {}
var _av: Avatar
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(PW, PH)
	_av = Avatar.new()
	_av.position = Vector2(20, 20)
	_av.size = Vector2(80, 80)
	_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_av)

func show_for(pp: Dictionary) -> void:
	p = pp
	_av.set_spec(p.get("avatar", {"k": "none"}))
	_t = 0.0
	visible = true
	queue_redraw()

func _process(dt: float) -> void:
	if visible:
		_t += dt
		if _t < 0.3:
			queue_redraw()

## The best heroes to show: most played first (at least one game), [hero, wins, losses].
static func best_heroes(pp: Dictionary, n := 3) -> Array:
	var rows: Array = Ranked.heroes_played(pp).filter(func(r): return int(r[1]) + int(r[2]) > 0)
	# a hero with a real sample and a good win rate ranks above one with a few more games and a poor one
	rows.sort_custom(func(a, b):
		var ga := float(int(a[1]) + int(a[2]))
		var gb := float(int(b[1]) + int(b[2]))
		return ga * (0.5 + float(a[1]) / ga) > gb * (0.5 + float(b[1]) / gb))
	return rows.slice(0, n)

func _draw() -> void:
	if p.is_empty():
		return
	var r := Rect2(Vector2.ZERO, size)
	U.skin(self, "soc_menu", r.grow(10))
	var a := clampf(_t / 0.12, 0.0, 1.0) if bool(Options.get_value("ui_motion")) else 1.0
	modulate.a = a
	var f := U.font("bold")
	var b := U.font("body")
	var tf := U.font("title")
	var you := String(p.get("id", "")) == "me"
	# ---- who
	draw_string(f, Vector2(116, 44), String(p.get("name", "")) + ("  (you)" if you else ""), HORIZONTAL_ALIGNMENT_LEFT, PW - 136, 22,
		U.GOLD if you else U.TEXT)
	var tier := Ranked.tier_for(p)
	var ic := RankEmblem.icon(tier)
	if ic:
		draw_texture_rect(ic, Rect2(110, 52, 54, 54), false)
	draw_string(b, Vector2(168, 74), Ranked.rank_label(p), HORIZONTAL_ALIGNMENT_LEFT, PW - 188, 17, U.GOLD)
	var place := Ranked.place_of(String(p.get("id", "")))
	var mm := "%s MMR" % RankedNum.num(int(p.get("mmr", 0)))
	if place > 0:
		mm += "  ·  #%s on the ladder" % RankedNum.num(place)
	draw_string(b, Vector2(168, 98), mm, HORIZONTAL_ALIGNMENT_LEFT, PW - 188, 16, U.TEXT)
	# ---- record
	var w := int(p.get("wins", 0))
	var l := int(p.get("losses", 0))
	var g := w + l
	var wr := Ranked.win_rate(p)
	draw_string(f, Vector2(20, 140), "%s W  -  %s L" % [RankedNum.num(w), RankedNum.num(l)], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.TEXT)
	draw_string(b, Vector2(230, 140), ("%.1f%% wins" % (wr * 100.0)) if g > 0 else "No games yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		S.GREEN_HI if wr > 0.52 and g > 0 else (S.RED if wr < 0.48 and g > 0 else U.TEXT_DIM))
	var st := int(p.get("streak", 0))
	if absi(st) >= 2:
		var sc := "%d win streak" % st if st > 0 else "%d losses in a row" % -st
		S.text_r(self, sc, PW - 20, 140, 15, S.GREEN_HI if st > 0 else S.RED)
	_line(156)
	# ---- the last five
	draw_string(b, Vector2(20, 180), "Last 5 games", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
	var ms := Career.matches(p).slice(0, 5)
	var w5 := 0
	for e in ms:
		w5 += 1 if String(e.get("r", "")) == "W" else 0
	if not ms.is_empty():
		S.text_r(self, "%d won, %d lost" % [w5, ms.size() - w5], PW - 20, 180, 15, S.GREEN_HI if w5 * 2 > ms.size() else (S.RED if w5 * 2 < ms.size() else U.TEXT))
	var cw := (PW - 40.0 - 4 * 8.0) / 5.0
	for i in 5:
		var cr := Rect2(20 + i * (cw + 8.0), 192, cw, 104)
		if i >= ms.size():
			draw_rect(cr, Color(1, 1, 1, 0.05))
			continue
		var e: Dictionary = ms[i]
		var won := String(e.get("r", "")) == "W"
		var left := String(e.get("r", "")) == "A"
		var band := S.GREEN if won else (Color(0.5, 0.5, 0.5) if left else S.RED)
		draw_rect(cr, Color(0.03, 0.035, 0.05, 0.9))
		var hr := Rect2(cr.position + Vector2((cw - 56) * 0.5, 6), Vector2(56, 56))
		var tex := U.hero_portrait(String(e.get("h", "")))
		if tex:
			draw_texture_rect(tex, hr, false)
		draw_rect(hr, Color(band, 0.9), false, 2.0)
		draw_rect(Rect2(cr.position.x, cr.end.y - 4, cr.size.x, 4), band)
		S.text_c(self, "W" if won else ("Left" if left else "L"), cr.get_center().x, cr.position.y + 80, 14, band, "bold")
		var kda := "%d/%d/%d" % [int(e.get("k", 0)), int(e.get("x", 0)), int(e.get("a", 0))] if e.has("k") else "-"
		S.text_c(self, kda, cr.get_center().x, cr.position.y + 96, 13, U.TEXT)
		if bool(e.get("mvp", false)):
			var mi := S.icon("mvp", true)
			if mi:
				draw_texture_rect(mi, Rect2(hr.end.x - 20, hr.position.y - 4, 22, 22), false)
	_line(310)
	# ---- best heroes
	draw_string(b, Vector2(20, 334), "Best heroes", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
	var best := best_heroes(p, 3)
	if best.is_empty():
		draw_string(b, Vector2(20, 362), "No hero games yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
	for i in best.size():
		var row: Array = best[i]
		var hero := String(row[0])
		var y := 346.0 + i * 52.0
		var tex2 := U.hero_portrait(hero)
		if tex2:
			draw_texture_rect(tex2, Rect2(20, y, 44, 44), false)
			draw_rect(Rect2(20, y, 44, 44), Color(1, 1, 1, 0.25), false, 1.0)
		var hg := int(row[1]) + int(row[2])
		var hwr := float(row[1]) / maxf(1.0, float(hg))
		draw_string(f, Vector2(74, y + 20), HeroDraft.hero_name(hero), HORIZONTAL_ALIGNMENT_LEFT, 190, 17, U.TEXT)
		draw_string(b, Vector2(74, y + 40), "%s games  ·  %s W - %s L" % [RankedNum.num(hg), RankedNum.num(int(row[1])), RankedNum.num(int(row[2]))],
			HORIZONTAL_ALIGNMENT_LEFT, 230, 14, U.TEXT_DIM)
		S.text_r(self, "%d%%" % int(round(hwr * 100.0)), PW - 84, y + 30, 20, S.GREEN_HI if hwr >= 0.55 else (S.RED if hwr < 0.45 else U.TEXT), "bold")
		var md := Ranked.hero_medal(p, hero)
		if int(md.get("medal", 0)) > 0:
			HeroBadge.paint(self, Rect2(PW - 72, y, 48, 48), hero, md, _t)
	_line(504)
	# ---- averages and trophies
	var av := Career.averages(p)
	draw_string(b, Vector2(20, 528), "Averages", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.TEXT_DIM)
	draw_string(f, Vector2(104, 528), Career.kda_text(av), HORIZONTAL_ALIGNMENT_LEFT, 170, 16, U.TEXT)
	var kd := float(av.get("kda", -1.0))
	if kd >= 0.0:
		S.text_r(self, "KDA %s" % S.dec(kd), PW - 20, 528, 16, S.GREEN_HI if kd >= 4.0 else (S.RED if kd < 2.0 else U.TEXT), "bold")
	var farm := "%s last hits a minute  ·  %s gold a minute" % [S.dec(float(av.get("lhm", -1.0))), S.whole(float(av.get("gpm", -1.0)))]
	draw_string(b, Vector2(20, 552), farm, HORIZONTAL_ALIGNMENT_LEFT, PW - 40, 14, U.TEXT)
	var mo := Career.moments(p)
	var tx := 20.0
	for t in [["mvp", int(mo.mvp), "MVPs"], ["rampage", int(mo.rp), "Rampages"], ["triple", int(mo.tr), "Triples"]]:
		var ic2 := S.icon(String(t[0]))
		if ic2:
			draw_texture_rect(ic2, Rect2(tx, 566, 30, 30), false)
		draw_string(f, Vector2(tx + 34, 588), RankedNum.num(int(t[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.GOLD if int(t[1]) > 0 else U.TEXT_DIM)
		draw_string(b, Vector2(tx + 34, 602), String(t[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, U.TEXT_DIM)
		tx += 148.0
	# ---- who they are to you
	var foot := ""
	if bool(p.get("bot", false)):
		var tags := Persona.labels(p)
		var y: Dictionary = p.get("you", {})
		foot = " · ".join(tags)
		if int(y.get("games", 0)) > 0:
			foot += ("  ·  " if foot != "" else "") + Persona.feeling(float(y.get("rep", 0.0)))
	elif Ranked.is_account(String(p.get("id", ""))):
		foot = "Another of your accounts"
	if foot != "":
		draw_string(b, Vector2(20, 628), foot, HORIZONTAL_ALIGNMENT_LEFT, PW - 40, 14, U.GOLD)
	draw_string(b, Vector2(20, 652), "Right-click for the profile and more", HORIZONTAL_ALIGNMENT_LEFT, PW - 40, 12, Color(U.TEXT_DIM, 0.75))

func _line(y: float) -> void:
	draw_line(Vector2(20, y), Vector2(PW - 20, y), Color(U.GOLD, 0.25), 1.0)
