class_name SimTeamAI
extends RefCounted
## One team's brain (Valve's "team level"): it splits the heroes into roles and lanes so every lane has someone,
## leaves the lane the player takes to the player, keeps what the team has seen of the enemy (last position, health,
## who is dead or missing), and calls team plays: ganks on heroes caught alone or low, pushes when the enemy is down
## heroes, defence when a tower is hit, regrouping late. It answers the player's pings, often but not always, and its
## bots say in team chat what they will do and, when they will not, why (dead, low health, TP on cooldown, too far,
## outnumbered...). Bots read their task from here (task_for) and decide everything else themselves (SimBot).
## It acts only through bots, chat and the Fortify button, like a team of players.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const KITS = preload("res://src/sim/sim_bot_kits.gd")

var w: SimWorld
var team := 0
var rng := RandomNumberGenerator.new()
var roles := {}                            # hero id -> role 1..5
var lane_of := {}                          # hero id -> "top" / "mid" / "bot"
var seen := {}                             # enemy hero id -> {pos, t, hp, max_hp, level, lane}
var plans: Array = []                      # [{id, kind, lane, target, pos, members: {hero id: true}, until, ping}]
var camp_seen := {}                        # camp id -> {up: bool, t} what the team last saw of a camp
var camp_claim := {}                       # camp id -> [hero id, until] (two bots do not farm one camp)
var stack_count := {}                      # camp id -> how many times stacked since last cleared
var player_lane := {}                      # human hero id -> lane detected or chosen
var player_pref := {}                      # human hero id -> lane chosen in Game Setup ("" = any)
var fixed_role := {}                       # bot hero id -> role set for it in Game Setup
var _plan_id := 1
var _next_think := C.LONG_AGO
var _assigned := false
var _said := {}                            # chat key -> time said
var _last_chat := C.LONG_AGO
var _bot_chat := {}                        # hero id -> time of its last line
var _pending_pings: Array = []
var _lane_watch := {}                      # human hero id -> [lane, since]
var _missing_called := {}                  # enemy hero id -> time of the last "missing" call
var _fight_called := C.LONG_AGO

func _init(world: SimWorld = null, p_team := 0) -> void:
	if world == null:
		return                                   # being restored from a snapshot
	w = world
	team = p_team
	rng.seed = int(world.rng.seed) * 31 + 7 + p_team

# ---- Members --------------------------------------------------------------------------------------------------------

func members() -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for h in w.heroes:
		if h.team == team:
			out.append(h)
	return out

func bot_of(hid: int) -> SimBot:
	for b in w.bots:
		if b.hero_id == hid:
			return b
	return null

func enemies_alive() -> int:
	var n := 0
	for h in w.heroes:
		if h.team != team and h.alive:
			n += 1
	return n

func allies_alive() -> int:
	var n := 0
	for h in members():
		if h.alive:
			n += 1
	return n

## The lane names for a team's safe and off lanes.
static func lane_name(kind: String, p_team: int) -> String:
	match kind:
		"safe":
			return "bot" if p_team == C.DAWN else "top"
		"off":
			return "top" if p_team == C.DAWN else "bot"
	return "mid"

static func lane_kind(lane: String, p_team: int) -> String:
	if lane == "mid":
		return "mid"
	return "safe" if lane == lane_name("safe", p_team) else "off"

static func lane_label(lane: String) -> String:
	return {"top": "top", "mid": "mid", "bot": "bottom"}.get(lane, lane)

static func hero_label(h: SimUnit) -> String:
	return String(h.def.get("name", h.def.id))

# ---- Thinking -------------------------------------------------------------------------------------------------------

func think() -> void:
	if w == null or w.time < _next_think:
		return
	_next_think = w.time + 0.5
	if not _assigned:
		assign_lanes()
		_assigned = true
		_announce_lanes()
	_update_seen()
	_update_camps()
	_watch_players()
	for pg in _pending_pings:
		_answer_ping(pg)
	_pending_pings.clear()
	plans = plans.filter(func(p): return w.time < float(p.until) and _plan_alive(p))
	if w.time >= 0.0:
		_call_defence()
		_call_ganks()
		_call_push()
		_call_missing()
		_call_danger()
		_glyph()

# ---- Roles and lanes ------------------------------------------------------------------------------------------------

## Roles by team size: who has to be there before anyone doubles up (every lane covered from three heroes up).
const ROLE_ORDER := {1: [2], 2: [2, 1], 3: [2, 1, 3], 4: [2, 1, 3, 5], 5: [2, 1, 3, 5, 4]}

