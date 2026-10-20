extends Control
## The hero pick and the versus screen of a ranked match (run 2026-10-19 b; the owner: nobody picks a hero before
## matchmaking; when the match starts, a pick with a random numbered turn for each player, bots saying in team chat
## which hero they want, then a versus shot of both teams with each player's name over their hero, then their rank).
##
## Pick: your team on the left, the enemy on the right, each player with their pick number; the one picking glows. The
## heroes in the middle (taken ones marked with who took them); on your turn pick one (its card shows below with its
## roles and skills), Lock in or Random, within 30 s. A picked hero lands in its slot with a flash and a ring of
## sparks. Team chat at the bottom: your bots call their heroes and change their mind when someone takes theirs; every
## pick is logged.
## Versus (the owner: "a fully rendered versus screen where all the heroes face each other"): the ten heroes in 3D on a
## battle field, your team on the left facing the enemy on the right (VersusStage; each hero is placed as it is
## picked), the camera pushing in; over each hero the player's name, then their rank, and their medal on that hero; VS
## slams down in the middle; then the match loads.
## Automation: --capture=path [--phase=pick|versus] [--at=seconds] [--4k] [--frames=n].

const U = preload("res://src/ui/ui_kit.gd")
const MATCH := "res://src/game/main.tscn"
const SFX := "res://assets/audio/sfx/%s.wav"
const W := 1920.0
const H := 1080.0
const BLUE := Color(0.4, 0.72, 1.0)
const RED := Color(0.95, 0.38, 0.33)
const GREEN_HI := Color(0.42, 0.95, 0.5)

var draft: HeroDraft
var phase := "pick"                        # pick, done, versus, loading
var _t := 0.0                              # seconds in this phase
var _frame: Control
var _pick_layer: Control
var _vs_layer: VersusLayer
var _slots := {}                           # id -> PickSlot
var _tiles := {}                           # hero -> HeroTile
var _preview: HeroPreview
var _lock: BigLock
var _random_btn: Button
var _chat: ChatBox
var _banner: TurnBanner
var _chosen := ""                          # the hero you have selected (not locked yet)
var _chat_seen := 0
var _friends_seen := 0
var _picks_seen := 0
var _audio: Array = []
var _capture := ""
var _cap_frames := 60
var _frames := 0
var _shake := 0.0

func _ready() -> void:
	theme = U.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ranked.load_data()
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("4k"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(3840, 2160))
	_capture = String(args.get("capture", ""))
	_cap_frames = int(args.get("frames", "60"))
	var l: Dictionary = Matchmaker.accepted_match
	if l.is_empty():
		# opened on its own (captures): a match near your MMR
		var r := RandomNumberGenerator.new()
		r.seed = 4
		var near: Array = Ranked.bots().filter(func(b): return absi(int(b.mmr) - int(Ranked.me().mmr)) <= 500)
		l = Matchmaker.build_lineup(near, Ranked.me(), Ranked.me().get("roles", [1, 2, 3, 4, 5]), r)
	draft = HeroDraft.new(l, 7 if _capture != "" else 0)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Interface"
		add_child(p)
		_audio.append(p)
	_build()
	resized.connect(_layout)
	_layout()
	# captures of the pick chat (run 2026-10-19 e): --say=text, --want=hero (Alt+click), --suggest=hero (Shift+click)
	if args.has("say"):
		draft.say_me(String(args.say))
	if args.has("want"):
		draft.want_me(String(args.want))
	if args.has("suggest"):
		draft.suggest(String(args.suggest))
	if args.has("at") or String(args.get("phase", "")) == "versus":
		# captures: run the pick forward (you pick when your turn comes)
		var at := float(args.get("at", "999"))
		var tt := 0.0
		while tt < at and not draft.done():
			if draft.current() == "me":
				draft.pick("me", draft.auto_hero("me"))
			draft.step(0.1)
			tt += 0.1
		_sync(true)
		if String(args.get("phase", "")) == "versus":
			_start_versus()
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

func _sfx(n: String, vol := -4.0) -> void:
	var s: AudioStream = load(SFX % n) if ResourceLoader.exists(SFX % n) else null
	if s == null:
		return
	for p: AudioStreamPlayer in _audio:
		if not p.playing:
			p.stream = s
			p.volume_db = vol
			p.play()
			return

func _layout() -> void:
	var k := minf(size.x / W, size.y / H)
	_frame.scale = Vector2(k, k)
	_frame.position = ((size - Vector2(W, H) * k) * 0.5).floor()

