class_name SimBot
extends RefCounted
## A bot for one hero. It acts only through the orders a player issues (SimWorld.command, buy, learn, chat), so it
## obeys every rule a player does. Built after Valve's bot design (research/bots.md of run 2026-10-13-camps-ai-setup):
## its team's brain (SimTeamAI) gives it a role, a lane and team plays; the bot scores its modes several times a second
## (retreat, heal, fight, the team's play, lane, farm, stack, pull, ward) and runs the one it wants most, with a small
## bonus for the current mode so it does not flip back and forth.
##
## What it knows: its hero's kit (combos, skill, talent and item builds per role, SimBotKits), last hits with damage
## prediction, denies, harass, creep and tower aggro, when to leave a lane, which jungle camps it can clear and when
## they respawn, stacking at :53, pulling the safe lane's camps into its own wave, wards, Town Portal for defence,
## ganks and escapes, buyback late in the game. Skill levels follow Dota's bot difficulties (reaction delay, last hit
## error, spell lockouts; Unfair gets +200% gold and +50% experience, the owner's numbers). With learning on (BotMemory) it uses and improves its
## fight model, retreat bar, item build choice, skill shot ranges and lane matchups.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const KITS = preload("res://src/sim/sim_bot_kits.gd")

## Dota's bot difficulties (Valve, research/bots.md section 6): think interval, spell reaction delay, last hit timing
## error (s), skill shot lead (0..1), spells allowed, stacking / pulling / warding, spell lockout every N s for M s,
## lockout after each use, gold and experience multipliers (Unfair: the owner's +200% gold, +50% experience).
const SKILLS := {
	"passive": {"think": 0.45, "react": 9.0, "lh_error": 0.4, "aim": 0.0, "spells": false, "advanced": false,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gold": 1.0, "xp": 1.0, "aggr": 0.0},
	"easy": {"think": 0.4, "react": 0.75, "lh_error": 0.4, "aim": 0.35, "spells": true, "advanced": false,
		"lock_every": 8.0, "lock_for": 6.0, "after_use": 6.0, "gold": 1.0, "xp": 1.0, "aggr": 0.8},
	"medium": {"think": 0.3, "react": 0.45, "lh_error": 0.2, "aim": 0.7, "spells": true, "advanced": true,
		"lock_every": 10.0, "lock_for": 3.0, "after_use": 3.0, "gold": 1.0, "xp": 1.0, "aggr": 0.9},
	"hard": {"think": 0.2, "react": 0.15, "lh_error": 0.0, "aim": 1.0, "spells": true, "advanced": true,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gold": 1.0, "xp": 1.0, "aggr": 1.0},
	"unfair": {"think": 0.15, "react": 0.11, "lh_error": 0.0, "aim": 1.0, "spells": true, "advanced": true,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gold": 3.0, "xp": 1.5, "aggr": 1.05},
}
const SKILL_IDS := ["passive", "easy", "medium", "hard", "unfair"]

## Ranked bots (run 2026-10-19 b): they play by a hidden skill on the MMR scale, between these points: 0-1000 like
## Easy, 2500 like Medium, 4500 like Hard, 7000 like Unfair without its gold. Spells always on; stacking, pulling,
## warding and counter items from 1800. items: how good its item choices are (below 0.35 a scrambled build, below
## 0.6 two items swapped for random ones, from 0.8 a Spell Shield planned for a core, a Jump Knife for a melee hero,
## Fade Cape and Push Staff for a support); item_use: the chance it uses an item when the moment calls for it (each
## look); farm: how well it farms (the jungle and the lane it picks).
const RATED := [
	[0.0, {"think": 0.5, "react": 1.3, "lh_error": 0.5, "aim": 0.15, "lock_every": 8.0, "lock_for": 6.0,
		"after_use": 7.0, "aggr": 0.75, "items": 0.1, "item_use": 0.06, "farm": 0.2}],
	[1000.0, {"think": 0.42, "react": 0.8, "lh_error": 0.42, "aim": 0.35, "lock_every": 8.0, "lock_for": 5.0,
		"after_use": 5.0, "aggr": 0.82, "items": 0.3, "item_use": 0.2, "farm": 0.35}],
	[2500.0, {"think": 0.3, "react": 0.45, "lh_error": 0.2, "aim": 0.7, "lock_every": 10.0, "lock_for": 3.0,
		"after_use": 3.0, "aggr": 0.9, "items": 0.62, "item_use": 0.55, "farm": 0.65}],
	[4500.0, {"think": 0.2, "react": 0.15, "lh_error": 0.0, "aim": 1.0, "lock_every": 0.0, "lock_for": 0.0,
		"after_use": 0.0, "aggr": 1.0, "items": 0.88, "item_use": 0.9, "farm": 0.9}],
	[7000.0, {"think": 0.15, "react": 0.11, "lh_error": 0.0, "aim": 1.0, "lock_every": 0.0, "lock_for": 0.0,
		"after_use": 0.0, "aggr": 1.05, "items": 1.0, "item_use": 1.0, "farm": 1.0}],
]

## A ranked bot's settings for a skill on the MMR scale (RATED, interpolated).
static func rated(r: float) -> Dictionary:
	var lo: Array = RATED[0]
	var hi: Array = RATED[RATED.size() - 1]
	if r >= float(hi[0]):
		lo = hi
	elif r > float(lo[0]):
		for i in RATED.size() - 1:
			if r <= float(RATED[i + 1][0]):
				lo = RATED[i]
				hi = RATED[i + 1]
				break
	else:
		hi = lo
	var f := 0.0 if float(hi[0]) == float(lo[0]) else clampf((r - float(lo[0])) / (float(hi[0]) - float(lo[0])), 0.0, 1.0)
	var out := {"spells": true, "advanced": r >= 1800.0, "gold": 1.0, "xp": 1.0, "rating": r}
	for k in (lo[1] as Dictionary):
		out[k] = lerpf(float(lo[1][k]), float(hi[1][k]), f)
	return out

var w: SimWorld
var hero_id := -1
var lane := "mid"
var name := "Bot"
var state := "lane"                        # kept for older tools: the current mode
var passive := false                       # Debug panel: the bot stands still (a training dummy)
var kit := "blood_ranger"
var role := 2
var skill := "hard"
var sk: Dictionary = SKILLS["hard"]
var aggression := 1.0                      # personality: <1 careful, >1 bold
var rating := -1.0                         # ranked: hidden skill on the MMR scale (-1: a Game Setup skill level)
var coop := 1.0                            # ranked: how often it goes along with the team's calls (1 always)
var disrupt := 0.0                         # ranked: how likely it takes the lane it wants over the one given
var toxic := 0.0                           # ranked: how rough it is in chat
var rage := false                          # ranked: a ragebaiter (dives, flames, ignores the team)
var voice := {}                            # ranked: its chat voice {tl, salt, rough} ({} = from its name)
var lane_grab := ""                        # ranked: the lane a disruptive bot took for itself ("" none)
var persona := {}                          # ranked: who the player is (Persona: traits, typing; {} = from its name)
var pid := ""                              # ranked: the player's id on the ladder ("" for a Game Setup bot)
var you_rec := {}                          # ranked: what it remembers of earlier matches with you (Ranked "you")
var card := {}                             # ranked: what it can tell you about itself (rank, mmr, country, friends)
var _calls_judged := {}                    # team call id -> true once a selfish bot decided about it
var skill_order: Array = []
var build: Array = []
var build_idx := 0
var _build_i := 0
var human := false                         # a player took this hero over while watching (Main.take_control): it sits out
var rng := RandomNumberGenerator.new()
var mode := "lane"
var mode_since := C.LONG_AGO
var desires := {}                          # the last scores (debugging, tests)
var lane_foe := ""                         # the enemy hero it laned against (learning)
var lane_kills := 0
var lane_deaths := 0
var poke_at := C.LONG_AGO                  # Blau: when the bot next looks for a Bounce Shot poke (SimBot16)
var _hunt_target := -1                     # Blau: the laner it went in to kill (SimBot16._blau_hunt)
var _next_think := C.LONG_AGO
var _last_order := {}
var botlog := SimBotLog.new()             # the Debug panel's Bot Log (left out of snapshots)
var _was_alive := true

func _init(world: SimWorld = null, hid := -1, p_lane := "mid", p_name := "Bot", p_skill := "hard") -> void:
	if world == null:
		return                                   # being restored from a snapshot (SimSnapshot sets every field)
	w = world
	hero_id = hid
	lane = p_lane
	name = p_name
	rng.seed = int(world.rng.seed) * 7907 + hid * 131
	set_skill(p_skill)
	var h := hero()
	if h != null:
		kit = String(h.def.id)
		h.bot = true
		h.bot_name = p_name
		w.brain(h.team)
	var r := 2 if p_lane == "mid" else int(KITS.roles(kit)[0])
	set_role(r, p_lane)

func set_skill(p_skill: String) -> void:
	skill = p_skill if SKILLS.has(p_skill) else "hard"
	sk = SKILLS[skill]
	rating = -1.0
	var h := hero()
	if h != null:
		h.gold_mult = float(sk.gold)
		h.xp_mult = float(sk.xp)
	aggression = float(sk.aggr) * rng.randf_range(0.9, 1.12)
	_plan_knife()

## A ranked bot: its play from its hidden skill (RATED) and its personality from its profile (coop, disrupt, toxic,
## rage, voice). Its build is redone for its item sense while nothing is bought.
func set_rating(r: float, traits := {}) -> void:
	rating = r
	skill = "ranked"
	sk = rated(r)
	coop = clampf(float(traits.get("coop", 1.0)), 0.0, 1.0)
	disrupt = clampf(float(traits.get("disrupt", 0.0)), 0.0, 1.0)
	toxic = clampf(float(traits.get("toxic", 0.0)), 0.0, 1.0)
	rage = bool(traits.get("rage", false))
	voice = (traits.get("voice", {}) as Dictionary).duplicate() if traits.get("voice", {}) is Dictionary else {}
	persona = (traits.get("persona", {}) as Dictionary).duplicate(true) if traits.get("persona", {}) is Dictionary else {}
	pid = String(traits.get("pid", ""))
	you_rec = (traits.get("you", {}) as Dictionary).duplicate(true) if traits.get("you", {}) is Dictionary else {}
	card = (traits.get("card", {}) as Dictionary).duplicate(true) if traits.get("card", {}) is Dictionary else {}
	var h := hero()
	if h != null:
		h.gold_mult = 1.0
		h.xp_mult = 1.0
	aggression = float(sk.aggr) * rng.randf_range(0.9, 1.12) + (0.3 if rage else 0.0)
	if _build_i == 0 and not build.is_empty():
		_rate_build()
	_plan_knife()

## A ladder player in a casual match (run 2026-10-19 e, Options "Bots are ladder players"): its name, persona, chat
## voice, memory of you and card, while it plays at the Game Setup skill it was given.
func set_identity(traits := {}) -> void:
	toxic = clampf(float(traits.get("toxic", 0.0)), 0.0, 1.0)
	voice = (traits.get("voice", {}) as Dictionary).duplicate() if traits.get("voice", {}) is Dictionary else {}
	persona = (traits.get("persona", {}) as Dictionary).duplicate(true) if traits.get("persona", {}) is Dictionary else {}
	pid = String(traits.get("pid", ""))
	you_rec = (traits.get("you", {}) as Dictionary).duplicate(true) if traits.get("you", {}) is Dictionary else {}
	card = (traits.get("card", {}) as Dictionary).duplicate(true) if traits.get("card", {}) is Dictionary else {}

## Items a scrambled build draws from: finished items and big parts, 900-6000 gold.
func _random_items(n: int) -> Array:
	var pool: Array = []
	for id in SimData.items():
		var d: Dictionary = SimData.item(id)
		if bool(d.get("consumable", false)) or not (String(d.category) in ["upgrades", "armaments", "misc", "big_parts"]):
			continue
		if int(d.cost) < 900 or int(d.cost) > 6000 or id in build:
			continue
		pool.append(id)
	pool.sort()
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out

## A ranked bot's build for its item sense (RATED "items"): the starting items stay; below 0.35 a few planned items
## and random ones in a random order; below 0.6 two planned items swapped for random ones; from 0.8 a Spell Shield
## for a core, a Fade Cape and a Push Staff for a support (and _plan_knife's Jump Knife for a melee core).
func _rate_build() -> void:
	if rating < 0.0 or build.is_empty():
		return
	var q := float(sk.get("items", 1.0))
	var start := 0
	while start < build.size() and start < 9 and int(SimData.item(String(build[start])).get("cost", 0)) <= 500:
		start += 1
	var rest: Array = build.slice(start)
	if q < 0.35:
		rest = rest.slice(0, rng.randi_range(2, 5)) + _random_items(4 + rng.randi_range(0, 3))
		for i in range(rest.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var x = rest[i]
			rest[i] = rest[j]
			rest[j] = x
	elif q < 0.6:
		var swaps := _random_items(2)
		for x in swaps:
			if rest.size() > 3:
				rest[rng.randi_range(2, rest.size() - 1)] = x
	if q >= 0.8:
		var wants: Array = ["glimmer_cape", "push_staff"] if KITS.is_support(role) else ["spell_shield"]
		for wid in wants:
			var at := rest.find(wid)
			var good := mini(4, rest.size())
			if at < 0 or at > good:
				if at >= 0:
					rest.remove_at(at)
				rest.insert(mini(good, rest.size()), wid)
	build = build.slice(0, start) + rest
	_core_len = build.size()

## Role (1..5) and lane from the team's brain. The build is picked (or learned, BotMemory) once, before anything is
## bought; later role changes keep the items already planned.
func set_role(r: int, p_lane: String) -> void:
	var group_changed := KITS.is_support(r) != KITS.is_support(role) or build.is_empty()
	role = r
	lane = p_lane
	skill_order = KITS.skill_order(kit, r)
	if group_changed and _build_i == 0:
		var opts: Array = KITS.builds(kit, r)
		build_idx = BotMemory.pick_build(KITS.build_key(kit, r), opts.size(), 0, _team())
		build = (opts[clampi(build_idx, 0, opts.size() - 1)] as Array).duplicate()
		_rate_build()
	_plan_knife()
	_core_len = build.size()

const BOOT_UPGRADES := ["power_treads", "slip_boots", "mana_boots", "guard_boots", "travel_boots"]

## Unfair bots on melee heroes buy a Jump Knife right after their boots (the owner's rule): to jump on a target to
## gank it, or away to escape.
func _plan_knife() -> void:
	# Unfair bots, and ranked bots with good item sense (RATED "items" from 0.8)
	if not (skill == "unfair" or (rating >= 0.0 and float(sk.get("items", 0.0)) >= 0.8)) or build.is_empty():
		return
	var h := hero()
	if h == null or float(h.def.projectile_speed) > 0.0:
		return
	var want := -1
	for i in build.size():
		if String(build[i]) in BOOT_UPGRADES:
			want = i + 1
			break
	if want < 0:
		want = mini(build.size(), 7)
	want = maxi(want, _build_i)
	var at := build.find("jump_knife")
	if at >= 0 and at <= want:
		return
	if at >= 0:
		build.remove_at(at)
	build.insert(mini(want, build.size()), "jump_knife")

func hero() -> SimUnit:
	return w.get_unit(hero_id) if w != null else null

func _team() -> int:
	var h := hero()
	return h.team if h != null else -1

func brain() -> SimTeamAI:
	var h := hero()
	return w.brain(h.team) if h != null else null

## What the bot is doing, in a few plain words (the Watch panel shows it over the hero). Reads only: safe to call
## from the interface at any time.
func plan_text() -> String:
	var h := hero()
	if h == null:
		return ""
	if human:
		return "Played by you"
	if not h.alive:
		return "Dead"
	if passive:
		return "Standing still"
	if not h.channel.is_empty() and String(h.channel.get("ability", "")) == "tp":
		return "Teleporting"
	var name_of := func(id: int) -> String:
		var u := w.get_unit(id)
		return String(u.def.get("name", u.name)) if u != null and u.is_hero() else ""
	match mode:
		"retreat":
			return "Retreating"
		"heal":
			return "Going back to heal"
		"fight":
			var fname: String = name_of.call(_fight_target)
			return "Fighting " + fname if fname != "" else "Fighting"
		"task":
			var t := brain().task_for(h.id) if brain() != null else {}
			var tname: String = name_of.call(int(t.get("target", -1)))
			var where := SimTeamAI.lane_label(String(t.get("lane", "")))
			match String(t.get("kind", "")):
				"save": return "Saving " + tname if tname != "" else "Helping an ally"
				"fight": return "Team fight" + (" on " + tname if tname != "" else "")
				"defend": return "Defending " + where if where != "" else "Defending"
				"gank": return "Ganking " + tname if tname != "" else "Ganking"
				"push": return "Pushing " + where if where != "" else "Pushing"
				"group": return "Grouping up"
				"retreat": return "Retreating"
			return "Following a team call"
		"lane":
			return "Laning " + SimTeamAI.lane_label(lane)
		"farm":
			return "Farming camps" if _camp >= 0 else "Farming"
		"stack":
			return "Stacking a camp"
		"pull":
			return "Pulling a camp"
		"ward":
			return "Placing a ward"
		"clear":
			return "Clearing creeps"
	return String(mode).capitalize()

const ORDER_NAMES := ["None", "Move", "Attack", "Attack move", "Hold", "Stop", "Cast", "Cast", "Cast", "Follow",
	"Drop item", "Pick up item", "Give item", "Take orb", "Use site"]

## A line in team chat (SimTeamAI.say). kind and f: what the call is and its facts, typed the bot's own way
## (SimBotChat.casual); "voice": a hero's own line, only typed in the bot's style.
func say(text: String, key := "", every := 30.0, urgent := false, kind := "voice", f := {}) -> void:
	var b := brain()
	if b != null:
		b.say(hero(), text, key, every, urgent, kind, f)
		botlog.on_say(w.time, text)

# ---- Thinking ---------------------------------------------------------------------------------------------------------

func think() -> void:
	if w == null or w.time < _next_think or passive or human:
		return
	# a creep in reach close to dying: look again sooner (the better the bot, the sooner)
	var quick: bool = _creep_low and mode in ["lane", "farm"] and float(sk.lh_error) <= 0.2
	if _next_think == C.LONG_AGO:
		# bots start their think cycles on different ticks, so ten bots never all think in the same tick
		_next_think = w.time + C.DT * float(hero_id % maxi(1, int(round(float(sk.think) / C.DT))))
		return
	_next_think = w.time + (C.DT * 2.0 if quick else float(sk.think))
	var h := hero()
	if h == null:
		return
	botlog.on_think(C.DT * 2.0 if quick else float(sk.think), mode if h.alive else "dead")
	h.bot = true
	h.auto_attack = false
	if not h.alive:
		if _was_alive:
			_on_death(h)
		_was_alive = false
		_dead(h)
		# dead heroes shop too (into the stash; it comes into the bags at the fountain), as players do
		if bool(sk.advanced) and w.time >= 600.0:
			_shop(h)
		return
	_was_alive = true
	var pt := Time.get_ticks_usec() if w.profiling else 0
	_learn(h)
	if w.profiling: pt = w._prof("  bot:learn", pt)
	_shop(h)
	if bool(sk.spells):
		_items(h)
	if w.profiling: pt = w._prof("  bot:shop_items", pt)
	_scan(h)
	# inside Azrael's door: nothing to do but wait (her bot places the exit)
	if w.abilities.kits4.in_door(h):
		SimBot17.tick(self, h)
		return
	if w.vision.sees(1 - h.team, h):
		_seen_by_enemy_at = w.time
	if w.profiling: pt = w._prof("  bot:scan", pt)
	_track_fight(h)
	_track_retreat(h)
	_track_lane(h)
	_track_shot(h)
	if _unstick(h):
		return
	if w.profiling: pt = w._prof("  bot:track", pt)
	if _busy(h):
		# a Town Portal is committed to (run 2026-10-18 h: bots broke nearly every escape teleport to walk off and died
		# on foot). It is broken only for a ready way out that is surer than the channel: a Jump Knife, with an enemy
		# hero on top of a badly hurt bot and over a second of the channel left.
		if not h.channel.is_empty() and String(h.channel.ability) == "tp" and _foes.size() > 0 \
				and _nearest(h, _foes).distance_to(h.pos) < 500.0 and h.hp < h.max_hp * 0.4 \
				and float(h.channel.until) - w.time > 1.0:
			var safe := _safe_point(h)
			var jp := h.pos + (safe - h.pos).normalized() * 950.0
			var jk := _jump_slot(h, jp)
			if jk >= 0:
				_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": jk, "point": jp}, true)
				_cast_deadline = w.time + 0.5
		return
	if w.time < 0.0:
		_pregame(h)
		return
	_choose_mode(h)
	if w.profiling: pt = w._prof("  bot:choose", pt)
	# Azrael's door (hers, and every bot stepping into an allied one when hurt)
	if SimBot17.tick(self, h):
		return
	if w.profiling: pt = w._prof("  bot:door", pt)
	# Blau's turrets (his own piloting and turret drops, and every bot knocking enemy turrets down)
	if SimBot16.tick(self, h):
		return
	if w.profiling: pt = w._prof("  bot:turret", pt)
	# out of an enemy Ser Emelrich's red cone or line before the blow lands
	if bool(sk.spells) and SimBot18.dodge_windups(self, h):
		return
	# the five heroes of run 2026-10-18 f (Burak's axe leap, Steel Stance, Ghorman's taming)
	if SimBot18.tick(self, h):
		return
	# Araki (run 2026-10-19 c): Blur Strike's second dash home after a lane poke
	if SimBot19.tick(self, h):
		return
	if mode != "retreat" and mode != "fight" and _grab_orb(h):
		return
	if _use_site(h):
		return
	if w.profiling: pt = w._prof("  bot:orb_site", pt)
	_run_mode(h)
	if w.profiling: w._prof("  bot:run_" + mode, pt)

## An orb the team can see close by is worth a detour (the mid hero also goes for the river orbs from farther), unless
## an enemy hero stands nearer to it than half our distance.
func _grab_orb(h: SimUnit) -> bool:
	var best: Dictionary = {}
	var bd := INF
	for o in w.orbs.orbs:
		var p: Vector2 = o.pos
		if not w.vision.cell_visible(h.team, p):
			continue
		var reach := 2200.0 if (role == 2 and String(o.spot) == "power") else 1300.0
		var d := h.pos.distance_to(p)
		if d > reach or d >= bd:
			continue
		var contested := false
		for f in _foes:
			if f.pos.distance_to(p) < d * 0.5:
				contested = true
		if not contested:
			bd = d
			best = o
	if best.is_empty():
		return false
	if h.order != O.PICKUP_ORB or h.order_gid != int(best.id):
		_order(h, {"type": O.PICKUP_ORB, "orb": int(best.id)}, true)
	state = "orb"
	return true

## Map sites (SimSites) on the way: a Lily Pond with lilies when hurt or low on mana and no enemy hero near it; a dark
## Lookout Lamp close by when nothing threatens. Warp Gates are used by _go for long walks.
var site_uses := {}                         # report counters (bot games): "lily", "lamp", "gate" -> times
var _site_goal := -1                        # the site it is walking to (-1 none)

func _use_site(h: SimUnit) -> bool:
	if w.sites == null or mode == "fight" or w.time < 0.0:
		_site_goal = -1
		return false
	var chased := not _chasers(h).is_empty()
	var hurt := h.max_hp - h.hp >= 110.0 or (h.max_mana > 0.0 and h.max_mana - h.mana >= 110.0 and role != 1)
	for s in w.sites.sites:
		var p: Vector2 = s.pos
		var d := h.pos.distance_to(p)
		match String(s.kind):
			"pond":
				if not hurt or int(s.lilies) <= 0 or chased:
					continue
				if not w.vision.cell_visible(h.team, p) and d > 1600.0:
					continue
				# going home to heal: a pond with two lilies or more on the way (nearer than the fountain) will do
				var reach := 1500.0
				if mode in ["heal", "retreat"]:
					reach = 4500.0 if int(s.lilies) >= 2 and d < h.pos.distance_to(w.map.fountains[h.team]) else 2600.0
				if d > reach or _enemy_near_spot(p, 1000.0):
					continue
				if d > SimSites.POND_RANGE * 0.5:
					_go_direct(h, p)
				state = "lily"
				if _site_goal != int(s.id):
					_site_goal = int(s.id)
					site_uses["lily"] = int(site_uses.get("lily", 0)) + 1
				return true
			"lamp":
				# supports go out of their way to light lamps (Dota's supports take the Watchers); others on the way
				var lamp_reach := 3500.0 if role >= 4 and mode in ["lane", "farm", "ward", "stack"] and w.time > 60.0 else 1100.0
				if mode in ["retreat", "heal", "fight"] or chased or d > lamp_reach:
					continue
				if w.sites.lamp_lit(s, h.team) or w.time < float(s.out_until) or _enemy_near_spot(h.pos, 1100.0):
					continue
				if h.order != O.USE_SITE or h.order_gid != int(s.id):
					_order(h, {"type": O.USE_SITE, "site": int(s.id)}, true)
					site_uses["lamp"] = int(site_uses.get("lamp", 0)) + 1
				_site_goal = int(s.id)
				state = "lamp"
				return true
	_site_goal = -1
	return false

## Whether an enemy hero its team knows of stands within `r` of a spot.
func _enemy_near_spot(p: Vector2, r: float) -> bool:
	for e in _known:
		if e.pos.distance_to(p) < r:
			return true
	return false

## A Warp Gate that shortens a long walk to `p` a lot (the 4 s channel counted as walking), or {}.
func _gate_for(h: SimUnit, p: Vector2) -> Dictionary:
	if w.sites == null or mode in ["fight", "retreat"] or w.time < 0.0:
		return {}
	var direct := h.pos.distance_to(p)
	if direct < 5000.0 or (h.max_mana > 0.0 and h.mana < SimSites.GATE_MANA + 40.0):
		return {}
	var best: Dictionary = {}
	var bc := direct * 0.7
	for g in w.sites.of_kind("gate"):
		var to := w.sites.get_site(int(g.pair))
		if to.is_empty():
			continue
		var cost := h.pos.distance_to(g.pos) + (to.exit as Vector2).distance_to(p) + SimSites.GATE_CHANNEL * h.move_speed + 300.0
		if cost < bc and not _enemy_near_spot(g.pos, 1200.0):
			bc = cost
			best = g
	return best

func _pregame(h: SimUnit) -> void:
	mode = "lane"
	state = mode
	if role >= 4 and bool(sk.advanced) and _ward_slot(h) >= 0 and w.time > -70.0:
		_run_ward(h)
		return
	if not _foes.is_empty() and _nearest(h, _foes).distance_to(h.pos) < 1300.0:
		_lane(h)
		return
	# before the horn: wait by the lane's tier 1 tower, but fight any hero that comes looking for a kill
	_go(h, _waiting_spot(h))

# ---- Scan: what the bot sees around it -----------------------------------------------------------------------------------

var _allies: Array[SimUnit] = []           # allied heroes within 1600 (not itself)
var _foes: Array[SimUnit] = []             # enemy heroes it sees within 1800
var _known: Array[SimUnit] = []            # enemy heroes its team saw within 1600 in the last 3 s
var _ecreeps: Array[SimUnit] = []          # visible enemy lane creeps within 1600
var _acreeps: Array[SimUnit] = []          # allied lane creeps within 1600
var _etowers: Array[SimUnit] = []          # enemy towers within 1800
var _otowers: Array[SimUnit] = []          # allied towers within 1800
var _threat := 0.0                         # enemy strength near / our strength near
var _tower_on_me := false
var _first_seen := {}                      # enemy hero id -> time it came into sight (reaction delay)

func _scan(h: SimUnit) -> void:
	_allies.clear()
	_foes.clear()
	_ecreeps.clear()
	_acreeps.clear()
	_etowers.clear()
	_otowers.clear()
	_tower_on_me = false
	for u: SimUnit in w.query(h.pos, 1800.0):
		if not u.alive or u == h:
			continue
		if u.is_hero():
			if u.team == h.team:
				if u.pos.distance_to(h.pos) <= 1600.0:
					_allies.append(u)
			elif w.vision.sees(h.team, u):
				_foes.append(u)
		elif u.is_lane_creep() and u.pos.distance_to(h.pos) <= 1600.0:
			if u.team == h.team:
				_acreeps.append(u)
			elif w.vision.sees(h.team, u):
				_ecreeps.append(u)
		elif u.kind == K.TOWER:
			if u.team == h.team:
				_otowers.append(u)
			else:
				_etowers.append(u)
				if u.atk_target == h.id:
					_tower_on_me = true
	var b := brain()
	_known = b.enemies_near(h.pos, 1600.0, 3.0) if b != null else _foes.duplicate()
	for e in _foes:
		if not _first_seen.has(e.id):
			_first_seen[e.id] = w.time
	for k in _first_seen.keys():
		var e := w.get_unit(k)
		if e == null or not (e in _foes):
			_first_seen.erase(k)
	var ours := KITS.power(w, h, _known[0] if not _known.is_empty() else null)
	for a in _allies:
		if a.pos.distance_to(h.pos) < 1200.0:
			ours += KITS.power(w, a, _known[0] if not _known.is_empty() else null)
	var theirs := 0.0
	for e in _known:
		theirs += KITS.power(w, e, h)
	_threat = theirs / maxf(1.0, ours)

func _nearest(h: SimUnit, arr: Array) -> Vector2:
	var best := Vector2.INF
	for u in arr:
		if best == Vector2.INF or (u.pos as Vector2).distance_to(h.pos) < best.distance_to(h.pos):
			best = u.pos
	return best

## Spells allowed now: the reaction delay after a hero comes into sight, and the easy / medium lockouts.
func _spells_ok(e: SimUnit = null) -> bool:
	if not bool(sk.spells):
		return false
	if float(sk.lock_every) > 0.0 and fposmod(w.time, float(sk.lock_every)) < float(sk.lock_for):
		return false
	if w.time < _spell_lock_until:
		return false
	if e != null and w.time - float(_first_seen.get(e.id, w.time)) < float(sk.react):
		return false
	return true

var _spell_lock_until := C.LONG_AGO

func _spent() -> void:
	if float(sk.after_use) > 0.0:
		_spell_lock_until = w.time + float(sk.after_use)

# ---- Choosing a mode ----------------------------------------------------------------------------------------------------

var _fight_target := -1

func _choose_mode(h: SimUnit) -> void:
	var d := {}
	var task := brain().task_for(h.id)
	if not task.is_empty() and w.time < float(_given_up.get(int(task.get("id", -1)), C.LONG_AGO)):
		task = {}                                  # this bot gave up on that play (nothing to do there)
	if not task.is_empty() and coop < 1.0 and String(task.kind) != "retreat" and not _calls_judged.has(int(task.get("id", -1))):
		_calls_judged[int(task.get("id", -1))] = true
		if rng.randf() > coop:
			_give_up(task, 90.0)
			if toxic > 0.4 and rng.randf() < toxic:
				say(["no", "kayo na lang", "farm muna ako", "busy", "di ako sasama", "go without me", "nah"][rng.randi_range(0, 6)],
					"refuse_%d" % h.id, 40.0)
			task = {}
	if not task.is_empty():
		botlog.on_task(w.time, task)
	d["retreat"] = _retreat_desire(h, task)
	d["heal"] = _heal_desire(h)
	var ft := _pick_fight(h)
	_fight_target = ft[0].id if ft[0] != null else -1
	d["fight"] = float(ft[1])
	if w.debug_flags.has("brawl") and not _foes.is_empty():
		# benchmarks (SimDebug.stage_fight): every bot fights the nearest enemy hero it sees
		var near_e: SimUnit = _foes[0]
		for e in _foes:
			if e.pos.distance_to(h.pos) < near_e.pos.distance_to(h.pos):
				near_e = e
		_fight_target = near_e.id
		d["fight"] = 1.0
	if not task.is_empty() and String(task.kind) == "save" and int(task.get("victim", -1)) == h.id:
		# the one being saved: it runs toward the helpers (retreat) until they are close, then turns on the gankers
		if _save_turn(h, task):
			d["task"] = 0.97
	elif not task.is_empty() and String(task.kind) != "retreat":
		d["task"] = {"save": 0.9, "fight": 0.88, "defend": 0.8, "gank": 0.78, "push": 0.62, "group": 0.6}.get(String(task.kind), 0.5)
	if _laning_phase(h):
		d["lane"] = 0.45
	else:
		d["farm"] = 0.4
	if bool(sk.advanced):
		d["stack"] = _stack_desire(h)
		d["pull"] = _pull_desire(h)
		d["ward"] = _ward_desire(h)
	_creep_choice(h, d, task)
	desires = d
	var best := mode if d.has(mode) else "lane"
	var bv := float(d.get(best, 0.0)) + 0.08
	for k in d:
		if float(d[k]) > bv:
			bv = float(d[k])
			best = k
	# commit at least a second to a choice unless something urgent comes up
	if best != mode and w.time - mode_since < 1.0 and bv < 0.85 and d.has(mode) and float(d[mode]) > 0.0:
		best = mode
	if best != mode:
		botlog.on_mode(w.time, mode, best, d)
		_leave_mode(h, mode, best)
		mode = best
		mode_since = w.time
	state = mode

func _leave_mode(h: SimUnit, old: String, new_mode: String) -> void:
	if old == "stack" or old == "pull":
		_stack = {}
	if old == "farm":
		_camp = -1
	if old == "task" and new_mode == "retreat":
		var t := brain().task_for(h.id)
		if not t.is_empty() and String(t.kind) == "gank":
			say("Backing off, too dangerous.", "abort_%d" % int(t.id), 30.0, false, "abort")

func _run_mode(h: SimUnit) -> void:
	match mode:
		"retreat":
			_run_retreat(h)
		"heal":
			_run_heal(h)
		"fight":
			var e := w.get_unit(_fight_target)
			if e != null and e.alive:
				_run_fight(h, e)
			else:
				_lane_or_farm(h)
		"task":
			_run_task(h, brain().task_for(h.id))
		"lane":
			_lane(h)
		"farm":
			_run_farm(h)
		"stack":
			_run_stack(h)
		"pull":
			_run_pull(h)
		"ward":
			_run_ward(h)
		"clear":
			_run_clear(h)

# ---- Creeps on the bot (run 2026-10-18 h) ----------------------------------------------------------------------------------
# A bot with several creeps hitting it used to switch between lane, fight and retreat every second and stand there. Now
# it reads how fast they would kill it: with a spell ready that clears them (and time to cast it) it clears the wave;
# otherwise, low or losing health fast, it backs off and keeps backing off for a few seconds (creeps drop a hero
# that walks out of their reach), then comes back.

## Each hero's spells that hit a creep pack: [ability, how it is aimed: "self" (around the hero, radius key), "point",
## "unit", "toggle", "line"]. A plain list so every kit is known in one place.
const CLEAR_SPELLS := {
	"sludge": [["stench", "toggle"]], "ezee": [["dark_stomp", "self"]],
	"azrin": [["touch_of_ember", "point"], ["spirit_of_fire", "point"]],
	"froster": [["breath_of_cold", "point"], ["ice_pulse", "unit"]],
	"blood_ranger": [["gale_impact", "line"], ["burst_shot", "point"]], "kragg": [["repel", "self"]],
	"tock": [["time_bolt", "line"]], "roydo": [["grip_of_the_ruler", "point"]],
	"blau": [["summon_boulders", "point"], ["bounce_shot", "point"]],
	"azrael": [["soul_tap", "toggle"], ["door_of_the_end", "point"]], "airah": [["gust", "line"]],
	"emelrich": [["sweep", "self"]], "feran": [["joke_box", "point"], ["knife_juggle", "line"]],
	"burak": [["reckless_swing", "self"]], "ghorman": [["roar", "self"]], "araki": [["blur_strike", "line"]],
}
const CLEAR_DAMAGE_KEYS := ["damage", "explode_damage", "blast_damage", "impact_damage", "crash_damage"]

var _creep_back_until := C.LONG_AGO        # backing off from creeps until then
var _clear_list: Array[SimUnit] = []       # the creeps it means to clear (mode "clear")
var creep_clears := 0                      # report counters (tests, bot games)
var soul_ons := 0                          # Azrael's Soul Tap switched on / off by its planner (SimBot17)
var soul_offs := 0
var creep_backoffs := 0

## The enemy creeps (lane and neutral) attacking the hero now, their damage a second on it, and the seconds they need
## to kill it: {list, dps, ttd}.
func _creep_gang(h: SimUnit) -> Dictionary:
	var list: Array[SimUnit] = []
	var dps := 0.0
	var red := 1.0 - 0.06 * h.armor / (1.0 + 0.06 * absf(h.armor))
	for u: SimUnit in w.query(h.pos, 900.0):
		if not u.alive or u.team == h.team or u.atk_target != h.id:
			continue
		if not (u.is_lane_creep() or u.kind == K.NEUTRAL_CREEP):
			continue
		list.append(u)
		# creep attacks deal 50-75% to heroes (Slash, Piercing on the Hero armor type)
		dps += (u.dmg_min + u.dmg_max) * 0.5 / maxf(0.3, u.attack_interval()) * red * (0.5 if u.is_ranged() else 0.75)
	return {"list": list, "dps": dps, "ttd": h.hp / maxf(1.0, dps)}

## The pack damage its ready clearing spells deal now (0 when none is ready or mana is short).
func _clear_damage(h: SimUnit) -> float:
	if not _spells_ok():
		return 0.0
	var total := 0.0
	for sp in CLEAR_SPELLS.get(kit, []):
		var aid := String(sp[0])
		if h.ability_level_of(aid) <= 0:
			continue
		if String(sp[1]) == "toggle":
			total += 40.0 * float(h.ability_level_of(aid))       # a burn around it: helps, never clears alone
			continue
		if w.abilities.cast_error(h, aid, -1, null, h.pos) in ["Ability on cooldown", "Not enough mana", "Silenced",
				"Stunned", "Muted", "Ability not learned", "Ability is passive", "No spirits of fire"]:
			continue
		if h.mana < w.abilities.ability_mana(h, aid) + h.max_mana * 0.15:
			continue
		var best := 0.0
		for key in CLEAR_DAMAGE_KEYS:
			var v := w.abilities.val(h, aid, key)
			best = maxf(best, v)
		total += best
	return total

## Sets the "clear" desire or raises "retreat" from the creeps on the bot.
func _creep_choice(h: SimUnit, d: Dictionary, task: Dictionary) -> void:
	if mode == "retreat" and w.time < _creep_back_until:
		d["retreat"] = maxf(float(d.get("retreat", 0.0)), 0.86)
	var cg := _creep_gang(h)
	var list: Array[SimUnit] = cg.list
	if list.size() < 2:
		return
	var ttd := float(cg.ttd)
	var hpf := h.hp / h.max_hp
	var team_fight := not task.is_empty() and String(task.kind) in ["fight", "save", "defend"]
	var foe_close := not _foes.is_empty() and _nearest(h, _foes).distance_to(h.pos) < 900.0
	# can it clear them? its spells against their average health, with time to cast
	var hp_sum := 0.0
	for c in list:
		hp_sum += c.hp
	var avg := hp_sum / float(list.size())
	var dmg := _clear_damage(h)
	if dmg >= avg * 0.75 and ttd > 3.5 and (list.size() >= 3 or dmg >= avg) and not (foe_close and hpf < 0.5):
		_clear_list = list
		d["clear"] = 0.9 if not team_fight else 0.7
		return
	if team_fight and hpf > 0.35:
		return                                 # the fight matters more than the creeps on it
	# losing fast or already low: back off for a while (and keep backing off)
	if ttd < 7.0 or hpf < _retreat_bar() + 0.15 or (list.size() >= 4 and ttd < 14.0):
		if mode != "retreat" or w.time >= _creep_back_until:
			creep_backoffs += 1
		_creep_back_until = w.time + 2.5
		d["retreat"] = maxf(float(d.get("retreat", 0.0)), 0.9 if ttd < 7.0 else 0.8)

## Clear the creeps on it: its clearing spells (CLEAR_SPELLS), aimed at the pack, then plain attacks on the weakest.
func _run_clear(h: SimUnit) -> void:
	if _busy(h):
		return
	var live: Array[SimUnit] = []
	for c in _clear_list:
		if c != null and c.alive:
			live.append(c)
	if live.is_empty():
		_lane_or_farm(h)
		return
	var mid := Vector2.ZERO
	for c in live:
		mid += c.pos
	mid /= float(live.size())
	if _spells_ok():
		for sp in CLEAR_SPELLS.get(kit, []):
			var aid := String(sp[0])
			if h.ability_level_of(aid) <= 0:
				continue
			var how := String(sp[1])
			if how == "toggle":
				if not bool(h.toggles.get(aid, false)) and h.mana > w.abilities.ability_mana(h, aid) + h.max_mana * 0.2:
					_order(h, {"type": O.CAST_NO_TARGET, "ability": aid}, true)
					return
				continue
			if h.mana < w.abilities.ability_mana(h, aid) + h.max_mana * 0.15:
				continue
			match how:
				"self":
					var r := maxf(w.abilities.val(h, aid, "radius"), 250.0)
					var inside := live.filter(func(c): return c.pos.distance_to(h.pos) < r).size()
					if inside >= mini(2, live.size()) and w.abilities.cast_error(h, aid, -1, null, h.pos) == "":
						_order(h, {"type": O.CAST_NO_TARGET, "ability": aid}, true)
						_cast_deadline = w.time + 0.8
						creep_clears += 1
						_spent()
						return
				"point", "line":
					if w.abilities.cast_error(h, aid, -1, null, mid) == "":
						_order(h, {"type": O.CAST_POINT, "ability": aid, "point": mid}, true)
						_cast_deadline = w.time + (2.6 if aid == "burst_shot" else 0.8)
						creep_clears += 1
						_spent()
						return
				"unit":
					var near: SimUnit = live[0]
					for c in live:
						if c.pos.distance_to(mid) < near.pos.distance_to(mid):
							near = c
					if w.abilities.cast_error(h, aid, -1, near, near.pos) == "":
						_order(h, {"type": O.CAST_UNIT, "ability": aid, "target": near.id}, true)
						_cast_deadline = w.time + 0.8
						creep_clears += 1
						_spent()
						return
	var weakest: SimUnit = live[0]
	for c in live:
		if c.hp < weakest.hp:
			weakest = c
	_order(h, {"type": O.ATTACK_UNIT, "target": weakest.id})

## Laning: until 10:00 while the lane's tier 1 tower stands (cores keep farming their lane after that).
func _laning_phase(h: SimUnit) -> bool:
	if w.time >= 600.0:
		return false
	var t1 := _own_tower(h, 1)
	return t1 != null

# ---- Retreat and heal ---------------------------------------------------------------------------------------------------

## How bold the bot plays now: its personality (aggression), more while its team is ahead in net worth (the owner's
## rule): from 10% ahead, +0.1 for every further 10%, at most +0.4.
func _boldness() -> float:
	var b := brain()
	var lead := b.networth_lead() if b != null else 0.0
	return aggression + clampf(lead - 0.1, 0.0, 0.4)

func _retreat_bar() -> float:
	var base := 0.28 if role <= 3 else 0.33
	base += (1.0 - _boldness()) * 0.2
	return BotMemory.retreat_hp(kit, base, _team())

var _threat_back_until := C.LONG_AGO      # a retreat from a stronger enemy holds until then (see _retreat_desire)

func _retreat_desire(h: SimUnit, task: Dictionary) -> float:
	if rage:
		return _retreat_core(h, task) * 0.55
	return _retreat_core(h, task)

func _retreat_core(h: SimUnit, task: Dictionary) -> float:
	if not task.is_empty() and String(task.kind) == "retreat" and h.pos.distance_to(task.pos) < 2800.0:
		return 0.95
	var hpf := h.hp / h.max_hp
	var bar := _retreat_bar()
	if mode == "retreat":
		# once running, keep going until properly healthier (less when healing and nobody is near)
		bar += 0.08 if (_has_mod(h, "salve") or _has_mod(h, "tango")) and _foes.is_empty() else 0.22
	var creeps_tank := false
	if _tower_on_me:
		for tw in _etowers:
			for c in _acreeps:
				if c.pos.distance_to(tw.pos) < tw.attack_range + 100.0:
					creeps_tank = true
	# a pushing group takes the tower's shots in turn (Dota's tower diving late in the game): a hero in a push with two
	# allies beside it and health to spare does not run from tower aggro alone. Every hero used to back off the moment
	# the tower turned on it, so groups without a creep wave never took a building and games never ended.
	var diving := not task.is_empty() and String(task.kind) == "push" and w.time > 1200.0 and hpf > 0.45 \
			and _allies.filter(func(a): return a.pos.distance_to(h.pos) < 900.0).size() >= 2
	if _tower_on_me and (not creeps_tank or hpf < 0.6) and not diving:
		return 0.92
	if hpf < bar and (not _known.is_empty() or _tower_on_me):
		return 0.95
	if hpf < bar * 0.7:
		return 0.9
	var team_fight := not task.is_empty() and (String(task.kind) == "fight" or String(task.kind) == "save" 		and int(task.get("victim", -1)) != h.id)
	if _threat > 1.7 and not team_fight and not _foes.is_empty() and _nearest(h, _foes).distance_to(h.pos) < 1000.0:
		_threat_back_until = w.time + 2.5
		return clampf(0.6 + (_threat - 1.7) * 0.3, 0.6, 0.9)
	# backing off from a stronger enemy lasts a moment: it used to flip back to the lane the instant it stepped out of
	# 1000 range and walk straight back in, every second or two (seen in the Bot Log)
	if mode == "retreat" and w.time < _threat_back_until and _threat > 1.3 and not team_fight and not _known.is_empty() 			and _nearest(h, _known).distance_to(h.pos) < 1400.0:
		return 0.6
	if BotMemory.danger(h.team, h.pos) > 0.6 and hpf < bar + 0.2 and not _known.is_empty() and not team_fight:
		return 0.8
	return 0.0

## A Healing Paste, Vegan Picker or Mana Potion in the stash or on the courier, and a courier alive to bring it.
func _regen_coming(h: SimUnit) -> bool:
	var c := w.get_unit(h.courier_id)
	if c == null or not c.alive:
		return false
	for arr in [h.stash, h.courier_items]:
		for it in arr:
			if it != null and String(it.id) in ["salve", "tango", "clarity"]:
				return true
	return false

func _heal_desire(h: SimUnit) -> float:
	var hpf := h.hp / h.max_hp
	var mpf := h.mana / maxf(1.0, h.max_mana)
	var home := h.pos.distance_to(w.map.fountains[h.team]) < C.FOUNTAIN_AURA_RADIUS
	if home and (hpf < 0.9 or mpf < 0.7) and mode in ["heal", "retreat"]:
		return 0.75
	# healing on its way by courier: wait for it in lane rather than walk home (unless badly hurt)
	var coming := _regen_coming(h)
	# a late push with two allies beside keeps its heroes down to a quarter of their health (pushes lost their momentum
	# while half-healthy heroes went home)
	var low := 0.4
	if w.time > 1500.0 and String(brain().task_for(h.id).get("kind", "")) == "push" 			and _allies.filter(func(a): return a.pos.distance_to(h.pos) < 1200.0).size() >= 2:
		low = 0.25
	if hpf < low and not _has_item(h, "salve") and not _has_item(h, "tango") and not _has_mod(h, "salve") 			and not (coming and hpf > 0.22):
		return 0.62
	if mpf < 0.12 and role != 1 and h.max_mana > 300.0 and not _has_item(h, "clarity") and not coming:
		return 0.5
	return 0.0

## Where to run: the fountain when badly hurt, else the nearest own tower away from the enemies.
func _safe_point(h: SimUnit) -> Vector2:
	var home: Vector2 = w.map.fountains[h.team]
	var regen := _has_item(h, "salve") or _has_item(h, "tango") or _has_item(h, "magic_wand") and h.stick_charges >= 5
	if h.hp < h.max_hp * (0.2 if regen and w.time < 900.0 else 0.35):
		return home
	var threat := _nearest(h, _known)
	var best := home
	var bs := INF
	for u in w.units:
		if not u.alive or u.team != h.team or u.kind != K.TOWER:
			continue
		var d := u.pos.distance_to(h.pos)
		if threat != Vector2.INF and u.pos.distance_to(threat) < h.pos.distance_to(threat):
			continue                       # running toward the enemy
		if d < bs:
			bs = d
			best = u.pos + (home - u.pos).normalized() * 250.0
	return best

## Enemy heroes chasing it: where they are or were last seen (no peeking into the fog), within 1500 and 4 s.
func _chasers(h: SimUnit) -> PackedVector2Array:
	var out := PackedVector2Array()
	var b := brain()
	for e in _known:
		var ls := b.last_seen(e)
		if float(ls[1]) < 4.0 and (ls[0] as Vector2).distance_to(h.pos) < 1500.0:
			out.append(ls[0])
	return out

var _seen_by_enemy_at := C.LONG_AGO          # when the enemy team last had sight of it
var _chased_at := C.LONG_AGO                 # when it last ran from enemy heroes
var _juke := Vector2.INF
var _juke_until := C.LONG_AGO
var jukes := 0                               # report counters (bot games, tests): teleports home after a juke
var counter_saves := 0                      # counter-ganks this bot joined as a helper and fought in
var _save_counted := -1

## The helper of a counter-gank called for this bot (the one to run to), or null: none called, or the way to it
## leads through the gankers.
func _save_helper(h: SimUnit) -> SimUnit:
	var task := brain().task_for(h.id)
	if task.is_empty() or String(task.kind) != "save" or int(task.get("victim", -1)) != h.id:
		return null
	var foe := _nearest(h, _foes)
	var best: SimUnit = null
	for hid in task.members:
		var a := w.get_unit(int(hid))
		if a == null or a == h or not a.alive:
			continue
		if foe != Vector2.INF and a.pos.distance_to(h.pos) > 500.0 				and absf((a.pos - h.pos).angle_to(foe - h.pos)) < deg_to_rad(60.0):
			continue                       # the gankers stand between
		if best == null or a.pos.distance_to(h.pos) < best.pos.distance_to(h.pos):
			best = a
	return best

## Whether the victim of a counter-gank turns and fights now: a helper is beside it (or on the gankers), and it has
## health left to fight with.
func _save_turn(h: SimUnit, task: Dictionary) -> bool:
	if h.hp < h.max_hp * 0.18:
		return false
	var t := w.get_unit(int(task.target))
	for hid in task.members:
		var a := w.get_unit(int(hid))
		if a == null or a == h or not a.alive:
			continue
		if a.pos.distance_to(h.pos) < 650.0 or (t != null and a.edge_distance(t) < a.attack_range + 250.0):
			return true
	return false

## Whether a Town Portal started now would land: no enemy hero the team knows of (seen in the last 3 s) could walk
## into reach of it during the 3 s channel (run 2026-10-18 h: bots teleported with a hero 200-700 away and died
## channelling). Their walk is counted short (they need to turn and path) but their reach in full.
func _tp_safe(h: SimUnit) -> bool:
	for list in [_known, _foes]:
		for f: SimUnit in list:
			if f.alive and f.pos.distance_to(h.pos) < maxf(1200.0, f.move_speed * 2.2 + f.attack_range + 150.0):
				return false
	return true

## Juked: it ran from enemy heroes in the last 12 s, the enemy has not seen it for 2 s and none of them is in sight
## near: teleport home from the fog (hurt or short of mana; healthy, it just goes back to work).
func _juke_tp(h: SimUnit) -> bool:
	if w.time - _chased_at > 12.0 or w.time - _seen_by_enemy_at < 2.0 or not bool(sk.advanced):
		return false
	# early on a scratch is not worth the trip: before 8:00 only when badly hurt
	var hurt := 0.35 if w.time < 480.0 else 0.65
	if h.hp > h.max_hp * hurt and (h.mana > h.max_mana * 0.3 or w.time < 480.0):
		return false
	if not _tp_safe(h):
		return false
	var home: Vector2 = w.map.fountains[h.team]
	if h.pos.distance_to(home) < 3500.0 or w.abilities.cast_error(h, "tp", -1, null, home) != "":
		return false
	_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": home}, true)
	_cast_deadline = w.time + 3.5
	_chased_at = C.LONG_AGO
	jukes += 1
	say("Lost them in the trees, going home.", "juke_%d" % h.id, 45.0, false, "juke")
	return true

func _run_retreat(h: SimUnit) -> void:
	var safe := _safe_point(h)
	var near_foe := _nearest(h, _foes)
	var fd := near_foe.distance_to(h.pos) if near_foe != Vector2.INF else INF
	var chasers := _chasers(h)
	if not chasers.is_empty() and fd < 1300.0:
		_chased_at = w.time
	if _juke_tp(h):
		return
	# a counter-gank on its way: run toward the helpers (the gankers follow into them) instead of to a tower
	var helper := _save_helper(h)
	if helper != null:
		safe = helper.pos
	# out of reach: heal up with what we carry instead of walking home
	if fd > 900.0 and not _tower_on_me and bool(sk.spells):
		if h.hp < h.max_hp * 0.6 and not _has_mod(h, "salve") and _use_item(h, "salve"):
			return
		if h.hp < h.max_hp * 0.7 and not _has_mod(h, "tango") and not _has_mod(h, "salve") and w.time >= _next_tango and _tango(h):
			_next_tango = w.time + 18.0
			_cast_deadline = w.time + 4.0
			return
	if bool(h.toggles.get("stench", false)) and fd > 300.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "stench"}, true)
	if bool(sk.spells):
		if fd < 900.0:
			var slip := _ready_slot(h, "slip_boots")
			if slip >= 0:
				w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": slip})
		# Spell Shield against a disabler on its heels (a stun now is the end)
		if fd < 600.0 and _foes.any(func(f): return KITS.disable_power(String(f.def.id)) >= 0.6 and f.pos.distance_to(h.pos) < 600.0):
			var bk := _ready_slot(h, "spell_shield")
			if bk >= 0:
				w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": bk})
		if fd < 700.0:
			var jk := _jump_slot(h, h.pos + (safe - h.pos).normalized() * 950.0)
			if jk >= 0:
				_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": jk, "point": h.pos + (safe - h.pos).normalized() * 950.0}, true)
				_cast_deadline = w.time + 0.5
				return
			var ps := _ready_slot(h, "push_staff", h, h.pos)
			if ps >= 0 and h.moving and absf(angle_difference(h.facing, (safe - h.pos).angle())) < 0.5:
				_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": ps, "target": h.id}, true)
				_cast_deadline = w.time + 0.3
				return
		if _escape_spells(h, fd):
			return
	# a long way home, badly hurt, nothing to heal with and nobody close: teleport to the fountain
	if fd > 1200.0 and _tp_safe(h) and h.pos.distance_to(w.map.fountains[h.team]) > 6000.0 and h.hp < h.max_hp * 0.3 and w.time > 240.0 \
			and not _has_item(h, "salve") and w.abilities.cast_error(h, "tp", -1, null, w.map.fountains[h.team]) == "":
		_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": w.map.fountains[h.team]}, true)
		_cast_deadline = w.time + 3.5
		say("Going home to heal.", "tp_home_%d" % h.id, 60.0, false, "heal")
		return
	# chased: through the trees and out of their sight rather than down the open road
	if not chasers.is_empty() and helper == null and bool(sk.advanced) and fd > 200.0:
		if w.time >= _juke_until or _juke == Vector2.INF or h.pos.distance_to(_juke) < 120.0:
			_juke = SimBotTactics.juke_point(w, h, chasers, safe)
			_juke_until = w.time + 0.6
		_go(h, _juke)
		return
	_go(h, safe)

## The kit's ways out: Blubber or Stench off for Sludge, Dark Stomp to throw chasers back for Ezee, Gale Impact into
## the chaser for Blood Ranger.
func _escape_spells(h: SimUnit, fd: float) -> bool:
	if not _spells_ok():
		return false
	if SimBot16.handles(kit):
		return SimBot16.escape(self, h, fd)
	if SimBot17.handles(kit):
		return SimBot17.escape(self, h, fd)
	if SimBot18.handles(kit):
		return SimBot18.escape(self, h, fd)
	if SimBot19.handles(kit):
		return SimBot19.escape(self, h, fd)
	var ab := w.abilities
	match kit:
		"tock":
			# a chaser close: Slow Field on it; badly hurt: Rewind (back to safety and the health he had)
			if h.hp < h.max_hp * 0.35 and fd < 700.0 and ab.cast_error(h, "rewind", -1, null, h.pos) == "":
				_order(h, {"type": O.CAST_NO_TARGET, "ability": "rewind"}, true)
				_spent()
				return true
			var tc: SimUnit = null
			for f in _foes:
				if tc == null or f.pos.distance_to(h.pos) < tc.pos.distance_to(h.pos):
					tc = f
			if tc != null and fd < 600.0 and ab.cast_error(h, "slow_field", -1, null, tc.pos) == "":
				_order(h, {"type": O.CAST_POINT, "ability": "slow_field", "point": tc.pos}, true)
				_cast_deadline = w.time + 0.6
				_spent()
				return true
		"kragg":
			if fd < 330.0 and ab.cast_error(h, "repel", -1, null, h.pos) == "":
				_order(h, {"type": O.CAST_NO_TARGET, "ability": "repel"}, true)
				_cast_deadline = w.time + 0.6
				_spent()
				return true
		"sludge":
			if fd < 500.0 and ab.cast_error(h, "blubber", -1, null, h.pos) == "":
				_order(h, {"type": O.CAST_NO_TARGET, "ability": "blubber"}, true)
				_spent()
		"ezee":
			if fd < 300.0 and ab.cast_error(h, "dark_stomp", -1, null, h.pos) == "":
				_order(h, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"}, true)
				_cast_deadline = w.time + 0.8
				_spent()
				return true
		"azrin":
			# the javelin through the nearest chaser drags it away; the spirits slow it
			var c: SimUnit = null
			for f in _foes:
				if c == null or f.pos.distance_to(h.pos) < c.pos.distance_to(h.pos):
					c = f
			if c != null and fd < 600.0:
				var away := h.pos + (c.pos - h.pos).normalized() * 1000.0
				if ab.cast_error(h, "fiery_javelin", -1, null, away) == "":
					_order(h, {"type": O.CAST_POINT, "ability": "fiery_javelin", "point": away}, true)
					_cast_deadline = w.time + 0.6
					_spent()
					return true
				if ab.spirits(h) > 0 and ab.cast_error(h, "spirit_of_fire", -1, null, c.pos) == "":
					_order(h, {"type": O.CAST_POINT, "ability": "spirit_of_fire", "point": c.pos}, true)
					_cast_deadline = w.time + 0.5
					_spent()
					return true
		"froster":
			# the cold cone slows the nearest chaser
			var fc: SimUnit = null
			for f in _foes:
				if fc == null or f.pos.distance_to(h.pos) < fc.pos.distance_to(h.pos):
					fc = f
			if fc != null and fd < 700.0 and ab.cast_error(h, "breath_of_cold", -1, null, fc.pos) == "":
				_order(h, {"type": O.CAST_POINT, "ability": "breath_of_cold", "point": fc.pos}, true)
				_cast_deadline = w.time + 0.6
				_spent()
				return true
		"caziel":
			# into the shadows: faster and hard to hit
			if fd < 900.0 and ab.cast_error(h, "master_of_shadows", -1, null, h.pos) == "":
				_order(h, {"type": O.CAST_NO_TARGET, "ability": "master_of_shadows"}, true)
				_spent()
		"blood_ranger":
			var e: SimUnit = null
			for f in _foes:
				if e == null or f.pos.distance_to(h.pos) < e.pos.distance_to(h.pos):
					e = f
			if e != null and fd < 700.0 and ab.cast_error(h, "gale_impact", -1, null, e.pos) == "":
				_order(h, {"type": O.CAST_POINT, "ability": "gale_impact", "point": h.pos + (e.pos - h.pos).normalized() * 1200.0}, true)
				_cast_deadline = w.time + 0.6
				_spent()
				return true
	return false

func _run_heal(h: SimUnit) -> void:
	var home: Vector2 = w.map.fountains[h.team]
	if h.pos.distance_to(home) > 5500.0 and _known.is_empty() and _tp_safe(h) and w.abilities.cast_error(h, "tp", -1, null, home) == "":
		_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": home}, true)
		_cast_deadline = w.time + 3.5
		return
	_go(h, home + (Vector2.ZERO - home).normalized() * 300.0)

# ---- Fights ----------------------------------------------------------------------------------------------------------------

## The fight's features for the fight model (BotMemory): [1, strength ratio (log), target health, own health, numbers,
## enemy tower, own tower, level difference, own ultimate ready]. Allies near the target count, and enemies the team
## saw near it in the last 3 s (fog guesses, no cheating).
func fight_features(h: SimUnit, e: SimUnit) -> Array:
	var b := brain()
	var ours := 0.0
	var n_ours := 0
	var allies := b.allies_near(e.pos, 1300.0)
	if not (h in allies):
		allies.append(h)
	for a in allies:
		ours += KITS.power(w, a, e)
		n_ours += 1
	var theirs := 0.0
	var n_theirs := 0
	for x in b.enemies_near(e.pos, 1300.0, 3.0):
		theirs += KITS.power(w, x, h)
		n_theirs += 1
	if n_theirs == 0:
		theirs = KITS.power(w, e, h)
		n_theirs = 1
	var et := 0.0
	var ot := 0.0
	for u: SimUnit in w.query(e.pos, 1100.0):
		if u.alive and u.kind == K.TOWER and e.pos.distance_to(u.pos) <= u.attack_range + u.hull + 100.0:
			if u.team == h.team:
				ot = 1.0
			else:
				et = 1.0
	return [1.0, clampf(log(maxf(1.0, ours) / maxf(1.0, theirs)), -2.0, 2.0), e.hp / e.max_hp, h.hp / h.max_hp,
		clampf(float(n_ours - n_theirs) / 4.0, -1.0, 1.0), et, ot, clampf(float(h.level - e.level) / 5.0, -1.0, 1.0),
		1.0 if KITS.ult_ready(w, h) else 0.0]

## The enemy hero worth fighting now and how much (0 when no fight is worth it).
func _pick_fight(h: SimUnit) -> Array:
	var best: SimUnit = null
	var best_s := -INF
	var best_p := 0.0
	var thresh := 0.58 - (_boldness() - 1.0) * 0.25
	if _laning_phase(h):
		thresh += 0.06                     # in lane, commit only to clear chances (trading is handled by _lane)
		var foe_kit := lane_foe
		if foe_kit != "":
			thresh -= (BotMemory.matchup(kit, foe_kit, h.team) - 1.0) * 0.2
	var laning := _laning_phase(h)
	var path := w.map.lane_path(lane, h.team) if laning else PackedVector2Array()
	for e in _foes:
		if not e.alive or e.is_invulnerable():
			continue
		var d := h.pos.distance_to(e.pos)
		if d > (1500.0 if mode == "fight" else 1250.0):
			continue
		# in the laning phase: not off into the jungle after it, not under its tower unless it is nearly dead
		if laning and e.hp > e.max_hp * 0.2:
			if SimMap._polyline_distance(e.pos, path) > 900.0:
				continue
			var near_tower := false
			for tw in _etowers:
				if e.pos.distance_to(tw.pos) < tw.attack_range + tw.hull + 900.0:
					near_tower = true
			if near_tower:
				continue
		if mode == "fight" and e.id == _fight_target and not _fight.is_empty() and h.edge_distance(e) > h.attack_range + 150.0 \
				and (w.time - float(_fight.t0) > 7.0 and e.hp / e.max_hp > float(_fight.e0) - 0.1 \
				or laning and w.time - float(_fight.t0) > 3.0 and e.hp > e.max_hp * 0.25):
			continue                       # it got away (in lane: out of reach after 3 s): let it go
		var x := fight_features(h, e)
		var p := BotMemory.fight_p(x, h.team)
		var s := p + (0.15 if e.hp < e.max_hp * 0.25 else 0.0) - d / 8000.0 + (0.05 if e.id == _fight_target else 0.0)
		if s > best_s:
			best_s = s
			best = e
			best_p = p
	if best == null or best_p < thresh:
		return [null, 0.0]
	return [best, clampf(0.55 + (best_p - thresh) * 1.2, 0.55, 0.9)]

var _fight := {}                           # the fight being scored: {x, target, t0, my0, e0}

func _run_fight(h: SimUnit, e: SimUnit) -> void:
	if _fight.is_empty() or int(_fight.target) != e.id:
		_fight = {"x": fight_features(h, e), "target": e.id, "t0": w.time, "my0": h.hp / h.max_hp, "e0": e.hp / e.max_hp}
		if e.hp < e.max_hp * 0.4:
			say("Going for %s." % SimTeamAI.hero_label(e), "go_%d" % e.id, 20.0, false, "go", {"hero": SimTeamAI.hero_label(e)})
	if not w.vision.sees(h.team, e):
		_go(h, e.pos)
		return
	if _spells_ok(e):
		_spells_on(h, e)
		if _busy(h):
			return
	# a ranged hero keeps out of a melee hero's reach between its attacks
	if h.is_ranged() and not e.is_ranged() and h.edge_distance(e) < 220.0 and w.time < h.next_attack_at - 0.2:
		_go(h, h.pos + (h.pos - e.pos).normalized() * 250.0)
		return
	_order(h, {"type": O.ATTACK_UNIT, "target": e.id})

## Score a fight once it resolves: the target died (win), the bot died or fled (loss), or the trade after 12 s.
func _track_fight(h: SimUnit) -> void:
	if _fight.is_empty():
		return
	var e := w.get_unit(int(_fight.target))
	var y := -1.0
	if e == null or not e.alive:
		y = 1.0
	elif mode == "retreat":
		y = 0.15
	elif w.time - float(_fight.t0) > 12.0 or mode != "fight" and w.time - float(_fight.t0) > 4.0:
		var lost_mine := float(_fight.my0) - h.hp / h.max_hp
		var lost_theirs := float(_fight.e0) - e.hp / e.max_hp
		y = clampf(0.5 + (lost_theirs - lost_mine), 0.1, 0.9)
	if y >= 0.0:
		BotMemory.learn_fight(_fight.x, y, h.team)
		_fight = {}

# ---- Death, buyback, learning hooks ----------------------------------------------------------------------------------

func _on_death(h: SimUnit) -> void:
	BotMemory.note_death(h.team, h.pos)
	# what killed it (its last 20 s of damage by type), older deaths fading; a death with no ally near counts as
	# caught alone (calls for a way out)
	death_dmg = death_dmg * 0.6 + SimBotItems.death_damage(h)
	if _allies.filter(func(a): return a.alive and a.pos.distance_to(h.pos) < 1300.0).is_empty():
		alone_deaths += 1
	_counter_next = minf(_counter_next, w.time + 1.0)
	if not _fight.is_empty():
		BotMemory.learn_fight(_fight.x, 0.0, h.team)
		_fight = {}
	if not _retreat.is_empty():
		BotMemory.note_retreat(kit, _retreat_bar(), true, 0.0, h.team)
		_retreat = {}
	if w.time < 600.0:
		lane_deaths += 1
	_stack = {}
	_camp = -1

func _dead(h: SimUnit) -> void:
	# buy back late in the game when the base is under attack and the wait is long
	if w.time < 1500.0 or h.respawn_at - w.time < 25.0 or w.time < h.buyback_ready:
		return
	if h.gold() < w.buyback_cost(h):
		return
	var threatened := false
	for b in w.units:
		if b.alive and b.team == h.team and b.is_building() and (b.kind == K.ANCIENT or b.kind == K.BARRACKS \
				or b.kind == K.TOWER and b.lane_tier >= 3):
			for u: SimUnit in w.query(b.pos, 1200.0):
				if u.alive and u.team != h.team and u.team != C.NEUTRAL and (u.is_hero() or u.is_lane_creep()):
					threatened = true
	if threatened and w.buyback(h) == "":
		say("Buying back to defend.", "bb_%d" % h.id, 60.0, true, "bb")

var _retreat := {}                         # {t0, hp0}: a retreat in progress (learning the retreat bar)

func _track_retreat(h: SimUnit) -> void:
	if mode == "retreat" and _retreat.is_empty():
		_retreat = {"t0": w.time, "hp0": h.hp / h.max_hp}
	elif mode != "retreat" and not _retreat.is_empty():
		BotMemory.note_retreat(kit, _retreat_bar(), false, float(_retreat.hp0), h.team)
		_retreat = {}

func _track_lane(h: SimUnit) -> void:
	if lane_foe == "" and w.time > 150.0 and w.time < 400.0 and not _foes.is_empty():
		var e: SimUnit = _foes[0]
		if SimMap._polyline_distance(e.pos, w.map.lane_path(lane, h.team)) < 900.0:
			lane_foe = String(e.def.id)

var _still_since := C.LONG_AGO              # when the hero last moved more than 60 units
var _still_pos := Vector2.INF
var _unstick_until := C.LONG_AGO             # walking out of a stuck spot until then

## A bot whose hero has an order to walk or attack something out of reach, yet has not moved 60 units in 6 s, is
## stuck (an unreachable spot, a target across a cliff): it drops the camp, the farm lane and its team play, and walks
## to a safe point for a few seconds. Late-game bots used to stand like this for minutes.
func _unstick(h: SimUnit) -> bool:
	if _still_pos == Vector2.INF or h.pos.distance_to(_still_pos) > 60.0:
		_still_pos = h.pos
		_still_since = w.time
	if w.time < _unstick_until:
		return true
	var reaching := false
	if h.order == O.MOVE and h.pos.distance_to(h.order_point) > 150.0:
		reaching = true
	elif h.order == O.ATTACK_UNIT:
		var t := w.get_unit(h.order_target)
		reaching = t != null and t.alive and h.edge_distance(t) > h.attack_range + 100.0
	if h.moving or not h.is_stunned() and h.blocked_time <= 0.0 and not h.path.is_empty():
		reaching = false                   # it is walking (or has a way): not stuck
	if not reaching or w.time - _still_since < 6.0 or h.atk_phase != SimUnit.AtkPhase.NONE or not h.channel.is_empty():
		return false
	_camp = -1
	_farm_lane = ""
	var task := brain().task_for(h.id)
	if not task.is_empty():
		_give_up(task, 20.0)
	_still_since = w.time
	_unstick_until = w.time + 2.5
	unstuck_count += 1
	var away := _safe_point(h)
	_order(h, {"type": O.MOVE, "point": h.pos + (away - h.pos).limit_length(700.0)}, true)
	return true

var unstuck_count := 0                      # report counter (bot games)

var _shot := {}                            # a skill shot in flight: {ability, dist, t, target}

func _track_shot(h: SimUnit) -> void:
	if _shot.is_empty():
		return
	var hit: Array = w.abilities.hook_hits.get(h.id, [C.LONG_AGO, -1])
	if float(hit[0]) >= float(_shot.t) and int(hit[1]) == int(_shot.target):
		BotMemory.note_shot(String(_shot.ability), float(_shot.dist), true, h.team)
		_shot = {}
	elif w.time - float(_shot.t) > 2.0:
		BotMemory.note_shot(String(_shot.ability), float(_shot.dist), false, h.team)
		_shot = {}

# ---- Team plays -------------------------------------------------------------------------------------------------------

var _given_up := {}                        # team play id -> game time until which this bot ignores it

## Leave a team play that has nothing left for this bot to do (it farms or lanes instead); the team's brain may call
## a new one.
func _give_up(task: Dictionary, secs := 30.0) -> void:
	_given_up[int(task.get("id", -1))] = w.time + secs
	if _given_up.size() > 24:
		_given_up.erase(_given_up.keys()[0])

func _run_task(h: SimUnit, task: Dictionary) -> void:
	if task.is_empty():
		_lane(h)
		return
	var t := w.get_unit(int(task.target))
	var where: Vector2 = task.pos
	if t != null and (t.team == h.team or w.vision.sees(h.team, t)):
		where = t.pos
	elif t != null and t.is_hero():
		where = brain().last_seen(t)[0]
	# far away: teleport to the allied building nearest the play
	var et := brain().eta(h, where)
	if bool(et.tp) and h.pos.distance_to(where) > 4000.0 and _known.is_empty():
		var b := w.get_unit(int(et.get("building", -1)))
		if b != null:
			_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": where}, true)
			_cast_deadline = w.time + 3.5
			return
	match String(task.kind):
		"gank":
			var gather := not bool(task.get("strike", true))
			if gather and t != null and t.alive and h.edge_distance(t) > h.attack_range + 150.0:
				# gathering out of its sight: wait at the rally point for the others
				var rally: Vector2 = task.rally
				if h.pos.distance_to(rally) > 120.0:
					_go(h, rally)
				else:
					_order(h, {"type": O.HOLD})
			elif t != null and t.alive and w.vision.sees(h.team, t) and h.pos.distance_to(t.pos) < 1300.0:
				_run_fight(h, t)
			elif t == null or not t.alive or h.pos.distance_to(where) < 350.0:
				# reached where it was last seen and it is gone: no point standing there
				_give_up(task)
				_lane_or_farm(h)
			else:
				_go(h, where)
		"defend":
			_run_defend(h, t, where)
		"push":
			if not _run_push(h, t, String(task.lane)):
				_give_up(task)
		"save":
			# a counter-gank: to the ally in trouble, then on the ganker hurting it (or whichever is in reach)
			var v := w.get_unit(int(task.get("victim", -1)))
			var sf: SimUnit = t if t != null and t.alive and w.vision.sees(h.team, t) else null
			if v != null and v != h and h.pos.distance_to(v.pos) > 1400.0 and (sf == null or h.pos.distance_to(sf.pos) > 1300.0):
				_go(h, v.pos)
			elif sf != null:
				if h.id != int(task.get("victim", -1)) and _save_counted != int(task.id):
					_save_counted = int(task.id)
					counter_saves += 1
				_run_fight(h, sf)
			elif not _foes.is_empty():
				_run_fight(h, _foes[0])
			else:
				_go(h, where)
		"fight":
			# the team's focus; an enemy already in reach is hit rather than walked past on the way
			var focus: SimUnit = t if t != null and t.alive and w.vision.sees(h.team, t) else null
			var near: SimUnit = null
			for e in _foes:
				var in_reach := e.alive and not e.is_invulnerable() and h.edge_distance(e) <= h.attack_range + 120.0
				if in_reach and (near == null or h.edge_distance(e) < h.edge_distance(near)):
					near = e
			if focus != null and h.pos.distance_to(focus.pos) < 1900.0:
				if near != null and near != focus and h.edge_distance(focus) > h.attack_range + 350.0:
					_run_fight(h, near)
				else:
					_run_fight(h, focus)
			elif near != null:
				_run_fight(h, near)
			else:
				_go(h, where)
		"group":
			if h.pos.distance_to(where) > 600.0:
				_go(h, where)
			elif not _foes.is_empty():
				var e := _foes[0]
				_run_fight(h, e)
			else:
				_lane_or_farm(h)
		_:
			_lane_or_farm(h)

func _lane_or_farm(h: SimUnit) -> void:
	if _laning_phase(h):
		_lane(h)
	else:
		_run_farm(h)

func _run_defend(h: SimUnit, b: SimUnit, where: Vector2) -> void:
	if h.pos.distance_to(where) > 1200.0:
		_go(h, where)
		return
	# enemy heroes first when the fight is even (the tower helps), then the creeps hitting the building
	for e in _foes:
		if e.pos.distance_to(where) < 1200.0 and BotMemory.fight_p(fight_features(h, e), h.team) > 0.4:
			_run_fight(h, e)
			return
	var best: SimUnit = null
	for c in _ecreeps:
		if c.pos.distance_to(where) < 1100.0 and (best == null or c.hp < best.hp):
			best = c
	if best != null:
		if kit == "sludge" and h.ability_level_of("stench") > 0:
			_sludge_stench(h, _foes, _ecreeps)
		_order(h, {"type": O.ATTACK_UNIT, "target": best.id})
		return
	_go(h, where + (w.map.fountains[h.team] - where).normalized() * 200.0)

## Returns false when the push has nothing for this bot (no building, or no wave of ours anywhere near it and too few
## heroes to take it alone): the bot then farms instead of waiting under the tower.
func _run_push(h: SimUnit, t: SimUnit, p_lane: String) -> bool:
	if t == null or not t.alive:
		_lane_or_farm(h)
		return false
	# walk with the creeps: clear them, then hit the building while our creeps (or several heroes) are there
	if h.pos.distance_to(t.pos) > 1800.0:
		_go(h, t.pos + (w.map.fountains[h.team] - t.pos).normalized() * 1000.0)
		return true
	for e in _foes:
		if BotMemory.fight_p(fight_features(h, e), h.team) > 0.5 and h.pos.distance_to(e.pos) < 1000.0:
			_run_fight(h, e)
			return true
	var tanking := 0
	for c in _acreeps:
		if c.pos.distance_to(t.pos) < t.attack_range + 200.0:
			tanking += 1
	var heroes_here := 1
	for a in _allies:
		if a.pos.distance_to(t.pos) < 1200.0:
			heroes_here += 1
	if not t.is_invulnerable() and (tanking >= 2 or heroes_here >= 3 or t.atk_target != h.id and heroes_here >= 2):
		_order(h, {"type": O.ATTACK_UNIT, "target": t.id})
		return true
	var best: SimUnit = null
	for c in _ecreeps:
		if best == null or c.hp < best.hp:
			best = c
	if best != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": best.id})
		return true
	# wait for the next wave just outside the tower's reach, but only if one of ours is on its way
	var coming := false
	for c in w.query(t.pos, 3200.0):
		if c.alive and c.team == h.team and c.is_lane_creep():
			coming = true
			break
	if not coming:
		_lane_or_farm(h)
		return false
	_go(h, t.pos + (h.pos - t.pos).normalized() * (t.attack_range + t.hull + 220.0))
	return true

# ---- Farming: lanes and the jungle -------------------------------------------------------------------------------------

var _camp := -1                            # the camp it is farming
var _farm_lane := ""

## After the laning phase (or with its lane lost): the best of the lane waves and camps it can reach, by gold per
## second of travel and killing, avoiding places where enemies were seen and (learned) where bots died.
func _run_farm(h: SimUnit) -> void:
	var b := brain()
	if _camp >= 0:
		var c: Dictionary = w.map.camps[_camp]
		if not b.camp_up(_camp) and h.pos.distance_to(c.pos) < 500.0 and _camp_creeps(_camp).is_empty():
			_camp = -1
		elif not b.claim_camp(_camp, h.id) or not _safe_to_farm(h, c.pos):
			_camp = -1
		else:
			_farm_camp(h, _camp)
			return
	if _farm_lane != "" and w.time < float(_farm_lane_until):
		_farm_wave(h, _farm_lane)
		return
	# choose
	var best_s := 0.0
	var pick := ""
	var pick_camp := -1
	for ln in ["top", "mid", "bot"]:
		var fp := _lane_front(h, ln)
		if fp == Vector2.INF or not _safe_to_farm(h, fp):
			continue
		var travel := h.pos.distance_to(fp) / maxf(150.0, h.move_speed)
		var s := 180.0 / (travel + 12.0)
		if ln == lane:
			s *= 1.25
		if s > best_s:
			best_s = s
			pick = ln
			pick_camp = -1
	var fq := float(sk.get("farm", 1.0))
	if fq < 0.7 and pick != "" and rng.randf() > fq + 0.3:
		pick = ["top", "mid", "bot"][rng.randi_range(0, 2)]   # a poor farmer drifts to some other lane
	for c in w.map.camps:
		if not b.camp_up(c.id) or b.camp_claimed_by_other(c.id, h.id):
			continue
		if fq < 1.0 and (String(c.kind) == "ancient" and fq < 0.8 or rng.randf() > fq):
			continue                       # a poor farmer seldom thinks of the jungle
		if c.side != h.team and w.time < 1200.0 and role > 1:
			continue                       # the enemy's jungle only for the carry, and later
		if not _can_clear(h, c) or not _safe_to_farm(h, c.pos):
			continue
		var travel2 := h.pos.distance_to(c.pos) * 1.2 / maxf(150.0, h.move_speed)
		var value: float = {"small": 90.0, "medium": 150.0, "large": 210.0, "ancient": 330.0}.get(String(c.kind), 100.0)
		value *= 1.0 + 0.6 * float(b.stack_count.get(c.id, 0))
		var s2 := value / (travel2 + _clear_time(h, c)) * (1.0 - 0.5 * BotMemory.danger(h.team, c.pos))
		if s2 > best_s:
			best_s = s2
			pick = ""
			pick_camp = c.id
	if pick_camp >= 0:
		_camp = pick_camp
		b.claim_camp(pick_camp, h.id)
		if _tp_out(h, w.map.camps[pick_camp].pos):
			return
		_farm_camp(h, pick_camp)
		return
	if pick != "":
		_farm_lane = pick
		_farm_lane_until = w.time + 6.0
		if _tp_out(h, _lane_front(h, pick)):
			return
		_farm_wave(h, pick)
		return
	_go(h, _waiting_spot(h))

var _farm_lane_until := C.LONG_AGO

func _farm_wave(h: SimUnit, ln: String) -> void:
	if not _laning_phase(h) and _foes.is_empty() and _clear_wave(h, ln):
		return
	var old := lane
	lane = ln
	_lane(h)
	lane = old

## After the laning phase, with no enemy hero in sight, a lane wave is farmed by killing it: last hits first, else the
## weakest creep in reach, area spells on three or more; never under an enemy tower that is not busy with our creeps.
## Waiting for creep-on-creep last hits, as in lane, left cores standing idle for most of each wave. False when there
## is nothing to clear here (the caller lanes as before).
func _clear_wave(h: SimUnit, ln: String) -> bool:
	var ns: Array[SimUnit] = []
	var towers: Array[SimUnit] = []
	var allies: Array[SimUnit] = []
	for u: SimUnit in w.query(h.pos, 1300.0):
		if not u.alive:
			continue
		if u.kind == K.TOWER and u.team != h.team:
			towers.append(u)
		elif u.is_lane_creep() and u.team == h.team:
			allies.append(u)
		elif u.is_lane_creep() and u.team != h.team and u.lane == ln and w.vision.sees(h.team, u):
			ns.append(u)
	var safe: Array[SimUnit] = []
	for n in ns:
		var under := false
		for tw in towers:
			var busy := w.get_unit(tw.atk_target)
			if n.pos.distance_to(tw.pos) <= tw.attack_range + tw.hull + 60.0 and not (busy != null and busy.team == h.team and not busy.is_hero()):
				under = true
		if not under:
			safe.append(n)
	if safe.is_empty():
		return false
	if _busy(h):
		return true
	var mid := Vector2.ZERO
	for n in safe:
		mid += n.pos
	mid /= safe.size()
	if safe.size() >= 3 and _aoe_farm(h, safe, mid):
		return true
	var lh := _last_hit_target(h, safe, allies)
	if lh != null and lh.team != h.team:
		_order(h, {"type": O.ATTACK_UNIT, "target": lh.id})
		return true
	var best: SimUnit = null
	for n in safe:
		if best == null or n.hp < best.hp:
			best = n
	_order(h, {"type": O.ATTACK_UNIT, "target": best.id})
	return true

## Where a lane's creep waves meet, from our side: our furthest creep along the lane, else our front tower.
func _lane_front(h: SimUnit, ln: String) -> Vector2:
	var path := w.map.lane_path(ln, h.team)
	var best := Vector2.INF
	var bp := -1.0
	for u in w.units:
		if u.alive and u.is_lane_creep() and u.team == h.team and u.lane == ln:
			var pr := _progress(u.pos, path)
			if pr > bp:
				bp = pr
				best = u.pos
	if best == Vector2.INF:
		return Vector2.INF
	# early on, not right under the enemy's tower; later, up to its reach (the wave pushes the tower with us)
	var et := brain().front_tower(1 - h.team, ln)
	if et != null and best.distance_to(et.pos) < et.attack_range + 500.0:
		if w.time < 900.0 or not brain().enemies_near(et.pos, 2000.0, 6.0).is_empty():
			return Vector2.INF
		return et.pos + (best - et.pos).normalized() * (et.attack_range + et.hull + 150.0)
	return best

func _safe_to_farm(h: SimUnit, p: Vector2) -> bool:
	for e in brain().enemies_near(p, 1700.0, 8.0):
		if KITS.power(w, e, h) > KITS.power(w, h, e) * 0.7:
			return false
	return true

func _camp_creeps(camp_id: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var c: Dictionary = w.map.camps[camp_id]
	for u: SimUnit in w.query(c.pos, 1300.0):
		if u.alive and u.camp_id == camp_id:
			out.append(u)
	return out

## Whether the hero can clear a camp without dropping below half its health: the camp's creeps as they stand (grown
## and stacked; its usual group when unseen), all hitting at once while we kill them, against our health. A camp
## kind that nearly killed this bot is skipped until it has two more levels (a carry used to walk back to a camp
## it could not clear again and again, crossing the map each time).
func _can_clear(h: SimUnit, c: Dictionary) -> bool:
	var kind := String(c.kind)
	if h.level < int(_camp_fail.get(kind, 0)):
		return false
	if h.level < {"small": 2, "medium": 4, "large": 6, "ancient": 10}.get(kind, 4) and not (role == 1 and h.level >= 4 and kind != "ancient"):
		return false
	var hp := 0.0
	var dps := 0.0
	var live := _camp_creeps(int(c.id)).filter(func(n): return w.vision.sees(h.team, n))
	if not live.is_empty():
		for n in live:
			hp += n.hp
			dps += (n.dmg_min + n.dmg_max) * 0.5 / maxf(0.2, n.attack_interval())
	else:
		var stacks := 1.0 + float(brain().stack_count.get(c.id, 0))
		for id in SimMap.CAMP_GROUPS[c.kind][0]:
			var d := SimData.unit(id)
			hp += float(d.hp) * stacks
			dps += (float(d.dmg_min) + float(d.dmg_max)) * 0.5 / float(d.get("bat", 2.0)) * stacks
	var t := hp / maxf(10.0, _my_camp_dps(h))
	# the camp's damage shrinks as its creeps die: about two thirds of it over the whole clear
	var taken := dps * t * 0.65 * C.armor_multiplier(h.armor)
	return taken < h.hp * 0.5

var _camp_fail := {}                       # camp kind -> hero level needed before trying that kind again

func _my_camp_dps(h: SimUnit) -> float:
	var my := KITS.dps(w, h, null) * 0.85
	if kit == "sludge" and h.ability_level_of("stench") > 0:
		my += w.abilities.val(h, "stench", "dps") * 2.0
	return my

func _clear_time(h: SimUnit, c: Dictionary) -> float:
	var hp := 0.0
	var live := _camp_creeps(int(c.id)).filter(func(n): return w.vision.sees(h.team, n))
	if not live.is_empty():
		for n in live:
			hp += n.hp
	else:
		for id in SimMap.CAMP_GROUPS[c.kind][0]:
			hp += float(SimData.unit(id).hp)
	return hp / maxf(10.0, _my_camp_dps(h))

func _farm_camp(h: SimUnit, camp_id: int) -> void:
	var c: Dictionary = w.map.camps[camp_id]
	if h.hp < h.max_hp * 0.35 and not _camp_creeps(camp_id).is_empty():
		_camp_fail[String(c.kind)] = h.level + 2
		_camp = -1
		_go(h, _safe_point(h))
		return
	var ns: Array[SimUnit] = []
	for n in _camp_creeps(camp_id):
		if w.vision.sees(h.team, n):
			ns.append(n)
	if ns.is_empty():
		if h.pos.distance_to(c.pos) > 350.0:
			_go(h, c.pos + (h.pos - c.pos).normalized() * 300.0)
		else:
			# nobody home: the camp was cleared (the team marks it) and we move on
			_camp = -1
		return
	# AoE spells on a crowd, then the weakest creep
	if _aoe_farm(h, ns, c.pos):
		return
	var best: SimUnit = null
	for n in ns:
		if best == null or n.hp < best.hp:
			best = n
	_order(h, {"type": O.ATTACK_UNIT, "target": best.id})

## Area spells on a crowd of creeps (a camp or a lane wave): true when one was cast.
func _aoe_farm(h: SimUnit, ns: Array[SimUnit], centre: Vector2) -> bool:
	var close := 0
	for n in ns:
		if n.pos.distance_to(h.pos) < 350.0:
			close += 1
	if _spells_ok() and SimBot16.handles(kit):
		return SimBot16.aoe_farm(self, h, ns, centre)
	if _spells_ok() and SimBot17.handles(kit):
		return SimBot17.aoe_farm(self, h, ns, centre)
	if _spells_ok() and SimBot18.handles(kit):
		return SimBot18.aoe_farm(self, h, ns, centre)
	if _spells_ok() and SimBot19.handles(kit):
		return SimBot19.aoe_farm(self, h, ns, centre)
	if _spells_ok():
		var ab := w.abilities
		match kit:
			"sludge":
				var want := close >= 2 and h.hp > h.max_hp * 0.4
				if h.ability_level_of("stench") > 0 and want != bool(h.toggles.get("stench", false)):
					_order(h, {"type": O.CAST_NO_TARGET, "ability": "stench"}, true)
			"ezee":
				if close >= 2 and h.mana > h.max_mana * 0.5 and ab.cast_error(h, "dark_stomp", -1, null, h.pos) == "":
					_order(h, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"}, true)
					_cast_deadline = w.time + 0.8
					return true
			"azrin":
				var mid2 := Vector2.ZERO
				for n in ns:
					mid2 += n.pos
				mid2 /= ns.size()
				if ns.size() >= 2 and h.mana > h.max_mana * 0.5 and ab.cast_error(h, "touch_of_ember", -1, null, mid2) == "" \
						and h.pos.distance_to(mid2) < 760.0:
					_order(h, {"type": O.CAST_POINT, "ability": "touch_of_ember", "point": mid2}, true)
					_cast_deadline = w.time + 0.9
					return true
				if ab.spirits(h) >= 3 and ab.cast_error(h, "spirit_of_fire", -1, null, mid2) == "" and h.pos.distance_to(mid2) < 800.0:
					_order(h, {"type": O.CAST_POINT, "ability": "spirit_of_fire", "point": mid2}, true)
					_cast_deadline = w.time + 0.7
					return true
			"froster":
				var mid3 := Vector2.ZERO
				for n in ns:
					mid3 += n.pos
				mid3 /= ns.size()
				if ns.size() >= 2 and h.mana > h.max_mana * 0.45 and ab.cast_error(h, "breath_of_cold", -1, null, mid3) == "" \
						and h.pos.distance_to(mid3) < 700.0:
					_order(h, {"type": O.CAST_POINT, "ability": "breath_of_cold", "point": mid3}, true)
					_cast_deadline = w.time + 0.7
					return true
			"blood_ranger":
				if ns.size() >= 3 and h.mana > h.max_mana * 0.6 and ab.cast_error(h, "burst_shot", -1, null, centre) == "":
					var mid := Vector2.ZERO
					for n in ns:
						mid += n.pos
					_order(h, {"type": O.CAST_POINT, "ability": "burst_shot", "point": mid / ns.size()}, true)
					_cast_deadline = w.time + 2.6
					return true
	return false

# ---- Stacking, pulling, wards -------------------------------------------------------------------------------------------

var _stack := {}                           # {camp, phase, dir}: a stack or pull in progress

## Supports stack a camp near them at :53 when their lane can spare them (offlane support any time).
func _stack_desire(h: SimUnit) -> float:
	if role < 4 or w.time < 120.0 or w.time > 1500.0:
		return 0.0                             # late in the game supports group with the team instead
	var sec := fposmod(w.time, 60.0)
	if not _stack.is_empty() and String(_stack.kind) == "stack":
		if sec > 2.5 and sec < 30.0:
			_stack = {}                    # the minute passed (stacked or not): done
			return 0.0
		return 0.66
	if sec < 36.0 or sec > 50.0 or not _known.is_empty() or h.hp < h.max_hp * 0.5 or w.time - _last_stack < 110.0:
		return 0.0
	var b := brain()
	if role == 5 and _laning_phase(h) and w.time < 360.0:
		var core := b._core_in_lane(lane, h)
		if core != null and core.alive and core.pos.distance_to(h.pos) < 2000.0:
			return 0.0
	var best := -1
	var bd := INF
	for c in w.map.camps:
		if c.side != h.team or not b.camp_up(c.id) or int(b.stack_count.get(c.id, 0)) >= 3:
			continue
		if b.camp_claimed_by_other(c.id, h.id) or bool(c.pull) and role == 5:
			continue
		var d: float = h.pos.distance_to(c.pos)
		var travel := d * 1.2 / maxf(150.0, h.move_speed)
		if travel + sec > 51.0 or d > bd or d > 2600.0:
			continue
		bd = d
		best = c.id
	if best < 0:
		return 0.0
	_stack = {"kind": "stack", "camp": best, "phase": "go", "t": w.time}
	_last_stack = w.time
	return 0.66

func _run_stack(h: SimUnit) -> void:
	if _stack.is_empty():
		_lane_or_farm(h)
		return
	var c: Dictionary = w.map.camps[int(_stack.camp)]
	var sec := fposmod(w.time, 60.0)
	var box: Vector2 = c.box
	# pull the creeps out toward our side, along the way it came in
	var dir: Vector2 = (w.map.fountains[h.team] - (c.pos as Vector2)).normalized()
	var reach := (h.attack_range + 40.0) if h.is_ranged() else 140.0
	var wait_at: Vector2 = c.pos + dir * (maxf(box.x, box.y) + 120.0)
	var aggro_at: float = {"small": 53.6, "medium": 53.2, "large": 52.8, "ancient": 52.2}.get(String(c.kind), 53.0)
	if not h.is_ranged():
		aggro_at -= 0.8
	match String(_stack.phase):
		"go":
			if sec >= aggro_at and sec < 58.0:
				_stack.phase = "hit"
			else:
				_go(h, wait_at)
		"hit":
			var ns := _camp_creeps(int(_stack.camp))
			if ns.is_empty() or sec >= 58.0 or sec < 30.0:
				_stack.phase = "run"
				return
			var near: SimUnit = ns[0]
			for n in ns:
				if n.pos.distance_to(h.pos) < near.pos.distance_to(h.pos):
					near = n
			if near.neutral_state == 1:
				_stack.phase = "run"
			elif h.edge_distance(near) > reach + 400.0:
				_go(h, near.pos)
			else:
				_order(h, {"type": O.ATTACK_UNIT, "target": near.id})
		"run":
			_go(h, c.pos + dir * 1400.0)
			if sec > 1.0 and sec < 30.0:
				var b := brain()
				b.stack_count[int(_stack.camp)] = int(b.stack_count.get(int(_stack.camp), 0)) + 1
				var core := b._core_in_lane(lane, h)
				if core != null and rng.randf() < 0.5:
					say("Stacked the %s camp for %s." % [String(c.kind), b._name_of(core)], "stk_%d" % h.id, 120.0, false, "stack",
						{"core": SimTeamAI.hero_label(core) if core.bot else (core.player_label() if core.player_label() != "" else SimTeamAI.hero_label(core))})
				_stack = {}

## The safe lane's support pulls a pull camp into its own creep wave as the wave walks past (Dota's :15 / :45 pull),
## pulling the lane back toward our tower and denying the enemy the wave.
func _pull_desire(h: SimUnit) -> float:
	if role != 5 or not _laning_phase(h) or w.time < 120.0:
		return 0.0
	if not _stack.is_empty() and String(_stack.kind) == "pull":
		if w.time - float(_stack.t) > 12.0:
			_stack = {}                    # the pull is over (or never started)
			return 0.0
		return 0.64
	if h.hp < h.max_hp * 0.5 or w.time - _last_pull < 50.0:
		return 0.0
	var b := brain()
	for c in w.map.camps:
		if c.side != h.team or not bool(c.pull) or not b.camp_up(c.id) or c.kind != "small":
			continue
		if h.pos.distance_to(c.pos) > 2500.0 or not brain().enemies_near(c.pos, 1300.0, 3.0).is_empty():
			continue
		# our fresh wave walking past the camp, not yet fighting
		var wave := 0
		for cr in _acreeps:
			if cr.pos.distance_to(c.pos) < 1500.0 and cr.atk_target < 0:
				wave += 1
		if wave >= 3:
			_stack = {"kind": "pull", "camp": c.id, "phase": "hit", "t": w.time}
			_last_pull = w.time
			return 0.64
	return 0.0

var _last_pull := C.LONG_AGO
var _last_stack := C.LONG_AGO

func _run_pull(h: SimUnit) -> void:
	if _stack.is_empty():
		_lane(h)
		return
	var ns := _camp_creeps(int(_stack.camp))
	if ns.is_empty():
		_stack = {}
		return
	match String(_stack.phase):
		"hit":
			var near: SimUnit = ns[0]
			for n in ns:
				if n.pos.distance_to(h.pos) < near.pos.distance_to(h.pos):
					near = n
			if near.neutral_state == 1:
				_stack.phase = "lead"
			else:
				_order(h, {"type": O.ATTACK_UNIT, "target": near.id})
		"lead":
			# walk into our own creeps; once they fight the neutrals, back to the lane
			var tgt := Vector2.INF
			for cr in _acreeps:
				if tgt == Vector2.INF or cr.pos.distance_to(h.pos) < tgt.distance_to(h.pos):
					tgt = cr.pos
			var fighting := false
			for cr in _acreeps:
				var t := w.get_unit(cr.atk_target)
				if t != null and t.kind == K.NEUTRAL_CREEP:
					fighting = true
			if fighting or tgt == Vector2.INF:
				_stack = {}
				return
			_go(h, tgt)

## Supports keep an Eye Ward on the river or jungle entrance nearest their lane.
const WARD_SPOTS := [Vector2(-2900, 2200), Vector2(2450, -3250), Vector2(-500, -1900), Vector2(4300, -4100)]

func _ward_slot(h: SimUnit) -> int:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == "observer_ward":
			return i
	return -1

func _ward_desire(h: SimUnit) -> float:
	if role < 4 or _ward_slot(h) < 0 or not _known.is_empty():
		return 0.0
	return 0.52 if _ward_spot(h) != Vector2.INF else 0.0

func _ward_spot(h: SimUnit) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for s: Vector2 in WARD_SPOTS:
		var p := s if h.team == C.DAWN else -s
		var taken := false
		for u: SimUnit in w.query(p, 1200.0):
			if u.alive and u.is_ward() and u.team == h.team:
				taken = true
		if taken:
			continue
		var d := p.distance_to(h.pos) + p.distance_to(_waiting_spot(h)) * 0.5
		if d < bd:
			bd = d
			best = p
	return best

func _run_ward(h: SimUnit) -> void:
	var slot := _ward_slot(h)
	var p := _ward_spot(h)
	if slot < 0 or p == Vector2.INF:
		_lane_or_farm(h)
		return
	if not w.map.is_walkable(p):
		var cc := w.map.nearest_walkable(w.map.world_to_cell(p))
		p = w.map.cell_center(cc.x, cc.y)
	if h.pos.distance_to(p) > 450.0:
		_go(h, p)
		return
	_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": slot, "point": p}, true)
	_cast_deadline = w.time + 0.6

# ---- Skills and items -----------------------------------------------------------------------------------------------------

func _learn(h: SimUnit) -> void:
	# a talent first whenever a tier opens (heroes without a talent tree skip this)
	var tree: Array = h.def.get("talents", [])
	for tier in tree.size():
		if w.abilities.can_learn_talent(h, tier):
			w.abilities.learn_talent(h, tier, KITS.talent_side(kit, tier))
	var guard := 0
	while h.ability_points > 0 and guard < 4:
		guard += 1
		var done := false
		for aid in skill_order:
			if w.abilities.can_learn(h, aid) and _wants(h, aid):
				w.abilities.learn(h, aid)
				done = true
				break
		if not done:
			for aid in h.abilities:
				if w.abilities.learn(h, aid):
					done = true
					break
		if not done:
			break
	if h.level == 6 and role == 2 and not _said_six:
		_said_six = true
		say("Level 6, I can gank now.", "six_%d" % h.id, 9999.0, false, "six")

var _said_six := false

func _wants(h: SimUnit, aid: String) -> bool:
	# follow the skill order: count how many times this ability appears before the current level
	var want := 0
	for i in mini(h.level, skill_order.size()):
		if skill_order[i] == aid:
			want += 1
	return h.ability_level_of(aid) < want

func _shop(h: SimUnit) -> void:
	# every 30 s from 5:00 (and right after a death): read the enemy team and move the item the game calls for to the
	# front of the list (SimBotItems)
	if w.time >= _counter_next and w.time >= 300.0 and bool(sk.advanced):
		_counter_next = w.time + 30.0
		_counter_items(h)
	# sell and sort first (SimBotBags): junk out, the best items into the main slots
	if h.alive and SimBotBags.tidy(self, h):
		return
	# past the planned build: what this kind of hero buys late (SimBotBags.LATE)
	if _build_i >= build.size() and w.time >= 900.0:
		var more := SimBotBags.next_late(self, h)
		if more != "":
			build.append(more)
	var guard := 0
	while _build_i < build.size() and guard < 6:
		guard += 1
		var id: String = build[_build_i]
		var d := SimData.item(id)
		# owned already (a basic item owned counts too: a second pair of boots is never wanted)
		if w.shop.owns(h, id) and (not (d.components as Array).is_empty() or id == "jump_knife" or bool(d.get("unique", false))
				or id in SimBotBags.BOOTS) or _covered_by(h, id):
			_build_i += 1
			continue
		# an early item the game has moved past (a Zap Wand at 35:00) is not worth buying any more
		if SimBotBags.EARLY.has(id) and w.time > float(SimBotBags.EARLY[id]):
			_build_i += 1
			continue
		if w.shop.buy_error(h, id) != "":
			break
		var cost := w.shop.price(h, id)
		if cost <= 0 and not (d.components as Array).is_empty():
			break                          # every piece is bought: it forms when the pieces meet (shop or courier)
		# late luxury items keep buyback gold back (cores past 30:00)
		var reserve := w.buyback_cost(h) if _build_i >= _core_len and w.time >= 2100.0 and not KITS.is_support(role) else 0
		if h.gold() < cost + reserve:
			# short of the whole item: its biggest part that fits now (its stats work at once)
			if h.gold() - reserve >= 250:
				var part := SimBotBags.buy_part(self, h, id)
				if part != "":
					parts_bought += 1
			break
		var err := w.shop.buy(h, id)
		if err == "Inventory full":
			# no room: wait for the shop or the courier to clear the bags (it used to skip the item for good)
			_room_wanted_at = w.time
			break
		if err != "" and err != "Not enough gold":
			_build_i += 1
			continue
		if err == "":
			# bought away from the shop, its pieces may wait in the stash apart from the parts in the bags: the item
			# stays next in line (its parts kept, SimBotBags) until it forms
			if not (d.components as Array).is_empty() and not w.shop.owns(h, id):
				break
			_build_i += 1
			if KITS.power_spike(h, id):
				say("Got my %s." % String(d.get("name", id)), "item_%d_%s" % [h.id, id], 9999.0, false, "item",
					{"item": String(d.get("name", id)), "item_id": id})
	# away from the shop, the courier brings what is waiting in the stash
	if h.alive and (h.stash.any(func(x): return x != null) or h.courier_items.any(func(x): return x != null)) and not w.shop.in_shop(h):
		var c := w.get_unit(h.courier_id)
		if c and c.alive and c.courier_state == "idle":
			w.courier_deliver(h)
	if w.shop.tp_owned(h) == 0 and h.gold() >= 100 and w.time > -60.0:
		w.shop.buy(h, "tp_scroll")
	# supports carry an Eye Ward (free) from the start
	if role >= 4 and bool(sk.advanced) and _ward_slot(h) < 0 and not w.shop.owns(h, "observer_ward") \
			and w.time - _last_ward_buy > 150.0 and w.shop.in_shop(h):
		if w.shop.buy(h, "observer_ward") == "":
			_last_ward_buy = w.time
	# out of healing in lane: one more Healing Paste (the courier brings it)
	if h.hp < h.max_hp * 0.5 and w.time < 900.0 and not _has_item(h, "salve") and h.gold() >= 100 \
			and w.time - _last_salve_buy > 40.0 and not h.stash.any(func(x): return x != null and x.id == "salve"):
		if w.shop.buy(h, "salve") == "":
			_last_salve_buy = w.time
	# casters low on mana in lane: a Mana Potion by courier
	if h.max_mana > 300.0 and h.mana < h.max_mana * 0.25 and w.time < 900.0 and role != 1 and not _has_item(h, "clarity") 			and h.gold() >= 50 and w.time - _last_clarity_buy > 45.0:
		if w.shop.buy(h, "clarity") == "":
			_last_clarity_buy = w.time
	# drink a salve when hurt and not in the fountain
	if h.alive and h.hp < h.max_hp * 0.55 and bool(sk.spells):
		_use_item(h, "salve")

var _last_ward_buy := C.LONG_AGO
var items_sold: Array = []                 # item ids sold (report, tests)
var parts_bought := 0                      # parts bought ahead of a whole item (report, tests)
var _room_wanted_at := C.LONG_AGO          # last time a purchase found no room
var _next_room_sale := C.LONG_AGO          # the next sale made only for room (SimBotBags.tidy)
var _core_len := 99                        # the planned build's length (items past it are late luxuries)

## An early part the hero no longer needs because it owns what it builds into (a Zap Stick after the Zap Wand).
func _covered_by(h: SimUnit, id: String) -> bool:
	for it in h.inventory:
		if it != null and String(it.id) != id and id in SimBotBags.all_parts(String(it.id)):
			return true
	return false
var _last_salve_buy := C.LONG_AGO
var _last_clarity_buy := C.LONG_AGO
var death_dmg := Vector3.ZERO              # damage by type that killed it lately: physical, magic, pure (fading)
var alone_deaths := 0                      # deaths with no ally near (caught alone)
var _counter_next := 300.0
var counters_bought: Array = []            # counter items it moved up (report, tests)
var _last_dust_buy := C.LONG_AGO

## The counter item the game calls for now (SimBotItems.next_counter): put first in the build, or bought at once when
## it is a consumable (Reveal Dust, a Reveal Ward). Says why in team chat once per item.
func _counter_items(h: SimUnit) -> void:
	var prof := SimBotItems.profile(w, h.team)
	# true sight against invisible enemies, bought at once (cheap)
	var sight := SimBotItems.wants_sight(w, h, role, prof)
	if sight != "" and w.time - _last_dust_buy > 60.0 and h.gold() >= int(SimData.item(sight).cost) + 100 			and w.shop.buy(h, sight) == "":
		_last_dust_buy = w.time
		say("Bought %s, they have invisible heroes." % String(SimData.item(sight).name), "dust_%d" % h.id, 300.0, false, "dust_buy")
	# one counter at a time: the last one planned is bought first (no re-ordering every half minute)
	for c in counters_bought:
		if not w.shop.owns(h, String(c)) and build.find(c) >= _build_i:
			return
	var want := SimBotItems.next_counter(w, h, role, build, _build_i, prof, death_dmg, alone_deaths)
	if want == "":
		return
	var d := SimData.item(want)
	var i := build.find(want)
	if i >= 0 and i < _build_i:
		return
	if i > _build_i:
		build.remove_at(i)
	build.insert(mini(_build_i, build.size()), want)
	counters_bought.append(want)
	var why := {"magic": "their magic damage", "physical": "their right clicks", "disable": "their stuns",
		"invis": "their invisible heroes", "evasion": "their evasion", "escape": "getting caught"}
	var kind := String((SimBotItems.ANSWERS.get(want, ["physical"]) as Array)[0])
	if prof.disablers >= 2 and want == "spell_shield":
		kind = "disable"
	var short := {"magic": "magic", "physical": "right clicks", "disable": "stuns", "invis": "invis", "evasion": "evasion",
		"escape": "ganks"}
	say("Getting %s against %s." % [String(d.name), String(why.get(kind, "them"))], "counter_%d_%s" % [h.id, want], 9999.0, false,
		"counter", {"item": String(d.name), "why": String(short.get(kind, "them"))})

func _has_item(h: SimUnit, id: String) -> bool:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == id:
			return true
	return false

## The main slot holding an item whose active can be used now (no error), or -1. A ranked bot with poor item sense
## (RATED "item_use") often does not think of it at that moment.
func _ready_slot(h: SimUnit, item_id: String, t: SimUnit = null, p := Vector2.INF) -> int:
	if rating >= 0.0 and rng.randf() > float(sk.get("item_use", 1.0)):
		return -1
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == item_id:
			var at := p if p != Vector2.INF else (t.pos if t else h.pos)
			return i if w.abilities.cast_error(h, "", i, t, at) == "" else -1
	return -1

## Item actives that do not depend on a fight: wand when hurt, Mana Boots when low on mana, Medic Kit when hurt, a
## Gold Glove charge on the healthiest creep in reach.
func _items(h: SimUnit) -> void:
	if not h.alive or _busy(h):
		return
	for wid in ["magic_wand", "magic_stick"]:
		var ws := _ready_slot(h, wid)
		if ws >= 0 and h.stick_charges >= 4 and (h.hp < h.max_hp * 0.45 or h.mana < h.max_mana * 0.2):
			w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": ws})
	# a Mana Potion when short of mana and no enemy hero is close (damage ends it)
	if h.mana < h.max_mana * 0.55 and not _has_mod(h, "clarity") and not _enemy_hero_near(h, 1100.0):
		_use_item(h, "clarity")
	var ms := _ready_slot(h, "mana_boots")
	if ms >= 0 and h.max_mana - h.mana >= 160.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": ms})
	var mk := _ready_slot(h, "medic_kit")
	if mk >= 0 and (h.hp < h.max_hp * 0.6 or _ally_hurt_near(h, 750.0)):
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": mk})
	var gb := _ready_slot(h, "guard_boots")
	if gb >= 0 and (h.hp < h.max_hp * 0.45 or _ally_hurt_near(h, 900.0) or h.max_mana - h.mana >= 250.0):
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": gb})
	_save_items(h)
	for i in 6:
		var it = h.inventory[i]
		if it == null or it.id != "gold_glove" or int(it.get("charges", 0)) <= 0:
			continue
		var best: SimUnit = null
		for c: SimUnit in w.query(h.pos, 600.0):
			if c.alive and c.is_creep() and c.team != h.team and not bool(c.def.get("ancient", false)) \
					and w.vision.sees(h.team, c) and (best == null or c.max_hp > best.max_hp):
				best = c
		if best != null and w.abilities.cast_error(h, "", i, best, best.pos) == "":
			_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": i, "target": best.id}, true)
			_cast_deadline = w.time + 1.0

## Items that keep someone alive or find someone hidden: Fade Cape on an ally (or itself) that enemy heroes are
## bringing down, Push Staff to shove a caught ally away from its chaser, Reveal Dust when an enemy hero it saw a
## moment ago fades out of sight near it.
func _save_items(h: SimUnit) -> void:
	if _foes.is_empty() and _known.is_empty():
		return
	var gc := _ready_slot(h, "glimmer_cape", h)
	var ps := _ready_slot(h, "push_staff", h, h.pos)
	if gc >= 0 or ps >= 0:
		var cands: Array = [h]
		cands.append_array(_allies)
		for a: SimUnit in cands:
			if not a.alive or a.pos.distance_to(h.pos) > 600.0 or a.hp > a.max_hp * 0.4 or not _hit_by_heroes(a, 1.5):
				continue
			var chaser: SimUnit = null
			for f in _foes:
				if f.pos.distance_to(a.pos) < 700.0 and (chaser == null or f.pos.distance_to(a.pos) < chaser.pos.distance_to(a.pos)):
					chaser = f
			if chaser == null:
				continue
			if gc >= 0 and not w.vision.true_sighted(1 - h.team, a):
				_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": gc, "target": a.id}, true)
				_cast_deadline = w.time + 0.3
				if a != h:
					say("Fade Cape on you, %s, run!" % SimTeamAI.hero_label(a), "glimmer_%d" % a.id, 30.0, false, "fade_cape",
						{"ally": SimTeamAI.hero_label(a)})
				return
			# Push Staff pushes where the ally faces: only when it is already running away from the chaser
			if ps >= 0 and a != h and a.moving and absf(angle_difference(a.facing, (a.pos - chaser.pos).angle())) < 0.6 					and w.abilities.cast_error(h, "", ps, a, a.pos) == "":
				_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": ps, "target": a.id}, true)
				_cast_deadline = w.time + 0.3
				return
	# Reveal Dust: an enemy hero seen in the last 3 s within 800 is now invisible
	var b := brain()
	for e in w.heroes:
		if e.team == h.team or not e.alive or w.vision.sees(h.team, e) or not e.has_flag("invisible"):
			continue
		var ls := b.last_seen(e)
		if float(ls[1]) < 3.0 and (ls[0] as Vector2).distance_to(h.pos) < 800.0 and _use_item(h, "reveal_dust"):
			say("Dusting their %s." % SimTeamAI.hero_label(e), "dust_use_%d" % e.id, 20.0, false, "dust_use", {"hero": SimTeamAI.hero_label(e)})
			return

## Whether enemy heroes hurt `a` within the last `secs` seconds.
func _hit_by_heroes(a: SimUnit, secs: float) -> bool:
	for sid in a.hero_damage_log:
		if w.time - float(a.hero_damage_log[sid]) < secs:
			var src := w.get_unit(int(sid))
			if src != null and src.team != a.team:
				return true
	return false

func _ally_hurt_near(h: SimUnit, r: float) -> bool:
	for a in _allies:
		if a.pos.distance_to(h.pos) < r and a.hp < a.max_hp * 0.5:
			return true
	return false

## Fight items, used when going after an enemy hero: Spell Shield, Frenzy Mask, Slip Boots to close in, and the
## disables (Hex Staff, Stun Blade, Silence Staff, Root Staff, Halberd) on a target that is not already disabled.
func _fight_items(h: SimUnit, e: SimUnit) -> void:
	var d := h.edge_distance(e)
	if _jump_in(h, e, d):
		return
	var held: Dictionary = w.status.disable_info(e)
	if held.is_empty() or float(held.left) < 0.3:
		for dis in ["hex_staff", "stun_blade", "silence_staff", "root_staff", "halberd"]:
			var ds := _ready_slot(h, dis, e)
			if ds < 0:
				continue
			var reach := float(SimData.item(dis).values.range)
			# the Halberd answers a right-clicker hitting us; Root Staff stops a target walking away
			if dis == "halberd" and (e.atk_target != h.id or e.def.primary == "int"):
				continue
			if dis == "root_staff" and e.hp > e.max_hp * 0.6 and not e.moving:
				continue
			if d <= reach + 50.0:
				_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": ds, "target": e.id}, true)
				_cast_deadline = w.time + 0.6
				return
	var bkb := _ready_slot(h, "spell_shield")
	# a sharp ranked bot puts it on before the stuns land: going in on a disabler, or two enemy heroes near
	var early := rating >= 0.0 and float(sk.get("item_use", 0.0)) >= 0.85 and d < 650.0 \
			and (KITS.disable_power(String(e.def.id)) >= 0.6 or _foes.size() >= 2)
	if bkb >= 0 and (early or d < 500.0 and (h.hp < h.max_hp * 0.75 or e.hp < e.max_hp * 0.5 or _foes.size() >= 2)):
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": bkb})
	var mom := _ready_slot(h, "mask_of_madness")
	if mom >= 0 and d < h.attack_range + 100.0 and h.hp > h.max_hp * 0.5:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": mom})
	var slip := _ready_slot(h, "slip_boots")
	if slip >= 0 and d > h.attack_range + 50.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": slip})
	var sa := _ready_slot(h, "spike_armor")
	if sa >= 0 and d < 400.0 and h.hp < h.max_hp * 0.7:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": sa})
	# run 2026-10-15 b items: Blast Rod to finish or open, Net Staff on a group or a runner, Frost Plate and War Drum
	# when the fight is on, Team Shield when hit, Leech Blade low, Storm Hammer's charge on itself, Refresh Stone once
	# the ultimate has been used
	for lv in range(5, 0, -1):
		var did := "dagon" if lv == 1 else "dagon_%d" % lv
		var bs := _ready_slot(h, did, e)
		if bs >= 0:
			var dmg := float(SimData.item(did).values.damage) * (1.0 - e.magic_resist)
			if d <= w.abilities.cast_range(h, "", bs, e) + 40.0 and (e.hp < dmg * 1.15 or e.hp < e.max_hp * 0.6):
				_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": bs, "target": e.id}, true)
				_cast_deadline = w.time + 0.4
				return
			break
	var ns := _ready_slot(h, "net_staff", null, e.pos)
	if ns >= 0 and d < 1050.0 and (held.is_empty() or float(held.left) < 0.3) and (e.moving or _foes.size() >= 2):
		_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": ns, "point": e.pos}, true)
		_cast_deadline = w.time + 0.4
		return
	var fp := _ready_slot(h, "frost_plate")
	if fp >= 0 and d < 600.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": fp})
	var dr := _ready_slot(h, "war_drum")
	if dr >= 0 and d < 900.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": dr})
	var tsh := _ready_slot(h, "team_shield")
	if tsh >= 0 and d < 700.0 and (h.hp < h.max_hp * 0.8 or _foes.size() >= 2):
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": tsh})
	var lb := _ready_slot(h, "leech_blade")
	if lb >= 0 and d < h.attack_range + 100.0 and h.hp < h.max_hp * 0.5:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": lb})
	var sh := _ready_slot(h, "storm_hammer", h)
	if sh >= 0 and d < 700.0:
		_order(h, {"type": O.CAST_UNIT, "ability": "", "item_slot": sh, "target": h.id}, true)
		_cast_deadline = w.time + 0.3
	var rs := _ready_slot(h, "refresh_stone")
	var ult := SimBotKits.ultimate(h)
	if rs >= 0 and ult != "" and h.ability_level_of(ult) > 0 and w.abilities.cooldown_left(h, ult) > 10.0 \
			and h.mana >= float(SimData.item("refresh_stone").mana) + w.abilities.ability_mana(h, ult) and d < 900.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": rs})

## A melee hero with a Jump Knife jumps onto the enemy hero it fights (a gank opener): healthy, the target out of
## reach but within the knife's, not onto an enemy tower (unless the target is nearly dead) and not into a crowd.
## Sludge has his own (the knife when Chomp is ready).
func _jump_in(h: SimUnit, e: SimUnit, d: float) -> bool:
	if h.is_ranged() or kit == "sludge" or not e.is_hero() or d < 300.0 or d > 1100.0 or h.hp < h.max_hp * 0.55:
		return false
	var land := e.pos + (h.pos - e.pos).normalized() * (h.hull + e.hull + 30.0)
	if e.moving:
		land += Vector2.from_angle(e.facing) * e.move_speed * 0.15
	var jk := _jump_slot(h, land)
	if jk < 0:
		return false
	if e.hp > e.max_hp * 0.35:
		for t in _etowers:
			if t.alive and t.pos.distance_to(land) < 800.0:
				return false
	var crowd := 0
	for f in _foes:
		if f.alive and f != e and f.pos.distance_to(land) < 800.0:
			crowd += 1
	var friends := 0
	for a in _allies:
		if a.alive and a.pos.distance_to(land) < 1200.0:
			friends += 1
	if crowd > friends + 1 or (crowd > friends and e.hp > e.max_hp * 0.5):
		return false
	_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": jk, "point": land}, true)
	_cast_deadline = w.time + 0.5
	return true

## A Jump Knife or Crash Knife ready to jump toward `p`, or -1.
func _jump_slot(h: SimUnit, p: Vector2) -> int:
	var s := _ready_slot(h, "crash_knife", null, p)
	return s if s >= 0 else _ready_slot(h, "jump_knife", null, p)

func _use_item(h: SimUnit, item_id: String) -> bool:
	if rating >= 0.0 and rng.randf() > float(sk.get("item_use", 1.0)):
		return false
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == item_id and h.get_meta("used_" + item_id, -99.0) + 13.0 < w.time:
			h.set_meta("used_" + item_id, w.time)
			w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": i})
			return true
	return false

# ---- Laning -------------------------------------------------------------------------------------------------------

func _enemy_hero_near(h: SimUnit, r: float) -> bool:
	for u: SimUnit in w.query(h.pos, r):
		if u.alive and u.is_hero() and u.team != h.team and w.vision.sees(h.team, u):
			return true
	return false

func _waiting_spot(h: SimUnit) -> Vector2:
	var t1 := _own_tower(h, 1)
	if t1 == null:
		var ft := brain().front_tower(h.team, lane)
		return ft.pos if ft != null else w.map.fountains[h.team]
	var path := w.map.lane_path(lane, h.team)
	return t1.pos + (path[0] - t1.pos).normalized() * 250.0

func _own_tower(h: SimUnit, tier: int) -> SimUnit:
	for u in w.units:
		if u.alive and u.team == h.team and u.kind == K.TOWER and u.lane_tier == tier and u.building_lane == lane:
			return u
	return null

var _next_tango := C.LONG_AGO

## Casting, channelling or walking to a cast target: let it finish rather than interrupt it.
func _busy(h: SimUnit) -> bool:
	return h.cast_phase != SimUnit.CastPhase.NONE or not h.channel.is_empty() \
		or h.order in [O.CAST_POINT, O.CAST_NO_TARGET, O.CAST_UNIT] and w.time < _cast_deadline

var _cast_deadline := C.LONG_AGO
var _lh_id := -1
var _lh_until := C.LONG_AGO
var _trade_id := -1
var _trade_until := C.LONG_AGO
var _next_trade := C.LONG_AGO

## Back to work by Town Portal: a bot at its base (healed, or just respawned) whose lane or farm is over 5000 away
## teleports to the allied building nearest it instead of walking for half a minute, as Dota's bots do.
func _tp_out(h: SimUnit, p: Vector2) -> bool:
	if p == Vector2.INF or h.pos.distance_to(w.map.fountains[h.team]) > 2600.0 or h.pos.distance_to(p) < 5000.0:
		return false
	if h.hp < h.max_hp * 0.8 or w.abilities.cast_error(h, "tp", -1, null, p) != "":
		return false
	_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": p}, true)
	_cast_deadline = w.time + 3.5
	return true

func _lane(h: SimUnit) -> void:
	if _busy(h):
		return
	var path := w.map.lane_path(lane, h.team)
	if h.pos.distance_to(w.map.fountains[h.team]) < 2600.0 and _tp_out(h, _front(h, [], path)):
		return
	var allies: Array[SimUnit] = []
	var foes: Array[SimUnit] = []
	var enemy_heroes: Array[SimUnit] = []
	var enemy_towers: Array[SimUnit] = []
	for u: SimUnit in w.query(h.pos, 1600.0):
		if not u.alive:
			continue
		if u.is_lane_creep():
			if u.team == h.team:
				allies.append(u)
			elif w.vision.sees(h.team, u):
				foes.append(u)
		elif u.is_hero() and u.team != h.team and w.vision.sees(h.team, u):
			enemy_heroes.append(u)
		elif u.kind == K.TOWER and u.team != h.team:
			enemy_towers.append(u)
	var spells := _spells_ok()
	if kit == "sludge" and spells:
		_sludge_stench(h, enemy_heroes, foes)
	# use a salve / tango when chipped (and nothing is about to die in front of us)
	if h.hp < h.max_hp * 0.6 and not _has_mod(h, "salve") and not _has_mod(h, "tango") and w.time >= _next_tango and bool(sk.spells):
		if h.hp < h.max_hp * 0.45 and _use_item(h, "salve"):
			_next_tango = w.time + 2.0
		elif _tango(h):
			_next_tango = w.time + 18.0
			_cast_deadline = w.time + 4.0
			return
	# 1. go for the kill when ahead: the enemy is low, or clearly weaker than us and away from their tower
	for e in enemy_heroes:
		var mine := h.hp / h.max_hp
		var theirs := e.hp / e.max_hp
		var safe := not _under_enemy_tower(h, e.pos, enemy_towers)
		var edge := (_boldness() - 1.0) * 0.25          # ahead in net worth: go in on smaller leads
		var winning := theirs < 0.3 + edge and mine > 0.4 or theirs < mine - 0.3 + edge and mine > 0.55 and h.level >= e.level
		if winning and (safe or theirs < 0.15) and h.pos.distance_to(e.pos) < 1100.0:
			if _spells_ok(e):
				_spells_on(h, e)
			if not _busy(h):
				_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
	# 2. no enemy hero around (none seen near for 3 s), or the team well ahead in net worth with none in sight: push
	# (the owner's rule). Kill the wave (last hits first, then the weakest creep), then hit the tower while our creeps
	# tank it (step 5). A support beside its core leaves the creeps to the core.
	var alone := enemy_heroes.is_empty() and _known.is_empty()
	var pushing := h.hp > h.max_hp * 0.5 and not _tower_on_me and enemy_heroes.is_empty() 		and (alone or _boldness() > 1.15)
	var shy := role >= 4 and _allies.any(func(a): return a.alive and a.pos.distance_to(h.pos) < 900.0)
	if pushing and not shy and _clear_wave(h, lane):
		return
	# 3. last hit / deny (melee heroes commit to the walk-up instead of second-guessing it every think)
	var committed := w.get_unit(_lh_id)
	if committed != null and committed.alive and w.time < _lh_until and h.order == O.ATTACK_UNIT and h.order_target == _lh_id:
		return
	var lh := _last_hit_target(h, foes, allies)
	if lh != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": lh.id})
		_lh_id = lh.id
		_lh_until = w.time + (1.3 if not h.is_ranged() else 0.0)
		return
	# 4. harass: melee heroes trade blows when the enemy hero wanders into reach; Blood Ranger pokes from range.
	# Sludge also throws the hook from range whenever the chain would reach the hero first. Supports harass more.
	if kit == "sludge" and spells:
		for e in enemy_heroes:
			if _spells_ok(e) and _sludge_hook(h, e, enemy_towers):
				return
			# a hero just dragged in (or standing at his side): fight it out while he is healthy enough
			if h.edge_distance(e) < 200.0 and h.hp > h.max_hp * 0.45 and not _under_enemy_tower(h, h.pos, enemy_towers):
				_trade_id = e.id
				_trade_until = w.time + 3.0
				if _spells_ok(e):
					_spells_on(h, e)
				if not _busy(h):
					_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
				return
	var trade_hp := 0.55 if role <= 3 else 0.45
	if not h.is_ranged():
		for e in enemy_heroes:
			var safe := not _under_enemy_tower(h, e.pos, enemy_towers) and not _under_enemy_tower(h, h.pos, enemy_towers)
			var healthy := h.hp > h.max_hp * trade_hp and h.hp / h.max_hp >= e.hp / e.max_hp - 0.15
			var trading := w.time < _trade_until and w.get_unit(_trade_id) == e
			# commit to a trade for a few seconds, then back off and let the cooldown run
			if safe and healthy and (trading or (h.edge_distance(e) <= 650.0 and w.time >= _next_trade)):
				if not trading:
					_trade_id = e.id
					_trade_until = w.time + 3.5
					_next_trade = w.time + (9.0 / _boldness())
				if _spells_ok(e):
					_spells_on(h, e)
				if not _busy(h):
					_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
				return
	for e in enemy_heroes:
		var exposed := _under_enemy_tower(h, h.pos, enemy_towers)
		# a free right click when the enemy hero stands in range and nothing needs last-hitting
		if not exposed and h.edge_distance(e) <= h.attack_range and h.atk_phase == SimUnit.AtkPhase.NONE \
				and w.time >= _next_trade and h.hp > h.max_hp * 0.5:
			_next_trade = w.time + 2.5
			_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
		if h.edge_distance(e) <= 1100.0 and h.mana > h.max_mana * (0.6 if role <= 3 else 0.4) and _spells_ok(e):
			_spells_on(h, e)
			if _busy(h):
				return
	# 5. push the tower when our creeps are tanking it (but never at the cost of a last hit coming up)
	var lh_near := false
	for f in foes:
		if h.edge_distance(f) < h.attack_range + 300.0 and f.hp < (h.dmg_min + h.bonus_damage) * 3.0:
			lh_near = true
	# early in the laning phase, or with an enemy hero close, a tower is not worth our health and last hits
	if _laning_phase(h) and (w.time < 300.0 or not enemy_heroes.is_empty()) and not pushing:
		lh_near = true
	for tw in enemy_towers:
		if tw.is_invulnerable() or lh_near:
			continue
		var tanking := w.get_unit(tw.atk_target)
		if tanking != null and tanking.team == h.team and not tanking.is_hero() and allies.size() >= (1 if pushing else 2):
			_order(h, {"type": O.ATTACK_UNIT, "target": tw.id})
			return
	# 6. stand behind the wave, just outside the enemies' reach
	var front := _front(h, allies, path)
	var spot := front
	var nearest_foe: SimUnit = null
	var nd := INF
	for f in foes:
		var d := f.pos.distance_to(h.pos)
		if d < nd:
			nd = d
			nearest_foe = f
	var back := (path[0] - front).normalized()
	if nearest_foe != null:
		var keep := maxf(h.attack_range * 0.85, 330.0) if not h.is_ranged() else h.attack_range * 0.85
		spot = nearest_foe.pos + (h.pos - nearest_foe.pos).normalized() * keep
		spot = spot.lerp(front + back * 300.0, 0.3)
	else:
		spot = front + back * 300.0
	# two heroes in one lane stand a little apart (the support beside and behind the core)
	if role >= 4:
		spot += back.orthogonal() * 180.0 + back * 120.0
	for tw in enemy_towers:
		if tw.pos.distance_to(spot) < tw.attack_range + tw.hull + 160.0:
			spot = tw.pos + (spot - tw.pos).normalized() * (tw.attack_range + tw.hull + 180.0)
	if h.pos.distance_to(spot) > 120.0:
		_go(h, spot)

## Where our wave is in this lane: the creep of ours furthest along it (anywhere in the lane, not just near us: the
## long safe lane's waves meet far from the tier 1 tower), held short of the enemy's front tower.
func _front(h: SimUnit, _allies: Array[SimUnit], path: PackedVector2Array) -> Vector2:
	var best: SimUnit = null
	var bi := -1.0
	for a in w.units:
		if not a.alive or a.team != h.team or not a.is_lane_creep() or a.lane != lane:
			continue
		var prog := _progress(a.pos, path)
		if prog > bi:
			bi = prog
			best = a
	if best == null:
		return _waiting_spot(h)
	var p := best.pos
	var et := brain().front_tower(1 - h.team, lane)
	if et != null and p.distance_to(et.pos) < et.attack_range + et.hull + 200.0:
		p = et.pos + (p - et.pos).normalized() * (et.attack_range + et.hull + 200.0)
	return p

func _progress(p: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	var acc := 0.0
	var res := 0.0
	for i in path.size() - 1:
		var cp := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		var d := cp.distance_to(p)
		if d < best:
			best = d
			res = acc + path[i].distance_to(cp)
		acc += path[i].distance_to(path[i + 1])
	return res

func _under_enemy_tower(h: SimUnit, p: Vector2, towers: Array[SimUnit]) -> bool:
	for tw in towers:
		if not tw.alive:
			continue
		if p.distance_to(tw.pos) <= tw.attack_range + tw.hull + h.hull + 60.0:
			return true
	return false

## A creep we can kill (or deny) with the next attack. For every unit hitting the creep we work out when its next hits
## land (what is left of its wind-up, its attack cooldown, its projectile's flight) and so the creep's health at the
## moment our own hit would land; we attack when that is above zero and at or below our least damage. Last hits come
## before denies. A support leaves the last hits to a core beside it and only denies. Easier bots misjudge the timing
## (sk.lh_error).
func _last_hit_target(h: SimUnit, foes: Array[SimUnit], allies: Array[SimUnit]) -> SimUnit:
	_creep_low = false
	var reach := h.attack_range + 250.0
	var core_near := false
	if role >= 4:
		for a in _allies:
			if a.pos.distance_to(h.pos) < 900.0 and int(brain().roles.get(a.id, 5)) <= 3:
				core_near = true
	var err := rng.randf_range(-float(sk.lh_error), float(sk.lh_error))
	var wait := maxf(0.0, h.next_attack_at - w.time)
	# commit only when our attack is (nearly) ready: earlier the creep's health is too uncertain
	if wait > 0.25:
		for c in foes:
			if c.alive and h.edge_distance(c) <= reach and c.hp <= h.dmg_min * 2.5:
				_creep_low = true
		return null
	var lh_soon := false
	for pass_i in 2:
		var best: SimUnit = null
		var best_margin := INF
		var list: Array[SimUnit] = foes if pass_i == 0 else allies
		if pass_i == 1 and lh_soon:
			break                          # keep the attack ready for the enemy creep about to be last-hittable
		for c in list:
			if not c.alive or h.edge_distance(c) > reach:
				continue
			if c.team == h.team and c.hp >= c.max_hp * 0.5:
				continue
			if c.team != h.team and core_near:
				continue
			var snap := {"hero": true, "class": h.weapon, "element": h.element}
			var mult := w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor)
			var my_min := (h.dmg_min + h.bonus_damage + (w.combat._quelling(h) if c.team != h.team else 0.0)) * mult
			if c.hp <= my_min * 2.5:
				_creep_low = true
			# when our hit would land: cooldown left, a turn, the walk into range, the wind-up, the arrow's flight
			var walk := maxf(0.0, h.edge_distance(c) - h.attack_range) / maxf(1.0, h.move_speed)
			var turn := absf(angle_difference(h.facing, (c.pos - h.pos).angle())) / maxf(0.1, h.turn_speed())
			var land := wait + turn + walk + h.attack_point_time() + 0.05
			if h.is_ranged():
				land += maxf(0.0, c.pos.distance_to(h.pos) - h.hull) / maxf(1.0, h.projectile_speed())
			var hp_then := _hp_when(c, maxf(0.0, land + err + lh_lead))
			if hp_then <= 0.0:
				continue
			if c.team != h.team and hp_then <= my_min * 1.8:
				lh_soon = true
			if hp_then <= my_min:
				var margin := my_min - hp_then
				if margin < best_margin:
					best_margin = margin
					best = c
		if best != null:
			return best
	return null

var _creep_low := false                    # a creep in reach is close to dying (think faster)
## Seconds added to when our hit lands, in the creep health forecast. Calibrated in the last-hit lab
## (tests/tools/lh_lab.gd, five heroes alone in mid for 8 minutes): -0.2 s took last hits from 17-31 to 37-47; the raw
## forecast fired too late. (Learning it per hero in games was tried and drifted towards 0 in contested lanes, which
## the lab shows halves last hits, so it stays fixed.)
var lh_lead := -0.2
var lh_bias := 0.5                         # where in their damage range the other attackers' hits are counted

## A creep's health `t` seconds from now, counting the hits already on their way and the next ones its attackers will
## land in that time.
func _hp_when(c: SimUnit, t: float) -> float:
	# a guard: an infinite time (a division by a zero projectile speed) once hung the game in the loop below
	if not is_finite(t):
		t = 30.0
	var hp := c.hp
	for o: SimUnit in w.query(c.pos, 1200.0):
		if not o.alive or o.atk_target != c.id or o == hero():
			continue
		# only attackers already in reach (one still walking up will not hit in time)
		if o.atk_phase != SimUnit.AtkPhase.WINDUP and o.edge_distance(c) > o.attack_range + 40.0:
			continue
		var avg := lerpf(o.dmg_min, o.dmg_max, lh_bias) + o.bonus_damage
		var snap := {"hero": o.is_hero(), "class": o.weapon, "element": o.element}
		var hit := avg * w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor)
		var fly := 0.0
		# a melee hero in a ranged form (Anomaly) has no projectile speed of his own: the form's counts
		if o.is_ranged() and o.projectile_speed() > 0.0:
			fly = maxf(0.0, o.pos.distance_to(c.pos) - o.hull) / o.projectile_speed()
		var first := 0.0
		if o.atk_phase == SimUnit.AtkPhase.WINDUP:
			first = o.atk_timer + fly
		else:
			first = maxf(0.0, o.next_attack_at - w.time) + o.attack_point_time() + fly
		var k := first
		while k < t:
			hp -= hit
			k += o.attack_interval()
	# arrows already in the air at it
	for pr in w.projectiles:
		if String(pr.kind) != "attack" or int(pr.target) != c.id:
			continue
		var eta := (pr.pos as Vector2).distance_to(c.pos) / maxf(1.0, float(pr.speed))
		var src := w.get_unit(int(pr.src))
		if eta < t and src != null:
			var snap2 := {"hero": src.is_hero(), "class": src.weapon, "element": src.element}
			hp -= ((src.dmg_min + src.dmg_max) * 0.5 + src.bonus_damage) * w.combat.attack_class_multiplier(snap2, c) 				* C.armor_multiplier(c.armor)
	return hp

# ---- Hero kits: combos ------------------------------------------------------------------------------------------------

func _spells_on(h: SimUnit, e: SimUnit) -> void:
	_fight_items(h, e)
	if kit == "ezee":
		_ezee_spells(h, e)
	elif kit == "sludge":
		_sludge_spells(h, e)
	elif kit == "azrin":
		_azrin_spells(h, e)
	elif kit == "froster":
		_froster_spells(h, e)
	elif kit == "caziel":
		_caziel_spells(h, e)
	elif kit == "tock":
		_tock_spells(h, e)
	elif kit == "kragg":
		_kragg_spells(h, e)
	elif SimBot16.handles(kit):
		SimBot16.spells(self, h, e)
	elif SimBot17.handles(kit):
		SimBot17.spells(self, h, e)
	elif SimBot18.handles(kit):
		SimBot18.spells(self, h, e)
	elif SimBot19.handles(kit):
		SimBot19.spells(self, h, e)
	else:
		_ranger_spells(h, e)

## Froster: Ice Pulse first (everything after it hits harder), the cold cone through the target, and the blizzard when
## two or more enemies are close or the target is slowed and near; then attacks to spend Frost Hearts.
func _froster_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var near := 0
	for f in _foes:
		if f.pos.distance_to(h.pos) < 520.0:
			near += 1
	var slowed := not e.get_modifier("breath_of_cold_slow").is_empty() or not e.get_modifier("frosted").is_empty() \
		or e.is_stunned()
	if ab.cast_error(h, "endless_winter", -1, null, h.pos) == "" and (near >= 2 or (slowed and d < 450.0)) \
			and h.hp > h.max_hp * 0.35:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "endless_winter"}, true)
		_cast_deadline = w.time + 7.5
		_spent()
		return
	if ab.cast_error(h, "ice_pulse", -1, e, e.pos) == "" and d < 700.0:
		_order(h, {"type": O.CAST_UNIT, "ability": "ice_pulse", "target": e.id}, true)
		_cast_deadline = w.time + 0.7
		_spent()
		return
	if ab.cast_error(h, "breath_of_cold", -1, null, e.pos) == "" and d < 760.0:
		_order(h, {"type": O.CAST_POINT, "ability": "breath_of_cold", "point": e.pos}, true)
		_cast_deadline = w.time + 0.7
		_spent()

## Tock: Stop Time on two or more enemies (or a lone target his team can reach), Time Bolt through the target, Slow
## Field under it, Fast Forward on the ally with the longest cooldowns (or himself), Rewind when badly hurt.
func _tock_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	if h.hp < h.max_hp * 0.3 and ab.cast_error(h, "rewind", -1, null, h.pos) == "":
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "rewind"}, true)
		_spent()
		return
	var near := 0
	for f in _foes:
		if f.pos.distance_to(e.pos) < 400.0:
			near += 1
	var helpers := 0
	for a in _allies:
		if a != h and a.pos.distance_to(e.pos) < 700.0:
			helpers += 1
	if ab.cast_error(h, "stop_time", -1, null, e.pos) == "" and d < 850.0 and (near >= 2 or helpers >= 1 or e.hp < e.max_hp * 0.55) \
			and not e.is_stunned():
		_order(h, {"type": O.CAST_POINT, "ability": "stop_time", "point": e.pos}, true)
		_cast_deadline = w.time + 0.7
		_spent()
		return
	if ab.cast_error(h, "time_bolt", -1, null, e.pos) == "" and d < 950.0:
		_order(h, {"type": O.CAST_POINT, "ability": "time_bolt", "point": e.pos}, true)
		_cast_deadline = w.time + 0.6
		_spent()
		return
	if ab.cast_error(h, "slow_field", -1, null, e.pos) == "" and d < 900.0 and not e.is_stunned():
		_order(h, {"type": O.CAST_POINT, "ability": "slow_field", "point": e.pos}, true)
		_cast_deadline = w.time + 0.6
		_spent()
		return
	if ab.cast_error(h, "fast_forward", -1, h, h.pos) == "":
		var best: SimUnit = h
		var most := -1.0
		for a in _allies:
			if not a.alive or a.pos.distance_to(h.pos) > 700.0:
				continue
			# Fast Forward cuts basic spells' cooldowns: give it to whoever waits longest on them
			var waiting := 0.0
			for aid in SimKits2.basic_spells(a):
				waiting += minf(ab.cooldown_left(a, aid), ab.val(h, "fast_forward", "cut"))
			if waiting > most:
				most = waiting
				best = a
		if most > 4.0:
			_order(h, {"type": O.CAST_UNIT, "ability": "fast_forward", "target": best.id}, true)
			_cast_deadline = w.time + 0.5
			_spent()

