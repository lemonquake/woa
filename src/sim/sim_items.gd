class_name SimItems
extends RefCounted
## The combination items' actives, passives and auras (Dota 7.41d rules and numbers, our names; see sim_data.gd).
##
## Actives: Jump Knife, Push Staff, Gold Glove, Spell Shield, Slip Boots, Mana Boots, Medic Kit, Spike Armor, Sneak
## Blade and Break Blade, Switch Boots, and the disables: Stun Blade (stun), Silence Staff (silence, then a burst of
## the damage taken), Root Staff (root, by projectile), Halberd (disarm), Hex Staff (hex). Passives: pierce (Spear,
## Sure Hit Staff), bash (Stun Club, Stun Blade), Rust Stone / Armor Breaker corruption (the strongest one counts)
## and Armor Breaker's kill damage, Shock Hammer's chain lightning, Cleave Axe's cleave, Block Shield's block,
## Spike Armor's damage return. Every chance passive is pseudo-random (SimStatus.roll). Auras (Mana Ring, Mana Boots, Leaf Hat, Medic Kit) refresh every 6 ticks on allies
## in range and linger 0.5 s; the same aura from two items never stacks, the stronger one counts.
## Random rolls happen only when the item is equipped, so matches without these items replay exactly as before.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const CORRUPTION_SRC := -7                 # one corruption debuff per unit, whoever applied it
const AURA_SRC := -1

var w: SimWorld
var chains: Array = []                     # chain lightning in progress: {src, team, dmg, left, hit, last, next_at}
var waves: Array = []                      # Frost Plate blasts spreading out: {src, team, pos, start, speed, radius, hit}

func _init(world: SimWorld = null) -> void:
	w = world

# ---- Queries ---------------------------------------------------------------------------------------------------------

## The first copy of an item in the six main slots, or {}.
func equipped(u: SimUnit, item_id: String) -> Dictionary:
	if not u.is_hero():
		return {}
	for i in mini(6, u.inventory.size()):
		var it = u.inventory[i]
		if it != null and it.id == item_id:
			return it
	return {}

## The main-slot item with this passive, or {}: the first one; for chain lightning and block the most expensive one
## (Storm Hammer's over the Shock Hammer's, Team Shield's over Block Shield's), since copies never stack.
func passive(u: SimUnit, kind: String) -> Dictionary:
	if not u.is_hero():
		return {}
	var strongest := kind == "chain" or kind == "block"
	var best: Dictionary = {}
	var best_cost := -1
	for i in mini(6, u.inventory.size()):
		var it = u.inventory[i]
		if it == null:
			continue
		var d := SimData.item(it.id)
		if String(d.get("passive", "")) == kind and not strongest:
			return it
		if String(d.get("passive", "")) == kind and int(d.cost) > best_cost:
			best = it
			best_cost = int(d.cost)
	return best

# ---- Targeting, errors and use (called by SimAbilities for these item kinds) ----------------------------------------

## "point", "unit" or "none" for this item's active.
static func target_kind(use: String) -> String:
	match use:
		"jump":
			return "point"
		"push", "gold", "overwhelm", "silence", "root", "disarm", "hex", "blast", "static", "fade":
			return "unit"
		"net":
			return "point"
	return "none"

func cast_range(u: SimUnit, use: String, d: Dictionary, t: SimUnit) -> float:
	match use:
		"jump":
			return INF                             # no walking: a click beyond the range blinks a shorter way
		"push":
			return float(d.values.range_enemy) if t != null and t.team != u.team else float(d.values.range_ally)
		"gold", "overwhelm", "silence", "root", "disarm", "hex", "blast", "static", "net", "fade":
			return float(d.values.range)
	return 0.0

func error(u: SimUnit, it: Dictionary, d: Dictionary, t: SimUnit, _p: Vector2) -> String:
	match String(d.use):
		"jump":
			if u.is_rooted():
				return "Rooted"
			var lock := float(d.values.hero_damage_lockout)
			for hid in u.hero_damage_log:
				if w.time - float(u.hero_damage_log[hid]) < lock:
					return "Jump Knife is disabled"
		"push":
			if t == null or not t.alive or t.is_building() or t.is_ward() or t.kind == K.COURIER:
				return "Must target a hero or creep"
			if t.team != u.team and t.debuff_immune:
				return "Target is immune"
			if t.is_invulnerable():
				return "Target is invulnerable"
			if not w.vision.sees(u.team, t):
				return "Target not visible"
		"bottle":
			if int(it.get("charges", 0)) <= 0 and String(it.get("orb", "")) == "":
				return "No charges"
		"static":
			if t == null or not t.alive or t.team != u.team or t.is_building() or t.is_ward() or t.kind == K.COURIER:
				return "Must target an ally"
		"fade":
			if t == null or not t.alive or t.team != u.team or t.is_building() or t.is_ward():
				return "Must target an ally"
		"overwhelm", "silence", "root", "disarm", "hex", "blast":
			if t == null or not t.alive or t.team == u.team or t.is_building() or t.is_ward() or t.kind == K.COURIER:
				return "Must target an enemy unit"
			if t.is_invulnerable():
				return "Target is invulnerable"
			# only the Stun Blade's stun goes through debuff immunity
			if t.debuff_immune and String(d.use) != "overwhelm":
				return "Target is immune"
			if not w.vision.sees(u.team, t):
				return "Target not visible"
		"gold":
			if int(it.get("charges", 0)) <= 0:
				return "No charges"
			if t == null or not t.alive or not t.is_creep() or t.team == u.team:
				return "Must target an enemy creep"
			if bool(t.def.get("ancient", false)):
				return "Cannot target ancient creeps"
			if not w.vision.sees(u.team, t):
				return "Target not visible"
	return ""

