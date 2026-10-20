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
##
## Living players (run 2026-10-19 d; the owner: "make sure they really know what they are playing ... missed shots,
## kills, revenge"): every bot has a persona (Persona: from its ranked profile, else from its name) that sets how much
## it talks, how kind or rough it is and how it types (ChatStyle), and it keeps a memory of the match:
##   * who killed it and whom it killed, so a kill on the hero that last killed it is a revenge line and a third kill
##     on the same hero calls out the count; the victim answers back;
##   * the damage on each hero (kill steals: the ally who did most of the work says so, the thief says sorry or not),
##     the ability that landed the killing blow ("nerf {skill}"), stuns before a death ("perma stun"), double and
##     triple kills, team wipes, escapes on a sliver of health;
##   * the game itself: an enemy ultimate just used ("Froster used Endless Winter, go"), our ultimate ready, a big item
##     done, net worth leads and deficits by the thousand, a fed enemy, an enemy core dead long enough to push;
##   * its mood: deaths and flames tilt it (it shouts, blames, gives up), a kind one cheers the team up instead;
##   * the player: answers to what they type (rank, where from, where is a hero, items, why no help, insults with the
##     player's own score, praise, sorry, gg, ff, "are you a bot"), and in ranked what happened the last time they met
##     (Ranked "you"): "you again, we won last time", "revenge time", "oh it's the flamer"; Ranked reads back what
##     happened here (relations()) so the next match remembers it;
##   * other bots: a flamed teammate answers (sorry, argues back), a third tells them to stop;
##   * team calls (SimTeamAI.say, SimBot.say) come out the way players type them (casual()).
## Lines are timed like typing (0.6-2.5 s after the moment), limited so chat stays readable, and not repeated soon.
## Everything is drawn from the world's own seeded generator here, so every multiplayer peer sees the same lines.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const L = preload("res://src/sim/bot_chat_lines.gd")

## Lines that need nothing filled in may be said anywhere; a line with {victim} etc. needs that name.
const KEYS := ["victim", "killer", "ally", "hero", "lane", "item", "n"]
## Library categories that mock someone (a laugh at the end now and then).
const MOCKING := ["casual_short_mockery", "missed_skillshot_and_whiffs", "killed_enemy_all_chat", "ragebait_and_trolling",
	"gen_z_brainrot_and_slang", "rival", "miss_named", "ks_player", "revenge", "escape_enemy", "wipe", "meet_won_vs"]
## Lines aimed at one teammate (who may answer back).
const AT_ALLY := ["teammate_roast_and_blame", "dying_too_much_and_feeding", "failing_lane_and_no_farm", "ks", "feed_ally_flame",
	"kda_awful_ally"]

var w: SimWorld
var _rng := RandomNumberGenerator.new()
var _queue: Array = []                      # [{at, team, u, text, all, cat, target}]
var _voice := {}                            # hero id -> {tl, salt, rough}
var _ps := {}                               # hero id -> persona
var _mind := {}                             # hero id -> {tilt, last_killer, killer_t, kills_on, deaths_to, stun, doing}
var _dmg := {}                              # hero id -> {source hero id: [damage, time]} (the last 12 s)
var _last_hit := {}                         # hero id -> [source hero id, ability, time] (the last ability that hurt it)
var _bot_last := {}                         # hero id -> last line time
var _last_all := C.LONG_AGO
var _last_team := [C.LONG_AGO, C.LONG_AGO]
var _recent := {}                           # category -> the line indices said lately
var _recent_mind := []                      # ChatMind lines said lately
var _kills := []                            # [time, killer team] of recent hero kills (team fights)
var _deaths := [[], []]                     # per team: times of its heroes' deaths (wipes)
var _fight_said := C.LONG_AGO
var _wipe_said := C.LONG_AGO
var _ult_said := [C.LONG_AGO, C.LONG_AGO]
var _nw_said := [C.LONG_AGO, C.LONG_AGO]
var _nw_prev := [0, 0]
var _fed_said := [C.LONG_AGO, C.LONG_AGO]
var _push_said := [C.LONG_AGO, C.LONG_AGO]
var _cheer_said := [C.LONG_AGO, C.LONG_AGO]
var _close := {}                            # hero id -> [time it was nearly killed, enemy hero id]
var _next_review := 240.0
var _next_beat := 0.0
var _greeted := false
var _memories_said := false
var _mega_said := [false, false]
var _speaker := [{}, {}, {}]                # the last bot line in team 0, team 1, all chat: {u, t}
var _rel := {}                              # bot hero id -> what passed between it and the player (relations())
var _recent_calls := [[], []]               # per team: the team calls typed lately (no word-for-word echoes)
var _my_calls := {}                         # hero id -> {call text: time} (no one repeats a call within 150 s)
var _used := {}                             # every line of 3+ words said this match -> who said it first (no echoes)
var _own := {}                              # hero id -> {ChatMind line: times this player typed it}
var _next_lid := 1                          # line ids (the online chat writer, LlmChat, rewrites lines by id)
var _said_now := ""                         # the player's line being answered (for LlmChat)
var _said_by := -1                          # the player hero who typed it
## The player comes first (the owner, 2026-10-20: "the player should be TOP PRIORITY to have them reply at all
## means"): while a player's line is being answered, the next line queued skips the dice, the gap since the bot's
## last line and the one-line-at-a-time rule; every line answering the player jumps the chat queue.
var _must := false
var _answered := false
var _intents: Array = []                    # "chat_intent" events for this step (added after the events are read)
var said := 0                               # report counter (tests, bot games)
var social: ChatSocial                      # the crowd: multi-kills, feeding, KDA, trash talk, friends, MVP (run 2026-10-19 e)
var prof: ChatProfile                       # profiles: they look you (and each other) up (run 2026-10-20)

func _init(world: SimWorld = null) -> void:
	w = world
	if w != null:
		_rng.seed = w.rng.seed ^ 0x5ca7
	social = ChatSocial.new(self)
	prof = ChatProfile.new(self)

# ---- Voices and personas -----------------------------------------------------------------------------------------------

## A bot's voice, fixed by its name: tl (share of Filipino and Taglish lines), salt (how often it talks), rough (how
## often a line comes from the rough Filipino set).
func voice(h: SimUnit) -> Dictionary:
	if _voice.has(h.id):
		return _voice[h.id]
	var b = _bot_of(h)
	if b != null and not (b.voice as Dictionary).is_empty():
		# a ranked bot talks the way its profile says (Ranked: tl, salt from how toxic it is, rough)
		var pv := {"tl": float(b.voice.get("tl", 0.4)), "salt": float(b.voice.get("salt", 0.6)), "rough": float(b.voice.get("rough", 0.1))}
		_voice[h.id] = pv
		return pv
	var hh := absi(hash(h.player_label() + String(h.def.id)))
	var kind := hh % 3                      # 0 Pinoy, 1 Taglish, 2 English
	var v := {"tl": [0.75, 0.45, 0.08][kind], "salt": 0.55 + float((hh / 3) % 45) / 100.0,
		"rough": [0.35, 0.2, 0.05][kind]}
	_voice[h.id] = v
	return v

## Who the bot is (Persona): its ranked profile's, else one made from its name (the same on every machine).
func persona(h: SimUnit) -> Dictionary:
	if _ps.has(h.id):
		return _ps[h.id]
	var b = _bot_of(h)
	var p: Dictionary = {}
	if b != null and not (b.persona as Dictionary).is_empty():
		p = b.persona
	else:
		p = Persona.from_name(h.player_label() + String(h.def.id), float(b.toxic) if b != null else 0.35)
	_ps[h.id] = p
	return p

func _style(h: SimUnit) -> Dictionary:
	return persona(h).get("style", {})

func _trait(h: SimUnit, k: String, dflt := 0.5) -> float:
	return float(persona(h).get(k, dflt))

