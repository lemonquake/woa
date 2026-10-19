class_name Matchmaker
extends RefCounted
## Finding a ranked match (run 2026-10-19 b). Like Dota's role queue: you tick the roles you will play, the search
## looks for nine players near your MMR and widens its window the longer it takes (100 MMR, then +45 a second), then
## splits the ten into two teams of even average MMR with every role 1-5 covered on each side (players kept on roles
## they like where possible) and you on one of the roles you ticked. Heroes are picked after everyone accepts (HeroDraft,
## the owner: nobody picks a hero before matchmaking). Then the match is offered: every player has 15 seconds to
## accept; a bot with a poor behaviour score sometimes fails to, and you go back into the queue. Declining puts the
## search back on and keeps those nine out of your next few offers.
##
## The screen calls start(), step(dt) every frame, accept(), decline() and cancel(), and reads `state`, `stage`,
## `progress()`, `found` and `lineup`.

const C = preload("res://src/sim/sim_const.gd")
const KITS = preload("res://src/sim/sim_bot_kits.gd")
const ACCEPT_SECS := 15.0

var state := "idle"                        # idle, searching, found (the offer), ready, failed
var t := 0.0                               # seconds in the queue
var expect := 10.0                         # seconds this search will take
var roles: Array = [1, 2, 3, 4, 5]         # roles you ticked (1 carry .. 5 hard support)
## The match everyone accepted, handed from the Ranked screen to the hero pick (ranked_draft.gd).
static var accepted_match := {}
var window := 100                          # MMR either side of yours
var found := 0                             # players found so far (shown while searching)
var stage := ""
var note := ""                             # what happened last ("A player failed to accept" ...)
var lineup := {}
var accept_t := 0.0                        # seconds since the offer
var you_accepted := false
var rng := RandomNumberGenerator.new()
var _avoid := {}                           # bot id -> searches left it stays out of offers (you declined it)

func _init() -> void:
	rng.randomize()

func start(p_roles: Array) -> void:
	roles = p_roles.duplicate() if not p_roles.is_empty() else [1, 2, 3, 4, 5]
	t = 0.0
	found = 0
	window = 100
	lineup = {}
	you_accepted = false
	state = "searching"
	var my := int(Ranked.me().mmr)
	var near := 0
	for b in Ranked.bots():
		if absi(int(b.mmr) - my) <= 300:
			near += 1
	# fewer players near you (very high or very low MMR) and the cores' roles take longer, as in Dota
	expect = clampf(5.0 + 70.0 / float(near + 2) + rng.randf_range(-1.5, 3.5), 5.0, 28.0)
	if roles.size() <= 2 and (1 in roles or 2 in roles) and not (4 in roles or 5 in roles):
		expect += 3.0
	elif 5 in roles or 4 in roles:
		expect -= 1.0

func cancel() -> void:
	state = "idle"
	note = ""
	lineup = {}

## Seconds left to accept.
func accept_left() -> float:
	return maxf(0.0, ACCEPT_SECS - accept_t)

## 0..1 for the search bar.
func progress() -> float:
	if state == "searching":
		return clampf(t / maxf(expect, 0.1), 0.0, 0.98)
	return 1.0 if state in ["found", "ready"] else 0.0

func step(dt: float) -> void:
	match state:
		"searching":
			t += dt
			window = 100 + int(45.0 * t)
			var cands := _candidates()
			var f := progress()
			found = mini(9, mini(cands.size(), int(floor(9.0 * f / 0.85))))
			var my := int(Ranked.me().mmr)
			if f < 0.3:
				stage = "Searching for players near %d MMR" % my
			elif f < 0.6:
				stage = "Widening the search to %d MMR either side" % window
			elif f < 0.85:
				stage = "Matching roles"
			else:
				stage = "Balancing teams"
			if t >= expect and cands.size() >= 9:
				_offer(cands)
		"found":
			accept_t += dt
			var all_in := you_accepted
			for id in lineup.accept_at:
				if lineup.fails.has(id) or accept_t < float(lineup.accept_at[id]):
					all_in = false
			if all_in:
				state = "ready"
				note = ""
			elif accept_t >= ACCEPT_SECS:
				if not you_accepted:
					note = "You did not accept the match."
					state = "failed"
				else:
					# a player failed to accept: back into the queue, ahead of where you were
					note = "A player failed to accept. You are back in the queue."
					for id in lineup.fails:
						_avoid[id] = 3
					var keep := roles
					start(keep)
					expect = maxf(4.0, expect * 0.6)