func assign_lanes() -> void:
	var ms := members()
	var n := clampi(ms.size(), 1, 5)
	var need: Array = (ROLE_ORDER[n] as Array).duplicate()
	roles.clear()
	# the players first: the lane they chose or took (or used to take with this hero), else their hero's best role
	for h in ms:
		if h.bot:
			continue
		var lk := String(player_lane.get(h.id, player_pref.get(h.id, "")))
		if lk == "":
			lk = BotMemory.player_lane(String(h.def.id))
		var r := _role_for_lane_kind(lk, String(h.def.id), need)
		if r == 0:
			for cand in KITS.roles(String(h.def.id)):
				if cand in need:
					r = cand
					break
		if r == 0 and not need.is_empty():
			r = need[0]
		roles[h.id] = r
		need.erase(r)
	# then the bots: those given a role in Game Setup take it, the rest fill each open role (cores first) with the
	# bot whose hero plays it best
	var bots: Array[SimUnit] = []
	for h in ms:
		if h.bot:
			bots.append(h)
	for h in bots:
		if fixed_role.has(h.id):
			roles[h.id] = int(fixed_role[h.id])
			need.erase(int(fixed_role[h.id]))
	for r in need.duplicate():
		var best: SimUnit = null
		var best_i := 99
		for h in bots:
			if roles.has(h.id):
				continue
			var pref: Array = KITS.roles(String(h.def.id))
			var i := pref.find(r)
			if i < 0:
				i = 10
			if i < best_i:
				best_i = i
				best = h
		if best != null:
			roles[best.id] = r
			need.erase(r)
	# anyone left over (more heroes than roles): a support role in the safe lane
	for h in bots:
		if not roles.has(h.id):
			roles[h.id] = 5
	for h in ms:
		lane_of[h.id] = lane_name(KITS.ROLE_LANE[int(roles[h.id])], team)
		var b := bot_of(h.id)
		if b != null:
			b.set_role(int(roles[h.id]), String(lane_of[h.id]))

func _role_for_lane_kind(lk: String, hero: String, need: Array) -> int:
	match lk:
		"mid":
			return 2
		"safe":
			return 1 if not (KITS.roles(hero)[0] in [4, 5]) else 5
		"off":
			return 3 if not (KITS.roles(hero)[0] in [4, 5]) else 4
	return 0

func _announce_lanes() -> void:
	for h in members():
		if not h.bot:
			continue
		var r := int(roles.get(h.id, 0))
		var ln := lane_label(String(lane_of.get(h.id, "mid")))
		var text := "I'll go %s." % ln
		if r == 5 or r == 4:
			var core := _core_in_lane(String(lane_of[h.id]), h)
			text = "I'll support %s in the %s lane." % [_name_of(core), ln] if core != null else "I'll support the %s lane." % ln
		elif r == 1:
			text = "I'll farm the %s lane (safe lane)." % ln
		say(h, text, "lane_%d" % h.id, 9999.0, true)

func _core_in_lane(lane: String, not_h: SimUnit) -> SimUnit:
	for h in members():
		if h != not_h and String(lane_of.get(h.id, "")) == lane and int(roles.get(h.id, 5)) <= 3:
			return h
	return null

func _name_of(h: SimUnit) -> String:
	if h == null:
		return "nobody"
	if not h.bot:
		return "you"
	return h.bot_name if h.bot_name != "" else hero_label(h)

## The player's lane: watched from the horn until 2:30. When they settle in a lane (3 s), the bots re-plan around it
## and say so; every lane stays covered.
func _watch_players() -> void:
	if w.time > 150.0:
		return
	for h in members():
		if h.bot or not h.alive:
			continue
		var best := ""
		var bd := INF
		for ln in ["top", "mid", "bot"]:
			var d := SimMap._polyline_distance(h.pos, w.map.lane_path(ln, team))
			if d < bd:
				bd = d
				best = ln
		if bd > 900.0 or h.pos.distance_to(w.map.fountains[team]) < 3200.0:
			_lane_watch.erase(h.id)
			continue
		var cur: Array = _lane_watch.get(h.id, ["", 0.0])
		if cur[0] != best:
			_lane_watch[h.id] = [best, w.time]
			continue
		if w.time - float(cur[1]) < 3.0 or String(player_lane.get(h.id, "")) == lane_kind(best, team):
			continue
		var old := lane_of.duplicate()
		player_lane[h.id] = lane_kind(best, team)
		assign_lanes()
		if w.time < 600.0:
			BotMemory.note_player_lane(String(h.def.id), lane_kind(best, team))
		for m in members():
			if m.bot and String(old.get(m.id, "")) != String(lane_of.get(m.id, "")):
				var ln := lane_label(String(lane_of[m.id]))
				var r := int(roles.get(m.id, 0))
				if String(old.get(m.id, "")) == best:
					say(m, "You're %s? Okay, I'll go %s." % [lane_label(best), ln], "swap_%d_%s" % [m.id, best], 60.0, true)
				elif r >= 4 and String(lane_of[m.id]) == best:
					say(m, "I'll support you in the %s lane." % ln, "swap_%d_%s" % [m.id, best], 60.0, true)
				else:
					say(m, "Going %s so no lane is empty." % ln, "swap_%d_%s" % [m.id, best], 60.0, true)

# ---- What the team knows ----------------------------------------------------------------------------------------------

func _update_seen() -> void:
	for e in w.heroes:
		if e.team == team:
			continue
		if not e.alive:
			var s: Dictionary = seen.get(e.id, {})
			s["dead_until"] = e.respawn_at
			s["t"] = w.time
			s["pos"] = w.map.fountains[e.team]
			seen[e.id] = s
			continue
		if w.vision.sees(team, e):
			seen[e.id] = {"pos": e.pos, "t": w.time, "hp": e.hp, "max_hp": e.max_hp, "level": e.level,
				"dead_until": -1.0}

## Where the team last saw an enemy hero, and how long ago (INF if never).
func last_seen(e: SimUnit) -> Array:
	var s: Dictionary = seen.get(e.id, {})
	if s.is_empty():
		return [w.map.fountains[e.team], INF]
	return [s.pos, w.time - float(s.t)]

