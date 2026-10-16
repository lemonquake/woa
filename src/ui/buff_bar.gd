class_name BuffBar
extends RefCounted
## The buff bar over the skills, like Dota's: every buff, debuff, aura and status on the unit the bottom panel shows.
## Buffs sit on the left with a green rim, debuffs on the right with a red one; when one row is full the bar grows
## upward, with smaller icons when crowded and a "+N" slot when even those do not fit. Each instance is its own icon
## (two Stench clouds from two Sludges, every burn); a counter (Kragg's Charge) shows its number. A timed one darkens
## clockwise as it runs out, like a cooldown, with the seconds left along its foot; auras and lasting effects have no
## timer. Hover for its name, who applied it, what it does and how long is left.
## Debuffs: disables (stun, hex, silence, root, disarm, mute, break), slows, lowered stats (armor, attack speed),
## damage taken, healing cut, reveals, burns, and enemy auras.

const C = preload("res://src/sim/sim_const.gd")
const U = preload("res://src/ui/ui_kit.gd")

const SIZE := 32.0                         # icon side at the 1080p layout
const SIZES := [32.0, 28.0, 24.0]          # smaller icons when the rows are full
const GAP := 4.0
const MAX_ROWS := 3
const BUFF_COL := Color(0.45, 0.9, 0.4)
const DEBUFF_COL := Color(1.0, 0.36, 0.3)

## Marks that only feed other visuals or are shown another way ("burning" sums the burns, which show one by one).
const HIDDEN := {"burning": true, "hook_lock": true}

## Names for effects that are not an ability, item or aura of their own.
const NAMES := {"stunned": "Stunned", "bashed": "Bashed", "frosted": "Frozen", "burning": "Burning",
	"fountain": "Fountain", "flying": "Flying", "courier_burst": "Speed Burst", "courier_shield": "Shield",
	"aura_regen": "Health Regen Aura", "aura_mana": "Mana Regen Aura", "ward_invis": "Invisible",
	"orb_speed": "Speed Orb", "orb_damage": "Damage Orb", "orb_stealth": "Stealth Orb", "orb_healing": "Healing Orb",
	"orb_magic": "Magic Orb", "orb_shield": "Shield Orb", "reveal_dust": "Revealed", "corruption": "Armor Loss",
	"magnet_charge": "Charge", "unholy_fatigue": "Tired", "tainted_curse": "Curse", "static_charge": "Static Charge",
	"fortify_mark": "Fortify Mark", "ensnared": "Caught", "piloting": "In a Turret", "piloted": "Piloted",
	"void_rush_buff": "Void Rush", "dark_matter_slow": "Dark Matter Skin"}

## Icons for those (assets/ui/<path>.svg); abilities and items use their own.
const ICONS := {"stunned": "status/stunned", "bashed": "status/stunned", "frosted": "status/frozen",
	"burning": "status/burning", "fountain": "status/aura_mending", "flying": "status/windswept",
	"courier_burst": "status/haste", "courier_shield": "status/shielded", "aura_regen": "status/aura_mending",
	"aura_mana": "status/aura_clarity", "ward_invis": "status/stealth", "orb_speed": "status/haste",
	"orb_damage": "status/valor", "orb_stealth": "status/stealth", "orb_healing": "status/regen",
	"orb_magic": "status/overcharged", "orb_shield": "status/shielded", "reveal_dust": "status/dazzled",
	"corruption": "status/armor_broken", "magnet_charge": "status/overcharged", "unholy_fatigue": "status/weakened",
	"tainted_curse": "status/cursed", "static_charge": "status/shocked", "fortify_mark": "status/marked",
	"ensnared": "status/webbed", "piloted": "status/fortified"}

## Endings that name a part of an ability or item (Leap Strike's slow is "leap_strike_slow").
const SUFFIXES := ["_slow", "_stun", "_armor", "_curse", "_aura"]

