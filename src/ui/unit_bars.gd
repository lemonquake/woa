class_name UnitBars
extends Control
## Health bars above every visible unit, drawn in screen space like Dota: thin dark frames, green for your side,
## red for enemies, gold-brown for neutrals; heroes get a wider bar with 250-health ticks, a mana bar and a level
## badge; buildings a long bar. A unit under a timed disable (stun, bash, hex, silence, root, disarm, break, mute) gets
## a timer bar under its health that empties as the disable runs out, with its name and the seconds left. Also draws
## floating combat text (gold, denies, misses, critical strikes).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var game: Node                             # Main
var font: Font
var popups: Array = []                     # [{text, pos, t, color, size, rise, life, drift, pop}]
var _texts: Array = []                     # deferred labels: [font, pos, text, size, outline, colour]
var _ghost := {}                           # unit id -> [shown health fraction, time it last dropped]
var _icons: Array = []                     # deferred status icons: [texture, rect, remaining fraction]
var _mod_seen := {}                        # "unit:modifier:expiry" -> game time first seen (icon timers)

const STATUS_ICONS := {"stun": "status/stunned", "slow": "status/slowed", "frost": "status/chilled",
	"curse": "status/cursed", "taint": "status/empowered", "unholy": "status/titan", "fatigue": "status/weakened",
	"heal": "status/regen", "mana": "status/arcane_charge", "berserk": "status/frenzy", "slip": "status/haste",
	"spell_shield": "status/rune_immune", "corruption": "status/armor_broken", "spikes": "status/aura_thorns",
	"sneak": "status/stealth", "blubber": "status/fortified", "silence": "status/silenced", "root": "status/webbed",
	"disarm": "status/sundered", "hex": "status/enfeebled", "break": "status/staggered", "weakened": "status/demoralized",
	"fountain": "status/aura_mending", "dust": "status/dazzled", "haste": "status/haste", "orb_damage": "status/valor",
	"orb_magic": "status/overcharged", "orb_shield": "status/shielded", "burn": "status/burning",
	"ember_mark": "status/marked", "time_slow": "status/slowed", "stop_time": "status/frozen",
	"fast_forward": "status/haste", "magnet": "status/overcharged", "magnet_field": "status/shocked",
	"static": "status/shocked", "guard": "status/guard", "chill": "status/chilled"}

## Timer bar colours by disable (Dota's overhead bars: stuns white-gold, the rest in their debuff's colour).
const DISABLE_COLORS := {"Stunned": Color(1.0, 0.86, 0.35), "Frosted": Color(0.55, 0.85, 1.0), "Hexed": Color(0.45, 1.0, 0.45),
	"Silenced": Color(0.72, 0.45, 1.0), "Rooted": Color(0.55, 0.85, 0.3), "Disarmed": Color(1.0, 0.58, 0.2),
	"Broken": Color(1.0, 0.35, 0.3), "Muted": Color(0.75, 0.75, 0.8)}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func popup(text: String, at: Vector3, color: Color, size := 18, rise := 1.2, life := 1.3, drift := Vector2.ZERO,
		pop := false) -> void:
	popups.append({"text": text, "pos": at, "t": 0.0, "color": color, "size": size, "rise": rise, "life": life,
		"drift": drift, "pop": pop})
	if popups.size() > 90:
		popups.pop_front()

const DMG_COLORS := [Color(1.0, 0.86, 0.62), Color(0.5, 0.68, 1.0), Color(1.0, 0.86, 0.32)]

## Floating damage numbers. style: "out" (dealt by your hero), "in" (taken by your hero), "spell" (other heroes'
## spells you can see), "reflect" (Unholy Might's deflected half).
var _stack := {}                           # target key -> [time of last number, how many stacked]

var _merge := {}                            # target:style:source -> {p: the live popup, at: last hit time}

