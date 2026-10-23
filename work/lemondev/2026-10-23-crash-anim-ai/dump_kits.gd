extends SceneTree
## Every hero's stats and kit (names, behaviour, descriptions) and the items by cost, for writing the bots' knowledge.

func _init() -> void:
	for id in GameSettings.HEROES:
		var d := SimData.unit(String(id))
		print("## %s (%s) %s range %d move %d primary %s element %s" % [id, d.get("name", ""), d.get("title", ""),
			int(d.get("range", 0)), int(d.get("move_speed", 0)), d.get("primary", ""), str(d.get("element", ""))])
		var all: Array = (d.get("abilities", []) as Array).duplicate()
		if d.has("innate"):
			all.push_front(d.innate)
		for a in all:
			var ad := SimData.ability(String(a))
			print("  - %s [%s, %s]: %s" % [ad.get("name", a), a, ad.get("behavior", ""), String(ad.get("desc", "")).left(260)])
	print("## ITEMS")
	var items: Array = []
	for k in SimData._items:
		var it := SimData.item(String(k))
		items.append([int(it.get("cost", 0)), String(k), String(it.get("name", ""))])
	items.sort()
	for it in items:
		print("  %5d %s %s" % it)
	quit()
