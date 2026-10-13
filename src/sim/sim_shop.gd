class_name SimShop
extends RefCounted
## Buying, selling, recipes, the stash and the To Buy list. Inside the base shop's radius purchases go straight to
## the inventory (then the stash); elsewhere they go to the stash, which empties into the hero's bags when they come
## into the shop's range (or by Grab All). In the base, items move freely between the bags and the stash. Stashed
## items can be sold from anywhere. Unreliable gold is spent first. Full refund within 10 seconds of buying, half after.
##
## To Buy (Dota's quick buy): Shift + click in the shop adds an item broken into the parts still missing. An entry set
## to auto-buy is bought the moment gold allows; if the hero is away from the shop and the courier waits at the
## fountain, the courier takes it (otherwise the stash does). Entries leave the list when bought.
##
## Recipes work as in Dota: an item is built from its parts plus, when its recipe costs gold, a recipe scroll.
## Buying an item buys only the parts the hero does not already own (looking inside partly built parts too), as
## separate pieces, and the pieces combine at once wherever all of them are together: in the inventory, in the
## stash, or across both while the hero stands in the shop. Some items have several recipes (Switch Boots).

const C = preload("res://src/sim/sim_const.gd")

var w: SimWorld

func _init(world: SimWorld) -> void:
	w = world

func in_shop(u: SimUnit) -> bool:
	return u.alive and u.pos.distance_to(w.map.shops[u.team]) <= C.SHOP_RADIUS or u.pos.distance_to(w.map.fountains[u.team]) <= C.SHOP_RADIUS

## Every way to build an item: lists of part ids, the recipe scroll included when the recipe costs gold. Empty for
## a basic item.
static func recipe_sets(item_id: String) -> Array:
	var d := SimData.item(item_id)
	if d.is_empty() or (d.components as Array).is_empty():
		return []
	var sets: Array = d.get("recipes", [d.components])
	var out: Array = []
	for s in sets:
		var parts: Array = (s as Array).duplicate()
		if int(d.recipe_cost) > 0:
			parts.append("recipe_" + item_id)
		out.append(parts)
	return out

## The pieces buying `item_id` would purchase now: the cheapest way to fill in what the hero does not own.
func plan(u: SimUnit, item_id: String) -> Array:
	var owned := _owned_ids(u)
	# a second copy of something already owned is bought whole: only its parts count as owned
	var sets := recipe_sets(item_id)
	if sets.is_empty():
		return [item_id]
	var best: Array = []
	var best_cost := INF
	for s in sets:
		var left := owned.duplicate()
		var pieces: Array = []
		for part in s:
			pieces.append_array(_missing(part, left))
		var cost := _cost_of(pieces)
		if cost < best_cost:
			best_cost = cost
			best = pieces
	return best

func _missing(item_id: String, owned: Array) -> Array:
	var idx := owned.find(item_id)
	if idx >= 0:
		owned.remove_at(idx)
		return []
	var sets := recipe_sets(item_id)
	if sets.is_empty():
		return [item_id]
	var best: Array = []
	var best_cost := INF
	var best_owned: Array = []
	for s in sets:
		var left := owned.duplicate()
		var pieces: Array = []
		for part in s:
			pieces.append_array(_missing(part, left))
		var cost := _cost_of(pieces)
		if cost < best_cost:
			best_cost = cost
			best = pieces
			best_owned = left
	owned.assign(best_owned)
	return best

func _cost_of(pieces: Array) -> int:
	var t := 0
	for p in pieces:
		t += int(SimData.item(p).cost)
	return t

## What buying `item_id` would cost now: the parts the hero lacks plus the recipe.
func price(u: SimUnit, item_id: String) -> int:
	var d := SimData.item(item_id)
	if d.is_empty():
		return 0
	if (d.components as Array).is_empty():
		return int(d.cost)
	return _cost_of(plan(u, item_id))

func _owned_ids(u: SimUnit) -> Array:
	var out: Array = []
	for arr in [u.inventory, u.stash, u.courier_items]:
		for it in arr:
			if it != null:
				out.append(it.id)
	return out

## Whether the hero has this item anywhere (bags or stash).
func owns(u: SimUnit, item_id: String) -> bool:
	return _owned_ids(u).has(item_id)

## Why the item cannot be bought at all right now ("" = it can, gold aside).
func buy_error(u: SimUnit, item_id: String) -> String:
	var d := SimData.item(item_id)
	if d.is_empty():
		return "Unknown item"
	if w.time < float(d.get("available_at", -INF)):
		return "Not available until %d:00" % int(float(d.available_at) / 60.0)
	if String(d.get("grants", "")) == "shard" and u.shard:
		return "Already upgraded"
	return ""

