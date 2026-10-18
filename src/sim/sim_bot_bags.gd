class_name SimBotBags
extends RefCounted
## A bot's bags (run 2026-10-18 h; the owner saw bots carrying useless items into the late game, never selling them,
## backpacks full of parts that never became an item, and gold left unspent). What every held item is worth now,
## which ones to sell and how (at the shop, from the stash anywhere, or handed to the courier to take home), which six
## ride in the main slots, parts bought ahead when the whole item is out of reach, and what to buy once the build
## list runs out. Ordinary Dota habits:
##   * early items (twigs, Headbands, bands, the Zap Wand, the Mini-Axe on a hero who no longer farms trees) are worth
##     their slot for the first 10-35 minutes and are sold when a better item needs the room;
##   * a spare pair of boots, a part of nothing still planned, food and potions late are sold;
##   * the most valuable items and every item with an active ride in the six main slots, the rest in the backpack;
##   * with gold short of the next item, its most expensive part that fits is bought now (its stats work at once);
##   * past the planned build, each kind of hero keeps buying what such heroes buy (LATE), keeping buyback gold late.

const C = preload("res://src/sim/sim_const.gd")
const KITS = preload("res://src/sim/sim_bot_kits.gd")

## Early items: the second the item stops being worth its slot (it fades from half that time).
const EARLY := {
	"branch": 900.0, "tango": 1200.0, "faerie_fire": 1080.0, "clarity": 1200.0, "mango": 1200.0, "salve": 1500.0,
	"circlet": 1200.0, "slippers": 1200.0, "gauntlets": 1200.0, "mantle": 1200.0, "magic_stick": 1200.0,
	"ring_protection": 1500.0, "ring_regen": 1500.0, "sobi_mask": 1500.0, "quelling_blade": 1500.0,
	"gold_band": 1800.0, "fur_hat": 1800.0, "pointy_hat": 1800.0, "speed_ribbon": 1800.0, "mana_ring": 1800.0,
	"wraith_band": 2100.0, "tough_band": 2100.0, "smart_band": 2100.0, "small_shield": 2100.0, "leaf_hat": 2100.0,
	"magic_wand": 2400.0, "bottle": 2400.0,
}
## Boots, worst first: a hero keeps only its best pair.
const BOOTS := ["boots", "power_treads", "slip_boots", "mana_boots", "guard_boots", "travel_boots"]
## Carried for the team or for sight: kept while useful, never counted as junk.
const KEEP := ["observer_ward", "reveal_ward", "reveal_dust", "tp_scroll"]

## What each kind of hero buys after its planned build (Dota habits; situational counters still come first,
## SimBotItems). Kinds: str_melee, agi_melee, ranged (right-clickers at range), caster (intelligence cores),
## support.
const LATE := {
	"str_melee": ["spell_shield", "giant_heart", "battle_armor", "stun_blade", "halberd", "leech_blade", "twin_swords",
		"crash_knife", "travel_boots", "refresh_stone", "moth_blade"],
	"agi_melee": ["twin_swords", "crit_bow", "leech_blade", "moth_blade", "armor_breaker", "spell_shield",
		"storm_hammer", "sure_hit_staff", "battle_armor", "travel_boots", "break_blade"],
	"ranged": ["dragon_lance", "crit_bow", "sure_hit_staff", "moth_blade", "storm_hammer", "armor_breaker",
		"spell_shield", "burning_cape", "leech_blade", "travel_boots", "battle_armor"],
	"caster": ["glimmer_cape", "hex_staff", "refresh_stone", "time_crystal", "long_lens", "kugmo_atuli", "spell_shield",
		"net_staff", "frost_plate", "travel_boots", "dagon"],
	"support": ["glimmer_cape", "push_staff", "guard_boots", "team_shield", "war_drum", "net_staff", "hex_staff",
		"frost_plate", "refresh_stone", "travel_boots", "time_crystal"],
}

## Pieces that do the same job: a hero owning one skips the others in LATE (two crit items, two lifesteal blades).
const SAME_JOB := [["crit_sword", "crit_bow"], ["leech_blade", "mask_of_madness"], ["battle_armor", "spike_armor"],
	["moth_blade", "burning_cape", "halberd"], ["twin_swords", "heavy_sword", "yasha"], ["kugmo_atuli", "spell_sword"],
	["glimmer_cape", "spell_shield"]]

