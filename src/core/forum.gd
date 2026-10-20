class_name Forum
extends RefCounted
## The Forums (run 2026-10-19 e; the owner: "a FORUMS section that uses the LLM (also works for no LLM but of course
## LLM is more alive feeling) to make the AI players have their very own personality and actually post - kinda like a
## Reddit corner for the game. Some will troll and some will contribute. AI players will remember you and other AI
## players. They will acknowledge, they will react, they will discuss. Especially if the player posts, then AI players
## will usually reply and discuss ... VERY particular with someone's rank, skill ... high MMR are usually confident and
## arrogant assholes (there are some who are very kind of course)").
##
## The ladder's players (Ranked) post threads and reply while you are away, from what really happens on the ladder and
## to you: ranks reached, rampages, Top 1 players, losing streaks, the heroes that beat them, the matches they played
## with you ("Just played against Bea, 14/2 on Araki, smurf?"), the feeder they met; help questions, looking for a
## duo, tier lists, item questions, jokes. Who answers and how follows their persona and rank: a kind one helps, a
## high-rank show-off sneers ("Mythic here, low mmr problem"), a troll trolls, a joker jokes, a shot caller gives real
## tips from the game's heroes and items. Your threads and replies get answers over the next minute or two (and more
## later); a reply to someone gets that one talking back; your insults and praise change what they think of you, and
## asking for a duo can bring friend requests. Votes go up as people read. Saved in user://forums.json.
## The words come from this offline writer; with Options "Online bot chat" on, ForumWriter asks the language model to
## write the post in the player's voice instead, and this text stays as the fallback.

const PATH := "user://forums.json"
const VERSION := 1
const TAGS := ["Discussion", "Heroes", "Help", "Looking for group", "Match stories", "Funny"]
const THREAD_EVERY := 1500                  # seconds of real time per new thread while you are away
const MAX_NEW := 6                          # new threads at most per visit
const SEED_THREADS := 14
const MAX_THREADS := 120

static var data := {}
static var path := PATH
static var _loaded := false
static var rng := RandomNumberGenerator.new()

# ---- Save and load ------------------------------------------------------------------------------------------------------

static func load_data() -> void:
	if _loaded:
		return
	_loaded = true
	rng.randomize()
	if path == PATH and OS.get_environment("WOA_FORUM_FILE") != "":
		path = OS.get_environment("WOA_FORUM_FILE")
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and int(d.get("version", 0)) == VERSION and d.get("threads") is Array:
			data = d
			_clean()
			return
	data = {"version": VERSION, "last": 0, "threads": [], "next": 1}

static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

static func reset(p := PATH) -> void:
	path = p
	_loaded = false
	data = {}

static func _clean() -> void:
	data["last"] = int(data.get("last", 0))
	data["next"] = int(data.get("next", 1))
	for th in data.threads:
		for k in ["id", "t", "votes", "seen"]:
			th[k] = int(th.get(k, 0))
		if not (th.get("replies") is Array):
			th["replies"] = []
		if not (th.get("pending") is Array):
			th["pending"] = []
		for r in th.replies:
			for k in ["t", "votes", "to"]:
				r[k] = int(r.get(k, -1 if k == "to" else 0))
		for q in th.pending:
			q["at"] = int(q.get("at", 0))
			q["to"] = int(q.get("to", -1))

static func threads() -> Array:
	load_data()
	return data.threads

static func thread(id: int) -> Dictionary:
	for th in threads():
		if int(th.id) == id:
			return th
	return {}

# ---- People -------------------------------------------------------------------------------------------------------------

static func person(id: String) -> Dictionary:
	return Ranked.profile(id)

static func name_of(id: String) -> String:
	return String(person(id).get("name", "someone"))

static func _ps(id: String) -> Dictionary:
	return person(id).get("persona", {})

static func _tr(id: String, k: String) -> float:
	return float(_ps(id).get(k, 0.5))

static func tier_of(id: String) -> int:
	var p := person(id)
	return Ranked.tier_for(p) if not p.is_empty() else 0

static func rank_of(id: String) -> String:
	var p := person(id)
	return Ranked.rank_label(p) if not p.is_empty() else ""

static func _tl(id: String) -> bool:
	return float((person(id).get("voice", {}) as Dictionary).get("tl", 0.2)) >= 0.45

## A ladder player who would post now: online players more often; `pick` filters.
static func _someone(pick := Callable(), avoid: Array = []) -> String:
	var bots: Array = Ranked.bots()
	var t := Ranked.now()
	for attempt in 40:
		var b: Dictionary = bots[rng.randi_range(0, bots.size() - 1)]
		var id := String(b.id)
		if id in avoid:
			continue
		if attempt < 25 and not Persona.online(b, t) and rng.randf() < 0.6:
			continue
		if attempt < 30 and float((b.get("persona", {}) as Dictionary).get("talk", 0.5)) < rng.randf() * 0.6:
			continue
		if pick.is_valid() and attempt < 36 and not bool(pick.call(b)):
			continue
		return id
	return String(bots[rng.randi_range(0, bots.size() - 1)].id)

## How a reply sounds, from who writes it: arrogant (high rank, big ego), troll, kind, helpful, joker, or plain.
static func stance(id: String) -> String:
	var p := person(id)
	var tr := tier_of(id)
	if bool(p.get("rage", false)) or float(p.get("toxic", 0.0)) > 0.78:
		return "troll"
	if tr >= 6 and _tr(id, "ego") > 0.5 and _tr(id, "kind") < 0.75:
		return "arrogant"
	if _tr(id, "kind") > 0.75:
		return "kind"
	if _tr(id, "focus") > 0.65:
		return "helpful"
	if _tr(id, "humor") > 0.75:
		return "joker"
	if float(p.get("toxic", 0.0)) > 0.55:
		return "troll"
	return "plain"

# ---- Words ------------------------------------------------------------------------------------------------------------------

