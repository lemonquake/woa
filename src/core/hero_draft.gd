class_name HeroDraft
extends RefCounted
## The hero pick of a ranked match (run 2026-10-19 b; the owner: nobody picks a hero before matchmaking; each player gets
## a random numbered turn to pick; bots say in team chat which hero they want and pick it unless someone takes it
## first, then change their mind).
##   * The ten players pick one at a time in a random order (turn 1..10); no hero twice in a match.
##   * Each bot wants a hero when the pick starts: its favourite that plays its role and that no teammate already
##     called, else any free hero for its role (a low, selfish bot may want anything, even what a teammate called).
##     Your teammates say it in team chat, one after another.
##   * When someone takes the hero a bot wanted, it wants another and says so ("nvm, Kragg na lang ako"); if it was you
##     who took it, it answers you (politely or not, by its manners).
##   * A bot picks after 1-4 s of its turn; you have 30 s (then a hero is picked for you: one for your role).
##   * Your heroes with a Gold medal or better (Ranked.hero_medal) are left to you by your team: they say so ("Bea is
##     Diamond Azrael, let them have it"), hurry you when an enemy is picking before you, and cheer or groan when an enemy
##     takes it. A strong enemy (2500+) may take your Platinum or better hero first, to deny it.
## The screen calls step(dt), pick("me", hero) and reads order, turn, picks, chat (new lines are appended).

const KITS = preload("res://src/sim/sim_bot_kits.gd")
const YOUR_TIME := 30.0

var lineup := {}
var order: Array = []                      # profile ids in pick order (the pick numbers are index + 1)
var turn := 0                              # index in order of who picks now (10: done)
var t := 0.0                               # seconds into this turn
var picks := {}                            # id -> hero
var wants := {}                            # bot id -> hero it wants now
var chat: Array = []                       # [{id, name, text, team}] your team's chat, in order
var rng := RandomNumberGenerator.new()
var _delay := {}                           # bot id -> seconds into its turn before it picks
var _said_want := {}                       # bot ids that announced their hero
var _announce_t := 0.0
var _profiles := {}                        # id -> profile
var best: Array = []                       # your heroes with Gold or better: [[hero, medal info]], best first
var _later: Array = []                     # [seconds, id, text] lines your team says a little later
var _clock := 0.0
var _hurried := 0
var _last_turn := -1
var _team := {}                            # id -> team index

func _init(l: Dictionary = {}, seed := 0) -> void:
	if l.is_empty():
		return
	lineup = l
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	for side in 2:
		for p in l.teams[side]:
			_profiles[String(p.id)] = p
			_team[String(p.id)] = side
			order.append(String(p.id))
	# a random order: everyone gets a numbered turn
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var x = order[i]
		order[i] = order[j]
		order[j] = x
	best = Ranked.top_heroes(Ranked.me(), 3) if _profiles.has("me") else []
	var yours := {}
	for b in best:
		yours[String(b[0])] = true
	for side in 2:
		var called := {}
		if side == mine():
			called = yours.duplicate()            # your team leaves your best heroes to you
		for p in l.teams[side]:
			var id := String(p.id)
			if id == "me":
				continue
			var h := _choose(id, called)
			# a strong enemy may go for your Platinum or better hero, to deny it
			if side != mine() and not best.is_empty() and int(best[0][1].medal) >= 4 and int(p.get("skill", 0)) >= 2500 					and rng.randf() < 0.35 and not wants.values().has(String(best[0][0])):
				h = String(best[0][0])
			wants[id] = h
			called[h] = true
	_react_to_best()
	_react_to_mvp()
	_react_to_profiles()
	for id in order:
		_delay[id] = rng.randf_range(1.2, 3.6) + (1.5 if float(_profiles[id].get("toxic", 0.0)) > 0.7 else 0.0)

