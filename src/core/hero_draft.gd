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
	var free := func(h: String) -> bool: return not taken(h) and not called.has(h)
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
	chat.append({"id": id, "name": String(profile(id).get("name", "")), "text": typed, "team": team_of(id)})

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
