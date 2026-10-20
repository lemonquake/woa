class_name SimKits6
extends RefCounted
## The kits of Feran Mock and Ghorman (hero_ideas.txt, run 2026-10-18 f; see docs/HANDOFF.md). Called by
## SimAbilities: cast(), cast_error(), update_effect(), tick(); by SimCombat for Pie's misses and Beast Form's maul.
##
## Feran: Knife Juggle throws knives at random angles round his aim (each enemy hit at most 5 times a cast); the Joke
## Box pops after a fuse and plays a random prank on every enemy (Pie, Spring, Confetti, Glue); Swap trades places with
## any hero; Shuffle trades every enemy in an area with another, stuns and dizzies them, then knives fly out of it.
## Ghorman: Tame makes a neutral or enemy lane creep his beast for good (a summon that follows him, fights what he
## fights, uses its own spell, and obeys the player); Roar weakens enemies and drives his beasts; Pack Leader turns the
## beasts near him into damage and armor; Blessing of the Beast King heals and spurs one beast; Beast Form makes him (and
## his beasts) bigger, every 3rd attack a mauling bash.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order
const CASTS := ["knife_juggle", "joke_box", "swap", "shuffle", "tame", "roar", "blessing_of_the_beast_king",
	"beast_form"]
const EFFECTS := ["juggle", "knife", "joke_box", "dizzy_after"]
const CRASHES := {"joke_box": ["", "spring_stun"]}
const PRANKS := ["pie", "spring", "confetti", "glue"]
const BEAST_THINK := 6                      # ticks between a beast's thoughts (0.2 s)
const FOLLOW := 320.0                       # a beast with nothing to do stays this close to Ghorman
const LEASH := 1500.0                       # and walks back from further than this

var w: SimWorld
var ab: SimAbilities
var beasts := {}                            # Ghorman id -> [beast ids, oldest first]
var _juggle_hits := {}                      # juggle cast id -> {unit id: knives that hit it}
var _marks := {}                            # Feran id -> [ally id, until]: Upgrade Staff Swap's marked ally
var _seq := 0

func _init(world: SimWorld = null, abilities: SimAbilities = null) -> void:
	w = world
	ab = abilities

func handles(aid: String) -> bool:
	return aid in CASTS

func owns_effect(kind: String) -> bool:
	return kind in EFFECTS

func _enemy(team: int, o: SimUnit) -> bool:
	return o.alive and o.team != team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
		and not o.is_invulnerable()

func _movable(o: SimUnit) -> bool:
	return o.alive and not o.is_building() and not o.is_ward() and o.kind != K.COURIER and bool(o.def.can_move) \
		and float(o.def.move_speed) > 0.0 and not o.is_invulnerable()

func _land_spot(p: Vector2) -> Vector2:
	p = Vector2(clampf(p.x, -SimMap.EDGE, SimMap.EDGE), clampf(p.y, -SimMap.EDGE, SimMap.EDGE))
	if w.map.is_walkable(p):
		return p
	var c := w.map.nearest_walkable(w.map.world_to_cell(p))
	return w.map.cell_center(c.x, c.y)

func cast(u: SimUnit, aid: String, lv: int, t: SimUnit, p: Vector2) -> void:
	match aid:
		"knife_juggle":
			var dir := p - u.pos
			dir = Vector2.from_angle(u.facing) if dir.length() < 1.0 else dir.normalized()
			u.facing = dir.angle()
			juggle(u, u.id, u.pos, dir, true)
		"joke_box":
			_joke_box(u, aid, lv, p)
		"swap":
			_swap(u, aid, t)
		"shuffle":
			_shuffle(u, aid, p)
		"tame":
			_tame(u, aid, t)
		"roar":
			_roar(u, aid)
		"blessing_of_the_beast_king":
			_bless(u, aid, t)
		"beast_form":
			_beast_form(u, aid)

