class_name BotNames
extends RefCounted
## Player names for the ranked ladder's bots (run 2026-10-19 b; the owner: names like "01-hank pop", "weakass",
## "BISAKOL SLAYER", "basta tangalog bobo", "mama mo"). Names are built the way players type them: a number and a
## nickname, a word glued onto "ass" or "boi", a Filipino word in capitals with a gamer word, a whole Taglish phrase,
## xX tags, clan tags, l33t spelling, "<hero> main". Every name is checked against the ones made so far (case and
## spaces ignored), so the ladder never shows two alike.

## The owner's own examples, always on the ladder.
const OWNER := ["01-hank pop", "weakass", "BISAKOL SLAYER", "basta tangalog bobo", "mama mo"]

const FIRST := ["hank", "jun", "jojo", "nonoy", "totoy", "kevin", "mark", "jhon", "jerome", "jay", "ronnie", "bong",
	"dong", "ding", "pao", "migs", "kiko", "jepoy", "buboy", "tonyo", "kulot", "bimbo", "toto", "bebot", "inday",
	"neneng", "dodong", "carlo", "rj", "jm", "jp", "kc", "lj", "aj", "mj", "bryan", "kenneth", "jericho", "ace",
	"paolo", "renz", "vince", "dave", "earl", "kyle", "aldrin", "ramon", "lito", "boyet", "nestor", "edgar", "gary",
	"wally", "dennis", "rodel", "jomar", "marlon", "arnel", "joel", "ricky"]
const SHORT := ["pop", "boy", "lang", "gg", "ez", "tv", "jr", "ph", "pogi", "xd", "lol", "ko", "pre", "tol", "idol",
	"bai", "sir", "po", "ok", "ngani"]
const FIL := ["bisakol", "tambay", "lodi", "petmalu", "werpa", "astig", "pasaway", "bunso", "kuya", "tito", "tita",
	"lola", "lolo", "pogi", "sabaw", "gutom", "antok", "chibog", "sisig", "adobo", "lechon", "balut", "tuyo",
	"longganisa", "pandesal", "siomai", "taho", "ube", "kanin", "sinigang", "tinola", "bagoong", "kalamansi", "tropa",
	"barkada", "pare", "bes", "marites", "lods", "bossing", "utol", "kabayo", "kalabaw", "manok", "bangus", "tilapia",
	"itlog", "pancit", "lumpia", "turon", "fishball", "jeep", "trike", "tsinelas", "walis", "kaldero", "unan",
	"kumot", "tabo", "tsismis", "kanto", "sari sari", "videoke", "kape", "tsokolate", "mais", "kamote", "talong",
	"sitaw", "upo", "patis", "toyo", "suka", "bigas"]
const ENG := ["slayer", "killer", "enjoyer", "main", "feeder", "smurf", "carry", "goblin", "gremlin", "potato",
	"toaster", "noob", "gamer", "sweat", "tryhard", "rat", "menace", "demon", "legend", "beast", "monster", "machine",
	"sniper", "cooker", "chef", "merchant", "farmer", "hunter", "sensei", "intern", "boomer", "npc", "simp", "goat",
	"clown", "lord", "king", "prince", "boss", "addict", "survivor", "tourist", "dealer", "collector", "gambler",
	"specialist", "expert", "professor", "student", "spammer", "camper", "jungler", "pusher", "diver", "stacker"]
const ADJ := ["weak", "sad", "tired", "angry", "salty", "toxic", "sleepy", "hungry", "broke", "lonely", "sweaty",
	"crazy", "lazy", "chill", "spicy", "cursed", "based", "silent", "tiny", "big", "fat", "fast", "slow", "lucky",
	"unlucky", "noisy", "shy", "smelly", "sneaky", "sus", "washed", "retired", "jobless", "single", "petty", "baby",
	"humble", "loud", "random", "crispy", "soggy", "boring", "mid", "nervous", "honest", "useless", "clutch"]
const GLUE := ["ass", "boi", "guy", "kid", "lolo", "tito", "dude", "cat", "dog", "ako", "lang", "man", "gurl", "bro"]
const PHRASES := ["ikaw na bahala", "di ako feeder", "carry mo ko", "bawi next game", "sana all mmr", "wag kang ganyan",
	"lag lang to", "isang game pa", "tulog na ko", "gutom na ako", "pa carry po", "ako na bahala", "walang support",
	"report mid", "mid or feed", "sorry na po", "gg ez", "ez lang", "no tilt", "kain muna", "mamaya na", "uwi na ko",
	"bahala na", "ayoko na", "char lang", "tapos na", "bili ka ward", "pa mmr po", "di ko kasalanan", "nag aaral pa",
	"one more game", "my mom is calling", "it was lag", "just one more", "trust me bro", "not my fault", "buy wards pls",
	"why am i here", "i only play mid", "send help", "stop pinging me", "no flame pls", "uninstall pls",
	"inom muna tayo", "basta ako mid", "nasaan support", "sino feeder", "ewan ko sayo", "di na ako galit",
	"mahal kita mid", "walang ganon", "hindi ako bot", "papa mo pogi", "tita mo ganda", "kuya wag", "sige lang",
	"basta ako carry", "pakyu lag", "tanga ng team"]