## What the bot remembers of this match.
func mind(h: SimUnit) -> Dictionary:
	if not _mind.has(h.id):
		var t0 := 0.0
		var b = _bot_of(h)
		if b != null and float(b.card.get("mood", 0.0)) < -0.4:
			t0 = 0.25
		_mind[h.id] = {"tilt": t0, "last_killer": -1, "killer_t": C.LONG_AGO, "kills_on": {}, "deaths_to": {},
			"stun": 0.0, "stun_t": C.LONG_AGO}
	return _mind[h.id]

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

func _humans(team := -1) -> Array:
	return w.heroes.filter(func(x): return not x.bot and (team < 0 or x.team == team))

func _pick_from(list: Array) -> SimUnit:
	if list.is_empty():
		return null
	return list[_rng.randi_range(0, list.size() - 1)]

## A bot from `list`, the talkative ones more often.
func _talker(list: Array, trait_name := "talk") -> SimUnit:
	if list.is_empty():
		return null
	var total := 0.0
	for h in list:
		total += 0.15 + _trait(h, trait_name)
	var x := _rng.randf() * total
	for h in list:
		x -= 0.15 + _trait(h, trait_name)
		if x <= 0.0:
			return h
	return list[-1]

func label(u: SimUnit) -> String:
	if u == null:
		return ""
	return SimTeamAI.hero_label(u)

## How bots call a player by name: the name they play under, else the hero.
func pname(u: SimUnit) -> String:
	if u == null:
		return ""
	var n := u.player_label()
	return n if n != "" else label(u)

func _kda(u: SimUnit) -> String:
	return "%d/%d/%d" % [u.kills, u.deaths, u.assists]

func _team_nw(team: int) -> int:
	var s := 0
	for h in w.heroes:
		if h.team == team:
			s += h.networth()
	return s

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
		var ok := _fits_clock(text)
		for k in KEYS:
			if ok and text.contains("{" + k + "}"):
				if not fill.has(k):
					ok = false
					break
				text = text.replace("{" + k + "}", str(fill[k]))
		if not ok or _echo(text, h):
			continue
		recent.append(i)
		while recent.size() > mini(40, lines.size() / 2):
			recent.pop_front()
		_recent[cat] = recent
		_mark(text, h)
		return text
	return ""

## Whether `text` (three words or more) was already typed by another player this match: people do not echo each
## other word for word, so a second player never sends the same line.
func _echo(text: String, h: SimUnit) -> bool:
	var k := text.to_lower().strip_edges().rstrip(".!?")
	if k.split(" ", false).size() < 3:
		return false
	return _used.has(k) and int(_used[k]) != h.id

func _mark(text: String, h: SimUnit) -> void:
	var k := text.to_lower().strip_edges().rstrip(".!?")
	if not _used.has(k):
		_used[k] = h.id

## A ChatMind line of `sit` that nobody else typed this match ("" if every try was taken).
func _fresh(h: SimUnit, sit: String, fill: Dictionary, avoid: Array) -> String:
	var tl := _rng.randf() < float(voice(h).tl)
	# a player does not type the same line a third time in a match (the review of run 2026-10-19 e)
	var mine: Dictionary = _own.get(h.id, {})
	for i in 6:
		var t := ChatMind.pick(sit, fill, tl, _rng, avoid)
		if t == "":
			return t
		if _echo(t, h) or (int(mine.get(t, 0)) >= 2 and i < 5):
			continue
		mine[t] = int(mine.get(t, 0)) + 1
		_own[h.id] = mine
		return t
	return ""

## A line naming a minute ("still holding tangos at 25 min", "20 mins no boots") fits only a game that long.
func _fits_clock(text: String) -> bool:
	var m := _MIN_RE.search(text.to_lower())
	if m == null:
		return true
	return w.time / 60.0 >= float(m.get_string(1)) - 2.0

static var _MIN_RE := RegEx.create_from_string("(\\d+)\\s*(min|mins|minutes|minute)\\b")

## Whether `h` may talk now: a bot (not one a player took over), not mid-line, not too soon after its last line.
func _can_talk(h: SimUnit, gap := 4.0) -> bool:
	if h == null or not h.bot:
		return false
	var b = _bot_of(h)
	if b == null or b.passive or b.human:
		return false
	if _must:
		return true                         # answering the player: never too busy
	if w.time - float(_bot_last.get(h.id, C.LONG_AGO)) < gap:
		return false
	for q in _queue:
		if int(q.u) == h.id:
			return false                    # one line typing at a time
	return true

## How likely `h` speaks up, for a moment worth `chance`.
func _roll(h: SimUnit, chance: float) -> bool:
	if _must:
		return true
	var v := voice(h)
	return _rng.randf() <= chance * (0.55 + float(v.salt) * 0.6) * (0.45 + _trait(h, "talk") * 0.85)

## Queue a library line from `h` after a typing delay. all: all chat. Returns whether it was queued.
func say(h: SimUnit, cat: String, all: bool, fill := {}, chance := 1.0, delay := -1.0, target := -1) -> bool:
	if not _can_talk(h) or not _roll(h, chance):
		return false
	var v := voice(h)
	# the rough Filipino set now and then in place of the moment's line (a Pinoy voice swears more)
	var c := cat
	if all and _rng.randf() < float(v.rough) * 0.35 and cat in ["killed_enemy_all_chat", "missed_skillshot_and_whiffs",
			"ragebait_and_trolling", "casual_short_mockery", "responses_and_comebacks"]:
		c = "tagalog_trashtalk_and_kanal_humor"
	var text := line(h, c, fill)
	if text == "":
		return false
	_queue_line(h, text, all, cat, delay, target, fill.values(), fill)
	return true

## Queue a line about the moment (ChatMind) from `h`. gap: the least time since its last line (replies come quicker).
func speak(h: SimUnit, sit: String, all: bool, fill := {}, chance := 1.0, delay := -1.0, target := -1, gap := 4.0) -> bool:
	if not _can_talk(h, gap) or not _roll(h, chance):
		return false
	var text := _fresh(h, sit, fill, _recent_mind)
	if text == "":
		return false
	_mark(text, h)
	_recent_mind.append(text)
	while _recent_mind.size() > 60:
		_recent_mind.pop_front()
	_queue_line(h, text, all, sit, delay, target, fill.values(), fill)
	return true

func _queue_line(h: SimUnit, text: String, all: bool, cat: String, delay: float, target: int, keep: Array = [],
		fill := {}) -> void:
	var laugh := (0.1 + _trait(h, "humor") * 0.25) if cat in MOCKING else 0.02
	var typed := ChatStyle.apply(text, _style(h), float(mind(h).tilt), _rng, false, laugh, -1.0, keep)
	var at := w.time + (delay if delay >= 0.0 else _rng.randf_range(0.6, 2.2) + float(typed.length()) * 0.03)
	var lid := _next_lid
	_next_lid += 1
	var pri := _said_by >= 0                # an answer to the player
	if pri:
		_answered = true
		_must = false
	_queue.append({"at": at, "team": h.team, "u": h.id, "text": typed, "all": all, "cat": cat, "target": target, "lid": lid,
		"pri": pri})
	_bot_last[h.id] = maxf(at, float(_bot_last.get(h.id, C.LONG_AGO)))
	# for the online chat writer (presentation only: nothing in the match reads it)
	_intents.append({"t": "chat_intent", "lid": lid, "u": h.id, "team": h.team, "all": all, "cat": cat, "text": typed,
		"fill": fill.duplicate(), "said": _said_now if pri else "", "by": _said_by if pri else -1})

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
		# answers to the player go out almost at once; other lines keep chat readable
		var all_gap := 0.6 if bool(q.get("pri", false)) else 1.5
		var team_gap := 0.6 if bool(q.get("pri", false)) else 1.2
		if bool(q.all) and w.time - _last_all < all_gap or not bool(q.all) and w.time - float(_last_team[int(q.team)]) < team_gap:
			q.at = float(q.at) + 0.5
			i += 1
			continue
		_queue.remove_at(i)
		if bool(q.all):
			_last_all = w.time
		else:
			_last_team[int(q.team)] = w.time
		w.chat(int(q.team), h.id, String(q.text), bool(q.all), true, int(q.get("lid", -1)))
		said += 1
		_speaker[2 if bool(q.all) else int(q.team)] = {"u": h.id, "t": w.time}
		_after_line(h, q)