## Enemy heroes believed near a point: seen there within `recent` seconds (fog-of-war guesses, no cheating).
func enemies_near(p: Vector2, r: float, recent := 4.0) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for e in w.heroes:
		if e.team == team or not e.alive:
			continue
		var ls := last_seen(e)
		if float(ls[1]) <= recent and (ls[0] as Vector2).distance_to(p) <= r:
			out.append(e)
	return out

func allies_near(p: Vector2, r: float) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for h in members():
		if h.alive and h.pos.distance_to(p) <= r:
			out.append(h)
	return out

## What the team believes about each camp: up (creeps there) or cleared, from what it saw; unseen cleared camps are
## assumed back after the next minute mark unless something stood in the box.
func _update_camps() -> void:
	for c in w.map.camps:
		var vis := w.vision.cell_visible(team, c.pos)
		if vis:
			var up := false
			for u in w.ai.box_units(c):
				if u.camp_id == c.id:
					up = true
					break
			if not up:
				for u: SimUnit in w.query(c.pos, 900.0):
					if u.alive and u.camp_id == c.id:
						up = true
						break
			var prev: Dictionary = camp_seen.get(c.id, {})
			if prev.get("up", true) and not up:
				stack_count.erase(c.id)
			camp_seen[c.id] = {"up": up, "t": w.time}
		elif camp_seen.has(c.id) and not bool(camp_seen[c.id].up):
			# a minute mark passed since we saw it empty: probably back
			var t := float(camp_seen[c.id].t)
			if w.time >= 60.0 and floorf(w.time / 60.0) > floorf(t / 60.0):
				camp_seen[c.id] = {"up": true, "t": t}

func camp_up(camp_id: int) -> bool:
	if w.time < 60.0:
		return false
	return bool((camp_seen.get(camp_id, {"up": true}) as Dictionary).get("up", true))

func claim_camp(camp_id: int, hid: int, dur := 20.0) -> bool:
	var cl: Array = camp_claim.get(camp_id, [-1, 0.0])
	if int(cl[0]) != hid and int(cl[0]) >= 0 and w.time < float(cl[1]) and w.valid(int(cl[0])):
		return false
	camp_claim[camp_id] = [hid, w.time + dur]
	return true

func camp_claimed_by_other(camp_id: int, hid: int) -> bool:
	var cl: Array = camp_claim.get(camp_id, [-1, 0.0])
	return int(cl[0]) >= 0 and int(cl[0]) != hid and w.time < float(cl[1]) and w.valid(int(cl[0]))

# ---- Buildings ------------------------------------------------------------------------------------------------------

func tower(p_team: int, lane: String, tier: int) -> SimUnit:
	for u in w.units:
		if u.alive and u.team == p_team and u.kind == K.TOWER and u.building_lane == lane and u.lane_tier == tier:
			return u
	return null

## The outermost living tower of a team in a lane (or its next building toward the Ancient).
func front_tower(p_team: int, lane: String) -> SimUnit:
	for tier in [1, 2, 3]:
		var t := tower(p_team, lane, tier)
		if t != null:
			return t
	for u in w.units:
		if u.alive and u.team == p_team and u.is_building() and u.kind != K.FOUNTAIN and u.building_lane == lane:
			return u
	for u in w.units:
		if u.alive and u.team == p_team and (u.kind == K.TOWER and u.lane_tier == 4 or u.kind == K.ANCIENT):
			return u
	return null

func lane_of_point(p: Vector2) -> String:
	var best := "mid"
	var bd := INF
	for ln in ["top", "mid", "bot"]:
		var d := SimMap._polyline_distance(p, w.map.lane_path(ln, team))
		if d < bd:
			bd = d
			best = ln
	return best

# ---- Plans ----------------------------------------------------------------------------------------------------------

func _new_plan(kind: String, lane: String, target: int, pos: Vector2, dur: float, ping := false) -> Dictionary:
	var p := {"id": _plan_id, "kind": kind, "lane": lane, "target": target, "pos": pos, "members": {},
		"until": w.time + dur, "ping": ping, "t": w.time}
	_plan_id += 1
	plans.append(p)
	return p

func _plan_alive(p: Dictionary) -> bool:
	var t := w.get_unit(int(p.target))
	match String(p.kind):
		"gank":
			return t != null and t.alive and float(last_seen(t)[1]) < 8.0 \
				and (last_seen(t)[0] as Vector2).distance_to(p.pos) < (2600.0 if w.time < 600.0 else 3800.0)
		"push", "defend":
			return t == null or t.alive
	return true

## The plan a hero is part of (or {}).
func task_for(hid: int) -> Dictionary:
	var best := {}
	for p in plans:
		if (p.members as Dictionary).has(hid):
			if best.is_empty() or _plan_rank(String(p.kind)) > _plan_rank(String(best.kind)):
				best = p
	return best

static func _plan_rank(kind: String) -> int:
	return {"retreat": 5, "defend": 4, "gank": 3, "push": 2, "group": 1}.get(kind, 0)

func leave_plan(hid: int, plan_id := -1) -> void:
	for p in plans:
		if plan_id < 0 or int(p.id) == plan_id:
			(p.members as Dictionary).erase(hid)