static func _pick(a: Array) -> String:
	return String(a[rng.randi_range(0, a.size() - 1)]) if not a.is_empty() else ""

static func _fill(text: String, f: Dictionary) -> String:
	var s := text
	for k in f:
		s = s.replace("{" + String(k) + "}", str(f[k]))
	return s

## `text` typed the way `id` types (lower case, short forms, their laugh); long posts keep their words.
static func typed(id: String, text: String, short := true) -> String:
	var st: Dictionary = _ps(id).get("style", {})
	if st.is_empty():
		return text
	var s := text
	if short:
		s = ChatStyle.apply(text, st, 0.0, rng, false, 0.08)
	elif bool(st.get("lower", false)):
		s = text.to_lower()
	return s.replace("{laugh}", String(st.get("laugh", "haha")))

static func _hero_facts(hero: String) -> Dictionary:
	var d := SimData.unit(hero)
	var ab: Array = []
	for a in d.get("abilities", []):
		var nm := String(SimData.ability(String(a)).get("name", ""))
		if nm != "":
			ab.append(nm)
	return {"hero": String(d.get("name", hero)), "skill": String(ab[0]) if not ab.is_empty() else "the stun",
		"skill2": String(ab[1]) if ab.size() > 1 else "the second skill", "ult": String(ab[ab.size() - 1]) if not ab.is_empty() else "the ult"}

static func _rand_hero() -> String:
	var pool: Array = GameSettings.random_pool()
	return String(pool[rng.randi_range(0, pool.size() - 1)])

const ITEMS := ["Spell Shield", "Jump Knife", "Kugmo", "Igit", "Atuli", "Mini-Axe", "Fade Cape", "Push Staff", "Vegan Picker",
	"Power Boots", "Magic Wand"]

## Titles and bodies of threads by kind (fields: {hero} {hero2} {hero3} {skill} {skill2} {ult} {item} {rank} {old}
## {next} {n} {role} {country} {you} {kda} {name} {myrank}).
const THREAD := {
	"rank": [["Finally {rank}!", "took me {n} games but i did it. {hero} is so good right now"],
		["{rank} reached, {hero} carried", "no more {old}. next stop {next}"], ["Hit {rank} today", "thanks to my duo. who else is climbing?"],
		["From {old} to {rank}", "played {role} only. it works, just stop feeding"]],
	"rampage": [["Rampage with {hero}!!", "they dove me under my tower and i just pressed {skill}. 5 dead"],
		["First rampage ever", "on {hero}. my hands are still shaking"], ["{hero} rampage, they typed ff", "the {ult} into {skill} combo is unreal"]],
	"top": [["Top 1 {hero} on the ladder", "{n} games on {hero}. ask me anything"], ["I'm the best {hero} on the ladder now", "tips below if anyone wants"]],
	"nerf": [["{hero} is broken", "died to {skill} 4 times today. there is no counter"], ["Nerf {skill} already", "{hero} has damage, escape and a stun. how is that fair"],
		["Every game a {hero}, every game they win", "please do something about {ult}"], ["{hero} players are the worst", "press {skill}, win lane, type ez. every time"]],
	"help": [["How do you play {hero}?", "i keep dying in lane. what do you build and what do you max?"], ["Tips for {role}?", "new to the game, came from another moba. what should i know?"],
		["Stuck in {myrank}, help", "{n} games and still {myrank}. what am i doing wrong"], ["How to last hit better", "i get like 30 last hits in 10 minutes. is that bad?"]],
	"lfg": [["LF duo {myrank}+", "i play {role}, mostly {hero}. evenings {country} time"], ["Looking for a {role} duo", "no flamers pls. trying to reach {next}"],
		["{country} players, add me", "{myrank} {role}. lets climb"]],
	"rant": [["Lost {n} in a row", "every game someone goes 0/10 and blames me"], ["My teammates are bots", "{n} losses. i played fine every game. not my fault"],
		["This matchmaking is a joke", "why is a {old} in my {myrank} game"], ["Done with ranked for today", "3 feeders in one game. how"]],
	"tier": [["Best {role} right now?", "i say {hero}, but people sleep on {hero2}"], ["My tier list after {n} games", "S: {hero}, {hero2}. A: {hero3}. fight me"],
		["Most broken hero right now?", "{hero} for me. {skill} does too much"]],
	"item": [["Is {item} worth it on {hero}?", "or should i go {item2} first?"], ["{item} first or boots?", "on {hero} i mean"],
		["Stop building {item} on {hero}", "seen it 5 times today. it does nothing"]],
	"you_good": [["Just played against {you}", "{kda} on {hero}. {myrank} lobby. smurf?"], ["Anyone know {you}?", "{kda} on {hero} against us. new account?"],
		["{you} is a smurf", "{kda}, MVP. reported. there is no way"]],
	"you_carry": [["{you} carried me today", "+rep, best {hero} i've played with"], ["Shoutout to {you}", "{kda} on {hero}, MVP. add me pls"]],
	"you_bad": [["{you} fed my game", "{kda} on {hero}. how is this guy {rank}"], ["Avoid {you}", "{kda}. then flamed us. reported"]],
	"you_toxic": [["{you} trash talked all game", "typed ez the whole game. lost anyway {laugh}"], ["{you} is so toxic", "ez this, ez that. muted and reported"]],
	"bot_feeder": [["{name} is the worst {hero} i've seen", "0 wards, 12 deaths, still flamed us"], ["Avoid {name}", "fed and blamed everyone"]],
	"bot_rampage": [["{name} rampaged us", "on {hero}. we had no chance"], ["{name} is a monster", "rampage on {hero} in my game today"]],
	"funny": [["my support bought 3 tangos and died at 1 minute", "and then typed 'no support'"], ["Who else plays ranked at 3am", "the 3am games hit different"],
		["typed gg at 5 minutes and we won", "never give up i guess {laugh}"], ["my {hero} hit 0 skillshots and still got MVP", "how"],
		["the enemy {hero} danced on my body", "i'm never recovering from this"]],
}