## What a posted line sets off: a flamed teammate answers, trash talk draws a pile-on or a comeback.
func _after_line(h: SimUnit, q: Dictionary) -> void:
	var cat := String(q.cat)
	var target := w.get_unit(int(q.get("target", -1)))
	if target != null and cat in AT_ALLY:
		_note(h, "flames")
		if not target.bot:
			_note(h, "flamed_you")
		else:
			_answer_flame(target, h)
		return
	if bool(q.all) and cat != "responses_and_comebacks" and cat != "game_start" and not cat.begins_with("r_") \
			and not cat.begins_with("t_") and not cat.begins_with("meet_") and not cat.begins_with("end_"):
		var r := _rng.randf()
		if r < 0.18:
			say(_talker(_bots(1 - h.team)), "responses_and_comebacks", true, {}, 1.0)
		elif r < 0.3:
			say(_talker(_bots(h.team, h)), "casual_short_mockery" if _rng.randf() < 0.6 else "gen_z_brainrot_and_slang", true, {}, 1.0)

## A teammate's flame at `b` gets an answer that fits `b`: sorry, or arguing back; a third bot may tell them to stop.
func _answer_flame(b: SimUnit, from: SimUnit) -> void:
	mind(b).tilt = minf(1.0, float(mind(b).tilt) + 0.08)
	var kind := _trait(b, "kind")
	var hot := _trait(b, "ego") * 0.5 + _trait(b, "temper") * 0.5 + float(mind(b).tilt) * 0.4
	var d := _rng.randf_range(1.2, 3.0)
	var ok := false
	if kind > hot and _rng.randf() < 0.6:
		ok = speak(b, "t_sorry", false, {}, 0.8, d, -1, 2.0)
	elif _rng.randf() < 0.75:
		ok = speak(b, "t_argue", false, {"kda": _kda(from)}, 0.9, d, -1, 2.0)
	if ok and _rng.randf() < 0.45:
		var calm: Array = _bots(b.team, b).filter(func(x): return x != from and _trait(x, "kind") > 0.5)
		speak(_talker(calm, "focus"), "t_calm", false, {}, 0.8, d + _rng.randf_range(1.5, 3.0), -1, 2.0)

# ---- Team calls -------------------------------------------------------------------------------------------------------

## A team call (SimTeamAI.say) typed the way a player would: `kind` names it, `f` holds its facts (hero, lane,
## seconds). "" leaves it out (a call players rarely bother to type); the formal text stays when nothing fits.
## urgent: a ping reply or a call the team relies on (never left out).
func casual(h: SimUnit, kind: String, f: Dictionary, text: String, urgent := false) -> String:
	if kind == "" or h == null or not h.bot:
		return text
	var b = _bot_of(h)
	if b == null or b.human:
		return text
	var talk := _trait(h, "talk")
	if kind == "voice":
		if _rng.randf() < 0.35 + (0.3 - talk if talk < 0.3 else 0.0) or _echo(text, h):
			return ""
		# a hero quip once in a while, not the same one again and again (the blind review: 4 times a match)
		var said_v: Dictionary = _my_calls.get(h.id, {})
		if w.time - float(said_v.get(text, C.LONG_AGO)) < 900.0:
			return ""
		said_v[text] = w.time
		_my_calls[h.id] = said_v
		_mark(text, h)
		return ChatStyle.apply(text, _style(h), float(mind(h).tilt), _rng, true)
	# calls a player often would not type (the plan still happens); answers to the player's pings and the lane calls
	# always come
	var skip := {"go": 0.72, "abort": 0.5, "juke": 0.45, "heal": 0.55, "gank_go": 0.35, "gank_tp": 0.2, "miss": 0.15,
		"stack": 0.35, "item": 0.2, "push_on": 0.3, "dust_buy": 0.3, "counter": 0.45, "save": 0.35, "save_tp": 0.2,
		"save_run": 0.4, "def_go": 0.3, "def_tp": 0.15, "six": 0.2, "gank": 0.35, "teamfight": 0.25, "push": 0.2,
		"def": 0.1, "danger": 0.1}
	var must := kind.begins_with("p_") or kind.begins_with("lane_") or kind in ["ok_back", "nogank"]
	if not must and _rng.randf() < float(skip.get(kind, 0.0)) + (0.25 - talk if talk < 0.25 else 0.0):
		return ""
	var sit := kind
	if kind == "item":
		var iid := String(f.get("item_id", ""))
		if iid.contains("knife"):
			sit = "knife_done"
		elif iid == "spell_shield":
			sit = "shield_done"
		elif _rng.randf() < 0.5:
			sit = "item_done"
	var ff := f.duplicate()
	for k in ["hero", "ally", "core"]:
		if ff.has(k):
			ff[k] = String(ff[k]).to_lower()
	# players do not echo each other's calls word for word, and one player does not send the same call again and again
	var recent: Array = _recent_calls[h.team]
	var t := _fresh(h, sit, ff, recent)
	if t == "":
		if not must:
			return ""
		t = ChatMind.pick(sit, ff, _rng.randf() < float(voice(h).tl), _rng, recent)
		if t == "":
			return text
	var mine: Dictionary = _my_calls.get(h.id, {})
	var said_at := float(mine.get(t, C.LONG_AGO))
	if w.time - said_at < 420.0 and not must:
		return ""
	mine[t] = w.time
	_my_calls[h.id] = mine
	_mark(t, h)
	recent.append(t)
	while recent.size() > 30:
		recent.pop_front()
	return ChatStyle.apply(t, _style(h), float(mind(h).tilt), _rng, true, 0.0, -1.0, ff.values())

# ---- Every step --------------------------------------------------------------------------------------------------------

func tick() -> void:
	if w.bots.is_empty():
		return
	if not _greeted and w.time >= -50.0:
		_greeted = true
		for team in [C.DAWN, C.DUSK]:
			for h in _bots(team):
				say(h, "game_start", _rng.randf() < 0.6, {}, 0.4, _rng.randf_range(0.5, 6.0))
	if not _memories_said and w.time >= -40.0:
		_memories_said = true
		_memories()
	for e in w.events:
		match String(e.t):
			"damage":
				_on_damage(e)
			"stunned":
				var su := w.get_unit(int(e.u))
				if su != null and su.is_hero():
					var m := mind(su)
					m.stun = (float(m.stun) if w.time - float(m.stun_t) < 4.0 else 0.0) + float(e.get("dur", 0.0))
					m.stun_t = w.time
			"hero_kill":
				_on_kill(e)
			"skill_miss":
				_on_miss(e)
			"cast":
				_on_cast(e)
			"level_up":
				_on_level(e)
			"death":
				_on_death(e)
			"buyback":
				var bh := w.get_unit(int(e.u))
				if bh != null:
					say(_talker(_bots(1 - bh.team)), "buyback", true, {}, 0.5)
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
	if w.time >= _next_beat:
		_next_beat = w.time + 0.5
		_beat()
	if w.time >= _next_review:
		_next_review = w.time + _rng.randf_range(100.0, 170.0)
		_review()
	_flush()
	if not _intents.is_empty():
		w.events.append_array(_intents)
		_intents.clear()

