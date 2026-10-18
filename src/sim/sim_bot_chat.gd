class_name SimBotChat
extends RefCounted
## Bots that talk like players (run 2026-10-18 h; the owner: "bots really feel like real people", criticizing anyone
## who fails in lane, dies too much or has no farm, mocking missed skillshots, all chatting a killed hero, Gen Z slang
## and trash talk). The lines are the owner's bot_trashtalk_chat_lines.json and more (tools/bot_chat.py ->
## BotChatLines); this decides who says what, when, and to whom:
##   * all chat (both teams read it): a kill on an enemy hero, first blood, a streak, a shutdown, a dodged skillshot,
##     a hero killed by creeps or a tower, a buyback, an enemy who barely got away, a won team fight, a tower or the
##     last barracks taken, the greeting, the end;
##   * team chat: an ally (bot or player, no one is spared) dying again and again, failing its lane or short of farm
##     (a review every couple of minutes), an ally standing by while a bot died, excuses for its own death, praise,
##     a lost fight, a tower lost;
##   * replies: a line the player types (or another bot's trash talk) can get a comeback, a moment later.
## Each bot has its own voice, from its name: how much Filipino and Taglish it uses, how often it talks trash and how
## rough it gets. Lines are timed like typing (0.6-2.5 s after the moment), limited so chat stays readable, and not
## repeated soon. Everything is drawn from the world's own seeded generator here, so every multiplayer peer sees
## the same lines.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const L = preload("res://src/sim/bot_chat_lines.gd")

## Lines that need nothing filled in may be said anywhere; a line with {victim} etc. needs that name.
const KEYS := ["victim", "killer", "ally", "hero", "lane", "item", "n"]

var w: SimWorld
var _rng := RandomNumberGenerator.new()
var _queue: Array = []                      # [{at, team, u, text, all, reply_to}]
var _voice := {}                            # hero id -> {tl, salt, rough}
var _bot_last := {}                         # hero id -> last line time
var _last_all := C.LONG_AGO
var _last_team := [C.LONG_AGO, C.LONG_AGO]
var _recent := {}                           # category -> the line indices said lately
var _kills := []                            # [time, killer team] of recent hero kills (team fights)
var _fight_said := C.LONG_AGO
var _next_review := 240.0
var _greeted := false
var _mega_said := [false, false]
var said := 0                               # report counter (tests, bot games)

func _init(world: SimWorld = null) -> void:
	w = world
	if w != null:
		_rng.seed = w.rng.seed ^ 0x5ca7

# ---- Voices ------------------------------------------------------------------------------------------------------------

## A bot's voice, fixed by its name: tl (share of Filipino and Taglish lines), salt (how often it talks), rough (how
## often a line comes from the rough Filipino set).
func voice(h: SimUnit) -> Dictionary:
	if _voice.has(h.id):
		return _voice[h.id]
	var hh := absi(hash(h.player_label() + String(h.def.id)))
	var kind := hh % 3                      # 0 Pinoy, 1 Taglish, 2 English
	var v := {"tl": [0.75, 0.45, 0.08][kind], "salt": 0.55 + float((hh / 3) % 45) / 100.0,
		"rough": [0.35, 0.2, 0.05][kind]}
	_voice[h.id] = v
	return v

func _bot_of(h: SimUnit):
	if h == null or not h.bot:
		return null
	for b in w.bots:
		if b.hero_id == h.id:
			return b
	return null

## Bots of `team` (alive or dead) other than `but`.
func _bots(team: int, but: SimUnit = null) -> Array:
	var out: Array = []
	for b in w.bots:
		var h: SimUnit = b.hero()
		if h != null and h.team == team and h != but and not b.passive and not b.human:
			out.append(h)
	return out

func _pick_from(list: Array) -> SimUnit:
	if list.is_empty():
		return null
	return list[_rng.randi_range(0, list.size() - 1)]

# ---- Lines ------------------------------------------------------------------------------------------------------------

## A line of `cat` for `h`'s voice with the names filled in, or "" (none fits).
func line(h: SimUnit, cat: String, fill := {}) -> String:
	var lines: Array = L.LINES.get(cat, [])
	if lines.is_empty():
		return ""
	var v := voice(h)
	var want_tl: bool = _rng.randf() < float(v.tl)
	var recent: Array = _recent.get(cat, [])
	for attempt in 14:
		var i := _rng.randi_range(0, lines.size() - 1)
		var entry: Array = lines[i]
		var text := String(entry[0])
		if i in recent and attempt < 12:
			continue
		if attempt < 10 and (String(entry[1]) == "tl") != want_tl:
			continue
		var ok := true
		for k in KEYS:
			if text.contains("{" + k + "}"):
				if not fill.has(k):
					ok = false
					break
				text = text.replace("{" + k + "}", str(fill[k]))
		if not ok:
			continue
		recent.append(i)
		while recent.size() > mini(40, lines.size() / 2):
			recent.pop_front()
		_recent[cat] = recent
		return text
	return ""

