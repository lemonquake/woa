class_name Options
extends RefCounted
## Player options (Options screen), saved in user://options.json and applied at boot.
##
## Sound: four buses (Master, Effects, Interface, Ambience). Sliders are 0-100%; loudness follows the ear, so every
## halving of a slider halves how loud it sounds (about -10 dB): db = 10 * log2(p). Master starts at 50%.
## Video: monitor, window mode, resolution, V-Sync, frame limit, render scale, quality preset, FPS counter.
## Game: edge pan, camera speed, centre the camera on the hero at respawn, screen shake, damage numbers.
## Cursor: Borderless and Fullscreen always keep the cursor inside the game window (so edge panning cannot lose it on
## a second screen); Windowed does so when "Lock cursor to window" is on.
## Bots: learn from games (BotMemory, on by default), show their team chat.
## Automated runs (--capture, --bench) keep the project's window and quality settings so captures stay comparable.

const PATH := "user://options.json"
const BUSES := ["Effects", "Interface", "Ambience"]
const WINDOW_MODES := ["Windowed", "Borderless", "Fullscreen"]
const RESOLUTIONS := ["Fit screen", "1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440", "3840 x 2160"]
const FRAME_LIMITS := [30, 60, 120, 144, 240, 0]          # 0 = unlimited
const QUALITIES := ["Low", "Medium", "High", "Ultra"]

const DEFAULTS := {
	"master": 0.5, "effects": 1.0, "interface": 1.0, "ambience": 1.0, "mute_unfocused": true,
	"monitor": 0, "window_mode": 0, "resolution": 0, "vsync": true, "frame_limit": 5, "render_scale": 1.0, "quality": 2,
	"show_fps": false,
	"edge_pan": true, "lock_cursor": false, "camera_speed": 32.0, "screen_shake": true, "damage_numbers": true, "center_on_respawn": true,
	"bots_learn": true, "bot_chat": true, "bot_trash_talk": true, "quick_cast": false, "llm_chat": false,
}

static var data := {}
static var _loaded := false
static var _agent: Node
static var _placed_monitor := -1

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	data = DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if d is Dictionary:
			for k in DEFAULTS:
				if d.has(k) and typeof(d[k]) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
					data[k] = d[k]
	_sanitize()

static func _sanitize() -> void:
	for k in ["master", "effects", "interface", "ambience"]:
		data[k] = clampf(float(data[k]), 0.0, 1.0)
	data.monitor = clampi(int(data.monitor), 0, 16)
	data.window_mode = clampi(int(data.window_mode), 0, WINDOW_MODES.size() - 1)
	data.resolution = clampi(int(data.resolution), 0, RESOLUTIONS.size() - 1)
	data.frame_limit = clampi(int(data.frame_limit), 0, FRAME_LIMITS.size() - 1)
	data.quality = clampi(int(data.quality), 0, QUALITIES.size() - 1)
	data.render_scale = clampf(float(data.render_scale), 0.5, 1.0)
	data.camera_speed = clampf(float(data.camera_speed), 12.0, 60.0)
	for k in ["mute_unfocused", "vsync", "show_fps", "edge_pan", "lock_cursor", "screen_shake", "damage_numbers", "center_on_respawn",
			"bots_learn", "bot_chat", "bot_trash_talk", "llm_chat"]:
		data[k] = bool(data[k])

static func get_value(key: String):
	_ensure()
	return data.get(key, DEFAULTS.get(key))

static func set_value(key: String, v) -> void:
	_ensure()
	data[key] = v
	_sanitize()

static func save() -> void:
	_ensure()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))

static func reset() -> void:
	data = DEFAULTS.duplicate()
	_loaded = true

## The Effects slider's 100% plays effects at 60% of their level (owner's request 2026-10-17): 10 * log2(0.6) = -7.4 dB.
const EFFECTS_CEILING := 0.6

## Slider fraction (0..1) to decibels: each halving is -10 dB (half as loud to the ear); 0 is silence.
static func to_db(p: float) -> float:
	return -80.0 if p <= 0.001 else 10.0 * log(p) / log(2.0)

static func automated() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture") or a.begins_with("--bench"):
			return true
	return false

## Create the sound buses if they are missing (Effects, Interface and Ambience all feed Master).
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

