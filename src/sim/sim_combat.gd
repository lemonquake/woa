class_name SimCombat
extends RefCounted
## Attacks landing, projectiles, damage (attack classes, armor, magic resistance, backdoor protection, glyph),
## death and its rewards: last-hit gold, denies, experience sharing, hero kill and assist gold, building bounties.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

var w: SimWorld
var _deaths: Array = []                    # [{u, killer}]
var _next_proj := 1

func _init(world: SimWorld = null) -> void:
	w = world

# ---- Attacks ----------------------------------------------------------------------------------------------------------

## The attack point was reached: melee attacks land now, ranged attacks launch a projectile.
func release_attack(u: SimUnit, t: SimUnit, mod: String) -> void:
	var snap := _snapshot(u, mod)
	if u.is_hero():
		var sn := w.items.break_sneak(u)
		snap["sneak"] = float(sn.get("bonus", 0.0))
		snap["sneak_break"] = float(sn.get("break", 0.0))
	if mod != "":
		w.abilities.pay_attack_modifier(u, mod)
	if u.is_hero():
		snap["burst"] = w.abilities.masterful_bonus(u, t)
		if w.abilities.frost_heart_spend(u, t):
			snap["frost"] = true
	if u.is_ranged():
		var p := {"id": _next_proj, "src": u.id, "target": t.id, "pos": u.pos + Vector2.from_angle(u.facing) * u.hull,
			"speed": float(u.def.projectile_speed), "snap": snap, "kind": "attack", "model": u.def.model, "mod": mod}
		_next_proj += 1
		w.projectiles.append(p)
		w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": t.id, "kind": "attack", "mod": mod,
			"burst": float(snap.get("burst", 0.0)) > 0.0, "frost": bool(snap.get("frost", false))})
		# glyph: tier 2+ towers also fire at extra nearby enemies
		if u.kind == K.TOWER and u.lane_tier >= 2 and w.time < u.glyph_until:
			_glyph_multishot(u, t, snap)
	else:
		land_attack(snap, t)

func _glyph_multishot(u: SimUnit, main: SimUnit, snap: Dictionary) -> void:
	var n := 0
	for o: SimUnit in w.query(u.pos, u.attack_range + 200.0, true):
		if n >= C.GLYPH_EXTRA_TARGETS:
			break
		if o == main or o.team == u.team or o.is_building() or o.is_ward() or not w.vision.sees(u.team, o):
			continue
		if u.edge_distance(o) > u.attack_range:
			continue
		var p := {"id": _next_proj, "src": u.id, "target": o.id, "pos": u.pos, "speed": float(u.def.projectile_speed),
			"snap": snap, "kind": "attack", "model": u.def.model, "mod": ""}
		_next_proj += 1
		w.projectiles.append(p)
		w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": o.id, "kind": "attack", "mod": ""})
		n += 1

## An attack snapshot for an ability that strikes with the unit's attack (Swift Dagger's stab).
func attack_snapshot(u: SimUnit, mod: String) -> Dictionary:
	return _snapshot(u, mod)

## What an attack carries, fixed at launch (the attacker may die before it lands).
func _snapshot(u: SimUnit, mod: String) -> Dictionary:
	return {"src": u.id, "team": u.team, "hero": u.is_hero(), "kind": u.kind, "dmg_min": u.dmg_min, "dmg_max": u.dmg_max,
		"bonus": u.bonus_damage, "class": u.weapon, "element": u.element, "level_h": w.map.level_at(u.pos), "mod": mod,
		"lifesteal": u.lifesteal, "lifesteal_ab": u.lifesteal_ability, "ranged": u.is_ranged(), "quell": _quelling(u),
		"taint": _taint(u), "crit": u.atk_crit, "out_pct": u.attack_out_pct, "flying": bool(u.def.flying)}

## A spell arrow (Burst Shot): a projectile that homes on `t`, or flies to `spot` when t is null, and deals `dmg`
## physical spell damage (no lifesteal, cannot miss; Dota's rule for spells).
func launch_spell_arrow(u: SimUnit, t: SimUnit, spot: Vector2, dmg: float, speed: float, key: String) -> void:
	var p := {"id": _next_proj, "src": u.id, "team": u.team, "target": t.id if t else -1, "point": spot,
		"pos": u.pos + Vector2.from_angle(u.facing) * u.hull, "speed": speed, "kind": "spell", "dmg": dmg, "key": key}
	_next_proj += 1
	w.projectiles.append(p)
	w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": p.target, "kind": "spell", "key": key,
		"point": spot})

