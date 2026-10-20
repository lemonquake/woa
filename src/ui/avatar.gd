class_name Avatar
extends Control
## A ranked player's picture (run 2026-10-19 b): a hero's portrait, a picture you uploaded (user://ranked_avatar.png),
## a plain silhouette, or for bots a funny face drawn from a seed: a round, potato, square or blob head in frog green,
## pig pink, potato brown and other colours, with googly, sleepy, crossed-out, crying, heart, spiral or sunglasses
## eyes, a grin, a tongue, a moustache or a wobbly mouth, and maybe cat ears, a cap, a party hat, a sweat drop or
## blushing cheeks. Square with a thin frame, like Dota's.

const U = preload("res://src/ui/ui_kit.gd")
const CUSTOM := "user://ranked_avatar.png"

var spec := {"k": "none"}
var frame := Color(0.55, 0.43, 0.2)
var _tex: Texture2D

static var _custom := {}                    # file -> [texture, modified time]

func set_spec(s: Dictionary) -> void:
	spec = s if s is Dictionary else {"k": "none"}
	_tex = null
	match String(spec.get("k", "none")):
		"hero":
			_tex = U.hero_portrait(String(spec.get("id", "")))
		"custom":
			_tex = custom_texture(String(spec.get("file", CUSTOM)))
	queue_redraw()

## Where an account keeps its uploaded picture (the first account's is the file from before accounts existed).
static func custom_path(acc: String) -> String:
	return CUSTOM if acc == "" or acc == "u1" else "user://ranked_avatar_%s.png" % acc.validate_filename()

## A picture you uploaded (reloaded when the file changes).
static func custom_texture(file := CUSTOM) -> Texture2D:
	if not FileAccess.file_exists(file):
		return null
	var stamp := int(FileAccess.get_modified_time(file))
	var c: Array = _custom.get(file, [])
	if not c.is_empty() and int(c[1]) == stamp:
		return c[0]
	var img := Image.load_from_file(ProjectSettings.globalize_path(file))
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_custom[file] = [tex, stamp]
	return tex

## Load a picture from disk, crop it to a centred square, scale it to 256 px and keep it as the picture of the account
## logged in (custom_path). "" or an error message.
static func import_picture(path: String) -> String:
	var img := Image.new()
	var err := img.load(path)
	if err != OK or img.is_empty():
		return "That file could not be read as a picture."
	var s := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var dest := custom_path(Ranked.account_id())
	if img.save_png(dest) != OK:
		return "The picture could not be saved."
	_custom.erase(dest)
	return ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var k := String(spec.get("k", "none"))
	if _tex != null:
		draw_rect(r, Color(0.05, 0.05, 0.07))
		draw_texture_rect(_tex, r, false)
	elif k == "face":
		_draw_face(r, int(spec.get("seed", 1)))
	else:
		_draw_silhouette(r)
	# the frame: a dark inner line and a coloured outer one
	draw_rect(r.grow(-1.0), Color(0, 0, 0, 0.6), false, 2.0)
	draw_rect(r, frame, false, maxf(1.0, size.x / 64.0))

func _draw_silhouette(r: Rect2) -> void:
	var c := r.get_center()
	var s := r.size.x
	draw_rect(r, Color(0.13, 0.15, 0.2))
	draw_rect(Rect2(r.position, Vector2(s, s * 0.5)), Color(0.17, 0.19, 0.25))
	var col := Color(0.42, 0.45, 0.52)
	draw_circle(c + Vector2(0, -s * 0.1), s * 0.2, col)
	var body := PackedVector2Array()
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		body.append(c + Vector2(cos(a) * s * 0.36, s * 0.5 + sin(a) * s * 0.3))
	draw_colored_polygon(body, col)

