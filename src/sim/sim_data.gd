class_name SimData
extends RefCounted
## Unit, hero, ability and item definitions. Stats are copied from Dota 2's game data (npc_units / heroes / items,
## see docs/MECHANICS.md); names and designs are Warriors of Aether's own.
##
## A unit definition is a Dictionary; every key below is always present (see `_unit`).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const WP = C.Weapon
const EL = C.Element
const AT = C.ArmorType

static var _units := {}
static var _items := {}
static var _abilities := {}
static var _talents := {}
static var _ready := false

## A unit whose element is its team's: Light for Ancient Light, Dark for Black Sun (the Throne, the fountain).
const TEAM_ELEMENT := -2

static func _unit(id: String, d: Dictionary) -> Dictionary:
	var u := {
		"id": id, "name": id, "kind": K.CREEP_MELEE, "hull": 16.0, "hp": 150.0, "hp_regen": 0.0, "mana": 0.0,
		"mana_regen": 0.0, "armor": 0.0, "magic_resist": 0.0, "dmg_min": 1.0, "dmg_max": 1.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 0.5, "acquire": 800.0, "range": 100.0,
		"projectile_speed": 0.0, "move_speed": 300.0, "turn_rate": 0.5, "vision_day": 750.0, "vision_night": 750.0,
		"xp": 0.0, "gold_min": 0, "gold_max": 0, "weapon": -1, "armor_type": -1, "element": EL.NONE, "level": 1, "model": id,
		"can_attack": true, "can_move": true, "flying": false, "abilities": [], "bounty_key": "",
		"ancient": false, "innate": "", "talents": [],
	}
	u.merge(d, true)
	return u

static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	_build_units()
	_build_items()
	_build_abilities()
	_build_neutral_abilities()
	_build_abilities_15b()
	_build_abilities_16()
	_build_abilities_17()
	_build_abilities_18()
	_build_talents()
	_build_talents_18()

static func unit(id: String) -> Dictionary:
	_ensure()
	return _units.get(id, {})

static func units() -> Dictionary:
	_ensure()
	return _units

static func has_unit(id: String) -> bool:
	_ensure()
	return _units.has(id)

static func item(id: String) -> Dictionary:
	_ensure()
	return _items.get(id, {})

static func items() -> Dictionary:
	_ensure()
	return _items

static func ability(id: String) -> Dictionary:
	_ensure()
	return _abilities.get(id, {})

## A hero's ultimate: the skill with hero level requirements (Dota's 6/12/18), otherwise the last one.
static func ultimate_of(abilities: Array) -> String:
	_ensure()
	for aid in abilities:
		if (_abilities.get(String(aid), {}) as Dictionary).has("required_level"):
			return String(aid)
	return String(abilities[-1]) if not abilities.is_empty() else ""

## A talent: {id, name, mods: [{ability, add: {key: n}, mult: {key: n}}], stats: {key: n}}.
static func talent(id: String) -> Dictionary:
	_ensure()
	return _talents.get(id, {})

# ---- Units --------------------------------------------------------------------------------------------------------

static func _add(id: String, d: Dictionary) -> void:
	_units[id] = _unit(id, d)

static func _build_units() -> void:
	# Lane creeps (npc_dota_creep_*). Backswing values are the animation lengths after the attack point.
	var melee := {"kind": K.CREEP_MELEE, "hull": 16.0, "hp": 550.0, "hp_regen": 0.5, "armor": 2.0, "dmg_min": 19.0,
		"dmg_max": 23.0, "bat": 1.0, "attack_point": 0.467, "backswing": 0.533, "acquire": 500.0, "range": 100.0,
		"move_speed": 325.0, "turn_rate": 0.5, "xp": 57.0, "gold_min": 34, "gold_max": 39, "weapon": WP.SLASH,
		"level": 3}
	var ranged := {"kind": K.CREEP_RANGED, "hull": 8.0, "hp": 300.0, "hp_regen": 2.0, "mana": 500.0, "mana_regen": 0.75,
		"armor": 0.0, "dmg_min": 21.0, "dmg_max": 26.0, "bat": 1.0, "attack_point": 0.5, "backswing": 0.3,
		"acquire": 600.0, "range": 500.0, "projectile_speed": 900.0, "move_speed": 325.0, "turn_rate": 0.5, "xp": 69.0,
		"gold_min": 43, "gold_max": 52, "weapon": WP.PIERCING, "level": 5}
	var siege := {"kind": K.CREEP_SIEGE, "hull": 16.0, "hp": 935.0, "magic_resist": 0.8, "dmg_min": 35.0, "dmg_max": 46.0,
		"bat": 3.0, "attack_point": 0.7, "backswing": 0.3, "acquire": 800.0, "range": 690.0, "projectile_speed": 1100.0,
		"move_speed": 325.0, "turn_rate": 0.5, "xp": 88.0, "gold_min": 59, "gold_max": 72, "weapon": WP.SIEGE,
		"level": 4}
	var flag := melee.duplicate()
	flag.merge({"kind": K.CREEP_FLAG, "magic_resist": 0.4}, true)
	var super_melee := melee.duplicate()
	super_melee.merge({"hp": 700.0, "armor": 3.0, "dmg_min": 36.0, "dmg_max": 44.0, "xp": 25.0, "gold_min": 20, "gold_max": 26}, true)
	var super_ranged := ranged.duplicate()
	super_ranged.merge({"hp": 475.0, "armor": 1.0, "dmg_min": 41.0, "dmg_max": 46.0, "xp": 22.0, "gold_min": 19, "gold_max": 25}, true)
	# mega creeps (every enemy barracks down): fully upgraded super creeps (30 upgrades) from the first wave
	var mega_melee := super_melee.duplicate()
	mega_melee.merge({"hp": 1270.0, "dmg_min": 96.0, "dmg_max": 104.0}, true)
	var mega_ranged := super_ranged.duplicate()
	mega_ranged.merge({"hp": 1015.0, "dmg_min": 131.0, "dmg_max": 136.0}, true)
	# siege creeps of a lane whose enemy ranged barracks fell: +16 damage (their only upgrade)
	var super_siege := siege.duplicate()
	super_siege.merge({"dmg_min": 51.0, "dmg_max": 62.0}, true)
	var names := {
		0: {"melee": "Footman", "ranged": "Archer", "siege": "Stone Golem", "flag": "Flag Bearer"},
		1: {"melee": "Ghoul", "ranged": "Skeleton Archer", "siege": "Bone Golem", "flag": "Flag Bearer"},
	}
	for team in [0, 1]:
		var p := "dawn_" if team == 0 else "dusk_"
		var n: Dictionary = names[team]
		var el := EL.LIGHT if team == 0 else EL.DARK
		for d in [melee, ranged, siege, flag, super_melee, super_ranged, mega_melee, mega_ranged, super_siege]:
			d["element"] = el
		_add(p + "melee", _named(melee, n.melee, p + "melee"))
		_add(p + "ranged", _named(ranged, n.ranged, p + "ranged"))
		_add(p + "siege", _named(siege, n.siege, p + "siege"))
		_add(p + "flag", _named(flag, n.flag, p + "flag"))
		_add(p + "melee_super", _named(super_melee, "Super " + n.melee, p + "melee"))
		_add(p + "ranged_super", _named(super_ranged, "Super " + n.ranged, p + "ranged"))
		_add(p + "melee_mega", _named(mega_melee, "Mega " + n.melee, p + "melee"))
		_add(p + "ranged_mega", _named(mega_ranged, "Mega " + n.ranged, p + "ranged"))
		_add(p + "siege_super", _named(super_siege, "Super " + n.siege, p + "siege"))

	# Buildings (npc_dota_goodguys_*). Towers use the Reinforced (siege) attack class.
	var tower := {"kind": K.TOWER, "hull": 144.0, "can_move": false, "bat": 0.9, "attack_speed": 110.0,
		"attack_point": 0.6, "backswing": 0.4, "acquire": 700.0, "range": 700.0, "projectile_speed": 750.0,
		"move_speed": 0.0, "turn_rate": 1.0, "vision_day": 1900.0, "weapon": WP.SIEGE,
		"element": EL.EARTH}
	_add("tower1", _merged(tower, {"name": "Tier 1 Tower", "hp": 1800.0, "armor": 12.0, "dmg_min": 88.0, "dmg_max": 92.0,
		"vision_night": 800.0, "level": 1, "bounty_key": "tower1"}))
	_add("tower2", _merged(tower, {"name": "Tier 2 Tower", "hp": 2500.0, "armor": 16.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 2, "bounty_key": "tower2"}))
	_add("tower3", _merged(tower, {"name": "Tier 3 Tower", "hp": 2500.0, "armor": 16.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 3, "bounty_key": "tower3"}))
	_add("tower4", _merged(tower, {"name": "Tier 4 Tower", "hp": 2600.0, "armor": 21.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 4, "bounty_key": "tower4"}))
	var building := {"can_attack": false, "can_move": false, "move_speed": 0.0, "turn_rate": 0.0, "acquire": 0.0,
		"element": EL.EARTH}
	_add("melee_rax", _merged(building, {"name": "Melee Barracks", "kind": K.BARRACKS, "hull": 144.0, "hp": 2200.0,
		"hp_regen": 5.0, "armor": 15.0, "vision_day": 900.0, "vision_night": 600.0, "bounty_key": "melee_rax"}))
	_add("ranged_rax", _merged(building, {"name": "Ranged Barracks", "kind": K.BARRACKS, "hull": 144.0, "hp": 1300.0,
		"armor": 9.0, "vision_day": 900.0, "vision_night": 600.0, "bounty_key": "ranged_rax"}))
	_add("ancient", _merged(building, {"name": "Throne", "kind": K.ANCIENT, "hull": 298.0, "hp": 4500.0,
		"hp_regen": 12.0, "armor": 23.0, "vision_day": 2600.0, "vision_night": 2600.0, "element": TEAM_ELEMENT}))
	_add("filler", _merged(building, {"name": "Statue", "kind": K.FILLER, "hull": 96.0, "hp": 1000.0, "armor": 10.0,
		"vision_day": 900.0, "vision_night": 600.0, "bounty_key": "filler"}))
	_add("fountain", {"name": "Fountain", "kind": K.FOUNTAIN, "hull": 144.0, "hp": 500.0, "can_move": false,
		"true_sight": C.FOUNTAIN_TRUE_SIGHT,
		"move_speed": 0.0, "dmg_min": 290.0, "dmg_max": 310.0, "bat": 0.15, "attack_point": 0.0, "backswing": 0.0,
		"acquire": 1200.0, "range": 1200.0, "projectile_speed": 1400.0, "vision_day": 1800.0, "vision_night": 1800.0,
		"turn_rate": 1.0, "weapon": WP.SIEGE, "element": TEAM_ELEMENT})
	# health counts hits (7.35): a melee hero's attack takes 6, a ranged hero's 3, anything else 1
	_add("courier", {"name": "Courier", "kind": K.COURIER, "hull": 8.0, "hp": 6.0, "hp_regen": 0.0, "can_attack": false,
		"move_speed": 290.0, "turn_rate": 0.5, "vision_day": 200.0, "vision_night": 200.0, "model": "courier", "flying": true})
	_add("ward_observer", {"name": "Eye Ward", "kind": K.WARD, "hull": 8.0, "hp": 200.0, "can_attack": false,
		"can_move": false, "move_speed": 0.0, "vision_day": 1600.0, "vision_night": 1600.0, "xp": 0.0})
	# Reveal Ward (Dota's Sentry Ward): no sight of its own, True Sight 1050 over its team's vision
	_add("ward_sentry", {"name": "Reveal Ward", "kind": K.WARD, "hull": 8.0, "hp": 200.0, "can_attack": false,
		"can_move": false, "move_speed": 0.0, "vision_day": 0.0, "vision_night": 0.0, "xp": 0.0,
		"true_sight": 1050.0, "model": "ward_observer"})

	# Neutral creeps (npc_dota_neutral_*), renamed.
	var neu := {"kind": K.NEUTRAL_CREEP, "turn_rate": 0.9, "bat": 2.0, "vision_day": 800.0, "vision_night": 800.0}
	_add("mudling", _merged(neu, {"name": "Goblin", "element": EL.EARTH, "hull": 16.0, "hp": 240.0, "hp_regen": 0.5, "dmg_min": 15.0,
		"dmg_max": 16.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0, "range": 100.0, "move_speed": 290.0,
		"xp": 14.0, "gold_min": 3, "gold_max": 5, "level": 1}))
	_add("mudling_digger", _merged(neu, {"name": "Goblin Digger", "element": EL.EARTH, "hull": 16.0, "hp": 325.0, "hp_regen": 0.5,
		"armor": 1.0, "dmg_min": 22.0, "dmg_max": 23.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0,
		"range": 100.0, "move_speed": 270.0, "xp": 17.0, "gold_min": 12, "gold_max": 14, "level": 1,
		"on_hit": {"id": "weapon_grab", "name": "Weapon Grab", "disarm": true, "dur": 3.0, "cooldown": 9.0}}))
	_add("mudling_foreman", _merged(neu, {"name": "Goblin Boss", "element": EL.EARTH, "hull": 16.0, "hp": 400.0, "hp_regen": 0.5,
		"armor": 2.0, "dmg_min": 24.0, "dmg_max": 26.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0,
		"range": 110.0, "move_speed": 330.0, "xp": 30.0, "gold_min": 19, "gold_max": 21, "level": 2,
		"auras": [{"id": "pace_aura", "name": "Pace Aura", "stats": {"move_speed": 12.0}, "radius": 1200.0}]}))
	_add("ashfang", _merged(neu, {"name": "Wolf", "element": EL.ICE, "weapon": WP.BLUNT, "hull": 16.0, "hp": 500.0, "hp_regen": 0.5, "mana": 200.0,
		"armor": 1.0, "dmg_min": 15.0, "dmg_max": 17.0, "attack_point": 0.33, "backswing": 0.64, "acquire": 500.0,
		"range": 90.0, "move_speed": 350.0, "xp": 40.0, "gold_min": 18, "gold_max": 22, "level": 3,
		"abilities": ["snarl"]}))
	_add("ashfang_alpha", _merged(neu, {"name": "Alpha Wolf", "element": EL.ICE, "weapon": WP.BLUNT, "hull": 24.0, "hp": 600.0, "hp_regen": 0.5,
		"armor": 3.0, "dmg_min": 27.0, "dmg_max": 29.0, "attack_point": 0.33, "backswing": 0.64, "acquire": 500.0,
		"range": 90.0, "move_speed": 350.0, "xp": 60.0, "gold_min": 32, "gold_max": 34, "level": 5,
		"crit": {"name": "Crit", "chance": 0.20, "mult": 2.0},
		"auras": [{"id": "pack_aura", "name": "Pack Aura", "stats": {"base_damage_pct": 0.20}, "radius": 1200.0}]}))
	_add("strider", _merged(neu, {"name": "Orc", "element": EL.NATURE, "hull": 16.0, "hp": 350.0, "hp_regen": 0.5, "armor": 1.0,
		"dmg_min": 18.0, "dmg_max": 20.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 500.0, "range": 100.0,
		"move_speed": 320.0, "xp": 32.0, "gold_min": 16, "gold_max": 18, "level": 2,
		"auras": [{"id": "magic_armor_aura", "name": "Magic Armor Aura", "stats": {"magic_resist": 0.20},
			"hero_stats": {"magic_resist": 0.10}, "radius": 1200.0}]}))
	_add("strider_warlord", _merged(neu, {"name": "Orc Shaman", "element": EL.LIGHTNING, "hull": 24.0, "hp": 1100.0, "hp_regen": 1.0,
		"mana": 200.0, "armor": 4.0, "dmg_min": 49.0, "dmg_max": 55.0, "attack_point": 0.3, "backswing": 0.3,
		"acquire": 500.0, "range": 100.0, "move_speed": 320.0, "xp": 90.0, "gold_min": 54, "gold_max": 60, "level": 5,
		"abilities": ["stomp"]}))
	_add("hill_troll", _merged(neu, {"name": "Swamp Troll", "element": EL.WATER, "hull": 16.0, "hp": 500.0, "hp_regen": 0.5,
		"armor": 1.0, "dmg_min": 28.0, "dmg_max": 37.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 300.0,
		"range": 500.0, "projectile_speed": 1200.0, "move_speed": 270.0, "xp": 28.0, "gold_min": 18, "gold_max": 20,
		"weapon": WP.PIERCING, "level": 2,
		"on_hit": {"id": "break_strike", "name": "Break Strike", "break": true, "dur": 3.0, "cooldown": 10.0}}))
	_add("ogre_brute", _merged(neu, {"name": "Ogre", "element": EL.EARTH, "hull": 24.0, "hp": 800.0, "hp_regen": 0.5, "armor": 1.0,
		"dmg_min": 22.0, "dmg_max": 24.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 500.0, "range": 100.0,
		"move_speed": 270.0, "xp": 32.0, "gold_min": 22, "gold_max": 26, "level": 2, "abilities": ["smash"]}))
	_add("cinder_wyrmling", _merged(neu, {"name": "Fire Imp", "element": EL.FIRE, "weapon": WP.MAGIC, "hull": 24.0, "hp": 950.0, "hp_regen": 0.5,
		"armor": 2.0, "magic_resist": 0.25, "dmg_min": 20.0, "dmg_max": 22.0, "attack_point": 0.5, "backswing": 0.5,
		"acquire": 300.0, "range": 300.0, "projectile_speed": 900.0, "move_speed": 350.0, "xp": 95.0, "gold_min": 37,
		"gold_max": 43, "level": 3, "ancient": true}))
	_add("elder_cinder_wyrm", _merged(neu, {"name": "Lava Golem", "element": EL.FIRE, "weapon": WP.MAGIC, "hull": 40.0, "hp": 2000.0, "hp_regen": 2.0,
		"mana": 500.0, "armor": 4.0, "magic_resist": 0.3, "dmg_min": 62.0, "dmg_max": 68.0, "attack_point": 0.5,
		"backswing": 0.5, "acquire": 300.0, "range": 300.0, "projectile_speed": 1500.0, "move_speed": 300.0,
		"xp": 124.0, "gold_min": 76, "gold_max": 80, "level": 6, "ancient": true,
		"splash": {"name": "Splash", "radius": 250.0, "pct": 1.0},
		"auras": [{"id": "thick_hide_aura", "name": "Thick Hide Aura", "stats": {"armor": 3.0}, "radius": 1200.0}]}))

	# Heroes. Blood Ranger: a ranged agility archer (stats follow the classic ranged-agility carry template).
	_add("blood_ranger", {"name": "Jayla", "title": "the Blood Ranger", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 27.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 0.55, "acquire": 800.0, "range": 625.0,
		"projectile_speed": 1250.0, "move_speed": 300.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 16.0, "str_gain": 1.9, "agi": 24.0, "agi_gain": 2.8, "int": 15.0,
		"int_gain": 1.4, "element": EL.NATURE, "abilities": ["burst_shot", "gale_impact", "masterful_archery", "blood_ranger_ult"],
		"talents": [["ranger_archery_chance", "ranger_attack_speed"], ["ranger_gale_damage", "ranger_burst_damage"],
			["ranger_ult_range", "ranger_gale_cooldown"], ["ranger_ult_lifesteal", "ranger_archery_damage"]],
		"model": "hero"})
	# Ezee, the Dark Paladin: a melee strength fighter (stats follow the classic melee-strength template).
	_add("ezee", {"name": "Ezee", "title": "the Dark Paladin", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.5, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 1.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 30.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.4, "backswing": 0.6, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "str", "str": 24.0, "str_gain": 3.2, "agi": 16.0, "agi_gain": 2.0, "int": 18.0,
		"int_gain": 1.7, "element": EL.DARK, "abilities": ["dark_stomp", "leap_strike", "tainted_touch", "unholy_might"],
		"talents": [["ezee_strength", "ezee_stomp_damage"], ["ezee_stomp_stun", "ezee_touch_damage"],
			["ezee_leap_cooldown", "ezee_leap_strength"], ["ezee_might_chance", "ezee_might_duration"]],
		"model": "hero_ezee"})
	# Sludge, the Butcher: Dota 2's Pudge one to one (patch 7.41d, Liquipedia and the game's hero data), renamed.
	_add("sludge", {"name": "Sludge", "title": "the Butcher", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 2.5, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 45.0, "dmg_max": 51.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 1.17, "acquire": 600.0, "range": 175.0,
		"projectile_speed": 0.0, "move_speed": 280.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "str", "str": 25.0, "str_gain": 3.0, "agi": 13.0, "agi_gain": 1.4, "int": 16.0,
		"int_gain": 1.8, "element": EL.EARTH, "abilities": ["shuriken_hook", "stench", "blubber", "chomp"], "innate": "growing_gut",
		"talents": [["sludge_stench_slow", "sludge_armor"], ["sludge_hook_damage", "sludge_spell_lifesteal"],
			["sludge_hook_cooldown", "sludge_chomp_time"], ["sludge_gut_blubber", "sludge_chomp_power"]],
		"model": "hero_sludge"})

	# Azrin, the Flamemander (the owner's hero, 2026-10-14): a ranged intelligence caster of the Fire element who floats
	# above the ground. Range 665 is the owner's; the rest follows the classic ranged-intelligence nuker template
	# (chosen, see docs/HANDOFF.md).
	_add("azrin", {"name": "Azrin", "title": "the Flamemander", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 24.0, "dmg_max": 30.0, "bat": 1.6,
		"attack_speed": 100.0, "attack_point": 0.6, "backswing": 0.7, "acquire": 800.0, "range": 665.0,
		"projectile_speed": 1000.0, "move_speed": 290.0, "turn_rate": 0.6, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "int", "str": 18.0, "str_gain": 2.2, "agi": 21.0, "agi_gain": 1.8, "int": 27.0,
		"int_gain": 3.4, "element": EL.FIRE,
		"abilities": ["fiery_javelin", "touch_of_ember", "spirit_of_fire", "divine_smite"],
		"talents": [["azrin_javelin_burn", "azrin_damage"], ["azrin_magic_amp", "azrin_ember_cooldown"],
			["azrin_spirits", "azrin_smite_damage"], ["azrin_ember_stun", "azrin_smite_cooldown"]],
		"model": "hero_azrin"})

	# Froster, the Winter Master (the owner's hero, 2026-10-14 b): a ranged intelligence caster of the Ice element.
	# The owner gave the abilities; the stats follow the classic ranged-intelligence template (chosen, see HANDOFF).
	_add("froster", {"name": "Froster", "title": "the Winter Master", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 22.0, "dmg_max": 28.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.45, "backswing": 0.5, "acquire": 800.0, "range": 600.0,
		"projectile_speed": 900.0, "move_speed": 295.0, "turn_rate": 0.6, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "int", "str": 19.0, "str_gain": 2.3, "agi": 16.0, "agi_gain": 1.6, "int": 24.0,
		"int_gain": 3.3, "element": EL.ICE,
		"abilities": ["breath_of_cold", "ice_pulse", "frost_heart", "endless_winter"],
		"talents": [["froster_breath_damage", "froster_mana_regen"], ["froster_pulse_cooldown", "froster_heart_burst"],
			["froster_breath_slow", "froster_magic_amp"], ["froster_winter_damage", "froster_pulse_loss"]],
		"model": "hero_froster"})
	# Caziel, the Void Assassin (the owner's hero, 2026-10-14 b): a melee agility assassin of the Dark element. The owner
	# gave the abilities; the stats follow the classic melee-agility carry template (chosen, see HANDOFF).
	_add("caziel", {"name": "Caziel", "title": "the Void Assassin", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.5, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 1.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 26.0, "dmg_max": 30.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.3, "backswing": 0.5, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.8, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 20.0, "str_gain": 2.0, "agi": 23.0, "agi_gain": 3.1, "int": 15.0,
		"int_gain": 1.6, "element": EL.DARK,
		"abilities": ["swift_dagger", "sweet_poison", "master_of_shadows", "death_order"],
		"talents": [["caziel_attack_speed", "caziel_dagger_damage"], ["caziel_poison_chance", "caziel_shadows_cooldown"],
			["caziel_poison_damage", "caziel_dagger_armor"], ["caziel_order_threshold", "caziel_shadows_evasion"]],
		"model": "hero_caziel"})
	_add_heroes_15b()
	_add_heroes_16()
	_add_heroes_17()
	_add_heroes_18()