## Your teammates notice your best hero (Gold and up) when the pick starts.
func _react_to_best() -> void:
	if best.is_empty():
		return
	var h := String(best[0][0])
	var m: Dictionary = best[0][1]
	var hn := hero_name(h)
	var you := String(Ranked.me().get("name", "you"))
	var mates: Array = []
	for id in order:
		if id != "me" and team_of(id) == mine():
			mates.append(id)
	var n := 1 if int(m.medal) <= 3 else (2 if int(m.top) == 0 else 3)
	var lines: Array
	if int(m.top) > 0:
		lines = ["%s is Top %d %s?! pick it pls" % [you, int(m.top), hn], "omg top %d %s player on our team" % [int(m.top), hn],
			"we have a Top %d %s, gg ez" % [int(m.top), hn], "everyone leave %s to %s" % [hn, you]]
	elif int(m.medal) >= 5:
		lines = ["wait, %s is Diamond %s" % [you, hn], "Diamond %s on our team, ez" % hn, "%s pick %s, you're Diamond" % [you, hn],
			"nobody take %s, that's %s's hero" % [hn, you]]
	elif int(m.medal) == 4:
		lines = ["%s is Platinum %s, let them have it" % [you, hn], "%s pick your %s" % [you, hn], "%s for %s pls" % [hn, you]]
	else:
		lines = ["%s has Gold %s, leave it to them" % [you, hn], "%s play your %s" % [you, hn]]
	var t := 1.4
	for i in mini(n, mates.size()):
		var id: String = mates[rng.randi_range(0, mates.size() - 1)]
		_later.append([t, id, String(lines[rng.randi_range(0, lines.size() - 1)])])
		t += rng.randf_range(1.0, 2.2)

func _best_free() -> String:
	if best.is_empty() or picks.has("me"):
		return ""
	var h := String(best[0][0])
	return "" if taken(h) else h

func mine() -> int:
	return int(lineup.get("mine", 0))

func team_of(id: String) -> int:
	return int(_team.get(id, 0))

func profile(id: String) -> Dictionary:
	return _profiles.get(id, {})

func role_of(id: String) -> int:
	return int(lineup.roles.get(id, 0))

func current() -> String:
	return String(order[turn]) if turn < order.size() else ""

func done() -> bool:
	return turn >= order.size()

func number_of(id: String) -> int:
	return order.find(id) + 1

func taken(hero: String) -> bool:
	return picks.values().has(hero)

func pool() -> Array:
	return GameSettings.random_pool()

func time_left() -> float:
	return maxf(0.0, YOUR_TIME - t) if current() == "me" else 0.0

## The hero a bot wants: its favourite for its role nobody took or (on its team) called, else any such hero; a low,
## selfish bot sometimes wants any hero at all.
func _choose(id: String, called: Dictionary) -> String:
	var p := profile(id)
	var role := role_of(id)
	var free := func(h: String) -> bool: return not taken(h) and not called.has(h) and (h != mine_wants or team_of(id) != mine())
	var wild := int(p.get("skill", 3000)) < 1500 and rng.randf() < (1.0 - float(p.get("coop", 1.0))) * 0.5
	if wild:
		var any: Array = pool().filter(func(h): return not taken(String(h)))
		if not any.is_empty():
			return String(any[rng.randi_range(0, any.size() - 1)])
	for h in p.get("heroes", []):
		if free.call(String(h)) and role in KITS.roles(String(h)).slice(0, 3):
			return String(h)
	var fits: Array = pool().filter(func(h): return free.call(String(h)) and role in KITS.roles(String(h)).slice(0, 3))
	if not fits.is_empty():
		return String(fits[rng.randi_range(0, fits.size() - 1)])
	var rest: Array = pool().filter(func(h): return not taken(String(h)))
	return String(rest[rng.randi_range(0, rest.size() - 1)]) if not rest.is_empty() else String(pool()[0])

static func hero_name(h: String) -> String:
	return String(SimData.unit(h).get("name", h))

func _say(id: String, text: String) -> void:
	if team_of(id) != mine():
		return                                 # the other team's chat is theirs
	# typed the way this player types (Persona style: lower case, short forms, their laugh, their pet word)
	var style: Dictionary = (profile(id).get("persona", {}) as Dictionary).get("style", {})
	var typed := ChatStyle.apply(text, style, 0.0, rng, false, 0.05) if id != "me" else text
	chat.append({"id": id, "name": String(profile(id).get("name", "")), "text": typed, "team": team_of(id), "me": id == "me"})

