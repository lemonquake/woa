extends SceneTree
## The online bot chat (LlmChat) against a stand-in API (tools/llm_mock.py), run 2026-10-19 d:
##   python tools/llm_mock.py --port=8765 --log=work/llm_requests.json      (in another shell)
##   godot --headless --path . -s tests/tools/llm_probe.gd -- [--port=8765] [--min=3]
## A 5 v 5 match with you on Ancient Light plays for a few minutes; every bot line you could read is offered to the
## writer (share 1); prints PASS / FAIL for: requests sent, replies used, the call cap, a slow answer falling back to
## the bot's own line, a failed one too, and the usage counted. The request bodies are checked from the mock's log.

const C = preload("res://src/sim/sim_const.gd")

var _fails := 0
var _opts := {"port": "8765", "min": "3"}

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()

func _world() -> SimWorld:
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(11, m)
	w.setup_match()
	var i := 0
	for team in [C.DAWN, C.DUSK]:
		for id in (["sludge", "ezee", "azrin", "froster", "tock"] if team == C.DAWN else ["caziel", "kragg", "blood_ranger", "azrael", "araki"]):
			var h := w.spawn_hero(id, team)
			if team == C.DAWN and i == 0:
				h.player = true
				h.player_name = "Tester"
			else:
				w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % i))
			i += 1
	w.brain(C.DAWN)
	return w

func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await process_frame

func _run() -> void:
	var base := "http://127.0.0.1:%s" % String(_opts.port)
	var w := _world()
	var llm := LlmChat.new()
	root.add_child(llm)
	llm.setup(w, C.DAWN, {"api_key": "test-key", "endpoint": base + "/v1/messages", "share": 1.0, "max_calls": 12, "timeout": 3.0,
		"usage_path": "user://llm_usage_probe.json"})
	var intents := 0
	var lids: Array = []
	var shown := 0
	var t_end := float(_opts.min) * 60.0 - 90.0
	while w.time < t_end:
		w.step()
		for e in w.events:
			if e.t == "chat_intent":
				intents += 1
				llm.want(e)
				lids.append(int(e.lid))
			elif e.t == "chat" and int(e.get("lid", -1)) >= 0:
				if String(llm.text_for(int(e.lid)).state) == "ready":
					shown += 1
		w.events.clear()
		if w.tick % 30 == 0:
			await process_frame                 # let the requests run
	await _wait(2.0)
	var ready := 0
	for lid in lids:
		if String(llm.text_for(lid).state) == "ready":
			ready += 1
	print("intents %d, calls %d, ready %d, shown on time %d" % [intents, llm.calls, ready, shown])
	check(intents > 0, "bot lines were offered to the writer (%d)" % intents)
	check(llm.calls > 0 and llm.calls <= 12, "requests sent and the per-match cap holds (%d of 12)" % llm.calls)
	check(ready > 0, "replies came back and are used (%d)" % ready)
	var u := llm.usage()
	check(int(u.calls) == ready and float(u.usd) > 0.0, "usage counted: %d calls, $%.5f" % [int(u.calls), float(u.usd)])
	# a slow answer: the bot's own line is used once the wait runs out
	var slow := LlmChat.new()
	root.add_child(slow)
	slow.setup(w, C.DAWN, {"api_key": "test-key", "endpoint": base + "/slow/v1/messages", "share": 1.0, "timeout": 1.5,
		"usage_path": "user://llm_usage_probe.json"})
	var h := w.heroes[1]
	slow.want({"lid": 900001, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi", "fill": {}, "said": "hello"})
	await _wait(0.4)
	check(String(slow.text_for(900001).state) == "waiting", "a slow answer is waited for a moment")
	await _wait(1.6)
	check(String(slow.text_for(900001).state) == "none", "then the bot's own line is used")
	# a failed answer
	var bad := LlmChat.new()
	root.add_child(bad)
	bad.setup(w, C.DAWN, {"api_key": "test-key", "endpoint": base + "/fail/v1/messages", "share": 1.0,
		"usage_path": "user://llm_usage_probe.json"})
	bad.want({"lid": 900002, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi", "fill": {}, "said": "hello"})
	await _wait(1.0)
	check(String(bad.text_for(900002).state) == "none", "a failed answer leaves the bot's own line")
	# no key: nothing is sent
	var off := LlmChat.new()
	root.add_child(off)
	off.setup(w, C.DAWN, {})
	off.want({"lid": 900003, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi"})
	check(off.calls == 0, "without a key nothing is sent")
	# the request itself
	var body := llm.request_body({"lid": 1, "u": h.id, "team": h.team, "all": true, "cat": "revenge", "text": "payback caziel",
		"fill": {"victim": "caziel"}})
	check(String(body.model) == "claude-haiku-5-5" and int(body.max_tokens) == 60 and String(body.thinking.type) == "disabled",
		"model, token cap, thinking off")
	check(String(body.system[0].cache_control.type) == "ephemeral" and String(body.system[0].text).length() > 2500,
		"the long system prompt is marked for caching (%d letters)" % String(body.system[0].text).length())
	check(String(body.messages[0].content).contains("payback caziel") and String(body.messages[0].content).contains("caziel, who killed you"),
		"the moment and the bot's own line are in the request")
	print("---- a request ----\n%s" % String(body.messages[0].content))
	# OpenRouter (the owner's choice): its chat completions format, Bearer key, reported cost
	var orc := LlmChat.new()
	root.add_child(orc)
	orc.setup(w, C.DAWN, {"api_key": "sk-or-test", "endpoint": base + "/api/v1/chat/completions", "share": 1.0,
		"usage_path": "user://llm_usage_probe.json"})
	check(orc.openrouter() and orc.model() == "deepseek/deepseek-v4.1-flash", "an sk-or- key uses OpenRouter with DeepSeek V4.1 Flash (%s)" % orc.model())
	var ob := orc.request_body({"lid": 2, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi", "fill": {}})
	check(String(ob.messages[0].role) == "system" and not (ob.messages[0].content[0] as Dictionary).has("cache_control")
		and not bool(ob.reasoning.enabled) and bool(ob.usage.include) and int(ob.max_tokens) == 200,
		"OpenRouter request: system part (DeepSeek caches on its own), reasoning off, cost reported, 200 tokens of room")
	orc.want({"lid": 900010, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi guys", "fill": {}, "said": "hello"})
	await _wait(1.5)
	var ot: Dictionary = orc.text_for(900010)
	check(String(ot.state) == "ready" and String(ot.text) == "mock hi guys", "OpenRouter's answer is used (%s)" % str(ot))
	check(absf(float(orc.usage().usd) - 0.0000358) < 0.0000001, "the cost OpenRouter reported is logged ($%.7f)" % float(orc.usage().usd))
	var cheap := LlmChat.new()
	root.add_child(cheap)
	cheap.setup(w, C.DAWN, {"api_key": "sk-or-test", "model": "anthropic/claude-haiku-5.5", "usage_path": "user://llm_usage_probe.json"})
	var cb := cheap.request_body({"lid": 3, "u": h.id, "team": h.team, "all": false, "cat": "r_greet", "text": "hi", "fill": {}})
	check(String(cb.model) == "anthropic/claude-haiku-5.5" and String(cb.messages[0].content[0].cache_control.type) == "ephemeral",
		"another OpenRouter model by name (Claude gets its cache mark)")
	llm.save_usage()
	print("%s: %d failed" % ["DONE" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)
