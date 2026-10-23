class_name LlmChat
extends Node
## The online chat writer (run 2026-10-19 d; the owner: "suggest some perfect ways to utilize an LLM ... very cheap
## ... wire their brains to it"). Off unless Options "Online bot chat" is on and an API key is set. It never decides
## anything: the bots' own chat brain (SimBotChat, deterministic, multiplayer safe) still picks who speaks, when, about
## what and with which facts, and queues its own line. This only asks a small, cheap language model (Claude Haiku 5.5
## by default) to write that same moment in the bot's own voice, with the match around it (the hero, the score, the
## gold gap, the last lines of chat, what the player just typed). The chat panel shows the model's line if it comes
## back in time, else the bot's own line, so a slow network or a refusal never stalls or breaks chat. Multiplayer
## never uses it (every machine must show the same lines).
##
## Setup: put {"api_key": "..."} in user://llm.json (or set OPENROUTER_API_KEY or ANTHROPIC_API_KEY), then Options >
## Game > Online bot chat. Two services (the owner chose OpenRouter, 2026-10-19 d):
##   * OpenRouter (a key starting "sk-or-", or "provider": "openrouter"): one key for hundreds of models; the default
##     is deepseek/deepseek-v4.1-flash (the owner's choice); "model" picks another (anthropic/claude-haiku-5.5,
##     mistralai/mistral-nemo ...).
##     OpenRouter reports what each call cost, and that is what is logged;
##   * Anthropic's own Messages API (any other key): claude-haiku-5-5.
## Optional keys: provider, model, endpoint, max_calls (per match, default 150), timeout (seconds, default 4), share
## (0..1 of ordinary lines rewritten; answers to you, memories, revenge and arguments are always tried, default 0.5),
## max_replies (answers to what you type, per match, default 400: they never count against max_calls), reply_timeout
## (seconds an answer to you may wait for the model, default 9).
##
## Answers to the player come first (the owner, 2026-10-20: "the player should be TOP PRIORITY to have them reply at
## all means ... talk back to the player if he trash talks"): a line answering what the player typed is always sent,
## past the share, the cap and the three-at-a-time limit, waits longer, and its prompt asks the model to answer what
## the player actually wrote (and to hit back at trash talk, never to calm the player down).
## The key is read on this computer only; it is never saved in the project or the export. What it costs is logged in
## user://llm_usage.json.
##
## Requests over HTTPS (no SDK exists for GDScript): the long game and rules text as a cached system prompt (cache
## reads cost a tenth of input on Claude and Gemini), thinking off, at most 60 tokens out.

const CFG_PATH := "user://llm.json"
const USAGE_PATH := "user://llm_usage.json"
const ENDPOINT := "https://api.anthropic.com/v1/messages"
const MODEL := "claude-haiku-5-5"
const OR_ENDPOINT := "https://openrouter.ai/api/v1/chat/completions"
const OR_MODEL := "deepseek/deepseek-v4.1-flash"         # the owner's choice (2026-10-19 d)
## List prices per million tokens [input, output, cache read, cache write (5 minutes)] (Claude API and OpenRouter's
## model list, read 2026-10-19). OpenRouter's own reported cost is used when it comes back.
const PRICES := {"claude-haiku-5-5": [0.10, 0.50, 0.01, 0.125], "claude-sonnet-5-5": [2.0, 10.0, 0.20, 2.5],
	"anthropic/claude-haiku-5.5": [0.10, 0.50, 0.01, 0.125], "deepseek/deepseek-v4.1-flash": [0.038, 0.08, 0.0016, 0.038],
	"mistralai/mistral-nemo": [0.029, 0.03, 0.029, 0.029], "google/gemini-2.5-flash-lite": [0.10, 0.40, 0.01, 0.10],
	"meta-llama/llama-3.1-8b-instruct": [0.05, 0.08, 0.025, 0.05]}
## Moments always worth a rewrite (the player reads these): answers to the player, memories, revenge, arguments.
const ALWAYS := ["r_", "meet_", "end_", "t_", "revenge", "rival", "ks", "player_kill", "responses_and_comebacks", "tt_", "add_",
	"kda_", "mvp_", "hype_rampage", "salty_rampage", "known_", "feed_enemy"]
const MAX_PARALLEL := 3