func _pick_line(lines: Array) -> String:
	return String(lines[rng.randi_range(0, lines.size() - 1)])

## Your team's bots say which hero they want, one about every second, from the start.
func _announce(dt: float) -> void:
	_announce_t += dt
	if _announce_t < 0.9:
		return
	for id in order:
		if id == "me" or team_of(id) != mine() or _said_want.has(id) or picks.has(id):
			continue
		_announce_t = 0.0
		_said_want[id] = true
		var h := hero_name(String(wants[id]))
		var role := RankedNum.role(role_of(id))
		var tl := float((profile(id).get("voice", {}) as Dictionary).get("tl", 0.3)) > 0.4
		if tl:
			_say(id, _pick_line(["%s ako" % h, "pa-%s ako" % h, "akin si %s" % h, "%s ako, %s" % [h, role.to_lower()],
				"%s please" % h]))
		else:
			_say(id, _pick_line(["I want %s" % h, "%s for me" % h, "can I get %s?" % h, "I'll go %s %s" % [h, role.to_lower()],
				"%s or I feed" % h if float(profile(id).get("toxic", 0.0)) > 0.7 else "%s please" % h]))
		return

## `who` took `hero`: every bot that wanted it wants another, and your teammates say so.
func _taken_from(who: String, hero: String) -> void:
	for id in wants.keys():
		if id == who or picks.has(id) or String(wants[id]) != hero:
			continue
		var called := {}
		for o in wants:
			if o != id and team_of(String(o)) == team_of(id) and not picks.has(o):
				called[String(wants[o])] = true
		var next := _choose(id, called)
		wants[id] = next
		if not _said_want.has(id):
			continue                           # it never said it wanted that one
		var a := hero_name(hero)
		var b := hero_name(next)
		var toxic := float(profile(id).get("toxic", 0.0))
		if who == "me":
			if toxic > 0.65:
				_say(id, _pick_line(["bro %s was mine" % a, "wow kinuha mo %s ko" % a, "ok enjoy losing with %s" % a,
					"seriously? fine, %s" % b]))
			else:
				_say(id, _pick_line(["ok you take %s, I'll go %s" % [a, b], "sige, %s na lang ako" % b,
					"no worries, %s then" % b, "ok %s ako" % b]))
		else:
			_say(id, _pick_line(["nvm, %s na lang ako" % b, "they took %s, I'll go %s" % [a, b], "%s is gone, %s then" % [a, b]]))

## Pick `hero` for `id` on its turn. Returns "" or why not.
func pick(id: String, hero: String) -> String:
	if done() or current() != id:
		return "Not your turn"
	if taken(hero):
		return "That hero is taken"
	if not (hero in pool()):
		return "Unknown hero"
	if team_of(id) != mine() and not best.is_empty() and String(best[0][0]) == hero and not picks.has("me"):
		var mates: Array = order.filter(func(i): return i != "me" and team_of(String(i)) == mine())
		if not mates.is_empty():
			var mid: String = mates[rng.randi_range(0, mates.size() - 1)]
			var tox := float(profile(mid).get("toxic", 0.0)) > 0.6
			_later.append([_clock + rng.randf_range(0.4, 1.2), mid, (["ff", "why didn't you pick it", "bruh they sniped %s" % hero_name(hero)] if tox
				else ["they took your %s!" % hero_name(hero), "noo they sniped %s" % hero_name(hero), "they're scared of your %s lol" % hero_name(hero)])[rng.randi_range(0, 2)]])
	picks[id] = hero
	if id != "me" and team_of(id) == mine():
		_say(id, _pick_line(["locked %s" % hero_name(hero), "%s locked" % hero_name(hero), "gg ez", "let's go"]))
	_taken_from(id, hero)
	turn += 1
	t = 0.0
	return ""

