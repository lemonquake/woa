class_name BotMemory
extends RefCounted
## What the bots learn from their games, saved on this computer in user://bot_memory.json (Options > Game, "Bots learn
## from games", on by default). When learning is off, or in tests and bot duels, every bot uses the built-in values, so
## results stay repeatable.
##
## What is learned, and how it is used:
## * Fight model: a logistic regression P(win) over a fight's features (strength ratio, health, numbers, towers,
##   levels, ultimate). Each fight a bot starts is scored when it resolves (the target dies, the bot dies or runs, or
##   the trade after 12 s) and the weights take one gradient step. Bots engage when P(win) clears their bar.
## * Danger map: where heroes of the bots' side died (32 x 32 grid, both teams folded onto one side). Bots keep their
##   retreat bar higher and avoid farming camps where many died. Fades by 3% a game.
## * Item builds: each hero and role has a few builds; the one picked is scored by the game's result and net worth,
##   and the next pick uses UCB1 (try each, then favour what worked).
## * Skill shots: Shuriken Hook hits and misses by distance; a bot stops throwing from distances that keep missing.
## * Retreat bar per hero: raised when a bot dies while running away, lowered slowly when it runs with health to spare.
## * Lane matchups: lane deaths per (hero, enemy laner) set how hard a bot trades in that lane.
## * The player: which lane the player takes with each hero, so the bots leave it free from the start.

const DEFAULT_PATH := "user://bot_memory.json"
const VERSION := 1
const GRID := 32
## Default fight weights: [bias, strength ratio (log), target health, own health, numbers, enemy tower, own tower,
## level difference, ultimate ready]
const FIGHT_DEFAULT := [0.2, 2.2, -1.6, 1.4, 1.2, -1.5, 0.8, 0.6, 0.5]
const FIGHT_RATE := 0.05

static var path := DEFAULT_PATH
static var active := false                 # learning on for this match (set by the match from Options)
static var teams := [true, true]           # which teams' bots use and add to the memory (A/B tests: one side fresh)
static var data := {}
static var _loaded := false
static var dirty := false

static func _fresh() -> Dictionary:
	return {"version": VERSION, "games": 0, "wins": 0, "fight_w": FIGHT_DEFAULT.duplicate(), "fights": 0,
		"danger": {}, "builds": {}, "hook": {}, "retreat": {}, "matchup": {}, "player_lane": {}, "lessons": []}

static func load_data() -> void:
	_loaded = true
	data = _fresh()
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or int(d.get("version", 0)) != VERSION:
		return
	for k in data:
		if d.has(k) and typeof(d[k]) == typeof(data[k]):
			data[k] = d[k]
	var fw: Array = data.fight_w
	if fw.size() != FIGHT_DEFAULT.size():
		data.fight_w = FIGHT_DEFAULT.duplicate()

## Whether learning applies to a team's bots (team -1: any).
static func on(team := -1) -> bool:
	return active and (team < 0 or team > 1 or bool(teams[team]))

static func _ensure() -> void:
	if not _loaded:
		load_data()

static func save() -> void:
	if not active:
		return
	_ensure()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		dirty = false

static func reset() -> void:
	data = _fresh()
	_loaded = true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---- Fight model --------------------------------------------------------------------------------------------------

static func fight_weights(team := -1) -> Array:
	if not on(team):
		return FIGHT_DEFAULT
	_ensure()
	return data.fight_w

static func fight_p(x: Array, team := -1) -> float:
	var wv := fight_weights(team)
	var z := 0.0
	for i in mini(x.size(), wv.size()):
		z += float(wv[i]) * float(x[i])
	return 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))

## One gradient step on a resolved fight: y is 1 for a win, 0 for a loss, in between for a trade.
static func learn_fight(x: Array, y: float, team := -1) -> void:
	if not on(team):
		return
	_ensure()
	var p := fight_p(x, team)
	var wv: Array = data.fight_w
	for i in mini(x.size(), wv.size()):
		wv[i] = clampf(float(wv[i]) + FIGHT_RATE * (y - p) * float(x[i]), -6.0, 6.0)
	data.fights = int(data.fights) + 1
	dirty = true