static func _add_heroes_15b() -> void:
	# Tock, the Clockmaker (run 2026-10-15 b; names and numbers are ours, chosen to sit beside Dota's ranged
	# intelligence supports): an old tinkerer who bends time. Six skills.
	_add("tock", {"name": "Tock", "title": "the Clockmaker", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 21.0, "dmg_max": 27.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.4, "backswing": 0.5, "acquire": 800.0, "range": 575.0,
		"projectile_speed": 900.0, "move_speed": 295.0, "turn_rate": 0.6, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "int", "str": 19.0, "str_gain": 2.0, "agi": 17.0, "agi_gain": 1.7, "int": 25.0,
		"int_gain": 3.2, "element": EL.LIGHT,
		"abilities": ["time_bolt", "fast_forward", "rewind", "slow_field", "quick_hands", "stop_time"],
		"talents": [["tock_bolt_damage", "tock_mana_regen"], ["tock_field_slow", "tock_forward_rate"],
			["tock_rewind_cooldown", "tock_hands"], ["tock_stop_duration", "tock_bolt_delay"]],
		"model": "hero_tock"})
	# Kragg, the Magnet Knight (run 2026-10-15 b; ours, numbers chosen beside Dota's melee strength initiators): a
	# knight in iron plate who is a living magnet. Four skills and Magnetize as his innate (owner's rework 2026-10-15 g).
	_add("kragg", {"name": "Kragg", "title": "the Magnet Knight", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 1.0, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 2.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 31.0, "dmg_max": 37.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.45, "backswing": 0.55, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 300.0, "turn_rate": 0.6, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "str", "str": 25.0, "str_gain": 3.1, "agi": 14.0, "agi_gain": 1.6, "int": 17.0,
		"int_gain": 1.8, "element": EL.LIGHTNING,
		"abilities": ["iron_grip", "repel", "overload", "magnet_field"], "innate": "magnetize",
		"talents": [["kragg_grip_damage", "kragg_armor"], ["kragg_repel_cooldown", "kragg_charge_max"],
			["kragg_overload_damage", "kragg_field_pull"], ["kragg_field_stun", "kragg_grip_charges"]],
		"model": "hero_kragg"})

static func _add_heroes_16() -> void:
	# Roydo, the Anomaly (the owner's hero, 2026-10-16): a melee intelligence hero of no element (Neutral), a space
	# alien who bends gravity. The owner gave the abilities; the stats follow the melee intelligence template (chosen).
	_add("roydo", {"name": "Roydo", "title": "the Anomaly", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.75, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 2.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 28.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.4, "backswing": 0.5, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "int", "str": 21.0, "str_gain": 2.6, "agi": 18.0, "agi_gain": 1.8, "int": 24.0,
		"int_gain": 3.2, "element": EL.NONE,
		"abilities": ["grip_of_the_ruler", "void_rush", "dark_matter_skin", "anomaly"],
		"talents": [["roydo_grip_damage", "roydo_health"], ["roydo_rush_cooldown", "roydo_skin_chance"],
			["roydo_grip_stun", "roydo_rush_cut"], ["roydo_anomaly_bat", "roydo_skin_reflect"]],
		"model": "hero_roydo"})
	# Blau, the Master Tactician (the owner's hero, 2026-10-16): a ranged agility gunner (600) of no element, a mage
	# with a scout sniper rifle. The owner gave the abilities and range; the rest follows the ranged agility template.
	_add("blau", {"name": "Blau", "title": "the Master Tactician", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 22.0, "dmg_max": 28.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.35, "backswing": 0.55, "acquire": 800.0, "range": 600.0,
		"projectile_speed": 3000.0, "move_speed": 295.0, "turn_rate": 0.6, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 18.0, "str_gain": 2.0, "agi": 23.0, "agi_gain": 3.1, "int": 18.0,
		"int_gain": 1.8, "element": EL.NONE,
		"abilities": ["bounce_shot", "summon_boulders", "lay_trap", "place_turret"],
		"talents": [["blau_shot_damage", "blau_attack_speed"], ["blau_boulders", "blau_trap_root"],
			["blau_bounces", "blau_turret_damage"], ["blau_shot_hits", "blau_turret_health"]],
		"model": "hero_blau"})
	# Blau's turret: shoots every 1.5 s at 650 with a share of his attack (SimKits3.turret_snapshot); no regeneration, no
	# mana, 35 s. Armor and bounty are chosen.
	_add("blau_turret", {"name": "Turret", "kind": K.SUMMON, "hull": 34.0, "hp": 900.0, "hp_regen": 0.0, "mana": 0.0,
		"armor": 4.0, "dmg_min": 10.0, "dmg_max": 12.0, "bat": 1.5, "attack_speed": 100.0, "attack_point": 0.15,
		"backswing": 0.25, "acquire": 650.0, "range": 650.0, "projectile_speed": 2200.0, "move_speed": 0.0,
		"can_move": false, "turn_rate": 2.5, "vision_day": 900.0, "vision_night": 700.0, "xp": 40.0, "gold_min": 40,
		"gold_max": 50, "element": EL.NONE, "model": "blau_turret"})

static func _add_heroes_17() -> void:
	# Azrael, the Death Dealer (the owner's hero, 2026-10-17): a melee (150) hero of the Dark element, a soul of white
	# flame in a black hooded robe who floats over the ground with a great scythe. The owner gave the kit and the
	# range; agility as her attribute and the stats follow the melee agility template (chosen, see HANDOFF).
	_add("azrael", {"name": "Azrael", "title": "the Death Dealer", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.5, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 1.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 27.0, "dmg_max": 31.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.35, "backswing": 0.5, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 300.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 19.0, "str_gain": 2.2, "agi": 22.0, "agi_gain": 3.0, "int": 17.0,
		"int_gain": 1.7, "element": EL.DARK,
		"abilities": ["soul_tap", "door_of_the_end", "death_scythe", "divine_darkness"],
		"talents": [["azrael_attack_speed", "azrael_soul_damage"], ["azrael_health", "azrael_door_time"],
			["azrael_scythe_chance", "azrael_scythe_damage"], ["azrael_door_damage", "azrael_darkness_cooldown"]],
		"model": "hero_azrael"})

static func _add_heroes_18() -> void:
	# The five heroes from hero_ideas.txt (2026-10-18 e, the owner: "build the game now with all the new 5 heroes
	# pickable by the player"): their names, titles, attack ranges, base stats and elements as written there (Airah's
	# element: Lightning, the file's pick for its open question). Their kits landed in run 2026-10-18 f (SimKits5,
	# SimKits6).
	var base := {"kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP, "mana": SimConst.HERO_BASE_MANA,
		"mana_regen": 0.0, "magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "attack_speed": 100.0, "backswing": 0.5,
		"vision_day": 1800.0, "vision_night": 800.0, "xp": 0.0, "abilities": [], "talents": []}
	_add("airah", _merged(base, {"name": "Airah", "title": "the Wind Goddess", "hp_regen": 0.25, "armor": 0.0,
		"dmg_min": 21.0, "dmg_max": 29.0, "bat": 1.7, "attack_point": 0.4, "acquire": 800.0, "range": 600.0,
		"projectile_speed": 1200.0, "move_speed": 300.0, "turn_rate": 0.6, "primary": "int", "str": 18.0,
		"str_gain": 2.0, "agi": 18.0, "agi_gain": 1.8, "int": 24.0, "int_gain": 3.4, "element": EL.LIGHTNING,
		"abilities": ["gust", "tailwind", "wind_wall", "hurricane"],
		"talents": [["airah_gust_damage", "airah_mana_regen"], ["airah_tailwind_miss", "airah_wall_time"],
			["airah_gust_cooldown", "airah_magic_amp"], ["airah_hurricane_damage", "airah_hurricane_radius"]],
		"model": "hero_airah"}))
	_add("burak", _merged(base, {"name": "Burak", "title": "the Berserker", "hp_regen": 0.5, "armor": 2.0,
		"dmg_min": 30.0, "dmg_max": 36.0, "bat": 1.7, "attack_point": 0.35, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.7, "primary": "str", "str": 25.0,
		"str_gain": 3.2, "agi": 18.0, "agi_gain": 2.1, "int": 15.0, "int_gain": 1.4, "element": EL.FIRE,
		"abilities": ["axe_throw", "reckless_swing", "unstoppable", "berserk"],
		"talents": [["burak_damage", "burak_axe_damage"], ["burak_rage_decay", "burak_swing_lifesteal"],
			["burak_unstoppable_rage", "burak_axe_window"], ["burak_berserk_time", "burak_berserk_return"]],
		"innate": "rage", "model": "hero_burak"}))
	_add("emelrich", _merged(base, {"name": "Ser Emelrich", "title": "the Heavy Sword", "hp_regen": 0.5,
		"armor": 3.0, "dmg_min": 37.0, "dmg_max": 43.0, "bat": 1.8, "attack_point": 0.55, "acquire": 600.0,
		"range": 150.0, "projectile_speed": 0.0, "move_speed": 290.0, "turn_rate": 0.5, "primary": "str",
		"str": 26.0, "str_gain": 3.4, "agi": 13.0, "agi_gain": 1.5, "int": 16.0, "int_gain": 1.6, "element": EL.LIGHT,
		"abilities": ["overhead_cut", "sweep", "steel_stance", "giant_swing"],
		"talents": [["emelrich_health", "emelrich_cut_stun"], ["emelrich_sweep_damage", "emelrich_sweep_shove"],
			["emelrich_stance_sides", "emelrich_cut_windup"], ["emelrich_swing_armor", "emelrich_swing_cooldown"]],
		"model": "hero_emelrich"}))
	_add("feran", _merged(base, {"name": "Feran Mock", "title": "the Jester", "hp_regen": 0.25, "armor": 1.0,
		"dmg_min": 20.0, "dmg_max": 26.0, "bat": 1.7, "attack_point": 0.35, "acquire": 800.0, "range": 550.0,
		"projectile_speed": 1100.0, "move_speed": 305.0, "turn_rate": 0.6, "primary": "int", "str": 18.0,
		"str_gain": 1.9, "agi": 20.0, "agi_gain": 2.2, "int": 23.0, "int_gain": 3.0, "element": EL.NONE,
		"abilities": ["knife_juggle", "joke_box", "swap", "shuffle"],
		"talents": [["feran_knives", "feran_magic_amp"], ["feran_two_pranks", "feran_swap_cooldown"],
			["feran_swap_range", "feran_box_damage"], ["feran_shuffle_stun", "feran_shuffle_radius"]],
		"model": "hero_feran"}))
	_add("ghorman", _merged(base, {"name": "Ghorman", "title": "the Beast King", "hp_regen": 0.5, "armor": 1.0,
		"dmg_min": 30.0, "dmg_max": 36.0, "bat": 1.7, "attack_point": 0.4, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.6, "primary": "str", "str": 24.0,
		"str_gain": 3.0, "agi": 17.0, "agi_gain": 1.9, "int": 18.0, "int_gain": 1.8, "element": EL.NATURE,
		"abilities": ["tame", "roar", "pack_leader", "blessing_of_the_beast_king", "beast_form"],
		"talents": [["ghorman_beasts", "ghorman_roar_speed"], ["ghorman_tame_power", "ghorman_tame_cooldown"],
			["ghorman_pack_armor", "ghorman_roar_radius"], ["ghorman_form_time", "ghorman_maul_every"]],
		"model": "hero_ghorman"}))

static func _named(d: Dictionary, name: String, model: String) -> Dictionary:
	var o := d.duplicate()
	o["name"] = name
	o["model"] = model
	return o

static func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate()
	o.merge(b, true)
	return o

# ---- Abilities ----------------------------------------------------------------------------------------------------
## behaviour: "passive", "no_target", "point", "unit", "autocast_attack"; values are per level arrays.