# ---- Building ---------------------------------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float vs = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.015, 0.02, 0.04);
	// the two teams' light from the sides
	col += vec3(0.08, 0.2, 0.42) * smoothstep(0.75, 0.0, uv.x) * (0.55 + 0.45 * vs);
	col += vec3(0.42, 0.08, 0.06) * smoothstep(0.25, 1.0, uv.x) * (0.55 + 0.45 * vs);
	// drifting smoke
	float c = n(uv * vec2(4.0, 3.0) + vec2(TIME * 0.04, -TIME * 0.02)) * n(uv * vec2(7.0, 5.0) - vec2(TIME * 0.03, 0.0));
	col += vec3(0.25, 0.18, 0.08) * smoothstep(0.25, 0.8, c) * 0.35;
	// light rays from the middle (versus)
	vec2 d = uv - vec2(0.5, 0.48);
	float a = atan(d.y, d.x * 1.78);
	float rays = pow(0.5 + 0.5 * sin(a * 18.0 + TIME * 0.6), 6.0) * smoothstep(0.9, 0.05, length(d * vec2(1.78, 1.0)));
	col += vec3(1.0, 0.8, 0.45) * rays * 0.22 * vs;
	col += vec3(1.0, 0.85, 0.55) * exp(-pow(abs(d.x) * 40.0, 2.0)) * 0.35 * vs;
	float vig = smoothstep(1.3, 0.3, length((uv - 0.5) * vec2(1.5, 1.2)));
	COLOR = vec4(col * (0.5 + 0.5 * vig), 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	bg.material = m
	add_child(bg)
	bg.name = "Bg"
	_frame = Control.new()
	_frame.size = Vector2(W, H)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_pick_layer = Control.new()
	_pick_layer.size = Vector2(W, H)
	_pick_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_pick_layer)
	_banner = TurnBanner.new()
	_banner.draft = draft
	_banner.position = Vector2(480, 18)
	_banner.size = Vector2(960, 170)
	_pick_layer.add_child(_banner)
	var mine := draft.mine()
	for side in 2:
		var team_i := mine if side == 0 else 1 - mine
		var head := TeamHead.new()
		head.text = ("Your team  ·  " if side == 0 else "Enemy team  ·  ") + String(SimConst.TEAM_NAMES[team_i])
		head.col = BLUE if side == 0 else RED
		head.right = side == 1
		head.position = Vector2(40 if side == 0 else W - 40 - 430, 104)
		head.size = Vector2(430, 40)
		_pick_layer.add_child(head)
		var y := 150.0
		for p in draft.lineup.teams[team_i]:
			var s := PickSlot.new()
			s.draft = draft
			s.id = String(p.id)
			s.p = p
			s.right = side == 1
			s.col = BLUE if side == 0 else RED
			s.position = Vector2(40 if side == 0 else W - 40 - 430, y)
			s.size = Vector2(430, 168)
			_pick_layer.add_child(s)
			_slots[String(p.id)] = s
			y += 178.0
	# the heroes
	# two rows over the preview's width (904): 8 a row for 16 heroes; with more the tiles narrow (17: 9 of 93 x 112)
	var pool: Array = draft.pool()
	var cols := maxi(8, ceili(pool.size() / 2.0))
	var tw := floorf((904.0 - 8.0 * (cols - 1)) / cols)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.position = Vector2(500, 196)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_pick_layer.add_child(grid)
	for h in pool:
		var tile := HeroTile.new()
		tile.hero = String(h)
		tile.draft = draft
		tile.custom_minimum_size = Vector2(tw, roundf(tw * 1.2))
		var hid := String(h)
		tile.pressed.connect(func(): _choose(hid))
		tile.want.connect(func(): draft.want_me(hid))
		tile.suggest.connect(func(): draft.suggest(hid))
		grid.add_child(tile)
		_tiles[hid] = tile
	_preview = HeroPreview.new()
	_preview.position = Vector2(500, 470)
	_preview.size = Vector2(904, 290)
	_pick_layer.add_child(_preview)
	_lock = BigLock.new()
	_lock.text = "Lock in"
	_lock.position = Vector2(500, 772)
	_lock.size = Vector2(620, 84)
	_lock.pressed.connect(_lock_in)
	_pick_layer.add_child(_lock)
	_random_btn = Button.new()
	_random_btn.text = "Random"
	_random_btn.theme_type_variation = "DarkButton"
	_random_btn.focus_mode = Control.FOCUS_NONE
	_random_btn.position = Vector2(1136, 784)
	_random_btn.size = Vector2(268, 60)
	_random_btn.add_theme_font_size_override("font_size", 20)
	_random_btn.pressed.connect(func():
		Options.click()
		if draft.current() == "me":
			var free: Array = draft.pool().filter(func(h): return not draft.taken(String(h)))
			_choose(String(free[randi() % free.size()]))
			_lock_in())
	_pick_layer.add_child(_random_btn)
	_chat = ChatBox.new()
	_chat.position = Vector2(500, 866)
	_chat.size = Vector2(904, 200)
	_chat.sent.connect(func(text: String): draft.say_me(text))
	_pick_layer.add_child(_chat)
	_vs_layer = VersusLayer.new()
	_vs_layer.draft = draft
	_vs_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vs_layer.visible = false
	add_child(_vs_layer)

# ---- The pick ---------------------------------------------------------------------------------------------------------

func _choose(hero: String) -> void:
	if draft.taken(hero):
		return
	_chosen = hero
	_preview.hero = hero
	_preview.flash = 1.0
	for h in _tiles:
		(_tiles[h] as HeroTile).chosen = h == hero
	_sfx("ui_page", -8.0)

func _lock_in() -> void:
	if draft.current() != "me" or _chosen == "" or draft.taken(_chosen):
		return
	if draft.pick("me", _chosen) == "":
		_sfx("loot_drop_legendary", -2.0)