## Kragg: Iron Grip onto the target, Magnet Field when two or more enemies are near (or the grip landed), Repel when
## hurt or crowded. Overload is passive (every few attacks) and Magnetize innate.
func _kragg_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.edge_distance(e)
	var near := 0
	for f in _foes:
		if f.pos.distance_to(h.pos) < 650.0:
			near += 1
	if ab.cast_error(h, "magnet_field", -1, null, h.pos) == "" and (near >= 2 or (d < 250.0 and e.is_stunned())) \
			and h.hp > h.max_hp * 0.35:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "magnet_field"}, true)
		_cast_deadline = w.time + 0.5
		_spent()
		return
	if ab.cast_error(h, "iron_grip", -1, e, e.pos) == "" and d > 200.0 and d < ab.cast_range(h, "iron_grip", -1, e) + 20.0:
		_order(h, {"type": O.CAST_UNIT, "ability": "iron_grip", "target": e.id}, true)
		_cast_deadline = w.time + 0.6
		_spent()
		return
	if ab.cast_error(h, "repel", -1, null, h.pos) == "" and d < 300.0 and (near >= 2 or h.hp < h.max_hp * 0.5):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "repel"}, true)
		_cast_deadline = w.time + 0.5
		_spent()

## Caziel: Shadows when the fight starts, Swift Dagger onto the target (a gap closer and the opening stab), then his
## attacks do the rest (poison, and Death Order once it is low).
func _caziel_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.edge_distance(e)
	if ab.cast_error(h, "master_of_shadows", -1, null, h.pos) == "" and d < 900.0 and h.mana > 120.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "master_of_shadows"}, true)
		_spent()
	if ab.cast_error(h, "swift_dagger", -1, e, e.pos) == "" and d > 160.0 and d < 980.0:
		_order(h, {"type": O.CAST_UNIT, "ability": "swift_dagger", "target": e.id}, true)
		_cast_deadline = w.time + 0.4
		_spent()

