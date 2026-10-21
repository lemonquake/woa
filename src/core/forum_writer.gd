class_name ForumWriter
extends Node
## The online writer for the Forums (run 2026-10-19 e): with Options "Online bot chat" on and an API key (LlmChat's
## settings: OpenRouter with DeepSeek V4.1 Flash by default), replies to you and the newest threads are written by the
## language model in each player's own voice, with who they are (rank, heroes, personality, how they type, what they
## think of you) and the thread so far. Forum's offline writer has already chosen who answers and when, and its text is
## the fallback: a reply whose model text is not back in time goes up with Forum's own words. Usage is logged like the
## match writer's (llm_usage.json). At most 120 calls a visit, at most 12 of them for other players' new threads: replies
## to you come first (the owner, 2026-10-20: "even in the forums they dont reply to the player").

const MAX_CALLS := 120
const MAX_THREAD_CALLS := 12
const WAIT := 9.0                           # seconds a reply may wait for the model past its time

var llm: LlmChat
var calls := 0
var thread_calls := 0
var _pending := {}                          # request key -> {req, kind, ref, at}

## A writer when the option is on and a key is set, else null.
static func make(parent: Node) -> ForumWriter:
	var mock := OS.get_environment("WOA_FORUM_LLM") != ""
	# captures and probes never call the real service with your key (only a local stand-in, WOA_FORUM_LLM)
	var automated := OS.get_environment("WOA_FORUM_FILE") != "" or OS.get_environment("WOA_RANKED_FILE") != "" \
		or Array(OS.get_cmdline_user_args()).any(func(a): return String(a).begins_with("--capture")) \
		or LlmChat.automated(parent.get_tree() if parent.is_inside_tree() else null)
	if automated and not mock:
		return null
	if not LlmChat.ready_to_run() and not mock:
		return null
	var cfg := {}
	if mock:
		# the local stand-in only: your llm.json (and its key) is not read at all
		cfg = {"api_key": "sk-or-mock", "provider": "openrouter", "endpoint": OS.get_environment("WOA_FORUM_LLM"),
			"usage_path": "user://llm_usage_probe.json"}
	else:
		cfg = LlmChat.load_config()
	if cfg.is_empty():
		return null
	var fw := ForumWriter.new()
	fw.name = "ForumWriter"
	parent.add_child(fw)
	fw.llm = LlmChat.new()
	fw.add_child(fw.llm)
	fw.llm.setup(null, 0, cfg)
	return fw

func busy() -> bool:
	return not _pending.is_empty()

## Ask for the model's version of a pending reply `q` in `th` (its text lands in q.text).
func want_reply(th: Dictionary, q: Dictionary) -> void:
	if calls >= MAX_CALLS or q.has("text") or q.has("asked"):
		return
	q["asked"] = true
	var offline := Forum.answer_text(th, String(q.a), int(q.to))
	var prompt := _reply_prompt(th, String(q.a), int(q.to), offline)
	_ask("r%d:%d:%s" % [int(th.id), int(q.at), String(q.a)], "reply", q, prompt, 140)

## Ask for the model's version of a thread a ladder player just posted (title and body are replaced when it comes
## back, if you have not opened it yet).
func want_thread(th: Dictionary) -> void:
	if calls >= MAX_CALLS or thread_calls >= MAX_THREAD_CALLS or th.has("llm") or String(th.a) == "me":
		return
	thread_calls += 1
	th["llm"] = "asked"
	_ask("t%d" % int(th.id), "thread", th, _thread_prompt(th), 220)

func _ask(key: String, kind: String, ref: Dictionary, prompt: String, max_out: int) -> void:
	var body := {}
	var sys := _system()
	if llm.openrouter():
		body = {"model": llm.model(), "max_tokens": max_out + 80, "reasoning": {"enabled": false}, "usage": {"include": true},
			"messages": [{"role": "system", "content": sys}, {"role": "user", "content": prompt}]}
	else:
		body = {"model": llm.model(), "max_tokens": max_out, "thinking": {"type": "disabled"},
			"system": [{"type": "text", "text": sys, "cache_control": {"type": "ephemeral"}}],
			"messages": [{"role": "user", "content": prompt}]}
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	req.request_completed.connect(_on_done.bind(key, req))
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + llm.key, "anthropic-version: 2023-06-01"])
	if llm.openrouter():
		headers = PackedStringArray(["content-type: application/json", "authorization: Bearer " + llm.key, "x-title: Warriors of Aether"])
	var url := String(llm.cfg.get("endpoint", LlmChat.OR_ENDPOINT if llm.openrouter() else LlmChat.ENDPOINT))
	if req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		req.queue_free()
		return
	calls += 1
	_pending[key] = {"kind": kind, "ref": ref}

