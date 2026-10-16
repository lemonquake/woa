class_name SimBotKits
extends RefCounted
## What a bot knows about each hero: the roles it can play, its skill and talent order, a few item builds per role
## (the bot's memory picks among them and learns which works), how much damage its spells can do right now, how well it
## disables and escapes, and when it is strong (power spikes). The combos themselves live in SimBot (they issue orders).
##
## Roles are Dota's positions: 1 safe lane carry, 2 mid, 3 off lane, 4 roaming support (off lane), 5 safe lane support.

const C = preload("res://src/sim/sim_const.gd")

## Roles each hero plays, best first.
const ROLES := {
	"blood_ranger": [1, 2, 3, 5],
	"ezee": [3, 2, 1, 4],
	"sludge": [4, 2, 3, 5, 1],
	"azrin": [2, 4, 5, 1],
	"froster": [2, 5, 4, 3],
	"caziel": [1, 2, 3],
	"tock": [5, 4, 2],
	"kragg": [3, 4, 2, 1],
	"roydo": [3, 2, 4, 1],
	"blau": [1, 2, 3],
	"azrael": [1, 2, 3],
}
## Lane by role, from the team's side: "safe" (long lane with the tier 1 far out), "mid", "off".
const ROLE_LANE := {1: "safe", 2: "mid", 3: "off", 4: "off", 5: "safe"}

const SKILLS := {
	"blood_ranger": ["masterful_archery", "gale_impact", "burst_shot", "masterful_archery", "burst_shot",
		"blood_ranger_ult", "burst_shot", "burst_shot", "masterful_archery", "masterful_archery", "blood_ranger_ult",
		"gale_impact", "gale_impact", "gale_impact", "blood_ranger_ult"],
	"ezee": ["dark_stomp", "tainted_touch", "leap_strike", "dark_stomp", "dark_stomp", "unholy_might", "dark_stomp",
		"leap_strike", "leap_strike", "leap_strike", "unholy_might", "tainted_touch", "tainted_touch", "tainted_touch",
		"unholy_might"],
	# Stench early for lane control, Shuriken Hook to level 4 next, Blubber last (a common Dota Pudge order)
	"sludge": ["shuriken_hook", "stench", "stench", "blubber", "stench", "chomp", "stench", "shuriken_hook",
		"shuriken_hook", "shuriken_hook", "chomp", "blubber", "blubber", "blubber", "chomp"],
	# the stun first, the javelin to level 4 next, the spirits last
	"azrin": ["touch_of_ember", "fiery_javelin", "spirit_of_fire", "touch_of_ember", "touch_of_ember", "divine_smite",
		"touch_of_ember", "fiery_javelin", "fiery_javelin", "fiery_javelin", "divine_smite", "spirit_of_fire",
		"spirit_of_fire", "spirit_of_fire", "divine_smite"],
	# the cone first (lane harass and farm), the curse, the heart late
	"froster": ["breath_of_cold", "ice_pulse", "breath_of_cold", "frost_heart", "breath_of_cold", "endless_winter",
		"breath_of_cold", "ice_pulse", "ice_pulse", "ice_pulse", "endless_winter", "frost_heart", "frost_heart",
		"frost_heart", "endless_winter"],
	# poison and the dagger together early, the shadows for safety
	"caziel": ["swift_dagger", "sweet_poison", "swift_dagger", "master_of_shadows", "swift_dagger", "death_order",
		"swift_dagger", "sweet_poison", "sweet_poison", "sweet_poison", "death_order", "master_of_shadows",
		"master_of_shadows", "master_of_shadows", "death_order"],
	# the bolt first (harass, and it slows enemy cooldowns), Rewind early to live, the field and the passive next
	"tock": ["time_bolt", "fast_forward", "time_bolt", "rewind", "time_bolt", "stop_time", "time_bolt", "slow_field",
		"slow_field", "quick_hands", "stop_time", "slow_field", "slow_field", "quick_hands", "quick_hands",
		"quick_hands", "stop_time", "fast_forward", "fast_forward", "fast_forward", "rewind", "rewind", "rewind"],
	# the grip to level 4 with a point in Overload, Overload next, Repel last (Magnetize is innate)
	"kragg": ["iron_grip", "overload", "repel", "iron_grip", "iron_grip", "magnet_field", "iron_grip", "overload",
		"overload", "overload", "magnet_field", "repel", "repel", "repel", "magnet_field"],
	# the grip first (it throws and stuns), Void Rush for fights and escapes, the skin late
	"roydo": ["grip_of_the_ruler", "void_rush", "grip_of_the_ruler", "dark_matter_skin", "grip_of_the_ruler", "anomaly",
		"grip_of_the_ruler", "void_rush", "void_rush", "void_rush", "anomaly", "dark_matter_skin", "dark_matter_skin",
		"dark_matter_skin", "anomaly"],
	# Bounce Shot first (harass and farm), the trap for safety, boulders after; turrets at 6 / 12 / 18
	"blau": ["bounce_shot", "lay_trap", "bounce_shot", "summon_boulders", "bounce_shot", "place_turret", "bounce_shot",
		"lay_trap", "lay_trap", "lay_trap", "place_turret", "summon_boulders", "summon_boulders", "summon_boulders",
		"place_turret"],
	# Azrael: Soul Tap first (farm and trades), the door early for escapes, Death Scythe next
	"azrael": ["soul_tap", "death_scythe", "soul_tap", "door_of_the_end", "soul_tap", "divine_darkness", "soul_tap",
		"death_scythe", "death_scythe", "death_scythe", "divine_darkness", "door_of_the_end", "door_of_the_end",
		"door_of_the_end", "divine_darkness"],
}
## Supports skill the disable / save first.
const SUPPORT_SKILLS := {
	"sludge": ["shuriken_hook", "stench", "shuriken_hook", "blubber", "shuriken_hook", "chomp", "shuriken_hook",
		"stench", "stench", "stench", "chomp", "blubber", "blubber", "blubber", "chomp"],
	"ezee": ["dark_stomp", "leap_strike", "dark_stomp", "tainted_touch", "dark_stomp", "unholy_might", "dark_stomp",
		"leap_strike", "leap_strike", "leap_strike", "unholy_might", "tainted_touch", "tainted_touch", "tainted_touch",
		"unholy_might"],
}
## Talent side per tier (0 left, 1 right), for heroes with a talent tree.
const TALENTS := {"blood_ranger": [1, 1, 0, 1], "ezee": [0, 0, 1, 0], "sludge": [0, 0, 0, 1], "azrin": [0, 0, 1, 0], "froster": [0, 0, 1, 0], "caziel": [0, 0, 0, 0],
	"tock": [0, 1, 0, 0], "kragg": [0, 1, 0, 0], "roydo": [1, 1, 0, 0], "blau": [1, 0, 1, 0],
	"azrael": [0, 1, 1, 0]}

