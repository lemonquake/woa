class_name ChatStyle
extends RefCounted
## How a player types (run 2026-10-19 d): the same words come out differently from each persona (Persona "style").
## Short forms ("u", "pls", "idk"), lower case or a capital first letter, everything in capitals for the few who do
## and for anyone tilted enough, stretched letters on short outbursts ("nooo", "ezzz"), a slip of the fingers now and
## then, end punctuation for those who use it, their laugh, their pet word ("lods", "bro", "mate") and a smiley.
## Every choice is drawn from the generator passed in (the chat's seeded one), so every multiplayer peer types alike.

const SHORT := [["you are", "ur"], ["you're", "ur"], ["your", "ur"], ["you", "u"], ["please", "pls"], ["thanks", "ty"],
	["okay", "ok"], ["because", "bc"], ["i don't know", "idk"], ["i dont know", "idk"], ["never mind", "nvm"],
	["to be honest", "tbh"], ["going to", "gonna"], ["really", "rly"], ["people", "ppl"], ["what", "wat"],
	["right now", "rn"], ["oh my god", "omg"], ["be right back", "brb"], ["on my way", "omw"], ["are", "r"]]
## Letters next to each other on a keyboard (for slips).
const NEAR := {"a": "sq", "s": "ad", "d": "sf", "f": "dg", "g": "fh", "h": "gj", "j": "hk", "k": "jl", "l": "k",
	"q": "w", "w": "qe", "e": "wr", "r": "et", "t": "ry", "y": "tu", "u": "yi", "i": "uo", "o": "ip", "p": "o",
	"z": "x", "x": "zc", "c": "xv", "v": "cb", "b": "vn", "n": "bm", "m": "n"}

## `text` as `style` types it. tilt 0..1 (a tilted player shouts more); call: a team call (no slips, no stretching,
## numbers stay readable); laugh: chance of a laugh at the end; pet: chance of the pet word.
static func apply(text: String, style: Dictionary, tilt: float, rng: RandomNumberGenerator, call := false,
		laugh := 0.0, pet := -1.0, keep: Array = []) -> String:
	if text == "" or style.is_empty():
		return text
	var s := text
	var lt := String(style.get("laugh", "haha"))
	s = s.replace("{laugh}", lt)
	# short forms
	var short := float(style.get("short", 0.3))
	if short > 0.05:
		var low := " " + s.to_lower() + " "
		for pair in SHORT:
			var a := " " + String(pair[0]) + " "
			if low.contains(a) and rng.randf() < short * (0.35 if String(pair[1]) in ["wat", "r", "rly"] else 1.0):
				low = low.replace(a, " " + String(pair[1]) + " ")
		if low.strip_edges() != s.to_lower().strip_edges():
			s = low.strip_edges()
	# the end: punctuation the way they use it
	var words := s.split(" ", false)
	var bare := s.rstrip(".!")
	var punct := float(style.get("punct", 0.1))
	if bare != s and rng.randf() > punct + 0.25:
		s = bare
	elif bare == s and not s.ends_with("?") and rng.randf() < punct and words.size() >= 3:
		s += "!" if tilt > 0.5 or rng.randf() < 0.3 else "."
	# stretched letters on a short outburst (never on a name: "Frosteeeer")
	var names: Array = keep.map(func(x): return str(x).to_lower())
	var last := String(words[-1]).to_lower().rstrip(".!?") if not words.is_empty() else ""
	var is_name := last in names or names.any(func(n): return n != "" and last.begins_with(String(n).split(" ")[-1]))
	if not call and words.size() <= 3 and rng.randf() < float(style.get("stretch", 0.1)) and not is_name:
		s = _stretch(s, rng)
	# a slip of the fingers (not in names or numbers)
	if not call and rng.randf() < float(style.get("typo", 0.02)):
		s = _slip(s, rng, names)
	# laugh and pet word
	if laugh > 0.0 and rng.randf() < laugh and not s.to_lower().contains(lt.to_lower()):
		s += " " + lt
	var pw := String(style.get("pet", ""))
	var pr := float(style.get("pet_rate", 0.1)) if pet < 0.0 else pet
	if pw != "" and rng.randf() < pr and not s.to_lower().contains(pw) and words.size() <= 6:
		if rng.randf() < 0.25:
			s = pw + " " + s
		else:
			# before the end mark: "stupid man!", not "stupid! man"
			var body := s.rstrip(".!?")
			s = body + " " + pw + s.substr(body.length())
	var sm := String(style.get("smile", ""))
	if sm != "" and not call and rng.randf() < 0.08:
		s += " " + sm
	# case
	if float(style.get("caps", 0.0)) >= 1.0 or (tilt > 0.65 and rng.randf() < (tilt - 0.55) * 1.4):
		s = s.to_upper()
	elif bool(style.get("lower", true)):
		s = s.to_lower()
	elif s.length() > 0:
		s = s.substr(0, 1).to_upper() + s.substr(1)
	return s

## "no" -> "nooo", "ez" -> "ezzz", "why" -> "whyyy": the last vowel (or the last letter) held down.
static func _stretch(s: String, rng: RandomNumberGenerator) -> String:
	var i := s.length() - 1
	while i >= 0 and not (s[i].to_lower() in ["a", "e", "i", "o", "u", "y", "z", "s"]):
		i -= 1
	if i < 0:
		return s
	return s.substr(0, i + 1) + s[i].repeat(rng.randi_range(2, 5)) + s.substr(i + 1)

## One slip in a longer word: two letters swapped, a letter dropped, or a key next to it.
static func _slip(s: String, rng: RandomNumberGenerator, names: Array = []) -> String:
	var words := s.split(" ")
	var cands: Array = []
	var digits := RegEx.create_from_string("[0-9]")
	for i in words.size():
		var wd := String(words[i])
		var bare_wd := wd.to_lower().rstrip(".!?,")
		var in_name := bare_wd in names or names.any(func(n): return String(n).to_lower().split(" ").has(bare_wd))
		if wd.length() >= 4 and digits.search(wd) == null and not wd.contains("{") and not in_name:
			cands.append(i)
	if cands.is_empty():
		return s
	var wi := int(cands[rng.randi_range(0, cands.size() - 1)])
	var wd := String(words[wi])
	var p := rng.randi_range(1, wd.length() - 2)
	match rng.randi_range(0, 2):
		0:
			wd = wd.substr(0, p) + wd[p + 1] + wd[p] + wd.substr(p + 2)
		1:
			wd = wd.substr(0, p) + wd.substr(p + 1)
		_:
			var c := wd[p].to_lower()
			if NEAR.has(c):
				var opts := String(NEAR[c])
				wd = wd.substr(0, p) + opts[rng.randi_range(0, opts.length() - 1)] + wd.substr(p + 1)
	words[wi] = wd
	return " ".join(words)
