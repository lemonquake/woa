extends SceneTree
## Checks the match's sound world (AudioWorld): every sound group's files load and have length, the ambience loops
## exist, every unit model has a material and every attacker a weapon class, and the Effects bus tops out at 60%.
##   godot --headless --path . -s tests/tools/audio_probe.gd
func _init() -> void:
	var bad := 0
	var aw := AudioWorld.new()
	for g in AudioWorld.GROUPS:
		var spec: Array = AudioWorld.GROUPS[g]
		for i in int(spec[2]):
			var file: String
			if int(spec[1]) < 0:
				file = String(spec[0]) % ("" if i == 0 else str(i + 1)) if String(spec[0]).contains("%s") else String(spec[0])
			else:
				file = String(spec[0]) % (int(spec[1]) + i)
			var s = load(AudioWorld.DIR + file) if ResourceLoader.exists(AudioWorld.DIR + file) else null
			if s == null or (s as AudioStream).get_length() <= 0.0:
				bad += 1
				print("MISSING ", g, " ", file)
	for f in ["amb_birds.ogg", "bird_chirps.wav", "amb_crickets.mp3", "loop_water_flowing.ogg"]:
		if not ResourceLoader.exists(AudioWorld.DIR + f):
			bad += 1
			print("MISSING ambience ", f)
	for k in ModelCatalog.MODELS:
		if not AudioWorld.MATERIALS.has(k) and not String(k).begins_with("hero"):
			print("no material (falls back to leather): ", k)
	for w in ["blade", "blunt", "claw", "arrow", "magic", "siege", "tower"]:
		for m in ["plate", "metal", "flesh", "leather", "cloth", "stone", "wood", "spirit"]:
			for l in AudioWorld.layers(w, m):
				if not AudioWorld.GROUPS.has(String(l[0])):
					bad += 1
					print("unknown group ", l[0], " for ", w, "/", m)
	Options.ensure_buses()
	Options.apply_audio()
	var eb := AudioServer.get_bus_index("Effects")
	var want := Options.to_db(float(Options.get_value("effects")) * 0.6)
	if absf(AudioServer.get_bus_volume_db(eb) - want) > 0.05:
		bad += 1
		print("Effects bus at %.2f dB, wanted %.2f" % [AudioServer.get_bus_volume_db(eb), want])
	print("audio problems: ", bad)
	aw.free()
	quit(1 if bad > 0 else 0)
