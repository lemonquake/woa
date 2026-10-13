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
const TALENTS := {"sludge": [0, 0, 0, 1]}

## Item builds: role group "core" (positions 1-3) and "support" (4-5); a few variants each. Buying a finished item buys
## only its missing parts. Starting items come first.
const BUILDS := {
	"blood_ranger": {
		"core": [
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "branch", "branch",
				"magic_wand", "boots", "gloves", "boots_elves", "dragon_lance", "crit_sword", "shock_hammer",
				"spell_shield", "crit_bow", "armor_breaker"],
			["tango", "salve", "slippers", "circlet", "quelling_blade", "wraith_band", "magic_stick", "boots", "gloves",
				"boots_elves", "magic_wand", "gold_glove", "yasha", "dragon_lance", "heavy_sword", "twin_swords",
				"armor_breaker", "spell_shield"],
			["tango", "faerie_fire", "slippers", "circlet", "quelling_blade", "wraith_band", "boots", "magic_stick",
				"gloves", "boots_elves", "mask_of_madness", "dragon_lance", "crit_sword", "sure_hit_staff",
				"spell_shield", "crit_bow"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "wraith_band",
				"push_staff", "slip_boots", "dragon_lance", "spell_shield"],
		],
	},
	"ezee": {
		"core": [
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "branch", "branch", "magic_stick",
				"magic_wand", "slip_boots", "stun_club", "spike_armor", "spell_shield", "stun_blade", "armor_breaker"],
			["tango", "salve", "gauntlets", "quelling_blade", "circlet", "tough_band", "magic_stick", "boots",
				"magic_wand", "belt_str", "gloves", "block_shield", "cleave_axe", "stun_club", "spell_shield",
				"stun_blade"],
		],
		"support": [
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"medic_kit", "root_staff", "push_staff", "spell_shield"],
		],
	},
	"sludge": {
		"core": [
			["tango", "salve", "gauntlets", "branch", "branch", "magic_stick", "circlet", "tough_band", "magic_wand",
				"slip_boots", "jump_knife", "spike_armor", "spell_shield", "upgrade_staff"],
			["tango", "salve", "gauntlets", "branch", "branch", "magic_stick", "boots", "magic_wand", "block_shield",
				"jump_knife", "slip_boots", "spell_shield", "halberd", "upgrade_staff"],
		],
		"support": [
			["tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots", "jump_knife",
				"root_staff", "medic_kit", "spell_shield", "upgrade_staff"],
			["tango", "tango", "salve", "branch", "branch", "magic_stick", "boots", "magic_wand", "slip_boots",
				"push_staff", "jump_knife", "upgrade_gem", "spell_shield"],
		],
	},
}

## Items a bot buys first if the game calls for them (checked at 8, 15 and 25 minutes).
## spell_shield: the enemy has two or more disablers; spike_armor: a fed enemy right-clicker hits us (strength heroes).
const SITUATIONAL := ["spell_shield", "spike_armor", "push_staff"]

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
	return 0.3

## Whether the hero is fragile and right-clicks from range (keeps back in fights).
static func backliner(hero: String) -> bool:
	return hero == "blood_ranger"

## The hero's ultimate.
static func ultimate(h: SimUnit) -> String:
	return String(h.abilities[3]) if h.abilities.size() > 3 else ""

static func ult_ready(w: SimWorld, h: SimUnit) -> bool:
	var ult := ultimate(h)
	return ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) <= 0.0 \
		and h.mana >= w.abilities.ability_mana(h, ult)

## Average right-click damage per second against `t` (attack class, armor).
static func dps(w: SimWorld, h: SimUnit, t: SimUnit) -> float:
	var avg := (h.dmg_min + h.dmg_max) * 0.5 + h.bonus_damage
	var snap := {"hero": true, "class": int(h.def.get("attack_class", 0))}
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
	var dmg := burst(w, h, vs) + dps(w, h, vs) * 5.0
	var ehp := h.hp / maxf(0.2, C.armor_multiplier(h.armor) * 0.5 + (1.0 - h.magic_resist) * 0.5)
	return sqrt(maxf(1.0, dmg) * maxf(1.0, ehp))

## Level or item moments when the hero gets much stronger (the bot says so and its team may call a fight).
static func power_spike(h: SimUnit, item_id: String) -> bool:
	if item_id in ["jump_knife", "spell_shield", "shock_hammer", "armor_breaker", "cleave_axe", "dragon_lance",
			"spike_armor", "upgrade_staff", "mask_of_madness", "yasha", "crit_bow", "stun_club", "stun_blade", "hex_staff",
			"sure_hit_staff", "twin_swords", "halberd"]:
		return true
	return false