## Queue a line from `h` after a typing delay. all: all chat. Returns whether it was queued.
func say(h: SimUnit, cat: String, all: bool, fill := {}, chance := 1.0, delay := -1.0) -> bool:
	if h == null or not h.bot:
		return false
	var b = _bot_of(h)
	if b == null or b.passive or b.human:
		return false
	var v := voice(h)
	if _rng.randf() > chance * (0.55 + float(v.salt) * 0.6):
		return false
	if w.time - float(_bot_last.get(h.id, C.LONG_AGO)) < 4.0:
		return false
	for q in _queue:
		if int(q.u) == h.id:
			return false                    # one line typing at a time
	# the rough Filipino set now and then in place of the moment's line (a Pinoy voice swears more)
	var c := cat
	if all and _rng.randf() < float(v.rough) * 0.35 and cat in ["killed_enemy_all_chat", "missed_skillshot_and_whiffs",
			"ragebait_and_trolling", "casual_short_mockery", "responses_and_comebacks"]:
		c = "tagalog_trashtalk_and_kanal_humor"
	var text := line(h, c, fill)
	if text == "":
		return false
	var at := w.time + (delay if delay >= 0.0 else _rng.randf_range(0.6, 2.2) + float(text.length()) * 0.03)
	_queue.append({"at": at, "team": h.team, "u": h.id, "text": text, "all": all, "cat": cat})
	_bot_last[h.id] = at
	return true

## Post what is due (all chat at most every 1.5 s, a team's chat every 1.2 s).
func _flush() -> void:
	var i := 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		if w.time < float(q.at):
			i += 1
			continue
		var h := w.get_unit(int(q.u))
		if h == null:
			_queue.remove_at(i)
			continue
		if bool(q.all) and w.time - _last_all < 1.5 or not bool(q.all) and w.time - float(_last_team[int(q.team)]) < 1.2:
			q.at = float(q.at) + 0.5
			i += 1
			continue
		_queue.remove_at(i)
		if bool(q.all):
			_last_all = w.time
		else:
			_last_team[int(q.team)] = w.time
		w.chat(int(q.team), h.id, String(q.text), bool(q.all), true)
		said += 1
		# trash talk in all chat sometimes draws a pile-on from a teammate or a comeback from the other side
		if bool(q.all) and String(q.cat) != "responses_and_comebacks" and String(q.cat) != "game_start":
			var r := _rng.randf()
			if r < 0.18:
				say(_pick_from(_bots(1 - h.team)), "responses_and_comebacks", true, {}, 1.0)
			elif r < 0.3:
				say(_pick_from(_bots(h.team, h)), "casual_short_mockery" if _rng.randf() < 0.6 else "gen_z_brainrot_and_slang", true, {}, 1.0)

func label(u: SimUnit) -> String:
	if u == null:
		return ""
	return SimTeamAI.hero_label(u)

# ---- Every step --------------------------------------------------------------------------------------------------------

func tick() -> void:
	if w.bots.is_empty():
		return
	if not _greeted and w.time >= -50.0:
		_greeted = true
		for team in [C.DAWN, C.DUSK]:
			for h in _bots(team):
				say(h, "game_start", _rng.randf() < 0.6, {}, 0.4, _rng.randf_range(0.5, 6.0))
	for e in w.events:
		match String(e.t):
			"hero_kill":
				_on_kill(e)
			"skill_miss":
				_on_miss(e)
			"death":
				_on_death(e)
			"buyback":
				var bh := w.get_unit(int(e.u))
				if bh != null:
					say(_pick_from(_bots(1 - bh.team)), "buyback", true, {}, 0.5)
			"deny":
				var dh := w.get_unit(int(e.u))
				var dt := w.get_unit(int(e.get("target", -1)))
				if dh != null and dt != null and (dt.is_hero() or _rng.randf() < 0.03):
					say(dh, "denied", true, {}, 0.6 if dt.is_hero() else 0.5)
			"tp_end":
				_on_escape(e)
			"chat":
				_on_chat(e)
			"victory":
				_on_end(int(e.team))
	if w.time >= _next_review:
		_next_review = w.time + _rng.randf_range(100.0, 170.0)
		_review()
	_flush()

# ---- Moments -----------------------------------------------------------------------------------------------------------