## Azrin: Touch of Ember on the enemy (its own next spell will set it off), Fiery Javelin through it (leading a runner),
## the spirits once three or more circle her (or the enemy is low), and Divine Smite on a burning enemy to stretch the
## burns, or to finish it.
func _azrin_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	var lead := e.pos
	if e.moving:
		lead += Vector2.from_angle(e.facing) * e.move_speed * (0.35 + d / 2800.0) * float(sk.aim)
	var burning := not w.status.dots_on(e).is_empty()
	var smite_dmg := ab.val(h, "divine_smite", "damage") + ab.val(h, "divine_smite", "int_mult") * h.int_total
	var low := e.hp < smite_dmg * (1.0 - e.magic_resist) * 1.1
	if ab.cast_error(h, "divine_smite", -1, e, e.pos) == "" and d < 760.0 and (burning or low):
		_order(h, {"type": O.CAST_UNIT, "ability": "divine_smite", "target": e.id}, true)
		_cast_deadline = w.time + 1.0
		_spent()
		return
	if ab.cast_error(h, "touch_of_ember", -1, null, lead) == "" and h.pos.distance_to(lead) < 760.0:
		_order(h, {"type": O.CAST_POINT, "ability": "touch_of_ember", "point": lead}, true)
		_cast_deadline = w.time + 0.9
		_spent()
		return
	if ab.cast_error(h, "fiery_javelin", -1, null, lead) == "" and d < 950.0:
		# thrown past the enemy so it is caught early and dragged the whole way
		var aim := h.pos + (lead - h.pos).normalized() * 1000.0
		_order(h, {"type": O.CAST_POINT, "ability": "fiery_javelin", "point": aim}, true)
		_cast_deadline = w.time + 0.9
		_spent()
		return
	var n := ab.spirits(h)
	if n > 0 and ab.cast_error(h, "spirit_of_fire", -1, null, lead) == "" and h.pos.distance_to(lead) < 800.0 \
			and (n >= 3 or e.hp < e.max_hp * 0.35):
		_order(h, {"type": O.CAST_POINT, "ability": "spirit_of_fire", "point": lead}, true)
		_cast_deadline = w.time + 0.7
		_spent()