func damage_number(amount: float, dtype: int, at: Vector3, style: String, target := -1, src_key := "") -> void:
	if amount < 0.5 or not bool(Options.get_value("damage_numbers")):
		return
	var now := Time.get_ticks_msec() / 1000.0
	# rapid hits from one spell on one unit (Burst Shot's arrows) count up in a single number that pops on each hit
	if src_key != "" and src_key != "attack":
		var mk := "%d:%s:%s" % [target, style, src_key]
		var live = _merge.get(mk)
		if live != null and now - float(live.at) < 0.6 and popups.has(live.p):
			var mp: Dictionary = live.p
			mp.amount = float(mp.amount) + amount
			mp.text = ("-" if style == "in" else "") + str(int(round(float(mp.amount))))
			mp.size = int(clampf(15.0 + log(float(mp.amount) + 1.0) * 2.6, 16.0, 34.0)) if style != "in" else mp.size
			mp.t = minf(float(mp.t), 0.12)
			mp.pos = at
			live.at = now
			return
	# numbers on the same unit in quick succession stack upwards instead of overprinting each other
	var key := "%d:%s" % [target, style]
	var st: Array = _stack.get(key, [-9.0, 0])
	var level: int = st[1] + 1 if now - float(st[0]) < 0.35 else 0
	_stack[key] = [now, level]
	var n := int(round(amount))
	var size := int(clampf(15.0 + log(amount + 1.0) * 2.6, 16.0, 32.0))
	var col: Color = DMG_COLORS[clampi(dtype, 0, 2)]
	var drift := Vector2(randf_range(-26.0, 26.0), 0.0)
	var text := str(n)
	match style:
		"in":
			col = Color(1.0, 0.32, 0.26)
			size = int(size * 0.85)
			drift = Vector2(randf_range(-48.0, -18.0), 6.0)
			text = "-" + text
		"spell":
			size = int(size * 0.85)
		"reflect":
			col = Color(0.78, 0.45, 1.0)
	var pd := {"text": text, "pos": at, "t": 0.0, "color": col, "size": size, "rise": 1.1, "life": 1.05,
		"drift": drift, "pop": true, "offset": Vector2(0, -level * (size + 2)), "amount": amount}
	popups.append(pd)
	if src_key != "" and src_key != "attack":
		_merge["%d:%s:%s" % [target, style, src_key]] = {"p": pd, "at": now}
		if _merge.size() > 48:
			for k in _merge.keys():
				if now - float(_merge[k].at) > 1.0:
					_merge.erase(k)
	if popups.size() > 90:
		popups.pop_front()

func _process(dt: float) -> void:
	for p in popups:
		p.t += dt
	popups = popups.filter(func(p): return p.t < p.life)
	queue_redraw()

static var cost_us := 0                     # benchmark: total time spent drawing bars and text

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_all()
	cost_us += Time.get_ticks_usec() - t0

