class_name ChatSocial
extends RefCounted
## The crowd (run 2026-10-19 e; the owner: "AI players that REALLY REACT when someone (ANYONE) is owning or dying too
## much ... Double, Triple, Rampage (most reactions) ... remember those ... ACTUALLY ADD THE PLAYER if they say they wanna
## add the player ... praise if the player is owning or mock if the player is bad or even accuse the player of cheating
## ... very particular with someone's KDA ... accuse them of smurfing then threaten to report them ... reply if they
## notice the player is trashtalking ... strongly react if someone is MVP in their last game ... I wanna simulate the
## toxicity of the MOBA community"). SimBotChat calls these at its moments; the lines are ChatMore's, typed by ChatStyle.
##   * multi-kills by anyone: a double draws a word or two, a triple a few, an ultra kill more, a rampage the whole
##     lobby (the killer's team hypes it, the victims rage, accuse and blame each other);
##   * streaks (5, 7, 9, 11): the killer's team cheers it on, the other team calls to focus it, a shutdown is cheered;
##   * dying too much (5, 8, 11 ... deaths with a poor score): the enemy mocks the free gold, teammates flame or (kind
##     ones) help;
##   * the KDA review every few minutes: a stand-out score draws smurf and cheating accusations and report threats from
##     the enemy (arrogant high-rank players dismiss it, kind ones respect it) and praise from teammates; a terrible one
##     draws "boosted" and "who boosted u";
##   * the player's trash talk ("ez", "sit", insults) in all chat: the enemy answers with the facts (the player's score,
##     the gold gap, a death a moment ago), piles on, threatens a report; teammates tell them to stop or join in;
##   * "add me": the bot asked says yes or no by what it thinks of the player (its memory and this match), and a yes
##     really makes you friends (event "friend", Ranked);
##   * the MVP: a player who was MVP last game is expected to carry (called out at the start, mocked if bad, praised if
##     good); the MVP of this match is cheered and called a smurf at the end;
##   * bots who met before in a match say so ("{name} the feeder from last time").
## What the player said and did here goes back to Ranked through SimBotChat.relations() (trash talk, reports,
## accusations, praise, a friendship).
## Everything draws from the chat's seeded generator (multiplayer peers see the same lines).

const C = preload("res://src/sim/sim_const.gd")
## Line kinds that count as an accusation of the target (relations "accused_you").
const ACCUSE := ["salty_rampage", "kda_smurf", "kda_cheat", "mvp_salty"]
## Line kinds that count as a report threat (relations "reported_you").
const REPORT := ["kda_report", "tt_report", "end_report"]
const PRAISE := ["hype_triple", "hype_ultra", "hype_rampage", "kda_praise", "kda_respect", "mvp_cheer", "streak_ally"]

## Tools only: the crowd stays quiet (the A/B review plays the same match without it).
static var off := false

var bc: SimBotChat
var w: SimWorld
var _streak_said := {}                      # hero id -> highest streak reacted to
var _feed_said := {}                        # hero id -> death count last mocked
var _kda_said := {}                         # "id:great" / "id:awful" -> time
var _mvp_expect := {}                       # hero id -> true once the MVP expectation was voiced
var tt_count := {}                          # player hero id -> trash talk lines this match
var _tt_last := {}                          # player hero id -> time of the last answered trash talk
var _asked := {}                            # bot hero id -> answered the player's "add me" already
var said := 0

func _init(chat: SimBotChat = null) -> void:
	if chat == null:
		return                                   # being restored from a snapshot (SimSnapshot sets every field)
	bc = chat
	w = chat.w

func _r() -> RandomNumberGenerator:
	return bc._rng

# ---- Facts ------------------------------------------------------------------------------------------------------------

## What bots know of `u`'s standing: a bot's ranked card, the player's card (main.gd sets w.player_cards).
func card(u: SimUnit) -> Dictionary:
	if u == null:
		return {}
	if not u.bot:
		return w.player_cards.get(u.id, {})
	var b = bc._bot_of(u)
	return b.card if b != null else {}

