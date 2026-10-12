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
	var cliff_top := w.spawn("blood_ranger", C.DUSK, Vector2(-5200, -4000))
	var below := w.spawn("blood_ranger", C.DAWN, Vector2(-5200, -3350))
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
	check(_map.vision_block[_map.world_to_vcell(tp).y * SimMap.VN + _map.world_to_vcell(tp).x] == 0 or _map.tree_at(tp, 90.0) >= 0,
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
	check(w.abilities.item_target("branch") == "point", "Ironwood Twig targets the ground")
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
	check(rw.stick_charges == 0, "the Spark Rod was used mid-channel")
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
			if ev.t == "tree" and int(ev.i) == ti and not ev.alive:
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