## Ezee: the ultimate when a real fight is on; Tainted Touch first (his blows then curse the target: it is revealed
## and seen, the mark Leap Strike follows); Dark Stomp up close (it throws enemies into walls and trees for the stun);
## Leap Strike last, and only when it is sure to land on the target and worth it (run 2026-10-18 h, the owner's rule):
## Leap Strike jumps on the visible enemy in range with the lowest health share (a hurt creep will do), so it is cast
## when the cursed target has lost a real share of its health (it is the one picked, and the blow can finish it), or
## when the target stands alone (no other enemy in reach to steal the leap) and is hurt or getting away.
func _ezee_spells(h: SimUnit, e: SimUnit) -> void:
	var d := h.edge_distance(e)
	var ab := w.abilities
	if ab.cast_error(h, "unholy_might", -1, null, h.pos) == "" and d < 450.0 and (e.hp < e.max_hp * 0.75 or h.hp < h.max_hp * 0.6):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "unholy_might"}, true)
		_cast_deadline = w.time + 1.0
		_spent()
		return
	if ab.cast_error(h, "tainted_touch", -1, null, h.pos) == "" and d < 450.0 and h.get_modifier("tainted_touch").is_empty():
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "tainted_touch"}, true)
		_cast_deadline = w.time + 0.8
		_spent()
		return
	if _ezee_leap_ok(h, e) and ab.cast_error(h, "leap_strike", -1, null, h.pos) == "":
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "leap_strike"}, true)
		_cast_deadline = w.time + 1.2
		_spent()
		leaps_cast += 1
		return
	if ab.cast_error(h, "dark_stomp", -1, null, h.pos) == "" and d < 260.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"}, true)
		_cast_deadline = w.time + 0.9
		_spent()
		return