func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, key: String, req: HTTPRequest) -> void:
	req.queue_free()
	var p: Dictionary = _pending.get(key, {})
	_pending.erase(key)
	if p.is_empty() or result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or d.has("error"):
		return
	var text := ""
	for c in d.get("content", []):
		if c is Dictionary and String(c.get("type", "")) == "text":
			text += String(c.get("text", ""))
	for ch in d.get("choices", []):
		if ch is Dictionary and ch.get("message") is Dictionary and ch.message.get("content") != null:
			text += String(ch.message.content)
			break
	llm._count(d.get("usage", {}))
	text = text.strip_edges()
	if text == "":
		return
	var ref: Dictionary = p.ref
	if String(p.kind) == "reply":
		ref["text"] = _one_reply(text)
	else:
		var title := ""
		var bodytxt := ""
		for line in text.split("\n", false):
			var l := line.strip_edges()
			if l.to_upper().begins_with("TITLE:"):
				title = l.substr(6).strip_edges()
			elif l.to_upper().begins_with("BODY:"):
				bodytxt = l.substr(5).strip_edges()
			elif bodytxt != "":
				bodytxt += " " + l
		if title != "" and bodytxt != "" and String(ref.get("llm", "")) == "asked":
			ref["title"] = _trim(title, 90)
			ref["body"] = _trim(bodytxt, 600)
			ref["llm"] = "done"
			Forum.save()

static func _trim(s: String, n: int) -> String:
	return s.strip_edges().trim_prefix("\"").trim_suffix("\"").substr(0, n)

static func _one_reply(t: String) -> String:
	var s := t.strip_edges().trim_prefix("\"").trim_suffix("\"").strip_edges()
	var colon := s.find(": ")
	if colon > 0 and colon < 24 and not s.substr(0, colon).contains(" "):
		s = s.substr(colon + 2)
	return s.replace("\n", " ").substr(0, 320)

func save_usage() -> void:
	if llm != null:
		llm.save_usage()

func _exit_tree() -> void:
	save_usage()

# ---- Prompts ----------------------------------------------------------------------------------------------------------

var _sys := ""

func _system() -> String:
	if _sys != "":
		return _sys
	var heroes: Array = []
	for id in GameSettings.random_pool():
		var d := SimData.unit(String(id))
		var abil: Array = []
		for a in d.get("abilities", []):
			var nm := String(SimData.ability(String(a)).get("name", ""))
			if nm != "":
				abil.append(nm)
		var line := "- %s: %s" % [String(d.get("name", id)), ", ".join(abil)]
		if SimBotKits.HOW_TO_PLAY.has(String(id)):
			line += " (" + String(SimBotKits.HOW_TO_PLAY[String(id)]) + ")"
		heroes.append(line)
	_sys = """You write posts on the player forum of Warriors of Aether, a 5 v 5 lane battle game played exactly like Dota 2 (three lanes, towers, barracks, a Throne, creeps, last hits, denies, neutral camps, wards, items, buyback, MMR ranks: Rookie, Advanced, Licensed, Expert, Commander, Chief Commander, Legendary, Mythic, Hero, Transcendent, Aetherium; the top ten are Aetherium+). The forum is like a busy subreddit for the game: people brag, rant, ask for help, look for a duo, argue about heroes and items, troll and flame each other, and talk about players they met.

Heroes and abilities:
%s
Items people talk about: Spell Shield, Jump Knife, Kugmo, Igit, Atuli, Mini-Axe, Fade Cape, Push Staff, Vegan Picker, boots, wards.

How to write:
- Write as the forum user you are given, in their voice: their personality, their rank, their typing (lower case, short forms, laughs like haha, wkwk, kkkk, jaja), their language (some write Taglish or Filipino, most plain English).
- Rank matters a lot on this forum: high-rank players with a big ego are confident and arrogant toward lower ranks; kind players help; trolls troll; jokers joke; shot callers give real tips (abilities, items, timings).
- Use the facts you are given (names, heroes, abilities, scores). Do not invent match numbers.
- When someone talks to you, answer what they actually wrote: questions get real answers, jokes get jokes.
- When someone flames, insults or trash talks you, fire back like a real forum user: a witty, cocky, cutting roast (their rank, their post, their attitude, their record). Even a kind user answers with a joke at their expense. Never act like a moderator: never tell them to relax, calm down, chill or be nice, never lecture them, never apologise.
- Trash talk about the game and light swearing are normal ("tangina", "gago", "bobo", "pota", "wtf"). Never use slurs, never insult anyone's race, nationality, religion, sex, sexuality or disability, no threats outside the game, nothing about self-harm.
- You are a person, never an AI or assistant. No emoji, no hashtags, no quotes around your text, no name in front.""" % "\n".join(heroes)
	return _sys