func _draw_all() -> void:
	if game == null or game.world == null:
		return
	var cam: Camera3D = game.camera.cam
	var w: SimWorld = game.world
	var my_team: int = game.player_team
	var vp := get_viewport_rect().size
	_texts.clear()
	for v in game.views.values():
		var u: SimUnit = w.get_unit(v.uid)
		if u == null or not u.alive or not v.visible:
			continue
		if u.kind == K.WARD or u.has_flag("hidden"):
			continue
		var top: Vector3 = v.global_position + Vector3(0, v.bar_height, 0)
		if cam.is_position_behind(top):
			continue
		var s := cam.unproject_position(top)
		if s.x < -100 or s.y < -50 or s.x > vp.x + 100 or s.y > vp.y + 50:
			continue
		_bar(u, s, my_team)
	for ic in _icons:
		var rr: Rect2 = ic[1]
		draw_rect(rr.grow(1.0), Color(0, 0, 0, 0.8))
		draw_texture_rect(ic[0], rr, false, Color(1, 1, 1))
		if float(ic[2]) < 1.0:
			draw_rect(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * (1.0 - float(ic[2])))), Color(0, 0, 0, 0.55))
	_icons.clear()
	# text after every rectangle, so the renderer can batch each kind together
	for t in _texts:
		draw_string_outline(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[4], Color(0, 0, 0, 0.9))
	for t in _texts:
		draw_string(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[5])
	var dr: Rect2 = game.input.drag_rect if game.input else Rect2()
	if dr.size.x > 1.0 and dr.size.y > 1.0:
		draw_rect(dr, Color(0.25, 1.0, 0.35, 0.10))
		draw_rect(dr, Color(0.35, 1.0, 0.45, 0.9), false, 1.5)
	var pf := UiKit.font("bold")
	for p in popups:
		var k: float = p.t / p.life
		# rise fast then settle (ease out), pop in big, fade over the last third
		var pos: Vector3 = p.pos + Vector3(0, (1.0 - pow(1.0 - k, 2.2)) * p.rise, 0)
		if cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos) + (p.drift as Vector2) * k + (p.get("offset", Vector2.ZERO) as Vector2)
		var a := 1.0 - smoothstep(0.62, 1.0, k)
		var col: Color = p.color
		col.a = a
		var scale := 1.0 + (0.55 * exp(-p.t * 16.0) if p.pop else 0.0)
		var sz := int(round(p.size * scale))
		var tw := pf.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string_outline(pf, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, a * 0.9))
		draw_string(pf, sp + Vector2(-tw * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

## The disable timer under a unit's bars: it empties as the stun (or hex, silence, root...) runs out, with the
## disable's name and the seconds left beside it. Returns the height it used (0 when the unit is free).
func _disable_bar(u: SimUnit, r: Rect2, big: bool) -> float:
	var info: Dictionary = game.world.status.disable_info(u)
	if info.is_empty():
		return 0.0
	var kind := String(info.kind)
	var col: Color = DISABLE_COLORS.get(kind, Color(1, 1, 1))
	var k := clampf(float(info.left) / maxf(0.05, float(info.total)), 0.0, 1.0)
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.9))
	draw_rect(r, col.darkened(0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y * 0.4)), Color(1, 1, 1, 0.3))
	var label := ("Bashed" if bool(info.get("bash", false)) else kind) + " %.1f" % float(info.left)
	var f := UiKit.font("bold")
	var size := 13 if big else 11
	_texts.append([f, Vector2(r.end.x + 5, r.position.y + r.size.y * 0.5 + size * 0.36), label, size, 4, col.lightened(0.25)])
	return r.size.y + 6.0

## Small icons under a hero's bars for what affects it, darkened as their time runs out.
func _status_icons(u: SimUnit, at: Vector2) -> void:
	var x := at.x
	var shown := {}
	var now: float = game.world.time
	for m in u.modifiers:
		var key := String(m.get("fx", ""))
		if key == "" and float(m.get("slow", 0.0)) > 0.0:
			key = "slow"
		if key == "" or shown.has(key) or not STATUS_ICONS.has(key):
			continue
		shown[key] = true
		var tex: Texture2D = UiKit.icon(STATUS_ICONS[key])
		if tex == null:
			continue
		var left := 1.0
		var exp_t := float(m.get("expires", INF))
		if is_finite(exp_t):
			var mk := "%d:%s:%.2f" % [u.id, String(m.id), exp_t]
			if not _mod_seen.has(mk):
				if _mod_seen.size() > 400:
					_mod_seen.clear()
				_mod_seen[mk] = now
			var total := maxf(0.1, exp_t - float(_mod_seen[mk]))
			left = clampf((exp_t - now) / total, 0.0, 1.0)
		_icons.append([tex, Rect2(x, at.y, 16, 16), left])
		x += 19.0

