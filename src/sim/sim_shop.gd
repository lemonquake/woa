class_name SimShop
extends RefCounted
## Buying, selling, recipes and the stash. Inside the base shop's radius purchases go straight to the inventory
## (then the stash); elsewhere they go to the stash, which empties into the hero's bags the next time they are in
## the shop's range. Unreliable gold is spent first. Full refund within 10 seconds of buying, half after.
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
	for arr in [u.inventory, u.stash]:
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

func buy(u: SimUnit, item_id: String) -> String:
	var err := buy_error(u, item_id)
	if err != "":
		return err
	var d := SimData.item(item_id)
	var cost := price(u, item_id)
	if u.gold() < cost:
		return "Not enough gold"
	var here := in_shop(u)
	if item_id == "tp_scroll":
		# Town Portal scrolls live in their own slot
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
	# place every piece, combining as soon as parts meet; undo it all if the bags and stash run out of room
	var inv_before := _copy_items(u.inventory)
	var stash_before := _copy_items(u.stash)
	for p in pieces:
		if not _place(u, new_item(p), here):
			u.inventory = inv_before
			u.stash = stash_before
			return "Inventory full"
		_combine_all(u)
	_spend(u, cost)
	w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost})
	u.refresh_stats()
	return ""

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
## otherwise each on its own.
func _pools(u: SimUnit) -> Array:
	if in_shop(u):
		return [[u.inventory, u.stash]]
	return [[u.inventory], [u.stash]]

## Combine every item whose parts (and recipe scroll) are all in one pool, until nothing more combines. Items are
## tried in data order; the result takes the slot of its first part.
func _combine_all(u: SimUnit) -> void:
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
	var d := SimData.item(it.id)
	var value := int(d.cost)
	if bool(d.consumable):
		value = int(float(d.cost) * float(it.charges) / maxf(1.0, float(d.charges)))
	var refund := value if w.time - float(it.get("bought", -99.0)) <= 10.0 else value / 2
	u.inventory[slot] = null
	u.gold_unreliable += refund
	w.events.append({"t": "sell", "u": u.id, "item": it.id, "gold": refund})
	u.refresh_stats()
	return ""

func swap(u: SimUnit, a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= u.inventory.size() or b >= u.inventory.size():
		return
	var t = u.inventory[a]
	u.inventory[a] = u.inventory[b]
	u.inventory[b] = t
	u.refresh_stats()

## Called every tick for heroes: the stash empties into the bags while in the shop's range.
func update(u: SimUnit) -> void:
	if not in_shop(u):
		return
	var moved := false
	for i in u.stash.size():
		if u.stash[i] != null:
			var it = u.stash[i]
			u.stash[i] = null
			if _place_bags(u, it):
				moved = true
			else:
				u.stash[i] = it
	_combine_all(u)
	if moved:
		u.refresh_stats()

func _place_bags(u: SimUnit, it: Dictionary) -> bool:
	var d := SimData.item(it.id)
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
