class_name ChatProfile
extends RefCounted
## Profiles in the match chat (run 2026-10-20; the owner: "AI players will REALLY CHECK each others' profiles especially
## the player and will react according to the player's profile, averages, last 3-5 games ... THEY WILL ACKNOWLEDGE IF
## YOU PLAYED GOOD, but some trolls will still troll you"). SimBotChat calls these at its moments:
##   * meet: at the start, a teammate or two and an enemy look you up (your card's "prof": averages, the last five
##     matches, the form, MVPs, rampages ...) and say what they see, each in its own manner (ProfileTalk.opinion);
##     a bot also looks up a teammate, who answers;
##   * review: every few minutes your game is held against your averages ("better than ur profile", "{n} deaths, right
##     on ur avg", "whos playing on ur account");
##   * ask: you ask them to check your profile ("check my profile", "my stats?"), or ask one about its own.
##   * ladder: they know the top 20 of the ladder (SimWorld.ladder) and answer "who is top 1", "top 10?", "best
##     player", and a question naming anyone in it ("is bunso94 good?", "check sensei"), with what they think of them.
## Everything draws from the chat's seeded generator.

var bc: SimBotChat
var w: SimWorld
var _live := {}                             # "kind:hero id" -> true once said this match
var said := 0

func _init(chat: SimBotChat = null) -> void:
	if chat == null:
		return
	bc = chat
	w = chat.w

func _r() -> RandomNumberGenerator:
	return bc._rng

## What bots can read of `u`'s profile ({} for a bot with no ladder profile).
func prof(u: SimUnit) -> Dictionary:
	if u == null:
		return {}
	var c: Dictionary = bc.social.card(u)
	return c.get("prof", {})

## How `h` reads profiles (ProfileTalk.manner).
func manner(h: SimUnit) -> String:
	var b = bc._bot_of(h)
	return ProfileTalk.manner(bc.persona(h), float(b.toxic) if b != null else 0.3, bool(b.rage) if b != null else false)

## What `h` thinks of the player already (-1..1, its memory).
func like(h: SimUnit) -> float:
	var b = bc._bot_of(h)
	return float(b.you_rec.get("rep", 0.0)) if b != null else 0.0

## The ladder entry a line names (a top-20 player, at least 4 letters of the name), or {}.
func named(low: String) -> Dictionary:
	var best := {}
	for e: Dictionary in w.ladder:
		var nm := String(e.name).to_lower()
		if nm.length() >= 4 and (low.contains(nm) or (nm.split(" ")[0].length() >= 5 and low.contains(nm.split(" ")[0]))):
			if best.is_empty() or nm.length() > String(best.name).length():
				best = e
	return best

func names_ladder(low: String) -> bool:
	if w.ladder.is_empty():
		return false
	var e := named(" " + low + " ")
	if e.is_empty():
		return false
	# a name in the match is about that player, not the ladder
	for u in w.heroes:
		if bc.pname(u).to_lower() == String(e.name).to_lower():
			return false
	return true