func _bar(u: SimUnit, s: Vector2, my_team: int) -> void:
	var width := 46.0
	var height := 5.0
	if u.is_hero():
		width = 92.0
		height = 9.0
	elif u.is_building():
		width = 120.0 if u.kind != K.ANCIENT else 170.0
		height = 9.0
	elif u.kind == K.CREEP_SIEGE:
		width = 60.0
	var frac := clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0)
	var col: Color
	if u.team == C.NEUTRAL:
		col = Color(0.85, 0.62, 0.22)
	elif u.team == my_team:
		col = Color(0.32, 0.86, 0.26) if not (u.is_hero() and u.player) else Color(0.2, 0.95, 0.3)
	else:
		col = Color(0.92, 0.2, 0.16)
	var r := Rect2(s.x - width * 0.5, s.y - height, width, height)
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.85))
	draw_rect(r, Color(0.12, 0.1, 0.1, 0.9))
	# recent damage lingers as a pale chunk, then drains away
	var now := Time.get_ticks_msec() / 1000.0
	var g: Array = _ghost.get(u.id, [frac, now])
	if frac < float(g[0]):
		if now - float(g[1]) > 0.45:
			g[0] = maxf(frac, float(g[0]) - get_process_delta_time() * 0.9)
	else:
		g[0] = frac
		g[1] = now
	if frac < float(g[0]) - 0.002 and now - float(g[1]) <= 0.02:
		g[1] = now
	_ghost[u.id] = g
	if float(g[0]) > frac:
		draw_rect(Rect2(r.position.x + width * frac, r.position.y, width * (float(g[0]) - frac), height), Color(1.0, 0.93, 0.7, 0.85))
	var fill := Rect2(r.position, Vector2(width * frac, height))
	draw_rect(fill, col)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, height * 0.35)), Color(1, 1, 1, 0.18))
	if not u.modifiers.is_empty():
		var bt := SimBarrier.total(u)
		if bt != Vector3.ZERO:
			BarrierBar.draw(self, r, frac, u.max_hp, bt)
	var rage_on := u.is_hero() and u.ability_level.has("rage")
	if rage_on:
		# Berserk's held damage: a dark stretch at the end of his health, what will come back
		var held: float = game.world.abilities.kits5.held(u)
		if held > 0.0:
			var hw := minf(width * frac, width * held / maxf(1.0, u.max_hp))
			draw_rect(Rect2(r.position.x + width * frac - hw, r.position.y, hw, height), Color(0.25, 0.02, 0.04, 0.85))
	if not u.is_hero() and not u.is_building():
		_disable_bar(u, Rect2(r.position.x, r.end.y + 3, width, 4), false)
	if u.is_hero():
		# a tick every 250 health
		var ticks := int(u.max_hp / 250.0)
		for i in range(1, ticks + 1):
			var x := r.position.x + width * (i * 250.0 / u.max_hp)
			if x < r.end.x - 1:
				draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + height * (0.5 if i % 4 else 1.0)), Color(0, 0, 0, 0.7), 1.0)
		var mr := Rect2(r.position.x, r.end.y + 2, width, 4)
		draw_rect(mr.grow(1.0), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(mr.position, Vector2(width * clampf(u.mana / maxf(1.0, u.max_mana), 0.0, 1.0), 4)), Color(0.25, 0.5, 1.0))
		var below := 0.0
		if rage_on:
			# Burak's Rage: a red bar under his mana (0-100)
			var rr2 := Rect2(r.position.x, mr.end.y + 2, width, 3)
			draw_rect(rr2.grow(1.0), Color(0, 0, 0, 0.85))
			draw_rect(Rect2(rr2.position, Vector2(width * clampf(SimKits5.rage(u) / 100.0, 0.0, 1.0), 3)), Color(1.0, 0.18, 0.08))
			below = 5.0
		var lv := str(u.level)
		var badge := Rect2(r.position.x - 20, r.position.y - 4, 18, 17)
		draw_rect(badge, Color(0.05, 0.05, 0.07, 0.95))
		draw_rect(badge, Color(0.85, 0.7, 0.35), false, 1.0)
		var tw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_texts.append([font, Vector2(badge.position.x + 9 - tw * 0.5, badge.position.y + 13), lv, 12, 0, Color(1, 0.92, 0.7)])
		var dy := _disable_bar(u, Rect2(r.position.x, r.end.y + 9 + below, width, 6), true)
		_status_icons(u, Vector2(r.position.x, r.end.y + 9 + below + dy))
		# "lemonQ (Ezee)": the player in their player colour, the hero in its team's colour
		var parts := UiKit.who_parts(u)
		var nf := UiKit.font("bold")
		var gap := 5.0
		var nw := -gap
		for pt in parts:
			nw += nf.get_string_size(String(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + gap
		var nx := s.x - nw * 0.5
		for i in parts.size():
			var pc: Color = parts[i][1]
			_texts.append([nf, Vector2(nx, r.position.y - 7), String(parts[i][0]), 16, 5,
				pc.lightened(0.15) if i == 0 else pc.lightened(0.35)])
			nx += nf.get_string_size(String(parts[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + gap