## An item's effect carried by a homing projectile (Root Staff): on arrival it applies debuff `m` from `u` unless the
## target became immune or invulnerable meanwhile.
func launch_effect(u: SimUnit, t: SimUnit, speed: float, key: String, m: Dictionary) -> void:
	var p := {"id": _next_proj, "src": u.id, "team": u.team, "target": t.id, "point": t.pos,
		"pos": u.pos + Vector2.from_angle(u.facing) * u.hull, "speed": speed, "kind": "effect", "key": key, "mod": m}
	_next_proj += 1
	w.projectiles.append(p)
	w.events.append({"t": "projectile", "id": p.id, "src": u.id, "target": t.id, "kind": "effect", "key": key})

## Tainted Touch: the level of the enchantment riding on this attack (0 = none), fixed when the blow is released.
func _taint(u: SimUnit) -> int:
	var m := u.get_modifier("tainted_touch")
	return int(m.get("tainted", 0)) if not m.is_empty() else 0

func _quelling(u: SimUnit) -> float:
	if not u.is_hero():
		return 0.0
	# Mini-Axe or Cleave Axe: bonus damage against creeps (the larger one; they do not stack)
	var best := 0.0
	for i in 6:
		var it = u.inventory[i]
		if it != null and SimData.item(it.id).values.has("creep_damage_melee"):
			var v: Dictionary = SimData.item(it.id).values
			best = maxf(best, float(v.creep_damage_ranged if u.is_ranged() else v.creep_damage_melee))
	return best

## Disjoint (Dota 2 wiki, Disjoint): projectiles flying at `u` lose track of it and fall where it stood. Caused by a
## blink (Jump Knife), a teleport, and turning invisible.
func disjoint(u: SimUnit) -> void:
	for p in w.projectiles:
		if int(p.get("target", -1)) == u.id and not p.has("lost"):
			p["lost"] = true
			p["point"] = u.pos
	w.events.append({"t": "disjoint", "u": u.id})

func update_projectiles() -> void:
	for i in range(w.projectiles.size() - 1, -1, -1):
		var p: Dictionary = w.projectiles[i]
		if p.has("lost"):
			# disjointed: it flies on to where its target was and misses
			var lto: Vector2 = (p.point as Vector2) - p.pos
			var lstep: float = p.speed * C.DT
			if lto.length() > lstep:
				p.pos += lto.normalized() * lstep
				continue
			w.projectiles.remove_at(i)
			w.events.append({"t": "projectile_end", "id": p.id, "hit": false, "miss": true, "pos": p.point,
				"ground": true})
			continue
		if p.kind == "spell":
			_update_spell_arrow(i, p)
			continue
		if p.kind == "effect":
			_update_effect(i, p)
			continue
		var t := w.get_unit(p.target)
		if t == null or not t.alive:
			# the target died first: the projectile flies on to where it was and falls there (presentation only)
			w.projectiles.remove_at(i)
			w.events.append({"t": "projectile_end", "id": p.id, "hit": false, "pos": t.pos if t else p.pos})
			continue
		var to: Vector2 = t.pos - p.pos
		var step: float = p.speed * C.DT
		if to.length() <= step + t.hull * 0.5:
			w.projectiles.remove_at(i)
			var landed := land_attack(p.snap, t)
			w.events.append({"t": "projectile_end", "id": p.id, "hit": landed, "miss": not landed, "pos": t.pos,
				"target": t.id})
		else:
			p.pos += to.normalized() * step

func _update_effect(i: int, p: Dictionary) -> void:
	var t := w.get_unit(int(p.target))
	if t == null or not t.alive:
		w.projectiles.remove_at(i)
		w.events.append({"t": "projectile_end", "id": p.id, "hit": false, "pos": p.pos})
		return
	var to: Vector2 = t.pos - p.pos
	var step: float = p.speed * C.DT
	if to.length() > step + t.hull * 0.5:
		p.pos += to.normalized() * step
		return
	w.projectiles.remove_at(i)
	var m: Dictionary = (p.mod as Dictionary).duplicate()
	var hit := w.status.apply(t, int(p.src), int(p.team), m)
	w.events.append({"t": "projectile_end", "id": p.id, "hit": hit, "pos": t.pos, "target": t.id})
	if hit:
		w.events.append({"t": "item_debuff", "u": int(p.src), "target": t.id, "kind": String(p.key)})

func _update_spell_arrow(i: int, p: Dictionary) -> void:
	var t := w.get_unit(int(p.target))
	var goal: Vector2 = t.pos if t != null and t.alive else p.point
	if t != null and t.alive:
		p.point = t.pos
	var to: Vector2 = goal - p.pos
	var step: float = p.speed * C.DT
	if to.length() > step + (t.hull * 0.5 if t != null and t.alive else 0.0):
		p.pos += to.normalized() * step
		return
	w.projectiles.remove_at(i)
	var hit := t != null and t.alive and not t.is_invulnerable()
	if hit:
		deal_damage(int(p.src), int(p.team), true, t, float(p.dmg), C.DamageType.PHYSICAL, false, String(p.key))
	w.events.append({"t": "projectile_end", "id": p.id, "hit": hit, "pos": goal, "target": int(p.target), "ground": not hit})