func new_item(item_id: String) -> Dictionary:
	var d := SimData.item(item_id)
	return {"id": item_id, "charges": int(d.charges), "ready": C.LONG_AGO, "bought": w.time}

## to_courier: an auto-buy; away from the shop, a courier waiting at the fountain takes the pieces before the stash.
func buy(u: SimUnit, item_id: String, to_courier := false) -> String:
	var err := buy_error(u, item_id)
	if err != "":
		return err
	var d := SimData.item(item_id)
	var cost := price(u, item_id)
	if u.gold() < cost:
		return "Not enough gold"
	var here := in_shop(u)
	if item_id == "tp_scroll" and here:
		# Teleport Scrolls live in their own slot; bought away from the shop one waits in the stash like any item
		# (the courier brings it), as in Dota
		u.tp_charges += 1
		_spend(u, cost)
		w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost})
		return ""
	if bool(d.get("consume_on_buy", false)):
		# the Upgrade Gem is used the moment it is bought
		_spend(u, cost)
		if String(d.get("grants", "")) == "shard":
			u.shard = true
		w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost})
		u.refresh_stats()
		return ""
	var pieces := plan(u, item_id)
	var courier: SimUnit = w.get_unit(u.courier_id) if to_courier and not here else null
	if courier != null and not w.courier_at_base(courier):
		courier = null
	# place every piece, combining as soon as parts meet; undo it all if the bags and stash run out of room
	var inv_before := _copy_items(u.inventory)
	var stash_before := _copy_items(u.stash)
	var cour_before := _copy_items(u.courier_items)
	for p in pieces:
		var it := new_item(p)
		it["owner"] = u.id
		var placed := false
		if courier != null:
			placed = _place_in(u.courier_items, it)
		if not placed:
			placed = _place(u, it, here)
		if not placed:
			_restore(u.inventory, inv_before)
			_restore(u.stash, stash_before)
			_restore(u.courier_items, cour_before)
			return "Inventory full"
		combine_all(u)
	_spend(u, cost)
	w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost, "courier": courier != null})
	_bought(u, item_id, pieces)
	u.refresh_stats()
	return ""

## Write saved items back into the same array (the courier's bags are shared by reference with its hero).
func _restore(arr: Array, saved: Array) -> void:
	for i in arr.size():
		arr[i] = saved[i]

func _place_in(arr: Array, it: Dictionary) -> bool:
	var d := SimData.item(it.id)
	if bool(d.consumable):
		for o in arr:
			if o != null and o.id == it.id:
				o.charges = int(o.charges) + int(it.charges)
				return true
	var i := arr.find(null)
	if i < 0:
		return false
	arr[i] = it
	return true

# ---- To Buy -----------------------------------------------------------------------------------------------------------

## Shift + click: add the item, broken into the pieces still missing (parts already listed count as owned).
## Returns "" or why nothing was added.
func add_to_buy(u: SimUnit, item_id: String) -> String:
	var d := SimData.item(item_id)
	if d.is_empty():
		return "Unknown item"
	var listed: Array = u.to_buy.map(func(e): return String(e.id))
	var saved_courier := u.courier_items
	# plan as if the listed pieces were already owned, so a second Shift-click adds only what is still missing
	var pieces: Array
	if (d.components as Array).is_empty() or bool(d.get("consume_on_buy", false)):
		pieces = [item_id]
	else:
		var extra := listed.map(func(x): return {"id": x})
		u.courier_items = saved_courier + extra
		pieces = plan(u, item_id)
		u.courier_items = saved_courier
	if pieces.is_empty():
		return "You already have the parts"
	if u.to_buy.size() + pieces.size() > C.TO_BUY_MAX:
		return "To Buy is full"
	for p in pieces:
		u.to_buy.append({"id": String(p), "auto": false})
	w.events.append({"t": "to_buy", "u": u.id, "item": item_id})
	return ""

func remove_to_buy(u: SimUnit, idx: int) -> void:
	if idx >= 0 and idx < u.to_buy.size():
		u.to_buy.remove_at(idx)

## Right click on an entry: buy it automatically as soon as there is gold for it (again to stop).
func toggle_auto_buy(u: SimUnit, idx: int) -> void:
	if idx >= 0 and idx < u.to_buy.size():
		u.to_buy[idx].auto = not bool(u.to_buy[idx].auto)

## Left click on an entry: buy it now.
func buy_listed(u: SimUnit, idx: int) -> String:
	if idx < 0 or idx >= u.to_buy.size():
		return "No item"
	return buy(u, String(u.to_buy[idx].id), true)