## Replies by stance and by what they answer (fields as THREAD, plus {author} {arank}).
const REPLY := {
	"agree": ["true", "this", "facts", "100%", "same here", "agree", "korek", "tama", "real"],
	"disagree": ["no", "wrong", "{hero} is fine, learn to play", "hard disagree", "mali", "not really", "nah"],
	"arrogant": ["{myrank} here. this is a low mmr problem", "imagine being {arank}", "skill issue tbh", "at my rank nobody does that",
		"cute", "get to {myrank} then talk", "{arank} thread lol", "this is why ur {arank}"],
	"helpful": ["max {skill} first, then {skill2}", "build boots then {item}", "stay behind your creeps until level 6",
		"watch the minimap every few seconds", "{hero} wants {item}, trust me", "buy wards. seriously", "play safe till {ult} is up"],
	"troll": ["uninstall", "just win", "who asked", "nice story bro", "cool, anyway", "first", "L", "ratio", "ok and?", "cope"],
	"congrats": ["gz!", "congrats", "nice one", "grats", "deserved", "galing!", "big w", "lets gooo"],
	"doubt": ["clip or it didn't happen", "sure", "boosted", "probably got carried", "ok and?", "screenshot?"],
	"kind": ["you got this", "keep going", "dont listen to the haters", "add me, we can duo", "it happens, take a break", "gl on the climb"],
	"joker": ["lmao", "{laugh} same", "this is so real", "i felt this", "bro {laugh}", "this thread {laugh}"],
	"lfg": ["add me, {myrank} {role}", "me! i play {role}", "im from {country}, add me", "{myrank} support here", "add me, no flame"],
	"defend": ["that wasn't me", "my team was trash", "lol cope", "i was lagging", "ok and u lost", "bro i had a bad game"],
	"thanks": ["thanks!", "ty", "appreciate it", "salamat", "thx"],
	"flame_back": ["says the {arank}", "who even are you", "{author} go back to {arank}", "mad?", "imagine flaming on a forum",
		"bold words from a {arank}", "{author} the forum carry, 0 kills in game", "you type like you play, loud and wrong",
		"this is the most damage you've done all week", "you flame better than you farm", "imagine being {arank} and talking like that",
		"screenshotting this for your next loss post", "the keyboard is the only thing you've ever carried",
		"yabang mo sa forum, {arank} ka lang naman", "tapang mo dito, sa laro hindi", "iyak ka pa {author}"],
	# a nice one flamed still answers with a joke at your expense, never "calm down" (the owner, 2026-10-20)
	"roast": ["love you too {author}", "someone lost their last game {laugh}", "noted. now go farm", "that hurt less than your last fight",
		"you ok? need a hug or a ward", "posting this after another loss huh", "so mad its cute", "sending you a tango for that burn",
		"ok {arank} {laugh}", "galit na galit ka ah {laugh}", "ang init ng ulo, {arank} ka naman"],
	"about_you_mate": ["i played with {you} too, legit good", "{you} is my duo lol", "{you} is cool, chill guy"],
	"about_you_foe": ["{you} beat me too", "reported him too", "{you} is just good, cope", "{you} again? he's in every thread"],
	# by what the thread is about
	"rank_arrogant": ["{rank} is still low mmr bro", "cute. {myrank} here", "wake me up when you reach {myrank}", "{rank} lobbies are free wins",
		"{rank}? i was there in my first week", "now try {myrank}, different game"],
	"rank_congrats": ["gz {author}", "{rank}! nice one", "welcome to {rank}", "grats, {hero} is a beast", "big w {author}", "deserved, keep climbing",
		"next stop {next}", "congrats lods, sana all"],
	"rank_doubt": ["{author} boosted by duo", "screenshot or fake", "{arank} and posting this lol", "probably got carried by the support",
		"lets see how long you stay {rank}"],
	"funny_reply": ["i laughed way too hard at this", "this happens to me every game", "{hero} moment", "peak low mmr", "lmaooo",
		"bro i felt this in my soul", "this is why i play solo", "sounds like my last game {laugh}", "the {hero} players are like that"],
	"nerf_agree": ["{skill} is so dumb", "yes nerf {hero} pls", "{hero} has no counter", "every game a {hero}...", "{ult} needs a longer cooldown",
		"died to {skill} 3 times today, agree", "{hero} pickers think they're good lol"],
	"nerf_disagree": ["buy {item}", "just dodge {skill}", "{hero} is fine, you're bad", "skill issue, {hero} dies to everything",
		"{hero} is easy to kill, focus him", "stop walking into {skill}", "learn to play vs {hero} first"],
	"help_tip": ["max {skill} first, then {skill2}", "{ult} wins fights if you wait for them to group", "build boots then {item}",
		"save {skill2} to escape, dont waste it", "stay behind your creeps until 6", "watch the minimap every few seconds",
		"{hero} is all about timing {ult}. watch replays", "practice last hits in Play for 10 minutes a day", "buy wards, seriously"],
	"rant_reply": ["post your profile", "its always the teammates huh", "{n} losses? take a break bro", "mute all and play",
		"same, every game a feeder", "maybe you're the feeder {laugh}", "it gets better, keep going", "same luck here"],
	"top_reply": ["{hero} spammer lol", "how many hours on {hero}?", "teach me {hero}", "gz, {hero} is so hard to play", "top 1 {hero} and still {myrank}?",
		"i've seen you, you're good"],
	"item_reply": ["{item} is trash on {hero}", "{item} rush, trust", "depends, vs magic go Spell Shield", "boots first always", "{item} is fine after boots",
		"never build {item} on {hero}"],
	"tier_reply": ["{hero2} is not even top 5", "{hero} is a noob stomper", "where is {hero3}?", "this list is so wrong", "fair list honestly",
		"{hero} is S tier for sure"],
	"lfg_more": ["im {myrank}, {role}, add me", "{arank}? too low for me lol", "add me, i main {hero}", "my duo quit, add me"],
}