## An attack connects: miss chance (evasion, uphill), damage (critical strike, bash), lifesteal and attack modifiers.
## False on a miss. Order (Dota 2 wiki: Evasion, Critical Strike, Bash): true strike, then evasion and the uphill miss;
## the critical multiplier (rolled when the attack started) scales the attack damage and the creep bonus; bash damage
## is added after it and is not multiplied; armor and the attack class apply to the sum.
func land_attack(s: Dictionary, t: SimUnit) -> bool:
	if not t.alive:
		return false
	var src := w.get_unit(s.src)
	var pierce := w.items.roll_pierce(s, t)            # Spear, Sure Hit Staff: cannot miss (not against buildings)
	if pierce.is_empty() and _evaded(s, t):
		w.events.append({"t": "miss", "u": s.src, "target": t.id, "ranged": bool(s.ranged)})
		return false
	var crit := float(s.get("crit", 1.0))
	var dmg: float = w.rng.randf_range(s.dmg_min, s.dmg_max) + float(s.bonus)
	if t.is_creep() and t.team != s.team:
		dmg += float(s.quell)
	dmg *= crit
	dmg += float(s.get("burst", 0.0)) + float(s.get("sneak", 0.0))
	if s.mod != "":
		dmg += w.abilities.attack_modifier_damage(s, t)
	var bash := w.items.roll_bash(s, t)
	if not bash.is_empty():
		dmg += float(bash.damage)
	dmg *= maxf(0.0, 1.0 + float(s.get("out_pct", 0.0)))
	var base_dmg := dmg                            # before the weapon / armor type and element (cleave uses this)
	dmg *= attack_class_multiplier(s, t)
	if crit > 1.0:
		# Dota shows the critical number in red before the target's reductions
		w.events.append({"t": "crit", "u": s.src, "target": t.id, "amount": dmg, "mult": crit})
	# Death Order: Caziel's blow on an enemy about to die is pure damage
	var dtype := _attack_dtype(s)
	var executes := w.abilities.death_order(s, t)
	if executes:
		dtype = C.DamageType.PURE
		w.events.append({"t": "death_order", "u": s.src, "target": t.id})
	var dealt := deal_damage(s.src, s.team, bool(s.hero), t, dmg, dtype, true, "attack", false,
		{"element": int(s.get("element", 0)), "element_done": true})
	# lifesteal heals from the blow after armor (not after other damage manipulation, and in full even when the blow
	# kills); item lifesteal heals 40% against creeps; never from buildings or wards
	var ls := float(s.lifesteal) * (C.ITEM_LIFESTEAL_CREEP_FACTOR if t.is_creep() else 1.0) + float(s.get("lifesteal_ab", 0.0))
	if dealt > 0.0 and ls > 0.0 and src != null and src.alive and not t.is_building() and not t.is_ward():
		var before := src.hp
		heal(src, dmg * C.armor_multiplier(t.armor) * ls)
		if src.hp - before >= 1.0:
			w.events.append({"t": "lifesteal", "u": src.id, "target": t.id, "amount": src.hp - before})
	if not bash.is_empty() and t.alive:
		# the bash stun pierces debuff immunity; bashes share one modifier and refresh to the longer time
		if w.status.apply(t, s.src, s.team, {"id": "bashed", "stun": true, "dur": float(bash.dur), "fx": "stun"}, true):
			w.events.append({"t": "bash", "u": s.src, "target": t.id, "dur": float(bash.dur), "item": String(bash.item)})
	if float(s.get("burst", 0.0)) > 0.0:
		w.events.append({"t": "masterful_hit", "u": s.src, "target": t.id, "amount": float(s.burst)})
	if s.mod != "" and t.alive:
		w.abilities.attack_modifier_hit(s, t)
	if int(s.get("taint", 0)) > 0 and not t.is_building() and t.team != s.team:
		w.abilities.tainted_hit(s, t)
	if bool(s.get("frost", false)) and t.alive:
		w.abilities.frost_heart_hit(s, t)
	if bool(s.hero) and t.alive:
		w.abilities.sweet_poison_hit(s, t)
	if bool(s.hero) and t.alive and not t.is_building() and not t.is_ward() and t.team != s.team:
		w.abilities.kits2.on_attack_landed(s, t)
	if bool(s.hero):
		w.items.on_attack_landed(s, t, base_dmg, pierce)
	elif src != null and src.alive:
		w.ai.on_creep_hit(src, t, base_dmg)
	if t.alive and t.is_hero() and src != null:
		w.abilities.on_attacked(t, src)
	return true

