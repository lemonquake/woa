class_name Ranked
extends RefCounted
## Ranked play (run 2026-10-19 b; the owner's request): your ranked profile (name, picture, MMR from 1000, wins,
## losses, history) and a ladder of bot players with names, pictures, favourite heroes and roles, a hidden skill fixed
## when the profile is made, a behaviour score and a chat voice. Saved in user://ranked.json.
##
## MMR moves like Dota's: the same amount for the whole team, Elo on the two teams' average MMR, 25 for an even game
## (K 50), more for beating a stronger team, less for a weaker one. Leaving a ranked match counts as a loss.
##
## The ladder lives on while you are away: every 3 minutes of real time (at most 30 rounds at a time) and after each of
## your matches, most bots play a round of matches among themselves, grouped by MMR, won by the team with more hidden
## skill (Elo odds, 400 scale). So MMR drifts to where each bot's skill belongs: a new account starts at 1500, about
## one bot in seven starts at a random MMR (smurfs and boosted accounts), and they climb or fall to their level over
## the following days while the top ten (Aetherium+) changes hands.
##
## Living players (run 2026-10-19 d): every profile has a Persona (traits, typing, a daily schedule in its time zone),
## a mood that follows its results, a status ("On a 5 win streak", "Learning Araki", its own words), now and then a
## hero it is learning (kept if it goes well), friends, and a memory of the matches it played with or against you
## ("you": games, results, kills between you, who flamed whom, how much it likes you). Bots that liked a game with you
## send friend requests. The ladder's activity (rank ups, streaks, medals, new heroes, the top of each hero) is kept
## in "feed". The ladder holds 300 players and new accounts keep joining (two a day, up to 420). Older ladder files
## are upgraded in place: nobody's MMR or record changes.

const PATH := "user://ranked.json"
const VERSION := 4                          # 2: hero records and rankings; 3: hero mastery, countries
const YOUR_START := 1000
const BOT_START := 1500
const K := 50.0
const STARS := 5                           # stars in a rank, like Dota's medals (120 MMR each)
const TOP := 10                            # Aetherium+: the leaderboard's top ten (in Aetherium)
const RANKS := [["Rookie", 0], ["Advanced", 600], ["Licensed", 1200], ["Expert", 1800], ["Commander", 2400],
	["Chief Commander", 3000], ["Legendary", 3600], ["Mythic", 4200], ["Hero", 4800], ["Transcendent", 5400],
	["Aetherium", 6000]]
const TOP_NAME := "Aetherium+"
const TIERS := 12
const GUILD_TIER := 2                      # Licensed: guilds open (coming soon)
const ROLE_NAMES := ["Carry", "Mid", "Off Lane", "Soft Support", "Hard Support"]
const ROLE_LANES := ["Safe lane", "Middle lane", "Off lane", "Off lane", "Safe lane"]
const ROUND_SECS := 180
const MAX_CATCHUP := 30
const HISTORY_ME := 60
const HISTORY_BOT := 20
const GRAPH := 60
## The ladder's skill bands: [lowest, highest, bots]. 160 bots; 12 of them good enough for Aetherium.
const BANDS := [[50, 600, 12], [600, 1200, 28], [1200, 1800, 30], [1800, 2400, 26], [2400, 3000, 18], [3000, 3600, 12],
	[3600, 4200, 8], [4200, 4800, 6], [4800, 5400, 4], [5400, 6000, 4], [6000, 7300, 12]]
const PRESEASON := 40                      # ladder rounds played when the ladder is made
const LADDER_SIZE := 300                   # players on a new ladder (an older, smaller one grows to it)
const LADDER_MAX := 420                    # new accounts keep joining, two a day, up to this many
const FEED_MAX := 200
## Hero mastery (the owner, 2026-10-19 b): every player has XP on each hero, earned each match by the result and how
## well they played (a win 100 + up to 60 for the performance, a loss 20 + up to 60). XP gives stars, five to a medal:
## Bronze, Silver, Gold, Platinum, Diamond (25 levels). The first Bronze star takes 350 XP (three wins at least); each
## star costs 18% more than the one before (Gold about 75 wins, Diamond about 450). The five Diamond players with the
## most XP on a hero are its Top 5 .. Top 1 Players.
const MEDALS := ["", "Bronze", "Silver", "Gold", "Platinum", "Diamond"]
const HERO_FIRST := 350.0
const HERO_GROW := 1.18
const HERO_LEVELS := 25
const TOP_HERO := 5
## Where bots are from (a global ladder): country code, name, share. Filipino-sounding names are Filipino.
const COUNTRIES := [["PH", "Philippines"], ["ID", "Indonesia"], ["MY", "Malaysia"], ["TH", "Thailand"], ["VN", "Vietnam"],
	["SG", "Singapore"], ["PE", "Peru"], ["BR", "Brazil"], ["RU", "Russia"], ["UA", "Ukraine"], ["US", "United States"],
	["DE", "Germany"], ["SE", "Sweden"], ["CN", "China"], ["KR", "South Korea"], ["AU", "Australia"]]

static var data := {}
static var rng := RandomNumberGenerator.new()
static var _loaded := false
static var path := PATH                    # tests point this elsewhere
static var _clock := 0                     # the time results are stamped with (0: now; the pre-season sets it)
static var clock_override := 0             # tests: the time "now" returns (0: the real clock)

# ---- Ranks --------------------------------------------------------------------------------------------------------

## The rank (0 Rookie .. 10 Aetherium, 11 Aetherium+) for an MMR and a leaderboard place (1-based; 0 = not known).
static func tier_of(mmr: int, place := 0) -> int:
	var t := 0
	for i in RANKS.size():
		if mmr >= int(RANKS[i][1]):
			t = i
	if t == RANKS.size() - 1 and place >= 1 and place <= TOP:
		return TIERS - 1
	return t

static func tier_name(tier: int) -> String:
	return TOP_NAME if tier >= TIERS - 1 else String(RANKS[clampi(tier, 0, RANKS.size() - 1)][0])

## Where a rank starts, and where the next one starts (-1 for Aetherium and above).
static func tier_floor(tier: int) -> int:
	return int(RANKS[clampi(tier, 0, RANKS.size() - 1)][1])

static func next_floor(tier: int) -> int:
	return int(RANKS[tier + 1][1]) if tier + 1 < RANKS.size() else -1

## Stars inside a rank (1..5, 120 MMR each); Aetherium has none, like Dota's Immortal.
static func stars(mmr: int) -> int:
	var t := tier_of(mmr)
	if t >= RANKS.size() - 1:
		return 0
	return clampi(1 + (mmr - tier_floor(t)) * STARS / (next_floor(t) - tier_floor(t)), 1, STARS)

