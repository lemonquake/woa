class_name Persona
extends RefCounted
## Who a player is (run 2026-10-19 d; the owner: "each with their own personalities and uniqueness and profiles that are
## also updating through time"). A persona is fixed when a profile is made, from its seed and its manners (toxic, coop,
## rage, voice, country, skill), and never changes after; what changes is the player's mood, status, the hero they are
## learning and what they remember of you (Ranked keeps those).
##   * traits 0..1: talk (how often they type), kind, ego (brags), temper (tilts), humor, focus (talks about the game:
##     calls, timings, items), and the ranked manners they already had;
##   * typing: lower case or not, end punctuation, typos, stretched letters ("nooo"), short forms ("u", "pls"), their
##     laugh ("haha", "wkwk", "kkkk", "555", "jaja" by country), pet words ("lods", "pre", "bro", "mate"), a smiley;
##   * a daily schedule in their own time zone (evenings, nights, after school, all day), so at any hour some players
##     are online, some in a match and some away (last seen);
##   * labels for the profile ("Friendly", "Shot caller", "Flamer", "Quiet" ...), a short bio and a status of their own.
## Everything here is deterministic: the same seed gives the same persona, the same hour gives the same presence.

## Hours from UTC for each country on the ladder (Ranked.COUNTRIES).
const TZ := {"PH": 8, "ID": 7, "MY": 8, "TH": 7, "VN": 7, "SG": 8, "PE": -5, "BR": -3, "RU": 3, "UA": 2, "US": -5,
	"DE": 1, "SE": 1, "CN": 8, "KR": 9, "AU": 10, "": 8}
## How players laugh in chat, by country.
const LAUGH := {"PH": ["haha", "hahaha", "HAHAHA", "lol", "xD", "hahahaha", "ahahaha"], "ID": ["wkwk", "wkwkwk", "haha"],
	"MY": ["haha", "wkwk", "lol"], "TH": ["555", "5555", "haha"], "VN": ["haha", "kkk", "lol"], "SG": ["lol", "haha", "lmao"],
	"PE": ["jaja", "jajaja", "xD"], "BR": ["kkkk", "kkkkkk", "huehue", "rsrs"], "RU": ["xD", "lol", "ahah"],
	"UA": ["xD", "lol", "ahah"], "US": ["lol", "lmao", "haha"], "DE": ["xD", "lol", "haha"], "SE": ["haha", "lol", "xD"],
	"CN": ["666", "lol", "haha"], "KR": ["kkk", "lol", "haha"], "AU": ["haha", "lol", "lmao"]}
## Words a player keeps adding, by voice: Filipino and Taglish, English, Australian.
const PET_TL := ["lods", "pre", "par", "bai", "boss", "tol", "idol", "grabe", "hala", "jusko", "sheesh", "pare", "bes"]
const PET_EN := ["bro", "dude", "man", "fr", "ngl", "bruh", "sheesh", "lowkey", "tbh", "guys"]
const PET_AU := ["mate", "bro", "fr", "oi"]
const SMILES := [":)", ":D", "xd", "^^", ":(", ":/", "xD", "<3"]
## Daily schedules: [first hour, hours online] in local time.
const HOURS := {"evening": [18, 6], "night": [21, 7], "school": [15, 6], "all_day": [10, 14], "morning": [7, 6],
	"late": [23, 6]}

## Plain words for the profile (two at most are shown).
const LABELS := ["Friendly", "Quiet", "Talks a lot", "Shot caller", "Show-off", "Tilts easily", "Joker", "Tryhard",
	"Flamer", "Troll", "Plays alone", "Chill", "Team player", "Calm"]

## Bios (the line under the name on a profile). {hero}: their main hero.
const BIO_TL := ["laro lang", "chill lang tayo", "bawal pikon", "isang game pa tapos tulog", "pa add for duo",
	"{hero} lang malakas", "puyat na naman", "galing ML, bago lang dito", "no mic pero may utak", "walang tulog walang uwian",
	"student, laro pag walang klase", "trabaho muna tapos laro", "tropa lang, walang away", "basta {hero}",
	"mid or feed", "support na mahal ang ward", "di ako toxic promise", "sana all may support"]