static func kind_of(h: SimUnit, role: int) -> String:
	if KITS.is_support(role):
		return "support"
	var attr := String(h.def.get("primary", "str"))
	if attr == "int":
		return "caster"
	if h.is_ranged():
		return "ranged"
	return "agi_melee" if attr == "agi" else "str_melee"

# ---- Parts ------------------------------------------------------------------------------------------------------------

static var _parts_cache := {}

## Every item that goes into `item_id`, all the way down (recipes left out).
static func all_parts(item_id: String) -> Array:
	if _parts_cache.has(item_id):
		return _parts_cache[item_id]
	var out: Array = []
	for set_ in SimShop.recipe_sets(item_id):
		for p in set_:
			var pid := String(p)
			if pid.begins_with("recipe_") or pid in out:
				continue
			out.append(pid)
			for q in all_parts(pid):
				if not (q in out):
					out.append(q)
	_parts_cache[item_id] = out
	return out

## The items still to buy in the next few steps of the build (what parts are kept for).
static func planned(b, h: SimUnit, ahead := 3) -> Array:
	var out: Array = []
	var i: int = b._build_i
	while i < b.build.size() and out.size() < ahead:
		var id := String(b.build[i])
		if not b.w.shop.owns(h, id):
			out.append(id)
		i += 1
	return out

static func is_planned_part(b, h: SimUnit, id: String) -> bool:
	var target := id.trim_prefix("recipe_") if id.begins_with("recipe_") else ""
	for p in planned(b, h):
		var parts := all_parts(String(p))
		if id == p or id in parts or target == String(p) or (target != "" and target in parts):
			return true
	return false

# ---- Worth ------------------------------------------------------------------------------------------------------------

## What keeping `it` is worth to the hero now, in gold (0: dead weight).
static func worth(b, h: SimUnit, it: Dictionary) -> float:
	var w: SimWorld = b.w
	var id := String(it.id)
	var d := SimData.item(id)
	var cost := float(d.get("cost", 0))
	if id in KEEP:
		return 4000.0 if KITS.is_support(b.role) or id == "reveal_dust" else 150.0
	if bool(it.get("home", false)):
		return 0.0                         # junk on its way home
	if is_planned_part(b, h, id):
		return cost + 6000.0
	# a spare pair of boots
	var bi := BOOTS.find(id)
	if bi >= 0:
		var others := 0
		for o in h.inventory:
			if o != null and o != it and String(o.id) in BOOTS:
				others += 1
				if BOOTS.find(String(o.id)) > bi:
					return 0.0
		if others == 0:
			return cost + 3000.0           # its only pair: never sold
	if EARLY.has(id):
		var end := float(EARLY[id])
		# melee cores keep the Mini-Axe while they still farm trees and camps
		if id == "quelling_blade" and not h.is_ranged() and not KITS.is_support(b.role):
			end = 2100.0
		var f := clampf(1.0 - (w.time - end * 0.5) / (end * 0.5), 0.0, 1.0)
		return cost * f
	if bool(d.get("consumable", false)):
		return cost
	# a part of nothing planned: its own stats, fading as the game grows
	var sets := SimShop.recipe_sets(id)
	if sets.is_empty() and String(d.get("use", "")) == "":
		return cost * clampf(1.0 - (w.time - 900.0) / 2400.0, 0.3, 1.0)
	# an item with an active is worth more than its price says
	return cost * (1.25 if String(d.get("use", "")) != "" else 1.0)

## The worth below which an item is sold when its slot is wanted (it rises with the game).
static func bar(time: float) -> float:
	if time < 720.0:
		return 0.0
	if time < 1200.0:
		return 150.0
	if time < 1800.0:
		return 450.0
	if time < 2400.0:
		return 1000.0
	return 1600.0

## Free bag slots (main and backpack).
static func free_slots(h: SimUnit) -> int:
	return h.inventory.count(null)

## The bags want room: few free slots for what waits to come in (stash, courier). The pieces of one planned item
## count once (they combine into one item); junk riding home does not count.
static func crowded(b, h: SimUnit) -> bool:
	var waiting := 0
	var groups := {}
	var plan := planned(b, h)
	for arr in [h.stash, h.courier_items]:
		for it in arr:
			if it == null or bool(it.get("home", false)):
				continue
			var id := String(it.id)
			var tid := id.trim_prefix("recipe_") if id.begins_with("recipe_") else ""
			var grouped := false
			for p in plan:
				var parts := all_parts(String(p))
				if id in parts or tid == String(p) or (tid != "" and tid in parts):
					groups[p] = true
					grouped = true
					break
			if not grouped:
				waiting += 1
	waiting += groups.size()
	return free_slots(h) <= maxi(1, waiting)