# ---- Danger map -----------------------------------------------------------------------------------------------------

static func _cell(team: int, p: Vector2) -> String:
	# fold the Black Sun's side onto the Ancient Light's (the map is the same rotated 180 degrees)
	var q := p if team == SimConst.DAWN else -p
	var cx := clampi(int((q.x + SimMap.HALF) / (SimMap.HALF * 2.0) * GRID), 0, GRID - 1)
	var cy := clampi(int((q.y + SimMap.HALF) / (SimMap.HALF * 2.0) * GRID), 0, GRID - 1)
	return "%d,%d" % [cx, cy]

static func note_death(team: int, p: Vector2) -> void:
	if not on(team):
		return
	_ensure()
	var k := _cell(team, p)
	data.danger[k] = float(data.danger.get(k, 0.0)) + 1.0
	dirty = true

## 0 (nobody died here) .. 1 (one of the deadliest places on the map).
static func danger(team: int, p: Vector2) -> float:
	if not on(team):
		return 0.0
	_ensure()
	var v := float(data.danger.get(_cell(team, p), 0.0))
	if v <= 0.0:
		return 0.0
	var top := 1.0
	for k in data.danger:
		top = maxf(top, float(data.danger[k]))
	return clampf(v / top, 0.0, 1.0)

# ---- Item builds (UCB1 bandit) --------------------------------------------------------------------------------------

## Pick one of n builds for a hero and role: each untried build first, then the best mean reward plus exploration.
static func pick_build(key: String, n: int, fallback := 0, team := -1) -> int:
	if not on(team) or n <= 1:
		return fallback
	_ensure()
	var rec: Dictionary = data.builds.get(key, {})
	var total := 0
	for i in n:
		total += int((rec.get(str(i), {}) as Dictionary).get("n", 0))
	for i in n:
		if int((rec.get(str(i), {}) as Dictionary).get("n", 0)) == 0:
			return i
	var best := fallback
	var best_v := -INF
	for i in n:
		var r: Dictionary = rec.get(str(i), {})
		var v := float(r.get("r", 0.0)) / float(r.n) + sqrt(2.0 * log(float(total)) / float(r.n))
		if v > best_v:
			best_v = v
			best = i
	return best

static func reward_build(key: String, i: int, reward: float, team := -1) -> void:
	if not on(team):
		return
	_ensure()
	var rec: Dictionary = data.builds.get(key, {})
	var r: Dictionary = rec.get(str(i), {"n": 0, "r": 0.0})
	r.n = int(r.n) + 1
	r.r = float(r.r) + clampf(reward, 0.0, 1.0)
	rec[str(i)] = r
	data.builds[key] = rec
	dirty = true

static func build_stats(key: String, n: int) -> Array:
	_ensure()
	var rec: Dictionary = data.builds.get(key, {})
	var out := []
	for i in n:
		var r: Dictionary = rec.get(str(i), {"n": 0, "r": 0.0})
		out.append([int(r.n), float(r.r) / maxf(1.0, float(r.n))])
	return out

# ---- Skill shots --------------------------------------------------------------------------------------------------

const SHOT_BIN := 200.0

static func note_shot(ability: String, dist: float, hit: bool, team := -1) -> void:
	if not on(team):
		return
	_ensure()
	var rec: Dictionary = data.hook.get(ability, {})
	var k := str(int(dist / SHOT_BIN))
	var b: Array = rec.get(k, [0, 0])
	b[0] = int(b[0]) + (1 if hit else 0)
	b[1] = int(b[1]) + 1
	rec[k] = b
	data.hook[ability] = rec
	dirty = true

## Chance a shot from this distance hits, with a prior of 1 hit in 2 tries.
static func shot_rate(ability: String, dist: float, team := -1) -> float:
	if not on(team):
		return 0.5
	_ensure()
	var b: Array = (data.hook.get(ability, {}) as Dictionary).get(str(int(dist / SHOT_BIN)), [0, 0])
	return (float(b[0]) + 1.0) / (float(b[1]) + 2.0)

