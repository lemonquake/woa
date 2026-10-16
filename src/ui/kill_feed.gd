class_name KillFeed
extends Control
## The kill log (left side, like Dota): hero kills, first blood, streaks and shutdowns, buildings falling, couriers
## and denies, each line fading after ten seconds, with a light sweeping over each new line. Also the big centre
## announcements ("First Blood!", "Killing Spree", "Shutdown!") with a punch-in and slide-out; a hero kill shows as a
## kill card: both portraits slide in, a blade slash cuts across the fallen hero, a few sparks fly from the blade, a
## light sweeps the band and the gold counts up. Short and quiet enough not to pull the eye from the fight.

const U = preload("res://src/ui/ui_kit.gd")
const LIFE := 10.0
const MAX_LINES := 7
const STREAKS := {3: "Killing Spree", 4: "Dominating", 5: "Rampaging", 6: "Unstoppable", 7: "Merciless",
	8: "Ruthless", 9: "Godlike"}
const MULTI := {2: "Double Kill", 3: "Triple Kill", 4: "Ultra Kill", 5: "Rampage"}

var hud
var lines: Array = []                      # {t, parts: [[text, colour]], icon}
var _banner := {}                          # {title, sub, col, t}
var _queue: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func add_line(parts: Array, icon := "items/dagger_2") -> void:
	lines.append({"t": 0.0, "parts": parts, "icon": icon})
	while lines.size() > MAX_LINES:
		lines.pop_front()

## A big centre message; queued so two kills in a row do not overwrite each other. `kill` (optional) makes it a kill
## card: {killer, victim (unit ids), k_hero, v_hero (hero ids), k_team, v_team, k_parts, v_parts (who_parts), gold, mine}.
func banner(title: String, sub: String, col: Color, dur := 3.2, kill := {}) -> void:
	_queue.append({"title": title, "sub": sub, "col": col, "t": 0.0, "dur": dur, "kill": kill})
	# a backlog never holds the screen for long: the oldest waiting messages are dropped first
	while _queue.size() > 3:
		_queue.pop_front()
	if _banner.is_empty():
		_banner = _queue.pop_front()

func _process(dt: float) -> void:
	for l in lines:
		l.t += dt
	lines = lines.filter(func(l): return l.t < LIFE)
	if not _banner.is_empty():
		_banner.t += dt
		# a waiting message shortens the current one (a teamfight's kills follow each other quickly)
		if _banner.t >= _limit(_banner):
			_banner = _queue.pop_front() if not _queue.is_empty() else {}
	# redraw while something shows (lines fade and slide), once more when the last one goes, never when empty
	var showing := not lines.is_empty() or not _banner.is_empty()
	if showing or _was_showing:
		queue_redraw()
	_was_showing = showing

var _was_showing := true

func _limit(b: Dictionary) -> float:
	return float(b.dur) if _queue.is_empty() else minf(float(b.dur), 1.9)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	UiKit.draw_cost("feed", t0)

