class_name SimOrders
extends RefCounted
## Order execution: turning, walking (path following with unit collision), attack animations (attack point,
## backswing, cancels), chasing, holding, attack-move and casting. Target *choice* for AI units lives in SimAI; this
## class carries out whatever target or order a unit has.

const C = preload("res://src/sim/sim_const.gd")
const K = C.Kind
const AP = preload("res://src/sim/sim_unit.gd").AtkPhase
const CP = preload("res://src/sim/sim_unit.gd").CastPhase
const O = C.Order

var w: SimWorld

func _init(world: SimWorld = null) -> void:
	w = world

func clear(u: SimUnit) -> void:
	u.order = O.NONE
	u.order_target = -1
	u.order_queue.clear()
	u.path = PackedVector2Array()
	u.moving = false
	_cancel_windup(u)
	u.atk_phase = AP.NONE
	u.atk_target = -1
	u.cast_phase = CP.NONE

# ---- Issuing ----------------------------------------------------------------------------------------------------------

## Validate and apply an order. from_player: issued by a player or bot (as opposed to the unit's own AI).
func cancel_channel(u: SimUnit) -> void:
	if not u.channel.is_empty():
		var ch := u.channel
		var aid := String(ch.ability)
		u.channel = {}
		if aid == "tp":
			w.events.append({"t": "tp_cancel", "u": u.id})
		else:
			w.abilities.channel_cleanup(u, ch, true)
			w.events.append({"t": "channel_end", "u": u.id, "ability": aid, "cancelled": true})

