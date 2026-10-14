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
	_build_talents()

static func unit(id: String) -> Dictionary:
	_ensure()
	return _units.get(id, {})

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
	super_melee.merge({"hp": 700.0, "armor": 3.0, "dmg_min": 41.0, "dmg_max": 49.0, "xp": 25.0, "gold_min": 20, "gold_max": 26}, true)
	var super_ranged := ranged.duplicate()
	super_ranged.merge({"hp": 475.0, "armor": 1.0, "dmg_min": 46.0, "dmg_max": 51.0, "xp": 22.0, "gold_min": 19, "gold_max": 25}, true)
	var names := {
		0: {"melee": "Footman", "ranged": "Archer", "siege": "Stone Golem", "flag": "Flag Bearer"},
		1: {"melee": "Ghoul", "ranged": "Skeleton Archer", "siege": "Bone Golem", "flag": "Flag Bearer"},
	}
	for team in [0, 1]:
		var p := "dawn_" if team == 0 else "dusk_"
		var n: Dictionary = names[team]
		var el := EL.LIGHT if team == 0 else EL.DARK
		for d in [melee, ranged, siege, flag, super_melee, super_ranged]:
			d["element"] = el
		_add(p + "melee", _named(melee, n.melee, p + "melee"))
		_add(p + "ranged", _named(ranged, n.ranged, p + "ranged"))
		_add(p + "siege", _named(siege, n.siege, p + "siege"))
		_add(p + "flag", _named(flag, n.flag, p + "flag"))
		_add(p + "melee_super", _named(super_melee, "Super " + n.melee, p + "melee"))
		_add(p + "ranged_super", _named(super_ranged, "Super " + n.ranged, p + "ranged"))

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
	_add("blood_ranger", {"name": "Blood Ranger", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 27.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 0.55, "acquire": 800.0, "range": 625.0,
		"projectile_speed": 1250.0, "move_speed": 300.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 16.0, "str_gain": 1.9, "agi": 24.0, "agi_gain": 2.8, "int": 15.0,
		"int_gain": 1.4, "element": EL.NATURE, "abilities": ["burst_shot", "gale_impact", "masterful_archery", "blood_ranger_ult"],
		"model": "hero"})
	# Ezee, the Dark Paladin: a melee strength fighter (stats follow the classic melee-strength template).
	_add("ezee", {"name": "Ezee", "title": "the Dark Paladin", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.5, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 1.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 30.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.4, "backswing": 0.6, "acquire": 600.0, "range": 150.0,
		"projectile_speed": 0.0, "move_speed": 305.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "str", "str": 24.0, "str_gain": 3.2, "agi": 16.0, "agi_gain": 2.0, "int": 18.0,
		"int_gain": 1.7, "element": EL.DARK, "abilities": ["dark_stomp", "leap_strike", "tainted_touch", "unholy_might"],
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
		"desc": "Blood Ranger plants her feet and looses 30 arrows over five waves of four to seven into the target area. Each arrow strikes a random enemy there for a share of her attack damage. Channelled: moving, attacking, stopping, a stun, silence or a push ends it."}
	_abilities["gale_impact"] = {"id": "gale_impact", "name": "Gale Impact", "behavior": "point", "key": "W",
		"max_level": 4, "mana": [100, 110, 120, 130], "cooldown": [12, 12, 12, 12], "cast_point": 0.3, "range": 2000,
		"anim": "bow_1", "damage_type": "magical", "line": true, "direction": true,
		"values": {"damage": [120, 200, 280, 360], "impact_pct": [0.2, 0.2, 0.2, 0.2], "width": [110, 110, 110, 110],
		"speed": [2000, 2000, 2000, 2000], "distance": [2000, 2000, 2000, 2000], "push_speed": [1150, 1150, 1150, 1150]},
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
		"desc": "Blood Ranger gives in to the hunt: for 15 seconds her attacks steal life and reach much further. When an attack hits her she may leap back out of reach."}
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
		"desc": "Azrin hurls a great flaming javelin up to 1000 range. Every enemy near its path is caught and dragged along to where it lands, and burns for magic damage every second for 5 seconds."}
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
	# Recipe scrolls: one per item whose recipe costs gold, bought on its own or as part of the item
	for id in _items.keys():
		var d: Dictionary = _items[id]
		if int(d.recipe_cost) > 0:
			_it("recipe_" + id, "Recipe: " + String(d.name), int(d.recipe_cost), {"category": "recipe", "recipe_for": id,
				"icon": "recipe"})
