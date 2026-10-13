class_name SimOrbs
extends RefCounted
## Orbs: Dota's runes with plain names (Dota 2 wiki: Runes, Bounty Rune, Wisdom Rune, Water Rune and the power runes;
## see docs/MECHANICS.md "Orbs"). A hero picks one up by walking within 150 of it (a right click on it).
##   Gold Orb (Bounty): 0:00 at the two gold spots and the two river spots, then every 4:00 at the gold spots. Every hero
##     of the team gets 40 + 6 per 4 minutes of reliable gold.
##   Water Orb: 2:00 and 4:00 at both river spots: 40 health and 80 mana.
##   Wisdom Orb: 7:00 and every 7:00 at both wisdom spots: 280 experience per 7 minutes to the picker and to the
##     team's hero with the least experience (the next one if the picker is that hero), dead or alive.
##   Power orbs: from 6:00 every 2:00 at one of the two river spots, chosen at random. A cycle shows every kind once
##     before any repeats, and a kind never comes twice in a row. Speed (550 speed, slows ignored, 22 s + 3 s per
##     cycle), Damage (+80% base damage and +15% spell damage, 45 s), Stealth (invisible after 2 s for 45 s, 25% less
##     damage taken while invisible + 5% per cycle; broken by attacking or casting), Healing (6% of max health and mana
##     per second for 30 s, 1% for 3 s after damage from a hero, ends when both are full), Magic (25% shorter cooldowns,
##     30% cheaper mana costs, 50 s), Shield (absorbs damage up to 50% of max health, 75 s).
## Gold and Wisdom orbs stay until taken (a new one lies beside an old one); Water and power orbs vanish when the next
## river orb spawns. (Dota's Illusion rune is not in the cycle yet: the game has no illusions.)

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind

const POWER := ["speed", "damage", "stealth", "healing", "magic", "shield"]
const NAMES := {"gold": "Gold Orb", "water": "Water Orb", "wisdom": "Wisdom Orb", "speed": "Speed Orb",
	"damage": "Damage Orb", "stealth": "Stealth Orb", "healing": "Healing Orb", "magic": "Magic Orb",
	"shield": "Shield Orb"}
const PICKUP_RANGE := 150.0

var w: SimWorld
var orbs: Array = []                       # [{id, kind, pos, spot: "power" | "gold" | "wisdom", born}]
var spots := {"power": [Vector2(-1300, 1300), Vector2(1300, -1300)],
	"gold": [Vector2(-3300, -900), Vector2(3239, 1048)],
	"wisdom": [Vector2(-5200, 900), Vector2(5294, -1371)]}
var cycles := 0                            # power orb cycles begun (Speed lasts longer, Stealth protects more)
var _next_id := 1
var _bag: Array = []                       # power kinds left in this cycle
var _last_power := ""
var _next_gold := 0.0
var _next_water := 120.0
var _next_power := 360.0
var _next_wisdom := 420.0

func _init(world: SimWorld) -> void:
	w = world

func get_orb(id: int) -> Dictionary:
	for o in orbs:
		if int(o.id) == id:
			return o
	return {}

# ---- Spawning ---------------------------------------------------------------------------------------------------------

func update() -> void:
	if w.time < 0.0:
		return
	if w.time >= _next_gold:
		if _next_gold == 0.0:
			for p in spots.power:
				_spawn("gold", p, "power")
		for p in spots.gold:
			_spawn("gold", p, "gold")
		_next_gold += 240.0
	if _next_water <= 240.0 and w.time >= _next_water:
		_clear_river()
		for p in spots.power:
			_spawn("water", p, "power")
		_next_water += 120.0
	if w.time >= _next_power:
		_clear_river()
		var p2: Vector2 = spots.power[w.rng.randi_range(0, 1)]
		_spawn(_draw_power(), p2, "power")
		_next_power += 120.0
	if w.time >= _next_wisdom:
		for p in spots.wisdom:
			_spawn("wisdom", p, "wisdom")
		_next_wisdom += 420.0
	if w.tick % 15 == 0:
		_bottles()
	if w.tick % 3 == 0:
		_stealth_fade()
		for h in w.heroes:
			var full := h.hp >= h.max_hp - 0.01 and h.mana >= h.max_mana - 0.01
			if h.alive and full and not h.get_modifier("orb_healing").is_empty():
				h.remove_modifier("orb_healing")