## Twice a second: tilt cools, near deaths that got away.
func _beat() -> void:
	for id in _mind:
		var m: Dictionary = _mind[id]
		m.tilt = maxf(0.0, float(m.tilt) - 0.0035)
	for b in w.bots:
		var h: SimUnit = b.hero()
		if h == null or b.passive or b.human:
			continue
		if not h.alive:
			_close.erase(h.id)
			continue
		var near_e: SimUnit = null
		for e in w.heroes:
			if e.team != h.team and e.alive and e.pos.distance_to(h.pos) < 900.0:
				near_e = e
				break
		if _close.has(h.id):
			var c: Array = _close[h.id]
			if w.time - float(c[0]) > 4.0:
				_close.erase(h.id)
				if near_e == null or near_e.pos.distance_to(h.pos) > 1300.0:
					if not speak(h, "escape", _rng.randf() < 0.5, {}, 0.55):
						var foe := w.get_unit(int(c[1]))
						if foe != null and foe.bot:
							speak(foe, "escape_enemy", true, {"victim": label(h).to_lower()}, 0.35)
		elif near_e != null and h.hp < h.max_hp * 0.07:
			_close[h.id] = [w.time, near_e.id]

func _on_damage(e: Dictionary) -> void:
	var t := w.get_unit(int(e.u))
	if t == null or not t.is_hero():
		return
	var src := w.get_unit(int(e.get("src", -1)))
	if src == null or not src.is_hero() or src.team == t.team:
		return
	var amt := float(e.get("amount", 0.0))
	if amt <= 0.0:
		return
	var per: Dictionary = _dmg.get(t.id, {})
	var cur: Array = per.get(src.id, [0.0, w.time])
	per[src.id] = [(float(cur[0]) if w.time - float(cur[1]) < 12.0 else 0.0) + amt, w.time]
	_dmg[t.id] = per
	var key := String(e.get("key", ""))
	if key != "" and key in src.abilities:
		_last_hit[t.id] = [src.id, key, w.time]

## The share of the damage on `victim` in the last 12 s: {source id: share}.
func _shares(victim: SimUnit) -> Dictionary:
	var per: Dictionary = _dmg.get(victim.id, {})
	var tot := 0.0
	for sid in per:
		if w.time - float(per[sid][1]) < 12.0:
			tot += float(per[sid][0])
	var out := {}
	if tot <= 0.0:
		return out
	for sid in per:
		if w.time - float(per[sid][1]) < 12.0:
			out[sid] = float(per[sid][0]) / tot
	return out

# ---- Moments -----------------------------------------------------------------------------------------------------------

func _on_kill(e: Dictionary) -> void:
	var victim := w.get_unit(int(e.victim))
	if victim == null:
		return
	var killer := w.get_unit(int(e.u))
	_kills.append([w.time, 1 - victim.team])
	while not _kills.is_empty() and w.time - float(_kills[0][0]) > 15.0:
		_kills.pop_front()
	(_deaths[victim.team] as Array).append(w.time)
	var fill := {"victim": label(victim), "n": victim.deaths}
	var vm := mind(victim)
	vm.tilt = minf(1.0, float(vm.tilt) + 0.1 + _trait(victim, "temper", 0.4) * 0.22)
	var shares := _shares(victim)
	_dmg.erase(victim.id)
	if killer == null:
		# creeps, a tower or a camp did it
		var tower := w.get_unit(int(e.get("killer_unit", -1)))
		if tower != null and tower.kind == K.TOWER and victim.bot and speak(victim, "tower_dive", _rng.randf() < 0.4, {}, 0.3):
			pass
		else:
			say(_talker(_bots(1 - victim.team)), "died_to_creeps_or_tower", true, fill, 0.7)
		_after_death(victim, null)
		social.on_kill(e, null, victim)
		return
	var km := mind(killer)
	var times := int((km.kills_on as Dictionary).get(victim.id, 0)) + 1
	km.kills_on[victim.id] = times
	vm.deaths_to[killer.id] = int((vm.deaths_to as Dictionary).get(killer.id, 0)) + 1
	var revenge := int(km.last_killer) == victim.id and w.time - float(km.killer_t) < 900.0
	vm.last_killer = killer.id
	vm.killer_t = w.time
	if revenge:
		km.last_killer = -1
	# relations with the player (Ranked reads them back after the match)
	if not victim.bot and killer.bot:
		_note(killer, "kills_on_you")
	elif not killer.bot and victim.bot:
		_note(victim, "deaths_to_you")
	var spoke := false
	var kfill := {"victim": label(victim).to_lower(), "n": times}
	var hit: Array = _last_hit.get(victim.id, [])
	var skill := ""
	if not hit.is_empty() and int(hit[0]) == killer.id and w.time - float(hit[2]) < 3.0:
		skill = String(SimData.ability(String(hit[1])).get("name", ""))
	if bool(e.get("first_blood", false)):
		spoke = say(killer, "first_blood", true, fill, 1.0)
		if not spoke:
			say(_talker(_bots(killer.team, killer)), "first_blood", true, fill, 0.7)
	elif revenge:
		spoke = speak(killer, "revenge", true, kfill, 0.85)
		if spoke and victim.bot:
			speak(victim, "revenge_reply", true, {}, 0.4, _rng.randf_range(2.0, 4.0))
	elif int(e.get("ended_streak", 0)) >= 3:
		spoke = say(killer, "shutdown", true, fill, 0.9)
	elif int(e.get("multi", 0)) >= 2 and (int(e.multi) < 5 or ChatSocial.off):
		spoke = speak(killer, "double" if int(e.multi) == 2 else "multi", true, {"n": int(e.multi)}, 0.7)
	elif int(e.get("multi", 0)) >= 5:
		spoke = true                           # a rampage: ChatSocial has the killer's line
	elif times >= 3 and _rng.randf() < 0.7:
		spoke = speak(killer, "rival", true, kfill, 0.75)
		if spoke and victim.bot:
			speak(victim, "rival_reply", true, {}, 0.45, _rng.randf_range(2.0, 4.0))
	elif int(e.get("streak", 0)) >= 3 and _rng.randf() < 0.5:
		spoke = say(killer, "killing_spree", true, {"n": int(e.streak)}, 0.8)
	if not spoke and skill != "" and _rng.randf() < 0.45:
		spoke = speak(killer, "skill_kill", true, {"skill": skill.to_lower()}, 0.6)
	if not spoke and int(e.get("streak", 0)) >= 3 and _trait(killer, "ego") > 0.6:
		spoke = speak(killer, "brag", true, {}, 0.5)
	if not spoke:
		# "that's 3 for me" (lines with {n} wait for a second kill)
		var f2 := fill.duplicate()
		if times >= 2:
			f2["n"] = times
		else:
			f2.erase("n")
		say(killer, "killed_enemy_all_chat", true, f2, 0.55)
	# kill steals: an ally did most of the work
	var top := -1
	var top_s := 0.0
	for sid in shares:
		var su := w.get_unit(int(sid))
		if su != null and su.team == killer.team and float(shares[sid]) > top_s:
			top = int(sid)
			top_s = float(shares[sid])
	var ks_by := w.get_unit(top)
	if ks_by != null and ks_by != killer and top_s >= 0.5 and float(shares.get(killer.id, 0.0)) <= 0.2:
		_kill_steal(ks_by, killer)
	elif killer != null and not killer.bot:
		# the player got a kill: a teammate notices, the victim's side is less impressed
		speak(_talker(_bots(killer.team)), "player_kill", false, {"name": pname(killer)}, 0.45)
	elif killer != null:
		say(_talker(_bots(killer.team, killer)), "ally_praise", false, {"ally": label(killer)}, 0.2)
	# the victim: the ability, the stuns, its temper; its teammates: on its deaths, or on the ally who stood by
	var vspoke := false
	if skill != "" and victim.bot and _rng.randf() < 0.5:
		vspoke = speak(victim, "skill_death", _rng.randf() < 0.5, {"skill": skill.to_lower(), "hero": label(killer).to_lower()}, 0.45)
	if not vspoke and victim.bot and float(vm.stun) >= 1.4 and w.time - float(vm.stun_t) < 3.5:
		vspoke = speak(victim, "stun_death", _rng.randf() < 0.4, {}, 0.5)
	if not vspoke and victim.bot and float(vm.tilt) > 0.65:
		vspoke = speak(victim, "own_death_tilt", _rng.randf() < 0.3, {}, 0.45)
	if not vspoke:
		say(victim, "own_death_excuses", _rng.randf() < 0.2, {}, 0.3)
	_after_death(victim, killer)
	social.on_kill(e, killer, victim)
	# a fed enemy, an enemy core down long enough to push
	if killer.kills >= 7 and killer.kills >= killer.deaths * 2 and w.time - float(_fed_said[victim.team]) > 150.0:
		var focus := _talker(_bots(victim.team, victim), "focus")
		var big := _best_item_name(killer)
		if focus != null and speak(focus, "fed_enemy", false, {"hero": label(killer).to_lower(), "n": killer.kills, "item": big}, 0.4):
			_fed_said[victim.team] = w.time
	var wait := victim.respawn_at - w.time
	if w.time > 900.0 and wait >= 30.0 and w.time - float(_push_said[killer.team]) > 90.0:
		var caller := _talker(_bots(killer.team), "focus")
		if caller != null and speak(caller, "enemy_dead_push", false, {"hero": label(victim).to_lower(), "sec": int(wait)}, 0.3):
			_push_said[killer.team] = w.time
	# a team fight: three or more kills for one side within 15 s and at most one back; a wipe: five of a team in 25 s
	var dl: Array = _deaths[victim.team]
	while not dl.is_empty() and w.time - float(dl[0]) > 25.0:
		dl.pop_front()
	if dl.size() >= 5 and w.time - _wipe_said > 60.0:
		_wipe_said = w.time
		_fight_said = w.time
		var back := 0
		for k in _kills:
			if int(k[1]) == victim.team:
				back += 1
		speak(_talker(_bots(killer.team)), "wipe", true, {"n": dl.size(), "n2": back}, 1.0)
		speak(_talker(_bots(victim.team)), "wiped", false, {}, 0.8)
		return
	if w.time - _fight_said > 30.0:
		var by := [0, 0]
		for k in _kills:
			by[int(k[1])] += 1
		for team in [C.DAWN, C.DUSK]:
			if by[team] >= 3 and by[1 - team] <= 1:
				_fight_said = w.time
				say(_talker(_bots(team)), "teamfight_won", true, {"n": by[team]}, 1.0)
				say(_talker(_bots(1 - team)), "teamfight_lost", false, {}, 0.8)