static func apply_audio() -> void:
	_ensure()
	ensure_buses()
	var mute: bool = _agent != null and _agent.get("unfocused") == true and bool(data.mute_unfocused)
	AudioServer.set_bus_volume_db(0, to_db(float(data.master)))
	AudioServer.set_bus_mute(0, mute or float(data.master) <= 0.001)
	for b in BUSES:
		var i := AudioServer.get_bus_index(b)
		var p := float(data[String(b).to_lower()])
		# sound effects top out at 60% of their real level: the slider's 100% is 60% (owner's request 2026-10-17)
		var real := p * EFFECTS_CEILING if String(b) == "Effects" else p
		AudioServer.set_bus_volume_db(i, to_db(real))
		AudioServer.set_bus_mute(i, p <= 0.001)

## Monitor choices: "Main monitor" (the one Windows calls main), then every monitor by number and size.
static func monitor_names() -> Array:
	var names := ["Main monitor"]
	for i in DisplayServer.get_screen_count():
		var sz := DisplayServer.screen_get_size(i)
		names.append("Monitor %d (%d x %d)" % [i + 1, sz.x, sz.y])
	return names

## The screen the game window belongs on: the main one, or the chosen one while it is plugged in.
static func monitor_screen() -> int:
	_ensure()
	var m := int(data.monitor) - 1
	return m if m >= 0 and m < DisplayServer.get_screen_count() else DisplayServer.get_primary_screen()

static func apply_video(tree: SceneTree) -> void:
	_ensure()
	if automated():
		return
	var win := tree.root
	var screen := monitor_screen()
	# only at boot and when the Monitor choice changes, so a window dragged to another screen stays there
	if int(data.monitor) != _placed_monitor and DisplayServer.window_get_current_screen() != screen:
		# move as a plain window first: Windows keeps a fullscreen or maximized window on its old monitor
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(screen)
	_placed_monitor = int(data.monitor)
	match int(data.window_mode):
		0:
			if int(data.resolution) == 0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var p := String(RESOLUTIONS[int(data.resolution)]).split(" x ")
				var sz := Vector2i(int(p[0]), int(p[1]))
				var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
				sz = Vector2i(mini(sz.x, scr.size.x), mini(sz.y, scr.size.y))
				DisplayServer.window_set_size(sz)
				DisplayServer.window_set_position(scr.position + (scr.size - sz) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	apply_cursor()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FRAME_LIMITS[int(data.frame_limit)]
	win.scaling_3d_scale = float(data.render_scale)
	var q := int(data.quality)                # High matches the project settings (4x MSAA, 4096 soft-low shadows)
	win.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][q]
	win.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])

## Keep the cursor inside the window in Borderless and Fullscreen (and in Windowed with "Lock cursor to window").
## Windows releases the clip when the game loses focus; the options agent calls this again when it comes back.
static func apply_cursor() -> void:
	_ensure()
	var lock := int(data.window_mode) != 0 or bool(data.lock_cursor)
	if automated():
		lock = false
	var want := Input.MOUSE_MODE_CONFINED if lock else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED] and Input.mouse_mode != want:
		Input.mouse_mode = want

## Match-only quality switches (the environment and sun live in the match scene): SSAO from High, glow from Medium;
## the sun's shadow in two cascades from High, one on Low and Medium (half the shadow draw calls in fights).
static func apply_environment(env: Environment, sun: DirectionalLight3D = null) -> void:
	_ensure()
	if env == null or automated():
		return
	var q := int(data.quality)
	env.ssao_enabled = q >= 2
	env.glow_enabled = q >= 1
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL

## A quiet menu click on the Interface bus (played by the persistent helper node).
static func click() -> void:
	if _agent and is_instance_valid(_agent) and _agent.is_inside_tree():
		_agent.click()

## The persistent helper node (background mute, FPS counter, menu clicks). Safe to call repeatedly.
static func install(tree: SceneTree) -> void:
	_ensure()
	if _agent == null or not is_instance_valid(_agent):
		_agent = preload("res://src/core/options_agent.gd").new()
		tree.root.add_child.call_deferred(_agent)

## Everything at once (boot and "Reset to defaults").
static func apply_all(tree: SceneTree) -> void:
	install(tree)
	apply_audio()
	apply_video(tree)