func update_effect(e: Dictionary) -> bool:
	match String(e.kind):
		"juggle":
			return _update_juggle(e)
		"knife":
			return _update_knife(e)
		"joke_box":
			return _update_box(e)
		"dizzy_after":
			if w.time < float(e.at):
				return false
			var o := w.get_unit(int(e.u))
			if o != null and o.alive:
				w.status.apply(o, int(e.src), int(e.team), {"id": "shuffle_dizzy", "dur": float(e.dur),
					"slow": float(e.slow), "stats": {"turn_rate_pct": -float(e.turn)}, "fx": "dizzy"})
			return true
	return true

## Cast rules beyond SimAbilities' own. "" = fine.
func cast_error(u: SimUnit, aid: String, t: SimUnit, _p: Vector2, check_target: bool) -> String:
	if not check_target or t == null:
		return ""
	match aid:
		"swap":
			if t == u or not t.is_hero():
				return "Must target another hero"
			if t.team != u.team and not ab.can_debuff(t, u.team):
				return "Target is debuff immune"
			if t.team == u.team and u.has_scepter():
				return ""
		"tame":
			return tame_error(u, t)
		"blessing_of_the_beast_king":
			if not is_beast_of(u, t):
				return "Must target one of your beasts"
	return ""

# ---- Feran: Knife Juggle ------------------------------------------------------------------------------------------------

## A Knife Juggle from `at` along `dir`: Knife Juggle's knives at Feran's level, 0.1 s apart, each at a random angle
## within its spread of the aim. `from_hand`: thrown by Feran (each knife leaves from where he stands then); else from
## the fixed point (Shuffle's). Each juggle counts its own hits (at most 5 knives on one enemy).
func juggle(u: SimUnit, src_id: int, at: Vector2, dir: Vector2, from_hand: bool) -> void:
	var aid := "knife_juggle"
	if u.ability_level_of(aid) <= 0:
		return
	_seq += 1
	_juggle_hits[_seq] = {}
	w.effects.append({"kind": "juggle", "src": src_id, "team": u.team, "pos": at, "dir": dir, "hand": from_hand,
		"left": int(ab.val(u, aid, "knives")), "next_at": w.time, "interval": ab.val(u, aid, "interval"),
		"spread": deg_to_rad(ab.val(u, aid, "spread")), "distance": ab.val(u, aid, "distance"),
		"speed": ab.val(u, aid, "speed"), "half": ab.val(u, aid, "width") * 0.5, "damage": ab.val(u, aid, "damage"),
		"max_hits": int(ab.val(u, aid, "max_hits")), "cast": _seq})
	w.events.append({"t": "knife_juggle", "u": src_id, "pos": at, "dir": dir, "cast": _seq})

func _update_juggle(e: Dictionary) -> bool:
	var u := w.get_unit(int(e.src))
	while int(e.left) > 0 and w.time + 1e-6 >= float(e.next_at):
		e.left = int(e.left) - 1
		e.next_at = float(e.next_at) + float(e.interval)
		var from: Vector2 = e.pos
		if bool(e.hand) and u != null and u.alive:
			from = u.pos
		var d := (e.dir as Vector2).rotated(w.rng.randf_range(-float(e.spread), float(e.spread)))
		var start := from + d * 30.0
		_seq += 1
		w.effects.append({"kind": "knife", "src": int(e.src), "team": int(e.team), "pos": start, "dir": d,
			"left": float(e.distance), "speed": float(e.speed), "half": float(e.half), "damage": float(e.damage),
			"max_hits": int(e.max_hits), "cast": int(e.cast), "seq": _seq})
		w.events.append({"t": "knife", "u": int(e.src), "from": start, "dir": d, "speed": float(e.speed),
			"dist": float(e.distance), "seq": _seq})
	return int(e.left) <= 0

