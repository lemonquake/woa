class_name SimUnit
extends RefCounted
## One unit in the simulation (hero, creep, building, ward). Pure data plus stat rules; the systems in SimWorld,
## SimOrders, SimCombat and SimAI move it. No nodes, no rendering state.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

enum AtkPhase { NONE, WINDUP, BACKSWING }
enum CastPhase { NONE, WINDUP, BACKSWING }

var id := 0
var def: Dictionary
var kind := 0
var team := 0
var name := ""
var pos := Vector2.ZERO
var facing := 0.0
var hull := 16.0
var alive := true
var removed := false
var spawn_time := 0.0
var death_at := C.LONG_AGO
var killer_id := -1

# ---- Vital stats ----------------------------------------------------------------------------------------------------
var hp := 1.0
var max_hp := 1.0
var mana := 0.0
var max_mana := 0.0
var level := 1
var armor := 0.0
var magic_resist := 0.0
var dmg_min := 1.0
var dmg_max := 1.0
var bonus_damage := 0.0
var attack_speed := 100.0
var attack_range := 100.0
var move_speed := 300.0
var turn_rate := 0.5
var hp_regen := 0.0
var mana_regen := 0.0
var hp_regen_base := 0.0                   # the unit's own regen (base + attributes); the rest of hp_regen is bonus
var mana_regen_base := 0.0
var heal_amp := 0.0                        # health restoration amplification (regen, heals, lifesteal), 0..1
var mana_regen_amp := 0.0                  # mana regeneration amplification, 0..1
var vision_day := 750.0
var vision_night := 750.0
var acquire_range := 500.0
var lifesteal := 0.0                       # from items (40% against creeps)
var lifesteal_ability := 0.0               # from abilities (Blood Ranger)
var evasion := 0.0
var bat := 1.7
var spell_lifesteal := 0.0                 # heals from spell damage dealt (100% vs heroes, 20% vs creeps)
var status_resist := 0.0                   # shortens enemy debuffs (0..1, sources multiply)
var slow_resist := 0.0                     # shrinks movement slows (0..1)
var spell_amp := 0.0                       # raises spell damage dealt (0..1)
var magic_amp := 0.0                       # raises magic damage dealt by spells and items: intelligence + items
var magic_amp_int := 0.0                   # the part from intelligence (1% per 20)
var magic_amp_items := 0.0
var cooldown_reduction := 0.0              # cooldowns start this much shorter (Time Crystal; largest item counts)
var cooldown_rate := 0.0                   # cooldowns run this much faster (+) or slower (-); -1 freezes them
var aoe_bonus := 0.0                       # spell areas are this much wider (Wide Stone family; largest counts)
var cast_range_bonus := 0.0                # spell and item cast range (items, talents, buffs; see item_cast_range)
var hp_regen_pct := Vector2.ZERO           # regeneration in fractions of max health and of missing health (Giant Heart)
var mana_cost_cut := 0.0                   # spells and items cost this much less mana (largest item counts)
var cast_speed := 0.0                      # cast points are this much faster: time / (1 + cast_speed)                 # the part from items, diminishing (see SimConst.ITEM_MAGIC_AMP_FALLOFF)
var element := 0                           # SimConst.Element: what its attacks carry and what it resists
var weapon := 0                            # SimConst.Weapon: its attacks' damage type
var armor_type := 0                        # SimConst.ArmorType
var attack_out_pct := 0.0                  # change to attack damage dealt (Intimidate: -0.6)
var damage_out_pct := 0.0                  # change to all damage dealt, attacks and spells (Void Rush: -0.25)
var ranged_form := false                   # cached: a melee unit attacking at range for now (Anomaly)
var form_proj_speed := 0.0                 # cached: its projectile speed meanwhile
var prd := {}                              # pseudo-random counters: effect key -> rolls since the last proc
var debuff_immune := false                 # cached from modifiers in refresh_stats
var phased := false                        # cached: walks through units