## Shift-queued orders (o.queue) wait at the end of the queue while the unit is busy; from_queue: this order was just
## taken from the queue, so the rest of the queue stays.
func issue(u: SimUnit, o: Dictionary, from_player: bool, from_queue := false) -> void:
	var type: int = o.get("type", O.NONE)
	if o.get("queue", false) and (not u.is_idle() or not u.channel.is_empty() or not u.order_queue.is_empty()):
		u.order_queue.append(o)
		return
	# any new order breaks a channel, except something that acts at once without a target: an item, a toggle (Stench)
	# or an immediate spell (Blubber), as in Dota
	if not u.channel.is_empty():
		var islot := int(o.get("item_slot", -1))
		var instant := type == O.CAST_NO_TARGET and w.abilities.is_instant(u, String(o.get("ability", "")), islot)
		if not instant:
			cancel_channel(u)
	# Blau inside his turret: a move order (or one to walk to a unit or item) gets him out first
	if u.is_hero() and (type == O.MOVE or type == O.MOVE_TO_UNIT or type == O.PICKUP_ITEM or type == O.PICKUP_ORB) 			and w.abilities.kits3.is_piloting(u):
		w.abilities.kits3.leave_turret(u)
	# A unit inside Azrael's door: a move or attack order brings it out early without setting off the explosion
	if (type == O.MOVE or type == O.MOVE_TO_UNIT or type == O.PICKUP_ITEM or type == O.PICKUP_ORB or type == O.ATTACK_UNIT or type == O.ATTACK_MOVE) 			and w.abilities.kits4.in_door(u):
		w.abilities.kits4.leave_door(u, o.get("point", u.pos))
	# a hard stop (S held) keeps the unit from acquiring targets until it gets another order
	u.no_acquire = type == O.STOP and bool(o.get("hard", false))
	var tgt: SimUnit = w.get_unit(int(o.get("target", -1)))
	match type:
		O.ATTACK_UNIT:
			if tgt == null or not tgt.alive or tgt == u:
				return
			var why := attack_error(u, tgt)
			if why != "":
				w.events.append({"t": "error", "u": u.id, "msg": why})
				return
			# keep an attack already winding up on this target
			if not (u.atk_phase == AP.WINDUP and u.atk_target == tgt.id):
				_interrupt(u)
			u.order = O.ATTACK_UNIT
			u.order_target = tgt.id
			u.atk_target = tgt.id
			u.last_seen = tgt.pos
			if from_player and u.is_hero():
				if tgt.team != u.team and tgt.is_hero():
					w.ai.attack_order_aggro(u)
				elif tgt.team == u.team:
					w.ai.deaggro(u, tgt)
		O.MOVE, O.ATTACK_MOVE:
			_interrupt(u)
			u.order = type
			u.order_point = o.get("point", u.pos)
			u.atk_target = -1
		O.MOVE_TO_UNIT:
			if tgt == null:
				return
			_interrupt(u)
			u.order = type
			u.order_target = tgt.id
		O.DROP_ITEM, O.GIVE_ITEM:
			# walk to the spot (or the receiving unit), then drop or hand over the item in that slot
			var islot2 := int(o.get("item_slot", -1))
			if islot2 < 0 or islot2 >= u.inventory.size() or u.inventory[islot2] == null:
				return
			if type == O.GIVE_ITEM:
				var gerr := give_error(u, tgt)
				if gerr != "":
					w.events.append({"t": "error", "u": u.id, "msg": gerr})
					return
				u.order_target = tgt.id
			_interrupt(u)
			u.order = type
			u.cast_item_slot = islot2
			u.order_point = o.get("point", u.pos)
		O.PICKUP_ITEM:
			var g := w.ground_item(int(o.get("gid", -1)))
			if g.is_empty():
				return
			_interrupt(u)
			u.order = type
			u.order_gid = int(g.gid)
			u.order_point = g.pos
		O.PICKUP_ORB:
			var ob := w.orbs.get_orb(int(o.get("orb", -1)))
			if ob.is_empty() or not u.is_hero():
				return
			_interrupt(u)
			u.order = type
			u.order_gid = int(ob.id)
			u.order_point = ob.pos
		O.STOP:
			clear(u)
			return
		O.HOLD:
			clear(u)
			u.order = O.HOLD
			return
		O.CAST_NO_TARGET, O.CAST_POINT, O.CAST_UNIT:
			var aid := String(o.get("ability", ""))
			if type == O.CAST_UNIT and aid != "" and SimData.ability(aid).get("behavior", "") == "autocast_attack":
				# a hand-cast attack modifier is an attack order that creeps and towers do not react to
				var oerr := w.abilities.cast_error(u, aid, -1, tgt, u.pos)
				if oerr == "":
					oerr = attack_error(u, tgt)
				if oerr != "":
					w.events.append({"t": "error", "u": u.id, "msg": oerr})
					return
				if not (u.atk_phase == AP.WINDUP and u.atk_target == tgt.id):
					_interrupt(u)
				u.order = O.ATTACK_UNIT
				u.order_target = tgt.id
				u.atk_target = tgt.id
				u.last_seen = tgt.pos
				u.orb_manual = aid
				u.order_from_player = from_player
				if not from_queue:
					u.order_queue.clear()
				return
			var slot := int(o.get("item_slot", -1))
			var err := w.abilities.cast_error(u, aid, slot, tgt, o.get("point", u.pos))
			if err != "":
				w.events.append({"t": "error", "u": u.id, "msg": err})
				return
			if w.abilities.is_instant(u, aid, slot):
				# no cast point and no target: happens at once without interrupting anything (items, toggles)
				w.abilities.execute(u, aid, slot, tgt, o.get("point", u.pos))
				return
			_interrupt(u)
			u.order = type
			u.order_ability = aid
			u.cast_item_slot = slot
			u.order_target = tgt.id if tgt else -1
			u.order_point = o.get("point", tgt.pos if tgt else u.pos)
		_:
			return
	u.order_from_player = from_player
	if not from_queue:
		u.order_queue.clear()

## Why `u` may not attack `t` ("" = it may). An attack order on an ally is accepted: the unit follows it and only
## swings once the ally can be denied.
func attack_error(u: SimUnit, t: SimUnit) -> String:
	if not u.can_attack_at_all():
		return "This unit cannot attack"
	if t.is_invulnerable() and t.is_building():
		return "Target is invulnerable"
	if not w.vision.sees(u.team, t):
		return "Target not visible"
	return ""

## Allied lane creeps below 50% health and allied buildings below 10% can be denied.
func can_deny(u: SimUnit, t: SimUnit) -> bool:
	if t.team != u.team:
		return true
	if t.is_lane_creep():
		return t.hp < t.max_hp * 0.5
	if t.is_building() and t.kind != K.ANCIENT and t.kind != K.FOUNTAIN:
		return t.hp < t.max_hp * C.BUILDING_DENY_HEALTH
	if t.is_ward():
		return true
	return false

