class_name ProfileTalk
extends RefCounted
## Players read each other's profiles (run 2026-10-20; the owner: "AI players should be MORE AWARE of the situation like
## your last games (at least 5 of your last games, with YOUR STATS, and THEY WILL ACKNOWLEDGE IF YOU PLAYED GOOD, but
## some trolls will still troll you). AI players will REALLY CHECK each others' profiles especially the player and will
## react according to the player's profile, averages, last 3-5 games ... toxic as ever, but also with more kind people").
##   * read(p): what a profile shows anyone (facts: averages over 20 matches, the last five with their numbers, the form,
##     the career's MVPs, rampages, triple kills, first bloods, the favourite lane, rank, games, abandons);
##   * signals(f): what stands out (hot or cold form, a great or awful last match, feeding, farming, a smurf's numbers on
##     a new account, "boosted" numbers at a high rank, MVPs, rampages, leaving);
##   * opinion(viewer, f): what a viewer says, by who it is: kind ones praise a good profile and cheer up a bad one, fair
##     ones say what they see, rough ones flame a bad one and call a good one a smurf (and sometimes give credit), show-
##     offs compare, trolls troll whatever they see; the line's kind and its fields (ProfileLines);
##   * walls: the comments players leave on a profile (yours after matches and while you are away; a ladder player's
##     from the players it met), and the answers to what you write.

const LINES = preload("res://src/core/profile_lines.gd")
const WALL_MAX := 30
const VISITORS_MAX := 12

# ---- Facts ------------------------------------------------------------------------------------------------------------

## What a profile shows (a plain dictionary: it travels in a match card).
static func read(p: Dictionary) -> Dictionary:
	if p.is_empty():
		return {}
	var av := Career.averages(p, Career.RECENT)
	var life := Career.lifetime(p)
	var mo := Career.moments(p)
	var last5: Array = []
	for e in Career.matches(p).slice(0, 5):
		last5.append({"r": String(e.get("r", "L")), "h": String(e.get("h", "")), "k": int(e.get("k", 0)), "x": int(e.get("x", 0)),
			"a": int(e.get("a", 0)), "lh": int(e.get("lh", -1)), "mvp": bool(e.get("mvp", false)), "rp": int(e.get("rp", 0)),
			"tr": int(e.get("tr", 0)), "kind": String(e.get("kind", "ranked"))})
	var w5 := 0
	for e in last5:
		w5 += 1 if String(e.r) == "W" else 0
	var lanes := Career.fav_lanes(p)
	var roles: Array = p.get("roles", [])
	return {"name": String(p.get("name", "")), "id": String(p.get("id", "")), "rank": Ranked.rank_label(p),
		"tier": Ranked.tier_for(p), "mmr": int(p.get("mmr", 0)), "games": int(p.get("wins", 0)) + int(p.get("losses", 0)),
		"career_g": int(mo.g), "k": float(av.get("k", -1.0)), "x": float(av.get("x", -1.0)), "a": float(av.get("a", -1.0)),
		"kda": float(av.get("kda", -1.0)), "lh": float(av.get("lh", -1.0)), "lhm": float(av.get("lhm", -1.0)),
		"gpm": float(av.get("gpm", -1.0)), "wr": float(life.get("wr", 0.0)) if int(mo.g) > 0 else Ranked.win_rate(p),
		"wr20": float(av.get("wr", 0.0)), "last5": last5, "w5": w5, "l5": last5.size() - w5, "form": String(av.get("form", "")),
		"mvps": int(mo.mvp), "rp": int(mo.rp), "tr": int(mo.tr), "fb": int(mo.fb), "ul": int(mo.ul),
		"lane": String(lanes[0][0]) if not lanes.is_empty() else "", "streak": int(p.get("streak", 0)),
		"abandons": int(p.get("abandons", 0)), "behavior": int(p.get("behavior", 10000)),
		"support": not roles.is_empty() and int(roles[0]) >= 4 and roles.size() == 1}

