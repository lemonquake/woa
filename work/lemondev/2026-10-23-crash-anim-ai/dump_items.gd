extends SceneTree
func _init() -> void:
	SimData.item("boots")
	for k in SimData._items:
		var it := SimData.item(String(k))
		if int(it.get("cost", 0)) < 1400 and not (String(k) in ["jump_knife", "glimmer_cape", "push_staff", "sneak_charm", "reveal_dust", "reveal_ward", "observer_ward", "magic_wand", "bottle", "dodge_charm"]):
			continue
		if String(k).begins_with("recipe"):
			continue
		print("%s|%s|%d|use=%s|passive=%s|aura=%s|stats=%s" % [k, it.get("name", ""), int(it.get("cost", 0)), str(it.get("use", "")),
			str(it.get("passive", "")), str(it.get("aura", {}).get("name", "") if it.get("aura") is Dictionary else ""),
			str(it.get("stats", {}).keys())])
	quit()
