class_name Career
extends RefCounted
## A player's numbers (run 2026-10-20; the owner: "Profile needs to include Player averages like LH/D, KDA, Fave lanes
## ... MMR gain should be based on performance and should give around 23 up to 41 (perfect game, no deaths, 10+
## assists, 10+ kills, 150 LH) ... add to player stats: First Bloods, Triple Kills, Rampages ... update the profiles of
## all AI players and give them their respective stats, also update their MVPs").
##   * a match line: kills, deaths, assists, last hits, denies, gold and experience a minute, hero and building damage,
##     healing, wards, the lane played, first blood, double / triple / ultra kills and rampages, the length;
##   * a career (p.career): the totals of every match counted, ranked or not (yours: from 2026-10-20 on, plus the
##     ranked matches saved before with what they kept); a ladder player's starts from an estimate of the games it played
##     before (its skill, its main role) and grows with every match;
##   * averages over the last 20 matches (or the career), the favourite lanes, and the recent form (last 5);
##   * the MMR of a match: a win gives 23 to 41 and a loss takes 23 to 41 by how well you played (perf).

const KEEP_UNRANKED := 40                  # your unranked matches kept on the profile
const RECENT := 20                         # matches the averages read
const LANE_NAMES := {"safe": "Safe lane", "mid": "Middle lane", "off": "Off lane", "jungle": "Jungle", "roam": "Roaming"}
const LANE_SHORT := {"safe": "Safe", "mid": "Mid", "off": "Off", "jungle": "Jungle", "roam": "Roam"}
## The career's counters (every one an int total over `g` matches).
const SUMS := ["g", "w", "k", "x", "a", "lh", "dn", "gpm", "xpm", "hd", "bd", "heal", "wd", "fb", "db", "tr", "ul", "rp", "secs"]
const MMR_MIN := 23
const MMR_MAX := 41

# ---- One match ------------------------------------------------------------------------------------------------------

## A hero's line of the match that just ended.
static func line_of(w: SimWorld, h: SimUnit) -> Dictionary:
	var mins := maxf(w.time / 60.0, 0.25)
	var hd := 0.0
	var bd := 0.0
	for k in h.dmg_out:
		var r: Array = h.dmg_out[k]
		hd += float(r[0])
		bd += float(r[2])
	return {"k": h.kills, "x": h.deaths, "a": h.assists, "lh": h.last_hits, "dn": h.denies,
		"gpm": int(h.gold_earned / mins), "xpm": int(h.xp / mins), "nw": h.networth(), "hd": int(hd), "bd": int(bd),
		"heal": int(h.heal_given), "wd": h.wards_placed, "ln": lane_of(h.lane_secs), "len": maxi(0, int(w.time)),
		"fb": 1 if h.first_blood else 0, "db": int(h.multi_n[0]), "tr": int(h.multi_n[1]), "ul": int(h.multi_n[2]),
		"rp": int(h.multi_n[3]), "lvl": h.level}

## The lane a hero spent most of its laning time in (SimWorld._note_lanes), "roam" when it hardly stood in one.
static func lane_of(secs: Dictionary) -> String:
	var best := ""
	var bn := 0
	var total := 0
	for k in secs:
		total += int(secs[k])
		if int(secs[k]) > bn:
			bn = int(secs[k])
			best = String(k)
	return best if total >= 60 else "roam"

## How well a match was played, 0..1: kills (10 for full marks), assists (10), deaths (none for full marks, 10 or
## more for nothing) and last hits (150; a support's wards, healing and assists may stand in for them).
static func perf(e: Dictionary, role := 0) -> float:
	var ks := clampf(float(e.get("k", 0)) / 10.0, 0.0, 1.0)
	var as_ := clampf(float(e.get("a", 0)) / 10.0, 0.0, 1.0)
	var ds := 1.0 - clampf(float(e.get("x", 0)) / 10.0, 0.0, 1.0)
	var farm := clampf(float(e.get("lh", 0)) / 150.0, 0.0, 1.0)
	if role >= 4:
		var work := float(e.get("wd", 0)) * 0.07 + float(e.get("heal", 0)) / 5000.0 + float(e.get("a", 0)) / 25.0
		farm = maxf(farm, clampf(work, 0.0, 1.0))
	return clampf(0.25 * ks + 0.2 * as_ + 0.3 * ds + 0.25 * farm, 0.0, 1.0)

