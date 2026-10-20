extends SceneTree
## The owner's request (2026-10-20): "make my Rampages only 42. Matches should be around 1323 with some losses (should
## be around 60+% winrate)" (after "Make up some match stats for me (consistent no deaths, consistent with those
## averages) and make my MMR 4000"). Starts from the save as it was before the first fill (pass that file as
## WOA_RANKED_FILE) and makes:
##   * 1323 ranked matches, `--wins` of them won (default 820, 62%); no deaths in any;
##   * the last 60 shown in full on the profile: the 12 real ones and 48 made-up ones (about a third lost), each with
##     its MMR from Career.mmr_change, the graph ending at `--mmr` (default 4011);
##   * the 1263 before them counted only in the career, the record and hero medals (as a ladder player's are);
##   * rampages: your earlier record's (Edit profile) plus the matches' make `--rampages` (default 42);
##   * "Playing since" moved back so 1323 matches fit (about 330 days).
##   godot --headless --path . -s work/lemondev/2026-10-20-profile/tools/fill_career.gd -- [--matches=1323] [--wins=820]
##     [--mmr=4011] [--rampages=42] [--seed=11]

var avg := {}
var heroes := {}
var lanes := {}
var role := 2
var r := RandomNumberGenerator.new()

func _init() -> void:
	var total_m := 1323
	var total_w := 820
	var target := 4011
	var rampages := 42
	r.seed = 11
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() < 2:
			continue
		match kv[0]:
			"matches": total_m = int(kv[1])
			"wins": total_w = int(kv[1])
			"mmr": target = int(kv[1])
			"rampages": rampages = int(kv[1])
			"seed": r.seed = int(kv[1])
	Ranked.load_data()
	var me := Ranked.me()
	var real: Array = (me.history as Array).duplicate(true)
	real.reverse()                                      # oldest first
	if real.size() > 30 or real.is_empty():
		print("expected the save from before the first fill (%d ranked matches)" % real.size())
		quit(1)
		return
	var tracked := real.filter(func(e): return e.has("lh"))
	for k in ["k", "a", "lh", "gpm", "xpm", "hd", "bd", "nw", "len", "lvl", "db", "tr", "ul", "fb"]:
		var s := 0.0
		for e in tracked:
			s += float(e.get(k, 0))
		avg[k] = s / maxf(1.0, float(tracked.size()))
	for e in real:
		if String(e.get("h", "")) != "":
			heroes[String(e.h)] = int(heroes.get(String(e.h), 0)) + 1
		if e.has("ln"):
			lanes[String(e.ln)] = int(lanes.get(String(e.ln), 0)) + 1
	if lanes.is_empty():
		lanes = {"mid": 1}
	role = int((me.roles as Array)[0]) if not (me.roles as Array).is_empty() else 2
	# the real matches keep everything but their rampage count (a few)
	var real_rp := [2, 1, 0, 2]
	var ti := 0
	for e in real:
		if e.has("lh"):
			e["rp"] = int(real_rp[ti % real_rp.size()]) if int(e.get("rp", 0)) > 0 else 0
			e["ul"] = maxi(int(e.get("ul", 0)), int(e.rp))
			ti += 1
	# the 48 shown made-up matches, a third lost; then their MMR backwards from the target
	var shown_n := 60 - real.size()
	var shown: Array = []
	for i in shown_n:
		shown.append(_game(r.randf() >= 0.33))
	var all_shown: Array = shown + real
	var sum_d := 0
	for e in all_shown:
		if not e.has("d"):
			e["d"] = Career.mmr_change(String(e.r) == "W", e, role)
		sum_d += int(e.d)
	var start_mmr := target - sum_d
	# times: the shown made-up ones over the six days before the first real match
	var t_end := int(real[0].get("t", Ranked.now())) - 900
	var t_start := t_end - 6 * 86400
	for i in shown.size():
		shown[i]["t"] = int(t_start + (t_end - t_start) * float(i + 1) / float(shown.size() + 1) + r.randi_range(-900, 900))
	# rampages left for the older matches
	var base_rp := int((me.get("career_base", {}) as Dictionary).get("rp", 0))
	var rp_left := rampages - base_rp
	for e in all_shown:
		rp_left -= int(e.get("rp", 0))
	# the older matches: counted, not shown
	var wins_shown := all_shown.filter(func(e): return String(e.r) == "W").size()
	var bulk_n := total_m - all_shown.size()
	var bulk_w := total_w - wins_shown
	var bulk: Array = []
	for i in bulk_n:
		bulk.append(_game(i < bulk_w))
	for e in bulk:
		e["rp"] = 0
	var rp_slots := bulk.filter(func(e): return String(e.r) == "W" and int(e.k) >= 30)
	for i in maxi(0, rp_left):
		if rp_slots.is_empty():
			break
		var e: Dictionary = rp_slots.pop_at(r.randi_range(0, rp_slots.size() - 1))
		e["rp"] = 1
		e["ul"] = maxi(1, int(e.ul))
	# rebuild the profile: the older matches as totals, then the shown ones through Ranked._record
	var unranked: Array = me.get("unranked", [])
	me["created"] = int(t_start) - 330 * 86400
	me["career"] = {}
	for u in unranked:
		Career.add(me, u, String(u.get("r", "L")) == "W")
	me["hero_stats"] = {}
	me["mvps"] = int(me.get("mvps_casual", 0))
	var bw := 0
	var bl := 0
	for e in bulk:
		var won := String(e.r) == "W"
		Career.add(me, e, won)
		var hs: Array = (me.hero_stats as Dictionary).get(String(e.h), [0, 0, 0])
		me.hero_stats[String(e.h)] = [int(hs[0]) + (1 if won else 0), int(hs[1]) + (0 if won else 1), int(hs[2]) + int(e.hx)]
		if bool(e.mvp):
			me.mvps = int(me.mvps) + 1
		bw += 1 if won else 0
		bl += 0 if won else 1
	me["wins"] = bw
	me["losses"] = bl
	me["abandons"] = 0
	me["mmr"] = start_mmr
	me["peak"] = start_mmr + r.randi_range(40, 160)
	me["streak"] = 0
	me["best_streak"] = r.randi_range(11, 16)
	me["history"] = []
	me["graph"] = [start_mmr]
	for e in all_shown:
		var res := String(e.get("r", "W"))
		var ex := (e as Dictionary).duplicate()
		for k in ["r", "d", "m", "t", "h", "o"]:
			ex.erase(k)
		Ranked._clock = int(e.t)
		Ranked._record(me, res == "W", int(e.d), String(e.get("h", "")), int(e.get("o", role)), res == "A", ex)
	Ranked._clock = 0
	var newest: Dictionary = (me.history as Array)[0]
	me["last_game"] = {"kind": "ranked", "hero": String(newest.get("h", "")), "k": int(newest.get("k", 0)), "x": int(newest.get("x", 0)),
		"a": int(newest.get("a", 0)), "mvp": bool(newest.get("mvp", false)), "t": int(newest.get("t", 0))}
	Ranked._mark_dirty()
	Ranked.save()
	var mo := Career.moments(me)
	var c := Career.career(me)
	print("%d ranked matches: %d W - %d L (%.1f%%), MMR %d (start of the graph %d), place #%d" % [int(me.wins) + int(me.losses), int(me.wins),
		int(me.losses), Ranked.win_rate(me) * 100.0, int(me.mmr), start_mmr, Ranked.place_of("me")])
	print("rampages %d, triple kills %d, first bloods %d, MVPs %d, career %d matches, deaths %d" % [int(mo.rp), int(mo.tr), int(mo.fb), int(mo.mvp), int(c.g), int(c.x)])
	print("averages: ", Career.kda_text(Career.lifetime(me)), " lifetime; last 20 ", Career.kda_text(Career.averages(me)), " form ", String(Career.averages(me).form))
	quit()