## A bot's trip time to a point: walking (with a little for paths), or teleporting to the allied building nearest it
## (3 s channel plus the walk from there) when its TP is ready.
func eta(h: SimUnit, p: Vector2) -> Dictionary:
	var walk := h.pos.distance_to(p) * 1.25 / maxf(150.0, h.move_speed)
	var out := {"time": walk, "tp": false}
	if w.abilities.cast_error(h, "tp", -1, null, p) == "":
		var b := _nearest_building(p)
		if b != null:
			var tp_time := C.TP_CHANNEL + 1.0 + b.pos.distance_to(p) * 1.2 / maxf(150.0, h.move_speed)
			if tp_time + 4.0 < walk:
				out = {"time": tp_time, "tp": true, "building": b.id}
	return out

func _nearest_building(p: Vector2) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for b in w.units:
		if b.alive and b.team == team and b.is_building() and b.kind != K.FOUNTAIN:
			var d := b.pos.distance_to(p)
			if d < bd:
				bd = d
				best = b
	return best

# ---- Calls: defence -------------------------------------------------------------------------------------------------

func _call_defence() -> void:
	for b in w.units:
		if not b.alive or b.team != team or not b.is_building() or b.kind == K.FOUNTAIN or b.is_invulnerable():
			continue
		var heroes := 0
		var creeps := 0
		for u: SimUnit in w.query(b.pos, 1100.0):
			if not u.alive or u.team == team or u.team == C.NEUTRAL:
				continue
			if not w.vision.sees(team, u):
				continue
			if u.is_hero() and (u.atk_target == b.id or u.pos.distance_to(b.pos) < 500.0 and b.hp < b.max_hp * 0.97):
				heroes += 1
			elif u.is_lane_creep() and u.atk_target == b.id:
				creeps += 1
		if heroes == 0 and creeps < 3:
			continue
		# a creep push that one of ours already stands against needs nobody else, nor a fight our heroes there match
		var here := allies_near(b.pos, 1100.0).size()
		if heroes == 0 and here > 0 or heroes > 0 and here >= heroes:
			continue
		# outer towers early on: only the heroes of that lane and the roamer walk over; nobody teleports
		var early := w.time < 480.0 and b.kind == K.TOWER and b.lane_tier == 1
		var lane := b.building_lane if b.building_lane != "" else "mid"
		var existing := {}
		for p in plans:
			if p.kind == "defend" and int(p.target) == b.id:
				existing = p
		# give up an outer tower against a much bigger team; hold the base no matter what
		var deep := b.kind != K.TOWER or b.lane_tier >= 3
		if not deep and heroes >= allies_alive() + 2:
			continue
		var need := clampi(heroes + (1 if creeps >= 3 else 0), 1, 5) if not deep else 5
		if heroes == 0:
			need = 1 if b.hp < b.max_hp * 0.9 or deep else 0
		if need == 0:
			continue
		if existing.is_empty():
			existing = _new_plan("defend", lane, b.id, b.pos, 25.0)
			if heroes > 0:
				var first := _first_bot()
				if first != null and say(first, "They're hitting our %s %s. Defend!" % [lane_label(lane), _building_word(b)], "def_%d" % b.id, 40.0):
					w.ping(team, b.pos, first.id, b.id, "defend")
		existing.until = w.time + 12.0
		var have := (existing.members as Dictionary).size()
		if have >= need:
			continue
		# closest available bots by trip time
		var cands: Array = []
		for h in members():
			if not h.bot or not h.alive or (existing.members as Dictionary).has(h.id):
				continue
			var cur := task_for(h.id)
			if not cur.is_empty() and _plan_rank(String(cur.kind)) >= 4:
				continue
			if h.hp < h.max_hp * 0.35:
				continue
			if early and String(lane_of.get(h.id, "")) != lane and int(roles.get(h.id, 3)) != 4:
				continue
			var et_d := eta(h, b.pos)
			if early and bool(et_d.tp):
				continue
			cands.append([float(et_d.time), h])
		cands.sort_custom(func(a, c): return a[0] < c[0])
		for cd in cands:
			if have >= need:
				break
			if float(cd[0]) > (25.0 if deep else 18.0):
				break
			var h: SimUnit = cd[1]
			existing.members[h.id] = true
			have += 1
			if heroes > 0:
				var e := eta(h, b.pos)
				say(h, "Coming to defend (TP)." if e.tp else "Coming to defend, %d s." % ceili(float(e.time)),
					"defgo_%d_%d" % [h.id, b.id], 30.0)

func _building_word(b: SimUnit) -> String:
	match b.kind:
		K.TOWER:
			return "tower"
		K.BARRACKS:
			return "barracks"
		K.ANCIENT:
			return "Throne"
	return "base"

func _first_bot() -> SimUnit:
	for h in members():
		if h.bot and h.alive:
			return h
	for h in members():
		if h.bot:
			return h
	return null

# ---- Calls: ganks ---------------------------------------------------------------------------------------------------