# ---- Hero -----------------------------------------------------------------------------------------------------------
var str_total := 0.0
var agi_total := 0.0
var int_total := 0.0
var xp := 0.0
var gold_reliable := 0
var gold_unreliable := 0
var ability_points := 0
var abilities: Array = []                  # ability ids in slot order (Q W E R)
var ability_level := {}                    # id -> learned level (an innate ability is level 1 from the start)
var ability_ready := {}                    # id -> game time the cooldown ends
var autocast := {}                         # id -> bool
var toggles := {}                          # id -> bool: toggle abilities that are on (Stench)
var talents := {}                          # talent tier (0..3) -> chosen talent id
var stacks := {}                           # permanent counters, e.g. "growing_gut" -> enemy hero deaths
var perm_stats := {}                       # stats that survive death: talents and stacks (not modifiers)
var shard := false                         # Upgrade Gem bought (Dota's Aghanim's Shard)
var scepter := false                       # Upgrade Staff effect without the item (tests, Debug panel)
var inventory: Array = []                  # 9 slots (6 main + 3 backpack): null or {id, charges, ready}
var stash: Array = []                      # 6 slots
var respawn_at := -1.0
var buyback_ready := C.LONG_AGO
var kills := 0
var deaths := 0
var assists := 0
var last_hits := 0
var denies := 0
var streak := 0
var hero_damage_log := {}                  # enemy hero id -> last game time they damaged us
var stick_charges := 0
var player := false
var auto_attack := true                    # idle heroes attack enemies in acquisition range (Dota "Standard")
var no_acquire := false                    # set by a hard stop (S held): no auto-attack until the next order
var bot := false
var gold_mult := 1.0                       # gold earned, passive gold too (Unfair bots: 3.0, +200%)
var xp_mult := 1.0                         # experience earned (Unfair bots: 1.5, +50%)
var bot_name := ""                         # a bot hero's player name (shown in chat and on the scoreboard)
var look := {}                             # appearance dictionary (HeroLook) for the renderer
var dmg_out := {}                          # damage source key -> [to heroes, to other units, to buildings]
var dmg_in := {}                           # damage source key -> damage taken
var recent_in: Array = []                  # heroes: [{t, src, key, type, amount}] for the death recap (last 20 s)
var healed := 0.0                          # health restored by heals and lifesteal
var gold_earned := 0                       # heroes: all gold gained (for gold per minute)
var last_kill_at := C.LONG_AGO                  # heroes: for multi-kills
var multi_kill := 0

# ---- Orders and actions -------------------------------------------------------------------------------------------
var order := C.Order.NONE
var order_target := -1
var order_point := Vector2.ZERO
var order_ability := ""
var order_from_player := false
var order_queue: Array = []
var path := PackedVector2Array()
var path_i := 0
var path_goal := Vector2(INF, INF)
var repath_at := C.LONG_AGO
var moving := false
var blocked_time := 0.0

var atk_phase := AtkPhase.NONE
var atk_timer := 0.0
var atk_target := -1
var atk_modifier := ""                     # ability id riding on the current attack (orb)
var atk_crit := 1.0                        # critical strike multiplier rolled when this attack started (1 = none)
var orb_manual := ""                       # an attack modifier cast by hand: rides on the next attack, draws no aggro
var next_attack_at := C.LONG_AGO
var prev_attack_at := C.LONG_AGO
var cast_phase := CastPhase.NONE
var cast_timer := 0.0
var cast_ability := ""
var cast_target := -1
var cast_point := Vector2.ZERO
var cast_item_slot := -1

# ---- AI -------------------------------------------------------------------------------------------------------------
var lane := ""
var lane_i := 0
var lane_return := Vector2(INF, INF)       # where a lane creep left its lane
var camp_id := -1
var home := Vector2.ZERO
var home_facing := 0.0
var think_at := C.LONG_AGO
var aggro_target := -1
var aggro_until := C.LONG_AGO
var aggro_forced := false
var aggro_cd_until := C.LONG_AGO                  # heroes: creep aggro cooldown
var tower_deaggro_at := C.LONG_AGO
var last_seen := Vector2(INF, INF)         # last visible position of the chase target
var neutral_state := 0                     # 0 idle, 1 aggro, 2 returning
var neutral_aggro_at := C.LONG_AGO
var leash_since := -1.0                    # neutrals: when they left their 400 guard radius on this chase (-1 inside)
var no_reaggro_until := C.LONG_AGO         # neutrals: damage cannot wake them again until then (after a leash)
var hostile_until := C.LONG_AGO            # neutrals: lane creeps may attack it until then (it is fighting, or just was)
var stacked := false                       # neutrals: spawned by a stack (20% less bounty)
var stacker_id := -1                       # neutrals: the hero who stacked them (gets 30% of an ally's bounty)
var lane_tier := 0
var building_lane := ""
var upgrade := 0
var bounty_gold_add := 0.0
var bounty_xp_add := 0.0
var creep_dmg_add := 0.0
var is_super := false