## Every few ticks: buy the first auto entry that gold allows (one per call, in list order).
func auto_buy(u: SimUnit) -> void:
	for i in u.to_buy.size():
		var e: Dictionary = u.to_buy[i]
		if not bool(e.auto):
			continue
		var id := String(e.id)
		if buy_error(u, id) != "" or u.gold() < price(u, id):
			continue
		if buy(u, id, true) == "":
			w.events.append({"t": "auto_buy", "u": u.id, "item": id})
			return

## A purchase took these pieces off the To Buy list (one entry each), and the item itself if it was listed.
func _bought(u: SimUnit, item_id: String, pieces: Array) -> void:
	for p in pieces + [item_id]:
		for i in u.to_buy.size():
			if String(u.to_buy[i].id) == String(p):
				u.to_buy.remove_at(i)
				break

func _copy_items(arr: Array) -> Array:
	var out: Array = []
	for it in arr:
		out.append((it as Dictionary).duplicate(true) if it != null else null)
	return out

func _spend(u: SimUnit, cost: int) -> void:
	var from_unrel := mini(cost, u.gold_unreliable)
	u.gold_unreliable -= from_unrel
	u.gold_reliable -= cost - from_unrel

## Put an item into the bags (stacking consumables) or the stash.
func _place(u: SimUnit, it: Dictionary, in_range: bool) -> bool:
	var d := SimData.item(it.id)
	var lists: Array = [u.inventory, u.stash] if in_range else [u.stash]
	if bool(d.consumable):
		for arr in lists + [u.inventory]:
			for i in arr.size():
				var o = arr[i]
				if o != null and o.id == it.id:
					o.charges = int(o.charges) + int(it.charges)
					return true
	for arr in lists:
		for i in arr.size():
			if arr[i] == null:
				arr[i] = it
				return true
	return false

## The groups of slots whose items combine with each other: inventory and stash together while in the shop,
## otherwise each on its own; the courier's bags on their own.
func _pools(u: SimUnit) -> Array:
	var out: Array = [[u.inventory, u.stash]] if in_shop(u) else [[u.inventory], [u.stash]]
	if not u.courier_items.is_empty():
		out.append([u.courier_items])
	return out

## Combine every item whose parts (and recipe scroll) are all in one pool, until nothing more combines. Items are
## tried in data order; the result takes the slot of its first part.
func combine_all(u: SimUnit) -> void:
	_absorb_tp(u)
	var changed := true
	var guard := 0
	while changed and guard < 32:
		changed = false
		guard += 1
		for id in SimData.items():
			for parts in recipe_sets(id):
				for pool in _pools(u):
					if _combine(u, id, parts, pool):
						changed = true
						break
				if changed:
					break
			if changed:
				break

func _combine(u: SimUnit, id: String, parts: Array, pool: Array) -> bool:
	var found: Array = []                        # [array, index]
	for part in parts:
		var hit := false
		for arr in pool:
			for i in (arr as Array).size():
				var it = arr[i]
				if it == null or it.id != part:
					continue
				var taken := false
				for f in found:
					if f[0] == arr and f[1] == i:
						taken = true
						break
				if taken:
					continue
				found.append([arr, i])
				hit = true
				break
			if hit:
				break
		if not hit:
			return false
	var res := new_item(id)
	res["owner"] = u.id
	var d := SimData.item(id)
	# Switch Boots start on the attribute of the part they were built with
	var attr_from: Dictionary = d.get("attr_from", {})
	for part in parts:
		if attr_from.has(part):
			res["attr"] = attr_from[part]
	for f in found:
		f[0][f[1]] = null
	var first: Array = found[0]
	first[0][first[1]] = res
	w.events.append({"t": "combine", "u": u.id, "item": id})
	return true

func sell(u: SimUnit, slot: int) -> String:
	if slot < 0 or slot >= u.inventory.size() or u.inventory[slot] == null:
		return "No item"
	if not in_shop(u):
		return "Must be near a shop to sell"
	var it: Dictionary = u.inventory[slot]
	if int(it.get("owner", u.id)) != u.id:
		return "You do not own this item"
	u.inventory[slot] = null
	_refund(u, it)
	u.refresh_stats()
	return ""

## Stashed items can be sold from anywhere, as in Dota.
func sell_stash(u: SimUnit, i: int) -> String:
	if i < 0 or i >= u.stash.size() or u.stash[i] == null:
		return "No item"
	var it: Dictionary = u.stash[i]
	u.stash[i] = null
	_refund(u, it)
	return ""

func sell_value(it: Dictionary) -> int:
	var d := SimData.item(it.id)
	var value := int(d.cost)
	if bool(d.consumable):
		value = int(float(d.cost) * float(it.charges) / maxf(1.0, float(d.charges)))
	return value if w.time - float(it.get("bought", -99.0)) <= 10.0 else value / 2

