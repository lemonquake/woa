extends SceneTree
## Renders the four revised subjects at actual gameplay sizes and dim/cooldown states.
const IDS := ["death_order", "beast_form", "break_strike", "weapon_grab"]
const DIR := "A:/Python/woa/work/lemondev/2026-10-20-icons/review/focus/"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.content_scale_size = Vector2i(1920, 1080)
	for label in ["A", "B"]:
		var board := Board.new()
		for id in IDS:
			var texture: Texture2D = UiKit.ability_icon(id)
			if label == "A":
				texture = ImageTexture.create_from_image(Image.load_from_file(DIR + "old/" + id + ".png"))
			board.icons.append(texture)
		root.add_child(board)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(DIR + label + ".png")
		board.queue_free()
		await process_frame
	quit()

class Board extends Control:
	var icons: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.035, 0.04, 0.05))
		UiKit.text(self, "Skill images", Vector2(80, 70), 28)
		for i in icons.size():
			var y := 150.0 + i * 200.0
			UiKit.text(self, IDS[i].replace("_", " ").capitalize(), Vector2(80, y + 40), 22)
			for j in 9:
				var size_value := float([32, 44, 64][j % 3])
				var rect := Rect2(410 + j * 150, y, size_value, size_value)
				draw_texture_rect(icons[i], rect, false)
				if j >= 6:
					UiKit.cooldown(self, rect, 0.62, 8.0)
				elif j >= 3:
					draw_rect(rect, Color(0.04, 0.045, 0.05, 0.52))
				UiKit.text(self, "%d px" % int(size_value), Vector2(rect.position.x, y + 100), 16)
