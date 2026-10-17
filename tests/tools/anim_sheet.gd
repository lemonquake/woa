extends SceneTree
## Animation contact sheets (run 2026-10-15 g): for each hero, its idle, attacks, cast and run sampled at even times
## from the front and from the side, in its real look with its weapons, one sheet per hero. For finding limbs that
## twist too far and parts that pass through the body or the weapons.
##   godot --path . -s tests/tools/anim_sheet.gd -- --heroes=kragg,ezee --out=work/lemondev/x/anim [--frames=8]
##   [--clips=idle_shield,sword_1] [--yaws=30,-70] [--fov=14] [--raw: the clips before the repair]
##   [--cell=420x560] [--page=4: at most this many rows per image, <hero>_p0.png, _p1.png ...] [--aim=1.2: the
##   height the close camera looks at, with --fov]

const COLS := 8
var CELL := Vector2i(300, 420)
var _page := 0
var _aim := 1.2

var _out := "work/anim"
var _frames := 8
var _heroes: Array = []
var _clips_only: Array = []
var _yaws: Array = [0.0, PI * 0.5]
var _fov := 0.0                            # > 0: a closer camera on the upper body

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--heroes="):
			_heroes = Array(a.substr(9).split(",", false))
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--yaws="):
			_yaws = Array(a.substr(7).split(",", false)).map(func(x): return deg_to_rad(float(x)))
		elif a.begins_with("--cell="):
			var wh := a.substr(7).split("x")
			CELL = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("--page="):
			_page = int(a.substr(7))
		elif a.begins_with("--aim="):
			_aim = float(a.substr(6))
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a == "--raw":
			# the clips as built into the bodies (no RepairedClips repair)
			RepairedClips.disabled = true
		elif a.begins_with("--clips="):
			_clips_only = Array(a.substr(8).split(",", false))
	if _heroes.is_empty():
		_heroes = Array(GameSettings.HEROES)
	_run.call_deferred()

