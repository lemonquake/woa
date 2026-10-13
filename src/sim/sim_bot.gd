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
## error, spell lockouts; Unfair gets +25% gold and experience). With learning on (BotMemory) it uses and improves its
## fight model, retreat bar, item build choice, skill shot ranges and lane matchups.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const KITS = preload("res://src/sim/sim_bot_kits.gd")

## Dota's bot difficulties (Valve, research/bots.md section 6): think interval, spell reaction delay, last hit timing
## error (s), skill shot lead (0..1), spells allowed, stacking / pulling / warding, spell lockout every N s for M s,
## lockout after each use, gold and experience multiplier.
const SKILLS := {
	"passive": {"think": 0.45, "react": 9.0, "lh_error": 0.4, "aim": 0.0, "spells": false, "advanced": false,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gain": 1.0, "aggr": 0.0},
	"easy": {"think": 0.4, "react": 0.75, "lh_error": 0.4, "aim": 0.35, "spells": true, "advanced": false,
		"lock_every": 8.0, "lock_for": 6.0, "after_use": 6.0, "gain": 1.0, "aggr": 0.8},
	"medium": {"think": 0.3, "react": 0.45, "lh_error": 0.2, "aim": 0.7, "spells": true, "advanced": true,
		"lock_every": 10.0, "lock_for": 3.0, "after_use": 3.0, "gain": 1.0, "aggr": 0.9},
	"hard": {"think": 0.2, "react": 0.15, "lh_error": 0.0, "aim": 1.0, "spells": true, "advanced": true,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gain": 1.0, "aggr": 1.0},
	"unfair": {"think": 0.15, "react": 0.11, "lh_error": 0.0, "aim": 1.0, "spells": true, "advanced": true,
		"lock_every": 0.0, "lock_for": 0.0, "after_use": 0.0, "gain": 1.25, "aggr": 1.05},
}
const SKILL_IDS := ["passive", "easy", "medium", "hard", "unfair"]

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
var skill_order: Array = []
var build: Array = []
var build_idx := 0
var _build_i := 0
var rng := RandomNumberGenerator.new()
var mode := "lane"
var mode_since := C.LONG_AGO
var desires := {}                          # the last scores (debugging, tests)
var lane_foe := ""                         # the enemy hero it laned against (learning)
var lane_kills := 0
var lane_deaths := 0
var _next_think := C.LONG_AGO
var _last_order := {}
var _was_alive := true

func _init(world: SimWorld, hid: int, p_lane := "mid", p_name := "Bot", p_skill := "hard") -> void:
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
	var h := hero()
	if h != null:
		h.gain_mult = float(sk.gain)
	aggression = float(sk.aggr) * rng.randf_range(0.9, 1.12)

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

func hero() -> SimUnit:
	return w.get_unit(hero_id) if w != null else null

func _team() -> int:
	var h := hero()
	return h.team if h != null else -1

func brain() -> SimTeamAI:
	var h := hero()
	return w.brain(h.team) if h != null else null

func say(text: String, key := "", every := 30.0, urgent := false) -> void:
	var b := brain()
	if b != null:
		b.say(hero(), text, key, every, urgent)

# ---- Thinking ---------------------------------------------------------------------------------------------------------

func think() -> void:
	if w == null or w.time < _next_think or passive:
		return
	# a creep in reach close to dying: look again sooner (the better the bot, the sooner)
	var quick: bool = _creep_low and mode in ["lane", "farm"] and float(sk.lh_error) <= 0.2
	_next_think = w.time + (C.DT * 2.0 if quick else float(sk.think))
	var h := hero()
	if h == null:
		return
	h.bot = true
	h.auto_attack = false
	if not h.alive:
		if _was_alive:
			_on_death(h)
		_was_alive = false
		_dead(h)
		return
	_was_alive = true
	_learn(h)
	_shop(h)
	if bool(sk.spells):
		_items(h)
	_scan(h)
	_track_fight(h)
	_track_retreat(h)
	_track_lane(h)
	_track_shot(h)
	if _busy(h):
		# a Town Portal is only broken to save our life
		if not h.channel.is_empty() and String(h.channel.ability) == "tp" and _foes.size() > 0 \
				and _nearest(h, _foes).distance_to(h.pos) < 500.0 and h.hp < h.max_hp * 0.4:
			_go(h, _safe_point(h))
		return
	if w.time < 0.0:
		_pregame(h)
		return
	_choose_mode(h)
	_run_mode(h)

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
	d["retreat"] = _retreat_desire(h, task)
	d["heal"] = _heal_desire(h)
	var ft := _pick_fight(h)
	_fight_target = ft[0].id if ft[0] != null else -1
	d["fight"] = float(ft[1])
	if not task.is_empty() and String(task.kind) != "retreat":
		d["task"] = {"defend": 0.8, "gank": 0.78, "push": 0.62, "group": 0.6}.get(String(task.kind), 0.5)
	if _laning_phase(h):
		d["lane"] = 0.45
	else:
		d["farm"] = 0.4
	if bool(sk.advanced):
		d["stack"] = _stack_desire(h)
		d["pull"] = _pull_desire(h)
		d["ward"] = _ward_desire(h)
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
			say("Backing off, too dangerous.", "abort_%d" % int(t.id), 30.0)

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

## Laning: until 10:00 while the lane's tier 1 tower stands (cores keep farming their lane after that).
func _laning_phase(h: SimUnit) -> bool:
	if w.time >= 600.0:
		return false
	var t1 := _own_tower(h, 1)
	return t1 != null

# ---- Retreat and heal ---------------------------------------------------------------------------------------------------

func _retreat_bar() -> float:
	var base := 0.28 if role <= 3 else 0.33
	base += (1.0 - aggression) * 0.2
	return BotMemory.retreat_hp(kit, base, _team())

func _retreat_desire(h: SimUnit, task: Dictionary) -> float:
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
	if _tower_on_me and (not creeps_tank or hpf < 0.6):
		return 0.92
	if hpf < bar and (not _known.is_empty() or _tower_on_me):
		return 0.95
	if hpf < bar * 0.7:
		return 0.9
	if _threat > 1.7 and not _foes.is_empty() and _nearest(h, _foes).distance_to(h.pos) < 1000.0:
		return clampf(0.6 + (_threat - 1.7) * 0.3, 0.6, 0.9)
	if BotMemory.danger(h.team, h.pos) > 0.6 and hpf < bar + 0.2 and not _known.is_empty():
		return 0.8
	return 0.0

func _heal_desire(h: SimUnit) -> float:
	var hpf := h.hp / h.max_hp
	var mpf := h.mana / maxf(1.0, h.max_mana)
	var home := h.pos.distance_to(w.map.fountains[h.team]) < C.FOUNTAIN_AURA_RADIUS
	if home and (hpf < 0.9 or mpf < 0.7) and mode in ["heal", "retreat"]:
		return 0.75
	if hpf < 0.4 and not _has_item(h, "salve") and not _has_item(h, "tango") and not _has_mod(h, "salve"):
		return 0.62
	if mpf < 0.12 and role != 1 and h.max_mana > 300.0 and not _has_item(h, "clarity"):
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

func _run_retreat(h: SimUnit) -> void:
	var safe := _safe_point(h)
	var near_foe := _nearest(h, _foes)
	var fd := near_foe.distance_to(h.pos) if near_foe != Vector2.INF else INF
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
		if fd < 700.0:
			var jk := _ready_slot(h, "jump_knife", null, h.pos + (safe - h.pos).normalized() * 950.0)
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
	if fd > 1200.0 and h.pos.distance_to(w.map.fountains[h.team]) > 6000.0 and h.hp < h.max_hp * 0.3 and w.time > 240.0 \
			and not _has_item(h, "salve") and w.abilities.cast_error(h, "tp", -1, null, w.map.fountains[h.team]) == "":
		_order(h, {"type": O.CAST_POINT, "ability": "tp", "point": w.map.fountains[h.team]}, true)
		_cast_deadline = w.time + 3.5
		say("Going home to heal.", "tp_home_%d" % h.id, 60.0)
		return
	_go(h, safe)

## The kit's ways out: Blubber or Stench off for Sludge, Dark Stomp to throw chasers back for Ezee, Gale Impact into
## the chaser for Blood Ranger.
func _escape_spells(h: SimUnit, fd: float) -> bool:
	if not _spells_ok():
		return false
	var ab := w.abilities
	match kit:
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
	if h.pos.distance_to(home) > 5500.0 and _known.is_empty() and w.abilities.cast_error(h, "tp", -1, null, home) == "":
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
	var thresh := 0.58 - (aggression - 1.0) * 0.25
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
			say("Going for %s." % SimTeamAI.hero_label(e), "go_%d" % e.id, 20.0)
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
		say("Buying back to defend.", "bb_%d" % h.id, 60.0, true)

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
			if t != null and t.alive and w.vision.sees(h.team, t) and h.pos.distance_to(t.pos) < 1300.0:
				_run_fight(h, t)
			else:
				_go(h, where)
		"defend":
			_run_defend(h, t, where)
		"push":
			_run_push(h, t, String(task.lane))
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

func _run_push(h: SimUnit, t: SimUnit, p_lane: String) -> void:
	if t == null or not t.alive:
		_lane_or_farm(h)
		return
	# walk with the creeps: clear them, then hit the building while our creeps (or several heroes) are there
	if h.pos.distance_to(t.pos) > 1800.0:
		_go(h, t.pos + (w.map.fountains[h.team] - t.pos).normalized() * 1000.0)
		return
	for e in _foes:
		if BotMemory.fight_p(fight_features(h, e), h.team) > 0.5 and h.pos.distance_to(e.pos) < 1000.0:
			_run_fight(h, e)
			return
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
		return
	var best: SimUnit = null
	for c in _ecreeps:
		if best == null or c.hp < best.hp:
			best = c
	if best != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": best.id})
		return
	# wait for the next wave just outside the tower's reach
	_go(h, t.pos + (h.pos - t.pos).normalized() * (t.attack_range + t.hull + 220.0))

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
	for c in w.map.camps:
		if not b.camp_up(c.id) or b.camp_claimed_by_other(c.id, h.id):
			continue
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
		_farm_camp(h, pick_camp)
		return
	if pick != "":
		_farm_lane = pick
		_farm_lane_until = w.time + 6.0
		_farm_wave(h, pick)
		return
	_go(h, _waiting_spot(h))

var _farm_lane_until := C.LONG_AGO

func _farm_wave(h: SimUnit, ln: String) -> void:
	var old := lane
	lane = ln
	_lane(h)
	lane = old

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

## Whether the hero can clear a camp without dying: its damage against the camp's health, the camp's damage back.
func _can_clear(h: SimUnit, c: Dictionary) -> bool:
	var hp := 0.0
	var dps := 0.0
	for id in SimMap.CAMP_GROUPS[c.kind][0]:
		var d := SimData.unit(id)
		hp += float(d.hp)
		dps += (float(d.dmg_min) + float(d.dmg_max)) * 0.5 / float(d.get("bat", 2.0))
	var t := _clear_time(h, c)
	var taken := dps * t * 0.55 * C.armor_multiplier(h.armor)
	return taken < h.hp * 0.6 and (h.level >= {"small": 2, "medium": 4, "large": 6, "ancient": 10}.get(String(c.kind), 4) or role == 1 and h.level >= 3)

func _clear_time(h: SimUnit, c: Dictionary) -> float:
	var hp := 0.0
	for id in SimMap.CAMP_GROUPS[c.kind][0]:
		hp += float(SimData.unit(id).hp)
	var my := KITS.dps(w, h, null) * 0.85
	if kit == "sludge" and h.ability_level_of("stench") > 0:
		my += w.abilities.val(h, "stench", "dps") * 2.0
	return hp / maxf(10.0, my)

func _farm_camp(h: SimUnit, camp_id: int) -> void:
	var c: Dictionary = w.map.camps[camp_id]
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
	# AoE spells on a crowd, then the creep that hurts most (ranged) or the weakest
	var close := 0
	for n in ns:
		if n.pos.distance_to(h.pos) < 350.0:
			close += 1
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
					return
			"blood_ranger":
				if ns.size() >= 3 and h.mana > h.max_mana * 0.6 and ab.cast_error(h, "burst_shot", -1, null, c.pos) == "":
					var mid := Vector2.ZERO
					for n in ns:
						mid += n.pos
					_order(h, {"type": O.CAST_POINT, "ability": "burst_shot", "point": mid / ns.size()}, true)
					_cast_deadline = w.time + 2.6
					return
	var best: SimUnit = null
	for n in ns:
		if best == null or n.hp < best.hp:
			best = n
	_order(h, {"type": O.ATTACK_UNIT, "target": best.id})

# ---- Stacking, pulling, wards -------------------------------------------------------------------------------------------

var _stack := {}                           # {camp, phase, dir}: a stack or pull in progress

## Supports stack a camp near them at :53 when their lane can spare them (offlane support any time).
func _stack_desire(h: SimUnit) -> float:
	if role < 4 or w.time < 120.0:
		return 0.0
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
					say("Stacked the %s camp for %s." % [String(c.kind), b._name_of(core)], "stk_%d" % h.id, 120.0)
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
		say("Level 6, I can gank now.", "six_%d" % h.id, 9999.0)

var _said_six := false

func _wants(h: SimUnit, aid: String) -> bool:
	# follow the skill order: count how many times this ability appears before the current level
	var want := 0
	for i in mini(h.level, skill_order.size()):
		if skill_order[i] == aid:
			want += 1
	return h.ability_level_of(aid) < want

var _situational_at := 480.0

func _shop(h: SimUnit) -> void:
	# at 8, 15 and 25 minutes: move an item the game calls for to the front of the list
	if w.time >= _situational_at:
		_situational_at = {480.0: 900.0, 900.0: 1500.0}.get(_situational_at, INF)
		_situational(h)
	var guard := 0
	while _build_i < build.size() and guard < 6:
		guard += 1
		var id: String = build[_build_i]
		var d := SimData.item(id)
		if w.shop.owns(h, id) and (not (d.components as Array).is_empty() or id == "jump_knife"):
			_build_i += 1
			continue
		if w.shop.buy_error(h, id) != "":
			break
		var cost := w.shop.price(h, id)
		if h.gold() < cost:
			break
		var err := w.shop.buy(h, id)
		if err != "" and err != "Not enough gold":
			_build_i += 1
			continue
		if err == "":
			_build_i += 1
			if KITS.power_spike(h, id):
				say("Got my %s." % String(d.get("name", id)), "item_%d_%s" % [h.id, id], 9999.0)
	# away from the shop, the courier brings what is waiting in the stash
	if (h.stash.any(func(x): return x != null) or h.courier_items.any(func(x): return x != null)) and not w.shop.in_shop(h):
		var c := w.get_unit(h.courier_id)
		if c and c.alive and c.courier_state == "idle":
			w.courier_deliver(h)
	if h.tp_charges == 0 and h.gold() >= 100 and w.time > -60.0:
		w.shop.buy(h, "tp_scroll")
	# supports carry an Eye Ward (free) from the start
	if role >= 4 and bool(sk.advanced) and _ward_slot(h) < 0 and w.time - _last_ward_buy > 150.0 and w.shop.in_shop(h):
		if w.shop.buy(h, "observer_ward") == "":
			_last_ward_buy = w.time
	# out of healing in lane: one more Healing Paste (the courier brings it)
	if h.hp < h.max_hp * 0.5 and w.time < 900.0 and not _has_item(h, "salve") and h.gold() >= 100 \
			and w.time - _last_salve_buy > 40.0 and not h.stash.any(func(x): return x != null and x.id == "salve"):
		if w.shop.buy(h, "salve") == "":
			_last_salve_buy = w.time
	# drink a salve when hurt and not in the fountain
	if h.hp < h.max_hp * 0.55 and bool(sk.spells):
		_use_item(h, "salve")

var _last_ward_buy := C.LONG_AGO
var _last_salve_buy := C.LONG_AGO

## Items the game calls for: a Spell Shield early against two or more disablers, Spike Armor for a strength hero
## against a fed right-clicker, a Push Staff for a support whose cores keep dying.
func _situational(h: SimUnit) -> void:
	var disablers := 0
	var fed: SimUnit = null
	for e in w.heroes:
		if e.team == h.team:
			continue
		if KITS.disable_power(String(e.def.id)) >= 0.6:
			disablers += 1
		if KITS.backliner(String(e.def.id)) and (fed == null or e.networth() > fed.networth()):
			fed = e
	var want := ""
	if disablers >= 2 and role <= 3 and not w.shop.owns(h, "spell_shield"):
		want = "spell_shield"
	elif fed != null and fed.networth() > h.networth() * 1.3 and String(h.def.primary) == "str" and not w.shop.owns(h, "spike_armor"):
		want = "spike_armor"
	if want == "" or _build_i >= build.size():
		return
	var i := build.find(want)
	if i > _build_i:
		build.remove_at(i)
		build.insert(_build_i, want)
	elif i < 0:
		build.insert(_build_i, want)

func _has_item(h: SimUnit, id: String) -> bool:
	for i in 6:
		var it = h.inventory[i]
		if it != null and it.id == id:
			return true
	return false

## The main slot holding an item whose active can be used now (no error), or -1.
func _ready_slot(h: SimUnit, item_id: String, t: SimUnit = null, p := Vector2.INF) -> int:
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
	var ms := _ready_slot(h, "mana_boots")
	if ms >= 0 and h.max_mana - h.mana >= 160.0:
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": ms})
	var mk := _ready_slot(h, "medic_kit")
	if mk >= 0 and (h.hp < h.max_hp * 0.6 or _ally_hurt_near(h, 750.0)):
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": mk})
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

func _ally_hurt_near(h: SimUnit, r: float) -> bool:
	for a in _allies:
		if a.pos.distance_to(h.pos) < r and a.hp < a.max_hp * 0.5:
			return true
	return false

## Fight items, used when going after an enemy hero: Spell Shield, Frenzy Mask, Slip Boots to close in.
func _fight_items(h: SimUnit, e: SimUnit) -> void:
	var d := h.edge_distance(e)
	var bkb := _ready_slot(h, "spell_shield")
	if bkb >= 0 and d < 500.0 and (h.hp < h.max_hp * 0.75 or e.hp < e.max_hp * 0.5 or _foes.size() >= 2):
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

func _use_item(h: SimUnit, item_id: String) -> bool:
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

func _lane(h: SimUnit) -> void:
	if _busy(h):
		return
	var path := w.map.lane_path(lane, h.team)
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
		var winning := theirs < 0.3 and mine > 0.4 or theirs < mine - 0.3 and mine > 0.55 and h.level >= e.level
		if winning and (safe or theirs < 0.15) and h.pos.distance_to(e.pos) < 1100.0:
			if _spells_ok(e):
				_spells_on(h, e)
			if not _busy(h):
				_order(h, {"type": O.ATTACK_UNIT, "target": e.id})
			return
	# 2. last hit / deny (melee heroes commit to the walk-up instead of second-guessing it every think)
	var committed := w.get_unit(_lh_id)
	if committed != null and committed.alive and w.time < _lh_until and h.order == O.ATTACK_UNIT and h.order_target == _lh_id:
		return
	var lh := _last_hit_target(h, foes, allies)
	if lh != null:
		_order(h, {"type": O.ATTACK_UNIT, "target": lh.id})
		_lh_id = lh.id
		_lh_until = w.time + (1.3 if not h.is_ranged() else 0.0)
		return
	# 3. harass: melee heroes trade blows when the enemy hero wanders into reach; Blood Ranger pokes from range.
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
					_next_trade = w.time + (9.0 / aggression)
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
	# 4. push the tower when our creeps are tanking it (but never at the cost of a last hit coming up)
	var lh_near := false
	for f in foes:
		if h.edge_distance(f) < h.attack_range + 300.0 and f.hp < (h.dmg_min + h.bonus_damage) * 3.0:
			lh_near = true
	# early in the laning phase, or with an enemy hero close, a tower is not worth our health and last hits
	if _laning_phase(h) and (w.time < 300.0 or not enemy_heroes.is_empty()):
		lh_near = true
	for tw in enemy_towers:
		if tw.is_invulnerable() or lh_near:
			continue
		var tanking := w.get_unit(tw.atk_target)
		if tanking != null and tanking.team == h.team and not tanking.is_hero() and allies.size() >= 2:
			_order(h, {"type": O.ATTACK_UNIT, "target": tw.id})
			return
	# 5. stand behind the wave, just outside the enemies' reach
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
			var snap := {"hero": true, "class": int(h.def.attack_class)}
			var mult := w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor)
			var my_min := (h.dmg_min + h.bonus_damage + (w.combat._quelling(h) if c.team != h.team else 0.0)) * mult
			if c.hp <= my_min * 2.5:
				_creep_low = true
			# when our hit would land: cooldown left, a turn, the walk into range, the wind-up, the arrow's flight
			var walk := maxf(0.0, h.edge_distance(c) - h.attack_range) / maxf(1.0, h.move_speed)
			var turn := absf(angle_difference(h.facing, (c.pos - h.pos).angle())) / maxf(0.1, h.turn_speed())
			var land := wait + turn + walk + h.attack_point_time() + 0.05
			if h.is_ranged():
				land += maxf(0.0, c.pos.distance_to(h.pos) - h.hull) / float(h.def.projectile_speed)
			var hp_then := _hp_when(c, maxf(0.0, land + err))
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

## A creep's health `t` seconds from now, counting the hits already on their way and the next ones its attackers will
## land in that time.
func _hp_when(c: SimUnit, t: float) -> float:
	var hp := c.hp
	for o: SimUnit in w.query(c.pos, 1200.0):
		if not o.alive or o.atk_target != c.id or o == hero():
			continue
		# only attackers already in reach (one still walking up will not hit in time)
		if o.atk_phase != SimUnit.AtkPhase.WINDUP and o.edge_distance(c) > o.attack_range + 40.0:
			continue
		var avg := (o.dmg_min + o.dmg_max) * 0.5 + o.bonus_damage
		var snap := {"hero": o.is_hero(), "class": int(o.def.attack_class)}
		var hit := avg * w.combat.attack_class_multiplier(snap, c) * C.armor_multiplier(c.armor)
		var fly := 0.0
		if o.is_ranged() and float(o.def.get("projectile_speed", 0.0)) > 0.0:
			fly = maxf(0.0, o.pos.distance_to(c.pos) - o.hull) / float(o.def.projectile_speed)
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
			var snap2 := {"hero": src.is_hero(), "class": int(src.def.attack_class)}
			hp -= ((src.dmg_min + src.dmg_max) * 0.5 + src.bonus_damage) * w.combat.attack_class_multiplier(snap2, c) 				* C.armor_multiplier(c.armor)
	return hp

# ---- Hero kits: combos ------------------------------------------------------------------------------------------------

func _spells_on(h: SimUnit, e: SimUnit) -> void:
	_fight_items(h, e)
	if kit == "ezee":
		_ezee_spells(h, e)
	elif kit == "sludge":
		_sludge_spells(h, e)
	else:
		_ranger_spells(h, e)

## Ezee: the ultimate when a real fight is on, Leap Strike onto the hero it would pick, Dark Stomp up close (it throws
## enemies into walls and trees for the stun), Tainted Touch before the blows land.
func _ezee_spells(h: SimUnit, e: SimUnit) -> void:
	var d := h.edge_distance(e)
	var ab := w.abilities
	if ab.cast_error(h, "unholy_might", -1, null, h.pos) == "" and d < 450.0 and (e.hp < e.max_hp * 0.75 or h.hp < h.max_hp * 0.6):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "unholy_might"}, true)
		_cast_deadline = w.time + 1.0
		_spent()
		return
	var keen := e.hp < e.max_hp * 0.6 or h.hp > h.max_hp * 0.75
	if keen and ab.cast_error(h, "leap_strike", -1, null, h.pos) == "" and ab.leap_target(h, h.ability_level_of("leap_strike")) == e and d > 150.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "leap_strike"}, true)
		_cast_deadline = w.time + 1.2
		_spent()
		return
	if ab.cast_error(h, "dark_stomp", -1, null, h.pos) == "" and d < 260.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"}, true)
		_cast_deadline = w.time + 0.9
		_spent()
		return
	if ab.cast_error(h, "tainted_touch", -1, null, h.pos) == "" and d < 400.0:
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "tainted_touch"}, true)
		_cast_deadline = w.time + 0.8
		_spent()

## Sludge in a fight: Jump Knife in when Chomp is ready, Stench on, Blubber when he is being hit, Chomp in reach, the
## hook when it would land.
func _sludge_spells(h: SimUnit, e: SimUnit) -> void:
	var ab := w.abilities
	var d := h.edge_distance(e)
	var jk := _ready_slot(h, "jump_knife", null, e.pos)
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
	var want := false
	for e in enemy_heroes:
		if h.edge_distance(e) < r + 60.0:
			want = true
	var crowd := 0
	for f in foes:
		if h.edge_distance(f) < r:
			crowd += 1
	if crowd >= 3 and h.hp > h.max_hp * 0.5:
		want = true
	if h.hp < h.max_hp * 0.25 and enemy_heroes.is_empty():
		want = false
	if want != bool(h.toggles.get("stench", false)):
		_order(h, {"type": O.CAST_NO_TARGET, "ability": "stench"}, true)

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
	var a := SimData.ability("burst_shot")
	if ab.cast_error(h, "burst_shot", -1, null, e.pos) == "" and d < float(a.range) + 100.0 and e.hp < e.max_hp * 0.85:
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
