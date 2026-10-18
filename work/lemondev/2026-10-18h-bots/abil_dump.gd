extends SceneTree
func _init() -> void:
	for hid in GameSettings.HEROES:
		var d := SimData.unit(hid)
		var line := "%s:" % hid
		for aid in d.get("abilities", []):
			var a := SimData.ability(String(aid))
			var vals: Dictionary = a.get("values", {})
			var keys := []
			for k in vals:
				if String(k).contains("radius") or String(k).contains("damage") or String(k).contains("width"):
					keys.append("%s=%s" % [k, str(vals[k]).substr(0, 22)])
			line += "\n   %s [%s] mana %s cd %s %s" % [aid, a.get("behavior", ""), str(a.get("mana", "")).substr(0, 20), str(a.get("cooldown", "")).substr(0, 20), " ".join(keys)]
		print(line)
	quit()