## Stat labels for tooltips; the ones in PCT are fractions shown as percent.
const STAT_NAMES := {"armor": "armor", "attack_speed": "attack speed", "move_speed": "move speed",
	"move_speed_pct": "move speed", "damage": "damage", "base_damage_pct": "base damage", "magic_resist": "magic resistance",
	"hp_regen": "health regen", "mana_regen": "mana regen", "spell_amp": "spell amp", "lifesteal": "lifesteal",
	"lifesteal_ability": "lifesteal", "evasion": "evasion", "status_resist": "status resistance",
	"slow_resist": "slow resistance", "str": "strength", "agi": "agility", "int": "intelligence", "hp": "health",
	"mana": "mana", "range": "attack range", "range_melee": "attack range", "cast_range": "cast range",
	"heal_amp": "healing amp", "cooldown_reduction": "cooldown reduction", "attack_out_pct": "attack damage",
	"spell_lifesteal": "spell lifesteal", "mana_regen_amp": "mana regen amp", "magic_amp": "magic amp",
	"max_mana_pct": "max mana", "hp_regen_pct_missing": "missing health regen", "cast_speed": "cast speed",
	"mana_cost_cut": "mana cost cut", "aoe_bonus": "spell area", "damage_out_pct": "damage dealt",
	"attack_speed_pct": "attack speed", "range_form": "attack range"}
const PCT := ["move_speed_pct", "base_damage_pct", "magic_resist", "spell_amp", "lifesteal", "lifesteal_ability",
	"evasion", "status_resist", "slow_resist", "heal_amp", "cooldown_reduction", "attack_out_pct", "spell_lifesteal",
	"mana_regen_amp", "magic_amp", "max_mana_pct", "hp_regen_pct_missing", "cast_speed", "mana_cost_cut",
	"damage_out_pct", "attack_speed_pct"]

## Effects named after something else: Blood Ranger's ultimate is the ability "blood_ranger_ult".
const ALIAS := {"blood_ranger": "blood_ranger_ult", "void_rush_buff": "void_rush", "dark_matter_slow": "dark_matter_skin",
	"ensnared": "lay_trap", "piloting": "pilot_turret", "piloted": "pilot_turret"}

static var _index := {}                    # effect id -> {name, item | icon}: auras, creep attack effects, item uses

# ---- What an effect is ---------------------------------------------------------------------------------------------

## Effects that are not an ability or item id of their own: item and creep auras (by their aura's name), creep
## attack effects (Weapon Grab), and item actives whose effect is named after the use (Frenzy Mask's "berserk").
static func _lookup(id: String) -> Dictionary:
	if _index.is_empty():
		_index[""] = {}
		for iid in SimData.items():
			var it: Dictionary = SimData.items()[iid]
			for au in it.get("auras", []):
				_index[String(au.id)] = {"name": String(au.get("name", "")), "item": String(iid)}
			var use := String(it.get("use", ""))
			if use != "" and SimData.item(use).is_empty() and SimData.ability(use).is_empty() and not _index.has(use):
				_index[use] = {"name": String(it.name), "item": String(iid)}
		for d in SimData.units().values():
			for au in d.get("auras", []):
				_index[String(au.id)] = {"name": String(au.get("name", "")), "icon": "status/aura_might"}
			if d.has("on_hit"):
				var oh: Dictionary = d.on_hit
				_index[String(oh.id)] = {"name": String(oh.name),
					"icon": "status/staggered" if oh.get("break", false) else "status/sundered"}
	return _index.get(id, {})

## The ability or item an effect id belongs to ("" when none), trying the id itself and then without a suffix.
static func base_of(id: String) -> String:
	if ALIAS.has(id):
		return String(ALIAS[id])
	if _known(id):
		return id
	for s in SUFFIXES:
		if id.ends_with(s) and _known(id.trim_suffix(s)):
			return id.trim_suffix(s)
	return ""

static func _known(id: String) -> bool:
	return not SimData.ability(id).is_empty() or not SimData.item(id).is_empty() or not _lookup(id).is_empty()