## A made-up match, no deaths: a win around the averages; a loss with less of everything.
func _game(won: bool) -> Dictionary:
	var m := 1.0 if won else 0.62
	var f := func(k: String, lo := 0.0) -> int: return maxi(int(lo), int(round(float(avg[k]) * m * r.randf_range(0.8, 1.2))))
	var e := {"r": "W" if won else "L", "x": 0, "dn": 0, "heal": 0, "wd": 0}
	e["k"] = f.call("k", 6)
	e["a"] = f.call("a", 3)
	e["lh"] = maxi(90, int(round(float(avg.lh) * (1.0 if won else 0.85) * r.randf_range(0.8, 1.2))))
	e["gpm"] = f.call("gpm")
	e["xpm"] = f.call("xpm")
	e["hd"] = f.call("hd")
	e["bd"] = f.call("bd")
	e["nw"] = f.call("nw")
	e["len"] = maxi(240, int(round(float(avg.len) * r.randf_range(0.8, 1.25))))
	e["lvl"] = clampi(int(round(float(avg.lvl) * r.randf_range(0.85, 1.1))), 16, 30)
	# multi-kills: doubles and triples now and then, an ultra kill rarely; rampages are placed by the caller
	e["db"] = r.randi_range(0, 4) if won else r.randi_range(0, 2)
	e["tr"] = (1 if r.randf() < 0.45 else 0) if won else (1 if r.randf() < 0.15 else 0)
	e["ul"] = 1 if won and r.randf() < 0.08 else 0
	e["rp"] = 0
	e["fb"] = 1 if r.randf() < float(avg.fb) * (1.0 if won else 0.6) else 0
	e["mvp"] = r.randf() < (0.8 if won else 0.12)
	e["h"] = _weighted(heroes)
	e["ln"] = _weighted(lanes)
	e["o"] = role
	e["perf"] = snappedf(Career.perf(e, role), 0.01)
	e["hx"] = Ranked.hero_xp_gain(won, 1.0 if won else 0.6)
	return e

func _weighted(m: Dictionary) -> String:
	var total := 0
	for k in m:
		total += int(m[k])
	var x := r.randi_range(1, maxi(1, total))
	for k in m:
		x -= int(m[k])
		if x <= 0:
			return String(k)
	return String(m.keys()[0])
