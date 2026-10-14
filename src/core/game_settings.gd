class_name GameSettings
extends RefCounted
## The player's choices from the menus: which hero to play (Hero Select), who the bot plays, and each hero's
## appearance from the Hero Creator: display name, look (HeroLook), outfit {slot: wear id} and dyes
## {slot: {cloth, trim, leather, metal, gold}}. Saved to user://hero.json and read by the match.

const PATH := "user://hero.json"
const HEROES := ["blood_ranger", "ezee", "sludge", "azrin", "froster", "caziel", "tock", "kragg"]
## Heroes with their own body: no Hero Creator look, outfit or dyes.
const OWN_BODY := ["sludge"]

static var selected := "blood_ranger"        # the hero you play
static var opponent := "random"            # the bot's hero: "random" or a hero id
static var looks := {}                     # hero id -> appearance
static var hero := {}                      # the selected hero's appearance (what the Hero Creator edits)
static var custom := {}                    # hero ids whose look was changed in the Hero Creator (only these are saved)
static var _loaded := false

static func default_look(id: String) -> Dictionary:
	if id in OWN_BODY:
		return {"display_name": String(SimData.unit(id).get("name", id)), "look": {}, "outfit": {}, "dyes": {}}
	if id == "ezee":
		var look := HeroLook.preset("veteran")
		look.merge({"hair": "slick", "hair_color": "141016", "beard": "full", "beard_length": 0.7, "stubble": 0.6,
			"skin": "b48a72", "eye": "fierce", "eye_color": "a040ff", "eye_glow": 0.8, "muscle": 1.0, "build": 0.6,
			"height": 1.06, "jaw_wide": 0.8, "brow_heavy": 0.9, "marking": "scar", "marking_color": "4a2a3a"}, true)
		return {
			"display_name": "Ezee",
			"look": HeroLook.sanitize(look),
			"outfit": {"inner_garment": "chain_shirt", "armor": "warden_plate", "leggings": "riveted_legplates",
				"boots": "iron_sabaton", "gloves": "spiked_gauntlet", "helm": "visored_greathelm",
				"accessory_1": "tc_dread_command_signet"},
			"dyes": {"armor": {"metal": "433c55", "cloth": "3c1458", "trim": "a060f0", "leather": "1a1016", "gold": "6a3a9a"},
				"leggings": {"metal": "433c55", "cloth": "2a1040", "leather": "1a1016"},
				"boots": {"metal": "433c55", "leather": "1a1016"}, "gloves": {"metal": "433c55", "leather": "1a1016"},
				"helm": {"metal": "3a3448", "cloth": "3c1458", "trim": "a060f0"},
				"inner_garment": {"metal": "3a3444", "cloth": "2a1040"}},
		}
	if id == "azrin":
		# Azrin, the Flamemander: the owner's female_generic body (Athletic), flame-orange hair, dragonhide armour of
		# red scales and molten gold, crimson silks, a circlet
		var az := HeroLook.preset("huntress")
		az.merge({"body": "female_generic", "hair": "long", "hair_color": "c0491f", "hair_length": 1.15, "skin": "f0caa8", "eye": "glowing",
			"eye_color": "e0a020", "eye_glow": 1.0, "lip_color": "a8443e", "brow": "arched", "marking": "none",
			"build": -0.45, "height": 1.0, "cheeks": -0.4}, true)
		return {
			"display_name": "Azrin",
			"look": HeroLook.sanitize(az),
			"outfit": {"armor": "ember_dragonhide", "leggings": "magister_silks", "boots": "sage_boots",
				"helm": "seers_circlet", "accessory_1": "sunforged_medallion"},
			"dyes": {"armor": {"cloth": "5c1a10", "trim": "d89a40", "leather": "2a120a", "metal": "a87030", "gold": "e0a840"},
				"leggings": {"cloth": "1e0806", "trim": "c08a30", "leather": "1a0c08"},
				"boots": {"leather": "24100a", "cloth": "1e0806", "metal": "c89038", "gold": "e0a840"},
				"helm": {"cloth": "b8401a", "trim": "e0a040", "metal": "e0b048", "gold": "f0c050"},
				"inner_garment": {"cloth": "a04a18"}},
		}
	if id == "froster":
		# Froster, the Winter Master: a tall white-bearded frost mage in pale blue plate and deep blue robes, eyes of ice
		var fr := HeroLook.preset("veteran")
		fr.merge({"hair": "long", "hair_color": "c4d2de", "hair_length": 1.1, "beard": "full", "beard_length": 1.15,
			"stubble": 0.4, "skin": "e2d6d4", "eye": "glowing", "eye_color": "8fe4ff", "eye_glow": 0.7, "brow": "bushy",
			"marking": "none", "muscle": 0.5, "build": 0.3, "height": 1.08, "jaw_wide": 0.5, "brow_heavy": 0.7}, true)
		return {
			"display_name": "Froster",
			"look": HeroLook.sanitize(fr),
			"outfit": {"inner_garment": "padded_gambeson", "armor": "tc_sanctified_plate", "leggings": "u_rimewalkers",
				"boots": "guardian_greaves", "gloves": "guardian_gauntlets", "accessory_1": "tidecaller_moonstone"},
			"dyes": {"armor": {"metal": "6a86a4", "cloth": "16325a", "trim": "9cc8e8", "leather": "1e2836", "gold": "b8d8f0"},
				"leggings": {"metal": "6a86a4", "cloth": "122a4c", "leather": "1e2836", "trim": "9cc8e8"},
				"boots": {"metal": "708ca8", "leather": "1e2836"}, "gloves": {"metal": "708ca8", "leather": "1e2836"},
				"inner_garment": {"cloth": "0f2240"}},
		}
	if id == "caziel":
		# Caziel, the Void Assassin: a lean hooded killer in black and violet leathers, a dark band across the eyes
		var cz := HeroLook.preset("shade")
		cz.merge({"hair": "slick", "hair_color": "120a18", "skin": "c99a7c", "eye": "fierce", "eye_color": "c070ff",
			"eye_glow": 0.9, "brow": "straight", "marking": "band", "marking_color": "0e0812", "build": -0.25, "muscle": 0.35,
			"height": 1.02, "cheeks": -0.5, "stubble": 0.25}, true)
		return {
			"display_name": "Caziel",
			"look": HeroLook.sanitize(cz),
			"outfit": {"inner_garment": "silk_undershirt", "armor": "tc_nightstalker_leathers", "leggings": "nightweave_leggings",
				"boots": "depth_gloomthread_treads", "gloves": "silk_glove", "helm": "linen_hood", "accessory_1": "viper_coil_ring"},
			"dyes": {"armor": {"cloth": "1c0e2a", "leather": "120a14", "trim": "8a46e0", "metal": "3e3650"},
				"leggings": {"cloth": "140a1e", "leather": "120a14"}, "boots": {"leather": "120a14", "cloth": "140a1e"},
				"gloves": {"cloth": "1c0e2a", "leather": "120a14"}, "helm": {"cloth": "160b22", "trim": "8a46e0"},
				"inner_garment": {"cloth": "2a1240"}},
		}
	if id == "tock":
		# Tock, the Clockmaker: a small, wiry old tinkerer, white hair and beard, gold eyes, brass and teal robes, an
		# hourglass at his belt
		var tk := HeroLook.preset("scholar")
		tk.merge({"hair": "sidepart", "hair_color": "9a968e", "hair_length": 0.8, "beard": "full", "beard_length": 0.9,
			"stubble": 0.3, "skin": "e2c0a6", "eye": "glowing", "eye_color": "ffc640", "eye_glow": 0.8, "brow": "bushy",
			"marking": "none", "height": 0.92, "build": -0.4, "nose_long": 0.6}, true)
		return {
			"display_name": "Tock",
			"look": HeroLook.sanitize(tk),
			"outfit": {"inner_garment": "padded_gambeson", "armor": "tc_arcanist_vestments", "leggings": "scholars_breeches",
				"boots": "sage_boots", "gloves": "runed_glove", "helm": "seers_circlet", "accessory_1": "sands_of_tempo"},
			"dyes": {"armor": {"cloth": "12323a", "trim": "c89634", "leather": "3a2412", "metal": "a87a2a", "gold": "d8a840"},
				"leggings": {"cloth": "0e262c", "leather": "3a2412", "trim": "c89a3a"},
				"boots": {"leather": "3a2412", "cloth": "15363c", "metal": "c08a30"},
				"gloves": {"cloth": "1d4a52", "leather": "3a2412", "metal": "c08a30"},
				"helm": {"metal": "d8a840", "gold": "f0c860"}, "inner_garment": {"cloth": "6a4a1e"}},
		}
	if id == "kragg":
		# Kragg, the Magnet Knight: a huge knight in dark iron plate with cobalt trim, close-cropped hair, a braided
		# beard, eyes that glow blue
		var kg := HeroLook.preset("veteran")
		kg.merge({"hair": "crop", "hair_color": "2a2a30", "beard": "braided", "beard_length": 0.8, "stubble": 0.5,
			"skin": "b88a6e", "eye": "glowing", "eye_color": "4aa0ff", "eye_glow": 0.9, "muscle": 1.3, "build": 0.9,
			"height": 1.1, "jaw_wide": 1.0, "brow_heavy": 1.0, "marking": "none"}, true)
		return {
			"display_name": "Kragg",
			"look": HeroLook.sanitize(kg),
			"outfit": {"inner_garment": "chain_shirt", "armor": "guardian_plate", "leggings": "iron_cuisses",
				"boots": "iron_sabaton", "gloves": "iron_gauntlet", "accessory_1": "stoneheart_idol"},
			"dyes": {"armor": {"metal": "3c424e", "cloth": "16285a", "trim": "3a8aff", "leather": "1a1a20", "gold": "5aa0ff"},
				"leggings": {"metal": "3c424e", "cloth": "16285a", "leather": "1a1a20", "trim": "3a8aff"},
				"boots": {"metal": "3c424e", "leather": "1a1a20"}, "gloves": {"metal": "3c424e", "leather": "1a1a20"},
				"helm": {"metal": "343a46", "cloth": "16285a", "trim": "3a8aff"},
				"inner_garment": {"metal": "30343c", "cloth": "16285a"}},
		}
	# Blood Ranger: a pale huntress in blood-red leathers with crimson hair and faintly glowing red eyes
	var g := HeroLook.preset("huntress")
	g.merge({"hair": "long", "hair_color": "861620", "hair_length": 1.0, "skin": "e8c2a8", "eye": "cat",
		"eye_color": "e0202c", "eye_glow": 0.55, "lip_color": "8a2028", "marking": "none", "build": -0.35}, true)
	return {
		"display_name": "Blood Ranger",
		"look": HeroLook.sanitize(g),
		"outfit": {"inner_garment": "silk_undershirt", "armor": "tc_trackers_leathers", "leggings": "trackers_breeches",
			"boots": "wayfarer_boot", "gloves": "silk_glove", "accessory_1": "tc_bloodmoon_signet"},
		"dyes": {"armor": {"cloth": "8a1018", "leather": "3a1c16", "trim": "c8a060", "metal": "6a5a50"},
			"leggings": {"cloth": "2e1414", "leather": "2a1610"}, "boots": {"leather": "2a1610"},
			"inner_garment": {"cloth": "5a1016"}, "gloves": {"cloth": "3a1012", "leather": "2a1610"}},
	}