static func _build_abilities() -> void:
	# Blood Ranger. Values the owner specified: Burst Shot 30 arrows in 5 waves of 4-7, 55% + 10% per level of attack
	# damage, channelled, 17 s; Gale Impact 2000 range, 120 + 80 per level, +20% on impact, 12 s; Masterful Archery
	# (15% + 10% per level) of agility, 0.8 s cooldown; Blood Ranger 15 s, 40% + 10% lifesteal, +200 + 100 range, 30%
	# back leap of 300, 30 s. Everything else (mana, ranges, radii, timings, proc chance) is chosen; see docs/HANDOFF.md.
	_abilities["burst_shot"] = {"id": "burst_shot", "name": "Burst Shot", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [17, 17, 17, 17], "cast_point": 0.2, "range": 900,
		"anim": "bow_draw_hold", "damage_type": "physical", "channel": true, "channel_breaks_on_root": true,
		"values": {"arrows": [30, 30, 30, 30], "waves": [5, 5, 5, 5], "wave_min": [4, 4, 4, 4], "wave_max": [7, 7, 7, 7],
		"attack_pct": [0.55, 0.65, 0.75, 0.85], "radius": [400, 400, 400, 400], "wave_interval": [0.4, 0.4, 0.4, 0.4],
		"arrow_speed": [1800, 1800, 1800, 1800]},
		"desc": "Jayla plants her feet and looses 30 arrows over five waves of four to seven into the target area. Each arrow strikes a random enemy there for a share of her attack damage. Channelled: moving, attacking, stopping, a stun, silence or a push ends it."}
	_abilities["gale_impact"] = {"id": "gale_impact", "name": "Gale Impact", "behavior": "point", "key": "W",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [12, 12, 12, 12], "cast_point": 0.3, "range": 2000,
		"anim": "bow_1", "damage_type": "magical", "line": true, "direction": true,
		"values": {"damage": [120, 200, 280, 360], "impact_pct": [0.2, 0.2, 0.2, 0.2], "width": [110, 110, 110, 110],
		"speed": [2000, 2000, 2000, 2000], "distance": [2000, 2000, 2000, 2000], "push_speed": [963, 963, 963, 963]},
		"desc": "Looses a great arrow toward the target point; it always flies its full 2000 range. Every enemy it passes is struck for magic damage and hurled aside; an enemy that crashes into a wall, unit, building or tree takes another 20% of that damage. The arrow fells every tree in its path, and so do the units it throws."}
	_abilities["masterful_archery"] = {"id": "masterful_archery", "name": "Masterful Archery", "behavior": "passive",
		"key": "E", "max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0.8, 0.8, 0.8, 0.8], "cast_point": 0.0,
		"range": 0, "damage_type": "physical",
		"values": {"chance": [0.3, 0.3, 0.3, 0.3], "agility_pct": [0.15, 0.25, 0.35, 0.45], "proc_cooldown": [0.8, 0.8, 0.8, 0.8]},
		"desc": "Her attacks have a chance to burst for bonus physical damage based on her agility. Cooldown after each burst."}
	_abilities["blood_ranger_ult"] = {"id": "blood_ranger_ult", "name": "Blood Ranger", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [100, 125, 150], "cooldown": [30, 30, 30],
		"cast_point": 0.3, "range": 0, "anim": "war_cry",
		"values": {"duration": [15, 15, 15], "lifesteal": [0.4, 0.5, 0.6], "bonus_range": [200, 300, 400],
		"leap_chance": [0.3, 0.3, 0.3], "leap_distance": [300, 300, 300], "leap_time": [0.3, 0.3, 0.3],
		"leap_cooldown": [1.0, 1.0, 1.0]},
		"desc": "Jayla gives in to the hunt: for 15 seconds her attacks steal life and reach much further. When an attack hits her she may leap back out of reach."}
	# Ezee, the Dark Paladin
	_abilities["dark_stomp"] = {"id": "dark_stomp", "name": "Dark Stomp", "behavior": "no_target", "key": "Q",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [12, 12, 12, 12], "cast_point": 0.45, "range": 0,
		"anim": "boss_slam", "damage_type": "magical",
		"values": {"radius": [350, 350, 350, 350], "damage": [60, 90, 120, 150], "push_speed": [1000, 1000, 1000, 1000],
		"impact_damage": [50, 75, 100, 125], "impact_stun": [0.7, 1.4, 2.1, 2.8]},
		"desc": "Ezee slams the ground with unholy force, damaging nearby enemies and hurling them away. Enemies that crash into a unit, tree, cliff or wall take impact damage and are stunned."}
	_abilities["leap_strike"] = {"id": "leap_strike", "name": "Leap Strike", "behavior": "no_target", "key": "W",
		"max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [16, 15, 14, 13], "cast_point": 0.2, "range": 800,
		"anim": "leap_slam", "damage_type": "pure",
		"values": {"damage": [100, 125, 150, 175], "str_mult": [0.6, 0.6, 0.6, 0.6], "slow": [0.4, 0.4, 0.4, 0.4],
		"slow_duration": [1.5, 1.5, 1.5, 1.5], "leap_time": [0.55, 0.55, 0.55, 0.55]},
		"desc": "Ezee picks the visible enemy in range with the lowest health (the nearest one if none is hurt), leaps onto it and strikes for pure damage plus 60% of his strength, slowing it. Does nothing if no enemy is in sight."}
	_abilities["tainted_touch"] = {"id": "tainted_touch", "name": "Tainted Touch", "behavior": "no_target", "key": "E",
		"max_level": 4, "mana": [70, 80, 90, 100], "cooldown": [11, 11, 11, 11], "cast_point": 0.35, "range": 0,
		"anim": "cast_weapon", "damage_type": "magical", "element": "lightning",
		"values": {"bonus_damage": [60, 90, 120, 150], "duration": [7, 7, 7, 7], "curse_duration": [5, 5, 5, 5],
		"curse_vision": [300, 300, 300, 300]},
		"desc": "Purple lightning from the sky enchants Ezee's sword. His attacks deal bonus magic damage and curse the target, revealing it and granting sight around it, even through invisibility."}
	_abilities["unholy_might"] = {"id": "unholy_might", "name": "Unholy Might", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [100, 125, 150], "cooldown": [25, 25, 25],
		"cast_point": 0.5, "range": 0, "anim": "boss_roar", "damage_type": "pure",
		"values": {"duration": [10, 10, 10], "chance": [0.3, 0.4, 0.5], "reflect_radius": [700, 700, 700],
		"fatigue_slow": [0.5, 0.5, 0.5], "fatigue_duration": [2, 2, 2]},
		"desc": "Ezee roars and is wrapped in a dark aura. Each instance of damage he takes has a chance to be halved, the other half striking a random nearby enemy as pure damage. When the aura fades he is slowed for 2 seconds."}
	# Sludge, the Butcher (Pudge, 7.41d). Every number is Dota's; see docs/HANDOFF.md.
	_abilities["growing_gut"] = {"id": "growing_gut", "name": "Growing Gut", "behavior": "innate", "key": "",
		"max_level": 1, "mana": [0], "cooldown": [0], "cast_point": 0.0, "range": 0,
		"values": {"str_per_stack": [2.0], "radius": [450.0]},
		"desc": "Sludge gains 2 strength for good whenever an enemy hero dies within 450 of him, or anywhere if he gets the kill."}
	_abilities["shuriken_hook"] = {"id": "shuriken_hook", "name": "Shuriken Hook", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [120, 120, 120, 120], "cooldown": [18, 16, 14, 12], "cast_point": 0.3, "range": 1300,
		"anim": "cast_quick", "damage_type": "pure", "line": true,
		"values": {"damage": [150, 220, 290, 360], "distance": [1300, 1300, 1300, 1300], "speed": [1600, 1600, 1600, 1600],
		"width": [100, 100, 100, 100], "lock_pct": [0.65, 0.65, 0.65, 0.65], "vision_radius": [500, 500, 500, 500],
		"vision_duration": [4, 4, 4, 4]},
		"shard": {"drag_damage_pct": 0.2, "ally_cooldown_pct": 0.5},
		"desc": "Sludge hurls a chain tipped with a spinning shuriken. It always flies its full 1300 range and catches the first unit it touches, dragging it back to where he threw it. Enemies take pure damage and are stunned while dragged; enemy creeps die at once; allies are pulled to safety unharmed. The chain flies over cliffs and trees."}
	_abilities["stench"] = {"id": "stench", "name": "Stench", "behavior": "toggle", "key": "W", "element": "nature",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "magical",
		"values": {"radius": [250, 250, 250, 250], "dps": [30, 60, 90, 120], "slow": [0.14, 0.20, 0.26, 0.32],
		"tick": [0.2, 0.2, 0.2, 0.2], "linger": [0.5, 0.5, 0.5, 0.5], "heal_reduction": [0.0, 0.0, 0.0, 0.0]},
		"scepter": {"radius": 200.0, "dps": 90.0, "heal_reduction": 0.2},
		"desc": "A toxic cloud pours off Sludge, damaging and slowing nearby enemies, and hurting Sludge himself (it can never kill him). Toggle it on and off. Keeps working while he is stunned."}
	_abilities["blubber"] = {"id": "blubber", "name": "Blubber", "behavior": "no_target", "key": "E", "immediate": true,
		"max_level": 4, "mana": [65, 70, 75, 80], "cooldown": [20, 19, 18, 17], "cast_point": 0.0, "range": 0,
		"values": {"block": [8, 14, 20, 26], "duration": [4, 5, 6, 7]},
		"desc": "Sludge's fat thickens: every instance of damage he takes, from any source, is reduced by a flat amount for a few seconds. Does not interrupt Chomp."}
	_abilities["chomp"] = {"id": "chomp", "name": "Chomp", "behavior": "unit", "key": "R", "target_team": "enemy",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [100, 130, 170], "cooldown": [30, 25, 20],
		"cast_point": 0.3, "range": 200, "anim": "cast_channel", "damage_type": "magical", "channel": true,
		"values": {"dps": [80, 100, 120], "str_mult": [0.3, 0.6, 0.9], "duration": [2.75, 2.75, 2.75], "ticks": [6, 6, 6],
		"pull_speed": [75, 75, 75], "pull_min": [125, 125, 125], "damage_mult": [1.0, 1.0, 1.0]},
		"desc": "Sludge grabs an enemy and eats it alive. Channelled for 2.75 seconds: the victim is stunned and pulled in, taking magic damage that grows with his strength, and Sludge heals for all of it."}

	# Azrin, the Flamemander. The owner's numbers: Fiery Javelin 1000 range, burns 35 (+35 per level) magic damage per
	# second for 5 s, 12 s; Touch of Ember 300 area, 100 magic damage, then 100 (+100 per level) and a 1.7 s stun when
	# the enemy casts a spell or after 4 s, 9 s; Spirit of Fire: a spirit per spell cast (up to 5), shot at a 250 area,
	# each burning 100 (+50 per level) over 5 s and slowing 20% (+5% per level); Divine Smite: 250 + 2 x intelligence
	# magic damage, every Fire burn in the area lasts 2 s (+1.5 s per level) longer, 45 s. Mana, cast ranges, speeds,
	# widths and Spirit of Fire's cooldown are chosen (docs/HANDOFF.md).
	_abilities["fiery_javelin"] = {"id": "fiery_javelin", "name": "Fiery Javelin", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [12, 12, 12, 12], "cast_point": 0.35, "range": 1000,
		"anim": "cast_heavy", "damage_type": "magical", "element": "fire", "line": true, "direction": true,
		"values": {"burn_dps": [35, 70, 105, 140], "burn_duration": [5, 5, 5, 5], "distance": [1000, 1000, 1000, 1000],
		"min_distance": [300, 300, 300, 300], "speed": [1400, 1400, 1400, 1400], "width": [150, 150, 150, 150]},
		"desc": "Azrin hurls a great flaming javelin up to 1000 range. Every enemy near its path is caught and dragged along to where it lands, and burns for magic damage every second for 5 seconds. Trees in its path are knocked down."}
	_abilities["touch_of_ember"] = {"id": "touch_of_ember", "name": "Touch of Ember", "behavior": "point", "key": "W",
		"max_level": 4, "mana": [110, 120, 130, 140], "cooldown": [9, 9, 9, 9], "cast_point": 0.3, "range": 700,
		"anim": "cast_area", "damage_type": "magical", "element": "fire",
		"values": {"radius": [300, 300, 300, 300], "damage": [100, 100, 100, 100], "explode_damage": [100, 200, 300, 400],
		"delay": [4, 4, 4, 4], "stun": [1.7, 1.7, 1.7, 1.7]},
		"desc": "Spirit flames burst over a 300 area: enemies take 100 magic damage and carry the flames. When one of them casts a spell, or after 4 seconds, the flames explode for more magic damage and stun it."}
	_abilities["spirit_of_fire"] = {"id": "spirit_of_fire", "name": "Spirit of Fire", "behavior": "point", "key": "E",
		"max_level": 4, "mana": [50, 50, 50, 50], "cooldown": [4, 4, 4, 4], "cast_point": 0.2, "range": 800,
		"anim": "cast_quick", "damage_type": "magical", "element": "fire",
		"values": {"radius": [250, 250, 250, 250], "max_spirits": [5, 5, 5, 5], "burn": [100, 150, 200, 250],
		"duration": [5, 5, 5, 5], "slow": [0.2, 0.25, 0.3, 0.35], "speed": [900, 900, 900, 900]},
		"desc": "Every spell Azrin casts adds a spirit of fire circling her, up to 5. Shoot them all at a 250 area: each spirit burns the enemies there for magic damage over 5 seconds, and they are slowed while they burn."}
	_abilities["divine_smite"] = {"id": "divine_smite", "name": "Divine Smite", "behavior": "unit", "key": "R",
		"target_team": "enemy", "max_level": 3, "required_level": [6, 12, 18], "mana": [150, 200, 250],
		"cooldown": [45, 45, 45], "cast_point": 0.4, "range": 700, "anim": "cast_ultimate", "damage_type": "magical",
		"element": "fire",
		"values": {"damage": [250, 250, 250], "int_mult": [2.0, 2.0, 2.0], "radius": [400, 400, 400],
		"extend": [2.0, 3.5, 5.0], "speed": [1100, 1100, 1100]},
		"desc": "Azrin hurls a burning hammer at an enemy. It strikes for 250 plus twice her intelligence as magic damage and sets the ground around it alight: every Fire burn on enemies there lasts longer."}

	# Froster, the Winter Master. The owner's numbers: Breath of Cold 800 reach, 30% slow (+8% per level) for 3 s,
	# 100 magic damage (+70 per level), 10 s; Ice Pulse 20% lower defense (+5% per level) for 3.5 s, then a 100 damage
	# blast in 300, 16/15/14/13 s; Frost Heart a heart per 500/450/400/350 damage, 200 magic burst and a 40% slow for
	# 1.5 s on one attack; Endless Winter 7 s channel, 600 area, 100/200/300 damage per second, Frosted (stunned) 2 s
	# after 2 s inside, 1.5 s before it can happen again, 60 s. Mana, cast ranges, widths and speeds are chosen.
	_abilities["breath_of_cold"] = {"id": "breath_of_cold", "name": "Breath of Cold", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [10, 10, 10, 10], "cast_point": 0.3, "range": 800,
		"anim": "cast_heavy", "damage_type": "magical", "element": "ice", "line": true, "direction": true, "cone": true,
		"values": {"damage": [100, 170, 240, 310], "slow": [0.30, 0.38, 0.46, 0.54], "slow_duration": [3, 3, 3, 3],
		"distance": [800, 800, 800, 800], "start_width": [150, 150, 150, 150], "end_width": [450, 450, 450, 450],
		"speed": [1300, 1300, 1300, 1300]},
		"desc": "Froster breathes a cone of bitter cold up to 800 ahead. Every enemy in it takes magic damage and is slowed for 3 seconds."}
	_abilities["ice_pulse"] = {"id": "ice_pulse", "name": "Ice Pulse", "behavior": "unit", "key": "W",
		"target_team": "enemy", "max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [16, 15, 14, 13],
		"cast_point": 0.3, "range": 650, "anim": "cast_quick", "damage_type": "magical", "element": "ice",
		"values": {"defense_loss": [0.20, 0.25, 0.30, 0.35], "duration": [3.5, 3.5, 3.5, 3.5],
		"blast_damage": [100, 100, 100, 100], "blast_radius": [300, 300, 300, 300]},
		"desc": "Curses an enemy: its defense drops (armor and every resistance count less, so it takes more physical and magic damage) for 3.5 seconds. Then the curse bursts in an ice blast that deals 100 magic damage to it and every enemy within 300."}
	_abilities["frost_heart"] = {"id": "frost_heart", "name": "Frost Heart", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "magical", "element": "ice",
		"values": {"per_heart": [500, 450, 400, 350], "burst": [200, 200, 200, 200], "slow": [0.4, 0.4, 0.4, 0.4],
		"slow_duration": [1.5, 1.5, 1.5, 1.5], "max_hearts": [3, 3, 3, 3]},
		"desc": "Damage Froster deals to enemies builds a Frost Heart (one per 500 / 450 / 400 / 350 damage, up to 3). His next attack spends one: 200 extra magic damage and a 40% slow for 1.5 seconds."}
	_abilities["endless_winter"] = {"id": "endless_winter", "name": "Endless Winter", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 225, 300], "cooldown": [60, 60, 60],
		"cast_point": 0.3, "range": 0, "anim": "cast_channel", "damage_type": "magical", "element": "ice", "channel": true,
		"channel_breaks_on_root": false,
		"values": {"duration": [7, 7, 7], "radius": [600, 600, 600], "dps": [100, 200, 300], "frost_after": [2, 2, 2],
		"frost_stun": [2, 2, 2], "frost_cooldown": [1.5, 1.5, 1.5], "pulse": [1, 1, 1]},
		"desc": "Froster stands still and calls a blizzard for up to 7 seconds. Enemies within 600 take magic damage every second; one that stays inside for 2 seconds is Frosted, frozen solid for 2 seconds (once every 1.5 seconds after that). Channelled."}

	# Caziel, the Void Assassin. The owner's numbers: Swift Dagger 80/140/200/260 bonus physical damage, armor -4/5/6/7
	# for 3 s, 15/12/9/6 s; Sweet Poison 20/24/28/32% chance, 50/60/70/80 damage per second for 2 s, no stacking; Master
	# of Shadows 12 s off the enemy minimap, +30/35/40/45% evasion, +12/13/14/15% speed, 20 s; Death Order pure damage
	# on attacks below 10/12/14% health. Mana and the dagger's range are chosen.
	_abilities["swift_dagger"] = {"id": "swift_dagger", "name": "Swift Dagger", "behavior": "unit", "key": "Q",
		"target_team": "enemy", "max_level": 4, "mana": [50, 55, 60, 65], "cooldown": [15, 12, 9, 6], "cast_point": 0.1,
		"range": 1000, "anim": "blink", "damage_type": "physical",
		"values": {"bonus_damage": [80, 140, 200, 260], "armor_cut": [4, 5, 6, 7], "armor_duration": [3, 3, 3, 3]},
		"desc": "Caziel flashes to an enemy in a trail of shadows and stabs it at once with his attack plus bonus physical damage, cutting its armor for 3 seconds."}
	_abilities["sweet_poison"] = {"id": "sweet_poison", "name": "Sweet Poison", "behavior": "passive", "key": "W",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "magical", "element": "nature",
		"values": {"chance": [0.20, 0.24, 0.28, 0.32], "dps": [50, 60, 70, 80], "duration": [2, 2, 2, 2]},
		"desc": "Each attack has a chance to land a second, poisoned blow: the target takes poison damage every second for 2 seconds. A new poison renews the old one; they do not stack."}
	_abilities["master_of_shadows"] = {"id": "master_of_shadows", "name": "Master of Shadows", "behavior": "no_target",
		"key": "E", "max_level": 4, "mana": [60, 60, 60, 60], "cooldown": [20, 20, 20, 20], "cast_point": 0.0, "range": 0,
		"immediate": true,
		"values": {"duration": [12, 12, 12, 12], "evasion": [0.30, 0.35, 0.40, 0.45], "move_pct": [0.12, 0.13, 0.14, 0.15]},
		"desc": "Caziel wraps himself in shadows for 12 seconds: he vanishes from the enemy minimap, evades attacks more often and moves faster."}
	_abilities["death_order"] = {"id": "death_order", "name": "Death Order", "behavior": "passive", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [0, 0, 0], "cooldown": [0, 0, 0], "cast_point": 0.0,
		"range": 0, "damage_type": "pure",
		"values": {"threshold": [0.10, 0.12, 0.14]},
		"desc": "Caziel strikes hardest when an enemy is about to die: his attacks deal pure damage to enemies below 10 / 12 / 14% health."}

# ---- Tock and Kragg (run 2026-10-15 b; our heroes, chosen numbers, see docs/HANDOFF.md) ------------------------------