## Has this bot accepted yet (the offer's ten lights)?
func accepted(id: String) -> bool:
	if id == "me":
		return you_accepted
	if lineup.is_empty() or lineup.fails.has(id):
		return false
	return accept_t >= float(lineup.accept_at.get(id, 999.0))

func accept() -> void:
	if state == "found":
		you_accepted = true

## Decline the offer: those nine stay out of your next few offers and the search starts again.
func decline() -> void:
	if state != "found":
		return
	for t_ in 2:
		for p in lineup.teams[t_]:
			if String(p.id) != "me":
				_avoid[String(p.id)] = 2
	note = "You declined. Searching again."
	start(roles)

## Players near your MMR who are in the queue: online and not in a match (Persona's schedule). A long search takes
## players finishing their games too, and then anyone (no search waits forever).
func _candidates() -> Array:
	var my := int(Ranked.me().mmr)
	var now := Ranked.now()
	var out: Array = []
	for b in Ranked.bots():
		if absi(int(b.mmr) - my) > window or int(_avoid.get(String(b.id), 0)) > 0:
			continue
		if t < expect + 12.0 and not Persona.queueable(b, now):
			continue
		if t < expect + 25.0 and not Persona.online(b, now):
			continue
		out.append(b)
	return out

## Build the offer from the candidates: nine near you, two even teams with roles, heroes, accept timings.
func _offer(cands: Array) -> void:
	for id in _avoid.keys():
		_avoid[id] = int(_avoid[id]) - 1
		if int(_avoid[id]) <= 0:
			_avoid.erase(id)
	lineup = build_lineup(cands, Ranked.me(), roles, rng)
	accept_t = 0.0
	you_accepted = false
	state = "found"
	stage = "Match found"

## The match for you and nine of `cands`: {teams: [[profiles], [profiles]], mine, roles: {id: role}, accept_at: {id: s},
## fails: {id: true}, avg: [mmr, mmr], my_role}. Static so tests can call it.
static func build_lineup(cands: Array, you: Dictionary, p_roles: Array, r: RandomNumberGenerator) -> Dictionary:
	var my := int(you.mmr)
	var near := cands.duplicate()
	near.sort_custom(func(a, b): return absi(int(a.mmr) - my) < absi(int(b.mmr) - my))
	# nine from the closest fourteen, chosen at random (so two searches rarely meet the same nine)
	var pool := near.slice(0, mini(14, near.size()))
	var nine: Array = []
	while nine.size() < 9 and not pool.is_empty():
		var i := r.randi_range(0, mini(pool.size() - 1, 9 - nine.size() + 4))
		nine.append(pool[i])
		pool.remove_at(i)
	var my_role := int(p_roles[r.randi_range(0, p_roles.size() - 1)]) if not p_roles.is_empty() else r.randi_range(1, 5)
	# the split with the closest averages and the fewest players off their roles
	var best := {}
	var best_score := INF
	var idx := range(9)
	for combo in _combos(idx, 4):
		var a: Array = [you]
		var b: Array = []
		for i in 9:
			if i in combo:
				a.append(nine[i])
			else:
				b.append(nine[i])
		var ra := _assign_roles(a, {"me": my_role})
		var rb := _assign_roles(b, {})
		var score := absf(_avg(a) - _avg(b)) + 45.0 * float(ra.off + rb.off)
		if score < best_score:
			best_score = score
			best = {"a": a, "b": b, "ra": ra.roles, "rb": rb.roles}
	var roles: Dictionary = (best.ra as Dictionary).duplicate()
	roles.merge(best.rb)
	var order: Array = (best.a as Array).slice(1) + (best.b as Array)
	# accept timings: most within a few seconds; a bot with a poor behaviour score is slower and sometimes never does
	var accept_at := {}
	var fails := {}
	for p in order:
		var bh := float(p.get("behavior", 10000))
		accept_at[String(p.id)] = r.randf_range(0.6, 6.5) * (1.4 if bh < 4000.0 else 1.0)
		if r.randf() < 0.012 + (12000.0 - bh) / 12000.0 * 0.07:
			fails[String(p.id)] = true
	var mine := r.randi_range(0, 1)
	var teams := [[], []]
	teams[mine] = best.a
	teams[1 - mine] = best.b
	return {"teams": teams, "mine": mine, "roles": roles, "heroes": {}, "accept_at": accept_at, "fails": fails,
		"avg": [_avg(teams[0]), _avg(teams[1])], "my_role": my_role}