# ---- Buildings ------------------------------------------------------------------------------------------------------
var invulnerable := false
var backdoor_active := false
var backdoor_pool := 0.0
var backdoor_off_until := 0.0
var glyph_until := C.LONG_AGO

# ---- Effects ----------------------------------------------------------------------------------------------------------
var modifiers: Array = []                  # see SimUnit.add_modifier
var stats_dirty := true                    # recompute derived stats before the next tick
var knock: Dictionary = {}                 # {from, to, t, dur} (eased push) or {phys, vel, z, vz, ...} (physics push)
var leap: Dictionary = {}                  # {target, from, to, t, dur, ability, lv}: a leap in progress (Leap Strike)
var history: Array = []                    # Rewind: [time, pos, hp, mana] every 0.1 s for the last 4 s
var hop: Dictionary = {}                   # {from, to, t, dur, z}: Blood Ranger's back leap (keeps orders, no walking)
var channel: Dictionary = {}               # {ability, until, ...}: channelling (Town Portal, Burst Shot)
var tp_charges := 0                        # Town Portal scrolls in the dedicated slot
var courier_id := -1                       # heroes: their courier
var owner_id := -1                         # couriers: their hero
var courier_state := "idle"               # idle, move, return, retrieve, deliver, transfer, stash, collect
var courier_goal := Vector2.ZERO           # couriers: where a move order sends them
var courier_next := ""                     # couriers: the task after collecting ground items ("deliver", "retrieve")
var courier_auto := false                  # couriers: Auto Deliver is on
var courier_burst_ready := C.LONG_AGO      # couriers: Speed Burst / Shield cooldowns end
var courier_shield_ready := C.LONG_AGO
var to_buy: Array = []                     # heroes: the To Buy list, [{id, auto}] in order (Dota's quick buy)
var was_in_shop := false                   # heroes: in the shop's range last tick (the stash empties on arrival)
var order_gid := -1                        # PICKUP_ITEM: the ground item
var ward_expires := 0.0

func setup(p_id: int, p_def: Dictionary, p_team: int, p_pos: Vector2, now: float) -> void:
	id = p_id
	def = p_def
	kind = def.kind
	team = p_team
	name = def.name
	pos = p_pos
	hull = def.hull
	spawn_time = now
	element = int(def.get("element", 0))
	if element == SimData.TEAM_ELEMENT:
		element = C.Element.LIGHT if team == C.DAWN else C.Element.DARK
	element = maxi(0, element)
	weapon = int(def.get("weapon", -1))
	if weapon < 0:
		weapon = C.Weapon.HERO if kind == K.HERO else C.Weapon.BLUNT
	armor_type = int(def.get("armor_type", -1))
	if armor_type < 0:
		if kind == K.HERO:
			armor_type = C.ArmorType.HERO
		elif is_building():
			armor_type = C.ArmorType.STRUCTURE
		elif kind == K.CREEP_SIEGE:
			armor_type = C.ArmorType.ARMORED
		else:
			armor_type = C.ArmorType.ORGANIC
	level = def.level
	bat = def.bat
	if kind == K.HERO:
		level = 1
		abilities = (def.abilities as Array).duplicate()
		for a in abilities:
			ability_level[a] = 0
			ability_ready[a] = C.LONG_AGO
			autocast[a] = false
		if String(def.get("innate", "")) != "":
			ability_level[def.innate] = 1
			ability_ready[def.innate] = C.LONG_AGO
		ability_points = 1
		inventory.resize(9)
		stash.resize(6)
		gold_reliable = 0
		gold_unreliable = C.STARTING_GOLD
		tp_charges = 1
	if kind == K.COURIER:
		inventory.resize(6)                    # flying is granted by the world from its owner's level 4
	if kind != K.HERO:
		# creeps know their abilities from the start (the neutrals' Snarl, Stomp, Smash)
		abilities = (def.abilities as Array).duplicate()
		for a in abilities:
			ability_level[a] = 1
			ability_ready[a] = C.LONG_AGO
	refresh_stats()
	hp = max_hp
	mana = max_mana