## A hero for a player whose time ran out: one for their role nobody took.
func auto_hero(id: String) -> String:
	return _choose(id, {})

func step(dt: float) -> void:
	if done():
		return
	_clock += dt
	for e in _later.duplicate():
		if _clock >= float(e[0]):
			_later.erase(e)
			_say(String(e[1]), String(e[2]))
	if turn != _last_turn:
		_last_turn = turn
		var bf := _best_free()
		if bf != "" and _hurried < 2:
			var who := current()
			var mates: Array = order.filter(func(i): return i != "me" and team_of(String(i)) == mine())
			if not mates.is_empty() and who != "me" and team_of(who) != mine() and rng.randf() < 0.6:
				_hurried += 1
				var id: String = mates[rng.randi_range(0, mates.size() - 1)]
				_later.append([_clock + rng.randf_range(0.3, 1.0), id, ["hurry, pick %s before they take it" % hero_name(bf),
					"%s quick, they're picking" % hero_name(bf), "lock %s now!" % hero_name(bf)][rng.randi_range(0, 2)]])
			elif who == "me" and not mates.is_empty() and rng.randf() < 0.7:
				var id2: String = mates[rng.randi_range(0, mates.size() - 1)]
				_later.append([_clock + rng.randf_range(0.5, 1.5), id2, ["%s! %s!" % [hero_name(bf), hero_name(bf)], "go %s" % hero_name(bf),
					"your %s pls" % hero_name(bf)][rng.randi_range(0, 2)]])
	_announce(dt)
	t += dt
	var id := current()
	if id == "me":
		if t >= YOUR_TIME:
			pick("me", auto_hero("me"))
		return
	if t >= float(_delay.get(id, 2.0)):
		var h := String(wants.get(id, ""))
		if h == "" or taken(h):
			h = _choose(id, {})
		pick(id, h)

# ---- Talking during the pick (run 2026-10-19 e) -------------------------------------------------------------------------
# The owner: "allow the player to chat during the picking phase. Allow the player to Alt+click a hero to tell his allies
# that he wants to pick that hero, Shift+click a hero to tell allies to pick a certain hero."

var mine_wants := ""                       # the hero you told your team you want (Alt+click, or "X me")
var friends_made: Array = []               # ladder ids that said yes to your "add me" (the screen makes them friends)
var _asked_add := {}

## The bots of your team that have not picked yet.
func _free_mates() -> Array:
	return order.filter(func(i): return i != "me" and team_of(String(i)) == mine() and not picks.has(i))

func _mates() -> Array:
	return order.filter(func(i): return i != "me" and team_of(String(i)) == mine())

func _later_say(id: String, text: String, after: float) -> void:
	_later.append([_clock + after, id, text])

func _kind(id: String) -> float:
	return float((profile(id).get("persona", {}) as Dictionary).get("kind", 1.0 - float(profile(id).get("toxic", 0.3))))

## A hero named in `low` ("froster", "araki pls"): the first of the pool whose name starts with a word of 4+ letters.
func hero_in(low: String) -> String:
	var words := low.replace(",", " ").replace("?", " ").replace("!", " ").split(" ", false)
	for h in pool():
		var nm := hero_name(String(h)).to_lower()
		for wd in words:
			if (wd.length() >= 4 and nm.begins_with(wd)) or wd == nm:
				return String(h)
	return ""