## Bring the screen in line with the draft: new picks land in their slots, new chat lines come in.
func _sync(quiet := false) -> void:
	var n := draft.picks.size()
	if n != _picks_seen:
		for i in range(_picks_seen, n):
			var id := String(draft.order[i])
			var hero := String(draft.picks.get(id, ""))
			var s: PickSlot = _slots.get(id)
			if s != null:
				s.land(0.0 if quiet else 1.0)
			_vs_layer.place(id, hero)
			var who := "You" if id == "me" else String(draft.profile(id).get("name", ""))
			_chat.add_line("", "%s picked %s" % [who, HeroDraft.hero_name(hero)], U.TEXT_DIM, true)
			if not quiet and id != "me":
				_sfx("skill_unlock" if draft.team_of(id) == draft.mine() else "ui_equip", -6.0)
		_picks_seen = n
		if _chosen != "" and draft.taken(_chosen) and String(draft.picks.get("me", "")) != _chosen:
			_chosen = ""                     # someone else took the hero you were looking at
			_preview.hero = ""
			for h in _tiles:
				(_tiles[h] as HeroTile).chosen = false
	while _chat_seen < draft.chat.size():
		var c: Dictionary = draft.chat[_chat_seen]
		_chat.add_line(String(c.name), String(c.text), U.GOLD if bool(c.get("me", false)) else BLUE, false)
		_chat_seen += 1
	# teammates who said yes to your "add me" (run 2026-10-19 e)
	while _friends_seen < draft.friends_made.size():
		var fid := String(draft.friends_made[_friends_seen])
		_friends_seen += 1
		if not (fid in (Ranked.me().get("friends", []) as Array)):
			Ranked.befriend(fid)
			_chat.add_line("", "You and %s are now friends" % String(draft.profile(fid).get("name", "")), U.TEXT_DIM, true)
	for h in _tiles:
		(_tiles[h] as HeroTile).queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	var bg: ColorRect = get_node("Bg")
	match phase:
		"pick":
			var was := draft.current()
			draft.step(dt)
			_sync()
			if draft.current() == "me" and was != "me":
				_sfx("holy_chime", -2.0)
				if _chosen == "" or draft.taken(_chosen):
					_chosen = ""
			var my_turn := draft.current() == "me"
			_lock.disabled = not my_turn or _chosen == "" or draft.taken(_chosen)
			_lock.text = "Lock in" if my_turn else ("Wait for your turn" if not draft.picks.has("me") else "Locked in")
			_random_btn.disabled = not my_turn
			if draft.done():
				phase = "done"
				_t = 0.0
				_banner.all_done = true
		"done":
			if _t > 1.6:
				_start_versus()
		"versus":
			(bg.material as ShaderMaterial).set_shader_parameter("vs", clampf(_t / 0.6, 0.0, 1.0))
			if _vs_layer.slammed_now():
				_sfx("meteor_impact", -1.0)
				_sfx("war_cry", -6.0)
			if _t > 7.5 and _capture == "":
				phase = "loading"
				_launch()
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 2.5)
		var k := minf(size.x / W, size.y / H)
		_frame.position = ((size - Vector2(W, H) * k) * 0.5).floor() + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake * k
	if _capture != "":
		_frames += 1
		if _frames == _cap_frames:
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

func _start_versus() -> void:
	phase = "versus"
	_t = 0.0
	_pick_layer.visible = false
	_vs_layer.visible = true
	_vs_layer.start()
	_sfx("teleport_whoosh", -4.0)

## Into the match: the ten slots with their picked heroes, the match remembered (leaving it is a loss), loading.
func _launch() -> void:
	var l: Dictionary = draft.lineup.duplicate(true)
	l["heroes"] = draft.picks.duplicate()
	var teams := [[], []]
	var roles := {}
	for side in 2:
		for p in l.teams[side]:
			(teams[side] as Array).append(String(p.id))
			roles[String(p.id)] = int(l.roles.get(String(p.id), 0))
	GameSettings.ranked = Matchmaker.slots_for(l)
	Ranked.begin_match({"teams": teams, "mine": int(l.mine), "heroes": draft.picks.duplicate(), "roles": roles})
	Matchmaker.accepted_match = {}
	LoadingScreen.open(get_tree())
	LoadingScreen.progress(get_tree(), 0.02, "Loading the map")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(MATCH)

# =====================================================================================================================
# Widgets
# =====================================================================================================================