## The MMR a match is worth: a win 23 (a poor game) to 41 (a perfect one), a loss -41 (a poor game) to -23 (a great
## one); leaving the match: -41.
static func mmr_change(won: bool, e: Dictionary, role := 0, abandon := false) -> int:
	if abandon:
		return -MMR_MAX
	var s := perf(e, role)
	var span := float(MMR_MAX - MMR_MIN)
	return MMR_MIN + int(round(span * s)) if won else -(MMR_MIN + int(round(span * (1.0 - s))))

# ---- The career -----------------------------------------------------------------------------------------------------

static func career(p: Dictionary) -> Dictionary:
	if not (p.get("career") is Dictionary):
		p["career"] = {}
	var c: Dictionary = p.career
	for k in SUMS:
		c[k] = int(c.get(k, 0))
	if not (c.get("lanes") is Dictionary):
		c["lanes"] = {}
	for k in (c.lanes as Dictionary).keys():
		c.lanes[k] = int(c.lanes[k])
	return c

## Count one match into a career. `e` needs at least k, x, a; the rest is counted where present.
static func add(p: Dictionary, e: Dictionary, won: bool) -> void:
	var c := career(p)
	c.g += 1
	c.w += 1 if won else 0
	for k in ["k", "x", "a", "lh", "dn", "gpm", "xpm", "hd", "bd", "heal", "wd", "fb", "db", "tr", "ul", "rp"]:
		c[k] = int(c[k]) + int(e.get(k, 0))
	c.secs = int(c.secs) + int(e.get("len", 0))
	if e.has("lh"):
		c["gs"] = int(c.get("gs", 0)) + 1          # matches with farm numbers (your ranked ones before 2026-10-20 have none)
	var ln := String(e.get("ln", ""))
	if ln != "":
		c.lanes[ln] = int(c.lanes.get(ln, 0)) + 1

## Your unranked match (Play, with or without ladder players): your career and your match list.
static func record_unranked(line: Dictionary, won: bool, hero: String, mvp: bool) -> void:
	var you := Ranked.me()
	var e := line.duplicate()
	e["r"] = "W" if won else "L"
	e["h"] = hero
	e["t"] = Ranked.now()
	e["kind"] = "casual"
	if mvp:
		e["mvp"] = true
	if not (you.get("unranked") is Array):
		you["unranked"] = []
	(you.unranked as Array).push_front(e)
	while (you.unranked as Array).size() > KEEP_UNRANKED:
		(you.unranked as Array).pop_back()
	add(you, e, won)
	if mvp:
		you["mvps"] = int(you.get("mvps", 0)) + 1
		you["mvps_casual"] = int(you.get("mvps_casual", 0)) + 1
	Ranked.save()

## A profile's matches, newest first: its ranked history and (yours) the unranked ones. filter: "", "ranked", "casual".
static func matches(p: Dictionary, filter := "") -> Array:
	var out: Array = []
	if filter != "casual":
		for e in p.get("history", []):
			if e is Dictionary:
				out.append(e)
	if filter != "ranked":
		for e in p.get("unranked", []):
			if e is Dictionary:
				out.append(e)
	if p.has("unranked") and filter == "":
		out.sort_custom(func(a, b): return int(a.get("t", 0)) > int(b.get("t", 0)))
	return out

