class_name SimBot19
extends RefCounted
## How bots play Araki, the Blur (run 2026-10-19 c). Called by SimBot: spells() in fights and trades, escape() while
## running, aoe_farm() on creep packs, tick() every think. All static: `b` is the SimBot whose hero acts. The shared cast
## helpers are SimBot18's.
##
## Fights (the order of the combo matters):
##   1. The Blur first when he commits (a fight he can win or a kill in reach): every later Blur Strike and Djin Bomb
##      comes back twice as fast, and his first attacks are much faster.
##   2. Ghosts of the Will on the enemy near the target with the most Senryukai stacks (every stack is in each ghost's
##      blow), cast before the mana goes on the rest: they fly out one by one and land with the dash. Also on a fleeing
##      target he cannot reach in time.
##   3. Djin Bomb on the target (leading it), placed to cover as many enemy heroes as it can, before the magic damage
##      (it cuts magic resistance) and before allies' stuns (it cuts status resistance); never on a cloud of his own.
##   4. Blur Strike along the line that slashes the most (heroes count most, the target most of all), ending just past
##      the target so he can hit it; not into an enemy tower unless the kill is there. The refresh then slashes back
##      through them, or is kept to get away when he is low and the fight is not his.
## Mana: one Blur Strike is kept back (his way out) when the fight can turn on him, unless the kill is in reach.
## Lane trades: a dash through the enemy hero and its creeps (the creeps make sure of the refresh), then the second
## dash back home: a free hit and out. Farming: through three or more creeps (two big camp creeps), then back again.
## Running: Blur Strike toward safety, bent to pass through an enemy unit when one is close to the line (the refresh
## gives a second dash), the bomb on the chasers.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const B18 = preload("res://src/sim/sim_bot18.gd")
const KITS := ["araki"]

static func handles(kit: String) -> bool:
	return kit in KITS

# ---- Reading the fight ----------------------------------------------------------------------------------------------

## An enemy tower that would shoot at `p` (the kill excuses it).
static func _tower_at(w: SimWorld, team: int, p: Vector2) -> bool:
	for u in w.units:
		if u.alive and u.kind == K.TOWER and u.team != team and p.distance_to(u.pos) <= u.attack_range + u.hull + 90.0:
			return true
	return false