## "Hero Pick", whose turn it is and the turn's ring; "All heroes picked" at the end.
class TurnBanner extends Control:
	var draft: HeroDraft
	var all_done := false
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
	func _draw() -> void:
		var cx := size.x * 0.5
		var f := U.font("title")
		var title := "Hero Pick" if not all_done else "All heroes picked"
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
		draw_string(f, Vector2(cx - tw * 0.5 + 2, 64), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(cx - tw * 0.5, 61), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, U.GOLD)
		if all_done or draft.done():
			return
		var id := draft.current()
		var mine := id == "me"
		var who := "Your turn: pick a hero" if mine else "%s is picking" % String(draft.profile(id).get("name", ""))
		var col := U.GOLD.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 6.0)) if mine else (BLUE if draft.team_of(id) == draft.mine() else RED)
		var b := U.font("bold")
		var line := "Pick %d of 10   ·   %s" % [draft.turn + 1, who]
		var lw := b.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		if mine:
			for i in 3:
				draw_style_box(RankedNum.flat(Color(U.GOLD, 0.05 + 0.04 * sin(_t * 6.0)), Color(0, 0, 0, 0), 20), Rect2(cx - lw * 0.5 - 30 - i * 8, 84 - i * 6, lw + 60 + i * 16, 48 + i * 12))
		draw_string(b, Vector2(cx - lw * 0.5, 116), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
		# the turn's ring (yours: 30 s; a bot's: while it decides)
		var c := Vector2(cx + tw * 0.5 + 70, 44)
		var frac := draft.time_left() / HeroDraft.YOUR_TIME if mine else 1.0 - fmod(draft.t, 4.0) / 4.0
		draw_arc(c, 30, 0, TAU, 48, Color(1, 1, 1, 0.12), 6.0, true)
		draw_arc(c, 30, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, (GREEN_HI if frac > 0.33 else RED) if mine else Color(1, 1, 1, 0.5), 6.0, true)
		if mine:
			var n := str(int(ceil(draft.time_left())))
			var nw := b.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(b, c + Vector2(-nw * 0.5, 8), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, U.TEXT)

class TeamHead extends Control:
	var text := ""
	var col := Color.WHITE
	var right := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var f := U.font("title")
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, Vector2(size.x - tw if right else 0.0, 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
		draw_line(Vector2(0, 38), Vector2(size.x, 38), Color(col, 0.4), 2.0)

## One player's place in the pick: pick number, picture, name, rank, role, and the hero once picked (it lands with a
## flash, a bounce and a ring of sparks). The player picking now glows.
class PickSlot extends Control:
	var draft: HeroDraft
	var id := ""
	var p := {}
	var right := false
	var col := Color.WHITE
	var _land := -1.0                      # seconds since the hero landed (-1 not yet)
	var _t := 0.0
	var _av: Avatar
	var _sparks: Array = []
	func _ready() -> void:
		# right-click a player in the pick: the player menu (their profile opens over the pick) (run 2026-10-20)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "Right-click: profile and more"
		_av = Avatar.new()
		_av.size = Vector2(56, 56)
		_av.position = Vector2(size.x - 56 - 64, 14) if right else Vector2(64, 14)
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_av.set_spec(p.get("avatar", {"k": "none"}))
		add_child(_av)
	func _gui_input(e: InputEvent) -> void:
		if SocialUi.is_right(e) and id != "":
			PlayerMenu.open(self, id, SocialUi.at(self, e))
			accept_event()
	func land(strength: float) -> void:
		_land = 0.0 if strength > 0.0 else 9.0
		if strength > 0.0:
			for i in 26:
				var a := randf() * TAU
				_sparks.append([Vector2.ZERO, Vector2(cos(a), sin(a)) * randf_range(120.0, 380.0), randf_range(0.5, 1.0)])
	func _process(dt: float) -> void:
		_t += dt
		if _land >= 0.0:
			_land += dt
		for s in _sparks:
			s[0] += s[1] * dt
			s[1] *= 0.9
			s[2] -= dt * 1.4
		_sparks = _sparks.filter(func(s): return float(s[2]) > 0.0)
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var now := draft.current() == id
		var you := id == "me"
		var bg := Color(0.06, 0.075, 0.11, 0.92)
		var rim := Color(col, 0.35)
		if now:
			var pulse := 0.5 + 0.5 * sin(_t * 6.0)
			for i in 3:
				draw_style_box(RankedNum.flat(Color(col, 0.07 + 0.06 * pulse), Color(0, 0, 0, 0), 12 + i * 4), r.grow(4 + i * 6))
			rim = col.lerp(Color.WHITE, 0.4 * pulse)
		if you:
			rim = U.GOLD if not now else rim
		draw_style_box(RankedNum.flat(bg, rim, 8, 2 if now or you else 1), r)
		draw_rect(Rect2(0 if not right else size.x - 5, 0, 5, size.y), col)
		# the pick number
		var nc := Vector2(32, 42) if not right else Vector2(size.x - 32, 42)
		draw_circle(nc, 21, Color(0, 0, 0, 0.6))
		draw_arc(nc, 21, 0, TAU, 32, U.GOLD if now else Color(col, 0.8), 2.0, true)
		var f := U.font("title")
		var num := str(draft.number_of(id))
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, nc + Vector2(-nw * 0.5, 8), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, U.GOLD if now else U.TEXT)
		# the hero frame
		var hs := 140.0
		var hr := Rect2(size.x - hs - 14, 14, hs, hs) if not right else Rect2(14, 14, hs, hs)
		var hero := String(draft.picks.get(id, ""))
		draw_rect(hr, Color(0.02, 0.025, 0.04))
		if hero == "":
			var q := "?" if not now else "..."
			var qw := f.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
			draw_string(f, hr.get_center() + Vector2(-qw * 0.5, 22), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(col, 0.35 + (0.3 * sin(_t * 5.0) if now else 0.0)))
		else:
			var k := 1.0
			if _land < 0.5:
				k = 1.35 - 0.35 * _ease_back(clampf(_land / 0.5, 0.0, 1.0))
			var tex := U.hero_portrait(hero)
			var rr := Rect2(hr.get_center() - hr.size * 0.5 * k, hr.size * k)
			if tex:
				draw_texture_rect(tex, rr, false)
			if _land < 0.6:
				draw_rect(rr, Color(1, 1, 1, 0.8 * (1.0 - _land / 0.6)))
			for i in 3:
				var ring := _land * 400.0 - i * 40.0
				if ring > 0.0 and _land < 0.9:
					draw_arc(hr.get_center(), ring, 0, TAU, 48, Color(U.GOLD, 0.6 * (1.0 - _land / 0.9)), 3.0, true)
		draw_rect(hr, U.GOLD if hero != "" and you else Color(col, 0.6), false, 2.0)
		for s in _sparks:
			draw_circle(hr.get_center() + s[0], 3.0 * float(s[2]) + 1.0, Color(1.0, 0.85, 0.4, float(s[2])))
		# name, rank, role
		var tx := 64.0 + 66.0 if not right else 14.0 + hs + 14.0
		var tw := size.x - hs - 14.0 - 140.0
		var b := U.font("bold")
		var nm := "You" if you and String(p.get("name", "")) == "" else String(p.get("name", ""))
		var xr := func(txt: String, fs: int, fnt: Font) -> float:
			return tx if not right else size.x - 64.0 - 66.0 - minf(fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, tw)
		var nfs := 20
		while b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > tw and nfs > 12:
			nfs -= 1
		draw_string(b, Vector2(xr.call(nm, nfs, b), 40), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, nfs, U.GOLD if you else U.TEXT)
		var tier := Ranked.tier_for(p)
		var rk := Ranked.rank_label(p)
		var bd := U.font("body")
		draw_string(bd, Vector2(xr.call(rk, 15, bd), 62), rk, HORIZONTAL_ALIGNMENT_LEFT, tw, 15, U.TEXT_DIM)
		var role := RankedNum.role(draft.role_of(id))
		draw_string(bd, Vector2(xr.call(role, 15, bd), 84), role, HORIZONTAL_ALIGNMENT_LEFT, tw, 15, Color(col, 0.9))
		if Ranked.mvp_last(p):
			var rw := bd.get_string_size(role, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var px: float = xr.call(role, 15, bd)
			RankedNum.mvp_tag(self, Vector2(px + rw + 14 + 118 if not right else px - 12, 66), 1.0, _t)
		var ic := RankEmblem.icon(tier)
		if ic:
			draw_texture_rect(ic, Rect2((24.0 if not right else size.x - 24.0 - 52.0), 96, 52, 52), false)
		var line := HeroDraft.hero_name(hero) if hero != "" else ("Picking..." if now else ("Wants %s" % HeroDraft.hero_name(String(draft.wants[id])) if draft.team_of(id) == draft.mine() and draft.wants.has(id) and draft._said_want.has(id) else ""))
		if line != "":
			var lf := f if hero != "" else bd
			var fs := 24 if hero != "" else 15
			while lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw and fs > 12:
				fs -= 1
			draw_string(lf, Vector2(xr.call(line, fs, lf), 136), line, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, U.GOLD if hero != "" else U.TEXT_DIM)
	static func _ease_back(x: float) -> float:
		var c := 1.7
		return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

## A hero to pick: its face and name; it lifts on hover, glows gold when chosen, and once taken it dims with a band
## in the picker's team colour and their pick number.
class HeroTile extends Control:
	signal pressed
	signal want                            # Alt+click: you want this hero
	signal suggest                         # Shift+click: a teammate should pick it
	var hero := ""
	var draft: HeroDraft
	var chosen := false
	var _hot := 0.0
	var _in := false
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_in = true
			Options.click())
		mouse_exited.connect(func(): _in = false)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.alt_pressed and not draft.taken(hero):
				Options.click()
				want.emit()
			elif mb.shift_pressed and not draft.taken(hero):
				Options.click()
				suggest.emit()
			else:
				pressed.emit()
			accept_event()
	func _process(dt: float) -> void:
		_t += dt
		_hot = move_toward(_hot, 1.0 if _in and not draft.taken(hero) else 0.0, dt * 7.0)
		queue_redraw()
	func _draw() -> void:
		var taken := draft.taken(hero)
		var lift := -5.0 * _hot
		var r := Rect2(Vector2(0, lift), size)
		if chosen and not taken:
			for i in 3:
				draw_style_box(RankedNum.flat(Color(U.GOLD, 0.12 + 0.06 * sin(_t * 5.0)), Color(0, 0, 0, 0), 8 + i * 4), r.grow(3 + i * 4))
		draw_rect(r, Color(0.03, 0.035, 0.05))
		var tex := U.hero_portrait(hero)
		if tex:
			draw_texture_rect(tex, Rect2(r.position, Vector2(size.x, size.x)), false, Color(1, 1, 1, 0.25) if taken else Color(1, 1, 1, 0.85 + 0.15 * _hot))
		var f := U.font("bold")
		var nm := HeroDraft.hero_name(hero)
		var fs := 15
		while f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 6 and fs > 10:
			fs -= 1
		var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, r.position + Vector2((size.x - w) * 0.5, size.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, U.TEXT_DIM if taken else (U.GOLD if chosen else U.TEXT))
		if taken:
			var who := ""
			for id in draft.picks:
				if String(draft.picks[id]) == hero:
					who = String(id)
			var c := BLUE if draft.team_of(who) == draft.mine() else RED
			var band := Rect2(r.position + Vector2(0, size.x * 0.5 - 13), Vector2(size.x, 26))
			draw_rect(band, Color(c, 0.85))
			var t := "#%d %s" % [draft.number_of(who), "You" if who == "me" else String(draft.profile(who).get("name", ""))]
			draw_string(U.font("bold"), band.position + Vector2(4, 18), t, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12, Color.WHITE)
		var m := Ranked.hero_medal(Ranked.me(), hero)
		if int(m.medal) > 0 and not taken:
			HeroBadge.paint(self, Rect2(r.position + Vector2(size.x - 44, -2), Vector2(44, 44)), hero, m, _t)
		draw_rect(r, U.GOLD if chosen and not taken else (Color(1, 1, 1, 0.15 + 0.4 * _hot)), false, 2.0 if chosen else 1.0)

## The hero you selected: big face, name and title, roles, attribute and range, its skills.
class HeroPreview extends Control:
	var hero := ""
	var flash := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		flash = maxf(0.0, flash - dt * 3.0)
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(RankedNum.flat(Color(0.05, 0.065, 0.1, 0.92), Color(U.GOLD, 0.35), 10), r)
		var f := U.font("title")
		if hero == "":
			var t := "Choose a hero"
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(U.TEXT_DIM, 0.6))
			var s2 := "Your teammates say in chat which heroes they want."
			var sw := U.font("body").get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(U.font("body"), Vector2((size.x - sw) * 0.5, size.y * 0.5 + 40), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
			return
		var d := SimData.unit(hero)
		var pr := Rect2(16, 16, size.y - 32, size.y - 32)
		var tex := U.hero_portrait(hero)
		if tex:
			draw_texture_rect(tex, pr, false)
		draw_rect(pr, U.GOLD, false, 2.0)
		if flash > 0.0:
			draw_rect(pr, Color(1, 1, 1, 0.5 * flash))
		var x := pr.end.x + 24.0
		draw_string(f, Vector2(x, 62), String(d.get("name", hero)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 42, U.GOLD)
		draw_string(U.font("body"), Vector2(x, 92), String(d.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, U.TEXT)
		var roles: Array = SimBotKits.roles(hero).slice(0, 3)
		var rl := "Plays " + ", ".join(roles.map(func(rr): return RankedNum.role(int(rr))))
		draw_string(U.font("bold"), Vector2(x, 126), rl, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 16, 17, U.TEXT)
		var attr: String = {"str": "Strength", "agi": "Agility", "int": "Intelligence"}.get(String(d.get("primary", "")), "")
		var rng := "Ranged" if float(d.get("projectile_speed", 0.0)) > 0.0 else "Melee"
		draw_string(U.font("body"), Vector2(x, 152), "%s  ·  %s" % [attr, rng], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, U.TEXT_DIM)
		var ax := x
		for aid in (d.get("abilities", []) as Array).slice(0, 6):
			IconBorder.draw_icon(self, U.ability_icon(String(aid)), Rect2(ax, 174, 60, 60), IconBorder.ability_kind(String(aid)))
			ax += 72.0
		var me := Ranked.me()
		var hs = (me.get("hero_stats", {}) as Dictionary).get(hero, [0, 0])
		var g := int(hs[0]) + int(hs[1])
		var m := Ranked.hero_medal(me, hero)
		var mine := "Your record: %d W - %d L  ·  %s  ·  %s XP" % [int(hs[0]), int(hs[1]), String(m.name), RankedNum.num(int(m.xp))] if g > 0 else "You have not played this hero in ranked yet"
		draw_string(U.font("body"), Vector2(x, 264), mine, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HeroBadge.metal(m) if int(m.medal) > 0 else U.TEXT_DIM)

## Lock in: a big green button (grey when it is not your turn).
class BigLock extends Control:
	signal pressed
	var text := ""
	var disabled := false
	var _hot := false
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hot = true)
		mouse_exited.connect(func(): _hot = false)
	func _gui_input(e: InputEvent) -> void:
		if disabled:
			return
		if e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			pressed.emit()
			accept_event()
	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var base := Color(0.24, 0.74, 0.33) if not disabled else Color(0.2, 0.23, 0.24)
		if not disabled:
			for i in 3:
				draw_style_box(RankedNum.flat(Color(GREEN_HI, 0.08 + 0.05 * sin(_t * 4.0) + (0.06 if _hot else 0.0)), Color(0, 0, 0, 0), 12 + i * 5), r.grow(4 + i * 6))
		draw_style_box(RankedNum.flat(base.darkened(0.15), GREEN_HI if not disabled else Color(1, 1, 1, 0.15), 10, 2), r)
		draw_style_box(RankedNum.flat(Color(base.lightened(0.2 if _hot else 0.12), 0.9), Color(0, 0, 0, 0), 9), Rect2(2, 2, size.x - 4, size.y * 0.5 - 2))
		var f := U.font("title")
		var label := text.to_upper()
		var fs := 34
		while f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 40 and fs > 14:
			fs -= 2
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 if not disabled else 0.45))