## Item builds: role group "core" (positions 1-3) and "support" (4-5); a few variants each. Buying a finished item buys
## only its missing parts. Starting items come first.
const BUILDS := {
	"blood_ranger": {
		"core": [
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "branch", "branch",
				"magic_wand", "boots", "gloves", "boots_elves", "dragon_lance", "crit_sword", "shock_hammer",
				"spell_shield", "crit_bow", "armor_breaker", "moth_blade"],
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots", "gloves",
				"boots_elves", "magic_wand", "gold_glove", "yasha", "dragon_lance", "heavy_sword", "twin_swords",
				"armor_breaker", "spell_shield", "storm_hammer"],
			["tango", "faerie_fire", "slippers", "circlet", "quelling_blade", "wraith_band", "boots", "magic_stick",
				"gloves", "boots_elves", "mask_of_madness", "dragon_lance", "crit_sword", "sure_hit_staff",
				"spell_shield", "crit_bow"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "wraith_band",
				"push_staff", "slip_boots", "dragon_lance", "long_lens", "spell_shield", "guard_boots"],
		],
	},
	"ezee": {
		"core": [
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "branch", "branch", "magic_stick",
				"magic_wand", "slip_boots", "stun_club", "spike_armor", "spell_shield", "stun_blade", "battle_armor",
				"giant_heart"],
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "magic_stick", "boots",
				"magic_wand", "belt_str", "gloves", "block_shield", "cleave_axe", "stun_club", "spell_shield",
				"stun_blade"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"medic_kit", "root_staff", "small_shield", "team_shield", "push_staff", "guard_boots", "spell_shield"],
		],
	},
	"azrin": {
		"core": [
			["tango", "salve", "mantle", "circlet", "smart_band", "branch", "branch", "magic_stick", "boots",
				"magic_wand", "mana_boots", "spell_sword", "dagon", "push_staff", "kugmo_atuli", "time_crystal",
				"hex_staff", "refresh_stone"],
			["tango", "salve", "mantle", "circlet", "smart_band", "magic_stick", "boots", "magic_wand", "slip_boots",
				"spell_sword", "igit_atuli", "silence_staff", "hex_staff", "spell_shield"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "mana_boots",
				"push_staff", "spell_sword", "root_staff", "net_staff", "guard_boots", "hex_staff"],
		],
	},
	"froster": {
		"core": [
			["tango", "salve", "mantle", "circlet", "smart_band", "branch", "branch", "magic_stick", "boots",
				"magic_wand", "mana_boots", "spell_sword", "push_staff", "kugmo_atuli", "time_crystal", "frost_plate",
				"refresh_stone"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "mana_boots",
				"push_staff", "medic_kit", "war_drum", "spell_sword", "net_staff", "guard_boots", "spell_shield"],
		],
	},
	"caziel": {
		"core": [
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots",
				"magic_wand", "gloves", "boots_elves", "mask_of_madness", "crit_sword", "yasha", "spell_shield",
				"armor_breaker", "moth_blade", "leech_blade"],
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "boots", "magic_stick",
				"gloves", "boots_elves", "magic_wand", "sneak_blade", "crit_sword", "spell_shield", "armor_breaker",
				"battle_armor"],
		],
	},
	"tock": {
		"core": [
			["tango", "salve", "mantle", "circlet", "smart_band", "branch", "branch", "magic_stick", "boots",
				"magic_wand", "mana_boots", "spell_sword", "long_lens", "time_crystal", "refresh_stone", "hex_staff"],
		],
		"support": [
			["tango", "tango", "salve", "clarity", "branch", "branch", "magic_stick", "boots", "magic_wand", "mana_boots",
				"war_drum", "long_lens", "time_crystal", "guard_boots", "refresh_stone"],
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "mana_boots",
				"push_staff", "long_lens", "net_staff", "time_crystal", "guard_boots"],
		],
	},
	"kragg": {
		"core": [
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "magic_stick", "boots",
				"magic_wand", "slip_boots", "jump_knife", "spell_shield", "crash_knife", "battle_armor", "giant_heart"],
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "magic_stick", "boots",
				"magic_wand", "slip_boots", "block_shield", "team_shield", "jump_knife", "spell_shield", "frost_plate"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"small_shield", "jump_knife", "team_shield", "spell_shield", "crash_knife"],
		],
	},
	# Roydo: an initiator who wants to be hit (Dark Matter Skin): health, a way in, Spike Armor, Spell Shield
	"roydo": {
		"core": [
			["tango", "salve", "mantle", "circlet", "smart_band", "gauntlets", "magic_stick", "boots", "magic_wand",
				"slip_boots", "jump_knife", "spike_armor", "spell_shield", "giant_heart", "refresh_stone"],
			["tango", "salve", "mantle", "circlet", "smart_band", "magic_stick", "boots", "magic_wand", "mana_boots",
				"jump_knife", "block_shield", "spike_armor", "spell_shield", "hex_staff"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"jump_knife", "team_shield", "spike_armor", "spell_shield"],
		],
	},
	# Azrael: an aggressive melee carry: attack speed, a way in, cleave on top of Soul Tap's, Spell Shield
	"azrael": {
		"core": [
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots",
				"magic_wand", "gloves", "boots_elves", "mask_of_madness", "jump_knife", "shock_hammer", "spell_shield",
				"armor_breaker", "crit_sword", "moth_blade"],
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots", "gloves",
				"boots_elves", "magic_wand", "yasha", "cleave_axe", "jump_knife", "spell_shield", "armor_breaker",
				"crit_sword"],
		],
	},
	# Blau: attack speed and range first, the Upgrade Staff for Pilot Turret, then crits
	"blau": {
		"core": [
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots", "gloves",
				"boots_elves", "magic_wand", "dragon_lance", "mask_of_madness", "upgrade_staff", "crit_sword",
				"spell_shield", "crit_bow", "armor_breaker"],
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots", "gloves",
				"boots_elves", "dragon_lance", "yasha", "upgrade_staff", "sure_hit_staff", "spell_shield", "crit_bow"],
		],
	},
	"sludge": {
		"core": [
			["tango", "salve", "gauntlets", "branch", "branch", "magic_stick", "circlet", "tough_band", "magic_wand",
				"slip_boots", "jump_knife", "spike_armor", "spell_shield", "upgrade_staff", "crash_knife", "giant_heart"],
			["tango", "salve", "gauntlets", "branch", "branch", "magic_stick", "boots", "magic_wand", "block_shield",
				"jump_knife", "slip_boots", "spell_shield", "halberd", "upgrade_staff"],
		],
		"support": [
			["tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots", "jump_knife",
				"root_staff", "medic_kit", "war_drum", "spell_shield", "team_shield", "upgrade_staff"],
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"push_staff", "jump_knife", "upgrade_gem", "spell_shield"],
		],
	},
}


