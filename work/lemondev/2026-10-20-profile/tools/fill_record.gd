extends SceneTree
## The owner's request (2026-10-20): "Make up some match stats for me (consistent no deaths, consistent with those
## averages) and make my MMR 4000 (... the number of matches should coincide for me to have at least 4000 MMR)".
## Adds no-death ranked wins drawn around the averages of the player's tracked matches, older than the real ones, and
## replays the whole ranked history in time order through Ranked._record (MMR by Career.mmr_change, hero XP, career,
## MVPs, graph, streaks), so every number on the profile agrees. Uses WOA_RANKED_FILE (try it on a copy first).
##   godot --headless --path . -s work/lemondev/2026-10-20-profile/tools/fill_record.gd -- [--target=4000] [--seed=7]

func _init() -> void:
	var target := 4000
	var seed := 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			target = int(a.substr(9))
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
	Ranked.load_data()
	var me := Ranked.me()
	var real: Array = (me.history as Array).duplicate(true)
	real.reverse()                                      # oldest first
	var tracked := real.filter(func(e): return e.has("lh"))
	if tracked.is_empty():
		print("no tracked matches to take averages from")
		quit(1)
		return
	var keys := ["k", "a", "lh", "gpm", "xpm", "hd", "bd", "nw", "len", "lvl", "db", "tr", "ul", "rp", "fb"]
	var avg := {}
	for k in keys:
		var s := 0.0
		for e in tracked:
			s += float(e.get(k, 0))
		avg[k] = s / float(tracked.size())
	var heroes := {}
	var lanes := {}
	for e in tracked:
		heroes[String(e.h)] = int(heroes.get(String(e.h), 0)) + 1
		lanes[String(e.get("ln", "mid"))] = int(lanes.get(String(e.get("ln", "mid")), 0)) + 1
	for e in real:
		if String(e.get("h", "")) != "" and not heroes.has(String(e.h)):
			heroes[String(e.h)] = 1
	var role := int((me.roles as Array)[0]) if not (me.roles as Array).is_empty() else 2
	# how many wins it takes: from 1000 (your start) through the real matches' changes to the target
	var real_sum := 0
	for e in real:
		real_sum += int(e.get("d", 0))
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var made: Array = []
	var total := Ranked.YOUR_START + real_sum
	while total < target:
		var e := _game(avg, heroes, lanes, role, r)
		e["d"] = Career.mmr_change(true, e, role)
		total += int(e.d)
		made.append(e)
	# their times: from an hour after the account was made to ten minutes before the first real match, evenly
	var t0 := int(me.created) + 3600
	var t1 := int(real[0].get("t", Ranked.now())) - 600
	var step := maxf(400.0, float(t1 - t0) / float(made.size() + 1))
	for i in made.size():
		made[i]["t"] = int(t0 + step * (i + 1) + r.randi_range(-60, 60))
	# replay everything in time order from a fresh start (your unranked matches and earlier record stay)
	var unranked: Array = me.get("unranked", [])
	me["mmr"] = Ranked.YOUR_START
	me["wins"] = 0
	me["losses"] = 0
	me["abandons"] = 0
	me["streak"] = 0
	me["best_streak"] = 0
	me["peak"] = Ranked.YOUR_START
	me["history"] = []
	me["graph"] = [Ranked.YOUR_START]
	me["hero_stats"] = {}
	me["mvps"] = int(me.get("mvps_casual", 0))
	me["career"] = {}
	for u in unranked:
		Career.add(me, u, String(u.get("r", "L")) == "W")
	var all: Array = made + real
	for e in all:
		var res := String(e.get("r", "W"))
		var ex := (e as Dictionary).duplicate()
		for k in ["r", "d", "m", "t", "h", "o"]:
			ex.erase(k)
		Ranked._clock = int(e.t)
		Ranked._record(me, res == "W", int(e.get("d", 0)), String(e.get("h", "")), int(e.get("o", role)), res == "A", ex)
	Ranked._clock = 0
	var newest: Dictionary = (me.history as Array)[0]
	me["last_game"] = {"kind": "ranked", "hero": String(newest.get("h", "")), "k": int(newest.get("k", 0)), "x": int(newest.get("x", 0)),
		"a": int(newest.get("a", 0)), "mvp": bool(newest.get("mvp", false)), "t": int(newest.get("t", 0))}
	Ranked._mark_dirty()
	Ranked.save()
	var c := Career.career(me)
	print("added %d wins: MMR %d, %d W - %d L (%d left), best streak %d, place #%d, MVPs %d, career %d matches %d kills %d deaths" % [
		made.size(), int(me.mmr), int(me.wins), int(me.losses), int(me.abandons), int(me.best_streak), Ranked.place_of("me"),
		int(me.mvps), int(c.g), int(c.k), int(c.x)])
	print("averages now: ", JSON.stringify(Career.averages(me)))
	quit()

## One made-up match: a no-death win around the averages (each number within about a fifth of it).
func _game(avg: Dictionary, heroes: Dictionary, lanes: Dictionary, role: int, r: RandomNumberGenerator) -> Dictionary:
	var f := func(k: String, lo := 0.0) -> int: return maxi(int(lo), int(round(float(avg[k]) * r.randf_range(0.8, 1.2))))
	var e := {"r": "W", "x": 0, "dn": 0, "heal": 0, "wd": 0, "mvp": true}
	e["k"] = f.call("k", 10)
	e["a"] = f.call("a", 4)
	e["lh"] = f.call("lh", 120)
	e["gpm"] = f.call("gpm")
	e["xpm"] = f.call("xpm")
	e["hd"] = f.call("hd")
	e["bd"] = f.call("bd")
	e["nw"] = f.call("nw")
	e["len"] = f.call("len", 240)
	e["lvl"] = clampi(f.call("lvl"), 18, 30)
	e["db"] = f.call("db")
	e["tr"] = f.call("tr")
	e["ul"] = f.call("ul")
	e["rp"] = f.call("rp")
	e["fb"] = 1 if r.randf() < float(avg.fb) else 0
	e["h"] = _weighted(heroes, r)
	e["ln"] = _weighted(lanes, r)
	e["o"] = role
	e["perf"] = snappedf(Career.perf(e, role), 0.01)
	e["hx"] = Ranked.hero_xp_gain(true, 1.0)
	return e

func _weighted(m: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0
	for k in m:
		total += int(m[k])
	var x := r.randi_range(1, maxi(1, total))
	for k in m:
		x -= int(m[k])
		if x <= 0:
			return String(k)
	return String(m.keys()[0])