func _on_kill(e: Dictionary) -> void:
	var victim := w.get_unit(int(e.victim))
	if victim == null:
		return
	var killer := w.get_unit(int(e.u))
	_kills.append([w.time, 1 - victim.team])
	while not _kills.is_empty() and w.time - float(_kills[0][0]) > 15.0:
		_kills.pop_front()
	var fill := {"victim": label(victim), "n": victim.deaths}
	if killer == null:
		# creeps, a tower or a camp did it
		say(_pick_from(_bots(1 - victim.team)), "died_to_creeps_or_tower", true, fill, 0.7)
	elif bool(e.get("first_blood", false)):
		if not say(killer, "first_blood", true, fill, 1.0):
			say(_pick_from(_bots(killer.team, killer)), "first_blood", true, fill, 0.7)
	elif int(e.get("ended_streak", 0)) >= 3:
		say(killer, "shutdown", true, fill, 0.9)
	elif int(e.get("streak", 0)) >= 3 and _rng.randf() < 0.5:
		say(killer, "killing_spree", true, {"n": int(e.streak)}, 0.8)
	else:
		# the times this killer got this victim
		var times := int(killer.get_meta("kills_on_%d" % victim.id, 0)) + 1
		killer.set_meta("kills_on_%d" % victim.id, times)
		if times >= 2:
			fill["n"] = times                  # "that's 3 for me" (lines with {n} wait for a second kill)
		else:
			fill.erase("n")
		say(killer, "killed_enemy_all_chat", true, fill, 0.55)
	# the killer's teammates: praise in team chat
	if killer != null:
		say(_pick_from(_bots(killer.team, killer)), "ally_praise", false, {"ally": label(killer)}, 0.2)
	# the victim: an excuse; its teammates: on its deaths, or on the ally who stood by
	say(victim, "own_death_excuses", _rng.randf() < 0.2, {}, 0.3)
	var mates := _bots(victim.team, victim)
	var rough_record: bool = victim.deaths >= 4 and float(victim.deaths) >= float(victim.kills) + float(victim.assists) * 0.5 + 3.0
	if rough_record:
		say(_pick_from(mates), "dying_too_much_and_feeding", false, {"ally": label(victim), "n": victim.deaths}, 0.55)
	elif victim.bot:
		# an ally close by who did not help: it gets blamed
		var near: SimUnit = null
		for a in w.heroes:
			if a.team == victim.team and a != victim and a.alive and a.pos.distance_to(victim.pos) < 1800.0:
				near = a
		if near != null:
			say(victim, "teammate_roast_and_blame", false, {"ally": label(near)}, 0.35)
	# a team fight: three or more kills for one side within 15 s and at most one back
	if w.time - _fight_said > 30.0:
		var by := [0, 0]
		for k in _kills:
			by[int(k[1])] += 1
		for team in [C.DAWN, C.DUSK]:
			if by[team] >= 3 and by[1 - team] <= 1:
				_fight_said = w.time
				say(_pick_from(_bots(team)), "teamfight_won", true, {"n": by[team]}, 1.0)
				say(_pick_from(_bots(1 - team)), "teamfight_lost", false, {}, 0.8)

func _on_miss(e: Dictionary) -> void:
	var caster := w.get_unit(int(e.u))
	var dodger := w.get_unit(int(e.get("near", -1)))
	if caster == null or dodger == null:
		return
	if not say(dodger, "missed_skillshot_and_whiffs", true, {"hero": label(caster)}, 0.7):
		say(_pick_from(_bots(dodger.team, dodger)), "casual_short_mockery", true, {}, 0.3)
	# the caster's own team is not kinder
	say(_pick_from(_bots(caster.team, caster)), "missed_skillshot_and_whiffs", false, {"hero": label(caster)}, 0.12)

func _on_death(e: Dictionary) -> void:
	var u := w.get_unit(int(e.u))
	if u == null or not u.is_building():
		return
	var lane := SimTeamAI.lane_label(u.building_lane) if u.building_lane != "" else "base"
	if u.kind == K.TOWER:
		say(_pick_from(_bots(1 - u.team)), "tower_destroyed", _rng.randf() < 0.5, {"lane": lane}, 0.45)
		say(_pick_from(_bots(u.team)), "tower_lost", false, {"lane": lane}, 0.4)
	elif u.kind == K.BARRACKS and w.all_rax_dead(u.team) and not _mega_said[u.team]:
		_mega_said[u.team] = true
		say(_pick_from(_bots(1 - u.team)), "megas_and_base", true, {}, 1.0)
		say(_pick_from(_bots(u.team)), "tower_lost", false, {"lane": lane}, 0.8)