## You typed a line in team chat: it shows, and your teammates answer what they understood.
## A teammate answers about the ladder: who is top 1 (or the top 5 / 10 / 20), or a player you named, with the facts
## and what it thinks of them.
func _ladder_reply(low: String, top: bool, named: Dictionary, mates: Array, d: float) -> void:
	var who: String = mates[rng.randi_range(0, mates.size() - 1)]
	var card := Ranked.ladder_card(20)
	var about := {}
	var text := ""
	if top:
		var want := 10 if (low.contains("10") or low.contains("leaderboard") or low.contains("players")) else (5 if low.contains("5") else (20 if low.contains("20") else 1))
		if want == 1:
			about = Ranked.profile(String(card[0].id))
			text = "%s is top 1, %s mmr, %s avg, mostly %s" % [String(card[0].name), str(int(card[0].mmr)), String(card[0].kda), String(card[0].hero)]
			if String(card[0].id) == "me":
				text = "its u lol, top 1"
				about = {}
		else:
			var names: Array = []
			for e in card.slice(0, want):
				names.append("%d %s" % [int(e.place), String(e.name)])
			text = "top %d: %s" % [want, ", ".join(names)]
	else:
		about = named
		var pl := Ranked.place_of(String(named.id))
		var hp := Ranked.heroes_played(named)
		text = "%s? %s, %d mvps%s" % [String(named.name), FriendChat.about_line({}, named).split(". ")[0],
			int(Career.moments(named).mvp), (", plays " + HeroDraft.hero_name(String(hp[0][0]))) if not hp.is_empty() else ""]
		if Ranked.is_yours(String(named.id)):
			text = "%s? thats ur other account right? #%d" % [String(named.name), pl] if String(named.id) != "me" else "thats u lol"
			about = {}
	_later_say(who, text, d)
	if not about.is_empty() and rng.randf() < 0.8:
		var f := ProfileTalk.read(about)
		var sit := "pf_other_good" if ProfileTalk.verdict(f) >= 0 or ProfileTalk.elite_facts(f) else "pf_other_bad"
		var line := ProfileTalk.say(profile(who), sit, ProfileTalk.fill(f), rng)
		if line != "":
			_later_say(who, line, d + rng.randf_range(1.4, 2.6))

