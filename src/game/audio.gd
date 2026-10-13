class_name GameAudio
extends Node3D
## Sound for the match. Positional effects come from simulation events and are heard from the camera's ground
## point (like Dota, where the listener sits under the camera). Cues that are only for you (gold, level-up, shop,
## errors) play in 2D, and a forest ambience loops underneath. A small pool of players with per-sound cooldowns keeps
## big fights from turning into noise.

const SFX := "res://assets/audio/sfx/%s.wav"
const POOL := 28

var game: Node
var listener: AudioListener3D
var _pool: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _streams := {}
var _last := {}
var _i := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "Audio"
	Options.ensure_buses()
	listener = AudioListener3D.new()
	add_child(listener)
	listener.make_current()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 46.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	for i in 6:
		var u := AudioStreamPlayer.new()
		u.bus = "Interface"
		add_child(u)
		_ui.append(u)
	var amb := AudioStreamPlayer.new()
	var st := load("res://assets/audio/amb/amb_forest.wav") as AudioStreamWAV
	if st:
		st = st.duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = st.get_length() * st.mix_rate if st.mix_rate > 0 else 0
		amb.stream = st
		amb.volume_db = -14.0
		amb.bus = "Ambience"
		add_child(amb)
		amb.play()

func _stream(n: String) -> AudioStream:
	if not _streams.has(n):
		_streams[n] = load(SFX % n) if ResourceLoader.exists(SFX % n) else null
	return _streams[n]

## Play a positional sound; `variants` picks one of name_1..name_n.
func at(n: String, pos: Vector3, vol := 0.0, variants := 0, cooldown := 0.06, pitch_jitter := 0.08) -> void:
	if variants > 0:
		n = "%s_%d" % [n, _rng.randi_range(1, variants)]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(n, -9.0)) < cooldown:
		return
	if pos.distance_to(listener.global_position) > 48.0:
		return
	var s := _stream(n)
	if s == null:
		return
	_last[n] = now
	var p := _pool[_i]
	_i = (_i + 1) % POOL
	p.stream = s
	p.volume_db = vol
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.global_position = pos
	p.play()

func ui(n: String, vol := 0.0) -> void:
	var s := _stream(n)
	if s == null:
		return
	for u in _ui:
		if not u.playing:
			u.stream = s
			u.volume_db = vol
			u.play()
			return

func _process(_dt: float) -> void:
	if game and game.camera:
		listener.global_position = game.camera.target + Vector3(0, 4.0, 2.0)
		listener.global_rotation = game.camera.cam.global_rotation

func _pos(w: SimWorld, uid: int) -> Vector3:
	var u := w.get_unit(uid)
	if u == null:
		return Vector3(INF, INF, INF)
	return View.to3(u.pos, game.terrain.height_at(u.pos)) + Vector3(0, 1.2, 0)