## Use the item's active. Returns true when the item is used up (none of these are).
func use(u: SimUnit, it: Dictionary, d: Dictionary, t: SimUnit, p: Vector2) -> bool:
	var v: Dictionary = d.values
	match String(d.use):
		"switch":
			var order := ["str", "int", "agi"]
			it["attr"] = order[(order.find(String(it.get("attr", "str"))) + 1) % 3]
			w.events.append({"t": "treads", "u": u.id, "attr": it.attr})
		"slip":
			var ms := float(v.move_speed_pct_ranged if u.is_ranged() else v.move_speed_pct_melee)
			u.add_modifier({"id": "slip_boots", "source": u.id, "expires": w.time + float(v.duration), "phased": true,
				"stats": {"move_speed_pct": ms}, "fx": "slip"})
		"restore":
			for o: SimUnit in w.query(u.pos, float(v.radius)):
				if o.alive and o.team == u.team and o.max_mana > 0.0 and not o.is_building() and not o.is_ward():
					o.mana = minf(o.max_mana, o.mana + float(v.amount))
			w.events.append({"t": "mana_burst", "u": u.id, "radius": float(v.radius)})
		"mend":
			for o: SimUnit in w.query(u.pos, float(v.radius)):
				if o.alive and o.team == u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER:
					w.combat.heal(o, float(v.heal))
			w.events.append({"t": "mend", "u": u.id, "radius": float(v.radius)})
		"spikes":
			u.add_modifier({"id": "spike_armor", "source": u.id, "expires": w.time + float(v.duration), "fx": "spikes"})
		"shield":
			var durs: Array = v.durations
			var n := int(it.get("uses", 0))
			var dur := float(durs[mini(n, durs.size() - 1)])
			it["uses"] = n + 1
			_basic_dispel(u)
			u.add_modifier({"id": "spell_shield", "source": u.id, "expires": w.time + dur, "debuff_immune": true,
				"stats": {"magic_resist": float(v.magic_resist)}, "fx": "spell_shield"})
			w.events.append({"t": "spell_shield", "u": u.id, "dur": dur})
		"fade":
			# Fade Cape: the barrier at once, invisible after the fade time (SimItems.update)
			t.add_modifier({"id": "glimmer_cape", "source": u.id, "by": u.id, "expires": w.time + float(v.duration),
				"fade_until": w.time + float(v.fade), "invisible": false, "magic_barrier": float(v.barrier),
				"stats": {"move_speed_pct": float(v.move_speed_pct)}, "fx": "sneak"})
			t.refresh_stats()
			w.events.append({"t": "fade_cape", "u": u.id, "target": t.id})
		"sneak":
			u.add_modifier({"id": "sneak_blade", "source": u.id, "expires": w.time + float(v.duration),
				"fade_until": w.time + float(v.fade), "invisible": false, "bonus": float(v.bonus_damage),
				"break": float(v.get("break", 0.0)), "stats": {"move_speed_pct": float(v.move_speed_pct)}, "fx": "sneak"})
		"bottle":
			# a stored orb is let out first; otherwise one charge of health and mana over 2.7 s
			if String(it.get("orb", "")) != "":
				var kind := String(it.orb)
				it.erase("orb")
				it.erase("orb_until")
				w.orbs.activate(u, kind)
			elif int(it.get("charges", 0)) > 0:
				it["charges"] = int(it.charges) - 1
				u.add_modifier({"id": "bottle", "source": u.id, "expires": w.time + float(v.time),
					"regen": float(v.health) / float(v.time), "mana_regen": float(v.mana) / float(v.time),
					"break_on_damage": true, "fx": "heal"})
		"overwhelm":
			# Stun Blade: a bash-group stun that pierces debuff immunity
			w.status.apply(t, u.id, u.team, {"id": "bashed", "stun": true, "dur": float(v.stun), "fx": "stun"}, true)
			w.events.append({"t": "overwhelm", "u": u.id, "target": t.id})
		"silence":
			# Silence Staff: silenced for 5 s; when it ends, 30% of the damage taken meanwhile strikes again as magic
			if w.status.apply(t, u.id, u.team, {"id": "silence_staff", "silence": true, "dur": float(v.duration),
					"fx": "silence"}):
				var sm := t.get_modifier("silence_staff")
				w.status.add_burn(t, u, float(sm.expires), float(v.damage_pct))
			w.events.append({"t": "item_debuff", "u": u.id, "target": t.id, "kind": "silence"})
		"root":
			# Root Staff: a projectile that roots what it reaches (debuff immunity on arrival stops it)
			w.combat.launch_effect(u, t, float(v.speed), "root_staff", {"id": "root_staff", "root": true,
				"dur": float(v.duration), "fx": "root"})
		"disarm":
			w.status.apply(t, u.id, u.team, {"id": "halberd", "disarm": true, "dur": float(v.duration),
				"dispel": "strong", "fx": "disarm"})
			w.events.append({"t": "item_debuff", "u": u.id, "target": t.id, "kind": "disarm"})
		"hex":
			if w.status.apply(t, u.id, u.team, {"id": "hex_staff", "hex": true, "dur": float(v.duration), "fx": "hex"}):
				t.atk_phase = SimUnit.AtkPhase.NONE
				t.cast_phase = SimUnit.CastPhase.NONE
			w.events.append({"t": "item_debuff", "u": u.id, "target": t.id, "kind": "hex"})
		"jump":
			_jump(u, d, p)
			if v.has("crash_radius"):
				_crash(u, v)
		"blast":
			# Blast Rod (Dagon): magic damage at once
			w.combat.deal_damage(u.id, u.team, true, t, float(v.damage), C.DamageType.MAGICAL, false, String(it.id),
				false, {"element": C.Element.LIGHTNING})
			w.events.append({"t": "blast_rod", "u": u.id, "target": t.id, "level": int(d.get("level", 1))})
		"net":
			# Net Staff (Gleipnir): a net flies at every enemy in the area and roots it on arrival
			var rad := float(v.radius) + u.aoe_bonus
			var n := 0
			for o: SimUnit in w.query(p, rad):
				if o.alive and o.team != u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
						and not o.is_invulnerable() and w.vision.sees(u.team, o):
					w.combat.launch_effect(u, o, float(v.speed), "root_staff", {"id": "net_staff", "root": true,
						"dur": float(v.duration), "fx": "root"})
					n += 1
			w.events.append({"t": "net_staff", "u": u.id, "point": p, "radius": rad, "count": n})
		"static":
			t.add_modifier({"id": "static_charge", "source": u.id, "expires": w.time + float(v.static_duration),
				"static": it.id, "fx": "static"})
			w.events.append({"t": "static_charge", "u": u.id, "target": t.id})
		"frost_blast":
			waves.append({"src": u.id, "team": u.team, "pos": u.pos, "start": w.time, "speed": float(v.speed),
				"radius": float(v.radius) + u.aoe_bonus, "hit": {}, "item": it.id})
			w.events.append({"t": "frost_blast", "u": u.id, "radius": float(v.radius) + u.aoe_bonus, "speed": float(v.speed)})
		"rage":
			u.add_modifier({"id": "leech_rage", "source": u.id, "expires": w.time + float(v.duration),
				"stats": {"lifesteal": float(v.lifesteal)}, "fx": "berserk"})
			w.events.append({"t": "leech_rage", "u": u.id})
		"refresh":
			for aid in u.ability_ready.keys():
				if aid != "tp" and aid != "masterful_archery":
					u.ability_ready[aid] = C.LONG_AGO
			w.events.append({"t": "refresh", "u": u.id})
		"greaves":
			_basic_dispel(u)
			for o: SimUnit in w.query(u.pos, float(v.radius)):
				if o.alive and o.team == u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER:
					w.combat.heal(o, float(v.heal))
					o.mana = minf(o.max_mana, o.mana + float(v.mana))
			w.events.append({"t": "mend", "u": u.id, "radius": float(v.radius)})
		"guard":
			var blk := float(v.guard_block) + float(v.guard_hp_pct) * u.max_hp
			for o: SimUnit in w.query(u.pos, float(v.radius)):
				if o.alive and o.team == u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER:
					var old := o.get_modifier("team_guard")
					if not old.is_empty() and float(old.block) > blk and w.time < float(old.expires):
						continue
					o.add_modifier({"id": "team_guard", "source": u.id, "expires": w.time + float(v.duration),
						"block": blk, "team_guard_on": true, "fx": "guard"})
			w.events.append({"t": "team_guard", "u": u.id, "radius": float(v.radius)})
		"drum":
			for o: SimUnit in w.query(u.pos, float(v.radius)):
				if o.alive and o.team == u.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER:
					o.add_modifier({"id": "war_drum", "source": u.id, "expires": w.time + float(v.duration),
						"stats": {"attack_speed": float(v.attack_speed), "move_speed_pct": float(v.move_speed_pct)},
						"fx": "haste"})
					o.stats_dirty = true
			w.events.append({"t": "war_drum", "u": u.id, "radius": float(v.radius)})
		"push":
			_push(u, d, t)
		"gold":
			it["charges"] = int(it.charges) - 1
			if not it.has("next_charge"):
				it["next_charge"] = w.time + float(v.charge_time)
			w.combat.give_gold(u, int(v.gold), true, t.pos)
			w.events.append({"t": "gold_glove", "u": u.id, "target": t.id, "gold": int(v.gold)})
			w.combat.kill(t, null)
	u.stats_dirty = true
	return false