## Team chat and the pick log; new lines slide in.
class ChatBox extends Control:
	## (run 2026-10-19 e) a line to type in: Enter to send (Enter anywhere starts typing).
	signal sent(text: String)
	var lines: Array = []                  # [name, text, color, system, age]
	var input: LineEdit
	const ROWS := 5
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		input = LineEdit.new()
		input.placeholder_text = "Say to your team (Enter)"
		input.max_length = 120
		input.position = Vector2(10, size.y - 44)
		input.size = Vector2(size.x - 20, 36)
		input.add_theme_font_size_override("font_size", 16)
		input.text_submitted.connect(func(t: String):
			if t.strip_edges() != "":
				sent.emit(t.strip_edges())
			input.text = ""
			input.release_focus())
		add_child(input)
	func _unhandled_key_input(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] and is_visible_in_tree():
			input.grab_focus()
			get_viewport().set_input_as_handled()
	func add_line(nm: String, text: String, col: Color, system: bool) -> void:
		lines.append([nm, text, col, system, 0.0])
		while lines.size() > ROWS:
			lines.pop_front()
	func _process(dt: float) -> void:
		for l in lines:
			l[4] = float(l[4]) + dt
		queue_redraw()
	func _draw() -> void:
		draw_style_box(RankedNum.flat(Color(0.03, 0.04, 0.06, 0.85), Color(1, 1, 1, 0.08), 8), Rect2(Vector2.ZERO, size))
		draw_string(U.font("bold"), Vector2(14, 22), "Team chat", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, U.TEXT_DIM)
		var hint := "Alt+click a hero: you want it    Shift+click: ask a teammate to pick it"
		var hw := U.font("body").get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(U.font("body"), Vector2(size.x - hw - 14, 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(U.TEXT_DIM, 0.8))
		var y := 44.0
		for l in lines:
			var a := clampf(float(l[4]) / 0.25, 0.0, 1.0)
			var x := 14.0 - (1.0 - a) * 30.0
			var b := U.font("bold")
			if bool(l[3]):
				draw_string(U.font("body"), Vector2(x, y), String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 15, Color(U.TEXT_DIM, a))
			else:
				var nm := String(l[0]) + ": "
				var nw := b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(b, Vector2(x, y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(l[2], a))
				draw_string(U.font("body"), Vector2(x + nw, y), String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 28 - nw, 16, Color(U.TEXT, a))
			y += 21.0

## The versus shot: the 3D field (VersusStage) at the window's full size, and over it the team names, a plate over each
## hero (the player's name, then their rank, then their medal on that hero), VS slamming down, the flash, the loading
## line.
class VersusLayer extends Control:
	var draft: HeroDraft
	var stage: VersusStage
	var _vp: SubViewport
	var _over: Control
	var _t := -1.0
	var _slammed := false
	var _slam_flag := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var svc := SubViewportContainer.new()
		svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(svc)
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		svc.add_child(_vp)
		stage = VersusStage.new()
		_vp.add_child(stage)
		_over = Control.new()
		_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.draw.connect(_draw_over)
		add_child(_over)
	## A picked hero takes its place on the field (your hero leads your team's wedge).
	func place(id: String, hero: String) -> void:
		var side := 0 if draft.team_of(id) == draft.mine() else 1
		var team: Array = draft.lineup.teams[draft.team_of(id)]
		var ids: Array = team.map(func(p): return String(p.id))
		if ids.has("me"):
			ids.erase("me")
			ids.push_front("me")
		stage.add_hero(id, hero, side, ids.find(id))
	func start() -> void:
		_t = 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		stage.begin()
	func slammed_now() -> bool:
		if _slam_flag:
			_slam_flag = false
			return true
		return false
	func _process(dt: float) -> void:
		if _t < 0.0:
			return
		_t += dt
		if not _slammed and _t >= 2.4:
			_slammed = true
			_slam_flag = true
			stage.shake(1.0)
		_over.queue_redraw()
	func _k() -> float:
		return minf(size.x / W, size.y / H)
	func _off() -> Vector2:
		return ((size - Vector2(W, H) * _k()) * 0.5).floor()
	## Draw in the 1920 x 1080 design space, centred in the window.
	func _draw_over() -> void:
		if _t < 0.0:
			return
		var k := _k()
		_over.draw_set_transform(_off(), 0.0, Vector2(k, k))
		var mine := draft.mine()
		var f := U.font("title")
		var b := U.font("bold")
		# letterbox bars for the shot
		var bar := clampf(_t / 0.6, 0.0, 1.0)
		_over.draw_rect(Rect2(-2000, -2000, W + 4000, 2000 + 50.0 * bar), Color(0, 0, 0, 0.9))
		_over.draw_rect(Rect2(-2000, H - 100.0 * bar, W + 4000, 2000), Color(0, 0, 0, 0.92))
		# the team names, in the bottom bar
		for side in 2:
			var team_i := mine if side == 0 else 1 - mine
			var nm := String(SimConst.TEAM_NAMES[team_i]).to_upper()
			var col := BLUE if side == 0 else RED
			var a := clampf((_t - 0.5) / 0.5, 0.0, 1.0)
			var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			var x := 50.0 if side == 0 else W - 50.0 - tw
			_over.draw_string(f, Vector2(x, H - 52), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(col.lightened(0.15), a))
			var avg := "Average MMR %s" % RankedNum.num(int(draft.lineup.avg[team_i]))
			var aw := b.get_string_size(avg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			_over.draw_string(b, Vector2(52.0 if side == 0 else W - 52.0 - aw, H - 22), avg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(U.TEXT, a))
		# a plate over each hero: name, rank, medal on the hero
		var plates: Array = []
		var cam := stage.cam
		var vs := _vp.size
		for id in stage.heroes:
			var hp := stage.head_point(id)
			if cam.is_position_behind(hp):
				continue
			var sp := cam.unproject_position(hp)
			# viewport pixels -> window -> design space
			var wpx := sp * (size / Vector2(vs))
			var d := (wpx - _off()) / k
			var depth := cam.global_position.distance_to(hp)
			plates.append({"id": id, "pos": d, "depth": depth, "rect": Rect2(d.x - 95, maxf(58.0, d.y - 118), 190, 112)})
		# nearer plates keep their place; farther ones move up out of the way
		plates.sort_custom(func(a, c): return float(a.depth) < float(c.depth))
		for i in plates.size():
			for j in i:
				var r: Rect2 = plates[i].rect
				var o: Rect2 = plates[j].rect
				if r.intersects(o):
					var up := o.position.y - r.size.y - 6.0
					if up >= 58.0:
						r.position.y = up
					else:
						r.position.x = o.end.x + 6.0 if r.get_center().x >= o.get_center().x else o.position.x - r.size.x - 6.0
					plates[i].rect = r
		for i in plates.size():
			var rr: Rect2 = plates[i].rect
			rr.position.x = clampf(rr.position.x, 12.0, W - rr.size.x - 12.0)      # never off the screen
			plates[i].rect = rr
			_plate(plates[i], i)
		# VS
		if _t >= 2.15:
			var u := clampf((_t - 2.15) / 0.25, 0.0, 1.0)
			var scl := lerpf(4.0, 1.0, u * u)
			var fs := int(120 * scl)
			var tw2 := f.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var c := Vector2(W * 0.5, 610)
			for i in 4:
				_over.draw_circle(c, 90.0 + i * 26.0, Color(1.0, 0.7, 0.3, 0.06 * u))
			_over.draw_string(f, c + Vector2(-tw2 * 0.5 + 5, fs * 0.36 + 5), "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7 * u))
			_over.draw_string(f, c + Vector2(-tw2 * 0.5, fs * 0.36), "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.48, u))
			if _t < 3.0:
				var fl := clampf(1.0 - (_t - 2.4) / 0.5, 0.0, 1.0) if _t >= 2.4 else 0.0
				_over.draw_rect(Rect2(-2000, -2000, W + 4000, H + 4000), Color(1, 0.95, 0.85, 0.6 * fl))
				var ring := (_t - 2.4) * 1500.0
				if ring > 0.0:
					_over.draw_arc(c, ring, 0, TAU, 64, Color(1.0, 0.85, 0.5, 0.7 * fl), 8.0, true)
		if _t > 4.5:
			var a2 := clampf((_t - 4.5) / 0.5, 0.0, 1.0)
			var t := "Loading the match" + ".".repeat(1 + int(_t * 2.0) % 3)
			var tw3 := b.get_string_size("Loading the match...", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			_over.draw_string(b, Vector2((W - tw3) * 0.5, H - 40), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(U.TEXT, a2))
	func _plate(pl: Dictionary, order: int) -> void:
		var id := String(pl.id)
		var a := clampf((_t - 1.2 - 0.08 * float(order)) / 0.4, 0.0, 1.0)
		if a <= 0.0:
			return
		var p := draft.profile(id)
		var side := 0 if draft.team_of(id) == draft.mine() else 1
		var col := BLUE if side == 0 else RED
		var r: Rect2 = pl.rect
		r.position.y += (1.0 - a) * 14.0
		var you := id == "me"
		_over.draw_style_box(RankedNum.flat(Color(0.02, 0.03, 0.05, 0.78 * a), Color(U.GOLD if you else col, 0.85 * a), 8, 2 if you else 1), r)
		var b := U.font("bold")
		var nm := String(p.get("name", ""))
		var fs := 19
		while b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 14 and fs > 11:
			fs -= 1
		var nw := b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_over.draw_string(b, Vector2(r.position.x + (r.size.x - nw) * 0.5, r.position.y + 26), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(U.GOLD if you else U.TEXT, a))
		# then the rank
		var tier := Ranked.tier_for(p)
		var ic := RankEmblem.icon(tier)
		if ic:
			_over.draw_texture_rect(ic, Rect2(r.position.x + 8, r.position.y + 32, 42, 42), false, Color(1, 1, 1, a))
		var rk := Ranked.rank_label(p)
		_over.draw_string(U.font("bold"), Vector2(r.position.x + 54, r.position.y + 50), rk, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60, 14, Color(U.TEXT, a))
		_over.draw_string(U.font("body"), Vector2(r.position.x + 54, r.position.y + 68), "%s MMR" % RankedNum.num(int(p.mmr)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(U.TEXT_DIM, a))
		# and the medal on the hero they play
		var hero := String(draft.picks.get(id, ""))
		var m := Ranked.hero_medal(p, hero)
		var line := "%s  ·  %s" % [HeroDraft.hero_name(hero), String(m.name)]
		if int(m.medal) > 0 or int(m.top) > 0:
			HeroBadge.paint(_over, Rect2(r.position.x + 6, r.position.y + 74, 36, 36), hero, m, _t)
		_over.draw_string(U.font("body"), Vector2(r.position.x + 46, r.position.y + 98), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50, 13,
			Color(HeroBadge.metal(m) if int(m.medal) > 0 or int(m.top) > 0 else U.TEXT_DIM, a))
		# a thin line down to the hero
		_over.draw_line(Vector2(r.get_center().x, r.end.y), pl.pos + Vector2(0, -2), Color(col, 0.5 * a), 1.5)
		# MVP in their last game (run 2026-10-19 e): a gold tag on the plate
		if Ranked.mvp_last(p):
			RankedNum.mvp_tag(_over, Vector2(r.end.x - 4, r.position.y - 6), a, _t)