## Averages over the last `n` matches (each number over the matches that have it), with the win rate, MVP rate, the
## favourite lanes and the form: {n, k, x, a, kda, lh, dn, lhm, gpm, xpm, hd, wr, mvp, lanes: {lane: share}, form: "WLW.."}.
static func averages(p: Dictionary, n := RECENT) -> Dictionary:
	var ms := matches(p).filter(func(e): return String(e.get("r", "")) != "A" or e.has("k"))
	ms = ms.slice(0, n)
	var out := {"n": ms.size()}
	if ms.is_empty():
		return lifetime(p)
	var sums := {}
	var cnt := {}
	var wins := 0
	var mvps := 0
	var lanes := {}
	var mins := 0.0
	var lh_for_min := 0.0
	var form := ""
	for e in ms:
		for k in ["k", "x", "a", "lh", "dn", "gpm", "xpm", "hd", "fb", "tr", "rp"]:
			if e.has(k):
				sums[k] = float(sums.get(k, 0.0)) + float(e[k])
				cnt[k] = int(cnt.get(k, 0)) + 1
		if e.has("lh") and int(e.get("len", 0)) > 0:
			mins += float(e.len) / 60.0
			lh_for_min += float(e.lh)
		var r := String(e.get("r", "L"))
		wins += 1 if r == "W" else 0
		mvps += 1 if bool(e.get("mvp", false)) else 0
		if form.length() < 5:
			form += "W" if r == "W" else "L"
		var ln := String(e.get("ln", ""))
		if ln != "":
			lanes[ln] = int(lanes.get(ln, 0)) + 1
	for k in sums:
		out[k] = float(sums[k]) / maxf(1.0, float(cnt[k]))
	for k in ["k", "x", "a", "lh", "dn", "gpm", "xpm", "hd"]:
		if not out.has(k):
			out[k] = -1.0                       # unknown
	out["kda"] = (float(out.k) + float(out.a)) / maxf(1.0, float(out.x)) if float(out.k) >= 0.0 else -1.0
	out["lhm"] = lh_for_min / mins if mins > 0.0 else -1.0
	out["wr"] = float(wins) / float(ms.size())
	out["mvp"] = float(mvps) / float(ms.size())
	out["lanes"] = _shares(lanes)
	out["form"] = form
	return out

## The career's averages (all matches counted): the same keys as averages().
static func lifetime(p: Dictionary) -> Dictionary:
	var c := career(p)
	var g := maxf(1.0, float(c.g))
	var gs := maxf(1.0, float(c.get("gs", c.g)))
	var out := {"n": int(c.g)}
	for k in ["k", "x", "a"]:
		out[k] = float(c[k]) / g if int(c.g) > 0 else -1.0
	for k in ["lh", "dn", "gpm", "xpm", "hd"]:
		out[k] = float(c[k]) / gs if int(c.get("gs", c.g)) > 0 else -1.0
	out["kda"] = (float(c.k) + float(c.a)) / maxf(1.0, float(c.x)) if int(c.g) > 0 else -1.0
	out["lhm"] = float(c.lh) / maxf(1.0, float(c.secs) / 60.0) if int(c.secs) > 0 and int(c.get("gs", c.g)) > 0 else -1.0
	out["wr"] = float(c.w) / g if int(c.g) > 0 else 0.0
	out["mvp"] = float(p.get("mvps", 0)) / g if int(c.g) > 0 else 0.0
	out["lanes"] = _shares(c.lanes)
	out["form"] = ""
	return out

static func _shares(counts: Dictionary) -> Dictionary:
	var total := 0
	for k in counts:
		total += int(counts[k])
	var out := {}
	for k in counts:
		out[k] = float(counts[k]) / maxf(1.0, float(total))
	return out

## The favourite lanes, most played first: [[lane, share]].
static func fav_lanes(p: Dictionary, recent := false) -> Array:
	var sh: Dictionary = (averages(p) if recent else lifetime(p)).get("lanes", {})
	if sh.is_empty():
		sh = lifetime(p).get("lanes", {})
	var out: Array = []
	for k in sh:
		out.append([String(k), float(sh[k])])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out

## The career's big moments: {fb, db, tr, ul, rp, mvp, g}.
static func moments(p: Dictionary) -> Dictionary:
	var c := career(p)
	var base: Dictionary = p.get("career_base", {})          # yours: your own count from before 2026-10-20 (Edit profile)
	return {"fb": int(c.fb) + int(base.get("fb", 0)), "db": int(c.db), "tr": int(c.tr) + int(base.get("tr", 0)),
		"ul": int(c.ul), "rp": int(c.rp) + int(base.get("rp", 0)), "mvp": int(p.get("mvps", 0)), "g": int(c.g)}