static func roles(hero: String) -> Array:
	return ROLES.get(hero, [1, 2, 3, 4, 5])

static func is_support(role: int) -> bool:
	return role >= 4

static func skill_order(hero: String, role: int) -> Array:
	if is_support(role) and SUPPORT_SKILLS.has(hero):
		return SUPPORT_SKILLS[hero]
	return SKILLS.get(hero, [])

static func talent_side(hero: String, tier: int) -> int:
	var t: Array = TALENTS.get(hero, [])
	return int(t[tier]) if tier < t.size() else 0

static func builds(hero: String, role: int) -> Array:
	var b: Dictionary = BUILDS.get(hero, {})
	var grp := "support" if is_support(role) else "core"
	if not b.has(grp):
		grp = "core"
	return b.get(grp, [["tango", "salve", "boots"]])

static func build_key(hero: String, role: int) -> String:
	return "%s:%s" % [hero, "support" if is_support(role) else "core"]

## How well the hero holds enemies in place (0..1): picks targets for ganks and team fights.
static func disable_power(hero: String) -> float:
	match hero:
		"sludge":
			return 0.9
		"ezee":
			return 0.6
		"blood_ranger":
			return 0.25
		"azrin":
			return 0.55
		"froster":
			return 0.7
		"caziel":
			return 0.15
		"tock":
			return 0.8
		"kragg":
			return 0.85
		"roydo":
			return 0.75
		"blau":
			return 0.45
		"azrael":
			return 0.3
	return 0.3

