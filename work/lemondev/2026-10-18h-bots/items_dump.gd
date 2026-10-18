extends SceneTree
func _init() -> void:
	var out := {}
	for id in SimData.items():
		var d := SimData.item(id)
		out[id] = {"name": d.get("name"), "cost": d.get("cost"), "cat": d.get("category", ""), "parts": d.get("components", []),
			"stats": d.get("stats", {}), "use": d.get("use", ""), "passive": d.get("passive", d.get("passives", "")),
			"aura": d.get("aura", ""), "consumable": d.get("consumable", false), "recipe": d.get("recipe_cost", 0), "text": String(d.get("text", "")).substr(0, 140)}
	var f := FileAccess.open("res://work/lemondev/2026-10-18h-bots/items.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	quit()