## An enemy hero we see that we can likely kill before help comes: low, alone, or caught on our side. The bots in
## reach go for it (and say so); during the laning phase only roamers, mid after level 6 and its lane partner go.
func _call_ganks() -> void:
	for e in w.heroes:
		if e.team == team or not e.alive or not w.vision.sees(team, e):
			continue
		var busy := false
		for p in plans:
			if p.kind == "gank" and int(p.target) == e.id:
				busy = true
		if busy:
			continue
		var helpers := enemies_near(e.pos, 1400.0, 3.0)
		var laning := w.time < 600.0
		if w.time < 120.0:
			continue
		var cands: Array = []
		for h in members():
			if not h.bot or not h.alive or h.hp < h.max_hp * 0.45:
				continue
			var cur := task_for(h.id)
			if not cur.is_empty() and _plan_rank(String(cur.kind)) >= 3:
				continue
			if not _may_roam(h, e):
				continue
			var et := eta(h, e.pos)
			if float(et.time) > (14.0 if et.tp else 10.0):
				continue
			cands.append([float(et.time), h])
		if cands.is_empty():
			continue
		cands.sort_custom(func(a, c): return a[0] < c[0])
		if laning:
			cands = cands.filter(func(cd): return int(roles.get((cd[1] as SimUnit).id, 3)) != 1)
			if cands.is_empty():
				continue
		var ours := 0.0
		var chosen: Array[SimUnit] = []
		for cd in cands:
			if chosen.size() >= 3:
				break
			chosen.append(cd[1])
			ours += KITS.power(w, cd[1], e)
		var theirs := 0.0
		for x in helpers:
			theirs += KITS.power(w, x, chosen[0])
		var low := e.hp < e.max_hp * 0.4
		var alone := helpers.size() <= 1
		var tower_safe := not _under_enemy_tower(e.pos)
		var ratio := ours / maxf(1.0, theirs)
		# during the laning phase a gank is a rotation: someone from another lane has to come
		var rotating := false
		for h in chosen:
			if String(lane_of.get(h.id, "")) != lane_of_point(e.pos) or int(roles.get(h.id, 3)) == 4:
				rotating = true
		if laning and (not rotating or chosen.size() < 2 and not low):
			continue
		if not ((low and ratio > 1.1) or (alone and ratio > 1.6 and chosen.size() >= 2) or (ratio > 2.2)) or not (tower_safe or e.hp < e.max_hp * 0.2):
			continue
		var p := _new_plan("gank", lane_of_point(e.pos), e.id, e.pos, 22.0)
		for h in chosen:
			p.members[h.id] = true
		var lead: SimUnit = chosen[0]
		var names := []
		for i in range(1, chosen.size()):
			names.append(_name_of(chosen[i]))
		var why := "is low (%d%%)" % roundi(e.hp / e.max_hp * 100.0) if low else "is alone"
		var ln := lane_label(lane_of_point(e.pos))
		var text := "Their %s %s in the %s lane. Going for the kill" % [hero_label(e), why, ln]
		text += (", %s come too." % " and ".join(names)) if not names.is_empty() else "."
		if say(lead, text, "gank_%d" % e.id, 25.0):
			w.ping(team, e.pos, lead.id, e.id, "attack")
		for i in range(1, chosen.size()):
			var et2 := eta(chosen[i], e.pos)
			say(chosen[i], "Coming (TP)." if et2.tp else "On my way.", "gank_go_%d_%d" % [chosen[i].id, e.id], 25.0)

func _may_roam(h: SimUnit, e: SimUnit) -> bool:
	var r := int(roles.get(h.id, 3))
	if w.time >= 600.0:
		return true
	if String(lane_of.get(h.id, "")) == lane_of_point(e.pos):
		return true                          # it is in our lane anyway
	if r == 4:
		return true
	if r == 2 and h.level >= 6:
		return true
	return false

func _under_enemy_tower(p: Vector2) -> bool:
	for u: SimUnit in w.query(p, 1000.0):
		if u.alive and u.team != team and u.kind == K.TOWER and p.distance_to(u.pos) <= u.attack_range + u.hull + 60.0:
			return true
	return false

# ---- Calls: push ----------------------------------------------------------------------------------------------------

func _call_push() -> void:
	for p in plans:
		if p.kind == "push" and not bool(p.ping):
			return
	var ea := enemies_alive()
	var aa := allies_alive()
	var dead := 0
	for e in w.heroes:
		if e.team != team and not e.alive and e.respawn_at - w.time > 15.0:
			dead += 1
	var late := w.time > 25.0 * 60.0
	var ratio := _team_power_ratio() if w.time > 1200.0 else 1.0
	var want := (dead >= 2 and aa >= 2) or (aa - ea >= 2) or (dead >= 1 and aa >= ea and ratio > 1.1 and w.time > 900.0) 		or (late and aa >= ea and aa >= 3 and ratio > 0.95)
	if not want or w.time < 300.0:
		return
	# the lane whose enemy front tower is weakest and closest to our creeps
	var best := ""
	var bs := -INF
	var target: SimUnit = null
	for ln in ["top", "mid", "bot"]:
		var t := front_tower(1 - team, ln)
		if t == null or t.is_invulnerable() and t.kind != K.TOWER:
			continue
		var s := 1.0 - t.hp / t.max_hp - float(t.lane_tier) * 0.15
		var ours := 0
		for u: SimUnit in w.query(t.pos, 1600.0):
			if u.alive and u.team == team and u.is_lane_creep():
				ours += 1
		s += ours * 0.08
		if s > bs:
			bs = s
			best = ln
			target = t
	if target == null:
		return
	var p := _new_plan("push", best, target.id, target.pos, 45.0 if not late else 60.0)
	for h in members():
		if h.bot and h.alive and h.hp > h.max_hp * 0.4:
			var cur := task_for(h.id)
			if cur.is_empty() or _plan_rank(String(cur.kind)) < 2:
				if float(eta(h, target.pos).time) < 30.0:
					p.members[h.id] = true
	if (p.members as Dictionary).size() < mini(2, aa):
		plans.erase(p)
		return
	var lead := w.get_unit(int((p.members as Dictionary).keys()[0]))
	var why := "%d of them are dead" % dead if dead >= 2 else ("we have more heroes up" if aa - ea >= 2 else "we're stronger now")
	say(lead, "%s. Let's push %s and take their %s." % [why.left(1).to_upper() + why.substr(1), lane_label(best), _building_word(target)],
		"push_%d" % target.id, 45.0)