## The player-facing name of an effect id ("" when it has none: the census lists those).
static func name_of(id: String) -> String:
	if NAMES.has(id):
		return String(NAMES[id])
	var b := base_of(id)
	if b == "":
		return ""
	var x := _lookup(b)
	if not x.is_empty():
		return String(x.name)
	var d := SimData.ability(b)
	if d.is_empty():
		d = SimData.item(b)
	return String(d.get("name", ""))

static func icon_of(id: String, m: Dictionary) -> Texture2D:
	if ICONS.has(id):
		return U.icon(String(ICONS[id]))
	var b := base_of(id)
	var x := _lookup(b)
	if x.has("item"):
		return U.item_icon(String(x.item))
	if x.has("icon"):
		return U.icon(String(x.icon))
	if b != "" and U.ABILITY_ICONS.has(b):
		return U.ability_icon(b)
	if b != "" and U.NEUTRAL_SKILL_ICONS.has(b):
		return U.icon(String(U.NEUTRAL_SKILL_ICONS[b]))
	if b != "" and not SimData.item(b).is_empty():
		return U.item_icon(b)
	var fx := String(m.get("fx", ""))
	if fx != "" and UnitBars.STATUS_ICONS.has(fx):
		return U.icon(String(UnitBars.STATUS_ICONS[fx]))
	var dk := SimStatus.disable_kind(m)
	if dk != "":
		return U.icon({"Stunned": "status/stunned", "Frosted": "status/frozen", "Hexed": "status/enfeebled",
			"Silenced": "status/silenced", "Rooted": "status/webbed", "Disarmed": "status/sundered",
			"Broken": "status/staggered", "Muted": "status/silenced"}.get(dk, "status/weakened"))
	if b != "" and not SimData.ability(b).is_empty():
		return U.ability_icon(b)
	return U.icon("status/vigor")

## Whether an effect hurts its unit. Disables, slows, lowered stats, more damage taken, less healing and reveals
## always count as debuffs whoever put them there; otherwise the effect's own flag (set for enemy debuffs and enemy
## auras).
static func is_debuff(_u: SimUnit, m: Dictionary) -> bool:
	if SimStatus.disable_kind(m) != "" or float(m.get("slow", 0.0)) > 0.0:
		return true
	if float(m.get("defense_loss", 0.0)) > 0.0 or float(m.get("heal_reduction", 0.0)) > 0.0 or m.has("truesight_by"):
		return true
	if bool(m.get("debuff", false)):
		return true
	var st: Dictionary = m.get("stats", {})
	if not st.is_empty():
		var neg := 0
		for k in st:
			if float(st[k]) < 0.0:
				neg += 1
		if neg > 0 and neg == st.size():
			return true
	return false

static func is_aura(m: Dictionary) -> bool:
	return bool(m.get("aura", false)) or int(m.get("source", 0)) == SimItems.AURA_SRC

## How long a timed effect lasts in all (0: untimed, an aura, or not known yet).
static func total_time(m: Dictionary, _now: float) -> float:
	var e := float(m.get("expires", INF))
	if not is_finite(e) or is_aura(m):
		return 0.0
	var d := float(m.get("dur", 0.0))
	if d > 0.0:
		return d
	if m.has("t0"):
		return maxf(0.0, e - float(m.t0))
	return 0.0

# ---- The entries shown for a unit -------------------------------------------------------------------------------