# ---- Retreat bar ----------------------------------------------------------------------------------------------------

static func retreat_hp(hero: String, base: float, team := -1) -> float:
	if not on(team):
		return base
	_ensure()
	return float(data.retreat.get(hero, base))

## died: the bot died while running away (the bar was too low); spare: it got away with this much health left.
static func note_retreat(hero: String, base: float, died: bool, spare: float, team := -1) -> void:
	if not on(team):
		return
	_ensure()
	var v := float(data.retreat.get(hero, base))
	if died:
		v += 0.03
	elif spare > 0.2:
		v -= 0.005
	data.retreat[hero] = clampf(v, 0.12, 0.5)
	dirty = true

# ---- Lane matchups --------------------------------------------------------------------------------------------------

## How hard to trade in lane against this hero: 1 normal, lower after lane deaths, higher after lane kills.
static func matchup(me: String, foe: String, team := -1) -> float:
	if not on(team):
		return 1.0
	_ensure()
	var m: Dictionary = data.matchup.get(me + ">" + foe, {})
	var games := float(m.get("games", 0))
	if games <= 0.0:
		return 1.0
	var net := (float(m.get("kills", 0)) - float(m.get("deaths", 0))) / games
	return clampf(1.0 + net * 0.15, 0.6, 1.4)

static func note_lane(me: String, foe: String, kills: int, deaths: int, team := -1) -> void:
	if not on(team):
		return
	_ensure()
	var k := me + ">" + foe
	var m: Dictionary = data.matchup.get(k, {"games": 0, "kills": 0, "deaths": 0})
	m.games = int(m.games) + 1
	m.kills = int(m.kills) + kills
	m.deaths = int(m.deaths) + deaths
	data.matchup[k] = m
	dirty = true

# ---- The player ---------------------------------------------------------------------------------------------------

static func note_player_lane(hero: String, lane_role: String) -> void:
	if not active:
		return
	_ensure()
	var m: Dictionary = data.player_lane.get(hero, {})
	m[lane_role] = int(m.get(lane_role, 0)) + 1
	data.player_lane[hero] = m
	dirty = true

## The lane role ("safe", "mid", "off") the player took most with this hero, if they did it in most games.
static func player_lane(hero: String) -> String:
	if not active:
		return ""
	_ensure()
	var m: Dictionary = data.player_lane.get(hero, {})
	var best := ""
	var bn := 0
	var total := 0
	for k in m:
		total += int(m[k])
		if int(m[k]) > bn:
			bn = int(m[k])
			best = k
	return best if total >= 2 and bn * 2 > total else ""

# ---- End of a match -------------------------------------------------------------------------------------------------

static func end_match(won_any: bool, lesson: String) -> void:
	if not active:
		return
	_ensure()
	data.games = int(data.games) + 1
	if won_any:
		data.wins = int(data.wins) + 1
	for k in data.danger.keys():
		var v := float(data.danger[k]) * 0.97
		if v < 0.05:
			data.danger.erase(k)
		else:
			data.danger[k] = v
	var lessons: Array = data.lessons
	if lesson != "":
		lessons.append(lesson)
	while lessons.size() > 20:
		lessons.pop_front()
	save()

## Lines for the Options screen: what the bots have learned so far.
static func summary() -> Array:
	_ensure()
	var out := []
	out.append("Games learned from: %d (bots' side won %d)" % [int(data.games), int(data.wins)])
	out.append("Fights scored: %d" % int(data.fights))
	out.append("Places marked dangerous: %d" % (data.danger as Dictionary).size())
	var shots := 0
	for a in data.hook:
		for k in data.hook[a]:
			shots += int((data.hook[a][k] as Array)[1])
	out.append("Skill shots tracked: %d" % shots)
	var lessons: Array = data.lessons
	if not lessons.is_empty():
		out.append("Last lesson: " + String(lessons[-1]))
	return out