static func _build_abilities_15b() -> void:
	# Tock, the Clockmaker. Cooldown rate: -0.4 = an enemy's cooldowns run 40% slower; +1 = an ally's run twice as fast.
	_abilities["time_bolt"] = {"id": "time_bolt", "name": "Time Bolt", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [10, 9, 8, 7], "cast_point": 0.3, "range": 1000,
		"anim": "cast_quick", "damage_type": "magical", "element": "light", "line": true, "direction": true,
		"values": {"damage": [90, 150, 210, 270], "delay": [0.3, 0.4, 0.5, 0.6], "delay_duration": [4, 4, 4, 4],
		"distance": [1000, 1000, 1000, 1000], "width": [120, 120, 120, 120], "speed": [1400, 1400, 1400, 1400]},
		"desc": "Tock fires a bolt of slowed time up to 1000 ahead. Every enemy it passes takes magic damage, and for 4 seconds its spell and item cooldowns run 30 / 40 / 50 / 60% slower."}
	_abilities["fast_forward"] = {"id": "fast_forward", "name": "Fast Forward", "behavior": "unit", "key": "W",
		"target_team": "ally", "max_level": 4, "mana": [80, 80, 80, 80], "cooldown": [18, 16, 14, 12], "cast_point": 0.2,
		"range": 700, "anim": "cast_quick", "element": "light",
		"values": {"cut": [2.0, 3.5, 5.0, 6.5], "move_pct": [0.10, 0.14, 0.18, 0.22], "duration": [5, 5, 5, 5]},
		"desc": "Winds an ally (or Tock) forward: 2 / 3.5 / 5 / 6.5 seconds come off the cooldowns of its basic spells (not its ultimate, not items), and it moves 10 / 14 / 18 / 22% faster for 5 seconds."}
	_abilities["rewind"] = {"id": "rewind", "name": "Rewind", "behavior": "no_target", "key": "E", "immediate": true,
		"max_level": 4, "mana": [75, 75, 75, 75], "cooldown": [28, 24, 20, 16], "cast_point": 0.0, "range": 0,
		"element": "light", "values": {"back": [3, 3, 3, 3]},
		"desc": "Tock steps back to where he stood 3 seconds ago, with the health and mana he had then if he had more. Removes slows and silences (a basic dispel) and dodges projectiles on the way."}
	_abilities["slow_field"] = {"id": "slow_field", "name": "Slow Field", "behavior": "point", "key": "D",
		"max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [18, 16, 14, 12], "cast_point": 0.3, "range": 900,
		"anim": "cast_area", "element": "light",
		"values": {"radius": [350, 350, 350, 350], "duration": [5, 5, 5, 5], "slow": [0.30, 0.35, 0.40, 0.45],
		"attack_slow": [40, 60, 80, 100]},
		"desc": "A field of slowed time for 5 seconds: enemies inside move 30 / 35 / 40 / 45% slower and attack slower."}
	_abilities["quick_hands"] = {"id": "quick_hands", "name": "Quick Hands", "behavior": "passive", "key": "F",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"values": {"cut": [1.0, 1.5, 2.0, 2.5]},
		"desc": "Every spell Tock casts takes 1 / 1.5 / 2 / 2.5 seconds off the cooldowns of his other spells."}
	_abilities["stop_time"] = {"id": "stop_time", "name": "Stop Time", "behavior": "point", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 200, 250], "cooldown": [110, 95, 80],
		"cast_point": 0.3, "range": 800, "anim": "cast_ultimate", "element": "light",
		"values": {"radius": [400, 400, 400], "duration": [2.5, 3.0, 3.5]},
		"desc": "Time stops in a 400 area: every enemy there is frozen (stunned) and its cooldowns stand still for 2.5 / 3 / 3.5 seconds. Tock's allies keep moving."}
	# Kragg, the Magnet Knight. Charges sit on enemies (up to 4, 8 s); his spells pull and throw by them.
	_abilities["iron_grip"] = {"id": "iron_grip", "name": "Iron Grip", "behavior": "unit", "key": "Q",
		"target_team": "enemy", "max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [14, 13, 12, 11],
		"cast_point": 0.25, "range": 650, "anim": "shield_bash", "damage_type": "magical", "element": "lightning",
		"values": {"damage": [80, 120, 160, 200], "stun": [0.8, 1.0, 1.2, 1.4], "charges": [2, 2, 2, 2],
		"pull_time": [0.3, 0.3, 0.3, 0.3]},
		"desc": "Kragg magnetizes an enemy: the two snap together and meet halfway. The enemy takes magic damage, is stunned and gets 2 Charges."}
	_abilities["repel"] = {"id": "repel", "name": "Repel", "behavior": "no_target", "key": "W",
		"max_level": 4, "mana": [100, 100, 100, 100], "cooldown": [13, 12, 11, 10], "cast_point": 0.3, "range": 0,
		"anim": "war_cry", "damage_type": "magical", "element": "lightning",
		"values": {"radius": [375, 375, 375, 375], "damage": [60, 100, 140, 180], "push_speed": [900, 900, 900, 900],
		"per_charge": [0.25, 0.25, 0.25, 0.25], "slow": [0.3, 0.3, 0.3, 0.3], "slow_duration": [2, 2, 2, 2],
		"impact_damage": [40, 70, 100, 130], "impact_stun": [0.8, 0.8, 0.8, 0.8]},
		"desc": "A magnetic blast throws enemies near Kragg away, 25% further for each Charge they carry, and slows them. One that crashes into a tree, wall or unit takes more damage and is stunned. Adds a Charge."}
	# owner's numbers (2026-10-15 g): Magnetize is innate, 0.10% spell amp per Charge (+0.05% per hero level), up to 4
	# Charges for 8 s; Overload is a passive burst every 6 / 5 / 4 / 3 attacks
	_abilities["magnetize"] = {"id": "magnetize", "name": "Magnetize", "behavior": "innate", "key": "",
		"max_level": 1, "mana": [0], "cooldown": [0], "cast_point": 0.0, "range": 0,
		"values": {"spell_amp": [0.001], "spell_amp_per_level": [0.0005], "max_charges": [4], "duration": [8]},
		"desc": "Kragg's attacks give enemies a Charge (up to 4, for 8 seconds). Each Charge makes the enemy take 0.10% more damage from his spells, +0.05% per hero level."}
	_abilities["overload"] = {"id": "overload", "name": "Overload", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "magical", "element": "lightning",
		"values": {"every": [6, 5, 4, 3], "radius": [200, 200, 200, 200], "damage": [60, 75, 90, 105],
		"slow": [0.80, 0.80, 0.80, 0.80], "slow_duration": [0.8, 0.8, 0.8, 0.8]},
		"desc": "Every 6th / 5th / 4th / 3rd attack, Kragg overloads and bursts electric charge around him: enemies within 200 are slowed by 80% for 0.8 seconds and take 60 / 75 / 90 / 105 electric magic damage (Lightning element)."}
	_abilities["magnet_field"] = {"id": "magnet_field", "name": "Magnet Field", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 200, 250], "cooldown": [100, 90, 80],
		"cast_point": 0.3, "range": 0, "anim": "boss_roar", "damage_type": "magical", "element": "lightning",
		"values": {"duration": [6, 6, 6], "radius": [700, 700, 700], "pull": [60, 80, 100], "pull_per_charge": [15, 15, 15],
		"end_radius": [300, 300, 300], "end_stun": [1.0, 1.5, 2.0], "end_damage": [100, 175, 250]},
		"desc": "For 6 seconds Kragg is a giant magnet: enemies within 700 are dragged toward him (harder with each Charge) and gain a Charge every second. When it ends, enemies within 300 take magic damage and are stunned."}

# ---- Roydo and Blau (run 2026-10-16; the owner's kits, his numbers; chosen fill-ins listed in docs/HANDOFF.md) ------

static func _build_abilities_16() -> void:
	# Roydo, the Anomaly
	_abilities["grip_of_the_ruler"] = {"id": "grip_of_the_ruler", "name": "Grip of the Ruler", "behavior": "point",
		"key": "Q", "max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [18, 17, 16, 15], "cast_point": 0.35,
		"range": 650, "anim": "roydo_cast_shoot", "damage_type": "magical", "aoe": true,
		"values": {"damage": [100, 140, 180, 220], "radius": [400, 400, 400, 400], "stun": [1.0, 1.0, 1.0, 1.0],
		"toss_time": [0.8, 0.8, 0.8, 0.8]}, "hidden_values": ["toss_time"],
		"desc": "Roydo's gravity seizes one unit in a 400 area, enemy heroes first, and throws it to the middle over 0.8 seconds. Then every enemy there takes magic damage and is stunned for 1 second. With no enemy in the area, an ally is thrown instead and comes to no harm."}
	_abilities["void_rush"] = {"id": "void_rush", "name": "Void Rush", "behavior": "no_target", "key": "W",
		"max_level": 4, "mana": [80, 90, 100, 110], "cooldown": [15, 14, 13, 12], "cast_point": 0.25, "range": 0,
		"anim": "roydo_cast_throw",
		"values": {"radius": [650, 650, 650, 650], "duration": [7, 7, 7, 7], "status_cut": [0.2, 0.3, 0.4, 0.5],
		"damage_cut": [0.10, 0.15, 0.20, 0.25], "armor": [7, 9, 11, 13], "move_pct": [0.07, 0.09, 0.11, 0.13]},
		"desc": "A wave of gravity rolls out 650 around Roydo for 7 seconds. Enemies lose 20 / 30 / 40 / 50% status resistance and deal 10 / 15 / 20 / 25% less damage. Allies gain 7 / 9 / 11 / 13 armor and move 7 / 9 / 11 / 13% faster."}
	_abilities["dark_matter_skin"] = {"id": "dark_matter_skin", "name": "Dark Matter Skin", "behavior": "passive",
		"key": "E", "max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "magical",
		"values": {"chance": [0.09, 0.13, 0.17, 0.21], "reflect": [0.25, 0.28, 0.31, 0.34], "radius": [650, 650, 650, 650],
		"slow": [0.8, 0.8, 0.8, 0.8], "attack_slow": [0.8, 0.8, 0.8, 0.8], "slow_duration": [0.3, 0.3, 0.3, 0.3]},
		"desc": "Damage Roydo takes has a 9 / 13 / 17 / 21% chance to burst back out: 25 / 28 / 31 / 34% of it hits every enemy within 650 as magic damage and slows their movement and attacks by 80% for 0.3 seconds."}
	_abilities["anomaly"] = {"id": "anomaly", "name": "Anomaly", "behavior": "no_target", "key": "R", "max_level": 3,
		"required_level": [6, 12, 18], "mana": [100, 125, 150], "cooldown": [65, 65, 65], "cast_point": 0.35,
		"range": 0, "anim": "roydo_cast_enter",
		"values": {"duration": [30, 30, 30], "damage": [60, 120, 180], "bat_cut": [0.25, 0.25, 0.25],
		"attack_range": [650, 650, 650], "projectile_speed": [1200, 1200, 1200]}, "hidden_values": ["projectile_speed"],
		"desc": "Roydo becomes the Anomaly, a hulking monster, for 30 seconds: his base attack time is 0.25 seconds shorter, he deals 60 / 120 / 180 more attack damage and he attacks from range (650)."}
	# Blau, the Master Tactician
	_abilities["bounce_shot"] = {"id": "bounce_shot", "name": "Bounce Shot", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [12, 11, 10, 9], "cast_point": 0.25, "range": 800,
		"anim": "blau_shoot", "damage_type": "magical", "bounce_path": true,
		"values": {"damage": [70, 110, 150, 190], "bounces": [3, 5, 7, 9], "max_hits": [2, 2, 2, 2],
		"distance": [1800, 1800, 1800, 1800], "bounce_distance": [400, 400, 400, 400], "speed": [2400, 2400, 2400, 2400]},
		"hidden_values": ["speed"],
		"desc": "Blau fires a magic bullet toward the target point. It passes through enemies and ricochets off trees, walls, boulders and other units, up to 3 / 5 / 7 / 9 times; each ricochet lets it fly 400 further. A tree it ricochets off is knocked down. Each enemy it passes takes magic damage, at most twice."}
	_abilities["summon_boulders"] = {"id": "summon_boulders", "name": "Summon Boulders", "behavior": "point",
		"key": "W", "max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [20, 19, 18, 17], "cast_point": 0.3,
		"range": 700, "anim": "blau_cast_throw", "damage_type": "magical", "direction": true,
		"values": {"count": [3, 4, 5, 6], "damage": [80, 100, 120, 140], "push": [200, 200, 200, 200],
		"duration": [10, 10, 10, 10], "distance": [700, 700, 700, 700], "min_distance": [200, 200, 200, 200],
		"roll_max": [2.5, 2.5, 2.5, 2.5], "speed_min": [520, 520, 520, 520], "speed_max": [760, 760, 760, 760],
		"spread": [0.6, 0.6, 0.6, 0.6]},
		"hidden_values": ["min_distance", "roll_max", "speed_min", "speed_max", "spread"],
		"desc": "3 / 4 / 5 / 6 boulders roll out toward the target point at random angles, as far as it (at most 700), bouncing off each other, walls and units. An enemy they hit takes magic damage once and is knocked 200 back. They stay for 10 seconds and block every unit, even phased ones. Bounce Shot ricochets off them."}
	_abilities["lay_trap"] = {"id": "lay_trap", "name": "Lay Trap", "behavior": "no_target", "key": "E",
		"max_level": 4, "mana": [50, 55, 60, 65], "cooldown": [10, 9, 8, 7], "cast_point": 0.1, "range": 0,
		"anim": "blau_jump_start",
		"values": {"leap": [400, 400, 400, 400], "leap_time": [0.5, 0.5, 0.5, 0.5], "root": [1.2, 1.6, 2.0, 2.4],
		"trap_duration": [25, 25, 25, 25], "trigger_radius": [110, 110, 110, 110], "arm_time": [0.6, 0.6, 0.6, 0.6]},
		"hidden_values": ["leap_time", "arm_time"],
		"desc": "Blau leaps 400 backwards and leaves a hidden trap where he stood. The first enemy to step on it is caught and cannot move for 1.2 / 1.6 / 2 / 2.4 seconds. The trap lasts 25 seconds."}
	_abilities["place_turret"] = {"id": "place_turret", "name": "Place Turret", "behavior": "point", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [100, 125, 150], "cooldown": [10, 10, 10],
		"cast_point": 0.5, "range": 600, "anim": "blau_kneel_fix",
		"values": {"hp": [900, 1500, 2100], "damage_pct": [0.25, 0.30, 0.35], "duration": [35, 35, 35],
		"attack_range": [650, 650, 650], "interval": [1.5, 1.5, 1.5]},
		"scepter": {"damage_pct": 0.05},
		"desc": "Blau builds a turret that shoots enemies within 650 every 1.5 seconds for 25 / 30 / 35% of his attack damage (40% at level 3 with the Upgrade Staff); his attack effects work with its shots. It has 900 / 1500 / 2100 health, no regeneration and lasts 35 seconds."}
	_abilities["pilot_turret"] = {"id": "pilot_turret", "name": "Pilot Turret", "behavior": "unit", "key": "D",
		"target_team": "ally", "granted": "scepter", "max_level": 3, "mana": [0, 0, 0], "cooldown": [5, 5, 5],
		"cast_point": 0.1, "range": 250, "anim": "blau_interact",
		"values": {"hp": [300, 600, 900]},
		"desc": "Upgrade Staff: Blau climbs into one of his turrets and pilots it. The turret gains 300 / 600 / 900 health and shoots what Blau attacks; Blau cannot be hurt inside and still attacks and casts from it. Cast again or move to get out. 5 second cooldown to get in."}

# ---- Neutral creep abilities (Dota 7.41d npc_abilities.txt; our names) -------------------------------------------------
## Cast by the neutral AI (SimAI) while the camp fights. Snarl: Giant Wolf's Intimidate; Stomp: Centaur Conqueror's War
## Stomp; Smash: Ogre Bruiser's Ogre Smash (a long 2.8 s wind-up that can be walked out of).

static func _build_neutral_abilities() -> void:
	_abilities["snarl"] = {"id": "snarl", "name": "Snarl", "behavior": "no_target", "key": "", "max_level": 1,
		"mana": [50], "cooldown": [16.0], "cast_point": 0.2, "range": 0, "anim": "cast",
		"values": {"radius": [300.0], "damage_reduction": [0.6], "duration": [4.0]},
		"desc": "The wolf snarls: nearby enemies deal 60% less attack damage for 4 seconds."}
	_abilities["stomp"] = {"id": "stomp", "name": "Stomp", "behavior": "no_target", "key": "", "max_level": 1, "element": "earth",
		"mana": [50], "cooldown": [12.0], "cast_point": 0.4, "range": 0, "anim": "cast", "damage_type": "magical",
		"values": {"radius": [250.0], "damage": [25.0], "hero_stun": [1.6], "stun": [3.0]},
		"desc": "Stomps the ground: enemies nearby take magic damage and are stunned (1.6 s heroes, 3 s others)."}
	_abilities["smash"] = {"id": "smash", "name": "Smash", "behavior": "point", "key": "", "max_level": 1,
		"mana": [0], "cooldown": [12.0], "cast_point": 2.8, "range": 150, "anim": "cast", "damage_type": "magical",
		"values": {"radius": [200.0], "damage": [200.0], "hero_stun": [2.4], "stun": [2.4]},
		"desc": "Raises its club for 2.8 seconds, then smashes the ground: enemies in the area take magic damage and are stunned."}

# ---- Talents ---------------------------------------------------------------------------------------------------------

## Azrael, the Death Dealer (2026-10-17). The owner's numbers: Soul Tap 700 range, 300 area, +15/20/25/30 damage a
## unit and +20 more a hero, 15 s, spent by one attack that cleaves 100%, 18 s, 80 mana; Door of the End 400 to the
## entrance, 800 to the exit, 3/4/5/6 s, 150/250/350/450 magic damage in 450, 12 s, her and two allies; Death Scythe
## 15/18/21/24% to strike pure with +30/40/50/60 pure, 1.5 s; Divine Darkness 25 s, flight, +30/50/70% sight, enemies
## within 700 -30/40/50% sight, +30/40/50 attack speed, 60 s. Chosen: the mana of Door of the End and Divine
## Darkness, cast points, the cleave cone (Dota's), the door's entry reach.
static func _build_abilities_17() -> void:
	_abilities["soul_tap"] = {"id": "soul_tap", "name": "Soul Tap", "behavior": "toggle", "key": "Q",
		"max_level": 4, "mana": [80, 80, 80, 80], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"damage_type": "pure", "aoe": true,
		"values": {"scan_interval": [4.5, 4.5, 4.5, 4.5], "radius": [600, 600, 600, 600],
		"per_unit": [20, 25, 30, 35], "per_hero": [40, 40, 40, 40], "duration": [15, 15, 15, 15],
		"cleave_pct": [1.0, 1.0, 1.0, 1.0], "cleave_start": [150, 150, 150, 150],
		"cleave_end": [400, 400, 400, 400], "cleave_distance": [400, 400, 400, 400],
		"slow": [0.80, 0.80, 0.80, 0.80], "slow_duration": [0.80, 0.80, 0.80, 0.80]},
		"hidden_values": ["cleave_start", "cleave_end"],
		"desc": "Toggle. Every 4.5 seconds Azrael scans 600 around her for souls (every unit but herself, allies and enemies alike). If at least one unit is found, it spends 80 mana and grants bonus attack damage on her next strike for each unit and each hero scanned. Her next attack deals pure damage in a 100% cleave over a 400 area, slowing hit enemies by 80% for 0.8 seconds."}
	_abilities["door_of_the_end"] = {"id": "door_of_the_end", "name": "Door of the End", "behavior": "point", "key": "W",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [12, 12, 12, 12], "cast_point": 0.3, "range": 400,
		"anim": "cast_heavy", "damage_type": "magical", "aoe": true,
		"values": {"duration": [3, 4, 5, 6], "exit_range": [800, 800, 800, 800], "damage": [150, 250, 350, 450],
		"heal": [100, 150, 200, 250], "stun": [1.0, 1.0, 1.0, 1.0],
		"element_resist_loss": [0.10, 0.16, 0.22, 0.28], "debuff_duration": [4.0, 4.0, 4.0, 4.0],
		"radius": [450, 450, 450, 450], "allies": [2, 2, 2, 2], "enter_radius": [110, 110, 110, 110]},
		"hidden_values": ["enter_radius"],
		"desc": "Azrael opens a door to the spirit world. She and up to two allied heroes can walk into it, hidden and unharmed, and may move to step out early without setting off the blast. Cast again to place the exit, up to 800 away. When the door closes, everyone inside steps out in a spirit blast that heals nearby allies, deals magic damage to enemies, stuns them for 1 second, and strips their elemental resistances for 4 seconds."}
	_abilities["death_scythe"] = {"id": "death_scythe", "name": "Death Scythe", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [1.0, 1.0, 1.0, 1.0], "cast_point": 0.0, "range": 0,
		"damage_type": "pure",
		"values": {"chance": [0.15, 0.18, 0.21, 0.24], "bonus": [30, 40, 50, 60],
		"lifesteal": [0.50, 0.50, 0.50, 0.50], "proc_cooldown": [1.0, 1.0, 1.0, 1.0]},
		"desc": "Azrael's attacks and spells have a chance to strike as pure damage, adding bonus pure damage and healing her for 50% of the damage done. 1 second cooldown after each strike."}
	_abilities["divine_darkness"] = {"id": "divine_darkness", "name": "Divine Darkness", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [100, 150, 200], "cooldown": [60, 60, 60],
		"cast_point": 0.4, "range": 0, "anim": "cast_ultimate",
		"values": {"duration": [25, 25, 25], "move_speed_pct": [0.15, 0.15, 0.15], "vision_bonus": [0.3, 0.5, 0.7],
		"vision_cut": [0.3, 0.4, 0.5], "radius": [700, 700, 700], "attack_speed": [30, 40, 50]},
		"desc": "Azrael spreads her white wings for 25 seconds: she flies over cliffs and trees, moves 15% faster, sees further day and night and attacks faster. Enemies within 700 of her lose part of their sight."}

# ---- The five heroes of hero_ideas.txt (run 2026-10-18 f; SimKits5, SimKits6) ------------------------------------------
## The numbers are the file's (the owner's annotations there win); chosen fill-ins (cast points, drag strength, Airah's
## talents, Blessing of the Beast King's effect) are listed in docs/HANDOFF.md. "width" here is the whole width
## ("full_width"), as the file writes it.