## Answer a question about the top of the ladder (top: the top 1, the top 5 or 10 listed) or about a ladder player the
## line names: the facts, then what this bot thinks of them (ProfileTalk.opinion), in its typing. Returns whether it spoke.
func ladder_ask(u: SimUnit, to: SimUnit, listeners: Array, all: bool, low: String, top: bool) -> bool:
	if w.ladder.is_empty():
		return false
	var h: SimUnit = to if to != null else bc._talker(listeners, "ego" if all else "talk")
	if h == null:
		return false
	var r := _r()
	var d := r.randf_range(1.0, 2.2)
	var text := ""
	var about := {}
	if top and not names_ladder(low):
		var want := 10 if (low.contains("10") or low.contains("leaderboard") or low.contains("players")) else (5 if low.contains("5") else (20 if low.contains("20") else 1))
		if want == 1:
			about = w.ladder[0]
			text = "%s is top 1, %s mmr, %s avg, mostly %s" % [String(about.name), str(int(about.mmr)), String(about.kda), String(about.hero)]
			if bool(about.get("you", false)) and String(about.id) == "me":
				text = "its u lol. top 1, %s mmr" % str(int(about.mmr))
		else:
			var names: Array = []
			for e: Dictionary in w.ladder.slice(0, want):
				names.append("%d %s" % [int(e.place), String(e.name)])
			text = "top %d: %s" % [want, ", ".join(names)]
		# where the player stands, if they are up there
		for e: Dictionary in w.ladder:
			if String(e.id) == "me" and text.find("its u") < 0:
				text += "  (ur #%d btw)" % int(e.place)
				break
	else:
		about = named(" " + low + " ")
		if about.is_empty():
			return false
		var rk := String(about.rank).to_lower()
		text = "%s? %s, %s avg, %d mvps, plays %s" % [String(about.name), rk if int(about.place) <= 10 else "#%d, %s" % [int(about.place), rk],
			String(about.kda), int(about.mvps), String(about.hero)]
		if String(about.id) == "me":
			text = "thats u lol. #%d, %s avg" % [int(about.place), String(about.kda)]
	bc._must = true
	bc._queue_line(h, text, all or h.team != u.team, "ladder", d, u.id, [], {})
	# and what it thinks of them (the top 1 or the one named)
	if not about.is_empty() and String(about.id) != "me" and r.randf() < 0.8:
		# its take on them (about them, not to the one who asked)
		var fa: Dictionary = about.prof
		var fl := ProfileTalk.fill(fa)
		fl["name"] = String(about.name)
		var sit := "pf_other_good" if ProfileTalk.verdict(fa) >= 0 or ProfileTalk.elite_facts(fa) else "pf_other_bad"
		bc.speak(h, sit, all or h.team != u.team, fl, 1.0, d + r.randf_range(1.2, 2.4), u.id, 0.0)
	said += 1
	return true

## `h` says what it sees in `about`'s profile. Returns whether it spoke.
func comment(h: SimUnit, about: SimUnit, all: bool, delay: float, chance := 1.0) -> bool:
	var f := prof(about)
	if h == null or f.is_empty() or int(f.get("games", 0)) + int(f.get("career_g", 0)) == 0:
		return false
	var op := ProfileTalk.opinion(manner(h), f, _r(), like(h) if not about.bot else 0.0, "with" if h.team == about.team else "vs")
	var sit := String(op[0])
	var fl: Dictionary = op[1]
	fl["name"] = bc.pname(about)
	if not bc.speak(h, sit, all, fl, chance, delay, about.id, 1.0):
		return false
	said += 1
	if not about.bot:
		if sit == "pf_accuse":
			bc._note(h, "accused_you")
		elif sit.begins_with("pf_good") or sit == "pf_kind_good" or sit in ["pf_pro_awe", "pf_pro_gopro", "pf_pro_root",
				"pf_pro_vs", "pf_pro_compare", "pf_pro_respect"]:
			bc._note(h, "praised_you")
		elif sit.begins_with("pf_bad") or sit.begins_with("pf_troll") or sit in ["pf_pro_hater", "pf_pro_troll"]:
			bc._note(h, "flamed_you")
	return true

## The start of the match: they look you up (and one looks up a teammate). Returns the time after the last line.
func meet(p: SimUnit, t0: float) -> float:
	if ChatSocial.off or p == null or prof(p).is_empty():
		return t0
	var t := t0
	var mates: Array = bc._bots(p.team)
	var foes: Array = bc._bots(1 - p.team)
	var n := 0
	var pool := mates.duplicate()
	while n < 2 and not pool.is_empty():
		var h: SimUnit = bc._talker(pool)
		pool.erase(h)
		if comment(h, p, false, t, 0.55 + bc._trait(h, "talk") * 0.4):
			n += 1
			t += _r().randf_range(1.8, 3.5)
	pool = foes.duplicate()
	var m := 0
	while m < 1 + (1 if _r().randf() < 0.4 else 0) and not pool.is_empty():
		var h2: SimUnit = bc._talker(pool, "ego")
		pool.erase(h2)
		if comment(h2, p, true, t, 0.45 + bc._trait(h2, "ego") * 0.4):
			m += 1
			t += _r().randf_range(1.8, 3.5)
	# a bot looks up a teammate (bots read each other too), who answers
	if _r().randf() < 0.55:
		for team in [p.team, 1 - p.team]:
			var bs: Array = bc._bots(team)
			if bs.size() < 2:
				continue
			var who: SimUnit = bc._talker(bs)
			var others: Array = bs.filter(func(x): return x != who and not prof(x).is_empty())
			if others.is_empty():
				continue
			var tgt: SimUnit = others[_r().randi_range(0, others.size() - 1)]
			var v := ProfileTalk.verdict(prof(tgt))
			var fl := ProfileTalk.fill(prof(tgt))
			fl["name"] = bc.pname(tgt)
			var sit := "pf_other_good" if v > 0 else ("pf_other_bad" if v < 0 or manner(who) in ["rough", "troll"] else "")
			if sit != "" and bc.speak(who, sit, false, fl, 0.8, t, tgt.id, 1.0):
				said += 1
				bc.speak(tgt, "pf_other_reply_good" if v > 0 else "pf_other_reply_bad", false, ProfileTalk.fill(prof(who)), 0.75,
					t + _r().randf_range(1.5, 3.0), who.id, 0.5)
				t += 4.0
			break
	return t