## What his ready spells and a few seconds of attacks would do to `e` (SimBotKits.burst plus attacks).
static func _kill_in_reach(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	var dmg := SimBotKits.burst(b.w, h, e) + SimBotKits.dps(b.w, h, e) * 3.0
	return dmg > e.hp * 1.05

## Dash end for a line from `from` toward `aim`, ending `past` beyond it (Blur Strike's own limits).
static func _dash_dest(b: SimBot, h: SimUnit, from: Vector2, aim: Vector2, past: float) -> Vector2:
	var ab := b.w.abilities
	var dir := aim - from
	if dir.length() < 1.0:
		dir = Vector2.from_angle(h.facing)
	var dist := clampf(dir.length() + past, ab.val(h, "blur_strike", "min_distance"), ab.val(h, "blur_strike", "distance"))
	return ab.kits7.dash_end(from, dir.normalized(), dist)

## Mana kept back for one Blur Strike (his way out) unless the kill is in reach: his pool is small (about 290 at level
## 1) and in run 2026-10-19 c's games he spent it all on a dash, its refresh and the bomb, then died at 8% health with
## his escape on 9% mana.
static func _can_spend(b: SimBot, h: SimUnit, aid: String, kill: bool) -> bool:
	var ab := b.w.abilities
	var cost := ab.ability_mana(h, aid)
	if kill:
		return h.mana >= cost
	# safe (healthy, not outmatched): spend freely; the reserve is for fights that can turn on him
	if h.hp > h.max_hp * 0.6 and b._threat < 0.9:
		return h.mana >= cost
	var keep := ab.ability_mana(h, "blur_strike") if h.ability_level_of("blur_strike") > 0 else 0.0
	return h.mana >= cost + keep

## How good a dash from his spot to `to` is: heroes count 10 (the target 16), creeps and summons 1, ghosts nothing.
static func _line_score(b: SimBot, h: SimUnit, to: Vector2, target: SimUnit) -> float:
	var ab := b.w.abilities
	var s := 0.0
	for o: SimUnit in ab.kits7.strike_targets(h.team, h.pos, to, ab.val(h, "blur_strike", "radius") * 0.9):
		if o == target:
			s += 16.0
		elif o.is_hero():
			s += 10.0
		elif not ab.kits7.is_ghost(o):
			s += 1.0
	return s

## The best Blur Strike at `e`: straight through it ending a little past, or bent to catch another enemy hero along
## with it. Returns the cast point, or Vector2.INF when no line reaches it.
static func _best_strike(b: SimBot, h: SimUnit, e: SimUnit, past: float) -> Vector2:
	var aim := B18._lead(b, e, 0.12)
	var best := Vector2.INF
	var bs := 0.0
	var cands: Array[Vector2] = [aim]
	for f in b._foes:
		if f != e and f.alive and f.pos.distance_to(e.pos) < 500.0:
			cands.append(aim.lerp(f.pos, 0.5))
			cands.append(f.pos)
	for c in cands:
		var to := _dash_dest(b, h, h.pos, c, past)
		var sc := _line_score(b, h, to, e)
		if sc < 16.0:
			continue                                   # the target must be on the line
		if sc > bs:
			bs = sc
			best = to
	return best

# ---- Fights ---------------------------------------------------------------------------------------------------------

static func spells(b: SimBot, h: SimUnit, e: SimUnit) -> void:
	var w := b.w
	var ab := w.abilities
	var k7 := ab.kits7
	var d := h.pos.distance_to(e.pos)
	var on := B18._fight_on(b, h, e)
	var kill := _kill_in_reach(b, h, e)
	var low := h.hp < h.max_hp * 0.35
	var commit := (on or kill) and not (low and b._threat > 1.1 and not kill)
	# levels 1-2: a 50 damage dash wins nothing on its own; only for a kill
	if h.level < 3 and not kill:
		commit = false
	# 1. The Blur when he commits and the target is close
	if commit and d < 750.0 and h.hp > h.max_hp * 0.3 and ab.cast_error(h, "the_blur", -1, null, h.pos) == "":
		var spells_up := ab.cooldown_left(h, "blur_strike") <= 0.0 or ab.cooldown_left(h, "djin_bomb") <= 0.0
		if spells_up or h.edge_distance(e) < h.attack_range + 80.0 or B18._foes_near(b, h.pos, 900.0) >= 2:
			if B18._cast_none(b, h, "the_blur", 0.05):
				b.say("Too slow.", "blur_%d" % h.id, 60.0)
				return
	# 2. Ghosts of the Will next, before the mana goes on the bomb and the dashes: they fly out one by one, so cast
	# now they land with the dash, and every stack the dash adds is in their blows (run 2026-10-19 c: cast last, the
	# mana was gone and they flew once in 20 minutes)
	if commit and d < ab.cast_range(h, "ghosts_of_the_will", -1, e) + 60.0 and _can_spend(b, h, "ghosts_of_the_will", kill) 			and _ghosts(b, h, e):
		return
	# 3. Djin Bomb before the magic damage and the stuns
	if commit and _can_spend(b, h, "djin_bomb", kill) and _bomb(b, h, e):
		return
	# 4. Blur Strike: the second dash first (it runs out), then a fresh one
	if k7.strike_again(h):
		if low and not kill and b._threat > 0.9:
			return                                     # kept to get away (escape uses it)
		if d < ab.val(h, "blur_strike", "distance") + 120.0:
			var p := _best_strike(b, h, e, 160.0)
			if p != Vector2.INF and (kill or not _tower_at(w, h.team, p)) and B18._cast_point(b, h, "blur_strike", p, 0.25):
				return
	elif d < ab.val(h, "blur_strike", "distance") + 150.0 and ab.cast_error(h, "blur_strike", -1, null, e.pos) == "":
		# the first dash only with mana for the second too (it is his way out), unless it kills
		var go := (commit and _can_spend(b, h, "blur_strike", kill)) or (kill and e.moving and d > h.attack_range + 120.0)
		if go:
			var p := _best_strike(b, h, e, 160.0)
			if p != Vector2.INF and (kill or not _tower_at(w, h.team, p)) and B18._cast_point(b, h, "blur_strike", p, 0.25):
				return
		elif b.mode == "lane" and _lane_poke(b, h, e):
			return
	# 5. Ghosts of the Will on a runner he cannot catch
	if e.hp < e.max_hp * 0.3 and e.moving and _can_spend(b, h, "ghosts_of_the_will", kill) and _ghosts(b, h, e):
		return

## Djin Bomb on the target, leading it, shifted to cover more enemy heroes; not on a cloud of his own.
static func _bomb(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	var ab := b.w.abilities
	if ab.cast_error(h, "djin_bomb", -1, null, e.pos) != "":
		return false
	var r := ab.val(h, "djin_bomb", "radius")
	var c := B18._lead(b, e, ab.val(h, "djin_bomb", "throw_time") + 0.5)
	for cl in ab.kits7.clouds():
		if int(cl[2]) == h.team and (cl[0] as Vector2).distance_to(c) < float(cl[1]) * 0.7:
			return false
	# pull the centre toward other enemy heroes within reach of the cloud (the target stays well inside)
	var sum := c * 2.0
	var n := 2.0
	for f in b._foes:
		if f != e and f.alive and f.pos.distance_to(c) < r * 1.3:
			sum += f.pos
			n += 1.0
	var at := sum / n
	if at.distance_to(c) > r * 0.55:
		at = c + (at - c).normalized() * r * 0.55
	if h.pos.distance_to(at) > ab.cast_range(h, "djin_bomb", -1) + 80.0:
		return false
	return B18._cast_point(b, h, "djin_bomb", at, 0.35)

## Ghosts of the Will on the enemy hero near the target with the most Senryukai stacks (the target on a tie).
static func _ghosts(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	var ab := b.w.abilities
	if h.ability_level_of("ghosts_of_the_will") <= 0 or ab.cooldown_left(h, "ghosts_of_the_will") > 0.0:
		return false
	var best := e
	var bs := float(ab.kits7.stacks_on(h, e)) + 0.5
	for f in b._foes:
		if f == e or not f.alive or f.pos.distance_to(h.pos) > ab.cast_range(h, "ghosts_of_the_will", -1, f):
			continue
		var s := float(ab.kits7.stacks_on(h, f)) + (3.0 if f.hp < f.max_hp * 0.3 else 0.0)
		if s > bs:
			bs = s
			best = f
	return B18._cast_unit(b, h, "ghosts_of_the_will", best, 0.4)

## A lane poke: dash through the enemy hero when its creeps sit on the line too (the refresh is sure), with mana to spare
## and no tower at the end; the second dash (tick) takes him home.
static func _lane_poke(b: SimBot, h: SimUnit, e: SimUnit) -> bool:
	var ab := b.w.abilities
	if h.level < 3 or h.mana < ab.ability_mana(h, "blur_strike") * 2.0 + 40.0 or h.hp < h.max_hp * 0.6:
		return false
	var to := _dash_dest(b, h, h.pos, e.pos, 80.0)
	if _tower_at(b.w, h.team, to) or _line_score(b, h, to, e) < 17.0:
		return false
	if B18._cast_point(b, h, "blur_strike", to, 0.25):
		b.botlog.add(b.w.time, "think", "araki lane poke")
		return true
	return false

## The second dash home: from where he stands toward safety, through the enemies again when the line allows.
static func _dash_home(b: SimBot, h: SimUnit) -> bool:
	var safe := b._safe_point(h)
	var dir := (safe - h.pos)
	if dir.length() < 1.0:
		return false
	return B18._cast_point(b, h, "blur_strike", h.pos + dir.normalized() * 600.0, 0.25)

# ---- Running --------------------------------------------------------------------------------------------------------

static func escape(b: SimBot, h: SimUnit, fd: float) -> bool:
	if not b._spells_ok():
		return false
	var w := b.w
	var ab := w.abilities
	var chaser: SimUnit = null
	for f in b._foes:
		if f.alive and (chaser == null or f.pos.distance_to(h.pos) < chaser.pos.distance_to(h.pos)):
			chaser = f
	if fd < 900.0 and ab.cast_error(h, "blur_strike", -1, null, h.pos) == "" and not h.is_rooted():
		var safe := b._safe_point(h)
		var base := (safe - h.pos).normalized() if safe.distance_to(h.pos) > 1.0 else Vector2.from_angle(h.facing)
		# bend the line (up to 45 degrees) through an enemy unit for the refresh when one is near it
		var best := base
		var bs := -INF
		for k in [0.0, -0.4, 0.4, -0.8, 0.8]:
			var dir := base.rotated(k)
			var to := ab.kits7.dash_end(h.pos, dir, ab.val(h, "blur_strike", "distance"))
			var hits := ab.kits7.strike_targets(h.team, h.pos, to, ab.val(h, "blur_strike", "radius") * 0.85)
			var sc := -absf(k) * 2.0 + (3.0 if not hits.is_empty() else 0.0) + to.distance_to(h.pos) / 300.0
			if chaser != null:
				sc += (to.distance_to(chaser.pos) - h.pos.distance_to(chaser.pos)) / 200.0
			if sc > bs:
				bs = sc
				best = dir
		if B18._cast_point(b, h, "blur_strike", h.pos + best * 600.0, 0.2):
			return true
	# the bomb on the chasers only when it does not cost the dash (or the dash is down anyway)
	var dash_up := ab.cooldown_left(h, "blur_strike") <= 0.0 or ab.kits7.strike_again(h)
	if chaser != null and fd < 550.0 and ab.cast_error(h, "djin_bomb", -1, null, chaser.pos) == "" \
			and (not dash_up or _can_spend(b, h, "djin_bomb", false)) \
			and B18._cast_point(b, h, "djin_bomb", chaser.pos, 0.25):
		return true
	return false

# ---- Farming --------------------------------------------------------------------------------------------------------

static func aoe_farm(b: SimBot, h: SimUnit, ns: Array[SimUnit], _centre: Vector2) -> bool:
	if not b._spells_ok() or ns.is_empty():
		return false
	var ab := b.w.abilities
	if ab.cast_error(h, "blur_strike", -1, null, h.pos) != "":
		return false
	var again := ab.kits7.strike_again(h)
	# the mana for a fight stays: Blur Strike and Ghosts of the Will, unless the refresh is free to use
	var keep := ab.ability_mana(h, "ghosts_of_the_will") + ab.ability_mana(h, "blur_strike")
	if not again and h.mana < keep + ab.ability_mana(h, "blur_strike") and h.mana < h.max_mana * 0.6:
		return false
	var best := Vector2.INF
	var bn := 0.0
	for n in ns:
		if not n.alive or n.pos.distance_to(h.pos) > 750.0:
			continue
		var to := _dash_dest(b, h, h.pos, n.pos, 150.0)
		if _tower_at(b.w, h.team, to):
			continue
		var cnt := 0.0
		for o: SimUnit in ab.kits7.strike_targets(h.team, h.pos, to, ab.val(h, "blur_strike", "radius") * 0.9):
			cnt += 2.0 if o.max_hp >= 900.0 else 1.0
		if cnt > bn:
			bn = cnt
			best = to
	if best == Vector2.INF or bn < (2.0 if again else 3.0):
		return false
	return B18._cast_point(b, h, "blur_strike", best, 0.25)

# ---- Every think ----------------------------------------------------------------------------------------------------

## True when it gave an order that should stand this think. The refresh is never wasted: in a fight spells() uses it;
## running, escape() does; in lane it brings him home after a poke; farming, it goes back through the creeps.
static func tick(b: SimBot, h: SimUnit) -> bool:
	if not handles(b.kit) or not b._spells_ok():
		return false
	var ab := b.w.abilities
	if not ab.kits7.strike_again(h) or ab.cast_error(h, "blur_strike", -1, null, h.pos) != "":
		return false
	if b.mode == "lane" and b._foes.size() > 0 and b.w.time - float(h.ability_ready.get("blur_strike", 0.0)) > 0.35:
		var e: SimUnit = null
		for f in b._foes:
			if e == null or f.pos.distance_to(h.pos) < e.pos.distance_to(h.pos):
				e = f
		if e != null and not B18._fight_on(b, h, e) and not _kill_in_reach(b, h, e):
			return _dash_home(b, h)
	return false