var world: SimWorld
var team := 0                               # the player's team (only lines the player can read are rewritten)
var cfg := {}
var key := ""
var calls := 0
var replies := 0                            # answers to the player sent this match
var _pending := {}                          # line id -> {req, at}
var _done := {}                             # line id -> text
var _failed := {}                           # line id -> true
var _system := ""
var _usage := {"calls": 0, "in": 0, "out": 0, "cache_read": 0, "cache_write": 0, "usd": 0.0, "failed": 0}
var _rng := RandomNumberGenerator.new()

## The settings and key, or {} when the writer cannot run (no key).
static func load_config() -> Dictionary:
	var c := {}
	if FileAccess.file_exists(CFG_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
		if d is Dictionary:
			c = d
	var k := String(c.get("api_key", "")).strip_edges()
	if k == "":
		k = OS.get_environment("OPENROUTER_API_KEY")
	if k == "":
		k = OS.get_environment("ANTHROPIC_API_KEY")
	if k == "":
		return {}
	c["api_key"] = k
	if not c.has("provider"):
		c["provider"] = "openrouter" if k.begins_with("sk-or-") else "anthropic"
	return c

## Whether the writer would run in a match now (the option is on and a key is set).
static func ready_to_run() -> bool:
	return bool(Options.get_value("llm_chat")) and not load_config().is_empty()

## Whether a test script drives the game (godot -s ...: probes, captures). Then your key is never used, only a local
## stand-in given on the command line (run 2026-10-20: a live probe once sent real requests with the owner's key).
static func automated(tree: SceneTree) -> bool:
	return tree != null and tree.get_script() != null

## What the writer has cost on this computer so far.
static func usage_total() -> Dictionary:
	if FileAccess.file_exists(USAGE_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(USAGE_PATH))
		if d is Dictionary:
			return d
	return {}

func setup(w: SimWorld, p_team: int, p_cfg: Dictionary) -> void:
	world = w
	team = p_team
	cfg = p_cfg
	key = String(cfg.get("api_key", ""))
	_rng.randomize()
	_system = _system_prompt()

func openrouter() -> bool:
	return String(cfg.get("provider", "")) == "openrouter" or key.begins_with("sk-or-")

func model() -> String:
	return String(cfg.get("model", OR_MODEL if openrouter() else MODEL))

# ---- Asking --------------------------------------------------------------------------------------------------------

## A bot line was queued (SimBotChat "chat_intent"): ask for the model's version if the player will read it.
func want(e: Dictionary) -> void:
	if key == "" or world == null:
		return
	var lid := int(e.get("lid", -1))
	if lid < 0 or _pending.has(lid) or _done.has(lid):
		return
	if not bool(e.get("all", false)) and int(e.get("team", -1)) != team:
		return                                 # the other team's team chat: never seen
	var wait := wait_for(e)
	if wait < 0.0:
		return
	var answer := is_answer(e)
	var body := request_body(e)
	var req := HTTPRequest.new()
	req.timeout = wait + 2.0
	add_child(req)
	req.request_completed.connect(_on_done.bind(lid, req))
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + key, "anthropic-version: 2023-06-01"])
	if openrouter():
		headers = PackedStringArray(["content-type: application/json", "authorization: Bearer " + key,
			"x-title: Warriors of Aether"])
	var err := req.request(String(cfg.get("endpoint", OR_ENDPOINT if openrouter() else ENDPOINT)), headers, HTTPClient.METHOD_POST,
		JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return
	if answer:
		replies += 1
	else:
		calls += 1
	_pending[lid] = {"req": req, "at": Time.get_ticks_msec(), "wait": wait}

## How long line `e` may wait for the model if it should be sent now, else -1. An answer to the player is always sent
## (up to max_replies) and waits longer; other lines keep to the cap, the parallel limit and the share.
func wait_for(e: Dictionary) -> float:
	if is_answer(e):
		return float(cfg.get("reply_timeout", 9.0)) if replies < int(cfg.get("max_replies", 400)) else -1.0
	if calls >= int(cfg.get("max_calls", 150)) or _pending.size() >= MAX_PARALLEL:
		return -1.0
	var cat := String(e.get("cat", ""))
	var always := false
	for a in ALWAYS:
		if cat.begins_with(a):
			always = true
	if not always and _rng.randf() > float(cfg.get("share", 0.5)):
		return -1.0
	return float(cfg.get("timeout", 4.0))

## Whether a queued line answers something the player typed.
static func is_answer(e: Dictionary) -> bool:
	return String(e.get("said", "")) != "" and int(e.get("by", -1)) >= 0

## The request for one line (also used by the tests and the probe).
func request_body(e: Dictionary) -> Dictionary:
	if openrouter():
		# OpenRouter's chat completions: the system text as a part Claude and Gemini cache, reasoning off, the cost
		# of the call reported back
		var sys_part := {"type": "text", "text": _system}
		if model().begins_with("anthropic/") or model().begins_with("google/"):
			sys_part["cache_control"] = {"type": "ephemeral"}
		# 200 tokens of room: if a model reasons anyway its line still fits (the line itself is cut to 90 letters)
		return {"model": model(), "max_tokens": 200, "reasoning": {"enabled": false}, "usage": {"include": true},
			"messages": [{"role": "system", "content": [sys_part]}, {"role": "user", "content": user_prompt(e)}]}
	return {"model": model(), "max_tokens": 60, "thinking": {"type": "disabled"},
		"system": [{"type": "text", "text": _system, "cache_control": {"type": "ephemeral"}}],
		"messages": [{"role": "user", "content": user_prompt(e)}]}

func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, lid: int, req: HTTPRequest) -> void:
	req.queue_free()
	_pending.erase(lid)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failed[lid] = true
		_usage.failed = int(_usage.failed) + 1
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or String(d.get("stop_reason", "")) == "refusal" or d.has("error"):
		_failed[lid] = true
		_usage.failed = int(_usage.failed) + 1
		return
	var text := ""
	for c in d.get("content", []):
		if c is Dictionary and String(c.get("type", "")) == "text":
			text += String(c.get("text", ""))
	for ch in d.get("choices", []):
		# OpenRouter: the first choice's message
		if ch is Dictionary and ch.get("message") is Dictionary and String(ch.get("finish_reason", "")) != "content_filter":
			text += String(ch.message.get("content", "") if ch.message.get("content") != null else "")
			break
	text = clean(text)
	if text == "":
		_failed[lid] = true
	else:
		_done[lid] = text
	_count(d.get("usage", {}))