## A new order cancels a windup (no cooldown spent) and a backswing (free); a cast point is cancelled too.
func _interrupt(u: SimUnit) -> void:
	_cancel_windup(u)
	if u.atk_phase == AP.BACKSWING:
		u.atk_phase = AP.NONE
	if u.cast_phase != CP.NONE:
		u.cast_phase = CP.NONE
	u.path = PackedVector2Array()
	u.path_goal = Vector2(INF, INF)

func _cancel_windup(u: SimUnit) -> void:
	if u.atk_phase == AP.WINDUP:
		u.atk_phase = AP.NONE
		u.next_attack_at = u.prev_attack_at
		w.events.append({"t": "attack_cancel", "u": u.id})

# ---- Update -----------------------------------------------------------------------------------------------------------

func update(u: SimUnit) -> void:
	# fast path: a non-hero with no order, no target and nothing in progress has nothing to do (only heroes acquire
	# targets on their own here; creeps and towers get theirs from SimAI)
	if u.order == O.NONE and u.atk_target < 0 and u.atk_phase == AP.NONE and u.cast_phase == CP.NONE 			and u.kind != K.HERO and u.channel.is_empty() and u.leap.is_empty():
		u.moving = false
		return
	if u.is_leaping():
		u.moving = false
		return
	if not u.channel.is_empty() and String(u.channel.ability) != "tp":
		# an ability channel (Burst Shot, Chomp): stuns, pushes and silence end it (roots too, for abilities that say
		# so); the hero keeps facing the target
		var ch := u.channel
		var breaks_on_root := bool(SimData.ability(String(ch.ability)).get("channel_breaks_on_root", false))
		if u.is_stunned() or u.is_silenced() or (breaks_on_root and u.has_flag("root")):
			cancel_channel(u)
		else:
			if ch.has("point"):
				_turn_towards(u, ((ch.point as Vector2) - u.pos).angle())
			w.abilities.channel_tick(u)
			if u.channel.is_empty():
				pass                                   # ended inside the tick (the victim died)
			elif w.time >= float(ch.until) - 0.0001:
				var aid := String(ch.ability)
				u.channel = {}
				w.abilities.channel_cleanup(u, ch, false)
				u.order = O.NONE
				w.events.append({"t": "channel_end", "u": u.id, "ability": aid, "cancelled": false})
				if not u.order_queue.is_empty():
					_finish_order(u)
			u.moving = false
			return
	if not u.channel.is_empty():
		# Teleport: stuns, hexes and mutes end it, and so do roots (Dota's Town Portal is "root disables")
		if u.is_stunned() or u.is_muted() or u.has_flag("root"):
			cancel_channel(u)
		elif w.time >= float(u.channel.until):
			var dest: Vector2 = u.channel.dest
			u.channel = {}
			w.combat.disjoint(u)
			u.pos = dest
			u.path = PackedVector2Array()
			u.order = O.NONE
			u.atk_target = -1
			w.events.append({"t": "tp_end", "u": u.id, "pos": dest})
			return
		else:
			return
	if u.is_stunned():
		if u.atk_phase == AP.WINDUP:
			_cancel_windup(u)
		u.atk_phase = AP.NONE
		u.cast_phase = CP.NONE
		u.moving = false
		return
	if u.cast_phase != CP.NONE:
		_update_cast(u)
		return
	if u.atk_phase == AP.WINDUP:
		_update_windup(u)
		return
	if u.atk_phase == AP.BACKSWING:
		u.atk_timer -= C.DT
		var t := w.get_unit(u.atk_target)
		var again := t != null and t.alive and w.time >= u.next_attack_at
		if u.atk_timer > 0.0 and not again:
			return
		u.atk_phase = AP.NONE
	u.moving = false
	match u.order:
		O.NONE:
			_idle(u, false)
		O.HOLD:
			_idle(u, true)
		O.MOVE:
			if _move_to(u, u.order_point, 8.0):
				_finish_order(u)
		O.MOVE_TO_UNIT:
			var t := w.get_unit(u.order_target)
			if t == null or not t.alive:
				_finish_order(u)
			elif u.edge_distance(t) > 60.0:
				_move_to(u, t.pos, 0.0)
		O.ATTACK_UNIT:
			_order_attack(u)
		O.ATTACK_MOVE:
			_order_attack_move(u)
		O.CAST_NO_TARGET, O.CAST_POINT, O.CAST_UNIT:
			_order_cast(u)
		O.DROP_ITEM, O.PICKUP_ITEM, O.GIVE_ITEM:
			_order_item(u)
		O.PICKUP_ORB:
			# walk within 150 of the orb and take it (gone meanwhile: the order ends)
			var ob := w.orbs.get_orb(u.order_gid)
			if ob.is_empty():
				_finish_order(u)
			elif u.pos.distance_to(ob.pos) > SimOrbs.PICKUP_RANGE:
				_move_to(u, ob.pos, SimOrbs.PICKUP_RANGE * 0.6)
			else:
				w.orbs.take(u, int(ob.id))
				_finish_order(u)