## Whether the hero is fragile and right-clicks from range (keeps back in fights).
static func backliner(hero: String) -> bool:
	return hero == "blood_ranger" or hero == "azrin" or hero == "froster" or hero == "tock" or hero == "blau"

## The hero's ultimate.
static func ultimate(h: SimUnit) -> String:
	return SimData.ultimate_of(h.abilities)

static func ult_ready(w: SimWorld, h: SimUnit) -> bool:
	var ult := ultimate(h)
	return ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) <= 0.0 \
		and h.mana >= w.abilities.ability_mana(h, ult)

## Average right-click damage per second against `t` (attack class, armor).
static func dps(w: SimWorld, h: SimUnit, t: SimUnit) -> float:
	var avg := (h.dmg_min + h.dmg_max) * 0.5 + h.bonus_damage
	var snap := {"hero": true, "class": h.weapon, "element": h.element}
	var mult := w.combat.attack_class_multiplier(snap, t) * C.armor_multiplier(t.armor) if t != null else 1.0
	return avg * mult / maxf(0.2, h.attack_interval())

## Damage the hero's ready spells could deal to `t` right now (after armor and magic resistance, a rough average:
## skill shots count at their usual hit rate).
static func burst(w: SimWorld, h: SimUnit, t: SimUnit) -> float:
	var ab := w.abilities
	var mr := 1.0 - (t.magic_resist if t != null else 0.25)
	var arm := C.armor_multiplier(t.armor) if t != null else 1.0
	var mana := h.mana
	var total := 0.0
	var ready := func(aid: String) -> bool:
		if h.ability_level_of(aid) <= 0 or ab.cooldown_left(h, aid) > 0.0:
			return false
		var cost := ab.ability_mana(h, aid)
		if cost > mana:
			return false
		mana -= cost
		return true
	match String(h.def.id):
		"blood_ranger":
			if ready.call("gale_impact"):
				total += ab.val(h, "gale_impact", "damage") * 1.1 * mr * 0.7
			if ready.call("burst_shot"):
				var avg := (h.dmg_min + h.dmg_max) * 0.5 + h.bonus_damage
				total += 30.0 * ab.val(h, "burst_shot", "attack_pct") * avg * arm * 0.35
			if h.ability_level_of("blood_ranger_ult") > 0 and ab.cooldown_left(h, "blood_ranger_ult") <= 0.0:
				total += dps(w, h, t) * 3.0
		"ezee":
			if ready.call("dark_stomp"):
				total += (ab.val(h, "dark_stomp", "damage") + ab.val(h, "dark_stomp", "impact_damage") * 0.5) * mr
			if ready.call("leap_strike"):
				total += ab.val(h, "leap_strike", "damage") + ab.val(h, "leap_strike", "str_mult") * h.str_total
			if ready.call("tainted_touch"):
				total += ab.val(h, "tainted_touch", "bonus_damage") * mr * 3.0
			if h.ability_level_of("unholy_might") > 0 and ab.cooldown_left(h, "unholy_might") <= 0.0:
				total += h.max_hp * 0.08
		"azrin":
			if ready.call("touch_of_ember"):
				total += (ab.val(h, "touch_of_ember", "damage") + ab.val(h, "touch_of_ember", "explode_damage")) * mr
			if ready.call("fiery_javelin"):
				total += ab.val(h, "fiery_javelin", "burn_dps") * ab.val(h, "fiery_javelin", "burn_duration") * mr * 0.7
			if h.ability_level_of("spirit_of_fire") > 0:
				total += ab.spirits(h) * ab.val(h, "spirit_of_fire", "burn") * mr
			if ready.call("divine_smite"):
				total += (ab.val(h, "divine_smite", "damage") + ab.val(h, "divine_smite", "int_mult") * h.int_total) * mr
			total *= 1.0 + h.magic_amp
		"froster":
			var amp := 1.0 + (ab.val(h, "ice_pulse", "defense_loss") if h.ability_level_of("ice_pulse") > 0 else 0.0)
			if ready.call("breath_of_cold"):
				total += ab.val(h, "breath_of_cold", "damage") * mr
			if ready.call("ice_pulse"):
				total += ab.val(h, "ice_pulse", "blast_damage") * mr
			if ready.call("endless_winter"):
				total += ab.val(h, "endless_winter", "dps") * 4.0 * mr
			total += w.abilities.frost_hearts(h) * ab.val(h, "frost_heart", "burst") * mr
			total *= (1.0 + h.magic_amp) * amp
		"caziel":
			if ready.call("swift_dagger"):
				var avg2 := (h.dmg_min + h.dmg_max) * 0.5 + h.bonus_damage
				total += (avg2 + ab.val(h, "swift_dagger", "bonus_damage")) * C.armor_multiplier(
					(t.armor if t != null else 3.0) - ab.val(h, "swift_dagger", "armor_cut"))
			if h.ability_level_of("sweet_poison") > 0:
				total += ab.val(h, "sweet_poison", "chance") * 5.0 * ab.val(h, "sweet_poison", "dps") * 2.0 * mr * 0.5
		"tock":
			if ready.call("time_bolt"):
				total += ab.val(h, "time_bolt", "damage") * mr * 0.8
			if ready.call("stop_time"):
				total += dps(w, h, t) * 2.0
			total *= 1.0 + h.magic_amp
		"kragg":
			var ch := ab.kits2.charges(t) if t != null else 0
			if ready.call("iron_grip"):
				total += ab.val(h, "iron_grip", "damage") * mr
				ch += 2
			if ready.call("repel"):
				total += ab.val(h, "repel", "damage") * mr
			if h.ability_level_of("overload") > 0:
				# about one burst in a few seconds of hitting
				total += ab.val(h, "overload", "damage") * mr * 4.0 / maxf(3.0, ab.val(h, "overload", "every"))
			if ready.call("magnet_field"):
				total += ab.val(h, "magnet_field", "end_damage") * mr
			total *= (1.0 + h.magic_amp) * (1.0 + ab.kits2.amp_per_charge(h) * mini(ch, 4))
		"roydo":
			if ready.call("grip_of_the_ruler"):
				total += ab.val(h, "grip_of_the_ruler", "damage") * mr
				total += dps(w, h, t) * ab.val(h, "grip_of_the_ruler", "stun")
			if h.ability_level_of("dark_matter_skin") > 0:
				total += 200.0 * ab.val(h, "dark_matter_skin", "chance") * ab.val(h, "dark_matter_skin", "reflect") * 4.0 * mr
			if ready.call("anomaly"):
				total += ab.val(h, "anomaly", "damage") * 4.0 * arm
			total *= 1.0 + h.magic_amp
		"azrael":
			# Soul Tap's slash: a few souls' worth (the target and the creeps round it), then Death Scythe on the blows
			# that follow and the door's blast
			if ready.call("soul_tap"):
				total += (ab.val(h, "soul_tap", "per_unit") * 4.0 + ab.val(h, "soul_tap", "per_hero")) * arm
			if h.ability_level_of("death_scythe") > 0:
				total += ab.val(h, "death_scythe", "chance") * ab.val(h, "death_scythe", "bonus") * 4.0
			if ready.call("door_of_the_end"):
				total += ab.val(h, "door_of_the_end", "damage") * mr * 0.7
			if ready.call("divine_darkness"):
				total += dps(w, h, t) * 2.5
		"blau":
			# the bullet usually passes its target twice (out and back off a tree, boulder or wall)
			if ready.call("bounce_shot"):
				total += ab.val(h, "bounce_shot", "damage") * mr * 1.7
			# boulders hit, then wall the target in for a few more of his shots
			if ready.call("summon_boulders"):
				total += ab.val(h, "summon_boulders", "damage") * mr * 0.8 + dps(w, h, t) * 1.5
			if ready.call("place_turret"):
				total += dps(w, h, t) * ab.val(h, "place_turret", "damage_pct") * 1.13 * 6.0
			total *= 1.0 + h.magic_amp
		"sludge":
			if ready.call("shuriken_hook"):
				total += ab.val(h, "shuriken_hook", "damage") * 0.6
			if ready.call("chomp"):
				var lv := h.ability_level_of("chomp")
				total += (ab.val(h, "chomp", "dps") + ab.val(h, "chomp", "str_mult") * h.str_total) \
					* ab.val(h, "chomp", "duration") * mr
				if lv > 0:
					total += dps(w, h, t) * 1.0
			if h.ability_level_of("stench") > 0:
				total += ab.val(h, "stench", "dps") * 3.0 * mr
	return total