## "Legendary 3", "Aetherium", "Aetherium+ #4".
static func rank_label(p: Dictionary) -> String:
	var mmr := int(p.get("mmr", 0))
	var pl := place_of(String(p.get("id", "")))
	var t := tier_of(mmr, pl)
	if t == TIERS - 1:
		return "%s #%d" % [TOP_NAME, pl]
	var s := stars(mmr)
	return tier_name(t) + (" %d" % s if s > 0 else "")

static func tier_for(p: Dictionary) -> int:
	return tier_of(int(p.get("mmr", 0)), place_of(String(p.get("id", ""))))

# ---- MMR ----------------------------------------------------------------------------------------------------------

## The chance a team with average skill `a` beats one with `b` (Elo, 400 scale).
static func win_chance(a: float, b: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (b - a) / 400.0))

## The MMR a team with average MMR `mine` gets for a result against `theirs`: +25 / -25 for an even game.
static func elo_delta(mine: float, theirs: float, won: bool) -> int:
	var e := win_chance(mine, theirs)
	var d := int(round(K * ((1.0 if won else 0.0) - e)))
	if won:
		return clampi(d, 5, 45)
	return clampi(d, -45, -5)

# ---- Save and load ------------------------------------------------------------------------------------------------

static func load_data() -> void:
	if _loaded:
		return
	_loaded = true
	rng.randomize()
	if path == PATH and OS.get_environment("WOA_RANKED_FILE") != "":
		path = OS.get_environment("WOA_RANKED_FILE")     # probes and captures keep your own ladder untouched
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and int(d.get("version", 0)) == VERSION and d.get("bots") is Array and d.get("me") is Dictionary \
				and (d.bots as Array).size() >= 100:
			data = d
			_clean()
			return
	new_ladder(rng.randi())
	save()

static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

## Forget what is loaded (tests).
static func reset(p_path := PATH) -> void:
	path = p_path
	_loaded = false
	data = {}

## Numbers read back from JSON are floats: make the counters ints again, fill fields an older file lacks.
static func _clean() -> void:
	for p in all_profiles():
		for k in ["mmr", "wins", "losses", "abandons", "streak", "best_streak", "peak", "behavior", "created"]:
			p[k] = int(p.get(k, 0))
		if not (p.get("history") is Array):
			p["history"] = []
		if not (p.get("graph") is Array):
			p["graph"] = [p.mmr]
		if not (p.get("avatar") is Dictionary):
			p["avatar"] = {"k": "none"}
		if not (p.get("roles") is Array):
			p["roles"] = []
		p["roles"] = (p.roles as Array).map(func(r): return int(r))       # JSON gives floats; roles are ints
		if not (p.get("heroes") is Array):
			p["heroes"] = []
		var hs := {}
		if p.get("hero_stats") is Dictionary:
			for h in p.hero_stats:
				var v = p.hero_stats[h]
				if v is Array and (v as Array).size() >= 2:
					hs[String(h)] = [int(v[0]), int(v[1]), int(v[2]) if (v as Array).size() > 2 else 0]
		p["hero_stats"] = hs
	for k in ["last_sim", "rounds"]:
		data[k] = int(data.get(k, 0))
	if not (data.get("pending") is Dictionary):
		data["pending"] = {}
	_upgrade()

## Living players (run 2026-10-19 d) on a ladder saved before them: a persona for every bot (from the ladder's seed and
## the bot's id, so it is the same each time), the new fields, friends, the feed; a smaller ladder grows to
## LADDER_SIZE. Nobody's MMR or record changes.
static func _upgrade() -> void:
	var seed := int(data.get("seed", 1))
	var made := false
	for b in data.bots:
		if not (b.get("persona") is Dictionary) or (b.persona as Dictionary).is_empty():
			b["persona"] = Persona.make(absi(hash("%d:%s" % [seed, String(b.id)])), b)
			made = true
		b["mood"] = float(b.get("mood", 0.0))
		b["learning"] = String(b.get("learning", ""))
		b["learn_n"] = int(b.get("learn_n", 0))
		if not (b.get("friends") is Array):
			b["friends"] = []
		if not (b.get("you") is Dictionary):
			b["you"] = {}
		var ps: Dictionary = b.persona
		ps["shift"] = int(ps.get("shift", 0))
		ps["seed"] = int(ps.get("seed", 0))
		var yo: Dictionary = b.you
		for k in yo.keys():
			if yo[k] is float and k != "rep":
				yo[k] = int(yo[k])
	var me_p: Dictionary = data.me
	if not (me_p.get("met") is Dictionary):
		me_p["met"] = {}
	for k in (me_p.met as Dictionary).keys():
		me_p.met[k] = int(me_p.met[k])
	if not (me_p.get("friends") is Array):
		me_p["friends"] = []
	if not (me_p.get("requests") is Array):
		me_p["requests"] = []
	if not (data.get("feed") is Array):
		data["feed"] = []
	if not (data.get("tops") is Dictionary):
		data["tops"] = {}
	data["grow_t"] = int(data.get("grow_t", data.get("last_sim", now())))
	if (data.bots as Array).size() < LADDER_SIZE:
		var r := RandomNumberGenerator.new()
		r.seed = seed ^ 0x51ab
		var start := (data.bots as Array).size()
		_grow(LADDER_SIZE - start, r, false)
		_make_friends(r, start)
		made = true
	elif made:
		var r2 := RandomNumberGenerator.new()
		r2.seed = seed ^ 0x51ab
		_make_friends(r2, 0)
	if made:
		_mark_dirty()

static func me() -> Dictionary:
	load_data()
	return data.me

static func bots() -> Array:
	load_data()
	return data.bots

static func all_profiles() -> Array:
	var out: Array = [data.me] if data.has("me") else []
	if data.has("bots"):
		out.append_array(data.bots)
	return out

static func profile(id: String) -> Dictionary:
	load_data()
	if id == "me":
		return data.me
	for b in data.bots:
		if String(b.id) == id:
			return b
	return {}

static func now() -> int:
	if clock_override > 0:
		return clock_override
	return int(Time.get_unix_time_from_system())

## When a result happened (a round's own time during the pre-season and catch-up, else now).
static func stamp() -> int:
	return _clock if _clock > 0 else now()

# ---- The ladder -----------------------------------------------------------------------------------------------------

