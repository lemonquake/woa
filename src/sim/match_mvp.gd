class_name MatchMvp
extends RefCounted
## The match's MVP (run 2026-10-19 e; the owner: "an MVP after the game with all the epic UI and some stats on why he is
## the MVP. Supports can become MVPs as well of course with tons of supporting like heals, wards, assists, saves").
## Every hero gets a score from what it did: kills, assists and deaths; its share of the match's hero damage and
## building damage; healing given to allies, seconds of disables on enemy heroes, wards placed and saves (a low ally
## healed or its attacker stopped, and it lived); farm for the time; a win. A support that keeps its team alive scores
## like a carry that kills. The reasons shown are the numbers the hero led the match in, or stood out with.

## Every hero, best first: [{u (unit id), score, reasons: [[label, value]], tag}].
static func rank(w: SimWorld) -> Array:
	var mins := maxf(w.time, 60.0) / 60.0
	var top := {"hero": 1.0, "building": 1.0, "heal": 1.0, "disable": 1.0, "kills": 0, "assists": 0, "lh": 0, "wards": 0,
		"saves": 0, "nw": 0}
	var tots := {}
	for h in w.heroes:
		var t := totals(h)
		tots[h.id] = t
		top.hero = maxf(top.hero, float(t.hero))
		top.building = maxf(top.building, float(t.building))
		top.heal = maxf(top.heal, h.heal_given)
		top.disable = maxf(top.disable, h.disable_given)
		top.kills = maxi(top.kills, h.kills)
		top.assists = maxi(top.assists, h.assists)
		top.lh = maxi(top.lh, h.last_hits)
		top.wards = maxi(top.wards, h.wards_placed)
		top.saves = maxi(top.saves, h.saves)
		top.nw = maxi(top.nw, h.networth())
	var out: Array = []
	for h in w.heroes:
		var t: Dictionary = tots[h.id]
		var s := 3.0 * h.kills + 1.7 * h.assists - 1.5 * h.deaths
		s += 9.0 * float(t.hero) / float(top.hero)
		s += 4.0 * float(t.building) / float(top.building)
		s += minf(9.0, h.heal_given / 350.0)
		s += minf(6.0, h.disable_given / 6.0)
		s += minf(7.0, h.wards_placed * 0.75)
		s += 2.5 * h.saves
		s += minf(4.0, float(h.last_hits) / (mins * 6.0) * 3.0)
		s += 3.0 if h.best_multi >= 5 else (1.5 if h.best_multi >= 3 else 0.0)
		if w.winner >= 0 and h.team == w.winner:
			s += 5.0
		var reasons: Array = []
		var add := func(cond: bool, label: String, val: String) -> void:
			if cond and reasons.size() < 4:
				reasons.append([label, val])
		add.call(h.best_multi >= 5, "Rampage", "5 heroes in one fight")
		add.call(h.kills > 0 and h.kills == top.kills, "Most kills", str(h.kills))
		add.call(float(t.hero) >= float(top.hero) and t.hero > 0, "Most hero damage", RankedNum.num(int(t.hero)))
		add.call(h.heal_given >= 600.0 and h.heal_given >= top.heal, "Most healing", RankedNum.num(int(h.heal_given)))
		add.call(h.saves > 0 and h.saves == top.saves, "Saves", str(h.saves))
		add.call(h.assists >= 5 and h.assists == top.assists, "Most assists", str(h.assists))
		add.call(h.wards_placed >= 4 and h.wards_placed == top.wards, "Most wards", str(h.wards_placed))
		add.call(h.disable_given >= 10.0 and h.disable_given >= top.disable, "Most disables", "%.0f s" % h.disable_given)
		add.call(float(t.building) >= float(top.building) and t.building > 500, "Most building damage", RankedNum.num(int(t.building)))
		add.call(h.last_hits > 0 and h.last_hits == top.lh, "Most last hits", str(h.last_hits))
		add.call(h.networth() == top.nw, "Highest net worth", RankedNum.num(h.networth()))
		add.call(h.deaths <= 1 and h.kills + h.assists >= 8, "Deaths", str(h.deaths))
		add.call(h.best_multi == 4, "Ultra Kill", "4 heroes in one fight")
		add.call(h.best_multi == 3, "Triple Kill", "3 heroes in one fight")
		add.call(true, "K / D / A", "%d / %d / %d" % [h.kills, h.deaths, h.assists])
		var sup := h.heal_given / 350.0 + h.wards_placed * 0.75 + h.saves * 2.5 + h.disable_given / 6.0 + h.assists * 0.5
		var tag := "Support" if sup > 3.0 * h.kills * 0.6 + float(h.last_hits) / (mins * 6.0) * 3.0 and sup >= 6.0 else "Core"
		out.append({"u": h.id, "score": snappedf(s, 0.01), "reasons": reasons, "tag": tag})
	out.sort_custom(func(a, b): return float(a.score) > float(b.score) if float(a.score) != float(b.score) else int(a.u) < int(b.u))
	return out

## The MVP: {u, score, reasons, tag}, or {} for an empty match.
static func best(w: SimWorld) -> Dictionary:
	var r := rank(w)
	return r[0] if not r.is_empty() else {}

## Honours beside the MVP: the best of each kind among the others ({title, u, value}).
static func honours(w: SimWorld, mvp_id: int) -> Array:
	var out: Array = []
	var pick := func(title: String, key: Callable, fmt: Callable) -> void:
		var best_h: SimUnit = null
		var best_v := 0.0
		for h in w.heroes:
			if h.id == mvp_id:
				continue
			var v: float = key.call(h)
			if v > best_v:
				best_v = v
				best_h = h
		if best_h != null:
			out.append({"title": title, "u": best_h.id, "value": fmt.call(best_h, best_v)})
	pick.call("Top support", func(h): return h.heal_given / 350.0 + h.wards_placed * 0.75 + h.saves * 2.5 + h.disable_given / 6.0 + h.assists * 0.4,
		func(h, _v): return "%s healed  ·  %d wards  ·  %d saves" % [RankedNum.num(int(h.heal_given)), h.wards_placed, h.saves])
	pick.call("Most damage", func(h): return float(totals(h).hero), func(_h, v): return "%s to heroes" % RankedNum.num(int(v)))
	pick.call("Best farm", func(h): return float(h.last_hits), func(h, v): return "%d last hits  ·  %s net worth" % [int(v), RankedNum.num(h.networth())])
	return out

## Damage dealt by `h`, from its ledger: to heroes, to buildings (the scoreboard's numbers).
static func totals(h: SimUnit) -> Dictionary:
	var hero := 0.0
	var build := 0.0
	for k in h.dmg_out:
		var r: Array = h.dmg_out[k]
		hero += float(r[0])
		build += float(r[2])
	return {"hero": hero, "building": build}