func _clips(id: String) -> Array:
	if not _clips_only.is_empty():
		return _clips_only
	var cfg := ModelCatalog.info(String(SimData.unit(id).model))
	var out: Array = [String(cfg.get("idle", "idle"))]
	var st := ModelCatalog.anim(cfg, String(HeroStage.IDLE.get(id, "")))
	if st != "" and not (st in out):
		out.append(st)
	var fl := ModelCatalog.anim(cfg, String(HeroStage.FLOURISH.get(id, "")))       # the Hero Select flourish
	if fl != "" and not (fl in out):
		out.append(fl)
	for c in cfg.get("attack", []):
		out.append(String(c))
	if String(cfg.get("cast", "")) != "" and not (String(cfg.cast) in out):
		out.append(String(cfg.cast))
	for aid in SimData.unit(id).abilities:
		var an := ModelCatalog.anim(cfg, String(SimData.ability(String(aid)).get("anim", "")))
		if an != "" and not (an in out):
			out.append(an)
	out.append(String(cfg.get("run", "run")))
	# pushes, the stun, hit reactions and deaths, as the game plays them (their motion-capture stand-ins)
	for c in ["knockback", "getup", "launch", "wall_impact", "hit_heavy", "hit_light", "idle_hurt"] + Array(cfg.get("deaths", [cfg.get("death", "death")])):
		var mc := ModelCatalog.anim(cfg, String(c))
		if not (mc in out):
			out.append(mc)
	return out

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 960))
	await process_frame
	for id in _heroes:
		var stage := HeroStage.new()
		stage.scenery = false
		stage.mode = "select"
		stage.spin = 0.0
		root.add_child(stage)
		await process_frame
		var clips: Array
		if String(id) == "knight" or String(id).begins_with("unit:"):
			# a unit model (unit:<catalog key>; "knight" is the lane knight) with its weapons, its clips repaired
			# unless --raw; sized so a 1.8 m figure fills the frame like a hero
			var key := "dawn_melee" if String(id) == "knight" else String(id).substr(5)
			var ucfg := ModelCatalog.info(key)
			stage.show_hero("blood_ranger", {}, false)
			for i in 3:
				await process_frame
			stage.model.queue_free()
			stage.model = (load(String(ucfg.scene)) as PackedScene).instantiate()
			RepairedClips.patch(stage.model)
			stage.add_child(stage.model)
			var usk: Skeleton3D = stage.model.find_children("*", "Skeleton3D", true, false)[0]
			var sh := usk.get_bone_global_rest(usk.find_bone("upper_arm.L")).origin.y
			stage.model.scale = Vector3.ONE * 1.44 / maxf(0.3, sh)
			for side in ["R", "L"]:
				var ps := ModelCatalog.weapon(String(ucfg.get(side, "")))
				if ps and usk.find_bone("weapon." + side) >= 0:
					var at := BoneAttachment3D.new()
					at.bone_name = "weapon." + side
					usk.add_child(at)
					var wpn := ps.instantiate() as Node3D
					at.add_child(wpn)
					wpn.transform = ModelCatalog.prop_transform(ucfg, side)
			stage.anim = stage.model.find_children("*", "AnimationPlayer", true, false)[0]
			clips = _clips_only.duplicate()
			if clips.is_empty():
				for c in [String(ucfg.get("idle", "idle"))] + Array(ucfg.get("attack", [])):
					if stage.anim.has_animation(c) and not (c in clips):
						clips.append(c)
		else:
			stage.show_hero(String(id), {}, false)
			clips = _clips(String(id))
		for i in 10:
			await process_frame
		if _fov > 0.0:
			stage.cam.fov = _fov
			stage.cam.position = Vector3(0.0, _aim + 0.15, 5.6)
			stage.cam.look_at(Vector3(0.0, _aim, 0))
		var rows: Array = []
		for clip in clips:
			if stage.anim == null or not stage.anim.has_animation(clip):
				print("missing ", id, " ", clip)
				continue
			for yaw in _yaws:
				rows.append([clip, yaw])
		var per := rows.size() if _page <= 0 else _page
		var ncols := mini(COLS, _frames)
		var sheet: Image
		for r in rows.size():
			if r % per == 0:
				sheet = Image.create(ncols * CELL.x, mini(per, rows.size() - r) * CELL.y + 4, false, Image.FORMAT_RGBA8)
				sheet.fill(Color(0.05, 0.05, 0.06))
			var clip := String(rows[r][0])
			var a := stage.anim.get_animation(clip)
			stage.yaw = float(rows[r][1])
			stage.model.rotation.y = stage.yaw
			stage.anim.play(clip, 0.0)
			stage.anim.pause()
			for f in mini(COLS, _frames):
				var t := a.length * float(f) / float(mini(COLS, _frames))
				stage.anim.seek(t, true)
				await process_frame
				await RenderingServer.frame_post_draw
				var img := root.get_viewport().get_texture().get_image()
				var vs := img.get_size()
				# the hero's middle third of the frame, scaled into the cell
				var cw := int(vs.y * 0.6)
				var ch := int(cw * float(CELL.y) / float(CELL.x))
				var crop := img.get_region(Rect2i((vs.x - cw) / 2, int(vs.y * 0.06), cw, mini(ch, int(vs.y * 0.94))))
				crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
				crop.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i(f * CELL.x, (r % per) * CELL.y))
			print("%s %s yaw %d" % [id, clip, roundi(rad_to_deg(float(rows[r][1])))])
			if r % per == per - 1 or r == rows.size() - 1:
				var nm := String(id).replace("unit:", "") + ("" if _page <= 0 else "_p%d" % (r / per))
				var path := ProjectSettings.globalize_path("res://%s/%s.png" % [_out, nm])
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				sheet.save_png(path)
				var part := rows.slice(r - r % per, r + 1)
				print("saved ", path, " rows: ", ", ".join(part.map(func(x): return "%s@%d" % [x[0], roundi(rad_to_deg(float(x[1])))])))
		stage.queue_free()
		await process_frame
	quit()
