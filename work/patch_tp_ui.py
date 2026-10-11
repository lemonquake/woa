def rw(p, pairs):
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if b in s:
            continue
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:70]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)

rw('src/game/model_catalog.gd', [('''	"mudling": {''', '''	"courier": {"scene": UNITS + "aether_wisp.glb", "scene_dusk": UNITS + "star_mote.glb", "scale": 1.6, "attack": [],
		"idle": "idle", "run": "idle", "death": "death", "R": "", "L": "", "bar": 2.4, "float": 1.5},
	"mudling": {''')])
rw('src/game/unit_view.gd', [
    ('''	model = ModelCatalog.scene(key).instantiate() as Node3D''', '''	if cfg.has("scene_dusk") and u.team == 1:
		model = (load(String(cfg.scene_dusk)) as PackedScene).instantiate() as Node3D
	else:
		model = ModelCatalog.scene(key).instantiate() as Node3D'''),
    ('''	if _ring and _ring.visible:
		_ring.position.y = 0.04''', '''	if _ring and _ring.visible:
		_ring.position.y = 0.04
	if cfg.has("float") and model:
		model.position.y = float(cfg.float) + sin(Time.get_ticks_msec() / 400.0 + uid) * 0.15'''),
])
rw('src/game/fx.gd', [('''## Dota's order feedback:''', '''## Town Portal: a column of light at the hero and at the destination while channelling.
var _tp := {}

func tp_start(uid: int, from: Vector3, to: Vector3, team: int) -> void:
	tp_end(uid)
	var col := Color(0.45, 0.85, 1.0) if team == 0 else Color(1.0, 0.35, 0.4)
	var nodes: Array = []
	for at in [from, to]:
		var n := Node3D.new()
		add_child(n)
		n.global_position = at
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.75
		cyl.height = 7.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		beam.mesh = cyl
		var m := _glow(Color(col.r, col.g, col.b, 0.35), 3.0).duplicate() as StandardMaterial3D
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = m
		beam.position.y = 3.5
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(beam)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.85
		tm.outer_radius = 1.0
		ring.mesh = tm
		ring.scale = Vector3(1, 0.1, 1)
		ring.material_override = _glow(col, 4.0)
		ring.position.y = 0.08
		n.add_child(ring)
		var p := _trail(col, 40, 0.08)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_radius = 0.8
		p.emission_ring_inner_radius = 0.6
		p.emission_ring_height = 0.1
		p.emission_ring_axis = Vector3.UP
		p.direction = Vector3.UP
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.0
		p.lifetime = 1.0
		n.add_child(p)
		var tw := beam.create_tween().set_loops()
		tw.tween_property(beam, "scale", Vector3(1.15, 1.0, 1.15), 0.4)
		tw.tween_property(beam, "scale", Vector3(0.9, 1.0, 0.9), 0.4)
		nodes.append(n)
	_tp[uid] = nodes

func tp_end(uid: int, flash := false) -> void:
	if not _tp.has(uid):
		return
	for n: Node3D in _tp[uid]:
		if flash:
			impact(n.global_position + Vector3(0, 1.0, 0), Color(0.8, 0.95, 1.0), 1.2)
		n.queue_free()
	_tp.erase(uid)

## Dota's order feedback:''')])
rw('src/game/main.gd', [('''			"effect_move":
				fx.gale_move(e.pos)''', '''			"effect_move":
				fx.gale_move(e.pos)
			"tp_start":
				var tu := world.get_unit(e.u)
				if tu and (tu.team == player_team or world.vision.sees(player_team, tu)):
					fx.tp_start(e.u, View.to3(tu.pos, terrain.height_at(tu.pos)), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
				elif tu:
					# enemies still see where a Town Portal is going to land
					fx.tp_start(e.u, Vector3(0, -50, 0), View.to3(e.dest, terrain.height_at(e.dest)), tu.team)
			"tp_end":
				fx.tp_end(e.u, true)
				var v3 = views.get(e.u)
				if v3 is UnitView:
					v3.prev_pos = e.pos
					v3.cur_pos = e.pos
			"tp_cancel":
				fx.tp_end(e.u)''')])
