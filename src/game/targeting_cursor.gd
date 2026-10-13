class_name TargetingCursor
extends RefCounted
## The targeting cursor: a crosshair that pulses while a spell, item or attack waits for its target. Red for orders
## aimed at enemies, green for support orders (allies, yourself, the ground for a teleport or a ward). Drawn once into
## a few frames per colour and swapped about 15 times a second as a hardware cursor, so it never lags the mouse.

const FRAMES := 10
const PULSE := 0.9                         # seconds per pulse
const RED := Color(1.0, 0.16, 0.12)
const GREEN := Color(0.3, 1.0, 0.38)

var _frames := {}                          # "enemy" / "ally" -> [ImageTexture]
var _size := 0
var _shown := ""                           # "colour:frame" currently set, "" = the normal cursor

## Set the cursor for this frame. team: "" (normal cursor), "enemy" or "ally".
func update(team: String, scale: float) -> void:
	if team == "":
		if _shown != "":
			_shown = ""
			Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
			Input.set_custom_mouse_cursor(null, Input.CURSOR_CROSS)
		return
	var size := clampi(int(round(44.0 * scale)) / 2 * 2, 32, 128)
	if size != _size:
		_size = size
		_frames.clear()
		_shown = ""
	if not _frames.has(team):
		_frames[team] = _build(RED if team == "enemy" else GREEN, size)
	var t := Time.get_ticks_msec() / 1000.0
	var f := int(fposmod(t, PULSE) / PULSE * FRAMES) % FRAMES
	var key := "%s:%d" % [team, f]
	if key == _shown:
		return
	_shown = key
	var tex: Texture2D = _frames[team][f]
	var hot := Vector2(size, size) * 0.5
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_CROSS, hot)

func _build(col: Color, size: int) -> Array:
	var out: Array = []
	for f in FRAMES:
		var k := 0.5 - 0.5 * cos(float(f) / FRAMES * TAU)     # 0 -> 1 -> 0 over the pulse
		out.append(ImageTexture.create_from_image(_draw(col, size, k)))
	return out

## One frame: a dark-outlined ring with four ticks pointing in and a centre dot; the ring breathes outward and the
## glow brightens with k.
static func _draw(col: Color, size: int, k: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var s := size / 44.0
	var ring_r := (11.0 + 3.0 * k) * s
	var ring_w := 2.2 * s
	var tick_in := (6.0 + 1.5 * k) * s
	var tick_out := (19.0 + 1.5 * k) * s
	var tick_w := 2.0 * s
	var glow := col.lerp(Color(1, 1, 1), 0.25 * k)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := p.length()
			# coverage of each shape: ring, four ticks on the axes, the centre dot
			var ring := 1.0 - clampf(absf(d - ring_r) - ring_w * 0.5 + 0.5, 0.0, 1.0)
			var tick := 0.0
			var ax := absf(p.x)
			var ay := absf(p.y)
			if ax < ay:
				tick = (1.0 - clampf(ax - tick_w * 0.5 + 0.5, 0.0, 1.0)) * float(ay >= tick_in and ay <= tick_out)
			else:
				tick = (1.0 - clampf(ay - tick_w * 0.5 + 0.5, 0.0, 1.0)) * float(ax >= tick_in and ax <= tick_out)
			var dot := 1.0 - clampf(d - 1.6 * s + 0.5, 0.0, 1.0)
			var fill := maxf(ring, maxf(tick, dot))
			# a dark outline one pixel (scaled) around every shape so the cursor reads on bright grass and snow
			var ol := 0.0
			var ow := 1.4 * s
			ol = maxf(ol, 1.0 - clampf(absf(d - ring_r) - ring_w * 0.5 - ow + 0.5, 0.0, 1.0))
			if ax < ay:
				ol = maxf(ol, (1.0 - clampf(ax - tick_w * 0.5 - ow + 0.5, 0.0, 1.0)) * float(ay >= tick_in - ow and ay <= tick_out + ow))
			else:
				ol = maxf(ol, (1.0 - clampf(ay - tick_w * 0.5 - ow + 0.5, 0.0, 1.0)) * float(ax >= tick_in - ow and ax <= tick_out + ow))
			ol = maxf(ol, 1.0 - clampf(d - 1.6 * s - ow + 0.5, 0.0, 1.0))
			# soft halo that pulses
			var halo := clampf(1.0 - absf(d - ring_r) / (5.0 * s), 0.0, 1.0) * 0.35 * k
			var outc := Color(0, 0, 0, ol * 0.85)
			var px := outc
			if halo > 0.0:
				px = px.blend(Color(glow, halo))
			if fill > 0.0:
				px = px.blend(Color(glow, fill))
			img.set_pixel(x, y, px)
	return img