## Evasion and the uphill miss, each its own pseudo-random roll: the target's evasion (its sources multiplied), then
## for ranged attacks from lower ground (not flying attackers) the 25% uphill miss.
func _evaded(s: Dictionary, t: SimUnit) -> bool:
	if t.is_building():
		return false
	if t.evasion > 0.0 and w.status.roll(t, "evasion", t.evasion):
		return true
	if bool(s.ranged) and not bool(s.get("flying", false)) and int(s.level_h) < w.map.level_at(t.pos):
		var src := w.get_unit(s.src)
		if src != null:
			return w.status.roll(src, "uphill", C.UPHILL_MISS)
		return w.rng.randf() < C.UPHILL_MISS
	return false

## The critical strike multiplier for an attack `u` starts on `t` (1 = none). Sources roll from the strongest
## multiplier down and stop at the first proc, so two never stack and weaker ones keep their pseudo-random counters.
## Never against buildings or wards (and no roll is counted there).
func roll_crit(u: SimUnit, t: SimUnit) -> float:
	if t == null or t.is_building() or t.is_ward():
		return 1.0
	var srcs := crit_sources(u)
	if srcs.is_empty():
		return 1.0
	srcs.sort_custom(func(x, y): return float(x.mult) > float(y.mult))
	for c in srcs:
		if w.status.roll(u, "crit:" + String(c.key), float(c.chance)):
			return float(c.mult)
	return 1.0

## Every critical strike source a unit has: items (one roll per kind of item) and its own passive (the Alpha Wolf's;
## off while broken).
func crit_sources(u: SimUnit) -> Array:
	var out: Array = []
	var seen := {}
	if u.is_hero():
		for i in mini(6, u.inventory.size()):
			var it = u.inventory[i]
			if it == null or seen.has(it.id):
				continue
			var d := SimData.item(it.id)
			if String(d.get("passive", "")) == "crit":
				seen[it.id] = true
				out.append({"key": it.id, "chance": float(d.values.crit_chance), "mult": float(d.values.crit_mult)})
	var own: Dictionary = u.def.get("crit", {})
	if not own.is_empty() and not u.is_broken():
		out.append({"key": "own", "chance": float(own.chance), "mult": float(own.mult)})
	return out

## An attack's multiplier against `t`: its weapon against the target's armor type (SimConst.DAMAGE_TABLE), times its
## element against the target's element. s: an attack snapshot, or {class: weapon, element} (bots' estimates).
func attack_class_multiplier(s: Dictionary, t: SimUnit) -> float:
	return C.damage_mult(int(s.get("class", 0)), t.armor_type) * element_mult(int(s.get("element", 0)), t.element)

## SimConst.element_mult, or 1 when the world plays without elements (some mechanics tests).
func element_mult(atk: int, def: int) -> float:
	return C.element_mult(atk, def) if w.elements else 1.0

## Attacks with the Magic weapon (Fire Imp, Lava Golem) deal magic damage; every other attack is physical.
func _attack_dtype(s: Dictionary) -> int:
	return C.DamageType.MAGICAL if int(s.get("class", 0)) == C.Weapon.MAGIC else C.DamageType.PHYSICAL

## The element a damage instance carries: the caller's choice (opts.element), else an attack's or a spell's caster
## (an ability may name its own element), an item's own element, or none.
func damage_element(src: SimUnit, key: String, is_attack: bool, opts: Dictionary) -> int:
	if opts.has("element"):
		return int(opts.element)
	if is_attack or key in ["attack", "splash", "cleave_axe"]:
		return src.element if src != null else C.Element.NONE
	var a := SimData.ability(key)
	if not a.is_empty():
		if a.has("element"):
			return C.element_of(String(a.element))
		return src.element if src != null else C.Element.NONE
	var it := SimData.item(key)
	if not it.is_empty():
		return C.element_of(String(it.get("element", "none")))
	return src.element if src != null else C.Element.NONE

## The weapon row a damage instance uses: attacks their own (applied in land_attack), magic damage Magic, pure
## damage Aether. Physical spell damage uses no row (armor still reduces it), as in Dota.
static func damage_row(dtype: int) -> int:
	match dtype:
		C.DamageType.MAGICAL:
			return C.Weapon.MAGIC
		C.DamageType.PURE:
			return C.Weapon.AETHER
	return -1

# ---- Damage ---------------------------------------------------------------------------------------------------------------