## One chat line from what the model wrote: the first line, no quotes, no name in front, at most 120 letters (cut at a
## word).
static func clean(t: String) -> String:
	var s := t.strip_edges().split("\n", false)[0] if t.strip_edges() != "" else ""
	s = s.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'").strip_edges()
	var colon := s.find(": ")
	if colon > 0 and colon < 24 and not s.substr(0, colon).contains(" "):
		s = s.substr(colon + 2)
	if s.length() > 120:
		s = s.substr(0, 120)
		var sp := s.rfind(" ")
		if sp > 60:
			s = s.substr(0, sp)
	return s

## The model's line for `lid`: {state: "ready", text} | {state: "waiting"} | {state: "none"} (use the bot's own).
func text_for(lid: int) -> Dictionary:
	if _done.has(lid):
		return {"state": "ready", "text": String(_done[lid])}
	if _pending.has(lid):
		var waited := float(Time.get_ticks_msec() - int(_pending[lid].at)) / 1000.0
		if waited < float(_pending[lid].get("wait", cfg.get("timeout", 4.0))):
			return {"state": "waiting"}
	return {"state": "none"}

func _count(u) -> void:
	if not (u is Dictionary):
		return
	var price: Array = PRICES.get(model(), PRICES[MODEL])
	var i := int(u.get("input_tokens", 0))
	var o := int(u.get("output_tokens", 0))
	var cr := int(u.get("cache_read_input_tokens", 0))
	var cw := int(u.get("cache_creation_input_tokens", 0))
	if u.has("prompt_tokens"):
		# OpenRouter (OpenAI style): prompt tokens include the cached ones
		var det = u.get("prompt_tokens_details", {})
		cr = int(det.get("cached_tokens", 0)) if det is Dictionary else 0
		i = maxi(0, int(u.prompt_tokens) - cr)
		o = int(u.get("completion_tokens", 0))
		cw = 0
	_usage.calls = int(_usage.calls) + 1
	_usage["in"] = int(_usage["in"]) + i
	_usage.out = int(_usage.out) + o
	_usage.cache_read = int(_usage.cache_read) + cr
	_usage.cache_write = int(_usage.cache_write) + cw
	if u.get("cost") != null and (u.get("cost") is float or u.get("cost") is int):
		_usage.usd = float(_usage.usd) + float(u.cost)        # what OpenRouter charged for this call
	else:
		_usage.usd = float(_usage.usd) + (i * float(price[0]) + o * float(price[1]) + cr * float(price[2]) + cw * float(price[3])) / 1000000.0

