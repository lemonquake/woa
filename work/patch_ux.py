def rw(p, pairs):
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if b in s:
            continue
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:70]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)

rw('src/game/main.gd', [
    ('''	for id in views:
		var v = views[id]
		if v is UnitView:
			v.set_selected(id == selected_id, Color(0.3, 1.0, 0.4, 0.9) if world.get_unit(id) and world.get_unit(id).team == player_team else Color(1.0, 0.3, 0.25, 0.9))''',
     '''	var hover: int = input.hover_id if input else -1
	for id in views:
		var v = views[id]
		if v is UnitView:
			var su := world.get_unit(id)
			var friendly := su != null and su.team == player_team
			if id == selected_id:
				v.set_selected(true, Color(0.3, 1.0, 0.4, 0.9) if friendly else Color(1.0, 0.3, 0.25, 0.9))
			elif id == hover:
				v.set_selected(true, Color(1.0, 1.0, 1.0, 0.55) if friendly else Color(1.0, 0.55, 0.3, 0.7))
			else:
				v.set_selected(false, Color.WHITE)
	fx.tower_ranges(world, world.get_unit(player_hero_id), player_team)'''),
    ('''			"hero_kill":
				if hud and hud.has_method("on_kill"):
					hud.on_kill(e)''', '''			"hero_kill":
				if hud and hud.has_method("on_kill"):
					hud.on_kill(e)
			"death":
				var du := world.get_unit(e.u)
				if du and du.is_building() and hud and hud.has_method("announce"):
					var side := "Your" if du.team == player_team else "The enemy's"
					var what := {"tower1": "tier 1 tower", "tower2": "tier 2 tower", "tower3": "tier 3 tower", "tower4": "tier 4 tower",
						"melee_rax": "melee barracks", "ranged_rax": "ranged barracks", "filler": "effigy", "ancient": "Aether Core"}
					var verb := "was denied" if e.get("deny", false) else "has fallen"
					hud.announce("%s %s %s" % [side, String(what.get(String(du.def.id), "building")), verb],
						du.building_lane.capitalize() + (" lane" if du.building_lane != "" else ""))
			"victory":
				if hud and hud.has_method("announce"):
					hud.announce("Victory!" if int(e.team) == player_team else "Defeat", "The Aether Core has been destroyed")'''),
])

rw('src/game/fx.gd', [
    ('''## Dota's order feedback:''', '''## Attack-range rings for enemy towers near your hero: yellow, or red while the tower is targeting you.
var _ranges := {}

func tower_ranges(w: SimWorld, h: SimUnit, team: int) -> void:
	for u in w.units:
		if u.kind != SimConst.Kind.TOWER or u.team == team:
			continue
		var near := h != null and h.alive and u.alive and h.pos.distance_to(u.pos) < u.attack_range + u.hull + 700.0
		var ring: MeshInstance3D = _ranges.get(u.id)
		if not near:
			if ring:
				ring.visible = false
			continue
		if ring == null:
			ring = MeshInstance3D.new()
			var tm := TorusMesh.new()
			var r := (u.attack_range + u.hull) * View.S
			tm.inner_radius = r - 0.07
			tm.outer_radius = r
			tm.rings = 96
			tm.ring_segments = 4
			ring.mesh = tm
			ring.scale = Vector3(1, 0.05, 1)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = m
			add_child(ring)
			ring.global_position = View.to3(u.pos, game.terrain.height_at(u.pos)) + Vector3(0, 0.1, 0)
			_ranges[u.id] = ring
		ring.visible = true
		var aggro := u.atk_target == h.id
		var d := h.pos.distance_to(u.pos) - (u.attack_range + u.hull)
		var a := clampf(1.0 - d / 700.0, 0.25, 0.9)
		(ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.2, 0.15, 0.95) if aggro else Color(1.0, 0.85, 0.3, a)

## Dota's order feedback:'''),
])

rw('src/ui/hud.gd', [
    ('''func error(msg: String) -> void:''', '''## Info card for a selected unit that is not your hero (creeps, towers, neutrals, enemy heroes).
func _unit_card() -> void:
	var w: SimWorld = game.world
	var sel: SimUnit = w.get_unit(game.selected_id)
	if sel == null or sel.id == game.player_hero_id or not sel.alive:
		return
	var vs := get_viewport_rect().size
	var r := Rect2(vs.x * 0.5 - 230, vs.y - BottomPanel.H - 92, 460, 80)
	U.panel(self, r, U.GOLD_DIM, 6)
	var col := U.DAWN if sel.team == 0 else (U.DUSK if sel.team == 1 else Color(0.95, 0.8, 0.4))
	U.text(self, String(sel.look.get("display_name", sel.name)), r.position + Vector2(14, 26), 18, col, "title")
	var lvl := " level %d" % sel.level if sel.is_hero() else ""
	U.text_r(self, ["Dawn", "Dusk", "Neutral"][sel.team] + lvl, Vector2(r.end.x - 14, r.position.y + 24), 13, U.TEXT_DIM, "body")
	U.bar(self, Rect2(r.position + Vector2(14, 36), Vector2(200, 14)), sel.hp / maxf(1.0, sel.max_hp), U.HP)
	U.text_c(self, "%d / %d" % [int(sel.hp), int(sel.max_hp)], r.position + Vector2(114, 48), 11, U.TEXT, "bold")
	if sel.max_mana > 0.0:
		U.bar(self, Rect2(r.position + Vector2(14, 54), Vector2(200, 10)), sel.mana / maxf(1.0, sel.max_mana), U.MANA)
	var dmg := "%d-%d" % [int(sel.dmg_min + sel.bonus_damage), int(sel.dmg_max + sel.bonus_damage)] if sel.can_attack_at_all() else "-"
	U.text(self, "Damage %s   Armor %.0f   Range %d   Speed %d" % [dmg, sel.armor, int(sel.attack_range), int(sel.move_speed)],
		r.position + Vector2(228, 50), 13, U.TEXT, "body")
	if sel.is_building() and sel.is_invulnerable():
		U.text(self, "Invulnerable", r.position + Vector2(228, 70), 12, Color(1.0, 0.75, 0.4), "bold")
	elif sel.is_building() and sel.backdoor_active:
		U.text(self, "Backdoor protection", r.position + Vector2(228, 70), 12, Color(0.6, 0.85, 1.0), "bold")

func error(msg: String) -> void:'''),
    ('''	var h := hero()
	if h and not h.alive:
		var t := maxf(0.0, h.respawn_at - game.world.time)''', '''	_unit_card()
	var h := hero()
	if h and not h.alive:
		var t := maxf(0.0, h.respawn_at - game.world.time)'''),
])
print("ok")