func _update_knife(e: Dictionary) -> bool:
	var step := minf(float(e.speed) * C.DT, float(e.left))
	var from: Vector2 = e.pos
	var to: Vector2 = from + (e.dir as Vector2) * step
	e.left = float(e.left) - step
	e.pos = to
	var hits: Dictionary = _juggle_hits.get(int(e.cast), {})
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(to, float(e.half) + 160.0, true):
		if not _enemy(int(e.team), o) or int(hits.get(o.id, 0)) >= int(e.max_hits):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(o.pos, from, to)
		if cp.distance_to(o.pos) > float(e.half) + o.hull:
			continue
		var d := from.distance_to(cp)
		if d < bd:
			bd = d
			best = o
	if best != null:
		hits[best.id] = int(hits.get(best.id, 0)) + 1
		w.combat.deal_damage(int(e.src), int(e.team), true, best, float(e.damage), C.DamageType.MAGICAL, false,
			"knife_juggle")
		w.events.append({"t": "knife_hit", "seq": int(e.seq), "u": best.id, "src": int(e.src), "pos": best.pos})
		if best.kind == K.NEUTRAL_CREEP:
			var src := w.get_unit(int(e.src))
			if src:
				w.ai.neutral_provoked(best, src)
		return true
	if float(e.left) <= 0.0:
		w.events.append({"t": "knife_end", "seq": int(e.seq), "pos": to})
		return true
	return false

# ---- Feran: Joke Box ------------------------------------------------------------------------------------------------------

## The Joke Box lands at the point, then pops after its fuse: magic damage within 275, and every enemy there rolls its
## own prank (two different ones with the talent).
func _joke_box(u: SimUnit, aid: String, lv: int, p: Vector2) -> void:
	var at := _land_spot(p)
	_seq += 1
	var land := w.time + ab.val(u, aid, "throw_time")
	w.effects.append({"kind": "joke_box", "ability": aid, "src": u.id, "team": u.team, "pos": at, "lv": lv,
		"pop_at": land + ab.val(u, aid, "fuse"), "seq": 9000000 + _seq})
	w.events.append({"t": "joke_box", "u": u.id, "from": u.pos, "pos": at, "land": land - w.time,
		"fuse": ab.val(u, aid, "fuse"), "radius": ab.val(u, aid, "radius"), "seq": 9000000 + _seq})

func _update_box(e: Dictionary) -> bool:
	if w.time < float(e.pop_at):
		return false
	var u := w.get_unit(int(e.src))
	var aid := "joke_box"
	var lv := int(e.lv)
	var val := func(k: String) -> float: return ab._cv(int(e.src), aid, k, lv)
	var r: float = val.call("radius")
	var played := {}
	for o: SimUnit in w.query(e.pos, r + 60.0, true):
		if not _enemy(int(e.team), o) or o.pos.distance_to(e.pos) > r + o.hull:
			continue
		w.combat.deal_damage(int(e.src), int(e.team), true, o, val.call("damage"), C.DamageType.MAGICAL, false, aid)
		if o.kind == K.NEUTRAL_CREEP and u != null:
			w.ai.neutral_provoked(o, u)
		if not o.alive:
			continue
		var pool := PRANKS.duplicate()
		var picks: Array = []
		for i in clampi(int(val.call("pranks")), 1, PRANKS.size()):
			var k := w.rng.randi_range(0, pool.size() - 1)
			picks.append(pool[k])
			pool.remove_at(k)
		for pr in picks:
			_prank(o, String(pr), e, val)
		played[o.id] = picks
	w.events.append({"t": "joke_box_pop", "u": int(e.src), "pos": e.pos, "radius": r, "pranks": played,
		"seq": int(e.seq)})
	return true

func _prank(o: SimUnit, pr: String, e: Dictionary, val: Callable) -> void:
	var src := int(e.src)
	var team := int(e.team)
	match pr:
		"pie":
			w.status.apply(o, src, team, {"id": "joke_pie", "dur": val.call("pie_duration"), "blind": val.call("pie_miss"),
				"debuff": true, "fx": "pie"})
		"spring":
			if ab.can_debuff(o, team) and _movable(o) and o.kind != K.TOWER:
				var dir := Vector2.from_angle(w.rng.randf() * TAU)
				ab.start_push(o, dir * SimKits5.push_speed_for(val.call("spring")), src, team, "joke_box", int(e.lv),
					int(e.seq))
		"confetti":
			w.status.apply(o, src, team, {"id": "joke_confetti", "silence": true, "dur": val.call("silence"),
				"fx": "silence"})
		"glue":
			w.status.apply(o, src, team, {"id": "joke_glue", "root": true, "dur": val.call("root"), "fx": "root"})

