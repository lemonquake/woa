class_name SimBotItems
extends RefCounted
## What a bot knows about items (run 2026-10-15 g): what each defensive or utility item answers, what the enemy team
## threatens, what killed the bot, and from that which item it should buy next and when.
##
## The enemy profile is built from what any player can see: the enemy heroes, their levels and items (Dota shows
## them on click) and their spells. It weighs each enemy by how much it is ahead in net worth, so a fed nuker counts
## more than a starving one. The bot also keeps a record of the damage that killed it (its last 20 s of damage taken,
## by type) so it learns, game by game, whether it dies to spells or to right clicks.
##
## Choices follow ordinary Dota thinking: magic burst -> magic resistance early (Scarf, Spell Cloak), Spell Shield for
## a core facing several disablers, Fade Cape for a support who keeps an ally (or itself) alive; fed right-clickers ->
## armor or evasion (Spike Armor on a strength core, Halberd against one hitter, Moth Blade / Burning Cape for agility,
## Frost Plate for an intelligence hero, Medic Kit / Guard Boots / Team Shield for supports); invisible enemies ->
## Reveal Dust and a Reveal Ward; enemies with evasion -> Sure Hit Staff; dying alone with nothing to escape with ->
## Jump Knife, Push Staff or Slip Boots.

const KITS = preload("res://src/sim/sim_bot_kits.gd")
const C = preload("res://src/sim/sim_const.gd")

## What an item answers. magic: magic resistance or a magic barrier; physical: armor, evasion, block, returning damage;
## disable: debuff immunity or status resistance; invis: true sight; evasion: hits that cannot miss; save: keeps an
## ally alive; escape: gets the owner out.
const ANSWERS := {
	"shawl": ["magic"], "cloak": ["magic"], "glimmer_cape": ["magic", "save", "escape"],
	"spell_shield": ["magic", "disable"], "twin_swords": ["disable"], "heavy_sword": ["disable"],
	"stun_blade": ["disable"], "kugmo_atuli": ["disable"],
	"spike_armor": ["physical"], "halberd": ["physical"], "battle_armor": ["physical"], "frost_plate": ["physical"],
	"moth_blade": ["physical"], "burning_cape": ["physical"], "block_shield": ["physical"], "team_shield": ["physical"],
	"medic_kit": ["physical", "save"], "guard_boots": ["physical", "save"], "plate_vest": ["physical"],
	"chainmail": ["physical"], "plate_armor": ["physical"],
	"reveal_dust": ["invis"], "reveal_ward": ["invis"],
	"sure_hit_staff": ["evasion"],
	"push_staff": ["save", "escape"], "jump_knife": ["escape"], "slip_boots": ["escape"], "crash_knife": ["escape"],
}

## Items that make their owner invisible (an enemy with one calls for true sight).
const INVIS_ITEMS := ["sneak_blade", "break_blade", "glimmer_cape"]
## Items that give evasion (an enemy core with one calls for sure hits).
const EVASION_ITEMS := ["moth_blade", "burning_cape", "halberd", "dodge_charm"]

## The enemy team's threat as fractions and counts: {magic, physical, pure (shares of their damage, summing to 1),
## disablers, invis, evasion, fed_hitter (the enemy right-clicker furthest ahead, or null), power (their total)}.
static func profile(w: SimWorld, team: int) -> Dictionary:
	var mine := _avg_networth(w, team)
	var mag := 0.0
	var phys := 0.0
	var pure := 0.0
	var disablers := 0
	var invis := 0
	var evasion := 0
	var fed: SimUnit = null
	var vs: SimUnit = null
	for h in w.heroes:
		if h.team == team:
			vs = h
			break
	for e in w.heroes:
		if e.team == team:
			continue
		# a hero far ahead hits harder than its kit alone says
		var weight := clampf(float(e.networth()) / maxf(1.0, mine), 0.5, 2.5)
		# spells: what is ready now, or what the kit deals at this level when they are on cooldown (a hero that just
		# nuked us is still a nuker)
		var kit: Array = KIT_SPELLS.get(String(e.def.id), [0.0, 1.0, 0.0])
		var spells := maxf(KITS.burst(w, e, vs) if e.alive else 0.0, 75.0 * float(e.level) * (1.0 + e.magic_amp))
		var hits := KITS.dps(w, e, vs) * 6.0
		phys += (hits + spells * float(kit[0])) * weight
		mag += spells * float(kit[1]) * weight
		pure += spells * float(kit[2]) * weight
		if KITS.disable_power(String(e.def.id)) >= 0.6 or _owns_any(w, e, ["hex_staff", "stun_blade", "silence_staff", "root_staff", "net_staff", "halberd"]):
			disablers += 1
		if _owns_any(w, e, INVIS_ITEMS):
			invis += 1
		if _owns_any(w, e, EVASION_ITEMS) or String(e.def.id) == "caziel":
			evasion += 1
		if not KITS.backliner(String(e.def.id)) or String(e.def.primary) == "agi":
			if String(e.def.primary) != "int" and (fed == null or e.networth() > fed.networth()):
				fed = e
	var total := maxf(1.0, mag + phys + pure)
	return {"magic": mag / total, "physical": phys / total, "pure": pure / total, "disablers": disablers,
		"invis": invis, "evasion": evasion, "fed_hitter": fed, "fed_ratio": float(fed.networth()) / maxf(1.0, mine) if fed else 0.0}