## Every icon for `u`, buffs and debuffs in the order they arrived: [{id, name, icon, debuff, aura, left, total,
## count, mod (the modifier, or a burn's entry), burn}].
static func entries(u: SimUnit, w: SimWorld) -> Array:
	var out: Array = []
	if u == null or not u.alive:
		return out
	for m in u.modifiers:
		var id := String(m.id)
		if HIDDEN.has(id):
			continue
		var e := float(m.get("expires", INF))
		var en := {"id": id, "name": _display_name(id), "icon": icon_of(id, m), "debuff": is_debuff(u, m),
			"aura": is_aura(m), "left": e - w.time if is_finite(e) and not is_aura(m) else 0.0,
			"total": total_time(m, w.time), "count": int(m.get("charges", 0)), "mod": m, "burn": false}
		if id == "magnet_charge":
			# how much more of the Kragg's spell damage the Charges add (Magnetize grows with his level)
			var kr := w.get_unit(int(m.get("by", -1)))
			if kr != null and kr.ability_level_of("magnetize") > 0:
				en["amp"] = w.abilities.kits2.amp_per_charge(kr) * float(m.get("charges", 0))
		out.append(en)
	# Kragg's Overload counts his attacks to the next burst (a lasting counter, like Dota's attack counters)
	var oc: Vector2i = w.abilities.kits2.overload_count(u)
	if oc.y > 0:
		out.append({"id": "overload", "name": "Overload", "icon": U.ability_icon("overload"), "debuff": false,
			"aura": false, "left": 0.0, "total": 0.0, "count": oc.x, "mod": {"by": u.id, "counter": oc}, "burn": false})
	for d in w.status.dots_on(u):
		var key := String(d.key)
		var nm := name_of(key)
		out.append({"id": key, "name": nm if nm != "" else "Burning", "icon": U.icon("status/burning") if base_of(key) == "" else icon_of(key, {}),
			"debuff": true, "aura": false, "left": float(d.left), "total": float(d.total), "count": 0, "mod": d,
			"burn": true})
	return out

static func _display_name(id: String) -> String:
	var n := name_of(id)
	return n if n != "" else id.capitalize()

# ---- Tooltip ---------------------------------------------------------------------------------------------------

## Tooltip lines (the HUD's [text, size, colour, font] rows) for one entry on `u`.
static func tip(e: Dictionary, u: SimUnit, w: SimWorld) -> Array:
	var col: Color = DEBUFF_COL if e.debuff else BUFF_COL
	var lines: Array = [[String(e.name), 18, col, "title"]]
	var m: Dictionary = e.mod
	var kind := "Debuff" if e.debuff else "Buff"
	if e.aura:
		kind = "Aura (" + ("enemy" if e.debuff else "ally") + ")"
	var by_id := int(m.get("src", -1)) if e.burn else int(m.get("by", m.get("source", -1)))
	var by := w.get_unit(by_id) if by_id >= 0 else null
	if by != null and by != u:
		kind += "  ·  from " + String(by.look.get("display_name", by.def.get("name", by.name)) if by.is_hero() else by.def.get("name", by.name))
	elif by == u:
		kind += "  ·  its own"
	lines.append([kind, 13, U.TEXT_DIM, "body"])
	for l in effects(e, u):
		for wl in U.wrap(String(l), 320, 14):
			lines.append([wl, 14, U.TEXT, "body"])
	if float(e.left) > 0.0:
		var t := "%.1f s left" % float(e.left)
		if float(e.total) > 0.0:
			t += " of %.1f" % float(e.total)
		lines.append([t, 13, Color(0.6, 0.75, 1.0), "body"])
	elif e.aura:
		lines.append(["Lasts while in range", 13, Color(0.6, 0.75, 1.0), "body"])
	var dsp := String(m.get("dispel", "")) if not e.burn else ""
	if dsp == "basic":
		lines.append(["Any dispel removes it", 12, U.TEXT_DIM, "body"])
	elif dsp == "strong":
		lines.append(["Only a strong dispel removes it", 12, U.TEXT_DIM, "body"])
	return lines