## What stands out, strongest first: ["hot", "good_last", ...] (good ones) and ["feeder", "cold", ...] (bad ones).
static func signals(f: Dictionary) -> Dictionary:
	var good: Array = []
	var bad: Array = []
	if f.is_empty():
		return {"good": good, "bad": bad, "new": false, "smurf": false}
	var last: Dictionary = (f.last5 as Array)[0] if not (f.get("last5", []) as Array).is_empty() else {}
	var n5 := (f.get("last5", []) as Array).size()
	if not last.is_empty():
		var lr := (float(last.k) + float(last.a) * 0.5) / maxf(1.0, float(last.x))
		if bool(last.mvp) or (lr >= 3.0 and int(last.k) >= 8) or int(last.rp) > 0:
			good.append("good_last")
		elif int(last.x) >= 10 and float(last.x) > float(last.k) + float(last.a) * 0.5:
			bad.append("bad_last")
	if n5 >= 4 and int(f.w5) >= 4:
		good.append("hot")
	elif n5 >= 4 and int(f.l5) >= 4:
		bad.append("cold")
	if float(f.kda) >= 3.6 and float(f.x) >= 0.0 and float(f.x) <= 5.5:
		good.append("good_avg")
	if float(f.x) >= 8.0:
		bad.append("feeder")
	if int(f.mvps) >= maxi(3, int(float(f.get("career_g", 0)) * 0.18)) or (not last.is_empty() and bool(last.mvp)):
		good.append("mvp")
	if int(f.rp) >= 3 or (int(f.rp) >= 1 and int(f.get("career_g", 0)) < 60):
		good.append("rampage")
	if float(f.lhm) >= 6.0:
		good.append("farm")
	elif float(f.lhm) >= 0.0 and float(f.lhm) < 2.4 and not bool(f.get("support", false)):
		bad.append("farm")
	if int(f.fb) >= 10:
		good.append("fb")
	if float(f.kda) >= 0.0 and float(f.kda) < 1.9 and int(f.tier) >= 4:
		bad.append("boosted")
	if int(f.abandons) >= 2:
		bad.append("leaver")
	var is_new := int(f.games) < 25
	var smurf := (is_new or int(f.tier) <= 2) and float(f.kda) >= 4.0 and float(f.get("wr20", 0.0)) >= 0.6 and n5 >= 3
	return {"good": good, "bad": bad, "new": is_new, "smurf": smurf}

## Fields for the lines (ProfileLines).
static func fill(f: Dictionary) -> Dictionary:
	var out := {"name": String(f.get("name", "")), "rank": String(f.get("rank", "")).to_lower(), "games": int(f.get("games", 0)),
		"mvps": int(f.get("mvps", 0)), "rp": int(f.get("rp", 0)), "tr": int(f.get("tr", 0)), "fb": int(f.get("fb", 0)),
		"w5": int(f.get("w5", 0)), "l5": int(f.get("l5", 0)), "form": String(f.get("form", "")), "n": int(f.get("abandons", 0)),
		"wr": int(round(float(f.get("wr", 0.0)) * 100.0))}
	if float(f.get("k", -1.0)) >= 0.0:
		out["kda"] = "%d/%d/%d" % [int(round(float(f.k))), int(round(float(f.x))), int(round(float(f.a)))]
		out["d"] = "%.1f" % float(f.x)
	if float(f.get("lh", -1.0)) >= 0.0:
		out["lh"] = int(round(float(f.lh)))
	if float(f.get("lhm", -1.0)) >= 0.0:
		out["lhm"] = "%.1f" % float(f.lhm)
	if float(f.get("gpm", -1.0)) >= 0.0:
		out["gpm"] = int(round(float(f.gpm)))
	if String(f.get("lane", "")) != "":
		out["lane"] = String(Career.LANE_SHORT.get(String(f.lane), String(f.lane))).to_lower()
	var l5: Array = f.get("last5", [])
	if not l5.is_empty():
		var e: Dictionary = l5[0]
		out["last"] = "%d/%d/%d" % [int(e.k), int(e.x), int(e.a)]
		if String(e.h) != "":
			out["lhero"] = HeroDraft.hero_name(String(e.h)).to_lower()
	# the last five together: their average K/D/A and MVPs
	if l5.size() >= 3:
		var k5 := 0.0
		var x5 := 0.0
		var a5 := 0.0
		var m5 := 0
		for g in l5:
			k5 += float(g.k)
			x5 += float(g.x)
			a5 += float(g.a)
			m5 += 1 if bool(g.get("mvp", false)) else 0
		var n5 := float(l5.size())
		out["kda5"] = "%d/%d/%d" % [int(round(k5 / n5)), int(round(x5 / n5)), int(round(a5 / n5))]
		out["n5"] = l5.size()
		if m5 > 0:
			out["mvp5"] = m5
	return out

