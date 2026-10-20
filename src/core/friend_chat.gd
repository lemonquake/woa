class_name FriendChat
extends RefCounted
## Chat with friends (run 2026-10-20 e; the owner: "Overhaul and GREATLY ENHANCE ... the PLAYERS UI, like showing how
## many friends and online friends and offline friends and others, Friend chat"). Each conversation lives on your
## profile (me.chats: friend id -> messages {f: "y" you | "t" them, x: text, t: time}, the last 80), with what is unread
## (me.unread) and the answers still on their way (me.typing: {id, at, x}).
##
## A friend answers by what you wrote (ChatMind.intent: hello, how are you, duo, your profile, their profile, the top
## of the ladder, a player on it, praise, trash talk, thanks, gg) and by who they are (kind, rough, troll, show-off):
## online and free in a few seconds; in a match after it ("sorry was in a game"); away when they are back. Now and then
## an online friend writes first (a game of yours they saw, a duo, their own news). Words are the friend's own typing
## (Persona style). Your other accounts can be friends too: they never answer (it is you).

const KEEP := 80
const WROTE_FIRST := 1800                  # an online friend may write first once in this many seconds

static var rng := RandomNumberGenerator.new()

## A conversation, oldest first.
static func messages(id: String) -> Array:
	var me := Ranked.me()
	if not (me.get("chats") is Dictionary):
		me["chats"] = {}
	var c: Dictionary = me.chats
	if not (c.get(id) is Array):
		c[id] = []
	return c[id]

static func unread(id: String) -> int:
	return int((Ranked.me().get("unread", {}) as Dictionary).get(id, 0))

static func unread_total() -> int:
	var n := 0
	for k in (Ranked.me().get("unread", {}) as Dictionary):
		n += int(Ranked.me().unread[k])
	return n

static func mark_read(id: String) -> void:
	var me := Ranked.me()
	if me.get("unread") is Dictionary and (me.unread as Dictionary).has(id):
		me.unread.erase(id)
		Ranked.save()

## Whether a friend is typing an answer now (shown under the conversation).
static func typing(id: String) -> bool:
	for q in Ranked.me().get("typing", []):
		if String(q.get("id", "")) == id and int(q.get("at", 0)) - Ranked.now() <= 8:
			return true
	return false

## Conversations with something in them, the latest first: [[id, last message]].
static func recent() -> Array:
	var out: Array = []
	var c: Dictionary = Ranked.me().get("chats", {})
	for id in c:
		var ms: Array = c[id]
		if not ms.is_empty() and not Ranked.profile(String(id)).is_empty():
			out.append([String(id), ms[ms.size() - 1]])
	out.sort_custom(func(a, b): return int(a[1].t) > int(b[1].t))
	return out

## You write to a friend; their answer is on its way (see tick()).
static func send(id: String, text: String) -> void:
	var x := text.strip_edges().substr(0, 300)
	if x == "" or Ranked.profile(id).is_empty():
		return
	_add(id, "y", x)
	var p := Ranked.profile(id)
	if Ranked.is_yours(id):
		Ranked.save()
		return
	var me := Ranked.me()
	if not (me.get("typing") is Array):
		me["typing"] = []
	# one answer at a time per friend: a quick second line folds into the first
	for q in me.typing:
		if String(q.id) == id:
			q["also"] = String(q.get("also", "")) + " " + x
			Ranked.save()
			return
	var t := Ranked.now()
	var st := String(Persona.presence(p, t).state)
	var wait := rng.randi_range(3, 8) + x.length() / 25
	var pre := ""
	# talking with you right now (answered in the last ten minutes): they answer as if online
	var ms := messages(id)
	for i in range(ms.size() - 2, -1, -1):
		if String(ms[i].f) == "t":
			if t - int(ms[i].t) < 600:
				st = "online"
			break
	if st == "match":
		wait = rng.randi_range(40, 150)
		pre = _one(["sorry was in a game. ", "was in a game. ", "just finished a game. ", "sorry, game. ", "kakatapos lang ng game. "])
	elif st == "offline":
		wait = rng.randi_range(240, 1500)
		pre = _one(["sorry was away. ", "just saw this. ", "back. ", "sorry late reply. ", "ngayon ko lang nakita. "])
	(me.typing as Array).append({"id": id, "at": t + wait, "x": x, "pre": pre})
	Ranked.save()