func rank_lc(u: SimUnit) -> String:
	return String(card(u).get("rank", "")).to_lower()

func tier(u: SimUnit) -> int:
	return int(card(u).get("tier", -1))

func kda(u: SimUnit) -> String:
	return "%d/%d/%d" % [u.kills, u.deaths, u.assists]

## (kills + half the assists) per death.
func ratio(u: SimUnit) -> float:
	return (float(u.kills) + float(u.assists) * 0.5) / maxf(1.0, float(u.deaths))

func fill(u: SimUnit) -> Dictionary:
	var f := {"name": bc.pname(u), "kda": kda(u), "hero": bc.label(u).to_lower(), "n": u.deaths, "lh": u.last_hits,
		"min": maxi(1, int(w.time / 60.0))}
	var rk := rank_lc(u)
	if rk != "":
		f["rank"] = rk
	return f

func _trait(h: SimUnit, k: String) -> float:
	return bc._trait(h, k)

# ---- Saying -----------------------------------------------------------------------------------------------------------

## Up to `n` different bots of `list` each say a line of `sit`, one after another from `t0` seconds. note: what it
## counts toward with `about` when that is the player (accused_you, reported_you, praised_you). Returns how many spoke.
func crowd(list: Array, sit: String, all: bool, f: Dictionary, n: int, chance: float, t0: float, about: SimUnit = null,
		target := -1) -> int:
	var pool := list.duplicate()
	var spoke := 0
	var t := t0
	while spoke < n and not pool.is_empty():
		var h: SimUnit = bc._talker(pool)
		pool.erase(h)
		if one(h, sit, all, f, chance, t, about, target):
			spoke += 1
			t += _r().randf_range(0.7, 1.8)
	return spoke

## One bot says a line of `sit` (a short gap since its last line: big moments get quick answers).
func one(h: SimUnit, sit: String, all: bool, f: Dictionary, chance: float, delay: float, about: SimUnit = null, target := -1) -> bool:
	if h == null:
		return false
	if not bc.speak(h, sit, all, f, chance, delay, target, 1.2):
		return false
	said += 1
	if about != null and not about.bot:
		if sit in ACCUSE:
			bc._note(h, "accused_you")
		elif sit in REPORT:
			bc._note(h, "reported_you")
		elif sit in PRAISE:
			bc._note(h, "praised_you")
	return true

# ---- Kills --------------------------------------------------------------------------------------------------------------

## A hero kill (SimBotChat._on_kill): multi-kills, streaks, shutdowns, a victim who keeps dying.
func on_kill(e: Dictionary, killer: SimUnit, victim: SimUnit) -> void:
	if off:
		return
	if killer != null:
		_multi(killer, victim, mini(int(e.get("multi", 0)), 5))
		_streak(killer, victim, int(e.get("streak", 0)), int(e.get("ended_streak", 0)))
	_feeding(victim)

func _multi(k: SimUnit, v: SimUnit, m: int) -> void:
	if m < 2:
		return
	var mates := bc._bots(k.team, k)
	var foes := bc._bots(v.team)
	var f := fill(k)
	match m:
		2:
			crowd(mates, "hype_double", false, f, 1, 0.5, 1.6, k)
			crowd(foes, "salty_multi", true, f, 1, 0.22, 2.4, k)
		3:
			crowd(mates, "hype_triple", _r().randf() < 0.3, f, 2, 0.8, 1.2, k)
			var ft := f.duplicate()
			ft["n"] = 3
			if crowd(foes, "salty_named", _r().randf() < 0.6, ft, 1, 0.85, 1.8, k) == 0:
				crowd(foes, "salty_multi", true, f, 1, 0.7, 2.6, k)
			crowd(foes, "victim_blame", false, {}, 1, 0.45, 4.2)
		4:
			crowd(mates, "hype_ultra", _r().randf() < 0.4, f, 3, 0.9, 1.0, k)
			var fu := f.duplicate()
			fu["n"] = 4
			crowd(foes, "salty_named", true, fu, 1, 1.0, 1.6, k)
			crowd(foes, "salty_rampage", true, f, 2, 0.8, 3.0, k)
			crowd(foes, "victim_blame", false, {}, 1, 0.6, 5.0)
		_:
			# a rampage: everyone has something to say
			if k.bot:
				one(k, "killer_rampage", true, f, 1.0, 0.7)
			crowd(mates, "hype_rampage", _r().randf() < 0.55, f, 4, 1.0, 1.0, k)
			crowd(foes, "salty_rampage", true, f, 4, 1.0, 2.0, k)
			crowd(foes, "victim_blame", false, {}, 2, 0.8, 5.5)
			for x in foes:
				bc.mind(x).tilt = minf(1.0, float(bc.mind(x).tilt) + 0.2)