const BIO_EN := ["just here to have fun", "add me for duo", "gl hf everyone", "{hero} main", "road to Aetherium",
	"grinding every night", "no flame, we learn", "i play for the memes", "professional feeder", "mid only",
	"support player, buy your own wards", "back after a long break", "one more game then sleep", "{hero} or nothing",
	"chill games only", "my team is the enemy", "dont talk to me before coffee", "best {hero} in my house",
	"work all day, ranked all night", "trying to hit Mythic this season"]
const BIO_QUIET := ["...", "gl", "{hero}", "no mic", "-", "gg"]
const BIO_TOXIC := ["carry me or uninstall", "report = skill issue", "dont pick {hero}, its mine", "mute all", "i dont lose, my team does",
	"ez", "feeders get reported", "1v9 every game"]

## A persona for a profile: from the ranked manners (toxic, coop, rage, voice, country, skill) and a seed.
static func make(seed: int, p: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var toxic := float(p.get("toxic", 0.3))
	var coop := float(p.get("coop", 0.7))
	var rage := bool(p.get("rage", false))
	var skill := clampf(float(p.get("skill", 2500)) / 7000.0, 0.0, 1.0)
	var country := String(p.get("country", "PH"))
	var tl := float((p.get("voice", {}) as Dictionary).get("tl", 0.4))
	var kind := clampf((1.0 - toxic) * 0.75 + coop * 0.25 + r.randf_range(-0.2, 0.2), 0.0, 1.0)
	var talk := clampf(r.randf_range(0.1, 1.0) * 0.8 + toxic * 0.25 + (0.15 if rage else 0.0), 0.08, 1.0)
	if r.randf() < 0.18:
		talk = r.randf_range(0.05, 0.2)                # some players hardly type at all
	var ego := clampf(r.randf_range(0.0, 0.8) + skill * 0.25 + (0.2 if rage else 0.0), 0.0, 1.0)
	var temper := clampf(r.randf_range(0.0, 0.7) + toxic * 0.4 - skill * 0.15, 0.0, 1.0)
	var humor := clampf(r.randf_range(0.0, 1.0), 0.0, 1.0)
	var focus := clampf(r.randf_range(0.0, 0.6) + skill * 0.5 + coop * 0.1, 0.0, 1.0)
	# typing
	var lower := r.randf() < 0.62
	var caps := 1.0 if r.randf() < 0.025 else 0.0    # the few who type everything in capitals
	var style := {
		"lower": lower, "caps": caps,
		"punct": r.randf_range(0.0, 0.15) if lower else r.randf_range(0.2, 0.7),
		"typo": r.randf_range(0.0, 0.05) + (0.08 if r.randf() < 0.2 else 0.0),
		"stretch": r.randf_range(0.0, 0.3),
		"short": clampf(r.randf_range(0.0, 1.0) * (1.2 - skill * 0.4), 0.0, 1.0),
		"laugh": _pick(r, LAUGH.get(country, LAUGH.PH)),
		"smile": _pick(r, SMILES) if r.randf() < 0.3 else "",
		"pet": "",
		"pet_rate": r.randf_range(0.05, 0.3),
	}
	var pets: Array = PET_TL if tl >= 0.3 else (PET_AU if country == "AU" else PET_EN)
	if r.randf() < 0.7:
		style.pet = _pick(r, pets)
	var sched: String = ["evening", "evening", "night", "night", "school", "all_day", "morning", "late"][r.randi_range(0, 7)]
	return {"talk": snappedf(talk, 0.01), "kind": snappedf(kind, 0.01), "ego": snappedf(ego, 0.01),
		"temper": snappedf(temper, 0.01), "humor": snappedf(humor, 0.01), "focus": snappedf(focus, 0.01),
		"style": style, "hours": sched, "shift": r.randi_range(-1, 1), "seed": seed & 0x7fffffff,
		"bio": _bio(r, p, talk, toxic, tl)}

static func _pick(r: RandomNumberGenerator, list: Array) -> String:
	return String(list[r.randi_range(0, list.size() - 1)]) if not list.is_empty() else ""

static func _bio(r: RandomNumberGenerator, p: Dictionary, talk: float, toxic: float, tl: float) -> String:
	var pool: Array = BIO_QUIET if talk < 0.18 else (BIO_TOXIC if toxic > 0.72 else (BIO_TL if tl >= 0.3 and r.randf() < 0.75 else BIO_EN))
	var heroes: Array = p.get("heroes", [])
	var hero := HeroDraft.hero_name(String(heroes[0])) if not heroes.is_empty() else "mid"
	return _pick(r, pool).replace("{hero}", hero)

## A persona for a bot that has no ranked profile (Game Setup, multiplayer): from its name only, so every machine in a
## multiplayer match makes the same one.
static func from_name(nm: String, toxic := 0.35) -> Dictionary:
	var h := absi(hash(nm))
	var kind := h % 3
	return make(h, {"toxic": toxic + float((h / 7) % 30) / 100.0 - 0.1, "coop": 0.75, "skill": 2500,
		"country": "PH" if kind < 2 else "US", "voice": {"tl": [0.75, 0.45, 0.08][kind]}, "heroes": []})

# ---- Labels and status ------------------------------------------------------------------------------------------------

## Up to two plain words for a profile ("Friendly", "Shot caller").
static func labels(p: Dictionary) -> Array:
	var ps: Dictionary = p.get("persona", {})
	if ps.is_empty():
		return []
	var out: Array = []
	var toxic := float(p.get("toxic", 0.0))
	var coop := float(p.get("coop", 1.0))
	if bool(p.get("rage", false)):
		out.append("Troll")
	elif toxic > 0.68:
		out.append("Flamer")
	if float(ps.focus) > 0.72 and coop > 0.7:
		out.append("Shot caller")
	if float(ps.kind) > 0.72 and toxic < 0.35:
		out.append("Friendly")
	if float(ps.talk) < 0.2:
		out.append("Quiet")
	elif float(ps.talk) > 0.85:
		out.append("Talks a lot")
	if float(ps.humor) > 0.8:
		out.append("Joker")
	if float(ps.ego) > 0.8:
		out.append("Show-off")
	if float(ps.temper) > 0.75:
		out.append("Tilts easily")
	if coop < 0.3 and not bool(p.get("rage", false)):
		out.append("Plays alone")
	if float(p.get("skill", 0)) > 4800.0 and float(ps.focus) > 0.6 and not ("Shot caller" in out):
		out.append("Tryhard")
	if out.is_empty():
		out.append("Chill" if float(ps.temper) < 0.4 else ("Team player" if coop > 0.75 else "Calm"))
	return out.slice(0, 2)

## What a profile says about how its player is doing now (shown under the name): their own words unless something
## stands out (a streak, a new hero, a new rank, a slide).
static func status(p: Dictionary) -> String:
	var hero := String(p.get("learning", ""))
	var s := int(p.get("streak", 0))
	if s >= 4:
		return "On a %d win streak" % s
	if s <= -4:
		return "Lost %d in a row" % -s
	if hero != "":
		return "Learning %s" % HeroDraft.hero_name(hero)
	var hist: Array = p.get("history", [])
	if hist.size() >= 2:
		var now_t := Ranked.tier_of(int(p.mmr))
		var before := Ranked.tier_of(int(hist[mini(hist.size() - 1, 4)].get("m", p.mmr)) - int(hist[mini(hist.size() - 1, 4)].get("d", 0)))
		if now_t > before:
			return "Just reached %s" % Ranked.tier_name(now_t)
	var tr := Ranked.trend(p, 10)
	if tr >= 120:
		return "Climbing: %+d MMR in 10 games" % tr
	if tr <= -120:
		return "Rough week: %d MMR in 10 games" % tr
	return String((p.get("persona", {}) as Dictionary).get("bio", ""))

## What a player thinks of you (Ranked "you" rep, -1..1), in plain words.
static func feeling(rep: float) -> String:
	if rep > 0.45:
		return "Likes you"
	if rep > 0.15:
		return "Friendly to you"
	if rep < -0.45:
		return "Does not like you"
	if rep < -0.15:
		return "Annoyed with you"
	return "No strong feelings"

# ---- Presence -----------------------------------------------------------------------------------------------------

## Whether a player is online at unix time `t`: {state: "online" | "match" | "offline", label, hero (in a match),
## minute (of the match), seen (when last online, for "offline")}.
static func presence(p: Dictionary, t: int) -> Dictionary:
	var ps: Dictionary = p.get("persona", {})
	if ps.is_empty() or not bool(p.get("bot", true)):
		return {"state": "online", "label": "Online"}
	var tz := int(TZ.get(String(p.get("country", "")), 8))
	var local := t + tz * 3600
	var day := local / 86400
	var hour := float(local % 86400) / 3600.0
	var on := _on_at(p, ps, day, hour)
	if not on:
		# when they were last on: walk back hour by hour (at most 4 days)
		var seen := t
		for back in range(1, 97):
			var lt := local - back * 3600
			if _on_at(p, ps, lt / 86400, float(lt % 86400) / 3600.0):
				seen = t - back * 3600 + 1800
				break
		if seen == t:
			seen = t - 4 * 86400
		return {"state": "offline", "label": "Last seen " + RankedNum.ago(seen), "seen": seen}
	# online: in a match about half of the time, in 40-minute blocks
	var hh := _match_hash(p, t)
	if hh % 100 < 52:
		var heroes: Array = p.get("heroes", [])
		var hero := String(p.get("learning", "")) if String(p.get("learning", "")) != "" and hh % 3 == 0 else \
			(String(heroes[(hh / 100) % heroes.size()]) if not heroes.is_empty() else "")
		var minute := int(((t + (hh / 100) % 2400) % 2400) / 60) + 1      # each match started at its own time
		return {"state": "match", "label": "In a match" + (" as %s" % HeroDraft.hero_name(hero) if hero != "" else "") + "  ·  %d min" % minute,
			"hero": hero, "minute": minute}
	return {"state": "online", "label": "Online"}

static func _on_at(p: Dictionary, ps: Dictionary, day: int, hour: float) -> bool:
	var sched: Array = HOURS.get(String(ps.get("hours", "evening")), [18, 6])
	var dh := absi(hash("%d:%s" % [day, String(p.get("id", ""))]))
	if dh % 100 < 9:
		return false                                   # a day off
	var weekend := (day + 4) % 7 >= 5                    # 1970-01-01 was a Thursday
	var start := float(int(sched[0]) + int(ps.get("shift", 0)) + (dh / 100) % 3 - 1)
	var length := float(int(sched[1]) + (3 if weekend else 0) + (dh / 300) % 3 - 1)
	var x := fposmod(hour - start, 24.0)
	return x < length

static func _match_hash(p: Dictionary, t: int) -> int:
	return absi(hash("%d:%s:m" % [t / 2400, String(p.get("id", ""))]))

## Online at unix time `t` (in a match or not): cheaper than presence() (no last seen).
static func online(p: Dictionary, t: int) -> bool:
	var ps: Dictionary = p.get("persona", {})
	if ps.is_empty() or not bool(p.get("bot", true)):
		return true
	var local := t + int(TZ.get(String(p.get("country", "")), 8)) * 3600
	return _on_at(p, ps, local / 86400, float(local % 86400) / 3600.0)

static func in_match(p: Dictionary, t: int) -> bool:
	return online(p, t) and _match_hash(p, t) % 100 < 52

## Players who could join your queue now (online and not in a match).
static func queueable(p: Dictionary, t: int) -> bool:
	return online(p, t) and _match_hash(p, t) % 100 >= 52