## Make a new ladder: your profile at 1000 and 160 bots (skill from BANDS, their MMR settled near it, at 1500 for a
## new account or random), then a short pre-season so everyone has a record.
static func new_ladder(seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var names := BotNames.make_many(_bot_count() + 20, r)
	var you_name := "Player"
	var prefs: Dictionary = NetBrowser.load_prefs()
	if String(prefs.get("name", "")).strip_edges() != "":
		you_name = String(prefs.name).strip_edges().substr(0, 20)
	var t := now()
	data = {"version": VERSION, "seed": seed, "last_sim": t, "rounds": 0, "pending": {},
		"me": {"id": "me", "name": you_name, "mmr": YOUR_START, "wins": 0, "losses": 0, "abandons": 0, "streak": 0,
			"best_streak": 0, "peak": YOUR_START, "history": [], "graph": [YOUR_START], "avatar": {"k": "none"},
			"behavior": 10000, "roles": [1, 2, 3, 4, 5], "heroes": [], "created": t, "bot": false, "hero_stats": {},
			"country": "", "met": {}, "friends": [], "requests": []},
		"bots": []}
	var i := 0
	for band in BANDS:
		for n in _band_count(band):
			var skill := r.randf_range(float(band[0]), float(band[1]))
			data.bots.append(_make_bot(i, String(names[i]), skill, r, t))
			i += 1
	data["feed"] = []
	data["tops"] = {}
	data["grow_t"] = t
	_make_friends(r, 0)
	# the pre-season: one round every 40 minutes up to now
	for k in PRESEASON:
		_clock = t - (PRESEASON - k) * 2400
		simulate_rounds(1, r)
	_clock = 0
	data.rounds = 0
	data.last_sim = t

static func _bot_count() -> int:
	var n := 0
	for band in BANDS:
		n += _band_count(band)
	return n

## Bots in a skill band on a new ladder (BANDS give the shares for 160; the ladder holds LADDER_SIZE).
static func _band_count(band: Array) -> int:
	return int(round(float(band[2]) * float(LADDER_SIZE) / 160.0))

## `n` new accounts join the ladder: skill drawn the way the bands share it out, names unlike any on the ladder.
## new_only: brand new accounts (at 1500, now and then a smurf at a random MMR, no record before).
static func _grow(n: int, r: RandomNumberGenerator, new_only: bool) -> void:
	var seen := {}
	var top_i := 0
	for b in data.bots:
		seen[BotNames.key(String(b.name))] = true
		top_i = maxi(top_i, int(String(b.id).substr(1)) + 1)
	var total := 0
	for band in BANDS:
		total += int(band[2])
	var t := now()
	for k in n:
		var nm := ""
		for guard in 80:
			var cand := BotNames.make(r)
			if cand.length() >= 3 and cand.length() <= 22 and not seen.has(BotNames.key(cand)):
				nm = cand
				break
		if nm == "":
			nm = "player%d" % (top_i + k)
		seen[BotNames.key(nm)] = true
		var roll := r.randi_range(1, total)
		var band: Array = BANDS[0]
		for bd in BANDS:
			roll -= int(bd[2])
			if roll <= 0:
				band = bd
				break
		var skill := r.randf_range(float(band[0]), float(band[1]))
		var b := _make_bot(top_i + k, nm, skill, r, t)
		if new_only:
			b.start = "new"
			b.mmr = BOT_START if r.randf() < 0.85 else r.randi_range(300, 5000)
			b.wins = r.randi_range(0, 4)
			b.losses = r.randi_range(0, 4)
			b.graph = [int(b.mmr)]
			b.peak = int(b.mmr)
			b.created = t - r.randi_range(0, 3) * 86400
			for h in (b.hero_stats as Dictionary).keys():
				b.hero_stats[h] = [0, 0, 0]
		data.bots.append(b)

## Friends: most players have one to three, from their own country when they can, near their skill. Bots from
## `from` on get theirs (and become friends of older ones).
static func _make_friends(r: RandomNumberGenerator, from: int) -> void:
	var bots: Array = data.bots
	for i in range(from, bots.size()):
		var b: Dictionary = bots[i]
		if (b.friends as Array).size() >= 2 or r.randf() < 0.25:
			continue
		var want := r.randi_range(1, 3) - (b.friends as Array).size()
		var tries := 0
		while want > 0 and tries < 60:
			tries += 1
			var o: Dictionary = bots[r.randi_range(0, bots.size() - 1)]
			if String(o.id) == String(b.id) or String(o.id) in (b.friends as Array) or (o.friends as Array).size() >= 4:
				continue
			if absf(float(o.skill) - float(b.skill)) > 900.0:
				continue
			if String(o.country) != String(b.country) and r.randf() < 0.75:
				continue
			(b.friends as Array).append(String(o.id))
			(o.friends as Array).append(String(b.id))
			want -= 1

static func _make_bot(i: int, nm: String, skill: float, r: RandomNumberGenerator, t: int) -> Dictionary:
	var s := clampf(skill / 7000.0, 0.0, 1.0)
	# where its MMR starts: settled near its skill, a new account at 1500, or anywhere (the top always settled)
	var start := "settled"
	var mmr := skill + r.randfn(0.0, 110.0)
	var roll := r.randf()
	if skill < 6000.0 and roll < 0.16:
		start = "new"
		mmr = BOT_START
	elif skill < 6000.0 and roll < 0.30:
		start = "random"
		mmr = r.randf_range(100.0, 6200.0)
	# personality: low skill leans toxic and selfish; about one low bot in six is a ragebaiter
	var rage := r.randf() < lerpf(0.18, 0.03, s)
	var toxic: float
	var coop: float
	if rage:
		toxic = r.randf_range(0.8, 1.0)
		coop = r.randf_range(0.05, 0.3)
	else:
		toxic = clampf(r.randf_range(0.0, 0.75) * (1.15 - 0.7 * s), 0.0, 1.0)
		coop = clampf(lerpf(0.45, 0.97, s) + r.randf_range(-0.18, 0.08), 0.05, 1.0)
	var disrupt := clampf((1.0 - coop) * (1.0 - 0.8 * s) * (1.2 if rage else 0.8), 0.0, 1.0)
	var kind: int = [0, 0, 0, 0, 1, 1, 1, 2, 2, 2][r.randi_range(0, 9)]   # Pinoy, Taglish or English
	var voice := {"tl": [0.75, 0.45, 0.08][kind], "salt": clampf(0.3 + toxic * 0.7, 0.0, 1.0),
		"rough": clampf([0.35, 0.2, 0.05][kind] * (0.3 + toxic * 1.3), 0.0, 0.8)}
	var behavior := clampi(int(11200.0 - toxic * 5200.0 - (1.0 - coop) * 3600.0 + r.randf_range(-700.0, 500.0)), 600, 12000)
	# roles and favourite heroes that play them
	var main_role := r.randi_range(1, 5)
	var roles: Array = [main_role]
	if r.randf() < 0.6:
		var second := r.randi_range(1, 5)
		if second != main_role:
			roles.append(second)
	var heroes: Array = []
	var pool: Array = GameSettings.random_pool()
	var fits: Array = pool.filter(func(h): return main_role in SimBotKits.roles(String(h)).slice(0, 3))
	for n in 3:
		var from: Array = fits if not fits.is_empty() and r.randf() < 0.8 else pool
		var h := String(from[r.randi_range(0, from.size() - 1)])
		if not (h in heroes):
			heroes.append(h)
	if heroes.is_empty():
		heroes.append(String(pool[0]))
	var av_roll := r.randf()
	var avatar := {"k": "hero", "id": heroes[0]} if av_roll < 0.32 else ({"k": "face", "seed": r.randi()} if av_roll < 0.9 else {"k": "none"})
	# a record before the ladder began: better players have played more
	# the best players have played for years: thousands of games, most on a few heroes (their mastery shows it)
	var games := int(lerpf(30.0, 3400.0, pow(s, 1.3)) * r.randf_range(0.5, 1.3))
	if start == "new":
		games = r.randi_range(0, 12)
	var wr := clampf(0.5 + r.randf_range(-0.035, 0.045), 0.3, 0.7)
	var wins := int(round(games * wr))
	var m := int(round(mmr))
	var hero_stats := {}
	var shares := [0.5, 0.3, 0.2]
	for k in heroes.size():
		var g := int(round(games * float(shares[k]) * r.randf_range(0.7, 1.2)))
		var hw := int(round(g * clampf(wr + r.randf_range(-0.06, 0.06), 0.2, 0.8)))
		if g > 0:
			hero_stats[String(heroes[k])] = [hw, g - hw, int(hw * (100.0 + 45.0 * s) * r.randf_range(0.9, 1.1)
				+ (g - hw) * (20.0 + 14.0 * s))]
	var country := _country_for(nm, r)
	if country != "PH" and country != "":
		kind = 2                               # an English voice for players from elsewhere
		voice = {"tl": 0.05, "salt": voice.salt, "rough": clampf(0.05 * (0.3 + toxic * 1.3), 0.0, 0.8)}
	var p := {"id": "b%d" % i, "name": nm, "bot": true, "skill": int(round(skill)), "mmr": maxi(0, m), "start": start,
		"wins": wins, "losses": games - wins, "abandons": 0, "streak": 0, "best_streak": r.randi_range(2, 9),
		"peak": maxi(m, int(skill) + r.randi_range(0, 220)), "history": [], "graph": [maxi(0, m)], "avatar": avatar,
		"behavior": behavior, "roles": roles, "heroes": heroes, "toxic": snappedf(toxic, 0.01),
		"coop": snappedf(coop, 0.01), "disrupt": snappedf(disrupt, 0.01), "rage": rage, "voice": voice,
		"created": t - r.randi_range(3, 900) * 86400, "hero_stats": hero_stats, "country": country,
		"mood": 0.0, "learning": "", "learn_n": 0, "friends": [], "you": {}}
	p["persona"] = Persona.make(r.randi(), p)
	return p

## Play `n` rounds of bot matches: about 60% of the bots (not those in `busy`) play one each, ten at a time in MMR
## order with some noise, split into two teams of even MMR; the team with more hidden skill tends to win.
static func simulate_rounds(n: int, r: RandomNumberGenerator = null, busy := {}) -> int:
	if r == null:
		r = rng
	var played := 0
	for round_i in n:
		var keyed: Array = []
		var t := stamp()
		for b in data.bots:
			# players online at that hour play most rounds, players away a few (Persona's schedule)
			var on := Persona.online(b, t)
			if not busy.has(String(b.id)) and r.randf() < (0.8 if on else 0.12):
				keyed.append([float(b.mmr) + r.randf_range(-160.0, 160.0), b])
		keyed.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		var i := 0
		while i + 10 <= keyed.size():
			var group: Array = []
			for j in 10:
				group.append(keyed[i + j][1])
			i += 10
			var ta: Array = [group[0], group[3], group[4], group[7], group[8]]
			var tb: Array = [group[1], group[2], group[5], group[6], group[9]]
			var won_a := r.randf() < win_chance(_avg(ta, "skill") + r.randfn(0.0, 60.0), _avg(tb, "skill") + r.randfn(0.0, 60.0))
			var d := elo_delta(_avg(ta, "mmr"), _avg(tb, "mmr"), won_a)
			var length := r.randi_range(24, 52) * 60 + r.randi_range(0, 59)
			for side in 2:
				var team: Array = ta if side == 0 else tb
				var won := won_a if side == 0 else not won_a
				for p in team:
					var hero := _sim_hero(p, r)
					var role := int(p.roles[0])
					var ex := _sim_line(p, won, role, length, r)
					_record(p, won, d if side == 0 else -d, hero, role, false, ex)
					_after_game(p, hero, r)
			played += 1
		data.rounds = int(data.get("rounds", 0)) + 1
	_check_tops()
	return played

## The hero a bot plays in a ladder match: the one it is learning about half the time, else its own heroes (the
## first most).
static func _sim_hero(p: Dictionary, r: RandomNumberGenerator) -> String:
	var learning := String(p.get("learning", ""))
	if learning != "" and r.randf() < 0.5:
		return learning
	var hs: Array = p.heroes
	var x := r.randf()
	var i := 0 if x < 0.5 or hs.size() == 1 else (1 if x < 0.8 or hs.size() == 2 else 2)
	return String(hs[mini(i, hs.size() - 1)])

## A bot's line in a ladder match, for its history: kills, deaths, assists by role, skill and result; the length.
static func _sim_line(p: Dictionary, won: bool, role: int, length: int, r: RandomNumberGenerator) -> Dictionary:
	var sk := clampf(float(p.get("skill", 2000)) / 7000.0, 0.0, 1.0)
	var mins := float(length) / 60.0
	var core := role <= 3
	var k := maxi(0, int(round(r.randfn((0.24 if core else 0.09) * mins * (1.25 if won else 0.75) * (0.8 + sk * 0.4), 2.0))))
	var x := maxi(0, int(round(r.randfn(0.17 * mins * (0.7 if won else 1.25) * (1.15 - sk * 0.3), 1.8))))
	var a := maxi(0, int(round(r.randfn((0.28 if core else 0.42) * mins * (1.2 if won else 0.8), 2.5))))
	return {"k": k, "x": x, "a": a, "len": length}

## After a ladder match: the bot's mood, the hero it is learning (kept if it goes well), and what the ladder hears
## about (a rank reached, a long streak, a new medal).
static func _after_game(p: Dictionary, hero: String, r: RandomNumberGenerator) -> void:
	var ps: Dictionary = p.get("persona", {})
	var temper := float(ps.get("temper", 0.4))
	var last: Dictionary = p.history[0] if not (p.history as Array).is_empty() else {}
	var won := String(last.get("r", "L")) == "W"
	p["mood"] = snappedf(clampf(float(p.get("mood", 0.0)) * 0.8 + (0.22 if won else -0.18 - temper * 0.12), -1.0, 1.0), 0.01)
	# rank reached (Expert and up), streaks of 5, 8 and 12
	var before := tier_of(int(p.mmr) - int(last.get("d", 0)))
	var after := tier_of(int(p.mmr))
	if after > before and after >= 4:
		_feed(String(p.id), "rank", after)
	var st := int(p.streak)
	if st in [6, 9, 12]:
		_feed(String(p.id), "streak", st)
	# a new medal on the hero (Gold and up)
	var hs: Array = (p.hero_stats as Dictionary).get(hero, [0, 0, 0])
	var xp := int(hs[2]) if hs.size() > 2 else 0
	var sk := clampf(float(p.get("skill", 2000)) / 7000.0, 0.0, 1.0)
	var gain := int(last.get("hx", 0)) if last.has("hx") else int((100.0 + 45.0 * sk) if won else (20.0 + 14.0 * sk))
	var m0 := (hero_level(maxi(0, xp - gain)) - 1) / 5 + 1 if hero_level(maxi(0, xp - gain)) > 0 else 0
	var m1 := (hero_level(xp) - 1) / 5 + 1 if hero_level(xp) > 0 else 0
	if m1 > m0 and m1 >= 3:
		_feed(String(p.id), "medal", [hero, m1])
	# learning a hero: started now and then, kept when it went well (it becomes one of theirs)
	var learning := String(p.get("learning", ""))
	if learning != "":
		if hero == learning:
			p["learn_n"] = int(p.get("learn_n", 0)) + 1
		if int(p.learn_n) >= 14:
			var ls: Array = (p.hero_stats as Dictionary).get(learning, [0, 0, 0])
			var wr := float(ls[0]) / maxf(1.0, float(ls[0]) + float(ls[1]))
			if wr >= 0.5 or r.randf() < 0.35:
				var heroes: Array = p.heroes
				if heroes.size() >= 3:
					heroes[heroes.size() - 1] = learning
				else:
					heroes.append(learning)
				_feed(String(p.id), "main", learning)
			p["learning"] = ""
			p["learn_n"] = 0
	elif r.randf() < 1.0 / 220.0:
		var pool: Array = GameSettings.random_pool().filter(func(h): return not (h in (p.heroes as Array)))
		var fits: Array = pool.filter(func(h): return int(p.roles[0]) in SimBotKits.roles(String(h)).slice(0, 3))
		var from: Array = fits if not fits.is_empty() else pool
		if not from.is_empty():
			p["learning"] = String(from[r.randi_range(0, from.size() - 1)])
			p["learn_n"] = 0
			_feed(String(p.id), "learning", p.learning)

## The ladder's news (Players screen): {t, id, k: rank | streak | medal | main | learning | top | top10 | friend, a}.
static func _feed(id: String, k: String, a) -> void:
	if not (data.get("feed") is Array):
		data["feed"] = []
	(data.feed as Array).push_front({"t": stamp(), "id": id, "k": k, "a": a})
	while (data.feed as Array).size() > FEED_MAX:
		(data.feed as Array).pop_back()

## The best player on each hero, and the top ten of the ladder: changes go into the feed.
static func _check_tops() -> void:
	if not (data.get("tops") is Dictionary):
		data["tops"] = {}
	_mark_dirty()
	for hero in GameSettings.random_pool():
		var b := hero_board(String(hero))
		if b.is_empty():
			continue
		var top := String(b[0].id)
		var was := String((data.tops as Dictionary).get(hero, ""))
		if top != was:
			if was != "" and top != "me":
				_feed(top, "top", hero)
			data.tops[hero] = top
	var ten: Array = leaderboard().slice(0, TOP).map(func(p): return String(p.id))
	var old: Array = (data.tops as Dictionary).get("_ten", [])
	for id in ten:
		if not old.is_empty() and not (id in old) and id != "me":
			_feed(id, "top10", 0)
	data.tops["_ten"] = ten

static func _avg(team: Array, key: String) -> float:
	var s := 0.0
	for p in team:
		s += float(p.get(key, p.get("mmr", 0)))
	return s / maxf(1.0, float(team.size()))

## Rounds owed for the time since the ladder last moved (one per 3 minutes, at most 30 at once).
static func catch_up() -> int:
	load_data()
	var t := now()
	var owed := (t - int(data.last_sim)) / ROUND_SECS
	if owed <= 0:
		return 0
	var n := mini(owed, MAX_CATCHUP)
	var t0 := t - n * ROUND_SECS
	for i in n:
		_clock = t0 + (i + 1) * ROUND_SECS            # each round stamped with its own time
		simulate_rounds(1)
	_clock = 0
	data.last_sim = t if owed > MAX_CATCHUP else int(data.last_sim) + n * ROUND_SECS
	_grow_daily(t)
	save()
	return n

## New accounts join the ladder: two a day of real time (at most 30 at once), up to LADDER_MAX.
static func _grow_daily(t: int) -> void:
	var days := (t - int(data.get("grow_t", t))) / 86400
	if days <= 0:
		return
	data["grow_t"] = int(data.get("grow_t", t)) + days * 86400
	var room := LADDER_MAX - (data.bots as Array).size()
	var add := mini(mini(days * 2, 30), room)
	if add <= 0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d" % [int(data.get("seed", 1)), t / 86400])
	var start := (data.bots as Array).size()
	_grow(add, r, true)
	_make_friends(r, start)
	_mark_dirty()

## One result on a profile: MMR, wins / losses, streaks, peak, history and graph.
static func _record(p: Dictionary, won: bool, d: int, hero: String, role: int, abandon: bool, extra := {}) -> void:
	p.mmr = maxi(0, int(p.mmr) + d)
	if won:
		p.wins = int(p.wins) + 1
		p.streak = maxi(0, int(p.streak)) + 1
		p.best_streak = maxi(int(p.best_streak), int(p.streak))
	else:
		p.losses = int(p.losses) + 1
		p.streak = mini(0, int(p.streak)) - 1
	if abandon:
		p.abandons = int(p.abandons) + 1
	p.peak = maxi(int(p.peak), int(p.mmr))
	if hero != "":
		if not (p.get("hero_stats") is Dictionary):
			p["hero_stats"] = {}
		var hs: Array = p.hero_stats.get(hero, [0, 0, 0])
		var gain := int(extra.get("hx", -1))
		if gain < 0:
			# a bot's game: the result and how well a player of its skill plays
			var sk := clampf(float(p.get("skill", 2000)) / 7000.0, 0.0, 1.0)
			gain = int((100.0 + 45.0 * sk) if won else (20.0 + 14.0 * sk))
		p.hero_stats[hero] = [int(hs[0]) + (1 if won else 0), int(hs[1]) + (0 if won else 1), int(hs[2] if hs.size() > 2 else 0) + gain]
	var e := {"r": "A" if abandon else ("W" if won else "L"), "d": d, "m": int(p.mmr), "t": _clock if _clock > 0 else now(),
		"h": hero, "o": role}
	var ex2 := extra.duplicate()
	ex2.erase("hx")
	ex2.erase("rel")
	e.merge(ex2)
	if hero != "" and extra.has("hx"):
		e["hx"] = int(extra.hx)
	(p.history as Array).push_front(e)
	var keep := HISTORY_BOT if bool(p.get("bot", false)) else HISTORY_ME
	while (p.history as Array).size() > keep:
		(p.history as Array).pop_back()
	(p.graph as Array).append(int(p.mmr))
	while (p.graph as Array).size() > GRAPH:
		(p.graph as Array).pop_front()

# ---- The leaderboard ----------------------------------------------------------------------------------------------

static var _board: Array = []
static var _board_rounds := -1
static var _board_mmr := -1

## Everyone by MMR, highest first (you included).
static func leaderboard() -> Array:
	load_data()
	var key := int(data.rounds) * 100000 + int(data.me.mmr)
	if _board_rounds == key and _board.size() == data.bots.size() + 1:
		return _board
	_board = all_profiles()
	_board.sort_custom(func(a, b): return int(a.mmr) > int(b.mmr) if int(a.mmr) != int(b.mmr) else String(a.id) < String(b.id))
	_board_rounds = key
	return _board

## A profile's leaderboard place (1-based), 0 if unknown.
static func place_of(id: String) -> int:
	if id == "":
		return 0
	var b := leaderboard()
	for i in b.size():
		if String(b[i].id) == id:
			return i + 1
	return 0

## The MMR change over a profile's last `n` games.
static func trend(p: Dictionary, n := 5) -> int:
	var s := 0
	var h: Array = p.get("history", [])
	for i in mini(n, h.size()):
		s += int(h[i].get("d", 0))
	return s

static func win_rate(p: Dictionary) -> float:
	var g := int(p.wins) + int(p.losses)
	return float(p.wins) / float(g) if g > 0 else 0.0

static func _mark_dirty() -> void:
	_board_rounds = -1
	_hero_key = -1

# ---- Your matches -------------------------------------------------------------------------------------------------

## A ranked match begins: remember it (until it ends, leaving the game counts as a loss).
## m: {teams: [[ids], [ids]], mine: team index of "me", heroes: {id: hero}, roles: {id: role}}
static func begin_match(m: Dictionary) -> void:
	load_data()
	data.pending = m.duplicate(true)
	data.pending["t"] = now()
	save()

static func has_pending() -> bool:
	load_data()
	return not (data.pending as Dictionary).is_empty()

## The match ended (or was left): MMR for all ten, your summary back.
## Returns {delta, old, new, old_tier, new_tier, place, abandon}.
static func finish_match(won: bool, abandon := false, extra := {}) -> Dictionary:
	load_data()
	var m: Dictionary = data.pending
	if m.is_empty():
		return {}
	var mine := int(m.get("mine", 0))
	var teams: Array = m.get("teams", [[], []])
	var ps := [[], []]
	for t in 2:
		for id in teams[t]:
			var p := profile(String(id))
			if not p.is_empty():
				(ps[t] as Array).append(p)
	var you := me()
	var old := int(you.mmr)
	var old_tier := tier_for(you)
	var my_hero := String((m.get("heroes", {}) as Dictionary).get("me", ""))
	var hm_old := hero_medal(you, my_hero) if my_hero != "" else {}
	var d := elo_delta(_avg(ps[mine], "mmr"), _avg(ps[1 - mine], "mmr"), won)
	var heroes: Dictionary = m.get("heroes", {})
	var roles: Dictionary = m.get("roles", {})
	for t in 2:
		var w := won if t == mine else not won
		for p in ps[t]:
			var id := String(p.id)
			var ex := extra.duplicate() if id == "me" else {}
			if id == "me":
				ex["hx"] = hero_xp_gain(w, float(extra.get("perf", 0.5)), abandon)
			else:
				# a bot's own line of this match (SimBotChat.relations), for its history
				var br: Dictionary = (extra.get("rel", {}) as Dictionary).get(id, {})
				if br.has("k"):
					ex = {"k": int(br.k), "x": int(br.get("x", 0)), "a": int(br.get("a", 0))}
					if extra.has("len"):
						ex["len"] = int(extra.len)
			_record(p, w, d if t == mine else -d, String(heroes.get(id, "")), int(roles.get(id, 0)), abandon and id == "me", ex)
	if abandon:
		you.behavior = maxi(0, int(you.behavior) - 400)
	else:
		you.behavior = mini(12000, int(you.behavior) + 100)
	var asked := _remember(ps, mine, won, abandon, extra, heroes)
	data.pending = {}
	# the rest of the ladder played while you did
	var busy := {}
	for t in 2:
		for id in teams[t]:
			busy[String(id)] = true
	simulate_rounds(3, rng, busy)
	data.last_sim = now()
	_mark_dirty()
	save()
	var out := {"delta": d, "old": old, "new": int(you.mmr), "old_tier": old_tier, "new_tier": tier_for(you),
		"place": place_of("me"), "abandon": abandon, "won": won, "hero": my_hero, "requests": asked}
	if my_hero != "":
		out["hero_old"] = hm_old
		out["hero_new"] = hero_medal(you, my_hero)
		out["hero_xp"] = int(you.history[0].get("hx", 0)) if not (you.history as Array).is_empty() else 0
	return out

## A ranked match left without an end (quit, crash, closed window): a loss, as in Dota.
static func abandon_pending() -> Dictionary:
	if not has_pending():
		return {}
	return finish_match(false, true)

## Every bot of a finished match remembers it (its "you"): games with and against you, the results, the kills
## between you, who flamed whom (SimBotChat.relations() in extra.rel), and how much it likes you (rep, -1..1). Your
## profile keeps when you last met each (me.met). A bot that liked the game may send a friend request.
## Returns the ids that asked.
static func _remember(ps: Array, mine: int, won: bool, abandon: bool, extra: Dictionary, heroes: Dictionary) -> Array:
	var you := me()
	var rel: Dictionary = extra.get("rel", {})
	var yk := int(extra.get("k", 0))
	var yx := int(extra.get("x", 0))
	var ya := int(extra.get("a", 0))
	var good := float(yk) + float(ya) * 0.5 >= float(yx) + 2.0
	var bad := float(yx) >= float(yk) + float(ya) * 0.5 + 4.0
	var asked: Array = []
	var t := now()
	for side in 2:
		for p in ps[side]:
			var id := String(p.id)
			if id == "me":
				continue
			var with := side == mine
			var bot_won := won if with else not won
			var r: Dictionary = rel.get(id, {})
			var y: Dictionary = p.get("you", {})
			var kind := float((p.get("persona", {}) as Dictionary).get("kind", 0.5))
			y["games"] = int(y.get("games", 0)) + 1
			if with:
				y["with"] = int(y.get("with", 0)) + 1
				y["with_w"] = int(y.get("with_w", 0)) + (1 if won else 0)
			else:
				y["vs"] = int(y.get("vs", 0)) + 1
				y["vs_w"] = int(y.get("vs_w", 0)) + (1 if bot_won else 0)
			y["kills_on"] = int(y.get("kills_on", 0)) + int(r.get("kills_on_you", 0))
			y["deaths_to"] = int(y.get("deaths_to", 0)) + int(r.get("deaths_to_you", 0))
			y["flamed"] = int(y.get("flamed", 0)) + int(r.get("flamed", 0))
			y["flamed_you"] = int(y.get("flamed_you", 0)) + int(r.get("flamed_you", 0))
			y["praised"] = int(y.get("praised", 0)) + int(r.get("praised", 0))
			y["last_side"] = "with" if with else "vs"
			y["last_res"] = "W" if bot_won else "L"
			y["last_kills_on"] = int(r.get("kills_on_you", 0))
			y["last_hero"] = String(heroes.get(id, ""))
			y["your_hero"] = String(heroes.get("me", ""))
			y["last_t"] = t
			# how much it likes you: a win together, your game, your words; a rough loser likes nobody
			var dr := 0.0
			if with:
				dr += 0.18 if won else -0.06
				dr += 0.1 if good else (-0.14 if bad else 0.0)
				if abandon:
					dr -= 0.5
			else:
				dr += 0.06 if good and kind > 0.55 else (-0.04 if bot_won else 0.0)
			dr -= 0.22 * float(r.get("flamed", 0))
			dr += 0.12 * float(r.get("praised", 0))
			dr += (kind - 0.5) * 0.12
			y["rep"] = snappedf(clampf(float(y.get("rep", 0.0)) + dr, -1.0, 1.0), 0.01)
			p["you"] = y
			(you.met as Dictionary)[id] = t
			# a friend request after a good game together (or a well played one against)
			if not (id in (you.friends as Array)) and not _requested(id):
				var ch := 0.0
				if with and float(y.rep) > 0.3:
					ch = 0.2 + kind * 0.35
				elif not with and good and float(y.rep) > 0.15 and kind > 0.6:
					ch = 0.08
				if rng.randf() < ch:
					(you.requests as Array).append({"id": id, "t": t, "after": "with" if with else "vs"})
					asked.append(id)
	return asked

static func _requested(id: String) -> bool:
	for q in me().get("requests", []):
		if String(q.get("id", "")) == id:
			return true
	return false

## Friends (Players screen).
static func accept_request(id: String) -> void:
	var you := me()
	you.requests = (you.requests as Array).filter(func(q): return String(q.get("id", "")) != id)
	if not (id in (you.friends as Array)):
		(you.friends as Array).append(id)
		var b := profile(id)
		if not b.is_empty():
			(b.get("you", {}) as Dictionary)["friend"] = true
			b.you["rep"] = maxf(0.4, float(b.you.get("rep", 0.0)))
		_feed(id, "friend", 0)
	save()

## You ask a player to be friends: one who likes you, or a kind one who has nothing against you, says yes.
static func ask_friend(id: String) -> bool:
	var b := profile(id)
	if b.is_empty() or id == "me":
		return false
	var y: Dictionary = b.get("you", {})
	var kind := float((b.get("persona", {}) as Dictionary).get("kind", 0.5))
	var rep := float(y.get("rep", 0.0))
	var ok := rep > 0.25 or (rep > -0.15 and rng.randf() < 0.25 + kind * 0.6)
	if ok:
		accept_request(id)
	return ok

static func ignore_request(id: String) -> void:
	var you := me()
	you.requests = (you.requests as Array).filter(func(q): return String(q.get("id", "")) != id)
	save()

static func remove_friend(id: String) -> void:
	var you := me()
	you.friends = (you.friends as Array).filter(func(x): return String(x) != id)
	var b := profile(id)
	if not b.is_empty() and b.get("you") is Dictionary:
		b.you["friend"] = false
	save()

## Players you met in ranked, most recent first: [[profile, unix time]].
static func recent_players(n := 30) -> Array:
	var out: Array = []
	var met: Dictionary = me().get("met", {})
	for id in met:
		var p := profile(String(id))
		if not p.is_empty():
			out.append([p, int(met[id])])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return out.slice(0, n)

## How many players are online now, and how many of them in a match.
static func online_counts() -> Array:
	var t := now()
	var on := 0
	var playing := 0
	for b in bots():
		if Persona.online(b, t):
			on += 1
			if Persona.in_match(b, t):
				playing += 1
	return [on, playing]

## A feed entry in words ("Mika reached Mythic", "Ken started learning Araki").
static func feed_text(e: Dictionary) -> String:
	var p := profile(String(e.get("id", "")))
	var nm := String(p.get("name", "Someone"))
	var a = e.get("a", 0)
	match String(e.get("k", "")):
		"rank":
			return "%s reached %s" % [nm, tier_name(int(a))]
		"streak":
			return "%s is on a %d win streak" % [nm, int(a)]
		"medal":
			return "%s earned %s on %s" % [nm, String(MEDALS[clampi(int(a[1]), 0, 5)]), HeroDraft.hero_name(String(a[0]))]
		"main":
			return "%s now plays %s" % [nm, HeroDraft.hero_name(String(a))]
		"learning":
			return "%s started learning %s" % [nm, HeroDraft.hero_name(String(a))]
		"top":
			return "%s is the new Top 1 Player on %s" % [nm, HeroDraft.hero_name(String(a))]
		"top10":
			return "%s made the top ten" % nm
		"friend":
			return "You and %s are now friends" % nm
	return nm

static func set_player_name(s: String) -> void:
	var n := s.strip_edges().substr(0, 20)
	if n != "":
		var p := me()
		p["name"] = n
		save()

static func set_avatar(spec: Dictionary) -> void:
	var p := me()
	p["avatar"] = spec
	save()

static func set_roles(roles: Array) -> void:
	var p := me()
	p["roles"] = roles.duplicate()
	save()

# ---- Hero mastery and rankings --------------------------------------------------------------------------------------

static var _hero_boards := {}
static var _hero_key := -1

## XP a match gives on the hero played: a win 100, a loss 20, plus up to 60 for the performance (0..1); nothing when
## the match was left.
static func hero_xp_gain(won: bool, perf: float, left := false) -> int:
	if left:
		return 0
	return int((100.0 if won else 20.0) + round(60.0 * clampf(perf, 0.0, 1.0)))

## The XP to reach mastery level L (1 = Bronze 1 star .. 25 = Diamond 5 stars).
static func hero_xp_for(level: int) -> int:
	if level <= 0:
		return 0
	return int(round(HERO_FIRST * (pow(HERO_GROW, float(level)) - 1.0) / (HERO_GROW - 1.0)))

static func hero_level(xp: int) -> int:
	var lv := 0
	while lv < HERO_LEVELS and xp >= hero_xp_for(lv + 1):
		lv += 1
	return lv

static func hero_xp(p: Dictionary, hero: String) -> int:
	var hs = (p.get("hero_stats", {}) as Dictionary).get(hero, null)
	return int(hs[2]) if hs is Array and (hs as Array).size() > 2 else 0

## A player's mastery of a hero: {xp, level, medal (0 none, 1 Bronze .. 5 Diamond), stars (1..5), frac (to the next
## star), top (1..5 for a Top Player, else 0), name ("Gold 3", "Top 2 Player", "Unranked")}.
static func hero_medal(p: Dictionary, hero: String) -> Dictionary:
	var xp := hero_xp(p, hero)
	var lv := hero_level(xp)
	var medal := 0 if lv == 0 else (lv - 1) / 5 + 1
	var stars := 0 if lv == 0 else (lv - 1) % 5 + 1
	var frac := 1.0
	if lv < HERO_LEVELS:
		frac = clampf(float(xp - hero_xp_for(lv)) / float(hero_xp_for(lv + 1) - hero_xp_for(lv)), 0.0, 1.0)
	var top := 0
	if medal >= 5:
		var pl := hero_place(String(p.get("id", "")), hero)
		if pl >= 1 and pl <= TOP_HERO:
			top = pl
	var nm := "Unranked"
	if top > 0:
		nm = "Top %d Player" % top
	elif medal > 0:
		nm = "%s %d" % [MEDALS[medal], stars]
	return {"xp": xp, "level": lv, "medal": medal, "stars": stars, "frac": frac, "top": top, "name": nm,
		"next": hero_xp_for(lv + 1) if lv < HERO_LEVELS else xp}

## A hero's ranking across every player by mastery XP: [{id, xp, w, l}], best first (players with any XP on it).
static func hero_board(hero: String) -> Array:
	load_data()
	var me_hs: Dictionary = data.me.get("hero_stats", {})
	var key := int(data.rounds) * 100000 + int(data.me.mmr) + me_hs.size() * 7 + int(data.me.wins) * 13 + int(data.me.losses) * 17
	if key != _hero_key:
		_hero_boards.clear()
		_hero_key = key
	if _hero_boards.has(hero):
		return _hero_boards[hero]
	var out: Array = []
	for p in all_profiles():
		var hs = (p.get("hero_stats", {}) as Dictionary).get(hero, null)
		if hs is Array and int(hs[2] if (hs as Array).size() > 2 else 0) > 0:
			out.append({"id": String(p.id), "xp": int(hs[2]), "w": int(hs[0]), "l": int(hs[1])})
	out.sort_custom(func(a, b): return int(a.xp) > int(b.xp) if int(a.xp) != int(b.xp) else String(a.id) < String(b.id))
	_hero_boards[hero] = out
	return out

## A player's place on a hero's ranking (1-based), 0 if they have no XP on it.
static func hero_place(id: String, hero: String) -> int:
	var b := hero_board(hero)
	for i in b.size():
		if String(b[i].id) == id:
			return i + 1
	return 0

## A player's heroes with a medal of `min_medal` or better (Gold = 3), best first: [[hero, medal info]].
static func top_heroes(p: Dictionary, min_medal := 3) -> Array:
	var out: Array = []
	for h in (p.get("hero_stats", {}) as Dictionary):
		var m := hero_medal(p, String(h))
		if int(m.medal) >= min_medal:
			out.append([String(h), m])
	out.sort_custom(func(a, b): return _medal_rank(a[1]) > _medal_rank(b[1]))
	return out

static func _medal_rank(m: Dictionary) -> int:
	return (10 - int(m.top)) * 100 if int(m.top) > 0 else int(m.level)

## A player's heroes by games played: [[hero, wins, losses]].
static func heroes_played(p: Dictionary) -> Array:
	var out: Array = []
	var hs: Dictionary = p.get("hero_stats", {})
	for h in hs:
		out.append([String(h), int(hs[h][0]), int(hs[h][1])])
	out.sort_custom(func(a, b): return int(a[1]) + int(a[2]) > int(b[1]) + int(b[2]))
	return out

## A bot's country: Filipino-sounding names are from the Philippines, the rest from around the world.
static func _country_for(nm: String, r: RandomNumberGenerator) -> String:
	var low := nm.to_lower()
	for w in BotNames.FIL + BotNames.PHRASES + ["ni ", " ako", " lang", " ang ", "kuya", "ate ", "tito", "tita", "bobo", "mama mo"]:
		if low.contains(String(w)):
			return "PH"
	var weights := [10, 6, 5, 4, 4, 2, 5, 5, 5, 2, 5, 3, 2, 3, 2, 2]
	var total := 0
	for x in weights:
		total += x
	var roll := r.randi_range(1, total)
	for i in weights.size():
		roll -= int(weights[i])
		if roll <= 0:
			return String(COUNTRIES[i][0])
	return "PH"

static func country_name(code: String) -> String:
	for c in COUNTRIES:
		if String(c[0]) == code:
			return String(c[1])
	return ""
