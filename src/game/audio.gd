class_name GameAudio
extends Node3D
## Sound for the match. Positional effects come from simulation events and are heard from the camera's ground
## point (like Dota, where the listener sits under the camera). Cues that are only for you (gold, level-up, shop,
## errors) play in 2D, and a forest ambience loops underneath. A small pool of players with per-sound cooldowns keeps
## big fights from turning into noise.

const SFX := "res://assets/audio/sfx/%s.wav"
const POOL := 40

var game: Node
var listener: AudioListener3D
var _pool: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _streams := {}
var _last := {}
var _i := 0
var _rng := RandomNumberGenerator.new()
var world_audio: AudioWorld                 # hits by material, ambience in 3D, the room's reverb

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
		# air takes the edge off distant sounds; muffled ones (in the fog) are set lower per play
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_pool.append(p)
	for i in 6:
		var u := AudioStreamPlayer.new()
		u.bus = "Interface"
		add_child(u)
		_ui.append(u)
	# the effect sounds are read now, not on first use mid-fight
	var dir := DirAccess.open("res://assets/audio/sfx")
	if dir:
		for f in dir.get_files():
			var base := f.trim_suffix(".import")
			if base.ends_with(".wav"):
				_stream(base.get_basename())
	if not OS.get_cmdline_user_args().has("--noaudioworld"):
		world_audio = AudioWorld.new()
		world_audio.game = game
		world_audio.audio = self
		add_child(world_audio)
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
	p.attenuation_filter_cutoff_hz = 9000.0
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.global_position = pos
	p.play()

## A ranged hero's attack leaving its hand, by what it throws (ModelCatalog "proj"): only the archer draws a bow;
## Azrin's fireballs whoosh, Froster's bolts crackle with frost, Feran's knives whip through the air.
func _hero_shot(src: SimUnit, p: Vector3) -> void:
	match String(ModelCatalog.info(String(src.def.model)).get("proj", "")):
		"arrow":
			at("bow_attack", p, -4.0, 3)
		"fireball", "fire", "fire_big":
			at("fire_whoosh", p, -7.0, 0, 0.08, 0.12)
			at("cast_fire", p, -14.0, 0, 0.2, 0.1)
		"frost_bolt":
			at("cast_ice", p, -11.0, 0, 0.1, 0.12)
		"knife":
			at("swing_dagger", p, -3.0, 2, 0.05, 0.15)
			at("attack_woosh", p, -11.0, 3, 0.05, 0.2)
		"bullet", "turret_shot":
			at("crossbow_fire", p, -5.0, 2, 0.06)
		_:
			at("mage_attack", p, -8.0, 2, 0.08)

## A ranged hero's attack landing, matched to _hero_shot.
func _hero_shot_hit(src: SimUnit, p: Vector3) -> void:
	match String(ModelCatalog.info(String(src.def.model)).get("proj", "")):
		"arrow":
			at("arrow_impact", p, -6.0, 2, 0.05)
		"fireball", "fire", "fire_big":
			at("fireball_hit", p, -10.0, 0, 0.1, 0.12)
		"frost_bolt":
			at("shatter_ice", p, -10.0, 0, 0.1, 0.12)
		"knife":
			at("dagger_hit", p, -5.0, 3, 0.05)
		_:
			at("magic_hit", p, -7.0, 2, 0.06)

## Play a stream at a point (AudioWorld's sounds): `key` limits repeats to one per `cooldown`; muffled: heard
## through the fog (quieter, high frequencies cut).
func play_stream(s: AudioStream, pos: Vector3, vol: float, key: String, cooldown := 0.06, pitch_jitter := 0.08,
		pitch := 1.0, muffled := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(key, -9.0)) < cooldown or pos.distance_to(listener.global_position) > 48.0:
		return
	_last[key] = now
	var p := _pool[_i]
	_i = (_i + 1) % POOL
	p.stream = s
	p.volume_db = vol - (6.0 if muffled else 0.0)
	p.attenuation_filter_cutoff_hz = 1400.0 if muffled else 9000.0
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))
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

## Lane and neutral creeps die 40% quieter (owner's request, 2026-10-14): 60% as loud by the ear, the same rule as the
## volume sliders (Options.to_db): 10 * log2(0.6) = -7.4 dB.
const CREEP_DEATH_DB := -7.37

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
					_hero_shot(src, p)
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
			# what hit what: the weapon on the target's material (AudioWorld), under the attacker's own sound below
			if world_audio and not bool(e.get("blocked", false)):
				world_audio.hit(src2, w.get_unit(e.u), float(e.get("amount", 0.0)), p2)
			if src2.kind == SimConst.Kind.HERO and String(src2.def.id) == "ezee":
				at("greatsword_hit", p2, -5.0, 3, 0.05)
				return
			if src2.kind == SimConst.Kind.HERO and String(src2.def.id) == "araki":
				at("sword_hit", p2, -7.0, 3, 0.05)          # his katana (and his ghosts' blows)
				return
			if src2.kind == SimConst.Kind.HERO and String(src2.def.id) == "sludge":
				at("axe_hit", p2, -4.0, 3, 0.05)
				at("hit_flesh", p2, -10.0, 3, 0.05)
				return
			if src2.is_ranged():
				if src2.is_hero():
					_hero_shot_hit(src2, p2)
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
				at("ghoul_death", p3, -10.0 + CREEP_DEATH_DB, 0, 0.15)
			elif u.is_creep():
				at("body_fall", p3, -12.0 + CREEP_DEATH_DB, 0, 0.12)
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
					if world_audio:
						world_audio.strike("wood", pi, -4.0)
				"cliff", "building":
					at("wall_impact", pi, -2.0, 2, 0.08)
					if world_audio:
						world_audio.strike("stone", pi, -4.0)
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
				if world_audio:
					world_audio.strike("ground", View.to3(pg, game.terrain.height_at(pg)), -14.0)
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
		# Araki (run 2026-10-19 c): the dash's rush and cut, the bomb's throw and burst, the ghosts' hiss, The Blur
		"blur_strike":
			var pf := View.to3(e.from, game.terrain.height_at(e.from)) + Vector3(0, 1.0, 0)
			var pt := View.to3(e.to, game.terrain.height_at(e.to)) + Vector3(0, 1.0, 0)
			at("blink", pf, -6.0, 0, 0.05)
			at("swing_light", pt, -2.0, 3, 0.05)
			if not (e.hits as Array).is_empty():
				at("cleave", pt, -5.0, 2, 0.05)
		"djin_bomb":
			at("swing_dagger", _pos(w, e.u), -6.0, 2, 0.1)
		"djin_smoke":
			var pd := View.to3(e.pos, game.terrain.height_at(e.pos)) + Vector3(0, 0.6, 0)
			at("fire_explode", pd, -3.0, 0, 0.2, 0.05)
			at("shade_hiss", pd, -6.0, 0, 0.3, 0.05)
		"ghosts_call":
			at("dark_cast", _pos(w, e.u), -5.0, 0, 0.2)
		"ghost_spawn":
			at("shade_hiss", _pos(w, e.ghost), -14.0, 0, 0.15, 0.15)
		"the_blur":
			at("boss_charge", _pos(w, e.u), -5.0, 0, 0.3)
		"attack_start":
			pass