## This match's use, added to the total on this computer (called when the match ends or the writer goes away).
func save_usage() -> void:
	if int(_usage.calls) == 0 and int(_usage.failed) == 0:
		return
	var upath := String(cfg.get("usage_path", USAGE_PATH))
	var tot := usage_total() if upath == USAGE_PATH else {}
	for k in _usage:
		tot[k] = (float(tot.get(k, 0)) + float(_usage[k])) if k == "usd" else int(tot.get(k, 0)) + int(_usage[k])
	tot["matches"] = int(tot.get("matches", 0)) + 1
	tot["model"] = model()
	var f := FileAccess.open(upath, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(tot, " "))
	print("Online bot chat: %d lines, %d in + %d out tokens (%d cached), $%.4f this match" % [int(_usage.calls),
		int(_usage["in"]), int(_usage.out), int(_usage.cache_read), float(_usage.usd)])
	_usage = {"calls": 0, "in": 0, "out": 0, "cache_read": 0, "cache_write": 0, "usd": 0.0, "failed": 0}

func usage() -> Dictionary:
	return _usage

func _exit_tree() -> void:
	save_usage()

# ---- Prompts --------------------------------------------------------------------------------------------------------

## The game, its heroes and the rules for chat: the same for every request (so it is cached).
func _system_prompt() -> String:
	var heroes: Array = []
	for id in GameSettings.random_pool():
		var d := SimData.unit(String(id))
		var abil: Array = []
		for a in d.get("abilities", []):
			var nm := String(SimData.ability(String(a)).get("name", ""))
			if nm != "":
				abil.append(nm)
		var line := "- %s: %s; abilities %s" % [String(d.get("name", id)), ", ".join(SimBotKits.roles(String(id)).slice(0, 2).map(func(r): return RankedNum.role(int(r)))),
			", ".join(abil)]
		if SimBotKits.HOW_TO_PLAY.has(String(id)):
			line += "; how it plays: " + String(SimBotKits.HOW_TO_PLAY[String(id)])
		var know := BotKnowledge.hero_line(String(id))
		if know != "":
			line += "; " + know
		heroes.append(line)
	return """You write one in-game chat line for a player in Warriors of Aether, a 5 v 5 lane battle game played like Dota 2 (two teams, Ancient Light and Black Sun; three lanes: top, mid, bottom; towers, barracks and a Throne to destroy; creeps, last hits and denies; neutral camps and stacks; orbs in the river; Town Portal scrolls (tp); buyback; Fortify; experience and gold at 150%%). Players are ranked by MMR in ranks Rookie, Advanced, Licensed, Expert, Commander, Chief Commander, Legendary, Mythic, Hero, Transcendent, Aetherium.

The heroes (what each does, what makes it dangerous, how to beat it, when it is strong, which items answer it):
%s

The items worth talking about, and what they do:
%s

Rules players know:
%s

How players chat, and how you must write:
- Write exactly one chat line, the way this player types it in a fast online game. Usually 1 to 8 words, never more than 16 (a comeback or an answer may use up to 20).
- React to what just happened, with the facts you are given (names, abilities, numbers). Never invent numbers, items or events you were not told.
- Know the game like a good player: talk about what matters right now (who is dangerous and why, whose ultimate is up or down, who is dead, the gold gap, the towers, a counter item that would really help, the next objective). Use the hero knowledge above when it fits.
- Only name an item when it truly matters: a finished big item, or a counter that answers an enemy hero. Never mention starting items, parts or consumables (branches, tangos, circlets, salves, recipes, plain boots), and never name an item nobody in this game has or needs.
- Follow the player's typing style: lower case or not, short forms (u, ur, pls, idk, ty, gg, ez, omw, ss, mia, b, tp), their laugh (haha, wkwk, kkkk, 555, jaja), their pet word, no full stops unless they use them.
- Follow their language: some players type Filipino or Taglish (mixing Tagalog and English: "bawi ako", "ang sakit ng hook", "tara mid", "lods", "pre"), others plain English.
- Personality matters: a kind player encourages teammates, a toxic one trash talks and blames, a show-off brags, a quiet one says little, a shot caller gives short calls (push, b, def top, focus their carry).
- When someone talks to you, answer what they actually said. Questions get real answers with the facts you know; jokes get jokes back.
- When someone trash talks, taunts or insults you, you talk back like a real player: a witty, cocky, cutting comeback, ideally using their own score, deaths, last hits or the gold gap against them. Even a kind player jabs back with a joke. Never act like a moderator: never tell them to relax, chill, calm down, be nice or that it is just a game, and never apologise for being flamed.
- Trash talk about the game and light swearing are normal in this chat ("tangina", "gago", "wtf", "pota", "bobo"). Never use slurs or insults about race, nationality, religion, sex, sexuality or disability, never threaten anyone outside the game, nothing about self-harm.
- You are a player, not an assistant: never say you are an AI or a bot, never explain, never use emoji or hashtags. If someone calls you a bot, joke about it the way a player would.
- Output only the chat line: no quotes, no name in front, nothing else.""" % ["\n".join(heroes), "; ".join(BotKnowledge.item_lines()),
		"\n".join(BotKnowledge.RULES.map(func(r): return "- " + String(r)))]

