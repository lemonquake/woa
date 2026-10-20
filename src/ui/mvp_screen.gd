class_name MvpScreen
extends Control
## The MVP after a match (run 2026-10-19 e; the owner: "an MVP after the game with all the epic UI and some stats on why
## he is the MVP. Supports can become MVPs as well"). The match's MVP (MatchMvp) stands in 3D on the versus field
## (VersusStage) in a gold light, plays its flourish while the camera pushes in; MVP slams down over it; the player's
## name, hero, team and rank come in beside it, then the reasons one by one (the numbers it led the match in), then the
## other honours of the match (top support, most damage, best farm) along the bottom. Continue (or Enter) goes on to the
## scoreboard.

signal finished

const U = preload("res://src/ui/ui_kit.gd")
const W := 1920.0
const H := 1080.0

var world: SimWorld
var mine := 0                               # your team (blue)
var best := {}                              # MatchMvp.best
var honours: Array = []
var _hero: SimUnit
var _stage: VersusStage
var _vp: SubViewport
var _over: Control
var _t := 0.0
var _cont: Button
var _slam_said := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = U.theme()
	_hero = world.get_unit(int(best.get("u", -1)))
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	svc.add_child(_vp)
	_stage = VersusStage.new()
	_vp.add_child(_stage)
	if _hero != null:
		var you := _hero.player
		_stage.add_hero("me" if you else "mvp", String(_hero.def.id), 0, 0)
		var b: Dictionary = _stage.heroes.get("me" if you else "mvp", {})
		if not b.is_empty():
			var holder: Node3D = b.holder
			holder.position = Vector3(-1.45, 0.0, 0.6)
			holder.rotation.y = 0.45
			for c in holder.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
					var m := (c as MeshInstance3D).material_override as StandardMaterial3D
					m.albedo_color = U.GOLD
					m.emission = U.GOLD
					c.scale = Vector3(1.35, 0.08, 1.35)
	_stage._cam_from = Vector3(0.6, 3.0, 9.5)
	_stage._cam_to = Vector3(0.9, 1.55, 5.3)
	_stage._look = Vector3(0.55, 1.3, 0.0)
	_stage.begin()
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)
	_cont = Button.new()
	_cont.text = "Continue"
	_cont.custom_minimum_size = Vector2(220, 56)
	_cont.add_theme_font_size_override("font_size", 22)
	_cont.modulate.a = 0.0
	_cont.pressed.connect(_done)
	add_child(_cont)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var k := _k()
	_cont.scale = Vector2(k, k)
	_cont.position = _off() + Vector2(W - 270, H - 96) * k

func _k() -> float:
	return minf(size.x / W, size.y / H) if size.x > 0.0 else 1.0

func _off() -> Vector2:
	return ((size - Vector2(W, H) * _k()) * 0.5).floor()

func _done() -> void:
	Options.click()
	finished.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE] and _t > 1.5:
		get_viewport().set_input_as_handled()
		_done()

func _process(dt: float) -> void:
	_t += dt
	if _t >= 1.15 and not _slam_said:
		_slam_said = true
		_stage.shake(0.8)
	_cont.modulate.a = clampf((_t - 3.2) / 0.5, 0.0, 1.0)
	_over.queue_redraw()

## The MVP's player: its name, the rank it plays at (ranked cards), and its team.
func _who() -> Dictionary:
	var h := _hero
	var nm := h.player_label() if h.player_label() != "" else SimTeamAI.hero_label(h)
	var rk := ""
	var tier := -1
	if h.player:
		var c: Dictionary = world.player_cards.get(h.id, {})
		rk = String(c.get("rank", ""))
		tier = int(c.get("tier", -1))
	else:
		for b in world.bots:
			if b.hero_id == h.id:
				rk = String((b.card as Dictionary).get("rank", ""))
				tier = int((b.card as Dictionary).get("tier", -1))
	return {"name": nm, "rank": rk, "tier": tier}