## Who may receive an item: an allied hero or the giver's own courier, alive, with a free slot.
func give_error(u: SimUnit, t: SimUnit) -> String:
	if t == null or not t.alive or t == u:
		return "Must target an allied hero or your courier"
	if t.team != u.team or not (t.is_hero() or (t.kind == K.COURIER and t.owner_id == u.id)):
		return "Must target an allied hero or your courier"
	if t.inventory.find(null) < 0:
		return "Their inventory is full"
	return ""

## Drop, pick up, give: walk into reach (150), then act. Dropping in the fountain area keeps the item's owner, so the
## owner's courier can sweep it up.
func _order_item(u: SimUnit) -> void:
	var slot := u.cast_item_slot
	match u.order:
		O.DROP_ITEM:
			if slot < 0 or u.inventory[slot] == null:
				_finish_order(u)
				return
			if not _move_to(u, u.order_point, C.ITEM_REACH * 0.5):
				return
			var it: Dictionary = u.inventory[slot]
			u.inventory[slot] = null
			if not it.has("owner"):
				it["owner"] = u.id
			w.drop_item(it, u.order_point if u.pos.distance_to(u.order_point) <= C.ITEM_REACH else u.pos, u.id)
			u.refresh_stats()
			_finish_order(u)
		O.PICKUP_ITEM:
			var g := w.ground_item(u.order_gid)
			if g.is_empty():
				_finish_order(u)
				return
			if u.pos.distance_to(g.pos) > C.ITEM_REACH:
				_move_to(u, g.pos, C.ITEM_REACH * 0.6)
				return
			var free := u.inventory.find(null)
			if free < 0:
				w.events.append({"t": "error", "u": u.id, "msg": "Inventory full"})
				_finish_order(u)
				return
			var got := w.take_ground_item(u.order_gid, u)
			u.inventory[free] = got.item
			w.shop.combine_all(u)
			u.refresh_stats()
			_finish_order(u)
		O.GIVE_ITEM:
			var t := w.get_unit(u.order_target)
			if slot < 0 or u.inventory[slot] == null or give_error(u, t) != "":
				_finish_order(u)
				return
			if u.edge_distance(t) > C.ITEM_REACH:
				_move_to(u, t.pos, 0.0, t)
				return
			var free2 := t.inventory.find(null)
			t.inventory[free2] = u.inventory[slot]
			u.inventory[slot] = null
			u.refresh_stats()
			if t.is_hero():
				w.shop.combine_all(t)
				t.refresh_stats()
			w.events.append({"t": "item_give", "u": u.id, "target": t.id})
			_finish_order(u)

## The current order is done: start the next queued one. Orders that fail (a spell still on cooldown, a dead
## target) or finish at once (instant items) are skipped over to the one after, as in Dota.
func _finish_order(u: SimUnit) -> void:
	u.order = O.NONE
	u.order_target = -1
	u.path = PackedVector2Array()
	var guard := 0
	while not u.order_queue.is_empty() and guard < 32:
		guard += 1
		var nxt: Dictionary = u.order_queue.pop_front()
		nxt.erase("queue")
		issue(u, nxt, true, true)
		if not u.is_idle() or not u.channel.is_empty() or u.order == O.HOLD:
			return