## Jump Knife: appear at the target point; a point beyond 1200 (plus cast range bonuses) lands 960 (plus them) toward it. Lands on the nearest open spot.
func _jump(u: SimUnit, d: Dictionary, p: Vector2) -> void:
	var v: Dictionary = d.values
	var from := u.pos
	var to := p
	if p.distance_to(u.pos) > float(v.range) + u.cast_range_bonus:
		to = u.pos + (p - u.pos).normalized() * (float(v.clamp) + u.cast_range_bonus)
	if not w.map.is_walkable(to):
		var c := w.map.nearest_walkable(w.map.world_to_cell(to))
		to = w.map.cell_center(c.x, c.y)
	u.pos = to
	u.path = PackedVector2Array()
	u.moving = false
	if (to - from).length() > 1.0:
		u.facing = (to - from).angle()
	w.combat.disjoint(u)
	w.events.append({"t": "jump", "u": u.id, "from": from, "to": to})

## Crash Knife (Overwhelming Blink): where its owner lands, enemies within 800 take 100 + 50% of his strength as magic
## damage at once and 100% of his strength over 6 s, and are slowed 50% (move) and 50 (attack) for 6 s.
func _crash(u: SimUnit, v: Dictionary) -> void:
	var dur := float(v.duration)
	var strength := u.str_total
	for o: SimUnit in w.query(u.pos, float(v.crash_radius) + u.aoe_bonus):
		if not o.alive or o.team == u.team or o.is_building() or o.is_ward() or o.kind == K.COURIER or o.is_invulnerable():
			continue
		w.combat.deal_damage(u.id, u.team, true, o, float(v.damage_base) + float(v.damage_pct) * strength,
			C.DamageType.MAGICAL, false, "crash_knife")
		if o.alive and not o.debuff_immune:
			w.status.add_dot(o, u, "crash_knife", float(v.dot_pct) * strength / dur, dur, C.Element.NONE, true)
			w.status.apply(o, u.id, u.team, {"id": "crash_knife", "slow": float(v.slow), "dur": dur,
				"stats": {"attack_speed": -float(v.attack_slow)}, "fx": "slow"})
	w.events.append({"t": "crash_knife", "u": u.id, "radius": float(v.crash_radius) + u.aoe_bonus})