func _draw_over() -> void:
	if _hero == null:
		return
	var k := _k()
	_over.draw_set_transform(_off(), 0.0, Vector2(k, k))
	var f := U.font("title")
	var b := U.font("bold")
	var body := U.font("body")
	var team_col := Color(0.4, 0.72, 1.0) if _hero.team == mine else Color(0.95, 0.38, 0.33)
	# letterbox and a gold wash from the right
	var bar := clampf(_t / 0.5, 0.0, 1.0)
	_over.draw_rect(Rect2(-2000, -2000, W + 4000, 2000 + 60.0 * bar), Color(0, 0, 0, 0.92))
	_over.draw_rect(Rect2(-2000, H - 110.0 * bar, W + 4000, 2000), Color(0, 0, 0, 0.92))
	# a soft shade behind the text on the right (a gradient: no seam)
	var sa := 0.62 * clampf(_t / 1.0, 0.0, 1.0)
	var c0 := Color(0.02, 0.015, 0.0, 0.0)
	var c1 := Color(0.02, 0.015, 0.0, sa)
	_over.draw_polygon(PackedVector2Array([Vector2(W * 0.36, 60), Vector2(W * 0.62, 60), Vector2(W * 0.62, H - 110), Vector2(W * 0.36, H - 110)]),
		PackedColorArray([c0, c1, c1, c0]))
	_over.draw_rect(Rect2(W * 0.62, 60, W * 0.38 + 2000, H - 170), c1)
	# light rays behind the title
	var c := Vector2(W * 0.66, 190)
	for i in 16:
		var ang := TAU * float(i) / 16.0 + _t * 0.15
		var p1 := c + Vector2.from_angle(ang - 0.06) * 900.0
		var p2 := c + Vector2.from_angle(ang + 0.06) * 900.0
		_over.draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(1.0, 0.8, 0.35, 0.035 * clampf((_t - 0.8) / 0.6, 0.0, 1.0)))
	# MVP slams down
	if _t >= 0.8:
		var u := clampf((_t - 0.8) / 0.35, 0.0, 1.0)
		var scl := lerpf(3.2, 1.0, u * u)
		var fs := int(170 * scl)
		var tw := f.get_string_size("MVP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		for gi in 3:
			_over.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36) + Vector2(0, 0), "MVP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + gi * 6,
				Color(1.0, 0.75, 0.3, 0.07 * u))
		_over.draw_string(f, c + Vector2(-tw * 0.5 + 6, fs * 0.36 + 6), "MVP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75 * u))
		_over.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), "MVP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.45, u))
		if _t < 1.7:
			var fl := clampf(1.0 - (_t - 1.15) / 0.5, 0.0, 1.0) if _t >= 1.15 else 0.0
			_over.draw_rect(Rect2(-2000, -2000, W + 4000, H + 4000), Color(1, 0.95, 0.8, 0.45 * fl))
			var ring := (_t - 1.15) * 1600.0
			if ring > 0.0:
				_over.draw_arc(c, ring, 0, TAU, 64, Color(1.0, 0.85, 0.5, 0.7 * fl), 8.0, true)
		var sub := "Most valuable player"
		var sw := b.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_over.draw_string(b, Vector2(c.x - sw * 0.5, c.y + 92), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(U.TEXT, u))
	# the player
	var a := clampf((_t - 1.5) / 0.5, 0.0, 1.0)
	if a > 0.0:
		var who := _who()
		var x := W * 0.5 + 40.0 - (1.0 - a) * 40.0
		var y := 360.0
		var nm := String(who.name)
		var nfs := 56
		while b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > 800 and nfs > 24:
			nfs -= 2
		_over.draw_string(b, Vector2(x + 3, y + 3), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(0, 0, 0, 0.7 * a))
		_over.draw_string(b, Vector2(x, y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(U.GOLD if _hero.player else U.TEXT, a))
		var line := "%s  ·  %s  ·  %s" % [SimTeamAI.hero_label(_hero), String(SimConst.TEAM_NAMES[_hero.team]), String(best.get("tag", "Core"))]
		_over.draw_string(body, Vector2(x, y + 40), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(team_col.lightened(0.2), a))
		if String(who.rank) != "":
			var ic := RankEmblem.icon(int(who.tier)) if int(who.tier) >= 0 else null
			var rx := x
			if ic:
				_over.draw_texture_rect(ic, Rect2(x - 4, y + 54, 54, 54), false, Color(1, 1, 1, a))
				rx += 56.0
			_over.draw_string(b, Vector2(rx, y + 90), String(who.rank), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(U.TEXT, a))
		var kda := "%d / %d / %d" % [_hero.kills, _hero.deaths, _hero.assists]
		_over.draw_string(f, Vector2(x, y + 160), kda, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(U.TEXT, a))
		_over.draw_string(b, Vector2(x + f.get_string_size(kda, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x + 18, y + 156), "K / D / A",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(U.TEXT_DIM, a))
	# the reasons, one by one
	var reasons: Array = best.get("reasons", [])
	for i in reasons.size():
		var ra := clampf((_t - 2.0 - 0.28 * float(i)) / 0.35, 0.0, 1.0)
		if ra <= 0.0:
			continue
		var r := Rect2(W * 0.5 + 40.0 + float(i % 2) * 400.0 + (1.0 - ra) * 60.0, 560.0 + float(i / 2) * 118.0, 380, 104)
		_over.draw_style_box(RankedNum.flat(Color(0.03, 0.035, 0.05, 0.86 * ra), Color(U.GOLD, 0.6 * ra), 8, 1), r)
		_over.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Color(U.GOLD, ra))
		var lab := String(reasons[i][0])
		var val := String(reasons[i][1])
		_over.draw_string(b, r.position + Vector2(22, 34), lab, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30, 19, Color(U.TEXT_DIM, ra))
		var vfs := 40
		while f.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs).x > r.size.x - 40 and vfs > 18:
			vfs -= 2
		_over.draw_string(f, r.position + Vector2(22, 84), val, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs, Color(U.GOLD, ra))
	# the other honours of the match
	for i in honours.size():
		var ha := clampf((_t - 3.0 - 0.2 * float(i)) / 0.4, 0.0, 1.0)
		if ha <= 0.0:
			continue
		var hon: Dictionary = honours[i]
		var hu := world.get_unit(int(hon.u))
		if hu == null:
			continue
		var r2 := Rect2(60.0 + float(i) * 470.0, H - 100.0 + (1.0 - ha) * 30.0, 450, 84)
		var hc := Color(0.4, 0.72, 1.0) if hu.team == mine else Color(0.95, 0.38, 0.33)
		_over.draw_style_box(RankedNum.flat(Color(0.04, 0.05, 0.07, 0.95 * ha), Color(hc, 0.55 * ha), 8, 1), r2)
		var pt := U.hero_portrait(String(hu.def.id))
		if pt:
			_over.draw_texture_rect(pt, Rect2(r2.position + Vector2(8, 8), Vector2(68, 68)), false, Color(1, 1, 1, ha))
		_over.draw_string(b, r2.position + Vector2(88, 28), String(hon.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(U.GOLD, ha))
		var hn := hu.player_label() if hu.player_label() != "" else SimTeamAI.hero_label(hu)
		_over.draw_string(b, r2.position + Vector2(88, 52), hn, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 96, 18, Color(U.TEXT, ha))
		_over.draw_string(body, r2.position + Vector2(88, 74), String(hon.value), HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 96, 15, Color(U.TEXT_DIM, ha))
