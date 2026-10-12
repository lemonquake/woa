class_name ItemFx
extends Node
## Visual feedback for the combination items, driven by simulation events: Jump Knife's flashes at both ends,
## Shock Hammer's lightning arcs, Spell Shield's golden burst, Gold Glove's coins, the Mana Boots and Medic Kit
## pulses, a dust trail behind a Push Staff push, a puff when Sneak Blade's invisibility ends, a sparkle when items
## combine. Lasting states (Spell Shield's size, an invisible hero's fade) are shown by UnitView.

var game: Node
var fx: Fx

func event(e: Dictionary) -> void:
	match String(e.t):
		"jump":
			_jump(e)
		"chain":
			_chain(e)
		"spell_shield":
			var su: SimUnit = game.world.get_unit(int(e.u))
			var c := fx._chest(int(e.u), 0.5)
			if su and fx._seen(su.pos):
				fx.shockwave(fx.ground3(su.pos, 0.05), 1.4, Color(1.0, 0.8, 0.3), 0.4, 0.2, 2.5)
				fx.impact(c, Color(1.0, 0.85, 0.4), 0.45)
				fx.flash_light(c, Color(1.0, 0.85, 0.45), 3.0, 5.0, 0.3)
		"gold_glove":
			var t: SimUnit = game.world.get_unit(int(e.target))
			if t and fx._seen(t.pos):
				var c2 := fx._chest(t.id, 0.5)
				fx.debris(c2, 10, Color(1.0, 0.8, 0.2), 3.5, 0.8, "sphere")
				fx.flash_light(c2, Color(1.0, 0.85, 0.3), 3.0, 4.0, 0.3)
			if int(e.u) == game.player_hero_id and t:
				game.bars.popup("+%d" % int(e.gold), fx._chest(t.id, 1.0), Color(1.0, 0.82, 0.25), 24, 1.4, 1.6)
		"mana_burst":
			var u: SimUnit = game.world.get_unit(int(e.u))
			if u and fx._seen(u.pos):
				fx.shockwave(fx.ground3(u.pos, 0.05), float(e.radius) * View.S, Color(0.35, 0.55, 1.0), 0.7, 0.25, 2.0)
		"mend":
			var u2: SimUnit = game.world.get_unit(int(e.u))
			if u2 and fx._seen(u2.pos):
				fx.shockwave(fx.ground3(u2.pos, 0.05), float(e.radius) * View.S, Color(0.45, 1.0, 0.5), 0.7, 0.25, 2.0)
				fx.impact(fx._chest(u2.id, 0.5), Color(0.6, 1.0, 0.6), 0.4)
		"knockback":
			if bool(e.get("push_staff", false)):
				var u3: SimUnit = game.world.get_unit(int(e.u))
				if u3 and fx._seen(u3.pos):
					var dir: Vector2 = (e.to as Vector2) - u3.pos
					fx.sparks(fx.ground3(u3.pos, 0.3), Vector3(-dir.x, 0.4, dir.y).normalized(), 8,
						Color(0.85, 0.85, 1.0), 4.0)
					fx.edge_ring(fx.ground3(u3.pos, 0.05), 0.9, Color(0.75, 0.8, 1.0), 0.5)
		"sneak_end":
			var u4: SimUnit = game.world.get_unit(int(e.u))
			if u4 and fx._seen(u4.pos):
				fx.debris(fx._chest(u4.id, 0.5), 8, Color(0.3, 0.3, 0.35), 2.0, 1.2, "sphere")
		"combine":
			if int(e.u) == game.player_hero_id:
				var u5: SimUnit = game.world.get_unit(int(e.u))
				if u5:
					fx.sparks(fx._chest(u5.id, 0.8), Vector3.UP, 10, Color(1.0, 0.85, 0.4), 3.0)

func _jump(e: Dictionary) -> void:
	var from: Vector2 = e.from
	var to: Vector2 = e.to
	for p in [from, to]:
		if fx._seen(p):
			var at := fx.ground3(p, 1.0)
			fx.flash_light(at, Color(0.8, 0.7, 1.0), 3.5, 5.0, 0.25)
			fx.sparks(at, Vector3.UP, 12, Color(0.85, 0.75, 1.0), 4.0)
			fx.shockwave(fx.ground3(p, 0.05), 0.9, Color(0.7, 0.6, 1.0), 0.35, 0.15, 2.0)

func _chain(e: Dictionary) -> void:
	var to: Vector2 = e.pos
	var from: Vector2 = e.get("from", to)
	if not fx._seen(to) and not fx._seen(from):
		return
	var t3 := fx._chest(int(e.u), 0.55)
	if from.distance_to(to) < 1.0:
		# the first strike comes down from above the target
		fx.lightning(t3 + Vector3(0, 3.5, 0), t3, Color(0.6, 0.8, 1.0), 0.3, 0.08, 10)
	else:
		fx.lightning(fx.ground3(from, 1.0), t3, Color(0.6, 0.8, 1.0), 0.3, 0.08, 14)
	fx.sparks(t3, Vector3.UP, 6, Color(0.7, 0.85, 1.0), 4.0)
	fx.flash_light(t3, Color(0.6, 0.8, 1.0), 2.5, 4.0, 0.15)
