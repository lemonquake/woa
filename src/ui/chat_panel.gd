class_name ChatPanel
extends Control
## Chat, bottom left above the minimap (as in Dota): your team's lines from bots and yourself and everyone's all chat
## (marked "(All)"), each fading after 12 seconds. Enter opens a line to type to your team, Shift+Enter to everyone
## (Enter sends, Esc closes); your bots understand a few plain words (SimTeamAI.on_player_chat: "push top", "defend
## mid", "gank", "back", "group"). While the line is open the history stays up. Options > Game: "Show bot chat" hides
## the bots' lines, "Bot trash talk" only their trash talk (SimBotChat).

const U = preload("res://src/ui/ui_kit.gd")
const W := 560.0
const SHOW := 12.0
const FADE := 2.0
const ROWS := 8

var hud
var lines: Array = []                      # [{name, text, team, me, t (real seconds)}]
var input: LineEdit
var to_all := false                        # the open line goes to all chat
var _now := 0.0

func _ready() -> void:
	theme = U.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, ROWS * 24 + 48)
	input = LineEdit.new()
	input.placeholder_text = "Say to your team (Enter to send, Esc to close)"
	input.max_length = 120
	input.custom_minimum_size = Vector2(W, 36)
	input.size = Vector2(W, 36)
	input.position = Vector2(0, size.y - 36)
	input.visible = false
	input.text_submitted.connect(_send)
	input.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
			close()
			accept_event())
	add_child(input)

func is_open() -> bool:
	return input.visible

func open(all := false) -> void:
	to_all = all
	input.placeholder_text = "Say to everyone (Enter to send, Esc to close)" if all else "Say to your team (Enter to send, Esc to close)"
	input.visible = true
	input.text = ""
	input.grab_focus()
	queue_redraw()

func close() -> void:
	input.release_focus()
	input.visible = false
	queue_redraw()

func _send(text: String) -> void:
	var t := text.strip_edges()
	close()
	if t == "" or hud.game == null or hud.game.world == null:
		return
	hud.game.act({"k": "chat", "text": t, "all": to_all})

## A chat event from the world (only the player's team reaches here).
func add(e: Dictionary) -> void:
	var u: SimUnit = hud.game.world.get_unit(int(e.u))
	var is_bot := u != null and u.bot
	if is_bot and not bool(Options.get_value("bot_chat")):
		return
	if bool(e.get("bot_line", false)) and not bool(Options.get_value("bot_trash_talk")):
		return
	lines.append({"name": ("(All) " if bool(e.get("all", false)) else "") + String(e.name), "text": String(e.text),
		"me": int(e.u) == hud.game.player_hero_id,
		"hero": SimTeamAI.hero_label(u) if u != null else "", "t": _now,
		"col": U.player_color(u) if u != null and u.is_hero() else U.DAWN})
	while lines.size() > 40:
		lines.pop_front()
	queue_redraw()

func _process(dt: float) -> void:
	_now += dt
	# the fade needs no more than 30 redraws a second (new lines and typing redraw at once)
	_redraw_t -= dt
	if _redraw_t <= 0.0 and not lines.is_empty() and (_now - float(lines[-1].t) < SHOW + FADE + 0.5 or is_open()):
		_redraw_t = 1.0 / 30.0
		queue_redraw()

var _redraw_t := 0.0

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	UiKit.draw_cost("chat", t0)

func _draw_body() -> void:
	# newest lines last; each wraps onto as many rows as it needs, the name only on its first row
	var rows: Array = []                   # [[who, text, colour, alpha]]
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		var age := _now - float(l.t)
		if not is_open() and age > SHOW + FADE:
			break
		var a := 1.0 if is_open() else clampf((SHOW + FADE - age) / FADE, 0.0, 1.0)
		var who := String(l.name) + (" (%s)" % l.hero if String(l.hero) != "" and String(l.hero) != String(l.name) else "") + ": "
		var col := Color((l.get("col", U.DAWN) as Color).lerp(Color.WHITE, 0.2), a)
		var wx := U.font("bold").get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var parts := U.wrap(String(l.text), W - wx, 16, "body")
		var block: Array = []
		for k in parts.size():
			block.append([who if k == 0 else "", parts[k], col, a, wx])
		rows = block + rows
		if rows.size() >= ROWS:
			break
	while rows.size() > ROWS:
		rows.pop_front()
	if rows.is_empty() and not is_open():
		return
	var bottom := size.y - (42.0 if is_open() else 4.0)
	if is_open():
		draw_rect(Rect2(Vector2(-4, bottom - rows.size() * 22.0 - 8.0), Vector2(W + 8, rows.size() * 22.0 + 52.0)), Color(0, 0, 0, 0.45))
	var y := bottom - rows.size() * 22.0
	for r in rows:
		y += 22.0
		if String(r[0]) != "":
			U.text(self, r[0], Vector2(0, y - 5), 16, r[2], "bold")
		U.text(self, r[1], Vector2(float(r[4]), y - 5), 16, Color(U.TEXT, float(r[3])), "body")