## What an effect does, as short sentences, read from its fields.
static func effects(e: Dictionary, u: SimUnit) -> Array:
	var m: Dictionary = e.mod
	var out: Array = []
	if e.burn:
		out.append("Takes %d magic damage per second." % roundi(float(m.dps)))
		return out
	match SimStatus.disable_kind(m):
		"Stunned":
			out.append("Stunned: cannot move, attack, cast or use items.")
		"Frosted":
			out.append("Frozen solid: cannot move, attack, cast or use items.")
		"Hexed":
			out.append("Hexed: a harmless critter that cannot attack, cast or use items.")
		"Silenced":
			out.append("Silenced: cannot cast spells.")
		"Rooted":
			out.append("Rooted: cannot move.")
		"Disarmed":
			out.append("Disarmed: cannot attack.")
		"Broken":
			out.append("Broken: its passive abilities do nothing.")
		"Muted":
			out.append("Muted: cannot use items.")
	# a second kind of disable on the same effect (Hex covers silence and the rest)
	for k in [["silence", "Silenced"], ["root", "Rooted"], ["disarm", "Disarmed"], ["mute", "Muted"], ["break", "Broken"]]:
		if m.get(k[0], false) and SimStatus.disable_kind(m) != k[1] and not m.get("stun", false) and not m.get("hex", false):
			out.append(String(k[1]) + ".")
	var slow := float(m.get("slow", 0.0))
	if slow > 0.0:
		out.append("Moves %d%% slower." % roundi(slow * 100.0))
	var st: Dictionary = m.get("stats", {})
	var parts: Array = []
	for k in st:
		var v := float(st[k])
		if is_zero_approx(v):
			continue
		var key := String(k).trim_suffix("_max")
		var label := String(STAT_NAMES.get(key, key.replace("_", " ")))
		if key in PCT:
			parts.append("%s%d%% %s" % ["+" if v > 0.0 else "-", roundi(absf(v) * 100.0), label])
		else:
			var num := ("%d" % roundi(absf(v))) if is_equal_approx(absf(v), roundf(absf(v))) else ("%.1f" % absf(v))
			parts.append("%s%s %s" % ["+" if v > 0.0 else "-", num, label])
	if not parts.is_empty():
		out.append(", ".join(parts) + ".")
	if float(m.get("regen", 0.0)) > 0.0:
		out.append("Restores %s health per second." % _num(float(m.regen)))
	if float(m.get("regen_pct", 0.0)) > 0.0:
		out.append("Restores %d%% of max health per second." % roundi(float(m.regen_pct) * 100.0))
	if float(m.get("mana_regen", 0.0)) > 0.0:
		out.append("Restores %s mana per second." % _num(float(m.mana_regen)))
	if float(m.get("block_all", 0.0)) > 0.0:
		out.append("Blocks %d damage from every hit." % roundi(float(m.block_all)))
	if float(m.get("defense_loss", 0.0)) > 0.0:
		out.append("Takes %d%% more damage." % roundi(float(m.defense_loss) * 100.0))
	if float(m.get("heal_reduction", 0.0)) > 0.0:
		out.append("Healing and regen %d%% weaker." % roundi(float(m.heal_reduction) * 100.0))
	if float(m.get("barrier", 0.0)) > 0.0:
		out.append("A shield takes the next %d damage." % roundi(float(m.barrier)))
	if float(m.get("cdr", 0.0)) > 0.0:
		out.append("Cooldowns %d%% shorter." % roundi(float(m.cdr) * 100.0))
	if float(m.get("mana_cut", 0.0)) > 0.0:
		out.append("Spells cost %d%% less mana." % roundi(float(m.mana_cut) * 100.0))
	if m.get("invulnerable", false):
		out.append("Invulnerable: takes no damage and cannot be targeted.")
	if m.get("debuff_immune", false):
		out.append("Immune to debuffs.")
	if m.get("invisible", false) or m.has("fade_until"):
		out.append("Invisible to enemies without true sight.")
	if m.get("phased", false):
		out.append("Walks through units.")
	if m.get("haste", false):
		out.append("Runs at top speed.")
	if m.has("truesight_by"):
		out.append("Seen by the enemy even when invisible.")
	if m.get("fountain", false):
		out.append("Fast health and mana regen at the fountain.")
	if m.get("flying", false):
		out.append("Flies over trees and cliffs.")
	if m.has("counter"):
		var oc: Vector2i = m.counter
		out.append("%d of %d attacks: attack %d bursts in an Overload." % [oc.x, oc.y, oc.y])
	if e.has("amp"):
		out.append("Takes %s%% more damage from Kragg's spells." % _amp_text(float(e.amp) * 100.0))
	if float(m.get("tower_bonus", 0.0)) > 0.0:
		out.append("Fortified towers hit it for %d more physical damage (%d marks)." % [roundi(float(m.tower_bonus)), int(m.get("charges", 0))])
	elif int(m.get("charges", 0)) > 0:
		out.append("%d charge%s." % [int(m.charges), "" if int(m.charges) == 1 else "s"])
	if out.is_empty():
		var b := base_of(String(e.id))
		var txt := ""
		if b != "":
			var d := SimData.ability(b)
			if d.is_empty():
				d = SimData.item(b)
			txt = String(d.get("desc", d.get("text", "")))
		if txt != "":
			var dot := txt.find(". ")
			out.append(txt.substr(0, dot + 1) if dot > 0 else txt)
	return out