## Idle or holding: attack whatever target the unit has (AI-chosen or auto-acquired), hold only within range.
func _idle(u: SimUnit, hold: bool) -> void:
	if not u.can_attack_at_all() or u.is_disarmed():
		return
	var t := w.get_unit(u.atk_target)
	if t == null or not _attackable(u, t):
		u.atk_target = -1
		t = null
		# invisible units never attack on their own (Dota 2 wiki, Invisibility)
		if u.is_hero() and (u.auto_attack or hold) and not u.no_acquire and not u.has_flag("invisible"):
			t = _acquire(u, u.attack_range if hold else u.acquire_range)
			if t:
				u.atk_target = t.id
	if t == null:
		return
	var chase := not hold and float(u.def.move_speed) > 0.0
	if u.is_hero() and chase and u.edge_distance(t) > u.acquire_range:
		u.atk_target = -1
		return
	_attack(u, t, chase)

## Explicit attack order on a unit: chase it; if it slips into the fog, walk to where it was last seen.
func _order_attack(u: SimUnit) -> void:
	var t := w.get_unit(u.order_target)
	if t == null or not t.alive:
		u.atk_target = -1
		_finish_order(u)
		return
	if not w.vision.sees(u.team, t):
		if _move_to(u, u.last_seen, 16.0):
			_finish_order(u)
		return
	u.last_seen = t.pos
	if u.is_disarmed():
		_move_to(u, t.pos, u.attack_range)
		return
	if t.team == u.team and not can_deny(u, t):
		# not deniable yet: stay at attack range and wait for it to drop low enough
		if u.edge_distance(t) > u.attack_range * 0.9:
			_move_to(u, t.pos, 0.0, t)
		return
	u.atk_target = t.id
	_attack(u, t, true)

## Attack-move: walk to the point, fighting the nearest enemy that comes within acquisition range on the way.
func _order_attack_move(u: SimUnit) -> void:
	var t := w.get_unit(u.atk_target)
	if t != null and not _attackable(u, t):
		t = null
		u.atk_target = -1
	if t == null and (u.is_hero() or u.lane == "" and u.camp_id < 0):
		t = _acquire(u, u.acquire_range)
		if t:
			u.atk_target = t.id
	if t != null and not u.is_disarmed():
		_attack(u, t, true)
		return
	if _move_to(u, u.order_point, 24.0):
		_finish_order(u)

func _attackable(u: SimUnit, t: SimUnit) -> bool:
	if not t.alive or t.removed:
		return false
	if t.is_invulnerable() and t.is_building():
		return false
	if not w.vision.sees(u.team, t):
		return false
	if t.team == u.team and not can_deny(u, t):
		return false
	return true

## The nearest visible enemy within `r` (heroes' auto-attack and attack-move).
func _acquire(u: SimUnit, r: float) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in w.query(u.pos, r + 200.0, true):
		if o.team == u.team or o.is_invulnerable() and o.is_building() or o.is_ward() and not o.alive:
			continue
		if o.kind == K.FOUNTAIN:
			continue
		if not w.vision.sees(u.team, o):
			continue
		var d := u.edge_distance(o)
		if d > r:
			continue
		# heroes on auto-attack never pick a building over a unit
		var score := d + (5000.0 if o.is_building() else 0.0)
		if score < bd:
			bd = score
			best = o
	return best

# ---- Attacking ------------------------------------------------------------------------------------------------------