## The chance an attacker's attacks miss (Pie; Dota's blind), 0 if none.
static func blind(u: SimUnit) -> float:
	var r := 0.0
	for m in u.modifiers:
		r = maxf(r, float(m.get("blind", 0.0)))
	return r

# ---- Feran: Swap, Shuffle ------------------------------------------------------------------------------------------------

## Swap: Feran and the hero trade places at once (projectiles at either lose them). A swapped enemy is turned to face
## away and slowed. With the Upgrade Staff an allied hero is marked first (free); the next Swap on an enemy hero trades
## those two and Feran stays put.
func try_swap_mark(u: SimUnit, t: SimUnit) -> bool:
	if t == null or not u.has_scepter() or t.team != u.team or not t.is_hero() or t == u:
		return false
	_marks[u.id] = [t.id, w.time + ab.val(u, "swap", "mark_time")]
	w.events.append({"t": "swap_mark", "u": u.id, "target": t.id})
	return true

func swap_mark(u: SimUnit) -> SimUnit:
	var m = _marks.get(u.id)
	if m == null or w.time >= float(m[1]):
		return null
	var a := w.get_unit(int(m[0]))
	return a if a != null and a.alive else null

func _swap(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive:
		return
	var a: SimUnit = u
	if t.team != u.team:
		var marked := swap_mark(u)
		if marked != null:
			a = marked
			_marks.erase(u.id)
	trade_places(a, t)
	if t.team != u.team:
		w.orders.cancel_channel(t)
		t.facing = wrapf(t.facing + PI, -PI, PI)
		w.status.apply(t, u.id, u.team, {"id": "swap_slow", "dur": ab.val(u, aid, "slow_duration"), "slow": ab.val(u, aid, "slow"),
			"fx": "slow"})
		if t.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(t, u)
	w.events.append({"t": "swap", "u": u.id, "a": a.id, "b": t.id, "pos_a": a.pos, "pos_b": t.pos})

func trade_places(a: SimUnit, b: SimUnit) -> void:
	var pa := a.pos
	var pb := b.pos
	w.combat.disjoint(a)
	w.combat.disjoint(b)
	a.pos = pb
	b.pos = pa
	for o: SimUnit in [a, b]:
		o.path = PackedVector2Array()
		o.path_goal = Vector2(INF, INF)
		o.knock = {}
		o.hop = {}

## Shuffle: every enemy hero and creep in the area takes another one's place (a random derangement: nobody stays), is
## stunned, then dizzy; then Knife Juggles fly out of the middle in every direction. With one enemy inside it trades
## places with Feran instead.
func _shuffle(u: SimUnit, aid: String, p: Vector2) -> void:
	var r := ab.val(u, aid, "radius")
	var inside: Array = []
	for o: SimUnit in w.query(p, r + 60.0, true):
		if not _enemy(u.team, o) or o.pos.distance_to(p) > r + o.hull or not ab.can_debuff(o, u.team) or not _movable(o):
			continue
		if not (o.is_hero() or o.is_creep() or o.kind == K.SUMMON):
			continue
		inside.append(o)
	# a fixed order (ids), then a deterministic shuffle
	inside.sort_custom(func(x, y): return x.id < y.id)
	for i in range(inside.size() - 1, 0, -1):
		var j := w.rng.randi_range(0, i)
		var tmp = inside[i]
		inside[i] = inside[j]
		inside[j] = tmp
	var moves: Array = []
	if inside.size() == 1:
		trade_places(u, inside[0])
		moves.append([inside[0].id, inside[0].pos])
	elif inside.size() >= 2:
		var spots: Array = inside.map(func(o): return o.pos)
		for i in inside.size():
			var o: SimUnit = inside[i]
			w.combat.disjoint(o)
			o.pos = spots[(i + 1) % inside.size()]
			o.path = PackedVector2Array()
			o.path_goal = Vector2(INF, INF)
			o.knock = {}
			moves.append([o.id, o.pos])
	var stun := ab.val(u, aid, "stun")
	for o: SimUnit in inside:
		w.orders.cancel_channel(o)
		if w.status.apply(o, u.id, u.team, {"id": "stunned", "stun": true, "dur": stun, "fx": "stun"}):
			var st := o.get_modifier("stunned")
			var left := maxf(0.0, float(st.get("expires", w.time)) - w.time)
			w.effects.append({"kind": "dizzy_after", "u": o.id, "src": u.id, "team": u.team, "at": w.time + left,
				"dur": ab.val(u, aid, "dizzy"), "slow": ab.val(u, aid, "dizzy_slow"), "turn": ab.val(u, aid, "dizzy_turn")})
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	w.events.append({"t": "shuffle", "u": u.id, "pos": p, "radius": r, "moves": moves})
	# the knives: Knife Juggles from the middle, evenly round, each with its own 5-hit cap
	var n := int(ab.val(u, aid, "juggles"))
	var turn := w.rng.randf() * TAU
	for k in n:
		juggle(u, u.id, p, Vector2.from_angle(turn + TAU * float(k) / float(maxi(1, n))), false)

# ---- Ghorman: Tame and his beasts -----------------------------------------------------------------------------------------

func is_beast(o: SimUnit) -> bool:
	return o != null and o.kind == K.SUMMON and not o.get_modifier("tamed").is_empty()

func is_beast_of(u: SimUnit, o: SimUnit) -> bool:
	return is_beast(o) and o.owner_id == u.id and o.alive

## His living beasts, oldest first.
func beasts_of(u: SimUnit) -> Array:
	var out: Array = []
	for id in beasts.get(u.id, []):
		var b := w.get_unit(int(id))
		if b != null and b.alive:
			out.append(b)
	return out

func tame_error(u: SimUnit, t: SimUnit) -> String:
	if t == null or not t.alive:
		return "Must target a creep"
	if is_beast(t):
		return "Already a beast"
	if t.kind == K.NEUTRAL_CREEP:
		if bool(t.def.get("ancient", false)) and not u.has_scepter():
			return "Cannot tame ancient creeps"
		return ""
	if t.is_lane_creep() and t.team != u.team and t.team != C.NEUTRAL:
		return ""
	return "Must target a neutral or enemy lane creep"

## Tame: the creep becomes Ghorman's beast for good (a summon on his team), with more health and attack damage, keeping
## its spell. Past his limit the oldest beast is released (it dies); with the Upgrade Staff an ancient creep may be
## tamed, one at a time.
func _tame(u: SimUnit, aid: String, t: SimUnit) -> void:
	if t == null or not t.alive or tame_error(u, t) != "":
		return
	var bonus := ab.val(u, aid, "bonus")
	var frac := t.hp / maxf(1.0, t.max_hp)
	var old_hp := t.max_hp
	var old_armor := t.armor
	var old_as := t.attack_speed
	w.orders.clear(t)
	w.orders.cancel_channel(t)
	var from_team := t.team
	t.team = u.team
	t.kind = K.SUMMON
	t.owner_id = u.id
	t.camp_id = -1
	t.lane = ""
	t.neutral_state = 0
	t.atk_target = -1
	t.aggro_target = -1
	t.ward_expires = INF
	t.stacked = false
	t.stacker_id = -1
	t.home = t.pos
	t.upgrade = 0
	t.refresh_stats()
	# what the creep had from the clock (lane and neutral upgrades) stays, and the taming adds its share
	t.perm_stats = {"hp": old_hp * (1.0 + bonus) - t.max_hp, "armor": old_armor - t.armor,
		"attack_speed": maxf(0.0, old_as - t.attack_speed), "base_damage_pct": bonus}
	t.add_modifier({"id": "tamed", "source": u.id, "expires": INF, "dispel": "", "by": u.id, "fx": "tamed"})
	t.refresh_stats()
	t.hp = t.max_hp * frac
	for a in t.abilities:
		t.ability_ready[a] = minf(float(t.ability_ready.get(a, C.LONG_AGO)), w.time)
	var list: Array = beasts.get(u.id, []).filter(func(id): return w.valid(int(id)) and w.get_unit(int(id)).alive)
	# one ancient beast at a time (Upgrade Staff)
	if bool(t.def.get("ancient", false)):
		for id in list.duplicate():
			var b := w.get_unit(int(id))
			if b != null and bool(b.def.get("ancient", false)):
				list.erase(id)
				_release(b)
	list.append(t.id)
	var cap := int(ab.val(u, aid, "max_beasts"))
	while list.size() > cap:
		var old := w.get_unit(int(list.pop_front()))
		if old != null:
			_release(old)
	beasts[u.id] = list
	w.events.append({"t": "tame", "u": u.id, "target": t.id, "from_team": from_team})

func _release(b: SimUnit) -> void:
	w.events.append({"t": "beast_released", "u": b.owner_id, "target": b.id})
	b.remove_modifier("tamed")
	w.combat.kill(b, null)

## Beasts every 0.2 s: a player's order stands until it is done; otherwise they fight what Ghorman fights (or what
## fights him), take on enemies close to them and to him, use their spell when it is worth it, and keep near him.
func _beast_ai(b: SimUnit, owner: SimUnit) -> void:
	if b.is_stunned() or b.cast_phase != SimUnit.CastPhase.NONE or not b.channel.is_empty():
		return
	var busy := b.order_from_player and b.order != O.NONE
	if busy and b.order != O.ATTACK_MOVE:
		return
	var tgt: SimUnit = null
	if owner != null and owner.alive:
		var ot := w.get_unit(owner.atk_target)
		if ot != null and ot.alive and ot.team != b.team and not ot.is_ward() and w.vision.sees(b.team, ot) \
				and ot.pos.distance_to(b.pos) < 1400.0 and not (ot.is_building() and ot.is_invulnerable()):
			tgt = ot
	if tgt == null:
		var best_key := INF
		var around: Vector2 = owner.pos if owner != null and owner.alive else b.pos
		for o: SimUnit in w.query(b.pos, b.acquire_range + 100.0, true):
			if not _enemy(b.team, o) or not w.vision.sees(b.team, o) or (o.team == C.NEUTRAL and o.atk_target != b.id \
					and o.atk_target != (owner.id if owner != null else -2)):
				continue
			if o.pos.distance_to(around) > 900.0:
				continue
			var key := b.edge_distance(o) - (600.0 if o.is_hero() else 0.0)
			if owner != null and o.atk_target == owner.id:
				key -= 800.0
			if key < best_key:
				best_key = key
				tgt = o
	if tgt != null and not b.is_disarmed():
		if _beast_cast(b, tgt):
			return
		if busy:
			return
		if b.order != O.ATTACK_UNIT or b.order_target != tgt.id:
			w.orders.issue(b, {"type": O.ATTACK_UNIT, "target": tgt.id}, false)
		return
	if busy or owner == null or not owner.alive:
		return
	var d := b.pos.distance_to(owner.pos)
	if d > FOLLOW or (d > LEASH * 0.5 and b.order == O.ATTACK_UNIT):
		# a place beside him, by its place in his pack
		var i: int = (beasts.get(owner.id, []) as Array).find(b.id)
		var spot := owner.pos + Vector2.from_angle(owner.facing + PI * 0.75 + 0.6 * float(i)) * 170.0
		if b.order != O.MOVE or b.order_point.distance_to(spot) > 120.0:
			w.orders.issue(b, {"type": O.MOVE, "point": _land_spot(spot)}, false)
	elif b.order == O.MOVE and not b.order_from_player and d < FOLLOW * 0.6:
		w.orders.issue(b, {"type": O.STOP}, false)

## A beast's own spell (the neutrals' Snarl, Stomp, Smash) when it is worth it, as the camps use them.
func _beast_cast(b: SimUnit, t: SimUnit) -> bool:
	if b.abilities.is_empty() or b.is_silenced():
		return false
	for aid in b.abilities:
		if w.abilities.cast_error(b, aid, -1, null, b.pos, false, false) != "":
			continue
		var a := SimData.ability(aid)
		var r := float(a.values.radius[0]) if (a.values as Dictionary).has("radius") else 200.0
		match String(aid):
			"stomp", "snarl":
				var heroes := 0
				var others := 0
				for o: SimUnit in w.query(b.pos, r + 40.0, true):
					if not _enemy(b.team, o) or o.pos.distance_to(b.pos) > r + o.hull:
						continue
					if o.is_hero():
						heroes += 1
					else:
						others += 1
				if heroes > 0 or (aid == "stomp" and others >= 2):
					w.orders.issue(b, {"type": O.CAST_NO_TARGET, "ability": aid}, false)
					return true
			"smash":
				if t != null and t.alive and b.edge_distance(t) <= float(a.range) + 40.0:
					w.orders.issue(b, {"type": O.CAST_POINT, "ability": aid, "point": t.pos}, false)
					return true
	return false

# ---- Ghorman: Roar, Pack Leader, Blessing, Beast Form ----------------------------------------------------------------------

## Roar: enemies within 500 are slowed and deal less attack damage; his beasts within 900 attack and move faster (2% more
## attack speed for each beast he leads).
func _roar(u: SimUnit, aid: String) -> void:
	var r := ab.val(u, aid, "radius")
	var dur := ab.val(u, aid, "duration")
	var hit: Array = []
	for o: SimUnit in w.query(u.pos, r + 60.0, true):
		if not _enemy(u.team, o) or u.edge_distance(o) > r:
			continue
		if w.status.apply(o, u.id, u.team, {"id": "roar", "dur": dur, "slow": ab.val(u, aid, "slow"),
				"stats": {"attack_out_pct": -ab.val(u, aid, "attack_cut")}, "fx": "weakened"}):
			hit.append(o.id)
		if o.kind == K.NEUTRAL_CREEP:
			w.ai.neutral_provoked(o, u)
	var pack := beasts_of(u)
	var cheered: Array = []
	for b: SimUnit in pack:
		if b.pos.distance_to(u.pos) > ab.val(u, aid, "beast_reach"):
			continue
		b.add_modifier({"id": "roar_pack", "source": u.id, "expires": w.time + dur, "dispel": "basic", "fx": "roar_pack",
			"stats": {"attack_speed": ab.val(u, aid, "beast_attack_speed"),
				"attack_speed_pct": ab.val(u, aid, "beast_attack_pct") * pack.size(),
				"move_speed_pct": ab.val(u, aid, "beast_move_pct")}})
		b.refresh_stats()
		cheered.append(b.id)
	w.events.append({"t": "roar", "u": u.id, "pos": u.pos, "radius": r, "hits": hit, "beasts": cheered})

## Pack Leader, twice a second: each beast near him gives him attack damage and armor (Break stops it). A beast that
## died since the last look heals him.
func _pack(u: SimUnit) -> void:
	var list: Array = beasts.get(u.id, [])
	var live: Array = []
	for id in list:
		var b := w.get_unit(int(id))
		if b != null and b.alive and is_beast(b):
			live.append(id)
		elif b != null and not b.alive and not b.get_modifier("tamed").is_empty():
			# a beast fell (a released one loses its mark first and heals nothing)
			if u.alive and u.ability_level_of("pack_leader") > 0 and not u.is_broken():
				var healed := w.combat.heal(u, u.max_hp * ab.val(u, "pack_leader", "heal"))
				w.events.append({"t": "pack_heal", "u": u.id, "beast": b.id, "amount": healed})
			b.remove_modifier("tamed")
	beasts[u.id] = live
	if u.ability_level_of("pack_leader") <= 0:
		return
	var n := 0
	if u.alive and not u.is_broken():
		for id in live:
			var b := w.get_unit(int(id))
			if b.pos.distance_to(u.pos) <= ab.val(u, "pack_leader", "reach"):
				n += 1
	if n == 0:
		if not u.get_modifier("pack_leader").is_empty():
			u.remove_modifier("pack_leader")
		return
	u.add_modifier({"id": "pack_leader", "source": u.id, "expires": INF, "charges": n, "dispel": "",
		"stats": {"damage": ab.val(u, "pack_leader", "damage") * n, "armor": ab.val(u, "pack_leader", "armor") * n},
		"fx": ""})

## Blessing of the Beast King (chosen effect, see docs/HANDOFF.md): one of his beasts heals, is cleansed (a basic
## dispel), its spell is ready again, and for 8 s it hits harder and faster.
func _bless(u: SimUnit, aid: String, t: SimUnit) -> void:
	if not is_beast_of(u, t):
		return
	w.combat.heal(t, t.max_hp * ab.val(u, aid, "heal"), u)
	w.status.dispel(t, false, u.team)
	for a in t.abilities:
		t.ability_ready[a] = minf(float(t.ability_ready.get(a, C.LONG_AGO)), w.time)
	var dur := ab.val(u, aid, "duration")
	t.add_modifier({"id": aid, "source": u.id, "expires": w.time + dur, "dispel": "basic", "fx": "blessed",
		"stats": {"base_damage_pct": ab.val(u, aid, "damage_pct"), "attack_speed": ab.val(u, aid, "attack_speed")}})
	t.refresh_stats()
	w.events.append({"t": "blessing", "u": u.id, "target": t.id, "dur": dur})

## Beast Form: 25 s as the beast (his model swaps, as Roydo's Anomaly): health, damage and speed; every 3rd attack a
## maul (SimCombat asks maul()); his beasts grow too (more health, spells back sooner) while it lasts.
func _beast_form(u: SimUnit, aid: String) -> void:
	var dur := ab.val(u, aid, "duration")
	u.add_modifier({"id": "beast_form", "source": u.id, "expires": w.time + dur, "dispel": "", "fx": "beast_form",
		"stats": {"hp": ab.val(u, aid, "hp"), "damage": ab.val(u, aid, "damage"), "move_speed": ab.val(u, aid, "move_speed")}})
	u.refresh_stats()
	u.stacks["maul"] = 0
	w.events.append({"t": "beast_form", "u": u.id, "dur": dur})

func _grow_pack(u: SimUnit) -> void:
	var m := u.get_modifier("beast_form")
	if m.is_empty() or not u.alive:
		return
	for b: SimUnit in beasts_of(u):
		var g := b.get_modifier("beast_growth")
		var hp := float((g.get("stats", {}) as Dictionary).get("hp", 0.0)) if not g.is_empty() else \
			b.max_hp * ab.val(u, "beast_form", "beast_hp")
		var was := b.max_hp
		b.add_modifier({"id": "beast_growth", "source": u.id, "expires": float(m.expires), "dispel": "", "fx": "beast_growth",
			"stats": {"hp": hp, "cooldown_rate": ab.val(u, "beast_form", "beast_cooldown_rate")}})
		if g.is_empty():
			b.refresh_stats()
			b.hp = minf(b.max_hp, b.hp + (b.max_hp - was))

## Beast Form's maul on an attack that landed (SimCombat.land_attack, before the item bash roll): every 3rd attack on a
## unit (not buildings or wards) adds the maul's physical damage and a bash; it is the bash of that attack (bashes do
## not stack). {} when this is not one.
func maul(s: Dictionary, t: SimUnit) -> Dictionary:
	if not bool(s.hero) or t.is_building() or t.is_ward():
		return {}
	var u := w.get_unit(int(s.src))
	if u == null or u.get_modifier("beast_form").is_empty():
		return {}
	var n := int(u.stacks.get("maul", 0)) + 1
	if n < int(ab.val(u, "beast_form", "maul_every")):
		u.stacks["maul"] = n
		return {}
	u.stacks["maul"] = 0
	w.events.append({"t": "maul", "u": u.id, "target": t.id})
	return {"damage": ab.val(u, "beast_form", "maul"), "dur": ab.val(u, "beast_form", "bash"), "item": "beast_form"}

# ---- Per tick ---------------------------------------------------------------------------------------------------------------

func tick() -> void:
	if not _juggle_hits.is_empty() and w.tick % 150 == 0:
		var live := {}
		for e in w.effects:
			if String(e.kind) == "knife" or String(e.kind) == "juggle":
				live[int(e.cast)] = true
		for k in _juggle_hits.keys():
			if not live.has(k):
				_juggle_hits.erase(k)
	if beasts.is_empty():
		return
	var pack_now := w.tick % 15 == 0
	for gid in beasts.keys():
		var g := w.get_unit(int(gid))
		if g == null:
			continue
		if pack_now:
			_pack(g)
			_grow_pack(g)
		for id in beasts.get(gid, []):
			var b := w.get_unit(int(id))
			if b != null and b.alive and (w.tick + b.id) % BEAST_THINK == 0:
				_beast_ai(b, g)