static func _amp_text(pct: float) -> String:
	return "%.2f" % pct if pct < 10.0 else "%.1f" % pct

static func _num(v: float) -> String:
	return ("%d" % roundi(v)) if absf(v - roundf(v)) < 0.05 else ("%.1f" % v)

# ---- Layout and drawing ------------------------------------------------------------------------------------------

## Icon rects for `n_buff` buffs and `n_debuff` debuffs in the area from x0 to x1 whose lowest row ends at y_bottom:
## buffs from the left, debuffs from the right; a full row sends the rest to a row above. Returns [buff_rects,
## debuff_rects] (only those that fit).
static func layout(n_buff: int, n_debuff: int, x0: float, x1: float, y_bottom: float, s := SIZE) -> Array:
	var step := s + GAP
	var per := maxi(2, int((x1 - x0 + GAP) / step))
	var br: Array = []
	var dr: Array = []
	var b := n_buff
	var d := n_debuff
	var row := 0
	while (b > 0 or d > 0) and row < MAX_ROWS:
		var nd := mini(d, ceili(per / 2.0))
		var nb := mini(b, per - nd)
		nd = mini(d, per - nb)
		var y := y_bottom - s - row * step
		for i in nb:
			br.append(Rect2(x0 + i * step, y, s, s))
		for i in nd:
			dr.append(Rect2(x1 - s - i * step, y, s, s))
		b -= nb
		d -= nd
		row += 1
	return [br, dr]

## Draw the bar for `u` on `ci` and return the icon rects drawn (for hit tests). Shows the tooltip of the icon under
## the mouse through hud.show_tip.
static func draw(ci: CanvasItem, hud, u: SimUnit, w: SimWorld, x0: float, x1: float, y_bottom: float) -> Array:
	var all := entries(u, w)
	var buffs: Array = all.filter(func(e): return not e.debuff)
	var debuffs: Array = all.filter(func(e): return e.debuff)
	var rs := fit(buffs.size(), debuffs.size(), x0, x1, y_bottom)
	var m := ci.get_local_mouse_position()
	var drawn: Array = []
	for side in 2:
		var list: Array = buffs if side == 0 else debuffs
		var rects: Array = rs[side]
		for i in rects.size():
			var r: Rect2 = rects[i]
			var hot := r.has_point(m)
			drawn.append(r)
			if i == rects.size() - 1 and list.size() > rects.size():
				# no room left: the last slot counts the rest, and its tooltip lists them
				var rest: Array = list.slice(i)
				_more(ci, rest, side == 1, r, hot)
				if hot and hud != null:
					hud.show_tip(ci.get_global_mouse_position(), _more_tip(rest, side == 1))
				continue
			_icon(ci, list[i], r, hot)
			if hot and hud != null:
				hud.show_tip(ci.get_global_mouse_position(), tip(list[i], u, w))
	return drawn