## The next power kind: every kind once per cycle, never the same twice in a row.
func _draw_power() -> String:
	if _bag.is_empty():
		_bag = POWER.duplicate()
		cycles += 1
	var pool := _bag.filter(func(k): return k != _last_power)
	if pool.is_empty():
		pool = _bag
	var kind: String = pool[w.rng.randi_range(0, pool.size() - 1)]
	_bag.erase(kind)
	_last_power = kind
	return kind

## Water and power orbs at the river spots go when the next river orb comes (gold orbs there stay).
func _clear_river() -> void:
	for i in range(orbs.size() - 1, -1, -1):
		var o: Dictionary = orbs[i]
		if String(o.spot) == "power" and String(o.kind) != "gold":
			orbs.remove_at(i)
			w.events.append({"t": "orb_gone", "id": o.id})

func _spawn(kind: String, p: Vector2, spot: String) -> void:
	# an orb left lying there: the new one comes beside it
	var at := p
	var n := 0
	for o in orbs:
		if (o.pos as Vector2).distance_to(p) < 40.0 * (n + 1):
			n += 1
	if n > 0:
		at = p + Vector2.from_angle(n * 2.1) * 70.0
	var o2 := {"id": _next_id, "kind": kind, "pos": at, "spot": spot, "born": w.time}
	_next_id += 1
	orbs.append(o2)
	w.events.append({"t": "orb_spawn", "id": o2.id, "kind": kind, "pos": at})

# ---- Taking ---------------------------------------------------------------------------------------------------------

## A hero within reach takes the orb. Returns false when it is gone or too far.
func take(h: SimUnit, id: int) -> bool:
	var o := get_orb(id)
	if o.is_empty() or not h.alive or not h.is_hero():
		return false
	if h.pos.distance_to(o.pos) > PICKUP_RANGE + h.hull:
		return false
	orbs.erase(o)
	w.events.append({"t": "orb_gone", "id": o.id})
	# a Flask with room keeps the orb (and refills: 2 charges for a gold or water orb, 3 for the others)
	var b := _bottle(h)
	if not b.is_empty() and String(b.get("orb", "")) == "":
		var kind := String(o.kind)
		b["orb"] = kind
		b["orb_until"] = w.time + float(SimData.item("bottle").values.orb_expire)
		b["charges"] = maxi(int(b.get("charges", 0)), 2 if kind in ["gold", "water"] else 3)
		w.events.append({"t": "orb_bottled", "u": h.id, "kind": kind, "name": String(NAMES.get(kind, kind))})
		return true
	activate(h, String(o.kind))
	return true

## The hero's Flask in its six main slots, or {}.
func _bottle(h: SimUnit) -> Dictionary:
	for i in mini(6, h.inventory.size()):
		var it = h.inventory[i]
		if it != null and it.id == "bottle":
			return it
	return {}

func activate(h: SimUnit, kind: String) -> void:
	var info := {"t": "orb_taken", "u": h.id, "kind": kind, "name": String(NAMES.get(kind, kind))}
	match kind:
		"gold":
			var gold := 40 + 6 * int(floor(w.time / 240.0))
			for a in w.heroes:
				if a.team == h.team:
					w.combat.give_gold(a, gold, true, a.pos)
			info["gold"] = gold
		"wisdom":
			var xp := 280.0 * maxf(1.0, floor(w.time / 420.0))
			# also the team's hero with the least experience (judged before the gain); the next one if that is the picker
			var team: Array = w.heroes.filter(func(a): return a.team == h.team)
			team.sort_custom(func(a, b): return a.xp < b.xp or (a.xp == b.xp and a.id < b.id))
			var lowest: SimUnit = null
			if not team.is_empty():
				lowest = team[0] if team[0] != h else (team[1] if team.size() > 1 else null)
			w.combat.give_xp(h, xp)
			if lowest != null:
				w.combat.give_xp(lowest, xp)
				info["also"] = lowest.id
			info["xp"] = xp
		"water":
			w.combat.heal(h, 40.0)
			h.mana = minf(h.max_mana, h.mana + 80.0)
		"speed":
			h.add_modifier({"id": "orb_speed", "source": -60, "expires": w.time + 22.0 + 3.0 * maxi(0, cycles - 1),
				"haste": true, "fx": "haste", "dispel": "basic"})
		"damage":
			h.add_modifier({"id": "orb_damage", "source": -60, "expires": w.time + 45.0, "fx": "orb_damage",
				"stats": {"base_damage_pct": 0.8, "spell_amp": 0.15}, "dispel": "basic"})
		"stealth":
			h.add_modifier({"id": "orb_stealth", "source": -60, "expires": w.time + 45.0, "fade_until": w.time + 2.0,
				"invisible": false, "resist": 0.25 + 0.05 * maxi(0, cycles - 1), "fx": "sneak", "dispel": "basic"})
		"healing":
			h.add_modifier({"id": "orb_healing", "source": -60, "expires": w.time + 30.0, "regen_pct": 0.06,
				"hurt_until": C.LONG_AGO, "fx": "heal", "dispel": "basic"})
		"magic":
			h.add_modifier({"id": "orb_magic", "source": -60, "expires": w.time + 50.0, "cdr": 0.25, "mana_cut": 0.30,
				"fx": "orb_magic", "dispel": "basic"})
		"shield":
			h.add_modifier({"id": "orb_shield", "source": -60, "expires": w.time + 75.0, "barrier": h.max_hp * 0.5,
				"fx": "orb_shield", "dispel": "basic"})
	h.stats_dirty = true
	w.events.append(info)