func _refund(u: SimUnit, it: Dictionary) -> void:
	var refund := sell_value(it)
	u.gold_unreliable += refund
	w.events.append({"t": "sell", "u": u.id, "item": it.id, "gold": refund})

## Swap two of the hero's nine slots (drag and drop, or right click to and from the backpack). An item that leaves the
## backpack for a main slot waits 6 seconds before it can be used, as in Dota.
func swap(u: SimUnit, a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= u.inventory.size() or b >= u.inventory.size() or a == b:
		return
	var t = u.inventory[a]
	u.inventory[a] = u.inventory[b]
	u.inventory[b] = t
	for pair in [[a, b], [b, a]]:
		var it = u.inventory[pair[1]]
		if it != null and pair[0] >= 6 and pair[1] < 6 and float(SimData.item(it.id).cooldown) > 0.0:
			it.ready = maxf(float(it.get("ready", C.LONG_AGO)), w.time + C.BACKPACK_SWAP_COOLDOWN)
	u.refresh_stats()

## In the base: move a bag item into the stash.
func to_stash(u: SimUnit, slot: int) -> String:
	if slot < 0 or slot >= u.inventory.size() or u.inventory[slot] == null:
		return "No item"
	if not in_shop(u):
		return "Must be in the base"
	var i := u.stash.find(null)
	if i < 0:
		return "Stash is full"
	u.stash[i] = u.inventory[slot]
	u.inventory[slot] = null
	u.refresh_stats()
	return ""

## In the base: move one stashed item into the bags (to a given slot, swapping with what is there, or the first free).
func from_stash(u: SimUnit, i: int, slot := -1) -> String:
	if i < 0 or i >= u.stash.size() or u.stash[i] == null:
		return "No item"
	if not in_shop(u) and u.alive:
		return "Must be in the base"
	var it: Dictionary = u.stash[i]
	if slot >= 0 and slot < u.inventory.size():
		u.stash[i] = u.inventory[slot]
		u.inventory[slot] = it
	else:
		u.stash[i] = null
		if not place_in_bags(u, it):
			u.stash[i] = it
			return "Inventory full"
	combine_all(u)
	u.refresh_stats()
	return ""

## Grab All: every stashed item that fits goes into the bags (in the base, or while dead).
func grab_all(u: SimUnit) -> String:
	if not in_shop(u) and u.alive:
		return "Must be in the base"
	var moved := false
	for i in u.stash.size():
		var it = u.stash[i]
		if it == null:
			continue
		u.stash[i] = null
		if place_in_bags(u, it):
			moved = true
		else:
			u.stash[i] = it
	combine_all(u)
	u.refresh_stats()
	return "" if moved else "Nothing to take"

## Called every half second for heroes: the stash empties into the bags when the hero arrives in the shop's range
## (afterwards items stay where the player puts them), and parts in reach combine.
func update(u: SimUnit) -> void:
	var here := in_shop(u)
	var arrived := here and not u.was_in_shop
	u.was_in_shop = here
	if not here:
		return
	if arrived:
		var moved := false
		for i in u.stash.size():
			if u.stash[i] != null:
				var it = u.stash[i]
				u.stash[i] = null
				if place_in_bags(u, it):
					moved = true
				else:
					u.stash[i] = it
		if moved:
			u.refresh_stats()
	combine_all(u)

## Teleport Scrolls that reach the hero's bags (from the stash or the courier) go into the Teleport slot.
func _absorb_tp(u: SimUnit) -> void:
	if not u.is_hero():
		return
	for i in u.inventory.size():
		var it = u.inventory[i]
		if it != null and it.id == "tp_scroll":
			u.tp_charges += maxi(1, int(it.get("charges", 1)))
			u.inventory[i] = null

## Teleport Scrolls the hero has anywhere: its slot, bags, stash and courier.
func tp_owned(u: SimUnit) -> int:
	var n := u.tp_charges
	for arr in [u.inventory, u.stash, u.courier_items]:
		for it in arr:
			if it != null and it.id == "tp_scroll":
				n += maxi(1, int(it.get("charges", 1)))
	return n

func place_in_bags(u: SimUnit, it: Dictionary) -> bool:
	var d := SimData.item(it.id)
	if it.id == "tp_scroll" and u.is_hero():
		u.tp_charges += maxi(1, int(it.get("charges", 1)))
		return true
	if bool(d.consumable):
		for o in u.inventory:
			if o != null and o.id == it.id:
				o.charges = int(o.charges) + int(it.charges)
				return true
	for i in u.inventory.size():
		if u.inventory[i] == null:
			u.inventory[i] = it
			return true
	return false