## After a death: its teammates on the record or on the ally who stood by, a kind one cheering the team up.
func _after_death(victim: SimUnit, killer: SimUnit) -> void:
	var mates := _bots(victim.team, victim)
	var rough_record: bool = victim.deaths >= 4 and float(victim.deaths) >= float(victim.kills) + float(victim.assists) * 0.5 + 3.0
	if rough_record:
		var critic := _talker(mates.filter(func(x): return _trait(x, "kind") < 0.7))
		say(critic, "dying_too_much_and_feeding", false, {"ally": label(victim), "n": victim.deaths}, 0.55, -1.0, victim.id)
	elif victim.bot:
		# an ally close by who did not help: it gets blamed
		var near: SimUnit = null
		for a in w.heroes:
			if a.team == victim.team and a != victim and a.alive and a.pos.distance_to(victim.pos) < 1800.0:
				near = a
		if near != null and _trait(victim, "kind") < 0.75:
			say(victim, "teammate_roast_and_blame", false, {"ally": label(near)}, 0.35, -1.0, near.id)
	# the player died: what each bot was doing (for "why no help")
	if not victim.bot:
		for b in w.bots:
			var bh: SimUnit = b.hero()
			if bh != null and bh.team == victim.team and bh != victim:
				mind(bh)["doing"] = String(b.plan_text()).to_lower()
				mind(bh)["doing_t"] = w.time
	# behind and losing fights: a kind bot keeps the team going, a tilted one gives up
	if _team_nw(victim.team) < _team_nw(1 - victim.team) - 4000 and w.time - float(_cheer_said[victim.team]) > 150.0:
		var kind_one := _talker(mates.filter(func(x): return _trait(x, "kind") > 0.65 and float(mind(x).tilt) < 0.5))
		if kind_one != null and speak(kind_one, "encourage", false, {}, 0.35, _rng.randf_range(2.0, 5.0)):
			_cheer_said[victim.team] = w.time
		elif victim.bot and float(mind(victim).tilt) > 0.8 and _trait(victim, "kind") < 0.5:
			if speak(victim, "give_up", _rng.randf() < 0.3, {}, 0.4):
				_cheer_said[victim.team] = w.time

func _kill_steal(by: SimUnit, killer: SimUnit) -> void:
	if by.bot and killer.bot:
		if speak(by, "ks", _rng.randf() < 0.4, {"killer": label(killer).to_lower()}, 0.6):
			var d := _rng.randf_range(2.0, 3.5)
			if _trait(killer, "kind") > 0.55:
				speak(killer, "ks_sorry", false, {}, 0.5, d, -1, 1.5)
			else:
				speak(killer, "ks_proud", false, {}, 0.45, d, -1, 1.5)
	elif by.bot and not killer.bot:
		if speak(by, "ks_player", _rng.randf() < 0.3, {"name": pname(killer)}, 0.55):
			_note(by, "flamed_you")
	elif not by.bot and killer.bot:
		if _trait(killer, "kind") > 0.5:
			speak(killer, "ks_to_player", false, {"name": pname(by)}, 0.5)
		else:
			speak(killer, "ks_proud", false, {}, 0.35)

func _on_miss(e: Dictionary) -> void:
	var caster := w.get_unit(int(e.u))
	var dodger := w.get_unit(int(e.get("near", -1)))
	if caster == null or dodger == null:
		return
	var skill := String(SimData.ability(String(e.get("ability", ""))).get("name", "")).to_lower()
	var named := skill != "" and _rng.randf() < 0.6
	if named:
		if not speak(dodger, "miss_named", true, {"skill": skill, "hero": label(caster).to_lower()}, 0.7):
			say(_talker(_bots(dodger.team, dodger)), "casual_short_mockery", true, {}, 0.3)
	elif not say(dodger, "missed_skillshot_and_whiffs", true, {"hero": label(caster)}, 0.7):
		say(_talker(_bots(dodger.team, dodger)), "casual_short_mockery", true, {}, 0.3)
	# the caster's own team is not kinder; the caster grumbles
	if skill != "" and _rng.randf() < 0.5:
		speak(_talker(_bots(caster.team, caster)), "miss_team", false, {"skill": skill}, 0.12)
	else:
		say(_talker(_bots(caster.team, caster)), "missed_skillshot_and_whiffs", false, {"hero": label(caster)}, 0.12)
	if caster.bot and skill != "":
		speak(caster, "miss_self", false, {"skill": skill}, 0.15)

## An enemy ultimate seen used: a bot that saw it tells the team to go.
func _on_cast(e: Dictionary) -> void:
	var c := w.get_unit(int(e.u))
	if c == null or not c.is_hero():
		return
	var aid := String(e.get("ability", ""))
	if aid == "" or aid != SimBotKits.ultimate(c):
		return
	var team := 1 - c.team
	if w.time - float(_ult_said[team]) < 50.0 or not w.vision.sees(team, c):
		return
	var seen: Array = _bots(team).filter(func(x): return x.alive and x.pos.distance_to(c.pos) < 2200.0)
	var who := _talker(seen, "focus")
	var nm := String(SimData.ability(aid).get("name", "")).to_lower()
	if who != null and nm != "" and speak(who, "enemy_ult", false, {"hero": label(c).to_lower(), "skill": nm}, 0.3 + _trait(who, "focus") * 0.4):
		_ult_said[team] = w.time