func say_me(text: String) -> void:
	var t := text.strip_edges().substr(0, 120)
	if t == "":
		return
	chat.append({"id": "me", "name": String(Ranked.me().get("name", "You")), "text": t, "team": mine(), "me": true})
	var low := t.to_lower()
	var mates := _mates()
	if mates.is_empty():
		return
	var h := hero_in(low)
	var it := ChatMind.intent(low)
	var d := rng.randf_range(0.9, 2.0)
	if it == "add":
		var who: String = mates[rng.randi_range(0, mates.size() - 1)]
		for m in mates:
			var mn := String(profile(String(m)).get("name", "")).to_lower()
			if mn.length() >= 3 and low.contains(mn.split(" ")[0]):
				who = String(m)
		if _asked_add.has(who):
			return
		_asked_add[who] = true
		var rep := float((profile(who).get("you", {}) as Dictionary).get("rep", 0.0))
		if rep * 1.2 + _kind(who) * 0.7 + rng.randf_range(-0.15, 0.15) >= 0.55:
			friends_made.append(who)
			_later_say(who, _pick_line(["sure", "added", "sige add kita", "ok, duo after", "g"]), d)
		else:
			_later_say(who, _pick_line(["no", "win first", "nah", "after the game maybe", "pass"]), d)
		return
	# the top of the ladder, or a ladder player you named who is not in this match (run 2026-10-20 e)
	var named := Ranked.named_in(low)
	var in_match := false
	for side in 2:
		for p in lineup.teams[side]:
			if not named.is_empty() and String(p.id) == String(named.get("id", "")):
				in_match = true
	if it == "ladder_top" or (not named.is_empty() and not in_match and h == ""):
		_ladder_reply(low, it == "ladder_top" and (named.is_empty() or in_match), named, mates, d)
		return
	if h != "" and (low.begins_with("pick ") or low.contains("u pick") or low.contains("you pick") or low.contains("someone pick") or low.contains("play ")):
		suggest(h, false)
		return
	if h != "" and not taken(h):
		want_me(h, false)
		return
	match it:
		"greet":
			var g: String = mates[rng.randi_range(0, mates.size() - 1)]
			_later_say(g, _pick_line(["hi", "yo", "gl hf", "hello", "uy", "musta", "glhf"]), d)
			if mates.size() > 1 and rng.randf() < 0.5:
				var g2: String = mates[rng.randi_range(0, mates.size() - 1)]
				if g2 != g:
					_later_say(g2, _pick_line(["hey", "gl", "sup", "hello po", "lets win this"]), d + rng.randf_range(0.8, 1.8))
		"taunt", "insult":
			var x: String = mates[rng.randi_range(0, mates.size() - 1)]
			if _kind(x) > 0.5:
				_later_say(x, _pick_line(["we didnt even start lol", "save it for the game", "talk after u pick", "big words for " + _kda_avg("me") + " avg",
					"ok tough guy, pick first", "angas ah, laro muna"]), d)
			else:
				_later_say(x, _pick_line(["ur the one feeding later", "talk after u pick", "ok mr toxic", "report this guy", "yabang"]), d)
		"profile_me", "profile_you":
			# they look you up (or the one you asked looks at itself): what they see, in their own manner
			var pm: String = mates[rng.randi_range(0, mates.size() - 1)]
			for m in mates:
				var mn := String(profile(String(m)).get("name", "")).to_lower()
				if mn.length() >= 3 and low.contains(mn.split(" ")[0]):
					pm = String(m)
			if it == "profile_me":
				var line := ProfileTalk.line_about(profile(pm), Ranked.me(), rng, "with")
				if line != "":
					_later_say(pm, line, d)
				if mates.size() > 1 and rng.randf() < 0.55:
					var pm2: String = mates[rng.randi_range(0, mates.size() - 1)]
					if pm2 != pm:
						var line2 := ProfileTalk.line_about(profile(pm2), Ranked.me(), rng, "with")
						if line2 != "":
							_later_say(pm2, line2, d + rng.randf_range(1.2, 2.4))
			else:
				var f := ProfileTalk.read(profile(pm))
				var txt := ProfileTalk.say(profile(pm), "pf_other_reply_good" if ProfileTalk.verdict(f) > 0 else "pf_other_reply_bad", ProfileTalk.fill(f), rng)
				if txt != "":
					_later_say(pm, txt, d)
		"rank":
			var r: String = mates[rng.randi_range(0, mates.size() - 1)]
			var rk := Ranked.rank_label(profile(r)).to_lower()
			_later_say(r, _pick_line([rk, rk + ", u?", "im " + rk, rk + " lol"]), d)
		"praise", "thanks":
			var p2: String = mates[rng.randi_range(0, mates.size() - 1)]
			_later_say(p2, _pick_line(["np", "ty", "gl", "lets go"]), d)
		_:
			if low.contains("mid") or low.contains("carry") or low.contains("support") or low.contains("offlane") or low.contains("safe"):
				var c: String = mates[rng.randi_range(0, mates.size() - 1)]
				var my_role := RankedNum.role(role_of("me")).to_lower()
				if _kind(c) > 0.45:
					_later_say(c, _pick_line(["ok", "ur " + my_role + " anyway", "sure", "fine", "k"]), d)
				else:
					_later_say(c, _pick_line(["ur " + my_role + ", play ur role", "no, ur " + my_role, "we'll see"]), d)
			elif rng.randf() < 0.35:
				var o: String = mates[rng.randi_range(0, mates.size() - 1)]
				_later_say(o, _pick_line(["?", "ok", "lol", "k", "sure", "ano"]), d)