## Kept for callers that want Blood Ranger's default look.
static func default_hero() -> Dictionary:
	return default_look("blood_ranger")

static func look_for(id: String) -> Dictionary:
	_load()
	if not looks.has(id):
		looks[id] = default_look(id)
	return looks[id]

## The selected hero's appearance (also what the Hero Creator edits).
static func load_hero() -> Dictionary:
	_load()
	hero = look_for(selected)
	return hero

static func select(id: String) -> void:
	_load()
	if id in HEROES:
		selected = id
		hero = look_for(id)

## The bot's hero for the next match: the opponent setting, or a random hero.
static func opponent_hero(rng: RandomNumberGenerator) -> String:
	_load()
	if opponent in HEROES:
		return opponent
	return HEROES[rng.randi_range(0, HEROES.size() - 1)]

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary):
		return
	if d.has("looks"):
		selected = String(d.get("selected", "blood_ranger")) if String(d.get("selected", "")) in HEROES else "blood_ranger"
		var opp := String(d.get("opponent", "random"))
		opponent = opp if opp == "random" or opp in HEROES else "random"
		var src: Dictionary = d.looks if d.looks is Dictionary else {}
		var marked: Array = d.get("custom", src.keys()) if d.get("custom", null) is Array else src.keys()
		for id in src:
			if id in HEROES and src[id] is Dictionary and id in marked:
				looks[id] = _sanitize(src[id], id)
				custom[id] = true
	else:
		# the older single-hero file: Blood Ranger's look
		looks["blood_ranger"] = _sanitize(d, "blood_ranger")
		custom["blood_ranger"] = true

