class_name KillFeed
extends Control
## The kill log (left side, like Dota): hero kills, first blood, streaks and shutdowns, buildings falling, couriers
## and denies, each line fading after ten seconds. Also the big centre announcements ("First Blood!", "Killing
## Spree", "Shutdown!") with a punch-in and slide-out.

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

## A big centre message; queued so two kills in a row do not overwrite each other.
func banner(title: String, sub: String, col: Color, dur := 3.2) -> void:
	_queue.append({"title": title, "sub": sub, "col": col, "t": 0.0, "dur": dur})
	if _banner.is_empty():
		_banner = _queue.pop_front()

func _process(dt: float) -> void:
	for l in lines:
		l.t += dt
	lines = lines.filter(func(l): return l.t < LIFE)
	if not _banner.is_empty():
		_banner.t += dt
		if _banner.t >= _banner.dur:
			_banner = _queue.pop_front() if not _queue.is_empty() else {}
	queue_redraw()

func _draw() -> void:
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
	if not _banner.is_empty():
		var t: float = _banner.t
		var dur: float = _banner.dur
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
		add_line([[by, _team_col(ku.team if ku else 2)], ["status/marked", Color.WHITE, "icon"], [vn, _team_col(victim.team)]])
		banner("%s was killed" % vn, "by %s" % by, col)
		return
	var kn := _name(killer)
	var parts := [[kn, _team_col(killer.team)], ["items/dagger_2", Color.WHITE, "icon"], [vn, _team_col(victim.team)]]
	if e.get("first_blood", false):
		parts.append(["First Blood", U.GOLD])
	add_line(parts)
	var ended := int(e.get("ended_streak", 0))
	var streak := int(e.get("streak", 0))
	var multi := int(e.get("multi", 0))
	var gold := int(e.get("gold", 0))
	if e.get("first_blood", false):
		banner("First Blood!", "%s drew first blood on %s" % [kn, vn], col)
	elif ended >= 3:
		var what := String(STREAKS.get(mini(ended, 9), "Killing Spree"))
		banner("Shutdown!", "%s ended %s's %s  (+%d gold)" % [kn, vn, what, gold], col)
	if MULTI.has(mini(multi, 5)) and multi >= 2:
		banner(String(MULTI[mini(multi, 5)]), kn, col, 2.4)
	if streak >= 3:
		var title := String(STREAKS.get(streak, "Legendary"))
		banner(title, "%s is on a %d kill streak" % [kn, streak], col, 2.8)
		add_line([[kn, _team_col(killer.team)], ["is " + title.to_lower() if streak < 10 else "is legendary", U.GOLD]], "status/frenzy")
	elif not e.get("first_blood", false) and ended < 3:
		banner("%s killed %s" % [kn, vn], "+%d gold" % gold if mine else "", col, 2.6)

func on_building(du: SimUnit, killer: SimUnit, deny: bool, player_team: int, what: String) -> void:
	var side_col := _team_col(du.team)
	if deny:
		add_line([[what.capitalize(), side_col], ["was denied", U.TEXT_DIM]], "ui/level")
	else:
		var kn := _name(killer) if killer else ("Dusk" if du.team == 0 else "Dawn")
		var kc := _team_col(killer.team if killer else 1 - du.team)
		add_line([[kn, kc], ["ui/shop", Color.WHITE, "icon"], [what.capitalize(), side_col]], "ui/shop")

func on_courier(dead: SimUnit, killer: SimUnit) -> void:
	add_line([[_name(killer) if killer else "?", _team_col(killer.team if killer else 2)], ["items/dagger_2", Color.WHITE, "icon"],
		["Courier", _team_col(dead.team)]])

func on_deny_hero(victim: SimUnit) -> void:
	add_line([[_name(victim), _team_col(victim.team)], ["was denied", U.TEXT_DIM]])
