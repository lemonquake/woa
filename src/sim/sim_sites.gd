class_name SimSites
extends RefCounted
## Map sites in the outer ground beyond the top and bottom lanes: Dota 2's Twin Gates, Lotus Pools and Watchers with
## plain names (docs/MECHANICS.md "Map sites"). Where they stand comes from SimMap.sites.
##   Warp Gate (Twin Gate): two linked gates, one in each river corner. A hero within 200 channels 4 s for 30 mana
##     (given back if the channel is broken) and steps out beside the other gate. No cooldown. Stuns, silences, roots
##     and any new order break the channel; damage does not.
##   Lily Pond (Lotus Pool): one in each river corner. A Healing Lily grows every 3:00, at most 6 at a time. Heroes of
##     one team within 350 of the pond gather them, the first after 1.5 s and each next one in a row 30% faster; an
##     enemy hero in the area pauses the gathering. A lily goes to a random gathering hero: 125 health and 125 mana.
##   Lookout Lamp (Watcher): a hero within 300 channels 1 s to light it for its team for 7:00: sight 800 by day and 450
##     by night around it (ground sight: trees and higher ground block it). Channelling a lamp the other team holds puts
##     it out for 2:00, and nobody can light it meanwhile.

const C = preload("res://src/sim/sim_const.gd")

const NAMES := {"gate": "Warp Gate", "pond": "Lily Pond", "lamp": "Lookout Lamp"}
const GATE_RANGE := 200.0
const GATE_CHANNEL := 4.0
const GATE_MANA := 30.0
const POND_RANGE := 350.0
const LILY_EVERY := 180.0
const LILY_MAX := 6
const LILY_FIRST := 1.5                    # seconds for the first lily in a row
const LILY_FASTER := 0.7                   # each next lily in a row takes 30% less time
const LILY_HEAL := 125.0
const LILY_MANA := 125.0
const LAMP_RANGE := 300.0
const LAMP_CHANNEL := 1.0
const LAMP_TIME := 420.0
const LAMP_OUT := 120.0
const LAMP_DAY := 800.0
const LAMP_NIGHT := 450.0

var w: SimWorld
## [{id, kind, pos, ...}]; gate: pair (the other gate's id), exit (where a hero comes out); pond: lilies, next (time
## the next lily grows), progress (s), streak (lilies in a row), team (gathering team or -1); lamp: team (-1 dark),
## until (lit until), out_until (put out until).
var sites: Array = []
var stats := {"warp": [0, 0], "lily": [0, 0], "lamp_lit": [0, 0], "lamp_out": [0, 0]}   # per team (reports, tests)

func _init(world: SimWorld = null) -> void:
	w = world
	if w != null:
		build()

func build() -> void:
	sites.clear()
	for s in w.map.sites:
		var d := {"id": sites.size(), "kind": String(s.kind), "pos": s.pos}
		match String(s.kind):
			"gate":
				d["pair"] = int(s.pair)
				d["exit"] = s.exit
			"pond":
				d["lilies"] = 0
				d["next"] = LILY_EVERY
				d["progress"] = 0.0
				d["streak"] = 0
				d["team"] = -1
			"lamp":
				d["team"] = -1
				d["until"] = 0.0
				d["out_until"] = 0.0
		sites.append(d)

func get_site(id: int) -> Dictionary:
	return sites[id] if id >= 0 and id < sites.size() else {}

func of_kind(kind: String) -> Array:
	return sites.filter(func(s): return String(s.kind) == kind)

func site_name(s: Dictionary) -> String:
	return String(NAMES.get(String(s.get("kind", "")), "Site"))

## How close a hero must stand to use the site.
static func reach(s: Dictionary) -> float:
	match String(s.kind):
		"gate":
			return GATE_RANGE
		"lamp":
			return LAMP_RANGE
	return POND_RANGE * 0.6

## Whether the lamp is lit for `team` now.
func lamp_lit(s: Dictionary, team: int) -> bool:
	return int(s.team) == team and w.time < float(s.until)

# ---- Every tick -------------------------------------------------------------------------------------------------------

func update() -> void:
	if w.time < 0.0:
		return
	for s in sites:
		match String(s.kind):
			"pond":
				_pond(s)
			"lamp":
				if int(s.team) >= 0 and w.time >= float(s.until):
					s.team = -1
					w.events.append({"t": "site", "id": int(s.id), "what": "lamp_dark"})