func _who(id: String) -> String:
	var p := Forum.person(id)
	var ps: Dictionary = p.get("persona", {})
	var st: Dictionary = ps.get("style", {})
	var tl := float((p.get("voice", {}) as Dictionary).get("tl", 0.2))
	var heroes: Array = (p.get("heroes", []) as Array).map(func(h): return HeroDraft.hero_name(String(h)))
	return "%s, %s (%d MMR) from %s, plays %s, main heroes %s. Personality (0 to 1): kind %.1f, ego %.1f, temper %.1f, humor %.1f, focus %.1f; on the forum: %s. Types %s, %s, laughs \"%s\". Language: %s." % [
		String(p.get("name", "")), Ranked.rank_label(p), int(p.get("mmr", 0)), Ranked.country_name(String(p.get("country", ""))),
		RankedNum.role(int((p.get("roles", [1]) as Array)[0])), ", ".join(heroes), float(ps.get("kind", 0.5)), float(ps.get("ego", 0.5)),
		float(ps.get("temper", 0.5)), float(ps.get("humor", 0.5)), float(ps.get("focus", 0.5)), Forum.stance(id),
		"in lower case" if bool(st.get("lower", true)) else "with capitals", "many short forms" if float(st.get("short", 0.3)) > 0.5 else "few short forms",
		String(st.get("laugh", "haha")), "Taglish and Filipino" if tl >= 0.6 else ("Taglish or English" if tl >= 0.3 else "English")]

func _name_rank(id: String) -> String:
	if id == "me":
		return "%s (%s)" % [String(Ranked.me().get("name", "Player")), Ranked.rank_label(Ranked.me())]
	return "%s (%s)" % [Forum.name_of(id), Forum.rank_of(id)]

func _thread_text(th: Dictionary) -> String:
	var out := "[%s] \"%s\" by %s:\n%s\n" % [String(th.tag), String(th.title), _name_rank(String(th.a)), String(th.body)]
	var rs: Array = th.replies
	if not rs.is_empty():
		out += "Replies so far:\n"
		for r in rs.slice(maxi(0, rs.size() - 8)):
			out += "- %s: %s\n" % [_name_rank(String(r.a)), String(r.text)]
	return out

func _reply_prompt(th: Dictionary, author: String, to: int, offline: String) -> String:
	var y: Dictionary = Forum.person(author).get("you", {})
	var you := String(Ranked.me().get("name", "Player"))
	var feel := Persona.feeling(float(y.get("rep", 0.0)))
	var met := "never played with %s" % you if not y.has("games") else "played %d games with or against %s (last time %s, %s %s); %s" % [
		int(y.get("games", 0)), you, "with them" if String(y.get("last_side", "")) == "with" else "against them",
		"they went", String(y.get("last_you_kda", "?")), feel.to_lower()]
	var target := String(th.a) if to < 0 or to >= (th.replies as Array).size() else String(th.replies[to].a)
	var said := String(th.body) if to < 0 else String(th.replies[to].text)
	var out := "You are %s\nAbout the player %s (%s): you %s.\n%s's profile (anyone can look it up; on this forum averages and recent matches are everything): %s\n\nThe thread:\n%s\n" % [
		_who(author), you, Ranked.rank_label(Ranked.me()), met, you, ProfileTalk.summary(ProfileTalk.read(Ranked.me())), _thread_text(th)]
	out += "You are replying to %s, who wrote: \"%s\"\n" % [_name_rank(target), said]
	if target == "me":
		var rude := ChatMind.intent(" " + said.to_lower() + " ") in ["insult", "taunt"]
		if rude:
			out += "%s is trash talking or insulting. Talk back: a witty, cutting roast that answers exactly what they wrote. Do not calm them down, do not tell them to relax or be nice, do not lecture, do not ignore it.\n" % you
		else:
			out += "Answer %s directly, about exactly what they wrote, in your own voice (a question gets a real answer, bait gets bitten).\n" % you
	out += "A reply this user might write (keep its facts if they help): \"%s\"\nWrite your reply now: 1 to 3 sentences, at most 60 words." % offline
	return out

func _thread_prompt(th: Dictionary) -> String:
	return "You are %s\nYou are posting a new thread in the forum section \"%s\". A post this user might write:\nTITLE: %s\nBODY: %s\nWrite your own version with the same subject and facts. Output exactly two lines:\nTITLE: (at most 12 words)\nBODY: (1 to 4 sentences, at most 80 words)" % [
		_who(String(th.a)), String(th.tag), String(th.title), String(th.body)]