var leaps_cast := 0                        # report counter (tests)

## Whether Leap Strike would land on `e` and is worth it now (see _ezee_spells).
func _ezee_leap_ok(h: SimUnit, e: SimUnit) -> bool:
	var ab := w.abilities
	if h.ability_level_of("leap_strike") <= 0 or ab.leap_target(h, h.ability_level_of("leap_strike")) != e:
		return false                           # it would jump on someone else (or nobody)
	var d := h.edge_distance(e)
	var frac := e.hp / maxf(1.0, e.max_hp)
	var lv := h.ability_level_of("leap_strike")
	var blow := ab.val(h, "leap_strike", "damage") + ab.val(h, "leap_strike", "str_mult") * h.str_total
	var finish := e.hp <= blow * 1.1 + h.dmg_max * 2.0
	var cursed := not e.get_modifier("tainted_curse").is_empty()
	# alone: no other enemy unit the leap could pick within its reach
	var alone := true
	for o: SimUnit in w.query(h.pos, ab.cast_range(h, "leap_strike", -1) + 200.0, true):
		if o != e and ab._ezee_can_hit(h, o) and w.vision.sees(h.team, o) and h.edge_distance(o) <= ab.cast_range(h, "leap_strike", -1):
			alone = false
			break
	var fleeing := e.moving and d > h.attack_range + 120.0
	if cursed and (frac < 0.55 or finish):
		return true
	if alone and (frac < 0.7 or finish or fleeing) and lv > 0:
		return true
	return false