## Close in (when allowed), face the target and start an attack when the cooldown allows.
func _attack(u: SimUnit, t: SimUnit, chase: bool) -> void:
	var d := u.edge_distance(t)
	if d > u.attack_range:
		if chase and u.move_speed > 0.0 and not u.is_rooted():
			_move_to(u, t.pos, 0.0, t)
		return
	u.path = PackedVector2Array()
	if not _turn_towards(u, (t.pos - u.pos).angle()):
		return
	if w.time < u.next_attack_at:
		return
	u.atk_phase = AP.WINDUP
	u.atk_target = t.id
	u.atk_timer = u.attack_point_time()
	u.prev_attack_at = u.next_attack_at
	u.next_attack_at = w.time + u.attack_interval()
	u.atk_modifier = w.abilities.attack_modifier_for(u, t)
	# Dota decides a critical strike when the attack starts, not when it lands
	u.atk_crit = w.combat.roll_crit(u, t)
	w.events.append({"t": "attack_start", "u": u.id, "target": t.id, "point": u.atk_timer,
		"interval": u.attack_interval(), "mod": u.atk_modifier, "crit": u.atk_crit > 1.0})
	w.ai.on_attack_start(u, t, u.atk_modifier != "" and u.atk_modifier == u.orb_manual)
	if u.atk_timer <= 0.0:
		_update_windup(u)

func _update_windup(u: SimUnit) -> void:
	var t := w.get_unit(u.atk_target)
	if t == null or not t.alive or (t.team == u.team and not can_deny(u, t)):
		_cancel_windup(u)
		return
	if u.edge_distance(t) > u.attack_range + C.ATTACK_RANGE_BUFFER:
		_cancel_windup(u)
		return
	_turn_towards(u, (t.pos - u.pos).angle())
	u.atk_timer -= C.DT
	if u.atk_timer > 0.0:
		return
	# the attack point is reached: the attack is released
	w.combat.release_attack(u, t, u.atk_modifier)
	u.atk_modifier = ""
	u.atk_crit = 1.0
	u.atk_phase = AP.BACKSWING
	u.atk_timer = u.backswing_time()

# ---- Casting ------------------------------------------------------------------------------------------------------------

func _order_cast(u: SimUnit) -> void:
	var aid := u.order_ability
	var slot := u.cast_item_slot
	var t := w.get_unit(u.order_target)
	if u.order == O.CAST_UNIT and (t == null or not t.alive):
		_finish_order(u)
		return
	var target_pos: Vector2 = t.pos if t else u.order_point
	var rng := w.abilities.cast_range(u, aid, slot, t)
	if u.order != O.CAST_NO_TARGET:
		var d := u.pos.distance_to(target_pos) - (t.hull if t else 0.0) - u.hull
		if d > rng:
			if u.is_rooted():
				return
			_move_to(u, target_pos, 0.0)
			return
		# a spell or item on oneself (Push Staff, self-cast point spell) needs no turn: it keeps the way the hero faces
		if t != u and target_pos.distance_to(u.pos) > 1.0 and not _turn_towards(u, (target_pos - u.pos).angle()):
			return
	u.cast_phase = CP.WINDUP
	u.cast_ability = aid
	u.cast_target = t.id if t else -1
	u.cast_point = target_pos
	u.cast_timer = w.abilities.cast_point(aid, slot) / (1.0 + u.cast_speed)
	w.events.append({"t": "cast_start", "u": u.id, "ability": aid, "slot": slot, "point": u.cast_point, "target": u.cast_target})
	if u.cast_timer <= 0.0:
		_update_cast(u)

func _update_cast(u: SimUnit) -> void:
	if u.cast_phase == CP.WINDUP:
		if u.is_silenced() and u.cast_item_slot < 0:
			u.cast_phase = CP.NONE
			_finish_order(u)
			return
		u.cast_timer -= C.DT
		if u.cast_timer > 0.0:
			return
		var t := w.get_unit(u.cast_target)
		var err := w.abilities.cast_error(u, u.cast_ability, u.cast_item_slot, t, u.cast_point, true)
		if err == "":
			w.abilities.execute(u, u.cast_ability, u.cast_item_slot, t, u.cast_point)
		elif u.order_from_player:
			w.events.append({"t": "error", "u": u.id, "msg": err})     # nothing spent; the player is told why
		u.cast_phase = CP.BACKSWING
		u.cast_timer = 0.3
		u.order = O.NONE
		u.order_target = -1
		# a channel that just began keeps queued orders waiting until it ends
		if not u.order_queue.is_empty() and u.channel.is_empty():
			u.cast_phase = CP.NONE
			_finish_order(u)
		return
	u.cast_timer -= C.DT
	if u.cast_timer <= 0.0:
		u.cast_phase = CP.NONE