## Your own count of first bloods, triple kills and rampages from matches played before they were counted.
static func set_base(rp: int, tr: int, fb: int) -> void:
	var you := Ranked.me()
	you["career_base"] = {"rp": maxi(0, rp), "tr": maxi(0, tr), "fb": maxi(0, fb)}
	Ranked.save()

## "K/D/A" averages as text: "8.2 / 4.1 / 11.6".
static func kda_text(av: Dictionary) -> String:
	if float(av.get("k", -1.0)) < 0.0:
		return "-"
	return "%.1f / %.1f / %.1f" % [float(av.k), float(av.x), float(av.a)]

# ---- Ladder players --------------------------------------------------------------------------------------------------

## A ladder player's farm in a match (Ranked._sim_line): by role, skill and length; with its lane, first blood (set by
## the round), multi-kills from its kills.
static func sim_farm(p: Dictionary, e: Dictionary, role: int, r: RandomNumberGenerator) -> void:
	var sk := clampf(float(p.get("skill", 2000)) / 7000.0, 0.0, 1.0)
	var mins := maxf(10.0, float(e.get("len", 2280)) / 60.0)
	var core := role <= 3 and role > 0
	var lhm := (lerpf(2.6, 7.6, sk) if role in [1, 2] else (lerpf(2.0, 5.2, sk) if role == 3 else lerpf(0.5, 1.5, sk)))
	if role == 2:
		lhm *= 1.05
	e["lh"] = maxi(0, int(round(lhm * mins * r.randf_range(0.8, 1.2))))
	e["dn"] = maxi(0, int(round((lerpf(0.06, 0.5, sk) if core else lerpf(0.02, 0.15, sk)) * minf(mins, 14.0) * r.randf_range(0.5, 1.5))))
	var won := String(e.get("r", "L")) == "W"
	e["gpm"] = int((lerpf(320.0, 640.0, sk) if core else lerpf(210.0, 330.0, sk)) * (1.08 if won else 0.9) * r.randf_range(0.88, 1.12))
	e["xpm"] = int((lerpf(380.0, 720.0, sk) if core else lerpf(260.0, 430.0, sk)) * (1.08 if won else 0.9) * r.randf_range(0.88, 1.12))
	e["hd"] = int((float(e.get("k", 0)) * 1500.0 + float(e.get("a", 0)) * 700.0 + mins * (260.0 if core else 140.0)) * r.randf_range(0.8, 1.2))
	e["ln"] = String(KITS.ROLE_LANE.get(role, "safe")) if r.randf() < 0.85 else ["safe", "mid", "off", "roam"][r.randi_range(0, 3)]
	if role >= 4:
		e["wd"] = int(lerpf(4.0, 14.0, sk) * mins / 38.0 * r.randf_range(0.6, 1.3))
	var k := int(e.get("k", 0))
	var db := 0
	var tr := 0
	var ul := 0
	var rp := 0
	for i in k:
		if r.randf() < 0.14 + 0.08 * sk:
			db += 1
	for i in maxi(0, k - 2):
		if r.randf() < 0.025 + 0.035 * sk:
			tr += 1
	if k >= 7 and r.randf() < (0.03 + 0.07 * sk) * float(k - 6) / 4.0:
		ul = 1
		if r.randf() < 0.3 + 0.2 * sk:
			rp = 1
	e["db"] = db
	e["tr"] = tr
	e["ul"] = ul
	e["rp"] = rp

const KITS = preload("res://src/sim/sim_bot_kits.gd")