func _streak(k: SimUnit, v: SimUnit, st: int, ended: int) -> void:
	if ended >= 5:
		crowd(bc._bots(k.team), "shutdown_cheer", _r().randf() < 0.3, {}, 2 if ended >= 8 else 1, 0.75, 1.2)
	if not (st in [5, 7, 9, 11, 13, 15, 18, 20, 25, 30, 35, 40]) or int(_streak_said.get(k.id, 0)) >= st:
		return
	_streak_said[k.id] = st
	var f := fill(k)
	f["n"] = st
	crowd(bc._bots(k.team, k), "streak_ally", false, f, 1, 0.6, 2.2, k)
	crowd(bc._bots(v.team), "streak_enemy", false, {"hero": bc.label(k).to_lower(), "n": st}, 1, 0.8, 2.8)
	if not k.bot or _r().randf() < 0.6:
		crowd(bc._bots(v.team), "streak_enemy_all", true, f, 1, 0.55, 4.0)
	if st >= 10:
		# a streak that long: the victims call it a smurf or hacks, and someone threatens a report
		var foes := bc._bots(v.team)
		var sit := "kda_cheat" if st >= 18 and _r().randf() < 0.5 else "kda_smurf"
		if crowd(foes, sit, true, f, 1, 0.9, 5.0, k) > 0 and st >= 15:
			crowd(foes.filter(func(x): return _trait(x, "kind") < 0.6), "kda_report", true, f, 1, 0.7, 7.0, k)

## 5, 8, 11 ... deaths with a poor score: the enemy mocks, teammates flame (or help), the bot itself says sorry.
func _feeding(v: SimUnit) -> void:
	var d := v.deaths
	if not (d in [5, 8, 11, 14, 17, 20]) or int(_feed_said.get(v.id, 0)) >= d:
		return
	if float(d) < float(v.kills) + float(v.assists) * 0.5 + 3.0:
		return
	_feed_said[v.id] = d
	var f := fill(v)
	f["n"] = d
	crowd(bc._bots(1 - v.team), "feed_enemy_mock", true, f, 1 if d < 8 else 2, 0.6, 1.8, v)
	var mates := bc._bots(v.team, v)
	var kind: Array = mates.filter(func(x): return _trait(x, "kind") > 0.72)
	var rough: Array = mates.filter(func(x): return _trait(x, "kind") <= 0.72)
	if not rough.is_empty() and (kind.is_empty() or _r().randf() < 0.7):
		crowd(rough, "feed_ally_flame", false, f, 1 if d < 11 else 2, 0.7, 2.4, v, v.id)
	elif not kind.is_empty():
		crowd(kind, "feed_ally_kind", false, f, 1, 0.6, 2.4)
	if v.bot and _r().randf() < 0.5:
		one(v, "feed_self", false, {}, 0.6, 4.5)

# ---- The KDA review ----------------------------------------------------------------------------------------------------

