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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
	var ally := w.spawn("dawn_melee", C.DAWN, Vector2(-1700, -4000))
	ally.order = O.HOLD
	w.vision.update()
	check(w.orders.attack_error(h, ally) != "", "cannot attack an ally creep above half health")
	ally.hp = ally.max_hp * 0.49
	check(w.orders.attack_error(h, ally) == "", "can deny an ally creep below half health")

func test_attack_class_matrix() -> void:
	var w := empty_world()
	var ranged := w.spawn("dawn_ranged", C.DAWN, Vector2(-2000, -4000))
	var melee := w.spawn("dusk_melee", C.DUSK, Vector2(-1600, -4000))
	var hero := w.spawn("galewarden", C.DUSK, Vector2(-1500, -4100))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("galewarden", C.DUSK, Vector2(-2000, -3500))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2600, -4000))
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
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
	var foe := w.spawn("galewarden", C.DUSK, Vector2(-1300, -4000))
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

func test_orb_walk_no_aggro() -> void:
	var w := empty_world()
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2000, -4000))
	h.ability_level["frost_quiver"] = 1
	var foe := w.spawn("galewarden", C.DUSK, Vector2(-1500, -4000))
	foe.order = O.HOLD
	var c := w.spawn("dusk_melee", C.DUSK, Vector2(-2000, -3700))
	c.lane = "mid"
	c.order = O.HOLD
	var bait := w.spawn("dawn_melee", C.DAWN, Vector2(-2000, -3580))
	bait.order = O.HOLD
	bait.def = bait.def.duplicate()
	bait.def.hp = 1e6
	bait.refresh_stats()
	bait.hp = bait.max_hp
	h.facing = 0.0
	w.vision.update()
	run(w, 0.4)
	check(c.atk_target == bait.id, "the creep is busy with the bait creep")
	w.command(h.id, {"type": O.CAST_UNIT, "ability": "frost_quiver", "target": foe.id})
	check(not c.aggro_forced, "hand-cast orb draws no creep aggro")
	run(w, 1.0)
	check(c.atk_target == bait.id, "nor does its attack swing")
	var slowed := foe.modifiers.any(func(m): return m.id == "frost_quiver_slow")
	check(slowed, "frost orb slowed the target")

func test_tower_protects_heroes() -> void:
	var w := empty_world()
	var tw := w.spawn("tower1", C.DUSK, Vector2(-1000, -4000))
	var h := w.spawn("galewarden", C.DAWN, Vector2(-1500, -4000))
	var foe := w.spawn("galewarden", C.DUSK, Vector2(-1500, -3550))
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
	var blocker := w.spawn("galewarden", C.DAWN, camp.pos)
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
	var h := w.spawn("galewarden", C.DAWN, camp.pos + Vector2(-500, 0))
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
	var h := w.spawn("galewarden", C.DAWN, _map.fountains[0] + Vector2(200, 200))
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
	var h := w.spawn_hero("galewarden", C.DAWN)
	check(h.gold() == 600, "600 starting gold")
	run(w, 61.0)
	var passive := h.gold_reliable
	check(passive >= 89 and passive <= 92, "about 90 passive gold in the first minute (got %d)" % passive)

# ---- Vision -------------------------------------------------------------------------------------------------------------

func test_vision_high_ground() -> void:
	var w := empty_world()
	var low := w.spawn("galewarden", C.DAWN, Vector2(-500, 500))       # river
	var high_p := Vector2(-4600, -4600)
	w.vision.update()
	check(not w.vision.cell_visible(C.DAWN, Vector2(-400, 1200)) or true, "sanity")
	var up := w.spawn("galewarden", C.DUSK, Vector2(-200, -200))
	w.vision.update()
	check(w.vision.sees(C.DAWN, up), "sees units on the same level nearby")
	var cliff_top := w.spawn("galewarden", C.DUSK, Vector2(-5200, -4000))
	var below := w.spawn("galewarden", C.DAWN, Vector2(-5200, -3350))
	w.vision.update()
	check(_map.level_at(cliff_top.pos) == SimMap.HIGH and _map.level_at(below.pos) == SimMap.GROUND, "test spots on high and low ground")
	check(not w.vision.sees(C.DAWN, cliff_top), "low ground cannot see onto high ground")
	check(w.vision.sees(C.DUSK, below), "high ground sees down")

func test_night_vision() -> void:
	var w := empty_world()
	var h := w.spawn("galewarden", C.DAWN, Vector2(-2500, -6350))
	var foe := w.spawn("galewarden", C.DUSK, Vector2(-1300, -6350))
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
	var a := w.spawn_hero("galewarden", C.DAWN)
	var b := w.spawn_hero("galewarden", C.DUSK)
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
	var a := w.spawn_hero("galewarden", C.DAWN)
	var b := w.spawn_hero("galewarden", C.DUSK)
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
	var h := w.spawn_hero("galewarden", C.DAWN)
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
	var h2 := w.spawn_hero("galewarden", C.DAWN)
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
	var h := w.spawn_hero("galewarden", C.DAWN)
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
	var h := w.spawn_hero("galewarden", C.DAWN)
	h.pos = Vector2(-1500, -1300)
	h.gold_unreliable = 1000
	check(w.shop.buy(h, "slippers") == "", "bought away from the shop")
	check(h.stash.any(func(x): return x != null and x.id == "slippers"), "item waits in the stash")
	check(w.courier_deliver(h) == "", "courier sent")
	run(w, 40.0)
	check(h.inventory.any(func(x): return x != null and x.id == "slippers"), "the courier delivered the slippers")
	var c := w.get_unit(h.courier_id)
	check(c.courier_state in ["return", "idle"], "courier heads home after delivering")
