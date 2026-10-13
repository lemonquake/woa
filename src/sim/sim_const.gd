class_name SimConst
extends RefCounted
## Rules constants for the Warriors of Aether simulation. Values follow Dota 2 (7.3x game data where available, see
## docs/MECHANICS.md for each source); anything marked APPROX is a best-known value that could not be checked against
## the game files and is kept in one place so it can be corrected.
##
## Units: distances in game units (1 unit = 1 cm when rendered), time in seconds, angles in radians.

const TICK_RATE := 30
const DT := 1.0 / 30.0

# ---- Teams --------------------------------------------------------------------------------------------------------
const DAWN := 0
const DUSK := 1
const NEUTRAL := 2
const TEAM_NAMES := ["Ancient Light", "Black Sun", "Neutral"]

# ---- Unit kinds -----------------------------------------------------------------------------------------------------
enum Kind { HERO, CREEP_MELEE, CREEP_RANGED, CREEP_SIEGE, CREEP_FLAG, NEUTRAL_CREEP, TOWER, BARRACKS, ANCIENT, FILLER, FOUNTAIN, WARD, COURIER }

## Attack classes (Liquipedia "Attack Damage": Default, Runty, Piercing, Reinforced).
enum AttackClass { DEFAULT, RUNTY, PIERCING, REINFORCED }
## Defence classes: heroes, everything else, buildings.
enum DefenseClass { HERO, NON_HERO, STRUCTURE }

## damage multiplier [attack class][defence class]. Default vs structure depends on whether the attacker is a hero.
const ATTACK_MATRIX := [
	[1.0, 1.0, 0.7],     # DEFAULT (non-hero attacker; heroes use HERO_VS_STRUCTURE)
	[0.75, 1.0, 0.7],    # RUNTY      (melee lane creeps: creep_irresolute -25% vs heroes)
	[0.5, 1.5, 0.35],    # PIERCING   (ranged lane creeps: creep_piercing)
	[1.0, 1.0, 2.5],     # REINFORCED (siege creeps, towers: creep_siege +150% vs buildings)
]
const HERO_VS_STRUCTURE := 0.5

## Siege creeps take reduced damage (creep_siege incoming penalties).
const SIEGE_TAKEN_FROM_HERO := 0.5
const SIEGE_TAKEN_FROM_BASIC := 0.7

enum DamageType { PHYSICAL, MAGICAL, PURE }

# ---- Orders ---------------------------------------------------------------------------------------------------------
enum Order { NONE, MOVE, ATTACK_UNIT, ATTACK_MOVE, HOLD, STOP, CAST_NO_TARGET, CAST_POINT, CAST_UNIT, MOVE_TO_UNIT,
	DROP_ITEM, PICKUP_ITEM, GIVE_ITEM, PICKUP_ORB }

# ---- Movement & attack ---------------------------------------------------------------------------------------------
## A unit only starts walking, attacking or casting when its target is within this angle of its facing (11.5 deg).
const FACING_TOLERANCE := deg_to_rad(11.5)
## Turn rate is radians per 0.03 s in the data files.
const TURN_RATE_PERIOD := 0.03
const MOVE_SPEED_MIN := 100.0
const MOVE_SPEED_MAX := 550.0
const ATTACK_SPEED_MIN := 20.0
const ATTACK_SPEED_MAX := 700.0
const BASE_ATTACK_SPEED := 100.0
## Once an attack has started, the target may move this far beyond attack range before the windup is cancelled.
const ATTACK_RANGE_BUFFER := 250.0
## Attacks against a unit on higher ground miss this often (APPROX: 25%).
const UPHILL_MISS := 0.25

# ---- Hulls (DOTA_HULL_SIZE_*) ---------------------------------------------------------------------------------------
const HULL := {"small": 8.0, "regular": 16.0, "siege": 16.0, "hero": 24.0, "huge": 80.0, "filler": 96.0,
	"tower": 144.0, "barracks": 144.0, "building": 298.0, "ward": 8.0}