## Every few minutes (SimBotChat._review): the stand-out scores, the player's first.
func review() -> void:
	if off:
		return
	if w.time < 360.0:
		return
	var order: Array = bc._humans() + w.heroes.filter(func(x): return x.bot)
	var great_done := false
	var awful_done := false
	for h in order:
		var r := ratio(h)
		var great: bool = h.kills >= 6 and r >= 4.0 or h.kills >= 10 and r >= 3.0
		var awful: bool = h.deaths >= 7 and r <= 0.45
		if great and not great_done and w.time - float(_kda_said.get("%d:great" % h.id, C.LONG_AGO)) > 260.0:
			if not h.bot or r >= 6.0 or h.kills >= 12 or _r().randf() < 0.45:
				_kda_said["%d:great" % h.id] = w.time
				great_done = true
				_great(h, r)
		elif awful and not awful_done and w.time - float(_kda_said.get("%d:awful" % h.id, C.LONG_AGO)) > 260.0:
			if not h.bot or _r().randf() < 0.45:
				_kda_said["%d:awful" % h.id] = w.time
				awful_done = true
				_awful(h)
		if not h.bot:
			_mvp_expectation(h, great, awful or h.deaths >= h.kills + 4)

func _great(h: SimUnit, r: float) -> void:
	var foes := bc._bots(1 - h.team)
	var mates := bc._bots(h.team, h)
	var f := fill(h)
	var big := r >= 6.0 or h.kills >= 12                  # a bot running away with the game counts like a player
	var n_foes := 3 if not h.bot else (2 if big else 1)
	var t := 1.0
	var pool := foes.duplicate()
	var accused := false
	for i in n_foes:
		if pool.is_empty():
			break
		var x: SimUnit = bc._talker(pool, "ego")
		pool.erase(x)
		var sit := "kda_smurf"
		if _trait(x, "kind") > 0.72 and float(bc.mind(x).tilt) < 0.5:
			sit = "kda_respect"
		elif tier(x) >= 0 and tier(x) >= tier(h) + 2 and _trait(x, "ego") > 0.5:
			sit = "kda_arrogant"
		elif not h.bot and (r >= 7.0 or h.best_multi >= 4) and _r().randf() < 0.55:
			sit = "kda_cheat"
		var ff := f.duplicate()
		var mr := rank_lc(x)
		if mr != "":
			ff["myrank"] = mr
		if one(x, sit, true, ff, 0.95 if not h.bot or big else 0.6, t, h):
			t += _r().randf_range(1.0, 2.2)
			accused = accused or sit in ["kda_smurf", "kda_cheat"]
	if accused and (not h.bot or big):
		var rough: Array = foes.filter(func(x): return _trait(x, "kind") < 0.5)
		crowd(rough, "kda_report", true, f, 1, 0.75, t + 0.6, h)
	crowd(mates, "kda_praise", false, f, 2 if not h.bot else 1, 0.75 if not h.bot else 0.45, 1.6, h)

func _awful(h: SimUnit) -> void:
	var f := fill(h)
	crowd(bc._bots(1 - h.team), "kda_awful_enemy", true, f, 2 if not h.bot else 1, 0.7, 1.2, h)
	var mates: Array = bc._bots(h.team, h).filter(func(x): return _trait(x, "kind") < 0.65)
	if crowd(mates, "kda_awful_ally", false, f, 1, 0.75, 2.6, h, h.id) > 0 and not h.bot and _r().randf() < 0.45:
		crowd(mates, "kda_report", false, f, 1, 0.7, 5.0, h)

## A player who was MVP in their last game: expected to carry.
func _mvp_expectation(p: SimUnit, good: bool, bad: bool) -> void:
	if _mvp_expect.has(p.id) or not bool(card(p).get("last_mvp", false)) or w.time < 480.0:
		return
	if bad:
		_mvp_expect[p.id] = true
		var f := fill(p)
		crowd(bc._bots(1 - p.team), "mvp_expect_fail", true, f, 1, 0.85, 1.4, p)
		crowd(bc._bots(p.team), "mvp_expect_fail", false, f, 1, 0.6, 3.2, p)
	elif good:
		_mvp_expect[p.id] = true
		crowd(bc._bots(p.team), "mvp_expect_good", false, fill(p), 1, 0.7, 1.6, p)

# ---- The player's words ------------------------------------------------------------------------------------------------