func _pond(s: Dictionary) -> void:
	if int(s.lilies) < LILY_MAX and w.time >= float(s.next):
		s.lilies = int(s.lilies) + 1
		s.next = float(s.next) + LILY_EVERY
		w.events.append({"t": "site", "id": int(s.id), "what": "lily_grew", "lilies": int(s.lilies)})
	elif int(s.lilies) >= LILY_MAX:
		s.next = w.time + LILY_EVERY           # a full pond grows the next one 3:00 after a lily is taken
	var near := [[], []]
	for h in w.heroes:
		if h.alive and h.team < 2 and h.pos.distance_to(s.pos) <= POND_RANGE and not h.has_flag("hidden"):
			(near[h.team] as Array).append(h)
	var team := -1
	if not (near[0] as Array).is_empty() and (near[1] as Array).is_empty():
		team = 0
	elif not (near[1] as Array).is_empty() and (near[0] as Array).is_empty():
		team = 1
	elif not (near[0] as Array).is_empty():
		return                                 # both teams there: paused
	if team != int(s.team):
		s.team = team
		s.progress = 0.0
		s.streak = 0
	if team < 0 or int(s.lilies) <= 0:
		s.progress = 0.0
		return
	s.progress = float(s.progress) + C.DT
	var need := LILY_FIRST * pow(LILY_FASTER, int(s.streak))
	if float(s.progress) + 0.0001 < need:
		return
	var who: Array = near[team]
	var h: SimUnit = who[w.rng.randi_range(0, who.size() - 1)]
	s.progress = 0.0
	s.streak = int(s.streak) + 1
	s.lilies = int(s.lilies) - 1
	stats.lily[h.team] += 1
	var got := w.combat.heal(h, LILY_HEAL)
	var before := h.mana
	h.mana = minf(h.max_mana, h.mana + LILY_MANA)
	w.events.append({"t": "site", "id": int(s.id), "what": "lily_taken", "u": h.id, "hp": got, "mana": h.mana - before,
		"lilies": int(s.lilies)})

# ---- Using a site (SimOrders: walk into reach, then this) -------------------------------------------------------------

## Why `u` cannot use site `s` now ("" when it can).
func use_error(u: SimUnit, s: Dictionary) -> String:
	if s.is_empty() or not u.is_hero():
		return "Only heroes can use that"
	match String(s.kind):
		"gate":
			if u.max_mana > 0.0 and u.mana < GATE_MANA:
				return "Not enough mana"
		"lamp":
			if w.time < float(s.out_until):
				return "The lamp is out for %d s" % int(ceil(float(s.out_until) - w.time))
			if lamp_lit(s, u.team):
				return "Your team already holds this lamp"
	return ""

## In reach: start the channel (gate, lamp) or stand and gather (pond). Returns false if it could not start.
func begin(u: SimUnit, s: Dictionary) -> bool:
	var err := use_error(u, s)
	if err != "":
		w.events.append({"t": "error", "u": u.id, "msg": err})
		return false
	match String(s.kind):
		"gate":
			var mana := GATE_MANA if u.max_mana > 0.0 else 0.0
			u.mana -= mana
			u.channel = {"ability": "site_gate", "site": int(s.id), "until": w.time + GATE_CHANNEL, "start": w.time,
				"dur": GATE_CHANNEL, "mana": mana, "point": s.pos}
		"lamp":
			u.channel = {"ability": "site_lamp", "site": int(s.id), "until": w.time + LAMP_CHANNEL, "start": w.time,
				"dur": LAMP_CHANNEL, "point": s.pos}
		_:
			return false
	u.moving = false
	w.events.append({"t": "channel_start", "u": u.id, "ability": String(u.channel.ability), "until": u.channel.until,
		"site": int(s.id)})
	return true

## A site channel ended (SimAbilities.channel_cleanup): finished, or broken.
func channel_end(u: SimUnit, ch: Dictionary, cancelled: bool) -> void:
	var s := get_site(int(ch.get("site", -1)))
	if s.is_empty():
		return
	match String(ch.ability):
		"site_gate":
			if cancelled:
				u.mana = minf(u.max_mana, u.mana + float(ch.get("mana", 0.0)))
				return
			var to := get_site(int(s.pair))
			if to.is_empty() or not u.alive:
				return
			var dest: Vector2 = to.exit
			if not w.map.is_walkable(dest):
				var cc: Vector2i = w.map.nearest_walkable(w.map.world_to_cell(dest))
				dest = w.map.cell_center(cc.x, cc.y)
			var from := u.pos
			w.combat.disjoint(u)
			u.pos = dest
			u.path = PackedVector2Array()
			u.atk_target = -1
			u.facing = (dest - (to.pos as Vector2)).angle()
			stats.warp[u.team] += 1
			w.events.append({"t": "site", "id": int(s.id), "what": "warp", "u": u.id, "from": from, "to": dest,
				"to_site": int(to.id)})
		"site_lamp":
			if cancelled or not u.alive:
				return
			if int(s.team) >= 0 and int(s.team) != u.team and w.time < float(s.until):
				s.team = -1
				s.until = 0.0
				s.out_until = w.time + LAMP_OUT
				stats.lamp_out[u.team] += 1
				w.events.append({"t": "site", "id": int(s.id), "what": "lamp_out", "u": u.id})
			else:
				s.team = u.team
				s.until = w.time + LAMP_TIME
				stats.lamp_lit[u.team] += 1
				w.events.append({"t": "site", "id": int(s.id), "what": "lamp_lit", "u": u.id, "team": u.team})

## Lit lamps' sight for SimVision: [[pos, radius]] for `team`.
func sight(team: int, night: bool) -> Array:
	var out: Array = []
	for s in sites:
		if String(s.kind) == "lamp" and lamp_lit(s, team):
			out.append([s.pos, LAMP_NIGHT if night else LAMP_DAY])
	return out

## The site whose spot is nearest `p` within `r` (any kind), or {}.
func site_at(p: Vector2, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := r
	for s in sites:
		var d := p.distance_to(s.pos)
		if d <= bd:
			bd = d
			best = s
	return best