## Apply damage after armor / magic resistance and building protections. Returns the health removed.
## key names the source for the damage tables ("attack", an ability or item id); reflected damage is not reflected again.
## opts: ignore_armor (cleave), non_lethal (Stench on its owner), no_spell_lifesteal.
func deal_damage(src_id: int, src_team: int, src_hero: bool, t: SimUnit, amount: float, dtype: int, is_attack := false,
		key := "", reflected := false, opts := {}) -> float:
	if not t.alive or amount <= 0.0:
		return 0.0
	if t.is_invulnerable():
		return 0.0
	if w.time < t.glyph_until:
		w.events.append({"t": "damage", "u": t.id, "src": src_id, "amount": 0.0, "blocked": true})
		return 0.0
	if key == "":
		key = "attack" if is_attack else "spell"
	var src0 := w.get_unit(src_id)
	# spell amplification raises every non-attack damage its source deals (not returned or attack-derived damage);
	# magic amp (intelligence and items) adds to it for magic damage
	if not is_attack and not reflected and not opts.get("no_amp", false) and src0 != null:
		var amp := src0.spell_amp + (src0.magic_amp if dtype == C.DamageType.MAGICAL else 0.0)
		if amp != 0.0:
			amount *= 1.0 + amp
	# the element: x1.25 when it beats the target's, x0.75 when it is beaten (an attack applied it already)
	var elem := damage_element(src0, key, is_attack, opts)
	var emult := element_mult(elem, t.element)
	if not opts.get("element_done", false):
		amount *= emult
	# armor type against the damage type (magic and pure rows; attacks applied their weapon row already)
	if not is_attack:
		var row := damage_row(dtype)
		if row >= 0:
			amount *= C.damage_mult(row, t.armor_type)
	if t.kind == K.COURIER:
		# couriers count hits, not damage (7.35): 1 melee hero attack, 2 ranged hero attacks, 6 of anything else
		var src_u := w.get_unit(src_id)
		var hits := 1.0
		if is_attack and src_hero and src_u != null:
			hits = 6.0 if not src_u.is_ranged() else 3.0
		t.hp = maxf(0.0, t.hp - hits)
		w.events.append({"t": "damage", "u": t.id, "src": src_id, "amount": hits, "type": dtype, "attack": is_attack,
			"key": key, "reflected": reflected, "halved": 0.0})
		if t.hp <= 0.001:
			kill(t, src_u)
		return hits
	var raw := amount                                  # before any reduction (Spike Armor returns this)
	if is_attack and dtype == C.DamageType.PHYSICAL and (t.is_hero() or t.has_flag("team_guard_on")) and src_team != t.team:
		amount = w.items.block_attack(t, amount)       # Block Shield, before armor
	match dtype:
		C.DamageType.PHYSICAL:
			if not opts.get("ignore_armor", false):
				amount *= C.armor_multiplier(t.armor)
		C.DamageType.MAGICAL:
			if t.is_building():
				return 0.0
			amount *= 1.0 - t.magic_resist
	# Ice Pulse: lowered defense, so physical and magic damage hit harder (armor and resistances count less)
	if dtype != C.DamageType.PURE and not t.modifiers.is_empty():
		var loss := t.defense_loss()
		if loss > 0.0:
			amount *= 1.0 + loss
	if t.is_building() and t.backdoor_active and src_team != t.team:
		amount *= 1.0 - C.BACKDOOR_DAMAGE_REDUCTION
		t.backdoor_pool += amount
	# Unholy Might: a chance to halve the blow and send the other half into a random nearby enemy
	var reflect_to: SimUnit = null
	var reflect_amt := 0.0
	if not reflected and src_team != t.team:
		var um := t.get_modifier("unholy_might")
		if not um.is_empty() and amount > 0.5 and w.status.roll(t, "unholy_might", float(um.chance)):
			reflect_amt = amount * 0.5
			amount -= reflect_amt
			reflect_to = w.abilities.unholy_victim(t, float(um.radius))
	# flat damage negation on every instance after reductions (Blubber), from any source
	var blk := t.damage_block()
	if blk > 0.0:
		amount = maxf(0.0, amount - blk)
	# Stealth Orb resistance and the Shield Orb's barrier
	if t.is_hero():
		amount = w.orbs.absorb(t, amount, src_hero)
	if opts.get("non_lethal", false):
		amount = clampf(amount, 0.0, maxf(0.0, t.hp - 1.0))
	amount = minf(amount, t.hp)
	t.hp -= amount
	w.status.on_damage(t, amount)
	var src := w.get_unit(src_id)
	# spell lifesteal: heals from spell damage dealt to enemies (100% from heroes, 20% from creeps)
	if src != null and src.alive and src != t and not is_attack and not reflected and src.spell_lifesteal > 0.0 \
			and src_team != t.team and amount > 0.0 and not opts.get("no_spell_lifesteal", false) \
			and not t.is_building() and not t.is_ward():
		heal(src, amount * src.spell_lifesteal * (1.0 if t.is_hero() else 0.2))
	_ledger(src, t, key, dtype, amount, src_id)
	if src != null and src.is_hero() and src != t and src.ability_level_of("frost_heart") > 0:
		w.abilities.frost_heart_charge(src, t, amount)
	if src_hero and t.is_hero() and src_team != t.team:
		t.hero_damage_log[src_id] = w.time
	if t.is_hero() and src_hero and src_team != t.team:
		for i in range(t.modifiers.size() - 1, -1, -1):
			if t.modifiers[i].get("break_on_damage", false):
				t.modifiers.remove_at(i)
				t.stats_dirty = true
	# neutrals wake up and fight back when hurt
	if t.kind == K.NEUTRAL_CREEP and src != null:
		w.ai.neutral_provoked(t, src)
	w.events.append({"t": "damage", "u": t.id, "src": src_id, "amount": amount, "type": dtype, "attack": is_attack,
		"key": key, "reflected": reflected, "halved": reflect_amt, "element": elem, "emult": emult})
	if not reflected and (t.is_hero() or not t.get_modifier("static_charge").is_empty()):
		w.items.on_damaged(t, src, raw, dtype, is_attack, elem)
	if t.hp <= 0.001:
		t.hp = 0.0
		kill(t, src)
	if reflect_amt > 0.0:
		w.events.append({"t": "unholy_reflect", "u": t.id, "target": reflect_to.id if reflect_to else -1, "amount": reflect_amt})
		if reflect_to != null and reflect_to.alive:
			deal_damage(t.id, t.team, t.is_hero(), reflect_to, reflect_amt, C.DamageType.PURE, false, "unholy_might", true,
				{"element": C.Element.DARK})
	return amount