# ---- Movement -----------------------------------------------------------------------------------------------------------

## Turn towards `angle`; true once facing within the 11.5 degree tolerance.
func _turn_towards(u: SimUnit, angle: float) -> bool:
	if u.has_flag("face_lock"):
		return false                               # Shuriken Hook's follow-through: no turning
	var diff := wrapf(angle - u.facing, -PI, PI)
	var step := u.turn_speed() * C.DT
	if absf(diff) <= step:
		u.facing = angle
	else:
		u.facing = wrapf(u.facing + signf(diff) * step, -PI, PI)
	return absf(wrapf(angle - u.facing, -PI, PI)) <= C.FACING_TOLERANCE

## Walk towards `goal`, stopping within `stop_dist`. Returns true on arrival. `chase` is the unit being chased
## (its hull counts for stopping and it is ignored for collisions).
func _move_to(u: SimUnit, goal: Vector2, stop_dist: float, chase: SimUnit = null) -> bool:
	if u.move_speed <= 0.0 or u.is_rooted():
		return false
	var to_goal := u.pos.distance_to(goal)
	if to_goal <= maxf(stop_dist, 4.0):
		u.path = PackedVector2Array()
		return true
	if u.is_hero() and u.has_flag("free_flight"):
		return _fly_to(u, goal, stop_dist)
	var need_path := u.path.is_empty() or u.path_goal.distance_to(goal) > 96.0 or w.time >= u.repath_at
	if need_path:
		var tp := Time.get_ticks_usec() if w.profiling else 0
		u.path = w.map.find_path(u.pos, goal)
		if w.profiling:
			w._prof("  find_path", tp)
			w.prof["  n_paths"] = float(w.prof.get("  n_paths", 0.0)) + 1.0
		u.path_i = 0
		u.path_goal = goal
		u.repath_at = w.time + (0.35 if chase else 3.0)
		if u.path.is_empty():
			return true
	if u.path_i >= u.path.size():
		u.path = PackedVector2Array()
		return true
	# corner cutting: skip ahead while the next-but-one point is in a straight walkable line
	var tl := Time.get_ticks_usec() if w.profiling else 0
	var cut := u.path_i + 1 < u.path.size() and (w.tick + u.id) % 4 == 0 and w.map.line_walkable(u.pos, u.path[u.path_i + 1])
	if w.profiling:
		w._prof("  corner_cut", tl)
	if cut:
		u.path_i += 1
	var nxt := u.path[u.path_i]
	if u.path_i == u.path.size() - 1:
		nxt = goal
	var dir := nxt - u.pos
	var dist := dir.length()
	if dist < 1.0:
		u.path_i += 1
		return u.path_i >= u.path.size() and to_goal <= maxf(stop_dist, 24.0)
	var want := dir.angle()
	if not _turn_towards(u, want):
		return false
	var step := u.move_speed * C.DT
	var d := Vector2.from_angle(u.facing)
	var move := d * minf(step, dist)
	var tr := Time.get_ticks_usec() if w.profiling else 0
	var np := _resolve(u, u.pos + move, move, chase)
	if w.profiling:
		w._prof("  resolve", tr)
	if np.distance_squared_to(u.pos) < 0.01:
		u.blocked_time += C.DT
		if u.blocked_time > 0.6:
			u.repath_at = C.LONG_AGO
			u.blocked_time = 0.0
		return false
	u.blocked_time = 0.0
	u.pos = np
	u.moving = true
	if u.pos.distance_to(nxt) < maxf(step, 8.0):
		u.path_i += 1
	return false

## Free flight (Azrael's Divine Darkness): straight at the goal over cliffs, trees and units, inside the map.
func _fly_to(u: SimUnit, goal: Vector2, stop_dist: float) -> bool:
	u.path = PackedVector2Array()
	var dir := goal - u.pos
	if not _turn_towards(u, dir.angle()):
		return false
	var step := minf(u.move_speed * C.DT, maxf(0.0, dir.length() - stop_dist * 0.5))
	var np := u.pos + Vector2.from_angle(u.facing) * step
	u.pos = Vector2(clampf(np.x, -7900.0, 7900.0), clampf(np.y, -7900.0, 7900.0))
	u.moving = step > 0.01
	return u.pos.distance_to(goal) <= maxf(stop_dist, 4.0)

