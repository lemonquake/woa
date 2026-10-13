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
var vision_day := 750.0
var vision_night := 750.0
var acquire_range := 500.0
var lifesteal := 0.0                       # from items (40% against creeps)
var lifesteal_ability := 0.0               # from abilities (Blood Ranger)
var evasion := 0.0
var bat := 1.7
var spell_lifesteal := 0.0                 # heals from spell damage dealt (100% vs heroes, 20% vs creeps)
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
var gain_mult := 1.0                       # gold and experience earned (Unfair bots: 1.25)
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
	refresh_stats()
	hp = max_hp
	mana = max_mana

func is_hero() -> bool:
	return kind == K.HERO

func is_building() -> bool:
	return kind in [K.TOWER, K.BARRACKS, K.ANCIENT, K.FILLER, K.FOUNTAIN]

func is_lane_creep() -> bool:
	return kind in [K.CREEP_MELEE, K.CREEP_RANGED, K.CREEP_SIEGE, K.CREEP_FLAG]

func is_creep() -> bool:
	return is_lane_creep() or kind == K.NEUTRAL_CREEP

func is_ward() -> bool:
	return kind == K.WARD

func is_ranged() -> bool:
	return float(def.projectile_speed) > 0.0

func can_attack_at_all() -> bool:
	return bool(def.can_attack)

func defense_class() -> int:
	if kind == K.HERO:
		return C.DefenseClass.HERO
	if is_building():
		return C.DefenseClass.STRUCTURE
	return C.DefenseClass.NON_HERO

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
func add_modifier(m: Dictionary) -> void:
	for i in modifiers.size():
		var o: Dictionary = modifiers[i]
		if o.id == m.id and o.get("source", -1) == m.get("source", -1):
			var same_stats: bool = o.get("stats", {}) == m.get("stats", {}) and o.get("slow", 0.0) == m.get("slow", 0.0)
			modifiers[i] = m
			if not same_stats or o.keys().size() != m.keys().size():
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
	return has_flag("silence") or is_stunned()

func is_rooted() -> bool:
	return has_flag("root") or is_stunned() or not hop.is_empty() or not knock.is_empty()

## Muted: no item use (Shuriken Hook's follow-through).
func is_muted() -> bool:
	return has_flag("mute") or is_stunned()

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

## The strongest healing reduction on this unit (Stench with the Upgrade Staff), 0..1.
func heal_reduction() -> float:
	var r := 0.0
	for m in modifiers:
		r = maxf(r, float(m.get("heal_reduction", 0.0)))
	return r

func is_disarmed() -> bool:
	return has_flag("disarm") or is_stunned()

func is_invulnerable() -> bool:
	return invulnerable or has_flag("invulnerable")

func expire_modifiers(now: float) -> void:
	for i in range(modifiers.size() - 1, -1, -1):
		var e: float = modifiers[i].get("expires", INF)
		if now >= e:
			modifiers.remove_at(i)
			stats_dirty = true

# ---- Stats ------------------------------------------------------------------------------------------------------------

## Bonuses from the six main slots (the backpack gives none). Boot speed does not stack: the fastest pair counts.
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

func _add_item_stats(out: Dictionary, st: Dictionary) -> void:
	for k in st:
		if k == "boot_ms":
			out[k] = maxf(float(out.get(k, 0.0)), float(st[k]))
		else:
			out[k] = float(out.get(k, 0.0)) + float(st[k])

func _mod_stat(k: String) -> float:
	var s := 0.0
	for m in modifiers:
		var st: Dictionary = m.get("stats", {})
		if st.has(k):
			s += float(st[k])
	return s

## Recompute derived stats from definition, level, attributes, items, abilities and modifiers.
func refresh_stats() -> void:
	var items := _item_stats() if kind == K.HERO else {}
	var f := func(k: String) -> float: return float(items.get(k, 0.0)) + _mod_stat(k) + float(perm_stats.get(k, 0.0))
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
	bonus_damage = f.call("damage")
	attack_speed = clampf(float(def.attack_speed) + attr_as + f.call("attack_speed"), C.ATTACK_SPEED_MIN, C.ATTACK_SPEED_MAX)
	attack_range = float(def.range) + range_bonus + (f.call("range") if is_ranged() else 0.0)
	var slow := 0.0
	for m in modifiers:
		slow = maxf(slow, float(m.get("slow", 0.0)))
	var ms: float = (float(def.move_speed) + f.call("move_speed") + f.call("boot_ms")) * (1.0 + f.call("move_speed_pct")) * (1.0 - slow)
	move_speed = clampf(ms, C.MOVE_SPEED_MIN, C.MOVE_SPEED_MAX) if float(def.move_speed) > 0.0 else 0.0
	turn_rate = float(def.turn_rate)
	hp_regen = float(def.hp_regen) + attr_hpr + f.call("hp_regen")
	mana_regen = float(def.mana_regen) + attr_mpr + f.call("mana_regen")
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