## Damage tables: what each unit dealt by source, what heroes took by source, and a short history for the death recap.
func _ledger(src: SimUnit, t: SimUnit, key: String, dtype: int, amount: float, src_id: int) -> void:
	if amount <= 0.0:
		return
	if src != null and src != t:
		var row: Array = src.dmg_out.get(key, [0.0, 0.0, 0.0])
		row[0 if t.is_hero() else (2 if t.is_building() else 1)] += amount
		src.dmg_out[key] = row
	if t.is_hero():
		var k2 := (String(src.def.id) if src != null else "?") + ":" + key
		t.dmg_in[k2] = float(t.dmg_in.get(k2, 0.0)) + amount
		t.recent_in.append({"t": w.time, "src": src_id, "key": key, "type": dtype, "amount": amount})
		while not t.recent_in.is_empty() and (w.time - float(t.recent_in[0].t) > 20.0 or t.recent_in.size() > 80):
			t.recent_in.pop_front()

## Restore health, raised by the unit's health restoration amplification and lowered by healing reduction (both
## also scale regeneration and lifesteal, as in Dota). Returns the health actually restored.
func heal(t: SimUnit, amount: float) -> float:
	if not t.alive or amount <= 0.0:
		return 0.0
	amount *= (1.0 + t.heal_amp) * (1.0 - t.heal_reduction())
	var before := t.hp
	t.hp = minf(t.max_hp, t.hp + amount)
	t.healed += t.hp - before
	return t.hp - before

# ---- Death --------------------------------------------------------------------------------------------------------------

func kill(t: SimUnit, killer: SimUnit) -> void:
	if not t.alive:
		return
	t.alive = false
	t.hp = 0.0
	t.death_at = w.time
	t.killer_id = killer.id if killer else -1
	t.moving = false
	t.atk_phase = SimUnit.AtkPhase.NONE
	t.cast_phase = SimUnit.CastPhase.NONE
	t.order = C.Order.NONE
	t.path = PackedVector2Array()
	t.leap = {}
	t.hop = {}
	if not t.channel.is_empty():
		w.orders.cancel_channel(t)
	_deaths.append({"u": t, "killer": killer})