# ---- Attributes (7.3x) ------------------------------------------------------------------------------------------------
const STR_HP := 22.0
const STR_HP_REGEN := 0.1
const AGI_ARMOR := 1.0 / 6.0
const AGI_ATTACK_SPEED := 1.0
const INT_MANA := 12.0
const INT_MANA_REGEN := 0.05
const INT_MAGIC_RESIST := 0.001
const HERO_BASE_HP := 120.0
const HERO_BASE_MANA := 75.0
const HERO_BASE_MAGIC_RESIST := 0.25
## Hero levels at which talent tiers open (one ability point picks one of the two talents in a tier).
const TALENT_LEVELS := [10, 15, 20, 25]

# ---- Experience -------------------------------------------------------------------------------------------------------
## Total XP needed to reach level i+1 (index 0 = level 1).
const XP_TABLE := [0, 240, 640, 1160, 1760, 2440, 3200, 4000, 4900, 5900, 7000, 8200, 9500, 10900, 12400, 14000, 15700,
	17500, 19400, 21400, 23600, 26000, 28600, 31400, 34400, 38400, 43400, 49400, 56400, 64400]
const MAX_LEVEL := 30
const XP_RADIUS := 1500.0
const DENY_XP_FACTOR := 0.5
## Hero kill XP: (base + factor * victim total XP) / heroes sharing (APPROX).
const HERO_KILL_XP_BASE := 40.0
const HERO_KILL_XP_FACTOR := 0.13

# ---- Gold ---------------------------------------------------------------------------------------------------------------
const STARTING_GOLD := 600
## Passive gold per minute at given game minutes (interpolated). 0:00 value APPROX; later points from the wiki table.
const PASSIVE_GPM := [[0.0, 90.0], [12.0, 94.8], [30.0, 99.8], [45.0, 105.5], [62.0, 112.8], [87.0, 120.5], [112.0, 129.0]]
const HERO_KILL_GOLD_BASE := 110.0          # APPROX
const HERO_KILL_GOLD_PER_LEVEL := 8.0       # APPROX
const FIRST_BLOOD_GOLD := 150               # APPROX
const ASSIST_RADIUS := 1200.0               # APPROX
const ASSIST_GOLD_BASE := 40.0              # APPROX
const ASSIST_GOLD_SCALING := 140.0          # APPROX
const ASSIST_GOLD_NETWORTH := 0.037         # APPROX
const KILL_TIME_WINDOW := 20.0              # APPROX: hero damage this recent counts for kill credit
const DEATH_GOLD_DIVISOR := 40.0            # APPROX: gold lost on death = net worth / 40 (unreliable only)
const BUYBACK_BASE := 200
const BUYBACK_NETWORTH_DIVISOR := 13.0
const BUYBACK_COOLDOWN := 480.0

## Respawn time by level (APPROX, 7.3x shape).
const RESPAWN_TIME := [6, 8, 10, 14, 16, 26, 28, 30, 32, 34, 36, 44, 46, 48, 50, 52, 54, 65, 70, 75, 80, 85, 90, 95, 100,
	100, 100, 100, 100, 100]

# ---- Lane creeps ----------------------------------------------------------------------------------------------------
const WAVE_INTERVAL := 30.0
const CREEP_UPGRADE_INTERVAL := 450.0       # 7:30
const CREEP_MAX_UPGRADES := 30
## Per-upgrade gains (APPROX): [hp, damage, gold, xp]
const CREEP_UPGRADE := {
	"melee": [12.0, 1.0, 1.0, 0.0],
	"ranged": [12.0, 2.0, 1.0, 4.0],
	"super_melee": [19.0, 2.0, 1.0, 0.0],
	"super_ranged": [18.0, 3.0, 1.0, 0.0],
}
const CREEP_AGGRO_RADIUS := 500.0
const CREEP_AGGRO_DURATION := 2.3
const CREEP_AGGRO_COOLDOWN := 3.0
## Lane creeps re-evaluate targets this often while walking (game polls every few frames).
const CREEP_THINK_INTERVAL := 0.1