# ---- Who is looking ---------------------------------------------------------------------------------------------------

## How a viewer reads profiles: "troll", "rough", "kind", "ego" or "fair". ps: its persona; toxic, rage: its manners.
static func manner(ps: Dictionary, toxic: float, rage: bool) -> String:
	var kind := float(ps.get("kind", 0.5))
	var humor := float(ps.get("humor", 0.5))
	var temper := float(ps.get("temper", 0.4))
	if rage or (toxic > 0.55 and humor > 0.62):
		return "troll"
	if toxic >= 0.45 or (temper > 0.72 and kind < 0.45):
		return "rough"
	if kind >= 0.62:
		return "kind"
	if float(ps.get("ego", 0.4)) > 0.72:
		return "ego"
	return "fair"

static func manner_of(p: Dictionary) -> String:
	return manner(p.get("persona", {}), float(p.get("toxic", 0.3)), bool(p.get("rage", false)))

## What a viewer says about a profile: [line kind, fields]. like: what the viewer already thinks of the player (-1..1);
## a liked player gets the kinder reading, a disliked one the harsher.
static func opinion(manner_s: String, f: Dictionary, rng: RandomNumberGenerator, like := 0.0) -> Array:
	var sg := signals(f)
	var good: Array = sg.good
	var bad: Array = sg.bad
	var fl := fill(f)
	var m := manner_s
	if like > 0.45 and m == "rough":
		m = "fair"
	elif like < -0.45 and m in ["fair", "kind"]:
		m = "rough" if rng.randf() < 0.6 else m
	var score := good.size() - bad.size()
	if m == "troll" and rng.randf() < 0.7:
		return ["pf_troll_good" if score > 0 else "pf_troll", fl]
	if bool(sg.new) and rng.randf() < 0.35:
		return ["pf_accuse" if bool(sg.smurf) and m in ["rough", "troll", "ego"] else "pf_new", fl]
	if score > 0:
		if m in ["rough", "troll"]:
			var x := rng.randf()
			if bool(sg.smurf) or x < 0.35:
				return ["pf_accuse", fl]
			if x < 0.65:
				return ["pf_grudge", fl]
			# even a rough one gives credit now and then
		elif m == "ego" and rng.randf() < 0.55:
			return ["pf_ego", fl]
		elif m == "kind" and rng.randf() < 0.3:
			return ["pf_kind_good", fl]
		return [_good_sit(String(good[0]) if rng.randf() < 0.6 else String(good[rng.randi_range(0, good.size() - 1)])), fl]
	if score < 0:
		if m == "kind":
			return ["pf_kind_bad", fl]
		if m == "fair" and rng.randf() < 0.45:
			return ["pf_fact", fl]
		var b := String(bad[0]) if rng.randf() < 0.6 else String(bad[rng.randi_range(0, bad.size() - 1)])
		return [_bad_sit(b), fl]
	# nothing stands out
	if m in ["rough", "troll"] and rng.randf() < 0.5:
		return ["pf_troll", fl]
	if m == "kind":
		return ["pf_kind_good" if rng.randf() < 0.5 else "pf_fact", fl]
	return ["pf_fact", fl]

static func _good_sit(s: String) -> String:
	return {"hot": "pf_good_hot", "good_last": "pf_good_last", "good_avg": "pf_good_avg", "mvp": "pf_good_mvp",
		"rampage": "pf_good_rampage", "farm": "pf_good_farm", "fb": "pf_good_fb"}.get(s, "pf_good_avg")

static func _bad_sit(s: String) -> String:
	return {"feeder": "pf_bad_feeder", "cold": "pf_bad_cold", "bad_last": "pf_bad_last", "farm": "pf_bad_farm",
		"boosted": "pf_bad_boosted", "leaver": "pf_bad_leaver"}.get(s, "pf_bad_feeder")

## Whether a profile reads as good (1), bad (-1) or plain (0).
static func verdict(f: Dictionary) -> int:
	var sg := signals(f)
	var s: int = (sg.good as Array).size() - (sg.bad as Array).size()
	return 1 if s > 0 else (-1 if s < 0 else 0)