## Plain words for what happened (SimBotChat's situation or line category).
const MOMENTS := {
	"revenge": "You just killed {victim}, who killed you earlier.", "revenge_reply": "{killer} just took revenge on you.",
	"rival": "You just killed {victim} again ({n} times this game).", "rival_reply": "{killer} keeps killing you.",
	"double": "You just got a double kill.", "multi": "You just got {n} kills in a row in one fight.",
	"skill_kill": "You just killed an enemy with {skill}.", "skill_death": "You just died to {hero}'s {skill}.",
	"stun_death": "You were stunned the whole time and died.", "ks": "Your teammate {killer} took the last hit on a kill you did most of the damage for.",
	"ks_sorry": "You took the last hit on a kill a teammate earned.", "ks_proud": "You took the last hit on a kill a teammate earned and you do not care.",
	"ks_player": "The player {name} took the last hit on your kill.", "ks_to_player": "You took the last hit on the player {name}'s kill.",
	"player_kill": "Your teammate {name} just got a kill.", "escape": "You escaped a fight with almost no health.",
	"escape_enemy": "The enemy {victim} escaped you with almost no health.", "tower_dive": "You died to a tower after diving.",
	"wipe": "Your team just killed the whole enemy team.", "wiped": "Your whole team just died.",
	"miss_named": "{hero} missed {skill} on you.", "miss_team": "Your teammate missed {skill}.", "miss_self": "You missed your {skill}.",
	"enemy_ult": "The enemy {hero} just used their ultimate {skill}: a good time to fight.", "ult_ready": "Your ultimate is ready.",
	"item_done": "You finished {item}.", "nw_up": "Your team is {n}k gold ahead.", "nw_down": "Your team is {n}k gold behind.",
	"comeback": "Your team came back from far behind.", "fed_enemy": "The enemy {hero} has {n} kills and is getting strong.",
	"enemy_dead_push": "The enemy {hero} is dead for {sec} more seconds.", "give_up": "You are tilted and losing.",
	"encourage": "Your team is behind and morale is low.", "brag": "You are on a killing streak.",
	"own_death_tilt": "You died again and you are angry.", "meet_friend": "Your friend {name} is in this match.",
	"meet_won_with": "You played with {name} last time and won.", "meet_lost_with": "You played with {name} last time and lost.",
	"meet_lost_vs": "{name} beat you last time; now you face them again.", "meet_won_vs": "You beat {name} last time; you face them again.",
	"meet_flamer": "{name} flamed you in an earlier game.", "meet_killer": "{name} killed you {n} times in your last game.",
	"end_like": "The game is over and you liked playing with {name}.", "end_dislike": "The game is over and {name} played badly on your team.",
	"end_respect": "The game is over and {name} played well against you.",
	"r_rank": "The player asked your rank. You are {rank} ({mmr} MMR).", "r_rank_none": "The player asked your rank; you play unranked.",
	"r_from": "The player asked where you are from: {city}, {country}.", "r_where_seen": "The player asked where {hero} is: seen {lane} {sec} seconds ago.",
	"r_where_lost": "The player asked where {hero} is: nobody has seen them for {min} minutes.", "r_item": "The player asked what you are buying: {item} next.",
	"r_why_dead": "The player asked why you did not help: you were dead.", "r_why_far": "The player asked why you did not help: you were {doing}.",
	"r_insult_fact": "The player insulted you. Their score is {kda} on {me_hero} with {lh} last hits at {min} minutes.",
	"r_insult_witty": "The player insulted you; hit back with a joke at their expense.", "r_praise": "The player praised you.", "r_thanks": "The player thanked you.",
	"r_sorry_kind": "The player apologised.", "r_sorry_rude": "The player apologised and you are still annoyed.",
	"r_gg_early": "The player said gg but the game is not over and your team is winning.", "r_ff_no": "A teammate wants to give up; you do not.",
	"r_ff_yes": "A teammate wants to give up and you agree.", "r_bot": "The player called you a bot.", "r_report": "The player talks about reporting someone.",
	"r_lag": "The player says the game lags.", "r_laugh": "The player laughed.", "r_huh": "The player typed something unclear.",
	"r_greet": "The player greeted everyone.", "r_name": "The player said your name.",
	"t_sorry": "A teammate flamed you; you apologise.", "t_argue": "A teammate flamed you; you argue back. Their score is {kda}.",
	"t_calm": "Two teammates are arguing; you tell them to stop.",
	"killed_enemy_all_chat": "You just killed {victim}.", "first_blood": "First blood: you got the first kill of the game.",
	"shutdown": "You ended an enemy's killing streak.", "killing_spree": "You are on a {n} kill streak.",
	"own_death_excuses": "You just died.", "teammate_roast_and_blame": "Your teammate {ally} did not help you.",
	"dying_too_much_and_feeding": "Your teammate {ally} has died {n} times.", "failing_lane_and_no_farm": "Your teammate {ally} has very little farm.",
	"missed_skillshot_and_whiffs": "{hero} missed a spell.", "died_to_creeps_or_tower": "An enemy died to creeps or a tower.",
	"tower_destroyed": "Your team destroyed a {lane} tower.", "tower_lost": "Your team lost a {lane} tower.",
	"teamfight_won": "Your team won a team fight.", "teamfight_lost": "Your team lost a team fight.",
	"game_start": "The game is starting.", "ally_praise": "Your teammate {ally} got a kill.", "enemy_escaped": "{victim} teleported away with low health.",
	"denied": "You denied an ally.", "buyback": "An enemy bought back.", "megas_and_base": "Your team destroyed all their barracks.",
	"responses_and_comebacks": "Someone trash talked in all chat; you answer.", "casual_short_mockery": "You mock the enemy.",
	"gen_z_brainrot_and_slang": "You say something random.", "ragebait_and_trolling": "You troll the enemy.",
	# run 2026-10-19 e: the crowd (ChatSocial)
	"hype_double": "Your teammate {name} just got a double kill.", "hype_triple": "Your teammate {name} just got a triple kill.",
	"hype_ultra": "Your teammate {name} just got an ultra kill (4 heroes).", "hype_rampage": "Your teammate {name} just got a RAMPAGE (killed all 5 enemies). Go wild.",
	"salty_multi": "The enemy {name} just killed several of your team in one fight.",
	"salty_named": "The enemy {name} just killed {n} of your team in one fight. React to it, name the number.", "salty_rampage": "The enemy {name} ({rank}) just got a rampage on your whole team. You are furious: accuse, blame, call smurf or hacks.",
	"killer_rampage": "You just got a RAMPAGE: killed all five enemies.", "victim_blame": "Your whole team just died to one enemy; blame your team's play.",
	"streak_ally": "Your teammate {name} is on a {n} kill streak.", "streak_enemy": "The enemy {hero} is on a {n} kill streak; tell your team to focus them.",
	"streak_enemy_all": "The enemy {name} is on a big kill streak; taunt them about their bounty.", "shutdown_cheer": "Your team just ended an enemy's big kill streak.",
	"feed_enemy_mock": "The enemy {name} has died {n} times ({kda}). Mock them for feeding you gold.",
	"feed_ally_flame": "Your teammate {name} has died {n} times ({kda}). Flame them.", "feed_ally_kind": "Your teammate {name} keeps dying; tell them kindly to play safe.",
	"feed_self": "You keep dying and you know it.",
	"kda_smurf": "The enemy {name} ({rank}) is {kda}. Accuse them of smurfing.", "kda_cheat": "The enemy {name} is {kda} and always knows where you are. Accuse them of cheating.",
	"kda_report": "Threaten to report {name}.", "kda_praise": "Your teammate {name} is {kda}. Praise them.", "kda_respect": "The enemy {name} is {kda}; respect it.",
	"kda_arrogant": "You are {myrank}; the enemy {name} is a lower rank doing well ({kda}). Be arrogant and dismissive.",
	"kda_awful_enemy": "The enemy {name} ({rank}) is {kda}. Mock them, call them boosted.", "kda_awful_ally": "Your teammate {name} ({rank}) is {kda}. Flame them.",
	"tt_lucky": "The player trash talked you, and they are doing well ({kda}). Answer: lucky, wait for late game.",
	"tt_fact": "The player trash talked you, but their score is {kda} with {lh} last hits at {min} minutes. Answer with those facts.",
	"tt_gold": "The player trash talked you, but their team is {n}k gold behind. Answer with that.",
	"tt_report": "The player keeps trash talking. Threaten to report or mute them.", "tt_back": "The player trash talked you. Talk back.",
	"tt_ally_join": "Your teammate is trash talking the enemy; join in.",
	"tt_after_death": "The player trash talked you right after dying. Point it out.", "tt_witty": "The player trash talked you; answer with a cocky, witty jab (the game is not over).",
	"end_tt_won": "Your team won after the player {name} trash talked you all game. Rub it in.", "end_tt_lost": "You lost to the player {name}, who trash talked all game.",
	"end_report": "The game is over; say you are reporting {name}.",
	"mvp_cheer": "The game is over and your teammate {name} is the MVP.", "mvp_salty": "The game is over and the enemy {name} is the MVP; call it smurfing.",
	"meet_mvp_ally": "Your teammate {name} was MVP in their last game; expect them to carry.", "meet_mvp_enemy": "The enemy {name} was MVP in their last game; challenge them.",
	"mvp_expect_fail": "{name} was MVP last game but is {kda} now. Mock them.", "mvp_expect_good": "{name} was MVP last game and is playing well again.",
	"meet_bot_mvp": "You were MVP in your last game; mention it.", "meet_bot_mvp_other": "{name} was MVP in their last game.",
	"meet_rampage": "{name} got a rampage last time you played them.", "meet_trash": "{name} trash talked a lot last time you met.",
	"meet_reported": "You reported {name} last game.",
	"known_feeder": "You played with {name} before and they fed.", "known_rampage": "You played with {name} before and they got a rampage.",
	"known_flamer": "You played with {name} before and they flamed.", "known_mvp": "You played with {name} before and they were MVP.",
	"known_again": "You played with {name} before.", "known_reply": "Someone recognised you from an earlier game.",
	"add_yes": "The player {name} asked to add you as a friend; you say yes.", "add_no": "The player {name} ({kda}) asked to add you as a friend; you say no.",
	"add_already": "The player asked to add you, but you are already friends.", "add_offer": "The game is over and you want to add {name} as a friend.",
	"add_tease": "Two players are adding each other as friends; tease them.",
	# run 2026-10-20: the player is always answered
	"r_back": "The player {name} ({kda}) trash talked or insulted you. Roast them back.",
	"r_any": "Your teammate, the player {name}, said something to you. Answer it.",
	"r_any_foe": "The enemy player {name} ({kda}) said something in all chat. Answer it.",
	# run 2026-10-23: what the bots know of the heroes (BotKnowledge)
	"intel_tip": "Warn your team about the enemy {hero}: {tip}.",
	"counter_call": "The enemy {hero} keeps killing your team; tell them to get {item} ({why}).",
}