## A hero teleported out with little health while an enemy bot was close: it got away.
func _on_escape(e: Dictionary) -> void:
	var h := w.get_unit(int(e.u))
	if h == null or h.hp > h.max_hp * 0.25:
		return
	var from: Vector2 = e.get("from", h.pos)
	for f in _bots(1 - h.team):
		if f.alive and f.pos.distance_to(from) < 1400.0:
			say(f, "enemy_escaped", true, {"victim": label(h)}, 0.6)
			return

## The player's lines (and another bot's trash talk) can get a comeback.
func _on_chat(e: Dictionary) -> void:
	var u := w.get_unit(int(e.u))
	if u == null or u.bot or bool(e.get("bot_line", false)):
		return                                 # bots' own lines draw replies in _flush
	var text := String(e.text).to_lower()
	var rude := false
	for word in ["noob", "bad", "trash", "report", "ez", "gg", "lol", "bot", "stfu", "?", "bobo", "tanga", "gago", "ulol",
			"pota", "tangina", "weak", "feed", "noob", "lmao", "cry", "mad", "loser", "ff"]:
		if text.contains(word):
			rude = true
			break
	if bool(e.get("all", false)):
		# the other team answers (and sometimes its own team laughs along)
		if not say(_pick_from(_bots(1 - u.team)), "responses_and_comebacks", true, {}, 0.85 if rude else 0.45):
			say(_pick_from(_bots(1 - u.team)), "gen_z_brainrot_and_slang", true, {}, 0.4)
		say(_pick_from(_bots(u.team)), "casual_short_mockery", true, {}, 0.15)
	elif rude:
		say(_pick_from(_bots(u.team, u)), "responses_and_comebacks", false, {}, 0.5)

## Every couple of minutes each team looks at itself (the player too): the one furthest behind on farm hears about it,
## and the other team mocks the poorest of its enemies now and then; a teammate with a terrible record too.
func _review() -> void:
	if w.time < 300.0:
		return
	for team in [C.DAWN, C.DUSK]:
		var mates: Array = w.heroes.filter(func(x): return x.team == team)
		if mates.is_empty():
			continue
		var avg := 0.0
		for m in mates:
			avg += float(m.networth())
		avg /= float(mates.size())
		var worst: SimUnit = null
		for m in mates:
			if worst == null or m.networth() < worst.networth():
				worst = m
		if worst != null and float(worst.networth()) < avg * 0.62:
			var fill := {"ally": label(worst), "n": worst.last_hits, "item": _missing_item(worst), "lane": _lane_of(worst)}
			say(_pick_from(_bots(team, worst)), "failing_lane_and_no_farm", false, fill, 0.8)
			say(_pick_from(_bots(1 - team)), "ragebait_and_trolling" if _rng.randf() < 0.5 else "casual_short_mockery",
				true, {"victim": label(worst)}, 0.3)
		for m in mates:
			if m.deaths >= 6 and m.deaths >= 2 * (m.kills + 1):
				say(_pick_from(_bots(team, m)), "dying_too_much_and_feeding", false, {"ally": label(m), "n": m.deaths}, 0.5)
				break
		# a bored bot now and then
		say(_pick_from(_bots(team)), "gen_z_brainrot_and_slang", _rng.randf() < 0.4, {}, 0.2)

func _missing_item(h: SimUnit) -> String:
	for id in ["boots", "power_treads", "slip_boots", "mana_boots"]:
		if w.shop.owns(h, id):
			return "core item"
	return "boots"

func _lane_of(h: SimUnit) -> String:
	var b = _bot_of(h)
	return SimTeamAI.lane_label(String(b.lane)) if b != null else "your lane"

func _on_end(winner: int) -> void:
	var t0 := 0.4
	for h in _bots(winner):
		if _rng.randf() < 0.75:
			_say_now(h, "game_won", true, t0)
			t0 += 0.6
	for h in _bots(1 - winner):
		if _rng.randf() < 0.6:
			_say_now(h, "game_lost", _rng.randf() < 0.6, t0)
			t0 += 0.6
	_flush_all()

## The game is over (the world stops stepping): end lines go out at once.
func _say_now(h: SimUnit, cat: String, all: bool, _delay: float) -> void:
	var mate := _pick_from(w.heroes.filter(func(x): return x.team == h.team and x != h))
	var text := line(h, cat, {"ally": label(mate)} if mate != null else {})
	if text != "":
		_queue.append({"at": w.time, "team": h.team, "u": h.id, "text": text, "all": all, "cat": cat})

func _flush_all() -> void:
	for q in _queue:
		w.chat(int(q.team), int(q.u), String(q.text), bool(q.all), true)
		said += 1
	_queue.clear()