func _team_power_ratio() -> float:
	var ours := 0.0
	var theirs := 0.0
	var ms := members()
	for h in w.heroes:
		if not h.alive:
			continue
		var vs: SimUnit = null
		for o in w.heroes:
			if o.team != h.team:
				vs = o
				break
		if h.team == team:
			ours += KITS.power(w, h, vs)
		else:
			theirs += KITS.power(w, h, ms[0] if not ms.is_empty() else null)
	return ours / maxf(1.0, theirs)

# ---- Calls: missing heroes, danger, Fortify -------------------------------------------------------------------------

func _call_missing() -> void:
	if w.time > 600.0 or w.time < 30.0:
		return
	for e in w.heroes:
		if e.team == team or not e.alive:
			continue
		var s: Dictionary = seen.get(e.id, {})
		if s.is_empty():
			continue
		var gone := w.time - float(s.t)
		if gone < 10.0 or gone > 13.0:
			continue
		if w.time - float(_missing_called.get(e.id, C.LONG_AGO)) < 60.0:
			continue
		var ln := lane_of_point(s.pos)
		# called by the bot who was laning against it
		for h in members():
			if h.bot and h.alive and String(lane_of.get(h.id, "")) == ln and h.pos.distance_to(s.pos) < 2500.0:
				_missing_called[e.id] = w.time
				say(h, "%s is missing from %s! Careful." % [hero_label(e), lane_label(ln)], "miss_%d" % e.id, 60.0)
				break

## Four or more enemies seen together near one of ours: everyone near backs off unless we are stronger there.
func _call_danger() -> void:
	if w.time - _fight_called < 20.0:
		return
	for h in members():
		if not h.alive:
			continue
		var es := enemies_near(h.pos, 1500.0, 2.0)
		if es.size() < 3 or w.time < 300.0:
			continue
		var ours := 0.0
		for a in allies_near(h.pos, 1500.0):
			ours += KITS.power(w, a, es[0])
		var theirs := 0.0
		for e in es:
			theirs += KITS.power(w, e, h)
		if theirs > ours * 1.6:
			_fight_called = w.time
			var p := _new_plan("retreat", lane_of_point(h.pos), -1, h.pos, 6.0)
			for a in allies_near(h.pos, 2200.0):
				if a.bot:
					p.members[a.id] = true
			var who := h if h.bot else _first_bot()
			if who != null and say(who, "%d of them together near %s! Back off." % [es.size(), lane_label(lane_of_point(h.pos))], "danger", 20.0):
				w.ping(team, es[0].pos, who.id, -1, "danger")
			return

func _glyph() -> void:
	if w.time < w.glyph_ready_at[team]:
		return
	for b in w.units:
		if not b.alive or b.team != team or b.kind != K.TOWER or b.is_invulnerable():
			continue
		if b.hp > b.max_hp * 0.3:
			continue
		var attackers := 0
		for u: SimUnit in w.query(b.pos, 900.0):
			if u.alive and u.team != team and u.team != C.NEUTRAL and u.atk_target == b.id:
				attackers += 1
		var help := false
		for p in plans:
			if p.kind == "defend" and int(p.target) == b.id and not (p.members as Dictionary).is_empty():
				help = true
		if attackers >= 3 and help:
			# only a bot team uses Fortify on its own: a player's team leaves the button to the player
			for h in members():
				if not h.bot:
					return
			w.glyph(team)
			return

# ---- Pings ------------------------------------------------------------------------------------------------------------

func on_ping(pg: Dictionary) -> void:
	var from := w.get_unit(int(pg.from))
	if from != null and from.bot:
		return
	_pending_pings.append(pg)

