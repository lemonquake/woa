class_name SimCommands
extends RefCounted
## Every action a player takes, as plain data the simulation applies: orders, shop and item actions, learning, the
## courier, pings, chat, Fortify, buyback, pause. The interface never changes the simulation itself; it builds one of
## these and hands it to Main.act(), which applies it at once (single player) or sends it through the network session
## to be applied on every machine at the same tick (multiplayer). A command only ever acts for the hero of the player
## who sent it (and that hero's courier), whatever unit ids it names.
##
## Kinds (field "k") and their fields:
##   order {u, o}            o: an order dictionary (SimOrders.issue); u: the hero, its courier or a beast it leads
##   courier_move {p}        courier {cmd}            courier_idle
##   ping {p, target, kind}  chat {text}              glyph
##   buy {item}              buy_listed {i}           to_buy_add {item}   to_buy_remove {i}   to_buy_auto {i}
##   to_buy_clear            sell {slot, stash}       disassemble {slot, stash}               lock {slot, stash}
##   swap {a, b}             to_stash {slot}          from_stash {slot, to}                   grab_all
##   learn {ability}         talent {tier, side}      autocast {ability}  buyback
##   pause                   resume

const C = preload("res://src/sim/sim_const.gd")

## Apply command `c` for the player whose hero is `hero_id`. Returns "" or an error for the player ("Not enough gold").
## emit_errors: also put the error in the event stream for that hero (multiplayer, where the command runs later).
static func apply(w: SimWorld, hero_id: int, c: Dictionary, emit_errors := false) -> String:
	var err := _apply(w, hero_id, c)
	if err != "" and emit_errors:
		w.events.append({"t": "error", "u": hero_id, "msg": err})
	return err

static func _apply(w: SimWorld, hero_id: int, c: Dictionary) -> String:
	var h := w.get_unit(hero_id)
	if h == null:
		return "No hero"
	var k := String(c.get("k", ""))
	match k:
		"order":
			var uid := int(c.get("u", hero_id))
			if uid != h.id and uid != h.courier_id and not w.abilities.commands(h, w.get_unit(uid)):
				return ""
			var o = c.get("o", {})
			if not (o is Dictionary):
				return ""
			var od := (o as Dictionary).duplicate(true)
			if od.has("point"):
				od.point = _spot(od.point)        # a point off the map (or not a number) aims at the map's edge
			w.command(uid, od)
		"courier_move":
			return w.courier_move(h, _v2(c.get("p")))
		"courier":
			return w.courier_command(h, String(c.get("cmd", "")))
		"courier_idle":
			var cu := w.get_unit(h.courier_id)
			if cu != null:
				cu.courier_state = "idle"
		"ping":
			w.ping(h.team, _v2(c.get("p")), h.id, int(c.get("target", -1)), String(c.get("kind", "")))
		"chat":
			var text := String(c.get("text", "")).strip_edges().left(C.CHAT_MAX_LEN)
			if text != "":
				w.chat(h.team, h.id, text, bool(c.get("all", false)))
		"glyph":
			if not w.glyph(h.team, h.id):
				return "Fortify is not ready"
		"buy":
			return w.shop.buy(h, String(c.get("item", "")))
		"buy_listed":
			return w.shop.buy_listed(h, int(c.get("i", -1)))
		"to_buy_add":
			return w.shop.add_to_buy(h, String(c.get("item", "")))
		"to_buy_remove":
			w.shop.remove_to_buy(h, int(c.get("i", -1)))
		"to_buy_auto":
			w.shop.toggle_auto_buy(h, int(c.get("i", -1)))
		"to_buy_clear":
			h.to_buy.clear()
		"sell":
			var idx := int(c.get("slot", -1))
			return w.shop.sell_stash(h, idx) if bool(c.get("stash", false)) else w.shop.sell(h, idx)
		"disassemble":
			return w.shop.disassemble(h, int(c.get("slot", -1)), bool(c.get("stash", false)))
		"lock":
			return w.shop.toggle_lock(h, int(c.get("slot", -1)), bool(c.get("stash", false)))
		"swap":
			var a := int(c.get("a", -1))
			var b := int(c.get("b", -1))
			if a < 0 or b < 0 or a >= h.inventory.size() or b >= h.inventory.size():
				return ""
			w.shop.swap(h, a, b)
		"to_stash":
			return w.shop.to_stash(h, int(c.get("slot", -1)))
		"from_stash":
			return w.shop.from_stash(h, int(c.get("slot", -1)), int(c.get("to", -1)))
		"grab_all":
			return w.shop.grab_all(h)
		"learn":
			w.abilities.learn(h, String(c.get("ability", "")))
		"talent":
			w.abilities.learn_talent(h, int(c.get("tier", -1)), int(c.get("side", -1)))
		"autocast":
			w.abilities.toggle_autocast(h, String(c.get("ability", "")))
		"buyback":
			return w.buyback(h)
		"pause":
			w.paused = true
			w.events.append({"t": "paused", "u": h.id, "on": true})
		"resume":
			w.paused = false
			w.events.append({"t": "paused", "u": h.id, "on": false})
	return ""

static func _v2(v) -> Vector2:
	return v if v is Vector2 else Vector2.ZERO

## An order's point, finite and on the map.
static func _spot(v) -> Vector2:
	var p := _v2(v)
	if not p.is_finite():
		return Vector2.ZERO
	return p.clamp(-Vector2.ONE * (SimMap.EDGE - 1.0), Vector2.ONE * (SimMap.EDGE - 1.0))