## A line of `sit` with fields, in the viewer's own typing (Persona style). "" when no line fits the fields.
static func say(p: Dictionary, sit: String, fl: Dictionary, rng: RandomNumberGenerator) -> String:
	var tl := float((p.get("voice", {}) as Dictionary).get("tl", 0.3))
	var text := ChatMind.pick(sit, fl, rng.randf() < tl, rng)
	if text == "":
		return ""
	return ChatStyle.apply(text, (p.get("persona", {}) as Dictionary).get("style", {}), 0.0, rng, false, 0.08)

## What `viewer` (a ladder profile) says about `target`'s profile: the text, in its typing ("" if nothing fits).
static func line_about(viewer: Dictionary, target: Dictionary, rng: RandomNumberGenerator) -> String:
	var f := read(target)
	var like := float((viewer.get("you", {}) as Dictionary).get("rep", 0.0)) if String(target.get("id", "")) == "me" else 0.0
	for attempt in 3:
		var op := opinion(manner_of(viewer), f, rng, like)
		var t := say(viewer, String(op[0]), op[1], rng)
		if t != "":
			return t
	return ""

# ---- Profile walls ------------------------------------------------------------------------------------------------------

## A comment `viewer` leaves on `target`'s profile: {id, t, text, mood: 1 good, -1 bad, 0}. ctx: "match" (just played
## together; with, won, tt: trash talk), "visit".
static func wall_comment(viewer: Dictionary, target: Dictionary, rng: RandomNumberGenerator, ctx := {}) -> Dictionary:
	var f := read(target)
	var m := manner_of(viewer)
	var like := float((viewer.get("you", {}) as Dictionary).get("rep", 0.0)) if String(target.get("id", "")) == "me" else 0.0
	var v := verdict(f)
	var sit := ""
	if int(ctx.get("tt", 0)) > 0 and m != "kind":
		sit = "pf_wall_tt"
	elif m == "troll" and rng.randf() < 0.6:
		sit = "pf_wall_troll"
	elif v > 0:
		sit = "pf_wall_smurf" if m == "rough" and (bool(signals(f).smurf) or rng.randf() < 0.3) else "pf_wall_good"
	elif v < 0:
		sit = "pf_wall_kind" if m == "kind" or like > 0.4 else "pf_wall_bad"
	else:
		sit = "pf_wall_kind" if m in ["kind", "fair"] or like > 0.2 else "pf_wall_troll"
	var text := ""
	if rng.randf() < 0.45:
		text = line_about(viewer, target, rng)        # a longer read of the profile
	if text == "":
		text = say(viewer, sit, fill(f), rng)
	if text == "":
		text = say(viewer, "pf_wall_kind", fill(f), rng)
	var mood := 1 if sit in ["pf_wall_good", "pf_wall_kind"] else (-1 if sit in ["pf_wall_bad", "pf_wall_smurf", "pf_wall_tt", "pf_wall_troll"] else 0)
	return {"id": String(viewer.get("id", "")), "t": Ranked.now(), "text": text, "mood": mood}

static func _wall(p: Dictionary) -> Array:
	if not (p.get("wall") is Array):
		p["wall"] = []
	return p.wall

## Add a comment to a profile's wall (newest first, WALL_MAX kept).
static func post(p: Dictionary, c: Dictionary) -> void:
	if String(c.get("text", "")) == "":
		return
	var wl := _wall(p)
	wl.push_front(c)
	while wl.size() > WALL_MAX:
		wl.pop_back()

## Someone looked at a profile (your "Recent visitors").
static func visit(p: Dictionary, who: String, t: int) -> void:
	if not (p.get("visitors") is Array):
		p["visitors"] = []
	var vs: Array = p.visitors
	for i in range(vs.size() - 1, -1, -1):
		if String(vs[i].get("id", "")) == who:
			vs.remove_at(i)
	vs.push_front({"id": who, "t": t})
	while vs.size() > VISITORS_MAX:
		vs.pop_back()