func is_hero() -> bool:
	return kind == K.HERO

## Kinds are ordered (SimConst.Kind): lane creeps 1-4, buildings TOWER..FOUNTAIN. Plain comparisons, no array per call
## (these run thousands of times a tick).
func is_building() -> bool:
	return kind >= K.TOWER and kind <= K.FOUNTAIN

func is_lane_creep() -> bool:
	return kind >= K.CREEP_MELEE and kind <= K.CREEP_FLAG

func is_creep() -> bool:
	return is_lane_creep() or kind == K.NEUTRAL_CREEP

func is_ward() -> bool:
	return kind == K.WARD

func is_ranged() -> bool:
	return ranged_form or float(def.projectile_speed) > 0.0

## Attack projectile speed (a melee hero in a ranged form uses the form's).
func projectile_speed() -> float:
	return form_proj_speed if ranged_form and float(def.projectile_speed) <= 0.0 else float(def.projectile_speed)

func can_attack_at_all() -> bool:
	return bool(def.can_attack)

## Target priority for lane creeps and towers: 1 heroes and non-heroes, 2 siege creeps, 3 buildings, 4 wards.
func type_priority() -> int:
	if kind == K.CREEP_SIEGE:
		return 2
	if is_building():
		return 3
	if is_ward():
		return 4
	return 1

func gold() -> int:
	return gold_reliable + gold_unreliable

func is_night_vision(night: bool) -> float:
	return vision_night if night else vision_day

# ---- Modifiers --------------------------------------------------------------------------------------------------------

## A modifier: {id, source, expires (game time, INF = forever; pre-game times are negative), stats: {}, stun, root, silence, disarm, slow (0..1),
## invulnerable, regen (hp/s), mana_regen (mana/s), break_on_damage, stack_key}. Same id + source refreshes.
## expire_modifiers stamps "t0", the game time it was first seen, so the HUD's buff bar knows how long it lasts in all.
func add_modifier(m: Dictionary) -> void:
	for i in modifiers.size():
		var o: Dictionary = modifiers[i]
		if o.id == m.id and o.get("source", -1) == m.get("source", -1):
			var same_stats: bool = o.get("stats", {}) == m.get("stats", {}) and o.get("slow", 0.0) == m.get("slow", 0.0)
			modifiers[i] = m
			# "t0" (when it started, for the HUD's timer) is stamped later and changes no stat
			if not same_stats or o.keys().size() - int(o.has("t0")) != m.keys().size() - int(m.has("t0")):
				stats_dirty = true
			return
	modifiers.append(m)
	stats_dirty = true

func remove_modifier(mid: String) -> void:
	for i in range(modifiers.size() - 1, -1, -1):
		if modifiers[i].id == mid:
			modifiers.remove_at(i)
			stats_dirty = true

func has_flag(flag: String) -> bool:
	for m in modifiers:
		if m.get(flag, false):
			return true
	return false

## Stunned: a stun modifier, or an eased push / drag that disables (a drag by an ally's hook does not).
func is_stunned() -> bool:
	return has_flag("stun") or (not knock.is_empty() and bool(knock.get("disable", true)))

## Leaping (Leap Strike): the unit flies to its target and takes no orders until it lands.
func is_leaping() -> bool:
	return not leap.is_empty()

func get_modifier(mid: String) -> Dictionary:
	for m in modifiers:
		if m.id == mid:
			return m
	return {}

func is_silenced() -> bool:
	return has_flag("silence") or has_flag("hex") or is_stunned()

## Hexed: a harmless critter that cannot attack, cast or use items, at 140 speed.
func is_hexed() -> bool:
	return has_flag("hex")

