extends SceneTree
## Prints the online chat writer's prompts (run 2026-10-23) for a bot game at a given minute, without sending anything:
## no key is read and nothing goes over the network. For checking what the model is told (the heroes, the items worth
## naming, the rules, the match digest).
##   godot --headless --path . -s tests/tools/llm_prompt_probe.gd -- [--min=12] [--seed=3] [--out=x.txt]

const C = preload("res://src/sim/sim_const.gd")

func _init() -> void:
	var minutes := 12.0
	var seed := 3
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min="):
			minutes = float(a.substr(6))
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
	var m := SimMap.new()
	m.build(1)
	var w := SimWorld.new(seed, m)
	w.setup_match()
	var ids := ["dracoxinia", "sludge", "froster", "kaileh", "tock", "caziel", "gancho", "blackfire", "azrin", "emelrich"]
	for i in ids.size():
		var team := C.DAWN if i < 5 else C.DUSK
		var h := w.spawn_hero(ids[i], team)
		w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % i, "hard"))
	while w.time < minutes * 60.0 and w.winner < 0:
		w.step()
	var lc := LlmChat.new()
	lc.setup(w, C.DAWN, {"api_key": "", "provider": "openrouter", "endpoint": "http://127.0.0.1:9/none"})
	var h0: SimUnit = w.heroes[0]
	var text := "=== SYSTEM ===\n" + lc._system_prompt() + "\n\n=== USER (a counter call) ===\n" + lc.user_prompt(
		{"u": h0.id, "cat": "counter_call", "fill": {"hero": "sludge", "item": "spell shield", "why": "spell immunity"},
		"text": "vs sludge get spell shield"})
	print(text)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	lc.free()
	quit()
