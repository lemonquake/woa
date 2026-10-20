extends SceneTree
## Prints careers, averages and profile talk from a ladder file (WOA_RANKED_FILE).
func _init() -> void:
	Ranked.load_data()
	var me := Ranked.me()
	print("ME career ", JSON.stringify(me.career))
	print("ME avg ", JSON.stringify(Career.averages(me)))
	print("ME read ", ProfileTalk.summary(ProfileTalk.read(me)))
	var b := Ranked.leaderboard()
	for i in [0, 5, 60, 150, 290]:
		var p: Dictionary = b[mini(i, b.size() - 1)]
		var c := Career.career(p)
		print("#%d %s %s mmr %d games %d mvps %d rp %d tr %d fb %d | avg %s lhm %.1f gpm %d lanes %s" % [i + 1, p.name, Ranked.rank_label(p), int(p.mmr), int(c.g), int(p.get("mvps", 0)), int(c.rp), int(c.tr), int(c.fb), Career.kda_text(Career.averages(p)), float(Career.averages(p).lhm), int(Career.averages(p).gpm), JSON.stringify(Career.fav_lanes(p))])
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 14:
		var v: Dictionary = Ranked.bots()[r.randi_range(0, Ranked.bots().size() - 1)]
		print("  [%s] %s: %s" % [ProfileTalk.manner_of(v), v.name, ProfileTalk.line_about(v, me, r)])
	for i in 6:
		var v2: Dictionary = Ranked.bots()[r.randi_range(0, 299)]
		var t: Dictionary = Ranked.bots()[r.randi_range(0, 299)]
		print("  about %s (%s): [%s] %s" % [t.name, Career.kda_text(Career.averages(t)), ProfileTalk.manner_of(v2), ProfileTalk.line_about(v2, t, r)])
	# MMR spread
	for e in [{"k": 10, "x": 0, "a": 10, "lh": 150}, {"k": 5, "x": 5, "a": 8, "lh": 90}, {"k": 1, "x": 9, "a": 3, "lh": 30}, {"k": 26, "x": 0, "a": 7, "lh": 0}]:
		print("perf %s win %+d loss %+d" % [JSON.stringify(e), Career.mmr_change(true, e), Career.mmr_change(false, e)])
	quit()