## Push Staff: shoves the target 600 the way it faces over 0.5 s. It is not a disable; trees in the way are cut.
func _push(u: SimUnit, d: Dictionary, t: SimUnit) -> void:
	var v: Dictionary = d.values
	var dir := Vector2.from_angle(t.facing)
	var to := t.pos + dir * float(v.distance)
	# cut the trees along the way
	for i in w.map.trees.size():
		var tr: Dictionary = w.map.trees[i]
		if not tr.alive:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(tr.pos, t.pos, to)
		if cp.distance_to(tr.pos) <= t.hull + 70.0:
			w.cut_tree(i, t.pos)
	w.orders.cancel_channel(t)
	t.knock = {"from": t.pos, "to": to, "t": 0.0, "dur": float(v.time), "disable": false, "src": u.id}
	t.path = PackedVector2Array()
	w.events.append({"t": "knockback", "u": t.id, "phys": false, "to": to, "push_staff": true})

## Basic dispel on the user: removes the debuffs enemies put on it that a basic dispel takes (slows, roots,
## silences, disarms, mutes; not stuns or hexes). Older debuffs without a dispel mark are judged by their flags.
func _basic_dispel(u: SimUnit) -> void:
	w.status.dispel(u, false, u.team)
	for i in range(u.modifiers.size() - 1, -1, -1):
		var m: Dictionary = u.modifiers[i]
		if m.has("dispel") or m.get("stun", false) or m.get("hex", false):
			continue
		var src := w.get_unit(int(m.get("source", -1)))
		if src == null or src.team == u.team:
			continue
		if m.get("slow", 0.0) > 0.0 or m.get("root", false) or m.get("silence", false) or m.get("disarm", false) \
				or m.get("mute", false):
			u.modifiers.remove_at(i)
			u.stats_dirty = true

## Sneak Blade and Break Blade end when their owner attacks or casts. Returns what the breaking attack carries:
## {bonus damage, break (seconds of Break on the target, Break Blade)}.
func break_sneak(u: SimUnit) -> Dictionary:
	# the Stealth Orb breaks the same way, with nothing extra on the attack
	if not u.get_modifier("orb_stealth").is_empty():
		u.remove_modifier("orb_stealth")
		w.events.append({"t": "sneak_end", "u": u.id})
	# Fade Cape: the invisibility ends, the magic barrier stays
	var gm := u.get_modifier("glimmer_cape")
	if not gm.is_empty() and not bool(gm.get("broken", false)):
		gm["invisible"] = false
		gm["broken"] = true
		w.events.append({"t": "sneak_end", "u": u.id})
	var m := u.get_modifier("sneak_blade")
	if m.is_empty():
		return {}
	u.remove_modifier("sneak_blade")
	w.events.append({"t": "sneak_end", "u": u.id})
	return {"bonus": float(m.get("bonus", 0.0)), "break": float(m.get("break", 0.0))}