## The layout at the largest icon size (32, then 28, then 24) that fits everything in MAX_ROWS rows; when even 24
## does not, the 24 layout (draw turns each side's last slot into a "+N").
static func fit(n_buff: int, n_debuff: int, x0: float, x1: float, y_bottom: float) -> Array:
	var rs: Array = []
	for s in SIZES:
		rs = layout(n_buff, n_debuff, x0, x1, y_bottom, s)
		if (rs[0] as Array).size() == n_buff and (rs[1] as Array).size() == n_debuff:
			return rs
	# share the slots that exist: a side that overflows gets what the other leaves
	var cap: int = (layout(1000, 0, x0, x1, y_bottom, SIZES[-1])[0] as Array).size()
	var nd := mini(n_debuff, maxi(cap / 2, cap - n_buff))
	var nb := mini(n_buff, cap - nd)
	return layout(nb, nd, x0, x1, y_bottom, SIZES[-1])

static func _more(ci: CanvasItem, rest: Array, debuff: bool, r: Rect2, hot: bool) -> void:
	var col: Color = DEBUFF_COL if debuff else BUFF_COL
	ci.draw_rect(r, Color(0.03, 0.035, 0.05, 0.95))
	ci.draw_rect(r, col.lightened(0.25) if hot else col.darkened(0.15), false, 2.0)
	U.text_c(ci, "+%d" % rest.size(), r.get_center() + Vector2(0, 5), 13, U.TEXT, "bold")

static func _more_tip(rest: Array, debuff: bool) -> Array:
	var lines: Array = [["%d more %s" % [rest.size(), "debuffs" if debuff else "buffs"], 16, DEBUFF_COL if debuff else BUFF_COL, "title"]]
	for e in rest.slice(0, 14):
		var t := String(e.name)
		if float(e.left) > 0.0:
			t += "  %d s" % ceili(float(e.left))
		lines.append([t, 14, U.TEXT, "body"])
	if rest.size() > 14:
		lines.append(["and %d more" % (rest.size() - 14), 13, U.TEXT_DIM, "body"])
	return lines

static func _icon(ci: CanvasItem, e: Dictionary, r: Rect2, hot: bool) -> void:
	var col: Color = DEBUFF_COL if e.debuff else BUFF_COL
	ci.draw_rect(r, Color(0.03, 0.035, 0.05, 0.95))
	var ic: Texture2D = e.icon
	if ic:
		ci.draw_texture_rect(ic, r.grow(-2), false)
	var total := float(e.total)
	var left := float(e.left)
	if total > 0.0 and left > 0.0:
		# the spent part darkens clockwise from the top, like a cooldown sweep
		_sweep(ci, r.grow(-2), clampf(1.0 - left / total, 0.0, 1.0))
	ci.draw_rect(r, col.lightened(0.25) if hot else col.darkened(0.15), false, 2.0)
	if e.aura:
		# auras: a thin inner rim
		ci.draw_rect(r.grow(-3), Color(col, 0.55), false, 1.0)
	# the seconds left along the foot (the icon stays readable), the stack count at the top right
	var fs := 12 if r.size.x >= 30.0 else 10
	if left > 0.0:
		var s := str(ceili(left)) if left >= 1.0 else "%.1f" % left
		U.text_c(ci, s, Vector2(r.get_center().x, r.end.y - 3.0), fs, Color(1, 1, 1), "bold")
	if int(e.count) > 1 or (int(e.count) > 0 and (e.mod as Dictionary).has("counter")):
		U.text_r(ci, str(int(e.count)), Vector2(r.end.x - 2.0, r.position.y + fs), fs, U.GOLD, "bold")

static func _sweep(ci: CanvasItem, r: Rect2, spent: float) -> void:
	if spent <= 0.0:
		return
	var c := r.get_center()
	var rad := r.size.length() * 0.5
	var steps := maxi(4, int(32.0 * spent))
	var start := -PI * 0.5
	var pts := PackedVector2Array([c])
	for i in steps + 1:
		var a := start + TAU * spent * float(i) / steps
		var p := c + Vector2(cos(a), sin(a)) * rad
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.y = clampf(p.y, r.position.y, r.end.y)
		if p.distance_squared_to(pts[pts.size() - 1]) > 0.25:
			pts.append(p)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, Color(0.0, 0.0, 0.02, 0.62))