## The most an item waiting to come in (stash, courier; not junk riding home) is worth: a full bag gives up its
## weakest item for it.
static func incoming(b, h: SimUnit) -> float:
	var best := 0.0
	for arr in [h.stash, h.courier_items]:
		for it in arr:
			if it != null and not bool(it.get("home", false)):
				best = maxf(best, float(SimData.item(String(it.id)).get("cost", 0)))   # its own price, not its plan
	# every piece of the next item bought (in the stash, on the courier, in the bags): it is worth the whole item
	for p in planned(b, h, 1):
		if b.w.shop.price(h, String(p)) <= 0:
			best = maxf(best, float(SimData.item(String(p)).get("cost", 0)))
	return best

## The bag slot to sell first, or -1: an item worth nothing at all, or (when the bags want room) the least worth one
## under the bar or well under what waits to come in. Locked items and planned parts are left alone.
static func junk_slot(b, h: SimUnit, need_room: bool) -> int:
	var cap := bar(b.w.time)
	if need_room:
		cap = maxf(cap, incoming(b, h) * 0.6)
	var worst := -1
	var worst_v := INF
	for i in h.inventory.size():
		var it = h.inventory[i]
		if it == null or bool(it.get("locked", false)) or int(it.get("owner", h.id)) != h.id or bool(it.get("home", false)):
			continue
		var v := worth(b, h, it)
		var cost := float(SimData.item(String(it.id)).get("cost", 0))
		var dead: bool = v <= cost * 0.12 and b.w.time >= 600.0
		if not dead and not (need_room and v < cap):
			continue
		if v < worst_v:
			worst_v = v
			worst = i
	return worst

# ---- Every think -----------------------------------------------------------------------------------------------------

## Sell, send home, sort. Returns true when it gave the hero an order (an item handed to the courier).
static func tidy(b, h: SimUnit) -> bool:
	var w: SimWorld = b.w
	if w.time < 0.0:
		return false
	var need := crowded(b, h)
	# junk in the stash sells from anywhere (half its price, as in Dota): what the courier brought home, and what is
	# worth nothing now
	for i in h.stash.size():
		var st = h.stash[i]
		if st == null:
			continue
		var sid := String(st.id)
		if bool(st.get("home", false)) or (worth(b, h, st) <= float(SimData.item(sid).get("cost", 0)) * 0.12
				and w.time >= 600.0 and not is_planned_part(b, h, sid)):
			if w.shop.sell_stash(h, i) == "":
				b.items_sold.append("%s(stash %s %s %s)" % [sid, "home" if bool(st.get("home", false)) else "dead", String(st.get("why", "")), w.clock_text()])
	# at the shop: sell what is worth nothing (any number), or the least worth item when room is wanted (one at a
	# time, five seconds apart: the bags are read again before the next)
	if w.shop.in_shop(h):
		var guard := 0
		while guard < 3:
			guard += 1
			var j := junk_slot(b, h, need)
			if j < 0:
				break
			var jit: Dictionary = h.inventory[j]
			var dead: bool = worth(b, h, jit) <= float(SimData.item(String(jit.id)).get("cost", 0)) * 0.12
			if not dead and w.time < b._next_room_sale:
				break
			if not dead:
				b._next_room_sale = w.time + 5.0
			var sold := "%s(shop worth %d need %s in %d %s)" % [String(h.inventory[j].id), roundi(worth(b, h, h.inventory[j])), need,
				roundi(incoming(b, h)), w.clock_text()]
			if w.shop.sell(h, j) != "":
				break
			b.items_sold.append(sold)
			need = crowded(b, h)
		# pieces left on the courier at the base: it brings them over, they combine with the stash and the bags
		var cb := w.get_unit(h.courier_id)
		if cb != null and cb.alive and cb.courier_state == "idle" and free_slots(h) > 0:
			for it in cb.inventory:
				if it != null and not bool(it.get("home", false)):
					w.courier_command(h, "transfer")
					break
		_arrange(b, h)
		return false
	# away from the shop with the bags crowded: junk goes to the courier when it is close (marked to ride home: the
	# courier never hands it back), the courier hands over what it brought, then takes the junk to the stash
	var c := w.get_unit(h.courier_id)
	if c != null and c.alive:
		var junk_on := false
		var good_on := false
		for it in c.inventory:
			if it != null:
				if bool(it.get("home", false)):
					junk_on = true
				else:
					good_on = true
		var near := h.edge_distance(c) <= C.COURIER_REACH
		var calm: bool = b.mode != "fight" and b.mode != "retreat"
		var j2 := junk_slot(b, h, true) if need else -1
		if calm and j2 >= 0 and c.inventory.find(null) >= 0 and c.courier_state in ["deliver", "transfer", "return", "idle"]:
			if near:
				h.inventory[j2]["home"] = true
				h.inventory[j2]["why"] = "worth %d in %d" % [roundi(worth(b, h, h.inventory[j2])), roundi(incoming(b, h))]
				w.command(h.id, {"type": C.Order.GIVE_ITEM, "item_slot": j2, "target": c.id})
				return true
			# what it carries cannot fit: call it over to swap the junk for it
			if good_on and free_slots(h) == 0 and c.courier_state in ["return", "idle"]:
				w.courier_command(h, "transfer")
		if junk_on and good_on and near and free_slots(h) > 0:
			w.courier_command(h, "transfer")
		elif junk_on and not good_on and c.courier_state in ["idle", "return"] and not near:
			w.courier_command(h, "stash")
	if b.mode != "fight" and b.mode != "retreat":
		_arrange(b, h)
	return false