# ---- Buildings ------------------------------------------------------------------------------------------------------
const BUILDING_DENY_HEALTH := 0.1
const TOWER_PROTECT_RADIUS := 700.0          # hero attacking a hero within this range of a tower draws its fire (APPROX)
const TOWER_DEAGGRO_COOLDOWN := 1.0          # APPROX
const BACKDOOR_DAMAGE_REDUCTION := 0.5
const BACKDOOR_REGEN := 90.0
const BACKDOOR_T2_RADIUS := 900.0
const BACKDOOR_BASE_RADIUS := 4000.0
const BACKDOOR_LINGER := 15.5
const GLYPH_COOLDOWN := 300.0
const GLYPH_INITIAL_COOLDOWN := 180.0
const GLYPH_BUILDING_DURATION := 7.0
const GLYPH_CREEP_DURATION := 3.0
const GLYPH_EXTRA_TARGETS := 5
## Team / last-hit gold per building (APPROX): [team gold per hero, last hit min, last hit max]
const BUILDING_BOUNTY := {
	"tower1": [90, 150, 150], "tower2": [110, 150, 150], "tower3": [125, 150, 150], "tower4": [125, 150, 150],
	"melee_rax": [90, 150, 150], "ranged_rax": [50, 100, 100], "filler": [0, 68, 68],
}
const TOWER_DENY_FACTOR := 0.5

# ---- Town Portal, buyback, courier --------------------------------------------------------------------------------
const TP_CHANNEL := 3.0                     # items.txt tooltip_channel_time
const TP_COOLDOWN := 80.0                   # items.txt AbilityCooldown
const TP_MANA := 75.0                       # items.txt AbilityManaCost
# Courier (Dota 7.23 rework, 7.27 flying level, 7.35 hit counts and respawn; npc_units.txt for speed and vision).
# Its level is its owner's level.
const COURIER_SPEED := 290.0                # npc_units.txt MovementSpeed
const COURIER_SPEED_PER_LEVEL := 10.0       # APPROX (wiki: 290 + 10 per level)
const COURIER_FLY_LEVEL := 4                # 7.27: flying from level 4 (was 5)
const COURIER_HITS := 6                     # 7.35: 1 melee hero attack, 2 ranged hero attacks, 6 other attacks
const COURIER_RESPAWN_BASE := 60.0          # 7.35: 60 + 6 x level
const COURIER_RESPAWN_PER_LEVEL := 6.0
const COURIER_BOUNTY_BASE := 25             # APPROX (7.23 notes: 25 + 5 x level to every enemy hero)
const COURIER_BOUNTY_PER_LEVEL := 5
const COURIER_VISION := 200.0               # npc_units.txt VisionDaytimeRange / VisionNighttimeRange
const COURIER_BURST_LEVEL := 10             # 7.23: Speed Burst from level 10
const COURIER_BURST_SPEED := 0.5            # abilities.txt courier_burst: +50% for 6 s, 120 s cooldown
const COURIER_BURST_TIME := 6.0
const COURIER_BURST_COOLDOWN := 120.0
const COURIER_SHIELD_LEVEL := 20            # 7.23: Shield from level 20
const COURIER_SHIELD_TIME := 2.0            # abilities.txt courier_shield: 2 s, 200 s cooldown
const COURIER_SHIELD_COOLDOWN := 200.0
const COURIER_REACH := 220.0                # hand-over distance to its hero
const COURIER_BASE_RADIUS := 600.0          # "at the fountain": within this of the fountain

# ---- Items on the ground, giving, the stash -------------------------------------------------------------------------
const ITEM_REACH := 150.0                   # drop, pick up and give range (Dota: 150)
const WELL_RADIUS := 1000.0                 # the fountain area the courier sweeps for its owner's items (= shop radius)
const BACKPACK_SWAP_COOLDOWN := 6.0         # an item moved out of the backpack waits 6 s before it can be used
const TO_BUY_MAX := 24                      # entries kept in the To Buy list (8 are shown)
const TO_BUY_SHOWN := 8

# ---- Fountain -------------------------------------------------------------------------------------------------------
const FOUNTAIN_AURA_RADIUS := 1200.0
const FOUNTAIN_HP_REGEN_PCT := 0.05          # Rejuvenation Aura (Dota 2 wiki, Fountain): 5% max health per second
const FOUNTAIN_MANA_REGEN_PCT := 0.06        # and 6% max mana per second
const FOUNTAIN_LINGER := 3.0                 # the aura's buff lingers 3 s
const TOWER_TRUE_SIGHT := 700.0             # APPROX (Dota 2 wiki: towers, the Ancient and the fountain have True Sight)
const ANCIENT_TRUE_SIGHT := 900.0            # APPROX
const FOUNTAIN_TRUE_SIGHT := 1200.0          # APPROX
const HEX_MOVE_SPEED := 140.0                # a hexed unit's base movement speed (Hex Staff: sheep_movement_speed)
const SHOP_RADIUS := 1000.0

