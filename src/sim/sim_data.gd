class_name SimData
extends RefCounted
## Unit, hero, ability and item definitions. Stats are copied from Dota 2's game data (npc_units / heroes / items,
## see docs/MECHANICS.md); names and designs are Warriors of Aether's own.
##
## A unit definition is a Dictionary; every key below is always present (see `_unit`).

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const AC = C.AttackClass

static var _units := {}
static var _items := {}
static var _abilities := {}
static var _ready := false

static func _unit(id: String, d: Dictionary) -> Dictionary:
	var u := {
		"id": id, "name": id, "kind": K.CREEP_MELEE, "hull": 16.0, "hp": 150.0, "hp_regen": 0.0, "mana": 0.0,
		"mana_regen": 0.0, "armor": 0.0, "magic_resist": 0.0, "dmg_min": 1.0, "dmg_max": 1.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 0.5, "acquire": 800.0, "range": 100.0,
		"projectile_speed": 0.0, "move_speed": 300.0, "turn_rate": 0.5, "vision_day": 750.0, "vision_night": 750.0,
		"xp": 0.0, "gold_min": 0, "gold_max": 0, "attack_class": AC.DEFAULT, "level": 1, "model": id,
		"can_attack": true, "can_move": true, "flying": false, "abilities": [], "bounty_key": "",
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

# ---- Units --------------------------------------------------------------------------------------------------------

static func _add(id: String, d: Dictionary) -> void:
	_units[id] = _unit(id, d)

static func _build_units() -> void:
	# Lane creeps (npc_dota_creep_*). Backswing values are the animation lengths after the attack point.
	var melee := {"kind": K.CREEP_MELEE, "hull": 16.0, "hp": 550.0, "hp_regen": 0.5, "armor": 2.0, "dmg_min": 19.0,
		"dmg_max": 23.0, "bat": 1.0, "attack_point": 0.467, "backswing": 0.533, "acquire": 500.0, "range": 100.0,
		"move_speed": 325.0, "turn_rate": 0.5, "xp": 57.0, "gold_min": 34, "gold_max": 39, "attack_class": AC.RUNTY,
		"level": 3}
	var ranged := {"kind": K.CREEP_RANGED, "hull": 8.0, "hp": 300.0, "hp_regen": 2.0, "mana": 500.0, "mana_regen": 0.75,
		"armor": 0.0, "dmg_min": 21.0, "dmg_max": 26.0, "bat": 1.0, "attack_point": 0.5, "backswing": 0.3,
		"acquire": 600.0, "range": 500.0, "projectile_speed": 900.0, "move_speed": 325.0, "turn_rate": 0.5, "xp": 69.0,
		"gold_min": 43, "gold_max": 52, "attack_class": AC.PIERCING, "level": 5}
	var siege := {"kind": K.CREEP_SIEGE, "hull": 16.0, "hp": 935.0, "magic_resist": 0.8, "dmg_min": 35.0, "dmg_max": 46.0,
		"bat": 3.0, "attack_point": 0.7, "backswing": 0.3, "acquire": 800.0, "range": 690.0, "projectile_speed": 1100.0,
		"move_speed": 325.0, "turn_rate": 0.5, "xp": 88.0, "gold_min": 59, "gold_max": 72, "attack_class": AC.REINFORCED,
		"level": 4}
	var flag := melee.duplicate()
	flag.merge({"kind": K.CREEP_FLAG, "magic_resist": 0.4}, true)
	var super_melee := melee.duplicate()
	super_melee.merge({"hp": 700.0, "armor": 3.0, "dmg_min": 41.0, "dmg_max": 49.0, "xp": 25.0, "gold_min": 20, "gold_max": 26}, true)
	var super_ranged := ranged.duplicate()
	super_ranged.merge({"hp": 475.0, "armor": 1.0, "dmg_min": 46.0, "dmg_max": 51.0, "xp": 22.0, "gold_min": 19, "gold_max": 25}, true)
	var names := {
		0: {"melee": "Sunguard Footman", "ranged": "Sunseer", "siege": "Sunforge Golem", "flag": "Banner Warden"},
		1: {"melee": "Hollow Ghoul", "ranged": "Bone Caster", "siege": "Grave Colossus", "flag": "Dread Standard"},
	}
	for team in [0, 1]:
		var p := "dawn_" if team == 0 else "dusk_"
		var n: Dictionary = names[team]
		_add(p + "melee", _named(melee, n.melee, p + "melee"))
		_add(p + "ranged", _named(ranged, n.ranged, p + "ranged"))
		_add(p + "siege", _named(siege, n.siege, p + "siege"))
		_add(p + "flag", _named(flag, n.flag, p + "flag"))
		_add(p + "melee_super", _named(super_melee, "Elder " + n.melee, p + "melee"))
		_add(p + "ranged_super", _named(super_ranged, "Elder " + n.ranged, p + "ranged"))

	# Buildings (npc_dota_goodguys_*). Towers use the Reinforced (siege) attack class.
	var tower := {"kind": K.TOWER, "hull": 144.0, "can_move": false, "bat": 0.9, "attack_speed": 110.0,
		"attack_point": 0.6, "backswing": 0.4, "acquire": 700.0, "range": 700.0, "projectile_speed": 750.0,
		"move_speed": 0.0, "turn_rate": 1.0, "vision_day": 1900.0, "attack_class": AC.REINFORCED}
	_add("tower1", _merged(tower, {"name": "Tier 1 Tower", "hp": 1800.0, "armor": 12.0, "dmg_min": 88.0, "dmg_max": 92.0,
		"vision_night": 800.0, "level": 1, "bounty_key": "tower1"}))
	_add("tower2", _merged(tower, {"name": "Tier 2 Tower", "hp": 2500.0, "armor": 16.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 2, "bounty_key": "tower2"}))
	_add("tower3", _merged(tower, {"name": "Tier 3 Tower", "hp": 2500.0, "armor": 16.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 3, "bounty_key": "tower3"}))
	_add("tower4", _merged(tower, {"name": "Tier 4 Tower", "hp": 2600.0, "armor": 21.0, "dmg_min": 170.0, "dmg_max": 174.0,
		"vision_night": 1100.0, "level": 4, "bounty_key": "tower4"}))
	var building := {"can_attack": false, "can_move": false, "move_speed": 0.0, "turn_rate": 0.0, "acquire": 0.0}
	_add("melee_rax", _merged(building, {"name": "Melee Barracks", "kind": K.BARRACKS, "hull": 144.0, "hp": 2200.0,
		"hp_regen": 5.0, "armor": 15.0, "vision_day": 900.0, "vision_night": 600.0, "bounty_key": "melee_rax"}))
	_add("ranged_rax", _merged(building, {"name": "Ranged Barracks", "kind": K.BARRACKS, "hull": 144.0, "hp": 1300.0,
		"armor": 9.0, "vision_day": 900.0, "vision_night": 600.0, "bounty_key": "ranged_rax"}))
	_add("ancient", _merged(building, {"name": "Aether Core", "kind": K.ANCIENT, "hull": 298.0, "hp": 4500.0,
		"hp_regen": 12.0, "armor": 23.0, "vision_day": 2600.0, "vision_night": 2600.0}))
	_add("filler", _merged(building, {"name": "Effigy", "kind": K.FILLER, "hull": 96.0, "hp": 1000.0, "armor": 10.0,
		"vision_day": 900.0, "vision_night": 600.0, "bounty_key": "filler"}))
	_add("fountain", {"name": "Fountain", "kind": K.FOUNTAIN, "hull": 144.0, "hp": 500.0, "can_move": false,
		"move_speed": 0.0, "dmg_min": 290.0, "dmg_max": 310.0, "bat": 0.15, "attack_point": 0.0, "backswing": 0.0,
		"acquire": 1200.0, "range": 1200.0, "projectile_speed": 1400.0, "vision_day": 1800.0, "vision_night": 1800.0,
		"turn_rate": 1.0, "attack_class": AC.REINFORCED})
	_add("courier", {"name": "Courier", "kind": K.COURIER, "hull": 8.0, "hp": 75.0, "can_attack": false,
		"move_speed": 380.0, "turn_rate": 1.0, "vision_day": 500.0, "vision_night": 500.0, "model": "courier", "flying": true})
	_add("ward_observer", {"name": "Watcher Ward", "kind": K.WARD, "hull": 8.0, "hp": 200.0, "can_attack": false,
		"can_move": false, "move_speed": 0.0, "vision_day": 1600.0, "vision_night": 1600.0, "xp": 0.0})

	# Neutral creeps (npc_dota_neutral_*), renamed.
	var neu := {"kind": K.NEUTRAL_CREEP, "turn_rate": 0.9, "bat": 2.0, "vision_day": 800.0, "vision_night": 800.0}
	_add("mudling", _merged(neu, {"name": "Goblin Skulker", "hull": 16.0, "hp": 240.0, "hp_regen": 0.5, "dmg_min": 15.0,
		"dmg_max": 16.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0, "range": 100.0, "move_speed": 290.0,
		"xp": 14.0, "gold_min": 3, "gold_max": 5, "level": 1}))
	_add("mudling_digger", _merged(neu, {"name": "Goblin Sapper", "hull": 16.0, "hp": 325.0, "hp_regen": 0.5,
		"armor": 1.0, "dmg_min": 22.0, "dmg_max": 23.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0,
		"range": 100.0, "move_speed": 270.0, "xp": 17.0, "gold_min": 12, "gold_max": 14, "level": 1}))
	_add("mudling_foreman", _merged(neu, {"name": "Goblin Taskmaster", "hull": 16.0, "hp": 400.0, "hp_regen": 0.5,
		"armor": 2.0, "dmg_min": 24.0, "dmg_max": 26.0, "attack_point": 0.38, "backswing": 0.5, "acquire": 500.0,
		"range": 110.0, "move_speed": 330.0, "xp": 30.0, "gold_min": 19, "gold_max": 21, "level": 2}))
	_add("ashfang", _merged(neu, {"name": "Dire Wolf", "hull": 16.0, "hp": 500.0, "hp_regen": 0.5, "mana": 200.0,
		"armor": 1.0, "dmg_min": 15.0, "dmg_max": 17.0, "attack_point": 0.33, "backswing": 0.64, "acquire": 500.0,
		"range": 90.0, "move_speed": 350.0, "xp": 40.0, "gold_min": 18, "gold_max": 22, "level": 3}))
	_add("ashfang_alpha", _merged(neu, {"name": "Dire Wolf Alpha", "hull": 24.0, "hp": 600.0, "hp_regen": 0.5,
		"armor": 3.0, "dmg_min": 27.0, "dmg_max": 29.0, "attack_point": 0.33, "backswing": 0.64, "acquire": 500.0,
		"range": 90.0, "move_speed": 350.0, "xp": 60.0, "gold_min": 32, "gold_max": 34, "level": 5}))
	_add("strider", _merged(neu, {"name": "Orc Raider", "hull": 16.0, "hp": 350.0, "hp_regen": 0.5, "armor": 1.0,
		"dmg_min": 18.0, "dmg_max": 20.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 500.0, "range": 100.0,
		"move_speed": 320.0, "xp": 32.0, "gold_min": 16, "gold_max": 18, "level": 2}))
	_add("strider_warlord", _merged(neu, {"name": "Orc Warchanter", "hull": 24.0, "hp": 1100.0, "hp_regen": 1.0,
		"mana": 200.0, "armor": 4.0, "dmg_min": 49.0, "dmg_max": 55.0, "attack_point": 0.3, "backswing": 0.3,
		"acquire": 500.0, "range": 100.0, "move_speed": 320.0, "xp": 90.0, "gold_min": 54, "gold_max": 60, "level": 5}))
	_add("hill_troll", _merged(neu, {"name": "Mire Troll", "hull": 16.0, "hp": 500.0, "hp_regen": 0.5,
		"armor": 1.0, "dmg_min": 28.0, "dmg_max": 37.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 300.0,
		"range": 500.0, "projectile_speed": 1200.0, "move_speed": 270.0, "xp": 28.0, "gold_min": 18, "gold_max": 20,
		"attack_class": AC.PIERCING, "level": 2}))
	_add("ogre_brute", _merged(neu, {"name": "Ogre Crusher", "hull": 24.0, "hp": 800.0, "hp_regen": 0.5, "armor": 1.0,
		"dmg_min": 22.0, "dmg_max": 24.0, "attack_point": 0.3, "backswing": 0.3, "acquire": 500.0, "range": 100.0,
		"move_speed": 270.0, "xp": 32.0, "gold_min": 22, "gold_max": 26, "level": 2}))
	_add("cinder_wyrmling", _merged(neu, {"name": "Cinder Imp", "hull": 24.0, "hp": 950.0, "hp_regen": 0.5,
		"armor": 2.0, "magic_resist": 0.25, "dmg_min": 20.0, "dmg_max": 22.0, "attack_point": 0.5, "backswing": 0.5,
		"acquire": 300.0, "range": 300.0, "projectile_speed": 900.0, "move_speed": 350.0, "xp": 95.0, "gold_min": 37,
		"gold_max": 43, "level": 3}))
	_add("elder_cinder_wyrm", _merged(neu, {"name": "Magma Colossus", "hull": 40.0, "hp": 2000.0, "hp_regen": 2.0,
		"mana": 500.0, "armor": 4.0, "magic_resist": 0.3, "dmg_min": 62.0, "dmg_max": 68.0, "attack_point": 0.5,
		"backswing": 0.5, "acquire": 300.0, "range": 300.0, "projectile_speed": 1500.0, "move_speed": 300.0,
		"xp": 124.0, "gold_min": 76, "gold_max": 80, "level": 6}))

	# Heroes. Galewarden: a ranged agility archer (stats follow the classic ranged-agility carry template).
	_add("galewarden", {"name": "Galewarden", "kind": K.HERO, "hull": 24.0, "hp": SimConst.HERO_BASE_HP,
		"hp_regen": 0.25, "mana": SimConst.HERO_BASE_MANA, "mana_regen": 0.0, "armor": 0.0,
		"magic_resist": SimConst.HERO_BASE_MAGIC_RESIST, "dmg_min": 27.0, "dmg_max": 34.0, "bat": 1.7,
		"attack_speed": 100.0, "attack_point": 0.5, "backswing": 0.55, "acquire": 800.0, "range": 625.0,
		"projectile_speed": 1250.0, "move_speed": 300.0, "turn_rate": 0.7, "vision_day": 1800.0, "vision_night": 800.0,
		"xp": 0.0, "primary": "agi", "str": 16.0, "str_gain": 1.9, "agi": 24.0, "agi_gain": 2.8, "int": 15.0,
		"int_gain": 1.4, "abilities": ["frost_quiver", "gale_shot", "hunters_focus", "arrow_storm"],
		"model": "hero"})

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
	_abilities["frost_quiver"] = {"id": "frost_quiver", "name": "Frost Quiver", "behavior": "autocast_attack",
		"key": "Q", "max_level": 4, "mana": [12, 12, 12, 12], "cooldown": [0, 0, 0, 0], "cast_point": 0.0,
		"range": 0, "values": {"bonus_damage": [8, 16, 24, 32], "slow": [0.12, 0.24, 0.36, 0.48], "duration": [1.5, 1.5, 1.5, 1.5]},
		"desc": "Arrows of frost slow the target. Autocast, or cast on an enemy to fire one without drawing creep attention."}
	_abilities["gale_shot"] = {"id": "gale_shot", "name": "Gale Shot", "behavior": "point", "key": "W",
		"max_level": 4, "mana": [90, 90, 90, 90], "cooldown": [16, 14, 12, 10], "cast_point": 0.25,
		"range": 1000, "values": {"damage": [70, 130, 190, 250], "width": [150, 150, 150, 150], "speed": [1800, 1800, 1800, 1800],
		"distance": [1000, 1000, 1000, 1000], "knockback": [300, 325, 350, 375], "knockback_time": [0.4, 0.4, 0.4, 0.4]},
		"desc": "Looses a gust-laden arrow in a line, damaging and pushing back every enemy it passes through."}
	_abilities["hunters_focus"] = {"id": "hunters_focus", "name": "Hunter's Focus", "behavior": "passive", "key": "E",
		"max_level": 4, "mana": [0, 0, 0, 0], "cooldown": [0, 0, 0, 0], "cast_point": 0.0, "range": 0,
		"values": {"bonus_range": [40, 80, 120, 160], "agility_pct": [0.06, 0.09, 0.12, 0.15]},
		"desc": "Sharpened senses extend attack range and amplify agility."}
	_abilities["arrow_storm"] = {"id": "arrow_storm", "name": "Arrow Storm", "behavior": "point", "key": "R",
		"max_level": 3, "required_level": [6, 12, 18], "mana": [150, 175, 200], "cooldown": [70, 60, 50],
		"cast_point": 0.35, "range": 900, "values": {"radius": [325, 325, 325], "volleys": [4, 4, 4], "interval": [0.5, 0.5, 0.5],
		"damage": [60, 95, 130], "slow": [0.3, 0.35, 0.4], "slow_duration": [1.0, 1.0, 1.0]},
		"desc": "Darkens the sky with arrows: volleys strike an area, damaging and slowing enemies inside."}

# ---- Items ----------------------------------------------------------------------------------------------------------
## Item data from items.txt. "stats": passive bonuses; "use": active effect; "recipe": components (recipe scroll cost
## is the item cost minus the components).

static func _it(id: String, name: String, cost: int, d: Dictionary) -> void:
	var it := {"id": id, "name": name, "cost": cost, "stats": {}, "use": "", "charges": 0, "stock": 0, "cooldown": 0.0,
		"components": [], "recipe_cost": 0, "category": "basics", "consumable": false, "values": {}, "icon": id}
	it.merge(d, true)
	_items[id] = it

static func _build_items() -> void:
	_it("tango", "Grove Leaves", 90, {"use": "tango", "charges": 3, "consumable": true, "category": "consumables",
		"values": {"health_regen": 7.0, "duration": 16.0}})
	_it("salve", "Mending Salve", 100, {"use": "salve", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"health_regen": 30.0, "duration": 13.0}})
	_it("clarity", "Clear Mind Draught", 60, {"use": "clarity", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"mana_regen": 6.0, "duration": 25.0}})
	_it("mango", "Sunfruit", 65, {"use": "mango", "charges": 1, "consumable": true, "category": "consumables",
		"stats": {"hp_regen": 0.4}, "values": {"mana": 100.0}})
	_it("faerie_fire", "Wisp Ember", 65, {"use": "faerie_fire", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 5.0, "stats": {"damage": 2.0}, "values": {"heal": 85.0}})
	_it("tp_scroll", "Town Portal Scroll", 100, {"use": "tp", "charges": 1, "consumable": true, "category": "consumables",
		"values": {"channel": SimConst.TP_CHANNEL}})
	_it("observer_ward", "Watcher Ward", 0, {"use": "ward", "charges": 1, "consumable": true, "category": "consumables",
		"cooldown": 1.0, "values": {"lifetime": 360.0}})
	_it("branch", "Ironwood Twig", 55, {"stats": {"str": 1.0, "agi": 1.0, "int": 1.0}})
	_it("slippers", "Quickstep Slippers", 140, {"stats": {"agi": 3.0}, "category": "attributes"})
	_it("gauntlets", "Bracers of Might", 140, {"stats": {"str": 3.0}, "category": "attributes"})
	_it("mantle", "Scholar's Mantle", 140, {"stats": {"int": 3.0}, "category": "attributes"})
	_it("circlet", "Simple Circlet", 155, {"stats": {"str": 2.0, "agi": 2.0, "int": 2.0}, "category": "attributes"})
	_it("boots_elves", "Elvenstep Band", 450, {"stats": {"agi": 6.0}, "category": "attributes"})
	_it("belt_str", "Warrior's Girdle", 450, {"stats": {"str": 6.0}, "category": "attributes"})
	_it("robe", "Sage's Robe", 450, {"stats": {"int": 6.0}, "category": "attributes"})
	_it("blade_alacrity", "Blade of Swiftness", 1000, {"stats": {"agi": 10.0}, "category": "attributes"})
	_it("blades_attack", "Fang Blades", 450, {"stats": {"damage": 9.0}, "category": "armaments"})
	_it("broadsword", "Broad Cleaver", 1000, {"stats": {"damage": 15.0}, "category": "armaments"})
	_it("gloves", "Hasted Gloves", 450, {"stats": {"attack_speed": 20.0}, "category": "armaments"})
	_it("ring_protection", "Warding Ring", 175, {"stats": {"armor": 2.0}, "category": "armaments"})
	_it("chainmail", "Ringmail", 500, {"stats": {"armor": 4.0}, "category": "armaments"})
	_it("quelling_blade", "Woodsman's Hatchet", 100, {"use": "chop", "cooldown": 4.0, "category": "armaments",
		"values": {"creep_damage_melee": 8.0, "creep_damage_ranged": 4.0, "chop_range": 350.0}})
	_it("ring_regen", "Ring of Renewal", 175, {"stats": {"hp_regen": 1.25}, "category": "misc"})
	_it("sobi_mask", "Calm Mask", 175, {"stats": {"mana_regen": 0.7}, "category": "misc"})
	_it("boots", "Traveler's Boots", 500, {"stats": {"move_speed": 45.0}, "category": "misc"})
	_it("magic_stick", "Spark Rod", 200, {"use": "stick", "cooldown": 17.0, "category": "misc",
		"values": {"max_charges": 10, "restore_per_charge": 15.0, "charge_radius": 1200.0}})
	_it("lifesteal", "Leech Charm", 900, {"stats": {"lifesteal": 0.18}, "category": "misc"})
	# Upgrades
	_it("wraith_band", "Wraith Sigil", 505, {"stats": {"agi": 5.0, "str": 2.0, "int": 2.0, "attack_speed": 6.0, "armor": 1.75},
		"components": ["circlet", "slippers"], "recipe_cost": 210, "category": "upgrades"})
	_it("magic_wand", "Spark Wand", 460, {"use": "stick", "cooldown": 15.0, "stats": {"str": 3.0, "agi": 3.0, "int": 3.0},
		"components": ["magic_stick", "branch", "branch"], "recipe_cost": 150, "category": "upgrades",
		"values": {"max_charges": 20, "restore_per_charge": 15.0, "charge_radius": 1200.0}})
	_it("power_treads", "Strider Treads", 1400, {"stats": {"move_speed": 45.0, "agi": 10.0, "attack_speed": 25.0},
		"components": ["boots", "gloves", "boots_elves"], "recipe_cost": 0, "category": "upgrades"})
	_it("mask_of_madness", "Frenzy Mask", 1900, {"use": "berserk", "cooldown": 16.0, "stats": {"damage": 20.0, "lifesteal": 0.22},
		"components": ["broadsword", "lifesteal"], "recipe_cost": 0, "category": "upgrades",
		"values": {"attack_speed": 100.0, "move_speed_pct": 0.06, "armor_reduction": 7.0, "duration": 6.0, "mana": 25.0}})
	_it("yasha", "Galeblade", 2100, {"stats": {"agi": 16.0, "attack_speed": 15.0, "move_speed_pct": 0.1},
		"components": ["blade_alacrity", "boots_elves"], "recipe_cost": 650, "category": "upgrades"})
	_it("dragon_lance", "Longwind Bow", 2000, {"stats": {"agi": 15.0, "str": 10.0, "range": 130.0},
		"components": ["boots_elves", "boots_elves", "blade_alacrity"], "recipe_cost": 100, "category": "upgrades"})
	# A Longwind Bow's components cost 1900 here; its recipe makes up the remaining 100 gold.