## Who the bot is, the match around it, the moment, the bot's own line.
func user_prompt(e: Dictionary) -> String:
	var h := world.get_unit(int(e.get("u", -1)))
	if h == null:
		return "Write a short chat line."
	var bc := world.botchat
	var ps: Dictionary = bc.persona(h)
	var st: Dictionary = ps.get("style", {})
	var b = bc._bot_of(h)
	var role := RankedNum.role(int(b.role)) if b != null else ""
	var mine := bc._team_nw(h.team)
	var theirs := bc._team_nw(1 - h.team)
	var gap := int(round(float(mine - theirs) / 1000.0))
	var tl := float(bc.voice(h).tl)
	var lang := "Filipino and Taglish mostly" if tl >= 0.6 else ("Taglish or English" if tl >= 0.3 else "English")
	var traits: Array = []
	for k in ["kind", "ego", "temper", "humor", "focus", "talk"]:
		traits.append("%s %.1f" % [k, float(ps.get(k, 0.5))])
	var typing := "%s, %s, laughs \"%s\"%s" % ["lower case" if bool(st.get("lower", true)) else "capital first letter",
		"many short forms" if float(st.get("short", 0.3)) > 0.5 else "few short forms", String(st.get("laugh", "haha")),
		(", pet word \"%s\"" % String(st.pet)) if String(st.get("pet", "")) != "" else ""]
	var card: Dictionary = b.card if b != null else {}
	var lines: Array = []
	for l in world.chat_log.slice(maxi(0, world.chat_log.size() - (12 if is_answer(e) else 8))):
		if bool(l.get("all", false)) or int(l.team) == h.team:
			lines.append("- %s%s: %s" % ["(all) " if bool(l.get("all", false)) else "", String(l.name), String(l.text)])
	var fill: Dictionary = e.get("fill", {})
	var moment := String(MOMENTS.get(String(e.get("cat", "")), "Say something that fits the game."))
	if String(e.get("cat", "")).begins_with("pf_"):
		# a profile look-up (ChatProfile): the facts of the profile it read
		var about := world.get_unit(int(e.get("target", -1)))
		var pf0: Dictionary = world.botchat.social.card(about).get("prof", {}) if about != null else {}
		moment = "You looked up %s's profile: %s React to it in your own manner (kind players give credit or cheer them up, rough ones flame bad numbers and call good ones smurfs, trolls troll). Use the real numbers." % [
			world.botchat.pname(about) if about != null else "a player", ProfileTalk.summary(pf0)]
	for k in fill:
		moment = moment.replace("{" + String(k) + "}", str(fill[k]))
	var out := "You are %s%s, playing %s%s for %s. Level %d, score %d/%d/%d, %d last hits. Game clock %s. Your team is %s.\n" % [
		h.player_label(), (" (%s, %s)" % [String(card.get("rank", "")), Ranked.country_name(String(card.get("country", "")))]) if not card.is_empty() else "",
		SimTeamAI.hero_label(h), (" (%s)" % role) if role != "" else "", SimConst.TEAM_NAMES[h.team], h.level, h.kills, h.deaths, h.assists,
		h.last_hits, world.clock_text(), ("%dk gold ahead" % gap) if gap > 0 else (("%dk gold behind" % -gap) if gap < 0 else "even in gold")]
	out += "The match right now:\n%s\n" % BotKnowledge.digest(world, h.team)
	out += "Personality (0 to 1): %s. Mood: %s.\n" % [", ".join(traits), "tilted" if float(bc.mind(h).tilt) > 0.6 else "fine"]
	out += "Typing: %s. Language: %s.\n" % [typing, lang]
	out += "Channel: %s.\n" % ("all chat (both teams read it)" if bool(e.get("all", false)) else "team chat")
	if not lines.is_empty():
		out += "Recent chat:\n%s\n" % "\n".join(lines)
	if is_answer(e):
		return out + _answer_part(e, h, moment)
	out += "What just happened: %s\n" % moment
	if String(e.get("said", "")) != "":
		out += "The player wrote: \"%s\"\n" % String(e.said)
	out += "A line this player might type: \"%s\"\nWrite this player's chat line now." % String(e.get("text", ""))
	return out