func process_deaths() -> void:
	# corpses are removed from the unit list a few seconds after death
	for u in w.units:
		if not u.alive and not u.removed and not u.is_hero() and u.kind != K.COURIER and w.time - u.death_at > 4.0:
			u.removed = true
	while not _deaths.is_empty():
		var d: Dictionary = _deaths.pop_front()
		var t: SimUnit = d.u
		var killer: SimUnit = d.killer
		var deny := killer != null and killer.team == t.team
		w.events.append({"t": "death", "u": t.id, "killer": killer.id if killer else -1, "deny": deny})
		if t.is_hero():
			w.abilities.on_hero_death(t, killer, null if deny else kill_credit(t, killer))
			w.items.on_hero_death(t, killer)
			_hero_death(t, killer)
		elif t.kind == K.COURIER:
			# it keeps what it carries (out of reach until it respawns); every enemy hero gets the bounty. Its level is
			# its owner's.
			var owner := w.get_unit(t.owner_id)
			var lvl := owner.level if owner else t.level
			t.respawn_at = w.time + C.COURIER_RESPAWN_BASE + C.COURIER_RESPAWN_PER_LEVEL * lvl
			t.removed = false
			t.courier_state = "idle"
			if killer != null and killer.team != t.team:
				for eh in w.heroes:
					if eh.team == killer.team:
						give_gold(eh, C.COURIER_BOUNTY_BASE + C.COURIER_BOUNTY_PER_LEVEL * lvl, false, t.pos)
		elif t.is_creep():
			_creep_death(t, killer, deny)
		elif t.is_building():
			_building_death(t, killer, deny)

func _creep_death(t: SimUnit, killer: SimUnit, deny: bool) -> void:
	var hero_killer := killer if killer != null and killer.is_hero() else null
	if deny:
		if hero_killer:
			hero_killer.denies += 1
			w.events.append({"t": "deny", "u": hero_killer.id, "target": t.id})
		_share_xp(t, _xp_value(t) * C.DENY_XP_FACTOR, _enemy_team_of(t, killer))
		return
	if hero_killer and hero_killer.team != t.team:
		var g := w.rng.randi_range(int(t.def.gold_min), int(t.def.gold_max)) + int(t.bounty_gold_add)
		if t.stacked:
			# a stack's new creeps give 20% less; the stacker gets 30% of what an ally earned
			g = int(round(g * (1.0 - C.STACK_BOUNTY_PENALTY)))
			var st := w.get_unit(t.stacker_id)
			if st != null and st != hero_killer and st.team == hero_killer.team:
				give_gold(st, int(round(g * C.STACKER_SHARE)), false, st.pos)
				give_xp(st, floorf(_xp_value(t) * C.STACKER_SHARE))
		give_gold(hero_killer, g, false, t.pos)
		hero_killer.last_hits += 1
		w.events.append({"t": "last_hit", "u": hero_killer.id, "target": t.id, "gold": g})
	# flagbearers pay their bounty to every enemy hero around them
	if t.kind == K.CREEP_FLAG and killer != null and killer.team != t.team:
		for h in w.heroes:
			if h.alive and h.team != t.team and h.pos.distance_to(t.pos) <= 700.0:
				give_gold(h, int(t.def.gold_min) + 10, false, h.pos)
	_share_xp(t, _xp_value(t), _enemy_team_of(t, killer))

func _xp_value(t: SimUnit) -> float:
	return (float(t.def.xp) + t.bounty_xp_add) * (1.0 - C.STACK_BOUNTY_PENALTY if t.stacked else 1.0)

## Which team's heroes are rewarded with experience for this death.
func _enemy_team_of(t: SimUnit, killer: SimUnit) -> int:
	if t.team == C.NEUTRAL:
		return killer.team if killer != null else -1
	return 1 - t.team

func _share_xp(t: SimUnit, amount: float, team: int, always: SimUnit = null) -> void:
	if team < 0 or amount <= 0.0:
		return
	var near: Array[SimUnit] = []
	for h in w.heroes:
		if h.alive and h.team == team and (h.pos.distance_to(t.pos) <= C.XP_RADIUS or h == always):
			near.append(h)
	if near.is_empty():
		return
	var each := floorf(amount / near.size())
	for h in near:
		give_xp(h, each)

func give_xp(h: SimUnit, amount: float) -> void:
	if amount <= 0.0 or h.level >= C.MAX_LEVEL:
		return
	amount *= h.gain_mult
	h.xp += amount
	w.events.append({"t": "xp", "u": h.id, "amount": amount})
	var lvl := C.xp_level(h.xp)
	while h.level < lvl:
		h.level += 1
		h.ability_points += 1
		h.refresh_stats()
		w.events.append({"t": "level_up", "u": h.id, "level": h.level})

func give_gold(h: SimUnit, amount: int, reliable: bool, at: Vector2) -> void:
	if amount == 0:
		return
	if amount > 0 and h.gain_mult != 1.0:
		amount = int(round(amount * h.gain_mult))
	if reliable:
		h.gold_reliable += amount
	else:
		h.gold_unreliable += amount
	if amount > 0:
		h.gold_earned += amount
	w.events.append({"t": "gold", "u": h.id, "amount": amount, "pos": at})