## A player's ping: each bot weighs it (dead? health? mana? TP? how far? how many enemies there? its own job?) and
## agrees or says why not. Not every bot agrees every time.
func _answer_ping(pg: Dictionary) -> void:
	var t := w.get_unit(int(pg.target))
	var pos: Vector2 = pg.pos
	var kind := String(pg.kind)
	var plan_kind := ""
	var target_id := -1
	if kind == "danger":
		var p := _new_plan("retreat", lane_of_point(pos), -1, pos, 8.0, true)
		var any := false
		for h in members():
			if h.bot and h.alive and h.pos.distance_to(pos) < 2500.0:
				p.members[h.id] = true
				for q in plans:
					if q != p and q.kind in ["gank", "push"] and (q.members as Dictionary).has(h.id):
						(q.members as Dictionary).erase(h.id)
				if not any:
					say(h, "Okay, backing off.", "ping_ok_%d" % pg.id, 0.0, true)
					any = true
		return
	if kind == "attack" and t != null and t.is_hero():
		plan_kind = "gank"
		target_id = t.id
	elif kind == "attack" and t != null and t.is_building():
		plan_kind = "push"
		target_id = t.id
	elif kind == "defend" and t != null and t.is_building():
		plan_kind = "defend"
		target_id = t.id
	elif kind == "defend" and t != null and t.is_hero():
		plan_kind = "group"
		target_id = t.id
	else:
		# a ground ping: what is it about? an enemy building, one of ours, an enemy hero seen there, or "come here"
		var eb := _building_near(pos, 1 - team, 1100.0)
		var ob := _building_near(pos, team, 900.0)
		var eh: SimUnit = null
		for e in enemies_near(pos, 900.0, 3.0):
			eh = e
		if eh != null:
			plan_kind = "gank"
			target_id = eh.id
		elif eb != null:
			plan_kind = "push"
			target_id = eb.id
		elif ob != null:
			plan_kind = "defend"
			target_id = ob.id
		else:
			plan_kind = "group"
	var tu := w.get_unit(target_id)
	var where: Vector2 = tu.pos if tu != null and (tu.team == team or w.vision.sees(team, tu)) else pos
	var lane := tu.building_lane if tu != null and tu.is_building() and tu.building_lane != "" else lane_of_point(where)
	var plan := _new_plan(plan_kind, lane, target_id, where, 35.0 if plan_kind != "group" else 25.0, true)
	var answered := 0
	var yes := 0
	# the bots who would go, quickest first; a gank or a gathering needs two or three, a push in the late game
	# everyone, defending a building as many as the threat calls for
	var replies: Array = []
	for h in members():
		if h.bot:
			replies.append([h, _ping_reply(h, plan, tu), float(eta(h, where).time)])
	replies.sort_custom(func(a, b): return a[2] < b[2])
	var cap := 3 if plan_kind in ["gank", "group"] else (5 if plan_kind == "push" and w.time > 1500.0 else 4)
	for rp in replies:
		var h: SimUnit = rp[0]
		var r: Dictionary = rp[1]
		if bool(r.ok) and yes >= cap:
			r = {"ok": false, "text": "Enough of us are going, I'll hold my lane." if h.pos.distance_to(where) < 5000.0 else ""}
		if bool(r.ok):
			plan.members[h.id] = true
			yes += 1
		# everyone answers a ping aimed at their area; others mostly only when they come
		var near := h.alive and h.pos.distance_to(where) < 3500.0
		if bool(r.ok) or near or answered < 2:
			if String(r.text) != "":
				say(h, String(r.text), "ping_%d_%d" % [pg.id, h.id], 0.0, true)
				answered += 1
	if yes == 0:
		plans.erase(plan)

func _ping_reply(h: SimUnit, plan: Dictionary, tu: SimUnit) -> Dictionary:
	var kind := String(plan.kind)
	var where: Vector2 = plan.pos
	if not h.alive:
		var left := ceili(maxf(0.0, h.respawn_at - w.time))
		return {"ok": false, "text": "I'm dead, back in %d s." % left}
	if h.hp < h.max_hp * 0.3:
		return {"ok": false, "text": "I'm low on health (%d%%), healing first." % roundi(h.hp / h.max_hp * 100.0)}
	var cur := task_for(h.id)
	if not cur.is_empty() and cur.kind == "defend" and kind != "defend" and int(cur.target) != int(plan.target):
		return {"ok": false, "text": "I'm defending our %s tower." % lane_label(String(cur.lane))}
	var e := eta(h, where)
	var far := float(e.time) > (22.0 if kind == "defend" else 18.0)
	if far:
		var tp_cd := w.abilities.cooldown_left(h, "tp")
		if h.tp_charges <= 0:
			return {"ok": false, "text": "I have no TP and it's too far (%d s away)." % ceili(float(e.time))}
		if tp_cd > 0.0:
			return {"ok": false, "text": "My TP is on cooldown (%d s) and it's too far." % ceili(tp_cd)}
		if h.mana < C.TP_MANA:
			return {"ok": false, "text": "Not enough mana to teleport."}
		return {"ok": false, "text": "Too far (%d s away) and no tower of ours near there to teleport to." % ceili(float(e.time))}
	if kind == "gank" and tu != null:
		var ours := KITS.power(w, h, tu)
		for a in allies_near(where, 1800.0):
			if a != h:
				ours += KITS.power(w, a, tu)
		var theirs := 0.0
		var n := 0
		for x in enemies_near(where, 1400.0, 4.0):
			theirs += KITS.power(w, x, h)
			n += 1
		if n >= 2 and theirs > ours * 1.5:
			return {"ok": false, "text": "Too risky, I see %d of them there." % n}
		if h.mana < h.max_mana * 0.25 and KITS.burst(w, h, tu) <= 0.0:
			return {"ok": false, "text": "I'm out of mana, I'd be no help."}
		var ult := KITS.ultimate(h)
		if ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) > 20.0 and rng.randf() < 0.35:
			return {"ok": false, "text": "My ultimate is on cooldown (%d s). Wait for it." % ceili(w.abilities.cooldown_left(h, ult))}
	if kind == "push":
		if enemies_alive() > allies_alive() + 1:
			return {"ok": false, "text": "They have more heroes up. Too risky to push now."}
	# the carry keeps farming early unless it is close by
	var role := int(roles.get(h.id, 3))
	if role == 1 and w.time < 900.0 and float(e.time) > 10.0 and kind != "defend" and rng.randf() < 0.6:
		return {"ok": false, "text": "I need to farm my lane right now, sorry."}
	# sometimes a bot simply prefers what it is doing (not every ping is agreed to)
	if kind in ["gank", "push", "group"] and rng.randf() < 0.12:
		return {"ok": false, "text": "I'd rather keep farming, the timing isn't good for me."}
	if bool(e.tp):
		return {"ok": true, "text": "Coming, I'll teleport."}
	var secs := ceili(float(e.time))
	match kind:
		"push":
			return {"ok": true, "text": "Okay, pushing %s with you." % lane_label(String(plan.lane)) if secs < 6 else "Okay, pushing %s. %d s away." % [lane_label(String(plan.lane)), secs]}
		"defend":
			return {"ok": true, "text": "Coming to defend." if secs < 6 else "Coming to defend, %d s." % secs}
		"gank":
			return {"ok": true, "text": "On my way." if secs < 6 else "On my way, %d s." % secs}
	return {"ok": true, "text": "Coming." if secs < 6 else "Coming, %d s." % secs}