## Sludge in a fight: Jump Knife in when Chomp is ready, Stench on, Blubber when he is being hit, Chomp in reach, the
## hook when it would land.
func _sludge_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.edge_distance(e)
	var jk := _jump_slot(h, e.pos)
	if jk >= 0 and d > 250.0 and d < 1100.0 and ab.cooldown_left(h, "chomp") <= 0.0 and h.ability_level_of("chomp") > 0 \
			and h.mana >= ab.ability_mana(h, "chomp") and h.hp > h.max_hp * 0.5:
		var land := e.pos + (h.pos - e.pos).normalized() * (h.hull + e.hull + 40.0)
		_order(h, {"type": O.CAST_POINT, "ability": "", "item_slot": jk, "point": land}, true)
		_cast_deadline = w.time + 0.6
		return
	if not bool(h.toggles.get("stench", false)) and h.ability_level_of("stench") > 0 and d < 300.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "stench"}, true)
	if ab.cast_error(h, "blubber", -1, null, h.pos) == "" and d < 500.0 and h.hp < h.max_hp * 0.8:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "blubber"}, true)
	if ab.cast_error(h, "chomp", -1, e, e.pos) == "" and d <= ab.cast_range(h, "chomp", -1) + 40.0:
		_order(h, {"type": O.CAST_UNIT, "ability": "chomp", "target": e.id}, true)
		_cast_deadline = w.time + 3.4
		_spent()
		return
	_sludge_hook(h, e, [])