const TAGS := ["PH", "GG", "MNL", "CEB", "DVO", "QC", "XD", "EZ", "SEA", "OG", "TNT", "BBQ", "LOL", "AFK"]
const HEROES := ["Jayla", "Ezee", "Sludge", "Azrin", "Froster", "Caziel", "Tock", "Kragg", "Roydo", "Blau", "Azrael",
	"Airah", "Burak", "Emelrich", "Feran", "Ghorman", "Araki", "Blackfire", "Thyrandael"]

## `n` names, all different (case and spaces ignored), the owner's examples first.
static func make_many(n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var seen := {}
	for o in OWNER:
		if out.size() >= n:
			break
		out.append(o)
		seen[key(o)] = true
	var guard := 0
	while out.size() < n and guard < n * 60:
		guard += 1
		var s := make(rng)
		var k := key(s)
		if s.length() < 3 or s.length() > 22 or seen.has(k):
			continue
		seen[k] = true
		out.append(s)
	return out

## The form two names are compared in: lower case, spaces, dots, dashes and underscores dropped.
static func key(s: String) -> String:
	var k := s.to_lower()
	for c in [" ", ".", "-", "_", "[", "]"]:
		k = k.replace(c, "")
	return k

static func _p(rng: RandomNumberGenerator, list: Array) -> String:
	return String(list[rng.randi_range(0, list.size() - 1)])

static func make(rng: RandomNumberGenerator) -> String:
	var roll := rng.randi_range(0, 99)
	if roll < 10:
		return "%02d-%s %s" % [rng.randi_range(0, 99), _p(rng, FIRST), _p(rng, SHORT)]
	if roll < 20:
		return _p(rng, ADJ) + _p(rng, GLUE)
	if roll < 30:
		return ("%s %s" % [_p(rng, FIL), _p(rng, ENG)]).to_upper()
	if roll < 40:
		var ph := _p(rng, PHRASES)
		return ph if rng.randf() < 0.75 else "%s %d" % [ph, rng.randi_range(1, 99)]
	if roll < 45:
		return "xX_%s_Xx" % _p(rng, ENG if rng.randf() < 0.6 else FIL)
	if roll < 53:
		return "%s%d" % [_p(rng, ENG if rng.randf() < 0.5 else FIL), [rng.randi_range(1, 99), rng.randi_range(1995, 2011)][rng.randi_range(0, 1)]]
	if roll < 60:
		return "%s ni %s" % [_p(rng, ENG if rng.randf() < 0.5 else FIL), _p(rng, FIRST)]
	if roll < 66:
		return "%s %s" % [_p(rng, ["lil", "big", "mr", "itz", "sir", "kuya", "ate", "papa", "mama", "tito"]), _p(rng, FIRST if rng.randf() < 0.5 else ENG)]
	if roll < 71:
		return "[%s] %s" % [_p(rng, TAGS), _p(rng, FIRST if rng.randf() < 0.5 else FIL)]
	if roll < 76:
		return _leet("%s %s" % [_p(rng, ADJ), _p(rng, ENG)], rng)
	if roll < 80:
		return "%s.exe" % _p(rng, FIRST if rng.randf() < 0.5 else FIL)
	if roll < 86:
		return "%s %s" % [_p(rng, HEROES), _p(rng, ["main", "enjoyer", "only", "spammer", "fan", "abuser", "god", "diff"])]
	if roll < 91:
		return "%s %s" % [_p(rng, ADJ), _p(rng, FIL)]
	if roll < 95:
		var a := _p(rng, FIRST)
		return a + a.substr(a.length() - 1).repeat(rng.randi_range(2, 4))
	return "%s %s" % [_p(rng, FIL), _p(rng, SHORT)]

## l33t spelling of some letters ("sad goblin" -> "s4d g0bl1n"), sometimes in capitals.
static func _leet(s: String, rng: RandomNumberGenerator) -> String:
	var map := {"a": "4", "e": "3", "i": "1", "o": "0", "s": "5"}
	var out := ""
	for c in s:
		out += String(map[c]) if map.has(c) and rng.randf() < 0.6 else c
	return out.to_upper() if rng.randf() < 0.3 else out