func _on_level(e: Dictionary) -> void:
	var h := w.get_unit(int(e.u))
	if h == null or not h.bot or int(e.get("level", 0)) != 6:
		return
	var b = _bot_of(h)
	if b == null or int(b.role) == 2:
		return                                 # the mid bot says it itself (SimBot "six")
	var ult := SimBotKits.ultimate(h)
	var nm := String(SimData.ability(ult).get("name", "")).to_lower() if ult != "" else ""
	speak(h, "ult_ready", false, {"skill": nm} if nm != "" else {}, 0.15 + _trait(h, "focus") * 0.25)

func _best_item_name(h: SimUnit) -> String:
	var best := ""
	var cost := 0
	for it in h.inventory:
		if it != null and int(SimData.item(String(it.id)).get("cost", 0)) > cost:
			cost = int(SimData.item(String(it.id)).cost)
			best = String(SimData.item(String(it.id)).get("name", ""))
	return best.to_lower()

func _on_death(e: Dictionary) -> void:
	var u := w.get_unit(int(e.u))
	if u == null or not u.is_building():
		return
	var lane := SimTeamAI.lane_label(u.building_lane) if u.building_lane != "" else "base"
	if u.kind == K.TOWER:
		say(_talker(_bots(1 - u.team)), "tower_destroyed", _rng.randf() < 0.5, {"lane": lane}, 0.45)
		say(_talker(_bots(u.team)), "tower_lost", false, {"lane": lane}, 0.4)
	elif u.kind == K.BARRACKS and w.all_rax_dead(u.team) and not _mega_said[u.team]:
		_mega_said[u.team] = true
		say(_talker(_bots(1 - u.team)), "megas_and_base", true, {}, 1.0)
		say(_talker(_bots(u.team)), "tower_lost", false, {"lane": lane}, 0.8)

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

# ---- The player's lines ------------------------------------------------------------------------------------------------

## A line the player typed: understood (ChatMind.intent), answered by the bot it was meant for, with what the bot
## knows (its rank, its town, its next item, where it saw a hero, what it was doing, the player's own score).
func _on_chat(e: Dictionary) -> void:
	var u := w.get_unit(int(e.get("u", -1)))
	var human := u != null and not u.bot and not bool(e.get("bot_line", false))
	_said_now = String(e.get("text", ""))
	_said_by = u.id if human else -1
	_must = human
	_answered = false
	_answer_chat(e)
	if human and not _answered:
		_answer_anything(u, e)
	_must = false
	_said_now = ""
	_said_by = -1

## Nothing above answered the player (a line the brain has no answer for, or the bot it was for had no line left):
## someone still does. The bot it was meant for, else whoever spoke last in that channel, else an enemy in all chat or
## a teammate in team chat. An insult or trash talk gets a comeback, never silence.
func _answer_anything(u: SimUnit, e: Dictionary) -> void:
	var all := bool(e.get("all", false))
	var low := String(e.text).to_lower()
	var foes := _bots(1 - u.team)
	var listeners: Array = _bots(u.team) if not all else foes + _bots(u.team)
	if listeners.is_empty():
		return
	var to := _addressed(low, listeners)
	if to == null:
		var last: Dictionary = _speaker[2 if all else u.team]
		if not last.is_empty() and w.time - float(last.t) < 20.0:
			var lu := w.get_unit(int(last.u))
			if lu != null and lu in listeners:
				to = lu
	if to == null:
		to = _talker(foes if all and not foes.is_empty() else listeners, "ego" if all else "talk")
	var it := ChatMind.intent(low)
	var foe := to.team != u.team
	var sit := "r_back" if it in ["insult", "taunt"] else ("r_any_foe" if foe else "r_any")
	var fill := {"name": pname(u), "kda": _kda(u), "lh": u.last_hits, "min": maxi(1, int(w.time / 60.0))}
	var d := _rng.randf_range(1.0, 2.4)
	var order: Array = [to] + listeners.filter(func(x): return x != to)
	for h in order:
		_must = true
		if speak(h, sit, all or foe, fill, 1.0, d, -1, 0.0):
			return
	# every line of that kind was used up this match: the first one that fits, used or not
	var t := ChatMind.pick(sit, fill, _rng.randf() < float(voice(to).tl), _rng, [])
	if t != "":
		_queue_line(to, t, all or foe, sit, d, -1, fill.values(), fill)

