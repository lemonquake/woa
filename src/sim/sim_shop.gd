class_name SimShop
extends RefCounted
## Buying, selling, recipes and the stash. Inside the base shop's radius purchases go straight to the inventory
## (then the backpack); elsewhere they go to the stash, which empties into the hero's bags the next time they are in
## the shop's range. Unreliable gold is spent first. Full refund within 10 seconds of buying, half after.

const C = preload("res://src/sim/sim_const.gd")

var w: SimWorld

func _init(world: SimWorld) -> void:
	w = world

func in_shop(u: SimUnit) -> bool:
	return u.alive and u.pos.distance_to(w.map.shops[u.team]) <= C.SHOP_RADIUS or u.pos.distance_to(w.map.fountains[u.team]) <= C.SHOP_RADIUS

## What buying `item_id` would cost now: components the hero lacks plus the recipe.
func price(u: SimUnit, item_id: String) -> int:
	var d := SimData.item(item_id)
	if d.is_empty():
		return 0
	if (d.components as Array).is_empty():
		return int(d.cost)
	var owned := _owned_ids(u)
	var total := int(d.recipe_cost)
	for comp in d.components:
		var idx := owned.find(comp)
		if idx >= 0:
			owned.remove_at(idx)
		else:
			total += int(SimData.item(comp).cost)
	return total

func _owned_ids(u: SimUnit) -> Array:
	var out: Array = []
	for arr in [u.inventory, u.stash]:
		for it in arr:
			if it != null:
				out.append(it.id)
	return out

func buy(u: SimUnit, item_id: String) -> String:
	var d := SimData.item(item_id)
	if d.is_empty():
		return "Unknown item"
	var cost := price(u, item_id)
	if u.gold() < cost:
		return "Not enough gold"
	var here := in_shop(u)
	var comps: Array = d.components
	if comps.is_empty():
		if not _place(u, {"id": item_id, "charges": int(d.charges), "ready": 0.0, "bought": w.time}, here):
			return "Inventory full"
	else:
		# take the components we own out of the bags, then place the finished item
		var removed: Array = []
		for comp in comps:
			var taken = _take(u, comp)
			if taken != null:
				removed.append(taken)
		if not _place(u, {"id": item_id, "charges": int(d.charges), "ready": 0.0, "bought": w.time}, here):
			for r in removed:
				_place(u, r, here)
			return "Inventory full"
	_spend(u, cost)
	w.events.append({"t": "buy", "u": u.id, "item": item_id, "cost": cost})
	_combine_all(u)
	u.refresh_stats()
	return ""

func _spend(u: SimUnit, cost: int) -> void:
	var from_unrel := mini(cost, u.gold_unreliable)
	u.gold_unreliable -= from_unrel
	u.gold_reliable -= cost - from_unrel

func _take(u: SimUnit, item_id: String):
	for arr in [u.inventory, u.stash]:
		for i in arr.size():
			if arr[i] != null and arr[i].id == item_id:
				var it = arr[i]
				arr[i] = null
				return it
	return null

## Put an item into the bags (stacking consumables) or the stash.
func _place(u: SimUnit, it: Dictionary, in_range: bool) -> bool:
	var d := SimData.item(it.id)
	var lists: Array = [u.inventory] if in_range else [u.stash]
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

## Combine any finished recipe whose components are all in the bags (or stash when in range).
func _combine_all(u: SimUnit) -> void:
	var changed := true
	while changed:
		changed = false
		for id in SimData.items():
			var d := SimData.item(id)
			var comps: Array = d.components
			if comps.is_empty() or int(d.recipe_cost) > 0:
				continue
			var owned := _owned_ids(u)
			var ok := true
			for comp in comps:
				var idx := owned.find(comp)
				if idx < 0:
					ok = false
					break
				owned.remove_at(idx)
			if ok:
				for comp in comps:
					_take(u, comp)
				_place(u, {"id": id, "charges": 0, "ready": 0.0, "bought": w.time}, in_shop(u))
				changed = true

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
	for i in u.stash.size():
		if u.stash[i] != null and _place(u, u.stash[i], true):
			u.stash[i] = null
			_combine_all(u)
			u.refresh_stats()