## Alt+click (or "X me"): you tell your team you want `hero`. Teammates who wanted it pick another (most say so;
## a rough one complains first), and nobody on your team goes for it while you have not picked.
func want_me(hero: String, post := true) -> void:
	if hero == "" or taken(hero) or picks.has("me"):
		return
	mine_wants = hero
	if post:
		chat.append({"id": "me", "name": String(Ranked.me().get("name", "You")), "text": "I want to play " + hero_name(hero),
			"team": mine(), "me": true, "call": true})
	var t := rng.randf_range(0.8, 1.6)
	var answered := false
	var a := hero_name(hero)
	for id in _free_mates():
		if String(wants.get(id, "")) != hero:
			continue
		var called := {hero: true}
		for o in wants:
			if o != id and team_of(String(o)) == mine() and not picks.has(o):
				called[String(wants[o])] = true
		var next := _choose(String(id), called)
		wants[id] = next
		var b := hero_name(next)
		if _kind(String(id)) < 0.35:
			_later_say(String(id), _pick_line(["bro i called " + a + " first", "fine, " + b + ". ur " + a + " better be good",
				"seriously? ok " + b]), t)
		else:
			_later_say(String(id), _pick_line(["ok " + a + " is yours, I'll go " + b, "sige sayo na " + a + ", " + b + " na lang ako",
				"np, " + b + " then"]), t)
		answered = true
		t += rng.randf_range(0.8, 1.5)
	if not answered:
		var mates := _mates()
		if not mates.is_empty() and rng.randf() < 0.75:
			var m: String = mates[rng.randi_range(0, mates.size() - 1)]
			var med := Ranked.hero_medal(Ranked.me(), hero)
			var lines := ["ok", "go " + a, "nice", a + " ok", "sige"]
			if int(med.medal) >= 3:
				lines = [String(med.name) + " " + a + ", nice", "yes " + a + " pls", "ur " + a + " is good, go"]
			elif int(med.medal) == 0 and int(profile(m).get("skill", 0)) > 2500 and _kind(m) < 0.5:
				lines = ["u even play " + a + "?", "first time " + a + "? lol", a + "... ok"]
			_later_say(m, _pick_line(lines), t)

## Shift+click (or "pick X"): you ask a teammate to pick `hero`. One who has not picked and whose role it fits takes it
## up (a rough one may refuse); nobody left: someone tells you so.
func suggest(hero: String, post := true) -> void:
	if hero == "" or taken(hero):
		return
	var hn := hero_name(hero)
	if post:
		chat.append({"id": "me", "name": String(Ranked.me().get("name", "You")), "text": "Pick " + hn, "team": mine(), "me": true, "call": true})
	var free := _free_mates()
	var t := rng.randf_range(0.9, 1.8)
	if free.is_empty():
		var mates := _mates()
		if not mates.is_empty():
			_later_say(String(mates[0]), _pick_line(["we all picked already", "too late lol", "pick it urself"]), t)
		return
	# the teammate it suits best: its role fits, it has the hero, it is not set on a hero of its own
	var best_id := ""
	var best_s := -INF
	for id in free:
		var s := 0.0
		if role_of(String(id)) in KITS.roles(hero).slice(0, 3):
			s += 2.0
		if hero in (profile(String(id)).get("heroes", []) as Array):
			s += 1.5
		if not _said_want.has(id):
			s += 0.5
		s += _kind(String(id)) + rng.randf_range(0.0, 0.6)
		if s > best_s:
			best_s = s
			best_id = String(id)
	if best_id == "":
		return
	var fits: bool = role_of(best_id) in KITS.roles(hero).slice(0, 3)
	var rough: bool = _kind(best_id) < 0.35 and float(profile(best_id).get("toxic", 0.0)) > 0.5
	var own := hero_name(String(wants.get(best_id, "")))
	if (not fits and rng.randf() < 0.6) or (rough and rng.randf() < 0.55):
		_later_say(best_id, _pick_line(["no, I'm " + own, "pick it yourself", hn + " is not my role", "nah", "ayoko, " + own + " ako"]), t)
		return
	wants[best_id] = hero
	_said_want[best_id] = true
	_later_say(best_id, _pick_line(["ok I'll go " + hn, "sure, " + hn, "sige " + hn + " ako", "fine, " + hn + " it is", "ok " + hn]), t)

## Your average K/D/A as chat text ("8/4/11"), "?" before your first match.
func _kda_avg(id: String) -> String:
	return String(ProfileTalk.fill(ProfileTalk.read(profile(id))).get("kda", "?"))