static func _sanitize(d: Dictionary, id: String) -> Dictionary:
	var out := default_look(id)
	out["display_name"] = String(d.get("display_name", out.display_name)).substr(0, 24)
	if id in OWN_BODY:
		return out
	out["look"] = HeroLook.sanitize(d.get("look", {}))
	var outfit := {}
	var cat := HeroAppearance.catalog()
	for slot in HeroAppearance.SLOTS:
		var wid := String((d.get("outfit", {}) as Dictionary).get(slot, ""))
		if wid != "" and cat.has(wid):
			outfit[slot] = wid
	out["outfit"] = outfit
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
	out["dyes"] = dyes
	return out

static func save_hero() -> void:
	_load()
	if not hero.is_empty():
		looks[selected] = hero
		custom[selected] = true
	save()

static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		var saved := {}
		for id in custom:
			if looks.has(id):
				saved[id] = looks[id]
		f.store_string(JSON.stringify({"selected": selected, "opponent": opponent, "looks": saved, "custom": custom.keys()}, "\t"))

# ---- Game Setup -----------------------------------------------------------------------------------------------------
# Who plays the match: two teams of five slots, each You, Bot or Empty, with a hero (or Random; bots may pick the same
# hero), a bot skill (Dota's bot difficulties) and, for you, the lane you mean to take (the bots leave it to you).
# Saved in user://setup.json.