# ---- Neutrals ---------------------------------------------------------------------------------------------------------
const NEUTRAL_SPAWN_INTERVAL := 60.0
const NEUTRAL_FIRST_SPAWN := 60.0
## Dota 2 neutral rules (Liquipedia "Neutral Creeps", 2026; research/camps.md in run 2026-10-13-camps-ai-setup)
const NEUTRAL_GUARD_RADIUS := 400.0          # a neutral's guard distance from its spawn spot
const NEUTRAL_CHASE_TIME := 5.0              # aggro drops this long after leaving the guard radius (resets inside it)
const NEUTRAL_REAGGRO_LOCK := 3.0            # after a leash, damage cannot wake it again for this long
const NEUTRAL_REAGGRO_CHASE := 3.0           # woken again while walking home: it chases for only this long
const NEUTRAL_PROXIMITY_AGGRO := 240.0       # by day, an enemy this close wakes a camp (at night they sleep)
const NEUTRAL_CAMPMATE_RADIUS := 500.0       # campmates this close to a damaged neutral join the fight
const NEUTRAL_UPGRADE_INTERVAL := 450.0      # every 7:30 from the horn, up to 30 times
const NEUTRAL_MAX_UPGRADES := 30
## Per neutral upgrade: [hp, armor, damage, attack speed, gold, xp]
const NEUTRAL_UPGRADE := [30.0, 0.5, 3.0, 5.0, 1.0, 5.0]
const STACK_BOUNTY_PENALTY := 0.2            # creeps from a stack give 20% less gold and xp (7.39e)
const STACKER_SHARE := 0.3                   # the stacker gets 30% of what an ally earned from them

# ---- Time of day ----------------------------------------------------------------------------------------------------
const DAY_LENGTH := 600.0                    # full day-night cycle; day first half from 0:00
const PREGAME_TIME := -90.0
## "Ready since forever": the default for every cooldown and timer, so nothing is locked during the pre-game
## (abilities, items, attacks and pathing all work from the first tick; only creeps and neutrals wait for 0:00).
const LONG_AGO := -1.0e9

# ---- Vision ---------------------------------------------------------------------------------------------------------
const VISION_CELL := 128.0
const VISION_UPDATE_TICKS := 3

# ---- Trees ----------------------------------------------------------------------------------------------------------
const TREE_REGROW := 180.0                  # game constant "tree respawn time" (Liquipedia, 2026)
const TREE_REGROW_CLEAR := 150.0            # "tree respawn radius": a tree waits while a unit stands this close
const PLANTED_TREE_DURATION := 20.0         # items.txt item_branches tree_duration
const PLANT_RANGE := 400.0                  # items.txt item_branches AbilityCastRange
const ITEM_LIFESTEAL_CREEP_FACTOR := 0.4    # game constant "item lifesteal creep factor"

# ---- Map ------------------------------------------------------------------------------------------------------------
const MAP_HALF := 8192.0
const PATH_CELL := 64.0
const LEVEL_HEIGHT := 200.0                  # rendered height per terrain level (visual only; the sim uses levels)

static func xp_level(xp: float) -> int:
	var lvl := 1
	for i in range(1, XP_TABLE.size()):
		if xp >= XP_TABLE[i]:
			lvl = i + 1
	return mini(lvl, MAX_LEVEL)

static func passive_gpm(game_time: float) -> float:
	var m := game_time / 60.0
	var t: Array = PASSIVE_GPM
	if m <= t[0][0]:
		return t[0][1]
	for i in range(1, t.size()):
		if m <= t[i][0]:
			var a: Array = t[i - 1]
			var b: Array = t[i]
			return lerpf(a[1], b[1], (m - a[0]) / (b[0] - a[0]))
	return t[-1][1]

## Physical damage multiplier from armor (Dota 7.20+ formula).
static func armor_multiplier(armor: float) -> float:
	return 1.0 - (0.06 * armor) / (1.0 + 0.06 * absf(armor))

static func is_night(game_time: float) -> bool:
	if game_time < 0.0:
		return true
	return fposmod(game_time, DAY_LENGTH) >= DAY_LENGTH * 0.5