## After your match: some of the nine look at your profile, and some leave a comment (the ones with something to say:
## a great or awful game, trash talk, a win together). ids: the nine; rel: SimBotChat.relations(); won: your result.
static func after_match(ids: Array, rel: Dictionary, mine_ids: Array, won: bool, rng: RandomNumberGenerator) -> int:
	var you := Ranked.me()
	var n := 0
	var t := Ranked.now()
	for id in ids:
		var b := Ranked.profile(String(id))
		if b.is_empty() or String(id) == "me":
			continue
		var r: Dictionary = rel.get(String(id), {})
		var with: bool = String(id) in mine_ids
		var ps: Dictionary = b.get("persona", {})
		var ch := 0.25 + float(ps.get("talk", 0.5)) * 0.25
		if int(r.get("trash_talked", 0)) > 0 or int(r.get("flamed", 0)) > 0:
			ch += 0.3
		if rng.randf() < 0.55:
			visit(you, String(id), t + rng.randi_range(20, 400))
		if rng.randf() >= ch or n >= 4:
			continue
		var c := wall_comment(b, you, rng, {"tt": int(r.get("trash_talked", 0)), "with": with, "won": won})
		c["t"] = t + rng.randi_range(30, 900)
		post(you, c)
		n += 1
	if n > 0:
		(you.wall as Array).sort_custom(func(a, b): return int(a.get("t", 0)) > int(b.get("t", 0)))
	return n

## While you were away: ladder players who are online drop by your profile (one about every 90 minutes, four at
## most), and some leave a comment. Returns the comments left.
static func catch_up(r: RandomNumberGenerator) -> int:
	var you := Ranked.me()
	var t := Ranked.now()
	var last := int(you.get("wall_t", 0))
	if last <= 0:
		last = t - 4 * 5400                         # the first time: the last few hours' visitors
	var owed := mini(4, (t - last) / 5400)
	if owed <= 0:
		return 0
	you["wall_t"] = t
	if int((you.get("career", {}) as Dictionary).get("g", 0)) == 0 and (you.history as Array).is_empty():
		return 0                                    # nothing to look at yet
	var pool: Array = []
	var met: Dictionary = you.get("met", {})
	for id in met:
		pool.append(String(id))
	for i in 20:
		pool.append(String(Ranked.bots()[r.randi_range(0, Ranked.bots().size() - 1)].id))
	var n := 0
	for i in owed:
		var id := String(pool[r.randi_range(0, pool.size() - 1)])
		var b := Ranked.profile(id)
		if b.is_empty():
			continue
		var at := last + int(float(t - last) * r.randf())
		visit(you, id, at)
		if r.randf() < 0.55:
			var c := wall_comment(b, you, r, {})
			c["t"] = at
			post(you, c)
			n += 1
	(you.wall as Array).sort_custom(func(a, b): return int(a.get("t", 0)) > int(b.get("t", 0)))
	return n

## A ladder player's wall as you see it: the comments the players it met left (made once from the ladder's seed and
## its id, then kept), with yours and its answers.
static func wall_of(p: Dictionary) -> Array:
	if String(p.get("id", "")) == "me":
		return _wall(p)
	if not bool(p.get("wall_made", false)):
		p["wall_made"] = true
		var r := RandomNumberGenerator.new()
		r.seed = absi(hash("wall:%d:%s" % [int(Ranked.data.get("seed", 1)), String(p.id)]))
		var pool: Array = (p.get("seen", {}) as Dictionary).keys() + (p.get("friends", []) as Array)
		var bots: Array = Ranked.bots()
		for i in 6:
			pool.append(String(bots[r.randi_range(0, bots.size() - 1)].id))
		var made: Array = []
		var t := Ranked.now()
		for i in r.randi_range(2, 6):
			var id := String(pool[r.randi_range(0, pool.size() - 1)])
			if id == String(p.id) or id == "me":
				continue
			var c := wall_comment(Ranked.profile(id), p, r, {})
			c["t"] = t - r.randi_range(600, 86400 * 9)
			if String(c.text) != "":
				made.append(c)
		made.sort_custom(func(a, b): return int(a.t) > int(b.t))
		for c in made:
			_wall(p).append(c)
	return _wall(p)