rw('src/game/input_controller.gd', [
    ('''		KEY_J:
			w.glyph(game.player_team)''', '''		KEY_J:
			w.glyph(game.player_team)
		KEY_T:
			begin_tp()
		KEY_F3:
			var err: String = w.courier_deliver(h)
			if err != "" and game.hud and game.hud.has_method("error"):
				game.hud.error(err)'''),
    ('''func use_item(slot: int) -> void:''', '''func begin_tp() -> void:
	var h := hero()
	var err: String = game.world.abilities.cast_error(h, "tp", -1, null, h.pos)
	if err != "":
		if game.hud and game.hud.has_method("error"):
			game.hud.error(err)
		return
	targeting = "tp"

## Issue the pending targeted order at a sim point (used by the minimap too).
func target_point(p: Vector2, shift := false) -> void:
	var h := hero()
	if targeting == "tp":
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": "tp", "point": p, "queue": shift})
	elif targeting == "attack":
		game.world.command(h.id, {"type": O.ATTACK_MOVE, "point": p, "queue": shift})
	elif targeting.begins_with("item:"):
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": "", "item_slot": int(targeting.substr(5)), "point": p, "queue": shift})
	elif targeting != "":
		game.world.command(h.id, {"type": O.CAST_POINT, "ability": targeting, "point": p, "queue": shift})
	targeting = ""

func use_item(slot: int) -> void:'''),
    ('''	if targeting == "attack":
		if tgt and tgt.id != h.id:''', '''	if targeting == "tp":
		target_point(ground, shift)
		return
	if targeting == "attack":
		if tgt and tgt.id != h.id:'''),
])
rw('src/ui/hud.gd', [
    ('''			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
				if mb.pressed:
					_focus(mb.position)''', '''			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed and hud.game.input.targeting != "":
					hud.game.input.target_point(_from_mm(mb.position), mb.shift_pressed)
					accept_event()
					return
				_drag = mb.pressed
				if mb.pressed:
					_focus(mb.position)'''),
    ('''		_shop_rect = Rect2(956, 132, 112, 62)''', '''		_shop_rect = Rect2(956, 132, 112, 62)
		_tp_rect = Rect2(956, 96, 52, 32)
		_courier_rect = Rect2(1012, 96, 56, 32)
		_buyback_rect = Rect2(352, 132, 330, 50)'''),
    ('''	var _shop_rect := Rect2()''', '''	var _shop_rect := Rect2()
	var _tp_rect := Rect2()
	var _courier_rect := Rect2()
	var _buyback_rect := Rect2()'''),
    ('''		_bars(h)
		_items(h, w)
		_gold(h)''', '''		_bars(h)
		_items(h, w)
		_gold(h)
		_tp_and_courier(h, w)
		if not h.alive:
			_buyback(h, w)'''),
    ('''	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		var p := mb.position''', '''	func _tp_and_courier(h: SimUnit, w: SimWorld) -> void:
		var m := get_local_mouse_position()
		U.slot(self, _tp_rect, hud.game.input.targeting == "tp")
		var ti: Texture2D = U.icon("ui/teleport")
		if ti:
			draw_texture_rect(ti, Rect2(_tp_rect.position + Vector2(10, 2), Vector2(28, 28)), false, U.DAWN if h.tp_charges > 0 else Color(0.4, 0.4, 0.4))
		var cd := w.abilities.cooldown_left(h, "tp")
		if cd > 0.0:
			U.cooldown(self, _tp_rect, cd / SimConst.TP_COOLDOWN, cd)
		U.text(self, "T", _tp_rect.position + Vector2(3, 12), 10, Color(1, 1, 1), "bold")
		U.text_r(self, str(h.tp_charges), _tp_rect.end + Vector2(-3, -3), 12, Color(1, 1, 1), "bold")
		if _tp_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Town Portal Scroll", 18, U.GOLD, "title"],
				["Channel 3 s, then teleport beside the allied building nearest the target point. Moving or a stun cancels it.", 14, U.TEXT, "body"],
				["Charges %d. Cooldown 80 s. Mana 75. Buy more in the shop (100 gold). Hotkey T." % h.tp_charges, 13, U.TEXT_DIM, "body"]])
		var c := w.get_unit(h.courier_id)
		U.slot(self, _courier_rect, c != null and c.courier_state != "idle")
		var state := "Dead" if c == null or not c.alive else c.courier_state.capitalize()
		U.text_c(self, "Courier", _courier_rect.get_center() + Vector2(0, -2), 11, U.GOLD, "bold")
		U.text_c(self, state, _courier_rect.get_center() + Vector2(0, 12), 10, U.TEXT_DIM, "body")
		if _courier_rect.has_point(m):
			hud.show_tip(get_global_mouse_position(), [["Courier", 18, U.GOLD, "title"],
				["Click (or F3) to have your courier fetch the stash and fly it to you.", 14, U.TEXT, "body"]])

	func _buyback(h: SimUnit, w: SimWorld) -> void:
		var cost := w.buyback_cost(h)
		var ready := w.time >= h.buyback_ready
		var can := ready and h.gold() >= cost
		draw_rect(_buyback_rect, Color(0.05, 0.04, 0.03, 0.92))
		draw_rect(_buyback_rect, U.GOLD if can else Color(0.4, 0.35, 0.3), false, 2.0)
		var label := "Buyback  %d gold" % cost if ready else "Buyback in %ds" % ceili(h.buyback_ready - w.time)
		U.text_c(self, label, _buyback_rect.get_center() + Vector2(0, 8), 20, U.GOLD if can else U.TEXT_DIM, "title")

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var h: SimUnit = hud.hero()
		var w: SimWorld = hud.game.world
		var p := mb.position
		if not h.alive and _buyback_rect.has_point(p):
			var err := w.buyback(h)
			if err != "":
				hud.error(err)
			accept_event()
			return
		if _tp_rect.has_point(p):
			hud.game.input.begin_tp()
			accept_event()
			return
		if _courier_rect.has_point(p):
			var err2 := w.courier_deliver(h)
			if err2 != "":
				hud.error(err2)
			accept_event()
			return'''),
])
print("ok")