## Deliver the answers that are due and maybe a friend's first message. Returns the ids with something new.
static func tick() -> Array:
	var me := Ranked.me()
	var t := Ranked.now()
	var got: Array = []
	var q_list: Array = me.get("typing", [])
	for i in range(q_list.size() - 1, -1, -1):
		var q: Dictionary = q_list[i]
		if int(q.at) > t:
			continue
		q_list.remove_at(i)
		var id := String(q.id)
		var p := Ranked.profile(id)
		if p.is_empty():
			continue
		var said := String(q.x) + " " + String(q.get("also", ""))
		var ans := String(q.get("pre", "")) + answer(p, said)
		_add(id, "t", typed(p, ans.strip_edges()))
		# a second line now and then (a question back, a laugh)
		if rng.randf() < 0.3:
			var more := _one(["wbu?", "u?", "how bout u", "ikaw?", "anyway", "haha", "lol"])
			_add(id, "t", typed(p, more))
		_unread(id)
		got.append(id)
	# an online friend writes first now and then
	if t - int(me.get("chat_first", 0)) >= WROTE_FIRST and rng.randf() < 0.5:
		me["chat_first"] = t
		var online: Array = (me.get("friends", []) as Array).map(func(fid): return Ranked.profile(String(fid))).filter(
			func(fp): return not fp.is_empty() and bool(fp.get("bot", false)) and Persona.online(fp, t))
		if not online.is_empty():
			var fp: Dictionary = online[rng.randi_range(0, online.size() - 1)]
			var fid := String(fp.id)
			_add(fid, "t", typed(fp, opener(fp)))
			_unread(fid)
			got.append(fid)
	if not got.is_empty():
		Ranked.save()
	return got

static func _add(id: String, from: String, x: String) -> void:
	var ms := messages(id)
	ms.append({"f": from, "x": x, "t": Ranked.now()})
	while ms.size() > KEEP:
		ms.pop_front()

static func _unread(id: String) -> void:
	var me := Ranked.me()
	if not (me.get("unread") is Dictionary):
		me["unread"] = {}
	me.unread[id] = int((me.unread as Dictionary).get(id, 0)) + 1

## A line in the friend's own typing.
static func typed(p: Dictionary, text: String) -> String:
	return ChatStyle.apply(text, (p.get("persona", {}) as Dictionary).get("style", {}), 0.0, rng, false, 0.1)

static func _one(a: Array) -> String:
	return String(a[rng.randi_range(0, a.size() - 1)])

static func _tl(p: Dictionary) -> bool:
	return float((p.get("voice", {}) as Dictionary).get("tl", 0.2)) >= 0.45 and rng.randf() < 0.7

## What a friend says first: your last game, a duo, how their games go.
static func opener(p: Dictionary) -> String:
	var me := Ranked.me()
	var lg: Dictionary = me.get("last_game", {})
	var tl := _tl(p)
	var x := rng.randf()
	if not lg.is_empty() and x < 0.35:
		var kda := "%d/%d/%d" % [int(lg.get("k", 0)), int(lg.get("x", 0)), int(lg.get("a", 0))]
		if ProfileTalk.elite(me):
			return _one(["saw ur %s game. u need to go pro fr" % kda, "%s again?? ur insane" % kda, "teach me pls. %s is crazy" % kda] if not tl else
				["nakita ko %s mo, idol talaga" % kda, "turuan mo naman ako, %s grabe" % kda])
		return _one(["saw ur last game, %s" % kda, "gg on ur last one", "how was ur last game"] if not tl else ["nakita ko last game mo, %s" % kda, "kamusta last game mo"])
	if x < 0.65:
		return _one(["duo?", "wanna queue?", "u on? lets duo", "one game?", "free for a game?"] if not tl else ["duo tayo?", "laro tayo", "g ka? duo", "isang game lang"])
	var s := int(p.get("streak", 0))
	if s >= 3:
		return "%d win streak lets gooo" % s if not tl else "%d sunod na panalo pre" % s
	if s <= -3:
		return "lost %d in a row, i need a carry" % -s if not tl else "%d talo na ako sunod sunod, buhatin mo ko" % -s
	var learning := String(p.get("learning", ""))
	if learning != "":
		return "trying %s lately, any tips?" % HeroDraft.hero_name(learning) if not tl else "nag aaral ako ng %s, tips?" % HeroDraft.hero_name(learning)
	return _one(["yo", "hey", "sup", "u there?"] if not tl else ["uy", "musta", "pre", "lods"])

## What `viewer` says about a third player (not you): the facts (rank, place, average K/D/A), then its take, about them
## and not to you (ProfileLines' pf_other_*).
static func about_line(viewer: Dictionary, about: Dictionary) -> String:
	var av := Career.averages(about)
	var place := Ranked.place_of(String(about.id))
	var rk := Ranked.rank_label(about).to_lower()
	var facts := "%s, %s avg" % [rk if place <= Ranked.TOP else "%s, #%d" % [rk, place], Career.kda_text(av).replace(" ", "")]
	var f := ProfileTalk.read(about)
	var fl := ProfileTalk.fill(f)
	var sit := "pf_other_good" if ProfileTalk.verdict(f) >= 0 or ProfileTalk.elite_facts(f) else "pf_other_bad"
	var take := ProfileTalk.say(viewer, sit, fl, rng)
	return facts + (". " + take if take != "" else "")

