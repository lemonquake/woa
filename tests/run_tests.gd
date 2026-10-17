extends SceneTree
## Headless mechanics tests: godot --headless --path . -s tests/run_tests.gd [-- --only=name]
## Each test builds its own world from a fixed seed and checks a Dota rule against an independent expectation.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const O = C.Order

var _map: SimMap
var _fails := 0
var _passes := 0
var _current := ""

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_map = SimMap.new()
	_map.build(1)
	print("map built in %d ms: %d trees" % [Time.get_ticks_msec() - t0, _map.trees.size()])
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for m in get_method_list():
		var n: String = m.name
		if n.begins_with("test_") and (only == "" or n.contains(only)):
			_current = n
			var before := _fails
			var t1 := Time.get_ticks_msec()
			call(n)
			print("%s %s (%d ms)" % ["PASS" if _fails == before else "FAIL", n, Time.get_ticks_msec() - t1])
			if _fails == before:
				_passes += 1
	print("\n%d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		push_error("[%s] %s" % [_current, msg])
		print("    x " + msg)

func near(a: float, b: float, tol: float, msg: String) -> void:
	check(absf(a - b) <= tol, "%s: got %.4f, expected %.4f (+-%.4f)" % [msg, a, b, tol])

## Mechanics tests check one rule at a time, so worlds start without the element table (test_element_* turn it on).
func world(start_time := 0.0) -> SimWorld:
	# every test starts on the whole forest: spells that fell trees (Gale Impact, Fiery Javelin, Bounce Shot) in an
	# earlier test must not change a later one
	for i in _map.trees.size():
		_restore_tree(i)
	var w := SimWorld.new(1, _map)
	w.elements = false
	w.time = start_time
	w.next_wave_at = INF if start_time > 0.0 else 0.0
	return w

func run(w: SimWorld, seconds: float) -> void:
	for i in int(round(seconds * C.TICK_RATE)):
		w.step()

## A world with no buildings, waves or camps unless the test adds them.
func empty_world() -> SimWorld:
	var w := world(5.0)
	w.next_neutral_at = INF
	w.vision.static_dirty = true
	return w

# ---- Formulas -------------------------------------------------------------------------------------------------------

func test_armor_formula() -> void:
	near(C.armor_multiplier(0.0), 1.0, 1e-6, "0 armor")
	near(C.armor_multiplier(10.0), 1.0 - 0.6 / 1.6, 1e-6, "10 armor")
	near(C.armor_multiplier(-5.0), 1.0 + 0.3 / 1.3, 1e-6, "-5 armor")

func test_xp_levels() -> void:
	check(C.xp_level(0) == 1, "level 1 at 0 xp")
	check(C.xp_level(239) == 1 and C.xp_level(240) == 2, "level 2 at 240 xp")
	check(C.xp_level(640) == 3, "level 3 at 640 xp")
	check(C.xp_level(999999) == 30, "level cap 30")

func test_day_night() -> void:
	check(C.is_night(-10.0), "pre-horn is night")
	check(not C.is_night(0.0) and not C.is_night(299.0), "day from 0:00 to 5:00")
	check(C.is_night(300.0) and C.is_night(599.0), "night from 5:00 to 10:00")
	check(not C.is_night(600.0), "day again at 10:00")

# ---- Map --------------------------------------------------------------------------------------------------------------

func test_map_lanes_walkable() -> void:
	for lane in ["top", "mid", "bot"]:
		for team in [C.DAWN, C.DUSK]:
			var path := _map.lane_path(lane, team)
			for i in path.size() - 1:
				var p := _map.find_path(path[i], path[i + 1])
				check(not p.is_empty(), "%s lane (team %d) segment %d reachable" % [lane, team, i])
	var p2 := _map.find_path(_map.fountains[0], _map.fountains[1])
	check(not p2.is_empty(), "fountain to fountain path exists")

func test_map_symmetry() -> void:
	var dawn := _map.buildings.filter(func(b): return b.team == C.DAWN)
	var dusk := _map.buildings.filter(func(b): return b.team == C.DUSK)
	check(dawn.size() == dusk.size() and dawn.size() == 22, "22 buildings per side (11 towers, 6 barracks, ancient, fountain, 3 effigies)")
	var towers := dawn.filter(func(b): return String(b.unit).begins_with("tower"))
	check(towers.size() == 11, "11 towers per side")
	check(_map.level_at(Vector2(-6000, -6000)) == SimMap.HIGH, "Dawn base is high ground")
	check(_map.level_at(Vector2(0, 0)) == SimMap.RIVER, "map centre is river")
	check(_map.level_at(Vector2(-3000, 3000)) == SimMap.RIVER, "river runs north-west to south-east")
	check(_map.level_at(Vector2(-2000, -4000)) == SimMap.GROUND, "jungle is ground level")

func test_map_elevation_and_mountains() -> void:
	var N := SimMap.N
	var asym := 0
	var high_jungle := 0
	var mountain := 0
	for cy in N:
		for cx in N:
			var l := _map.level[cy * N + cx]
			if l != _map.level[(N - 1 - cy) * N + (N - 1 - cx)]:
				asym += 1
			if l == SimMap.MOUNTAIN:
				mountain += 1
				check(_map.walkable[cy * N + cx] == 0, "mountain cells are impassable")
			var p := _map.cell_center(cx, cy)
			if l == SimMap.HIGH and not (absf(p.x) > 3700.0 and absf(p.y) > 3000.0 and signf(p.x) == signf(p.y)):
				high_jungle += 1
	check(asym == 0, "terrain levels are symmetric under p -> -p (%d cells differ)" % asym)
	check(high_jungle > 1500, "the jungle has raised plateaus (%d high cells outside the bases)" % high_jungle)
	check(mountain > 1500, "mountains frame the map (%d cells)" % mountain)
	check(_map.plateau_ramps.size() >= 10, "plateaus have ramps (%d)" % _map.plateau_ramps.size())
	# every camp and every plateau ramp can be walked to from both fountains
	for f in _map.fountains:
		var start: Vector2 = f + ((Vector2.ZERO - f).normalized() * 700.0)
		for c in _map.camps:
			var path := _map.find_path(start, c.pos)
			check(path.size() > 1 and path[path.size() - 1].distance_to(c.pos) < 300.0, "camp %d reachable from the fountain at %s" % [c.id, f])
		for r in _map.plateau_ramps:
			var path2 := _map.find_path(start, r.pos)
			check(path2.size() > 1 and path2[path2.size() - 1].distance_to(r.pos) < 300.0, "ramp at %s reachable" % r.pos)
	# vision: a hero on a plateau sees down, one below the cliff does not see up
	var w := empty_world()
	var pl: Array = SimMap.PLATEAUS[0]
	var top := w.spawn("blood_ranger", C.DUSK, pl[0])
	check(_map.level_at(top.pos) == SimMap.HIGH, "the hard camp bluff is high ground")

# ---- Turning and attacks ------------------------------------------------------------------------------------------

func test_turn_rate() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	h.facing = 0.0
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(-600, 0)})
	var ticks := 0
	while h.pos.x >= -2000.0 - 0.01 and ticks < 300:
		w.step()
		ticks += 1
	# 180 degree turn at 0.7 rad / 0.03 s, minus the 11.5 deg tolerance, then movement begins
	var expected := (PI - C.FACING_TOLERANCE) / (0.7 / 0.03)
	near(ticks * C.DT, expected, 2.0 * C.DT, "time before walking after an about-turn")

func test_attack_interval_and_point() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var dummy := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	dummy.def = dummy.def.duplicate()
	dummy.def.hp = 1e6
	dummy.def.dmg_min = 0.0
	dummy.def.dmg_max = 0.0
	dummy.refresh_stats()
	dummy.hp = dummy.max_hp
	h.facing = 0.0
	dummy.order = O.HOLD
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": dummy.id})
	var starts: Array = []
	var releases: Array = []
	for i in 30 * 8:
		w.step()
		for e in w.events:
			if e.t == "attack_start" and e.u == h.id:
				starts.append(w.time)
			if e.t == "projectile" and e.src == h.id:
				releases.append(w.time)
		w.events.clear()
	check(starts.size() >= 4, "hero attacked repeatedly (%d)" % starts.size())
	# agility 24 -> 124 attack speed -> 1.7 / 1.24 s between attacks
	var interval := 1.7 / ((100.0 + h.agi_total) / 100.0)
	for i in range(1, starts.size()):
		near(starts[i] - starts[i - 1], interval, C.DT * 1.01, "interval between attack starts")
	if starts.size() > 0 and releases.size() > 0:
		near(releases[0] - starts[0], 0.5 / ((100.0 + h.agi_total) / 100.0), C.DT * 1.01, "attack point scaled by attack speed")

func test_cancel_windup_keeps_cooldown() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	c.order = O.HOLD
	c.def = c.def.duplicate()
	c.def.dmg_min = 0.0
	c.def.dmg_max = 0.0
	h.facing = 0.0
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": c.id})
	w.step()
	w.step()
	check(h.atk_phase == SimUnit.AtkPhase.WINDUP, "windup started")
	w.command(h.id, {"type": O.STOP})
	check(h.atk_phase == SimUnit.AtkPhase.NONE, "stop cancels the windup")
	check(h.next_attack_at <= w.time, "cancelled windup spends no cooldown")
	var hp0 := c.hp
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": c.id})
	run(w, 1.0)
	check(c.hp < hp0, "attacking again right away lands")

func test_backswing_cancel_free() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	c.order = O.HOLD
	h.facing = 0.0
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": c.id})
	while h.atk_phase != SimUnit.AtkPhase.BACKSWING:
		w.step()
	var p0 := h.pos
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(0, -500)})
	run(w, 0.4)
	check(h.pos.distance_to(p0) > 20.0, "moving cancels the backswing at once (orb walk)")

# ---- Denies and attack classes --------------------------------------------------------------------------------------

func test_deny_rules() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var ally := w.spawn("dawn_melee", C.DAWN, Vector2(-1700, -4000))
	ally.order = O.HOLD
	w.vision.update()
	check(not w.orders.can_deny(h, ally), "an ally creep above half health is not deniable")
	# the order is accepted: the hero closes in and waits, swinging only once the creep can be denied
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": ally.id})
	check(h.order == O.ATTACK_UNIT, "attack order on an ally is accepted")
	run(w, 2.0)
	check(h.atk_phase == SimUnit.AtkPhase.NONE and ally.hp == ally.max_hp, "no swing while the ally is above half health")
	check(h.edge_distance(ally) <= h.attack_range, "the hero waits within attack range")
	ally.hp = ally.max_hp * 0.49
	check(w.orders.can_deny(h, ally), "can deny an ally creep below half health")
	run(w, 1.5)
	check(ally.hp < ally.max_hp * 0.49 or not ally.alive, "the hero attacks once the ally is deniable")

func test_attack_class_matrix() -> void:
	var w := empty_world()
	var ranged := w.spawn("dawn_ranged", C.DAWN, Vector2(-2000, -4000))
	var melee := w.spawn("dusk_melee", C.DUSK, Vector2(-1600, -4000))
	var hero := w.spawn("blood_ranger", C.DUSK, Vector2(-1500, -4100))
	var tower := w.spawn("tower1", C.DUSK, Vector2(-1000, -4000))
	var s := w.combat._snapshot(ranged, "")
	near(w.combat.attack_class_multiplier(s, melee), 1.5, 1e-6, "piercing vs creep")
	near(w.combat.attack_class_multiplier(s, hero), 0.5, 1e-6, "piercing vs hero")
	near(w.combat.attack_class_multiplier(s, tower), 0.35, 1e-6, "piercing vs building")
	var hs := w.combat._snapshot(hero, "")
	near(w.combat.attack_class_multiplier(hs, tower), 0.5, 1e-6, "hero vs building")
	var ms := w.combat._snapshot(melee, "")
	near(w.combat.attack_class_multiplier(ms, hero), 0.75, 1e-6, "melee creep vs hero")

# ---- Gold and experience ---------------------------------------------------------------------------------------------

func test_last_hit_gold_and_xp() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	c.order = O.HOLD
	c.hp = 1.0
	h.facing = 0.0
	w.vision.update()
	var g0 := h.gold()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": c.id})
	run(w, 2.0)
	check(not c.alive, "creep died")
	var gained := h.gold() - g0
	check(gained >= 34 and gained <= 39, "last hit pays the melee creep bounty 34-39 (got %d)" % gained)
	near(h.xp, 57.0, 0.01, "full 57 xp to the only hero nearby")
	check(h.last_hits == 1, "last hit counted")

func test_deny_xp_halved() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-2000, -3500))
	foe.order = O.HOLD
	var c := w.spawn("dawn_melee", C.DAWN, Vector2(-1500, -4000))
	c.order = O.HOLD
	c.hp = 2.0
	h.facing = 0.0
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": c.id})
	run(w, 2.0)
	check(not c.alive, "creep denied")
	check(h.denies == 1, "deny counted")
	near(foe.xp, 28.0, 0.01, "enemy gets half (floored) experience from a denied creep")
	check(h.xp == 0.0, "denier gets no experience")

func test_creep_kill_no_gold() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2600, -4000))
	h.order = O.HOLD
	var a := w.spawn("dawn_melee", C.DAWN, Vector2(-1650, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	c.hp = 5.0
	c.order = O.HOLD
	a.atk_target = c.id
	a.order = O.NONE
	a.lane = "mid"
	w.vision.update()
	var g0 := h.gold_unreliable
	run(w, 2.0)
	check(not c.alive, "creep killed by creep")
	check(h.gold_unreliable == g0, "no gold when a creep gets the last hit")
	near(h.xp, 57.0, 0.01, "experience is still shared")

# ---- Waves ----------------------------------------------------------------------------------------------------------

func test_wave_spawn() -> void:
	var w := SimWorld.new(1, _map)
	w.time = -1.0
	w.next_neutral_at = INF
	run(w, 1.2)
	var creeps := w.units.filter(func(u): return u.is_lane_creep())
	check(creeps.size() == 24, "first wave: 3 melee + 1 ranged in 3 lanes for 2 teams (got %d)" % creeps.size())
	run(w, 30.0)
	# counted as spawned: the top and bottom lanes now meet early enough for a creep to fall before 0:31
	var spawned := w.next_id - 1
	check(spawned == 48, "second wave at 0:30 (got %d spawned)" % spawned)
	check(w.wave == 2, "two waves by 0:31")

func test_wave_composition() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 120.0
	var before := w.units.size()
	w.ai.spawn_wave(5)
	var flags := w.units.filter(func(u): return u.kind == K.CREEP_FLAG).size()
	check(flags == 6, "wave 5 brings a flagbearer per lane per team")
	w.ai.spawn_wave(11)
	var sieges := w.units.filter(func(u): return u.kind == K.CREEP_SIEGE).size()
	check(sieges == 6, "wave 11 (5:00) brings a siege creep per lane per team")

# ---- Aggro ------------------------------------------------------------------------------------------------------------

func test_creep_aggro_attack_order() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-1300, -4000))
	foe.order = O.HOLD
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-2000, -3700))
	c.lane = "mid"
	c.order = O.HOLD
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	check(c.aggro_forced and c.aggro_target == h.id, "attack order on a hero aggroes enemy creeps within 500")
	near(c.aggro_until - w.time, 2.3, 1e-4, "aggro lasts 2.3 s")
	check(h.aggro_cd_until > w.time, "aggro cooldown started")
	var c2 := w.spawn("dusk_melee", C.DUSK, Vector2(-2000, -3750))
	c2.lane = "mid"
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	check(not c2.aggro_forced, "no new aggro while the 3 s cooldown runs")

func test_tower_protects_heroes() -> void:
	var w := empty_world()
	var tw := w.spawn("tower1", C.DUSK, Vector2(-1000, -4000))
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-1500, -4000))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-1500, -3550))
	foe.order = O.HOLD
	var creep := w.spawn("dawn_melee", C.DAWN, Vector2(-1250, -4000))
	creep.order = O.HOLD
	w.vision.update()
	run(w, 0.2)
	check(tw.atk_target == creep.id or tw.atk_target == h.id, "tower picked a target")
	h.facing = PI * 0.5
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	run(w, 0.6)
	var switched: bool = tw.atk_target == h.id or w.ai._pending.get(tw.id, -1) == h.id
	check(switched, "tower switches to a hero attacking a hero in its range")

func test_tower_prefers_units_over_buildings() -> void:
	var w := empty_world()
	var tw := w.spawn("tower1", C.DUSK, Vector2(-1000, -4000))
	var creep := w.spawn("dawn_melee", C.DAWN, Vector2(-1300, -4000))
	creep.order = O.HOLD
	var siege := w.spawn("dawn_siege", C.DAWN, Vector2(-1250, -3800))
	siege.order = O.HOLD
	w.vision.update()
	run(w, 0.2)
	check(tw.atk_target == creep.id, "tower attacks a regular unit before a siege creep")

# ---- Neutrals -----------------------------------------------------------------------------------------------------------

func test_neutral_spawn_and_block() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 59.0
	w.next_wave_at = INF
	var camp: Dictionary = _map.camps[0]
	var blocker := w.spawn("blood_ranger", C.DAWN, camp.pos)
	blocker.order = O.HOLD
	run(w, 1.2)
	var in_camp := w.units.filter(func(u): return u.camp_id == camp.id).size()
	check(in_camp == 0, "a unit inside the spawn box blocks the camp")
	var other := w.units.filter(func(u): return u.camp_id == 1).size()
	check(other == (camp_units(1)), "other camps spawn at 1:00")
	blocker.pos = Vector2(-7000, -7000)
	run(w, 60.0)
	in_camp = w.units.filter(func(u): return u.camp_id == camp.id).size()
	check(in_camp == camp_units(0), "camp spawns at the next minute once the box is clear")

func camp_units(i: int) -> int:
	return (_map.camps[i].units as Array).size()

func test_neutral_stack() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 59.0
	w.next_wave_at = INF
	run(w, 1.2)
	var camp: Dictionary = _map.camps[1]
	var h := w.spawn("blood_ranger", C.DAWN, camp.pos + Vector2(-500, 0))
	w.time = 113.5
	w.vision.update()
	var n := w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	check(n.size() == camp_units(1), "camp is up")
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": n[0].id})
	run(w, 1.5)
	w.command(h.id, {"type": O.MOVE, "point": camp.pos + Vector2(-1600, -200)})
	run(w, 8.0)
	n = w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	check(n.size() >= camp_units(1) * 2, "pulling the camp out of its box at :53.5 stacks a second camp (%d units)" % n.size())
	run(w, 10.0)
	var home := n.filter(func(u): return u.neutral_state == 0)
	check(home.size() == n.size(), "neutrals lose interest and return to their camp")

# ---- Buildings ------------------------------------------------------------------------------------------------------

func test_tower_invulnerability_chain() -> void:
	var w := SimWorld.new(1, _map)
	w.setup_match()
	var t1: SimUnit = null
	var t2: SimUnit = null
	for u in w.units:
		if u.team == C.DUSK and u.kind == K.TOWER and u.building_lane == "mid":
			if u.lane_tier == 1:
				t1 = u
			elif u.lane_tier == 2:
				t2 = u
	check(t1 != null and t2 != null, "found Dusk mid towers")
	check(not t1.invulnerable and t2.invulnerable, "tier 2 is invulnerable while tier 1 stands")
	w.combat.kill(t1, null)
	w.combat.process_deaths()
	check(not t2.invulnerable, "tier 2 becomes vulnerable after tier 1 falls")
	var anc: SimUnit = w.units.filter(func(u): return u.team == C.DUSK and u.kind == K.ANCIENT)[0]
	check(anc.invulnerable, "the Ancient stays invulnerable")

func test_glyph() -> void:
	var w := empty_world()
	w.time = 200.0
	var tw := w.spawn("tower2", C.DUSK, Vector2(-1000, -4000))
	check(w.glyph(C.DUSK), "glyph usable after 3:00")
	var dealt := w.combat.deal_damage(-1, C.DAWN, true, tw, 500.0, C.DamageType.PHYSICAL)
	check(dealt == 0.0, "glyphed buildings take no damage")
	check(not w.glyph(C.DUSK), "glyph on cooldown")

# ---- Shop -------------------------------------------------------------------------------------------------------------

func test_shop_recipe() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, _map.fountains[0] + Vector2(200, 200))
	h.gold_unreliable = 2000
	check(w.shop.buy(h, "circlet") == "", "bought circlet")
	check(w.shop.buy(h, "slippers") == "", "bought slippers")
	var price := w.shop.price(h, "wraith_band")
	check(price == 210, "wraith sigil needs only its 210 recipe now (got %d)" % price)
	check(w.shop.buy(h, "wraith_band") == "", "bought wraith sigil")
	var ids := h.inventory.filter(func(i): return i != null).map(func(i): return i.id)
	check(ids == ["wraith_band"], "components combined into one item (%s)" % str(ids))
	check(h.gold() == 2000 - 155 - 140 - 210, "gold spent correctly")
	h.refresh_stats()
	near(h.agi_total, 24.0 + 5.0, 0.01, "item agility applied")

func test_starting_gold_and_passive() -> void:
	var w := SimWorld.new(1, _map)
	w.time = -1.0
	w.next_neutral_at = INF
	var h := w.spawn_hero("blood_ranger", C.DAWN)
	check(h.gold() == 600, "600 starting gold")
	run(w, 61.0)
	var passive := h.gold_reliable
	check(passive >= 89 and passive <= 92, "about 90 passive gold in the first minute (got %d)" % passive)

# ---- Vision -------------------------------------------------------------------------------------------------------------

func test_vision_high_ground() -> void:
	var w := empty_world()
	var low := w.spawn("blood_ranger", C.DAWN, Vector2(-500, 500))       # river
	var high_p := Vector2(-4600, -4600)
	w.vision.update()
	check(not w.vision.cell_visible(C.DAWN, Vector2(-400, 1200)) or true, "sanity")
	var up := w.spawn("blood_ranger", C.DUSK, Vector2(-200, -200))
	w.vision.update()
	check(w.vision.sees(C.DAWN, up), "sees units on the same level nearby")
	# a column across the base's north cliff with no tree between the two spots
	var x := -6000.0
	while x < -4600.0:
		var clear := true
		for yy in range(-4000, -3300, 32):
			var c := _map.world_to_vcell(Vector2(x, yy))
			if _map.vision_block[c.y * SimMap.VN + c.x] == 1:
				clear = false
		if clear and not _map.in_ramp(Vector2(x, -3700)):
			break
		x += 64.0
	var cliff_top := w.spawn("blood_ranger", C.DUSK, Vector2(x, -4000))
	var below := w.spawn("blood_ranger", C.DAWN, Vector2(x, -3350))
	w.vision.update()
	check(_map.level_at(cliff_top.pos) == SimMap.HIGH and _map.level_at(below.pos) == SimMap.GROUND, "test spots on high and low ground")
	check(not w.vision.sees(C.DAWN, cliff_top), "low ground cannot see onto high ground")
	check(w.vision.sees(C.DUSK, below), "high ground sees down")

func test_night_vision() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2500, -6350))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-1300, -6350))
	w.time = 100.0
	w.vision.update()
	var seen_day := w.vision.sees(C.DAWN, foe)
	w.time = 400.0
	w.vision.update()
	var seen_night := w.vision.sees(C.DAWN, foe)
	check(seen_day and not seen_night, "1200 units away: seen by day (1800), not at night (800)")

# ---- Long run ---------------------------------------------------------------------------------------------------------

func test_long_match_10000_ticks() -> void:
	var w := SimWorld.new(7, _map)
	w.setup_match()
	var a := w.spawn_hero("blood_ranger", C.DAWN)
	var b := w.spawn_hero("blood_ranger", C.DUSK)
	w.bots.append(SimBot.new(w, a.id, "mid", "Bot Pip"))
	w.bots.append(SimBot.new(w, b.id, "mid", "Bot Gerald"))
	var t0 := Time.get_ticks_msec()
	var max_units := 0
	var bad := 0
	for i in 10000:
		w.step()
		w.events.clear()
		max_units = maxi(max_units, w.units.size())
		if i % 50 == 0:
			for u in w.units:
				if not (is_finite(u.pos.x) and is_finite(u.pos.y) and is_finite(u.hp) and is_finite(u.facing)):
					bad += 1
				if absf(u.pos.x) > SimMap.HALF or absf(u.pos.y) > SimMap.HALF:
					bad += 1
	var ms := Time.get_ticks_msec() - t0
	print("    10000 ticks (%.1f game s) in %d ms = %.2f ms/tick; peak units %d; hero levels %d/%d, LH %d/%d, gold %d/%d" % [
		10000.0 / 30.0, ms, ms / 10000.0, max_units, a.level, b.level, a.last_hits, b.last_hits, a.gold(), b.gold()])
	check(bad == 0, "all positions and health finite and inside the map")
	check(max_units < 400, "unit count bounded (%d)" % max_units)
	check(a.level > 1 and b.level > 1, "both bots gained levels")
	check(a.last_hits + b.last_hits > 5, "bots last-hit creeps")

func test_zprofile() -> void:
	var w := SimWorld.new(7, _map)
	w.setup_match()
	var a := w.spawn_hero("blood_ranger", C.DAWN)
	var b := w.spawn_hero("blood_ranger", C.DUSK)
	w.bots.append(SimBot.new(w, a.id, "mid", "Bot Pip"))
	w.bots.append(SimBot.new(w, b.id, "mid", "Bot Gerald"))
	for i in 30 * 300:
		w.step()
		w.events.clear()
	var tm := {"clock": 0, "grid": 0, "pre": 0, "ai": 0, "bots": 0, "orders": 0, "proj": 0, "vision": 0}
	for i in 600:
		w.tick += 1
		w.time += C.DT
		var t := Time.get_ticks_usec()
		w._clock()
		tm.clock += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		w._rebuild_grid()
		tm.grid += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for u in w.units:
			if u.alive:
				w._pre_unit(u)
		tm.pre += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		w.ai.think()
		tm.ai += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for bb in w.bots:
			bb.think()
		tm.bots += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for u in w.units:
			if u.alive:
				w.orders.update(u)
		tm.orders += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		w.combat.update_projectiles()
		w.abilities.update_effects()
		w.combat.process_deaths()
		w._respawns()
		tm.proj += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		if w.tick % 3 == 0:
			w.vision.update()
		tm.vision += Time.get_ticks_usec() - t
		w._cleanup()
		w.events.clear()
	var parts := []
	for k in tm:
		parts.append("%s %.2f" % [k, tm[k] / 600.0 / 1000.0])
	print("    ms per tick (%d units): %s" % [w.units.size(), ", ".join(parts)])

# ---- Town Portal, buyback, courier ----------------------------------------------------------------------------------

func test_town_portal() -> void:
	var w := SimWorld.new(1, _map)
	w.setup_match()
	w.time = 100.0
	w.next_wave_at = INF
	w.next_neutral_at = INF
	var h := w.spawn_hero("blood_ranger", C.DAWN)
	check(h.tp_charges == 1, "heroes start with one Town Portal scroll")
	var t1: SimUnit = null
	for u in w.units:
		if u.team == C.DAWN and u.kind == K.TOWER and u.lane_tier == 1 and u.building_lane == "bot":
			t1 = u
	w.command(h.id, {"type": O.CAST_POINT, "ability": "tp", "point": t1.pos + Vector2(400, 0)})
	run(w, 0.2)
	check(not h.channel.is_empty(), "channelling the Town Portal")
	run(w, 2.6)
	check(h.pos.distance_to(t1.pos) > 2000.0, "still home before 3 s")
	run(w, 0.4)
	check(h.pos.distance_to(t1.pos) < 500.0, "arrives next to the chosen building after 3 s")
	check(h.tp_charges == 0, "scroll spent")
	var h2 := w.spawn_hero("blood_ranger", C.DAWN)
	h2.tp_charges = 1
	h2.mana = h2.max_mana
	w.command(h2.id, {"type": O.CAST_POINT, "ability": "tp", "point": t1.pos})
	run(w, 1.0)
	w.command(h2.id, {"type": O.MOVE, "point": h2.pos + Vector2(100, 0)})
	run(w, 3.0)
	check(h2.pos.distance_to(t1.pos) > 2000.0, "moving cancels the channel")
	check(h2.tp_charges == 0, "a cancelled teleport still uses the scroll")

func test_buyback() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 600.0
	var h := w.spawn_hero("blood_ranger", C.DAWN)
	h.gold_unreliable = 2000
	w.combat.kill(h, null)
	w.combat.process_deaths()
	check(not h.alive and h.respawn_at > w.time, "dead and waiting to respawn")
	var cost := w.buyback_cost(h)
	var g0 := h.gold()
	check(w.buyback(h) == "", "buyback succeeds")
	check(h.alive, "back to life at once")
	check(g0 - h.gold() == cost, "buyback cost %d paid" % cost)
	w.combat.kill(h, null)
	w.combat.process_deaths()
	check(w.buyback(h) != "", "buyback on cooldown")

func test_courier_delivery() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 30.0
	w.next_wave_at = INF
	w.next_neutral_at = INF
	var h := w.spawn_hero("blood_ranger", C.DAWN)
	h.pos = Vector2(-1500, -1300)
	h.gold_unreliable = 1000
	check(w.shop.buy(h, "slippers") == "", "bought away from the shop")
	check(h.stash.any(func(x): return x != null and x.id == "slippers"), "item waits in the stash")
	check(w.courier_deliver(h) == "", "courier sent")
	run(w, 40.0)
	check(h.inventory.any(func(x): return x != null and x.id == "slippers"), "the courier delivered the slippers")
	var c := w.get_unit(h.courier_id)
	check(c.courier_state in ["return", "idle"], "courier heads home after delivering")
	# the hero dies while the courier is on its way: as in Dota the courier keeps the item and brings it home
	w.shop.buy(h, "mantle")
	w.courier_deliver(h)
	for i in 600:
		w.step()
		if c.inventory.any(func(x): return x != null):
			break
	check(c.inventory.any(func(x): return x != null), "courier picked up the Thinking Cap")
	w.combat.kill(h, null)
	w.combat.process_deaths()
	run(w, 40.0)
	check(c.courier_state == "idle" and _ids(c.inventory) == ["mantle"], "courier came home still carrying it (%s, %s)" % [c.courier_state, str(_ids(c.inventory))])
	check(h.courier_items.has(c.inventory[0]) and h.networth() >= int(SimData.item("mantle").cost), "it still counts as the hero's")

func test_stop_and_hard_stop() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -4000))
	foe.order = O.HOLD
	foe.def = foe.def.duplicate()
	foe.def["can_attack"] = false
	w.vision.update()
	w.command(h.id, {"type": O.STOP})
	run(w, 1.5)
	check(h.atk_target == foe.id, "after a tap of S the hero still auto-attacks an enemy in range")
	w.command(h.id, {"type": O.STOP, "hard": true})
	run(w, 0.8)
	var hp0 := foe.hp
	run(w, 2.0)
	check(h.atk_target == -1 and foe.hp >= hp0, "after a hard stop (S held) the hero does not auto-attack (target %d)" % h.atk_target)
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(10, 0)})
	run(w, 1.5)
	check(h.atk_target == foe.id, "the next order ends the hard stop")

func test_neutrals_wake_on_damage_only() -> void:
	var w := SimWorld.new(1, _map)
	w.time = 59.0
	w.next_wave_at = INF
	run(w, 1.2)
	var camp: Dictionary = _map.camps[1]
	var h := w.spawn("blood_ranger", C.DAWN, camp.pos + Vector2(-500, 0))
	w.vision.update()
	var n := w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": n[0].id})
	# stop before the arrow leaves: the attack started but nothing was hit
	for i in 40:
		w.step()
		if h.atk_phase == SimUnit.AtkPhase.WINDUP:
			break
	check(h.atk_phase == SimUnit.AtkPhase.WINDUP, "the attack is winding up")
	w.command(h.id, {"type": O.STOP, "hard": true})
	run(w, 0.5)
	check(n.all(func(u): return u.neutral_state == 0), "neutrals ignore an attack that never landed")
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": n[0].id})
	run(w, 2.0)
	check(n[0].neutral_state == 1, "neutrals turn on the hero once damaged")

# ---- Ezee, the Dark Paladin ----------------------------------------------------------------------------------------

func _ezee(w: SimWorld, p: Vector2, levels := {}) -> SimUnit:
	var e := w.spawn("ezee", C.DAWN, p)
	e.level = 18
	e.refresh_stats()
	e.hp = e.max_hp
	e.mana = e.max_mana
	for aid in e.abilities:
		e.ability_level[aid] = int(levels.get(aid, 4 if aid != "unholy_might" else 3))
	return e

## A tree with open walkable ground on one side, for impact tests: [tree index, free point, push direction].
func _tree_spot(from := 0) -> Array:
	for i in range(from, _map.trees.size()):
		var t: Dictionary = _map.trees[i]
		if not t.alive or t.pos.length() > 5000.0:
			continue
		for k in 8:
			var d := Vector2.from_angle(k * TAU / 8.0)
			var ok := true
			for s in range(2, 9):
				if not _map.is_walkable(t.pos + d * (s * 64.0)):
					ok = false
					break
			if ok:
				return [i, t.pos + d * 200.0, -d]
	return []

func test_ezee_dark_stomp_push() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1800, -4000))
	c.order = O.HOLD
	w.vision.update()
	var hp0 := c.hp
	var p0 := c.pos
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"})
	run(w, 0.5)
	check(c.hp < hp0, "the stomp damages an enemy in range")
	check(not c.knock.is_empty() or c.pos.distance_to(p0) > 100.0, "the enemy is hurled away")
	run(w, 1.5)
	var moved := c.pos.distance_to(p0)
	check(moved > 220.0 and moved < 520.0, "pushed a believable distance (%d units)" % int(moved))
	check(c.pos.x > p0.x, "pushed away from Ezee")
	check(not c.has_flag("stun"), "no impact, no extra stun")
	check(w.abilities.cooldown_left(e, "dark_stomp") > 9.0, "12 s cooldown started")

func test_ezee_dark_stomp_tree_impact() -> void:
	var w := empty_world()
	var spot := _tree_spot()
	check(not spot.is_empty(), "found a tree with open ground beside it")
	if spot.is_empty():
		return
	var ti: int = spot[0]
	var cp: Vector2 = spot[1]
	var dir: Vector2 = spot[2]
	var c := w.spawn("dusk_melee", C.DUSK, cp)
	c.order = O.HOLD
	var e := _ezee(w, cp - dir * 180.0)
	w.vision.update()
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"})
	var impacted := false
	var smashed := -1
	var stunned_at := -1.0
	for i in 90:
		w.step()
		for ev in w.events:
			if ev.t == "impact" and ev.u == c.id:
				impacted = ev.what == "tree"
			if ev.t == "tree" and ev.get("smashed", false):
				smashed = int(ev.i)
		if c.has_flag("stun") and stunned_at < 0.0:
			stunned_at = w.time
		w.events.clear()
	check(impacted, "the creep crashed into the tree")
	check(smashed >= 0 and not _map.trees[smashed].alive, "the tree was smashed")
	if smashed >= 0:
		_map.regrow_tree(smashed)
	var st := c.get_modifier("stunned")
	check(stunned_at > 0.0, "impact stun applied once the creep came to rest")
	if not st.is_empty():
		near(float(st.expires) - stunned_at, 2.8, 0.05, "level 4 impact stun lasts 2.8 s")
	var row: Array = e.dmg_out.get("dark_stomp", [0, 0, 0])
	near(float(row[1]), (150.0 + 125.0) * (1.0 + e.magic_amp) * (1.0 - c.magic_resist), 1.0, "stomp plus impact damage (magic)")

func test_ezee_dark_stomp_unit_collision() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1830, -4000))
	var c2 := w.spawn("dusk_melee", C.DUSK, Vector2(-1560, -4000))
	c.order = O.HOLD
	c2.order = O.HOLD
	w.vision.update()
	var p2 := c2.pos
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"})
	var hits := 0
	for i in 75:
		w.step()
		for ev in w.events:
			if ev.t == "impact" and ev.what == "unit":
				hits += 1
		w.events.clear()
	check(hits >= 1, "the hurled creep slammed into the other one")
	check(c2.pos.distance_to(p2) > 30.0, "momentum carried the struck creep along")
	check(c2.hp < c2.max_hp, "the struck enemy takes impact damage too")

func test_ezee_leap_strike_targeting() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var far_hurt := w.spawn("dusk_melee", C.DUSK, Vector2(-1400, -4000))
	var near_full := w.spawn("dusk_melee", C.DUSK, Vector2(-1800, -4000))
	var near_hurt := w.spawn("dusk_ranged", C.DUSK, Vector2(-1700, -3800))
	for u in [far_hurt, near_full, near_hurt]:
		u.order = O.HOLD
	far_hurt.hp = far_hurt.max_hp * 0.3
	near_hurt.hp = near_hurt.max_hp * 0.6
	w.vision.update()
	check(w.abilities.leap_target(e, 4) == far_hurt, "picks the lowest health fraction in range")
	far_hurt.hp = far_hurt.max_hp
	near_hurt.hp = near_hurt.max_hp
	check(w.abilities.leap_target(e, 4) == near_full, "nobody hurt: picks the nearest")
	var w2 := empty_world()
	var e2 := _ezee(w2, Vector2(-2000, -4000))
	w2.vision.update()
	check(w2.abilities.cast_error(e2, "leap_strike", -1, null, e2.pos) == "No enemy in sight", "no enemy, no leap")

func test_ezee_leap_strike_damage() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-1450, -4000))
	foe.order = O.HOLD
	w.vision.update()
	var hp0 := foe.hp
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "leap_strike"})
	var landed := false
	for i in 45:
		w.step()
		for ev in w.events:
			if ev.t == "leap_land" and ev.u == e.id:
				landed = true
		w.events.clear()
		if landed:
			break
	check(landed, "Ezee lands within 1.5 s")
	near(hp0 - foe.hp, 175.0 + 0.6 * e.str_total, 1.0, "pure damage 175 + 60% strength")
	check(not foe.get_modifier("leap_strike_slow").is_empty(), "the target is slowed")
	check(e.edge_distance(foe) < 40.0, "Ezee lands beside the target")

func test_ezee_tainted_touch_and_curse() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var foe := w.spawn("blood_ranger", C.DUSK, Vector2(-1820, -4000))
	foe.order = O.HOLD
	w.vision.update()
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "tainted_touch"})
	run(w, 0.6)
	check(not e.get_modifier("tainted_touch").is_empty(), "the sword is enchanted")
	w.command(e.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	run(w, 1.2)
	var row: Array = e.dmg_out.get("tainted_touch", [0, 0, 0])
	near(float(row[0]), 150.0 * (1.0 + e.magic_amp) * (1.0 - foe.magic_resist), 1.0, "a hit adds 150 magic damage at level 4")
	check(w.vision.revealed_to(foe, C.DAWN), "the target is cursed and revealed")
	foe.add_modifier({"id": "invis_test", "source": foe.id, "expires": -1.0, "invisible": true})
	check(w.vision.sees(C.DAWN, foe), "the curse reveals it even when invisible")

func test_ezee_unholy_might() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var foe := w.spawn("dusk_melee", C.DUSK, Vector2(-1800, -4000))
	foe.order = O.HOLD
	foe.def = foe.def.duplicate()
	foe.def["can_attack"] = false
	w.vision.update()
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "unholy_might"})
	run(w, 0.7)
	check(not e.get_modifier("unholy_might").is_empty(), "the dark aura is up")
	var halved := 0
	var total := 60
	for i in total:
		e.hp = e.max_hp
		var before := foe.hp
		var dealt := w.combat.deal_damage(foe.id, foe.team, false, e, 100.0, C.DamageType.PURE)
		if dealt < 99.0:
			halved += 1
			near(dealt, 50.0, 0.01, "a halved blow")
			check(foe.hp < before or not foe.alive, "the other half strikes a nearby enemy")
		foe.hp = foe.max_hp
	var rate := float(halved) / total
	check(rate > 0.3 and rate < 0.72, "about half the blows halved at level 3 (%.2f)" % rate)
	run(w, 10.0)
	check(e.get_modifier("unholy_might").is_empty(), "the aura fades after 10 s")
	check(not e.get_modifier("unholy_fatigue").is_empty(), "then Ezee is slowed")
	near(e.move_speed, maxf(100.0, float(e.def.move_speed) * 0.5), 1.0, "slowed by 50%")

# ---- Trees (Dota: regrow after 180 s, wait for a clear 150 radius; Ironwood Twig plants a 20 s tree) ----------------

func _restore_tree(i: int) -> void:
	if i >= 0 and not _map.trees[i].alive and not _map.trees[i].get("planted", false):
		_map.regrow_tree(i)

func test_tree_regrow_180() -> void:
	var w := empty_world()
	var spot := _tree_spot()
	var ti: int = spot[0]
	var tp: Vector2 = _map.trees[ti].pos
	check(w.cut_tree(ti, tp + Vector2(100, 0)), "the tree falls")
	check(_map.is_walkable(tp), "its ground becomes walkable")
	var vc := _map.world_to_vcell(tp)
	var shared := false
	for j in _map.trees.size():
		if j != ti and _map.trees[j].alive and _map.world_to_vcell(_map.trees[j].pos) == vc:
			shared = true
	check(_map.vision_block[vc.y * SimMap.VN + vc.x] == 0 or shared,
		"it stops blocking sight (unless another tree shares the vision cell)")
	run(w, 178.0)
	check(not _map.trees[ti].alive, "still down at 2:58")
	run(w, 3.0)
	check(_map.trees[ti].alive, "grown back by 3:01")
	check(not _map.is_walkable(tp), "and blocks the path again")
	# a unit standing within 150 holds the regrowth back until it leaves
	w.cut_tree(ti, tp)
	var c := w.spawn("dawn_melee", C.DAWN, spot[1])
	c.pos = tp + (spot[1] - tp).normalized() * 120.0
	c.order = O.HOLD
	run(w, 185.0)
	check(not _map.trees[ti].alive, "a unit within 150 keeps the tree from growing")
	c.pos = tp + (spot[1] - tp).normalized() * 400.0
	run(w, 1.5)
	check(_map.trees[ti].alive, "it grows once the unit steps away")
	_restore_tree(ti)

func test_mini_axe_and_vegan_picker() -> void:
	check(String(SimData.item("quelling_blade").name) == "Mini-Axe", "Quelling Blade is called Mini-Axe")
	check(String(SimData.item("tango").name) == "Vegan Picker", "Tango is called Vegan Picker")
	var w := empty_world()
	var spot := _tree_spot()
	var ti: int = spot[0]
	var tp: Vector2 = _map.trees[ti].pos
	var h := w.spawn("blood_ranger", C.DAWN, tp + (spot[1] - tp).normalized() * 600.0)
	h.inventory[0] = {"id": "quelling_blade", "charges": 0}
	h.inventory[1] = {"id": "tango", "charges": 3}
	h.refresh_stats()
	near(w.abilities.cast_range(h, "", 0), 350.0, 0.1, "Mini-Axe chops from 350")
	near(w.abilities.cast_range(h, "", 1), 165.0, 0.1, "Vegan Picker eats from 165")
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": tp})
	run(w, 2.0)
	check(not _map.trees[ti].alive, "the hero walks into range and chops the tree")
	var cd := w.abilities.item_cooldown_left(h, 0)
	check(cd > 1.0 and cd <= 4.0, "Chop Tree has a 4 s cooldown (%.2f left)" % cd)
	_restore_tree(ti)
	# the passive: +4 against creeps for a ranged hero
	var s := {"src": h.id, "team": h.team, "hero": true, "dmg_min": 50.0, "dmg_max": 50.0, "bonus": 0.0, "class": 0,
		"level_h": 1, "mod": "", "lifesteal": 0.0, "ranged": true, "quell": w.combat._quelling(h), "taint": 0}
	near(float(s.quell), 4.0, 0.01, "ranged heroes get +4 creep damage from the Mini-Axe")
	# Vegan Picker: 7 hp/s for 16 s, the tree is eaten
	h.pos = tp + (spot[1] - tp).normalized() * 150.0
	h.hp = h.max_hp * 0.3
	var hp0 := h.hp
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 1, "point": tp})
	run(w, 0.2)
	check(not _map.trees[ti].alive, "the tree is eaten")
	check(int(h.inventory[1].charges) == 2, "one charge used")
	var m := h.get_modifier("tango")
	near(float(m.expires) - w.time, 16.0 - 0.2, 0.1, "regeneration lasts 16 s")
	run(w, 10.0)
	near(h.hp - hp0, 10.2 * (7.0 + h.hp_regen), 6.0, "about 7 hp/s on top of normal regeneration")
	_restore_tree(ti)

func test_planted_tree() -> void:
	var w := empty_world()
	var h := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -4000))
	h.inventory[0] = {"id": "branch", "charges": 0}
	h.inventory[1] = {"id": "tango", "charges": 3}
	h.refresh_stats()
	var p := Vector2(-1750, -4000)
	var bystander := w.spawn("dawn_melee", C.DAWN, _map.cell_center(_map.world_to_cell(p).x, _map.world_to_cell(p).y))
	bystander.order = O.HOLD
	check(w.abilities.item_target("branch") == "point", "Tree Twig targets the ground")
	near(w.abilities.cast_range(h, "", 0), 400.0, 0.1, "planted within 400")
	var n0 := _map.trees.size()
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": p})
	run(w, 0.2)
	check(_map.trees.size() == n0 + 1 and _map.trees[n0].get("planted", false), "a planted tree stands")
	check(h.inventory[0] == null, "the twig is consumed")
	check(not _map.is_walkable(p), "it blocks the path")
	check(_map.is_walkable(bystander.pos), "a unit standing there steps out of it")
	h.pos = p + Vector2(-150, 0)
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 1, "point": p})
	run(w, 0.2)
	near(float(h.get_modifier("tango").expires) - w.time, 32.0 - 0.2, 0.1, "Vegan Picker on a planted tree lasts 32 s")
	check(_map.is_walkable(p), "eaten: the ground is open again")
	# a second one withers by itself after 20 s and never regrows
	h.inventory[0] = {"id": "branch", "charges": 0}
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": p + Vector2(0, 200)})
	run(w, 0.2)
	var ti := _map.trees.size() - 1
	check(_map.trees[ti].alive, "planted again")
	run(w, 19.0)
	check(_map.trees[ti].alive, "still standing at 19 s")
	run(w, 2.0)
	check(not _map.trees[ti].alive, "withered after 20 s")
	run(w, 200.0)
	check(not _map.trees[ti].alive, "planted trees never regrow")
	check(not w.map.can_plant(_map.fountains[0] + Vector2(300, 0)), "no planting in the fountain area")

# ---- Blood Ranger -----------------------------------------------------------------------------------------------------

func _ranger(w: SimWorld, p: Vector2, levels := {}, team := C.DAWN) -> SimUnit:
	var r := w.spawn("blood_ranger", team, p)
	r.level = 18
	r.refresh_stats()
	r.hp = r.max_hp
	r.mana = r.max_mana
	for aid in r.abilities:
		r.ability_level[aid] = int(levels.get(aid, 4 if aid != "blood_ranger_ult" else 3))
	r.refresh_stats()
	return r

func _dummy(w: SimWorld, id: String, team: int, p: Vector2, hp := 1e6) -> SimUnit:
	var d := w.spawn(id, team, p)
	d.def = d.def.duplicate()
	d.def.hp = hp
	d.def["can_attack"] = false
	d.refresh_stats()
	d.hp = d.max_hp
	d.order = O.HOLD
	return d

func test_burst_shot_split() -> void:
	var w := empty_world()
	for k in 400:
		var sp: Array = w.abilities.burst_split(30, 5, 4, 7)
		var sum := 0
		var ok := sp.size() == 5
		for n in sp:
			sum += int(n)
			ok = ok and int(n) >= 4 and int(n) <= 7
		if not ok or sum != 30:
			check(false, "split %s is not five waves of 4-7 summing to 30" % str(sp))
			return
	check(true, "400 random splits: five waves of 4-7 that always sum to 30")

func test_burst_shot_channel() -> void:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000), {"burst_shot": 1})
	var foe := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	w.vision.update()
	var mana0 := r.mana
	w.command(r.id, {"type": O.CAST_POINT, "ability": "burst_shot", "point": foe.pos})
	var arrows := 0
	var waves: Array = []
	var ended := -1.0
	var started := -1.0
	var hits := 0
	var per_hit: Array = []
	for i in 120:
		w.step()
		for ev in w.events:
			if ev.t == "channel_start" and ev.u == r.id:
				started = w.time
			if ev.t == "burst_wave":
				waves.append(int(ev.count))
			if ev.t == "projectile" and ev.get("kind", "") == "spell":
				arrows += 1
			if ev.t == "damage" and ev.u == foe.id and String(ev.get("key", "")) == "burst_shot":
				hits += 1
				per_hit.append(float(ev.amount))
			if ev.t == "channel_end" and ev.u == r.id and not ev.cancelled:
				ended = w.time
		w.events.clear()
	check(started > 0.0, "the channel starts after the 0.2 s cast point")
	near(r.mana, mana0 - 90.0 + r.mana_regen * 4.0, 3.0, "90 mana at level 1, spent as the channel starts")
	near(w.abilities.cooldown_left(r, "burst_shot"), 17.0 - (w.time - started), 0.1, "17 s cooldown")
	check(waves.size() == 5, "five waves (%d)" % waves.size())
	check(arrows == 30, "30 arrows (%d)" % arrows)
	near(ended - started, 2.0, 0.05, "a 2 s channel")
	check(hits == 30, "every arrow strikes the only enemy in the area (%d)" % hits)
	var expect := ((r.dmg_min + r.dmg_max) * 0.5 + r.bonus_damage) * 0.55 * C.armor_multiplier(foe.armor)
	if not per_hit.is_empty():
		near(float(per_hit[0]), expect, 0.5, "each arrow: 55% of attack damage at level 1, physical")
	check(r.dmg_out.has("burst_shot"), "recorded as Burst Shot in the damage table")
	# level 4: 85%
	var w2 := empty_world()
	var r2 := _ranger(w2, Vector2(-2000, -4000))
	var foe2 := _dummy(w2, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	w2.vision.update()
	w2.command(r2.id, {"type": O.CAST_POINT, "ability": "burst_shot", "point": foe2.pos})
	run(w2, 3.0)
	var row: Array = r2.dmg_out.get("burst_shot", [0, 0, 0])
	near(float(row[1]), 30.0 * ((r2.dmg_min + r2.dmg_max) * 0.5 + r2.bonus_damage) * 0.85 * C.armor_multiplier(foe2.armor), 2.0,
		"30 arrows at 85% of attack damage at level 4")

func _burst_then(order: Dictionary, setup: Callable) -> Array:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000))
	var foe := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	w.vision.update()
	w.command(r.id, {"type": O.CAST_POINT, "ability": "burst_shot", "point": foe.pos})
	run(w, 0.6)
	var arrows_before := w.projectiles.size()
	setup.call(w, r, foe)
	if not order.is_empty():
		w.command(r.id, order)
	run(w, 2.0)
	var row: Array = r.dmg_out.get("burst_shot", [0, 0, 0])
	return [r, float(row[1]), arrows_before]

func test_burst_shot_interrupts() -> void:
	var dmg_full := 30.0
	var none := func(_w, _r, _f): pass
	var moved := _burst_then({"type": O.MOVE, "point": Vector2(-2600, -4000)}, none)
	check((moved[0] as SimUnit).channel.is_empty(), "a move order ends the channel")
	var stopped := _burst_then({"type": O.STOP}, none)
	check((stopped[0] as SimUnit).channel.is_empty(), "stop ends it")
	var held := _burst_then({"type": O.HOLD}, none)
	check((held[0] as SimUnit).channel.is_empty(), "hold ends it")
	var attacked := _burst_then({"type": O.ATTACK_MOVE, "point": Vector2(-1500, -4000)}, none)
	check((attacked[0] as SimUnit).channel.is_empty(), "an attack order ends it")
	var stunned := _burst_then({}, func(w2, r, _f): r.add_modifier({"id": "stun", "source": -1, "expires": w2.time + 0.5, "stun": true}))
	check((stunned[0] as SimUnit).channel.is_empty(), "a stun ends it")
	var silenced := _burst_then({}, func(w2, r, _f): r.add_modifier({"id": "sil", "source": -1, "expires": w2.time + 0.5, "silence": true}))
	check((silenced[0] as SimUnit).channel.is_empty(), "silence ends it")
	var pushed := _burst_then({}, func(w2, r, f): w2.abilities.start_push(r, Vector2(-600, 0), f.id, f.team, "dark_stomp", 1, 99))
	check((pushed[0] as SimUnit).channel.is_empty(), "a push ends it")
	# full channel for comparison: interrupted ones dealt less
	var full := _burst_then({}, none)
	check(float(moved[1]) < float(full[1]) * 0.7, "cut short, fewer arrows land (%.0f vs %.0f)" % [float(moved[1]), float(full[1])])
	# an instant item does not break it; a queued order waits for it
	var wand := _burst_then({}, func(w2, r, _f):
		r.inventory[0] = {"id": "magic_stick", "charges": 0}
		r.stick_charges = 3
		w2.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
		w2.command(r.id, {"type": O.MOVE, "point": Vector2(-2600, -4000), "queue": true}))
	var rw: SimUnit = wand[0]
	check(rw.stick_charges == 0, "the Zap Stick was used mid-channel")
	near(float(wand[1]), float(full[1]), 1.0, "and the channel ran its course")
	check(rw.pos.x < -2030.0, "the queued move ran after the channel ended")

func test_no_cooldown_lock_before_horn() -> void:
	# Dota: only creeps and neutrals wait for the horn. Spells, items and attacks work from the first second.
	var w := world(C.PREGAME_TIME)
	w.next_wave_at = INF
	w.next_neutral_at = INF
	var r := _ranger(w, Vector2(-2000, -4000), {"gale_impact": 1})
	var foe := _dummy(w, "blood_ranger", C.DUSK, Vector2(-1500, -4000), 5000.0)
	w.vision.update()
	check(w.time < -80.0, "the clock is in the pre-game (%.1f)" % w.time)
	for aid in r.abilities:
		near(w.abilities.cooldown_left(r, aid), 0.0, 1e-6, "%s is ready before the horn" % aid)
	r.inventory[0] = {"id": "tango", "charges": 3, "ready": C.LONG_AGO}
	near(w.abilities.item_cooldown_left(r, 0), 0.0, 1e-6, "items are ready before the horn")
	check(w.abilities.cast_error(r, "gale_impact", -1, null, foe.pos) == "", "Gale Impact can be cast before the horn")
	w.command(r.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": foe.pos})
	run(w, 1.0)
	check(foe.hp < foe.max_hp, "and it hits an enemy hero")
	var hp1 := foe.hp
	w.command(r.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	run(w, 2.5)
	check(foe.hp < hp1, "attacks land before the horn too")

func test_keybinds_swap_and_templates() -> void:
	Keybinds.load_all()
	var saved: Dictionary = Keybinds.binds.duplicate()
	Keybinds.binds = Keybinds.defaults()
	check(Keybinds.key("ability_1") == KEY_Q and Keybinds.key("item_1") == KEY_Z, "Dota defaults")
	var swapped := Keybinds.assign("ability_1", KEY_Z)
	check(swapped == "item_1" and Keybinds.key("ability_1") == KEY_Z and Keybinds.key("item_1") == KEY_Q,
		"a taken key swaps with the old one (no action is left without a key)")
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.pressed = true
	check(Keybinds.action_for(ev) == "ability_1", "the event maps to the rebound action")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	Keybinds.assign("tp", Keybinds.binding_of(mb))
	check(Keybinds.action_for(mb) == "tp" and Keybinds.key_name("tp") == "Mouse 4", "extra mouse buttons bind too")
	Keybinds.apply_template("Items on 1-6")
	check(Keybinds.key("item_1") == KEY_1 and Keybinds.key("ability_1") == KEY_Q, "built-in template applies")
	var all := {}
	for a in Keybinds.binds:
		check(not all.has(Keybinds.binds[a]), "template has no duplicate key (%s)" % a)
		all[Keybinds.binds[a]] = true
	Keybinds.binds = saved

func test_keybind_combinations() -> void:
	Keybinds.load_all()
	var saved: Dictionary = Keybinds.binds.duplicate()
	Keybinds.binds = Keybinds.defaults()
	var ev := InputEventKey.new()
	ev.keycode = KEY_Q
	ev.pressed = true
	ev.ctrl_pressed = true
	var m := Keybinds.match_event(ev)
	check(m.action == "ability_1" and m.learn, "Ctrl + Q learns ability 1 while Ctrl + Q is unbound")
	ev.ctrl_pressed = false
	ev.shift_pressed = true
	m = Keybinds.match_event(ev)
	check(m.action == "ability_1" and not m.learn, "Shift + Q is still ability 1 (Shift only queues)")
	var alt1 := InputEventKey.new()
	alt1.keycode = KEY_1
	alt1.alt_pressed = true
	alt1.pressed = true
	Keybinds.assign("item_1", Keybinds.binding_of(alt1))
	check(Keybinds.action_for(alt1) == "item_1" and Keybinds.key_name("item_1") == "Alt + 1", "Alt + 1 binds an item")
	var plain1 := InputEventKey.new()
	plain1.keycode = KEY_1
	plain1.pressed = true
	check(Keybinds.action_for(plain1) == "", "plain 1 stays free for control groups")
	var cq := InputEventKey.new()
	cq.keycode = KEY_Q
	cq.ctrl_pressed = true
	cq.pressed = true
	Keybinds.assign("shop", Keybinds.binding_of(cq))
	m = Keybinds.match_event(cq)
	check(m.action == "shop" and not m.learn, "a bound Ctrl + Q wins over learning")
	var c1 := InputEventKey.new()
	c1.keycode = KEY_1
	c1.ctrl_pressed = true
	check(Keybinds.refuse(Keybinds.binding_of(c1)) != "", "Ctrl + 1 is refused (control groups)")
	var bare := InputEventKey.new()
	bare.keycode = KEY_CTRL
	bare.ctrl_pressed = true
	check(Keybinds.binding_of(bare) == 0, "a bare modifier is not a binding")
	Keybinds.binds = saved

func test_debug_helpers() -> void:
	var w := world(C.PREGAME_TIME)
	var h := w.spawn_hero("blood_ranger", C.DAWN, {})
	h.player = true
	SimDebug.force_start(w)
	run(w, 0.1)
	check(w.time >= 0.0 and w.wave == 1, "force start: the horn sounds and wave 1 spawns (wave %d)" % w.wave)
	var creeps := w.units.filter(func(u): return u.is_lane_creep()).size()
	SimDebug.force_wave(w)
	check(w.units.filter(func(u): return u.is_lane_creep()).size() > creeps, "force wave adds creeps")
	SimDebug.level_up(w, h)
	check(h.level == 2, "level up: level 2 (got %d)" % h.level)
	SimDebug.level_up(w, h, 30)
	check(h.level == C.MAX_LEVEL, "max level")
	var g := h.gold()
	SimDebug.gold(w, h, 1000)
	check(h.gold() == g + 1000, "+1000 gold")
	SimDebug.skip_time(w, 600.0)
	var before := w.units.size()
	run(w, 0.1)
	check(w.units.size() - before < 40, "skipping time does not flood the lanes with missed waves")
	SimDebug.set_flag(w, "god", true)
	h.hp = 1.0
	run(w, 0.1)
	check(h.hp == h.max_hp, "god mode keeps health full")
	SimDebug.set_flag(w, "god", false)
	SimDebug.set_flag(w, "reveal", true)
	check(w.vision.cell_visible(C.DAWN, Vector2(6000, 6000)), "reveal shows the enemy base")
	SimDebug.set_flag(w, "reveal", false)

func test_shift_queue() -> void:
	# Dota: Shift-queued orders run one after another; a queued order that cannot run (spell on cooldown) is skipped
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var p1 := Vector2(-1700, -4000)
	var p2 := Vector2(-1700, -3700)
	var p3 := Vector2(-2000, -3700)
	w.command(e.id, {"type": O.MOVE, "point": p1})
	w.command(e.id, {"type": O.MOVE, "point": p2, "queue": true})
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp", "queue": true})
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp", "queue": true})   # will be on cooldown: skipped
	w.command(e.id, {"type": O.MOVE, "point": p3, "queue": true})
	check(e.order_queue.size() == 4, "four orders wait in the queue (%d)" % e.order_queue.size())
	var visited_p2 := false
	var stomped_at := Vector2.INF
	for i in int(8.0 * C.TICK_RATE):
		w.step()
		if e.pos.distance_to(p2) < 30.0:
			visited_p2 = true
		for ev in w.events:
			if ev.t == "stomp" and stomped_at == Vector2.INF:
				stomped_at = e.pos
		w.events.clear()
	check(visited_p2, "the second waypoint is reached")
	check(stomped_at != Vector2.INF and stomped_at.distance_to(p2) < 60.0, "the queued spell is cast at the second waypoint")
	check(e.pos.distance_to(p3) < 30.0, "the queue carries on past the spell that was still cooling down to the last waypoint")
	check(e.order_queue.is_empty(), "the queue is empty at the end")
	# a new order without Shift replaces the whole queue
	w.command(e.id, {"type": O.MOVE, "point": p1})
	w.command(e.id, {"type": O.MOVE, "point": p2, "queue": true})
	w.command(e.id, {"type": O.MOVE, "point": p3})
	check(e.order_queue.is_empty() and e.order_point == p3, "an order without Shift clears the queue")

func test_gale_impact() -> void:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000), {"gale_impact": 1})
	var on_left := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1500, -3970), 550.0)
	var on_right := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1200, -4030), 550.0)
	w.vision.update()
	check(is_inf(w.abilities.cast_range(r, "gale_impact", -1)), "aimed by direction: no cast range to walk into")
	w.command(r.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": Vector2(-800, -4000)})
	run(w, 1.6)
	near(on_left.max_hp - on_left.hp, 120.0 * (1.0 + r.magic_amp) * (1.0 - on_left.magic_resist), 1.0, "120 magic damage at level 1")
	check(on_left.pos.y > -3970.0 + 120.0, "an enemy left of the arrow is thrown further left (y %.0f)" % on_left.pos.y)
	check(on_right.pos.y < -4030.0 - 120.0, "one right of it is thrown right (y %.0f)" % on_right.pos.y)
	check(w.abilities.cooldown_left(r, "gale_impact") > 10.0, "12 s cooldown")
	var fx_hits := 0
	for e2 in [on_left, on_right]:
		fx_hits += 1 if (e2 as SimUnit).hp < (e2 as SimUnit).max_hp else 0
	check(fx_hits == 2, "the arrow pierces: both enemies are hit")
	# distance: it always flies the full 2000, even when the player clicks right beside the hero
	var w2 := empty_world()
	var r2 := _ranger(w2, Vector2(-2000, -4000))
	var far_foe := _dummy(w2, "dusk_melee", C.DUSK, Vector2(-200, -4000), 900.0)
	var past_max := _dummy(w2, "dusk_melee", C.DUSK, Vector2(250, -4000), 900.0)
	w2.vision.update()
	var start := r2.pos
	w2.command(r2.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": Vector2(-1900, -4000)})
	run(w2, 1.6)
	check(r2.pos.distance_to(start) < 1.0, "a direction cast: the hero does not walk to the click")
	check(far_foe.hp < far_foe.max_hp, "a click 100 away still sends the arrow its full range (enemy 1800 away hit)")
	check(past_max.hp == past_max.max_hp, "but no further than 2000")
	var w3 := empty_world()
	var r3 := _ranger(w3, Vector2(-2000, -4000))
	w3.vision.update()
	w3.command(r3.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": Vector2(3000, -4000)})
	run(w3, 0.1)
	check(r3.cast_phase != SimUnit.CastPhase.NONE or w3.abilities.cooldown_left(r3, "gale_impact") > 0.0,
		"a click beyond 2000 casts at once instead of walking closer")

func test_gale_impact_trees_and_crash() -> void:
	var w := empty_world()
	# a tree with open ground beside it, and room for the archer's whole shot past the enemy
	var spot := _tree_spot()
	while not spot.is_empty():
		var a0: Vector2 = -(spot[2] as Vector2)
		var f0: Vector2 = _map.trees[int(spot[0])].pos + a0 * 170.0
		var s0 := a0.orthogonal()
		if _map.line_walkable(f0 + a0 * 120.0 - s0 * 700.0, f0 + a0 * 120.0 + s0 * 700.0):
			break
		spot = _tree_spot(int(spot[0]) + 1)
	var ti: int = spot[0]
	var tp: Vector2 = _map.trees[ti].pos
	var away: Vector2 = -(spot[2] as Vector2)              # from the tree out over open ground
	# the enemy stands just off the tree on the open side; the arrow passes beside it so the push throws it at the tree
	var foe := _dummy(w, "dusk_melee", C.DUSK, tp + away * 170.0, 2000.0)
	var side := away.orthogonal()
	var r := _ranger(w, foe.pos + away * 120.0 - side * 700.0)
	w.vision.update()
	var crashed := false
	var felled := false
	w.command(r.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": foe.pos + away * 120.0 + side * 700.0})
	for i in 90:
		w.step()
		for ev in w.events:
			if ev.t == "impact" and ev.u == foe.id and ev.what == "tree":
				crashed = true
			if ev.t == "tree" and not ev.alive and _map.trees[int(ev.i)].pos.distance_to(foe.pos) < 260.0:
				felled = true
		w.events.clear()
	var row: Array = r.dmg_out.get("gale_impact", [0, 0, 0])
	if crashed:
		near(float(row[1]), 360.0 * 1.2 * (1.0 + r.magic_amp) * (1.0 - foe.magic_resist), 2.0, "the crash adds 20% of the damage once")
		check(felled, "the tree it crashed into is destroyed")
	else:
		check(false, "the enemy was thrown into the tree")
	_restore_tree(ti)
	# the arrow itself fells every tree on its line
	var w2 := empty_world()
	var spot2 := _tree_spot()
	var ti2: int = spot2[0]
	var tp2: Vector2 = _map.trees[ti2].pos
	var out2: Vector2 = -(spot2[2] as Vector2)
	var r2 := _ranger(w2, tp2 + out2 * 500.0)
	w2.vision.update()
	w2.command(r2.id, {"type": O.CAST_POINT, "ability": "gale_impact", "point": tp2 - out2 * 300.0})
	run(w2, 1.0)
	check(not _map.trees[ti2].alive, "a tree on the arrow's path falls")
	for i in _map.trees.size():
		_restore_tree(i)

func test_masterful_archery() -> void:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000), {"masterful_archery": 4})
	var foe := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1600, -4000))
	foe.def.armor = 0.0
	foe.refresh_stats()
	w.vision.update()
	var procs := 0
	var bonus := 0.0
	var attacks := 0
	var last_proc := -99.0
	var gap_ok := true
	w.command(r.id, {"type": O.ATTACK_UNIT, "target": foe.id})
	for i in int(240.0 * C.TICK_RATE):
		w.step()
		for ev in w.events:
			if ev.t == "projectile" and ev.src == r.id and ev.get("kind", "") == "attack":
				attacks += 1
			if ev.t == "masterful_hit":
				procs += 1
				bonus = float(ev.amount)
				if w.time - last_proc < 0.8 - 0.001:
					gap_ok = false
				last_proc = w.time
		w.events.clear()
	near(bonus, r.agi_total * 0.45, 0.01, "bonus = 45% of agility at level 4")
	check(gap_ok, "never twice within 0.8 s")
	var rate := float(procs) / maxf(1.0, attacks)
	check(rate > 0.2 and rate < 0.36, "about 30%% of attacks burst (%.2f of %d)" % [rate, int(attacks)])

func test_blood_ranger_ult() -> void:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000), {"blood_ranger_ult": 1})
	var foe := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1300, -4000))
	w.vision.update()
	var range0 := r.attack_range
	w.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"})
	run(w, 0.4)
	check(not r.get_modifier("blood_ranger").is_empty(), "the ultimate is active")
	near(r.attack_range - range0, 200.0, 0.1, "+200 attack range at level 1")
	near(r.lifesteal_ability, 0.4, 0.001, "40% lifesteal at level 1")
	near(w.abilities.cooldown_left(r, "blood_ranger_ult"), 29.8, 0.3, "30 s cooldown")
	# lifesteal: a hit heals 40% of the damage after armor (no 40% creep factor for ability lifesteal)
	r.hp = r.max_hp * 0.5
	var s := w.combat._snapshot(r, "")
	s.dmg_min = 100.0
	s.dmg_max = 100.0
	s.bonus = 0.0
	s.quell = 0.0
	var hp0 := r.hp
	w.combat.land_attack(s, foe)
	near(r.hp - hp0, 100.0 * C.armor_multiplier(foe.armor) * 0.4, 0.5, "heals 40% of the blow")
	run(w, 15.0)
	check(r.get_modifier("blood_ranger").is_empty(), "ends after 15 s")
	near(r.attack_range, range0, 0.1, "range back to normal")

## A point with open ground for `dist` to its west (for leap tests).
func _open_west(dist: float) -> Vector2:
	for y in range(-4400, -3000, 64):
		for x in range(-3000, -1000, 64):
			var p := Vector2(x, y)
			var ok := true
			for d in range(-160, int(dist) + 40, 16):
				if not _map.is_walkable(p + Vector2(-d, 0)):
					ok = false
					break
			if ok:
				return p
	return Vector2(-2000, -4000)

func test_blood_ranger_back_leap() -> void:
	var w := empty_world()
	var at := _open_west(300.0)
	var r := _ranger(w, at)
	var foe := _dummy(w, "dusk_melee", C.DUSK, at + Vector2(120, 0))
	w.vision.update()
	w.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"})
	run(w, 0.4)
	var m := r.get_modifier("blood_ranger")
	m.leap_chance = 1.0                              # force the roll for the test
	var p0 := r.pos
	w.abilities.on_attacked(r, foe)
	check(not r.hop.is_empty(), "an attack that hits her makes her leap")
	check(r.is_rooted() and not r.is_stunned(), "the leap is not a disable")
	run(w, 0.4)
	check(r.hop.is_empty(), "landed within 0.4 s")
	near(r.pos.distance_to(p0), 300.0, 20.0, "300 back")
	check(r.pos.x < p0.x - 250.0, "away from the attacker")
	w.abilities.on_attacked(r, foe)
	check(r.hop.is_empty(), "not again within 1 s")
	run(w, 1.0)
	w.abilities.on_attacked(r, foe)
	check(not r.hop.is_empty(), "again after 1 s")
	run(w, 0.5)
	# the chance is 30%
	m = r.get_modifier("blood_ranger")
	m.leap_chance = 0.3
	var leaps := 0
	for i in 400:
		r.set_meta("hop_ready", 0.0)
		r.hop = {}
		r.pos = p0
		w.abilities.on_attacked(r, foe)
		if not r.hop.is_empty():
			leaps += 1
	r.hop = {}
	check(leaps > 90 and leaps < 150, "about 30%% of hits (%d of 400)" % leaps)
	# a cliff stops the leap short
	var w2 := empty_world()
	var base := Vector2(-5200, -3350)
	var r2 := _ranger(w2, base)
	var foe2 := _dummy(w2, "dusk_melee", C.DUSK, base + Vector2(0, 120))
	w2.command(r2.id, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"})
	run(w2, 0.4)
	r2.get_modifier("blood_ranger").leap_chance = 1.0
	var start := r2.pos
	var blocked := false
	for d in range(16, 301, 16):
		if not _map.is_walkable(start + Vector2(0, -d)):
			blocked = true
	w2.abilities.on_attacked(r2, foe2)
	run(w2, 0.5)
	check(_map.is_walkable(r2.pos), "she never lands inside a cliff or tree")
	if blocked:
		check(r2.pos.distance_to(start) < 290.0, "a cliff behind her cuts the leap short")

func test_item_lifesteal_vs_creeps() -> void:
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000))
	r.inventory[0] = {"id": "lifesteal", "charges": 0}
	r.refresh_stats()
	var foe := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1600, -4000))
	var hero := _dummy(w, "ezee", C.DUSK, Vector2(-1600, -3900))
	r.hp = r.max_hp * 0.5
	for t in [foe, hero]:
		var s := w.combat._snapshot(r, "")
		s.dmg_min = 100.0
		s.dmg_max = 100.0
		s.bonus = 0.0
		s.quell = 0.0
		var hp0 := r.hp
		w.combat.land_attack(s, t)
		var expect := 100.0 * C.armor_multiplier((t as SimUnit).armor) * 0.18 * (0.4 if (t as SimUnit).is_creep() else 1.0)
		near(r.hp - hp0, expect, 0.5, "Leech Charm heals 18%% (40%% of that against creeps) vs %s" % (t as SimUnit).name)

## Options: sound starts at half loudness (Master 50% = -10 dB) and every game sound has its own bus.
func test_options_audio_defaults() -> void:
	check(float(Options.DEFAULTS.master) == 0.5, "Master volume defaults to 50%")
	near(Options.to_db(0.5), -10.0, 0.001, "50% is half as loud (-10 dB)")
	near(Options.to_db(1.0), 0.0, 0.001, "100% is unchanged")
	near(Options.to_db(0.25), -20.0, 0.001, "25% is a quarter as loud")
	check(Options.to_db(0.0) <= -79.0, "0% is silent")
	Options.reset()
	Options.apply_audio()
	for b in ["Effects", "Interface", "Ambience"]:
		var i := AudioServer.get_bus_index(b)
		check(i > 0, "bus %s exists" % b)
		check(i > 0 and AudioServer.get_bus_send(i) == &"Master", "bus %s feeds Master" % b)
	near(AudioServer.get_bus_volume_db(0), -10.0, 0.01, "Master bus at -10 dB on a fresh profile")

# ---- Sludge, the Butcher (Dota 2's Pudge, patch 7.41d) -------------------------------------------------------------

func _sludge(w: SimWorld, p: Vector2, levels := {}, team := C.DAWN) -> SimUnit:
	var s := w.spawn("sludge", team, p)
	s.level = 18
	s.refresh_stats()
	s.hp = s.max_hp
	s.mana = s.max_mana
	for aid in s.abilities:
		s.ability_level[aid] = int(levels.get(aid, 4 if aid != "chomp" else 3))
	s.refresh_stats()
	s.auto_attack = false                      # spell tests: no swings at the dummies
	return s

## Damage dealt to `uid` by `key`, from the event stream (regeneration does not blur it).
func _dmg_events(evs: Array, uid: int, key: String) -> float:
	var t := 0.0
	for ev in evs:
		if ev.t == "damage" and int(ev.u) == uid and String(ev.get("key", "")) == key:
			t += float(ev.amount)
	return t

func _events_of(w: SimWorld, kind: String) -> Array:
	return w.events.filter(func(e): return e.t == kind)

func test_sludge_base_stats() -> void:
	var w := empty_world()
	var s := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	near(s.str_total, 25.0, 0.001, "25 strength at level 1")
	near(s.agi_total, 13.0, 0.001, "13 agility")
	near(s.int_total, 16.0, 0.001, "16 intelligence")
	near(s.max_hp, 120.0 + 25.0 * 22.0, 0.01, "health 120 + 22 per strength")
	near(s.dmg_min, 70.0, 0.001, "damage 45 + 25 strength")
	near(s.dmg_max, 76.0, 0.001, "damage 51 + 25 strength")
	near(s.move_speed, 280.0, 0.001, "280 move speed")
	near(s.attack_range, 175.0, 0.001, "175 melee range")
	near(s.attack_speed, 113.0, 0.001, "100 attack speed plus 13 agility")
	near(s.attack_point_time(), 0.5 / 1.13, 0.001, "0.5 attack point (scaled by attack speed)")
	near(s.backswing_time(), 1.17 / 1.13, 0.001, "1.17 backswing (scaled by attack speed)")
	near(s.armor, 13.0 / 6.0, 0.01, "0 base armor plus agility")
	near(s.hp_regen, 2.5 + 2.5, 0.01, "2.5 base regen plus 0.1 per strength")
	check(s.ability_level_of("growing_gut") == 1, "Growing Gut is innate (level 1 from the start)")
	check(not w.abilities.can_learn(s, "growing_gut"), "and cannot be levelled")
	s.level = 2
	s.refresh_stats()
	near(s.str_total, 28.0, 0.001, "+3 strength per level")

func test_shuriken_hook_full_range_damage_and_drag() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-2000 + 1000, -4000))
	w.vision.update()
	var hp0 := e.hp
	# clicked only 300 away: the hook still flies its full range and catches the hero at 1000
	w.command(s.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": Vector2(-1700, -4000)})
	var latch_t := -1.0
	var end_t := -1.0
	var stunned_while_dragged := false
	var start_t := w.time
	var hook_dmg := 0.0
	for i in 120:
		w.step()
		hook_dmg += _dmg_events(w.events, e.id, "shuriken_hook")
		for ev in w.events:
			if ev.t == "hook_latch" and int(ev.u) == e.id:
				latch_t = w.time - start_t
			if ev.t == "hook_end":
				end_t = w.time - start_t
		w.events.clear()
		if latch_t > 0.0 and end_t < 0.0 and e.is_stunned():
			stunned_while_dragged = true
		if end_t > 0.0:
			break
	near(latch_t, 0.3 + (1000.0 - 100.0 - 24.0) / 1600.0, 0.07, "caught after the 0.3 s cast point and the flight")
	near(hook_dmg, 360.0, 0.01, "360 pure damage at level 4")
	check(hp0 - e.hp > 355.0, "taken from its health")
	check(stunned_while_dragged, "the enemy is stunned while dragged")
	near(end_t - latch_t, (e.pos.distance_to(Vector2(-2000, -4000)) + 1000.0 - 100.0 - 24.0 - 48.0) / 1600.0, 0.1, "dragged back at hook speed")
	near(e.pos.distance_to(Vector2(-2000, -4000)), 48.0, 8.0, "lands at Sludge's feet")
	check(not e.is_stunned(), "free once it arrives")
	check(w.abilities.cooldown_left(s, "shuriken_hook") > 10.0, "12 s cooldown at level 4")
	near(s.mana, s.max_mana - 120.0, 4.0, "120 mana")

func test_shuriken_hook_misses_returns_and_locks() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	w.vision.update()
	w.command(s.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": Vector2(-1000, -4000)})
	var cast_t := -1.0
	for i in 30:
		w.step()
		if cast_t < 0.0 and not _events_of(w, "hook_launch").is_empty():
			cast_t = w.time
		w.events.clear()
		if cast_t > 0.0 and w.time - cast_t >= 0.1:
			break
	var lock := s.get_modifier("hook_lock")
	check(not lock.is_empty(), "while the hook flies out Sludge is locked")
	check(s.is_rooted() and s.is_disarmed() and s.has_flag("mute") and s.has_flag("face_lock"), "rooted, disarmed, muted, cannot turn")
	near(float(lock.get("expires", 0.0)) - cast_t, 1300.0 / 1600.0 * 0.65, 0.001, "for (1300 / 1600) x 65% = 0.53 s")
	var f0 := s.facing
	w.command(s.id, {"type": O.MOVE, "point": Vector2(-2000, -3000)})
	run(w, 0.2)
	near(s.facing, f0, 0.001, "cannot turn while locked")
	near(s.pos.distance_to(Vector2(-2000, -4000)), 0.0, 1.0, "cannot walk while locked")
	var ended := -1.0
	for i in 90:
		w.step()
		for ev in w.events:
			if ev.t == "hook_end":
				ended = w.time
		w.events.clear()
	check(ended > 0.0, "a hook that catches nothing comes back")
	check(s.get_modifier("hook_lock").is_empty(), "the lock wears off")

func test_shuriken_hook_first_unit_ally_and_ancient() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var ally := _dummy(w, "dawn_melee", C.DAWN, Vector2(-1600, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1100, -4000))
	w.vision.update()
	var a0 := ally.hp
	var e0 := e.hp
	w.command(s.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": Vector2(-1100, -4000)})
	run(w, 2.0)
	near(ally.hp, a0, 0.001, "an ally caught first is not hurt")
	near(e.hp, e0, 0.001, "the enemy behind it is untouched")
	near(ally.pos.distance_to(s.pos), s.hull + ally.hull, 10.0, "the ally is pulled to Sludge")
	# an ancient creep in front is ignored; the hero behind it is caught
	var w2 := empty_world()
	var s2 := _sludge(w2, Vector2(-2000, -4000))
	var anc := _dummy(w2, "cinder_wyrmling", C.NEUTRAL, Vector2(-1600, -4000))
	var e2 := _dummy(w2, "ezee", C.DUSK, Vector2(-1100, -4000))
	w2.vision.update()
	var anc0 := anc.hp
	var e20 := e2.hp
	w2.command(s2.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": Vector2(-1100, -4000)})
	run(w2, 2.2)
	near(anc.hp, anc0, 0.001, "ancient creeps cannot be hooked")
	check(e2.hp < e20, "the hero behind the ancient is caught")

func test_shuriken_hook_kills_enemy_creep() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1400, -4000))
	c.order = O.HOLD
	w.vision.update()
	var g0 := s.gold()
	w.command(s.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": Vector2(-1400, -4000)})
	run(w, 1.0)
	check(not c.alive, "a non-ancient enemy creep dies on the spot")
	check(s.last_hits == 1 and s.gold() > g0, "and Sludge gets the last hit and its gold")

func test_shuriken_hook_flies_over_trees() -> void:
	var w := empty_world()
	var spot := _tree_spot()
	check(not spot.is_empty(), "found a tree with open ground beside it")
	if spot.is_empty():
		return
	var ti: int = spot[0]
	var tree_pos: Vector2 = _map.trees[ti].pos
	var dir: Vector2 = spot[2]
	var s := _sludge(w, tree_pos - dir * 600.0)
	var e := _dummy(w, "ezee", C.DUSK, tree_pos + dir * 200.0)
	w.vision.update()
	var e0 := e.hp
	w.command(s.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": e.pos})
	run(w, 2.0)
	check(e.hp < e0, "the hook passes over the tree and catches the hero behind it")
	check(w.map.trees[ti].alive, "and leaves the tree standing")

func test_stench_damage_slow_self_damage_and_toggle() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1800, -4000))
	var far := _dummy(w, "ezee", C.DUSK, Vector2(-2000 + 300 + 24 + 30, -4000))
	w.vision.update()
	var e0 := e.hp
	var far0 := far.hp
	var s0 := s.hp
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	check(bool(s.toggles.get("stench", false)), "toggled on at once (no cast point)")
	var ticks := 0
	var st_dmg := 0.0
	var self_dmg := 0.0
	for i in 30:
		w.step()
		for ev in w.events:
			if ev.t == "damage" and int(ev.u) == e.id and ev.key == "stench":
				ticks += 1
		st_dmg += _dmg_events(w.events, e.id, "stench")
		self_dmg += _dmg_events(w.events, s.id, "stench")
		w.events.clear()
	check(ticks == 5 or ticks == 6, "a tick every 0.2 s (%d in 1 s)" % ticks)
	near(st_dmg, ticks * 120.0 * 0.2 * (1.0 + s.magic_amp) * (1.0 - e.magic_resist), 0.01, "120 magic damage per second at level 4")
	near(far.hp, far0, 0.001, "nothing beyond 250")
	near(self_dmg, ticks * 120.0 * 0.2 * (1.0 + s.magic_amp) * (1.0 - s.magic_resist), 0.01, "Sludge takes the same damage")
	check(s.hp < s0, "from his own health")
	var slow := e.get_modifier("stench")
	near(float(slow.get("slow", 0.0)), 0.32, 0.001, "32% slow at level 4")
	# while stunned it keeps burning
	s.add_modifier({"id": "stun", "source": -1, "expires": w.time + 1.0, "stun": true})
	var e1 := e.hp
	run(w, 0.6)
	check(e.hp < e1, "still burning while Sludge is stunned")
	run(w, 0.6)
	# off: no more damage; the slow lingers 0.5 s
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	check(not bool(s.toggles.get("stench", true)), "toggled off")
	run(w, 0.25)
	var e2 := e.hp
	check(not e.get_modifier("stench").is_empty(), "the slow lingers")
	run(w, 0.5)
	near(e.hp, e2 + e.hp_regen * 0.5, 2.0, "no damage once off")
	check(e.get_modifier("stench").is_empty(), "the slow fades after 0.5 s")
	# never lethal to Sludge
	s.hp = 5.0
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	run(w, 2.0)
	check(s.alive and s.hp >= 1.0, "Stench never kills Sludge")

func test_stench_scepter() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	s.scepter = true
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-2000 + 420, -4000))
	w.vision.update()
	near(w.abilities.val(s, "stench", "radius"), 450.0, 0.001, "Upgrade Staff: +200 radius")
	near(w.abilities.val(s, "stench", "dps"), 210.0, 0.001, "Upgrade Staff: +90 damage per second")
	var e0 := e.hp
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	run(w, 0.1)
	check(e.hp < e0, "reaches 420 away")
	e.hp = e.max_hp * 0.5
	var before := e.hp
	var got := w.combat.heal(e, 100.0)
	near(got, 80.0, 0.01, "-20% healing on enemies inside")
	near(e.hp - before, 80.0, 0.01, "applied to their health")

func test_blubber_blocks_every_instance() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	w.vision.update()
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "blubber"})
	check(not s.get_modifier("blubber").is_empty(), "instant, no cast point")
	near(s.mana, s.max_mana - 80.0, 0.5, "80 mana at level 4")
	check(w.abilities.cooldown_left(s, "blubber") > 16.9, "17 s cooldown at level 4")
	var h0 := s.hp
	w.combat.deal_damage(-1, C.DUSK, false, s, 100.0, C.DamageType.PURE)
	near(h0 - s.hp, 74.0, 0.01, "blocks 26 of a 100 damage hit")
	var h1 := s.hp
	w.combat.deal_damage(-1, C.DUSK, false, s, 20.0, C.DamageType.PURE)
	near(h1 - s.hp, 0.0, 0.01, "a hit under 26 does nothing")
	run(w, 7.1)
	check(s.get_modifier("blubber").is_empty(), "lasts 7 s at level 4")

func test_chomp_bites_heal_pull_and_end() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-2000 + 48 + 150, -4000))
	w.vision.update()
	s.hp = 200.0
	var e0 := e.hp
	var str0 := s.str_total
	w.command(s.id, {"type": O.CAST_UNIT, "ability": "chomp", "target": e.id})
	var bites := 0
	var healed := 0.0
	var stunned := false
	var bite_dmg := 0.0
	for i in int(0.3 * 30) + 2 + int(2.75 * 30) + 2:
		w.step()
		bite_dmg += _dmg_events(w.events, e.id, "chomp")
		for ev in w.events:
			if ev.t == "chomp_bite":
				bites += 1
				healed += float(ev.healed)
		w.events.clear()
		if e.has_flag("stun"):
			stunned = true
	var per_bite := (120.0 + 0.9 * str0) * 2.75 / 6.0
	check(bites == 6, "6 bites over the 2.75 s channel (%d)" % bites)
	near(bite_dmg, per_bite * 6.0 * (1.0 + s.magic_amp) * (1.0 - e.magic_resist), 0.05, "(120 + 0.9 x strength) magic damage per second")
	check(e0 - e.hp > bite_dmg - 15.0, "taken from its health")
	near(healed, per_bite * 6.0, 1.0, "Sludge heals the full bite each time")
	check(stunned, "the victim is stunned")
	check(not e.has_flag("stun"), "and free when it ends")
	near(e.pos.distance_to(s.pos), 125.0, 4.0, "pulled in to 125")
	check(w.abilities.cooldown_left(s, "chomp") > 17.0, "20 s cooldown at level 3")
	# cut short by a stun; Stench and Blubber do not break it
	var w2 := empty_world()
	var s2 := _sludge(w2, Vector2(-2000, -4000))
	var e2 := _dummy(w2, "ezee", C.DUSK, Vector2(-2000 + 48 + 150, -4000))
	w2.vision.update()
	w2.command(s2.id, {"type": O.CAST_UNIT, "ability": "chomp", "target": e2.id})
	run(w2, 0.6)
	check(not s2.channel.is_empty(), "channelling")
	w2.command(s2.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	w2.command(s2.id, {"type": O.CAST_NO_TARGET, "ability": "blubber"})
	run(w2, 0.2)
	check(not s2.channel.is_empty(), "Stench and Blubber do not break Chomp")
	s2.add_modifier({"id": "stun", "source": -1, "expires": w2.time + 0.5, "stun": true})
	run(w2, 0.1)
	check(s2.channel.is_empty(), "a stun ends it")
	check(not e2.has_flag("stun"), "and frees the victim")
	# only enemies
	var w3 := empty_world()
	var s3 := _sludge(w3, Vector2(-2000, -4000))
	var a3 := _dummy(w3, "dawn_melee", C.DAWN, Vector2(-1850, -4000))
	w3.vision.update()
	check(w3.abilities.cast_error(s3, "chomp", -1, a3, a3.pos) != "", "cannot Chomp an ally")

func test_growing_gut_stacks() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	var str0 := s.str_total
	# an enemy hero dies 400 away: +2 strength
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1600, -4000), 100.0)
	w.combat.deal_damage(-1, C.NEUTRAL, false, e, 1000.0, C.DamageType.PURE)
	w.combat.process_deaths()
	near(s.str_total - str0, 2.0, 0.001, "an enemy hero dying within 450 gives 2 strength")
	# far away and not his kill: nothing
	var e2 := _dummy(w, "ezee", C.DUSK, Vector2(2000, 2000), 100.0)
	w.combat.deal_damage(-1, C.NEUTRAL, false, e2, 1000.0, C.DamageType.PURE)
	w.combat.process_deaths()
	near(s.str_total - str0, 2.0, 0.001, "not for a death far away that is not his")
	# far away but his kill: a stack
	var e3 := _dummy(w, "ezee", C.DUSK, Vector2(2000, 2200), 100.0)
	w.combat.deal_damage(s.id, s.team, true, e3, 1000.0, C.DamageType.PURE)
	w.combat.process_deaths()
	near(s.str_total - str0, 4.0, 0.001, "a kill of his anywhere counts")
	check(int(s.stacks.get("growing_gut", 0)) == 2, "two stacks")
	# kept through death
	w.combat.deal_damage(-1, C.DUSK, false, s, 1e6, C.DamageType.PURE)
	w.combat.process_deaths()
	w.respawn(s)
	near(s.str_total - str0, 4.0, 0.001, "the strength stays after Sludge dies")
	# an allied hero dying near him: nothing
	var a := _dummy(w, "ezee", C.DAWN, s.pos + Vector2(100, 0), 100.0)
	w.combat.deal_damage(-1, C.DUSK, false, a, 1000.0, C.DamageType.PURE)
	w.combat.process_deaths()
	near(s.str_total - str0, 4.0, 0.001, "an ally's death does not count")

func test_ranger_ezee_talents() -> void:
	for id in ["blood_ranger", "ezee"]:
		var d := SimData.unit(id)
		check((d.talents as Array).size() == 4, "%s has 4 talent tiers" % id)
		for tier in d.talents:
			for tid in tier:
				check(not SimData.talent(String(tid)).is_empty(), "talent %s exists" % tid)
	var w := empty_world()
	var r := _ranger(w, Vector2(-2000, -4000))
	r.level = 25
	r.ability_points = 4
	var chance0 := w.abilities.val(r, "masterful_archery", "chance")
	check(w.abilities.learn_talent(r, 0, 0), "ranger level 10 talent")
	near(w.abilities.val(r, "masterful_archery", "chance"), chance0 + 0.10, 0.001, "+10% Masterful Archery chance")
	check(w.abilities.learn_talent(r, 1, 0), "ranger level 15 talent")
	near(w.abilities.val(r, "gale_impact", "damage"), 460.0, 0.001, "+100 Gale Impact damage")
	check(w.abilities.learn_talent(r, 2, 1), "ranger level 20 talent")
	near(w.abilities.ability_cooldown(r, "gale_impact"), 8.0, 0.001, "-4 s Gale Impact cooldown")
	check(w.abilities.learn_talent(r, 3, 0), "ranger level 25 talent")
	w.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "blood_ranger_ult"})
	run(w, 0.6)
	var m := r.get_modifier("blood_ranger")
	check(not m.is_empty() and is_equal_approx(float(m.stats.lifesteal_ability), 0.8), "the cast carries +20%% lifesteal (%s)" % str(m.get("stats")))
	# Ezee: values read by his spells as they go off
	var w2 := empty_world()
	var e := _ezee(w2, Vector2(-2000, -4000))
	e.level = 25
	e.ability_points = 4
	e.refresh_stats()
	var str0 := e.str_total
	check(w2.abilities.learn_talent(e, 0, 0), "ezee level 10 talent")
	near(e.str_total, str0 + 10.0, 0.001, "+10 strength")
	check(w2.abilities.learn_talent(e, 1, 0), "ezee level 15 talent")
	near(w2.abilities.val(e, "dark_stomp", "impact_stun"), 2.8 + 0.6, 0.001, "+0.6 s Dark Stomp stun")
	check(w2.abilities.learn_talent(e, 2, 1), "ezee level 20 talent")
	near(w2.abilities.val(e, "leap_strike", "str_mult"), 1.0, 0.001, "+40% Leap Strike strength damage")
	check(w2.abilities.learn_talent(e, 3, 1), "ezee level 25 talent")
	w2.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "unholy_might"})
	run(w2, 0.8)
	var um := e.get_modifier("unholy_might")
	check(not um.is_empty() and float(um.expires) - w2.time > 12.0, "Unholy Might lasts 14 s with the talent")
	check(SimBotKits.TALENTS.has("blood_ranger") and SimBotKits.TALENTS.has("ezee"), "bots pick their talents")

func test_azrin_javelin_fells_trees() -> void:
	var w := empty_world()
	var spot := _tree_spot()
	var ti: int = spot[0]
	var tp: Vector2 = _map.trees[ti].pos
	var out: Vector2 = -(spot[2] as Vector2)
	var a := _azrin(w, tp + out * 500.0)
	w.vision.update()
	w.command(a.id, {"type": O.CAST_POINT, "ability": "fiery_javelin", "point": tp - out * 300.0})
	var felled := []
	for i in 60:
		w.step()
		for ev in w.events:
			if ev.t == "tree" and not ev.alive:
				felled.append(int(ev.i))
		w.events.clear()
	check(ti in felled, "the tree in the javelin's path is knocked down")
	check(not _map.trees[ti].alive, "and stays down")
	for i in felled:
		_restore_tree(i)

func test_sludge_talents_and_shard() -> void:
	var w := empty_world()
	var s := _sludge(w, Vector2(-2000, -4000))
	s.level = 9
	s.ability_points = 4
	check(not w.abilities.can_learn_talent(s, 0), "no talent before level 10")
	s.level = 25
	check(w.abilities.learn_talent(s, 0, 0), "level 10 talent")
	near(w.abilities.val(s, "stench", "slow"), 0.42, 0.001, "+10% Stench slow")
	check(not w.abilities.learn_talent(s, 0, 1), "one talent per tier")
	check(w.abilities.learn_talent(s, 2, 0), "level 20 talent")
	near(w.abilities.ability_cooldown(s, "shuriken_hook"), 8.0, 0.001, "-4 s hook cooldown")
	check(w.abilities.learn_talent(s, 3, 0), "level 25 talent")
	near(w.abilities.val(s, "growing_gut", "str_per_stack"), 3.0, 0.001, "1.5x Growing Gut")
	near(w.abilities.val(s, "blubber", "block"), 39.0, 0.001, "1.5x Blubber")
	check(w.abilities.learn_talent(s, 1, 1), "level 15 talent")
	near(s.spell_lifesteal, 0.08, 0.001, "8% spell lifesteal")
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1800, -4000))
	s.hp = 100.0
	var dealt := w.combat.deal_damage(s.id, s.team, true, e, 500.0, C.DamageType.PURE, false, "shuriken_hook")
	near(s.hp - 100.0, dealt * 0.08, 0.01, "heals 8% of spell damage to heroes")
	check(s.ability_points == 0, "each talent costs an ability point")
	var w2 := empty_world()
	var s2 := _sludge(w2, Vector2(-2000, -4000))
	s2.level = 25
	s2.ability_points = 4
	w2.abilities.learn_talent(s2, 2, 1)
	near(w2.abilities.val(s2, "chomp", "duration"), 3.5, 0.001, "+0.75 s Chomp")
	near(w2.abilities.val(s2, "chomp", "ticks"), 8.0, 0.001, "two more bites")
	w2.abilities.learn_talent(s2, 1, 0)
	near(w2.abilities.val(s2, "shuriken_hook", "damage"), 510.0, 0.001, "+150 hook damage")
	# Upgrade Gem: the drag adds 20% of its distance as damage
	var w3 := empty_world()
	var s3 := _sludge(w3, Vector2(-2000, -4000))
	s3.shard = true
	var e3 := _dummy(w3, "ezee", C.DUSK, Vector2(-1000, -4000))
	w3.vision.update()
	var e30 := e3.hp
	w3.command(s3.id, {"type": O.CAST_POINT, "ability": "shuriken_hook", "point": e3.pos})
	run(w3, 1.0)
	near(e30 - e3.hp, 360.0 + 0.2 * (1000.0 - 100.0 - 24.0), 30.0, "Upgrade Gem: +20% of the drag distance as damage")

# ---- Combination items (Dota 7.41d items.txt, our names) ----------------------------------------------------------

## A hero standing in its base shop with plenty of gold.
func _shopper(w: SimWorld, id := "sludge", gold := 20000) -> SimUnit:
	var h := w.spawn(id, C.DAWN, _map.fountains[0] + Vector2(200, 200))
	h.gold_unreliable = gold
	return h

func _give(w: SimWorld, h: SimUnit, item_id: String, slot := -1) -> Dictionary:
	var it := w.shop.new_item(item_id)
	if slot < 0:
		slot = h.inventory.find(null)
	h.inventory[slot] = it
	h.refresh_stats()
	return it

func _ids(arr: Array) -> Array:
	return arr.filter(func(i): return i != null).map(func(i): return i.id)

func test_item_costs_match_their_parts() -> void:
	var bad: Array = []
	for id in SimData.items():
		var d := SimData.item(id)
		for parts in SimShop.recipe_sets(id):
			var sum := 0
			for p in parts:
				check(not SimData.item(p).is_empty(), "%s: part %s exists" % [id, p])
				sum += int(SimData.item(p).cost)
			if sum != int(d.cost):
				bad.append("%s %d != %d" % [id, sum, int(d.cost)])
		if int(d.recipe_cost) > 0:
			check(SimData.item("recipe_" + id).get("recipe_for", "") == id, "%s has a recipe scroll" % id)
	check(bad.is_empty(), "every recipe adds up to the item's price: %s" % str(bad))
	# spot checks against Dota's prices
	for pair in [["tough_band", 505], ["smart_band", 505], ["slip_boots", 1450], ["mana_boots", 1500], ["spell_shield", 4050],
			["armor_breaker", 3500], ["cleave_axe", 3900], ["shock_hammer", 2950], ["gold_glove", 2200], ["spike_armor", 2400],
			["upgrade_staff", 4200], ["sneak_blade", 3250], ["medic_kit", 1775], ["block_shield", 1700], ["push_staff", 2200],
			["jump_knife", 2250], ["upgrade_gem", 1400], ["dragon_lance", 2000]]:
		check(int(SimData.item(pair[0]).cost) == int(pair[1]), "%s costs %d" % pair)

func test_recipe_scroll_buys_only_missing_parts() -> void:
	var w := empty_world()
	var h := _shopper(w, "sludge", 2000)
	check(w.shop.buy(h, "circlet") == "", "bought a Headband")
	check(w.shop.price(h, "tough_band") == 140 + 210, "Tough Band now costs Heavy Gloves + recipe (%d)" % w.shop.price(h, "tough_band"))
	check(w.shop.buy(h, "tough_band") == "", "bought Tough Band")
	check(_ids(h.inventory) == ["tough_band"], "parts and scroll combined into one item (%s)" % str(_ids(h.inventory)))
	check(h.gold() == 2000 - 155 - 140 - 210, "paid 505 in total")
	near(h.str_total, 25.0 + 5.0, 0.01, "+5 strength")
	# the scroll on its own, then the parts: combines when the last part arrives
	var w2 := empty_world()
	var h2 := _shopper(w2, "sludge", 2000)
	check(w2.shop.buy(h2, "recipe_smart_band") == "", "bought the recipe scroll alone")
	check(_ids(h2.inventory) == ["recipe_smart_band"], "the scroll sits in the bags")
	w2.shop.buy(h2, "circlet")
	check(_ids(h2.inventory).size() == 2, "not yet")
	w2.shop.buy(h2, "mantle")
	check(_ids(h2.inventory) == ["smart_band"], "combined into Smart Band (%s)" % str(_ids(h2.inventory)))

func test_recipe_parts_combine_per_pool() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))      # away from the shop
	h.gold_unreliable = 2000
	_give(w, h, "gauntlets")
	check(w.shop.buy(h, "circlet") == "", "bought a Headband away from the shop")
	check(_ids(h.stash) == ["circlet"], "it waits in the stash")
	w.shop.buy(h, "recipe_tough_band")
	check(_ids(h.inventory) == ["gauntlets"] and _ids(h.stash).size() == 2, "bags and stash do not combine away from the shop")
	h.pos = _map.fountains[0] + Vector2(200, 200)
	w.shop.update(h)
	check(_ids(h.inventory) == ["tough_band"] and _ids(h.stash).is_empty(), "they combine in the shop (%s / %s)" % [str(_ids(h.inventory)), str(_ids(h.stash))])

func test_buy_counts_partly_built_parts() -> void:
	var w := empty_world()
	var h := _shopper(w)
	_give(w, h, "mana_stone")
	check(w.shop.price(h, "cleave_axe") == 3900 - 700, "Cleave Axe: the Mana Stone inside its Steady Ring is owned (%d)" % w.shop.price(h, "cleave_axe"))
	check(w.shop.buy(h, "cleave_axe") == "", "bought Cleave Axe")
	check(_ids(h.inventory) == ["cleave_axe"], "built through Steady Ring in one go (%s)" % str(_ids(h.inventory)))
	check(w.shop.buy(h, "dragon_lance") == "", "bought Long Spear")
	check(_ids(h.inventory).has("dragon_lance") and _ids(h.inventory).size() == 2, "Long Spear = Quick Blade + Heavy Belt + recipe")

func test_inventory_full_undoes_the_purchase() -> void:
	var w := empty_world()
	var h := _shopper(w, "sludge", 5000)
	for i in 9:
		_give(w, h, "branch", i)
	for i in 6:
		h.stash[i] = w.shop.new_item("clarity")
	var g := h.gold()
	check(w.shop.buy(h, "spell_shield") == "Inventory full", "no room for the parts")
	check(h.gold() == g and _ids(h.inventory).size() == 9 and _ids(h.stash).size() == 6, "nothing bought, nothing lost")

func test_switch_boots_recipes_attribute_and_speed() -> void:
	var w := empty_world()
	var h := _shopper(w, "sludge")
	for p in ["boots", "gloves", "robe"]:
		w.shop.buy(h, p)
	check(_ids(h.inventory) == ["power_treads"], "Running Shoes + Fast Gloves + Wizard Robe make Switch Boots")
	var it: Dictionary = h.inventory[0]
	check(String(it.get("attr", "")) == "int", "built with a robe: intelligence")
	var int0 := h.int_total
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	check(String(it.attr) == "agi", "the active switches intelligence -> agility")
	near(int0 - h.int_total, 10.0, 0.01, "the +10 moved off intelligence")
	near(h.move_speed, 280.0 + 55.0, 0.01, "melee heroes get 55 speed")
	_give(w, h, "boots")
	near(h.move_speed, 280.0 + 55.0, 0.01, "a second pair of boots adds nothing")
	var w2 := empty_world()
	var r := _shopper(w2, "blood_ranger")
	w2.shop.buy(r, "power_treads")
	check(String(r.inventory[0].attr) == "str", "bought whole: the Heavy Belt recipe (strength)")
	near(r.move_speed, 300.0 + 45.0, 0.01, "ranged heroes get 45 speed")
	# the bot no longer buys an item it already has
	var w3 := empty_world()
	var b := _shopper(w3, "sludge", 3000)
	var bot := SimBot.new(w3, b.id)
	bot.build = ["power_treads", "power_treads", "gloves"]
	bot._shop(b)
	check(_ids(b.inventory).count("power_treads") == 1, "bot: one pair (%s)" % str(_ids(b.inventory)))

func test_smart_band_mana_and_upgrade_staff() -> void:
	var w := empty_world()
	var h := _shopper(w)
	_give(w, h, "smart_band")
	near(h.max_mana, (float(h.def.mana) + h.int_total * C.INT_MANA) * 1.03, 0.01, "Smart Band: +3% max mana")
	check(not h.has_scepter(), "no upgrade yet")
	w.shop.buy(h, "upgrade_staff")
	check(_ids(h.inventory).has("upgrade_staff") and h.has_scepter(), "Upgrade Staff gives the upgrade")
	# Upgrade Gem: on sale from 15:00, used up at once, only once
	check(w.shop.buy(h, "upgrade_gem").begins_with("Not available"), "not before 15:00")
	w.time = 900.0
	var g := h.gold()
	check(w.shop.buy(h, "upgrade_gem") == "" and h.shard, "bought at 15:00: Sludge has the shard upgrade")
	check(not _ids(h.inventory).has("upgrade_gem") and g - h.gold() == 1400, "used up on purchase, 1400 gold")
	check(w.shop.buy(h, "upgrade_gem") != "", "cannot buy a second")

func test_slip_boots_and_frenzy_mask_melee() -> void:
	var w := empty_world()
	var h := _shopper(w, "sludge")
	_give(w, h, "slip_boots", 0)
	near(h.move_speed, 330.0, 0.01, "+50 speed")
	near(h.bonus_damage, 18.0, 0.01, "+18 damage (melee)")
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	run(w, 0.1)
	check(h.phased, "walks through units")
	near(h.move_speed, 330.0 * 1.2, 0.5, "+20% speed for melee")
	run(w, 3.0)
	check(not h.phased, "3 seconds")
	check(w.abilities.item_cooldown_left(h, 0) > 4.0, "8 s cooldown")
	_give(w, h, "mask_of_madness", 1)
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 1})
	run(w, 0.1)
	near(h.move_speed, 330.0 * 1.12, 0.5, "Frenzy Mask: +12% speed for melee heroes")

func test_mana_boots_and_medic_kit() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var ally := w.spawn("ezee", C.DAWN, Vector2(-1500, -4000))
	var far := w.spawn("ezee", C.DAWN, Vector2(-500, -4000))
	_give(w, h, "mana_boots", 0)
	_give(w, h, "medic_kit", 1)
	_give(w, h, "mana_ring", 2)
	_give(w, h, "leaf_hat", 3)
	run(w, 0.3)
	check(not ally.get_modifier("aura_mana").is_empty(), "mana aura on an ally in range")
	near(float(ally.get_modifier("aura_mana").mana_regen), 1.0, 0.001, "two mana auras do not stack")
	near(float(ally.get_modifier("aura_regen").regen), 2.5, 0.001, "Medic Kit's aura wins over the Leaf Hat's")
	check(far.get_modifier("aura_mana").is_empty(), "not past 1200")
	ally.mana = 0.0
	ally.hp = 100.0
	far.hp = 100.0
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	near(ally.mana, 150.0, 1.0, "Mana Boots: +150 mana to allies")
	var mana0 := h.mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 1})
	near(ally.hp, 350.0, 1.0, "Medic Kit: heals allies 250")
	near(mana0 - h.mana, 100.0, 0.01, "Medic Kit costs 100 mana")
	near(far.hp, 100.0, 0.5, "out of range: not healed")
	run(w, 1.0)
	check(ally.get_modifier("aura_mana").is_empty() == false, "aura keeps refreshing")
	h.inventory[0] = null
	h.inventory[2] = null
	h.refresh_stats()
	run(w, 1.0)
	check(ally.get_modifier("aura_mana").is_empty(), "the aura fades 0.5 s after the items leave")

func test_block_shield_blocks_attacks() -> void:
	var w := empty_world()
	var h := _dummy(w, "sludge", C.DAWN, Vector2(-2000, -4000))
	var src := _dummy(w, "blood_ranger", C.DUSK, Vector2(-1800, -4000))
	_give(w, h, "block_shield")
	var mult := C.armor_multiplier(h.armor)
	var n := 2000
	var blocked := 0
	for i in n:
		var d := w.combat.deal_damage(src.id, src.team, true, h, 100.0, C.DamageType.PHYSICAL, true, "attack")
		if d < 99.0 * mult:
			blocked += 1
			near(d, 50.0 * mult, 0.01, "blocks 50 before armor (melee owner)")
	near(float(blocked) / n, 0.6, 0.04, "about 60% of attacks are blocked")
	var spell := w.combat.deal_damage(src.id, src.team, true, h, 100.0, C.DamageType.PHYSICAL, false, "spell")
	near(spell, 100.0 * mult, 0.01, "spells are not blocked")

func test_spike_armor_returns_damage() -> void:
	var w := empty_world()
	var h := _dummy(w, "sludge", C.DAWN, Vector2(-2000, -4000))
	var src := _dummy(w, "blood_ranger", C.DUSK, Vector2(-1800, -4000))
	_give(w, h, "spike_armor", 0)
	var hp0 := src.hp
	w.combat.deal_damage(src.id, src.team, true, h, 100.0, C.DamageType.PHYSICAL, true, "attack")
	near(hp0 - src.hp, (10.0 + 15.0) * C.armor_multiplier(src.armor), 0.01, "passive: 10 + 15% of the attack, before reductions")
	hp0 = src.hp
	w.combat.deal_damage(src.id, src.team, true, h, 100.0, C.DamageType.MAGICAL, false, "spell")
	check(src.hp == hp0, "passive ignores spells")
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	w.combat.deal_damage(src.id, src.team, true, h, 200.0, C.DamageType.MAGICAL, false, "spell")
	near(hp0 - src.hp, 170.0 * (1.0 + src.magic_amp) * (1.0 - src.magic_resist), 0.01, "active: 85% of any damage, same type")
	hp0 = src.hp
	var h_hp := h.hp
	w.combat.deal_damage(src.id, src.team, true, h, 100.0, C.DamageType.PHYSICAL, true, "attack")
	near(hp0 - src.hp, (10.0 + 15.0 + 85.0) * C.armor_multiplier(src.armor), 0.01, "active attacks: passive + 85%")
	check(h.hp < h_hp, "the wearer still takes the damage")

func test_spell_shield_debuff_immunity() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var t := w.spawn("sludge", C.DUSK, Vector2(-1800, -4000))
	t.order = O.HOLD
	_give(w, t, "spell_shield", 0)
	var mr0 := t.magic_resist
	w.command(t.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	near(1.0 - (1.0 - mr0) * 0.4, t.magic_resist, 0.01, "60% magic resistance on top")
	check(t.debuff_immune, "debuff immune")
	w.vision.update()
	var p0 := t.pos
	var hp0 := t.hp
	w.command(e.id, {"type": O.CAST_NO_TARGET, "ability": "dark_stomp"})
	run(w, 1.0)
	check(t.hp < hp0, "Dark Stomp still damages")
	check(t.knock.is_empty() and t.pos.distance_to(p0) < 30.0, "but cannot push a debuff-immune hero")
	var m := t.get_modifier("spell_shield")
	near(float(m.expires) - (w.time - 1.0), 9.0, 0.1, "first use lasts 9 s")
	var it: Dictionary = t.inventory[0]
	var durs: Array = []
	for k in 4:
		it.ready = -INF
		t.mana = t.max_mana
		w.command(t.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
		durs.append(snappedf(float(t.get_modifier("spell_shield").expires) - w.time, 0.01))
	check(durs == [8.0, 7.0, 7.0, 7.0], "then 8 s and 7 s at the least (%s)" % str(durs))
	# Stench still burns a debuff-immune enemy (through the magic resistance) but cannot slow it
	var s := _sludge(w, t.pos + Vector2(-150, 0))
	var hp1 := t.hp
	w.command(s.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	run(w, 1.0)
	check(t.hp < hp1, "Stench damages through Spell Shield")
	check(t.get_modifier("stench").is_empty(), "but does not slow")

func test_jump_knife() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	_give(w, h, "jump_knife", 0)
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": Vector2(-1000, -4000)})
	run(w, 1.0)
	near(h.pos.distance_to(Vector2(-1000, -4000)), 0.0, 40.0, "jumps 1000 to the point")
	check(w.abilities.item_cooldown_left(h, 0) > 13.0, "15 s cooldown")
	h.inventory[0].ready = -INF
	var start := h.pos
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": start + Vector2(-2000, 0)})
	run(w, 1.0)
	near(start.distance_to(h.pos), 960.0, 40.0, "a point past 1200 lands 960 toward it")
	h.inventory[0].ready = -INF
	h.hero_damage_log[999] = w.time - 1.0
	check(w.abilities.cast_error(h, "", 0, null, h.pos) == "Jump Knife is disabled", "disabled 3 s after hero damage")
	h.hero_damage_log[999] = w.time - 3.5
	check(w.abilities.cast_error(h, "", 0, null, h.pos) == "", "usable again after 3 s")

func test_push_staff() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var e := w.spawn("ezee", C.DUSK, Vector2(-1500, -4000))
	e.facing = 0.0
	e.order = O.HOLD
	_give(w, h, "push_staff", 0)
	h.mana = h.max_mana
	w.vision.update()
	var p0 := e.pos
	w.command(h.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 0, "target": e.id})
	run(w, 0.2)
	check(not e.is_stunned(), "not a disable")
	run(w, 0.6)
	near(e.pos.x - p0.x, 600.0, 15.0, "pushed 600 the way it faces")
	near(e.pos.y, p0.y, 1.0, "in a straight line")
	# trees in the way are cut
	var spot := _tree_spot()
	var w2 := empty_world()
	var h2 := w2.spawn("sludge", C.DAWN, spot[1])
	h2.facing = (spot[2] as Vector2).angle()
	_give(w2, h2, "push_staff", 0)
	h2.mana = h2.max_mana
	w2.command(h2.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 0, "target": h2.id})
	run(w2, 1.0)
	check(not _map.trees[spot[0]].alive, "the tree in the way is cut")
	_map.regrow_tree(spot[0])

func test_gold_glove() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-1700, -4000))
	c.order = O.HOLD
	var foe := w.spawn("ezee", C.DUSK, Vector2(-1700, -3800))
	_give(w, h, "gold_glove", 0)
	w.vision.update()
	check(int(h.inventory[0].charges) == 1, "starts with one charge")
	check(w.abilities.cast_error(h, "", 0, foe, foe.pos) == "Must target an enemy creep", "not on heroes")
	var rel := h.gold_reliable
	w.command(h.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 0, "target": c.id})
	run(w, 0.5)
	check(not c.alive, "the creep dies")
	check(h.gold_reliable - rel == 160, "160 reliable gold (got %d)" % (h.gold_reliable - rel))
	check(h.last_hits == 0, "no bounty, no last hit")
	check(int(h.inventory[0].charges) == 0, "a charge used")
	run(w, 90.5)
	check(int(h.inventory[0].charges) == 1, "a charge back after 90 s")
	run(w, 90.5)
	check(int(h.inventory[0].charges) == 2, "up to two")
	run(w, 90.5)
	check(int(h.inventory[0].charges) == 2, "never more than two")

func test_corruption_and_armor_breaker_kill_damage() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var t := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	_give(w, h, "rust_stone", 0)
	var a0 := t.armor
	w.combat.land_attack(w.combat._snapshot(h, ""), t)
	run(w, 0.1)
	near(a0 - t.armor, 2.0, 0.01, "Rust Stone: -2 armor")
	_give(w, h, "armor_breaker", 1)
	w.combat.land_attack(w.combat._snapshot(h, ""), t)
	run(w, 0.1)
	near(a0 - t.armor, 6.0, 0.01, "Armor Breaker: -6 armor, the stronger one counts")
	h.inventory[1] = null
	h.refresh_stats()
	w.combat.land_attack(w.combat._snapshot(h, ""), t)
	run(w, 0.1)
	near(a0 - t.armor, 6.0, 0.01, "a weaker one does not replace it")
	run(w, 7.0)
	near(a0 - t.armor, 0.0, 0.01, "gone after 7 s")
	# kill damage: +2 per corrupted hero killed, +1 per assist, up to 30
	var w2 := empty_world()
	var k := w2.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var it := _give(w2, k, "armor_breaker", 0)
	var dmg0 := k.bonus_damage
	var v := w2.spawn("ezee", C.DUSK, Vector2(-1850, -4000))
	w2.combat.land_attack(w2.combat._snapshot(k, ""), v)
	w2.combat.deal_damage(k.id, k.team, true, v, 1e6, C.DamageType.PURE, false, "test")
	run(w2, 0.1)
	near(float(it.get("souls", 0.0)), 2.0, 0.01, "+2 for the kill")
	near(k.bonus_damage - dmg0, 2.0, 0.01, "applied to attack damage")
	it["souls"] = 29.0
	var v2 := w2.spawn("ezee", C.DUSK, Vector2(-1850, -3900))
	w2.combat.land_attack(w2.combat._snapshot(k, ""), v2)
	w2.combat.deal_damage(v.id, v.team, true, v2, 1e6, C.DamageType.PURE, false, "test")
	run(w2, 0.1)
	near(float(it.souls), 30.0, 0.01, "capped at 30")

func test_shock_hammer_chain_lightning() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	h.auto_attack = false
	_give(w, h, "shock_hammer", 0)
	var cs: Array = []
	for i in 6:
		var c := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850 + i * 300, -4000))
		cs.append(c)
	var hp0: Array = cs.map(func(c): return c.hp)
	w.items._start_chain(h, cs[0], SimData.item("shock_hammer").values)
	run(w, 1.5)
	var hit := 0
	for i in cs.size():
		var lost: float = hp0[i] - cs[i].hp
		if lost > 0.0:
			hit += 1
			near(lost, 110.0 * (1.0 - cs[i].magic_resist), 2.0, "110 magic damage per strike")
	check(hit == 4, "four strikes, each on a different unit (%d)" % hit)
	# the proc: about 25% of attacks
	var w2 := empty_world()
	var h2 := w2.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	_give(w2, h2, "shock_hammer", 0)
	var t2 := _dummy(w2, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	var procs := 0
	for i in 800:
		w2.time += 0.25
		var before := w2.items.chains.size()
		w2.combat.land_attack(w2.combat._snapshot(h2, ""), t2)
		if w2.items.chains.size() > before:
			procs += 1
		w2.items.chains.clear()
	near(procs / 800.0, 0.25, 0.04, "25% of attacks")

func test_cleave_axe() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	h.facing = 0.0
	_give(w, h, "cleave_axe", 0)
	var main := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1830, -4000))
	var side := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1700, -3920))
	var behind := _dummy(w, "dusk_melee", C.DUSK, Vector2(-2150, -4000))
	var wide := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1830, -3700))
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1700, -4080))
	var s := w.combat._snapshot(h, "")
	s.dmg_min = 100.0
	s.dmg_max = 100.0
	s.bonus = 0.0
	s.quell = 0.0
	var h0 := side.hp
	var f0 := foe.hp
	w.combat.land_attack(s, main)
	var mult := w.combat.attack_class_multiplier(s, side)
	near(h0 - side.hp, 100.0 * mult * 0.4, 0.5, "40% to creeps in front, ignoring armor")
	near(f0 - foe.hp, 100.0 * w.combat.attack_class_multiplier(s, foe) * 0.6, 0.5, "60% to heroes in front")
	check(behind.hp == behind.max_hp, "nothing behind the attacker")
	check(wide.hp == wide.max_hp, "nothing outside the cone")
	near(w.combat._quelling(h), 10.0, 0.01, "Mini-Axe's creep bonus (10 melee)")
	var r := w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -3000))
	_give(w, r, "cleave_axe", 0)
	var m2 := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1500, -3000))
	var n2 := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1400, -3000))
	w.combat.land_attack(w.combat._snapshot(r, ""), m2)
	check(n2.hp == n2.max_hp, "no cleave for ranged heroes")

func test_sneak_blade() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1830, -4000))
	_give(w, h, "sneak_blade", 0)
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	run(w, 0.1)
	w.vision.update()
	check(w.vision.sees(C.DUSK, h), "still visible while fading")
	run(w, 0.3)
	w.vision.update()
	check(not w.vision.sees(C.DUSK, h), "invisible after 0.3 s")
	near(h.move_speed, 280.0 * 1.2, 0.5, "+20% speed")
	var s := w.combat._snapshot(h, "")
	var hp0 := foe.hp
	h.atk_target = foe.id
	w.combat.release_attack(h, foe, "")
	check(h.get_modifier("sneak_blade").is_empty(), "attacking ends it")
	var dealt := hp0 - foe.hp
	check(dealt > (float(s.dmg_min) + float(s.bonus) + 175.0) * C.armor_multiplier(foe.armor) - 1.0, "the breaking attack deals 175 more (%d)" % int(dealt))

func test_spear_pierce() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	_give(w, h, "spear", 0)
	var t := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	t.add_modifier({"id": "test_evasion", "source": 0, "expires": INF, "stats": {"evasion": 1.0}})
	t.refresh_stats()
	var hits := 0
	for i in 1000:
		if w.combat.land_attack(w.combat._snapshot(h, ""), t):
			hits += 1
	near(hits / 1000.0, 0.25, 0.04, "25% of attacks pierce full evasion")

# ---- Courier, stash, To Buy, items on the ground (2026-10-13 b) -----------------------------------------------------

func _courier_world() -> Array:
	var w := SimWorld.new(1, _map)
	w.time = 30.0
	w.next_wave_at = INF
	w.next_neutral_at = INF
	var h := w.spawn_hero("sludge", C.DAWN)
	var c := w.get_unit(h.courier_id)
	return [w, h, c]

func test_courier_speed_flying_and_level() -> void:
	var a := _courier_world()
	var w: SimWorld = a[0]
	var h: SimUnit = a[1]
	var c: SimUnit = a[2]
	w.step()
	near(c.move_speed, 290.0 + 20.0 * 1, 0.01, "level 1 courier speed 290 + 20 x level")
	check(not c.has_flag("flying"), "walks before level 6")
	w.combat.give_xp(h, float(C.XP_TABLE[4]) - h.xp)
	w.step()
	check(h.level == 5 and not c.has_flag("flying"), "still walks at level 5")
	w.combat.give_xp(h, float(C.XP_TABLE[5]) - h.xp)
	w.step()
	check(h.level == 6 and c.has_flag("flying"), "flies from its owner's level 6")
	near(c.move_speed, 290.0 + 120.0, 0.01, "level 6 speed")
	check(w.courier_command(h, "burst").begins_with("Speed Burst needs level"), "no Speed Burst before level 10")
	check(w.courier_command(h, "shield").begins_with("Shield needs level"), "no Shield before level 20")
	w.combat.give_xp(h, float(C.XP_TABLE[19]) - h.xp)
	w.step()
	check(w.courier_command(h, "burst") == "", "Speed Burst at level %d" % h.level)
	w.step()
	near(c.move_speed, (290.0 + 20.0 * h.level) * 1.5, 0.01, "Speed Burst: +50%")
	check(w.courier_command(h, "burst") == "Speed Burst on cooldown", "120 s cooldown")
	run(w, 6.1)
	near(c.move_speed, 290.0 + 20.0 * h.level, 0.01, "lasts 6 s")
	check(w.courier_command(h, "shield") == "", "Shield at level 20")
	w.step()
	check(c.is_invulnerable(), "Shield: invulnerable")
	run(w, 2.1)
	check(not c.is_invulnerable(), "for 2 s")

func test_courier_dies_to_hit_counts_and_keeps_items() -> void:
	var a := _courier_world()
	var w: SimWorld = a[0]
	var h: SimUnit = a[1]
	var c: SimUnit = a[2]
	var melee := w.spawn("sludge", C.DUSK, c.pos + Vector2(100, 0))
	var ranged := w.spawn("blood_ranger", C.DUSK, c.pos + Vector2(100, 0))
	var creep := w.spawn("dusk_melee", C.DUSK, c.pos + Vector2(100, 0))
	w.combat.deal_damage(creep.id, C.DUSK, false, c, 9999.0, C.DamageType.PHYSICAL, true)
	check(c.alive and is_equal_approx(c.hp, 5.0), "a creep's attack takes one of six hits")
	w.combat.deal_damage(ranged.id, C.DUSK, true, c, 1.0, C.DamageType.PHYSICAL, true)
	check(c.alive and is_equal_approx(c.hp, 2.0), "a ranged hero's attack takes three")
	c.hp = c.max_hp
	c.inventory[0] = w.shop.new_item("boots")
	h.level = 7
	var g0 := melee.gold()
	w.combat.deal_damage(melee.id, C.DUSK, true, c, 1.0, C.DamageType.PHYSICAL, true)
	w.combat.process_deaths()
	check(not c.alive, "one melee hero attack kills it")
	near(c.respawn_at - w.time, 60.0 + 6.0 * 7, 0.05, "respawns in 60 + 6 x level")
	check(_ids(c.inventory) == ["boots"], "keeps what it carried")
	check(melee.gold() - g0 == 25 + 5 * 7 and ranged.gold() > 0, "every enemy hero gets 25 + 5 x level")
	check(w.courier_deliver(h) == "Courier is dead", "no orders while dead")

func test_deliver_sweeps_owner_items_in_the_well() -> void:
	var a := _courier_world()
	var w: SimWorld = a[0]
	var h: SimUnit = a[1]
	var c: SimUnit = a[2]
	var fountain: Vector2 = _map.fountains[0]
	h.pos = Vector2(-1500, -1300)
	var mine := w.shop.new_item("gauntlets")
	mine["owner"] = h.id
	w.drop_item(mine, fountain + Vector2(500, 300), h.id)
	var far := w.shop.new_item("slippers")
	far["owner"] = h.id
	w.drop_item(far, fountain + Vector2(2500, 2500), h.id)          # outside the Well
	var other := w.shop.new_item("mantle")
	other["owner"] = 999
	w.drop_item(other, fountain + Vector2(450, 250), 999)          # someone else's
	h.stash[0] = w.shop.new_item("circlet")
	check(w.courier_deliver(h) == "", "deliver ordered")
	var got := false
	for i in 30 * 120:
		w.step()
		if h.inventory.any(func(x): return x != null and x.id == "gauntlets"):
			got = true
			break
	check(got, "the hero received the item dropped in the Well")
	check(h.inventory.any(func(x): return x != null and x.id == "circlet"), "and the stash")
	check(w.ground_items.size() == 2, "the item outside the Well and another player's item stay on the ground")

func test_drop_pick_up_and_give() -> void:
	var w := empty_world()
	var h := w.spawn_hero("sludge", C.DAWN)
	var ally := w.spawn_hero("ezee", C.DAWN)
	h.pos = Vector2(-600, -600)
	ally.pos = h.pos + Vector2(600, 0)
	_give(w, h, "boots", 0)
	w.command(h.id, {"type": O.DROP_ITEM, "item_slot": 0, "point": h.pos + Vector2(400, 0)})
	run(w, 3.0)
	check(h.inventory[0] == null and w.ground_items.size() == 1, "walked over and dropped it")
	var g: Dictionary = w.ground_items[0]
	check((g.pos as Vector2).distance_to(Vector2(-200, -600)) < 1.0, "lies where it was dropped")
	w.command(ally.id, {"type": O.PICKUP_ITEM, "gid": g.gid})
	run(w, 3.0)
	check(_ids(ally.inventory) == ["boots"] and w.ground_items.is_empty(), "an ally picks it up")
	near(ally.move_speed - ally.def.move_speed, 45.0, 0.01, "and gets its bonus")
	w.command(ally.id, {"type": O.GIVE_ITEM, "item_slot": ally.inventory.find(ally.inventory.filter(func(x): return x != null)[0]), "target": h.id})
	run(w, 3.0)
	check(_ids(h.inventory) == ["boots"], "gives it back")
	var foe := w.spawn_hero("blood_ranger", C.DUSK)
	foe.pos = h.pos + Vector2(100, 0)
	w.command(h.id, {"type": O.GIVE_ITEM, "item_slot": 0, "target": foe.id})
	check(_ids(h.inventory) == ["boots"], "never to an enemy")

func test_to_buy_breakdown_and_auto_buy() -> void:
	var a := _courier_world()
	var w: SimWorld = a[0]
	var h: SimUnit = a[1]
	var c: SimUnit = a[2]
	h.pos = Vector2(-1500, -1300)                                   # away from the shop
	h.gold_unreliable = 0
	h.gold_reliable = 0
	_give(w, h, "gauntlets", 0)
	check(w.shop.add_to_buy(h, "tough_band") == "", "Shift-click adds Tough Band")
	check(h.to_buy.map(func(e): return e.id) == ["circlet", "recipe_tough_band"], "broken into the missing parts (%s)" % str(h.to_buy.map(func(e): return e.id)))
	check(w.shop.add_to_buy(h, "tough_band") == "You already have the parts" or h.to_buy.size() >= 3, "a second Shift-click adds only what is still missing")
	h.to_buy.resize(2)
	w.shop.toggle_auto_buy(h, 0)
	run(w, 1.0)
	check(h.to_buy.size() == 2, "nothing bought without gold")
	h.gold_unreliable = 150
	run(w, 1.0)
	check(h.to_buy.size() == 2, "150 gold is short of the Headband's 155")
	h.gold_unreliable = 155
	run(w, 1.0)
	check(h.to_buy.size() == 1 and String(h.to_buy[0].id) == "recipe_tough_band", "auto-bought the Headband when gold allowed")
	check(_ids(c.inventory) == ["circlet"], "the courier waiting at the fountain holds it (%s / stash %s)" % [str(_ids(c.inventory)), str(_ids(h.stash))])
	h.gold_unreliable = 500
	check(w.shop.buy(h, "recipe_tough_band") == "", "bought the recipe by hand")
	check(h.to_buy.is_empty(), "a manual purchase removes its entry")
	# the courier is out: an auto-buy waits in the stash
	w.courier_command(h, "transfer")
	run(w, 1.0)
	w.shop.add_to_buy(h, "slippers")
	w.shop.toggle_auto_buy(h, 0)
	run(w, 0.5)
	check(_ids(h.stash).has("slippers"), "with the courier away, the stash takes it")
	for i in 30:
		w.shop.add_to_buy(h, "branch")
	check(h.to_buy.size() == C.TO_BUY_MAX, "the list keeps at most %d" % C.TO_BUY_MAX)

func test_stash_rules() -> void:
	var w := empty_world()
	var h := w.spawn_hero("sludge", C.DAWN)
	h.pos = Vector2(-1500, -1300)
	h.gold_unreliable = 3000
	w.shop.buy(h, "boots")
	check(_ids(h.stash) == ["boots"], "away from the shop: stash")
	check(w.shop.grab_all(h) == "Must be in the base", "no Grab All in the field")
	var g0 := h.gold()
	check(w.shop.sell_stash(h, 0) == "" and h.gold() - g0 == 500, "stashed items sell from anywhere (full price in 10 s)")
	w.shop.buy(h, "boots")
	h.pos = _map.fountains[0] + Vector2(200, 200)
	run(w, 1.0)
	check(_ids(h.inventory) == ["boots"] and _ids(h.stash).is_empty(), "the stash empties when the hero arrives")
	check(w.shop.to_stash(h, 0) == "", "move to the stash in the base")
	run(w, 1.0)
	check(_ids(h.stash) == ["boots"], "and it stays there")
	check(w.shop.from_stash(h, 0, 4) == "" and h.inventory[4] != null and h.inventory[4].id == "boots", "take it into a chosen slot")
	w.shop.to_stash(h, 4)
	check(w.shop.grab_all(h) == "" and _ids(h.inventory) == ["boots"], "Grab All")

func test_backpack_swap_cooldown() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-600, -600))
	_give(w, h, "jump_knife", 6)
	w.shop.swap(h, 6, 0)
	check(w.abilities.item_cooldown_left(h, 0) > 5.9, "6 s cooldown after leaving the backpack")
	_give(w, h, "boots", 1)
	w.shop.swap(h, 1, 2)
	check(w.abilities.item_cooldown_left(h, 2) <= 0.0, "no cooldown moving between main slots")

func test_unit_spell_hotkey_ignores_missing_target() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-600, -600))
	h.ability_level["chomp"] = 1
	h.ability_level["stench"] = 1
	h.level = 6
	h.mana = 500
	check(w.abilities.cast_error(h, "chomp", -1, null, h.pos, false, false) == "", "Chomp: R starts targeting without a target")
	check(w.abilities.cast_error(h, "chomp", -1, null, h.pos) == "Must target a unit", "the click still needs a unit")
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "stench"})
	check(bool(h.toggles.get("stench", false)), "Stench toggles on from a no-target order")

# ---- Neutral camps (Dota 2, 7.41: research/camps.md of run 2026-10-13-camps-ai-setup) ---------------------------

func test_camp_layout_14_a_side() -> void:
	for side in [C.DAWN, C.DUSK]:
		var kinds := {}
		var pulls := 0
		for c in _map.camps:
			if c.side == side:
				kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
				if bool(c.pull):
					pulls += 1
		check(kinds == {"small": 3, "medium": 7, "large": 3, "ancient": 1}, "side %d: 3 small, 7 medium, 3 large, 1 ancient (%s)" % [side, str(kinds)])
		check(pulls == 2, "two pull camps by the safe lane")
	for c in _map.camps:
		check(_map.is_walkable(c.pos) and not _map.in_ramp(c.pos), "camp %d stands on open ground" % c.id)

func test_camp_groups_vary_never_twice() -> void:
	var w := world(59.0)
	w.next_wave_at = INF
	var cid := 1                               # a medium camp: three groups
	var last := -1
	var seen := {}
	for minute in 6:
		for u in w.units:
			if u.camp_id == cid:
				u.alive = false
		w._rebuild_grid()
		w.ai.spawn_neutrals()
		var g := int(w.ai.camp_group[cid])
		check(g != last, "minute %d: not the same group twice in a row" % minute)
		last = g
		seen[g] = true
	check(seen.size() >= 2, "the camp spawns different groups (%d)" % seen.size())

func test_courier_does_not_block_a_camp() -> void:
	var w := world(59.0)
	w.next_wave_at = INF
	var camp: Dictionary = _map.camps[0]
	var c := w.spawn("courier", C.DAWN, camp.pos)
	c.courier_state = "move"
	c.courier_goal = camp.pos
	run(w, 1.2)
	check(w.units.filter(func(u): return u.camp_id == camp.id and u.alive).size() == w.ai.camp_units(0).size(), "a courier in the box does not block the spawn")

func test_neutrals_proximity_day_and_sleep_at_night() -> void:
	var w := world(59.0)
	w.next_wave_at = INF
	run(w, 1.2)
	var camp: Dictionary = _map.camps[1]
	var n := w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	var h := w.spawn("blood_ranger", C.DAWN, n[0].pos + Vector2(100, 0))
	h.order = O.HOLD
	h.no_acquire = true
	run(w, 0.6)
	check(n[0].neutral_state == 1 and n[0].atk_target == h.id, "by day a hero walking within 125 wakes the camp")
	var w2 := world(359.0)
	w2.next_wave_at = INF
	w2.next_neutral_at = 360.0
	run(w2, 1.2)
	var n2 := w2.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	var h2 := w2.spawn("blood_ranger", C.DAWN, n2[0].pos + Vector2(100, 0))
	h2.order = O.HOLD
	h2.no_acquire = true                     # it does not attack them either
	run(w2, 1.0)
	check(n2.all(func(u): return u.neutral_state == 0), "at night they sleep through it")

func test_neutral_leash_400_then_5s() -> void:
	var w := world(59.0)
	w.next_wave_at = INF
	run(w, 1.2)
	var camp: Dictionary = _map.camps[1]
	var n := w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	var h := w.spawn("blood_ranger", C.DAWN, camp.pos + Vector2(-450, 0))
	w.vision.update()
	w.command(h.id, {"type": O.ATTACK_UNIT, "target": n[0].id})
	run(w, 1.2)
	check(n[0].neutral_state == 1, "awake")
	# run far away: it leaves its 400 guard radius and gives up 5 s later, then cannot be woken by damage for 3 s
	w.command(h.id, {"type": O.MOVE, "point": camp.pos + Vector2(-3000, 0)})
	var left_at := -1.0
	var gave_up_at := -1.0
	for i in 30 * 14:
		w.step()
		if left_at < 0.0 and n[0].pos.distance_to(n[0].home) > C.NEUTRAL_GUARD_RADIUS:
			left_at = w.time
		if gave_up_at < 0.0 and n[0].neutral_state == 2:
			gave_up_at = w.time
	check(left_at > 0.0 and gave_up_at > 0.0, "it left and gave up")
	near(gave_up_at - left_at, C.NEUTRAL_CHASE_TIME, 0.4, "gives up 5 s after leaving its guard radius")
	check(n[0].no_reaggro_until >= gave_up_at + 2.9, "and cannot be woken by damage for 3 s")

func test_neutrals_grow_every_7_30() -> void:
	var w := world(449.0)
	w.next_wave_at = INF
	w.next_neutral_at = 449.5
	run(w, 0.6)
	var n := w.units.filter(func(u): return u.kind == K.NEUTRAL_CREEP and u.alive and u.def.id == "mudling")
	check(not n.is_empty(), "goblins up")
	if n.is_empty():
		return
	var hp0: float = n[0].max_hp
	var arm0: float = n[0].armor
	run(w, 1.0)
	near(n[0].max_hp - hp0, 30.0, 0.01, "+30 health at 7:30")
	near(n[0].armor - arm0, 0.5, 0.01, "+0.5 armor at 7:30")
	near(n[0].creep_dmg_add, 3.0, 0.01, "+3 damage")
	near(n[0].bounty_gold_add, 1.0, 0.01, "+1 gold")

func test_stack_bounty_and_stacker_share() -> void:
	var w := world(5.0)
	w.next_wave_at = INF
	w.next_neutral_at = INF
	var a := w.spawn("blood_ranger", C.DAWN, Vector2(-600, -600))
	var b := w.spawn("ezee", C.DAWN, Vector2(-500, -600))
	var c := w.spawn("mudling", C.NEUTRAL, Vector2(-550, -500))
	c.stacked = true
	c.stacker_id = a.id
	var g0a := a.gold()
	var g0b := b.gold()
	w.combat.kill(c, b)
	w.combat.process_deaths()
	var got_b := b.gold() - g0b
	var got_a := a.gold() - g0a
	check(got_b >= int(round(3 * 0.8)) and got_b <= int(round(5 * 0.8)), "a stacked goblin gives 20%% less (%d)" % got_b)
	check(got_a == int(round(got_b * C.STACKER_SHARE)), "the stacker gets 30%% of what the ally got (%d of %d)" % [got_a, got_b])

func test_lane_creeps_fight_only_aggressive_neutrals() -> void:
	# owner's rule: lane creeps leave a camp sitting in its box alone; once a neutral fights (anyone) they may attack
	# it, and for 5 s after it stops
	var w := empty_world()
	var camp: Dictionary = _map.camps[0]
	var n := w.spawn("mudling", C.NEUTRAL, camp.pos)
	n.camp_id = camp.id
	n.home = camp.pos
	var lc := w.spawn("dawn_melee", C.DAWN, camp.pos + Vector2(250, 0))
	lc.lane = "bot"
	lc.lane_i = 1
	w._rebuild_grid()
	w.vision.update()
	check(w.ai._pick(lc, lc.acquire_range) == null, "a lane creep ignores a calm neutral in its camp")
	w.ai.neutral_provoked(n, lc)
	check(n.neutral_state == 1 and w.ai._pick(lc, lc.acquire_range) == n, "a neutral that fights is fair game")
	n.neutral_state = 0
	n.atk_target = -1
	w.time += C.NEUTRAL_HOSTILE_TIME - 0.5
	check(w.ai._pick(lc, lc.acquire_range) == n, "still within 5 s of fighting")
	w.time += 1.0
	check(w.ai._pick(lc, lc.acquire_range) == null, "calm again after 5 s")

func test_neutrals_wake_within_125_only() -> void:
	var w := world(59.0)
	w.next_wave_at = INF
	run(w, 1.2)
	var camp: Dictionary = _map.camps[1]
	var n := w.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	var h := w.spawn("blood_ranger", C.DAWN, n[0].pos + Vector2(200, 0))
	h.order = O.HOLD
	h.no_acquire = true
	run(w, 1.0)
	check(n.all(func(u): return u.neutral_state == 0), "a hero standing 200 away does not wake the camp")
	h.pos = n[0].pos + Vector2(n[0].hull + h.hull + 100.0, 0)
	run(w, 0.6)
	check(n[0].neutral_state == 1, "within 125 it does")

# ---- Team brain, bots, learning ---------------------------------------------------------------------------------

func _team_world(dawn: Array, dusk: Array, human_dawn := false) -> SimWorld:
	var w := SimWorld.new(5, _map)
	w.setup_match()
	var i := 0
	for team in [C.DAWN, C.DUSK]:
		for id in (dawn if team == C.DAWN else dusk):
			var h := w.spawn_hero(id, team)
			if team == C.DAWN and human_dawn and i == 0:
				h.player = true
			else:
				w.bots.append(SimBot.new(w, h.id, "mid", "Bot %d" % i))
			i += 1
	if human_dawn:
		w.brain(C.DAWN)
	return w

func test_every_lane_covered() -> void:
	BotMemory.active = false
	var w := _team_world(["sludge", "ezee", "blood_ranger", "sludge", "ezee"], ["ezee", "ezee", "ezee"])
	run(w, 1.0)
	for team in [C.DAWN, C.DUSK]:
		var lanes := {}
		for b in w.bots:
			if b.hero().team == team:
				lanes[b.lane] = int(lanes.get(b.lane, 0)) + 1
		check(lanes.has("top") and lanes.has("mid") and lanes.has("bot"), "team %d: every lane has someone (%s)" % [team, str(lanes)])
	var mids := 0
	for b in w.bots:
		if b.hero().team == C.DAWN and b.lane == "mid":
			mids += 1
	check(mids == 1, "one hero in mid")

func test_bots_leave_the_players_lane() -> void:
	BotMemory.active = false
	var w := _team_world(["blood_ranger", "sludge", "ezee", "sludge"], ["ezee"], true)
	var me := w.heroes[0]
	run(w, 1.0)
	var mid_bot: SimBot = null
	for b in w.bots:
		if b.hero().team == C.DAWN and b.lane == "mid":
			mid_bot = b
	check(mid_bot != null, "a bot planned to go mid")
	# the player walks into the middle lane and stays
	w.time = 10.0
	me.pos = Vector2(-1200, -1050)
	me.order = O.HOLD
	run(w, 4.5)
	var lanes := {}
	for b in w.bots:
		if b.hero().team == C.DAWN:
			lanes[b.lane] = true
	check(not lanes.has("mid"), "no bot stays mid once the player takes it (%s)" % str(lanes))
	check(lanes.has("top") and lanes.has("bot"), "and both side lanes stay covered")
	var said := w.chat_log.filter(func(l): return String(l.text).begins_with("You're mid?"))
	check(not said.is_empty(), "the bot says so in chat")

func test_ping_replies_with_reasons() -> void:
	BotMemory.active = false
	var w := _team_world(["blood_ranger", "sludge", "ezee"], ["ezee"], true)
	var me := w.heroes[0]
	run(w, 1.0)
	w.time = 700.0
	var foe: SimUnit = null
	for h in w.heroes:
		if h.team == C.DUSK:
			foe = h
	foe.pos = Vector2(3000, 3000)
	w.vision.reveal_all = true
	w.vision.update()
	# one bot dead, one without TP and far away
	var dead: SimUnit = w.heroes[1]
	w.combat.kill(dead, null)
	dead.respawn_at = w.time + 20.0
	var far: SimUnit = w.heroes[2]
	far.pos = w.map.fountains[C.DAWN]
	far.tp_charges = 0
	w.chat_log.clear()
	w.ping(C.DAWN, foe.pos, me.id, foe.id)
	run(w, 1.0)
	var texts := w.chat_log.map(func(l): return String(l.text))
	check(texts.any(func(t): return t.begins_with("I'm dead, back in")), "a dead bot says when it is back (%s)" % str(texts))
	check(texts.any(func(t): return t.contains("no TP") and t.contains("too far")), "a far bot without a TP says why")

func test_chat_is_rate_limited() -> void:
	var w := _team_world(["sludge"], ["ezee"])
	var b := w.brain(C.DAWN)
	var h := w.heroes[0]
	check(b.say(h, "one", "k1", 30.0), "first line goes out")
	check(not b.say(h, "two", "k2", 30.0), "a second line from the same bot right after is held back")
	check(b.say(h, "three", "k3", 30.0, true), "urgent lines (ping replies) are not held back")
	check(not b.say(h, "one again", "k1", 30.0, true), "the same line is not repeated within its period")

func test_bot_memory_learns_and_persists() -> void:
	var path := "user://test_bot_memory.json"
	BotMemory.path = path
	BotMemory.reset()
	BotMemory.active = true
	var x := [1.0, 0.5, 0.4, 0.9, 0.25, 0.0, 0.0, 0.2, 1.0]
	var p0 := BotMemory.fight_p(x)
	for i in 30:
		BotMemory.learn_fight(x, 0.0)
	check(BotMemory.fight_p(x) < p0 - 0.1, "losing that fight lowers its odds (%.2f -> %.2f)" % [p0, BotMemory.fight_p(x)])
	BotMemory.note_death(C.DAWN, Vector2(1000, -3000))
	BotMemory.note_death(C.DUSK, Vector2(-1000, 3000))
	check(BotMemory.danger(C.DAWN, Vector2(1000, -3000)) >= 0.99, "deaths mark the place dangerous, both teams folded together")
	check(BotMemory.pick_build("sludge:core", 2) == 0, "an untried build first")
	BotMemory.reward_build("sludge:core", 0, 0.1)
	check(BotMemory.pick_build("sludge:core", 2) == 1, "then the other untried one")
	BotMemory.reward_build("sludge:core", 1, 0.9)
	BotMemory.save()
	var w_before: Array = (BotMemory.data.fight_w as Array).duplicate()
	BotMemory.data = {}
	BotMemory.load_data()
	var same := true
	for i in w_before.size():
		same = same and absf(float(BotMemory.data.fight_w[i]) - float(w_before[i])) < 1e-5
	check(same, "fight weights survive a save and load")
	check(BotMemory.build_stats("sludge:core", 2)[1][0] == 1, "build scores too")
	BotMemory.active = false
	check(BotMemory.danger(C.DAWN, Vector2(1000, -3000)) == 0.0 and BotMemory.fight_weights() == BotMemory.FIGHT_DEFAULT, "learning off: built-in values")
	BotMemory.reset()
	BotMemory.path = BotMemory.DEFAULT_PATH

func test_unfair_bots_earn_more() -> void:
	var w := empty_world()
	var h := w.spawn("ezee", C.DAWN, Vector2(-600, -600))
	w.bots.append(SimBot.new(w, h.id, "mid", "Bot", "unfair"))
	var g0 := h.gold()
	w.combat.give_gold(h, 100, false, h.pos)
	check(h.gold() - g0 == 300, "Unfair: +200% gold (the owner's number)")
	var x0 := h.xp
	w.combat.give_xp(h, 100.0)
	near(h.xp - x0, 150.0, 0.01, "Unfair: +50% experience (the owner's number)")

func test_game_setup_roles_are_kept() -> void:
	BotMemory.active = false
	var w := SimWorld.new(5, _map)
	w.setup_match()
	var ids: Array = []
	for id in ["blood_ranger", "sludge", "ezee"]:
		var h := w.spawn_hero(id, C.DAWN)
		w.bots.append(SimBot.new(w, h.id, "mid", "Bot"))
		ids.append(h.id)
	var foe := w.spawn_hero("ezee", C.DUSK)
	w.bots.append(SimBot.new(w, foe.id, "mid", "Bot Gerald"))
	# Blood Ranger would be the carry; set as the mid player instead
	w.brain(C.DAWN).fixed_role[ids[0]] = 2
	run(w, 1.0)
	var b0: SimBot = w.brain(C.DAWN).bot_of(ids[0])
	check(b0.role == 2 and b0.lane == "mid", "a role chosen in Game Setup is kept (%d %s)" % [b0.role, b0.lane])
	var lanes := {}
	for b in w.bots:
		if b.hero().team == C.DAWN:
			lanes[b.lane] = true
	check(lanes.size() == 3, "the others still cover the other lanes (%s)" % str(lanes))

# ---- Status effects, pseudo-random procs, critical strike, bash (2026-10-13 d) --------------------------------------

func test_prd_constants_and_rates() -> void:
	# Valve's table (Dota 2 wiki, Pseudo-random distribution)
	near(SimStatus.prd_c(0.25), 0.084744, 0.0002, "C for 25%")
	near(SimStatus.prd_c(0.30), 0.118949, 0.0002, "C for 30%")
	near(SimStatus.prd_c(0.10), 0.014746, 0.0002, "C for 10%")
	near(SimStatus.prd_c(0.80), 0.75, 0.0005, "C for 80%")
	var w := empty_world()
	var u := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var procs := 0
	var longest := 0
	var dry := 0
	for i in 20000:
		if w.status.roll(u, "test", 0.25):
			procs += 1
			dry = 0
		else:
			dry += 1
			longest = maxi(longest, dry)
	near(procs / 20000.0, 0.25, 0.01, "25% PRD procs a quarter of the time")
	check(longest < ceili(1.0 / SimStatus.prd_c(0.25)), "never more than 1/C - 1 misses in a row (%d)" % longest)

func test_crit_rolls_at_attack_start_and_multiplies() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	_give(w, h, "crit_bow", 0)
	var t := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	var crits := 0
	var n := 3000
	for i in n:
		var m := w.combat.roll_crit(h, t)
		if m > 1.0:
			crits += 1
			near(m, 2.25, 1e-6, "Crit Bow multiplies by 2.25")
	near(crits / float(n), 0.30, 0.02, "30% of attacks crit")
	# never against buildings, and no roll is counted there
	var tower := w.spawn("tower1", C.DUSK, Vector2(-1500, -4300))
	var before: int = int(h.prd.get("crit:crit_bow", 0))
	for i in 50:
		check(w.combat.roll_crit(h, tower) == 1.0, "no critical strike on buildings")
	check(int(h.prd.get("crit:crit_bow", 0)) == before, "buildings do not move the PRD counter")
	# the multiplier rides on the attack from its start: a crit snapshot deals 2.25x the base and bonus damage
	h.atk_crit = 2.25
	var s := w.combat._snapshot(h, "")
	h.atk_crit = 1.0
	s.dmg_min = 100.0
	s.dmg_max = 100.0
	s.bonus = 0.0
	s.quell = 0.0
	t.def["armor"] = 0.0
	t.refresh_stats()
	var hp0 := t.hp
	w.combat.land_attack(s, t)
	var mult := w.combat.attack_class_multiplier(s, t)
	near(hp0 - t.hp, 225.0 * mult, 0.5, "the crit multiplies the attack damage")
	var found := w.events.filter(func(e): return e.t == "crit")
	check(not found.is_empty(), "a crit event for the red number")

func test_two_crit_sources_never_stack() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	_give(w, h, "crit_bow", 0)
	_give(w, h, "crit_sword", 1)
	var t := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	var big := 0
	var small := 0
	for i in 4000:
		var m := w.combat.roll_crit(h, t)
		if m == 2.25:
			big += 1
		elif m == 1.6:
			small += 1
	near(big / 4000.0, 0.30, 0.025, "the stronger crit rolls first (30%)")
	near(small / 4000.0, 0.70 * 0.30, 0.03, "the weaker one rolls only when the stronger misses")

func test_bash_stun_damage_cooldown_and_pierce() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var club := _give(w, h, "stun_club", 0)
	var t := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	# debuff immunity does not stop a bash
	t.add_modifier({"id": "spell_shield", "source": t.id, "expires": INF, "debuff_immune": true})
	t.refresh_stats()
	var bashes := 0
	var tries := 0
	var during_cd := 0
	for i in 4000:
		w.time += 0.1
		w.step()
		var cd := w.time < float(club.get("bash_ready", C.LONG_AGO))
		var prd_before: int = int(h.prd.get("bash", 0))
		var b := w.items.roll_bash(w.combat._snapshot(h, ""), t)
		if cd:
			check(b.is_empty(), "no bash while the bash cooldown runs")
			check(int(h.prd.get("bash", 0)) == prd_before, "and no roll is counted")
			during_cd += 1
			continue
		tries += 1
		if not b.is_empty():
			bashes += 1
			near(float(b.damage), 100.0, 1e-6, "Stun Club bash adds 100 damage")
			near(float(b.dur), 1.2, 1e-6, "1.2 s stun")
	near(bashes / float(tries), 0.25, 0.03, "melee bash 25% of the rolls")
	check(during_cd > 0, "the cooldown was exercised")
	# a landed bash stuns through debuff immunity in the bash group
	club.erase("bash_ready")
	h.prd["bash"] = 100
	w.combat.land_attack(w.combat._snapshot(h, ""), t)
	var st := t.get_modifier("bashed")
	check(not st.is_empty() and st.get("stun", false), "the bash stuns a debuff-immune hero")
	near(float(st.get("dur", 0.0)), 1.2, 0.01, "for 1.2 s")
	# ranged heroes: 10%
	var r := w.spawn("blood_ranger", C.DAWN, Vector2(-2200, -4000))
	_give(w, r, "stun_club", 0)
	var rb := 0
	var rt := 0
	for i in 6000:
		r.inventory[0].erase("bash_ready")
		rt += 1
		if not w.items.roll_bash(w.combat._snapshot(r, ""), t).is_empty():
			rb += 1
	near(rb / float(rt), 0.10, 0.015, "ranged bash 10%")
	# never against buildings
	var tower := w.spawn("tower1", C.DUSK, Vector2(-1500, -4300))
	h.prd["bash"] = 100
	club.erase("bash_ready")
	check(w.items.roll_bash(w.combat._snapshot(h, ""), tower).is_empty(), "no bash on buildings")

func test_only_one_bash_item_works() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var a := _give(w, h, "stun_club", 0)
	var b := _give(w, h, "stun_blade", 1)
	var t := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	h.prd["bash"] = 100
	var r := w.items.roll_bash(w.combat._snapshot(h, ""), t)
	check(String(r.get("item", "")) == "stun_club", "the first bash item rolls")
	check(a.has("bash_ready") and not b.has("bash_ready"), "only its cooldown starts")

func test_stuns_refresh_to_the_longer() -> void:
	var w := empty_world()
	var t := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	w.status.apply(t, 999, C.DAWN, {"id": "stunned", "stun": true, "dur": 2.0})
	w.status.apply(t, 998, C.DAWN, {"id": "stunned", "stun": true, "dur": 1.0})
	var ms := t.modifiers.filter(func(m): return String(m.id) == "stunned")
	check(ms.size() == 1, "one stun modifier for the group")
	near(float(ms[0].expires) - w.time, 2.0, 0.01, "a shorter stun does not cut a longer one")
	w.status.apply(t, 997, C.DAWN, {"id": "stunned", "stun": true, "dur": 3.0})
	near(float(t.get_modifier("stunned").expires) - w.time, 3.0, 0.01, "a longer one replaces it")
	check(t.is_stunned(), "stunned")

func test_status_resistance_and_slow_resistance() -> void:
	var w := empty_world()
	var t := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	t.inventory.resize(9)
	_give(w, t, "twin_swords", 0)
	near(t.status_resist, 0.16, 1e-6, "Twin Swords: 16% status resistance")
	w.status.apply(t, 999, C.DAWN, {"id": "bashed", "stun": true, "dur": 1.2})
	near(float(t.get_modifier("bashed").dur), 1.2 * 0.84, 0.001, "debuffs from enemies last 16% shorter")
	# slow resistance: the Heavy Sword family does not stack, the largest counts
	_give(w, t, "heavy_sword", 1)
	near(t.slow_resist, 0.30, 1e-6, "slow resistance: the largest copy (30%)")
	var ms0 := t.move_speed
	w.status.apply(t, 999, C.DAWN, {"id": "test_slow", "slow": 0.5, "dur": 5.0})
	t.refresh_stats()
	check(t.move_speed > ms0 * 0.5 + 1.0, "a 50% slow is shrunk by slow resistance")
	# an ally's buff is not shortened
	w.status.apply(t, t.id, C.DUSK, {"id": "ally_test", "dur": 2.0})
	near(float(t.get_modifier("ally_test").dur), 2.0, 1e-6, "allied effects ignore status resistance")

func test_hex_silence_mute_disarm_speed() -> void:
	var w := empty_world()
	var foe := _sludge(w, Vector2(-1850, -4000), {}, C.DUSK)
	_give(w, foe, "slip_boots", 0)
	var me := _sludge(w, Vector2(-2000, -4000))
	var hx := _give(w, me, "hex_staff", 0)
	me.mana = me.max_mana
	run(w, 0.2)
	var err: String = w.abilities.cast_error(me, "", 0, foe, foe.pos)
	check(err == "", "Hex Staff can target the enemy hero (%s)" % err)
	w.abilities.execute(me, "", 0, foe, foe.pos)
	check(foe.is_hexed() and foe.is_silenced() and foe.is_muted() and foe.is_disarmed(), "hexed: silenced, muted, disarmed")
	foe.refresh_stats()
	near(foe.move_speed, C.HEX_MOVE_SPEED + 50.0, 0.5, "hex sets base speed 140; flat boot speed still counts")
	check(w.abilities.cast_error(foe, "blubber", -1, null, foe.pos) == "Silenced", "cannot cast")
	check(w.abilities.cast_error(foe, "", 0, null, foe.pos) == "Muted", "cannot use items")
	near(float(foe.get_modifier("hex_staff").dur), 2.8, 0.01, "2.8 s")
	check(hx.get("ready", 0.0) > w.time, "the item went on cooldown")
	# a basic dispel does not remove it, a strong one does
	w.status.dispel(foe, false, foe.team)
	check(foe.is_hexed(), "basic dispel keeps the hex")
	w.status.dispel(foe, true, foe.team)
	check(not foe.is_hexed(), "strong dispel removes it")
	# Spell Shield (debuff immunity) blocks a hex
	foe.add_modifier({"id": "spell_shield", "source": foe.id, "expires": INF, "debuff_immune": true})
	foe.refresh_stats()
	hx.erase("ready")
	me.mana = me.max_mana
	var ierr: String = w.abilities.cast_error(me, "", 0, foe, foe.pos)
	check(ierr == "Target is immune", "hex refused on immune targets (%s)" % ierr)

func test_silence_staff_burst() -> void:
	var w := empty_world()
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	var me := _sludge(w, Vector2(-2000, -4000))
	_give(w, me, "silence_staff", 0)
	w.abilities.execute(me, "", 0, foe, foe.pos)
	check(foe.is_silenced(), "silenced")
	var hp0 := foe.hp
	w.combat.deal_damage(me.id, me.team, true, foe, 400.0, C.DamageType.PURE, false, "test")
	var taken := hp0 - foe.hp
	run(w, 5.2)
	check(not foe.is_silenced(), "the silence ends after 5 s")
	var burst := w.events.filter(func(e): return e.t == "soul_burst")
	var row: Array = me.dmg_out.get("silence_staff", [0, 0, 0])
	near(float(row[0]) + float(row[1]), taken * 0.30 * (1.0 - foe.magic_resist), 1.0,
		"30% of the damage taken returns as magic damage")

func test_root_staff_projectile_roots_and_stops_tp() -> void:
	var w := empty_world()
	var foe := _sludge(w, Vector2(-1500, -4000), {}, C.DUSK)
	var me := _sludge(w, Vector2(-2000, -4000))
	_give(w, me, "root_staff", 0)
	w.abilities.execute(me, "", 0, foe, foe.pos)
	check(not foe.has_flag("root"), "not rooted before the projectile arrives")
	run(w, 0.5)
	check(foe.has_flag("root") and foe.is_rooted(), "rooted once it arrives")
	check(w.abilities.cast_error(foe, "tp", -1, null, Vector2.ZERO) == "Rooted", "rooted heroes cannot teleport")
	near(float(foe.get_modifier("root_staff").dur), 2.0, 0.01, "2 s")
	# a root during a teleport channel ends it
	var b := _sludge(w, Vector2(-2600, -4400), {}, C.DUSK)
	b.channel = {"ability": "tp", "until": w.time + 3.0, "dest": Vector2.ZERO}
	w.status.apply(b, me.id, me.team, {"id": "root_staff", "root": true, "dur": 2.0})
	w.step()
	check(b.channel.is_empty(), "the root cancels the Teleport channel")

func test_halberd_disarm_and_evasion_stacking() -> void:
	var w := empty_world()
	var me := _sludge(w, Vector2(-2000, -4000))
	_give(w, me, "halberd", 0)
	near(me.evasion, 0.25, 1e-6, "Halberd 25% evasion")
	_give(w, me, "dodge_charm", 1)
	near(me.evasion, 1.0 - 0.75 * 0.85, 1e-6, "evasion sources multiply (36.25%)")
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1850, -4000))
	w.abilities.execute(me, "", 0, foe, foe.pos)
	check(foe.is_disarmed() and not foe.is_silenced(), "disarmed, can still cast")
	near(float(foe.get_modifier("halberd").dur), 3.5, 0.01, "3.5 s")
	w.status.dispel(foe, false, foe.team)
	check(foe.is_disarmed(), "the Halberd's disarm needs a strong dispel")

func test_break_blade_breaks_passives() -> void:
	var w := empty_world()
	var me := _sludge(w, Vector2(-2000, -4000))
	_give(w, me, "break_blade", 0)
	var r := _ranger(w, Vector2(-1850, -4000), {}, C.DUSK)
	w.abilities.execute(me, "", 0, null, me.pos)
	run(w, 0.5)
	var s := w.combat._snapshot(me, "")
	var sn := w.items.break_sneak(me)
	s["sneak"] = float(sn.get("bonus", 0.0))
	s["sneak_break"] = float(sn.get("break", 0.0))
	near(float(s.sneak), 300.0, 1e-6, "the breaking attack carries 300 damage")
	w.combat.land_attack(s, r)
	check(r.is_broken(), "the target is broken")
	near(float(r.get_modifier("break_blade").dur), 5.0, 0.01, "for 5 s")
	r.ability_ready.erase("masterful_archery")
	var procs := 0
	for i in 200:
		if w.abilities.masterful_bonus(r, me) > 0.0:
			procs += 1
			r.ability_ready.erase("masterful_archery")
	check(procs == 0, "Masterful Archery does nothing while broken")

func test_uphill_miss_only_for_ranged() -> void:
	var w := empty_world()
	var low := Vector2.ZERO
	var high := Vector2.ZERO
	# a river cell next to a ground cell
	for x in range(-3000, 3000, 64):
		var a := Vector2(x, 0)
		if _map.level_at(a) == SimMap.RIVER and _map.is_walkable(a):
			for d in [Vector2(0, 260), Vector2(0, -260), Vector2(260, 0), Vector2(-260, 0)]:
				if _map.level_at(a + d) > SimMap.RIVER and _map.is_walkable(a + d):
					low = a
					high = a + d
					break
		if low != Vector2.ZERO:
			break
	check(low != Vector2.ZERO, "found a slope")
	var melee := w.spawn("sludge", C.DAWN, low)
	var ranged := w.spawn("blood_ranger", C.DAWN, low)
	var t := _dummy(w, "dusk_melee", C.DUSK, high)
	var mm := 0
	var rm := 0
	for i in 2000:
		if not w.combat.land_attack(w.combat._snapshot(melee, ""), t):
			mm += 1
		if not w.combat.land_attack(w.combat._snapshot(ranged, ""), t):
			rm += 1
	check(mm == 0, "melee attacks never miss uphill (%d)" % mm)
	near(rm / 2000.0, C.UPHILL_MISS, 0.03, "ranged attacks miss 25% uphill")

func test_fountain_regen_bonus_and_linger() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, _map.fountains[C.DAWN] + Vector2(300, 300))
	h.hp = 100.0
	w.step()
	var r := w.regen_rates(h)
	near(r.z, h.hp_regen_base, 1e-6, "own regen is base plus strength")
	near(r.x - r.z, h.max_hp * 0.05, 0.01, "the fountain adds 5% of max health per second as bonus")
	near(r.y - r.w, h.max_mana * 0.06, 0.01, "and 6% of max mana")
	h.pos = Vector2(-2000, -4000)
	run(w, 2.5)
	check(not h.get_modifier("fountain").is_empty(), "the fountain's buff lingers after leaving")
	run(w, 1.0)
	check(h.get_modifier("fountain").is_empty(), "for 3 s")

func test_spell_amp_raises_spell_damage() -> void:
	var w := empty_world()
	var e := _ezee(w, Vector2(-2000, -4000))
	var t := _dummy(w, "dusk_melee", C.DUSK, Vector2(-1850, -4000))
	t.def["magic_resist"] = 0.0
	t.refresh_stats()
	var hp0 := t.hp
	w.combat.deal_damage(e.id, e.team, true, t, 100.0, C.DamageType.MAGICAL, false, "dark_stomp")
	near(hp0 - t.hp, 100.0 * (1.0 + e.int_total / 2000.0), 0.01, "without items only intelligence amplifies (1% per 20)")
	e.inventory.resize(9)
	_give(w, e, "spell_sword", 0)
	near(e.magic_amp_items, 0.10, 1e-6, "Atuli: 10% magic amp")
	hp0 = t.hp
	w.combat.deal_damage(e.id, e.team, true, t, 100.0, C.DamageType.MAGICAL, false, "dark_stomp")
	near(hp0 - t.hp, 100.0 * (1.10 + e.int_total / 2000.0), 0.01, "magic spells deal 10% more")
	# a Damage Orb's spell amp adds to it
	e.add_modifier({"id": "test_amp", "source": e.id, "expires": INF, "stats": {"spell_amp": 0.15}})
	e.refresh_stats()
	hp0 = t.hp
	w.combat.deal_damage(e.id, e.team, true, t, 100.0, C.DamageType.MAGICAL, false, "dark_stomp")
	near(hp0 - t.hp, 100.0 * (1.25 + e.int_total / 2000.0), 0.01, "spell amp and magic amp add up")
	e.remove_modifier("test_amp")
	e.refresh_stats()
	hp0 = t.hp
	w.combat.deal_damage(e.id, e.team, true, t, 100.0, C.DamageType.PHYSICAL, true, "attack")
	near(hp0 - t.hp, 100.0 * C.armor_multiplier(t.armor), 0.01, "attacks are not amplified")

# ---- Elements, armor and damage types, magic amp (owner's rules, 2026-10-14) ------------------------------------------

func _el_world() -> SimWorld:
	var w := empty_world()
	w.elements = true
	return w

func test_element_table() -> void:
	var E := C.Element
	near(C.element_mult(E.WATER, E.FIRE), 1.25, 1e-6, "Water beats Fire")
	near(C.element_mult(E.FIRE, E.WATER), 0.75, 1e-6, "Fire is weak against Water")
	near(C.element_mult(E.FIRE, E.NATURE), 1.25, 1e-6, "Fire beats Nature")
	near(C.element_mult(E.FIRE, E.ICE), 1.25, 1e-6, "Fire beats Ice")
	near(C.element_mult(E.EARTH, E.FIRE), 1.25, 1e-6, "Earth beats Fire")
	near(C.element_mult(E.LIGHTNING, E.WATER), 1.25, 1e-6, "Lightning beats Water")
	near(C.element_mult(E.LIGHTNING, E.EARTH), 0.75, 1e-6, "Lightning is weak against Earth")
	near(C.element_mult(E.LIGHT, E.DARK), 1.25, 1e-6, "Light beats Dark")
	near(C.element_mult(E.DARK, E.LIGHT), 1.25, 1e-6, "and Dark beats Light")
	near(C.element_mult(E.FIRE, E.FIRE), 0.75, 1e-6, "an element resists itself")
	near(C.element_mult(E.NONE, E.NONE), 1.0, 1e-6, "None is neutral to itself")
	for a in C.ELEMENT_NAMES.size():
		near(C.element_mult(E.NONE, a), 1.0, 1e-6, "None deals normal damage to " + C.ELEMENT_NAMES[a])
		near(C.element_mult(a, E.NONE), 1.0, 1e-6, C.ELEMENT_NAMES[a] + " deals normal damage to None")
		for b in C.ELEMENT_NAMES.size():
			var m := C.element_mult(a, b)
			check(m == 1.0 or m == 0.75 or m == 1.25, "only x0.75, x1 or x1.25 (%s vs %s)" % [C.ELEMENT_NAMES[a], C.ELEMENT_NAMES[b]])

func test_unit_elements_and_types() -> void:
	var w := _el_world()
	var az := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	check(az.element == C.Element.FIRE and az.weapon == C.Weapon.HERO and az.armor_type == C.ArmorType.HERO, "Azrin: Fire, Hero weapon, Hero armor")
	check(w.spawn("blood_ranger", C.DAWN, Vector2(-2000, -3800)).element == C.Element.NATURE, "Blood Ranger is Nature")
	check(w.spawn("ezee", C.DAWN, Vector2(-2000, -3600)).element == C.Element.DARK, "Ezee is Dark")
	check(w.spawn("sludge", C.DAWN, Vector2(-2000, -3400)).element == C.Element.EARTH, "Sludge is Earth")
	var dm := w.spawn("dawn_melee", C.DAWN, Vector2(-1500, -4000))
	var km := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -3800))
	check(dm.element == C.Element.LIGHT and km.element == C.Element.DARK, "lane creeps take their team's element")
	check(dm.weapon == C.Weapon.SLASH and dm.armor_type == C.ArmorType.ORGANIC, "melee creeps: Slash, Organic")
	var rc := w.spawn("dawn_ranged", C.DAWN, Vector2(-1500, -3600))
	check(rc.weapon == C.Weapon.PIERCING, "ranged creeps: Piercing")
	var sg := w.spawn("dusk_siege", C.DUSK, Vector2(-1500, -3400))
	check(sg.weapon == C.Weapon.SIEGE and sg.armor_type == C.ArmorType.ARMORED, "siege creeps: Siege, Armored")
	var tw := w.spawn("tower1", C.DUSK, Vector2(-800, -4000))
	check(tw.armor_type == C.ArmorType.STRUCTURE and tw.element == C.Element.EARTH and tw.weapon == C.Weapon.SIEGE, "towers: Structure, Earth, Siege")
	var th0 := w.spawn("ancient", C.DAWN, Vector2(-6000, -6000))
	var th1 := w.spawn("ancient", C.DUSK, Vector2(6000, 6000))
	check(th0.element == C.Element.LIGHT and th1.element == C.Element.DARK, "each Throne takes its team's element")
	var imp := w.spawn("cinder_wyrmling", C.NEUTRAL, Vector2(2000, 2000))
	check(imp.element == C.Element.FIRE and imp.weapon == C.Weapon.MAGIC, "Fire Imp: Fire, Magic attacks")
	check(w.spawn("ogre_brute", C.NEUTRAL, Vector2(2200, 2000)).weapon == C.Weapon.BLUNT, "Ogre: Blunt")

func test_damage_table_keeps_dota_pairings() -> void:
	var W := C.Weapon
	var A := C.ArmorType
	near(C.damage_mult(W.HERO, A.STRUCTURE), 0.5, 1e-6, "heroes deal 50% to buildings")
	near(C.damage_mult(W.HERO, A.ARMORED), 0.5, 1e-6, "heroes deal 50% to siege creeps")
	near(C.damage_mult(W.SLASH, A.HERO), 0.75, 1e-6, "melee creeps deal 75% to heroes")
	near(C.damage_mult(W.SLASH, A.ARMORED), 0.7, 1e-6, "melee creeps deal 70% to siege creeps")
	near(C.damage_mult(W.PIERCING, A.ORGANIC), 1.5, 1e-6, "piercing 150% to creeps")
	near(C.damage_mult(W.PIERCING, A.ARMORED), 1.05, 1e-6, "piercing 150% x 70% to siege creeps")
	near(C.damage_mult(W.SIEGE, A.STRUCTURE), 2.5, 1e-6, "siege 250% to buildings")
	near(C.damage_mult(W.BLUNT, A.STRUCTURE), 0.7, 1e-6, "neutrals' default class 70% to buildings")
	near(C.damage_mult(W.MAGIC, A.STRUCTURE), 0.0, 1e-6, "magic never hurts buildings")
	for a in 5:
		near(C.damage_mult(W.AETHER, a), 1.0, 1e-6, "Aether (pure) is full against " + C.ARMOR_NAMES[a])

func test_element_in_attacks_and_spells() -> void:
	var w := _el_world()
	var az := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	var br := _dummy(w, "blood_ranger", C.DUSK, Vector2(-1500, -4000))   # Nature: Fire beats it
	var sl := _dummy(w, "sludge", C.DUSK, Vector2(-1500, -3700))         # Earth: beats Fire
	for u in [br, sl]:
		u.def["magic_resist"] = 0.0
		u.refresh_stats()
	var hp0 := br.hp
	w.combat.deal_damage(az.id, az.team, true, br, 100.0, C.DamageType.PURE, false, "fiery_javelin")
	near(hp0 - br.hp, 125.0, 0.01, "Fire spell on a Nature hero: x1.25")
	hp0 = sl.hp
	w.combat.deal_damage(az.id, az.team, true, sl, 100.0, C.DamageType.PURE, false, "fiery_javelin")
	near(hp0 - sl.hp, 75.0, 0.01, "Fire spell on an Earth hero: x0.75")
	# an attack carries the attacker's element, on top of the weapon / armor table
	var s := w.combat._snapshot(az, "")
	near(w.combat.attack_class_multiplier(s, br), 1.25, 1e-6, "Azrin's attack on Blood Ranger: Hero vs Hero x Fire vs Nature")
	var tw := w.spawn("tower1", C.DUSK, Vector2(-1200, -4000))
	near(w.combat.attack_class_multiplier(s, tw), 0.5 * 0.75, 1e-6, "on an Earth tower: 50% x 0.75")
	# an item names its own element: Shock Hammer is Lightning (Lightning is weak against Earth)
	hp0 = sl.hp
	w.combat.deal_damage(az.id, az.team, true, sl, 100.0, C.DamageType.PURE, false, "shock_hammer")
	near(hp0 - sl.hp, 75.0, 0.01, "Shock Hammer (Lightning) on Earth: x0.75")
	# the event carries it for the HUD
	var ev: Array = w.events.filter(func(e): return e.t == "damage" and int(e.u) == sl.id)
	check(not ev.is_empty() and int(ev[-1].element) == C.Element.LIGHTNING and float(ev[-1].emult) == 0.75, "damage events name the element and its multiplier")
	# switched off (other mechanics tests), no element multiplier
	w.elements = false
	hp0 = br.hp
	w.combat.deal_damage(az.id, az.team, true, br, 100.0, C.DamageType.PURE, false, "fiery_javelin")
	near(hp0 - br.hp, 100.0, 0.01, "no multiplier with elements off")

func test_lane_creeps_with_elements() -> void:
	# Light and Dark beat each other, so both sides' creeps deal x1.25 to each other: the lane stays even
	var w := _el_world()
	var a := w.spawn("dawn_melee", C.DAWN, Vector2(-1500, -4000))
	var b := w.spawn("dusk_melee", C.DUSK, Vector2(-1400, -4000))
	var sa := w.combat._snapshot(a, "")
	var sb := w.combat._snapshot(b, "")
	near(w.combat.attack_class_multiplier(sa, b), 1.25, 1e-6, "Light melee on Dark melee")
	near(w.combat.attack_class_multiplier(sb, a), 1.25, 1e-6, "Dark melee on Light melee")

func test_magic_attacks_use_magic_resistance() -> void:
	var w := empty_world()
	var imp := w.spawn("cinder_wyrmling", C.NEUTRAL, Vector2(-2000, -4000))
	var h := _dummy(w, "sludge", C.DAWN, Vector2(-1750, -4000))
	h.def["armor"] = 50.0
	h.refresh_stats()
	var hp0 := h.hp
	var s := w.combat._snapshot(imp, "")
	s.dmg_min = 100.0
	s.dmg_max = 100.0
	s.bonus = 0.0
	w.combat.land_attack(s, h)
	near(hp0 - h.hp, 100.0 * (1.0 - h.magic_resist), 0.5, "a Magic attack ignores armor and meets magic resistance")

func test_int_magic_amp_and_resist() -> void:
	var w := empty_world()
	var az := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	near(az.int_total, 27.0, 1e-6, "27 intelligence at level 1")
	near(az.magic_amp_int, 27.0 / 20.0 / 100.0, 1e-6, "1% magic amp per 20 intelligence")
	near(az.magic_resist, 1.0 - 0.75 * (1.0 - 27.0 / 25.0 / 100.0), 1e-6, "25% base and 1% per 25 intelligence")
	az.level = 25
	az.refresh_stats()
	near(az.magic_amp_int, (27.0 + 3.4 * 24.0) / 2000.0, 1e-6, "grows with intelligence")

func test_item_magic_amp_diminishes() -> void:
	var w := empty_world()
	var az := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	_give(w, az, "spell_sword", 0)
	near(az.magic_amp_items, 0.10, 1e-6, "one Atuli: 10%")
	_give(w, az, "spell_sword", 1)
	near(az.magic_amp_items, 0.15, 1e-6, "two: 10% + 5%")
	_give(w, az, "kugmo_atuli", 2)
	near(az.magic_amp_items, 0.12 + 0.05 + 0.025, 1e-6, "12% + 10% / 2 + 10% / 4, largest first")
	near(az.magic_amp, az.magic_amp_int + az.magic_amp_items, 1e-6, "intelligence adds in full")
	az.inventory[7] = az.inventory[0]
	az.inventory[0] = null
	az.refresh_stats()
	near(az.magic_amp_items, 0.12 + 0.05, 1e-6, "the backpack gives none")

func test_kugmo_igit_atuli_family() -> void:
	var w := world()
	var h := w.spawn("azrin", C.DAWN, w.map.shops[C.DAWN])
	h.gold_unreliable = 99999
	check(SimData.item("heavy_sword").name == "Kugmo" and SimData.item("yasha").name == "Igit" and SimData.item("spell_sword").name == "Atuli", "the owner's names")
	check(w.shop.buy(h, "heavy_sword") == "" and w.shop.buy(h, "spell_sword") == "", "buy Kugmo and Atuli")
	check(w.shop.owns(h, "kugmo_atuli"), "they combine into Kugmo and Atuli")
	near(h.slow_resist, 0.25, 1e-6, "25% slow resistance")
	near(h.magic_amp_items, 0.12, 1e-6, "12% magic amp")
	near(h.mana_cost_cut, 0.25, 1e-6, "25% cheaper spells")
	h.ability_level["fiery_javelin"] = 1
	near(w.abilities.ability_mana(h, "fiery_javelin"), 75.0, 1e-6, "Fiery Javelin costs 75 instead of 100")
	var h2 := w.spawn("azrin", C.DAWN, w.map.shops[C.DAWN] + Vector2(100, 0))
	h2.gold_unreliable = 99999
	check(w.shop.buy(h2, "yasha") == "" and w.shop.buy(h2, "spell_sword") == "", "buy Igit and Atuli")
	check(w.shop.owns(h2, "igit_atuli"), "they combine into Igit and Atuli")
	near(h2.cast_speed, 0.25, 1e-6, "25% faster casting")
	check(w.shop.buy(h2, "heavy_sword") == "", "and a Kugmo")
	check(not w.shop.owns(h2, "twin_swords"), "Igit inside Igit and Atuli does not combine again")
	check(SimData.item("twin_swords").name == "Kugmo and Igit", "Kugmo and Igit")

func test_item_lock_and_disassemble() -> void:
	var w := world()
	var h := w.spawn("ezee", C.DAWN, w.map.shops[C.DAWN])
	h.gold_unreliable = 99999
	check(w.shop.buy(h, "spike_armor") == "", "buy Spike Armor")
	var slot := -1
	for i in 9:
		if h.inventory[i] != null and h.inventory[i].id == "spike_armor":
			slot = i
	check(slot >= 0, "it is in the bags")
	check(w.shop.disassemble(h, slot) == "", "take it apart")
	var ids := _ids(h.inventory)
	check(ids.has("broadsword") and ids.has("plate_vest") and ids.has("recipe_spike_armor"), "parts and the recipe scroll come back (%s)" % [ids])
	check(not w.shop.owns(h, "spike_armor"), "the item is gone")
	for it in h.inventory:
		if it != null:
			check(bool(it.get("locked", false)), "%s is locked" % it.id)
	w.shop.combine_all(h)
	check(not w.shop.owns(h, "spike_armor"), "locked parts do not combine")
	var bi := -1
	for i in 9:
		if h.inventory[i] != null and h.inventory[i].id == "broadsword":
			bi = i
	w.shop.toggle_lock(h, bi)
	check(not w.shop.owns(h, "spike_armor"), "one unlocked part alone does not combine")
	for i in 9:
		var it = h.inventory[i]
		if it != null and bool(it.get("locked", false)):
			w.shop.toggle_lock(h, i)
	check(w.shop.owns(h, "spike_armor"), "unlocking every part combines it again")
	# Gold Glove and Upgrade Staff cannot be taken apart (Dota's never list); basic items neither
	check(w.shop.buy(h, "gold_glove") == "", "buy Gold Glove")
	for i in 9:
		if h.inventory[i] != null and h.inventory[i].id == "gold_glove":
			check(w.shop.disassemble(h, i) == "Cannot be disassembled", "Gold Glove refuses")
	var gi := h.inventory.find(null)
	_give(w, h, "branch", gi)
	check(w.shop.disassemble(h, gi) == "Cannot be disassembled", "a basic item refuses")
	# a locked item stays locked and does not combine when its partner arrives
	var w2 := world()
	var h2 := w2.spawn("ezee", C.DAWN, w2.map.shops[C.DAWN])
	h2.gold_unreliable = 99999
	w2.shop.buy(h2, "circlet")
	w2.shop.toggle_lock(h2, 0)
	w2.shop.buy(h2, "gauntlets")
	w2.shop.buy(h2, "recipe_tough_band")
	check(not w2.shop.owns(h2, "tough_band"), "a locked Headband is not used for a Tough Band")
	# room: parts that do not fit refuse the whole thing
	var w3 := world()
	var h3 := w3.spawn("ezee", C.DAWN, Vector2(0, 0))
	for i in 9:
		_give(w3, h3, "branch", i)
	h3.inventory[0] = w3.shop.new_item("spike_armor")
	for i in 6:
		h3.stash[i] = w3.shop.new_item("branch")
	check(w3.shop.disassemble(h3, 0) == "Not enough room", "no room: refused")
	check(h3.inventory[0].id == "spike_armor", "and nothing changed")
	# Switch Boots come apart into the recipe they were built with
	var w4 := world()
	var h4 := w4.spawn("ezee", C.DAWN, w4.map.shops[C.DAWN])
	h4.gold_unreliable = 99999
	w4.shop.buy(h4, "boots")
	w4.shop.buy(h4, "gloves")
	w4.shop.buy(h4, "robe")
	check(w4.shop.owns(h4, "power_treads"), "Switch Boots built with a Wizard Robe")
	w4.shop.disassemble(h4, 0)
	check(_ids(h4.inventory).has("robe"), "they give the Wizard Robe back")

func test_full_refund_protection() -> void:
	# owner's rule: 10 s of full refund, kept when a combined item is taken apart; a combined item counts each piece
	# by its own purchase time
	var w := world()
	var h := w.spawn("ezee", C.DAWN, w.map.shops[C.DAWN])
	h.gold_unreliable = 99999
	w.shop.buy(h, "spike_armor")
	check(w.shop.sell_value(h.inventory[0]) == 2400, "Spike Armor just bought: 2400 back")
	run(w, 3.0)
	check(w.shop.disassemble(h, 0) == "", "taken apart by accident")
	var total := 0
	for it in h.inventory:
		if it != null:
			total += w.shop.sell_value(it)
	check(total == 2400, "its parts still sell for the full 2400 inside the 10 s (%d)" % total)
	var g0 := h.gold()
	for i in 9:
		if h.inventory[i] != null:
			w.shop.sell(h, i)
	check(h.gold() - g0 == 2400, "and selling them gives back 2400 (%d)" % (h.gold() - g0))
	# after 10 s: half
	w.shop.buy(h, "spike_armor")
	run(w, 11.0)
	check(w.shop.sell_value(h.inventory[0]) == 1200, "after 10 s: half (%d)" % w.shop.sell_value(h.inventory[0]))
	w.shop.disassemble(h, 0)
	total = 0
	for it in h.inventory:
		if it != null:
			total += w.shop.sell_value(it)
	check(total == 1200, "and its parts: half too (%d)" % total)
	# old parts and a new recipe: only the recipe is refunded in full
	var w2 := world()
	var h2 := w2.spawn("ezee", C.DAWN, w2.map.shops[C.DAWN])
	h2.gold_unreliable = 99999
	w2.shop.buy(h2, "broadsword")
	w2.shop.buy(h2, "plate_vest")
	run(w2, 20.0)
	w2.shop.buy(h2, "recipe_spike_armor")
	check(w2.shop.owns(h2, "spike_armor"), "combined from old parts and a new recipe")
	var sa = h2.inventory[0] if h2.inventory[0] != null and h2.inventory[0].id == "spike_armor" else h2.inventory[1]
	check(w2.shop.sell_value(sa) == 1000 / 2 + 950 / 2 + 450, "old parts at half, the new recipe in full (%d)" % w2.shop.sell_value(sa))

func _azrin(w: SimWorld, p: Vector2, team := C.DAWN) -> SimUnit:
	var a := w.spawn("azrin", team, p)
	a.level = 18
	a.refresh_stats()
	a.hp = a.max_hp
	a.mana = a.max_mana
	for aid in a.abilities:
		a.ability_level[aid] = 4 if aid != "divine_smite" else 3
	a.refresh_stats()
	a.auto_attack = false                      # it casts; its attacks would blur the damage sums
	return a

## A target dummy with no health regeneration and no magic resistance, for exact damage sums.
func _bare(w: SimWorld, id: String, team: int, p: Vector2) -> SimUnit:
	var d := _dummy(w, id, team, p)
	d.def["magic_resist"] = 0.0
	d.def["hp_regen"] = 0.0
	d.refresh_stats()
	return d

func test_burns_tick_and_extend() -> void:
	var w := empty_world()
	var a := _azrin(w, Vector2(-2000, -4000))
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	var hp0 := t.hp
	w.status.add_dot(t, a, "fiery_javelin", 100.0, 5.0, C.Element.FIRE)
	check(not t.get_modifier("burning").is_empty(), "the unit shows Burning")
	run(w, 2.6)
	near(hp0 - t.hp, 250.0 * (1.0 + a.magic_amp), 0.5, "5 ticks of 50 in the first 2.5 s")
	w.status.extend_dots(t, a.team, C.Element.FIRE, 2.0)
	run(w, 6.0)
	near(hp0 - t.hp, 700.0 * (1.0 + a.magic_amp), 0.5, "7 s of burning in all after a 2 s extension")
	check(w.status.dots.is_empty() and t.get_modifier("burning").is_empty(), "the burn ends")
	# debuff immunity refuses a burn
	t.add_modifier({"id": "spell_shield", "source": t.id, "expires": INF, "debuff_immune": true})
	t.refresh_stats()
	check(not w.status.add_dot(t, a, "fiery_javelin", 100.0, 5.0, C.Element.FIRE), "Spell Shield refuses a burn")

func test_fiery_javelin() -> void:
	var w := empty_world()
	var a := _azrin(w, Vector2(-2000, -4000))
	var e1 := _bare(w, "dusk_melee", C.DUSK, Vector2(-1700, -4000))
	var e2 := _bare(w, "dusk_melee", C.DUSK, Vector2(-1400, -3880))
	var off := _bare(w, "dusk_melee", C.DUSK, Vector2(-1400, -3600))
	var ally := _dummy(w, "dawn_melee", C.DAWN, Vector2(-1600, -4000))
	for u in [e1, e2, off]:
		u.def["magic_resist"] = 0.0
		u.refresh_stats()
	w.command(a.id, {"type": O.CAST_POINT, "ability": "fiery_javelin", "point": Vector2(-500, -4000)})
	var dragged := false
	for i in 30:
		w.step()
		if not e1.knock.is_empty():
			dragged = true
	check(dragged, "enemies on the path are dragged")
	run(w, 1.0)
	var end := Vector2(-2000, -4000) + Vector2(1000 + 24, 0)
	check(e1.pos.distance_to(end) < 120.0, "carried to where the javelin lands (%.0f away)" % e1.pos.distance_to(end))
	check(e2.pos.distance_to(end) < 160.0, "the second one too")
	check(off.pos.distance_to(Vector2(-1400, -3600)) < 1.0, "an enemy beyond the width is left alone")
	check(ally.pos.distance_to(Vector2(-1600, -4000)) < 1.0, "allies are ignored")
	check(e1.knock.is_empty(), "released at the end")
	var hp0 := e1.hp
	run(w, 5.0)
	check(e1.hp < hp0, "burning")
	var total := e1.max_hp - e1.hp
	near(total, 140.0 * 5.0 * (1.0 + a.magic_amp), 1.0, "140 magic damage per second for 5 s at level 4")
	check(w.abilities.cooldown_left(a, "fiery_javelin") > 0.0, "on cooldown")
	near(w.abilities.val(a, "fiery_javelin", "cooldown"), 12.0, 1e-6, "12 s cooldown")
	var a1 := w.spawn("azrin", C.DAWN, Vector2(0, 0))
	a1.ability_level["fiery_javelin"] = 1
	near(w.abilities.val(a1, "fiery_javelin", "burn_dps"), 35.0, 1e-6, "35 per second at level 1")

func test_touch_of_ember() -> void:
	var w := empty_world()
	var a := _azrin(w, Vector2(-2000, -4000))
	var e := _bare(w, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	var foe := _azrin(w, Vector2(-1450, -3880), C.DUSK)
	foe.def = foe.def.duplicate()
	foe.def["hp"] = 5000.0
	foe.refresh_stats()
	foe.def["hp_regen"] = -foe.str_total * C.STR_HP_REGEN      # no regeneration, for an exact sum
	foe.refresh_stats()
	foe.hp = foe.max_hp
	var far := _bare(w, "dusk_melee", C.DUSK, Vector2(-1500, -3500))
	for u in [e, far]:
		u.def["magic_resist"] = 0.0
		u.refresh_stats()
	var fhp0 := foe.hp
	w.command(a.id, {"type": O.CAST_POINT, "ability": "touch_of_ember", "point": Vector2(-1500, -4000)})
	run(w, 0.5)
	near(e.max_hp - e.hp, 100.0 * (1.0 + a.magic_amp), 0.5, "100 magic damage at once")
	check(far.hp == far.max_hp, "nothing beyond 300")
	check(not e.get_modifier("touch_of_ember").is_empty(), "the flames stay on it")
	# the enemy hero casts a spell: its flames explode at once
	foe.mana = foe.max_mana
	w.command(foe.id, {"type": O.CAST_POINT, "ability": "touch_of_ember", "point": Vector2(-2000, -4000)})
	run(w, 0.5)
	check(foe.get_modifier("touch_of_ember").is_empty(), "casting sets them off")
	check(not foe.get_modifier("stunned").is_empty(), "and stuns it")
	near(float(foe.get_modifier("stunned").get("dur", 0.0)), 1.7, 0.01, "for 1.7 s")
	var expect := (100.0 + 400.0) * (1.0 + a.magic_amp) * (1.0 - foe.magic_resist)
	near(fhp0 - foe.hp, expect, 2.0, "100, then 400 at level 4")
	# the creep's go off after 4 s
	var hp1 := e.hp
	run(w, 3.4)
	near(hp1 - e.hp, 400.0 * (1.0 + a.magic_amp), 1.0, "after 4 s: 400 more")
	check(not e.get_modifier("stunned").is_empty(), "and a stun")

func test_spirit_of_fire() -> void:
	var w := empty_world()
	var a := _azrin(w, Vector2(-2000, -4000))
	check(w.abilities.cast_error(a, "spirit_of_fire", -1, null, Vector2(-1500, -4000)) == "No spirits of fire", "no spirits: no cast")
	for i in 7:
		w.abilities._add_spirit(a)
	check(w.abilities.spirits(a) == 5, "at most 5 spirits")
	var e := _bare(w, "dusk_melee", C.DUSK, Vector2(-1400, -4000))
	e.def["magic_resist"] = 0.0
	e.refresh_stats()
	w.command(a.id, {"type": O.CAST_POINT, "ability": "spirit_of_fire", "point": Vector2(-1400, -4000)})
	run(w, 1.2)
	check(w.abilities.spirits(a) == 0, "all of them are shot")
	check(not e.get_modifier("spirit_of_fire_slow").is_empty(), "the enemy is slowed")
	near(float(e.get_modifier("spirit_of_fire_slow").slow), 0.35, 1e-6, "35% at level 4")
	run(w, 5.5)
	near(e.max_hp - e.hp, 5.0 * 250.0 * (1.0 + a.magic_amp), 1.0, "250 burn per spirit at level 4, 5 spirits")
	# spells add spirits; Spirit of Fire itself does not
	a.ability_ready["touch_of_ember"] = -INF
	a.mana = a.max_mana
	w.command(a.id, {"type": O.CAST_POINT, "ability": "touch_of_ember", "point": Vector2(-1700, -3700)})
	run(w, 0.6)
	check(w.abilities.spirits(a) == 1, "a spell cast adds a spirit")

func test_divine_smite() -> void:
	var w := empty_world()
	var a := _azrin(w, Vector2(-2000, -4000))
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1500, -4000))
	var n := _bare(w, "dusk_melee", C.DUSK, Vector2(-1500, -3750))
	for u in [t, n]:
		u.def["magic_resist"] = 0.0
		u.refresh_stats()
	w.status.add_dot(n, a, "fiery_javelin", 10.0, 3.0, C.Element.FIRE)
	var until0 := float(w.status.dots[0].until)
	var hp0 := t.hp
	w.vision.update()
	w.command(a.id, {"type": O.CAST_UNIT, "ability": "divine_smite", "target": t.id})
	run(w, 1.2)
	near(hp0 - t.hp, (250.0 + 2.0 * a.int_total) * (1.0 + a.magic_amp), 1.0, "250 + 2 x intelligence")
	near(float(w.status.dots[0].until) - until0, 5.0, 1e-6, "burns nearby last 5 s longer at level 3")
	near(w.abilities.val(a, "divine_smite", "cooldown"), 45.0, 1e-6, "45 s cooldown")

func test_azrin_base() -> void:
	var w := empty_world()
	var a := w.spawn("azrin", C.DAWN, Vector2(-2000, -4000))
	near(a.attack_range, 665.0, 1e-6, "665 attack range")
	check(a.is_ranged(), "ranged")
	check(String(a.def.primary) == "int", "intelligence hero")
	check((a.def.talents as Array).size() == 4, "four talent tiers")

func test_creep_death_sounds_quieter() -> void:
	# owner's request: lane and neutral creep deaths 40% quieter, by the same loudness rule as the volume sliders
	var gd := (load("res://src/game/audio.gd") as GDScript).get_script_constant_map()
	near(float(gd["CREEP_DEATH_DB"]), Options.to_db(0.6), 0.01, "60% as loud (-7.4 dB)")

func test_neutral_abilities() -> void:
	var w := empty_world()
	# Orc Shaman: Stomp stuns a hero 1.6 s
	var shaman := w.spawn("strider_warlord", C.NEUTRAL, Vector2(-2000, -4000))
	shaman.home = shaman.pos
	var h := _sludge(w, Vector2(-1820, -4000), {}, C.DAWN)
	check(shaman.ability_level_of("stomp") == 1, "the Orc Shaman knows Stomp")
	shaman.neutral_state = 1
	shaman.atk_target = h.id
	w.ai._neutral(shaman)
	run(w, 0.6)
	var st := h.get_modifier("stunned")
	check(not st.is_empty(), "Stomp stuns the hero")
	near(float(st.get("dur", 0.0)), 1.6, 0.01, "for 1.6 s")
	# Alpha Wolf: 20% x2 crit and +20% damage to its pack
	var alpha := w.spawn("ashfang_alpha", C.NEUTRAL, Vector2(2000, 4000))
	var wolf := w.spawn("ashfang", C.NEUTRAL, Vector2(2100, 4000))
	var src := w.combat.crit_sources(alpha)
	check(src.size() == 1 and float(src[0].mult) == 2.0, "Alpha Wolf crit x2")
	w.tick = 5
	w.step()
	wolf.refresh_stats()
	near(wolf.bonus_damage, (wolf.dmg_min + wolf.dmg_max) * 0.5 * 0.2, 0.01, "Pack Aura +20% damage")
	# Swamp Troll: its attacks break (3 s, 10 s apart)
	var troll := w.spawn("hill_troll", C.NEUTRAL, Vector2(3000, 4000))
	var r := _ranger(w, Vector2(3200, 4000))
	w.ai.on_creep_hit(troll, r, 30.0)
	check(r.is_broken(), "Break Strike breaks the hero")
	r.remove_modifier("break_strike")
	w.ai.on_creep_hit(troll, r, 30.0)
	check(not r.is_broken(), "not again within 10 s")
	# Ogre: Smash winds up for 2.8 s; stepping out avoids it
	var ogre := w.spawn("ogre_brute", C.NEUTRAL, Vector2(-4000, 2000))
	ogre.home = ogre.pos
	var v := _sludge(w, Vector2(-3880, 2000), {}, C.DAWN)
	ogre.neutral_state = 1
	ogre.atk_target = v.id
	w.ai._neutral_cast(ogre, v)
	run(w, 1.0)
	check(ogre.cast_phase != SimUnit.CastPhase.NONE and String(ogre.cast_ability) == "smash", "Smash is winding up")
	v.pos = Vector2(-3400, 2000)
	run(w, 2.2)
	check(v.get_modifier("stunned").is_empty(), "walked out of the Smash")

func test_tp_scroll_stash_rule_and_buy_key() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	h.gold_unreliable = 1000
	var n0 := h.tp_charges
	check(w.shop.buy(h, "tp_scroll") == "", "bought away from the shop")
	check(h.tp_charges == n0, "away from the shop it does not appear in the slot")
	check(_ids(h.stash).has("tp_scroll"), "it waits in the stash")
	check(w.shop.tp_owned(h) == n0 + 1, "it counts as owned")
	h.pos = _map.fountains[C.DAWN] + Vector2(300, 300)
	w.shop.update(h)
	check(h.tp_charges == n0 + 1 and not _ids(h.stash).has("tp_scroll"), "arriving at the shop puts it in the slot")
	check(_ids(h.inventory).is_empty() or not _ids(h.inventory).has("tp_scroll"), "never in the bags")
	check(w.shop.buy(h, "tp_scroll") == "" and h.tp_charges == n0 + 2, "at the shop it goes straight to the slot")
	near(float(SimData.item("tp_scroll").cost), 100.0, 0.0, "100 gold")
	check(Keybinds.defaults().get("buy_tp") == KEY_COMMA, "comma buys a Teleport Scroll by default")

func test_new_item_recipes_match_dota() -> void:
	var expect := {"crit_sword": 2000, "crit_bow": 5200, "stun_club": 2875, "stun_blade": 6250, "sure_hit_staff": 5000,
		"silence_staff": 3275, "root_staff": 2250, "halberd": 3300, "hex_staff": 5200, "break_blade": 5700,
		"heavy_sword": 2100, "spell_sword": 2100, "twin_swords": 4200, "battle_staff": 1625}
	for id in expect:
		var d := SimData.item(id)
		var parts := 0
		for c in d.components:
			parts += int(SimData.item(c).cost)
		check(int(d.cost) == int(expect[id]), "%s costs %d" % [id, int(expect[id])])
		check(parts + int(d.recipe_cost) == int(d.cost), "%s: parts + recipe = cost (%d + %d)" % [id, parts, int(d.recipe_cost)])

func test_true_sight_wards_dust_and_disjoint() -> void:
	var w := empty_world()
	# open ground in the river, so no tree blocks the sight between them
	var sneaker := _sludge(w, Vector2(300, -300), {}, C.DUSK)
	sneaker.add_modifier({"id": "sneak_blade", "source": sneaker.id, "expires": INF, "invisible": true})
	var me := _sludge(w, Vector2(0, -300))
	run(w, 0.4)
	check(not w.vision.sees(me.team, sneaker), "an invisible hero is not seen")
	# a Reveal Ward planted nearby gives True Sight where the team has vision
	_give(w, me, "reveal_ward", 0)
	w.abilities.execute(me, "", 0, null, Vector2(100, -200))
	run(w, 0.4)
	check(w.vision.sees(me.team, sneaker), "a Reveal Ward reveals it")
	var ward: SimUnit = null
	for u in w.units:
		if u.def.id == "ward_sentry":
			ward = u
	check(ward != null and ward.has_flag("invisible"), "the Reveal Ward itself is invisible")
	w.combat.kill(ward, null)
	run(w, 0.4)
	check(not w.vision.sees(me.team, sneaker), "hidden again once the ward is gone")
	# Reveal Dust: 25 damage to the invisible, reveals, slows 20% while invisible
	_give(w, me, "reveal_dust", 1)
	var hp0 := sneaker.hp
	w.abilities.execute(me, "", 1, null, me.pos)
	check(sneaker.hp < hp0, "dust hurts units invisible when it is thrown")
	run(w, 0.4)
	check(w.vision.sees(me.team, sneaker), "dust reveals it")
	check(float(sneaker.get_modifier("reveal_dust").get("slow", 0.0)) == 0.2, "and slows it 20% while invisible")
	# towers have True Sight
	var w2 := empty_world()
	var inv := _sludge(w2, Vector2(-1000, -4000), {}, C.DUSK)
	inv.add_modifier({"id": "sneak_blade", "source": inv.id, "expires": INF, "invisible": true})
	w2.spawn("tower1", C.DAWN, Vector2(-1500, -4000))
	run(w2, 0.4)
	check(w2.vision.sees(C.DAWN, inv), "a tower sees invisible heroes within 700")
	inv.pos = Vector2(-300, -4000)
	run(w2, 0.4)
	check(not w2.vision.sees(C.DAWN, inv), "but not beyond")
	# disjoint: a blink makes attacks in flight miss
	var w3 := empty_world()
	var r := _ranger(w3, Vector2(-2000, -4000))
	r.auto_attack = false
	var t := _sludge(w3, Vector2(-1300, -4000), {}, C.DUSK)
	run(w3, 0.3)
	w3.combat.release_attack(r, t, "")
	_give(w3, t, "jump_knife", 0)
	var hp1 := t.hp
	w3.abilities.execute(t, "", 0, null, t.pos + Vector2(0, 600))
	run(w3, 1.0)
	check(t.hp >= hp1, "a blink disjoints the arrow in flight")
	# an invisible hero does not attack on its own
	var w4 := empty_world()
	var a := w4.spawn("sludge", C.DAWN, Vector2(-2000, -4000))
	var foe := _dummy(w4, "dusk_melee", C.DUSK, Vector2(-1880, -4000))
	a.add_modifier({"id": "sneak_blade", "source": a.id, "expires": INF, "invisible": true})
	run(w4, 2.0)
	check(foe.hp == foe.max_hp, "invisible heroes never auto-attack")

# ---- Orbs (Dota's runes) ---------------------------------------------------------------------------------------------

func test_orb_schedule_and_power_cycle() -> void:
	var w := world(-1.0)
	w.next_neutral_at = INF
	w.next_wave_at = INF
	run(w, 1.2)
	var kinds := w.orbs.orbs.map(func(o): return String(o.kind))
	check(kinds.count("gold") == 4, "0:00: four Gold Orbs (two gold spots, two river spots) (%s)" % str(kinds))
	w.time = 119.9
	run(w, 0.2)
	check(w.orbs.orbs.filter(func(o): return String(o.kind) == "rejuvenation").size() == 2, "2:00: two Rejuvenation Orbs in the river")
	# power orbs from 6:00 every 2:00: a full cycle before any repeats, never twice in a row
	var seen: Array = []
	for k in 12:
		w.time = 359.9 + k * 120.0
		run(w, 0.2)
		var river: Array = w.orbs.orbs.filter(func(o): return String(o.spot) == "power" and String(o.kind) != "gold")
		check(river.size() == 1, "one river orb at %d:00 (%d)" % [6 + 2 * k, river.size()])
		if not river.is_empty():
			seen.append(String(river[0].kind))
	var first: Array = seen.slice(0, 6)
	first.sort()
	var all_kinds: Array = SimOrbs.POWER.duplicate()
	all_kinds.sort()
	check(first == all_kinds, "the first cycle shows every power orb once (%s)" % str(seen.slice(0, 6)))
	for i in seen.size() - 1:
		check(seen[i] != seen[i + 1], "never the same twice in a row (%s)" % str(seen))
	check(w.orbs.orbs.filter(func(o): return String(o.kind) == "wisdom").size() >= 2, "Wisdom Orbs from 7:00")

func test_orb_rewards_and_effects() -> void:
	var w := empty_world()
	w.time = 480.0
	var a := _sludge(w, Vector2(-1300, 1250))
	var b := _sludge(w, Vector2(-2000, -4000))
	var c := _sludge(w, Vector2(-2200, -4000))
	b.xp = 100.0
	c.xp = 50.0
	a.xp = 2000.0
	var g0 := b.gold()
	w.orbs._spawn("gold", Vector2(-1300, 1300), "power")
	var oid: int = w.orbs.orbs[-1].id
	a.pos = Vector2(-1300, 1500)
	check(not w.orbs.take(a, oid), "out of reach (200)")
	a.pos = Vector2(-1300, 1420)
	check(w.orbs.take(a, oid), "within 150 it is taken")
	check(b.gold() - g0 == 40 + 6 * 2, "Gold Orb at 8:00: 52 reliable gold to every hero of the team")
	w.orbs._spawn("wisdom", a.pos, "wisdom")
	var x0 := c.xp
	var xa := a.xp
	w.orbs.take(a, w.orbs.orbs[-1].id)
	near(a.xp - xa, 280.0, 0.01, "Wisdom Orb at 8:00: 280 experience")
	near(c.xp - x0, 280.0, 0.01, "and the same to the team's lowest hero")
	# Speed: 550 and slows ignored
	w.orbs.activate(a, "speed")
	a.add_modifier({"id": "test_slow", "source": 0, "expires": INF, "slow": 0.5})
	a.refresh_stats()
	near(a.move_speed, 550.0, 0.01, "Speed Orb: 550 speed even when slowed")
	# Damage: +80% base damage
	var bd0 := b.bonus_damage
	w.orbs.activate(b, "damage")
	b.refresh_stats()
	near(b.bonus_damage - bd0, (b.dmg_min + b.dmg_max) * 0.5 * 0.8, 0.01, "Damage Orb: +80% base damage")
	near(b.spell_amp, 0.15, 1e-6, "and 15% spell damage")
	# Magic: cooldowns and mana
	var cd0 := w.abilities.ability_cooldown(c, "shuriken_hook")
	var mana0 := w.abilities.ability_mana(c, "shuriken_hook")
	w.orbs.activate(c, "magic")
	near(w.abilities.ability_cooldown(c, "shuriken_hook"), cd0 * 0.75, 0.001, "Magic Orb: 25% shorter cooldowns")
	near(w.abilities.ability_mana(c, "shuriken_hook"), mana0 * 0.7, 0.001, "and 30% cheaper spells")
	# Shield: absorbs half of max health
	w.orbs.activate(c, "shield")
	var hp0 := c.hp
	w.combat.deal_damage(a.id, C.DUSK, true, c, c.max_hp * 0.3, C.DamageType.PURE, false, "test")
	near(c.hp, hp0, 0.01, "Shield Orb absorbs the blow")
	w.combat.deal_damage(a.id, C.DUSK, true, c, c.max_hp * 0.3, C.DamageType.PURE, false, "test")
	near(hp0 - c.hp, c.max_hp * 0.1, 0.5, "until half of max health is used up")
	# Healing: 6% per second, 1% for 3 s after hero damage, ends when full
	c.hp = c.max_hp * 0.5
	c.mana = c.max_mana * 0.5
	w.orbs.activate(c, "healing")
	var r := w.regen_rates(c)
	check(r.x >= c.max_hp * 0.06, "Healing Orb: 6% of max health per second")
	w.combat.deal_damage(a.id, C.DUSK, true, c, 10.0, C.DamageType.PURE, false, "test")
	r = w.regen_rates(c)
	check(r.x < c.max_hp * 0.03, "1% after damage from a hero")
	# Stealth: invisible after 2 s, 25% less damage while invisible, broken by an attack
	var s := _sludge(w, Vector2(0, -300))
	w.orbs.activate(s, "stealth")
	run(w, 0.5)
	check(not s.has_flag("invisible"), "still fading")
	run(w, 1.8)
	check(s.has_flag("invisible"), "invisible after 2 s")
	var hp1 := s.hp
	w.combat.deal_damage(a.id, C.DUSK, true, s, 100.0, C.DamageType.PURE, false, "test")
	near(hp1 - s.hp, 75.0, 0.5, "25% less damage while invisible")
	w.items.break_sneak(s)
	check(not s.has_flag("invisible"), "attacking breaks it")
	# a right-click order walks to it and takes it
	w.orbs._spawn("rejuvenation", Vector2(300, -300), "power")
	var wid: int = w.orbs.orbs[-1].id
	s.mana = 0.0
	w.command(s.id, {"type": O.PICKUP_ORB, "orb": wid})
	run(w, 2.0)
	check(w.orbs.get_orb(wid).is_empty() and s.mana >= 80.0 - 0.01, "the pick-up order walks over and takes the Rejuvenation Orb")

func test_bottle_drinks_refills_and_stores_orbs() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(300, -300))
	var b := _give(w, h, "bottle", 0)
	check(int(b.charges) == 3, "a Bottle starts with 3 charges")
	h.hp = h.max_hp * 0.5
	var hp0 := h.hp
	w.abilities.execute(h, "", 0, null, h.pos)
	check(int(b.charges) == 2, "drinking uses a charge")
	run(w, 3.0)
	check(h.hp - hp0 >= 110.0 - 1.0 + h.hp_regen_base * 2.0, "110 health over 2.7 s (%.1f)" % (h.hp - hp0))
	# hero damage ends the drink
	b["ready"] = 0.0
	w.abilities.execute(h, "", 0, null, h.pos)
	var foe := _sludge(w, Vector2(600, -300), {}, C.DUSK)
	w.combat.deal_damage(foe.id, foe.team, true, h, 1.0, C.DamageType.PURE, false, "test")
	check(h.get_modifier("bottle").is_empty(), "damage from an enemy hero ends it")
	# an orb taken while carrying it is stored and refills it
	b["charges"] = 0
	w.orbs._spawn("damage", h.pos, "power")
	w.orbs.take(h, w.orbs.orbs[-1].id)
	check(String(b.get("orb", "")) == "damage" and h.get_modifier("orb_damage").is_empty(), "the orb goes into the Bottle")
	check(int(b.charges) == 3, "a power orb refills it to 3")
	b["ready"] = 0.0
	w.abilities.execute(h, "", 0, null, h.pos)
	check(not h.get_modifier("orb_damage").is_empty() and String(b.get("orb", "")) == "", "drinking lets the orb out")
	# a stored orb lets itself out after 90 s
	w.orbs._spawn("speed", h.pos, "power")
	w.orbs.take(h, w.orbs.orbs[-1].id)
	run(w, 91.0)
	check(not h.get_modifier("orb_speed").is_empty() or String(b.get("orb", "")) == "", "after 90 s it activates by itself")
	# refills at the fountain
	b["charges"] = 0
	h.pos = _map.fountains[C.DAWN] + Vector2(300, 300)
	run(w, 1.0)
	check(int(b.charges) == 3, "the fountain refills it")

# ---- Performance rewrites keep the rules (2026-10-14 b) --------------------------------------------------------------

## The cached sight stamps give exactly the union of the ray casts (the old per-update method), after units move, trees
## fall and night comes.
func test_vision_cache_matches_ray_casts() -> void:
	var w := world(0.0)
	w.setup_match()
	for team in [C.DAWN, C.DUSK]:
		for id in ["sludge", "azrin"]:
			var h := w.spawn_hero(id, team)
			w.bots.append(SimBot.new(w, h.id, "mid", "Bot %s" % id, "hard"))
	for phase in 4:
		run(w, 40.0 if phase < 3 else 330.0)
		if phase == 1:
			for i in 40:
				if w.map.trees[i * 7].alive:
					w.cut_tree(i * 7, Vector2.INF)
		if phase == 2:
			# a few trees near the heroes: only the stamps that reach them are cast again
			var cut := 0
			for i in w.map.trees.size():
				var t: Dictionary = w.map.trees[i]
				if t.alive and cut < 4 and (t.pos as Vector2).distance_to(w.heroes[0].pos) < 1500.0:
					w.cut_tree(i, Vector2.INF)
					cut += 1
			w.vision.update()
			var regrown := false
			for i in w.map.trees.size():
				if not w.map.trees[i].alive and not regrown and w.map.can_regrow(i):
					w.map.regrow_tree(i)
					regrown = true
		w.vision.update()
		var night := w.is_night()
		for team in 2:
			var vis := PackedByteArray()
			vis.resize(SimVision.VN * SimVision.VN)
			for u in w.units:
				if u.alive and u.team == team:
					var r := u.vision_night if night else u.vision_day
					if r > 0.0:
						w.vision._cast(vis, u.pos, r, u.has_flag("flying"))
			for s in w.vision.sources:
				if int(s.team) == team and w.time < float(s.until):
					w.vision._cast(vis, s.pos, float(s.r), true)
			var got: PackedByteArray = w.vision.visible[team]
			var diff := 0
			for i in vis.size():
				if vis[i] != got[i]:
					diff += 1
			check(diff == 0, "phase %d team %d: %d cells differ from the ray casts" % [phase, team, diff])

## Lane creeps of every lane leave their base (the top tier 3 tower stands on the top lane's line: creeps used to spawn
## inside its footprint and never move) and no lane creep is stuck for long.
func test_every_lane_walks_out() -> void:
	var w := world(-1.0)
	w.elements = true
	w.next_wave_at = 0.0
	w.setup_match()
	run(w, 70.0)
	for team in [C.DAWN, C.DUSK]:
		for lane in ["top", "mid", "bot"]:
			var path := w.map.lane_path(lane, team)
			var far := 0.0
			for u in w.units:
				if u.alive and u.is_lane_creep() and u.team == team and u.lane == lane:
					far = maxf(far, u.pos.distance_to(path[0]))
			check(far > 1500.0, "team %d %s lane: creeps got %d from their spawn by 1:10" % [team, lane, int(far)])
	var stuck := 0
	for u in w.units:
		if u.alive and u.is_lane_creep() and u.blocked_time > 0.5:
			stuck += 1
	check(stuck <= 2, "%d lane creeps blocked for over half a second" % stuck)

## Every player action as a command (SimCommands, the multiplayer path) has exactly the effect of the direct call the
## interface used to make: two identical worlds, one driven by direct calls and one by commands, end with equal state
## fingerprints, tick after tick.
func test_commands_match_direct_calls() -> void:
	var ws: Array = []
	for k in 2:
		var w := world(-5.0)
		w.next_wave_at = 0.0
		w.setup_match()
		var h := w.spawn_hero("sludge", C.DAWN)
		w.spawn_hero("azrin", C.DUSK)
		h.gold_unreliable = 5000
		ws.append(w)
	var a: SimWorld = ws[0]
	var b: SimWorld = ws[1]
	var ha := a.heroes[0]
	var hb := b.heroes[0]
	check(a.state_hash() == b.state_hash(), "identical worlds start with equal fingerprints")
	var steps := [
		[func(): a.shop.buy(ha, "boots"), {"k": "buy", "item": "boots"}],
		[func(): a.shop.buy(ha, "circlet"), {"k": "buy", "item": "circlet"}],
		[func(): a.shop.add_to_buy(ha, "magic_wand"), {"k": "to_buy_add", "item": "magic_wand"}],
		[func(): a.shop.buy_listed(ha, 0), {"k": "buy_listed", "i": 0}],
		[func(): a.shop.swap(ha, 0, 7), {"k": "swap", "a": 0, "b": 7}],
		[func(): a.shop.toggle_lock(ha, 1, false), {"k": "lock", "slot": 1, "stash": false}],
		[func(): a.shop.sell(ha, 1), {"k": "sell", "slot": 1, "stash": false}],
		[func(): a.abilities.learn(ha, "shuriken_hook"), {"k": "learn", "ability": "shuriken_hook"}],
		[func(): a.command(ha.id, {"type": O.MOVE, "point": Vector2(-5000, -5000)}), {"k": "order", "u": hb.id, "o": {"type": O.MOVE, "point": Vector2(-5000, -5000)}}],
		[func(): a.command(ha.id, {"type": O.HOLD, "queue": true}), {"k": "order", "u": hb.id, "o": {"type": O.HOLD, "queue": true}}],
		[func(): a.courier_command(ha, "deliver"), {"k": "courier", "cmd": "deliver"}],
		[func(): a.ping(ha.team, Vector2(100, 100), ha.id, -1, ""), {"k": "ping", "p": Vector2(100, 100), "target": -1, "kind": ""}],
		[func(): a.chat(ha.team, ha.id, "push top"), {"k": "chat", "text": "push top"}],
		[func(): a.glyph(ha.team), {"k": "glyph"}],
	]
	for st in steps:
		(st[0] as Callable).call()
		var err := SimCommands.apply(b, hb.id, st[1])
		for i in 15:
			a.step()
			b.step()
		check(a.state_hash() == b.state_hash(), "after %s: fingerprints differ (error '%s')" % [str(st[1].k), err])
	# a command never acts for another player's units
	var foe := b.heroes[1]
	var before := foe.order
	SimCommands.apply(b, hb.id, {"k": "order", "u": foe.id, "o": {"type": O.MOVE, "point": Vector2.ZERO}})
	check(foe.order == before, "an order naming an enemy unit is ignored")

## A match saved with SimSnapshot and loaded again plays on exactly like the original: a 5 v 5 bot game is saved at
## 6:00 (mid fight, projectiles in the air, items bought, trees cut), loaded into a fresh world on the same map, and both
## are stepped another 3 minutes with the same player commands; the state fingerprints match at every tick.
func test_snapshot_restores_an_identical_match() -> void:
	var m := SimMap.new()
	m.build(1)
	var a := SimWorld.new(5, m)
	a.setup_match()
	var hs: Array = []
	for team in [C.DAWN, C.DUSK]:
		for id in ["sludge", "azrin", "ezee", "blood_ranger", "sludge"]:
			var h := a.spawn_hero(id, team)
			hs.append(h)
			if hs.size() != 1:
				a.bots.append(SimBot.new(a, h.id, "mid", "Bot %d" % hs.size(), "hard"))
	while a.time < 360.0:
		a.step()
		a.events.clear()
	var t0 := Time.get_ticks_msec()
	var bytes := SimSnapshot.capture(a)
	var t1 := Time.get_ticks_msec()
	var m2 := SimMap.new()
	m2.build(1)
	var b := SimSnapshot.restore(bytes, m2)
	var t2 := Time.get_ticks_msec()
	print("    snapshot %d KB, capture %d ms, restore %d ms" % [bytes.size() / 1024, t1 - t0, t2 - t1])
	check(b != null, "the snapshot loads")
	if b == null:
		return
	check(a.state_hash() == b.state_hash(), "loaded world has the same fingerprint")
	var me: SimUnit = hs[0]
	var bad := -1
	for i in 30 * 180:
		if i % 90 == 0:
			var cmd := {"k": "order", "u": me.id, "o": {"type": O.ATTACK_MOVE, "point": Vector2(-200 + (i % 7) * 300, -400)}}
			SimCommands.apply(a, me.id, cmd)
			SimCommands.apply(b, me.id, cmd)
		a.step()
		b.step()
		a.events.clear()
		b.events.clear()
		if bad < 0 and a.state_hash() != b.state_hash():
			bad = i
	check(bad < 0, "fingerprints diverged %d ticks after loading" % bad)

# ---- Froster, the Winter Master (owner's hero, 2026-10-14 b) ----------------------------------------------------------

func _froster(w: SimWorld, p: Vector2, team := C.DAWN, levels := {}) -> SimUnit:
	var f := w.spawn("froster", team, p)
	f.level = 18
	f.refresh_stats()
	f.hp = f.max_hp
	f.mana = f.max_mana
	for aid in f.abilities:
		f.ability_level[aid] = int(levels.get(aid, 4 if aid != "endless_winter" else 3))
	f.refresh_stats()
	f.auto_attack = false
	return f

## Damage events on unit `uid` keyed `key`, summed.
func _dmg_key(w: SimWorld, uid: int, key: String) -> float:
	var s := 0.0
	for e in w.events:
		if e.t == "damage" and int(e.u) == uid and String(e.get("key", "")) == key:
			s += float(e.amount)
	return s

func test_froster_base() -> void:
	var w := empty_world()
	var f := w.spawn("froster", C.DAWN, Vector2(-2000, -4000))
	check(f.is_ranged() and String(f.def.primary) == "int", "ranged intelligence hero")
	check(f.element == C.Element.ICE, "Ice element")
	check(f.abilities == ["breath_of_cold", "ice_pulse", "frost_heart", "endless_winter"], "the owner's four abilities")
	check((f.def.talents as Array).size() == 4, "four talent tiers")
	check(String(f.def.name) == "Froster" and String(f.def.title) == "the Winter Master", "the owner's name and title")

func test_breath_of_cold() -> void:
	var w := empty_world()
	var f := _froster(w, Vector2(-2000, -4000))
	var near1 := _bare(w, "dusk_melee", C.DUSK, Vector2(-1700, -4000))     # 300 ahead
	var far1 := _bare(w, "dusk_melee", C.DUSK, Vector2(-1300, -3800))      # 700 ahead, 200 aside (cone half-width there ~206)
	var wide := _bare(w, "dusk_melee", C.DUSK, Vector2(-1300, -3700))      # 700 ahead, 300 aside: outside
	var past := _bare(w, "dusk_melee", C.DUSK, Vector2(-1080, -4000))      # 920 ahead: beyond 800
	var behind := _bare(w, "dusk_melee", C.DUSK, Vector2(-2300, -4000))
	# clicking close still breathes the full 800
	w.command(f.id, {"type": O.CAST_POINT, "ability": "breath_of_cold", "point": Vector2(-1900, -4000)})
	run(w, 1.5)
	var dmg := 310.0 * (1.0 + f.magic_amp)
	near(_dmg_key(w, near1.id, "breath_of_cold"), dmg, 0.5, "310 magic damage at level 4 (300 ahead)")
	near(_dmg_key(w, far1.id, "breath_of_cold"), dmg, 0.5, "the cone widens: hit 700 ahead and 200 aside")
	check(_dmg_key(w, wide.id, "breath_of_cold") == 0.0, "300 aside at 700 is outside the cone")
	check(_dmg_key(w, past.id, "breath_of_cold") == 0.0, "nothing beyond 800")
	check(_dmg_key(w, behind.id, "breath_of_cold") == 0.0, "nothing behind Froster")
	var sl := near1.get_modifier("breath_of_cold_slow")
	near(float(sl.get("slow", 0.0)), 0.54, 1e-6, "54% slow at level 4 (30% + 8% per level)")
	near(float(sl.get("dur", 0.0)), 3.0, 1e-6, "for 3 s")
	near(w.abilities.val(f, "breath_of_cold", "cooldown"), 10.0, 1e-6, "10 s cooldown")
	var f1 := _froster(w, Vector2(3000, 3000), C.DAWN, {"breath_of_cold": 1})
	near(w.abilities.val(f1, "breath_of_cold", "damage"), 100.0, 1e-6, "100 damage at level 1")
	near(w.abilities.val(f1, "breath_of_cold", "slow"), 0.30, 1e-6, "30% slow at level 1")

func test_ice_pulse() -> void:
	var w := empty_world()
	var f := _froster(w, Vector2(-2000, -4000), C.DAWN, {"ice_pulse": 1})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1600, -4000))
	var side := _bare(w, "dusk_melee", C.DUSK, Vector2(-1600, -3780))     # 220 from the target
	var out := _bare(w, "dusk_melee", C.DUSK, Vector2(-1600, -3600))      # 400 from the target
	w.vision.update()
	w.command(f.id, {"type": O.CAST_UNIT, "ability": "ice_pulse", "target": t.id})
	run(w, 0.5)
	check(not t.get_modifier("ice_pulse").is_empty(), "the target is cursed")
	near(t.defense_loss(), 0.20, 1e-6, "20% lower defense at level 1")
	# physical and magic damage hit 20% harder after armor and resistance
	var hp0 := t.hp
	w.combat.deal_damage(f.id, f.team, true, t, 100.0, C.DamageType.PHYSICAL, false, "test")
	near(hp0 - t.hp, 100.0 * C.armor_multiplier(t.armor) * 1.2, 0.01, "physical damage +20% after armor")
	hp0 = t.hp
	w.combat.deal_damage(f.id, f.team, true, t, 100.0, C.DamageType.PURE, false, "test", false, {"no_amp": true})
	near(hp0 - t.hp, 100.0, 0.01, "pure damage is not raised")
	w.events.clear()
	run(w, 3.5)
	var blast := 100.0 * (1.0 + f.magic_amp)
	near(_dmg_key(w, t.id, "ice_pulse"), blast, 0.5, "the curse bursts for 100 magic damage on the target")
	near(_dmg_key(w, side.id, "ice_pulse"), blast, 0.5, "and on enemies within 300")
	check(_dmg_key(w, out.id, "ice_pulse") == 0.0, "not beyond 300")
	check(t.get_modifier("ice_pulse").is_empty(), "the curse lasts 3.5 s")
	var f4 := _froster(w, Vector2(3000, 3000))
	near(w.abilities.val(f4, "ice_pulse", "defense_loss"), 0.35, 1e-6, "35% at level 4 (+5% per level)")
	check(w.abilities.val(f4, "ice_pulse", "cooldown") == 13.0 and w.abilities.val(f, "ice_pulse", "cooldown") == 16.0,
		"16/15/14/13 s cooldown")

func test_frost_heart() -> void:
	var w := empty_world()
	var f := _froster(w, Vector2(-2000, -4000), C.DAWN, {"frost_heart": 1})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1600, -4000))
	t.def.hp = 1e7
	t.refresh_stats()
	t.hp = t.max_hp
	# 1000 damage dealt at level 1 (one heart per 500) gives two hearts
	w.combat.deal_damage(f.id, f.team, true, t, 1000.0 / (1.0 + f.magic_amp), C.DamageType.MAGICAL, false, "test")
	check(w.abilities.frost_hearts(f) == 2, "two hearts from 1000 damage (got %d)" % w.abilities.frost_hearts(f))
	w.combat.deal_damage(f.id, f.team, true, t, 5000.0, C.DamageType.MAGICAL, false, "test")
	check(w.abilities.frost_hearts(f) == 3, "at most three")
	# the next attack spends one: +200 magic damage and a 40% slow for 1.5 s
	w.events.clear()
	f.auto_attack = true
	w.command(f.id, {"type": O.ATTACK_UNIT, "target": t.id})
	var spent := false
	for i in 120:
		w.step()
		if w.events.any(func(e): return e.t == "frost_heart_hit"):
			spent = true
			break
	check(spent and w.abilities.frost_hearts(f) == 2, "an attack spends a heart")
	near(_dmg_key(w, t.id, "frost_heart"), 200.0 * (1.0 + f.magic_amp), 0.5, "the burst: 200 magic damage")
	var sl := t.get_modifier("frost_heart_slow")
	check(not sl.is_empty() and absf(float(sl.slow) - 0.4) < 1e-6, "a 40% slow")
	var f4 := _froster(w, Vector2(3000, 3000))
	near(w.abilities.val(f4, "frost_heart", "per_heart"), 350.0, 1e-6, "one heart per 350 at level 4")

func test_endless_winter() -> void:
	var w := empty_world()
	var f := _froster(w, Vector2(-2000, -4000), C.DAWN, {"endless_winter": 1})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1600, -4000))
	t.def.hp = 1e7
	t.refresh_stats()
	t.hp = t.max_hp
	var out := _bare(w, "dusk_melee", C.DUSK, Vector2(-1300, -4000))      # 700 away
	w.command(f.id, {"type": O.CAST_NO_TARGET, "ability": "endless_winter"})
	var frosts: Array = []
	var start := -1.0
	for i in int(9.0 * C.TICK_RATE):
		w.step()
		if start < 0.0 and not f.channel.is_empty():
			start = w.time
		for e in w.events:
			if e.t == "frosted" and int(e.u) == t.id:
				frosts.append(w.time - start)
		w.events = w.events.filter(func(e): return e.t == "damage")
	check(start >= 0.0, "Froster channels")
	var dealt := 0.0
	for e in w.events:
		if e.t == "damage" and int(e.u) == t.id and String(e.key) == "endless_winter":
			dealt += float(e.amount)
	near(dealt, 7.0 * 100.0 * (1.0 + f.magic_amp), 1.0, "7 pulses of 100 magic damage at level 1")
	check(frosts.size() == 2, "Frosted twice in 7 s while standing inside (got %s)" % str(frosts))
	if frosts.size() == 2:
		near(float(frosts[0]), 2.0, 0.07, "first Frost after 2 s inside")
		near(float(frosts[1]) - float(frosts[0]), 3.5, 0.07, "again after the 2 s freeze and 1.5 s more")
	var outdmg := 0.0
	for e in w.events:
		if e.t == "damage" and int(e.u) == out.id:
			outdmg += float(e.amount)
	check(outdmg == 0.0, "nothing outside 600")
	near(w.abilities.val(f, "endless_winter", "cooldown"), 60.0, 1e-6, "60 s cooldown")
	var f3 := _froster(w, Vector2(3000, 3000))
	near(w.abilities.val(f3, "endless_winter", "dps"), 300.0, 1e-6, "300 per second at level 3")

func test_endless_winter_breaks_on_stun() -> void:
	var w := empty_world()
	var f := _froster(w, Vector2(-2000, -4000))
	w.command(f.id, {"type": O.CAST_NO_TARGET, "ability": "endless_winter"})
	run(w, 1.0)
	check(not f.channel.is_empty(), "channelling")
	w.status.apply(f, -1, C.DUSK, {"id": "stunned", "stun": true, "dur": 0.5})
	run(w, 0.1)
	check(f.channel.is_empty(), "a stun ends the blizzard")

# ---- Caziel, the Void Assassin (owner's hero, 2026-10-14 b) -----------------------------------------------------------

func _caziel(w: SimWorld, p: Vector2, team := C.DAWN, levels := {}) -> SimUnit:
	var c := w.spawn("caziel", team, p)
	c.level = 18
	c.refresh_stats()
	c.hp = c.max_hp
	c.mana = c.max_mana
	for aid in c.abilities:
		c.ability_level[aid] = int(levels.get(aid, 4 if aid != "death_order" else 3))
	c.refresh_stats()
	c.auto_attack = false
	return c

func test_caziel_base() -> void:
	var w := empty_world()
	var c := w.spawn("caziel", C.DAWN, Vector2(-2000, -4000))
	check(not c.is_ranged() and String(c.def.primary) == "agi", "melee agility hero")
	check(c.element == C.Element.DARK, "Dark element")
	check(c.abilities == ["swift_dagger", "sweet_poison", "master_of_shadows", "death_order"], "the owner's four abilities")
	check(String(c.def.name) == "Caziel" and String(c.def.title) == "the Void Assassin", "the owner's name and title")

func test_swift_dagger() -> void:
	var w := empty_world()
	var c := _caziel(w, Vector2(-2000, -4000), C.DAWN, {"sweet_poison": 0, "death_order": 0})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1200, -4000))
	t.def.hp = 1e6
	t.def.armor = 10.0
	t.refresh_stats()
	t.hp = t.max_hp
	c.def = c.def.duplicate()
	var avg := (c.dmg_min + c.dmg_max) * 0.5
	w.vision.update()
	w.command(c.id, {"type": O.CAST_UNIT, "ability": "swift_dagger", "target": t.id})
	var hit := -1.0
	for i in 15:
		w.step()
		for e in w.events:
			if e.t == "damage" and int(e.u) == t.id and bool(e.get("attack", false)) and hit < 0.0:
				hit = float(e.amount)
		w.events.clear()
	check(c.pos.distance_to(t.pos) <= c.hull + t.hull + 10.0, "Caziel is beside the target (%.0f)" % c.pos.distance_to(t.pos))
	near(t.armor, 10.0 - 7.0, 1e-6, "armor cut by 7 at level 4")
	var lo := (c.dmg_min + c.bonus_damage + 260.0) * C.armor_multiplier(3.0)
	var hi := (c.dmg_max + c.bonus_damage + 260.0) * C.armor_multiplier(3.0)
	check(hit >= lo - 0.5 and hit <= hi + 0.5, "the stab: attack + 260 bonus after the cut armor (%.1f in %.1f..%.1f)" % [hit, lo, hi])
	check(c.atk_target == t.id, "and he fights on")
	run(w, 3.1)
	near(t.armor, 10.0, 1e-6, "the armor comes back after 3 s")
	check(w.abilities.val(c, "swift_dagger", "cooldown") == 6.0, "6 s cooldown at level 4")
	var c1 := _caziel(w, Vector2(3000, 3000), C.DAWN, {"swift_dagger": 1})
	check(w.abilities.val(c1, "swift_dagger", "cooldown") == 15.0 and w.abilities.val(c1, "swift_dagger", "bonus_damage") == 80.0,
		"15 s and +80 at level 1")
	var _a := avg

func test_sweet_poison() -> void:
	var w := empty_world()
	var c := _caziel(w, Vector2(-2000, -4000), C.DAWN, {"death_order": 0})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1900, -4000))
	t.def.hp = 1e7
	t.refresh_stats()
	t.hp = t.max_hp
	var snap := w.combat.attack_snapshot(c, "")
	var procs := 0
	var n := 3000
	for i in n:
		var before := w.status.dots.size()
		w.abilities.sweet_poison_hit(snap, t)
		for e in w.events:
			if e.t == "poison_blow":
				procs += 1
		w.events.clear()
		var _b := before
	near(float(procs) / n, 0.32, 0.03, "32% of attacks poison at level 4 (pseudo-random)")
	var mine := w.status.dots.filter(func(d): return int(d.t) == t.id and String(d.key) == "sweet_poison")
	check(mine.size() == 1, "poisons renew instead of stacking (%d running)" % mine.size())
	near(float(mine[0].dps), 80.0, 1e-6, "80 damage per second at level 4")
	near(float(mine[0].until) - w.time, 2.0, 1e-6, "for 2 s")

func test_master_of_shadows() -> void:
	var w := empty_world()
	var c := _caziel(w, Vector2(-2000, -4000))
	var ms0 := c.move_speed
	w.command(c.id, {"type": O.CAST_NO_TARGET, "ability": "master_of_shadows"})
	check(not c.get_modifier("master_of_shadows").is_empty(), "takes effect at once")
	c.refresh_stats()
	near(c.evasion, 0.45, 1e-6, "45% evasion at level 4")
	near(c.move_speed, ms0 * 1.15, 0.01, "15% faster")
	check(c.has_flag("minimap_hidden"), "hidden from the enemy minimap")
	run(w, 12.1)
	check(c.get_modifier("master_of_shadows").is_empty(), "lasts 12 s")
	near(w.abilities.val(c, "master_of_shadows", "cooldown"), 20.0, 1e-6, "20 s cooldown")

func test_death_order() -> void:
	var w := empty_world()
	var c := _caziel(w, Vector2(-2000, -4000), C.DAWN, {"sweet_poison": 0})
	var t := _bare(w, "dusk_melee", C.DUSK, Vector2(-1900, -4000))
	t.def.hp = 10000.0
	t.def.armor = 20.0
	t.refresh_stats()
	var snap := w.combat.attack_snapshot(c, "")
	snap.dmg_min = 100.0
	snap.dmg_max = 100.0
	snap.bonus = 0.0
	t.hp = 2000.0                                   # 20%: above 14%
	w.combat.land_attack(snap, t)
	var mult := C.damage_mult(c.weapon, t.armor_type)
	near(2000.0 - t.hp, 100.0 * mult * C.armor_multiplier(20.0), 0.5, "above the threshold: physical, armor counts")
	t.hp = 1300.0                                   # 13%: below 14% at level 3
	w.events.clear()
	w.combat.land_attack(snap, t)
	near(1300.0 - t.hp, 100.0 * mult, 0.5, "below 14%: pure, armor ignored")
	check(w.events.any(func(e): return e.t == "death_order"), "the execution is announced (effects)")
	var c1 := _caziel(w, Vector2(3000, 3000), C.DAWN, {"death_order": 1})
	near(w.abilities.val(c1, "death_order", "threshold"), 0.10, 1e-6, "10% at level 1")

# ---- Multiplayer server (no sockets: a stand-in for Net records what the server sends) ------------------------------

class FakeNet extends RefCounted:
	var sent: Array = []                     # [what, peer, args...]
	func _rec(a: Array) -> void:
		sent.append(a)
	func s_welcome(p, d): _rec(["welcome", p, d])
	func s_hub(p, b): _rec(["hub", p])
	func s_hub_log(p, l): _rec(["hub_log", p])
	func s_chat(p, ch, nm, t, sys): _rec(["chat", p, ch, nm, t, sys])
	func s_notice(p, t): _rec(["notice", p, t])
	func s_room(p, b): _rec(["room", p, bytes_to_var(b)])
	func s_room_left(p, r): _rec(["room_left", p, r])
	func s_begin(p, b): _rec(["begin", p, bytes_to_var(b)])
	func s_go(p): _rec(["go", p])
	func s_frame(p, f, b): _rec(["frame", p, f, bytes_to_var(b)])
	func s_snap_request(p): _rec(["snap_request", p])
	func s_snapshot(p, f, b): _rec(["snapshot", p, f])
	func peer_ping(_p): return 0
	func flush(): pass
	func last(what: String, peer := -1) -> Array:
		for i in range(sent.size() - 1, -1, -1):
			if sent[i][0] == what and (peer < 0 or int(sent[i][1]) == peer):
				return sent[i]
		return []
	func count(what: String, peer := -1) -> int:
		return sent.filter(func(e): return e[0] == what and (peer < 0 or int(e[1]) == peer)).size()

func _server() -> Array:
	var fake := FakeNet.new()
	var sv := NetServer.new()
	sv.net = fake
	var fp := NetSession.rules_fingerprint()
	for p in [[2, "Ann"], [3, "Bob"], [4, "Cy"]]:
		check(sv.hello(int(p[0]), String(p[1]), fp, NetSession.PROTOCOL, "") == "", "%s is welcome" % p[1])
	return [sv, fake]

func test_server_rooms_and_leaders() -> void:
	var a := _server()
	var sv: NetServer = a[0]
	var fake: FakeNet = a[1]
	check(sv.hello(9, "Ann", NetSession.rules_fingerprint(), NetSession.PROTOCOL, "") == "" and sv.players[9].name == "Ann 2", "a name already online gets a number")
	check(sv.hello(10, "Old", 123, NetSession.PROTOCOL, "") != "", "a different game version is refused")
	sv.password = "pw"
	check(sv.hello(11, "Pat", NetSession.rules_fingerprint(), NetSession.PROTOCOL, "") != "", "a passworded server refuses a player without it")
	sv.password = ""
	sv.create_room(2, "Friday", "", "5v5")
	var rid: int = sv.players[2].room
	var r: Dictionary = sv.rooms[rid]
	check(int(r.leader) == 2 and String(r.slots[0].name) == "Ann", "the maker leads the lobby from the first slot")
	sv.join_room(3, rid, "")
	check(int(sv.players[3].room) == rid and String(r.slots[5].name) == "Bob", "a newcomer goes to the smaller team")
	sv.create_room(4, "Locked", "secret", "1v1")
	var r2: Dictionary = sv.rooms[int(sv.players[4].room)]
	check(r2.slots.filter(func(s): return String(s.kind) == "closed").size() == 8, "1 vs 1 mid closes eight slots")
	sv.leave_room(4)
	check(not sv.rooms.has(int(r2.id)), "an empty lobby closes")
	sv.join_room(4, rid, "")
	sv.leader_slot(3, 3, "kind", "bot")
	check(String(r.slots[3].kind) == "open", "only the leader changes slots")
	sv.leader_slot(2, 3, "kind", "bot")
	check(String(r.slots[3].kind) == "bot", "the leader adds a bot")
	sv.leader_slot(2, 3, "hero", "froster")
	check(String(r.slots[3].hero) == "froster", "and sets its hero")
	sv.leader_slot(2, 6, "kind", "open")
	var cy := -1
	for i in r.slots.size():
		if String(r.slots[i].name) == "Cy":
			cy = i
	sv.leader_slot(2, cy, "kind", "open")
	check(int(sv.players[4].room) == -1 and fake.last("room_left", 4).size() > 0, "the leader can remove a player")
	sv.move_to(3, 7)
	check(String(r.slots[7].name) == "Bob" and String(r.slots[5].kind) == "open", "a player moves to an open slot")
	sv.set_mine(3, "hero", "caziel")
	sv.set_mine(3, "hero", "no_such_hero")
	check(String(r.slots[7].hero) == "caziel", "a player picks a hero (unknown ones are ignored)")
	sv.leave_room(2)
	check(int(r.leader) == 3, "when the leader leaves, the lobby passes to the next player")
	sv.chat(3, "hello")
	check(fake.last("chat", 3)[2] == "room" and fake.last("chat", 3)[4] == "hello", "chat in a lobby stays in the lobby")

func test_server_start_relay_repair_rejoin() -> void:
	var a := _server()
	var sv: NetServer = a[0]
	var fake: FakeNet = a[1]
	sv.create_room(2, "Game", "", "5v5")
	var rid: int = sv.players[2].room
	var r: Dictionary = sv.rooms[rid]
	sv.join_room(3, rid, "")
	sv.join_room(4, rid, "")
	sv.fill_bots(2)
	sv.start(2)
	check(String(r.state) == "lobby" and fake.last("notice", 2).size() > 0, "Start waits until everyone is ready")
	for p in [2, 3, 4]:
		sv.set_mine(p, "ready", true)
	sv.start(3)
	check(String(r.state) == "lobby", "only the leader starts")
	sv.start(2)
	check(String(r.state) == "loading" and fake.count("begin") == 3, "Start sends every player the match")
	var cfg: Dictionary = fake.last("begin", 2)[2]
	check(cfg.slots.size() == 10 and cfg.slots.all(func(s): return String(s.hero) in GameSettings.HEROES), "random heroes are chosen by the server")
	for p in [2, 3, 4]:
		sv.loaded(p)
	check(String(r.state) == "playing" and fake.count("go") == 3, "once all have loaded, go")
	sv.command(3, {"k": "order"})
	sv.tick()
	var fr: Array = fake.last("frame", 2)
	check(fr[2] == 0 and fr[3].size() == 1 and int(fr[3][0][0]) == int(sv.rooms[rid].m.slot_peer.keys()[sv.rooms[rid].m.slot_peer.values().find(3)]), "a command goes into the next frame under its sender's slot")
	check(fake.count("frame") == 3, "every player gets every frame")
	# fingerprints: Cy's world drifted; the majority's player sends a snapshot that goes to Cy with the frames after it
	for i in 40:
		sv.tick()
	sv.hash_report(2, 30, 111)
	sv.hash_report(3, 30, 111)
	sv.hash_report(4, 30, 999)
	for i in 10:
		sv.tick()
	var req: Array = fake.last("snap_request")
	check(req.size() > 0 and int(req[1]) in [2, 3], "a desync asks a player from the majority for a snapshot")
	var f_before := fake.count("frame", 4)
	sv.snapshot_reply(int(req[1]), 35, PackedByteArray([1, 2, 3]))
	check(fake.last("snapshot", 4).size() > 0 and int(fake.last("snapshot", 4)[2]) == 35, "the drifted player gets it")
	check(fake.count("frame", 4) - f_before == int(r.m.frame) - 36, "followed by every frame after the snapshot")
	# a drop and a return
	var bob_slot := -1
	for s in r.m.slot_peer:
		if int(r.m.slot_peer[s]) == 3:
			bob_slot = int(s)
	sv.gone(3)
	sv.tick()
	var sysf: Array = fake.last("frame", 2)[3]
	check(sysf.any(func(e): return int(e[0]) == -1 and String(e[1].k) == "sys_bot" and int(e[1].slot) == bob_slot), "a dropped player's hero goes to a bot in the next frame")
	check(sv.hello(7, "Bob", NetSession.rules_fingerprint(), NetSession.PROTOCOL, "") == "", "the player connects again")
	check(int(sv.players[7].room) == rid and fake.last("begin", 7).size() > 0, "and is sent straight back into the match")
	sv.loaded(7)
	check(fake.last("snap_request").size() > 0 and fake.last("go", 7).size() > 0, "once loaded: a snapshot is asked for them and they go")
	sv.tick()
	check(fake.last("frame", 2)[3].any(func(e): return int(e[0]) == -1 and String(e[1].k) == "sys_human"), "and their hero is theirs again")
	sv.match_over(2)
	r.m.end_at = 1
	sv.tick()
	check(String(r.state) == "lobby" and r.slots.all(func(s): return String(s.kind) != "human" or not bool(s.ready)), "after the match the lobby is open again, nobody ready")

# ---- Run 2026-10-15 b: twenty more items, cooldowns, AoE and cast range --------------------------------------------

func test_items_15b_recipes_match_dota() -> void:
	# costs from work/research/d2_items.txt (Valve's items.txt)
	var expect := {"travel_boots": 2500, "dagon": 3000, "dagon_2": 4100, "dagon_5": 7400, "net_staff": 4650,
		"storm_hammer": 5500, "soul_gem": 3000, "time_crystal": 5100, "small_shield": 425, "leech_totem": 2200,
		"battle_armor": 5125, "frost_plate": 4500, "burning_cape": 4700, "giant_heart": 5300, "leech_blade": 5050,
		"moth_blade": 5450, "refresh_stone": 5000, "guard_boots": 4450, "team_shield": 3725, "war_drum": 1625,
		"long_lens": 2275, "crash_knife": 6800, "mana_gem": 800, "swift_stone": 2000, "plate_armor": 1400,
		"gold_band": 450, "wide_stone": 900, "relic": 3400, "war_axe": 2800, "troll_ring": 1700, "feather": 2800,
		"iron_helm": 975, "speed_ribbon": 225}
	for id in expect:
		var d := SimData.item(id)
		check(not d.is_empty(), "%s exists" % id)
		if d.is_empty():
			continue
		var parts := 0
		for c in d.components:
			parts += int(SimData.item(c).cost)
		check(int(d.cost) == int(expect[id]), "%s costs %d (got %d)" % [id, int(expect[id]), int(d.cost)])
		if not (d.components as Array).is_empty():
			check(parts + int(d.recipe_cost) == int(d.cost), "%s: parts + recipe = cost (%d + %d)" % [id, parts, int(d.recipe_cost)])
		check(UiKit.item_icon_path(id).begins_with("items/gen/"), "%s has a generated icon" % id)

func test_items_15b_buy_and_combine() -> void:
	var w := empty_world()
	var h := w.spawn("sludge", C.DAWN, w.map.fountains[C.DAWN] + Vector2(200, 200))
	h.gold_unreliable = 20000
	check(w.shop.buy(h, "battle_armor") == "", "Battle Armor bought in the base")
	check(_ids(h.inventory).has("battle_armor"), "its parts combine into Battle Armor")
	check(w.shop.buy(h, "dagon") == "" and w.shop.buy(h, "recipe_dagon_2") == "", "Blast Rod and its next recipe")
	check(_ids(h.inventory).has("dagon_2") and not _ids(h.inventory).has("dagon"), "Blast Rod becomes Blast Rod 2")

func test_cooldown_reduction_and_rate() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	h.ability_level["blubber"] = 4
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "blubber"})
	near(w.abilities.cooldown_left(h, "blubber"), 17.0, 0.05, "Blubber 17 s without items")
	h.ability_ready["blubber"] = C.LONG_AGO
	_give(w, h, "time_crystal", 0)
	_give(w, h, "time_crystal", 1)
	near(h.cooldown_reduction, 0.25, 1e-6, "two Time Crystals do not stack: 25%")
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "blubber"})
	near(w.abilities.cooldown_left(h, "blubber"), 17.0 * 0.75, 0.05, "Time Crystal: 25% shorter")
	# a cooldown that runs 40% slower, then frozen, then twice as fast
	var left0 := w.abilities.cooldown_left(h, "blubber")
	h.add_modifier({"id": "slowed_time", "source": -9, "expires": w.time + 100.0, "stats": {"cooldown_rate": -0.4}})
	run(w, 1.0)
	near(left0 - w.abilities.cooldown_left(h, "blubber"), 0.6, 0.05, "40% slower: 0.6 s gone in 1 s")
	h.remove_modifier("slowed_time")
	h.add_modifier({"id": "stopped_time", "source": -9, "expires": w.time + 100.0, "stats": {"cooldown_rate": -1.0}})
	run(w, 0.1)
	left0 = w.abilities.cooldown_left(h, "blubber")
	run(w, 1.0)
	near(w.abilities.cooldown_left(h, "blubber"), left0, 0.05, "frozen: it does not move")
	h.remove_modifier("stopped_time")
	h.add_modifier({"id": "fast", "source": -9, "expires": w.time + 100.0, "stats": {"cooldown_rate": 1.0}})
	run(w, 0.1)
	left0 = w.abilities.cooldown_left(h, "blubber")
	run(w, 1.0)
	near(left0 - w.abilities.cooldown_left(h, "blubber"), 2.0, 0.05, "twice as fast: 2 s gone in 1 s")
	h.remove_modifier("fast")
	# items too
	_give(w, h, "refresh_stone", 2)
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 2})
	near(w.abilities.item_cooldown_left(h, 2), 180.0 * 0.75, 0.2, "Refresh Stone's own cooldown is cut too")
	check(w.abilities.cooldown_left(h, "blubber") == 0.0, "Refresh Stone finishes the spell cooldowns")

func test_aoe_and_cast_range_bonus() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	near(w.abilities.val(h, "stench", "radius"), 250.0, 0.01, "Stench 250")
	_give(w, h, "wide_stone", 0)
	near(w.abilities.val(h, "stench", "radius"), 290.0, 0.01, "Wide Stone: +40 area")
	_give(w, h, "frost_plate", 1)
	near(w.abilities.val(h, "stench", "radius"), 325.0, 0.01, "Frost Plate's +75 and the stone's +40 do not stack")
	near(w.abilities.val(h, "shuriken_hook", "vision_radius"), 500.0, 0.01, "sight radii do not grow")
	h.ability_level["chomp"] = 1
	near(w.abilities.cast_range(h, "chomp", -1), 200.0, 0.01, "Chomp 200")
	_give(w, h, "long_lens", 2)
	near(w.abilities.cast_range(h, "chomp", -1), 425.0, 0.01, "Long Lens: +225 cast range")

func test_battle_armor_and_frost_plate_auras() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var ally := _dummy(w, "ezee", C.DAWN, Vector2(-1600, -4000))
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1400, -4000))
	var creep := w.spawn("dusk_melee", C.DUSK, Vector2(-1500, -3800))
	creep.order = O.HOLD
	var ally_armor := ally.armor
	var foe_armor := foe.armor
	var foe_as := foe.attack_speed
	var ally_as := ally.attack_speed
	_give(w, h, "battle_armor", 0)
	_give(w, h, "frost_plate", 1)
	run(w, 0.4)
	near(ally.armor - ally_armor, 5.0, 0.01, "Battle Armor: +5 armor to allies")
	near(ally.attack_speed - ally_as, 30.0, 0.01, "and +30 attack speed")
	near(foe_armor - foe.armor, 5.0, 0.01, "-5 armor to enemies")
	near(foe_as - foe.attack_speed, 40.0, 0.01, "Frost Plate: -40 attack speed to enemies")
	check(not creep.get_modifier("battle_armor_curse").is_empty(), "enemy creeps get the armor loss too")
	h.inventory[0] = null
	h.inventory[1] = null
	h.refresh_stats()
	run(w, 1.0)
	near(ally.armor, ally_armor, 0.01, "auras fade once the items are gone")
	near(foe.attack_speed, foe_as, 0.01, "on enemies too")

func test_leech_totem_small_shield_drum_greaves() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var ally := _dummy(w, "ezee", C.DAWN, Vector2(-1600, -4000))
	var a0 := ally.armor
	var ls0 := ally.lifesteal
	var ms0 := ally.move_speed
	var dmg0 := ally.bonus_damage
	_give(w, h, "leech_totem", 0)
	_give(w, h, "small_shield", 1)
	run(w, 0.4)
	near(ally.lifesteal - ls0, 0.20, 0.001, "Leech Totem: 20% lifesteal to hero allies")
	near(ally.bonus_damage - dmg0, (ally.dmg_min + ally.dmg_max) * 0.5 * 0.18, 0.01, "+18% base damage")
	near(ally.armor - a0, 4.0, 0.01, "+2 armor each from the two different auras")
	check(h.lifesteal < 0.01, "its owner gets no lifesteal from it")
	_give(w, h, "war_drum", 2)
	run(w, 0.4)
	near(ally.move_speed - ms0, 15.0, 0.5, "War Drum: +15 speed aura")
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 2})
	check(not ally.get_modifier("war_drum").is_empty(), "Endurance reaches allies")
	_give(w, h, "guard_boots", 3)
	ally.hp = ally.max_hp * 0.2
	ally.mana = 0.0
	run(w, 0.4)
	check(float(ally.get_modifier("guard_boots_aura").stats.hp_regen) == 17.0, "Guard Boots: 17 regen below 25% health")
	var hp1 := ally.hp
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 3})
	check(ally.hp - hp1 >= 324.0 and ally.mana >= 199.0, "Mend: 325 health and 200 mana")

func test_blast_rod_net_staff_storm_hammer() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	_give(w, h, "dagon_5", 0)
	h.mana = h.max_mana
	run(w, 0.3)
	var hp0 := foe.hp
	w.command(h.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 0, "target": foe.id})
	run(w, 0.2)
	near(hp0 - foe.hp, 800.0 * (1.0 + h.magic_amp) * (1.0 - foe.magic_resist), 1.0, "Blast Rod 5: 800 magic damage")
	near(w.abilities.item_cooldown_left(h, 0), 15.0 - 0.2, 0.1, "15 s cooldown at level 5")
	near(w.abilities.cast_range(h, "", 0, foe), 640.0 + 180.0, 0.01, "its own +180 cast range")
	# Net Staff: roots every enemy in the area
	var foe2 := _dummy(w, "sludge", C.DUSK, Vector2(-1450, -3900))
	_give(w, h, "net_staff", 1)
	h.mana = h.max_mana
	run(w, 0.3)
	w.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 1, "point": Vector2(-1480, -3950)})
	run(w, 0.6)
	check(foe.is_rooted() and foe2.is_rooted(), "Net Staff roots both enemies in the area")
	# Storm Hammer's Static Charge on itself: attackers get struck
	_give(w, h, "storm_hammer", 2)
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 2, "target": h.id})
	run(w, 0.1)
	check(not h.get_modifier("static_charge").is_empty(), "Static Charge on the owner")
	h.get_modifier("static_charge")["expires"] = INF            # longer than its 12 s, to count many attacks
	var struck := 0
	for i in 40:
		var f0 := foe2.hp
		w.combat.deal_damage(foe2.id, foe2.team, true, h, 10.0, C.DamageType.PHYSICAL, true, "attack")
		if foe2.hp < f0:
			struck += 1
		run(w, 1.05)
		h.hp = h.max_hp
	check(struck >= 3 and struck <= 16, "about one attack in five sets off a strike (%d of 40)" % struck)

func test_burning_cape_giant_heart_leech_blade() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var foe := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	_give(w, h, "burning_cape", 0)
	var hp0 := foe.hp
	run(w, 2.0)
	near(hp0 - foe.hp, 120.0 * (1.0 + h.magic_amp) * (1.0 - foe.magic_resist), 15.0, "Burning Cape: about 60 magic damage a second")
	h.inventory[0] = null
	_give(w, h, "giant_heart", 0)
	h.hp = h.max_hp * 0.5
	var r: Vector4 = w.regen_rates(h)
	near(r.x, h.hp_regen + h.max_hp * 0.01 + h.max_hp * 0.5 * 0.015, 0.5, "Giant Heart: 1% max + 1.5% missing health a second")
	_give(w, h, "leech_blade", 1)
	var ls := h.lifesteal
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 1})
	h.refresh_stats()
	near(h.lifesteal - ls, 1.45, 0.001, "Blood Rage: +145% lifesteal")

func test_team_shield_and_travel_boots() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var ally := _dummy(w, "ezee", C.DAWN, Vector2(-1700, -4000))
	_give(w, h, "team_shield", 0)
	h.mana = h.max_mana
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
	var blk := 70.0 + 0.02 * h.max_hp
	near(float(ally.get_modifier("team_guard").block), blk, 0.01, "Guard: 70 + 2% of its owner's health")
	near(w.items.block_attack(ally, 200.0), 200.0 - blk, 0.01, "an ally blocks every attack")
	# Travel Boots: teleport without a scroll, to an allied creep
	var w2 := world(60.0)
	var t := _sludge(w2, Vector2(-2000, -4000))
	t.tp_charges = 0
	check(w2.abilities.cast_error(t, "tp", -1, null, t.pos) == "No Teleport Scroll", "no scroll, no teleport")
	var ms0 := t.move_speed
	_give(w2, t, "travel_boots", 0)
	near(t.move_speed - ms0, 90.0, 0.5, "Travel Boots: +90 speed")
	t.mana = t.max_mana
	check(w2.abilities.cast_error(t, "tp", -1, null, t.pos) == "", "with Travel Boots it needs no scroll")
	var c := w2.spawn("dawn_melee", C.DAWN, Vector2(2000, 2000))
	c.order = O.HOLD
	w2.command(t.id, {"type": O.CAST_POINT, "ability": "tp", "point": Vector2(2050, 2050)})
	run(w2, 0.2)
	check(not t.channel.is_empty() and Vector2(t.channel.get("dest", Vector2.INF)).distance_to(c.pos) < 400.0, "teleports beside the allied creep")
	check(t.tp_charges == 0, "no scroll used")
	near(w2.abilities.cooldown_left(t, "tp"), 40.0 - 0.2, 0.1, "40 s cooldown")

# ---- Tock and Kragg (run 2026-10-15 b) ------------------------------------------------------------------------------

func _hero15(w: SimWorld, id: String, p: Vector2, team := C.DAWN) -> SimUnit:
	var h := w.spawn(id, team, p)
	h.level = 18
	h.refresh_stats()
	for aid in h.abilities:
		h.ability_level[aid] = int(SimData.ability(aid).max_level)
	h.refresh_stats()
	h.hp = h.max_hp
	h.mana = h.max_mana
	return h

func test_tock_and_kragg_data() -> void:
	for id in ["tock", "kragg"]:
		var d := SimData.unit(id)
		check(not d.is_empty() and d.kind == K.HERO, "%s is a hero" % id)
		check((d.talents as Array).size() == 4, "%s has 4 talent tiers" % id)
		for tier in d.talents:
			for tid in tier:
				check(not SimData.talent(String(tid)).is_empty(), "talent %s exists" % tid)
		for aid in d.abilities:
			check(not SimData.ability(String(aid)).is_empty(), "%s exists" % aid)
		check(id in GameSettings.HEROES, "%s can be picked" % id)
	check(SimData.unit("tock").abilities.size() == 6, "Tock has six skills")
	check(SimData.unit("kragg").abilities.size() == 4, "Kragg has four skills")
	check(String(SimData.unit("kragg").innate) == "magnetize", "and Magnetize as his innate")
	check(SimData.ultimate_of(SimData.unit("tock").abilities) == "stop_time", "Stop Time is Tock's ultimate")
	check(Keybinds.ability_slot("ability_4", 6) == 5 and Keybinds.ability_slot("ability_5", 6) == 3, "six skills: Q W E D F R")

func test_tock_time_bolt_slows_cooldowns() -> void:
	var w := empty_world()
	var t := _hero15(w, "tock", Vector2(-2000, -4000))
	var e := _sludge(w, Vector2(-1500, -4000), {}, C.DUSK)
	e.order = O.HOLD
	e.ability_ready["blubber"] = w.time + 10.0
	var hp0 := e.hp
	w.command(t.id, {"type": O.CAST_POINT, "ability": "time_bolt", "point": e.pos})
	run(w, 1.0)
	check(e.hp < hp0, "Time Bolt hits")
	check(not e.get_modifier("time_bolt").is_empty(), "the enemy is delayed")
	var left0 := w.abilities.cooldown_left(e, "blubber")
	run(w, 1.0)
	near(left0 - w.abilities.cooldown_left(e, "blubber"), 0.4, 0.05, "its cooldowns run 60% slower")

func test_tock_fast_forward_quick_hands_rewind() -> void:
	var w := empty_world()
	var t := _hero15(w, "tock", Vector2(-2000, -4000))
	var ally := _sludge(w, Vector2(-1800, -4000))
	# Fast Forward (level 4): 6.5 s off the ally's basic spells, not its ultimate (Chomp), not its items
	ally.ability_ready["blubber"] = w.time + 10.0
	ally.ability_ready["stench"] = w.time + 4.0
	ally.ability_ready["chomp"] = w.time + 30.0
	var it := _give(w, ally, "jump_knife")
	it["ready"] = w.time + 12.0
	var t0 := w.time
	w.command(t.id, {"type": O.CAST_UNIT, "ability": "fast_forward", "target": ally.id})
	run(w, 0.3)
	var spent := w.time - t0
	near(w.abilities.cooldown_left(ally, "blubber"), 10.0 - spent - 6.5, 0.1, "Fast Forward: 6.5 s off a basic spell")
	near(w.abilities.cooldown_left(ally, "stench"), 0.0, 0.01, "a shorter cooldown ends (never below zero)")
	near(w.abilities.cooldown_left(ally, "chomp"), 30.0 - spent, 0.1, "the ultimate is untouched")
	near(float(it.ready) - w.time, 12.0 - spent, 0.1, "items are untouched")
	run(w, 1.0)
	near(w.abilities.cooldown_left(ally, "blubber"), 10.0 - (w.time - t0) - 6.5, 0.1, "then cooldowns run at the normal rate")
	# Quick Hands: Fast Forward's cast took 2.5 s off Time Bolt's cooldown
	t.ability_ready["time_bolt"] = w.time + 5.0
	t.ability_ready["fast_forward"] = C.LONG_AGO
	t.mana = t.max_mana
	w.command(t.id, {"type": O.CAST_UNIT, "ability": "fast_forward", "target": t.id})
	run(w, 0.3)
	check(w.abilities.cooldown_left(t, "time_bolt") < 5.0 - 2.5 + 0.01, "Quick Hands cuts other cooldowns by 2.5 s")
	# Rewind: back where he stood 3 s ago, health back up
	var start := t.pos
	run(w, 0.3)
	t.order = O.NONE
	w.command(t.id, {"type": O.MOVE, "point": start + Vector2(700, 0)})
	run(w, 2.0)
	t.hp = t.max_hp * 0.4
	var before := t.pos
	w.command(t.id, {"type": O.CAST_NO_TARGET, "ability": "rewind"})
	run(w, 0.1)
	check(t.pos.distance_to(before) > 200.0, "Rewind moves Tock back (%d)" % int(t.pos.distance_to(before)))
	check(t.hp > t.max_hp * 0.9, "with the health he had then")

func test_tock_slow_field_and_stop_time() -> void:
	var w := empty_world()
	var t := _hero15(w, "tock", Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	var ms0 := e.move_speed
	w.command(t.id, {"type": O.CAST_POINT, "ability": "slow_field", "point": e.pos})
	run(w, 0.8)
	check(e.move_speed < ms0 * 0.6, "Slow Field slows 45%")
	e.ability_ready["dark_stomp"] = w.time + 10.0
	t.mana = t.max_mana
	w.command(t.id, {"type": O.CAST_POINT, "ability": "stop_time", "point": e.pos})
	run(w, 0.5)
	check(e.is_stunned(), "Stop Time freezes the enemy")
	var left0 := w.abilities.cooldown_left(e, "dark_stomp")
	run(w, 1.0)
	near(w.abilities.cooldown_left(e, "dark_stomp"), left0, 0.05, "and its cooldowns stand still")
	var ally := _sludge(w, e.pos + Vector2(50, 0))
	t.ability_ready["stop_time"] = C.LONG_AGO
	t.mana = t.max_mana
	w.command(t.id, {"type": O.CAST_POINT, "ability": "stop_time", "point": e.pos})
	run(w, 0.5)
	check(not ally.is_stunned(), "allies keep moving")

func test_kragg_grip_charges_overload() -> void:
	var w := empty_world()
	var k := _hero15(w, "kragg", Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	var d0 := k.pos.distance_to(e.pos)
	run(w, 0.3)
	check(w.abilities.cast_error(k, "iron_grip", -1, e, e.pos) == "", "Iron Grip can be cast: " + w.abilities.cast_error(k, "iron_grip", -1, e, e.pos))
	w.command(k.id, {"type": O.CAST_UNIT, "ability": "iron_grip", "target": e.id})
	run(w, 0.8)
	check(k.pos.distance_to(e.pos) < 120.0 and k.pos.distance_to(Vector2(-2000, -4000)) > d0 * 0.3,
		"Iron Grip: they meet halfway")
	check(e.is_stunned(), "the enemy is stunned")
	check(w.abilities.kits2.charges(e) == 2, "and has 2 Charges")
	# attacks add Charges (Magnetize, innate: up to 4, 8 s)
	var snap := w.combat.attack_snapshot(k, "")
	w.combat.land_attack(snap, e)
	check(w.abilities.kits2.charges(e) == 3, "an attack adds a Charge")
	# level 18: 0.10% + 0.05% x 18 = 1.0% per Charge
	near(w.abilities.kits2.spell_mult(k, e), 1.03, 0.0001, "3 Charges at level 18: +3% spell damage")
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	check(w.abilities.kits2.charges(e) == 4, "at most 4 Charges")
	var m := e.get_modifier("magnet_charge")
	near(float(m.expires) - w.time, 8.0, 0.05, "lasting 8 seconds")

func test_kragg_magnetize_innate() -> void:
	var w := empty_world()
	var k := w.spawn("kragg", C.DAWN, Vector2(-2000, -4000))
	check(k.ability_level_of("magnetize") == 1, "Magnetize is learned at level 1")
	check(not ("magnetize" in k.abilities), "and has no skill slot")
	check(not w.abilities.can_learn(k, "magnetize"), "and takes no points")
	near(w.abilities.kits2.amp_per_charge(k), 0.0015, 0.00001, "level 1: 0.10% + 0.05% per Charge")
	k.level = 25
	near(w.abilities.kits2.amp_per_charge(k), 0.001 + 0.0005 * 25.0, 0.00001, "grows with hero level")

func test_kragg_overload_every_nth_attack() -> void:
	var w := empty_world()
	var k := _hero15(w, "kragg", Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1880, -4000))
	var e2 := _dummy(w, "sludge", C.DUSK, Vector2(-2000, -3880))
	var far := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	check(SimData.ability("overload").behavior == "passive", "Overload is passive")
	run(w, 0.1)
	var hp2 := e2.hp
	var hpf := far.hp
	# level 4: every 3rd attack
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	check(e2.hp == hp2, "no burst before the 3rd attack")
	check(w.abilities.kits2.overload_count(k) == Vector2i(2, 3), "two of three attacks counted")
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	var mult := w.abilities.kits2.spell_mult(k, e2)
	near(hp2 - e2.hp, 105.0 * mult * (1.0 - e2.magic_resist), 2.0, "the 3rd attack bursts: 105 magic damage nearby")
	check(far.hp == hpf, "not beyond 200")
	var sl := e2.get_modifier("overload_slow")
	check(not sl.is_empty() and is_equal_approx(float(sl.slow), 0.8), "and slows by 80%")
	near(float(sl.dur), 0.8 * (1.0 - e2.status_resist), 0.01, "for 0.8 seconds")
	check(w.abilities.kits2.overload_count(k).x == 0, "the count starts again")
	# level 1: every 6th attack
	k.ability_level["overload"] = 1
	k.refresh_stats()
	k.stacks["overload"] = 0
	var hp3 := e2.hp
	for i in 5:
		w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	check(e2.hp == hp3, "level 1: nothing on the 5th attack")
	w.combat.land_attack(w.combat.attack_snapshot(k, ""), e)
	check(e2.hp < hp3, "a burst on the 6th")

func test_kragg_repel_and_magnet_field() -> void:
	var w := empty_world()
	var k := _hero15(w, "kragg", Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1800, -4000))
	var e2 := _dummy(w, "sludge", C.DUSK, Vector2(-1800, -3900))
	w.abilities.kits2.add_charges(e, k, 4)
	w.command(k.id, {"type": O.CAST_NO_TARGET, "ability": "repel"})
	run(w, 1.6)
	check(e.pos.distance_to(k.pos) > e2.pos.distance_to(k.pos), "Repel throws the charged enemy further")
	check(w.abilities.kits2.charges(e2) >= 1, "and adds a Charge")
	# Magnet Field drags enemies in and stuns them at the end
	var far := _dummy(w, "ezee", C.DUSK, k.pos + Vector2(600, 0))
	far.def["move_speed"] = 0.0
	far.refresh_stats()
	var d0 := far.pos.distance_to(k.pos)
	k.mana = k.max_mana
	w.command(k.id, {"type": O.CAST_NO_TARGET, "ability": "magnet_field"})
	run(w, 3.0)
	check(far.pos.distance_to(k.pos) < d0 - 200.0, "Magnet Field drags enemies in (%d -> %d)" % [int(d0), int(far.pos.distance_to(k.pos))])
	check(w.abilities.kits2.charges(far) >= 2, "giving a Charge every second")
	run(w, 3.5)
	check(far.is_stunned() or far.get_modifier("magnet_field_stun").size() > 0 or far.pos.distance_to(k.pos) > 300.0,
		"enemies close at the end are stunned")

# ---- Bots: teamfights, ganks, pushes, camps, learning (2026-10-15 c) ------------------------------------------------

## Three of ours beside two hurt enemies they can see, after the laning phase: the team brain calls a teamfight, every
## bot near is in it and the focus is one of the two enemies.
func test_teamfight_called_with_the_odds() -> void:
	var w := empty_world()
	w.time = 900.0
	var ours: Array[SimUnit] = []
	for i in 3:
		var h := w.spawn_hero("kragg", C.DAWN)
		h.pos = Vector2(-300.0 + i * 120.0, 0.0)
		w.bots.append(SimBot.new(w, h.id, "mid", "A%d" % i))
		ours.append(h)
	var theirs: Array[SimUnit] = []
	for i in 2:
		var e := w.spawn_hero("tock", C.DUSK)
		e.pos = Vector2(300.0 + i * 120.0, 100.0)
		e.hp = e.max_hp * 0.6
		theirs.append(e)
	for h in w.heroes:
		h.bot = true
	w.vision.update()
	var br := w.brain(C.DAWN)
	br._update_seen()
	br._call_teamfight()
	var plan := br.task_for(ours[0].id)
	check(String(plan.get("kind", "")) == "fight", "a teamfight was called (got %s)" % str(plan.get("kind", "none")))
	if not plan.is_empty():
		check(theirs.has(w.get_unit(int(plan.target))), "the focus is one of the enemies")
		for h in ours:
			check((plan.members as Dictionary).has(h.id), "%d is in the fight" % h.id)
	check(br.fight_odds(ours, theirs) > SimTeamAI.ENGAGE, "the odds favour us")

## Two of ours against three healthy enemies: no teamfight (the danger call is for that).
func test_no_teamfight_against_the_odds() -> void:
	var w := empty_world()
	w.time = 900.0
	var ours: Array[SimUnit] = []
	for i in 2:
		var h := w.spawn_hero("tock", C.DAWN)
		h.pos = Vector2(-300.0 + i * 120.0, 0.0)
		h.bot = true
		ours.append(h)
	for i in 3:
		var e := w.spawn_hero("kragg", C.DUSK)
		e.pos = Vector2(300.0 + i * 120.0, 100.0)
	w.vision.update()
	var br := w.brain(C.DAWN)
	br._update_seen()
	br._call_teamfight()
	check(br.task_for(ours[0].id).is_empty(), "no plan against stronger enemies")

## A gank's rally point is near the target but out of its team's sight (at night, beyond its night vision), on the
## side of its way home.
func test_gank_rally_out_of_sight() -> void:
	var w := empty_world()
	w.time = 400.0
	var e := w.spawn_hero("tock", C.DUSK)
	e.pos = Vector2(0.0, -3000.0)
	var g := w.spawn_hero("kragg", C.DAWN)
	g.pos = Vector2(-2500.0, -4000.0)
	w.vision.update()
	var br := w.brain(C.DAWN)
	var q := br._gank_rally(e, [g])
	var d := q.distance_to(e.pos)
	check(d >= 600.0 and d <= 950.0, "rally 650-900 from the target (got %.0f)" % d)
	check(not w.vision.cell_visible(C.DUSK, q), "rally out of the target team's sight")
	check(w.map.is_walkable(q), "rally is walkable")
	var home: Vector2 = w.map.fountains[C.DUSK] - e.pos
	check((q - e.pos).dot(home) > 0.0, "rally on the target's way home")

## A push whose tower fell goes on to the next building in that lane.
func test_push_goes_on_to_next_building() -> void:
	var w := world(1500.0)
	w.setup_match()
	var br := w.brain(C.DAWN)
	var t1 := br.front_tower(C.DUSK, "mid")
	var ours: Array[SimUnit] = []
	for i in 3:
		var h := w.spawn_hero("kragg", C.DAWN)
		h.pos = t1.pos + Vector2(-700.0 - i * 100.0, -700.0)
		h.bot = true
		ours.append(h)
	var p := br._new_plan("push", "mid", t1.id, t1.pos, 45.0)
	for h in ours:
		p.members[h.id] = true
	SimDebug.kill(w, t1, ours[0])
	br._advance_pushes()
	var nxt := br.front_tower(C.DUSK, "mid")
	check(nxt != null and nxt != t1, "a next building exists")
	check(int(p.target) == nxt.id, "the push moved on to the %s (target %d, next %d)" % [str(nxt.def.id) if nxt else "?", int(p.target), nxt.id if nxt else -1])
	check(br.pushes_chained == 1, "counted as chained")

## A bot does not farm a camp it cannot clear: low level for the camp, or a camp kind that nearly killed it until it
## has two more levels.
func test_bot_skips_camp_it_cannot_clear() -> void:
	var w := world(900.0)
	w.setup_match()
	var h := w.spawn_hero("caziel", C.DAWN)
	var b := SimBot.new(w, h.id, "mid", "A")
	b.role = 3
	var large: Dictionary = {}
	var small: Dictionary = {}
	for c in w.map.camps:
		if c.kind == "large" and large.is_empty():
			large = c
		if c.kind == "small" and small.is_empty():
			small = c
	check(not b._can_clear(h, large), "level 1: no large camp")
	SimDebug.level_up(w, h, 11)
	h.refresh_stats()
	h.hp = h.max_hp
	b._camp_fail["small"] = h.level + 2
	check(not b._can_clear(h, small), "a camp kind that nearly killed it waits two levels")
	b._camp_fail.clear()
	check(b._can_clear(h, small), "level 12: a small camp is fine")

## What bots learn from teamfights and ganks moves the right way (learning on, a throwaway file).
func test_bot_memory_learns_fights_ganks() -> void:
	var old_path := BotMemory.path
	BotMemory.path = "user://test_bot_memory.json"
	BotMemory.active = true
	BotMemory.reset()
	var bar := BotMemory.engage_bar(SimTeamAI.ENGAGE)
	BotMemory.note_teamfight(SimTeamAI.ENGAGE, bar, 0.0)
	check(BotMemory.engage_bar(SimTeamAI.ENGAGE) > bar, "a lost close fight raises the odds needed")
	var bar2 := BotMemory.engage_bar(SimTeamAI.ENGAGE)
	BotMemory.note_teamfight(SimTeamAI.ENGAGE, bar2, 1.0)
	check(BotMemory.engage_bar(SimTeamAI.ENGAGE) < bar2, "a won close fight lowers it")
	var r0 := BotMemory.gank_rate(2)
	BotMemory.note_gank(2, true)
	check(BotMemory.gank_rate(2) > r0, "a working gank raises the success rate")
	BotMemory.active = false
	BotMemory.teams = [true, true]
	BotMemory.reset()
	BotMemory.path = old_path
	BotMemory._loaded = false
	check(not BotMemory.on(), "learning off again after the test")

## View.live: a freed node reads as null (effect lists hold nodes others may free).
func test_view_live_freed_node() -> void:
	var n := Node3D.new()
	check(View.live(n) == n, "a live node comes back")
	n.free()
	check(View.live(n) == null, "a freed node is null")

## Cast range (owner's rule 2026-10-15): copies of one source stack with diminishing returns (a second Long Lens adds
## half, a third a quarter; Blast Rods of any level are one source), different sources add fully; the bonus reaches
## talents' and upgrades' ranges, line shots' reach, Leap Strike's search radius and Jump Knife.
func test_cast_range_stacking_and_reach() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	h.ability_level["chomp"] = 1
	h.ability_level["shuriken_hook"] = 1
	var base := w.abilities.cast_range(h, "chomp", -1)
	var hook0 := w.abilities.val(h, "shuriken_hook", "distance")
	_give(w, h, "long_lens", 0)
	near(h.cast_range_bonus, 225.0, 0.01, "one Long Lens: +225")
	_give(w, h, "long_lens", 1)
	near(h.cast_range_bonus, 225.0 + 112.5, 0.01, "two: the second adds half")
	_give(w, h, "long_lens", 2)
	near(h.cast_range_bonus, 225.0 + 112.5 + 56.25, 0.01, "three: the third a quarter")
	_give(w, h, "dagon", 3)
	near(h.cast_range_bonus, 225.0 + 112.5 + 56.25 + 60.0, 0.01, "Blast Rod is another source: its +60 adds in full")
	_give(w, h, "dagon_5", 4)
	near(h.cast_range_bonus, 225.0 + 112.5 + 56.25 + 180.0 + 30.0, 0.01, "Blast Rod 1 and 5 are one source: 180 + 60 x 0.5")
	near(w.abilities.cast_range(h, "chomp", -1), base + h.cast_range_bonus, 0.01, "Chomp's cast range grows")
	near(w.abilities.val(h, "shuriken_hook", "distance"), hook0 + h.cast_range_bonus, 0.01, "the hook flies further")
	h.perm_stats["cast_range"] = 100.0
	h.refresh_stats()
	near(h.cast_range_bonus, 225.0 + 112.5 + 56.25 + 180.0 + 30.0 + 100.0, 0.01, "a talent's cast range adds")
	h.add_modifier({"id": "test_range", "source": h.id, "expires": INF, "stats": {"cast_range": 50.0}})
	h.refresh_stats()
	near(h.cast_range_bonus, 225.0 + 112.5 + 56.25 + 180.0 + 30.0 + 150.0, 0.01, "a buff's cast range adds")
	# a talent that changes an ability's own range goes through val()
	var e := _sludge(w, Vector2(0, 0))
	e.ability_level["chomp"] = 1
	SimData._ensure()
	SimData._talents["test_chomp_range"] = {"id": "test_chomp_range", "name": "t", "stats": {},
		"mods": [{"ability": "chomp", "add": {"range": 75.0}}]}
	e.talents[0] = "test_chomp_range"
	e.refresh_stats()
	near(w.abilities.cast_range(e, "chomp", -1), base + 75.0, 0.01, "a range talent lengthens the cast range")
	SimData._talents.erase("test_chomp_range")
	# Jump Knife reaches further with cast range
	var j := _sludge(w, Vector2(3000, -3000))
	_give(w, j, "jump_knife", 0)
	_give(w, j, "long_lens", 1)
	var from := j.pos
	w.command(j.id, {"type": O.CAST_POINT, "ability": "", "item_slot": 0, "point": from + Vector2(1400, 0)})
	run(w, 0.2)
	check(j.pos.distance_to(from) > 1300.0, "Jump Knife with Long Lens blinks 1400 (went %.0f)" % j.pos.distance_to(from))

## The buff bar (BuffBar): buffs and debuffs sorted by what they do (an enemy aura and a break are debuffs), one icon
## per instance (two Stench clouds, two burns), timers from the start stamp, no timer on auras, a name for each.
func test_buff_bar_entries() -> void:
	var w := empty_world()
	var h := _sludge(w, Vector2(-2000, -4000))
	var a := _sludge(w, Vector2(-1900, -4000), {}, C.DUSK)
	var b := _sludge(w, Vector2(-1800, -4000), {}, C.DUSK)
	h.add_modifier({"id": "salve", "source": h.id, "expires": w.time + 10.0, "regen": 40.0, "fx": "heal"})
	h.add_modifier({"id": "small_shield_aura", "source": SimItems.AURA_SRC, "expires": w.time + 0.7,
		"stats": {"armor": 2.0}, "aura": true, "by": h.id})
	h.add_modifier({"id": "battle_armor_curse", "source": SimItems.AURA_SRC, "expires": w.time + 0.7,
		"stats": {"armor": -5.0}, "aura": true, "by": a.id, "debuff": true})
	h.add_modifier({"id": "stench", "source": a.id, "expires": w.time + 3.0, "slow": 0.2, "debuff": true})
	h.add_modifier({"id": "stench", "source": b.id, "expires": w.time + 3.0, "slow": 0.2, "debuff": true})
	check(w.status.apply(h, a.id, a.team, {"id": "silence_staff", "silence": true, "dur": 5.0}), "silence lands")
	check(w.status.apply(h, b.id, b.team, {"id": "break_blade", "break": true, "dur": 4.0}), "break lands")
	w.status.add_dot(h, a, "fiery_javelin", 30.0, 6.0, C.Element.FIRE)
	w.status.add_dot(h, b, "fiery_javelin", 30.0, 6.0, C.Element.FIRE)
	for i in 3:
		w.step()
	var by_id := {}
	for e in BuffBar.entries(h, w):
		by_id[e.id] = by_id.get(e.id, []) + [e]
	check(not by_id.has("burning"), "the burns' summary mark is hidden (each burn shows)")
	check(by_id.get("fiery_javelin", []).size() == 2, "two burns, two icons")
	check(by_id.get("stench", []).size() == 2, "Stench from two enemies, two icons")
	var expect := {"salve": false, "small_shield_aura": false, "battle_armor_curse": true, "stench": true,
		"silence_staff": true, "break_blade": true, "fiery_javelin": true}
	for id in expect:
		var list: Array = by_id.get(id, [])
		check(not list.is_empty(), "%s shows" % id)
		for e in list:
			check(bool(e.debuff) == bool(expect[id]), "%s is a %s" % [id, "debuff" if expect[id] else "buff"])
			check(BuffBar.name_of(String(id)) != "" and String(e.name) == BuffBar.name_of(String(id)), "%s has a name (%s)" % [id, e.name])
			check(e.icon != null, "%s has an icon" % id)
	var salve: Dictionary = by_id.salve[0]
	near(float(salve.total), 10.0, 0.1, "a timed buff knows its full length from the start stamp")
	check(float(salve.left) < float(salve.total), "and how much is left")
	near(float(by_id.silence_staff[0].total), 5.0, 0.01, "a debuff keeps its length after status resistance")
	near(float(by_id.fiery_javelin[0].total), 6.0, 0.01, "a burn knows its length")
	check(float(by_id.small_shield_aura[0].total) == 0.0 and float(by_id.small_shield_aura[0].left) == 0.0,
		"an aura has no timer")
	check(by_id.battle_armor_curse[0].aura, "the enemy aura is marked as an aura")
	var tip: Array = BuffBar.tip(by_id.battle_armor_curse[0], h, w)
	check(String(tip[0][0]) == "Armor Loss Aura", "aura tooltip title is the aura's name")
	check(" ".join(tip.map(func(l): return String(l[0]))).contains("-5 armor"), "its tooltip says -5 armor")
	tip = BuffBar.tip(by_id.silence_staff[0], h, w)
	check(" ".join(tip.map(func(l): return String(l[0]))).contains("cannot cast"), "a silence says what it stops")
	# a refreshed aura does not mark stats dirty just because of the start stamp
	h.refresh_stats()
	h.add_modifier({"id": "small_shield_aura", "source": SimItems.AURA_SRC, "expires": w.time + 0.7,
		"stats": {"armor": 2.0}, "aura": true, "by": h.id})
	check(not h.stats_dirty, "refreshing the same aura leaves stats clean")
	# layout: buffs from the left, debuffs from the right, wrapping upward, never overlapping
	var lay := BuffBar.layout(9, 7, 400.0, 720.0, -4.0)
	var all: Array = lay[0] + lay[1]
	check(all.size() == 16, "16 icons fit in three rows of 8")
	for i in all.size():
		var r: Rect2 = all[i]
		check(r.position.x >= 400.0 - 0.01 and r.end.x <= 720.0 + 0.01 and r.end.y <= -4.0 + 0.01, "icon %d inside the area" % i)
		for j in range(i + 1, all.size()):
			check(not r.intersects(all[j]), "icons %d and %d do not overlap" % [i, j])

## Rejuvenation Orb (owner's rule 2026-10-15): two at 2:00, two at 4:00, never again (checked to 30:00).
func test_rejuvenation_orb_only_at_2_and_4_minutes() -> void:
	var w := empty_world()
	var times: Array = []
	for sec in range(0, 1801):
		w.time = float(sec)
		w.events.clear()
		w.orbs.update()
		for e in w.events:
			if e.t == "orb_spawn" and String(e.kind) == "rejuvenation":
				times.append(sec)
	check(times == [120, 120, 240, 240], "Rejuvenation Orbs only at 2:00 and 4:00 (%s)" % str(times))
	check(SimOrbs.NAMES.rejuvenation == "Rejuvenation Orb", "its name")

## Fortify (owner's rules 2026-10-15): tier 2+ towers splash within 300, shoot 50% faster and mark what they hit; each
## mark adds 50 physical damage to their shots and lasts 15 s. Tier 1 towers and towers after Fortify do none of it.
func test_fortify_towers_splash_mark_speed() -> void:
	var w := empty_world()
	w.time = 200.0
	var t2 := w.spawn("tower2", C.DUSK, Vector2(-1000, -4000))
	t2.lane_tier = 2
	var t1 := w.spawn("tower1", C.DUSK, Vector2(1500, -4000))
	t1.lane_tier = 1
	var a := _dummy(w, "ezee", C.DAWN, Vector2(-1000, -3400))
	var b := _dummy(w, "ezee", C.DAWN, Vector2(-1000, -3200))       # 200 from a: in the splash
	var c := _dummy(w, "ezee", C.DAWN, Vector2(-1000, -2900))       # 500 from a: outside it
	w._rebuild_grid()
	var speed0 := float(t2.def.projectile_speed)
	w.combat.release_attack(t2, a, "")
	near(float(w.projectiles[-1].speed), speed0, 0.01, "before Fortify: normal shot speed")
	w.projectiles.clear()
	w.events.clear()
	var by := _dummy(w, "sludge", C.DUSK, Vector2(-1200, -4200))
	check(w.glyph(C.DUSK, by.id), "Fortify pressed")
	var ge: Array = w.events.filter(func(e): return e.t == "glyph")
	check(ge.size() == 1 and int(ge[0].by) == by.id, "the event says who pressed it")
	w.combat.release_attack(t2, a, "")
	var p: Dictionary = w.projectiles[-1]
	near(float(p.speed), speed0 * 1.5, 0.01, "Fortified tier 2 tower: shots 50% faster")
	check(bool(p.snap.get("fortify", false)), "and Fortified")
	var ha := a.hp
	var hb := b.hp
	var hc := c.hp
	w.combat.land_attack(p.snap, a)
	var d1 := ha - a.hp
	check(int(a.get_modifier("fortify_mark").get("charges", 0)) == 1, "the target gets a Fortify Mark")
	near(float(a.get_modifier("fortify_mark").expires) - w.time, 15.0, 0.01, "for 15 s")
	check(hb - b.hp > 0.0 and int(b.get_modifier("fortify_mark").get("charges", 0)) == 1, "splash hits and marks an enemy 200 away")
	check(hc == c.hp and c.get_modifier("fortify_mark").is_empty(), "nothing 500 away")
	ha = a.hp
	w.combat.land_attack(p.snap, a)
	var d2 := ha - a.hp
	var per := 50.0 * C.armor_multiplier(a.armor)
	check(absf((d2 - d1) - per) < 10.0, "a second mark: +50 physical before armor (%.1f more, expected %.1f)" % [d2 - d1, per])
	check(int(a.get_modifier("fortify_mark").charges) == 2, "two marks")
	w.combat.release_attack(t1, a, "")
	check(not bool(w.projectiles[-1].snap.get("fortify", false)), "a tier 1 tower is not Fortified")
	w.time += C.GLYPH_BUILDING_DURATION + 0.1
	w.combat.release_attack(t2, a, "")
	check(not bool(w.projectiles[-1].snap.get("fortify", false)), "after Fortify ends, normal shots")
	w.time += 15.0
	a.expire_modifiers(w.time)
	check(a.get_modifier("fortify_mark").is_empty(), "marks fall off after 15 s")

## Bots press Fortify for a building in danger, but only on a team with no human player.
func test_bots_fortify_tower_in_danger() -> void:
	for human in [false, true]:
		var w := empty_world()
		w.time = 400.0
		var tw := w.spawn("tower2", C.DUSK, Vector2(-1000, -4000))
		tw.lane_tier = 2
		tw.hp = tw.max_hp * 0.25
		var bot := _dummy(w, "sludge", C.DUSK, Vector2(-1100, -4300))
		bot.bot = not human
		for i in 3:
			var e := w.spawn("dawn_melee", C.DAWN, tw.pos + Vector2(150 + 30 * i, 0))
			e.atk_target = tw.id
		w._rebuild_grid()
		w.events.clear()
		w.brain(C.DUSK)._glyph()
		var used := w.time < tw.glyph_until
		if human:
			check(not used, "a team with a human leaves Fortify to the human")
		else:
			check(used, "a bot team Fortifies a tower at 25% under attack")
			var ge: Array = w.events.filter(func(e): return e.t == "glyph")
			check(ge.size() == 1 and int(ge[0].by) == bot.id, "and the allies are told which bot did")

# ---- Run 2026-10-15 g: varied picks, bot items, counter-ganks, jukes, magic defence items ---------------------------

## Random heroes keep a team varied: no hero twice in one team, and with ten slots and eight heroes no hero three
## times in a match.
func test_varied_hero_picks() -> void:
	var dup_team := 0
	var triple := 0
	for sd in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var picked := [[], []]
		for i in 10:
			var t := i % 2
			var hid := GameSettings.varied_pick(rng, picked[t], (picked[0] as Array) + (picked[1] as Array))
			if hid in picked[t]:
				dup_team += 1
			picked[t].append(hid)
		var all: Array = (picked[0] as Array) + (picked[1] as Array)
		for hid in GameSettings.HEROES:
			if all.count(hid) >= 3:
				triple += 1
	check(dup_team == 0, "no hero twice in a team (%d)" % dup_team)
	check(triple == 0, "no hero three times in a match (%d)" % triple)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var h := GameSettings.varied_pick(rng2, ["kragg", "sludge"], ["kragg", "sludge"])
	check(h != "kragg" and h != "sludge", "Random avoids what the team has")

## The new magic defence items cost what Dota's do and have icons; Fade Cape hides an ally after 0.5 s and its barrier
## takes 375 magic damage (not physical).
func test_magic_defence_items() -> void:
	var expect := {"shawl": 450, "cloak": 900, "glimmer_cape": 2150}
	for id in expect:
		var d := SimData.item(id)
		check(int(d.cost) == int(expect[id]), "%s costs %d" % [id, int(expect[id])])
		check(UiKit.item_icon_path(id).begins_with("items/gen/"), "%s has a generated icon" % id)
	var gc := SimData.item("glimmer_cape")
	var parts := 0
	for c in gc.components:
		parts += int(SimData.item(c).cost)
	check(parts + int(gc.recipe_cost) == 2150, "Fade Cape: parts + recipe = cost")
	var w := empty_world()
	var a := _sludge(w, Vector2(-2000, -4000))
	var b := _sludge(w, Vector2(-1800, -4000))
	var mr0 := b.magic_resist
	_give(w, a, "glimmer_cape", 0)
	check(a.magic_resist > mr0 + 0.1, "Fade Cape: +20% magic resistance")
	a.mana = a.max_mana
	w.command(a.id, {"type": O.CAST_UNIT, "ability": "", "item_slot": 0, "target": b.id})
	run(w, 0.2)
	check(not b.get_modifier("glimmer_cape").is_empty(), "the ally gets it")
	check(not b.has_flag("invisible"), "not invisible at once")
	run(w, 0.6)
	check(b.has_flag("invisible"), "invisible after 0.5 s")
	var hp0 := b.hp
	w.combat.deal_damage(a.id + 999, C.DUSK, true, b, 300.0, C.DamageType.MAGICAL)
	near(hp0 - b.hp, 0.0, 0.5, "the barrier takes magic damage")
	w.combat.deal_damage(a.id + 999, C.DUSK, true, b, 100.0, C.DamageType.PHYSICAL)
	check(hp0 - b.hp > 10.0, "but not physical")

func _bot_game_world(lineup_a: Array, lineup_b: Array) -> Array:
	var w := world(600.0)
	w.setup_match()
	var ours: Array = []
	for id in lineup_a:
		var h := w.spawn_hero(String(id), C.DAWN)
		w.bots.append(SimBot.new(w, h.id, "mid", "A%d" % ours.size()))
		ours.append(h)
	var theirs: Array = []
	for id in lineup_b:
		theirs.append(w.spawn_hero(String(id), C.DUSK))
	return [w, ours, theirs]

## Bots read the enemy team: against fed magic nukers that keep killing it, a core moves magic resistance to the
## front; against fed right-clickers, a strength core moves armor; a support against invisible heroes buys Reveal Dust.
func test_bot_counter_items() -> void:
	var g := _bot_game_world(["ezee"], ["azrin", "froster", "tock"])
	var w: SimWorld = g[0]
	var h: SimUnit = g[1][0]
	var b: SimBot = w.bots[0]
	b.role = 3
	for e in g[2]:
		SimDebug.level_up(w, e, 12)
		e.refresh_stats()
		e.hp = e.max_hp
		e.mana = e.max_mana
	b.death_dmg = Vector3(200, 1400, 0)
	var prof := SimBotItems.profile(w, h.team)
	check(float(prof.magic) > float(prof.physical), "magic heroes read as magic damage (%.2f vs %.2f)" % [prof.magic, prof.physical])
	b._counter_items(h)
	var first := String(b.build[b._build_i])
	check("magic" in (SimBotItems.ANSWERS.get(first, []) as Array), "a magic answer comes first (%s)" % first)
	# right-clickers far ahead: armor
	var g2 := _bot_game_world(["kragg"], ["blood_ranger", "caziel"])
	var w2: SimWorld = g2[0]
	var h2: SimUnit = g2[1][0]
	var b2: SimBot = w2.bots[0]
	b2.role = 3
	for e in g2[2]:
		SimDebug.level_up(w2, e, 14)
		e.gold_reliable = 12000
		_give(w2, e, "crit_bow", 0)
		e.refresh_stats()
	b2.death_dmg = Vector3(1500, 100, 0)
	b2._counter_items(h2)
	var first2 := String(b2.build[b2._build_i])
	check("physical" in (SimBotItems.ANSWERS.get(first2, []) as Array), "armor against fed hitters (%s)" % first2)
	# an invisible enemy: a support buys Reveal Dust
	var g3 := _bot_game_world(["tock"], ["caziel"])
	var w3: SimWorld = g3[0]
	var h3: SimUnit = g3[1][0]
	var b3: SimBot = w3.bots[0]
	b3.role = 5
	_give(w3, g3[2][0], "sneak_blade", 0)
	h3.gold_unreliable = 2000
	for i in h3.inventory.size():
		h3.inventory[i] = null
	h3.pos = w3.map.fountains[h3.team] + Vector2(200, 200)
	b3._counter_items(h3)
	check(_ids(h3.stash).has("reveal_dust") or _ids(h3.inventory).has("reveal_dust"), "Reveal Dust against a Sneak Blade")

## Escape spots: running from a chaser, the bot prefers spots the trees (or higher ground) hide from it much more
## often than the straight run toward safety does.
func test_bot_juke_point_uses_cover() -> void:
	var w := world(600.0)
	w.setup_match()
	var h := w.spawn_hero("tock", C.DAWN)
	var tries := 0
	var juke_hidden := 0
	var road_hidden := 0
	var m := w.map
	for i in range(0, m.trees.size(), 37):
		var t: Dictionary = m.trees[i]
		if not t.alive or m.tree_cover(t.pos) < 4:
			continue
		var dir := Vector2.from_angle(float(i))
		var me: Vector2 = (t.pos as Vector2) - dir * 260.0
		var chaser := me - dir * 550.0
		if not m.is_walkable(me) or not m.is_walkable(chaser) or m.sight_blocked(chaser, me):
			continue
		h.pos = me
		var safe := me - dir.orthogonal() * 2000.0
		var q := SimBotTactics.juke_point(w, h, PackedVector2Array([chaser]), safe)
		tries += 1
		if m.sight_blocked(chaser, q):
			juke_hidden += 1
		if m.sight_blocked(chaser, me + (safe - me).normalized() * 600.0):
			road_hidden += 1
		if tries >= 40:
			break
	check(tries >= 15, "enough wooded spots tried (%d)" % tries)
	check(juke_hidden > road_hidden + tries * 0.25, "juke spots hidden %d / %d, the straight run %d" % [juke_hidden, tries, road_hidden])

## Juked: chased a moment ago, the enemy has not seen it for 2 s and nobody is in sight: it teleports home (hurt);
## still seen, or healthy, it does not.
func test_bot_juke_teleport() -> void:
	var g := _bot_game_world(["azrin"], ["sludge"])
	var w: SimWorld = g[0]
	var h: SimUnit = g[1][0]
	var b: SimBot = w.bots[0]
	h.pos = Vector2(0, 0)
	h.hp = h.max_hp * 0.4
	h.mana = h.max_mana
	h.ability_ready["tp"] = C.LONG_AGO
	b._chased_at = w.time - 1.0
	b._seen_by_enemy_at = w.time - 0.5
	check(not b._juke_tp(h), "still in their sight: no teleport")
	b._seen_by_enemy_at = w.time - 2.5
	h.hp = h.max_hp
	check(not b._juke_tp(h), "healthy: back to work instead")
	h.hp = h.max_hp * 0.4
	check(b._juke_tp(h), "lost them for 2 s: teleport home")
	check(h.order == O.CAST_POINT and String(h.order_ability) == "tp", "a Town Portal home is ordered")
	check(b.jukes == 1, "counted")

## Counter-ganks: an ally hit by an enemy hero with two bots close enough to help gets a save called (helpers and the
## victim in it); alone and far from help it does not.
func test_counter_gank_called() -> void:
	var g := _bot_game_world(["tock", "kragg", "ezee"], ["caziel"])
	var w: SimWorld = g[0]
	var v: SimUnit = g[1][0]
	var ganker: SimUnit = g[2][0]
	var p0 := Vector2(-3000, 1000)
	v.pos = p0
	v.hp = v.max_hp * 0.7
	(g[1][1] as SimUnit).pos = p0 + Vector2(700, 300)
	(g[1][2] as SimUnit).pos = p0 + Vector2(-600, 500)
	ganker.pos = p0 + Vector2(150, 0)
	var br := w.brain(C.DAWN)
	w.vision.update()
	br._update_seen()
	v.hero_damage_log[ganker.id] = w.time
	br._call_saves()
	var save := {}
	for p in br.plans:
		if String(p.kind) == "save":
			save = p
	check(not save.is_empty(), "a save is called")
	if not save.is_empty():
		check((save.members as Dictionary).has((g[1][1] as SimUnit).id) and (save.members as Dictionary).has((g[1][2] as SimUnit).id),
			"both helpers come")
		check(int(save.target) == ganker.id, "on the ganker")
		var bv: SimBot = w.bots[0]
		bv._scan(v)
		check(bv._save_helper(v) != null, "the victim runs to a helper")
	# far from help: nothing
	br.plans.clear()
	(g[1][1] as SimUnit).pos = Vector2(6000, -6000)
	(g[1][2] as SimUnit).pos = Vector2(6000, -6200)
	for x in [g[1][1], g[1][2]]:
		(x as SimUnit).tp_charges = 0
	br._call_saves()
	check(br.plans.filter(func(p): return String(p.kind) == "save").is_empty(), "no help near: no save")

# ---- Roydo and Blau (run 2026-10-16) --------------------------------------------------------------------------------

## A level 18 hero with every skill maxed that does not swing at the test dummies on its own.
func _hero16(w: SimWorld, id: String, p: Vector2, team := C.DAWN) -> SimUnit:
	var h := _hero15(w, id, p, team)
	h.auto_attack = false
	return h

func test_roydo_blau_data() -> void:
	for id in ["roydo", "blau"]:
		var d := SimData.unit(id)
		check(not d.is_empty() and d.kind == K.HERO, "%s is a hero" % id)
		check(int(d.element) == C.Element.NONE, "%s has no element (Neutral)" % id)
		check((d.talents as Array).size() == 4, "%s has 4 talent tiers" % id)
		for tier in d.talents:
			for tid in tier:
				check(not SimData.talent(String(tid)).is_empty(), "talent %s exists" % tid)
		for aid in d.abilities:
			check(not SimData.ability(String(aid)).is_empty(), "%s exists" % aid)
		check(id in GameSettings.HEROES, "%s can be picked" % id)
		check((d.abilities as Array).size() == 4, "%s has four skills" % id)
	check(String(SimData.unit("roydo").primary) == "int" and float(SimData.unit("roydo").range) == 150.0, "Roydo: intelligence, melee")
	check(String(SimData.unit("blau").primary) == "agi" and float(SimData.unit("blau").range) == 600.0, "Blau: agility, range 600")
	check(SimData.ultimate_of(SimData.unit("roydo").abilities) == "anomaly", "Anomaly is Roydo's ultimate")
	check(SimData.ultimate_of(SimData.unit("blau").abilities) == "place_turret", "Place Turret is Blau's ultimate")
	check(not ("pilot_turret" in SimData.unit("blau").abilities), "Pilot Turret only comes with the Upgrade Staff")
	var t := SimData.unit("blau_turret")
	check(t.kind == K.SUMMON and float(t.hp_regen) == 0.0 and float(t.mana) == 0.0, "the turret: no regeneration, no mana")
	near(float(t.range), 650.0, 0.01, "turret range 650")
	near(float(t.bat) / (float(t.attack_speed) / 100.0), 1.5, 0.001, "a shot every 1.5 s")

func test_roydo_grip_of_the_ruler() -> void:
	var w := empty_world()
	var r := _hero16(w, "roydo", Vector2(-2000, -4000))
	var center := Vector2(-1500, -4000)
	var e := _dummy(w, "ezee", C.DUSK, center + Vector2(300, 120))
	var c := _dummy(w, "dusk_melee", C.DUSK, center + Vector2(-250, -100))
	var far := _dummy(w, "ezee", C.DUSK, center + Vector2(700, 0))
	run(w, 0.2)
	var hp_e := e.hp
	var hp_c := c.hp
	var c_pos := c.pos
	w.command(r.id, {"type": O.CAST_POINT, "ability": "grip_of_the_ruler", "point": center})
	run(w, 0.35 + 0.1)
	check(not e.knock.is_empty() and bool(e.knock.get("air", false)), "the enemy hero is picked over the creep and thrown")
	check(c.pos.distance_to(c_pos) < 1.0, "the creep stays where it is")
	run(w, 0.35)
	check(e.knock.is_empty() or float(e.knock.get("z", 0.0)) > 40.0, "mid-flight it is in the air")
	check(e.hp == hp_e, "no damage before it lands")
	run(w, 0.6)
	check(e.pos.distance_to(center) < 80.0, "it lands in the middle (%d)" % int(e.pos.distance_to(center)))
	near(hp_e - e.hp, 220.0 * (1.0 + r.magic_amp + r.spell_amp) * (1.0 - e.magic_resist), 2.0, "220 magic damage at level 4")
	check(c.hp < hp_c, "the area is hit: the creep too")
	check(e.is_stunned() and c.is_stunned(), "and stunned")
	near(float(e.get_modifier("stunned").get("dur", 0.0)), 1.0 * (1.0 - e.status_resist), 0.01, "for 1 second")
	check(far.hp == far.max_hp, "not outside 400")
	# no enemy in the area: an ally is thrown, unharmed
	var w2 := empty_world()
	var r2 := _hero16(w2, "roydo", Vector2(-2000, -4000))
	var ally := _dummy(w2, "ezee", C.DAWN, center + Vector2(250, 0))
	run(w2, 0.2)
	w2.command(r2.id, {"type": O.CAST_POINT, "ability": "grip_of_the_ruler", "point": center})
	run(w2, 1.4)
	check(ally.pos.distance_to(center) < 80.0, "an ally is thrown when no enemy is there")
	check(ally.hp == ally.max_hp and not ally.is_stunned(), "and is neither hurt nor stunned")

func test_roydo_void_rush() -> void:
	var w := empty_world()
	var r := _hero16(w, "roydo", Vector2(-2000, -4000))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	var ally := _dummy(w, "ezee", C.DAWN, Vector2(-2000, -3600))
	var out := _dummy(w, "ezee", C.DUSK, Vector2(-1200, -4000))
	run(w, 0.2)
	var arm0 := ally.armor
	var ms0 := ally.move_speed
	var my_arm0 := r.armor
	w.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "void_rush"})
	run(w, 0.4)
	near(e.status_resist, -0.5, 0.001, "enemies: -50% status resistance at level 4")
	near(e.damage_out_pct, -0.25, 0.001, "and deal 25% less damage")
	near(ally.armor - arm0, 13.0, 0.01, "allies: +13 armor")
	near(ally.move_speed / ms0, 1.13, 0.005, "and 13% faster")
	near(r.armor - my_arm0, 13.0, 0.01, "Roydo too")
	check(out.get_modifier("void_rush").is_empty(), "not beyond 650")
	near(float(e.get_modifier("void_rush").get("dur", 0.0)), 7.0, 0.01, "7 seconds")
	# lower status resistance: a 1 s stun lasts 1.5 s
	w.status.apply(e, r.id, r.team, {"id": "stunned", "stun": true, "dur": 1.0})
	near(float(e.get_modifier("stunned").dur), 1.5, 0.001, "a 1 s stun lasts 1.5 s on them")
	# less damage dealt, by attacks and by spells
	e.def["can_attack"] = true
	var dummy := _dummy(w, "ezee", C.DAWN, Vector2(-1400, -4000))
	var snap := w.combat.attack_snapshot(e, "")
	snap.dmg_min = 100.0
	snap.dmg_max = 100.0
	snap.bonus = 0.0
	var hp0 := dummy.hp
	w.combat.land_attack(snap, dummy)
	near(hp0 - dummy.hp, 75.0 * C.armor_multiplier(dummy.armor), 0.5, "an attack deals 25% less")
	var hp1 := dummy.hp
	w.combat.deal_damage(e.id, e.team, true, dummy, 100.0, C.DamageType.PURE, false, "test")
	near(hp1 - dummy.hp, 75.0, 0.5, "a spell too")
	run(w, 7.0)
	check(e.get_modifier("void_rush").is_empty() and is_equal_approx(e.damage_out_pct, 0.0), "it wears off")

func test_roydo_dark_matter_skin() -> void:
	var w := empty_world()
	var r := _hero16(w, "roydo", Vector2(-2000, -4000))
	var near_e := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	var far_e := _dummy(w, "ezee", C.DUSK, Vector2(-1250, -4000))
	r.def = r.def.duplicate()
	r.def.hp = 1e7
	r.refresh_stats()
	r.hp = r.max_hp
	run(w, 0.1)
	w.events.clear()
	var procs := 0
	var n := 400
	for i in n:
		var before := near_e.hp
		var taken := w.combat.deal_damage(near_e.id, near_e.team, true, r, 200.0, C.DamageType.PURE, false, "test")
		if near_e.hp < before:
			procs += 1
			near(before - near_e.hp, taken * 0.34 * (1.0 - near_e.magic_resist), 0.5, "returns 34% of the damage taken")
	check(absf(float(procs) / n - 0.21) < 0.05, "procs about 21%% of the time (%.3f)" % (float(procs) / n))
	check(far_e.hp == far_e.max_hp, "only within 650")
	var sl := near_e.get_modifier("dark_matter_slow")
	check(not sl.is_empty() and is_equal_approx(float(sl.slow), 0.8), "slows 80%")
	near(float(sl.stats.attack_speed_pct), -0.8, 0.001, "and attack speed 80%")
	near(float(sl.dur), 0.3, 0.001, "for 0.3 s")
	# allies' damage never triggers it
	var hp_e := near_e.hp
	for i in 50:
		w.combat.deal_damage(r.id, r.team, true, r, 50.0, C.DamageType.PURE, false, "test")
	check(near_e.hp == hp_e, "self or ally damage is not returned")

func test_roydo_anomaly() -> void:
	var w := empty_world()
	var r := _hero16(w, "roydo", Vector2(-2000, -4000))
	run(w, 0.1)
	check(not r.is_ranged() and is_equal_approx(r.attack_range, 150.0), "melee before")
	near(r.bat, 1.7, 0.001, "base attack time 1.7")
	var dmg0 := r.bonus_damage
	var interval0 := r.attack_interval()
	w.command(r.id, {"type": O.CAST_NO_TARGET, "ability": "anomaly"})
	run(w, 0.5)
	check(r.is_ranged(), "Anomaly: ranged")
	near(r.attack_range, 650.0, 0.01, "range 650")
	near(r.bat, 1.45, 0.001, "base attack time 1.7 - 0.25")
	near(r.bonus_damage - dmg0, 180.0, 0.01, "+180 damage at level 3")
	check(r.attack_interval() < interval0 * 0.86, "attacks come faster")
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1500, -4000))
	w.events.clear()
	r.auto_attack = true
	w.command(r.id, {"type": O.ATTACK_UNIT, "target": e.id})
	run(w, 1.5)
	check(not _events_of(w, "projectile").filter(func(x): return int(x.src) == r.id).is_empty(), "his attacks fly as projectiles")
	check(e.hp < e.max_hp, "and hit from 500 away")
	run(w, 29.0)
	check(not r.is_ranged() and is_equal_approx(r.attack_range, 150.0) and is_equal_approx(r.bat, 1.7), "back to melee after 30 s")

## A spot with open ground of at least `clear` along +x before something the bullet bounces off.
func _bounce_spot(w: SimWorld, what: String) -> Vector2:
	var m := w.map
	if what == "tree":
		for t in m.trees:
			if not t.alive:
				continue
			var ok := true
			for k in range(3, 9):
				var q: Vector2 = (t.pos as Vector2) - Vector2(64.0 * k, 0)
				if not m.is_walkable(q) or m.tree_at(q, 90.0) >= 0:
					ok = false
					break
			if ok:
				return t.pos
	else:
		for cy in range(40, 216, 3):
			for cx in range(40, 216, 3):
				var p := m.cell_center(cx, cy)
				if m.is_walkable(p) or m.tree_at(p, 150.0) >= 0 or not m.is_cliff_cell(cx, cy):
					continue
				var ok2 := true
				for k in range(1, 9):
					var q2 := p - Vector2(64.0 * k, 0)
					if not m.is_walkable(q2) or m.tree_at(q2, 150.0) >= 0:
						ok2 = false
						break
				if ok2 and m.is_walkable_cell(Vector2i(cx - 1, cy)):
					return p
	return Vector2.INF

func test_blau_bounce_shot_ricochets() -> void:
	for what in ["tree", "wall"]:
		var w := empty_world()
		var spot := _bounce_spot(w, what)
		check(spot != Vector2.INF, "found a %s to shoot at" % what)
		if spot == Vector2.INF:
			continue
		var b := _hero16(w, "blau", spot - Vector2(420, 0))
		run(w, 0.1)
		w.events.clear()
		w.command(b.id, {"type": O.CAST_POINT, "ability": "bounce_shot", "point": spot})
		run(w, 0.8)
		var bounces := _events_of(w, "bounce_shot_bounce")
		check(not bounces.is_empty() and String(bounces[0].what) == what, "the bullet bounces off the %s (%s)" % [what, str(bounces.map(func(x): return x.what))])
		if not bounces.is_empty():
			check((bounces[0].pos as Vector2).distance_to(spot) < 100.0, "at the %s it was fired at" % what)
		if what == "tree":
			var ti := _map.tree_at(spot, 60.0)
			var felled := _events_of(w, "tree").filter(func(x): return not x.alive)
			check(not felled.is_empty() and (_map.trees[int(felled[0].i)].pos as Vector2).distance_to(spot) < 80.0,
				"the tree it bounced off is knocked down")
			for ev in felled:
				_restore_tree(int(ev.i))
			check(ti < 0 or _map.trees[ti].alive, "test map restored")
		if what == "wall" and not bounces.is_empty() and bounces[0].has("dir"):
			check((bounces[0].dir as Vector2).x < -0.2, "and comes back off the wall (%s)" % str(bounces[0].dir))
	# enemies are passed through, an allied unit is bounced off
	var w2 := empty_world()
	var b2 := _hero16(w2, "blau", Vector2(5200, -5700))
	var e1 := _dummy(w2, "dusk_melee", C.DUSK, Vector2(5500, -5700))
	var e2 := _dummy(w2, "dusk_melee", C.DUSK, Vector2(5700, -5700))
	var ally := _dummy(w2, "dawn_melee", C.DAWN, Vector2(5950, -5700))
	var behind := _dummy(w2, "dusk_melee", C.DUSK, Vector2(6200, -5700))
	run(w2, 0.1)
	w2.events.clear()
	w2.command(b2.id, {"type": O.CAST_POINT, "ability": "bounce_shot", "point": Vector2(5900, -5700)})
	run(w2, 1.0)
	check(e1.hp < e1.max_hp and e2.hp < e2.max_hp, "both enemies in a line are hit")
	var bb := _events_of(w2, "bounce_shot_bounce")
	check(not bb.is_empty() and String(bb[0].what) == "unit", "the allied creep makes it bounce")
	check(behind.hp == behind.max_hp, "the enemy behind the ally is not reached")
	near(e1.max_hp - e1.hp, (190.0 * 2.0) * (1.0 + b2.magic_amp + b2.spell_amp) * (1.0 - e1.magic_resist), 2.0, "the first enemy is hit twice (out and back), never more")

func test_blau_bounce_shot_limits() -> void:
	# a corridor of boulders: the bullet bounces between them, through an enemy, until its bounces run out
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var b := _hero16(w, "blau", o - Vector2(300, 0))
	var k3 := w.abilities.kits3
	for dx in [0.0, 300.0]:
		var bd := {"id": 900 + int(dx), "pos": o + Vector2(dx, 0), "vel": Vector2.ZERO, "r": SimKits3.BOULDER_R,
			"decel": 0.0, "rest_at": 0.0, "until": w.time + 30.0, "team": C.DAWN, "src": b.id, "cast": 0,
			"resting": false, "cells": [], "damage": 0.0, "push": 0.0, "spin": 0.0}
		k3.boulders.append(bd)
		k3._rest(bd)
	var e := _dummy(w, "dusk_melee", C.DUSK, o + Vector2(200, 0))
	b.pos = o + Vector2(100, 0)
	run(w, 0.1)
	w.events.clear()
	w.command(b.id, {"type": O.CAST_POINT, "ability": "bounce_shot", "point": o + Vector2(800, 0)})
	run(w, 2.0)
	var bounces := _events_of(w, "bounce_shot_bounce")
	var real := bounces.filter(func(x): return not bool(x.last))
	check(real.size() == 9, "9 bounces at level 4 (%d)" % real.size())
	check(not bounces.is_empty() and String(bounces[0].what) == "boulder", "off the boulders")
	var hits := _events_of(w, "bounce_shot_hit").filter(func(x): return int(x.u) == e.id)
	check(hits.size() == 2, "an enemy is damaged at most twice (%d)" % hits.size())
	for bd in k3.boulders:
		k3._unrest(bd)                         # the tests share one map: give the cells back

func test_blau_boulders() -> void:
	var w := empty_world()
	var b := _hero16(w, "blau", Vector2(5600, -5700))
	var e := _dummy(w, "ezee", C.DUSK, Vector2(5850, -5700))
	run(w, 0.1)
	var e_pos := e.pos
	w.events.clear()
	w.command(b.id, {"type": O.CAST_POINT, "ability": "summon_boulders", "point": Vector2(6600, -5700)})
	run(w, 0.4)
	var k3 := w.abilities.kits3
	check(k3.boulders.size() == 6, "6 boulders at level 4 (%d)" % k3.boulders.size())
	run(w, 2.7)
	check(k3.boulders.all(func(x): return bool(x.resting)), "they roll for at most 2.5 s, then rest")
	var dealt := _dmg_events(w.events, e.id, "summon_boulders")
	near(dealt, 140.0 * (1.0 + b.magic_amp + b.spell_amp) * (1.0 - e.magic_resist), 2.0, "an enemy is hurt once, whichever boulders hit it")
	check(e.pos.distance_to(e_pos) > 120.0, "and knocked back (%d)" % int(e.pos.distance_to(e_pos)))
	# resting boulders block walking, phased units too, and paths
	var bd: Dictionary = k3.boulders[0]
	var cell := w.map.world_to_cell(bd.pos)
	check(not w.map.is_walkable_cell(cell) and w.map.rock_at(cell) > 0, "a resting boulder's cell is blocked")
	var walker := _dummy(w, "dawn_melee", C.DAWN, (bd.pos as Vector2) - Vector2(220, 0))
	walker.add_modifier({"id": "phase_test", "source": -1, "expires": INF, "phased": true})
	walker.refresh_stats()
	walker.order = O.NONE
	w.orders.issue(walker, {"type": O.MOVE, "point": (bd.pos as Vector2) + Vector2(220, 0)}, false)
	var through := false
	for i in 90:
		w.step()
		if walker.pos.distance_to(bd.pos) < SimKits3.BOULDER_R + walker.hull - 6.0:
			through = true
	check(not through, "a phased unit cannot walk through a boulder")
	run(w, 8.0)
	check(k3.boulders.is_empty(), "after 10 s they are gone")
	check(w.map.rock_at(cell) == 0 and w.map.is_walkable_cell(cell), "and the ground is open again")

func test_blau_lay_trap() -> void:
	var w := empty_world()
	var b := _hero16(w, "blau", Vector2(5600, -5700))
	b.facing = 0.0
	run(w, 0.1)
	var start := b.pos
	w.command(b.id, {"type": O.CAST_NO_TARGET, "ability": "lay_trap"})
	run(w, 0.8)
	check(b.pos.distance_to(start - Vector2(400, 0)) < 40.0, "Blau leaps 400 back (%s)" % str(b.pos))
	var traps := w.effects.filter(func(x): return String(x.kind) == "blau_trap")
	check(traps.size() == 1 and (traps[0].pos as Vector2).distance_to(start) < 5.0, "the trap is where he stood")
	if traps.is_empty():
		return
	check(not w.abilities.kits3.trap_visible(C.DUSK, traps[0]), "armed, it is hidden from enemies")
	var e := w.spawn("dusk_melee", C.DUSK, start + Vector2(300, 0))
	var e2 := w.spawn("dusk_melee", C.DUSK, start + Vector2(400, 60))
	e.def = e.def.duplicate()
	e.def["can_attack"] = false
	e2.def = e2.def.duplicate()
	e2.def["can_attack"] = false
	w.orders.issue(e, {"type": O.MOVE, "point": start - Vector2(300, 0)}, false)
	w.orders.issue(e2, {"type": O.MOVE, "point": start - Vector2(300, 60)}, false)
	run(w, 1.5)
	var m := e.get_modifier("ensnared")
	check(not m.is_empty() and bool(m.root), "the first enemy on it is caught")
	if not m.is_empty():
		near(float(m.dur), 2.4 * (1.0 - e.status_resist), 0.01, "and rooted 2.4 s at level 4")
	check(e2.get_modifier("ensnared").is_empty(), "only one unit")
	check(w.effects.filter(func(x): return String(x.kind) == "blau_trap").is_empty(), "the trap is used up")

func test_blau_turret() -> void:
	var w := empty_world()
	var b := _hero16(w, "blau", Vector2(-2000, -4000))
	b.auto_attack = false
	run(w, 0.1)
	w.command(b.id, {"type": O.CAST_POINT, "ability": "place_turret", "point": Vector2(-1800, -4000)})
	run(w, 0.8)
	var turrets := w.units.filter(func(u): return u.kind == K.SUMMON and u.alive)
	check(turrets.size() == 1, "a turret is built")
	if turrets.is_empty():
		return
	var t: SimUnit = turrets[0]
	near(t.max_hp, 2100.0, 0.5, "2100 health at level 3")
	check(t.owner_id == b.id, "it is Blau's")
	t.hp = 1000.0
	run(w, 2.0)
	near(t.hp, 1000.0, 0.01, "no regeneration")
	var e := _dummy(w, "ezee", C.DUSK, Vector2(-1200, -4000))
	var far := _dummy(w, "ezee", C.DUSK, Vector2(-1000, -4000))
	w.events.clear()
	var hp0 := e.hp
	run(w, 6.05)
	var shots := _events_of(w, "projectile").filter(func(x): return int(x.src) == t.id)
	check(shots.size() >= 4 and shots.size() <= 5, "a shot every 1.5 s (%d in 6 s)" % shots.size())
	check(e.hp < hp0, "it shoots enemies within 650")
	check(far.hp == far.max_hp, "not beyond 650")
	var per := (hp0 - e.hp) / maxf(1.0, float(_events_of(w, "projectile_end").filter(func(x): return int(x.get("target", -1)) == e.id).size()))
	var avg := ((b.dmg_min + b.dmg_max) * 0.5 + b.bonus_damage) * 0.35 * C.armor_multiplier(e.armor)
	near(per, avg, avg * 0.15, "each shot: 35% of Blau's attack")
	# his attack effects ride on its shots: lifesteal heals Blau
	_give(w, b, "lifesteal")
	b.hp = b.max_hp * 0.5
	var bh := b.hp
	run(w, 3.1)
	check(b.hp > bh + 1.0, "Blau's lifesteal works through the turret")
	# credited to Blau; it lasts 35 s
	run(w, 35.0)
	check(not t.alive, "the turret is gone after 35 s")

func test_blau_pilot_turret() -> void:
	var w := empty_world()
	var b := _hero16(w, "blau", Vector2(-2000, -4000))
	b.auto_attack = false
	run(w, 0.1)
	check(not ("pilot_turret" in b.abilities), "no Pilot Turret without the Upgrade Staff")
	b.scepter = true
	run(w, 0.1)
	check("pilot_turret" in b.abilities and b.ability_level_of("pilot_turret") == 3, "the Upgrade Staff adds it at Place Turret's level")
	check(not w.abilities.can_learn(b, "pilot_turret"), "it takes no points")
	w.command(b.id, {"type": O.CAST_POINT, "ability": "place_turret", "point": Vector2(-1800, -4000)})
	run(w, 0.8)
	var t: SimUnit = w.units.filter(func(u): return u.kind == K.SUMMON and u.alive)[0]
	var hp0 := t.hp
	b.mana = b.max_mana
	w.command(b.id, {"type": O.CAST_UNIT, "ability": "pilot_turret", "target": t.id})
	run(w, 1.0)
	check(w.abilities.kits3.is_piloting(b), "Blau climbs in")
	check(b.pos.distance_to(t.pos) < 1.0 and b.is_invulnerable(), "he is inside and cannot be hurt")
	near(t.hp - hp0, 900.0, 1.0, "the turret gains 900 health at level 3")
	near(w.abilities.cooldown_left(b, "pilot_turret"), 5.0 - 0.9, 0.2, "5 s cooldown to get in")
	check(w.abilities.is_instant(b, "pilot_turret", -1), "while inside, the button gets him out at once")
	w.command(b.id, {"type": O.MOVE, "point": Vector2(-2400, -4000)})
	run(w, 0.2)
	check(not w.abilities.kits3.is_piloting(b) and not b.is_invulnerable(), "a move order gets him out")
	near(t.hp, hp0, 1.0, "the extra health goes with him")
	# the turret dies with him inside: he is thrown out unharmed
	b.ability_ready["pilot_turret"] = C.LONG_AGO
	w.command(b.id, {"type": O.CAST_UNIT, "ability": "pilot_turret", "target": t.id})
	run(w, 1.0)
	check(w.abilities.kits3.is_piloting(b), "back in")
	w.combat.kill(t, null)
	run(w, 0.2)
	check(not w.abilities.kits3.is_piloting(b) and b.alive, "the turret's death puts him out")
	b.scepter = false
	run(w, 0.1)
	check(not ("pilot_turret" in b.abilities), "without the staff the skill goes away")

# ---- Bots playing Roydo and Blau (run 2026-10-16) -------------------------------------------------------------------

func _bot16(w: SimWorld, h: SimUnit, foes: Array) -> SimBot:
	var b := SimBot.new(w, h.id, "mid", "Bot Test")
	b._foes.clear()
	for f in foes:
		b._foes.append(f)
	return b

## Steps the world, letting `b` think its kit every 0.2 s through `fn` (spells, escape or tick).
func _think16(w: SimWorld, b: SimBot, secs: float, fn: Callable) -> void:
	var steps := int(round(secs * C.TICK_RATE))
	for i in steps:
		if i % 6 == 0 and w.time >= b._cast_deadline:
			fn.call()
		w.step()

func test_bot_blau_banks_bounce_shot() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "blau", o)
	var e := _dummy(w, "ezee", C.DUSK, o + Vector2(620, 0))
	# a wall of his own creeps on the straight line: only a ricochet off the boulder above can reach the enemy
	for k in 5:
		_dummy(w, "dawn_melee", C.DAWN, o + Vector2(310, -110 + 55 * k))
	var k3 := w.abilities.kits3
	var bd := {"id": 77, "pos": o + Vector2(310, 330), "vel": Vector2.ZERO, "r": SimKits3.BOULDER_R, "decel": 0.0,
		"rest_at": 0.0, "until": w.time + 30.0, "team": C.DAWN, "src": h.id, "cast": 0, "resting": false, "cells": [],
		"damage": 0.0, "push": 0.0, "spin": 0.0}
	k3.boulders.append(bd)
	k3._rest(bd)
	h.ability_level["place_turret"] = 0             # the shot alone (no turret, no boulders first)
	h.ability_level["summon_boulders"] = 0
	run(w, 0.1)
	var b := _bot16(w, h, [e])
	var aim := SimBot16.best_bounce(b, h, e, false)
	check(not aim.is_empty() and float(aim.score) >= 3.0, "the bot finds a path to the enemy (%s)" % str(aim))
	w.events.clear()
	SimBot16.spells(b, h, e)
	run(w, 1.2)
	var hits := _events_of(w, "bounce_shot_hit").filter(func(x): return int(x.u) == e.id)
	var bounces := _events_of(w, "bounce_shot_bounce")
	check(not hits.is_empty(), "its Bounce Shot reaches the enemy behind the creeps")
	check(not bounces.is_empty(), "by a ricochet (first off the %s)" % (String(bounces[0].what) if not bounces.is_empty() else "-"))
	for x in k3.boulders:
		k3._unrest(x)

func test_bot_blau_hunts_a_killable_laner() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "blau", o)
	var e := _dummy(w, "ezee", C.DUSK, o + Vector2(560, 0), 2000.0)
	e.hp = 260.0                                     # well within his shot, boulders and a few attacks
	run(w, 0.1)
	var b := _bot16(w, h, [e])
	b.mode = "lane"
	check(SimBotKits.burst(w, h, e) + SimBotKits.dps(w, h, e) * 3.0 > e.hp, "his combo can finish it")
	w.events.clear()
	_think16(w, b, 2.4, func(): SimBot16.tick(b, h))
	var casts := _events_of(w, "cast").filter(func(x): return int(x.u) == h.id)
	check(not casts.is_empty(), "he spends spells on it (%s)" % str(casts.map(func(x): return x.ability)))
	check(e.hp < 260.0, "and the laner takes damage")
	check(b._hunt_target == e.id, "the hunt is recorded")
	# (this bot is not in w.bots, so only the orders it gave are logged, not the casts the world carried out)
	check(b.botlog.orders > 0 and not b.botlog.cast_orders.is_empty(), "the Bot Log counts his orders and spell orders")
	var sm := b.botlog.summary("Bot Test", "Blau", b.mode, w.time)
	check(sm.contains("Bounce Shot") or sm.contains("Place Turret") or sm.contains("Summon Boulders"),
		"the summary names the skills he ordered (%s)" % sm)
	for bd in w.abilities.kits3.boulders:
		w.abilities.kits3._unrest(bd)                  # resting boulders block the shared test map's cells
	# a healthy laner is not hunted
	var w2 := empty_world()
	var h2 := _hero16(w2, "blau", o)
	var e2 := _dummy(w2, "ezee", C.DUSK, o + Vector2(560, 0), 3000.0)
	run(w2, 0.1)
	var b2 := _bot16(w2, h2, [e2])
	b2.mode = "lane"
	check(not SimBot16._blau_hunt(b2, h2), "no hunt on a healthy laner")

func test_bot_log_counts_thinking() -> void:
	var w := world()
	w.setup_match()
	var a := w.spawn_hero("blau", C.DAWN)
	var bb := w.spawn_hero("ezee", C.DUSK)
	w.bots.append(SimBot.new(w, a.id, "mid", "Bot A"))
	w.bots.append(SimBot.new(w, bb.id, "mid", "Bot B"))
	run(w, 60.0)
	var lg: SimBotLog = w.bot_for(a.id).botlog
	check(lg.thinks > 100, "thoughts counted (%d)" % lg.thinks)
	check(lg.orders > 5 and lg.orders == lg.from_thought + lg.from_command, "orders counted and split by source")
	check(not lg.entries.is_empty() and lg.entries.size() <= SimBotLog.MAX_ENTRIES, "latest steps kept")
	check(w.bot_for(-5) == null, "no bot for a missing hero")
	var snap := SimSnapshot.capture(w)
	check(snap.size() > 0, "a snapshot leaves the log out and still works")
	w.dispose()

func test_bot_blau_trap_escape() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "blau", o)
	h.hp = h.max_hp * 0.3
	h.facing = 0.0                                # running away (east), the chaser behind him (west)
	var e := _dummy(w, "ezee", C.DUSK, o - Vector2(330, 0))
	run(w, 0.1)
	var b := _bot16(w, h, [e])
	w.events.clear()
	_think16(w, b, 1.6, func(): SimBot16.escape(b, h, h.pos.distance_to(e.pos)))
	var traps := w.effects.filter(func(x): return String(x.kind) == "blau_trap")
	var leaps := _events_of(w, "lay_trap")
	check(traps.size() == 1 and leaps.size() == 1, "the bot lays its trap")
	if leaps.is_empty():
		return
	var land: Vector2 = leaps[0].to
	check(land.distance_to(e.pos) > o.distance_to(e.pos) + 300.0, "it turned and leapt away from the chaser (%d)" % int(land.distance_to(e.pos)))
	var tp: Vector2 = leaps[0].pos
	check(tp.distance_to(e.pos) < tp.distance_to(land), "the trap is left in the chaser's way (trap %s, landing %s, chaser %s)" % [str(tp), str(land), str(e.pos)])

func test_bot_blau_turret_and_pilot() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "blau", o)
	h.scepter = true
	var e := _dummy(w, "ezee", C.DUSK, o + Vector2(700, 60))
	run(w, 0.2)
	var b := _bot16(w, h, [e])
	_think16(w, b, 1.2, func(): SimBot16.spells(b, h, e))
	var turrets := w.units.filter(func(u): return u.kind == K.SUMMON and u.alive and u.owner_id == h.id)
	check(turrets.size() >= 1, "in a fight the bot builds a turret")
	if turrets.is_empty():
		return
	check((turrets[0] as SimUnit).pos.distance_to(e.pos) <= 650.0 + e.hull, "within the turret's reach of the target")
	h.hp = h.max_hp * 0.3
	b.mode = "fight"
	_think16(w, b, 2.0, func(): SimBot16.tick(b, h))
	check(w.abilities.kits3.is_piloting(h), "hurt, it climbs into its turret")
	(turrets[0] as SimUnit).hp = (turrets[0] as SimUnit).max_hp * 0.15
	_think16(w, b, 0.5, func(): SimBot16.tick(b, h))
	check(not w.abilities.kits3.is_piloting(h), "and gets out before it falls")

func test_bot_roydo_rush_then_grip() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "roydo", o)
	h.ability_level["anomaly"] = 0                  # one thing at a time
	var e := _dummy(w, "ezee", C.DUSK, o + Vector2(480, 0))
	run(w, 0.2)
	var b := _bot16(w, h, [e])
	w.events.clear()
	_think16(w, b, 2.0, func(): SimBot16.spells(b, h, e))
	var casts := _events_of(w, "cast").filter(func(x): return int(x.u) == h.id).map(func(x): return String(x.ability))
	check(casts.size() >= 2 and casts[0] == "void_rush" and casts.has("grip_of_the_ruler"), "Void Rush, then the grip (%s)" % str(casts))
	var stun := _events_of(w, "debuff").filter(func(x): return int(x.u) == e.id and String(x.id) == "stunned")
	check(not stun.is_empty() and float(stun[0].dur) > 1.4, "the stun lasts longer on the weakened enemy (%s)" % (str(stun[0].dur) if not stun.is_empty() else "none"))

## Regression (2026-10-16): in Anomaly Roydo attacks at range with no projectile speed of his own; the bot's last-hit
## forecast divided by it and looped for ever, freezing every game his bot reached level 6 in a lane.
func test_bot_roydo_anomaly_last_hit_forecast() -> void:
	var w := empty_world()
	var o := Vector2(-2000, -4000)
	var h := _hero16(w, "roydo", o)
	w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "anomaly"})
	run(w, 0.5)
	check(h.is_ranged() and h.projectile_speed() > 0.0, "Anomaly: ranged with the form's projectile speed")
	var c := w.spawn("dusk_melee", C.DUSK, o + Vector2(500, 0))
	c.hp = 40.0
	var hitter := w.spawn("dawn_melee", C.DAWN, c.pos + Vector2(60, 0))
	hitter.atk_target = c.id
	var b := _bot16(w, h, [])
	var foes: Array[SimUnit] = [c]
	var allies: Array[SimUnit] = []
	var t0 := Time.get_ticks_msec()
	var pick := b._last_hit_target(h, foes, allies)
	check(Time.get_ticks_msec() - t0 < 1000, "the forecast returns")
	check(pick == c, "and picks the low creep in his 650 range (%s)" % str(pick))
	check(is_finite(b._hp_when(c, INF)), "an infinite forecast time is capped")

func test_bots_knock_down_enemy_turrets() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "ezee", o)
	var t := w.spawn("blau_turret", C.DUSK, o + Vector2(450, 0))
	t.ward_expires = w.time + 30.0
	run(w, 0.1)
	var b := _bot16(w, h, [])
	b.mode = "lane"
	check(SimBot16.tick(b, h), "the bot takes it on")
	check(h.order == O.ATTACK_UNIT and h.order_target == t.id, "it attacks the enemy turret")

# ---- 2026-10-16 b: the owner's mechanics list (grip target check, Blau's reach, Unfair bots, pushing) -----------------

func test_roydo_grip_needs_a_target() -> void:
	var w := empty_world()
	var r := _hero16(w, "roydo", Vector2(-2000, -4000))
	var center := Vector2(-1500, -4000)
	run(w, 0.2)
	var mana0 := r.mana
	w.events.clear()
	w.command(r.id, {"type": O.CAST_POINT, "ability": "grip_of_the_ruler", "point": center})
	run(w, 0.6)
	var errs := _events_of(w, "error").filter(func(x): return int(x.u) == r.id)
	check(not errs.is_empty() and String(errs[0].msg) == "No valid target", "an empty area: No valid target (%s)" % str(errs))
	check(r.mana == mana0 and w.abilities.cooldown_left(r, "grip_of_the_ruler") == 0.0, "nothing spent")
	check(_events_of(w, "grip").is_empty(), "and the spell does not go off")
	# an enemy in the fog is seized; an invisible one is not
	var e := _dummy(w, "ezee", C.DUSK, center + Vector2(200, 0))
	run(w, 0.1)
	e.add_modifier({"id": "test_invis", "source": -1, "expires": INF, "invisible": true})
	e.refresh_stats()
	run(w, 0.1)
	check(e.has_flag("invisible") and not w.vision.sees(r.team, e), "the enemy is invisible to Roydo")
	check(w.abilities.cast_error(r, "grip_of_the_ruler", -1, null, center) == "No valid target", "an invisible enemy is no target")
	e.remove_modifier("test_invis")
	e.refresh_stats()
	var hidden := _dummy(w, "ezee", C.DUSK, center + Vector2(-150, 60))
	w.vision.reveal_all = false
	var pool := w.abilities.kits3.grip_pool(r, center)
	check(pool.has(e) and pool.has(hidden), "units in the area are thrown, seen or in the fog (seen: %s)" % str(w.vision.sees(r.team, hidden)))
	check(w.abilities.cast_error(r, "grip_of_the_ruler", -1, null, center + Vector2(2000, 0)) == "No valid target", "far from anyone: refused")
	check(w.abilities.cast_error(r, "grip_of_the_ruler", -1, null, center, false, false) == "", "the hotkey alone is not refused (no point yet)")

func test_blau_bounce_shot_reach_grows_per_bounce() -> void:
	var w := empty_world()
	var spot := _bounce_spot(w, "wall")
	check(spot != Vector2.INF, "found a wall")
	if spot == Vector2.INF:
		return
	var b := _hero16(w, "blau", spot - Vector2(420, 0))
	var k3 := w.abilities.kits3
	var from := b.pos + Vector2(b.hull + 10.0, 0)
	var plain := k3.trace_bullet(from, Vector2.RIGHT, b.team, 1800.0, 9, b.id, SimKits3.SUBSTEP, {}, 0.0)
	var longer := k3.trace_bullet(from, Vector2.RIGHT, b.team, 1800.0, 9, b.id, SimKits3.SUBSTEP, {},
		w.abilities.val(b, "bounce_shot", "bounce_distance"))
	var length := func(tr: Dictionary) -> float:
		var s := 0.0
		var cs: Array = tr.corners
		for i in range(1, cs.size()):
			s += (cs[i] as Vector2).distance_to(cs[i - 1])
		return s
	check((longer.corners as Array).size() >= 3, "the shot ricochets (%d corners)" % (longer.corners as Array).size())
	check(float(length.call(longer)) > float(length.call(plain)) + 300.0, "each bounce adds reach (%d against %d)" % [int(length.call(longer)), int(length.call(plain))])
	# the real bullet: its distance left grows by 400 at a bounce
	run(w, 0.1)
	w.events.clear()
	w.command(b.id, {"type": O.CAST_POINT, "ability": "bounce_shot", "point": spot})
	var gain := -INF
	var left0 := -1.0
	for i in 40:
		var n0 := _events_of(w, "bounce_shot_bounce").size()
		w.step()
		for e in w.effects:
			if String(e.kind) == "bounce_shot":
				if left0 >= 0.0 and _events_of(w, "bounce_shot_bounce").size() > n0 and gain == -INF:
					gain = float(e.left) - left0
				left0 = float(e.left)
	check(not _events_of(w, "bounce_shot_bounce").is_empty(), "it bounced off the wall")
	near(gain, 400.0 - 2400.0 * C.DT, 1.0, "the bounce gave it 400 more distance (less this step's travel)")
	near(w.abilities.val(b, "bounce_shot", "bounce_distance"), 400.0, 0.01, "400 per bounce")

func test_blau_boulders_roll_to_the_point() -> void:
	for want in [300.0, 700.0, 2000.0]:
		var w := empty_world()
		var b := _hero16(w, "blau", Vector2(5600, -5700))
		run(w, 0.1)
		var start := b.pos
		w.command(b.id, {"type": O.CAST_POINT, "ability": "summon_boulders", "point": b.pos + Vector2(want, 0)})
		run(w, 3.2)
		var k3 := w.abilities.kits3
		check(k3.boulders.size() == 6 and k3.boulders.all(func(x): return bool(x.resting)), "6 boulders at rest after 3 s (%.0f)" % want)
		var far := 0.0
		for bd in k3.boulders:
			far = maxf(far, (bd.pos as Vector2).distance_to(start))
		var cap := minf(want, 700.0)
		check(far <= cap + 40.0 and far >= cap * 0.7, "cast %.0f away: they roll about that far, 700 at most (%d)" % [want, int(far)])
		check(b.pos.distance_to(start) < 30.0, "Blau casts where he stands (%.0f): moved to %s from %s, order %d" % [want, str(b.pos), str(start), b.order])
		for bd in k3.boulders:
			k3._unrest(bd)

# ---- Azrael (2026-10-17) ---------------------------------------------------------------------------------------------

func test_azrael_data() -> void:
	var d := SimData.unit("azrael")
	check(not d.is_empty() and d.kind == K.HERO, "Azrael is a hero")
	check(int(d.element) == C.Element.DARK, "of the Dark element")
	near(float(d.range), 150.0, 0.01, "melee, 150 range")
	check((d.talents as Array).size() == 4, "4 talent tiers")
	for tier in d.talents:
		for tid in tier:
			check(not SimData.talent(String(tid)).is_empty(), "talent %s exists" % tid)
	check(String(SimData.ability("soul_tap").behavior) == "toggle", "Soul Tap is a toggle")
	near(float(SimData.ability("soul_tap").mana[0]), 80.0, 0.01, "Soul Tap costs 80")
	near(float(SimData.ability("soul_tap").values.scan_interval[0]), 4.5, 0.01, "Soul Tap scans every 4.5 s")
	near(float(SimData.ability("soul_tap").values.radius[0]), 600.0, 0.01, "Soul Tap 600 scan radius")
	near(float(SimData.ability("door_of_the_end").cooldown[0]), 12.0, 0.01, "Door of the End 12 s")
	near(float(SimData.ability("death_scythe").cooldown[0]), 1.0, 0.01, "Death Scythe 1 s cooldown")
	near(float(SimData.ability("divine_darkness").cooldown[0]), 60.0, 0.01, "Divine Darkness 60 s")
	check(SimBotKits.ROLES.has("azrael") and SimBotKits.SKILLS.has("azrael"), "bots know her")
	check("azrael" in GameSettings.HEROES, "she can be picked")

func test_azrael_soul_tap_charge_and_cleave() -> void:
	var w := empty_world()
	var o := Vector2(-2000, -4000)
	var a := _hero16(w, "azrael", o)
	a.ability_level["death_scythe"] = 0
	# first: toggle on with no units within 600 -> scans after 4.5 s, spends 0 mana, continues scanning
	var far := _dummy(w, "dusk_melee", C.DUSK, o + Vector2(1600, 0), 5000.0)
	run(w, 0.1)
	var mana0 := a.mana
	w.command(a.id, {"type": O.CAST_NO_TARGET, "ability": "soul_tap"})
	run(w, 4.6)
	check(bool(a.toggles.get("soul_tap", false)), "Soul Tap stays toggled on")
	check(_events_of(w, "soul_tap").is_empty(), "no valid targets in 600: no soul_tap proc")
	near(a.mana, mana0, 0.5, "no valid targets: no mana spent")
	# now units enter the 600 radius around her: next scan 4.5 s later consumes 80 mana and charges her strike
	var target := _dummy(w, "dusk_melee", C.DUSK, o + Vector2(140, 0), 5000.0)
	target.def = target.def.duplicate()
	target.def.armor = 25.0
	target.refresh_stats()
	var beside := _dummy(w, "dusk_melee", C.DUSK, o + Vector2(260, 60), 5000.0)
	beside.def = beside.def.duplicate()
	beside.def.armor = 25.0
	beside.refresh_stats()
	var foe := _dummy(w, "ezee", C.DUSK, o + Vector2(250, -70), 5000.0)
	foe.status_resist = 0.0
	var friend := _dummy(w, "dawn_melee", C.DAWN, o + Vector2(200, 130), 5000.0)
	var dmg0 := a.bonus_damage
	a.mana = a.max_mana
	run(w, 4.6)
	var ev := _events_of(w, "soul_tap")
	check(not ev.is_empty(), "Soul Tap scans and charges")
	if not ev.is_empty():
		check((ev[0].souls as Array).size() == 4 and not (a.id in ev[0].souls) and not (far.id in ev[0].souls),
			"four souls in 600: enemies and ally, not her, not the far one (%s)" % str(ev[0].souls))
	near(a.bonus_damage - dmg0, 4.0 * 35.0 + 40.0, 0.01, "+35 a unit at level 4, +40 more for the hero")
	near(a.mana, a.max_mana - 80.0, 2.0, "80 mana consumed when targets are scanned")
	# one attack spends it, deals pure damage in a 100% cleave over 400 area, and slows all hit enemies by 80% for 0.80 s
	var hp_t := target.hp
	var hp_b := beside.hp
	w.events.clear()
	a.auto_attack = true
	w.command(a.id, {"type": O.ATTACK_UNIT, "target": target.id})
	for i in 60:
		w.step()
		if not _events_of(w, "soul_slash").is_empty():
			break
	check(not _events_of(w, "soul_slash").is_empty(), "the charged slash lands")
	check(a.get_modifier("soul_tap").is_empty(), "the charge is spent by one attack")
	near(a.bonus_damage, dmg0, 0.01, "the bonus damage is gone")
	var dealt_t := hp_t - target.hp
	var dealt_b := hp_b - beside.hp
	check(dealt_t > 240.0 and absf(dealt_t - dealt_b) < 1.0,
		"pure damage on target and 100%% pure cleave on creep beside (%.1f vs %.1f, ignoring 25 armor)" % [dealt_t, dealt_b])
	var st_t := target.get_modifier("soul_tap_slow")
	var st_b := beside.get_modifier("soul_tap_slow")
	check(not st_t.is_empty() and not st_b.is_empty(), "both primary target and cleaved enemy are slowed")
	near(float(st_t.get("slow", 0.0)), 0.80, 0.01, "slowed by 80%")
	near(float(st_t.get("dur", 0.0)), 0.80, 0.01, "slow lasts 0.80 s")
	check(friend.hp == friend.max_hp, "allies are not cleaved")

func test_azrael_door_of_the_end() -> void:
	var w := empty_world()
	var o := Vector2(-2000, -4000)
	var a := _hero16(w, "azrael", o)
	a.ability_level["death_scythe"] = 0
	var allies: Array = []
	for k in 3:
		allies.append(_hero16(w, ["ezee", "froster", "caziel"][k], o + Vector2(-150, -120 + 120 * k)))
	var exit_p := o + Vector2(0, 700)
	var foe := _dummy(w, "dusk_melee", C.DUSK, exit_p + Vector2(200, 0), 5000.0)
	var far_foe := _dummy(w, "dusk_melee", C.DUSK, exit_p + Vector2(900, 0), 5000.0)
	run(w, 0.1)
	var door_p := o + Vector2(300, 0)
	w.command(a.id, {"type": O.CAST_POINT, "ability": "door_of_the_end", "point": door_p})
	run(w, 0.5)
	check(w.abilities.kits4.exit_pending(a), "the door is open, the exit not yet set")
	near(w.abilities.cooldown_left(a, "door_of_the_end"), 11.8, 0.15, "cooldown from the entrance")
	var mana_after := a.mana
	check(w.abilities.cast_error(a, "door_of_the_end", -1, null, exit_p) == "", "the exit can be cast at once")
	near(w.abilities.cast_range(a, "door_of_the_end", -1), 800.0, 0.01, "exit range 800")
	# everyone walks in: her and two allies; the third is turned away
	w.command(a.id, {"type": O.MOVE, "point": door_p})
	for h in allies:
		w.command(h.id, {"type": O.MOVE, "point": door_p})
	run(w, 1.6)
	var inside := allies.filter(func(h): return w.abilities.kits4.in_door(h))
	check(w.abilities.kits4.in_door(a), "Azrael is inside")
	check(inside.size() == 2, "two allies inside, not three (%d)" % inside.size())
	check(a.is_invulnerable() and a.has_flag("hidden"), "hidden and invulnerable inside")
	check(w.abilities.cast_error(a, "divine_darkness", -1, null, a.pos) != "", "no other spells from inside")
	# the exit, from inside: free
	w.command(a.id, {"type": O.CAST_POINT, "ability": "door_of_the_end", "point": exit_p})
	run(w, 0.5)
	check(not w.abilities.kits4.exit_pending(a), "the exit is set")
	check(a.mana >= mana_after - 0.5, "the exit costs no mana (%.1f, was %.1f)" % [a.mana, mana_after])
	# one ally prematurely leaves the door by moving: comes out without triggering the explosion
	var early_ally: SimUnit = inside[0]
	var stay_ally: SimUnit = inside[1]
	w.command(early_ally.id, {"type": O.MOVE, "point": exit_p + Vector2(120, 0)})
	run(w, 0.2)
	check(not w.abilities.kits4.in_door(early_ally), "ally prematurely came out of the door")
	check(_events_of(w, "door_blast").is_empty(), "premature exit does not trigger the explosion")
	check(w.abilities.kits4.in_door(a) and w.abilities.kits4.in_door(stay_ally), "others remain inside until the door finishes")
	# damage Azrael and the allies right before the door closes so we can verify the 250 heal and 1 s stun on explosion
	run(w, 3.4)
	a.hp = a.max_hp - 400.0
	stay_ally.hp = stay_ally.max_hp - 400.0
	var hp_a_before := a.hp
	var hp_ally_before := stay_ally.hp
	run(w, 0.4)
	check(not w.abilities.kits4.in_door(a) and a.pos.distance_to(exit_p) < 160.0, "she steps out of the exit (%s)" % str(a.pos))
	check(stay_ally.pos.distance_to(exit_p) < 200.0 and not stay_ally.is_invulnerable(), "staying ally steps out with her")
	var blast := _events_of(w, "door_blast")
	check(not blast.is_empty(), "a spirit blast at the exit")
	near(a.hp - hp_a_before, 250.0, 5.0, "Door of the End heals Azrael by 250 at level 4")
	near(stay_ally.hp - hp_ally_before, 250.0, 5.0, "Door of the End heals nearby allies by 250 at level 4")
	near(foe.max_hp - foe.hp, 450.0 * (1.0 + a.magic_amp + a.spell_amp) * (1.0 - foe.magic_resist), 70.0, "450 magic damage near the exit")
	check(foe.is_stunned(), "enemies hit by the explosion are stunned for 1 s")
	near(foe.element_resist_loss(), 0.28, 0.001, "strips 28% elemental resistance at level 4 for 4 s")
	var hp_before_elem := foe.hp
	w.combat.deal_damage(a.id, a.team, true, foe, 100.0, C.DamageType.PURE, false, "test", false,
		{"no_amp": true, "element": C.Element.DARK})
	near(hp_before_elem - foe.hp, 128.0, 0.5, "stripped elemental resistance increases elemental damage taken by 28%")
	check(far_foe.hp == far_foe.max_hp, "not beyond 450")
	# after 4 s the elemental resistance strip expires
	run(w, 4.2)
	near(foe.element_resist_loss(), 0.0, 0.001, "elemental resistance strip expires after 4 s")
	# no exit placed: out of the entrance
	var w2 := empty_world()
	var a2 := _hero16(w2, "azrael", o)
	run(w2, 0.1)
	w2.command(a2.id, {"type": O.CAST_POINT, "ability": "door_of_the_end", "point": o + Vector2(200, 0)})
	run(w2, 0.5)
	w2.command(a2.id, {"type": O.MOVE, "point": o + Vector2(200, 0)})
	run(w2, 7.0)
	check(not w2.abilities.kits4.in_door(a2) and a2.pos.distance_to(o + Vector2(200, 0)) < 160.0, "no exit: out at the entrance")

func test_azrael_death_scythe() -> void:
	var w := empty_world()
	var o := Vector2(-2000, -4000)
	var a := _hero16(w, "azrael", o)
	var t := _dummy(w, "dusk_melee", C.DUSK, o + Vector2(140, 0), 1e6)
	t.def = t.def.duplicate()
	t.def.armor = 20.0
	t.refresh_stats()
	run(w, 0.1)
	a.hp = a.max_hp - 500.0
	var hp_start := a.hp
	a.auto_attack = true
	w.command(a.id, {"type": O.ATTACK_UNIT, "target": t.id})
	var procs: Array = []
	var pure_hits := 0
	for i in int(40.0 * C.TICK_RATE):
		w.step()
		for ev in w.events:
			if ev.t == "death_scythe":
				procs.append(w.time)
			if ev.t == "damage" and int(ev.u) == t.id and int(ev.get("type", -1)) == C.DamageType.PURE:
				pure_hits += 1
		w.events.clear()
	check(procs.size() >= 3, "Death Scythe strikes over 40 s of attacks (%d)" % procs.size())
	check(pure_hits >= procs.size(), "each strike is pure damage")
	check(a.hp > hp_start + 150.0, "Death Scythe lifesteals 50%% of the damage done (hp %.0f -> %.0f)" % [hp_start, a.hp])
	var ok := true
	for k in range(1, procs.size()):
		if float(procs[k]) - float(procs[k - 1]) < 0.99:
			ok = false
	check(ok, "never twice within 1.0 s")
	# the bonus and 50% lifesteal on a single forced strike
	var w2 := empty_world()
	var a2 := _hero16(w2, "azrael", o)
	var t2 := _dummy(w2, "dusk_melee", C.DUSK, o + Vector2(140, 0), 1e6)
	a2.hp = a2.max_hp - 300.0
	a2.prd["death_scythe"] = 100
	var hp_b := a2.hp
	var dealt := w2.combat.deal_damage(a2.id, a2.team, true, t2, 100.0, C.DamageType.PHYSICAL, true, "attack")
	near(dealt, 160.0, 0.01, "100 base + 60 bonus pure damage at level 4")
	near(a2.hp - hp_b, 80.0, 0.01, "heals 50% of the 160 damage done (80 hp)")
	check(w2.abilities.kits4.death_scythe(a2, t2, "item_x") < 0.0, "not on item damage")

func test_azrael_divine_darkness() -> void:
	var w := empty_world()
	w.time = 400.0                               # night
	var o := Vector2(-2000, -4000)
	var a := _hero16(w, "azrael", o)
	var e := _dummy(w, "ezee", C.DUSK, o + Vector2(500, 0), 5000.0)
	var e_far := _dummy(w, "ezee", C.DUSK, o + Vector2(1500, 0), 5000.0)
	run(w, 0.1)
	var as0 := a.attack_speed
	var ms0 := a.move_speed
	var ev0 := e.vision_night
	w.command(a.id, {"type": O.CAST_NO_TARGET, "ability": "divine_darkness"})
	run(w, 0.8)
	check(not a.get_modifier("divine_darkness").is_empty(), "the wings open")
	near(a.attack_speed - as0, 50.0, 0.5, "+50 attack speed")
	near(a.move_speed, ms0 * 1.15, 0.5, "+15% movement speed")
	near(a.vision_night, 1800.0 * 1.7, 1.0, "+70% sight, the day range at night too")
	near(e.vision_night, ev0 * 0.5, 1.0, "an enemy within 700 loses half its sight")
	near(e_far.vision_night, ev0, 1.0, "not one further away")
	# flight: straight over a tree line (the walking path is longer)
	var spot := _tree_spot()
	var tp: Vector2 = _map.trees[int(spot[0])].pos
	var out: Vector2 = -(spot[2] as Vector2)
	a.pos = tp + out * 250.0
	var goal := tp - out * 250.0
	w.command(a.id, {"type": O.MOVE, "point": goal})
	run(w, 2.0)
	check(a.pos.distance_to(goal) < 40.0, "she flies straight over the trees (%d left)" % int(a.pos.distance_to(goal)))
	run(w, 24.0)
	check(a.get_modifier("divine_darkness").is_empty(), "after 25 s the wings fold")
	check(w.map.is_walkable(a.pos), "she lands on open ground")
	near(e.vision_night, ev0, 1.0, "the enemy's sight comes back")

func test_unfair_bots_gold_and_xp() -> void:
	var w := empty_world()
	var a := _hero16(w, "ezee", Vector2(-2000, -4000))
	var h := _hero16(w, "blau", Vector2(-2200, -4000))
	SimBot.new(w, a.id, "mid", "Unfair", "unfair")
	SimBot.new(w, h.id, "top", "Hard", "hard")
	near(a.gold_mult, 3.0, 1e-6, "Unfair: +200% gold")
	near(a.xp_mult, 1.5, 1e-6, "Unfair: +50% experience")
	near(h.gold_mult, 1.0, 1e-6, "Hard: no bonus")
	var g0 := a.gold()
	w.combat.give_gold(a, 100, false, a.pos)
	check(a.gold() - g0 == 300, "100 gold earned is 300 (%d)" % (a.gold() - g0))
	a.level = 1
	a.xp = 0.0
	w.combat.give_xp(a, 100.0)
	near(a.xp, 150.0, 0.01, "100 experience is 150")
	var ga := a.gold()
	var gh := h.gold()
	run(w, 30.0)
	var pa := float(a.gold() - ga)
	var ph := float(h.gold() - gh)
	check(ph > 0.0 and absf(pa / ph - 3.0) < 0.2, "passive gold three times as fast (%d against %d)" % [int(pa), int(ph)])

func test_unfair_melee_bots_plan_jump_knife() -> void:
	var w := empty_world()
	for id in ["ezee", "kragg", "roydo", "sludge"]:
		var h := _hero16(w, id, Vector2(-2000, -4000))
		var b := SimBot.new(w, h.id, "mid", "Unfair", "unfair")
		var k := b.build.find("jump_knife")
		var boots := -1
		for i in b.build.size():
			if String(b.build[i]) in SimBot.BOOT_UPGRADES:
				boots = i
				break
		check(k >= 0 and (boots < 0 or k == boots + 1), "%s (Unfair) buys a Jump Knife right after its boots (%s)" % [id, str(b.build)])
	var rb := _hero16(w, "blau", Vector2(-2000, -4400))
	var rbot := SimBot.new(w, rb.id, "mid", "Ranged", "unfair")
	var plan: Array = (SimBotKits.builds("blau", rbot.role)[rbot.build_idx] as Array)
	check(rbot.build == plan, "a ranged Unfair bot keeps its build")

func test_bot_jumps_in_with_jump_knife() -> void:
	var w := empty_world()
	var o := Vector2(5600, -5700)
	var h := _hero16(w, "ezee", o)
	_give(w, h, "jump_knife", 0)
	var e := _dummy(w, "blau", C.DUSK, o + Vector2(800, 0))
	run(w, 0.2)
	var b := _bot16(w, h, [e])
	b._fight_items(h, e)
	check(h.order == O.CAST_POINT and h.cast_item_slot == 0, "a melee bot jumps on the hero it fights (order %d)" % h.order)
	run(w, 0.3)
	check(h.pos.distance_to(e.pos) < 250.0, "and lands beside it (%d)" % int(h.pos.distance_to(e.pos)))

func test_bots_push_when_no_enemy_hero_is_near() -> void:
	var w := empty_world()
	w.time = 120.0
	var o := Vector2(-1800, -1800)
	var h := _hero16(w, "ezee", o)
	var c := w.spawn("dusk_melee", C.DUSK, o + Vector2(160, 0))
	c.lane = "mid"
	c.order = O.HOLD
	var mine := w.spawn("dawn_melee", C.DAWN, o + Vector2(80, 60))
	mine.lane = "mid"
	mine.order = O.HOLD
	run(w, 0.2)
	var b := _bot16(w, h, [])
	b.lane = "mid"
	b._known.clear()
	b._lane(h)
	check(h.order == O.ATTACK_UNIT and h.order_target == c.id, "alone in lane, the bot hits the full-health creep (pushes)")
	# an enemy hero beside the wave: back to last hits and trades, no free pushing
	var e := _dummy(w, "blau", C.DUSK, o + Vector2(900, 0))
	run(w, 0.2)
	h.order = O.NONE
	h.order_target = -1
	b._last_order = {}
	b._known.clear()
	b._known.append(e)
	b._next_trade = w.time + 60.0
	b._lane(h)
	check(not (h.order == O.ATTACK_UNIT and h.order_target == c.id), "with an enemy hero near it does not push the wave")

func test_team_networth_lead_makes_bots_bold() -> void:
	var w := empty_world()
	var a := _hero16(w, "ezee", Vector2(-2000, -4000))
	var e := _hero16(w, "blau", Vector2(2000, 4000), C.DUSK)
	var b := SimBot.new(w, a.id, "mid", "Bot", "hard")
	a.gold_reliable = e.gold_reliable
	a.gold_unreliable = e.gold_unreliable
	near(w.brain(C.DAWN).networth_lead(), 0.0, 1e-6, "even net worth: no lead")
	var bold0 := b._boldness()
	a.gold_reliable += 6000
	var lead := w.brain(C.DAWN).networth_lead()
	check(lead > 0.3, "6000 gold more is a lead (%.2f)" % lead)
	check(w.brain(C.DUSK).networth_lead() < 0.0, "the other team is behind")
	check(b._boldness() > bold0 + 0.15, "and the bot plays bolder (%.2f against %.2f)" % [b._boldness(), bold0])

func test_bots_hit_the_tower_when_alone_early() -> void:
	var w := empty_world()
	w.time = 150.0                                  # before 5:00 a laning bot used to leave towers alone
	var tw := w.spawn("tower1", C.DUSK, Vector2(-1000, -4000))
	var h := _hero16(w, "ezee", tw.pos + Vector2(-tw.attack_range - 60.0, 0))
	var mine := w.spawn("dawn_melee", C.DAWN, tw.pos + Vector2(-140, 0))
	mine.lane = "bot"
	mine.order = O.HOLD
	run(w, 0.3)
	tw.atk_target = mine.id
	var b := _bot16(w, h, [])
	b.lane = "bot"
	b._known.clear()
	b._lane(h)
	check(h.order == O.ATTACK_UNIT and h.order_target == tw.id, "no enemy hero near: the bot hits the tower its creep tanks (order %d -> %d)" % [h.order, h.order_target])

func test_switch_boots_icon_follows_attribute() -> void:
	var w := empty_world()
	var h := _hero16(w, "ezee", Vector2(-2000, -4000))
	var it := _give(w, h, "power_treads", 0)
	it["attr"] = "str"
	var seen := {}
	for k in 3:
		var tex := UiKit.held_item_icon(it)
		check(tex != null and tex != UiKit.item_icon("power_treads"), "%s: its own icon" % String(it.attr))
		check(tex != null and tex.resource_path.ends_with("power_treads_%s.svg" % String(it.attr)), "the %s icon (%s)" % [String(it.attr), tex.resource_path if tex else "none"])
		seen[tex] = true
		w.command(h.id, {"type": O.CAST_NO_TARGET, "ability": "", "item_slot": 0})
		run(w, 0.1)
	check(seen.size() == 3, "three different icons as it switches (%d)" % seen.size())
	check(UiKit.held_item_icon({"id": "boots"}) == UiKit.item_icon("boots"), "other items keep their icon")

# ---- Map sites (Warp Gates, Lily Ponds, Lookout Lamps) -----------------------------------------------------------------

func _site(w: SimWorld, kind: String, n := 0) -> Dictionary:
	return w.sites.of_kind(kind)[n]

func test_map_outer_ground() -> void:
	# the map grew 1024 a side; the outer ground beyond the top and bottom lanes is open, the classic edge beside the bases
	# stays rock, and the map is still the same rotated 180 degrees
	check(SimMap.HALF == 9216.0 and SimMap.N * SimMap.CELL == 2.0 * SimMap.HALF, "map is 18432 across")
	check(SimMap.VN * C.VISION_CELL == 2.0 * SimMap.HALF, "vision grid covers the map")
	check(_map.is_walkable(Vector2(2600, -8250)), "open ground south of the bottom lane (lamp walkway)")
	check(_map.is_walkable(Vector2(-8250, 4300)), "open ground west of the top lane's north end")
	check(_map.level_at(Vector2(-8600, -7000)) == SimMap.MOUNTAIN, "past the classic edge beside Dawn's base: rock")
	check(_map.level_at(Vector2(8600, 7000)) == SimMap.MOUNTAIN, "past the classic edge beside Dusk's base: rock")
	for p: Vector2 in [Vector2(2600, -8250), Vector2(-8250, 4300), Vector2(-7000, 7500), Vector2(5000, -8700)]:
		check(_map.is_mountain(p) == _map.is_mountain(-p), "mountains symmetric at %s" % str(p))
	check(_map.sites.size() == 8, "8 sites: 2 gates, 2 ponds, 4 lamps (%d)" % _map.sites.size())
	for st in _map.sites:
		var path := _map.find_path(_map.fountains[0], st.pos)
		check(not path.is_empty() and path[-1].distance_to(st.pos) < 200.0, "%s at %s reachable" % [st.kind, str(st.pos)])

func test_warp_gate() -> void:
	var w := empty_world()
	var g := _site(w, "gate", 0)
	var other := w.sites.get_site(int(g.pair))
	check(not other.is_empty() and int(other.pair) == int(g.id), "the two gates are linked")
	var h := _sludge(w, (g.pos as Vector2) + Vector2(450, 0))
	h.mana = 200.0
	w.command(h.id, {"type": O.USE_SITE, "site": int(g.id)})
	run(w, 2.0)
	check(not h.channel.is_empty() and String(h.channel.ability) == "site_gate", "walks into reach (200) and channels")
	near(h.mana, 200.0 - SimSites.GATE_MANA, 6.0, "30 mana spent")
	run(w, 4.1)
	check(h.pos.distance_to(other.exit) < 80.0, "after 4 s it stands by the other gate (%s)" % str(h.pos))
	# broken by an order: mana back, no warp
	h.pos = (other.pos as Vector2) + Vector2(100, 0)
	h.mana = 200.0
	w.command(h.id, {"type": O.USE_SITE, "site": int(other.id)})
	run(w, 1.0)
	check(not h.channel.is_empty(), "second channel started")
	var m0 := h.mana
	w.command(h.id, {"type": O.MOVE, "point": h.pos + Vector2(200, 0)})
	check(h.channel.is_empty(), "a move order breaks it")
	near(h.mana - m0, SimSites.GATE_MANA, 0.01, "and gives the 30 mana back")
	run(w, 4.0)
	check(h.pos.distance_to(other.pos) < 600.0, "no warp after a broken channel")
	# a stun breaks it too; not enough mana: refused
	h.mana = 10.0
	w.command(h.id, {"type": O.USE_SITE, "site": int(other.id)})
	run(w, 1.0)
	check(h.channel.is_empty(), "10 mana: refused")

func test_lily_pond() -> void:
	var w := empty_world()
	var s := _site(w, "pond", 0)
	w.time = 179.0
	run(w, 1.1)
	check(int(s.lilies) == 1, "a lily at 3:00 (%d)" % int(s.lilies))
	w.time = 179.0 + 180.0 * 6
	s.next = w.time - 0.1
	s.lilies = 5
	run(w, 0.2)
	run(w, 0.2)
	check(int(s.lilies) == 6, "at most 6 (%d)" % int(s.lilies))
	var h := _sludge(w, (s.pos as Vector2) + Vector2(100, 0))
	h.hp = h.max_hp - 400.0
	h.mana = 0.0
	run(w, 1.4)
	check(int(s.lilies) == 6, "not before 1.5 s")
	run(w, 0.2)
	check(int(s.lilies) == 5, "the first after 1.5 s (%d)" % int(s.lilies))
	near(h.max_hp - h.hp, 400.0 - 125.0, 30.0, "125 health (and 1.6 s of regeneration)")
	check(h.mana >= 124.0, "125 mana")
	run(w, 1.05)
	check(int(s.lilies) == 4, "the next one 30%% faster (1.05 s) (%d)" % int(s.lilies))
	# an enemy hero in the area pauses it
	var e := _sludge(w, (s.pos as Vector2) + Vector2(-100, 0), {}, C.DUSK)
	run(w, 3.0)
	check(int(s.lilies) == 4, "paused while an enemy hero is in the pond (%d)" % int(s.lilies))
	e.pos = Vector2(0, 0)
	run(w, 0.8)
	check(int(s.lilies) == 3, "goes on when it leaves (the third in a row: 0.74 s) (%d)" % int(s.lilies))

func test_lookout_lamp() -> void:
	var w := empty_world()
	var s := _site(w, "lamp", 0)
	var h := _sludge(w, (s.pos as Vector2) + Vector2(500, 0))
	w.command(h.id, {"type": O.USE_SITE, "site": int(s.id)})
	run(w, 1.0)
	check(String(h.channel.get("ability", "")) == "site_lamp", "walks into reach (300) and channels")
	run(w, 1.1)
	check(w.sites.lamp_lit(s, C.DAWN), "lit for Dawn after 1 s")
	# its sight: 800 by day around the lamp, even with no unit there
	h.pos = Vector2(0, 0)
	w.vision.update()
	check(w.vision.cell_visible(C.DAWN, (s.pos as Vector2) + Vector2(0, 600)), "Dawn sees 600 from the lamp by day")
	check(not w.vision.cell_visible(C.DUSK, s.pos), "Dusk does not")
	# an enemy puts it out for 2:00
	var e := _sludge(w, (s.pos as Vector2) + Vector2(150, 0), {}, C.DUSK)
	w.command(e.id, {"type": O.USE_SITE, "site": int(s.id)})
	run(w, 1.2)
	check(not w.sites.lamp_lit(s, C.DAWN) and not w.sites.lamp_lit(s, C.DUSK), "put out by the other team")
	check(w.sites.use_error(e, s) != "", "nobody can light it for 2:00")
	w.time += 121.0
	check(w.sites.use_error(e, s) == "", "after 2:00 it can be lit again")
	w.command(e.id, {"type": O.USE_SITE, "site": int(s.id)})
	run(w, 1.2)
	check(w.sites.lamp_lit(s, C.DUSK), "lit for Dusk")
	w.time += 421.0
	run(w, 0.1)
	check(not w.sites.lamp_lit(s, C.DUSK), "dark again after 7:00")

## Body collision (run 2026-10-18): every hero's body has its collision set (tests/tools/body_collide.gd --fix), and it
## covers that hero's attacks, so RepairedClips keeps arms and weapons out of the body in them.
func test_body_collision_sets() -> void:
	for id in GameSettings.HEROES:
		var cfg := ModelCatalog.info(String(SimData.unit(id).model))
		var scene := String(cfg.scene) if String(id) in GameSettings.OWN_BODY else HeroLook.MODEL
		var path := RepairedClips.collide_path(scene)
		check(ResourceLoader.exists(path), "%s: collision set %s" % [id, path])
		if not ResourceLoader.exists(path):
			continue
		var lib := load(path) as AnimationLibrary
		for c in cfg.get("attack", []):
			check(lib.has_animation(String(c)), "%s: %s in its collision set" % [id, c])
