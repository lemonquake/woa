class_name SimBotLog
extends RefCounted
## What one bot did, for the Debug panel's Bot Log: how often it thought, every order it gave (and whether its own
## thinking or a team call / player command gave it), every spell and item it actually used, mode changes with the
## scores behind them, team calls it received and what it said. Counters cover the whole match; the entries are the
## last MAX_ENTRIES. Recording never changes what the bot does (lockstep safe); it is left out of snapshots.

const MAX_ENTRIES := 160

var thinks := 0
var orders := 0                            # every order the bot sent to its hero
var from_thought := 0                      # orders its own modes gave (lane, farm, fight, retreat ...)
var from_command := 0                      # orders while following a team call or a player's chat command
var orders_by_kind := {}                   # "Move" / "Attack" / "Cast" / "Item" ... -> count
var casts := {}                            # ability id -> times it went off
var cast_orders := {}                      # ability id -> times the bot ordered it (more than casts: refused, cut)
var items := {}                            # item id -> times used
var modes := {}                            # mode -> seconds spent in it
var mode_changes := 0
var calls := 0                             # team calls received (gank, push, defend, save ...)
var said := 0
var entries: Array = []                    # [game time, kind, text]
var _last_task := -1

func add(t: float, kind: String, text: String) -> void:
	entries.append([t, kind, text])
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()

func on_think(dt: float, mode: String) -> void:
	thinks += 1
	modes[mode] = float(modes.get(mode, 0.0)) + dt

func on_mode(t: float, old: String, new_mode: String, desires: Dictionary) -> void:
	mode_changes += 1
	var top: Array = desires.keys()
	top.sort_custom(func(a, b): return float(desires[a]) > float(desires[b]))
	var why: Array = []
	for k in top.slice(0, 3):
		why.append("%s %.2f" % [k, float(desires[k])])
	add(t, "mode", "%s -> %s  (%s)" % [old, new_mode, ", ".join(why)])

func on_task(t: float, task: Dictionary) -> void:
	var id := int(task.get("id", -1))
	if task.is_empty() or id == _last_task:
		return
	_last_task = id
	calls += 1
	var where := String(task.get("lane", task.get("where", "")))
	add(t, "call", "team call: %s%s" % [String(task.get("kind", "?")), (" " + where) if where != "" else ""])

const KIND_NAMES := {0: "None", 1: "Move", 2: "Attack", 3: "Attack move", 4: "Hold", 5: "Stop"}

func on_order(t: float, o: Dictionary, mode: String, kind_name: String, w: SimWorld) -> void:
	orders += 1
	var cmd := mode == "task"
	if cmd:
		from_command += 1
	else:
		from_thought += 1
	var aid := String(o.get("ability", ""))
	var label := kind_name
	if aid != "":
		label = "Cast"
		cast_orders[aid] = int(cast_orders.get(aid, 0)) + 1
	elif o.has("item_slot"):
		label = "Item"
	orders_by_kind[label] = int(orders_by_kind.get(label, 0)) + 1
	# moves and attacks are many and alike: only casts, items and the first order of a new kind are written out
	if label in ["Cast", "Item"] or entries.is_empty() or String(entries[-1][1]) != "order" \
			or not String(entries[-1][2]).begins_with(label):
		var what := label
		if aid != "":
			what += " " + _ability_name(aid)
		var tgt := w.get_unit(int(o.get("target", -1)))
		if tgt != null:
			what += " on " + (tgt.who() if tgt.is_hero() else String(tgt.name))
		elif o.has("point") and label != "Move":
			var p: Vector2 = o.point
			what += " at (%d, %d)" % [int(p.x), int(p.y)]
		add(t, "order", what + ("  [team call]" if cmd else "  [" + mode + "]"))

func on_cast(t: float, aid: String) -> void:
	casts[aid] = int(casts.get(aid, 0)) + 1
	add(t, "cast", "used " + _ability_name(aid))

static func _ability_name(aid: String) -> String:
	return "Town Portal" if aid == "tp" else String(SimData.ability(aid).get("name", aid))

func on_item(t: float, iid: String) -> void:
	items[iid] = int(items.get(iid, 0)) + 1
	add(t, "item", "used " + String(SimData.item(iid).get("name", iid)))

func on_say(t: float, text: String) -> void:
	said += 1
	add(t, "chat", "said: " + text)

## A plain-text summary (Debug panel, Save Bot Log, tools).
func summary(bot_name: String, hero_label: String, mode: String, now: float) -> String:
	var lines: Array = []
	lines.append("%s (%s): now %s" % [bot_name, hero_label, mode])
	var mins := maxf(now / 60.0, 1.0 / 60.0)
	lines.append("  thoughts %d   orders %d (own thinking %d, team calls %d)   %.0f orders a minute" % [thinks, orders,
		from_thought, from_command, float(orders) / maxf(mins, 0.5)])
	var kinds: Array = []
	for k in orders_by_kind:
		kinds.append("%s %d" % [k, int(orders_by_kind[k])])
	if not kinds.is_empty():
		lines.append("  orders: " + ", ".join(kinds))
	var sk: Array = []
	for aid in cast_orders:
		sk.append("%s %d of %d" % [_ability_name(aid), int(casts.get(aid, 0)), int(cast_orders[aid])])
	for aid in casts:
		if not cast_orders.has(aid):
			sk.append("%s %d" % [_ability_name(aid), int(casts[aid])])
	lines.append("  skills used (of ordered): " + (", ".join(sk) if not sk.is_empty() else "none"))
	var it: Array = []
	for iid in items:
		it.append("%s %d" % [String(SimData.item(iid).get("name", iid)), int(items[iid])])
	if not it.is_empty():
		lines.append("  items used: " + ", ".join(it))
	var tm: Array = modes.keys()
	tm.sort_custom(func(a, b): return float(modes[a]) > float(modes[b]))
	var ms: Array = []
	for m in tm.slice(0, 6):
		ms.append("%s %ds" % [m, int(modes[m])])
	lines.append("  time by mode: " + ", ".join(ms) + "   mode changes %d   team calls %d   lines said %d" % [mode_changes,
		calls, said])
	return "\n".join(lines)

func recent(n: int) -> String:
	var out: Array = []
	for e in entries.slice(maxi(0, entries.size() - n)):
		var t := float(e[0])
		out.append("%s%d:%02d  %s" % ["-" if t < 0.0 else "", int(absf(t)) / 60, int(absf(t)) % 60, String(e[2])])
	return "\n".join(out)