func _hero_death(t: SimUnit, killer: SimUnit) -> void:
	t.deaths += 1
	t.respawn_at = w.time + float(C.RESPAWN_TIME[t.level - 1])
	var loss := mini(t.gold_unreliable, int(t.networth() / C.DEATH_GOLD_DIVISOR))
	t.gold_unreliable -= loss
	if loss > 0:
		w.events.append({"t": "gold", "u": t.id, "amount": -loss, "pos": t.pos})
	var victim_streak := t.streak
	t.streak = 0
	if killer != null and killer.team == t.team:
		return                                # denied hero: no rewards
	var credit := kill_credit(t, killer)
	var enemy_team := 1 - t.team
	var assisters: Array[SimUnit] = []
	for h in w.heroes:
		if h.team != enemy_team or not h.alive and h != credit:
			continue
		var recent: bool = t.hero_damage_log.has(h.id) and w.time - float(t.hero_damage_log[h.id]) <= C.KILL_TIME_WINDOW
		if h == credit or h.pos.distance_to(t.pos) <= C.ASSIST_RADIUS or recent:
			assisters.append(h)
	var base := C.HERO_KILL_GOLD_BASE + C.HERO_KILL_GOLD_PER_LEVEL * t.level + _streak_gold(victim_streak)
	if credit != null:
		credit.kills += 1
		credit.streak += 1
		var fb := 0
		if not w.first_blood:
			w.first_blood = true
			fb = C.FIRST_BLOOD_GOLD
		give_gold(credit, int(base) + fb, false, t.pos)
		credit.multi_kill = credit.multi_kill + 1 if w.time - credit.last_kill_at <= 18.0 else 1
		credit.last_kill_at = w.time
		w.events.append({"t": "hero_kill", "u": credit.id, "victim": t.id, "first_blood": fb > 0, "streak": credit.streak,
			"multi": credit.multi_kill, "ended_streak": victim_streak, "gold": int(base) + fb})
	else:
		# no hero involved: the kill gold is split among the whole enemy team
		var team_heroes := w.heroes.filter(func(h): return h.team == enemy_team)
		for h in team_heroes:
			give_gold(h, int(base / maxf(1.0, team_heroes.size())), false, h.pos)
		w.events.append({"t": "hero_kill", "u": -1, "victim": t.id, "first_blood": false, "streak": 0, "multi": 0,
			"ended_streak": victim_streak, "killer_unit": killer.id if killer else -1})
	# assist (area) gold, shared equally including the killer
	if not assisters.is_empty():
		var nw_v := 0.0
		var nw_k := 0.0
		for h in w.heroes:
			if h.team == t.team:
				nw_v += h.networth()
			else:
				nw_k += h.networth()
		var f := C.ASSIST_GOLD_BASE + (C.ASSIST_GOLD_SCALING + t.networth() * C.ASSIST_GOLD_NETWORTH) / assisters.size()
		var ratio := clampf(nw_v / maxf(1.0, nw_k), 0.5, 2.0)
		for h in assisters:
			give_gold(h, int(f * ratio), false, h.pos)
			if h != credit:
				h.assists += 1
	# experience: shared by heroes in range; the killer always gets a share
	var xp := C.HERO_KILL_XP_BASE + C.HERO_KILL_XP_FACTOR * t.xp
	_share_xp(t, xp, enemy_team, credit)
	t.hero_damage_log.clear()

## Kill credit: an enemy hero who struck the killing blow, else the last enemy hero to damage the victim recently.
func kill_credit(t: SimUnit, killer: SimUnit) -> SimUnit:
	var credit: SimUnit = killer if killer != null and killer.is_hero() and killer.team != t.team else null
	if credit == null:
		var best_t := -INF
		for hid in t.hero_damage_log:
			var tt: float = t.hero_damage_log[hid]
			if w.time - tt <= C.KILL_TIME_WINDOW and tt > best_t:
				var h := w.get_unit(hid)
				if h != null:
					best_t = tt
					credit = h
	return credit

func _streak_gold(streak: int) -> float:
	if streak < 3:
		return 0.0
	return minf(60.0 * (streak - 2), 480.0)       # APPROX shutdown bounty

func _building_death(t: SimUnit, killer: SimUnit, deny: bool) -> void:
	var key := String(t.def.bounty_key)
	if C.BUILDING_BOUNTY.has(key):
		var b: Array = C.BUILDING_BOUNTY[key]
		if deny:
			for h in w.heroes:
				give_gold(h, int(b[0] * C.TOWER_DENY_FACTOR), false, h.pos)
		else:
			for h in w.heroes:
				if h.team != t.team:
					give_gold(h, int(b[0]), false, h.pos)
			if killer != null and killer.is_hero() and killer.team != t.team:
				give_gold(killer, w.rng.randi_range(int(b[1]), int(b[2])), false, t.pos)
	w.on_building_destroyed(t)
