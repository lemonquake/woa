class_name IconFrame
extends Control
## A framed skill or item icon for menu screens (Hero Select, the ranked pick, a lobby): the icon fills the control
## and the current border pack (IconBorder) frames it, a little brighter under the mouse.

var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
var kind := "skill":
	set(v):
		kind = v
		queue_redraw()
var tint := Color.WHITE

static func make(tex: Texture2D, p_kind: String, sz: float) -> IconFrame:
	var f := IconFrame.new()
	f.texture = tex
	f.kind = p_kind
	f.custom_minimum_size = Vector2(sz, sz)
	return f

func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func _draw() -> void:
	var hot := get_global_rect().has_point(get_global_mouse_position()) and mouse_filter != MOUSE_FILTER_IGNORE
	IconBorder.draw_icon(self, texture, Rect2(Vector2.ZERO, size), kind, tint, Color(1.2, 1.15, 1.0) if hot else Color.WHITE)