## Broken: its own passive abilities do nothing (item passives still work).
func is_broken() -> bool:
	return has_flag("break")

func is_rooted() -> bool:
	return has_flag("root") or is_stunned() or not hop.is_empty() or not knock.is_empty()

## Muted: no item use (Shuriken Hook's follow-through).
func is_muted() -> bool:
	return has_flag("mute") or has_flag("hex") or is_stunned()

## The Upgrade Staff (Dota's Aghanim's Scepter) is in a main slot, or granted another way.
func has_scepter() -> bool:
	if scepter:
		return true
	for i in mini(6, inventory.size()):
		var it = inventory[i]
		if it != null and String(SimData.item(it.id).get("grants", "")) == "scepter":
			return true
	return false

## The largest flat block on every damage instance (Blubber and similar), 0 if none.
func damage_block() -> float:
	var b := 0.0
	for m in modifiers:
		b = maxf(b, float(m.get("block_all", 0.0)))
	return b

## Lowered defense (Ice Pulse), 0..1: physical and magic damage it takes after armor and resistances is raised by it.
func defense_loss() -> float:
	var r := 0.0
	for m in modifiers:
		r = maxf(r, float(m.get("defense_loss", 0.0)))
	return r

## The strongest healing reduction on this unit (Stench with the Upgrade Staff), 0..1.
func heal_reduction() -> float:
	var r := 0.0
	for m in modifiers:
		r = maxf(r, float(m.get("heal_reduction", 0.0)))
	return r

func is_disarmed() -> bool:
	return has_flag("disarm") or has_flag("hex") or is_stunned()

func is_invulnerable() -> bool:
	return invulnerable or has_flag("invulnerable")

func expire_modifiers(now: float) -> void:
	for i in range(modifiers.size() - 1, -1, -1):
		var e: float = modifiers[i].get("expires", INF)
		if now >= e:
			modifiers.remove_at(i)
			stats_dirty = true
		elif not modifiers[i].has("t0"):
			modifiers[i]["t0"] = now

# ---- Stats ------------------------------------------------------------------------------------------------------------

## Bonuses from the six main slots (the backpack gives none). Boot speed does not stack: the fastest pair counts; nor
## do stats whose key ends in "_max" (the Heavy Sword family's slow resistance and health restoration): the largest
## copy counts, as in Dota.
## Some items differ for melee and ranged heroes; Switch Boots add to their chosen attribute; Armor Breaker adds the
## damage it has collected from kills.
func _item_stats() -> Dictionary:
	var out := {}
	var melee := not is_ranged()
	for i in mini(6, inventory.size()):
		var it = inventory[i]
		if it == null:
			continue
		var d := SimData.item(it.id)
		_add_item_stats(out, d.stats)
		var extra: Dictionary = d.get("stats_melee" if melee else "stats_ranged", {})
		_add_item_stats(out, extra)
		if it.has("attr"):
			out[it.attr] = float(out.get(it.attr, 0.0)) + float(d.values.attr_bonus)
		if it.has("souls"):
			out["damage"] = float(out.get("damage", 0.0)) + minf(float(it.souls), float(d.values.max_damage))
	return out

## Chances and resistances from several sources multiply: 1 - (1 - a)(1 - b), as Dota stacks evasion, magic
## resistance, status resistance and slow resistance.
const MULT_KEYS := ["evasion", "magic_resist", "status_resist", "slow_resist"]

static func _stack(a: float, b: float, k: String) -> float:
	return 1.0 - (1.0 - a) * (1.0 - b) if k in MULT_KEYS else a + b

func _add_item_stats(out: Dictionary, st: Dictionary) -> void:
	for k in st:
		if k == "cast_range_max":
			continue                       # item_cast_range() sums it by source
		if k == "boot_ms" or k.ends_with("_max"):
			out[k] = maxf(float(out.get(k, 0.0)), float(st[k]))
		else:
			out[k] = _stack(float(out.get(k, 0.0)), float(st[k]), k)