const BGS := [Color(0.98, 0.78, 0.25), Color(0.4, 0.75, 0.95), Color(0.95, 0.45, 0.55), Color(0.55, 0.85, 0.45),
	Color(0.7, 0.55, 0.95), Color(1.0, 0.6, 0.3), Color(0.3, 0.3, 0.38), Color(0.95, 0.95, 0.9), Color(0.2, 0.55, 0.5)]
const SKINS := [Color(1.0, 0.85, 0.25), Color(0.45, 0.78, 0.3), Color(1.0, 0.68, 0.72), Color(0.55, 0.7, 1.0),
	Color(0.72, 0.5, 0.9), Color(0.72, 0.52, 0.32), Color(1.0, 0.62, 0.3), Color(0.92, 0.92, 0.9), Color(0.6, 0.6, 0.62),
	Color(0.95, 0.78, 0.62), Color(0.55, 0.36, 0.25)]

func _draw_face(r: Rect2, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := r.size.x
	var bg: Color = BGS[rng.randi_range(0, BGS.size() - 1)]
	var skin: Color = SKINS[rng.randi_range(0, SKINS.size() - 1)]
	if absf(bg.h - skin.h) < 0.05 and absf(bg.v - skin.v) < 0.15:
		bg = bg.darkened(0.45)
	draw_rect(r, bg)
	# a soft light in the corner
	draw_circle(r.position + Vector2(s * 0.2, s * 0.15), s * 0.45, Color(1, 1, 1, 0.08))
	var c := r.get_center() + Vector2(0, s * 0.06)
	var line := Color(0.1, 0.07, 0.06)
	var shape := rng.randi_range(0, 4)
	var hw := s * rng.randf_range(0.3, 0.37)
	var hh := s * rng.randf_range(0.3, 0.37)
	if shape == 1:
		hw *= 1.15
		hh *= 0.88
	elif shape == 2:
		hw *= 0.85
		hh *= 1.1
	# ears behind the head
	var ears := rng.randi_range(0, 5)
	if ears == 1:
		for sd in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(sd * hw * 0.85, -hh * 0.45), c + Vector2(sd * hw * 0.95, -hh * 1.25),
				c + Vector2(sd * hw * 0.25, -hh * 0.85)]), skin.darkened(0.08))
	elif ears == 2:
		for sd in [-1.0, 1.0]:
			draw_circle(c + Vector2(sd * hw * 0.92, -hh * 0.2), hw * 0.3, skin.darkened(0.1))
			draw_circle(c + Vector2(sd * hw * 0.92, -hh * 0.2), hw * 0.17, skin.lightened(0.2))
	# the head
	var head := PackedVector2Array()
	var n := 40
	var bump := rng.randf_range(0.0, 0.07) if shape in [2, 4] else 0.0
	for i in n:
		var a := TAU * float(i) / float(n)
		var rr := 1.0 + bump * sin(a * 3.0 + float(seed % 7)) + (0.04 * sin(a * 5.0) if shape == 4 else 0.0)
		var p := Vector2(cos(a) * hw, sin(a) * hh) * rr
		if shape == 3:
			p = Vector2(clampf(cos(a) * hw * 1.3, -hw, hw), clampf(sin(a) * hh * 1.3, -hh, hh))
		head.append(c + p)
	draw_colored_polygon(head, skin)
	head.append(head[0])
	draw_polyline(head, line, maxf(1.0, s / 48.0), true)
	# frog eyes on top
	var frog := ears == 3
	var ey := c.y - hh * (0.75 if frog else 0.18)
	var ex := hw * 0.42
	var er := s * rng.randf_range(0.065, 0.1) * (1.4 if frog else 1.0)
	if frog:
		for sd in [-1.0, 1.0]:
			draw_circle(Vector2(c.x + sd * ex, ey), er * 1.25, skin)
	# cheeks
	if rng.randf() < 0.45:
		for sd in [-1.0, 1.0]:
			draw_circle(c + Vector2(sd * hw * 0.62, hh * 0.18), s * 0.06, Color(1.0, 0.35, 0.4, 0.45))
	# eyes
	var eyes := rng.randi_range(0, 9)
	var look := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * er * 0.45
	for sd in [-1.0, 1.0]:
		var e := Vector2(c.x + sd * ex, ey)
		var er2 := er * (rng.randf_range(0.75, 1.3) if eyes == 1 else 1.0)
		match eyes:
			0:
				draw_circle(e, er * 0.45, line)
			1, 2:
				draw_circle(e, er2, Color.WHITE)
				draw_arc(e, er2, 0, TAU, 24, line, maxf(1.0, s / 64.0))
				draw_circle(e + (look if eyes == 1 else Vector2(sd * -er * 0.3, 0)), er2 * 0.45, line)
				draw_circle(e + (look if eyes == 1 else Vector2(sd * -er * 0.3, 0)) + Vector2(-er2 * 0.15, -er2 * 0.15), er2 * 0.12, Color.WHITE)
			3:
				draw_line(e + Vector2(-er, 0), e + Vector2(er, er * 0.2), line, maxf(1.5, s / 40.0))
			4:
				var w := maxf(1.5, s / 36.0)
				draw_line(e + Vector2(-er, -er) * 0.7, e + Vector2(er, er) * 0.7, line, w)
				draw_line(e + Vector2(-er, er) * 0.7, e + Vector2(er, -er) * 0.7, line, w)
			5:
				draw_circle(e, er * 0.45, line)
				draw_line(e + Vector2(-sd * er * 1.1, -er * 1.2), e + Vector2(sd * er * 0.6, -er * 0.6), line, maxf(1.5, s / 36.0))
			6:
				draw_circle(e, er * 0.5, line)
				draw_rect(Rect2(e + Vector2(-er * 0.25, er * 0.4), Vector2(er * 0.5, s * 0.3)), Color(0.35, 0.65, 1.0, 0.8))
			7:
				_heart(e, er * 1.1, Color(0.95, 0.15, 0.25))
			8:
				for k in 3:
					draw_arc(e, er * (0.35 + 0.3 * float(k)), float(k), float(k) + PI * 1.4, 12, line, maxf(1.0, s / 64.0))
			9:
				pass
	if eyes == 9:
		# sunglasses
		var gl := Rect2(Vector2(c.x - ex - er * 1.4, ey - er * 0.9), Vector2(ex * 2.0 + er * 2.8, er * 1.8))
		draw_rect(gl, Color(0.05, 0.05, 0.06))
		draw_line(gl.position + Vector2(gl.size.x * 0.15, gl.size.y * 0.3), gl.position + Vector2(gl.size.x * 0.3, gl.size.y * 0.2), Color(1, 1, 1, 0.6), maxf(1.0, s / 64.0))
	# a pig snout or a nose
	if skin.is_equal_approx(SKINS[2]) or rng.randf() < 0.15:
		var sn := c + Vector2(0, hh * 0.12)
		draw_circle(sn, s * 0.08, skin.darkened(0.15))
		for sd in [-1.0, 1.0]:
			draw_circle(sn + Vector2(sd * s * 0.03, 0), s * 0.017, line)
	# the mouth
	var my := c.y + hh * 0.45
	var mw := hw * rng.randf_range(0.35, 0.6)
	var lw := maxf(1.5, s / 40.0)
	match rng.randi_range(0, 7):
		0:
			draw_arc(Vector2(c.x, my - mw * 0.6), mw, 0.35, PI - 0.35, 16, line, lw)
		1:
			var m := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				m.append(Vector2(c.x + cos(a) * mw, my - mw * 0.2 + sin(a) * mw * 0.8))
			draw_colored_polygon(m, Color(0.25, 0.05, 0.08))
			draw_circle(Vector2(c.x, my + mw * 0.35), mw * 0.35, Color(0.95, 0.4, 0.45))
		2:
			draw_line(Vector2(c.x - mw, my), Vector2(c.x + mw, my), line, lw)
		3:
			var m2 := PackedVector2Array()
			for i in 9:
				m2.append(Vector2(c.x - mw + 2.0 * mw * float(i) / 8.0, my + sin(float(i) * 1.6) * s * 0.012))
			draw_polyline(m2, line, lw)
		4:
			draw_rect(Rect2(Vector2(c.x - mw, my - mw * 0.25), Vector2(mw * 2.0, mw * 0.5)), Color.WHITE)
			draw_rect(Rect2(Vector2(c.x - mw, my - mw * 0.25), Vector2(mw * 2.0, mw * 0.5)), line, false, lw * 0.7)
			for i in range(1, 4):
				var x := c.x - mw + mw * 0.5 * float(i)
				draw_line(Vector2(x, my - mw * 0.25), Vector2(x, my + mw * 0.25), line, lw * 0.5)
		5:
			draw_arc(Vector2(c.x, my - mw * 0.6), mw, 0.4, PI - 0.4, 16, line, lw)
			draw_circle(Vector2(c.x + mw * 0.3, my + mw * 0.3), mw * 0.32, Color(0.95, 0.35, 0.45))
		6:
			draw_arc(Vector2(c.x, my + mw * 0.7), mw * 0.9, PI + 0.5, TAU - 0.5, 16, line, lw)
		7:
			draw_arc(Vector2(c.x, my - mw * 0.4), mw * 0.8, 0.3, PI - 0.3, 16, line, lw)
			for sd in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([Vector2(c.x, my - mw * 0.55), Vector2(c.x + sd * mw * 1.1, my - mw * 0.25),
					Vector2(c.x + sd * mw * 0.9, my - mw * 0.05), Vector2(c.x, my - mw * 0.35)]), Color(0.18, 0.1, 0.06))
	# something on top
	var top := rng.randi_range(0, 6)
	var crown_y := c.y - hh
	match top:
		1:
			# a cap
			draw_colored_polygon(_half_disc(Vector2(c.x, crown_y + hh * 0.3), hw * 0.95, hh * 0.55), Color(0.85, 0.2, 0.2))
			draw_rect(Rect2(Vector2(c.x - hw * 0.1, crown_y + hh * 0.22), Vector2(hw * 1.25, hh * 0.13)), Color(0.7, 0.12, 0.12))
		2:
			# a party hat
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - hw * 0.4, crown_y + hh * 0.08), Vector2(c.x + hw * 0.4, crown_y + hh * 0.08),
				Vector2(c.x + hw * 0.1, crown_y - hh * 0.75)]), Color(0.3, 0.6, 1.0))
			draw_circle(Vector2(c.x + hw * 0.1, crown_y - hh * 0.75), s * 0.04, Color(1.0, 0.85, 0.2))
		3:
			# a headband
			draw_rect(Rect2(Vector2(c.x - hw * 0.98, crown_y + hh * 0.35), Vector2(hw * 1.96, hh * 0.16)), Color(0.9, 0.15, 0.2))
		4:
			# a sweat drop
			draw_circle(c + Vector2(hw * 0.75, -hh * 0.55), s * 0.035, Color(0.55, 0.8, 1.0))
		5:
			# three hairs
			for i in 3:
				var x := c.x + (float(i) - 1.0) * hw * 0.15
				draw_arc(Vector2(x + s * 0.03, crown_y), s * 0.05, PI, PI * 1.9, 8, line, lw * 0.7)

static func _half_disc(c: Vector2, rw: float, rh: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		p.append(c + Vector2(cos(a) * rw, sin(a) * rh))
	return p

func _heart(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.45, -r * 0.2), r * 0.5, col)
	draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.5, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.92, -r * 0.05), c + Vector2(r * 0.92, -r * 0.05), c + Vector2(0, r * 0.9)]), col)
