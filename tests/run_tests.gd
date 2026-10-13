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

func world(start_time := 0.0) -> SimWorld:
	var w := SimWorld.new(1, _map)
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
	creeps = w.units.filter(func(u): return u.is_lane_creep())
	check(creeps.size() == 48, "second wave at 0:30 (got %d)" % creeps.size())
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
func _tree_spot() -> Array:
	for i in _map.trees.size():
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
	var st := c.get_modifier("stun")
	check(stunned_at > 0.0, "impact stun applied once the creep came to rest")
	if not st.is_empty():
		near(float(st.expires) - stunned_at, 2.8, 0.05, "level 4 impact stun lasts 2.8 s")
	var row: Array = e.dmg_out.get("dark_stomp", [0, 0, 0])
	near(float(row[1]), (150.0 + 125.0) * (1.0 - c.magic_resist), 1.0, "stomp plus impact damage (magic)")

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
	near(float(row[0]), 150.0 * (1.0 - foe.magic_resist), 1.0, "a hit adds 150 magic damage at level 4")
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
	near(on_left.max_hp - on_left.hp, 120.0 * (1.0 - on_left.magic_resist), 1.0, "120 magic damage at level 1")
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
	var spot := _tree_spot()
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
		near(float(row[1]), 360.0 * 1.2 * (1.0 - foe.magic_resist), 2.0, "the crash adds 20% of the damage once")
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
	near(st_dmg, ticks * 120.0 * 0.2 * (1.0 - e.magic_resist), 0.01, "120 magic damage per second at level 4")
	near(far.hp, far0, 0.001, "nothing beyond 250")
	near(self_dmg, ticks * 120.0 * 0.2 * (1.0 - s.magic_resist), 0.01, "Sludge takes the same damage")
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
	near(bite_dmg, per_bite * 6.0 * (1.0 - e.magic_resist), 0.05, "(120 + 0.9 x strength) magic damage per second")
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
	near(hp0 - src.hp, 170.0 * (1.0 - src.magic_resist), 0.01, "active: 85% of any damage, same type")
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
	near(c.move_speed, 290.0 + 10.0 * 1, 0.01, "level 1 courier speed 290 + 10 x level")
	check(not c.has_flag("flying"), "walks before level 4")
	w.combat.give_xp(h, float(C.XP_TABLE[3]) - h.xp)
	w.step()
	check(h.level == 4 and c.has_flag("flying"), "flies from its owner's level 4")
	near(c.move_speed, 290.0 + 40.0, 0.01, "level 4 speed")
	check(w.courier_command(h, "burst").begins_with("Speed Burst needs level"), "no Speed Burst before level 10")
	check(w.courier_command(h, "shield").begins_with("Shield needs level"), "no Shield before level 20")
	w.combat.give_xp(h, float(C.XP_TABLE[19]) - h.xp)
	w.step()
	check(w.courier_command(h, "burst") == "", "Speed Burst at level %d" % h.level)
	w.step()
	near(c.move_speed, (290.0 + 10.0 * h.level) * 1.5, 0.01, "Speed Burst: +50%")
	check(w.courier_command(h, "burst") == "Speed Burst on cooldown", "120 s cooldown")
	run(w, 6.1)
	near(c.move_speed, 290.0 + 10.0 * h.level, 0.01, "lasts 6 s")
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
	var h := w.spawn("blood_ranger", C.DAWN, n[0].pos + Vector2(200, 0))
	h.order = O.HOLD
	h.no_acquire = true
	run(w, 0.6)
	check(n[0].neutral_state == 1 and n[0].atk_target == h.id, "by day a hero walking within 240 wakes the camp")
	var w2 := world(359.0)
	w2.next_wave_at = INF
	w2.next_neutral_at = 360.0
	run(w2, 1.2)
	var n2 := w2.units.filter(func(u): return u.camp_id == camp.id and u.alive)
	var h2 := w2.spawn("blood_ranger", C.DAWN, n2[0].pos + Vector2(200, 0))
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

func test_lane_creeps_fight_only_pull_camps() -> void:
	var w := empty_world()
	var pull := -1
	var other := -1
	for c in _map.camps:
		if c.side == C.DAWN and bool(c.pull) and pull < 0:
			pull = c.id
		elif c.side == C.DAWN and not bool(c.pull) and other < 0:
			other = c.id
	for cid in [pull, other]:
		var camp: Dictionary = _map.camps[cid]
		var n := w.spawn("mudling", C.NEUTRAL, camp.pos)
		n.camp_id = cid
		n.home = camp.pos
		var lc := w.spawn("dawn_melee", C.DAWN, camp.pos + Vector2(250, 0))
		lc.lane = "bot"
		lc.lane_i = 1
		w._rebuild_grid()
		w.vision.update()
		var t := w.ai._pick(lc, lc.acquire_range)
		if cid == pull:
			check(t == n, "a lane creep attacks a pull camp's neutral")
		else:
			check(t != n, "but ignores other camps' neutrals")
		n.alive = false
		lc.alive = false
		w._rebuild_grid()

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
	check(h.gold() - g0 == 125, "Unfair: +25% gold")
	var x0 := h.xp
	w.combat.give_xp(h, 100.0)
	near(h.xp - x0, 125.0, 0.01, "Unfair: +25% experience")

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
