extends SceneTree
## A 5 v 5 match with a "player" (a bot drives the hero, but the chat sees a person: run 2026-10-19 e) who types like
## a toxic player: greets, says "ez" after kills, flames, asks where a hero is, asks a teammate to add them, "gg ez".
## Writes the whole chat the player can read (all chat, the player's team chat) with the kills marked, for the blind
## review of the social layer (ChatSocial) against the same match without it.
##   godot --headless --path . -s tests/tools/social_probe.gd -- [--seed=7] [--min=28] [--off] [--out=work/x.txt]

const C = preload("res://src/sim/sim_const.gd")

var lines: Array[String] = []

func _clock(t: float) -> String:
	var s := int(absf(t))
	return "%s%02d:%02d" % ["-" if t < 0.0 else "", s / 60, s % 60]

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed := int(args.get("seed", "7"))
	var mins := float(args.get("min", "28"))
	ChatSocial.off = args.has("off")
	var map := SimMap.new()
	map.build(1)
	var w := SimWorld.new(seed, map)
	w.setup_match()
	var dawn := ["araki", "azrael", "kragg", "froster", "ezee"]
	var dusk := ["caziel", "sludge", "blau", "azrin", "tock"]
	var names := ["lemonQ", "kuya jeff", "mika", "xXslayerXx", "Bea", "ken", "aimbot pls", "tito boy", "nova", "papi chulo"]
	var ranks := [["Commander 2", 4], ["Expert 4", 3], ["Legendary 1", 6], ["Commander 5", 4], ["Expert 1", 3],
		["Mythic 3", 7], ["Commander 1", 4], ["Licensed 4", 2], ["Chief Commander 2", 5], ["Expert 3", 3]]
	var me: SimUnit = null
	var pb: SimBot = null
	var i := 0
	for team in [C.DAWN, C.DUSK]:
		for id in (dawn if team == C.DAWN else dusk):
			var h := w.spawn_hero(id, team)
			if i == 0:
				me = h
				h.player = true
				h.player_name = String(names[0])
				pb = SimBot.new(w, h.id, "mid", String(names[0]))
				h.gold_mult = 1.8
				h.xp_mult = 1.4
			else:
				var b := SimBot.new(w, h.id, "mid", String(names[i]))
				b.card = {"rank": String(ranks[i][0]), "tier": int(ranks[i][1]), "mmr": 600 * int(ranks[i][1]) + 200}
				w.bots.append(b)
			i += 1
	me.bot = false
	w.brain(C.DAWN)
	w.player_cards[me.id] = {"rank": String(ranks[0][0]), "tier": int(ranks[0][1]), "last_mvp": true}
	var said := {}
	var mine_lines := {}
	var last_k := 0
	var last_d := 0
	var steps := int((mins * 60.0 - C.PREGAME_TIME) * C.TICK_RATE)
	for s in steps:
		pb.think()
		me.bot = false
		w.step()
		for e in w.events:
			match String(e.t):
				"chat":
					if bool(e.get("all", false)) or int(e.team) == me.team:
						var u := w.get_unit(int(e.u))
						if u == me and not mine_lines.has(String(e.text)):
							continue                     # the bot driving the hero calls its plans: not the player's words
						var who := ("YOU" if u == me else "%s (%s)" % [String(e.name), SimTeamAI.hero_label(u)]) if u != null else String(e.name)
						lines.append("[%s] %s %s: %s" % [_clock(w.time), "(All)" if bool(e.get("all", false)) else "(Team)", who, String(e.text)])
				"hero_kill":
					var k := w.get_unit(int(e.get("u", -1)))
					var v := w.get_unit(int(e.victim))
					var tag := ""
					var m := int(e.get("multi", 0))
					if m >= 2:
						tag = [" (Double Kill)", " (Triple Kill)", " (Ultra Kill)", " (Rampage)"][mini(m, 5) - 2]
					elif int(e.get("streak", 0)) >= 3:
						tag = " (%d kill streak)" % int(e.streak)
					lines.append("[%s] * %s killed %s%s" % [_clock(w.time), (k.who() if k != null else "creeps"), v.who() if v != null else "?", tag])
		w.events.clear()
		# the player's own lines
		var say := func(text: String, all: bool) -> void:
			mine_lines[text] = true
			w.chat(me.team, me.id, text, all)
		if w.time >= -45.0 and not said.has("hi"):
			said["hi"] = true
			say.call("hi guys", false)
		if me.kills > last_k:
			if me.multi_kill >= 2 or me.streak >= 3 or w.rng.randf() < 0.25:
				say.call(["ez", "too easy", "sit", "ez mid"][me.kills % 4], true)
			last_k = me.kills
		if me.deaths > last_d:
			if me.deaths % 3 == 0:
				say.call("noob team", false)
			last_d = me.deaths
		if w.time >= 480.0 and not said.has("where"):
			said["where"] = true
			say.call("where is caziel", false)
		if w.time >= 720.0 and not said.has("ggez"):
			said["ggez"] = true
			say.call("gg ez", true)
		if w.time >= 900.0 and not said.has("add"):
			said["add"] = true
			say.call("mika add me after", false)
		if w.time >= 1080.0 and not said.has("trash"):
			said["trash"] = true
			say.call("sludge so trash lol", true)
		if w.time >= 1320.0 and not said.has("rank"):
			said["rank"] = true
			say.call("what rank u guys", true)
		if w.winner >= 0:
			break
	lines.append("[%s] * end: %s, YOU %d/%d/%d" % [_clock(w.time), "winner " + String(C.TEAM_NAMES[w.winner]) if w.winner >= 0 else "time up", me.kills, me.deaths, me.assists])
	var outp := String(args.get("out", ""))
	if outp != "":
		var f := FileAccess.open(ProjectSettings.globalize_path("res://" + outp) if not outp.contains(":") else outp, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	else:
		print("\n".join(lines))
	print("lines: %d" % lines.size())
	quit(0)