## Cast range from the main-slot items: copies of one source (an item and its upgraded levels: Blast Rod 1-5 are one
## source) stack with diminishing returns (C.CAST_RANGE_FALLOFF), different sources add up. Owner's rule 2026-10-15.
func item_cast_range() -> float:
	if kind != K.HERO:
		return 0.0
	var by_source := {}
	for i in mini(6, inventory.size()):
		var it = inventory[i]
		if it == null:
			continue
		var r := float(SimData.item(it.id).stats.get("cast_range_max", 0.0))
		if r <= 0.0:
			continue
		var src := cast_range_source(String(it.id))
		if not by_source.has(src):
			by_source[src] = []
		(by_source[src] as Array).append(r)
	var total := 0.0
	for src in by_source:
		var vals: Array = by_source[src]
		vals.sort()
		vals.reverse()
		var f := 1.0
		for v in vals:
			total += float(v) * f
			f *= C.CAST_RANGE_FALLOFF
	return total

## The source an item's cast range comes from: its id without a level suffix ("dagon_3" -> "dagon").
static func cast_range_source(item_id: String) -> String:
	var m := item_id.rfind("_")
	if m > 0 and item_id.substr(m + 1).is_valid_int():
		return item_id.substr(0, m)
	return item_id

## Magic amp from each main-slot item, largest first (they stack with diminishing returns).
func item_magic_amps() -> Array:
	var out: Array = []
	if kind != K.HERO:
		return out
	for i in mini(6, inventory.size()):
		var it = inventory[i]
		if it == null:
			continue
		var a := float(SimData.item(it.id).stats.get("magic_amp", 0.0))
		if a > 0.0:
			out.append(a)
	out.sort()
	out.reverse()
	return out

## Item magic amp after diminishing returns: the largest counts in full, each next one half as much as the one before.
static func diminished_amp(amps: Array) -> float:
	var total := 0.0
	var f := 1.0
	for a in amps:
		total += float(a) * f
		f *= C.ITEM_MAGIC_AMP_FALLOFF
	return total

func _mod_stat(k: String) -> float:
	var s := 0.0
	for m in modifiers:
		var st: Dictionary = m.get("stats", {})
		if st.has(k):
			s = _stack(s, float(st[k]), k)
	return s

## Recompute derived stats from definition, level, attributes, items, abilities and modifiers.
## SimAbilities.val results (a cache, not state): "ability|key" -> [ability level, talents, value]. Emptied whenever
## the stats are recomputed (items, auras, Upgrade Staff and Gem, area bonus).
var _val_cache := {}

