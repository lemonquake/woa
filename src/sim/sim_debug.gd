class_name SimDebug
extends RefCounted
## Test helpers behind the Debug panel (F9 in a match): skip the pre-game, spawn waves and camps, level up, gold,
## refresh, god mode, free spells, reveal the map, skip time. They change the world directly, so they are for
## testing only; flags that need upkeep every tick (god mode, free spells) are applied by tick().

const C = preload("res://src/sim/sim_const.gd")

## Skip the rest of the pre-game: the horn sounds now and the first wave spawns on the next tick.
static func force_start(w: SimWorld) -> void:
	if w.time < 0.0:
		w.time = 0.0
		w.next_wave_at = 0.0
		w.wave = 0

## A lane wave for both teams right now (the regular schedule carries on).
static func force_wave(w: SimWorld) -> void:
	w.wave += 1
	w.ai.spawn_wave(w.wave)

static func force_neutrals(w: SimWorld) -> void:
	w.ai.spawn_neutrals()

## Experience up to the next level (with its ability point).
static func level_up(w: SimWorld, h: SimUnit, levels := 1) -> void:
	var target := mini(h.level + levels, C.MAX_LEVEL)
	var need := float(C.XP_TABLE[mini(target - 1, C.XP_TABLE.size() - 1)]) - h.xp
	if need > 0.0:
		w.combat.give_xp(h, need + 0.01, true)

static func gold(w: SimWorld, h: SimUnit, amount: int) -> void:
	w.combat.give_gold(h, amount, true, h.pos, true)

## Full health and mana, every ability and item ready.
static func refresh(w: SimWorld, h: SimUnit) -> void:
	h.hp = h.max_hp
	h.mana = h.max_mana
	for aid in h.ability_ready.keys():
		h.ability_ready[aid] = C.LONG_AGO
	for it in h.inventory:
		if it != null:
			it["ready"] = C.LONG_AGO

static func respawn(w: SimWorld, h: SimUnit) -> void:
	if not h.alive:
		w.respawn(h)

## Kill a unit outright, credited to `by` (gold, experience and kill feed as for a normal kill).
static func kill(w: SimWorld, u: SimUnit, by: SimUnit) -> void:
	if u != null and u.alive and not u.is_invulnerable():
		w.combat.deal_damage(by.id if by else -1, by.team if by else C.NEUTRAL, by != null and by.is_hero(), u,
			u.hp + 1.0e6, C.DamageType.PURE, false, "debug")

static func teleport(w: SimWorld, h: SimUnit, p: Vector2) -> void:
	if not h.alive:
		return
	h.pos = p
	h.path = PackedVector2Array()
	h.order = C.Order.NONE
	h.order_queue.clear()
	w.nudge_out(p, h.hull)

# ---- Bots (the Debug panel's Bots section) ---------------------------------------------------------------------------

## The heroes a Bots command acts on: "all" (every bot), "team0" / "team1" (that team's bots) or a hero id.
static func bot_heroes(w: SimWorld, pick: String) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for b in w.bots:
		var h := w.get_unit(int(b.hero_id))
		if h == null:
			continue
		if pick == "all" or pick == "team%d" % h.team or pick == str(h.id):
			out.append(h)
	return out

## An item into the hero's bags (its stash when they are full). Returns false if both are full.
static func give_item(w: SimWorld, h: SimUnit, item_id: String) -> bool:
	if SimData.item(item_id).is_empty():
		return false
	var it := w.shop.new_item(item_id)
	it["owner"] = h.id
	var ok := w.shop.place_in_bags(h, it)
	if not ok:
		for i in h.stash.size():
			if h.stash[i] == null:
				h.stash[i] = it
				ok = true
				break
	if ok:
		w.shop.combine_all(h)
		h.refresh_stats()
	return ok

## All the hero's gold, gone (to watch a bot play from behind).
static func take_gold(w: SimWorld, h: SimUnit) -> void:
	h.gold_reliable = 0
	h.gold_unreliable = 0

## A bot's skill level (Passive .. Unfair) and its gold and experience bonus with it.
static func set_bot_skill(w: SimWorld, h: SimUnit, skill: String) -> void:
	var b := w.bot_for(h.id)
	if b != null:
		b.set_skill(skill)

## A bot that stands still and gives no orders (a training dummy), or plays again.
static func set_bot_still(w: SimWorld, h: SimUnit, on: bool) -> void:
	var b := w.bot_for(h.id)
	if b == null:
		return
	b.passive = on
	if on:
		w.orders.clear(h)

## A teamfight for benchmarks: the dead come back, every hero is refreshed and the two teams stand face to face across
## `centre` (Ancient Light to the south-west), five abreast. On the first call each hero is levelled to `lvl` (bots
## learn their own kits) and given the last five items of its first core bot build.
static func stage_fight(w: SimWorld, centre: Vector2, lvl: int, first: bool) -> void:
	w.debug_flags["brawl"] = true
	var i := [0, 0]
	for h in w.heroes:
		if not h.alive:
			w.respawn(h)
		if first:
			level_up(w, h, lvl - h.level)
			var kit: Dictionary = SimBotKits.BUILDS.get(String(h.def.id), {})
			var build: Array = (kit.get("core", [[]]) as Array)[0]
			var n := 0
			for k in range(build.size() - 1, -1, -1):
				if n >= 5:
					break
				var item := w.shop.new_item(String(build[k]))
				if item.is_empty():
					continue
				h.inventory[n] = item
				h.inventory[n]["owner"] = h.id
				n += 1
			h.refresh_stats()
		refresh(w, h)
		var side := -1.0 if h.team == C.DAWN else 1.0
		var k2: int = i[h.team]
		i[h.team] += 1
		teleport(w, h, centre + Vector2(side * 380.0, side * 380.0) + Vector2(1, -1).normalized() * (float(k2) - 2.0) * 160.0)
	w.vision.update()

## Jump the clock forward. Waves and camps that would have spawned in the skipped time are skipped too, so the jump
## does not flood the lanes.
static func skip_time(w: SimWorld, seconds: float) -> void:
	w.time += seconds
	if w.time >= 0.0:
		w.wave = int(floor(w.time / C.WAVE_INTERVAL)) + 1
		w.next_wave_at = w.wave * C.WAVE_INTERVAL
	while w.next_neutral_at <= w.time:
		w.next_neutral_at += C.NEUTRAL_SPAWN_INTERVAL

static func set_flag(w: SimWorld, flag: String, on: bool) -> void:
	if on:
		w.debug_flags[flag] = true
	else:
		w.debug_flags.erase(flag)
	if flag == "reveal":
		w.vision.reveal_all = on
	if flag == "passive_bot":
		for b in w.bots:
			b.passive = on and not w.get_unit(b.hero_id).player

## Upkeep for the per-tick flags, called by SimWorld.step while any flag is set.
static func tick(w: SimWorld) -> void:
	for h in w.heroes:
		if not h.player or not h.alive:
			continue
		if w.debug_flags.has("god"):
			h.hp = h.max_hp
		if w.debug_flags.has("free_spells"):
			h.mana = h.max_mana
			for aid in h.ability_ready.keys():
				if aid != "masterful_archery":
					h.ability_ready[aid] = C.LONG_AGO
			for it in h.inventory:
				if it != null:
					it["ready"] = C.LONG_AGO