## How each hero's spell damage splits: [physical, magic, pure] (Blood Ranger's arrows are physical, Sludge's hook
## pure, Unholy Might's reflection pure).
const KIT_SPELLS := {"blood_ranger": [0.8, 0.2, 0.0], "ezee": [0.2, 0.55, 0.25], "sludge": [0.0, 0.5, 0.5],
	"azrin": [0.0, 1.0, 0.0], "froster": [0.0, 1.0, 0.0], "caziel": [0.4, 0.6, 0.0], "tock": [0.0, 1.0, 0.0],
	"kragg": [0.0, 1.0, 0.0], "roydo": [0.0, 1.0, 0.0], "blau": [0.0, 1.0, 0.0],
	"azrael": [0.5, 0.25, 0.25], "airah": [0.0, 1.0, 0.0], "burak": [0.85, 0.0, 0.15], "emelrich": [1.0, 0.0, 0.0],
	"feran": [0.3, 0.7, 0.0], "ghorman": [0.6, 0.4, 0.0], "araki": [0.65, 0.35, 0.0]}

static func _avg_networth(w: SimWorld, team: int) -> float:
	var s := 0.0
	var n := 0
	for h in w.heroes:
		if h.team == team:
			s += float(h.networth())
			n += 1
	return s / maxf(1.0, float(n))

static func _owns_any(w: SimWorld, h: SimUnit, ids: Array) -> bool:
	for id in ids:
		if w.shop.owns(h, String(id)):
			return true
	return false

## Damage by type in the 20 s before a death, from the hero's own record (SimCombat._ledger): [physical, magic, pure].
static func death_damage(h: SimUnit) -> Vector3:
	var out := Vector3.ZERO
	for r in h.recent_in:
		var a := float(r.amount)
		match int(r.type):
			C.DamageType.PHYSICAL:
				out.x += a
			C.DamageType.MAGICAL:
				out.y += a
			_:
				out.z += a
	return out

## How much the hero already answers each threat (0 none .. 1 well): magic resistance, armor, debuff immunity, etc.
static func covered(w: SimWorld, h: SimUnit) -> Dictionary:
	var out := {"magic": clampf((h.magic_resist - 0.25) / 0.3, 0.0, 1.0), "physical": clampf((h.armor - 4.0) / 16.0, 0.0, 1.0),
		"disable": 0.0, "invis": 0.0, "evasion": 0.0, "save": 0.0, "escape": 0.0}
	for id in ANSWERS:
		if w.shop.owns(h, String(id)) or _carries(h, String(id)):
			for a in ANSWERS[id]:
				out[a] = minf(1.0, float(out.get(a, 0.0)) + (0.6 if a in ["disable", "invis", "evasion", "escape", "save"] else 0.35))
	return out

static func _carries(h: SimUnit, id: String) -> bool:
	for arr in [h.inventory, h.stash]:
		for it in arr:
			if it != null and String(it.id) == id:
				return true
	return false