## They look each other up while picking (run 2026-10-20): a teammate or two reads your profile (your averages, your last
## five matches, your MVPs and rampages) and says what it sees; one reads an enemy's or a teammate's.
func _react_to_profiles() -> void:
	var mates := _mates()
	if mates.is_empty():
		return
	var t := 5.0 + (3.0 if not best.is_empty() else 0.0) + (2.5 if Ranked.mvp_last(Ranked.me()) else 0.0)
	var pool := mates.duplicate()
	var n := 0
	var want := 1 + (1 if rng.randf() < 0.45 else 0)
	# a pro on the team: nearly everyone has looked them up already, and says so
	var pro := ProfileTalk.elite(Ranked.me())
	if pro:
		want = 2 + (1 if rng.randf() < 0.6 else 0)
	while n < want and not pool.is_empty():
		var m: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var ps: Dictionary = profile(m).get("persona", {})
		if rng.randf() > (0.8 if pro else 0.45) + float(ps.get("talk", 0.5)) * 0.45:
			continue
		var line := ProfileTalk.line_about(profile(m), Ranked.me(), rng, "with")
		if line != "":
			_later.append([t, m, line])
			t += rng.randf_range(1.6, 3.2)
			n += 1
	# someone else's profile: an enemy (what to expect) or a teammate (who to trust)
	if rng.randf() < 0.6:
		var who: String = mates[rng.randi_range(0, mates.size() - 1)]
		var side := 1 - mine() if rng.randf() < 0.55 else mine()
		var others: Array = (lineup.teams[side] as Array).filter(func(p): return String(p.id) != "me" and String(p.id) != who)
		if not others.is_empty():
			var o: Dictionary = others[rng.randi_range(0, others.size() - 1)]
			var f := ProfileTalk.read(o)
			var v := ProfileTalk.verdict(f)
			var fl := ProfileTalk.fill(f)
			var sit := "pf_other_good" if v > 0 else "pf_other_bad"
			var line2 := ProfileTalk.say(profile(who), sit, fl, rng)
			if line2 != "" and (v != 0 or ProfileTalk.manner_of(profile(who)) in ["rough", "troll"]):
				_later.append([t, who, line2])
				if side == mine() and rng.randf() < 0.7:
					var back := ProfileTalk.say(o, "pf_other_reply_good" if v > 0 else "pf_other_reply_bad", ProfileTalk.fill(ProfileTalk.read(profile(who))), rng)
					if back != "":
						_later.append([t + rng.randf_range(1.4, 2.6), String(o.id), back])

## Your teammates notice MVPs from the last games: yours (they expect you to carry), an enemy's (careful), their own.
func _react_to_mvp() -> void:
	var mates := _mates()
	if mates.is_empty():
		return
	var you := String(Ranked.me().get("name", "you"))
	var t := 2.2 + (3.0 if not best.is_empty() else 0.0)
	if Ranked.mvp_last(Ranked.me()):
		var m: String = mates[rng.randi_range(0, mates.size() - 1)]
		_later.append([t, m, _pick_line([you + " was MVP last game, carry us", "MVP on our team!", you + " the MVP, ez",
			"ok " + you + ", MVP again pls", "MVP si " + you + " last game"])])
		t += rng.randf_range(1.2, 2.4)
		if mates.size() > 1 and rng.randf() < 0.6:
			var m2: String = mates[rng.randi_range(0, mates.size() - 1)]
			if m2 != m:
				_later.append([t, m2, _pick_line(["no pressure " + you + " lol", "lets see if its real", "carry pls", "buhat mo kami ha"])])
				t += rng.randf_range(1.2, 2.4)
	for side in 2:
		for p in lineup.teams[side]:
			var id := String(p.id)
			if id == "me" or not Ranked.mvp_last(p) or rng.randf() > 0.55:
				continue
			var nm := String(p.get("name", ""))
			var who: String = mates[rng.randi_range(0, mates.size() - 1)]
			if side == mine():
				if who == id:
					_later.append([t, id, _pick_line(["mvp last game btw", "im on a roll, MVP last game", "mvp ako last game"])])
				else:
					_later.append([t, who, _pick_line([nm + " was MVP last game", "we have " + nm + ", MVP last game"])])
			else:
				_later.append([t, who, _pick_line(["careful, " + nm + " was MVP last game", "they have " + nm + ", MVP last game",
					nm + " MVP last game, focus that one"])])
			t += rng.randf_range(1.5, 3.0)