# ---- Per tick ----------------------------------------------------------------------------------------------------------

func update() -> void:
	if w.tick % 6 == 0:
		_auras()
		_burns()
	if not waves.is_empty():
		_update_waves()
	for h in w.heroes:
		if not h.alive:
			continue
		# Fade Cape: invisible once the fade time has passed (its barrier stays when it breaks)
		var gm := h.get_modifier("glimmer_cape")
		if not gm.is_empty() and not bool(gm.invisible) and not bool(gm.get("broken", false)) and w.time >= float(gm.fade_until):
			gm["invisible"] = true
			if not w.vision.true_sighted(1 - h.team, h):
				w.combat.disjoint(h)
			if h.order != C.Order.ATTACK_UNIT and h.order != C.Order.ATTACK_MOVE:
				h.atk_target = -1
		# Sneak Blade: invisible once the fade time has passed
		var sm := h.get_modifier("sneak_blade")
		if not sm.is_empty() and not bool(sm.invisible) and w.time >= float(sm.fade_until):
			sm["invisible"] = true
			# turning invisible disjoints projectiles once, unless an enemy has True Sight over the unit
			if not w.vision.true_sighted(1 - h.team, h):
				w.combat.disjoint(h)
			# an invisible unit never attacks on its own: a swing it started by itself is dropped
			if h.order != C.Order.ATTACK_UNIT and h.order != C.Order.ATTACK_MOVE:
				h.atk_target = -1
		# Gold Glove charges come back one every 90 s, up to 2
		for i in mini(6, h.inventory.size()):
			var it = h.inventory[i]
			if it == null or String(SimData.item(it.id).get("use", "")) != "gold":
				continue
			var v: Dictionary = SimData.item(it.id).values
			if int(it.charges) >= int(v.max_charges):
				it.erase("next_charge")
			elif not it.has("next_charge"):
				it["next_charge"] = w.time + float(v.charge_time)
			elif w.time >= float(it.next_charge):
				it["charges"] = int(it.charges) + 1
				if int(it.charges) < int(v.max_charges):
					it["next_charge"] = w.time + float(v.charge_time)
				else:
					it.erase("next_charge")
	_update_chains()

## Aura items: allies within range (the owner too) get the aura for 0.5 s past each refresh; the strongest copy wins.
func _auras() -> void:
	for h in w.heroes:
		if not h.alive:
			continue
		for i in mini(6, h.inventory.size()):
			var it = h.inventory[i]
			if it == null:
				continue
			var d := SimData.item(it.id)
			var kind := String(d.get("aura", ""))
			if kind == "":
				continue
			var key := "mana_regen" if kind == "mana" else "regen"
			var amount := float(d.values.aura_mana_regen if kind == "mana" else d.values.aura_hp_regen)
			for o: SimUnit in w.query(h.pos, float(d.values.aura_radius)):
				if not o.alive or o.team != h.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
					continue
				var mid := "aura_" + kind
				var old := o.get_modifier(mid)
				if not old.is_empty() and float(old.get(key, 0.0)) > amount and w.time < float(old.expires):
					continue
				o.add_modifier({"id": mid, "source": AURA_SRC, "expires": w.time + 0.5 + 6.0 * C.DT, key: amount,
					"aura": true, "by": h.id})
	# stat auras of the newer items (Small Shield, Leech Totem, Battle Armor, Frost Plate, Guard Boots, War Drum): each
	# {id, stats, radius, enemy (on enemies instead of allies), buildings (buildings too), creep_stats, self_stats,
	# low_hp + low_hp_stats}. One copy of each aura counts; it lingers 0.5 s past each refresh.
	for h in w.heroes:
		if not h.alive or h.is_broken():
			continue
		for i in mini(6, h.inventory.size()):
			var it = h.inventory[i]
			if it == null:
				continue
			for au in SimData.item(it.id).get("auras", []):
				_stat_aura(h, au)

func _stat_aura(h: SimUnit, au: Dictionary) -> void:
	var enemy := bool(au.get("enemy", false))
	for o: SimUnit in w.query(h.pos, float(au.radius)):
		if not o.alive or o.is_ward() or o.kind == K.COURIER or o.kind == K.FOUNTAIN:
			continue
		if o.is_building() and not bool(au.get("buildings", false)):
			continue
		if enemy == (o.team == h.team):
			continue
		var st: Dictionary = au.stats
		if o == h and au.has("self_stats"):
			st = au.self_stats
		elif not o.is_hero() and au.has("creep_stats"):
			st = au.creep_stats
		if au.has("low_hp") and o.hp < o.max_hp * float(au.low_hp):
			st = au.low_hp_stats
		var old := o.get_modifier(String(au.id))
		var had := not old.is_empty()
		o.add_modifier({"id": String(au.id), "source": AURA_SRC, "expires": w.time + 0.5 + 6.0 * C.DT, "stats": st,
			"aura": true, "by": h.id, "debuff": enemy})
		if not had or old.get("stats") != st:
			o.stats_dirty = true

