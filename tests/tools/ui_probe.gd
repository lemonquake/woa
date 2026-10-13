extends SceneTree
## UI staging: boots a real match as Sludge, stages the new HUD pieces and saves screenshots, then quits.
##   godot --path . -s tests/tools/ui_probe.gd -- --hero=sludge --out=work/lemondev/<run>/shots [--tag=1080]
## Shots: hud (name, level and experience, stash, To Buy with an auto entry, an item on the ground, Blubber and
## Stench on), talents (the tree open), courier (courier selected), shop (shop open with To Buy beside it),
## cursor_enemy / cursor_ally (the targeting cursor frames, written straight from the cursor images).

const C = preload("res://src/sim/sim_const.gd")
const O = C.Order

var game: Node
var out := "work/shots"
var tag := ""

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--tag="):
			tag = "_" + a.substr(6)
	change_scene_to_file.call_deferred("res://src/game/main.tscn")
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://" + out + "/" + name + tag + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path, " ", img.get_size())

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		game = current_scene
		if game != null and game.get("booted") and game.world != null and game.hud != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(1)
			return
	await frames(30)
	if tag == "_4k":
		# a real 3840 x 2160 frame: a borderless window larger than the screen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(3840, 2160))
		await frames(20)
		print("window ", DisplayServer.window_get_size(), " viewport ", root.get_viewport().get_texture().get_size())
	var w: SimWorld = game.world
	var h: SimUnit = w.get_unit(game.player_hero_id)
	for b in w.bots.duplicate():
		w.bots.erase(b)
	w.time = 95.0
	w.combat.give_xp(h, float(C.XP_TABLE[11]) - h.xp + 120.0)
	for aid in h.abilities:
		h.ability_level[aid] = 1 if aid != "chomp" else 1
	h.ability_level["shuriken_hook"] = 3
	h.ability_level["stench"] = 3
	h.ability_level["blubber"] = 2
	h.ability_points = 2
	h.gold_unreliable = 1850
	h.refresh_stats()
	h.hp = h.max_hp * 0.8
	h.mana = h.max_mana
	# away from the base, near the river
	h.pos = Vector2(-1100, -900)
	w.orders.clear(h)
	var shop := w.shop
	for id in ["boots", "magic_wand", "quelling_blade", "branch"]:
		var it := shop.new_item(id)
		it["owner"] = h.id
		h.inventory[h.inventory.find(null)] = it
	h.inventory[6] = shop.new_item("clarity")
	h.stash[0] = shop.new_item("gauntlets")
	h.stash[1] = shop.new_item("recipe_tough_band")
	shop.add_to_buy(h, "spell_shield")
	shop.toggle_auto_buy(h, 1)
	var dropped := shop.new_item("salve")
	dropped["owner"] = h.id
	w.drop_item(dropped, h.pos + Vector2(160, -120), h.id)
	h.refresh_stats()
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "blubber"})
	game.camera.focus(View.to3(h.pos, game.terrain.height_at(h.pos)))
	await frames(40)
	await shot("hud")
	# talents open (level 12: the level 10 row can be learned)
	game.hud.bottom.talents_open = true
	await frames(10)
	await shot("talents")
	game.hud.bottom.talents_open = false
	# the courier selected
	var c := w.get_unit(h.courier_id)
	c.inventory[c.inventory.find(null)] = shop.new_item("circlet")
	game.input.select([c.id])
	await frames(10)
	await shot("courier")
	game.input.select([h.id])
	# shop open with To Buy beside it
	game.hud.toggle_shop()
	game.hud.shop.selected = "spell_shield"
	await frames(10)
	await shot("shop")
	game.hud.toggle_shop()
	# the targeting cursor frames, written as images (the hardware cursor is not in screenshots)
	for team in ["enemy", "ally"]:
		var col: Color = TargetingCursor.RED if team == "enemy" else TargetingCursor.GREEN
		var strip := Image.create(96 * 5, 96, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0.32, 0.42, 0.24))
		for i in 5:
			var f := TargetingCursor._draw(col, 96, float(i) / 4.0)
			strip.blend_rect(f, Rect2i(0, 0, 96, 96), Vector2i(i * 96, 0))
		var p := ProjectSettings.globalize_path("res://" + out + "/cursor_" + team + ".png")
		strip.save_png(p)
		print("saved ", p)
	quit(0)