func _building_near(p: Vector2, p_team: int, r: float) -> SimUnit:
	var best: SimUnit = null
	var bd := r
	for b in w.units:
		if b.alive and b.team == p_team and b.is_building() and b.kind != K.FOUNTAIN:
			var d := b.pos.distance_to(p)
			if d < bd:
				bd = d
				best = b
	return best

# ---- Player chat -------------------------------------------------------------------------------------------------------

## A few plain words from the player are understood: "push top", "defend mid", "gank" / "kill <hero>", "back" /
## "retreat", "group" / "come", "stack", "farm".
func on_player_chat(h: SimUnit, text: String) -> void:
	var t := text.to_lower()
	var lane := ""
	for ln in ["top", "mid", "bot"]:
		if t.contains(ln):
			lane = ln
	if t.contains("bottom"):
		lane = "bot"
	if t.contains("back") or t.contains("retreat") or t.contains("run"):
		on_ping({"id": -_plan_id, "team": team, "pos": h.pos, "kind": "danger", "target": -1, "from": h.id, "t": w.time})
		return
	if t.contains("push") and lane != "":
		var tw := front_tower(1 - team, lane)
		if tw != null:
			on_ping({"id": -_plan_id, "team": team, "pos": tw.pos, "kind": "attack", "target": tw.id, "from": h.id, "t": w.time})
		return
	if t.contains("def") and lane != "":
		var ot := front_tower(team, lane)
		if ot != null:
			on_ping({"id": -_plan_id, "team": team, "pos": ot.pos, "kind": "defend", "target": ot.id, "from": h.id, "t": w.time})
		return
	if t.contains("gank") or t.contains("kill"):
		var best: SimUnit = null
		for e in w.heroes:
			if e.team != team and e.alive and float(last_seen(e)[1]) < 6.0:
				if t.contains(hero_label(e).to_lower()) or best == null:
					best = e
		if best != null:
			on_ping({"id": -_plan_id, "team": team, "pos": best.pos, "kind": "attack", "target": best.id, "from": h.id, "t": w.time})
		else:
			var b := _first_bot()
			if b != null:
				say(b, "I don't see anyone to gank right now.", "nogank", 10.0, true)
		return
	if t.contains("group") or t.contains("come") or t.contains("help"):
		on_ping({"id": -_plan_id, "team": team, "pos": h.pos, "kind": "defend", "target": h.id, "from": h.id, "t": w.time})

# ---- Chat ---------------------------------------------------------------------------------------------------------------

## A bot says something in team chat. Lines are rate limited so chat stays readable: one line per key per `every`
## seconds, a bot at most every 6 s and the team at most every 2 s (`urgent` lines, such as ping replies, skip the
## last two limits).
func say(h: SimUnit, text: String, key := "", every := 30.0, urgent := false) -> bool:
	if h == null or text == "":
		return false
	if key != "" and w.time - float(_said.get(key, C.LONG_AGO)) < every:
		return false
	if not urgent:
		if w.time - _last_chat < 2.0 or w.time - float(_bot_chat.get(h.id, C.LONG_AGO)) < 6.0:
			return false
	if key != "":
		_said[key] = w.time
	_last_chat = w.time
	_bot_chat[h.id] = w.time
	w.chat(team, h.id, text)
	return true

# ---- End of a match: learning -------------------------------------------------------------------------------------

## Scores what each bot did this match into the bots' memory (builds, lane matchups) and records the game. Called
## once when the Throne falls.
static func match_over(world: SimWorld) -> void:
	if not BotMemory.active or world == null:
		return
	var won_teams := [world.winner]
	var lesson := ""
	var best_nw := 1.0
	for h in world.heroes:
		best_nw = maxf(best_nw, float(h.networth()))
	var bot_side_won := false
	for b in world.bots:
		var h: SimUnit = b.hero()
		if h == null:
			continue
		var won := h.team in won_teams
		bot_side_won = bot_side_won or won
		var reward := (0.6 if won else 0.0) + 0.4 * clampf(float(h.networth()) / best_nw, 0.0, 1.0)
		BotMemory.reward_build(KITS.build_key(b.kit, b.role), b.build_idx, reward, h.team)
		if b.lane_foe != "":
			BotMemory.note_lane(b.kit, b.lane_foe, b.lane_kills, b.lane_deaths, h.team)
		if lesson == "" and h.deaths >= 8:
			lesson = "%s died %d times; it will retreat sooner." % [b.name, h.deaths]
	if lesson == "":
		lesson = "Played a %d-minute game (%s won)." % [int(world.time / 60.0), C.TEAM_NAMES[world.winner] if world.winner >= 0 else "nobody"]
	BotMemory.end_match(bot_side_won, lesson)