## Burning Cape: every 0.2 s its owner burns the enemies within 650 (not buildings) for 60 magic damage a second.
func _burns() -> void:
	for h in w.heroes:
		if not h.alive:
			continue
		for i in mini(6, h.inventory.size()):
			var it = h.inventory[i]
			if it == null:
				continue
			var bd: Dictionary = SimData.item(it.id).get("burn", {})
			if bd.is_empty():
				continue
			var amount := float(bd.dps) * 6.0 * C.DT
			for o: SimUnit in w.query(h.pos, float(bd.radius)):
				if o.alive and o.team != h.team and not o.is_building() and not o.is_ward() and o.kind != K.COURIER \
						and not o.is_invulnerable():
					w.combat.deal_damage(h.id, h.team, true, o, amount, C.DamageType.MAGICAL, false, String(it.id), false,
						{"element": C.Element.FIRE, "no_spell_lifesteal": true, "quiet": true})
			break

## Frost Plate: the ring spreads at 400 a second; each enemy it reaches (once) takes the damage and the slow.
func _update_waves() -> void:
	for i in range(waves.size() - 1, -1, -1):
		var wv: Dictionary = waves[i]
		var r := minf(float(wv.radius), (w.time - float(wv.start)) * float(wv.speed))
		var v: Dictionary = SimData.item(String(wv.item)).values
		for o: SimUnit in w.query(wv.pos, r):
			if not o.alive or o.team == int(wv.team) or wv.hit.has(o.id) or o.is_building() or o.is_ward() \
					or o.kind == K.COURIER or o.is_invulnerable():
				continue
			wv.hit[o.id] = true
			w.combat.deal_damage(int(wv.src), int(wv.team), true, o, float(v.damage), C.DamageType.MAGICAL, false,
				"frost_plate", false, {"element": C.Element.ICE})
			if o.alive:
				w.status.apply(o, int(wv.src), int(wv.team), {"id": "frost_plate", "slow": float(v.slow),
					"dur": float(v.duration), "fx": "slow"})
		if r >= float(wv.radius):
			waves.remove_at(i)

# ---- Attacks ------------------------------------------------------------------------------------------------------

## Before the hit roll: pierce (Spear 25% / 60, Sure Hit Staff 80% / 70): the attack cannot miss and deals bonus
## magic damage. Pseudo-random; the strongest pierce item rolls, the others do not stack. Never against buildings
## (and no roll counts there). Returns {damage, item} on a proc, {} otherwise.
func roll_pierce(s: Dictionary, t: SimUnit) -> Dictionary:
	if not bool(s.hero) or t.is_building() or t.is_ward():
		return {}
	var src := w.get_unit(int(s.src))
	if src == null:
		return {}
	var best: Dictionary = {}
	for i in mini(6, src.inventory.size()):
		var it = src.inventory[i]
		if it == null or String(SimData.item(it.id).get("passive", "")) != "pierce":
			continue
		var v: Dictionary = SimData.item(it.id).values
		if best.is_empty() or float(v.chance) > float(best.chance):
			best = {"chance": float(v.chance), "damage": float(v.damage), "item": it.id}
	if best.is_empty() or not w.status.roll(src, "pierce", float(best.chance)):
		return {}
	return best

## Bash (Stun Club, Stun Blade): only the first bash item in the bags works (Dota: the one held longest), with its
## chance for melee or ranged heroes; while its 2.3 s cooldown runs it does not roll at all. Not against buildings or
## wards; it does work on allies being denied. Returns {damage, dur, item} on a proc, {} otherwise.
func roll_bash(s: Dictionary, t: SimUnit) -> Dictionary:
	if not bool(s.hero) or t.is_building() or t.is_ward():
		return {}
	var src := w.get_unit(int(s.src))
	if src == null:
		return {}
	var it := passive(src, "bash")
	if it.is_empty() or w.time < float(it.get("bash_ready", C.LONG_AGO)):
		return {}
	var v: Dictionary = SimData.item(it.id).values
	var chance := float(v.chance_ranged if bool(s.ranged) else v.chance_melee)
	if not w.status.roll(src, "bash", chance):
		return {}
	it["bash_ready"] = w.time + float(v.bash_cooldown)
	return {"damage": float(v.damage), "dur": float(v.duration), "item": it.id}