static func _build_abilities_18() -> void:
	# Airah, the Wind Goddess: she moves everyone
	_abilities["gust"] = {"id": "gust", "name": "Gust", "behavior": "point", "key": "Q", "max_level": 4,
		"mana": [110, 130, 150, 170], "cooldown": [12, 11, 10, 9], "cast_point": 0.3, "range": 900,
		"anim": "spell_wave", "damage_type": "magical", "line": true, "direction": true, "full_width": true,
		"values": {"damage": [80, 140, 200, 260], "crash_damage": [40, 60, 80, 100], "distance": [900, 900, 900, 900],
		"width": [200, 200, 200, 200], "speed": [1600, 1600, 1600, 1600], "drag": [650, 650, 650, 650],
		"drag_reach": [420, 420, 420, 420]}, "hidden_values": ["drag", "drag_reach"],
		"desc": "A blast of wind rushes 900 ahead, then turns back to Airah wherever she is. Every enemy it hits takes magic damage and is dragged along toward its head; enemies can still move and act, and can pull free by walking away. An enemy dragged into a tree, cliff, building or unit takes more damage. Trees it hits fall."}
	_abilities["tailwind"] = {"id": "tailwind", "name": "Tailwind", "behavior": "unit", "key": "W",
		"target_team": "ally", "max_level": 4, "mana": [100, 100, 100, 100], "cooldown": [16, 14, 12, 10],
		"cast_point": 0.2, "range": 800, "anim": "spell_quick",
		"values": {"duration": [5, 5, 5, 5], "move_pct": [0.16, 0.22, 0.28, 0.34], "ranged_miss": [0.25, 0.30, 0.35, 0.40]},
		"desc": "Wind at an ally's back (or Airah's) for 5 seconds: it moves 16 / 22 / 28 / 34% faster, walks through units, and ranged attacks against it miss 25 / 30 / 35 / 40% of the time. Removes slows when cast."}
	_abilities["wind_wall"] = {"id": "wind_wall", "name": "Wind Wall", "behavior": "point", "key": "E", "max_level": 4,
		"mana": [90, 100, 110, 120], "cooldown": [22, 20, 18, 16], "cast_point": 0.3, "range": 700, "anim": "spell_area",
		"values": {"duration": [4, 4.5, 5, 5.5], "width": [600, 600, 600, 600], "slow": [0.3, 0.3, 0.3, 0.3]},
		"desc": "A wall of wind 600 wide rises across Airah's aim for 4 / 4.5 / 5 / 5.5 seconds. Enemy ranged attacks that touch it stop. Enemies walking through it are slowed by 30%."}
	_abilities["hurricane"] = {"id": "hurricane", "name": "Hurricane", "behavior": "point", "key": "R", "max_level": 3,
		"required_level": [6, 12, 18], "mana": [150, 200, 250], "cooldown": [90, 80, 70], "cast_point": 0.4,
		"range": 900, "anim": "spell_big", "damage_type": "magical", "aoe": true,
		"values": {"radius": [450, 450, 450], "duration": [6, 6, 6], "pull": [400, 400, 400], "dps": [60, 90, 120],
		"throw": [450, 450, 450], "crash_stun": [1.0, 1.0, 1.0], "ally_move_pct": [0.25, 0.25, 0.25]},
		"desc": "A hurricane 450 wide for 6 seconds; Airah keeps moving and casting. Trees inside fall. Enemies inside are dragged toward its middle and take magic damage every second; allies inside move 25% faster. When it ends, every enemy still inside is thrown 450 straight out, and one that crashes into a tree, cliff, building or unit is stunned for 1 second."}
	# Burak, the Berserker: getting hurt makes him stronger
	_abilities["rage"] = {"id": "rage", "name": "Rage", "behavior": "innate", "key": "", "max_level": 1, "mana": [0],
		"cooldown": [0], "cast_point": 0.0, "range": 0,
		"values": {"max_rage": [100], "per_health_pct": [1], "per_hero_hit": [5], "decay": [10], "idle_time": [4],
		"attack_speed_per_10": [5]},
		"desc": "Burak fills with Rage (up to 100): 1 for every 1% of his health he loses and 5 for every attack he lands on a hero. After 4 seconds without hitting or being hit by a hero he loses 10 a second. Every 10 Rage gives him 5 attack speed (50 when full)."}
	_abilities["axe_throw"] = {"id": "axe_throw", "name": "Axe Throw", "behavior": "point", "key": "Q", "max_level": 4,
		"mana": [70, 75, 80, 85], "cooldown": [14, 13, 12, 11], "cast_point": 0.3, "range": 1000,
		"anim": "javelin_throw", "damage_type": "physical", "line": true, "direction": true, "full_width": true,
		"values": {"damage": [80, 140, 200, 260], "slow": [0.3, 0.3, 0.3, 0.3], "slow_duration": [2, 2, 2, 2],
		"distance": [1000, 1000, 1000, 1000], "speed": [1500, 1500, 1500, 1500], "width": [100, 100, 100, 100],
		"recast_window": [4, 4, 4, 4], "leap_time": [0.35, 0.35, 0.35, 0.35], "axe_out_cut": [0.2, 0.2, 0.2, 0.2],
		"hero_rage": [15, 15, 15, 15], "fork": [20, 20, 20, 20]},
		"hidden_values": ["leap_time", "fork"],
		"desc": "Burak throws an axe up to 1000. The first enemy hit takes physical damage and is slowed by 30% for 2 seconds; the axe sticks in it, or in the first tree or cliff, or drops at the end. For 4 seconds he can cast it again for free to leap to the axe, landing beside it and attacking at once. Walking over a dropped axe picks it up and halves the cooldown left. While the axe is gone he deals 20% less attack damage. A hero hit gives 15 Rage. Upgrade Staff: both axes fly in a fork; he can leap to either."}
	_abilities["reckless_swing"] = {"id": "reckless_swing", "name": "Reckless Swing", "behavior": "no_target",
		"key": "W", "max_level": 4, "mana": [60, 60, 60, 60], "cooldown": [16, 15, 14, 13], "cast_point": 0.15,
		"range": 0, "anim": "axe_battle_cry",
		"values": {"duration": [8, 8, 8, 8], "cleave": [0.5, 0.6, 0.7, 0.8], "lifesteal": [0.15, 0.20, 0.25, 0.30],
		"damage_taken": [0.15, 0.15, 0.15, 0.15], "cleave_start": [150, 150, 150, 150], "cleave_end": [360, 360, 360, 360],
		"cleave_distance": [650, 650, 650, 650]}, "hidden_values": ["cleave_start", "cleave_end", "cleave_distance"],
		"desc": "For 8 seconds Burak's attacks cleave 50 / 60 / 70 / 80% of their damage to the enemies behind his target and heal him for 15 / 20 / 25 / 30% of the damage, but he takes 15% more damage."}
	_abilities["unstoppable"] = {"id": "unstoppable", "name": "Unstoppable", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [12, 11, 10, 9], "cast_point": 0.0, "range": 0,
		"values": {"rage_cost": [40, 40, 40, 40], "cut": [0.40, 0.50, 0.60, 0.70]},
		"desc": "When a stun, root or hex lands on Burak while he has 40 Rage or more, he spends 40 Rage and it lasts 40 / 50 / 60 / 70% shorter. Break stops it."}
	_abilities["berserk"] = {"id": "berserk", "name": "Berserk", "behavior": "no_target", "key": "R", "max_level": 3,
		"required_level": [6, 12, 18], "mana": [100, 125, 150], "cooldown": [70, 60, 50], "cast_point": 0.2,
		"range": 0, "anim": "axe_battle_cry",
		"values": {"duration": [12, 12, 12], "damage": [40, 60, 80], "move_pct": [0.10, 0.10, 0.10],
		"held": [0.5, 0.5, 0.5], "return_time": [6, 6, 6]},
		"desc": "For 12 seconds Burak's Rage stays full, he deals 40 / 60 / 80 more attack damage, moves 10% faster and slows do nothing to him. Half of the damage he takes is held back and comes back as pure damage over 6 seconds after Berserk ends. Every enemy hero he kills or helps kill during Berserk clears the held damage."}
	# Ser Emelrich, the Heavy Sword: slow, readable, crushing
	_abilities["overhead_cut"] = {"id": "overhead_cut", "name": "Overhead Cut", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [90, 100, 110, 120], "cooldown": [13, 12, 11, 10], "cast_point": 0.3, "range": 450,
		"anim": "greatsword_slam", "damage_type": "physical", "line": true, "direction": true, "full_width": true,
		"values": {"windup": [0.6, 0.6, 0.6, 0.6], "distance": [450, 450, 450, 450], "width": [160, 160, 160, 160],
		"damage": [100, 160, 220, 280], "attack_pct": [0.6, 0.6, 0.6, 0.6], "stun": [0.8, 1.0, 1.2, 1.4]},
		"desc": "Ser Emelrich raises his sword (this part can still be called off), then winds up for 0.6 seconds with a red line on the ground for everyone to see; from then on only a stun, hex or silence stops the swing. The cut, 450 long and 160 wide, deals physical damage plus 60% of his attack damage and stuns. Trees on the line fall."}
	_abilities["sweep"] = {"id": "sweep", "name": "Sweep", "behavior": "no_target", "key": "W", "max_level": 4,
		"mana": [80, 85, 90, 95], "cooldown": [11, 11, 11, 11], "cast_point": 0.3, "range": 0,
		"anim": "greatsword_slash_2", "damage_type": "physical",
		"values": {"radius": [300, 300, 300, 300], "damage": [40, 70, 100, 130], "shove": [200, 200, 200, 200],
		"impact_damage": [40, 60, 80, 100], "impact_stun": [0.5, 0.5, 0.5, 0.5]},
		"desc": "A wide swing through the half circle in front of him (300): his attack damage plus 40 / 70 / 100 / 130 as physical damage. Enemies hit are shoved 200 to his left, so they pile up; one shoved into a tree, cliff, building or unit takes 40 / 60 / 80 / 100 more and is stunned for 0.5 seconds."}
	_abilities["steel_stance"] = {"id": "steel_stance", "name": "Steel Stance", "behavior": "toggle", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [1, 1, 1, 1], "cast_point": 0.0, "range": 0,
		"values": {"armor": [4, 6, 8, 10], "block": [0.25, 0.35, 0.45, 0.55], "front": [120, 120, 120, 120],
		"move_cut": [0.2, 0.2, 0.2, 0.2], "turn_cut": [0.5, 0.5, 0.5, 0.5]},
		"desc": "Toggle (1 second between toggles). While on, Ser Emelrich moves 20% slower and turns half as fast, but has 4 / 6 / 8 / 10 more armor and takes 25 / 35 / 45 / 55% less damage from attacks and line shots that come from his front 120 degrees. Other slows do nothing to him. How he faces matters."}
	_abilities["giant_swing"] = {"id": "giant_swing", "name": "Giant Swing", "behavior": "point", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 200, 250], "cooldown": [20, 15, 10],
		"cast_point": 0.3, "range": 700, "anim": "greatsword_power", "damage_type": "physical", "direction": true,
		"values": {"windup": [1.2, 1.2, 1.2], "distance": [700, 700, 700], "angle": [100, 100, 100],
		"damage": [150, 250, 350], "armor_ignore": [0.65, 0.65, 0.65], "stun": [1.2, 1.5, 1.8],
		"back_delay": [0.5, 0.5, 0.5], "back_distance": [500, 500, 500], "back_angle": [70, 70, 70]},
		"hidden_values": ["back_delay", "back_distance", "back_angle"],
		"desc": "Ser Emelrich winds up for 1.2 seconds (a red cone for everyone to see), then cuts through a cone 700 long and 100 degrees wide: physical damage that ignores 65% of armor, and every enemy hit is knocked down (stunned). Every tree in the cone falls. A stun, hex or silence breaks the wind-up; with Steel Stance on only a hex or silence does. Upgrade Staff: 0.5 seconds later he swings back the other way (a smaller cone, half damage)."}
	# Feran Mock, the Jester: chaos he can steer
	_abilities["knife_juggle"] = {"id": "knife_juggle", "name": "Knife Juggle", "behavior": "point", "key": "Q",
		"max_level": 4, "mana": [80, 90, 100, 110], "cooldown": [9, 9, 9, 9], "cast_point": 0.3, "range": 700,
		"anim": "javelin_throw", "damage_type": "magical", "line": true, "direction": true, "full_width": true,
		"values": {"knives": [4, 5, 6, 7], "damage": [45, 60, 75, 90], "interval": [0.1, 0.1, 0.1, 0.1],
		"spread": [25, 25, 25, 25], "distance": [800, 800, 800, 800], "speed": [1200, 1200, 1200, 1200],
		"width": [60, 60, 60, 60], "max_hits": [5, 5, 5, 5]}, "hidden_values": ["interval"],
		"desc": "Feran throws 4 / 5 / 6 / 7 knives 0.1 seconds apart, each at a random angle within 25 degrees of his aim, 800 far. Each knife deals magic damage to the first enemy it hits; one enemy is hit by at most 5 knives a cast."}
	_abilities["joke_box"] = {"id": "joke_box", "name": "Joke Box", "behavior": "point", "key": "W", "max_level": 4,
		"mana": [100, 110, 120, 130], "cooldown": [14, 13, 12, 11], "cast_point": 0.3, "range": 600,
		"anim": "hook_throw", "damage_type": "magical", "aoe": true,
		"values": {"radius": [275, 275, 275, 275], "fuse": [0.8, 0.8, 0.8, 0.8], "damage": [60, 100, 140, 180],
		"pie_miss": [0.5, 0.5, 0.5, 0.5], "pie_duration": [3, 3, 3, 3], "spring": [350, 350, 350, 350],
		"spring_stun": [0.6, 0.6, 0.6, 0.6], "silence": [1.5, 2.0, 2.5, 3.0], "root": [1.0, 1.3, 1.6, 1.9],
		"pranks": [1, 1, 1, 1], "throw_time": [0.35, 0.35, 0.35, 0.35]}, "hidden_values": ["throw_time", "pranks"],
		"desc": "Feran throws a box that lands and pops after a 0.8 second fuse: enemies within 275 take magic damage and each rolls its own prank. Pie: its attacks miss half the time for 3 seconds. Spring: thrown 350 in a random direction (a crash into a tree, cliff or unit stuns for 0.6 seconds). Confetti: silenced. Glue: rooted."}
	_abilities["swap"] = {"id": "swap", "name": "Swap", "behavior": "unit", "key": "E", "target_team": "any",
		"max_level": 4, "mana": [180, 180, 180, 180], "cooldown": [30, 28, 26, 24], "cast_point": 0.3,
		"range": [700, 800, 900, 1000], "anim": "spell_quick",
		"values": {"slow": [0.4, 0.4, 0.4, 0.4], "slow_duration": [1.5, 1.5, 1.5, 1.5], "mark_time": [6, 6, 6, 6]},
		"hidden_values": ["mark_time"],
		"desc": "Feran and any hero, ally or enemy, trade places at once; projectiles aimed at either of them miss. A swapped enemy is turned to face away and slowed by 40% for 1.5 seconds. Upgrade Staff: cast it on an allied hero to mark it, then on an enemy hero: those two trade places and Feran stays put."}
	_abilities["shuffle"] = {"id": "shuffle", "name": "Shuffle", "behavior": "point", "key": "R", "max_level": 3,
		"required_level": [6, 12, 18], "mana": [250, 300, 450], "cooldown": [80, 70, 60], "cast_point": 0.5,
		"range": 700, "anim": "spell_big", "damage_type": "magical", "aoe": true,
		"values": {"radius": [450, 550, 650], "stun": [0.8, 1.0, 1.2], "dizzy": [3, 3, 3], "dizzy_slow": [0.25, 0.25, 0.25],
		"dizzy_turn": [0.5, 0.5, 0.5], "juggles": [6, 6, 6]},
		"desc": "Every enemy hero and creep in the area trades places with another random enemy there, is stunned, then is dizzy for 3 seconds (turns half as fast and moves 25% slower). Then knives fly out of the middle in every direction: 6 Knife Juggles at its level, each hitting one enemy at most 5 times. With one enemy inside, it trades places with Feran instead."}
	# Ghorman, the Beast King: he leads a pack
	_abilities["tame"] = {"id": "tame", "name": "Tame", "behavior": "unit", "key": "Q", "target_team": "enemy",
		"max_level": 4, "mana": [70, 70, 70, 70], "cooldown": [30, 26, 22, 18], "cast_point": 0.3, "range": 600,
		"anim": "spell_quick",
		"values": {"bonus": [0.2, 0.3, 0.4, 0.5], "max_beasts": [1, 2, 3, 5]},
		"desc": "A neutral creep (not from the ancient camp) or an enemy lane creep becomes Ghorman's beast for good, with 20 / 30 / 40 / 50% more health and attack damage, and keeps its own ability. He can lead 1 / 2 / 3 / 5 at once; taming past that releases the oldest (it dies). Upgrade Staff: ancient creeps too, one of them at a time."}
	_abilities["roar"] = {"id": "roar", "name": "Roar", "behavior": "no_target", "key": "W", "max_level": 4,
		"mana": [90, 100, 110, 120], "cooldown": [15, 15, 15, 15], "cast_point": 0.3, "range": 0,
		"anim": "axe_battle_cry",
		"values": {"radius": [500, 500, 500, 500], "slow": [0.35, 0.40, 0.45, 0.50], "attack_cut": [0.15, 0.20, 0.25, 0.30],
		"duration": [6, 6, 6, 6], "beast_reach": [900, 900, 900, 900], "beast_attack_speed": [30, 30, 30, 30],
		"beast_attack_pct": [0.02, 0.02, 0.02, 0.02], "beast_move_pct": [0.2, 0.2, 0.2, 0.2]},
		"desc": "Enemies within 500 are slowed by 35 / 40 / 45 / 50% and deal 15 / 20 / 25 / 30% less attack damage for 6 seconds. His beasts within 900 attack 30 faster (and 2% more for each beast he leads) and move 20% faster for 6 seconds."}
	_abilities["pack_leader"] = {"id": "pack_leader", "name": "Pack Leader", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"values": {"reach": [900, 900, 900, 900], "damage": [3, 4, 5, 6], "armor": [1.0, 1.5, 2.0, 2.5],
		"heal": [0.08, 0.10, 0.12, 0.14]},
		"desc": "Each of his beasts within 900 gives Ghorman 3 / 4 / 5 / 6 attack damage and 1 / 1.5 / 2 / 2.5 armor. When one of his beasts dies, he heals 8 / 10 / 12 / 14% of his health."}
	_abilities["blessing_of_the_beast_king"] = {"id": "blessing_of_the_beast_king", "name": "Blessing of the Beast King",
		"behavior": "unit", "key": "D", "target_team": "ally", "max_level": 4, "mana": [150, 150, 150, 150],
		"cooldown": [10, 10, 10, 10], "cast_point": 0.2, "range": 600, "anim": "spell_quick",
		"values": {"heal": [0.3, 0.4, 0.5, 0.6], "duration": [8, 8, 8, 8], "damage_pct": [0.2, 0.3, 0.4, 0.5],
		"attack_speed": [20, 30, 40, 50]},
		"desc": "Ghorman blesses one of his beasts: it heals 30 / 40 / 50 / 60% of its health, is cleansed of slows, silences and roots, its ability is ready again, and for 8 seconds it deals 20 / 30 / 40 / 50% more attack damage and attacks 20 / 30 / 40 / 50 faster."}
	_abilities["beast_form"] = {"id": "beast_form", "name": "Beast Form", "behavior": "no_target", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 225, 300], "cooldown": [80, 70, 60],
		"cast_point": 0.4, "range": 0, "anim": "axe_chest_thump",
		"values": {"duration": [25, 25, 25], "hp": [300, 600, 900], "damage": [40, 60, 80], "move_speed": [40, 40, 40],
		"maul_every": [3, 3, 3], "maul": [100, 150, 200], "bash": [0.6, 0.6, 0.6], "beast_hp": [0.25, 0.25, 0.25],
		"beast_cooldown_rate": [0.25, 0.25, 0.25]},
		"desc": "Ghorman becomes a huge beast for 25 seconds: 300 / 600 / 900 more health, 40 / 60 / 80 more attack damage and 40 more speed; every 3rd attack is a maul for 100 / 150 / 200 more physical damage and a 0.6 second bash. His beasts grow too: 25% more health, and their abilities come back 25% faster."}

static func _talent(id: String, name: String, mods: Array, stats := {}) -> void:
	_talents[id] = {"id": id, "name": name, "mods": mods, "stats": stats}