## A friend's answer to what you wrote, by its meaning and the friend's manners.
static func answer(p: Dictionary, said: String) -> String:
	var low := said.to_lower()
	var it := ChatMind.intent(low)
	var m := ProfileTalk.manner_of(p)
	var tl := _tl(p)
	var me := Ranked.me()
	# a player of the ladder named in the line, or the top of it
	var named := Ranked.named_in(low)
	if it == "ladder_top" or (not named.is_empty() and String(named.id) != String(p.id) and String(named.id) != "me"):
		var about := named
		var lead := ""
		if about.is_empty() or it == "ladder_top" and not low.contains(String(named.get("name", "")).to_lower()):
			var card := Ranked.ladder_card(10)
			about = Ranked.profile(String(card[0].id))
			if low.contains("10") or low.contains("5") or low.contains("players") or low.contains("leaderboard"):
				var names: Array = card.slice(0, 10 if low.contains("10") else 5).map(func(e): return "%d %s" % [int(e.place), String(e.name)])
				return "top: " + ", ".join(names)
			lead = "%s is top 1. " % String(about.name)
		if String(about.get("id", "")) == "me":
			return lead + ("its u lol" if not tl else "ikaw yun lol")
		return lead + about_line(p, about)
	match it:
		"greet":
			return _one(["yo", "hey!", "sup", "hello", "yo whats up"] if not tl else ["uy!", "musta lods", "oy", "hello pre"])
		"add":
			return _one(["we're already friends lol", "duo? sure, invite me", "down, queue up"] if not tl else ["friends na tayo haha", "g, duo tayo"])
		"profile_me":
			var line := ProfileTalk.line_about(p, me, rng, "with")
			return line if line != "" else "ur doing fine"
		"profile_you":
			var f := ProfileTalk.read(p)
			return "%s, %s avg, %d games. not bad right?" % [Ranked.rank_label(p).to_lower(), Career.kda_text(Career.averages(p)).replace(" ", ""), int(f.games)]
		"rank":
			return "im %s, %d mmr" % [Ranked.rank_label(p).to_lower(), int(p.mmr)]
		"praise", "thanks", "gg":
			return _one(["haha ty", "u too", "thanks man", "anytime", "<3"] if not tl else ["salamat lods", "ikaw din", "ty pre"])
		"taunt", "insult":
			if m in ["rough", "troll"]:
				return _one(["says the guy who needs me to win", "ok mr keyboard", "come 1v1 then", "talk after u win a game without me",
					"who hurt u"] if not tl else ["ikaw nga eh", "1v1 tayo", "yabang mo ah", "tahimik ka nga"])
			return _one(["damn ok lol", "bad day?", "u good?", "chill... jk say it to the enemy"] if not tl else ["grabe ka haha", "badtrip ka?", "okay ka lang?"])
		"sorry":
			return _one(["np", "its fine", "all good"] if not tl else ["okay lang", "wala yun"])
		"why":
			return _one(["idk tbh", "no idea lol", "cause the game hates us"] if not tl else ["ewan ko rin", "malay ko haha"])
	# play together
	if low.contains("duo") or low.contains("play") or low.contains("game") or low.contains("queue") or low.contains("laro"):
		var st := String(Persona.presence(p, Ranked.now()).state)
		if st == "match":
			return _one(["in a game rn, after this?", "after this one", "give me 20 min"] if not tl else ["may game pa ako, after", "mamaya pagkatapos nito"])
		if ProfileTalk.elite(me):
			return _one(["duo with u?? obviously yes", "free win, im in", "lets go, carry me"] if not tl else ["oo naman, buhat mo ko", "g agad, idol"])
		return _one(["sure, invite me", "ok one game", "down", "g"] if not tl else ["g", "sige", "tara"])
	if low.contains("how are") or low.contains("hows it") or low.contains("kamusta") or low.contains("musta") or low.contains("wyd"):
		var s := int(p.get("streak", 0))
		if s >= 3:
			return "good, %d win streak" % s if not tl else "ayos, %d panalo sunod sunod" % s
		if s <= -3:
			return "bad, lost %d in a row" % -s if not tl else "pangit, %d talo na" % -s
		return _one(["good, just grinding", "tired lol", "chillin", "ok, one more game then sleep"] if not tl else ["ayos lang", "puyat haha", "chill lang"])
	if low.contains("?"):
		return _one(["hmm idk", "maybe", "probably yeah", "not sure lol", "good question"] if not tl else ["siguro", "ewan haha", "pwede"])
	if m == "troll":
		return _one(["ok", "lol", "and?", "cool story"] if not tl else ["ok", "tapos?", "haha"])
	return _one(["haha", "true", "nice", "ye", "lol fr"] if not tl else ["haha", "oo nga", "ayos", "totoo"])