## Throw the hook at an enemy hero, leading a moving one (less well on easier skills), but only when nothing else the
## chain could catch stands nearer along its line (the first unit touched is the one dragged), not into a fight under
## the enemy's tower, and (learned) not from distances that keep missing.
func _sludge_hook(h: SimUnit, e: SimUnit, towers: Array[SimUnit]) -> bool:
	var ab := w.abilities
	if ab.cast_error(h, "shuriken_hook", -1, null, e.pos) != "":
		return false
	var reach := ab.val(h, "shuriken_hook", "distance")
	var speed := ab.val(h, "shuriken_hook", "speed")
	var width := ab.val(h, "shuriken_hook", "width")
	var d := h.pos.distance_to(e.pos)
	if d > reach - 60.0 or d < 200.0:
		return false
	if _under_enemy_tower(h, e.pos, towers) and e.hp > e.max_hp * 0.3:
		return false
	if BotMemory.shot_rate("shuriken_hook", d, h.team) < 0.22:
		return false
	var lead := e.pos
	if e.moving:
		var t: float = float(SimData.ability("shuriken_hook").cast_point) + d / speed
		lead += Vector2.from_angle(e.facing) * e.move_speed * t * float(sk.aim)
	if h.pos.distance_to(lead) > reach - 40.0:
		return false
	var dir := (lead - h.pos).normalized()
	var to_t := (lead - h.pos).dot(dir)
	for o: SimUnit in w.query((h.pos + lead) * 0.5, to_t * 0.5 + width + 120.0, true):
		if o == e or o == h or not o.alive or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		if bool(o.def.get("ancient", false)) or o.is_invulnerable():
			continue
		var along := (o.pos - h.pos).dot(dir)
		if along < -o.hull or along > to_t:
			continue
		var cp := h.pos + dir * along
		if cp.distance_to(o.pos) <= width + o.hull + 25.0:
			return false                             # a creep or another hero would take the hook
	_order(h, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": h.pos + dir * minf(reach, to_t + 100.0)}, true)
	_cast_deadline = w.time + 0.8
	_shot = {"ability": "shuriken_hook", "dist": d, "t": w.time, "target": e.id}
	_spent()
	return true

## Stench on while an enemy hero is close or enemy creeps crowd him (it farms the wave), off otherwise and when low.
func _sludge_stench(h: SimUnit, enemy_heroes: Array[SimUnit], foes: Array[SimUnit]) -> void:
	if h.ability_level_of("stench") <= 0:
		return
	var r := w.abilities.val(h, "stench", "radius")
	# once on it stays on while targets are a little farther or fewer (it flipped 188 times in a 25-minute game)
	var on := bool(h.toggles.get("stench", false))
	var want := false
	for e in enemy_heroes:
		if h.edge_distance(e) < r + (220.0 if on else 60.0):
			want = true
	var crowd := 0
	for f in foes:
		if h.edge_distance(f) < r + (150.0 if on else 0.0):
			crowd += 1
	if crowd >= (2 if on else 3) and h.hp > h.max_hp * 0.5:
		want = true
	if h.hp < h.max_hp * 0.25 and enemy_heroes.is_empty():
		want = false
	if want != on and (w.time >= _stench_flip_at or h.hp < h.max_hp * 0.25):
		_stench_flip_at = w.time + 2.0
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "stench"}, true)

