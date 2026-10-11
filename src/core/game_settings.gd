class_name GameSettings
extends RefCounted
## The player's hero as built in the Hero Creator: display name, look (HeroLook), outfit {slot: wear id} and dyes
## {slot: {cloth, trim, leather, metal, gold}}. Saved to user://hero.json and read by the match.

const PATH := "user://hero.json"

static var hero := {}

static func default_hero() -> Dictionary:
	var look := HeroLook.preset("huntress")
	look["hair"] = "ponytail"
	look["hair_color"] = "e8d28a"
	look["eye_color"] = "3a7a6a"
	return {
		"display_name": "Galewarden",
		"look": look,
		"outfit": {"inner_garment": "silk_undershirt", "armor": "tc_trackers_leathers", "leggings": "hide_leggings",
			"boots": "wayfarer_boot", "gloves": "silk_glove", "accessory_1": "windrider_feather"},
		"dyes": {"armor": {"cloth": "2f6f4a", "leather": "3a2414"}, "leggings": {"cloth": "2a3424", "leather": "2a1a10"},
			"boots": {"leather": "3a2414"}, "inner_garment": {"cloth": "4a5638"}, "gloves": {"cloth": "3a2a1a", "leather": "2a1a10"}},
	}

static func load_hero() -> Dictionary:
	if not hero.is_empty():
		return hero
	hero = default_hero()
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			hero["display_name"] = String(d.get("display_name", hero.display_name)).substr(0, 24)
			hero["look"] = HeroLook.sanitize(d.get("look", {}))
			var outfit := {}
			var cat := HeroAppearance.catalog()
			for slot in HeroAppearance.SLOTS:
				var id := String((d.get("outfit", {}) as Dictionary).get(slot, ""))
				if id == "" or cat.has(id):
					if id != "":
						outfit[slot] = id
			hero["outfit"] = outfit
			var dyes := {}
			var src: Dictionary = d.get("dyes", {})
			for slot in src:
				if slot in HeroAppearance.SLOTS and src[slot] is Dictionary:
					var clean := {}
					for k in src[slot]:
						var v := String(src[slot][k])
						if k in ["cloth", "trim", "leather", "metal", "gold"] and v.length() == 6 and v.is_valid_hex_number():
							clean[k] = v
					dyes[slot] = clean
			hero["dyes"] = dyes
	return hero

static func save_hero() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(hero, "\t"))