static func _build_talents() -> void:
	# Sludge (Pudge's tree in 7.41d): level 10, 15, 20, 25; left and right.
	_talent("sludge_stench_slow", "+10% Stench slow", [{"ability": "stench", "add": {"slow": 0.10}}])
	_talent("sludge_armor", "+5 Armor", [], {"armor": 5.0})
	_talent("sludge_hook_damage", "+150 Shuriken Hook damage", [{"ability": "shuriken_hook", "add": {"damage": 150.0}}])
	_talent("sludge_spell_lifesteal", "8% Spell Lifesteal", [], {"spell_lifesteal": 0.08})
	_talent("sludge_hook_cooldown", "-4s Shuriken Hook cooldown", [{"ability": "shuriken_hook", "add": {"cooldown": -4.0}}])
	_talent("sludge_chomp_time", "+0.75s Chomp", [{"ability": "chomp", "add": {"duration": 0.75, "ticks": 2.0}}])
	_talent("sludge_gut_blubber", "1.5x Growing Gut and Blubber", [{"ability": "growing_gut", "mult": {"str_per_stack": 1.5}},
		{"ability": "blubber", "mult": {"block": 1.5}}])
	_talent("sludge_chomp_power", "1.5x Chomp damage and heal", [{"ability": "chomp", "mult": {"damage_mult": 1.5}}])
	# Azrin (chosen; the owner may change them)
	_talent("azrin_javelin_burn", "+30 Fiery Javelin burn", [{"ability": "fiery_javelin", "add": {"burn_dps": 30.0}}])
	_talent("azrin_damage", "+25 Attack Damage", [], {"damage": 25.0})
	_talent("azrin_magic_amp", "+6% Magic Amp", [], {"magic_amp": 0.06})
	_talent("azrin_ember_cooldown", "-2s Touch of Ember cooldown", [{"ability": "touch_of_ember", "add": {"cooldown": -2.0}}])
	_talent("azrin_spirits", "+2 Spirits of Fire", [{"ability": "spirit_of_fire", "add": {"max_spirits": 2.0}}])
	_talent("azrin_smite_damage", "+200 Divine Smite damage", [{"ability": "divine_smite", "add": {"damage": 200.0}}])
	_talent("azrin_ember_stun", "+0.8s Touch of Ember stun", [{"ability": "touch_of_ember", "add": {"stun": 0.8}}])
	_talent("azrin_smite_cooldown", "-15s Divine Smite cooldown", [{"ability": "divine_smite", "add": {"cooldown": -15.0}}])
	# Froster (chosen)
	_talent("froster_breath_damage", "+80 Breath of Cold damage", [{"ability": "breath_of_cold", "add": {"damage": 80.0}}])
	_talent("froster_mana_regen", "+1.5 Mana Regen", [], {"mana_regen": 1.5})
	_talent("froster_pulse_cooldown", "-3s Ice Pulse cooldown", [{"ability": "ice_pulse", "add": {"cooldown": -3.0}}])
	_talent("froster_heart_burst", "+100 Frost Heart damage", [{"ability": "frost_heart", "add": {"burst": 100.0}}])
	_talent("froster_breath_slow", "+15% Breath of Cold slow", [{"ability": "breath_of_cold", "add": {"slow": 0.15}}])
	_talent("froster_magic_amp", "+8% Magic Amp", [], {"magic_amp": 0.08})
	_talent("froster_winter_damage", "+100 Endless Winter damage", [{"ability": "endless_winter", "add": {"dps": 100.0}}])
	_talent("froster_pulse_loss", "+15% Ice Pulse defense loss", [{"ability": "ice_pulse", "add": {"defense_loss": 0.15}}])
	# Caziel (chosen)
	_talent("caziel_attack_speed", "+25 Attack Speed", [], {"attack_speed": 25.0})
	_talent("caziel_dagger_damage", "+60 Swift Dagger damage", [{"ability": "swift_dagger", "add": {"bonus_damage": 60.0}}])
	_talent("caziel_poison_chance", "+6% Sweet Poison chance", [{"ability": "sweet_poison", "add": {"chance": 0.06}}])
	_talent("caziel_shadows_cooldown", "-4s Master of Shadows cooldown", [{"ability": "master_of_shadows", "add": {"cooldown": -4.0}}])
	_talent("caziel_poison_damage", "+30 Sweet Poison damage", [{"ability": "sweet_poison", "add": {"dps": 30.0}}])
	_talent("caziel_dagger_armor", "+3 Swift Dagger armor cut", [{"ability": "swift_dagger", "add": {"armor_cut": 3.0}}])
	_talent("caziel_order_threshold", "+4% Death Order threshold", [{"ability": "death_order", "add": {"threshold": 0.04}}])
	_talent("caziel_shadows_evasion", "+15% Master of Shadows evasion", [{"ability": "master_of_shadows", "add": {"evasion": 0.15}}])
	# Roydo (chosen)
	_talent("roydo_grip_damage", "+80 Grip of the Ruler damage", [{"ability": "grip_of_the_ruler", "add": {"damage": 80.0}}])
	_talent("roydo_health", "+250 Health", [], {"hp": 250.0})
	_talent("roydo_rush_cooldown", "-3s Void Rush cooldown", [{"ability": "void_rush", "add": {"cooldown": -3.0}}])
	_talent("roydo_skin_chance", "+6% Dark Matter Skin chance", [{"ability": "dark_matter_skin", "add": {"chance": 0.06}}])
	_talent("roydo_grip_stun", "+0.6s Grip of the Ruler stun", [{"ability": "grip_of_the_ruler", "add": {"stun": 0.6}}])
	_talent("roydo_rush_cut", "+10% Void Rush damage cut", [{"ability": "void_rush", "add": {"damage_cut": 0.10}}])
	_talent("roydo_anomaly_bat", "-0.15s Anomaly attack time", [{"ability": "anomaly", "add": {"bat_cut": 0.15}}])
	_talent("roydo_skin_reflect", "+12% Dark Matter Skin reflect", [{"ability": "dark_matter_skin", "add": {"reflect": 0.12}}])
	# Blau (chosen)
	_talent("blau_shot_damage", "+50 Bounce Shot damage", [{"ability": "bounce_shot", "add": {"damage": 50.0}}])
	_talent("blau_attack_speed", "+25 Attack Speed", [], {"attack_speed": 25.0})
	_talent("blau_boulders", "+2 Boulders", [{"ability": "summon_boulders", "add": {"count": 2.0}}])
	_talent("blau_trap_root", "+0.8s Lay Trap root", [{"ability": "lay_trap", "add": {"root": 0.8}}])
	_talent("blau_bounces", "+4 Bounce Shot bounces", [{"ability": "bounce_shot", "add": {"bounces": 4.0}}])
	_talent("blau_turret_damage", "+10% Turret damage", [{"ability": "place_turret", "add": {"damage_pct": 0.10}}])
	_talent("blau_shot_hits", "+1 Bounce Shot hit per enemy", [{"ability": "bounce_shot", "add": {"max_hits": 1.0}}])
	_talent("blau_turret_health", "+700 Turret health", [{"ability": "place_turret", "add": {"hp": 700.0}}])
	# Blood Ranger and Ezee (added 2026-10-17; chosen beside Dota's agility archers and strength initiators)
	_talent("ranger_archery_chance", "+10% Masterful Archery chance", [{"ability": "masterful_archery", "add": {"chance": 0.10}}])
	_talent("ranger_attack_speed", "+20 Attack Speed", [], {"attack_speed": 20.0})
	_talent("ranger_gale_damage", "+100 Gale Impact damage", [{"ability": "gale_impact", "add": {"damage": 100.0}}])
	_talent("ranger_burst_damage", "+15% Burst Shot damage", [{"ability": "burst_shot", "add": {"attack_pct": 0.15}}])
	_talent("ranger_ult_range", "+150 Blood Ranger attack range", [{"ability": "blood_ranger_ult", "add": {"bonus_range": 150.0}}])
	_talent("ranger_gale_cooldown", "-4s Gale Impact cooldown", [{"ability": "gale_impact", "add": {"cooldown": -4.0}}])
	_talent("ranger_ult_lifesteal", "+20% Blood Ranger lifesteal", [{"ability": "blood_ranger_ult", "add": {"lifesteal": 0.20}}])
	_talent("ranger_archery_damage", "+25% Masterful Archery damage", [{"ability": "masterful_archery", "add": {"agility_pct": 0.25}}])
	_talent("ezee_strength", "+10 Strength", [], {"str": 10.0})
	_talent("ezee_stomp_damage", "+60 Dark Stomp damage", [{"ability": "dark_stomp", "add": {"damage": 60.0}}])
	_talent("ezee_stomp_stun", "+0.6s Dark Stomp stun", [{"ability": "dark_stomp", "add": {"impact_stun": 0.6}}])
	_talent("ezee_touch_damage", "+50 Tainted Touch damage", [{"ability": "tainted_touch", "add": {"bonus_damage": 50.0}}])
	_talent("ezee_leap_cooldown", "-4s Leap Strike cooldown", [{"ability": "leap_strike", "add": {"cooldown": -4.0}}])
	_talent("ezee_leap_strength", "+40% Leap Strike strength damage", [{"ability": "leap_strike", "add": {"str_mult": 0.40}}])
	_talent("ezee_might_chance", "+10% Unholy Might chance", [{"ability": "unholy_might", "add": {"chance": 0.10}}])
	_talent("ezee_might_duration", "+4s Unholy Might", [{"ability": "unholy_might", "add": {"duration": 4.0}}])
	# Azrael (chosen, 2026-10-17)
	_talent("azrael_attack_speed", "+25 Attack Speed", [], {"attack_speed": 25.0})
	_talent("azrael_soul_damage", "+6 Soul Tap damage per unit", [{"ability": "soul_tap", "add": {"per_unit": 6.0}}])
	_talent("azrael_health", "+250 Health", [], {"hp": 250.0})
	_talent("azrael_door_time", "+1s Door of the End", [{"ability": "door_of_the_end", "add": {"duration": 1.0}}])
	_talent("azrael_scythe_chance", "+8% Death Scythe chance", [{"ability": "death_scythe", "add": {"chance": 0.08}}])
	_talent("azrael_scythe_damage", "+40 Death Scythe damage", [{"ability": "death_scythe", "add": {"bonus": 40.0}}])
	_talent("azrael_door_damage", "+150 Door of the End damage", [{"ability": "door_of_the_end", "add": {"damage": 150.0}}])
	_talent("azrael_darkness_cooldown", "-20s Divine Darkness cooldown", [{"ability": "divine_darkness", "add": {"cooldown": -20.0}}])
	# Tock (chosen)
	_talent("tock_bolt_damage", "+70 Time Bolt damage", [{"ability": "time_bolt", "add": {"damage": 70.0}}])
	_talent("tock_mana_regen", "+2 Mana Regen", [], {"mana_regen": 2.0})
	_talent("tock_field_slow", "+15% Slow Field slow", [{"ability": "slow_field", "add": {"slow": 0.15}}])
	_talent("tock_forward_rate", "+1.5s Fast Forward cooldown cut", [{"ability": "fast_forward", "add": {"cut": 1.5}}])
	_talent("tock_rewind_cooldown", "-6s Rewind cooldown", [{"ability": "rewind", "add": {"cooldown": -6.0}}])
	_talent("tock_hands", "+1s Quick Hands", [{"ability": "quick_hands", "add": {"cut": 1.0}}])
	_talent("tock_stop_duration", "+1s Stop Time", [{"ability": "stop_time", "add": {"duration": 1.0}}])
	_talent("tock_bolt_delay", "+30% Time Bolt delay", [{"ability": "time_bolt", "add": {"delay": 0.3}}])
	# Kragg (chosen)
	_talent("kragg_grip_damage", "+80 Iron Grip damage", [{"ability": "iron_grip", "add": {"damage": 80.0}}])
	_talent("kragg_armor", "+6 Armor", [], {"armor": 6.0})
	_talent("kragg_repel_cooldown", "-3s Repel cooldown", [{"ability": "repel", "add": {"cooldown": -3.0}}])
	_talent("kragg_charge_max", "+2 max Charges", [{"ability": "magnetize", "add": {"max_charges": 2.0}}])
	_talent("kragg_overload_damage", "+40 Overload damage", [{"ability": "overload", "add": {"damage": 40.0}}])
	_talent("kragg_field_pull", "+40 Magnet Field pull", [{"ability": "magnet_field", "add": {"pull": 40.0}}])
	_talent("kragg_field_stun", "+1s Magnet Field stun", [{"ability": "magnet_field", "add": {"end_stun": 1.0}}])
	_talent("kragg_grip_charges", "+2 Iron Grip Charges", [{"ability": "iron_grip", "add": {"charges": 2.0}}])

## The five heroes of hero_ideas.txt (run 2026-10-18 f): the file's talents; Airah's are chosen (her section has none).
static func _build_talents_18() -> void:
	_talent("airah_gust_damage", "+60 Gust damage", [{"ability": "gust", "add": {"damage": 60.0}}])
	_talent("airah_mana_regen", "+1.5 Mana Regen", [], {"mana_regen": 1.5})
	_talent("airah_tailwind_miss", "+10% Tailwind miss chance", [{"ability": "tailwind", "add": {"ranged_miss": 0.10}}])
	_talent("airah_wall_time", "+1s Wind Wall", [{"ability": "wind_wall", "add": {"duration": 1.0}}])
	_talent("airah_gust_cooldown", "-3s Gust cooldown", [{"ability": "gust", "add": {"cooldown": -3.0}}])
	_talent("airah_magic_amp", "+8% Magic Amp", [], {"magic_amp": 0.08})
	_talent("airah_hurricane_damage", "+40 Hurricane damage per second", [{"ability": "hurricane", "add": {"dps": 40.0}}])
	_talent("airah_hurricane_radius", "+150 Hurricane radius", [{"ability": "hurricane", "add": {"radius": 150.0}}])
	_talent("burak_damage", "+15 Attack Damage", [], {"damage": 15.0})
	_talent("burak_axe_damage", "+150 Axe Throw damage", [{"ability": "axe_throw", "add": {"damage": 150.0}}])
	_talent("burak_rage_decay", "Rage drains 50% slower", [{"ability": "rage", "mult": {"decay": 0.5}}])
	_talent("burak_swing_lifesteal", "+10% Reckless Swing lifesteal", [{"ability": "reckless_swing", "add": {"lifesteal": 0.10}}])
	_talent("burak_unstoppable_rage", "-20 Rage for Unstoppable", [{"ability": "unstoppable", "add": {"rage_cost": -20.0}}])
	_talent("burak_axe_window", "+6s Axe Throw leap window", [{"ability": "axe_throw", "add": {"recast_window": 6.0}}])
	_talent("burak_berserk_time", "+4s Berserk", [{"ability": "berserk", "add": {"duration": 4.0}}])
	_talent("burak_berserk_return", "Berserk's held damage returns over 10s", [{"ability": "berserk", "add": {"return_time": 4.0}}])
	_talent("emelrich_health", "+250 Health", [], {"hp": 250.0})
	_talent("emelrich_cut_stun", "+1s Overhead Cut stun", [{"ability": "overhead_cut", "add": {"stun": 1.0}}])
	_talent("emelrich_sweep_damage", "+60 Sweep damage", [{"ability": "sweep", "add": {"damage": 60.0}}])
	_talent("emelrich_sweep_shove", "Sweep shoves 350", [{"ability": "sweep", "add": {"shove": 150.0}}])
	_talent("emelrich_stance_sides", "Steel Stance blocks from the sides", [{"ability": "steel_stance", "add": {"front": 60.0}}])
	_talent("emelrich_cut_windup", "-0.3s Overhead Cut wind-up", [{"ability": "overhead_cut", "add": {"windup": -0.3}}])
	_talent("emelrich_swing_armor", "Giant Swing ignores all armor", [{"ability": "giant_swing", "add": {"armor_ignore": 0.35}}])
	_talent("emelrich_swing_cooldown", "-20s Giant Swing cooldown", [{"ability": "giant_swing", "add": {"cooldown": -20.0}}])
	_talent("feran_knives", "+1 Knife Juggle knife", [{"ability": "knife_juggle", "add": {"knives": 1.0}}])
	_talent("feran_magic_amp", "+8% Magic Amp", [], {"magic_amp": 0.08})
	_talent("feran_two_pranks", "Joke Box plays two pranks", [{"ability": "joke_box", "add": {"pranks": 1.0}}])
	_talent("feran_swap_cooldown", "-3s Swap cooldown", [{"ability": "swap", "add": {"cooldown": -3.0}}])
	_talent("feran_swap_range", "+200 Swap range", [{"ability": "swap", "add": {"range": 200.0}}])
	_talent("feran_box_damage", "+60 Joke Box damage", [{"ability": "joke_box", "add": {"damage": 60.0}}])
	_talent("feran_shuffle_stun", "+1s Shuffle stun", [{"ability": "shuffle", "add": {"stun": 1.0}}])
	_talent("feran_shuffle_radius", "+150 Shuffle radius", [{"ability": "shuffle", "add": {"radius": 150.0}}])
	_talent("ghorman_beasts", "+1 beast", [{"ability": "tame", "add": {"max_beasts": 1.0}}])
	_talent("ghorman_roar_speed", "+20 Roar attack speed", [{"ability": "roar", "add": {"beast_attack_speed": 20.0}}])
	_talent("ghorman_tame_power", "+15% tamed health and damage", [{"ability": "tame", "add": {"bonus": 0.15}}])
	_talent("ghorman_tame_cooldown", "-6s Tame cooldown", [{"ability": "tame", "add": {"cooldown": -6.0}}])
	_talent("ghorman_pack_armor", "+2 Pack Leader armor per beast", [{"ability": "pack_leader", "add": {"armor": 2.0}}])
	_talent("ghorman_roar_radius", "+200 Roar radius", [{"ability": "roar", "add": {"radius": 200.0}}])
	_talent("ghorman_form_time", "+10s Beast Form", [{"ability": "beast_form", "add": {"duration": 10.0}}])
	_talent("ghorman_maul_every", "Maul every 2nd attack", [{"ability": "beast_form", "add": {"maul_every": -1.0}}])

# ---- Items ----------------------------------------------------------------------------------------------------------
## Item data from items.txt. "stats": passive bonuses; "use": active effect; "recipe": components (recipe scroll cost
## is the item cost minus the components).

static func _it(id: String, name: String, cost: int, d: Dictionary) -> void:
	var it := {"id": id, "name": name, "cost": cost, "stats": {}, "use": "", "charges": 0, "stock": 0, "cooldown": 0.0,
		"components": [], "recipe_cost": 0, "category": "basics", "consumable": false, "values": {}, "icon": id}
	it.merge(d, true)
	_items[id] = it