const SETUP_PATH := "user://setup.json"
const BOT_NAMES := ["Bot Gerald", "Bot Kevin", "Bot Doris", "Bot Nigel", "Bot Wanda", "Bot Mabel", "Bot Hank",
	"Bot Tilly", "Bot Barry", "Bot Pip"]
const SKILLS := ["passive", "easy", "medium", "hard", "unfair"]
const SKILL_NAMES := ["Passive", "Easy", "Medium", "Hard", "Unfair"]
const LANES := ["", "safe", "mid", "off"]
const LANE_NAMES := ["Any lane", "Safe lane", "Mid", "Off lane"]
const ROLES := ["", "1", "2", "3", "4", "5"]
const ROLE_NAMES := ["Any role", "Safe lane carry", "Mid", "Off lane", "Roamer", "Safe lane support"]
const KINDS := ["you", "bot", "empty"]
const KIND_NAMES := ["You", "Bot", "Empty"]

static var setup := {}
static var _setup_loaded := false

static func default_setup() -> Dictionary:
	var teams := [[], []]
	var n := 1
	for t in 2:
		for i in 5:
			var slot := {"kind": "bot", "hero": "random", "skill": "hard", "name": "", "lane": "", "role": ""}
			if t == 0 and i == 0:
				slot.kind = "you"
				slot.hero = selected
			elif t == 1 and i == 0:
				slot.name = "Bot Gerald"
				slot.hero = opponent
			else:
				slot.name = BOT_NAMES[n]
				n += 1
			teams[t].append(slot)
	return {"teams": teams}

## The classic duel: you against Bot Gerald in the middle lane.
static func duel_setup() -> Dictionary:
	var s := default_setup()
	for t in 2:
		for i in range(1, 5):
			s.teams[t][i].kind = "empty"
	s.teams[0][0].lane = "mid"
	s.teams[1][0].hero = opponent
	return s

static func load_setup() -> Dictionary:
	if _setup_loaded:
		return setup
	_setup_loaded = true
	_load()
	setup = default_setup()
	if not FileAccess.file_exists(SETUP_PATH):
		return setup
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETUP_PATH))
	if not (d is Dictionary) or not (d.get("teams") is Array) or (d.teams as Array).size() != 2:
		return setup
	var you := 0
	for t in 2:
		var src: Array = d.teams[t] if d.teams[t] is Array else []
		for i in mini(5, src.size()):
			if not (src[i] is Dictionary):
				continue
			var s: Dictionary = setup.teams[t][i]
			var kind := String(src[i].get("kind", s.kind))
			s.kind = kind if kind in KINDS else "empty"
			var hero_id := String(src[i].get("hero", "random"))
			s.hero = hero_id if hero_id == "random" or hero_id in HEROES else "random"
			var sk := String(src[i].get("skill", "hard"))
			s.skill = sk if sk in SKILLS else "hard"
			s.name = String(src[i].get("name", s.name)).substr(0, 20)
			var ln := String(src[i].get("lane", ""))
			s.lane = ln if ln in LANES else ""
			var rl := String(src[i].get("role", ""))
			s.role = rl if rl in ROLES else ""
			if s.kind == "you":
				you += 1
				if you > 1:
					s.kind = "bot"
	if you == 0:
		setup.teams[0][0].kind = "you"
	for t in 2:
		for s in setup.teams[t]:
			if s.kind == "you":
				s.hero = selected
	return setup

static func save_setup() -> void:
	var f := FileAccess.open(SETUP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(setup, "\t"))

## The slot you play in: [team, index].
static func your_slot() -> Array:
	load_setup()
	for t in 2:
		for i in 5:
			if setup.teams[t][i].kind == "you":
				return [t, i]
	return [0, 0]

## Every filled slot with Random resolved: [{team, kind, hero, skill, name, lane}].
static func match_slots(rng: RandomNumberGenerator) -> Array:
	load_setup()
	var out := []
	var used_names := {}
	for t in 2:
		for s in setup.teams[t]:
			if s.kind == "empty":
				continue
			var hero_id := String(s.hero)
			if s.kind == "you":
				hero_id = selected
			elif hero_id == "random" or not (hero_id in HEROES):
				hero_id = HEROES[rng.randi_range(0, HEROES.size() - 1)]
			var nm := String(s.name)
			if s.kind == "bot" and (nm == "" or used_names.has(nm)):
				for b in BOT_NAMES:
					if not used_names.has(b):
						nm = b
						break
			used_names[nm] = true
			out.append({"team": t, "kind": s.kind, "hero": hero_id, "skill": s.skill, "name": nm, "lane": s.lane,
				"role": String(s.get("role", ""))})
	return out