## A rough fighting strength over the next few seconds: damage it can deal (spells plus five seconds of attacks)
## times the punishment it can take (health over the incoming damage multiplier).
static func power(w: SimWorld, h: SimUnit, vs: SimUnit) -> float:
	if h == null or not h.alive:
		return 0.0
	# remembered for the rest of the tick: bots and both brains ask for the same pairs many times
	if w._power_tick != w.tick:
		w._power_cache.clear()
		w._power_tick = w.tick
	var key := h.id * 100000 + (vs.id if vs != null else 99999)
	var got = w._power_cache.get(key)
	if got != null:
		return got
	var dmg := burst(w, h, vs) + dps(w, h, vs) * 5.0
	var ehp := h.hp / maxf(0.2, C.armor_multiplier(h.armor) * 0.5 + (1.0 - h.magic_resist) * 0.5)
	var pw := sqrt(maxf(1.0, dmg) * maxf(1.0, ehp))
	w._power_cache[key] = pw
	return pw

## Level or item moments when the hero gets much stronger (the bot says so and its team may call a fight).
static func power_spike(h: SimUnit, item_id: String) -> bool:
	if item_id in ["jump_knife", "spell_shield", "shock_hammer", "armor_breaker", "cleave_axe", "dragon_lance",
			"spike_armor", "upgrade_staff", "mask_of_madness", "yasha", "crit_bow", "stun_club", "stun_blade", "hex_staff",
			"sure_hit_staff", "twin_swords", "halberd", "spell_sword", "kugmo_atuli", "igit_atuli"]:
		return true
	return false