## Which kinds of reply fit a thread kind for a stance (one of them is drawn).
static func _pools(kind: String, st: String) -> Array:
	match kind:
		"rank":
			return {"arrogant": ["rank_arrogant"], "troll": ["rank_doubt", "troll"], "joker": ["joker", "rank_congrats"], "kind": ["rank_congrats"]}.get(st, ["rank_congrats", "rank_congrats", "rank_doubt"])
		"rampage", "you_carry", "bot_rampage":
			return {"arrogant": ["arrogant", "doubt"], "troll": ["doubt", "troll"], "kind": ["congrats"]}.get(st, ["congrats", "doubt", "joker"])
		"top":
			return {"arrogant": ["arrogant", "top_reply"], "troll": ["troll", "doubt"]}.get(st, ["top_reply", "congrats"])
		"nerf":
			return {"arrogant": ["nerf_disagree", "arrogant"], "troll": ["troll", "nerf_disagree"], "helpful": ["nerf_disagree", "help_tip"], "kind": ["nerf_agree", "nerf_disagree"]}.get(st, ["nerf_agree", "nerf_disagree"])
		"help":
			return {"arrogant": ["arrogant", "help_tip"], "troll": ["troll"], "joker": ["joker", "help_tip"]}.get(st, ["help_tip"])
		"lfg":
			return {"arrogant": ["lfg_more", "arrogant"], "troll": ["troll"]}.get(st, ["lfg", "lfg_more"])
		"rant":
			return {"arrogant": ["arrogant", "rant_reply"], "troll": ["troll", "rant_reply"], "kind": ["kind"]}.get(st, ["rant_reply", "kind"])
		"tier":
			return {"troll": ["troll", "tier_reply"], "arrogant": ["arrogant", "tier_reply"]}.get(st, ["tier_reply", "agree", "disagree"])
		"item":
			return {"troll": ["troll"], "arrogant": ["arrogant", "item_reply"], "helpful": ["item_reply", "help_tip"]}.get(st, ["item_reply"])
		"funny":
			return {"troll": ["troll", "funny_reply"]}.get(st, ["funny_reply", "joker"])
		"you_good", "you_bad", "you_toxic", "bot_feeder":
			return {"troll": ["troll", "doubt"], "kind": ["kind", "agree"], "arrogant": ["arrogant"]}.get(st, ["agree", "joker", "disagree"])
	return {"arrogant": ["arrogant"], "troll": ["troll"], "joker": ["joker"], "kind": ["kind", "agree"], "helpful": ["agree", "help_tip"]}.get(st, ["agree", "disagree"])

# ---- Making threads ---------------------------------------------------------------------------------------------------------

## New posts and replies for the time since the last visit (and the first threads on a new forum).
static func catch_up() -> int:
	load_data()
	Ranked.load_data()
	var t := Ranked.now()
	var made := 0
	if (data.threads as Array).is_empty():
		for i in SEED_THREADS:
			if _new_thread(t - int(float(SEED_THREADS - i) / SEED_THREADS * 36.0 * 3600.0) - rng.randi_range(0, 900)) != {}:
				made += 1
		for th in data.threads:
			_grow(th, t, true)
		data.last = t
	else:
		var n := mini(MAX_NEW, (t - int(data.last)) / THREAD_EVERY)
		for i in n:
			if _new_thread(t - rng.randi_range(0, maxi(60, t - int(data.last)))) != {}:
				made += 1
		if n > 0 or t - int(data.last) > 300:
			for th in data.threads:
				_grow(th, t, false)
			data.last = t
	answer_ignored(t)
	resolve(t)
	(data.threads as Array).sort_custom(func(a, b): return int(a.t) > int(b.t))
	while (data.threads as Array).size() > MAX_THREADS:
		(data.threads as Array).pop_back()
	save()
	return made

## One thread from what is going on: picks a kind that has the facts it needs.
static func _new_thread(at: int) -> Dictionary:
	var kinds := [["rank", 3], ["rampage", 2], ["top", 1], ["nerf", 3], ["help", 3], ["lfg", 2], ["rant", 2], ["tier", 2], ["item", 2],
		["you", 3], ["bot", 2], ["funny", 2]]
	var total := 0
	for k in kinds:
		total += int(k[1])
	for attempt in 8:
		var roll := rng.randi_range(1, total)
		var kind := ""
		for k in kinds:
			roll -= int(k[1])
			if roll <= 0:
				kind = String(k[0])
				break
		var th := _make(kind, at)
		if not th.is_empty():
			(data.threads as Array).append(th)
			return th
	return {}