## The player trash talks ("ez", "sit", an insult) in all chat, or at an enemy: the enemy answers with what it knows.
func trash_talk(u: SimUnit, to: SimUnit, all: bool) -> void:
	if off:
		return
	var foes := bc._bots(1 - u.team)
	if foes.is_empty():
		return
	tt_count[u.id] = int(tt_count.get(u.id, 0)) + 1
	var n := int(tt_count[u.id])
	for x in foes:
		bc._note(x, "trash_talked")
	var f := fill(u)
	var gap := int(round(float(bc._team_nw(1 - u.team) - bc._team_nw(u.team)) / 1000.0))
	f["n"] = absi(gap)
	var bad := float(u.deaths) >= float(u.kills) + float(u.assists) * 0.5 + 2.0
	var good := ratio(u) >= 2.5 and u.kills >= 3
	var dead := not u.alive or w.time - u.death_at < 10.0
	var first: SimUnit = to if to != null and to.team != u.team else bc._talker(foes, "ego")
	var sit := "tt_back"
	if dead:
		sit = "tt_after_death"
	elif bad:
		sit = "tt_fact"
	elif gap >= 3:
		sit = "tt_gold"
	elif _trait(first, "kind") > 0.78 and float(bc.mind(first).tilt) < 0.4:
		sit = "tt_witty"                        # a nice one still jabs back, never "be nice" (the owner, 2026-10-20)
	elif good:
		sit = "kda_smurf" if ratio(u) >= 5.0 and _r().randf() < 0.4 else "tt_lucky"
	bc.mind(first).tilt = minf(1.0, float(bc.mind(first).tilt) + 0.12)
	var d := _r().randf_range(0.9, 2.0)
	if not one(first, sit, true, f, 1.0, d, u):
		var others := foes.filter(func(x): return x != first)
		first = bc._talker(others, "ego")
		one(first, sit, true, f, 1.0, d, u)
	# the pile-on: a second voice, a report threat once it keeps going
	var rest: Array = foes.filter(func(x): return x != first)
	var t := d + _r().randf_range(1.2, 2.4)
	if n >= 2 or _r().randf() < 0.55:
		var x2: SimUnit = bc._talker(rest, "ego")
		if x2 != null:
			var s2 := "tt_report" if n >= 3 and _trait(x2, "kind") < 0.4 and _r().randf() < 0.3 else ("tt_fact" if bad else "tt_back")
			if one(x2, s2, true, f, 0.85, t, u):
				t += _r().randf_range(1.0, 2.0)
			rest.erase(x2)
	if n >= 3:
		crowd(rest, "tt_fact" if bad else "tt_back", true, f, 1, 0.8, t, u)
	# the player's own team: the rough ones join in (nobody tells the player to calm down: the owner, 2026-10-20,
	# "they try to pacify the player which is STUPID")
	var mates := bc._bots(u.team)
	var toxic: Array = mates.filter(func(x): return _trait(x, "kind") < 0.45 or _trait(x, "ego") > 0.6)
	if not toxic.is_empty() and not bad and _r().randf() < 0.45:
		crowd(toxic, "tt_ally_join", true, {}, 1, 0.8, t + 0.5)
	_tt_last[u.id] = w.time