## How badly the hero needs each kind of answer now (0..1), from the enemy profile, its recent deaths (`deaths`:
## [physical, magic, pure] summed over its last deaths) and what it already has.
static func needs(w: SimWorld, h: SimUnit, prof: Dictionary, deaths: Vector3, alone_deaths: int) -> Dictionary:
	var cov := covered(w, h)
	var dsum := maxf(1.0, deaths.x + deaths.y + deaths.z)
	var died := deaths.x + deaths.y + deaths.z > 0.0
	var mag := float(prof.magic) * 0.6 + (deaths.y / dsum * 0.4 if died else float(prof.magic) * 0.4)
	var phys := float(prof.physical) * 0.6 + (deaths.x / dsum * 0.4 if died else float(prof.physical) * 0.4)
	# a fed right-clicker raises the need for armor however the damage splits
	phys = maxf(phys, clampf((float(prof.fed_ratio) - 1.0) * 0.6, 0.0, 0.8))
	var out := {
		"magic": clampf((mag - 0.35) * 2.0, 0.0, 1.0) * (1.0 - float(cov.magic)),
		"physical": clampf((phys - 0.35) * 2.0, 0.0, 1.0) * (1.0 - float(cov.physical)),
		"disable": clampf((float(prof.disablers) - 1.0) / 2.0, 0.0, 1.0) * (1.0 - float(cov.disable)),
		"invis": (0.9 if int(prof.invis) > 0 else 0.0) * (1.0 - float(cov.invis)),
		"evasion": clampf(float(prof.evasion) / 2.0, 0.0, 1.0) * (1.0 - float(cov.evasion)),
		"escape": clampf(float(alone_deaths) / 3.0, 0.0, 1.0) * (1.0 - float(cov.escape)),
	}
	return out

## The items that answer `need` for this hero, best first (role, main attribute, melee or ranged, game time).
static func answers_for(need: String, h: SimUnit, role: int, time: float) -> Array:
	var support := KITS.is_support(role)
	var attr := String(h.def.get("primary", "str"))
	var melee := not h.is_ranged()
	match need:
		"magic":
			if support:
				return ["glimmer_cape", "cloak"]
			if time < 900.0:
				return ["cloak", "spell_shield"] if attr != "int" else ["cloak", "glimmer_cape"]
			return ["spell_shield", "cloak"] if attr != "int" else ["glimmer_cape", "spell_shield"]
		"physical":
			if support:
				return ["medic_kit", "guard_boots", "team_shield", "frost_plate"]
			match attr:
				"str":
					return ["spike_armor", "halberd", "battle_armor", "team_shield"] if melee else ["halberd", "battle_armor"]
				"agi":
					return ["moth_blade", "halberd", "battle_armor", "burning_cape"]
			return ["frost_plate", "halberd", "guard_boots"]
		"disable":
			if support:
				return ["glimmer_cape", "push_staff"]
			return ["spell_shield", "twin_swords"] if attr != "int" else ["spell_shield", "kugmo_atuli"]
		"invis":
			return ["reveal_dust"] if not support else ["reveal_dust", "reveal_ward"]
		"evasion":
			if support or attr == "int":
				return []
			return ["sure_hit_staff"]
		"escape":
			if support:
				return ["push_staff", "glimmer_cape"]
			return ["jump_knife", "slip_boots", "push_staff"] if melee else ["push_staff", "slip_boots"]
	return []

## The one item the bot should move to the front of its list now, or "" (nothing pressing). Consumables (Reveal
## Dust and Ward) come back as their id and are bought straight away by the caller.
static func next_counter(w: SimWorld, h: SimUnit, role: int, build: Array, from_i: int, prof: Dictionary,
		deaths: Vector3, alone_deaths: int) -> String:
	var nd := needs(w, h, prof, deaths, alone_deaths)
	var best := ""
	var best_v := 0.45                    # below this nothing is pressing enough to change the plan
	for k in nd:
		var v := float(nd[k])
		if v <= best_v or k == "invis":
			continue                       # true sight is bought on its own (wants_sight)
		for id in answers_for(String(k), h, role, w.time):
			if w.shop.owns(h, String(id)) or _carries(h, String(id)):
				break                      # it has the first answer already
			# one it cannot afford for minutes is no answer now: early on, pick the cheaper one
			var cost := float(SimData.item(String(id)).get("cost", 0))
			if w.time < 1200.0 and cost > 4500.0:
				continue
			var at := build.find(String(id))
			if at >= from_i and at <= from_i + 1:
				break                      # already next in line
			best = String(id)
			best_v = v
			break
	return best

## True sight to carry against invisible enemies: Reveal Dust for anyone who has none (supports first: a core only
## when no support carries any), a Reveal Ward for a support. "" when nothing is needed.
static func wants_sight(w: SimWorld, h: SimUnit, role: int, prof: Dictionary) -> String:
	if int(prof.invis) <= 0:
		return ""
	if not _carries(h, "reveal_dust"):
		if KITS.is_support(role):
			return "reveal_dust"
		for a in w.heroes:
			if a.team == h.team and a != h and _carries(a, "reveal_dust"):
				return ""
		return "reveal_dust"
	if KITS.is_support(role) and not _carries(h, "reveal_ward"):
		return "reveal_ward"
	return ""