func _answer_chat(e: Dictionary) -> void:
	var u := w.get_unit(int(e.u))
	if u == null or u.bot or bool(e.get("bot_line", false)):
		return                                 # bots' own lines draw replies in _flush
	var text := String(e.text)
	var low := text.to_lower()
	var all := bool(e.get("all", false))
	var listeners: Array = _bots(u.team) if not all else _bots(1 - u.team) + _bots(u.team)
	if listeners.is_empty():
		return
	var it := ChatMind.intent(low)
	if ChatSocial.off and it in ["add", "taunt"]:
		it = "insult" if ChatMind.RUDE.any(func(x): return low.contains(String(x))) else ""
	var to := _addressed(low, listeners)
	if it == "add":
		social.friend_ask(u, to, listeners, all)
		return
	if it in ["profile_me", "profile_you"] and not ChatSocial.off:
		if prof.ask(u, to, listeners, all, it == "profile_me"):
			return
	if not ChatSocial.off and it in ["taunt", "insult"] and (all or (to != null and to.team != u.team)):
		# trash talk the enemy reads: answered with the facts, piled on (ChatSocial)
		if to != null:
			_note(to, "flamed")
		social.trash_talk(u, to, all)
		return
	if it == "taunt":
		it = "insult"
	if to == null and it in ["insult", "praise", "thanks", "sorry", "huh"]:
		# "?" and "thanks" go to whoever spoke last in that channel
		var last: Dictionary = _speaker[2 if all else u.team]
		if not last.is_empty() and w.time - float(last.t) < 12.0:
			var lu := w.get_unit(int(last.u))
			if lu != null and lu in listeners:
				to = lu
	var d := _rng.randf_range(1.0, 2.6)
	var fill := {"name": pname(u), "me_hero": label(u).to_lower(), "kda": _kda(u), "lh": u.last_hits,
		"min": maxi(1, int(w.time / 60.0))}
	var mates: Array = _bots(u.team)
	match it:
		"where":
			var foe := _hero_named(low, 1 - u.team)
			var who := to if to != null and to.team == u.team else _talker(mates, "focus")
			if foe == null or who == null:
				return
			var ls: Array = w.brain(u.team).last_seen(foe)
			var ago := float(ls[1])
			if not foe.alive:
				speak(who, "p_dead", false, {"sec": ceili(maxf(0.0, foe.respawn_at - w.time))}, 1.0, d, -1, 1.5)
			elif ago < 45.0:
				speak(who, "r_where_seen", false, {"hero": label(foe).to_lower(), "lane": SimTeamAI.lane_label(w.brain(u.team).lane_of_point(ls[0])),
					"sec": maxi(1, int(ago))}, 1.0, d, -1, 1.5)
			else:
				speak(who, "r_where_lost", false, {"hero": label(foe).to_lower(), "min": maxi(1, int(ago / 60.0)) if is_finite(ago) else 1}, 1.0, d, -1, 1.5)
		"ss":
			speak(_talker(mates), "r_ok", false, {}, 0.5, d, -1, 2.0)
		"rank":
			var r := to if to != null else _talker(listeners)
			var b = _bot_of(r)
			if b != null and String(b.card.get("rank", "")) != "":
				speak(r, "r_rank", all, {"rank": String(b.card.rank).to_lower(), "mmr": int(b.card.get("mmr", 0))}, 1.0, d, -1, 1.5)
			else:
				speak(r, "r_rank_none", all, {}, 1.0, d, -1, 1.5)
		"from":
			var r2 := to if to != null else _talker(listeners)
			if r2 != null:
				speak(r2, "r_from", all, _home(r2), 1.0, d, -1, 1.5)
		"item":
			var r3 := to if to != null and to.team == u.team else _talker(mates)
			var b3 = _bot_of(r3)
			if b3 != null:
				var nxt := _next_items(b3)
				if not nxt.is_empty():
					speak(r3, "r_item", false, {"item": nxt[0], "item2": nxt[1] if nxt.size() > 1 else ""}, 1.0, d, -1, 1.5)
		"why":
			var r4 := to if to != null and to.team == u.team else _talker(mates)
			if r4 == null:
				return
			var m := mind(r4)
			if not r4.alive or String(m.get("doing", "")) == "dead":
				speak(r4, "r_why_dead", false, {}, 0.9, d, -1, 1.5)
			else:
				var doing := String(m.get("doing", "")) if w.time - float(m.get("doing_t", C.LONG_AGO)) < 60.0 else ""
				speak(r4, "r_why_far", false, {"doing": doing} if doing != "" else {}, 0.9, d, -1, 1.5)
		"insult":
			var r5 := to if to != null else _talker(listeners)
			if r5 == null:
				return
			_note(r5, "flamed")
			mind(r5).tilt = minf(1.0, float(mind(r5).tilt) + 0.12)
			var bad := u.deaths >= u.kills + u.assists / 2 + 2
			# a nice one jokes at the player's expense; nobody tells the player to relax (the owner, 2026-10-20)
			if _trait(r5, "kind") > 0.7 and float(mind(r5).tilt) < 0.6:
				speak(r5, "r_insult_witty", r5.team != u.team or all, fill, 0.9, d, -1, 1.5)
			elif bad and _rng.randf() < 0.7:
				speak(r5, "r_insult_fact", r5.team != u.team or all, fill, 1.0, d, -1, 1.5)
			elif _rng.randf() < 0.5:
				speak(r5, "r_back", r5.team != u.team or all, fill, 1.0, d, -1, 1.5)
			else:
				say(r5, "responses_and_comebacks", r5.team != u.team or all, {}, 0.9, d)
			if all:
				say(_talker(_bots(u.team)), "casual_short_mockery", true, {}, 0.12)
		"praise":
			var r6 := to if to != null else _talker(mates)
			if r6 != null:
				_note(r6, "praised")
				mind(r6).tilt = maxf(0.0, float(mind(r6).tilt) - 0.15)
				speak(r6, "r_praise", all or r6.team != u.team, fill, 0.8, d, -1, 1.5)
		"thanks":
			speak(to if to != null else _talker(mates), "r_thanks", all, fill, 0.7, d, -1, 1.5)
		"sorry":
			var r7 := to if to != null else _talker(mates)
			if r7 != null:
				var rude := _trait(r7, "kind") < 0.35 or float(mind(r7).tilt) > 0.7
				speak(r7, "r_sorry_rude" if rude else "r_sorry_kind", all, fill, 0.8, d, -1, 1.5)
		"gg":
			if w.winner < 0 and w.time > 60.0:
				var ahead := _team_nw(1 - u.team) > _team_nw(u.team)
				if all and ahead:
					speak(_talker(_bots(1 - u.team)), "r_gg_early", true, {}, 0.7, d, -1, 1.5)
				elif not all:
					speak(_talker(mates), "r_ff_no", false, {}, 0.6, d, -1, 1.5)
		"ff":
			var r8 := _talker(mates)
			if r8 != null:
				var yes := float(mind(r8).tilt) > 0.6 or _trait(r8, "kind") < 0.3
				speak(r8, "r_ff_yes" if yes else "r_ff_no", false, {}, 0.8, d, -1, 1.5)
		"report":
			speak(to if to != null else _talker(listeners), "r_report", all, {"ally": label(_worst(u.team)).to_lower()}, 0.6, d, -1, 1.5)
		"lag":
			speak(_talker(listeners), "r_lag", all, {"n": _rng.randi_range(60, 240)}, 0.6, d, -1, 1.5)
		"bot":
			speak(to if to != null else _talker(listeners, "humor"), "r_bot", all, {}, 0.85, d, -1, 1.5)
		"laugh":
			var r9 := _talker(listeners, "humor")
			if r9 != null and _trait(r9, "humor") > 0.45:
				speak(r9, "r_laugh", all, {}, 0.4, d, -1, 2.0)
		"huh":
			speak(to if to != null else _talker(listeners), "r_huh", all, {}, 0.45, d, -1, 2.0)
		"greet":
			var g := _talker(listeners)
			speak(g, "r_greet", all, fill, 0.85, d, -1, 1.5)
			var g2 := _talker(listeners.filter(func(x): return x != g))
			speak(g2, "r_greet", all, fill, 0.35, d + _rng.randf_range(1.0, 2.5), -1, 1.5)
		_:
			# just the name ("ezee", "ezee?"): "yes?"; anything else is answered by _answer_anything (the bot it was
			# meant for, whoever spoke last, an enemy in all chat)
			if to != null and low.split(" ", false).size() <= 2:
				speak(to, "r_name", all or to.team != u.team, {}, 1.0, d, -1, 2.0)

## The bot in `list` the player named: its player name, the first word of it, or its hero.
func _addressed(low: String, list: Array) -> SimUnit:
	var words := low.replace(",", " ").replace("?", " ").replace("!", " ").split(" ", false)
	for h in list:
		var nm := pname(h).to_lower()
		var hero := label(h).to_lower()
		if nm.length() >= 3 and low.contains(nm):
			return h
		var first := nm.split(" ", false)[0] if nm != "" else ""
		for wd in words:
			if wd.length() >= 3 and (wd == first or (hero.begins_with(wd) and wd.length() >= 4)):
				return h
	return null

## An enemy hero of `team` the player named ("where sludge", "frost ss").
func _hero_named(low: String, team: int) -> SimUnit:
	var words := low.replace(",", " ").replace("?", " ").split(" ", false)
	for e in w.heroes:
		if e.team != team:
			continue
		var hero := label(e).to_lower()
		for wd in words:
			if wd.length() >= 3 and hero.begins_with(wd):
				return e
	return null

## Where a bot says it is from: a city of its country (ranked), else one from its voice.
func _home(h: SimUnit) -> Dictionary:
	var b = _bot_of(h)
	var cc := String(b.card.get("country", "")) if b != null else ""
	if cc == "":
		cc = "PH" if float(voice(h).tl) > 0.3 else "US"
	var cities: Array = ChatMind.CITIES.get(cc, ["manila"])
	var seed := int(persona(h).get("seed", 0))
	return {"city": String(cities[seed % cities.size()]), "country": Ranked.country_name(cc).to_lower() if cc != "" else "ph"}

## The next one or two items a bot means to buy, by name.
func _next_items(b) -> Array:
	var out: Array = []
	var h: SimUnit = b.hero()
	for i in range(int(b._build_i), (b.build as Array).size()):
		var id := String(b.build[i])
		if h != null and w.shop.owns(h, id):
			continue
		var nm := String(SimData.item(id).get("name", ""))
		if nm != "":
			out.append(nm.to_lower())
		if out.size() >= 2:
			break
	return out

func _worst(team: int) -> SimUnit:
	var worst: SimUnit = null
	for h in w.heroes:
		if h.team == team and (worst == null or h.deaths - h.kills > worst.deaths - worst.kills):
			worst = h
	return worst

