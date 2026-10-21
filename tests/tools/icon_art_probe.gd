extends SceneTree
## Check every skill, item, recipe and Switch Boots state through the runtime icon API.
## godot --headless --path . -s tests/tools/icon_art_probe.gd -- [--fallback]
## With a window: add --gallery=work/icons/gallery [--4k] to capture the runtime gallery.

var fails := 0
var checks := 0
var fallback := false
var gallery := ""
var big := false
var pictures := {}
var skills: Array = []
var items: Array = []

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--fallback":
			fallback = true
		elif arg.begins_with("--gallery="):
			gallery = arg.substr(10)
		elif arg == "--4k":
			big = true
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)

func picture(id: String, path: String, texture: Texture2D) -> void:
	check(texture != null, id + " loads")
	if texture == null:
		return
	var full := UiKit.icon_path(path)
	if not fallback:
		check(full == "res://assets/ui/" + path + ".png", id + " resolves its chosen art: " + full)
	var image := texture.get_image()
	check(image != null and image.get_width() == image.get_height(), id + " is square")
	if image == null:
		return
	if not fallback:
		check(image.get_width() >= 128, id + " has at least 128 pixels")
		if image.is_compressed():
			image.decompress()
		image.clear_mipmaps()
		var hash_value := image.get_data().hex_encode().sha256_text()
		check(not pictures.has(hash_value), id + " has distinct art from " + String(pictures.get(hash_value, "")))
		pictures[hash_value] = id

func _run() -> void:
	SimData.units()
	var ids: Array = SimData._abilities.keys()
	ids.sort()
	for id in ids:
		var path := String(UiKit.ABILITY_ICONS.get(id, UiKit.NEUTRAL_SKILL_ICONS.get(id, "")))
		var expected: String = "art/skills/" + String(id)
		check(path == expected, id + " has an explicit chosen skill route")
		picture("skill:" + id, path, UiKit.ability_icon(id))
		check(UiKit.icon(path) == UiKit.ability_icon(id), id + " direct HUD lookup agrees")
		skills.append({"name": SimData.ability(id).name, "texture": UiKit.ability_icon(id)})
	for id in UiKit.UNIT_SKILL_ICONS:
		var path: String = UiKit.UNIT_SKILL_ICONS[id]
		picture("unit:" + id, path, UiKit.icon(path))
		skills.append({"name": String(id).replace("_", " ").capitalize(), "texture": UiKit.icon(path)})
	# Use the simulation's current sword and modifier, then the legacy paths used by the real HUD and BuffBar.
	var hero := SimUnit.new()
	hero.def = SimData.unit("dracoxinia")
	var swords := SimKits11.new()
	for i in SimKits11.SWORDS.size():
		swords.sword[hero.id] = i
		swords._mark(hero)
		var id := "sword_" + swords.sword_id(hero)
		var path: String = UiKit.STATE_SKILL_ICONS.get(id, "")
		check(path == "art/skills/" + id, id + " has an explicit state route")
		var texture := UiKit.ability_icon(id)
		picture("state:" + id, path, texture)
		var hud_path := "skills/gen/sword_" + swords.sword_id(hero)
		check(UiKit.icon(hud_path) == texture, id + " current-sword HUD legacy route agrees")
		var modifier := hero.get_modifier(id)
		check(not modifier.is_empty(), id + " current sword has its live modifier")
		check(BuffBar.icon_of(id, modifier) == texture, id + " live buff bar route agrees")
		if not fallback:
			check(UiKit.icon_path(hud_path) == "res://assets/ui/" + path + ".png", id + " HUD alias resolves painted state")
			check(UiKit.icon_path(BuffBar.ICONS[id]) == "res://assets/ui/" + path + ".png", id + " buff alias resolves painted state")
		skills.append({"name": BuffBar.name_of(id), "texture": texture})
	for id in ["weapon_grab", "pace_aura", "pack_aura", "magic_armor_aura", "break_strike", "thick_hide_aura"]:
		check(BuffBar.icon_of(id, {}) == UiKit.ability_icon(id), id + " buff bar uses the same skill art")
	# Exercise the real unit panel, including every aura, on-hit passive, trait, ward and building entry.
	var hud := (load("res://src/ui/hud.gd") as GDScript).new() as Control
	for id in SimData.units():
		var unit := SimUnit.new()
		unit.def = SimData.unit(id)
		unit.kind = int(unit.def.kind)
		if unit.is_hero():
			continue
		for entry in hud.unit_skills(unit):
			check(String(entry.icon).begins_with("art/skills/"), id + ": " + entry.name + " uses skill art")
			check(UiKit.icon(entry.icon) != null, id + ": " + entry.name + " loads in the unit panel")
	hud.free()
	var item_ids: Array = SimData.items().keys()
	item_ids.sort()
	var recipe_checked := false
	for id in item_ids:
		var path := UiKit.item_icon_path(id)
		if String(id).begins_with("recipe_"):
			check(path == "art/items/recipe", id + " uses recipe art")
			check(UiKit.item_icon(id) == UiKit.icon("art/items/recipe"), id + " recipe lookup agrees")
			if recipe_checked:
				continue
			recipe_checked = true
		else:
			if not fallback:
				check(path == "art/items/" + id, id + " has an explicit item route")
		picture("item:" + id, path, UiKit.item_icon(id))
		items.append({"name": "Recipe" if String(id).begins_with("recipe_") else SimData.item(id).name, "texture": UiKit.item_icon(id)})
	for attr in ["str", "agi", "int"]:
		var id: String = "power_treads_" + attr
		var path := UiKit.item_icon_path(id)
		var texture := UiKit.held_item_icon({"id": "power_treads", "attr": attr})
		picture("item:" + id, path, texture)
		check(texture == UiKit.icon(path), id + " held lookup agrees")
		items.append({"name": "Switch Boots " + attr, "texture": texture})
	var empty_flask := UiKit.held_item_icon({"id": "bottle", "charges": 0})
	picture("item:bottle_empty", UiKit.item_icon_path("bottle_empty"), empty_flask)
	items.append({"name": "Empty Flask", "texture": empty_flask})
	check(empty_flask == UiKit.icon(UiKit.item_icon_path("bottle_empty")), "empty Flask uses its own art")
	check(UiKit.held_item_icon({"id": "bottle", "charges": 1}) == UiKit.item_icon("bottle"), "Flask with a charge keeps full art")
	check(UiKit.held_item_icon({"id": "bottle", "charges": 0, "orb": "haste"}) == UiKit.item_icon("bottle"), "Flask holding an orb keeps full art")
	check(UiKit.icon("ui/lock") != null, "unrelated SVG fallback loads")
	check(UiKit.ability_icon("missing_skill") != null, "unknown skill keeps default icon")
	check(UiKit.item_icon("missing_item") != null, "unknown item keeps default icon")
	check(UiKit.icon("missing_icon") == null, "missing unrelated icon returns null")
	if not fallback:
		check(UiKit.icon_path("ui/teleport") == "res://assets/ui/art/items/tp_scroll.png", "teleport button uses Town Portal art")
		for id in UiKit.ABILITY_FALLBACKS:
			var expected: String = "res://assets/ui/art/skills/%s.png" % id
			check(UiKit.icon_path(UiKit.ABILITY_FALLBACKS[id]) == expected, id + " legacy route uses chosen art")
		for id in SimData.items():
			if not String(id).begins_with("recipe_"):
				check(UiKit.icon_path("items/gen/" + id) == "res://assets/ui/art/items/%s.png" % id, id + " generated route upgrades")
	if gallery != "":
		await capture_gallery()
	print("Icon art: %d checks, %d failures; %d skills and unit traits, %d item states" % [checks, fails, skills.size(), items.size()])
	quit(1 if fails > 0 else 0)

