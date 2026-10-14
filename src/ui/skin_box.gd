class_name SkinBox
extends StyleBox
## A nine-slice style box for the generated interface skin (tools/ui_skin.py). The skin's textures hold twice the
## pixels they are drawn with at 1920x1080, so the corners stay sharp at 3840x2160; this box draws the corners and
## edges at the skin's drawn size (`margins`, in drawn pixels) while sampling the full texture.

var texture: Texture2D
var margins := Vector4(12, 12, 12, 12)      # left, top, right, bottom in drawn pixels
var scale := 2.0                            # texture pixels per drawn pixel
var modulate := Color(1, 1, 1, 1)
var draw_center := true
var expand := Vector4.ZERO                  # drawn outside the rect (left, top, right, bottom), e.g. for glows

func _init(p_tex: Texture2D = null, p_margins := Vector4(12, 12, 12, 12), p_scale := 2.0) -> void:
	texture = p_tex
	margins = p_margins
	scale = p_scale

## Containers add this to their content: only the content padding (the frame's corners may overlap the content).
func _get_minimum_size() -> Vector2:
	return Vector2(content_margin_left + content_margin_right, content_margin_top + content_margin_bottom)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	draw_nine(to_canvas_item, rect, texture, margins, scale, modulate, draw_center, expand)

## Draw a nine-slice of `tex` into `rect` on a canvas item (also used directly by the HUD's own drawing).
static func draw_nine(ci: RID, rect: Rect2, tex: Texture2D, m: Vector4, sc: float, col := Color.WHITE, center := true,
		exp := Vector4.ZERO) -> void:
	var r := Rect2(rect.position - Vector2(exp.x, exp.y), rect.size + Vector2(exp.x + exp.z, exp.y + exp.w))
	var ts := tex.get_size()
	# shrink the margins if the rect is smaller than the corners
	var l := minf(m.x, r.size.x * 0.5)
	var t := minf(m.y, r.size.y * 0.5)
	var rr := minf(m.z, r.size.x * 0.5)
	var b := minf(m.w, r.size.y * 0.5)
	var xs := [r.position.x, r.position.x + l, r.end.x - rr, r.end.x]
	var ys := [r.position.y, r.position.y + t, r.end.y - b, r.end.y]
	var us := [0.0, m.x * sc, ts.x - m.z * sc, ts.x]
	var vs := [0.0, m.y * sc, ts.y - m.w * sc, ts.y]
	var rid := tex.get_rid()
	for j in 3:
		for i in 3:
			if i == 1 and j == 1 and not center:
				continue
			var dst := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			var src := Rect2(us[i], vs[j], us[i + 1] - us[i], vs[j + 1] - vs[j])
			RenderingServer.canvas_item_add_texture_rect_region(ci, dst, rid, src, col, false, true)