## The end of the prompt for an answer to the player: who they are, what they wrote, and what to do with it.
func _answer_part(e: Dictionary, h: SimUnit, moment: String) -> String:
	var p := world.get_unit(int(e.get("by", -1)))
	var said := String(e.get("said", ""))
	var rude := ChatMind.intent(said.to_lower()) in ["insult", "taunt"]
	var out := ""
	if p != null:
		var rank := String(world.botchat.social.card(p).get("rank", ""))
		out += "The player %s is %s, playing %s%s: score %d/%d/%d, %d last hits, level %d%s.\n" % [
			p.player_label() if p.player_label() != "" else SimTeamAI.hero_label(p), "your teammate" if p.team == h.team else "an enemy",
			SimTeamAI.hero_label(p), (" (%s)" % rank) if rank != "" else "", p.kills, p.deaths, p.assists, p.last_hits, p.level,
			"" if p.alive else ", dead right now"]
		var pf: Dictionary = world.botchat.social.card(p).get("prof", {})
		if not pf.is_empty():
			out += "Their profile (you looked it up; averages and recent matches matter a lot in this community): %s\n" % ProfileTalk.summary(pf)
	out += "The player just wrote in %s: \"%s\"\n" % ["all chat" if bool(e.get("all", false)) else "team chat", said]
	out += "Context: %s\n" % moment
	out += "A possible answer with the facts (use its facts if they help, but answer what the player wrote): \"%s\"\n" % String(e.get("text", ""))
	if rude:
		out += "They are trash talking or insulting you. Talk back: a witty, cocky, cutting comeback, the kind that makes the lobby laugh. Use their score, deaths, last hits or the gold gap if it hurts. Do not calm them down, do not tell them to relax or chill or be nice, do not apologise, do not ignore it.\n"
	else:
		out += "Answer them directly, about what they actually said, as this player would. If it is a question, answer it; if it is a joke, joke back; if it is bait, bite back.\n"
	return out + "Write your chat line now."