static func _make(kind: String, at: int) -> Dictionary:
	var f := {}
	var author := ""
	var about := ""
	var key := kind
	var tag := "Discussion"
	match kind:
		"rank":
			var e := _feed_of("rank")
			if e.is_empty():
				return {}
			author = String(e.id)
			var tr := int(e.a)
			f = {"rank": Ranked.tier_name(tr), "old": Ranked.tier_name(maxi(0, tr - 1)), "next": Ranked.tier_name(mini(10, tr + 1))}
			tag = "Discussion"
		"rampage":
			var e2 := _feed_of("rampage")
			author = String(e2.get("id", ""))
			if author == "":
				author = _someone(func(b): return int(b.roles[0]) <= 3)
			f = _hero_facts(String(e2.get("a", (person(author).get("heroes", ["sludge"]) as Array)[0])))
			tag = "Match stories"
		"top":
			var e3 := _feed_of("top")
			if e3.is_empty():
				return {}
			author = String(e3.id)
			f = _hero_facts(String(e3.a))
			tag = "Heroes"
		"nerf":
			author = _someone(func(b): return float(b.get("mood", 0.0)) < 0.1 or float(b.get("toxic", 0.0)) > 0.4)
			f = _hero_facts(_rand_hero())
			tag = "Heroes"
		"help":
			author = _someone(func(b): return Ranked.tier_for(b) <= 4)
			f = _hero_facts(_rand_hero())
			tag = "Help"
		"lfg":
			author = _someone()
			f = _hero_facts(String((person(author).get("heroes", ["sludge"]) as Array)[0]))
			tag = "Looking for group"
		"rant":
			author = _someone(func(b): return int(b.get("streak", 0)) <= -3 or float(b.get("mood", 0.0)) < -0.3)
			f = {"n": maxi(3, -int(person(author).get("streak", -3)))}
			tag = "Discussion"
		"tier":
			author = _someone(func(b): return Ranked.tier_for(b) >= 3)
			f = _hero_facts(_rand_hero())
			f["hero2"] = HeroDraft.hero_name(_rand_hero())
			f["hero3"] = HeroDraft.hero_name(_rand_hero())
			tag = "Heroes"
		"item":
			author = _someone()
			f = _hero_facts(_rand_hero())
			f["item2"] = _pick(ITEMS)
			tag = "Discussion"
		"you":
			var m := _met_you()
			if m.is_empty():
				return {}
			author = String(m.id)
			f = m.f
			key = String(m.key)
			tag = "Match stories"
		"bot":
			var bb := _bot_story()
			if bb.is_empty():
				return {}
			author = String(bb.author)
			f = bb.f
			key = String(bb.key)
			about = String(bb.about)
			tag = "Match stories"
		"funny":
			author = _someone(func(b): return float((b.get("persona", {}) as Dictionary).get("humor", 0.0)) > 0.5)
			f = _hero_facts(_rand_hero())
			f["name"] = name_of(_someone())
			tag = "Funny"
	if author == "" or person(author).is_empty():
		return {}
	_common(f, author)
	var opts: Array = THREAD.get(key, [])
	if opts.is_empty():
		return {}
	var tb: Array = opts[rng.randi_range(0, opts.size() - 1)]
	var title := _fill(String(tb[0]), f)
	var body := _fill(String(tb[1]), f)
	if title.contains("{") or body.contains("{"):
		return {}
	for o in (data.threads as Array).slice(maxi(0, (data.threads as Array).size() - 30)):
		if String(o.get("t0", "")) == String(tb[0]) and String(o.get("kind", "")) == key:
			return {}
	var id := int(data.next)
	data.next = id + 1
	return {"id": id, "a": author, "title": typed(author, title, false), "body": typed(author, body, false), "tag": tag, "t": at,
		"votes": rng.randi_range(0, 4), "voted": false, "replies": [], "pending": [], "kind": key, "f": f, "seen": 0, "about": about,
		"t0": String(tb[0])}

static func _common(f: Dictionary, author: String) -> void:
	var p := person(author)
	if not f.has("hero"):
		f.merge(_hero_facts(String((p.get("heroes", ["sludge"]) as Array)[0])))
	f["myrank"] = Ranked.tier_name(tier_of(author))
	f["role"] = RankedNum.role(int((p.get("roles", [1]) as Array)[0])).to_lower()
	f["country"] = Ranked.country_name(String(p.get("country", "PH")))
	if not f.has("n"):
		f["n"] = rng.randi_range(40, 400)
	if not f.has("item"):
		f["item"] = _pick(ITEMS)
	if not f.has("next"):
		f["next"] = Ranked.tier_name(mini(10, tier_of(author) + 1))
	if not f.has("old"):
		f["old"] = Ranked.tier_name(maxi(0, tier_of(author) - 2))
	f["you"] = String(Ranked.me().get("name", "Player"))

static func _feed_of(k: String) -> Dictionary:
	var feed: Array = Ranked.data.get("feed", [])
	var hits: Array = feed.filter(func(e): return String(e.get("k", "")) == k)
	return hits[rng.randi_range(0, mini(hits.size() - 1, 12))] if not hits.is_empty() else {}

## A ladder player who met you lately and has something to say about it (good, carried, fed, toxic).
static func _met_you() -> Dictionary:
	var met := Ranked.recent_players(12)
	if met.is_empty():
		return {}
	for attempt in 6:
		var e: Array = met[rng.randi_range(0, met.size() - 1)]
		var p: Dictionary = e[0]
		var y: Dictionary = p.get("you", {})
		var kda := String(y.get("last_you_kda", ""))
		var parts := kda.split("/")
		if parts.size() < 3:
			continue
		var k := int(parts[0])
		var x := int(parts[1])
		var a := int(parts[2])
		var f := _hero_facts(String(y.get("your_hero", "sludge")))
		f["kda"] = kda
		f["rank"] = Ranked.rank_label(Ranked.me())
		var key := ""
		if int(y.get("trash_talked", 0)) >= 2 and rng.randf() < 0.7:
			key = "you_toxic"
		elif (float(k) + a * 0.5) / maxf(1.0, x) >= 3.0 and k >= 6:
			key = "you_carry" if String(y.get("last_side", "")) == "with" else "you_good"
		elif x >= 8 and x >= k + a:
			key = "you_bad"
		if key != "":
			return {"id": String(p.id), "f": f, "key": key}
	return {}

## A ladder player tells about another it met (Ranked "seen": the feeder, the rampage).
static func _bot_story() -> Dictionary:
	var bots: Array = Ranked.bots()
	for attempt in 30:
		var b: Dictionary = bots[rng.randi_range(0, bots.size() - 1)]
		var seen: Dictionary = b.get("seen", {})
		for oid in seen:
			var note := String((seen[oid] as Dictionary).get("note", ""))
			if note in ["feeder", "rampage"]:
				var o := person(String(oid))
				var f := _hero_facts(String((o.get("heroes", ["sludge"]) as Array)[0]))
				f["name"] = String(o.get("name", ""))
				return {"author": String(b.id), "f": f, "key": "bot_" + note, "about": String(oid)}
	return {}