## The player asks to be friends ("add me", "duo after?"): the bot asked says yes or no by what it thinks of the
## player; yes makes you friends (event "friend").
func friend_ask(u: SimUnit, to: SimUnit, listeners: Array, all: bool) -> void:
	if off:
		return
	var who := to
	if who == null:
		var last: Dictionary = bc._speaker[2 if all else u.team]
		if not last.is_empty() and w.time - float(last.t) < 15.0:
			var lu := w.get_unit(int(last.u))
			if lu != null and lu in listeners:
				who = lu
	if who == null:
		who = bc._talker(listeners, "kind")
	if who == null:
		return
	var b = bc._bot_of(who)
	if b == null:
		return
	var d := _r().randf_range(1.0, 2.4)
	var rec: Dictionary = b.you_rec
	if bool(rec.get("friend", false)) or _asked.has(who.id):
		bc.speak(who, "add_already", who.team != u.team or all, fill(u), 1.0, d, -1, 1.0)
		return
	_asked[who.id] = true
	var rel: Dictionary = bc._rel.get(who.id, {})
	var score := float(rec.get("rep", 0.0)) * 1.2 + _trait(who, "kind") * 0.7 - _trait(who, "ego") * 0.2
	score += 0.35 if who.team == u.team else -0.05
	score += 0.3 * minf(2.0, float(rel.get("praised", 0)) + float(rel.get("praised_you", 0)) * 0.5)
	score -= 0.45 * minf(2.0, float(rel.get("flamed", 0)) + float(rel.get("trash_talked", 0)) * 0.5)
	score += 0.3 if ratio(u) >= 3.0 and u.kills >= 4 else (-0.25 if float(u.deaths) >= float(u.kills + u.assists) + 4.0 else 0.0)
	score += _r().randf_range(-0.15, 0.15)
	if score >= 0.5:
		if bc.speak(who, "add_yes", who.team != u.team or all, fill(u), 1.0, d, -1, 1.0):
			bc._note(who, "befriended")
			if String(b.pid) != "":
				w.events.append({"t": "friend", "u": who.id, "pid": String(b.pid), "what": "added", "name": bc.pname(who)})
	else:
		bc.speak(who, "add_no", who.team != u.team or all, fill(u), 1.0, d, -1, 1.0)
	if _r().randf() < 0.25:
		var others := listeners.filter(func(x): return x != who)
		crowd(others, "add_tease", all, {}, 1, 0.8, d + 1.8)

# ---- Meeting -------------------------------------------------------------------------------------------------------------

## The start of the match (SimBotChat._memories): the player's last MVP, bots who met each other, a bot's own MVP.
## t0: when the first line may come. Returns the time after the last line queued.
func meet(p: SimUnit, t0: float) -> float:
	if off:
		return t0
	var t := t0
	if p != null and bool(card(p).get("last_mvp", false)):
		var f := fill(p)
		if crowd(bc._bots(p.team), "meet_mvp_ally", false, f, 2, 0.85, t, p) > 0:
			t += 3.0
		if crowd(bc._bots(1 - p.team), "meet_mvp_enemy", true, f, 1, 0.75, t, p) > 0:
			t += 2.5
	# bots who met before
	var pairs := 0
	var by_pid := {}
	for b in w.bots:
		if String(b.pid) != "" and b.hero() != null:
			by_pid[String(b.pid)] = b
	var order: Array = w.bots.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := _r().randi_range(0, i)
		var x = order[i]
		order[i] = order[j]
		order[j] = x
	for b in order:
		if pairs >= 3:
			break
		var h: SimUnit = b.hero()
		var seen: Dictionary = (b.card as Dictionary).get("seen", {})
		if h == null or seen.is_empty() or b.passive or b.human:
			continue
		for oid in seen:
			if not by_pid.has(String(oid)) or String(oid) == String(b.pid):
				continue
			var ob = by_pid[String(oid)]
			var oh: SimUnit = ob.hero()
			var note := String((seen[oid] as Dictionary).get("note", ""))
			var sit: String = {"feeder": "known_feeder", "rampage": "known_rampage", "flamer": "known_flamer",
				"mvp": "known_mvp"}.get(note, "known_again")
			if one(h, sit, oh.team != h.team, {"name": bc.pname(oh)}, 0.75, t):
				pairs += 1
				bc.speak(oh, "known_reply", oh.team != h.team, {}, 0.5, t + _r().randf_range(1.5, 3.0), -1, 1.0)
				t += _r().randf_range(2.0, 4.0)
			break
	# a bot that was MVP last game
	for b in order:
		var h2: SimUnit = b.hero()
		if h2 == null or not bool((b.card as Dictionary).get("last_mvp", false)) or b.passive or b.human:
			continue
		if _trait(h2, "ego") > 0.55:
			one(h2, "meet_bot_mvp", _r().randf() < 0.4, {}, 0.5, t)
		else:
			crowd(bc._bots(h2.team, h2), "meet_bot_mvp_other", false, {"name": bc.pname(h2)}, 1, 0.35, t)
		t += 2.0
		break
	return t