## An attack from a hero landed on `t` for `dmg` (before armor): pierce damage, Break Blade's break, corruption,
## chain lightning, cleave.
func on_attack_landed(s: Dictionary, t: SimUnit, dmg: float, pierce: Dictionary) -> void:
	var src := w.get_unit(int(s.src))
	if src == null or not src.is_hero() or t.team == src.team:
		return
	if not pierce.is_empty() and t.alive and not t.is_building():
		w.combat.deal_damage(src.id, src.team, true, t, float(pierce.damage), C.DamageType.MAGICAL, false,
			String(pierce.item), false, {"no_amp": true})
	if float(s.get("sneak_break", 0.0)) > 0.0 and t.alive and not t.is_building():
		w.status.apply(t, src.id, src.team, {"id": "break_blade", "break": true, "dur": float(s.sneak_break), "fx": "break"})
	_corrupt(src, t)
	if t.is_building() or t.is_ward():
		return
	var ch := passive(src, "chain")
	if not ch.is_empty() and w.time >= float(ch.get("chain_ready", C.LONG_AGO)):
		var v: Dictionary = SimData.item(ch.id).values
		if w.status.roll(src, "chain", float(v.chance)):
			ch["chain_ready"] = w.time + float(v.cooldown)
			_start_chain(src, t, v, String(ch.id))
	var cl := passive(src, "cleave")
	if not cl.is_empty() and not src.is_ranged():
		_cleave(src, t, dmg, SimData.item(cl.id).values)

## Corruption: the strongest armor reduction among the attacker's items (Armor Breaker over Rust Stone). One debuff per
## unit; a weaker one does not replace a stronger one still running.
func _corrupt(src: SimUnit, t: SimUnit) -> void:
	var best: Dictionary = {}
	var best_id := ""
	for i in mini(6, src.inventory.size()):
		var it = src.inventory[i]
		if it == null or String(SimData.item(it.id).get("passive", "")) != "corruption":
			continue
		var v: Dictionary = SimData.item(it.id).values
		if best.is_empty() or float(v.armor_reduction) > float(best.armor_reduction):
			best = v
			best_id = it.id
	if best.is_empty():
		return
	var old := t.get_modifier("corruption")
	if not old.is_empty() and w.time < float(old.expires) and float(old.reduction) > float(best.armor_reduction):
		return
	t.add_modifier({"id": "corruption", "source": CORRUPTION_SRC, "expires": w.time + float(best.duration),
		"reduction": float(best.armor_reduction), "stats": {"armor": -float(best.armor_reduction)}, "by": src.id,
		"item": best_id, "fx": "corruption"})

func _start_chain(src: SimUnit, t: SimUnit, v: Dictionary, item := "shock_hammer") -> void:
	var c := {"src": src.id, "team": src.team, "dmg": float(v.damage), "left": int(v.strikes), "hit": {},
		"last": t.id, "radius": float(v.radius), "delay": float(v.delay), "next_at": w.time, "pos": t.pos, "item": item}
	chains.append(c)
	_chain_strike(c, t)

func _chain_strike(c: Dictionary, t: SimUnit) -> void:
	c.hit[t.id] = true
	c.left = int(c.left) - 1
	c.last = t.id
	c.pos = t.pos
	c.next_at = w.time + float(c.delay)
	w.events.append({"t": "chain", "src": c.src, "u": t.id, "from": c.get("prev_pos", t.pos), "pos": t.pos})
	c["prev_pos"] = t.pos
	w.combat.deal_damage(int(c.src), int(c.team), true, t, float(c.dmg), C.DamageType.MAGICAL, false, String(c.get("item", "shock_hammer")))

func _update_chains() -> void:
	for i in range(chains.size() - 1, -1, -1):
		var c: Dictionary = chains[i]
		if int(c.left) <= 0:
			chains.remove_at(i)
			continue
		if w.time < float(c.next_at):
			continue
		var best: SimUnit = null
		var bd := INF
		for o: SimUnit in w.query(c.pos, float(c.radius)):
			if not o.alive or o.team == int(c.team) or c.hit.has(o.id) or o.is_building() or o.is_ward() \
					or o.kind == K.COURIER or o.is_invulnerable():
				continue
			var dd: float = o.pos.distance_to(c.pos)
			if dd < bd or (dd == bd and best != null and o.id < best.id):
				bd = dd
				best = o
		if best == null:
			chains.remove_at(i)
			continue
		_chain_strike(c, best)

## Cleave: 60% of the attack's damage (40% to creeps) to the other enemies in a cone in front of the attacker (150 wide at the
## attacker, 360 wide 650 away), ignoring their armor. Not against buildings.
func _cleave(src: SimUnit, main: SimUnit, dmg: float, v: Dictionary) -> void:
	var dir := (main.pos - src.pos)
	dir = Vector2.from_angle(src.facing) if dir.length() < 1.0 else dir.normalized()
	var dist := float(v.distance)
	w.events.append({"t": "cleave", "u": src.id, "target": main.id, "dir": dir, "dist": dist})
	for o: SimUnit in w.query(src.pos + dir * dist * 0.5, dist * 0.5 + float(v.end_width)):
		if o == main or not o.alive or o.team == src.team or o.is_building() or o.is_ward() or o.kind == K.COURIER:
			continue
		var rel := o.pos - src.pos
		var along := rel.dot(dir)
		if along < 0.0 or along > dist:
			continue
		var half := lerpf(float(v.start_width), float(v.end_width), along / dist) * 0.5
		if absf(rel.dot(dir.orthogonal())) > half + o.hull:
			continue
		var amount := dmg * float(v.cleave_pct_creep if o.is_creep() else v.cleave_pct)
		w.combat.deal_damage(src.id, src.team, true, o, amount, C.DamageType.PHYSICAL, false, "cleave_axe", false,
			{"ignore_armor": true, "no_spell_lifesteal": true})