## A ladder player's career before the ladder kept one: its games played (wins + losses), what a player of its skill
## and main role does on average, its first bloods, multi-kills and MVPs (high-ranked players have hundreds; everyone
## has some, one game in ten has an MVP). Deterministic from the ladder's seed and the player's id.
static func estimate(p: Dictionary, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = absi(hash("career:%d:%s" % [seed, String(p.get("id", ""))]))
	var sk := clampf(float(p.get("skill", 2000)) / 7000.0, 0.0, 1.0)
	var games := int(p.get("wins", 0)) + int(p.get("losses", 0))
	var role := int((p.get("roles", [1]) as Array)[0]) if not (p.get("roles", []) as Array).is_empty() else 1
	var core := role <= 3
	var mins := 38.0
	var g := float(games)
	var n := func(x: float) -> int: return int(round(x * g * r.randf_range(0.9, 1.1)))
	var c := {}
	c["g"] = games
	c["w"] = int(p.get("wins", 0))
	c["k"] = n.call((0.24 if core else 0.09) * mins * (0.8 + 0.4 * sk))
	c["x"] = n.call(0.17 * mins * (1.15 - 0.3 * sk))
	c["a"] = n.call((0.28 if core else 0.42) * mins)
	var lhm := (lerpf(2.6, 7.6, sk) if role in [1, 2] else (lerpf(2.0, 5.2, sk) if role == 3 else lerpf(0.5, 1.5, sk)))
	c["lh"] = n.call(lhm * mins)
	c["dn"] = n.call((lerpf(0.06, 0.5, sk) if core else lerpf(0.02, 0.15, sk)) * 14.0)
	c["gpm"] = n.call(lerpf(320.0, 640.0, sk) if core else lerpf(210.0, 330.0, sk))
	c["xpm"] = n.call(lerpf(380.0, 720.0, sk) if core else lerpf(260.0, 430.0, sk))
	c["hd"] = n.call(((0.24 if core else 0.09) * mins * 1500.0 + 0.3 * mins * 700.0 + mins * (260.0 if core else 140.0)))
	c["bd"] = n.call((2600.0 if core else 700.0) * (0.6 + 0.8 * sk))
	c["heal"] = n.call(0.0 if core else 1800.0 * (0.5 + sk))
	c["wd"] = n.call(0.6 if core else lerpf(4.0, 14.0, sk))
	c["fb"] = n.call((0.13 if role == 2 else (0.09 if core else 0.05)) * (0.8 + 0.6 * sk))
	c["db"] = n.call((0.24 if core else 0.07) * mins * (0.8 + 0.4 * sk) * (0.14 + 0.08 * sk))
	c["tr"] = n.call((0.06 + 0.24 * sk) * (1.0 if core else 0.3))
	c["ul"] = n.call((0.012 + 0.07 * sk) * (1.0 if core else 0.25))
	c["rp"] = n.call((0.003 + 0.024 * sk) * (1.0 if core else 0.2))
	c["secs"] = int(g * mins * 60.0)
	c["gs"] = games
	var lanes := {}
	var main_lane := String(KITS.ROLE_LANE.get(role, "safe"))
	lanes[main_lane] = int(round(g * r.randf_range(0.62, 0.86)))
	var rest := games - int(lanes[main_lane])
	for ln in ["safe", "mid", "off", "roam"]:
		if ln != main_lane and rest > 0:
			var take := mini(rest, int(round(float(rest) * r.randf_range(0.2, 0.6))))
			lanes[ln] = int(lanes.get(ln, 0)) + take
			rest -= take
	if rest > 0:
		lanes[main_lane] = int(lanes[main_lane]) + rest
	c["lanes"] = lanes
	c["est"] = true
	# what the ladder's matches already counted is added on top of the estimate's numbers by the caller
	p["career"] = c
	var rate := clampf(0.06 + 0.1 * sk + (0.025 if core else -0.01) + r.randf_range(-0.02, 0.03), 0.04, 0.24)
	p["mvps"] = maxi(int(p.get("mvps", 0)), int(round(g * rate)))
	# commends from other players: friendly team players collect them, flamers hardly any
	var toxic := float(p.get("toxic", 0.3))
	p["commends"] = maxi(int(p.get("commends", 0)), int(round(g * clampf(0.03 + 0.22 * (1.0 - toxic) * float(p.get("coop", 0.6)), 0.0, 0.3) * r.randf_range(0.7, 1.2))))

## Farm and multi-kills for a saved ladder match that lacks them (a ladder saved before 2026-10-20).
static func fill_old(e: Dictionary, p: Dictionary, r: RandomNumberGenerator) -> void:
	if e.has("lh") or not e.has("k"):
		return
	sim_farm(p, e, int(e.get("o", (p.get("roles", [1]) as Array)[0] if not (p.get("roles", []) as Array).is_empty() else 1)), r)
	e["fb"] = 1 if r.randf() < 0.08 else 0