## The six main slots carry the most valuable items (and every item with an active); one swap per think.
static func _arrange(b, h: SimUnit) -> void:
	var worst_main := -1
	var worst_v := INF
	for i in 6:
		var it = h.inventory[i]
		var v := -1.0 if it == null else _slot_value(b, h, it)
		if v < worst_v:
			worst_v = v
			worst_main = i
	var best_back := -1
	var best_v := -INF
	for i in range(6, h.inventory.size()):
		var it = h.inventory[i]
		if it == null:
			continue
		var v := _slot_value(b, h, it)
		if v > best_v:
			best_v = v
			best_back = i
	if best_back >= 0 and worst_main >= 0 and best_v > worst_v * 1.15 + 1.0:
		b.w.shop.swap(h, worst_main, best_back)

static func _slot_value(b, h: SimUnit, it: Dictionary) -> float:
	var id := String(it.id)
	var d := SimData.item(id)
	var v := worth(b, h, it)
	if id in KEEP:
		# wards and dust: in reach of a key, behind boots and real items; a support's Eye Ward rides up front (a
		# ward in the backpack is never placed)
		v = 2600.0 if id == "observer_ward" and KITS.is_support(b.role) else 700.0
	elif v >= 6000.0:
		v -= 6000.0                        # a planned part rides by its own stats, not its plan
	# actives in reach of a key; potions are used from the main slots only; boots move the hero
	if String(d.get("use", "")) != "" or bool(d.get("consumable", false)):
		v += 400.0
	if id in BOOTS:
		v += 900.0
	return v

# ---- Buying -----------------------------------------------------------------------------------------------------------

## Gold short of the next item: buy its most expensive part that the gold covers and the bags can take (two free
## slots away from the shop, so the courier can bring it). Returns the part bought, or "".
static func buy_part(b, h: SimUnit, item_id: String) -> String:
	var w: SimWorld = b.w
	if SimShop.recipe_sets(item_id).is_empty() or h.gold() < 250:
		return ""
	var here := w.shop.in_shop(h)
	if here:
		if free_slots(h) < 1 and h.stash.find(null) < 0:
			return ""
	elif h.stash.find(null) < 0 or free_slots(h) < 2:
		return ""
	var best := ""
	var best_c := 0
	for p in w.shop.plan(h, item_id):
		var pid := String(p)
		if pid.begins_with("recipe_"):
			continue
		var cost := w.shop.price(h, pid)
		if cost <= h.gold() and cost > best_c:
			best = pid
			best_c = cost
	if best == "" or w.shop.buy(h, best) != "":
		return ""
	return best

## The next item past the planned build, for this kind of hero ("" when nothing is left).
static func next_late(b, h: SimUnit) -> String:
	var w: SimWorld = b.w
	for id in LATE[kind_of(h, b.role)]:
		var sid := String(id)
		if w.shop.owns(h, sid) or sid in b.build:
			continue
		var clash := false
		for grp in SAME_JOB:
			if sid in grp:
				for o in grp:
					if o != sid and w.shop.owns(h, String(o)):
						clash = true
		if clash:
			continue
		# Travel Boots replace the hero's boots: only once its other boots are bought
		if sid == "travel_boots" and w.time < 1800.0:
			continue
		return sid
	return ""