## Every few minutes: your game against your averages, once per kind a match.
func review() -> void:
	if ChatSocial.off or w.time < 480.0:
		return
	for p in bc._humans():
		var f := prof(p)
		if f.is_empty() or float(f.get("x", -1.0)) < 0.0:
			continue
		var fl := ProfileTalk.fill(f)
		fl["name"] = bc.pname(p)
		fl["n"] = p.deaths
		var avg_kda := maxf(0.5, float(f.kda))
		var live_kda := (float(p.kills) + float(p.assists)) / maxf(1.0, float(p.deaths))
		var key := ""
		var sit := ""
		var team: int = 1 - p.team
		if p.kills >= 6 and live_kda >= avg_kda * 1.8 and live_kda >= 4.0:
			key = "better"
			var foe := bc._talker(bc._bots(1 - p.team), "ego")
			if foe != null and manner(foe) in ["rough", "troll"] and _r().randf() < 0.6:
				sit = "pf_live_smurf"
			else:
				sit = "pf_live_better"
				team = p.team if _r().randf() < 0.6 else 1 - p.team
		elif p.deaths >= 6 and float(p.deaths) >= float(f.x) + 4.0:
			key = "worse"
			sit = "pf_live_worse"
		elif p.deaths >= 6 and absf(float(p.deaths) - float(f.x)) <= 0.8:
			key = "schedule"
			sit = "pf_live_schedule"
		if key == "" or _live.has("%s:%d" % [key, p.id]):
			continue
		var list: Array = bc._bots(team)
		if sit == "pf_live_better" and team == 1 - p.team:
			list = list.filter(func(x): return manner(x) in ["kind", "fair"])
		var h: SimUnit = bc._talker(list)
		if h != null and bc.speak(h, sit, h.team != p.team, fl, 0.75, -1.0, p.id, 1.5):
			_live["%s:%d" % [key, p.id]] = true
			said += 1
			if sit == "pf_live_smurf":
				bc._note(h, "accused_you")
			elif sit != "pf_live_better":
				bc._note(h, "flamed_you")

## You asked them to look at your profile (about_me) or asked `to` about its own. Answers at once.
func ask(u: SimUnit, to: SimUnit, listeners: Array, all: bool, about_me: bool) -> bool:
	var d := _r().randf_range(1.2, 2.6)
	if about_me:
		var first: SimUnit = to if to != null else bc._talker(listeners, "ego" if all else "talk")
		var order: Array = [first] + listeners.filter(func(x): return x != first)
		var spoke := 0
		for h in order:
			bc._must = true
			if comment(h, u, all or h.team != u.team, d, 1.0):
				spoke += 1
				d += _r().randf_range(1.4, 2.8)
				if spoke >= (2 if listeners.size() > 2 and _r().randf() < 0.6 else 1):
					return true
		return spoke > 0
	var who: SimUnit = to if to != null else bc._talker(listeners)
	if who == null:
		return false
	var f := prof(who)
	if f.is_empty():
		return false
	var v := ProfileTalk.verdict(f)
	bc._must = true
	return bc.speak(who, "pf_other_reply_good" if v > 0 else "pf_other_reply_bad", all or who.team != u.team,
		ProfileTalk.fill(f), 1.0, d, u.id, 0.0)