## Walk towards a point for a unit with no order of its own (a ground courier).
func move_toward(u: SimUnit, goal: Vector2, stop: float) -> bool:
	return _move_to(u, goal, stop)

## Unit collision: try the step, then sidesteps of increasing angle; walls block, other units push sideways.
func _resolve(u: SimUnit, np: Vector2, move: Vector2, chase: SimUnit) -> Vector2:
	var near := w.query(u.pos, u.hull + 190.0)
	if _free(u, np, chase, near):
		return np
	# slide around the obstacle in the way: step along its tangent, on the side nearer the way we were going (a creep
	# meeting a tower head-on walks round it instead of pushing into it forever)
	var blocker := _blocker(u, np, chase, near)
	if blocker != null:
		var away := u.pos - blocker.pos
		if away.length_squared() > 0.01:
			var tan := away.orthogonal().normalized()
			if tan.dot(move) < 0.0 or (absf(tan.dot(move)) < 0.01 and (u.id % 2) == 0):
				tan = -tan
			var step := move.length()
			for k in 2:
				var tdir := tan if k == 0 else -tan
				var tp := u.pos + (tdir * 0.9 + away.normalized() * 0.1).normalized() * step
				if _free(u, tp, chase, near):
					return tp
	for a in [0.5, -0.5, 1.0, -1.0, 1.4, -1.4]:
		var m := move.rotated(a) * (0.85 if absf(a) > 1.2 else 1.0)
		var p := u.pos + m
		if _free(u, p, chase, near):
			return p
	# squeeze: a short step that tolerates slight overlap so crowds keep flowing
	var p2 := u.pos + move * 0.25
	if _free(u, p2, chase, near, true):
		return p2
	return u.pos

## The unit that stops a step to `p` (the nearest one in the way), or null when only the terrain does.
func _blocker(u: SimUnit, p: Vector2, chase: SimUnit, near: Array) -> SimUnit:
	if u.kind == K.COURIER:
		return null
	var best: SimUnit = null
	var bd := INF
	for o: SimUnit in near:
		if o == u or o == chase or o.is_ward() or o.kind == K.COURIER:
			continue
		if (u.phased or o.phased) and not o.is_building():
			continue
		var min_d := u.hull + o.hull - 2.0
		if o.is_building():
			min_d = u.hull + o.hull * 0.85
		var new_d2 := p.distance_squared_to(o.pos)
		if new_d2 < min_d * min_d and new_d2 < u.pos.distance_squared_to(o.pos) and new_d2 < bd:
			bd = new_d2
			best = o
	return best

func _free(u: SimUnit, p: Vector2, chase: SimUnit, near: Array, loose := false) -> bool:
	# Blau's resting boulders stop every walking unit, phased ones too
	if not w.abilities.kits3.boulders.is_empty() and u.kind != K.COURIER and w.abilities.kits3.blocks(p, u.hull) \
			and not w.abilities.kits3.blocks(u.pos, u.hull):
		return false
	if not w.map.is_walkable(p):
		# a unit standing inside a blocked cell (pushed or spawned there) may move within it to get out
		var cc := w.map.world_to_cell(u.pos)
		if w.map.is_walkable_cell(cc) or w.map.world_to_cell(p) != cc:
			return false
	if u.kind == K.COURIER:
		return true                                # couriers pass through units
	for o: SimUnit in near:
		if o == u or o == chase or o.is_ward() or o.kind == K.COURIER:
			continue
		if (u.phased or o.phased) and not o.is_building():
			continue
		var min_d := u.hull + o.hull - (8.0 if loose else 2.0)
		if o.is_building():
			min_d = u.hull + o.hull * 0.85
		var new_d2 := p.distance_squared_to(o.pos)
		if new_d2 < min_d * min_d and new_d2 < u.pos.distance_squared_to(o.pos):
			return false
	return true