## Map one simulation event to sound.
func event(e: Dictionary, w: SimWorld) -> void:
	match e.t:
		"projectile":
			var src := w.get_unit(e.src)
			if src == null:
				return
			var p := _pos(w, e.src)
			match src.kind:
				SimConst.Kind.HERO:
					at("bow_attack", p, -4.0, 3)
				SimConst.Kind.TOWER:
					at("arcane_charge" if src.team == 0 else "lightning_zap_1", p, -8.0, 0, 0.1)
				SimConst.Kind.CREEP_SIEGE:
					at("swing_heavy", p, -6.0, 3)
				SimConst.Kind.FOUNTAIN:
					at("holy_strike", p, -10.0, 0, 0.2)
				_:
					at("mage_attack", p, -12.0, 2, 0.08)
		"damage":
			if not e.get("attack", false):
				return
			var src2 := w.get_unit(e.src)
			var p2 := _pos(w, e.u)
			if src2 == null:
				return
			if src2.kind == SimConst.Kind.HERO and String(src2.def.id) == "ezee":
				at("greatsword_hit", p2, -5.0, 3, 0.05)
				return
			if src2.kind == SimConst.Kind.HERO and String(src2.def.id) == "sludge":
				at("axe_hit", p2, -4.0, 3, 0.05)
				at("hit_flesh", p2, -10.0, 3, 0.05)
				return
			if src2.is_ranged():
				if src2.is_hero():
					at("arrow_impact", p2, -6.0, 2, 0.05)
				elif src2.kind == SimConst.Kind.TOWER:
					at("magic_hit", p2, -6.0, 2, 0.08)
				else:
					at("magic_hit", p2, -14.0, 2, 0.12)
			else:
				var model := String(src2.def.model)
				if model.begins_with("ashfang"):
					at("claw_hit", p2, -10.0, 2, 0.1)
				elif model.ends_with("melee") or model.ends_with("flag"):
					at("sword_hit", p2, -14.0, 3, 0.09)
				else:
					at("hit_flesh", p2, -12.0, 3, 0.1)
		"death":
			var u := w.get_unit(e.u)
			if u == null:
				return
			var p3 := _pos(w, e.u)
			if u.is_building():
				at("break_stone", p3, 2.0, 0, 0.5, 0.02)
				at("explode", p3, -2.0, 0, 0.5, 0.02)
			elif u.is_hero():
				at("body_fall", p3, 0.0, 0, 0.3)
				if u.player:
					ui("sting_defeat", -4.0)
			elif u.team == 1 and u.is_lane_creep():
				at("ghoul_death", p3, -10.0, 0, 0.15)
			else:
				at("body_fall", p3, -12.0, 0, 0.12)
		"last_hit":
			if e.u == game.player_hero_id:
				ui("gold_pickup", -3.0)
		"deny":
			if e.u == game.player_hero_id:
				ui("parry", -6.0)
		"hook_move":
			# the spinning star whirs as it flies
			if String(e.get("state", "")) == "out" and int(e.get("target", -1)) < 0 and w.tick % 4 == 0:
				var hp: Vector2 = e.pos
				at("attack_woosh", View.to3(hp, game.terrain.height_at(hp)) + Vector3(0, 1.0, 0), -14.0, 3, 0.11, 0.2)
		"hook_latch":
			var lp: Vector2 = e.pos
			var l3 := View.to3(lp, game.terrain.height_at(lp)) + Vector3(0, 1.0, 0)
			at("hit_metal", l3, -3.0, 3, 0.05)
			if not bool(e.get("ally", false)):
				at("hit_flesh", l3, 0.0, 3, 0.05)
				at("spear_hit", l3, -2.0, 2, 0.05)
			at("skeleton_rattle_2", l3, -5.0, 0, 0.1)
		"hook_kill":
			at("cleave", _pos(w, e.u), -2.0, 2, 0.1)
		"hook_end":
			var ep: Vector2 = e.pos
			at("skeleton_rattle_1", View.to3(ep, game.terrain.height_at(ep)) + Vector3(0, 1.0, 0), -9.0, 0, 0.2)
		"blubber":
			at("block", _pos(w, e.u), -6.0, 2, 0.2)
		# combination items
		"jump":
			var jf: Vector2 = e.from
			var jt: Vector2 = e.to
			at("blink", View.to3(jf, game.terrain.height_at(jf)) + Vector3(0, 1, 0), -4.0, 0, 0.1)
			at("teleport_whoosh", View.to3(jt, game.terrain.height_at(jt)) + Vector3(0, 1, 0), -8.0, 0, 0.1)
		"chain":
			at("lightning_zap", _pos(w, e.u), -6.0, 2, 0.05)
		"spell_shield":
			at("holy_cast", _pos(w, e.u), -3.0, 0, 0.3)
		"gold_glove":
			at("gold_pickup", _pos(w, e.target), -2.0, 0, 0.2)
		"mana_burst":
			at("arcane_charge", _pos(w, e.u), -5.0, 0, 0.3)
		"mend":
			at("heal", _pos(w, e.u), -4.0, 0, 0.3)
		"sneak_end":
			at("shade_hiss", _pos(w, e.u), -8.0, 0, 0.2)
		"combine":
			if e.u == game.player_hero_id:
				ui("ui_craft", -6.0)
		"item_use":
			match String(e.item):
				"slip_boots":
					at("wind_gust", _pos(w, e.u), -10.0, 0, 0.2)
				"push_staff":
					at("wind_gust", _pos(w, e.u), -4.0, 0, 0.2)
				"spike_armor":
					at("hit_armor", _pos(w, e.u), -4.0, 3, 0.2)
				"sneak_blade":
					at("shade_hiss", _pos(w, e.u), -6.0, 0, 0.2)
				"power_treads":
					if e.u == game.player_hero_id:
						ui("ui_equip", -8.0)
		"level_up":
			if e.u == game.player_hero_id:
				ui("level_up", -4.0)
			else:
				at("level_up", _pos(w, e.u), -10.0)
		"cast":
			var p4 := _pos(w, e.u)
			match String(e.ability):
				"gale_impact":
					at("bow_release", p4, -1.0, 0, 0.1)
					at("wind_gust", p4, -1.0, 0, 0.2, 0.02)
				"burst_shot":
					at("bow_draw", p4, -4.0, 0, 0.2)
				"blood_ranger_ult":
					at("war_cry", p4, -4.0, 0, 0.2)
					at("drain", p4, -6.0, 0, 0.2)
				"leap_strike":
					at("attack_woosh", p4, -2.0, 3, 0.1)
				"shuriken_hook":
					at("swing_heavy", p4, -2.0, 3, 0.1)
					at("skeleton_rattle_1", p4, -6.0, 0, 0.2, 0.12)
				"chomp":
					at("ghoul_growl", p4, -3.0, 2, 0.3, 0.05)
				"tainted_touch":
					at("dark_cast", p4, -4.0, 0, 0.2)
		"stomp":
			var ps := View.to3(e.pos, game.terrain.height_at(e.pos)) + Vector3(0, 0.5, 0)
			at("boss_slam", ps, 0.0, 0, 0.2, 0.04)
			at("earth_quake", ps, -4.0, 0, 0.3, 0.04)
		"impact":
			var pi := View.to3(e.pos, game.terrain.height_at(e.pos)) + Vector3(0, 0.8, 0)
			match String(e.what):
				"tree":
					at("break_wood", pi, -2.0, 2, 0.08)
				"cliff", "building":
					at("wall_impact", pi, -2.0, 2, 0.08)
				_:
					at("hit_heavy", pi, -3.0, 2, 0.06)
		"stunned":
			at("stagger", _pos(w, e.u), -8.0, 0, 0.15)
		"crit":
			at("crit_hit", _pos(w, e.target), -2.0, 0, 0.1)
		"bash":
			at("hammer_hit", _pos(w, e.target), -2.0, 3, 0.1)
			at("stagger", _pos(w, e.target), -8.0, 0, 0.15, 0.03)
		"overwhelm":
			at("hammer_hit", _pos(w, e.target), 0.0, 3, 0.1)
			at("boss_slam", _pos(w, e.target), -8.0, 0, 0.2)
		"item_debuff":
			var pk := _pos(w, e.target)
			match String(e.kind):
				"silence":
					at("dark_curse", pk, -4.0, 0, 0.2)
				"disarm":
					at("parry", pk, -3.0, 0, 0.2)
				"hex":
					at("arcane_surge", pk, -4.0, 0, 0.2)
				"root_staff":
					at("cast_earth", pk, -4.0, 0, 0.2)
		"dust":
			at("wind_gust", _pos(w, e.u), -6.0, 0, 0.2)
		"orb_taken":
			at("gold_pickup" if String(e.kind) == "gold" else "skill_unlock", _pos(w, e.u), -3.0, 0, 0.2)
		"soul_burst":
			at("magic_hit", _pos(w, e.u), -2.0, 2, 0.15)
		"neutral_spell":
			var pn := View.to3(e.pos, game.terrain.height_at(e.pos)) + Vector3(0, 0.5, 0)
			match String(e.ability):
				"stomp":
					at("boss_slam", pn, -3.0, 0, 0.2, 0.04)
					at("earth_quake", pn, -8.0, 0, 0.3, 0.04)
				"smash":
					at("boss_slam", pn, 0.0, 0, 0.2, 0.04)
					at("rock_impact", pn, -4.0, 0, 0.2, 0.04)
				"snarl":
					at("ghoul_growl", pn, -4.0, 2, 0.3, 0.03)
		"leap_land":
			var pl := View.to3(e.pos, game.terrain.height_at(e.pos)) + Vector3(0, 0.5, 0)
			at("boss_slam", pl, -2.0, 0, 0.2, 0.05)
			if bool(e.hit):
				at("greatsword_hit", pl, -1.0, 3, 0.05)
		"taint_cast":
			at("thunder_strike", _pos(w, e.u), -2.0, 0, 0.2, 0.05)
		"curse":
			at("dark_curse", _pos(w, e.u), -9.0, 0, 0.25)
		"unholy_start":
			at("boss_roar", _pos(w, e.u), 1.0, 0, 0.3, 0.03)
			at("dark_cast", _pos(w, e.u), -5.0, 0, 0.3)
		"unholy_reflect":
			at("drain", _pos(w, e.u), -6.0, 0, 0.1)
		"unholy_end":
			at("shade_hiss", _pos(w, e.u), -8.0, 0, 0.3)
		"projectile_end":
			if not bool(e.get("hit", false)) and e.has("pos"):
				var pg: Vector2 = e.pos
				at("arrow_impact", View.to3(pg, game.terrain.height_at(pg)), -16.0, 2, 0.12, 0.2)
		"volley":
			at("arrow_impact", View.to3(e.pos, game.terrain.height_at(e.pos)), -4.0, 2, 0.05)
		"knockback":
			at("wind_gust", _pos(w, e.u), -8.0, 0, 0.2)
		"buy":
			if e.u == game.player_hero_id:
				ui("ui_buy", -6.0)
		"error":
			if e.u == game.player_hero_id:
				ui("ui_error", -8.0)
		"glyph":
			ui("holy_chime", -4.0)
		"hero_kill":
			if e.get("first_blood", false):
				ui("war_cry", -2.0)
			elif int(e.get("ended_streak", 0)) >= 3:
				ui("sting_boss", -4.0)
			elif int(e.get("streak", 0)) >= 3:
				ui("elite_spawn", -4.0)
			elif int(e.get("u", -1)) == game.player_hero_id:
				ui("sting_victory", -8.0)
		"respawn":
			if e.u == game.player_hero_id:
				ui("holy_cast", -6.0)
		"item_use":
			var it := String(e.item)
			if it in ["salve", "clarity", "mango", "faerie_fire", "tango"]:
				at("potion_drink", _pos(w, e.u), -6.0)
			elif it == "observer_ward":
				at("item_pickup", _pos(w, e.u), -6.0)
		"burst_wave":
			at("bow_attack", _pos(w, e.u), -3.0, 3, 0.05)
			at("crossbow_fire", _pos(w, e.u), -9.0, 2, 0.05)
		"gale_hit":
			at("hit_heavy", _pos(w, e.u), -3.0, 2, 0.08)
		"masterful_hit":
			at("crit_hit", _pos(w, e.target), -3.0, 0, 0.1)
		"back_leap":
			at("dodge_roll", _pos(w, e.u), -6.0, 0, 0.2)
		"tree":
			if not bool(e.alive) and e.has("from"):
				at("break_wood", View.to3(game.map.trees[int(e.i)].pos, game.terrain.height_at(game.map.trees[int(e.i)].pos)), -4.0, 2, 0.1)
		"attack_start":
			pass