## Replies to a thread for the time it has been up (an older thread slows down).
static func _grow(th: Dictionary, t: int, first: bool) -> void:
	var age := float(t - int(th.t)) / 3600.0
	var want := int(clampf(2.0 + sqrt(maxf(age, 0.0)) * 2.2 + float(int(th.id) % 3), 1.0, 14.0))
	if String(th.a) == "me":
		want += 2
	var have := (th.replies as Array).size()
	var n := mini(want - have, 3 if not first else 8)
	for i in n:
		var at := int(th.t) + int(float(t - int(th.t)) * float(have + i + 1) / float(want + 1))
		var r := _reply_for(th, at)
		if not r.is_empty():
			(th.replies as Array).append(r)
	th.votes = int(th.votes) + rng.randi_range(0, 2 + n)

## A reply to `th` (or to its reply `to`) from someone who fits.
static func _reply_for(th: Dictionary, at: int, to := -1, by := "") -> Dictionary:
	var used: Array = [String(th.a)]
	for r in th.replies:
		used.append(String(r.a))
	var author := by if by != "" else _someone(Callable(), used if rng.randf() < 0.8 else [String(th.a)])
	if author == "" or person(author).is_empty():
		return {}
	var text := _reply_text(th, author, to)
	if text == "":
		return {}
	return {"a": author, "text": typed(author, text), "t": at, "votes": rng.randi_range(0, 3), "voted": false, "to": to}

## What `author` says in `th` (to its reply `to`, or to the thread).
static func _reply_text(th: Dictionary, author: String, to := -1) -> String:
	var f: Dictionary = (th.get("f", {}) as Dictionary).duplicate()
	_common(f, author)
	var target := String(th.a) if to < 0 or to >= (th.replies as Array).size() else String(th.replies[to].a)
	f["author"] = name_of(target) if target != "me" else String(Ranked.me().get("name", "Player"))
	f["arank"] = Ranked.tier_name(tier_of(target)) if target != "me" else Ranked.tier_name(Ranked.tier_for(Ranked.me()))
	var st := stance(author)
	var kind := String(th.get("kind", ""))
	var pool := "agree"
	# a thread about this author: it defends itself
	if String(th.get("about", "")) == author:
		pool = "defend"
	elif kind in ["you_good", "you_carry", "you_bad", "you_toxic"] and (person(author).get("you", {}) as Dictionary).has("games") and rng.randf() < 0.5:
		pool = "about_you_mate" if String((person(author).get("you", {}) as Dictionary).get("last_side", "")) == "with" else "about_you_foe"
	else:
		var ps: Array = _pools(kind, st)
		pool = String(ps[rng.randi_range(0, ps.size() - 1)])
	# people reading a thread of yours look you up too
	if String(th.a) == "me" and target == "me" and pool != "defend" and rng.randf() < 0.3:
		var pl := ProfileTalk.raw_about(person(author), Ranked.me(), rng)
		if pl != "":
			return ("@%s " % f.author if to >= 0 else "") + pl
	# no line twice in a thread
	var said := {}
	for r in th.replies:
		said[String(r.text).to_lower()] = true
	var text := ""
	for attempt in 6:
		text = _fill(_pick(REPLY.get(pool, REPLY.agree)), f)
		if text.contains("{") and not text.contains("{laugh}"):
			continue
		if not said.has(typed(author, text).to_lower()) and not said.has(text.to_lower()):
			break
	if text.contains("{") and not text.contains("{laugh}"):
		text = _fill(_pick(REPLY.agree), f)
	# a reply to someone names them now and then
	if to >= 0 and rng.randf() < 0.5:
		text = "@%s %s" % [f.author, text]
	return text

# ---- Your posts --------------------------------------------------------------------------------------------------------------

## You post a thread: it goes up, and replies come in over the next minutes (resolve() shows them when due).
static func post(title: String, body: String, tag: String) -> Dictionary:
	load_data()
	var t := Ranked.now()
	var id := int(data.next)
	data.next = id + 1
	var kind := _kind_of(title + " " + body)
	var th := {"id": id, "a": "me", "title": title.strip_edges().substr(0, 90), "body": body.strip_edges().substr(0, 800),
		"tag": tag if tag in TAGS else "Discussion", "t": t, "votes": 1, "voted": true, "replies": [], "pending": [], "kind": kind,
		"f": _facts_in(title + " " + body), "seen": t}
	(data.threads as Array).push_front(th)
	var n := rng.randi_range(4, 7)
	var at := t + rng.randi_range(6, 14)
	var used: Array = []
	for i in n:
		var who := _answerer(th, used)
		used.append(who)
		(th.pending as Array).append({"a": who, "at": at, "to": -1})
		at += rng.randi_range(8, 30)
	_my_words(th.body if String(th.body) != "" else th.title, "")
	save()
	return th

## You reply in a thread (to its reply `to`, or to the thread): you are always answered (the owner, 2026-10-20: "even in
## the forums they dont reply to the player and they just ignore"). The one you answered talks back every time (in
## your own thread, a reply without a target is for whoever you named, else the last one who wrote); someone else
## joins in, and trash talk draws a second one.
static func reply(th: Dictionary, text: String, to := -1) -> void:
	var t := Ranked.now()
	if to >= (th.replies as Array).size():
		to = -1
	var r := {"a": "me", "text": text.strip_edges().substr(0, 500), "t": t, "votes": 1, "voted": true, "to": to}
	var target := target_of(th, text, to)
	(th.replies as Array).append(r)
	var my_i := (th.replies as Array).size() - 1
	var used: Array = ["me"]
	if target != "" and target != "me" and not person(target).is_empty():
		(th.pending as Array).append({"a": target, "at": t + rng.randi_range(5, 14), "to": my_i})
		used.append(target)
	var rude := ChatMind.intent(" " + text.to_lower() + " ") in ["insult", "taunt"]
	var more := 1 if used.size() == 1 or rude or rng.randf() < 0.6 else 0
	if rude and rng.randf() < 0.6:
		more += 1
	var at := t + rng.randi_range(12, 30)
	for i in more:
		var who := _joiner(th, used)
		if who == "":
			break
		used.append(who)
		(th.pending as Array).append({"a": who, "at": at, "to": my_i})
		at += rng.randi_range(8, 25)
	_my_words(text, target)
	save()