static func _avg(team: Array) -> float:
	var s := 0.0
	for p in team:
		s += float(p.mmr)
	return s / maxf(1.0, float(team.size()))

## Every way to choose k of `items` (as arrays of the chosen items).
static func _combos(items: Array, k: int) -> Array:
	var out: Array = []
	_combo_rec(items, k, 0, [], out)
	return out

static func _combo_rec(items: Array, k: int, from: int, cur: Array, out: Array) -> void:
	if cur.size() == k:
		out.append(cur.duplicate())
		return
	for i in range(from, items.size()):
		cur.append(items[i])
		_combo_rec(items, k, i + 1, cur, out)
		cur.pop_back()

## Roles 1..5 for a team of five with some fixed ({id: role}): the assignment with the fewest players off the roles
## they like. Returns {roles: {id: role}, off: count}.
static func _assign_roles(team: Array, fixed: Dictionary) -> Dictionary:
	var open: Array = [1, 2, 3, 4, 5]
	var free: Array = []
	var out := {}
	for p in team:
		var id := String(p.id)
		if fixed.has(id):
			out[id] = int(fixed[id])
			open.erase(int(fixed[id]))
		else:
			free.append(p)
	var best: Array = []
	var best_off := 99
	for perm in _perms(open):
		var off := 0
		for i in free.size():
			if not (int(perm[i]) in (free[i].get("roles", []) as Array)):
				off += 1
		if off < best_off:
			best_off = off
			best = perm
			if off == 0:
				break
	for i in free.size():
		out[String(free[i].id)] = int(best[i]) if i < best.size() else 5
	return {"roles": out, "off": best_off}

static func _perms(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		var x = rest.pop_at(i)
		for p in _perms(rest):
			out.append([x] + p)
	return out

## The match as Game Setup slots for the match scene (GameSettings.ranked): you and nine bots with their names,
## heroes (from the hero pick), roles, lanes, hidden skill and personality.
static func slots_for(l: Dictionary) -> Array:
	var out: Array = []
	for t_ in 2:
		for p in l.teams[t_]:
			var id := String(p.id)
			var role := int(l.roles.get(id, 0))
			var lane := String(KITS.ROLE_LANE.get(role, ""))
			var s := {"team": t_, "kind": "you" if id == "me" else "bot", "hero": String(l.heroes.get(id, "")),
				"skill": "hard", "name": String(p.name), "lane": lane, "role": str(role) if role > 0 else "", "id": id}
			if id != "me":
				s["rating"] = int(p.get("skill", 2000))
				var y: Dictionary = (p.get("you", {}) as Dictionary).duplicate()
				y["friend"] = id in (Ranked.me().get("friends", []) as Array)
				s["traits"] = {"coop": float(p.get("coop", 1.0)), "disrupt": float(p.get("disrupt", 0.0)),
					"toxic": float(p.get("toxic", 0.0)), "rage": bool(p.get("rage", false)), "voice": p.get("voice", {}),
					"persona": p.get("persona", {}), "pid": id, "you": y,
					"card": {"rank": Ranked.rank_label(p), "mmr": int(p.get("mmr", 0)), "country": String(p.get("country", "")),
						"mood": float(p.get("mood", 0.0))}}
			out.append(s)
	return out