# ---- Effects --------------------------------------------------------------------------------------------------------

## Flasks (Dota's Bottle): a stored orb lets itself out after 90 s (and is lost if its hero is dead then); at the fountain an empty
## Flask refills to 3 charges.
func _bottles() -> void:
	for h in w.heroes:
		for i in mini(6, h.inventory.size()):
			var it = h.inventory[i]
			if it == null or it.id != "bottle":
				continue
			if String(it.get("orb", "")) != "" and w.time >= float(it.orb_until):
				var kind := String(it.orb)
				it.erase("orb")
				it.erase("orb_until")
				if h.alive:
					activate(h, kind)
			elif String(it.get("orb", "")) == "" and h.alive and not h.get_modifier("fountain").is_empty():
				it["charges"] = int(SimData.item("bottle").values.max_charges)

## Stealth Orb: invisible once its 2 s fade is over (turning invisible disjoints projectiles).
func _stealth_fade() -> void:
	for h in w.heroes:
		var m := h.get_modifier("orb_stealth")
		if m.is_empty() or bool(m.invisible) or w.time < float(m.fade_until):
			continue
		m["invisible"] = true
		if not w.vision.true_sighted(1 - h.team, h):
			w.combat.disjoint(h)
		if h.order != C.Order.ATTACK_UNIT and h.order != C.Order.ATTACK_MOVE:
			h.atk_target = -1

## Damage about to be taken (after armor and other reductions): Stealth Orb's resistance while invisible, then the
## Shield Orb's barrier absorbs what it can. Returns what is left; `from_hero` marks player damage (Healing Orb).
func absorb(t: SimUnit, amount: float, from_hero: bool) -> float:
	if t.modifiers.is_empty():
		return amount
	var st := t.get_modifier("orb_stealth")
	if not st.is_empty() and bool(st.invisible):
		amount *= 1.0 - float(st.resist)
	var hl := t.get_modifier("orb_healing")
	if not hl.is_empty() and from_hero and amount > 0.0:
		hl["hurt_until"] = w.time + 3.0
	var sh := t.get_modifier("orb_shield")
	if not sh.is_empty() and amount > 0.0:
		var b := float(sh.barrier)
		var took := minf(b, amount)
		sh["barrier"] = b - took
		amount -= took
		if float(sh.barrier) <= 0.01:
			t.remove_modifier("orb_shield")
		w.events.append({"t": "barrier", "u": t.id, "amount": took})
	return amount

## Healing Orb regeneration per second for `u`: (hp, mana). Read only (the HUD calls it too); the buff ends in
## update() once health and mana are both full.
func healing(u: SimUnit) -> Vector2:
	var m := u.get_modifier("orb_healing")
	if m.is_empty():
		return Vector2.ZERO
	var pct := 0.01 if w.time < float(m.hurt_until) else float(m.regen_pct)
	return Vector2(u.max_hp * pct, u.max_mana * pct)

## Magic Orb: cooldowns x0.75, mana costs x0.7.
static func cooldown_mult(u: SimUnit) -> float:
	var m := u.get_modifier("orb_magic")
	return 1.0 - float(m.cdr) if not m.is_empty() else 1.0

static func mana_mult(u: SimUnit) -> float:
	var m := u.get_modifier("orb_magic")
	return 1.0 - float(m.mana_cut) if not m.is_empty() else 1.0