## Whom your reply in `th` is for: the reply you answered (`to`), else someone in the thread you named ("@bea", "bea"),
## else the thread's writer, or in your own thread the last one who wrote.
static func target_of(th: Dictionary, text: String, to := -1) -> String:
	var rs: Array = th.replies
	if to >= 0 and to < rs.size():
		return String(rs[to].a)
	var low := " " + text.to_lower() + " "
	var seen: Array = [String(th.a)]
	for x in rs:
		if not (String(x.a) in seen):
			seen.append(String(x.a))
	for id in seen:
		if id == "me":
			continue
		var nm := name_of(id).to_lower()
		if nm.length() >= 3 and (low.contains("@" + nm) or low.contains(" " + nm + " ") or low.contains(" " + nm + ",")
				or low.contains(" " + nm + "?") or low.contains(" " + nm + "!")):
			return id
	if String(th.a) != "me":
		return String(th.a)
	for i in range(rs.size() - 1, -1, -1):
		if String(rs[i].a) != "me":
			return String(rs[i].a)
	return ""

## Your replies of the last three days that nobody answered (forums saved before run 2026-10-20 left some): the one
## each was for answers it now. Returns how many were queued.
static func answer_ignored(t := 0) -> int:
	if t == 0:
		t = Ranked.now()
	var n := 0
	for th in threads():
		var rs: Array = th.replies
		for i in rs.size():
			var r: Dictionary = rs[i]
			if String(r.a) != "me" or t - int(r.t) > 3 * 86400:
				continue
			var answered := rs.any(func(x): return int(x.get("to", -1)) == i and String(x.a) != "me") \
				or (th.pending as Array).any(func(q): return int(q.to) == i)
			if answered:
				continue
			var who := target_of({"a": th.a, "replies": rs.slice(0, i)}, String(r.text), int(r.get("to", -1)))
			if who == "" or who == "me" or person(who).is_empty():
				who = _joiner(th, ["me"])
			if who == "":
				continue
			(th.pending as Array).append({"a": who, "at": t + rng.randi_range(4, 12) + n * 6, "to": i})
			n += 1
	if n > 0:
		save()
	return n

## Someone who joins in after your reply: often one already in the thread, else anyone likely to answer you.
static func _joiner(th: Dictionary, used: Array) -> String:
	var inside: Array = []
	for x in th.replies:
		var id := String(x.a)
		if id != "me" and not (id in used) and not (id in inside) and not person(id).is_empty():
			inside.append(id)
	if String(th.a) != "me" and not (String(th.a) in used) and not (String(th.a) in inside):
		inside.append(String(th.a))
	if not inside.is_empty() and rng.randf() < 0.6:
		return String(inside[rng.randi_range(0, inside.size() - 1)])
	return _answerer(th, used)

## Someone likely to answer a thread of yours: anyone, a little more often those who know you.
static func _answerer(th: Dictionary, used: Array) -> String:
	var met: Array = Ranked.recent_players(15).map(func(e): return String(e[0].id))
	if not met.is_empty() and rng.randf() < 0.3:
		var id := String(met[rng.randi_range(0, met.size() - 1)])
		if not (id in used):
			return id
	return _someone(Callable(), used)

## What a post of yours is about: a question, a brag, looking for a duo, a rant, trash talk, a hero.
static func _kind_of(text: String) -> String:
	var s := " " + text.to_lower() + " "
	if ChatMind.intent(s) in ["insult", "taunt"]:
		return "my_trash"
	for w in ["duo", " lf ", "looking for", "add me", "party", "team up", "friends"]:
		if s.contains(w):
			return "lfg"
	for w in ["rampage", "mvp", "top 1", "reached", "finally", "carried", "won ", "win streak", "ultra kill"]:
		if s.contains(w):
			return "my_brag"
	for w in ["lost", "lose", "losing", "feeder", "teammates", "matchmaking", "tilted", "hate"]:
		if s.contains(w):
			return "rant"
	if s.contains("?") or s.contains(" how ") or s.contains(" what ") or s.contains(" tips") or s.contains(" best ") or s.contains(" should "):
		return "help"
	return "discussion"

static func _facts_in(text: String) -> Dictionary:
	var low := text.to_lower()
	for h in GameSettings.random_pool():
		if low.contains(HeroDraft.hero_name(String(h)).to_lower()):
			return _hero_facts(String(h))
	return _hero_facts(_rand_hero())

## Your words reach the ones you answered: insults make them like you less (and remember you as a trash talker),
## praise more.
static func _my_words(text: String, target: String) -> void:
	var it := ChatMind.intent(" " + text.to_lower() + " ")
	if target == "" or target == "me":
		return
	var p := person(target)
	if p.is_empty():
		return
	var y: Dictionary = p.get("you", {})
	if it in ["insult", "taunt"]:
		y["rep"] = snappedf(clampf(float(y.get("rep", 0.0)) - 0.15, -1.0, 1.0), 0.01)
		y["trash_talked"] = int(y.get("trash_talked", 0)) + 1
	elif it in ["praise", "thanks"]:
		y["rep"] = snappedf(clampf(float(y.get("rep", 0.0)) + 0.1, -1.0, 1.0), 0.01)
	p["you"] = y
	Ranked.save()