func refresh_stats() -> void:
	_val_cache.clear()
	var items := _item_stats() if kind == K.HERO else {}
	var f := func(k: String) -> float:
		return _stack(_stack(float(items.get(k, 0.0)), _mod_stat(k), k), float(perm_stats.get(k, 0.0)), k)
	var base_dmg_min := float(def.dmg_min) + creep_dmg_add
	var base_dmg_max := float(def.dmg_max) + creep_dmg_add
	var hp_old_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var mana_old_frac := mana / max_mana if max_mana > 0.0 else 1.0
	var attr_hp := 0.0
	var attr_mana := 0.0
	var attr_armor := 0.0
	var attr_as := 0.0
	var attr_hpr := 0.0
	var attr_mpr := 0.0
	var attr_mr := 0.0
	var range_bonus := 0.0
	if kind == K.HERO:
		var lv := float(level - 1)
		var agi_pct := 0.0
		str_total = float(def.str) + float(def.str_gain) * lv + f.call("str")
		var agi_base := float(def.agi) + float(def.agi_gain) * lv
		agi_total = agi_base + f.call("agi") + agi_base * agi_pct
		int_total = float(def["int"]) + float(def.int_gain) * lv + f.call("int")
		attr_hp = str_total * C.STR_HP
		attr_hpr = str_total * C.STR_HP_REGEN
		attr_armor = agi_total * C.AGI_ARMOR
		attr_as = agi_total * C.AGI_ATTACK_SPEED
		attr_mana = int_total * C.INT_MANA
		attr_mpr = int_total * C.INT_MANA_REGEN
		attr_mr = int_total * C.INT_MAGIC_RESIST
		var primary: float = {"str": str_total, "agi": agi_total, "int": int_total}[def.primary]
		base_dmg_min += primary
		base_dmg_max += primary
	max_hp = float(def.hp) + attr_hp + f.call("hp") + upgrade_hp()
	max_mana = (float(def.mana) + attr_mana + f.call("mana")) * (1.0 + f.call("max_mana_pct"))
	hp = clampf(hp_old_frac * max_hp, 0.0, max_hp) if alive else 0.0
	mana = clampf(mana_old_frac * max_mana, 0.0, max_mana)
	armor = float(def.armor) + attr_armor + f.call("armor")
	if kind == K.NEUTRAL_CREEP:
		armor += C.NEUTRAL_UPGRADE[1] * upgrade
		attr_as += C.NEUTRAL_UPGRADE[3] * upgrade
	var mr: float = 1.0 - (1.0 - float(def.magic_resist)) * (1.0 - attr_mr) * (1.0 - f.call("magic_resist"))
	magic_resist = mr
	dmg_min = base_dmg_min
	dmg_max = base_dmg_max
	# raw damage % (an aura such as the Alpha Wolf's) counts as bonus damage, as in Dota
	var raw_pct: float = f.call("base_damage_pct")
	bonus_damage = f.call("damage") + (base_dmg_min + base_dmg_max) * 0.5 * raw_pct
	attack_out_pct = f.call("attack_out_pct")
	damage_out_pct = f.call("damage_out_pct")
	# a ranged form (Anomaly): ranged attacks with the form's projectile and a shorter base attack time
	ranged_form = false
	form_proj_speed = 0.0
	var bat_cut := 0.0
	for m in modifiers:
		if m.get("ranged_form", false):
			ranged_form = true
			form_proj_speed = maxf(form_proj_speed, float(m.get("proj_speed", 900.0)))
		bat_cut += float(m.get("bat_cut", 0.0))
	bat = maxf(0.5, float(def.bat) - bat_cut)
	# attack speed: flat bonuses, then percentage changes (Dark Matter Skin's slow: -80%)
	attack_speed = clampf((float(def.attack_speed) + attr_as + f.call("attack_speed")) * maxf(0.0, 1.0 + f.call("attack_speed_pct")),
		C.ATTACK_SPEED_MIN, C.ATTACK_SPEED_MAX)
	# item range counts for ranged heroes; a melee-only bonus (Sure Hit Staff) comes as "range_melee"; a form's own
	# range ("range_form") always counts
	attack_range = float(def.range) + range_bonus + (f.call("range") if is_ranged() else f.call("range_melee")) \
		+ f.call("range_form")
	# the strongest slow counts, shrunk by slow resistance (the Heavy Sword family's does not stack: largest wins)
	slow_resist = _stack(float(items.get("slow_resist_max", 0.0)), f.call("slow_resist"), "slow_resist")
	status_resist = _stack(float(items.get("status_resist_max", 0.0)), f.call("status_resist"), "status_resist")
	spell_amp = f.call("spell_amp")
	magic_amp_int = int_total * C.INT_MAGIC_AMP if kind == K.HERO else 0.0
	magic_amp_items = diminished_amp(item_magic_amps())
	# talents and buffs add on top (not diminished)
	magic_amp = magic_amp_int + magic_amp_items + _mod_stat("magic_amp") + float(perm_stats.get("magic_amp", 0.0))
	var slow := 0.0
	for m in modifiers:
		slow = maxf(slow, float(m.get("slow", 0.0)))
	slow *= 1.0 - slow_resist
	# a hex sets the base speed to 140; flat and percentage bonuses still apply (Dota: Hex, set movement speed)
	var base_ms := C.HEX_MOVE_SPEED if is_hexed() else float(def.move_speed)
	var ms: float = (base_ms + f.call("move_speed") + f.call("boot_ms")) * (1.0 + f.call("move_speed_pct")) * (1.0 - slow)
	move_speed = clampf(ms, C.MOVE_SPEED_MIN, C.MOVE_SPEED_MAX) if float(def.move_speed) > 0.0 else 0.0
	# haste (Speed Orb): the maximum speed, and slows cannot lower it
	if has_flag("haste") and move_speed > 0.0:
		move_speed = C.MOVE_SPEED_MAX
	turn_rate = float(def.turn_rate)
	hp_regen_base = float(def.hp_regen) + attr_hpr
	mana_regen_base = float(def.mana_regen) + attr_mpr
	hp_regen = hp_regen_base + f.call("hp_regen")
	mana_regen = mana_regen_base + f.call("mana_regen")
	heal_amp = maxf(float(items.get("heal_amp_max", 0.0)), 0.0) + _mod_stat("heal_amp")
	mana_regen_amp = float(items.get("mana_regen_amp_max", 0.0)) + _mod_stat("mana_regen_amp")
	mana_cost_cut = float(items.get("mana_cost_cut_max", 0.0))
	cast_speed = float(items.get("cast_speed_max", 0.0))
	cooldown_reduction = _stack(float(items.get("cooldown_reduction_max", 0.0)), _mod_stat("cooldown_reduction"), "evasion")
	cooldown_rate = maxf(-1.0, _mod_stat("cooldown_rate"))
	aoe_bonus = float(items.get("aoe_bonus_max", 0.0)) + _mod_stat("aoe_bonus")
	cast_range_bonus = item_cast_range() + _mod_stat("cast_range") + float(perm_stats.get("cast_range", 0.0))
	hp_regen_pct = Vector2(float(items.get("hp_regen_pct_max", 0.0)), float(items.get("hp_regen_pct_missing", 0.0)))
	vision_day = float(def.vision_day)
	vision_night = float(def.vision_night)
	acquire_range = float(def.acquire)
	lifesteal = float(items.get("lifesteal", 0.0)) + _mod_stat("lifesteal")
	lifesteal_ability = _mod_stat("lifesteal_ability")
	evasion = f.call("evasion")
	spell_lifesteal = f.call("spell_lifesteal")
	debuff_immune = has_flag("debuff_immune")
	phased = has_flag("phased")
	stats_dirty = false