## A bot's memory of the player beyond the last result (ranked "you"): a rampage it saw, trash talk, a report.
## Returns the situation or "".
func memory_sit(rec: Dictionary) -> String:
	if off:
		return ""
	if int(rec.get("reported_you", 0)) > 0 and _r().randf() < 0.35:
		return "meet_reported"
	if int(rec.get("trash_talked", 0)) >= 2 and _r().randf() < 0.7:
		return "meet_trash"
	if int(rec.get("last_you_multi", 0)) >= 5 or (int(rec.get("you_rampage", 0)) > 0 and _r().randf() < 0.5):
		return "meet_rampage"
	return ""

# ---- The end ----------------------------------------------------------------------------------------------------------------

## The match is over: the MVP cheered and called a smurf, trash talk paid back, reports, friend offers. Lines go out at
## once (SimBotChat._flush_all).
func on_end(winner: int) -> void:
	if off:
		return
	var best := MatchMvp.best(w)
	var mvp := w.get_unit(int(best.get("u", -1)))
	for p in bc._humans():
		var f := fill(p)
		if mvp == p:
			_now_crowd(bc._bots(p.team), "mvp_cheer", false, f, 2, 0.7, p)
			_now_crowd(bc._bots(1 - p.team), "mvp_salty", true, f, 1, 0.55, p)
		if int(tt_count.get(p.id, 0)) > 0:
			_now_crowd(bc._bots(1 - p.team), "end_tt_won" if winner != p.team else "end_tt_lost", true, f, 2 if winner != p.team else 1, 0.8, p)
		# bots that threatened a report follow through in chat
		var rep: Array = (bc._bots(0) + bc._bots(1)).filter(func(x): return int((bc._rel.get(x.id, {}) as Dictionary).get("reported_you", 0)) > 0)
		_now_crowd(rep, "end_report", true, f, 1, 0.6, p)
		# friend offers: a teammate who enjoyed it, an enemy who respected it
		var good: bool = ratio(p) >= 2.0 or mvp == p
		var offers := 0
		for b in w.bots:
			var h: SimUnit = b.hero()
			if h == null or b.passive or b.human or offers >= 2 or bool(b.you_rec.get("friend", false)) or _asked.has(h.id):
				continue
			var rel: Dictionary = bc._rel.get(h.id, {})
			if int(rel.get("flamed", 0)) > 0 or int(rel.get("trash_talked", 0)) > 0 or int(rel.get("befriended", 0)) > 0:
				continue
			var like := float(b.you_rec.get("rep", 0.0)) + _trait(h, "kind") * 0.5
			like += (0.35 if p.team == winner else 0.0) + (0.3 if good else -0.2) if h.team == p.team else (0.25 if good and _trait(h, "kind") > 0.6 else -0.4)
			like += 0.25 * float(rel.get("praised", 0))
			if like >= 0.75 and _r().randf() < 0.5:
				if _now_line(h, "add_offer", h.team != p.team, f):
					offers += 1
					if String(b.pid) != "":
						w.events.append({"t": "friend", "u": h.id, "pid": String(b.pid), "what": "request", "name": bc.pname(h)})

## Lines said at once (the world has stopped).
func _now_line(h: SimUnit, sit: String, all: bool, f: Dictionary) -> bool:
	if h == null:
		return false
	var text := ChatMind.pick(sit, f, _r().randf() < float(bc.voice(h).tl), _r())
	if text == "":
		return false
	bc._queue.append({"at": w.time, "team": h.team, "u": h.id, "text": ChatStyle.apply(text, bc._style(h), 0.0, _r(), false, 0.1),
		"all": all, "cat": sit})
	return true

func _now_crowd(list: Array, sit: String, all: bool, f: Dictionary, n: int, chance: float, about: SimUnit = null) -> void:
	var pool := list.duplicate()
	var spoke := 0
	while spoke < n and not pool.is_empty():
		var h: SimUnit = bc._talker(pool)
		pool.erase(h)
		if _r().randf() <= chance and _now_line(h, sit, all, f):
			spoke += 1
			if about != null and sit in REPORT:
				bc._note(h, "reported_you")