## Every couple of minutes each team looks at itself (the player too): the one furthest behind on farm hears about it,
## and the other team mocks the poorest of its enemies now and then; a teammate with a terrible record too; the net
## worth gap gets a call from a bot that reads the game (ahead: push and don't throw; behind: farm and defend).
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
			say(_talker(_bots(team, worst)), "failing_lane_and_no_farm", false, fill, 0.8, -1.0, worst.id)
			say(_talker(_bots(1 - team)), "ragebait_and_trolling" if _rng.randf() < 0.5 else "casual_short_mockery",
				true, {"victim": label(worst)}, 0.3)
		for m in mates:
			if m.deaths >= 6 and m.deaths >= 2 * (m.kills + 1):
				say(_talker(_bots(team, m)), "dying_too_much_and_feeding", false, {"ally": label(m), "n": m.deaths}, 0.5, -1.0, m.id)
				break
		# the gold gap
		var diff := _team_nw(team) - _team_nw(1 - team)
		var prev := int(_nw_prev[team])
		_nw_prev[team] = diff
		if w.time - float(_nw_said[team]) > 200.0:
			var caller := _talker(_bots(team), "focus")
			var k := int(round(absf(float(diff)) / 1000.0))
			if prev <= -6000 and diff >= -1000:
				if speak(caller, "comeback", false, {}, 0.7):
					_nw_said[team] = w.time
			elif diff >= 6000:
				if speak(caller, "nw_up", false, {"n": k}, 0.45 + _trait(caller, "focus") * 0.3 if caller != null else 0.0):
					_nw_said[team] = w.time
			elif diff <= -6000:
				if speak(caller, "nw_down", false, {"n": k}, 0.45 + _trait(caller, "focus") * 0.3 if caller != null else 0.0):
					_nw_said[team] = w.time
		# a bored bot now and then
		say(_talker(_bots(team)), "gen_z_brainrot_and_slang", _rng.randf() < 0.4, {}, 0.2)
	social.review()
	prof.review()

func _missing_item(h: SimUnit) -> String:
	for id in ["boots", "power_treads", "slip_boots", "mana_boots"]:
		if w.shop.owns(h, id):
			return "core item"
	return "boots"

func _lane_of(h: SimUnit) -> String:
	var b = _bot_of(h)
	return SimTeamAI.lane_label(String(b.lane)) if b != null else "your lane"

# ---- Memories of the player ----------------------------------------------------------------------------------------------

## The start of a ranked match: bots that met the player before say so (in team chat if on their side, else all chat).
func _memories() -> void:
	var players := _humans()
	if players.is_empty():
		return
	var p: SimUnit = players[0]
	var t0 := 3.0
	for b in w.bots:
		var h: SimUnit = b.hero()
		var rec: Dictionary = b.you_rec
		if h == null or rec.is_empty() or b.passive or b.human:
			continue
		var same := h.team == p.team
		var sit := ""
		var fill := {"name": pname(p), "n": int(rec.get("kills_on", 0))}
		var ms := social.memory_sit(rec)
		if bool(rec.get("friend", false)):
			sit = "meet_friend"
		elif ms != "":
			sit = ms
		elif float(rec.get("rep", 0.0)) < -0.3 and int(rec.get("flamed", 0)) > 0:
			sit = "meet_flamer"
		elif String(rec.get("last_side", "")) == "vs" and int(rec.get("last_kills_on", 0)) >= 4 and _rng.randf() < 0.5:
			sit = "meet_killer"
			fill["n"] = int(rec.get("last_kills_on", 0))
		elif String(rec.get("last_side", "")) == "with":
			sit = "meet_won_with" if String(rec.get("last_res", "")) == "W" else "meet_lost_with"
		elif String(rec.get("last_side", "")) == "vs":
			sit = "meet_won_vs" if String(rec.get("last_res", "")) == "W" else "meet_lost_vs"
		if sit == "":
			continue
		var chance := 0.95 if sit == "meet_friend" else 0.6
		if speak(h, sit, not same, fill, chance, t0 + _rng.randf_range(0.0, 4.0)):
			t0 += _rng.randf_range(2.0, 5.0)
	prof.meet(p, social.meet(p, t0 + 2.0) + 1.5)

## A count of what passed between bot `h` and the player (kills_on_you, deaths_to_you, flamed, flamed_you, praised).
func _note(h: SimUnit, k: String) -> void:
	if h == null or not h.bot:
		return
	var r: Dictionary = _rel.get(h.id, {})
	r[k] = int(r.get(k, 0)) + 1
	_rel[h.id] = r

## What passed between each bot and the player this match, by the bot's ladder id (Ranked.finish_match):
## {pid: {kills_on_you, deaths_to_you, flamed, flamed_you, praised, k, x, a}}.
func relations() -> Dictionary:
	var out := {}
	for b in w.bots:
		var h: SimUnit = b.hero()
		if h == null or String(b.pid) == "":
			continue
		var r: Dictionary = (_rel.get(h.id, {}) as Dictionary).duplicate()
		r["k"] = h.kills
		r["x"] = h.deaths
		r["a"] = h.assists
		r["multi"] = h.best_multi
		r["streak"] = h.best_streak
		r["line"] = Career.line_of(w, h)          # its whole line (Ranked: its career, its MMR by how it played)
		out[String(b.pid)] = r
	return out

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
	social.on_end(winner)
	# what the bots thought of the player this game
	for p in _humans():
		var good := float(p.kills) + float(p.assists) * 0.5 >= float(p.deaths) + 2.0
		var bad := float(p.deaths) >= float(p.kills) + float(p.assists) * 0.5 + 4.0
		for b in w.bots:
			var h: SimUnit = b.hero()
			if h == null or b.passive or b.human or _rng.randf() > 0.3:
				continue
			var r: Dictionary = _rel.get(h.id, {})
			var sit := ""
			if h.team == p.team:
				if (good or p.team == winner) and int(r.get("flamed", 0)) == 0:
					sit = "end_like"
				elif bad and _trait(h, "kind") < 0.4:
					sit = "end_dislike"
			elif good and _trait(h, "kind") > 0.55:
				sit = "end_respect"
			if sit != "":
				var text := ChatMind.pick(sit, {"name": pname(p)}, _rng.randf() < float(voice(h).tl), _rng)
				if text != "":
					_queue.append({"at": w.time, "team": h.team, "u": h.id, "text": ChatStyle.apply(text, _style(h), 0.0, _rng),
						"all": h.team != p.team, "cat": sit})
	_flush_all()

## The game is over and the world no longer steps (SimWorld.step), but the player can still type on the end screen:
## what they type is answered at once (the online chat writer's version first: its requests go out before the lines).
func after_end() -> void:
	for e in w.events.duplicate():
		if String(e.get("t", "")) == "chat" and not bool(e.get("after_end", false)):
			e["after_end"] = true
			_on_chat(e)
	if not _intents.is_empty():
		w.events.append_array(_intents)
		_intents.clear()
	for q in _queue:
		w.chat(int(q.team), int(q.u), String(q.text), bool(q.all), true, int(q.get("lid", -1)))
		said += 1
	_queue.clear()

## The game is over (the world stops stepping): end lines go out at once.
func _say_now(h: SimUnit, cat: String, all: bool, _delay: float) -> void:
	var mate := _pick_from(w.heroes.filter(func(x): return x.team == h.team and x != h))
	var text := line(h, cat, {"ally": label(mate)} if mate != null else {})
	if text != "":
		_queue.append({"at": w.time, "team": h.team, "u": h.id, "text": ChatStyle.apply(text, _style(h), float(mind(h).tilt), _rng),
			"all": all, "cat": cat})

func _flush_all() -> void:
	for q in _queue:
		w.chat(int(q.team), int(q.u), String(q.text), bool(q.all), true)
		said += 1
	_queue.clear()