func upgrade_hp() -> float:
	if kind == K.NEUTRAL_CREEP:
		return C.NEUTRAL_UPGRADE[0] * upgrade
	return 0.0 if not is_lane_creep() else _upgrade_val(0)

func _upgrade_val(i: int) -> float:
	var key := ""
	if kind == K.CREEP_MELEE or kind == K.CREEP_FLAG:
		key = "super_melee" if is_super else "melee"
	elif kind == K.CREEP_RANGED:
		key = "super_ranged" if is_super else "ranged"
	if key == "" or kind == K.CREEP_FLAG:
		return 0.0
	var n := upgrade if i < 2 else upgrade
	if i < 2:
		n = mini(upgrade, C.CREEP_MAX_UPGRADES)
	return float(C.CREEP_UPGRADE[key][i]) * n

## Seconds between attack starts.
func attack_interval() -> float:
	return bat / (attack_speed / 100.0)

func attack_point_time() -> float:
	return float(def.attack_point) / (attack_speed / 100.0)

func backswing_time() -> float:
	return float(def.backswing) / (attack_speed / 100.0)

## Radians per second.
func turn_speed() -> float:
	return turn_rate / C.TURN_RATE_PERIOD

func edge_distance(o: SimUnit) -> float:
	return maxf(0.0, pos.distance_to(o.pos) - hull - o.hull)

func networth() -> int:
	var w := gold()
	for arr in [inventory, stash, courier_items]:
		for it in arr:
			if it != null:
				w += int(SimData.item(it.id).cost)
	return w

## Heroes: what their courier carries (kept up to date by the world; counts toward net worth and the shop's plans).
var courier_items: Array = []

func xp_to_next() -> float:
	if level >= C.MAX_LEVEL:
		return 0.0
	return float(C.XP_TABLE[level]) - xp

func ability_level_of(aid: String) -> int:
	return int(ability_level.get(aid, 0))

func is_idle() -> bool:
	return order == C.Order.NONE and atk_phase == AtkPhase.NONE and cast_phase == CastPhase.NONE

## Whether this unit is currently attacking `target_id` (an order, or a swing in progress).
func is_attacking(target_id: int) -> bool:
	return atk_target == target_id and (atk_phase != AtkPhase.NONE or order == C.Order.ATTACK_UNIT or order == C.Order.ATTACK_MOVE)