# ---- Damage taken -------------------------------------------------------------------------------------------------

## Block Shield: 60% of attacks on its owner lose 50 damage (25 for a ranged owner), before armor.
func block_attack(t: SimUnit, amount: float) -> float:
	# Team Shield's Guard: every attack loses its block (the better of it and an item's block counts)
	var gm := t.get_modifier("team_guard")
	if not gm.is_empty() and w.time < float(gm.expires):
		var gb := float(gm.block)
		var it0 := passive(t, "block")
		if not it0.is_empty():
			var v0: Dictionary = SimData.item(it0.id).values
			gb = maxf(gb, float(v0.block_ranged if t.is_ranged() else v0.block_melee))
		w.events.append({"t": "blocked", "u": t.id, "amount": minf(gb, amount)})
		return maxf(0.0, amount - gb)
	var it := passive(t, "block")
	if it.is_empty():
		return amount
	var v: Dictionary = SimData.item(it.id).values
	if not w.status.roll(t, "block", float(v.chance)):
		return amount
	var b := float(v.block_ranged if t.is_ranged() else v.block_melee)
	w.events.append({"t": "blocked", "u": t.id, "amount": minf(b, amount)})
	return maxf(0.0, amount - b)

## Spike Armor: attacks on its owner send back 10 + 15% of their damage before reductions; while active, 85% of every
## damage instance (any type) goes back too. Not to buildings, wards or allies; returned damage is never returned.
func on_damaged(t: SimUnit, src: SimUnit, raw: float, dtype: int, is_attack: bool, elem := 0) -> void:
	if src == null or not src.alive or src == t or src.team == t.team or src.is_building() or src.is_ward():
		return
	if is_attack:
		_static_strike(t, src)
	var it := passive(t, "spikes")
	if it.is_empty():
		return
	var v: Dictionary = SimData.item(it.id).values
	var back := 0.0
	if is_attack:
		back += float(v.passive_flat) + raw * float(v.passive_pct)
	if not t.get_modifier("spike_armor").is_empty():
		back += raw * float(v.active_pct)
	if back <= 0.0:
		return
	# the spikes send back what came in, element and all
	w.combat.deal_damage(t.id, t.team, true, src, back, dtype, false, "spike_armor", true,
		{"no_spell_lifesteal": true, "element": elem})
	w.events.append({"t": "spikes_return", "u": t.id, "target": src.id, "amount": back, "active": not t.get_modifier("spike_armor").is_empty()})

## Storm Hammer's Static Charge: when the charged unit is attacked, a 20% (pseudo-random) chance, at most once a second,
## to strike up to 4 enemies within 900 (the attacker first when it is within 600) for 225 magic damage.
func _static_strike(t: SimUnit, attacker: SimUnit) -> void:
	var m := t.get_modifier("static_charge")
	if m.is_empty() or w.time < float(m.get("next", C.LONG_AGO)):
		return
	var v: Dictionary = SimData.item(String(m.static)).values
	if not w.status.roll(t, "static_charge", float(v.static_chance)):
		return
	m["next"] = w.time + float(v.static_cooldown)
	var owner := w.get_unit(int(m.source))
	var src_id := owner.id if owner != null else t.id
	var targets: Array = []
	if attacker.pos.distance_to(t.pos) <= float(v.static_primary_radius) and not attacker.is_building():
		targets.append(attacker)
	for o: SimUnit in w.query(t.pos, float(v.static_radius)):
		if targets.size() >= int(v.static_strikes):
			break
		if o.alive and o.team != t.team and not targets.has(o) and not o.is_building() and not o.is_ward() 				and o.kind != K.COURIER and not o.is_invulnerable():
			targets.append(o)
	for o: SimUnit in targets:
		w.combat.deal_damage(src_id, t.team, true, o, float(v.static_damage), C.DamageType.MAGICAL, false, "storm_hammer",
			false, {"element": C.Element.LIGHTNING})
		w.events.append({"t": "chain", "src": t.id, "u": o.id, "from": t.pos, "pos": o.pos})

## Armor Breaker: a hero who dies while corrupted by it gives its owner 2 damage (killer) or 1 (assist), up to 30.
func on_hero_death(t: SimUnit, killer: SimUnit) -> void:
	var m := t.get_modifier("corruption")
	if m.is_empty() or String(m.get("item", "")) != "armor_breaker":
		return
	var by := w.get_unit(int(m.by))
	if by == null or by.team == t.team:
		return
	for arr in [by.inventory, by.stash]:
		for it in arr:
			if it != null and it.id == "armor_breaker":
				var v: Dictionary = SimData.item("armor_breaker").values
				var gain := float(v.damage_per_kill) if by == killer else float(v.damage_per_assist)
				it["souls"] = minf(float(v.max_damage), float(it.get("souls", 0.0)) + gain)
				by.stats_dirty = true
				return