static func _build_items() -> void:
	# the Teleport Scroll first, as in Dota's shop
	_it("tp_scroll", "Teleport Scroll", 100, {"use": "tp", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"channel": SimConst.TP_CHANNEL}})
	# Flask (Dota's Bottle, 7.41d): 3 charges of 110 health and 60 mana over 2.7 s (lost to hero damage), refilled
	# at the fountain; it stores an orb taken while it is carried
	_it("bottle", "Flask", 675, {"use": "bottle", "charges": 3, "cooldown": 0.5, "category": "consumables",
		"values": {"health": 110.0, "mana": 60.0, "time": 2.7, "max_charges": 3, "orb_expire": 90.0}})
	_it("tango", "Vegan Picker", 90, {"use": "tango", "charges": 3, "consumable": true, "category": "consumables",
		"values": {"health_regen": 7.0, "duration": 16.0, "planted_duration": 32.0, "range": 165.0}})
	_it("salve", "Healing Paste", 100, {"use": "salve", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"health_regen": 30.0, "duration": 13.0}})
	_it("clarity", "Mana Potion", 60, {"use": "clarity", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"mana_regen": 6.0, "duration": 25.0}})
	_it("mango", "Ripe Mango", 65, {"use": "mango", "charges": 1, "consumable": true, "category": "consumables",
		"stats": {"hp_regen": 0.4}, "values": {"mana": 100.0}})
	_it("faerie_fire", "Firefly Jar", 65, {"use": "faerie_fire", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 5.0, "stats": {"damage": 2.0}, "values": {"heal": 85.0}})
	_it("observer_ward", "Eye Ward", 0, {"use": "ward", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 1.0, "values": {"lifetime": 360.0, "unit": "ward_observer"}})
	# Dota's Sentry Ward and Dust of Appearance: the answers to invisibility
	_it("reveal_ward", "Reveal Ward", 50, {"use": "ward", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 1.0, "values": {"lifetime": 420.0, "unit": "ward_sentry", "true_sight": 1050.0}})
	_it("reveal_dust", "Reveal Dust", 80, {"use": "dust", "element": "light", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 30.0, "values": {"radius": 1050.0, "duration": 12.0, "linger": 8.0, "slow": 0.2, "damage": 25.0}})
	_it("branch", "Tree Twig", 55, {"use": "plant", "stats": {"str": 1.0, "agi": 1.0, "int": 1.0}, "category": "attributes",
		"values": {"tree_duration": SimConst.PLANTED_TREE_DURATION, "range": SimConst.PLANT_RANGE}})
	_it("slippers", "Slippers", 140, {"stats": {"agi": 3.0}, "category": "attributes"})
	_it("gauntlets", "Heavy Gloves", 140, {"stats": {"str": 3.0}, "category": "attributes"})
	_it("mantle", "Thinking Cap", 140, {"stats": {"int": 3.0}, "category": "attributes"})
	_it("circlet", "Headband", 155, {"stats": {"str": 2.0, "agi": 2.0, "int": 2.0}, "category": "attributes"})
	_it("boots_elves", "Elf Band", 450, {"stats": {"agi": 6.0}, "category": "attributes"})
	_it("belt_str", "Heavy Belt", 450, {"stats": {"str": 6.0}, "category": "attributes"})
	_it("robe", "Wizard Robe", 450, {"stats": {"int": 6.0}, "category": "attributes"})
	_it("blade_alacrity", "Quick Blade", 1000, {"stats": {"agi": 10.0}, "category": "attributes"})
	_it("blades_attack", "Fist Blades", 450, {"stats": {"damage": 9.0}, "category": "armaments"})
	_it("broadsword", "Long Sword", 1000, {"stats": {"damage": 15.0}, "category": "armaments"})
	_it("gloves", "Fast Gloves", 450, {"stats": {"attack_speed": 20.0}, "category": "armaments"})
	_it("ring_protection", "Armor Ring", 175, {"stats": {"armor": 2.0}, "category": "armaments"})
	_it("chainmail", "Chain Shirt", 500, {"stats": {"armor": 4.0}, "category": "armaments"})
	_it("quelling_blade", "Mini-Axe", 100, {"use": "chop", "cooldown": 4.0, "category": "armaments",
		"values": {"creep_damage_melee": 8.0, "creep_damage_ranged": 4.0, "chop_range": 350.0}})
	_it("ring_regen", "Healing Ring", 175, {"stats": {"hp_regen": 1.25}, "category": "misc"})
	_it("sobi_mask", "Calm Mask", 175, {"stats": {"mana_regen": 0.7}, "category": "misc"})
	# boots: "boot_ms" does not stack (the fastest pair counts), as in Dota
	_it("boots", "Running Shoes", 500, {"stats": {"boot_ms": 45.0}, "category": "misc"})
	_it("magic_stick", "Zap Stick", 200, {"use": "stick", "cooldown": 17.0, "category": "misc",
		"values": {"max_charges": 10, "restore_per_charge": 15.0, "charge_radius": 1200.0}})
	_it("lifesteal", "Leech Mask", 900, {"stats": {"lifesteal": 0.18}, "category": "misc"})
	# More basic parts for the combination items (Dota 7.41d items.txt; names are ours)
	_it("giant_axe", "Giant Axe", 1000, {"stats": {"str": 10.0}, "category": "attributes"})
	_it("wizard_staff", "Wizard Staff", 1000, {"stats": {"int": 10.0}, "category": "attributes"})
	_it("greatsword", "Greatsword", 1350, {"stats": {"damage": 20.0}, "category": "armaments"})
	_it("steel_hammer", "Steel Hammer", 1600, {"stats": {"damage": 24.0}, "category": "armaments"})
	_it("spear", "Spear", 900, {"passive": "pierce", "category": "armaments",
		"values": {"chance": 0.25, "damage": 60.0}})
	_it("rust_stone", "Rust Stone", 300, {"passive": "corruption", "category": "armaments",
		"values": {"armor_reduction": 2.0, "duration": 3.0}})
	_it("brass_knuckles", "Brass Knuckles", 1000, {"stats": {"attack_speed": 35.0}, "category": "armaments"})
	_it("plate_vest", "Plate Vest", 950, {"stats": {"armor": 7.0}, "category": "armaments"})
	_it("big_healing_ring", "Big Healing Ring", 700, {"stats": {"hp_regen": 4.5}, "category": "misc"})
	_it("mana_stone", "Mana Stone", 700, {"stats": {"mana_regen": 1.75}, "category": "misc"})
	_it("health_crystal", "Health Crystal", 1000, {"stats": {"hp": 250.0}, "category": "misc"})
	_it("big_gem", "Big Gem", 1200, {"stats": {"hp": 175.0, "mana": 175.0}, "category": "misc"})
	_it("pointy_hat", "Pointy Hat", 250, {"stats": {"mana": 125.0}, "category": "misc"})
	_it("fur_hat", "Fur Hat", 250, {"stats": {"hp": 125.0}, "category": "misc"})
	_it("sneak_charm", "Sneak Charm", 900, {"category": "misc"})
	# magic defence (Dota 7.41d items.txt: Shawl, Cloak; our names, run 2026-10-15 g)
	_it("shawl", "Scarf", 450, {"stats": {"magic_resist": 0.10}, "category": "armaments"})
	_it("cloak", "Spell Cloak", 900, {"stats": {"magic_resist": 0.18}, "category": "armaments"})
	_it("jump_knife", "Jump Knife", 2250, {"use": "jump", "cooldown": 15.0, "category": "misc",
		"values": {"range": 1200.0, "clamp": 960.0, "hero_damage_lockout": 3.0}})
	# Upgrades
	_it("wraith_band", "Swift Band", 505, {"stats": {"agi": 5.0, "str": 2.0, "int": 2.0, "attack_speed": 6.0, "armor": 1.75},
		"components": ["circlet", "slippers"], "recipe_cost": 210, "category": "upgrades"})
	_it("tough_band", "Tough Band", 505, {"stats": {"str": 5.0, "agi": 2.0, "int": 2.0, "hp": 50.0, "hp_regen": 0.75},
		"components": ["circlet", "gauntlets"], "recipe_cost": 210, "category": "upgrades"})
	_it("smart_band", "Smart Band", 505, {"stats": {"int": 5.0, "str": 2.0, "agi": 2.0, "max_mana_pct": 0.03,
		"mana_regen": 1.0}, "components": ["circlet", "mantle"], "recipe_cost": 210, "category": "upgrades"})
	_it("magic_wand", "Zap Wand", 460, {"use": "stick", "cooldown": 15.0, "stats": {"str": 3.0, "agi": 3.0, "int": 3.0},
		"components": ["magic_stick", "branch", "branch"], "recipe_cost": 150, "category": "upgrades",
		"values": {"max_charges": 20, "restore_per_charge": 15.0, "charge_radius": 1200.0}})
	_it("mana_ring", "Mana Ring", 425, {"stats": {"mana_regen": 0.25}, "aura": "mana", "category": "upgrades",
		"components": ["sobi_mask"], "recipe_cost": 250, "values": {"aura_mana_regen": 1.0, "aura_radius": 1200.0}})
	_it("leaf_hat", "Leaf Hat", 425, {"stats": {"hp_regen": 0.5}, "aura": "regen", "category": "upgrades",
		"components": ["ring_regen"], "recipe_cost": 250, "values": {"aura_hp_regen": 2.0, "aura_radius": 1200.0}})
	_it("steady_ring", "Steady Ring", 1400, {"stats": {"hp_regen": 5.5, "mana_regen": 2.25},
		"components": ["big_healing_ring", "mana_stone"], "recipe_cost": 0, "category": "upgrades"})
	# Switch Boots: 25 attack speed, 55 (melee) / 45 (ranged) speed and +10 to the chosen attribute. Built with a
	# Heavy Belt it starts on strength, a Wizard Robe on intelligence, an Elf Band on agility; the active switches
	# strength -> intelligence -> agility.
	_it("power_treads", "Switch Boots", 1400, {"use": "switch", "stats": {"attack_speed": 25.0},
		"stats_melee": {"boot_ms": 55.0}, "stats_ranged": {"boot_ms": 45.0}, "values": {"attr_bonus": 10.0},
		"components": ["boots", "gloves", "belt_str"], "recipe_cost": 0, "category": "upgrades",
		"recipes": [["boots", "gloves", "belt_str"], ["boots", "gloves", "robe"], ["boots", "gloves", "boots_elves"]],
		"attr_from": {"belt_str": "str", "robe": "int", "boots_elves": "agi"}})
	_it("slip_boots", "Slip Boots", 1450, {"use": "slip", "cooldown": 8.0, "stats": {"boot_ms": 50.0, "armor": 4.0},
		"stats_melee": {"damage": 18.0}, "stats_ranged": {"damage": 12.0}, "category": "upgrades",
		"components": ["boots", "chainmail", "blades_attack"], "recipe_cost": 0,
		"values": {"move_speed_pct_melee": 0.2, "move_speed_pct_ranged": 0.1, "duration": 3.0}})
	_it("mana_boots", "Mana Boots", 1500, {"use": "restore", "cooldown": 55.0, "aura": "mana",
		"stats": {"boot_ms": 45.0, "mana_regen": 0.25, "mana": 125.0}, "category": "upgrades",
		"components": ["boots", "mana_ring", "pointy_hat"], "recipe_cost": 325,
		"values": {"amount": 150.0, "radius": 1200.0, "aura_mana_regen": 1.0, "aura_radius": 1200.0}})
	_it("medic_kit", "Medic Kit", 1775, {"use": "mend", "cooldown": 50.0, "mana": 100.0, "aura": "regen",
		"stats": {"armor": 5.0}, "category": "upgrades", "components": ["leaf_hat", "chainmail"], "recipe_cost": 850,
		"values": {"heal": 250.0, "radius": 1200.0, "aura_hp_regen": 2.5, "aura_radius": 1200.0}})
	_it("block_shield", "Block Shield", 1700, {"passive": "block", "stats": {"hp": 250.0, "hp_regen": 4.5},
		"components": ["health_crystal", "big_healing_ring"], "recipe_cost": 0, "category": "upgrades",
		"values": {"chance": 0.6, "block_melee": 50.0, "block_ranged": 25.0}})
	_it("spike_armor", "Spike Armor", 2400, {"use": "spikes", "cooldown": 25.0, "mana": 25.0, "passive": "spikes",
		"stats": {"damage": 15.0, "armor": 7.0}, "components": ["broadsword", "plate_vest"], "recipe_cost": 450,
		"category": "upgrades", "values": {"duration": 5.5, "active_pct": 0.85, "passive_flat": 10.0, "passive_pct": 0.15}})
	_it("gold_glove", "Gold Glove", 2200, {"use": "gold", "no_disassemble": true, "target_team": "enemy", "stats": {"attack_speed": 40.0}, "charges": 1,
		"category": "upgrades", "components": ["gloves"], "recipe_cost": 1750,
		"values": {"gold": 160.0, "range": 600.0, "max_charges": 2, "charge_time": 90.0}})
	_it("push_staff", "Push Staff", 2200, {"use": "push", "target_team": "any", "cooldown": 19.0, "mana": 150.0,
		"stats": {"int": 10.0, "hp": 175.0}, "components": ["wizard_staff", "fur_hat"], "recipe_cost": 950,
		"category": "upgrades", "values": {"distance": 600.0, "time": 0.5, "range_ally": 550.0, "range_enemy": 850.0}})
	_it("spell_shield", "Spell Shield", 4050, {"use": "shield", "cooldown": 95.0, "mana": 50.0,
		"stats": {"str": 10.0, "damage": 24.0}, "components": ["steel_hammer", "giant_axe"], "recipe_cost": 1450,
		"category": "upgrades", "values": {"durations": [9.0, 8.0, 7.0], "magic_resist": 0.6}})
	_it("armor_breaker", "Armor Breaker", 3500, {"passive": "corruption", "stats": {"damage": 55.0},
		"components": ["steel_hammer", "steel_hammer", "rust_stone"], "recipe_cost": 0, "category": "upgrades",
		"values": {"armor_reduction": 6.0, "duration": 7.0, "damage_per_kill": 2.0, "damage_per_assist": 1.0,
		"max_damage": 30.0}})
	_it("shock_hammer", "Shock Hammer", 2950, {"passive": "chain", "element": "lightning", "stats": {"damage": 25.0, "attack_speed": 25.0},
		"components": ["steel_hammer", "spear", "gloves"], "recipe_cost": 0, "category": "upgrades",
		"values": {"chance": 0.25, "damage": 110.0, "strikes": 4, "radius": 650.0, "delay": 0.25, "cooldown": 0.2}})
	# Cleave Axe: cleave works for melee heroes only; it also has the Mini-Axe's creep bonus and tree chop
	_it("cleave_axe", "Cleave Axe", 3900, {"use": "chop", "cooldown": 3.0, "passive": "cleave",
		"stats": {"damage": 50.0, "hp_regen": 7.5, "mana_regen": 2.75}, "category": "upgrades",
		"components": ["steady_ring", "broadsword", "broadsword", "quelling_blade"], "recipe_cost": 400,
		"values": {"creep_damage_melee": 10.0, "creep_damage_ranged": 5.0, "chop_range": 350.0, "cleave_pct": 0.6, "cleave_pct_creep": 0.4,
		"start_width": 150.0, "end_width": 360.0, "distance": 650.0}})
	# Glimmer Cape (Dota 7.41d): on an ally (or itself) within 600: after 0.5 s it is invisible for 5 s, 20% faster, and
	# a barrier takes the next 375 magic damage; attacking or casting ends the invisibility (not the barrier)
	_it("glimmer_cape", "Fade Cape", 2150, {"use": "fade", "target_team": "ally", "cooldown": 15.0, "mana": 125.0,
		"stats": {"magic_resist": 0.20}, "components": ["sneak_charm", "shawl"], "recipe_cost": 800, "category": "upgrades",
		"values": {"range": 600.0, "fade": 0.5, "duration": 5.0, "move_speed_pct": 0.20, "barrier": 375.0}})
	_it("sneak_blade", "Sneak Blade", 3250, {"use": "sneak", "cooldown": 25.0, "mana": 75.0,
		"stats": {"damage": 25.0, "attack_speed": 35.0}, "category": "upgrades",
		"components": ["greatsword", "brass_knuckles", "sneak_charm"], "recipe_cost": 0,
		"values": {"duration": 17.0, "fade": 0.3, "move_speed_pct": 0.2, "bonus_damage": 175.0}})
	_it("upgrade_staff", "Upgrade Staff", 4200, {"grants": "scepter", "no_disassemble": true, "stats": {"str": 10.0, "agi": 10.0,
		"int": 10.0, "hp": 175.0, "mana": 175.0}, "category": "upgrades",
		"components": ["big_gem", "wizard_staff", "giant_axe", "blade_alacrity"], "recipe_cost": 0})
	# Upgrade Gem: used up the moment it is bought (the hero keeps its upgrades for good); on sale from 15:00
	_it("upgrade_gem", "Upgrade Gem", 1400, {"grants": "shard", "consume_on_buy": true, "available_at": 900.0,
		"category": "upgrades"})
	_it("mask_of_madness", "Frenzy Mask", 1900, {"use": "berserk", "cooldown": 16.0, "stats": {"damage": 20.0, "lifesteal": 0.22},
		"components": ["broadsword", "lifesteal"], "recipe_cost": 0, "category": "upgrades",
		"values": {"attack_speed": 100.0, "move_speed_pct": 0.06, "move_speed_pct_melee": 0.12, "armor_reduction": 7.0,
		"duration": 6.0, "mana": 25.0}})
	# Igit (Dota's Yasha; the owner's name)
	_it("yasha", "Igit", 2100, {"stats": {"agi": 16.0, "attack_speed": 15.0, "move_speed_pct": 0.1},
		"components": ["blade_alacrity", "boots_elves"], "recipe_cost": 650, "category": "upgrades"})
	_it("dragon_lance", "Long Spear", 2000, {"stats": {"agi": 15.0, "str": 10.0, "range": 130.0},
		"components": ["blade_alacrity", "belt_str"], "recipe_cost": 550, "category": "upgrades"})
	# Big parts (Dota's secret shop parts; here in the main shop): Demon Edge, Talisman of Evasion, Mystic Staff,
	# Tiara of Selemene
	_it("huge_sword", "Huge Sword", 2200, {"stats": {"damage": 40.0}, "category": "big_parts"})
	_it("dodge_charm", "Dodge Charm", 1300, {"stats": {"evasion": 0.15}, "category": "big_parts"})
	_it("long_staff", "Long Staff", 2800, {"stats": {"int": 25.0}, "category": "big_parts"})
	_it("mana_tiara", "Mana Tiara", 1700, {"stats": {"mana_regen": 6.0}, "category": "big_parts"})
	# Status items (Dota 7.41d items.txt). Keys ending in "_max" do not stack between items (the largest counts).
	# The owner named Sange, Yasha and Kaya Kugmo, Igit and Atuli (2026-10-14). Kugmo: slow resistance and health
	# restoration; Atuli: magic amp (diminishing between items, see SimConst.ITEM_MAGIC_AMP_FALLOFF) and mana regen
	# amplification; the pairs combine both halves as Dota's Sange and Yasha, Kaya and Sange, Yasha and Kaya.
	_it("heavy_sword", "Kugmo", 2100, {"stats": {"str": 16.0, "slow_resist_max": 0.25, "heal_amp_max": 0.12},
		"components": ["giant_axe", "belt_str"], "recipe_cost": 650, "category": "upgrades"})
	_it("spell_sword", "Atuli", 2100, {"stats": {"int": 16.0, "magic_amp": 0.10, "mana_regen_amp_max": 0.20},
		"components": ["wizard_staff", "robe"], "recipe_cost": 650, "category": "upgrades"})
	_it("twin_swords", "Kugmo and Igit", 4200, {"stats": {"str": 16.0, "agi": 16.0, "attack_speed": 20.0,
		"move_speed_pct": 0.12, "status_resist_max": 0.16, "heal_amp_max": 0.16, "slow_resist_max": 0.30},
		"components": ["heavy_sword", "yasha"], "recipe_cost": 0, "category": "upgrades"})
	_it("kugmo_atuli", "Kugmo and Atuli", 4200, {"stats": {"str": 16.0, "int": 16.0, "slow_resist_max": 0.25,
		"heal_amp_max": 0.16, "magic_amp": 0.12, "mana_regen_amp_max": 0.30, "mana_cost_cut_max": 0.25},
		"components": ["heavy_sword", "spell_sword"], "recipe_cost": 0, "category": "upgrades"})
	_it("igit_atuli", "Igit and Atuli", 4200, {"stats": {"agi": 16.0, "int": 16.0, "attack_speed": 20.0,
		"move_speed_pct": 0.12, "magic_amp": 0.12, "mana_regen_amp_max": 0.30, "cast_speed_max": 0.25},
		"components": ["yasha", "spell_sword"], "recipe_cost": 0, "category": "upgrades"})
	_it("battle_staff", "Battle Staff", 1625, {"stats": {"int": 10.0, "attack_speed": 35.0, "mana_regen": 1.25},
		"components": ["brass_knuckles", "robe", "sobi_mask"], "recipe_cost": 0, "category": "upgrades"})
	# Critical strike (Crystalys, Daedalus): a pseudo-random chance to multiply the attack's damage
	_it("crit_sword", "Crit Sword", 2000, {"passive": "crit", "stats": {"damage": 32.0},
		"components": ["greatsword", "blades_attack"], "recipe_cost": 200, "category": "upgrades",
		"values": {"crit_chance": 0.30, "crit_mult": 1.6}})
	_it("crit_bow", "Crit Bow", 5200, {"passive": "crit", "stats": {"damage": 88.0},
		"components": ["crit_sword", "huge_sword"], "recipe_cost": 1000, "category": "upgrades",
		"values": {"crit_chance": 0.30, "crit_mult": 2.25}})
	# Bash (Skull Basher, Abyssal Blade): a chance to stun and add damage; only one bash item works, 2.3 s apart.
	# The Stun Blade's active (Overwhelm) stuns 1.6 s through debuff immunity.
	_it("stun_club", "Stun Club", 2875, {"passive": "bash", "stats": {"damage": 30.0, "str": 10.0},
		"components": ["steel_hammer", "belt_str"], "recipe_cost": 825, "category": "upgrades",
		"values": {"chance_melee": 0.25, "chance_ranged": 0.10, "duration": 1.2, "bash_cooldown": 2.3, "damage": 100.0}})
	_it("stun_blade", "Stun Blade", 6250, {"passive": "bash", "use": "overwhelm", "target_team": "enemy",
		"cooldown": 35.0, "mana": 75.0, "stats": {"damage": 35.0, "str": 30.0, "slow_resist_max": 0.30,
		"heal_amp_max": 0.16}, "components": ["stun_club", "heavy_sword"], "recipe_cost": 1275, "category": "upgrades",
		"values": {"chance_melee": 0.25, "chance_ranged": 0.10, "duration": 1.2, "bash_cooldown": 2.3, "damage": 120.0,
		"stun": 1.6, "range": 150.0}})
	# True strike (Monkey King Bar): Pierce, 80% for 70 magic damage and the attack cannot miss
	_it("sure_hit_staff", "Sure Hit Staff", 5000, {"passive": "pierce", "stats": {"damage": 50.0, "attack_speed": 50.0},
		"stats_melee": {"range_melee": 50.0}, "components": ["huge_sword", "brass_knuckles", "spear"], "recipe_cost": 900,
		"category": "upgrades", "values": {"chance": 0.80, "damage": 70.0}})
	# Disables: silence (Orchid), root (Rod of Atos), disarm (Heaven's Halberd), hex (Scythe of Vyse), break (Silver
	# Edge's Shadow Walk)
	_it("silence_staff", "Silence Staff", 3275, {"use": "silence", "element": "dark", "target_team": "enemy", "cooldown": 18.0,
		"mana": 125.0, "stats": {"attack_speed": 35.0, "damage": 20.0, "mana_regen": 2.5, "int": 12.0},
		"components": ["battle_staff", "greatsword"], "recipe_cost": 300, "category": "upgrades",
		"values": {"duration": 5.0, "damage_pct": 0.30, "range": 900.0}})
	_it("root_staff", "Root Staff", 2250, {"use": "root", "target_team": "enemy", "cooldown": 18.0, "mana": 100.0,
		"stats": {"int": 12.0, "hp": 275.0}, "components": ["wizard_staff", "health_crystal"], "recipe_cost": 250,
		"category": "upgrades", "values": {"duration": 2.0, "range": 1100.0, "speed": 1900.0}})
	_it("halberd", "Halberd", 3300, {"use": "disarm", "target_team": "enemy", "cooldown": 15.0, "mana": 25.0,
		"stats": {"armor": 9.0, "hp_regen": 6.5, "evasion": 0.25},
		"components": ["dodge_charm", "plate_vest", "big_healing_ring"], "recipe_cost": 350, "category": "upgrades",
		"values": {"duration": 3.5, "range": 750.0}})
	_it("hex_staff", "Hex Staff", 5200, {"use": "hex", "target_team": "enemy", "cooldown": 20.0, "mana": 250.0,
		"stats": {"int": 30.0, "mana_regen": 8.5}, "components": ["long_staff", "mana_tiara"], "recipe_cost": 700,
		"category": "upgrades", "values": {"duration": 2.8, "range": 800.0}})
	_it("break_blade", "Break Blade", 5700, {"use": "sneak", "cooldown": 23.0, "mana": 75.0,
		"stats": {"damage": 70.0, "attack_speed": 35.0}, "category": "upgrades",
		"components": ["sneak_blade", "huge_sword"], "recipe_cost": 250,
		"values": {"duration": 17.0, "fade": 0.3, "move_speed_pct": 0.2, "bonus_damage": 300.0, "break": 5.0}})
	# ---- Run 2026-10-15 b: twenty more Dota items (work/research/d2_items.txt), our names --------------------------
	# Parts: Energy Booster, Hyperstone, Platemail, Crown, Chasm Stone, Sacred Relic, Reaver, Ring of Tarrasque,
	# Eaglesong, Helm of Iron Will, Wind Lace
	_it("mana_gem", "Mana Gem", 800, {"stats": {"mana": 250.0}, "category": "misc"})
	_it("swift_stone", "Swift Stone", 2000, {"stats": {"attack_speed": 60.0}, "category": "big_parts"})
	_it("plate_armor", "Plate Armor", 1400, {"stats": {"armor": 10.0}, "category": "armaments"})
	_it("gold_band", "Gold Band", 450, {"stats": {"str": 4.0, "agi": 4.0, "int": 4.0}, "category": "attributes"})
	# Chasm Stone: +40 area of effect for spells (several AoE bonuses do not stack: the largest counts)
	_it("wide_stone", "Wide Stone", 900, {"stats": {"aoe_bonus_max": 40.0}, "category": "misc"})
	_it("relic", "Relic", 3400, {"stats": {"damage": 55.0}, "category": "big_parts"})
	_it("war_axe", "War Axe", 2800, {"stats": {"str": 25.0}, "category": "big_parts"})
	_it("troll_ring", "Troll Ring", 1700, {"stats": {"hp_regen": 12.0}, "category": "big_parts"})
	_it("feather", "Feather", 2800, {"stats": {"agi": 25.0}, "category": "big_parts"})
	_it("iron_helm", "Iron Helm", 975, {"stats": {"armor": 4.0, "hp_regen": 4.0}, "category": "armaments"})
	_it("speed_ribbon", "Speed Ribbon", 225, {"stats": {"move_speed": 15.0}, "category": "misc"})
	# Boots of Travel: +90 speed; teleports (no scroll needed) to an allied building or creep, 40 s cooldown
	_it("travel_boots", "Travel Boots", 2500, {"stats": {"boot_ms": 90.0}, "travel": true, "category": "upgrades",
		"components": ["boots"], "recipe_cost": 2000, "values": {"tp_cooldown": 40.0},
		"text": "Teleport without a scroll (Teleport key or the Teleport slot) to any allied building or creep. 40 second cooldown."})
	# Dagon 1-5 (Blast Rod): Energy Burst, magic damage to one enemy; each level is the one before plus its recipe
	var dagon_levels := [[3000, 400, 120, 27, 6, 200, 350, 60], [4100, 500, 140, 24, 7, 210, 375, 90],
		[5200, 600, 160, 21, 8, 220, 400, 120], [6300, 700, 180, 18, 9, 230, 425, 150],
		[7400, 800, 200, 15, 10, 240, 450, 180]]
	for i in 5:
		var dl: Array = dagon_levels[i]
		var did := "dagon" if i == 0 else "dagon_%d" % (i + 1)
		_it(did, "Blast Rod" if i == 0 else "Blast Rod %d" % (i + 1), int(dl[0]), {"use": "blast", "target_team": "enemy",
			"cooldown": float(dl[3]), "mana": float(dl[2]), "element": "lightning", "category": "upgrades", "level": i + 1,
			"stats": {"str": float(dl[4]), "agi": float(dl[4]), "int": float(dl[4]), "hp": float(dl[5]), "mana": float(dl[6]),
				"cast_range_max": float(dl[7])},
			"components": ["big_gem", "gold_band", "pointy_hat"] if i == 0 else ["dagon" if i == 1 else "dagon_%d" % i],
			"recipe_cost": 1100, "values": {"damage": float(dl[1]), "range": 640.0},
			"text": "Blast an enemy within 640 with %d magic damage at once. Buy the recipe again to raise its level (up to 5)." % int(dl[1])})
	# Gleipnir (Net Staff): Eternal Chains, roots every enemy in a 325 area (projectiles at 1900)
	_it("net_staff", "Net Staff", 4650, {"use": "net", "cooldown": 18.0, "mana": 150.0, "category": "upgrades",
		"stats": {"hp": 450.0, "mana": 200.0, "int": 12.0, "aoe_bonus_max": 75.0},
		"components": ["root_staff", "big_gem", "wide_stone"], "recipe_cost": 300,
		"values": {"radius": 325.0, "duration": 2.0, "range": 1100.0, "speed": 1900.0},
		"text": "Throw nets at every enemy in a 325 area within 1100: each one hit cannot move for 2 seconds. Costs 150 mana, 18 second cooldown."})
	# Mjollnir (Storm Hammer): Chain Lightning 25% / 180 / 12 strikes; Static Charge on an ally for 12 s
	_it("storm_hammer", "Storm Hammer", 5500, {"use": "static", "target_team": "ally", "cooldown": 35.0, "mana": 50.0,
		"passive": "chain", "element": "lightning", "stats": {"damage": 25.0, "attack_speed": 90.0}, "category": "upgrades",
		"components": ["shock_hammer", "swift_stone"], "recipe_cost": 550,
		"values": {"chance": 0.25, "damage": 180.0, "strikes": 12, "radius": 650.0, "delay": 0.25, "cooldown": 0.2,
			"static_duration": 12.0, "static_chance": 0.20, "static_strikes": 4, "static_damage": 225.0,
			"static_primary_radius": 600.0, "static_radius": 900.0, "static_cooldown": 1.0, "range": 800.0},
		"text": "Static Charge: for 12 seconds an ally (or yourself) has a 20% chance when attacked to strike up to 4 enemies within 900 with lightning for 225 magic damage (the attacker first). Costs 50 mana, 35 second cooldown."})
	_it("soul_gem", "Soul Gem", 3000, {"stats": {"hp": 425.0, "mana": 425.0}, "category": "upgrades",
		"components": ["big_gem", "health_crystal", "mana_gem"], "recipe_cost": 0})
	# Octarine Core (Time Crystal): 25% cooldown reduction for spells and items (does not stack)
	_it("time_crystal", "Time Crystal", 5100, {"stats": {"hp": 450.0, "mana": 450.0, "mana_regen": 6.0,
		"cooldown_reduction_max": 0.25}, "category": "upgrades", "components": ["soul_gem", "mana_tiara"], "recipe_cost": 400,
		"text": "Your spells and items cool down 25% faster (several of these do not stack)."})
	# Buckler (Small Shield): +2 armor aura
	_it("small_shield", "Small Shield", 425, {"stats": {"armor": 1.0}, "category": "upgrades", "components": ["ring_protection"],
		"recipe_cost": 250, "auras": [{"id": "small_shield_aura", "name": "Armor Aura", "stats": {"armor": 2.0}, "radius": 1200.0}]})
	# Vladmir's Offering (Leech Totem): allies near (not its owner's damage and lifesteal) get armor, mana regen,
	# lifesteal and base damage
	_it("leech_totem", "Leech Totem", 2200, {"stats": {"armor": 1.0, "mana_regen": 0.75}, "category": "upgrades",
		"components": ["small_shield", "mana_ring", "lifesteal", "blades_attack"], "recipe_cost": 0,
		"auras": [{"id": "leech_totem_aura", "name": "Leech Aura", "radius": 1200.0,
			"stats": {"armor": 2.0, "mana_regen": 1.0, "lifesteal": 0.20, "base_damage_pct": 0.18},
			"creep_stats": {"armor": 2.0, "mana_regen": 1.0, "lifesteal": 0.12, "base_damage_pct": 0.18},
			"self_stats": {"armor": 2.0, "mana_regen": 1.0}}]})
	# Assault Cuirass (Battle Armor): allies +30 attack speed and +5 armor, enemies -5 armor (buildings too)
	_it("battle_armor", "Battle Armor", 5125, {"stats": {"attack_speed": 30.0, "armor": 10.0}, "category": "upgrades",
		"components": ["small_shield", "swift_stone", "plate_armor"], "recipe_cost": 1300,
		"auras": [{"id": "battle_armor_aura", "name": "Battle Aura", "radius": 1200.0, "buildings": true,
			"stats": {"attack_speed": 30.0, "armor": 5.0}},
			{"id": "battle_armor_curse", "name": "Armor Loss Aura", "radius": 1200.0, "enemy": true, "buildings": true,
			"stats": {"armor": -5.0}}]})
	# Shiva's Guard (Frost Plate): enemies -40 attack speed; Arctic Blast 225 damage, -40% speed for 4 s, to 825
	_it("frost_plate", "Frost Plate", 4500, {"use": "frost_blast", "cooldown": 27.0, "mana": 75.0, "element": "ice",
		"stats": {"armor": 17.0, "aoe_bonus_max": 75.0}, "category": "upgrades",
		"components": ["plate_armor", "plate_vest", "wide_stone"], "recipe_cost": 1250,
		"auras": [{"id": "frost_plate_aura", "name": "Freezing Aura", "radius": 1200.0, "enemy": true,
			"stats": {"attack_speed": -40.0}}],
		"values": {"damage": 225.0, "slow": 0.40, "duration": 4.0, "radius": 825.0, "speed": 400.0},
		"text": "A ring of frost spreads out to 825: enemies it reaches take 225 magic damage and move 40% slower for 4 seconds. Costs 75 mana, 27 second cooldown."})
	# Radiance (Burning Cape): 60 magic damage per second to enemies within 650; 25% evasion
	_it("burning_cape", "Burning Cape", 4700, {"element": "fire", "stats": {"damage": 55.0, "evasion": 0.25}, "category": "upgrades",
		"components": ["relic", "dodge_charm"], "recipe_cost": 0, "burn": {"dps": 60.0, "radius": 650.0},
		"text": "Burns enemies within 650 for 60 magic damage per second (Fire)."})
	# Heart of Tarrasque (Giant Heart): +40 strength, regenerates 1% of max health and 1.5% of missing health a second
	_it("giant_heart", "Giant Heart", 5300, {"stats": {"str": 40.0, "hp_regen_pct_max": 0.01, "hp_regen_pct_missing": 0.015},
		"category": "upgrades", "components": ["war_axe", "troll_ring"], "recipe_cost": 800,
		"text": "Regenerates 1% of your maximum health and 1.5% of your missing health every second."})
	# Satanic (Leech Blade): Unholy Rage, +145% lifesteal for 6 s
	_it("leech_blade", "Leech Blade", 5050, {"use": "rage", "cooldown": 40.0, "stats": {"str": 25.0, "damage": 25.0,
		"lifesteal": 0.25}, "category": "upgrades", "components": ["war_axe", "greatsword", "lifesteal"], "recipe_cost": 0,
		"values": {"lifesteal": 1.45, "duration": 6.0},
		"text": "Blood Rage: +145% lifesteal for 6 seconds. 40 second cooldown."})
	# Butterfly (Moth Blade)
	_it("moth_blade", "Moth Blade", 5450, {"stats": {"agi": 30.0, "evasion": 0.35, "attack_speed": 20.0, "damage": 30.0},
		"category": "upgrades", "components": ["feather", "greatsword", "dodge_charm"], "recipe_cost": 0})
	# Refresher Orb (Refresh Stone): resets every ability cooldown (not items)
	_it("refresh_stone", "Refresh Stone", 5000, {"use": "refresh", "cooldown": 180.0, "mana": 325.0,
		"stats": {"hp_regen": 14.0, "mana_regen": 7.0}, "category": "upgrades", "components": ["troll_ring", "mana_tiara"],
		"recipe_cost": 1600,
		"text": "Finish the cooldowns of all your spells at once (not items). Costs 325 mana, 180 second cooldown."})
	# Guardian Greaves (Guard Boots): regen aura (much more below 25% health), Mend: heal 325 and 200 mana, dispel
	_it("guard_boots", "Guard Boots", 4450, {"use": "greaves", "cooldown": 45.0, "stats": {"boot_ms": 50.0, "armor": 5.0,
		"mana": 150.0, "mana_regen": 1.0}, "category": "upgrades", "components": ["mana_boots", "medic_kit"], "recipe_cost": 1175,
		"auras": [{"id": "guard_boots_aura", "name": "Guard Aura", "radius": 1200.0,
			"stats": {"hp_regen": 2.5, "mana_regen": 1.5}, "low_hp": 0.25, "low_hp_stats": {"hp_regen": 17.0, "mana_regen": 1.5}}],
		"values": {"heal": 325.0, "mana": 200.0, "radius": 1200.0},
		"text": "Mend: heal yourself and allies within 1200 for 325 health and 200 mana, and remove your own debuffs (a basic dispel). 45 second cooldown. Aura: +2.5 health regen (+17 below 25% health) and +1.5 mana regen."})
	# Crimson Guard (Team Shield): block like the Block Shield (75 / 50); Guard: allies block 70 + 2% of your health
	_it("team_shield", "Team Shield", 3725, {"use": "guard", "cooldown": 40.0, "mana": 75.0, "passive": "block",
		"stats": {"hp": 250.0, "hp_regen": 12.0, "armor": 6.0}, "category": "upgrades",
		"components": ["block_shield", "iron_helm"], "recipe_cost": 1050,
		"values": {"chance": 0.6, "block_melee": 75.0, "block_ranged": 50.0, "duration": 7.0, "radius": 1200.0,
			"guard_block": 70.0, "guard_hp_pct": 0.02},
		"text": "Guard: for 7 seconds you and allies within 1200 block 70 damage (+2% of your max health) from every attack. Costs 75 mana, 40 second cooldown."})
	# Drum of Endurance (War Drum): +15 speed aura; Endurance: allies +35 attack speed and +13% speed for 6 s
	_it("war_drum", "War Drum", 1625, {"use": "drum", "cooldown": 45.0, "stats": {"str": 8.0}, "category": "upgrades",
		"components": ["leaf_hat", "belt_str", "speed_ribbon"], "recipe_cost": 525,
		"auras": [{"id": "war_drum_aura", "name": "March Aura", "radius": 1200.0, "stats": {"move_speed": 15.0, "hp_regen": 2.5}}],
		"values": {"attack_speed": 35.0, "move_speed_pct": 0.13, "duration": 6.0, "radius": 1200.0},
		"text": "Endurance: you and allies within 1200 get +35 attack speed and 13% more speed for 6 seconds. 45 second cooldown. Aura: +15 movement speed and +2.5 health regen."})
	# Aether Lens (Long Lens): +225 cast range
	_it("long_lens", "Long Lens", 2275, {"stats": {"mana": 300.0, "mana_regen": 2.5, "cast_range_max": 225.0},
		"category": "upgrades", "components": ["mana_gem", "mana_stone"], "recipe_cost": 775,
		"text": "+225 cast range for spells and items. A second Long Lens adds half as much, a third a quarter."})
	# Overwhelming Blink (Crash Knife): a Jump Knife whose landing hurts and slows enemies within 800
	_it("crash_knife", "Crash Knife", 6800, {"use": "jump", "cooldown": 15.0, "stats": {"str": 25.0}, "category": "upgrades",
		"components": ["jump_knife", "war_axe"], "recipe_cost": 1750,
		"values": {"range": 1200.0, "clamp": 960.0, "hero_damage_lockout": 3.0, "crash_radius": 800.0, "slow": 0.5,
			"attack_slow": 50.0, "duration": 6.0, "damage_base": 100.0, "damage_pct": 0.5, "dot_pct": 1.0},
		"text": "Jump up to 1200 (as the Jump Knife). Where you land, enemies within 800 take 100 + 50% of your strength as magic damage, then another 100% of your strength over 6 seconds, and move 50% and attack 50 slower for 6 seconds."})
	# Recipe scrolls: one per item whose recipe costs gold, bought on its own or as part of the item
	for id in _items.keys():
		var d: Dictionary = _items[id]
		if int(d.recipe_cost) > 0:
			_it("recipe_" + id, "Recipe: " + String(d.name), int(d.recipe_cost), {"category": "recipe", "recipe_for": id,
				"icon": "recipe"})