## Replies that are due by now go up (text from ForumWriter if it came back, else this writer's).
static func resolve(t := 0) -> int:
	if t == 0:
		t = Ranked.now()
	var n := 0
	for th in threads():
		var keep: Array = []
		for q in th.pending:
			if int(q.at) > t or (bool(q.get("asked", false)) and not q.has("text") and t - int(q.at) < 9):
				keep.append(q)
				continue
			var text := String(q.get("text", ""))
			if text == "":
				text = answer_text(th, String(q.a), int(q.to))
			if text != "":
				(th.replies as Array).append({"a": String(q.a), "text": text, "t": int(q.at), "votes": rng.randi_range(0, 2), "voted": false,
					"to": int(q.to)})
				n += 1
				_after_answer(th, String(q.a), text)
		th.pending = keep
	if n > 0:
		save()
	return n

## A reply to you (your thread, or your reply `to`), from the facts of what you wrote and who answers.
static func answer_text(th: Dictionary, author: String, to: int) -> String:
	var mine_text := String(th.body) + " " + String(th.title)
	if to >= 0 and to < (th.replies as Array).size():
		mine_text = String(th.replies[to].text)
	var it := ChatMind.intent(" " + mine_text.to_lower() + " ")
	var kind := _kind_of(mine_text) if to >= 0 else String(th.kind)
	var f: Dictionary = (th.get("f", {}) as Dictionary).duplicate()
	_common(f, author)
	f["author"] = String(Ranked.me().get("name", "Player"))
	f["arank"] = Ranked.tier_name(Ranked.tier_for(Ranked.me()))
	var y: Dictionary = person(author).get("you", {})
	var rep := float(y.get("rep", 0.0))
	var st := stance(author)
	var pool := "agree"
	if it in ["insult", "taunt"] or kind == "my_trash":
		# trash talk is always answered in kind (the owner, 2026-10-20: "talk back to the player if he trash talks")
		pool = "roast" if st == "kind" or rng.randf() < 0.3 else "flame_back"
	elif it in ["praise", "thanks"]:
		pool = "thanks"
	else:
		match kind:
			"help":
				pool = {"arrogant": "arrogant", "troll": "troll", "joker": "joker"}.get(st, "helpful")
			"lfg":
				pool = "troll" if st == "troll" else ("arrogant" if st == "arrogant" and tier_of(author) > Ranked.tier_for(Ranked.me()) + 1 else "lfg")
			"my_brag":
				pool = {"arrogant": "arrogant", "troll": "doubt", "kind": "congrats", "joker": "joker"}.get(st, "congrats" if rng.randf() < 0.6 else "doubt")
			"rant":
				pool = {"arrogant": "arrogant", "troll": "troll", "kind": "kind", "joker": "joker"}.get(st, "kind" if rng.randf() < 0.5 else "joker")
			_:
				pool = {"arrogant": "arrogant", "troll": "troll", "joker": "joker", "helpful": "agree"}.get(st, "agree" if rng.randf() < 0.6 else "disagree")
	# what they think of you colours it
	var text := _fill(_pick(REPLY.get(pool, REPLY.agree)), f)
	if text.contains("{") and not text.contains("{laugh}"):
		text = _fill(_pick(REPLY.agree), f)
	# they look you up first (run 2026-10-20: averages are everything here): trash talk, brags, help and rants most of all
	var look := 0.6 if (it in ["insult", "taunt"] or kind in ["my_trash", "my_brag", "help", "rant"]) else 0.3
	if rng.randf() < look:
		var pl := ProfileTalk.raw_about(person(author), Ranked.me(), rng)
		if pl != "":
			text = pl if rng.randf() < 0.45 else text + " " + _pick(["also ", "btw ", "and ", "checked ur profile, ", "saw ur profile: "]) + pl
	var you := String(Ranked.me().get("name", "Player"))
	if rep > 0.45 and rng.randf() < 0.5:
		text = _pick([you + "! ", "yo " + you + ", ", "my duo " + you + " "]) + text
	elif rep < -0.4 and rng.randf() < 0.6:
		text = _pick(["oh its " + you + " again. ", you + " the flamer lol. ", "not u again " + you + ". "]) + text
	if to >= 0:
		text = "@%s %s" % [you, text]
	return typed(author, text)

## After a reply to you: someone answering "add me" to your duo post sends you a friend request.
static func _after_answer(th: Dictionary, author: String, text: String) -> void:
	if String(th.a) == "me" and String(th.kind) == "lfg" and text.to_lower().contains("add me") and rng.randf() < 0.75:
		Ranked.send_request(author, "forum")

# ---- Votes ----------------------------------------------------------------------------------------------------------------

static func vote_thread(th: Dictionary) -> void:
	th.voted = not bool(th.voted)
	th.votes = int(th.votes) + (1 if bool(th.voted) else -1)
	save()

static func vote_reply(r: Dictionary) -> void:
	r.voted = not bool(r.voted)
	r.votes = int(r.votes) + (1 if bool(r.voted) else -1)
	save()

## Threads in a list: "hot" (votes and replies, fading with age) or "new"; `tag` "" for all.
static func listed(sort := "hot", tag := "") -> Array:
	var t := Ranked.now()
	var out: Array = threads().filter(func(th): return tag == "" or String(th.tag) == tag)
	if sort == "new":
		out.sort_custom(func(a, b): return int(a.t) > int(b.t))
	else:
		var score := func(th) -> float:
			return (float(th.votes) + 1.5 * float((th.replies as Array).size()) + (8.0 if String(th.a) == "me" else 0.0)) / pow(float(t - int(th.t)) / 3600.0 + 2.0, 1.3)
		out.sort_custom(func(a, b): return float(score.call(a)) > float(score.call(b)))
	return out

## Players typing in a thread now: pending replies due within the next 20 s.
static func typing(th: Dictionary) -> Array:
	var t := Ranked.now()
	return (th.pending as Array).filter(func(q): return int(q.at) - t <= 20).map(func(q): return name_of(String(q.a)))