var _stench_flip_at := 0.0

## Blood Ranger: the ultimate when a fight is on, Gale Impact through the enemy (leading a running target), and
## Burst Shot into the enemy hero when few creeps stand around it to soak the arrows.
func _ranger_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.pos.distance_to(e.pos)
	if ab.cast_error(h, "blood_ranger_ult", -1, null, h.pos) == "" and d < h.attack_range + 350.0 \
			and (e.hp < e.max_hp * 0.6 or h.hp < h.max_hp * 0.5):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"}, true)
		_cast_deadline = w.time + 0.8
		_spent()
		return
	if ab.cast_error(h, "gale_impact", -1, null, e.pos) == "" and d < 1300.0:
		var lead := e.pos
		if e.moving:
			lead += Vector2.from_angle(e.facing) * e.move_speed * (0.3 + d / 2400.0) * float(sk.aim)
		var aim := h.pos + (lead - h.pos).normalized() * minf(2000.0, h.pos.distance_to(lead) + 250.0)
		_order(h, {"type": O.CAST_POINT, "ability": "gale_impact", "point": aim}, true)
		_cast_deadline = w.time + 1.0
		_spent()
		return
	if ab.cast_error(h, "burst_shot", -1, null, e.pos) == "" and d < ab.cast_range(h, "burst_shot", -1) + 100.0 and e.hp < e.max_hp * 0.85:
		var crowd := 0
		for o: SimUnit in w.query(e.pos, 400.0):
			if o.alive and o.team == e.team and not o.is_building() and o != e:
				crowd += 1
		if crowd <= 2 or e.hp < e.max_hp * 0.35:
			_order(h, {"type": O.CAST_POINT, "ability": "burst_shot", "point": e.pos}, true)
			_cast_deadline = w.time + 2.6
			_spent()

func _tango(h: SimUnit) -> bool:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == "tango" and not _has_mod(h, "tango"):
			var ti := w.map.tree_at(h.pos, 700.0)
			if ti >= 0:
				w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": i, "point": w.map.trees[ti].pos})
				return true
			return false
	return false

func _has_mod(h: SimUnit, mid: String) -> bool:
	for m in h.modifiers:
		if m.id == mid:
			return true
	return false

func _go(h: SimUnit, p: Vector2) -> void:
	var g := _gate_for(h, p)
	if not g.is_empty():
		if h.order != O.USE_SITE or h.order_gid != int(g.id):
			_order(h, {"type": O.USE_SITE, "site": int(g.id)}, true)
			site_uses["gate"] = int(site_uses.get("gate", 0)) + 1
		return
	_order(h, {"type": O.MOVE, "point": p})

## A move order without the Warp Gate detour.
func _go_direct(h: SimUnit, p: Vector2) -> void:
	_order(h, {"type": O.MOVE, "point": p})

## Re-issue an order only when it differs from the last one (players do not spam either).
func _order(h: SimUnit, o: Dictionary, force := false) -> void:
	var same: bool = not _last_order.is_empty() and _last_order.get("type") == o.get("type") and _last_order.get("target", -1) == o.get("target", -1)
	if same and o.get("type") == O.MOVE:
		same = (_last_order.point as Vector2).distance_to(o.point) < 100.0 and h.order == O.MOVE
	if same and o.get("type") == O.ATTACK_UNIT:
		same = h.order == O.ATTACK_UNIT and h.order_target == o.target
	if same and not force:
		return
	_last_order = o
	w.command(h.id, o)
	botlog.on_order(w.time, o, mode, ORDER_NAMES[clampi(int(o.get("type", 0)), 0, ORDER_NAMES.size() - 1)], w)