func _draw_body() -> void:
	var vs := get_viewport_rect().size
	var y := 196.0
	for l in lines:
		var a := clampf((LIFE - l.t) / 1.0, 0.0, 1.0) * clampf(l.t / 0.15, 0.0, 1.0)
		var slide := (1.0 - clampf(l.t / 0.2, 0.0, 1.0)) * -40.0
		var x := 12.0 + slide
		var w := 26.0
		for part in l.parts:
			if part.size() > 2 and part[2] == "icon":
				w += 30.0
			else:
				w += U.font("bold").get_string_size(String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 8.0
		var r := Rect2(x, y - 20, w + 12, 28)
		draw_rect(r, Color(0.03, 0.03, 0.05, 0.72 * a))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(U.GOLD, a))
		if l.t < 0.6:
			# a new line: a soft light runs across it once
			var sx: float = r.position.x + (r.size.x + 60.0) * (l.t / 0.6) - 30.0
			draw_colored_polygon(PackedVector2Array([Vector2(sx - 34.0, r.end.y), Vector2(sx, r.end.y),
				Vector2(sx + 14.0, r.position.y), Vector2(sx - 20.0, r.position.y)]),
				Color(1.0, 0.95, 0.8, 0.16 * (1.0 - l.t / 0.6)))
		var cx := x + 10.0
		for part in l.parts:
			var col: Color = part[1]
			col.a *= a
			if part.size() > 2 and part[2] == "icon":
				var ic: Texture2D = U.icon(String(part[0]))
				if ic:
					draw_texture_rect(ic, Rect2(cx, y - 17, 22, 22), false, Color(1, 1, 1, a))
				cx += 30.0
			else:
				U.text(self, String(part[0]), Vector2(cx, y), 16, col, "bold")
				cx += U.font("bold").get_string_size(String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 8.0
		y += 32.0
	if not _banner.is_empty() and not (_banner.get("kill", {}) as Dictionary).is_empty():
		_draw_kill_card(vs)
	elif not _banner.is_empty():
		var t: float = _banner.t
		var dur: float = _limit(_banner)
		var a2 := clampf(t / 0.12, 0.0, 1.0) * clampf((dur - t) / 0.5, 0.0, 1.0)
		var punch := 1.0 + 0.35 * exp(-t * 9.0)
		var size := int(round(46.0 * punch))
		var col2: Color = _banner.col
		col2.a = a2
		var cy := 150.0 - (1.0 - clampf((dur - t) / 0.5, 0.0, 1.0)) * 20.0
		# a dark band behind the words so they read over any scene
		var bw := 720.0
		draw_rect(Rect2(vs.x * 0.5 - bw * 0.5, cy - 50, bw, 88), Color(0, 0, 0, 0.35 * a2))
		draw_rect(Rect2(vs.x * 0.5 - bw * 0.5, cy - 50, bw, 2), Color(col2.r, col2.g, col2.b, 0.7 * a2))
		draw_rect(Rect2(vs.x * 0.5 - bw * 0.5, cy + 36, bw, 2), Color(col2.r, col2.g, col2.b, 0.7 * a2))
		U.text_c(self, String(_banner.title), Vector2(vs.x * 0.5, cy), size, col2, "title")
		if String(_banner.sub) != "":
			U.text_c(self, String(_banner.sub), Vector2(vs.x * 0.5, cy + 28), 19, Color(0.95, 0.95, 0.95, a2), "bold")

## The kill card (see the class comment). Times in seconds from its start; everything eases, nothing loops.
func _draw_kill_card(vs: Vector2) -> void:
	var b := _banner
	var k: Dictionary = b.kill
	var t: float = b.t
	var dur := _limit(b)
	var fade_out := clampf((dur - t) / 0.4, 0.0, 1.0)
	var a := clampf(t / 0.1, 0.0, 1.0) * fade_out
	var col: Color = b.col
	var cx := vs.x * 0.5
	var cy := 196.0 - (1.0 - fade_out) * 18.0
	# the band opens out from the middle
	var bw := 620.0 * _ease_out_back(clampf(t / 0.28, 0.0, 1.0))
	var band := Rect2(cx - bw * 0.5, cy - 54, bw, 112)
	draw_rect(band, Color(0.0, 0.0, 0.0, 0.42 * a))
	for edge in [band.position.y, band.end.y - 2.0]:
		draw_rect(Rect2(band.position.x, edge, band.size.x, 2), Color(col.r, col.g, col.b, 0.75 * a))
	# a light sweeps across the band once
	if t > 0.3 and t < 1.1:
		var f := (t - 0.3) / 0.8
		var sx := band.position.x + band.size.x * f
		draw_colored_polygon(PackedVector2Array([Vector2(sx - 70, band.end.y), Vector2(sx - 10, band.end.y),
			Vector2(sx + 30, band.position.y), Vector2(sx - 30, band.position.y)]),
			Color(1, 0.96, 0.85, 0.10 * sin(PI * f) * a))
	# the title above (First Blood!, Shutdown!, Double Kill) when there is one
	if String(b.title) != "":
		var punch := 1.0 + 0.3 * exp(-t * 9.0)
		var c2 := col
		c2.a = a
		U.text_c(self, String(b.title), Vector2(cx, cy - 68), int(round(34.0 * punch)), c2, "title")
	# portraits slide in from the sides
	var ps := 64.0
	var slide := _ease_out_cubic(clampf((t - 0.05) / 0.3, 0.0, 1.0))
	var kp := Vector2(cx - 150.0 - (1.0 - slide) * 120.0, cy - 40.0)
	var vp := Vector2(cx + 150.0 - ps + (1.0 - slide) * 120.0, cy - 40.0)
	var hit := 0.38                                   # the blow lands
	_portrait(String(k.k_hero), Rect2(kp, Vector2(ps, ps)), a * slide, U.team_color(int(k.k_team)), 0.0)
	var dead := clampf((t - hit) / 0.7, 0.0, 1.0) if t > hit else 0.0
	_portrait(String(k.v_hero), Rect2(vp, Vector2(ps, ps)), a * slide, U.team_color(int(k.v_team)), dead)
	if t > hit:
		# the slash: a bright diagonal cut across the fallen hero, drawn in quickly, then dimming to a red scar
		var cut := clampf((t - hit) / 0.12, 0.0, 1.0)
		var fade := clampf(1.0 - (t - hit - 0.12) / 0.9, 0.35, 1.0)
		var p0 := vp + Vector2(-6, ps + 6)
		var pe := p0.lerp(vp + Vector2(ps + 6, -6), cut)
		draw_line(p0, pe, Color(1.0, 0.25, 0.2, 0.9 * fade * a), 5.0)
		draw_line(p0, pe, Color(1.0, 0.95, 0.85, 0.9 * fade * a * (1.0 - dead * 0.7)), 1.6)
		var flash := clampf(1.0 - (t - hit) / 0.18, 0.0, 1.0)
		if flash > 0.0:
			draw_rect(Rect2(vp, Vector2(ps, ps)), Color(1, 1, 1, 0.45 * flash * a))
	# the blade between them pops when the blow lands; a few sparks fly off it
	var pop := (1.0 + 0.45 * exp(-(t - hit) * 10.0)) if t > hit else 0.8 + 0.2 * slide
	var isz := 34.0 * pop
	var ctr := Vector2(cx, cy - 8.0)
	var dia := PackedVector2Array([ctr + Vector2(0, -isz * 0.75), ctr + Vector2(isz * 0.75, 0),
		ctr + Vector2(0, isz * 0.75), ctr + Vector2(-isz * 0.75, 0)])
	draw_colored_polygon(dia, Color(0.05, 0.04, 0.05, 0.9 * a))
	dia.append(dia[0])
	draw_polyline(dia, Color(U.GOLD, 0.9 * a), 1.5)
	var ic := U.icon("items/dagger_2")
	if ic:
		draw_texture_rect(ic, Rect2(ctr - Vector2(isz, isz) * 0.42, Vector2(isz, isz) * 0.84), false, Color(1, 1, 1, a))
	if t > hit and t < hit + 0.6:
		var st := (t - hit) / 0.6
		for i in 9:
			var ang := -PI * 0.5 + (float(i) - 4.0) * 0.36 + (0.0 if i % 2 == 0 else PI)
			var d0 := 18.0 + 46.0 * _ease_out_cubic(st)
			var dv := Vector2.from_angle(ang)
			draw_line(ctr + dv * d0, ctr + dv * (d0 + 12.0 * (1.0 - st)), Color(1.0, 0.85, 0.45, (1.0 - st) * a), 2.0)
	# names under the portraits: the player in their colour, the hero in its team's
	_parts_c(k.k_parts, Vector2(kp.x + ps * 0.5, cy + 46.0), a * slide)
	_parts_c(k.v_parts, Vector2(vp.x + ps * 0.5, cy + 46.0), a * slide)
	# your team's gold, counting up after the blow; otherwise the subtitle
	if int(k.get("gold", 0)) > 0 and bool(k.get("mine", false)):
		if t > hit + 0.1:
			var g := int(round(float(k.gold) * _ease_out_cubic(clampf((t - hit - 0.1) / 0.6, 0.0, 1.0))))
			U.text_c(self, "+%d gold" % g, Vector2(cx, cy + 30.0), 17, Color(U.GOLD, a), "bold")
	elif String(b.sub) != "":
		U.text_c(self, String(b.sub), Vector2(cx, cy + 30.0), 15, Color(0.92, 0.92, 0.92, a), "bold")

func _portrait(hero: String, r: Rect2, a: float, rim: Color, dead: float) -> void:
	draw_rect(r.grow(2.0), Color(rim.r, rim.g, rim.b, 0.9 * a))
	draw_rect(r, Color(0.02, 0.02, 0.03, a))
	var tex := U.hero_portrait(hero)
	if tex:
		# the fallen hero greys and darkens toward red
		var m := Color.WHITE.lerp(Color(0.55, 0.38, 0.38), dead)
		m.a = a
		draw_texture_rect(tex, r, false, m)

func _parts_c(parts: Array, at: Vector2, a: float) -> void:
	var f := U.font("bold")
	var w := -6.0
	for pt in parts:
		w += f.get_string_size(String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 6.0
	var x := at.x - w * 0.5
	for pt in parts:
		var c: Color = (pt[1] as Color).lightened(0.15)
		c.a = a
		U.text(self, String(pt[0]), Vector2(x, at.y), 16, c, "bold")
		x += f.get_string_size(String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 6.0

static func _ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func _ease_out_back(x: float) -> float:
	return 1.0 + 2.4 * pow(x - 1.0, 3.0) + 1.4 * pow(x - 1.0, 2.0)

# ---- Events ---------------------------------------------------------------------------------------------------------

func _team_col(team: int) -> Color:
	return U.DAWN if team == 0 else (U.DUSK if team == 1 else Color(0.95, 0.8, 0.4))

func _name(u: SimUnit) -> String:
	return hud._name(u)

func on_hero_kill(e: Dictionary, w: SimWorld, player_team: int) -> void:
	var victim := w.get_unit(e.victim)
	var killer := w.get_unit(e.u)
	if victim == null:
		return
	var vn := _name(victim)
	var mine := killer != null and killer.team == player_team
	var col := U.GOLD if mine else U.DUSK
	if killer == null:
		var ku := w.get_unit(int(e.get("killer_unit", -1)))
		var by := ku.name if ku else "the enemy"
		add_line([[by, _team_col(ku.team if ku else 2)], ["status/marked", Color.WHITE, "icon"]] + U.who_parts(victim))
		banner("%s was killed" % vn, "by %s" % by, col)
		return
	var kn := _name(killer)
	var kparts := U.who_parts(killer)
	var vparts := U.who_parts(victim)
	var parts: Array = kparts + [["items/dagger_2", Color.WHITE, "icon"]] + vparts
	if e.get("first_blood", false):
		parts.append(["First Blood", U.GOLD])
	add_line(parts)
	var ended := int(e.get("ended_streak", 0))
	var streak := int(e.get("streak", 0))
	var multi := int(e.get("multi", 0))
	var gold := int(e.get("gold", 0))
	# one card per kill with the biggest title it earned (first blood, shutdown, multi-kill); streak news after it
	var title := ""
	var sub := ""
	if e.get("first_blood", false):
		title = "First Blood!"
		sub = "%s drew first blood on %s" % [kn, vn]
	elif ended >= 3:
		title = "Shutdown!"
		sub = "%s ended %s's %s  (+%d gold)" % [kn, vn, String(STREAKS.get(mini(ended, 9), "Killing Spree")), gold]
	elif MULTI.has(mini(multi, 5)) and multi >= 2:
		title = String(MULTI[mini(multi, 5)])
		sub = kn
	if killer.is_hero():
		banner(title, "" if mine else sub, col, 2.8, {"killer": killer.id, "victim": victim.id,
			"k_hero": String(killer.def.id), "v_hero": String(victim.def.id), "k_team": killer.team,
			"v_team": victim.team, "k_parts": kparts, "v_parts": vparts, "gold": gold, "mine": mine})
	else:
		banner(title if title != "" else "%s killed %s" % [kn, vn], sub if sub != "" else ("+%d gold" % gold if mine else ""),
			col, 2.6)
	if streak >= 3:
		var st := String(STREAKS.get(streak, "Legendary"))
		banner(st, "%s is on a %d kill streak" % [kn, streak], col, 2.4)
		add_line(kparts + [["is " + st.to_lower() if streak < 10 else "is legendary", U.GOLD]], "status/frenzy")

func on_building(du: SimUnit, killer: SimUnit, deny: bool, player_team: int, what: String) -> void:
	var side_col := _team_col(du.team)
	if deny:
		add_line([[what, side_col], ["was denied", U.TEXT_DIM]], "ui/level")
	else:
		var kn: String = _name(killer) if killer else String(SimConst.TEAM_NAMES[1 - du.team])
		var kc := _team_col(killer.team if killer else 1 - du.team)
		add_line([[kn, kc], ["status/sundered", Color.WHITE, "icon"], [what, side_col]], "ui/shop")

func on_courier(dead: SimUnit, killer: SimUnit) -> void:
	add_line([[_name(killer) if killer else "?", _team_col(killer.team if killer else 2)], ["items/dagger_2", Color.WHITE, "icon"],
		["Courier", _team_col(dead.team)]])

func on_deny_hero(victim: SimUnit) -> void:
	add_line(U.who_parts(victim) + [["was denied", U.TEXT_DIM]])