func capture_gallery() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(3840, 2160) if big else Vector2i(1920, 1080))
	root.content_scale_size = Vector2i(1920, 1080)
	var dir := ProjectSettings.globalize_path("res://" + gallery)
	DirAccess.make_dir_recursive_absolute(dir)
	for group in [["skills", skills], ["items", items]]:
		var rows: Array = group[1]
		var pages := ceili(rows.size() / 112.0)
		for page in pages:
			var board := Gallery.new()
			board.rows = rows.slice(page * 112, (page + 1) * 112)
			board.title = String(group[0]).capitalize()
			root.add_child(board)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var suffix := "_%02d" % (page + 1) if pages > 1 else ""
			root.get_texture().get_image().save_png(dir + "/" + group[0] + suffix + ("_4k" if big else "_1080") + ".png")
			board.queue_free()
			await process_frame

class Gallery extends Control:
	var rows: Array = []
	var title := ""

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.035, 0.04, 0.05))
		UiKit.text(self, title, Vector2(50, 43), 28)
		for i in rows.size():
			var at := Vector2(50 + (i % 14) * 130, 65 + (i / 14) * 120)
			var rect := Rect2(at, Vector2(74, 74))
			UiKit.slot(self, rect.grow(3), i % 3 == 0)
			var texture: Texture2D = rows[i].texture
			if texture:
				draw_texture_rect(texture, rect, false)
				draw_texture_rect(texture, Rect2(at + Vector2(82, 0), Vector2(32, 32)), false)
			if i % 3 == 1:
				UiKit.cooldown(self, rect, 0.62, 8.0)
			elif i % 3 == 2:
				draw_rect(rect, Color(0.04, 0.045, 0.05, 0.52))
			var lines := UiKit.wrap(String(rows[i].name), 122, 13)
			for line in mini(2, lines.size()):
				UiKit.text(self, lines[line], at + Vector2(0, 91 + line * 15), 13)