## You write on someone's profile: it goes on their wall and they answer (by what you wrote, what they think of you and
## your profile). Returns their answer ({} if they say nothing). Rude words cost you their liking, kind ones earn it.
static func write_on(p: Dictionary, text: String, rng: RandomNumberGenerator) -> Dictionary:
	var t := Ranked.now()
	post(p, {"id": "me", "t": t, "text": text.strip_edges().substr(0, 140), "mood": 0})
	if String(p.get("id", "")) == "me":
		return {}
	var it := ChatMind.intent(text.to_lower())
	var y: Dictionary = p.get("you", {})
	var rude := it in ["insult", "taunt"]
	var nice := it in ["praise", "thanks", "gg", "greet"] or text.to_lower().contains("+rep")
	if rude:
		y["rep"] = clampf(float(y.get("rep", 0.0)) - 0.12, -1.0, 1.0)
		y["trash_talked"] = int(y.get("trash_talked", 0)) + 1
	elif nice:
		y["rep"] = clampf(float(y.get("rep", 0.0)) + 0.06, -1.0, 1.0)
	p["you"] = y
	var f := read(Ranked.me())
	var m := manner_of(p)
	var sit := "pf_wall_back_nice"
	if rude:
		sit = "pf_wall_back_witty" if m == "kind" else "pf_wall_back_rude"
	elif not nice and (m in ["rough", "troll"] or float(y.get("rep", 0.0)) < -0.3):
		sit = "pf_wall_back_rude" if rng.randf() < 0.6 else "pf_wall_back_witty"
	var reply := say(p, sit, fill(f), rng)
	if reply == "":
		reply = say(p, "pf_wall_back_nice", fill(f), rng)
	var c := {"id": String(p.id), "t": t + rng.randi_range(8, 90), "text": reply, "mood": 0, "to": "me"}
	post(p, c)
	return c

# ---- In words (the online chat writer's prompts) -------------------------------------------------------------------------

## A profile in one paragraph of plain facts.
static func summary(f: Dictionary) -> String:
	if f.is_empty():
		return "no profile"
	var parts: Array = ["%s, %d MMR, %d ranked matches" % [String(f.get("rank", "Unranked")), int(f.get("mmr", 0)), int(f.get("games", 0))]]
	if float(f.get("k", -1.0)) >= 0.0:
		var s := "averages over the last matches: %.1f/%.1f/%.1f K/D/A" % [float(f.k), float(f.x), float(f.a)]
		if float(f.get("lh", -1.0)) >= 0.0:
			s += ", %d last hits (%.1f a minute), %d GPM" % [int(f.lh), maxf(0.0, float(f.get("lhm", 0.0))), maxi(0, int(f.get("gpm", 0)))]
		parts.append(s)
	var l5: Array = f.get("last5", [])
	if not l5.is_empty():
		var games: Array = []
		for e in l5:
			games.append("%s %s %d/%d/%d%s%s" % ["won" if String(e.r) == "W" else "lost", HeroDraft.hero_name(String(e.h)) if String(e.h) != "" else "?",
				int(e.k), int(e.x), int(e.a), (" %d LH" % int(e.lh)) if int(e.get("lh", -1)) >= 0 else "", " (MVP)" if bool(e.mvp) else ""])
		parts.append("last %d matches, newest first: %s" % [l5.size(), "; ".join(games)])
	parts.append("career: %d MVPs, %d rampages, %d triple kills, %d first bloods" % [int(f.get("mvps", 0)), int(f.get("rp", 0)), int(f.get("tr", 0)), int(f.get("fb", 0))])
	if String(f.get("lane", "")) != "":
		parts.append("plays mostly %s" % String(Career.LANE_NAMES.get(String(f.lane), String(f.lane))))
	if int(f.get("streak", 0)) >= 3 or int(f.get("streak", 0)) <= -3:
		parts.append(("on a %d win streak" % int(f.streak)) if int(f.streak) > 0 else ("lost %d in a row" % -int(f.streak)))
	return "; ".join(parts) + "."

## What `viewer` says about `target`'s profile, not yet typed in its style (the forum types it itself).
static func raw_about(viewer: Dictionary, target: Dictionary, rng: RandomNumberGenerator) -> String:
	var f := read(target)
	var like := float((viewer.get("you", {}) as Dictionary).get("rep", 0.0)) if String(target.get("id", "")) == "me" else 0.0
	var tl := float((viewer.get("voice", {}) as Dictionary).get("tl", 0.3))
	for attempt in 3:
		var op := opinion(manner_of(viewer), f, rng, like)
		var t := ChatMind.pick(String(op[0]), op[1], rng.randf() < tl, rng)
		if t != "":
			return t
	return ""
