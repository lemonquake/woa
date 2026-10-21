extends SceneTree
## Export the current icon routes and their runtime pixels before or after an art change.
## godot --headless --path . -s tests/tools/icon_art_dump.gd -- --out=work/icons/before

func _init() -> void:
	var out := "work/icons/dump"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var dir := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(dir)
	SimData.units()
	var skills: Array = []
	var skill_ids: Array = SimData._abilities.keys()
	skill_ids.sort()
	for id in skill_ids:
		var path := String(UiKit.ABILITY_ICONS.get(id, UiKit.NEUTRAL_SKILL_ICONS.get(id, UiKit.UNIT_SKILL_ICONS.get(id, "skills/keen_eye"))))
		skills.append({"id": id, "definition": SimData.ability(id), "path": path})
	for id in UiKit.UNIT_SKILL_ICONS:
		if not skill_ids.has(id):
			skills.append({"id": id, "definition": {"name": String(id).replace("_", " ").capitalize()}, "path": UiKit.UNIT_SKILL_ICONS[id]})
	var items: Array = []
	var item_ids: Array = SimData.items().keys()
	item_ids.sort()
	for id in item_ids:
		items.append({"id": id, "definition": SimData.item(id), "path": UiKit.item_icon_path(id)})
	for attr in ["str", "agi", "int"]:
		var id: String = "power_treads_" + attr
		items.append({"id": id, "definition": {"name": "Switch Boots: " + attr}, "path": UiKit.item_icon_path(id)})
	items.append({"id": "bottle_empty", "definition": {"name": "Empty Flask"}, "path": UiKit.item_icon_path("bottle_empty")})
	var states: Array = []
	# These are separate live buff-bar identifiers, rather than SimData abilities.
	for id in BuffBar.ICONS:
		if String(id).begins_with("sword_"):
			states.append({"id": id, "definition": {"name": BuffBar.NAMES.get(id, id)}, "path": BuffBar.ICONS[id]})
	for rows in [skills, items, states]:
		for row in rows:
			row["resolved_path"] = UiKit.icon_path(row.path)
			var texture := UiKit.icon(row.path)
			row["dimensions"] = [texture.get_width(), texture.get_height()] if texture else [0, 0]
	var file := FileAccess.open(dir + "/data.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"skills": skills, "items": items, "states": states, "units": SimData.units()}, "\t"))
	_sheet(skills, dir + "/skills.png")
	_sheet(items, dir + "/items.png")
	_sheet(states, dir + "/states.png")
	print("Dumped %d skills, %d items and %d buff states to %s" % [skills.size(), items.size(), states.size(), out])
	quit()

func _sheet(rows: Array, path: String) -> void:
	if rows.is_empty():
		return
	var sheet := Image.create(10 * 144, ceili(rows.size() / 10.0) * 112, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08))
	for i in rows.size():
		var texture := UiKit.icon(rows[i].path)
		if texture == null:
			continue
		var img := texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		# Imported RGB textures must match the RGBA sheet before blend_rect.
		img.convert(Image.FORMAT_RGBA8)
		var big := img.duplicate()
		big.resize(96, 96, Image.INTERPOLATE_LANCZOS)
		var small := img.duplicate()
		small.resize(32, 32, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((i % 10) * 144 + 4, (i / 10) * 112 + 4)
		sheet.blend_rect(big, Rect2i(0, 0, 96, 96), at)
		sheet.blend_rect(small, Rect2i(0, 0, 32, 32), at + Vector2i(100, 0))
	sheet.save_png(path)
