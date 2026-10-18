class_name AudioWorld
extends Node3D
## The match's sound world beyond single cues (GameAudio plays those), heard from the camera like the rest:
##   * Hits by what hits and what is hit: a sword on plate rings, on flesh it cuts, a club or a boulder thuds, claws
##     rake, arrows clink off armour and thunk into bodies, tower bolts land with a blast; stone, wood and spirits
##     answer in their own way. Bigger hits (a larger share of the target's health) are louder, big attackers pitch
##     lower, and a hit your team cannot see comes muffled and quieter.
##   * Living ambience in 3D: birds in the trees around the camera by day, crickets in the grass and frogs by the water
##     at night, the river where it flows and the Lily Ponds. Each comes from a real spot in the world (they pan and
##     fade as the camera moves) and crossfades with day and night.
##   * Footsteps: heroes walking close to the camera tread softly on the grass (not in the river or the fog).
##   * The room: reverb on the Effects bus follows where the camera looks (forest, river, base walls, mountains,
##     open ground).
## Sounds: CC0 packs (Kenney "Impact Sounds" and "RPG Audio"; OpenGameArt: isaiah658, syncopika, Wolfgang_,
## EZduzziteh, rubberduck, Eldritch Grim), see docs/ASSET_CREDITS.md.

const DIR := "res://assets/audio/cc0/"
## name -> [file pattern (%d = variant), first variant, variant count]
const GROUPS := {
	"metal_l": ["kenney_impactMetal_light_%03d.ogg", 0, 5], "metal_m": ["kenney_impactMetal_medium_%03d.ogg", 0, 5],
	"metal_h": ["kenney_impactMetal_heavy_%03d.ogg", 0, 5], "plate_l": ["kenney_impactPlate_light_%03d.ogg", 0, 5],
	"plate_m": ["kenney_impactPlate_medium_%03d.ogg", 0, 5], "plate_h": ["kenney_impactPlate_heavy_%03d.ogg", 0, 5],
	"punch_m": ["kenney_impactPunch_medium_%03d.ogg", 0, 5], "punch_h": ["kenney_impactPunch_heavy_%03d.ogg", 0, 5],
	"soft_m": ["kenney_impactSoft_medium_%03d.ogg", 0, 5], "soft_h": ["kenney_impactSoft_heavy_%03d.ogg", 0, 5],
	"wood_l": ["kenney_impactWood_light_%03d.ogg", 0, 5], "wood_m": ["kenney_impactWood_medium_%03d.ogg", 0, 5],
	"wood_h": ["kenney_impactWood_heavy_%03d.ogg", 0, 5], "stone": ["kenney_impactMining_%03d.ogg", 0, 5],
	"generic": ["kenney_impactGeneric_light_%03d.ogg", 0, 5], "plank": ["kenney_impactPlank_medium_%03d.ogg", 0, 5],
	"slice": ["kenney_knifeSlice%s.ogg", -1, 2], "chop": ["kenney_chop.ogg", -1, 1],
	"clang": ["sfx100_metal_%02d.ogg", 1, 12], "slam": ["sfx100_slam_%02d.ogg", 1, 7], "thud": ["sfx100_hit_%02d.ogg", 1, 4],
	"blast": ["impact_%02d.wav", 1, 15], "boom": ["sfx100_explosion.ogg", -1, 1], "cloth": ["kenney_cloth%d.ogg", 1, 4],
	"croak": ["frog_croak_%d.mp3", 1, 4], "ribbit": ["frog_ribbit_%d.mp3", 1, 3],
	"step": ["kenney_footstep_grass_%03d.ogg", 0, 5],
}

## What a unit is made of, by model (heroes and creeps); anything else falls back by kind.
const MATERIALS := {
	"hero_ezee": "plate", "hero_kragg": "plate", "hero_tock": "metal", "hero_roydo": "plate", "hero_anomaly": "stone",
	"hero_sludge": "flesh", "hero_azrael": "spirit", "hero_froster": "cloth", "hero_azrin": "cloth", "hero_caziel": "leather",
	"hero": "leather", "hero_blau": "leather", "blau_turret": "metal", "hero_emelrich": "plate", "hero_burak": "flesh",
	"hero_airah": "cloth", "hero_feran": "cloth", "hero_ghorman": "leather", "hero_ghorman_beast": "flesh",
	"dawn_melee": "plate", "dawn_flag": "plate", "dawn_ranged": "cloth", "dawn_siege": "stone",
	"dusk_melee": "flesh", "dusk_flag": "leather", "dusk_ranged": "cloth", "dusk_siege": "stone",
	"courier": "spirit", "elder_cinder_wyrm": "stone", "cinder_wyrmling": "flesh", "ashfang": "flesh",
	"ashfang_alpha": "flesh", "ogre_brute": "flesh", "hill_troll": "flesh", "strider": "leather",
	"strider_warlord": "leather", "mudling": "flesh", "mudling_digger": "leather", "mudling_foreman": "flesh",
}

var game: Node
var audio: GameAudio
var _streams := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "AudioWorld"
	_rng.randomize()
	_preload()
	_setup_reverb()
	_build_ambience()

## Every sound is read while the match loads: a first load mid-fight (a decode from disk) was a 30-60 ms hitch.
func _preload() -> void:
	for g in GROUPS:
		var spec: Array = GROUPS[g]
		for i in int(spec[2]):
			var file: String
			if int(spec[1]) < 0:
				file = String(spec[0]) % ("" if i == 0 else str(i + 1)) if String(spec[0]).contains("%s") else String(spec[0])
			else:
				file = String(spec[0]) % (int(spec[1]) + i)
			_res(file)
	for f in ["amb_birds.ogg", "bird_chirps.wav", "amb_crickets.mp3", "loop_water_flowing.ogg"]:
		_res(f)

func _res(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := DIR + file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]

## A random sound of a group.
func pick(group: String) -> AudioStream:
	var g: Array = GROUPS.get(group, [])
	if g.is_empty():
		return null
	var n: int = g[2]
	var i: int = _rng.randi_range(0, n - 1)
	var file: String
	if int(g[1]) < 0:
		file = String(g[0]) % ("" if i == 0 else str(i + 1)) if String(g[0]).contains("%s") else String(g[0])
	else:
		file = String(g[0]) % (int(g[1]) + i)
	return _res(file)

# ---- Hits ------------------------------------------------------------------------------------------------------------

## How a unit's attack lands: blade, blunt, claw, arrow, magic, siege, tower.
static func weapon_of(u: SimUnit) -> String:
	if u == null:
		return "blunt"
	if u.kind == SimConst.Kind.TOWER or u.kind == SimConst.Kind.FOUNTAIN:
		return "tower"
	if u.kind == SimConst.Kind.CREEP_SIEGE:
		return "siege"
	var cfg := ModelCatalog.info(String(u.def.get("model", "")))
	if u.is_ranged():
		var proj := String(cfg.get("proj", ""))
		if proj in ["arrow", "spear", "bullet", "turret_shot"] or proj == "":
			return "arrow"
		if proj.begins_with("boulder"):
			return "siege"
		return "magic"
	var wpn := String(cfg.get("R", ""))
	for k in ["sword", "dagger", "cleaver", "scythe", "axe", "greatsword"]:
		if wpn.contains(k):
			return "blade"
	if wpn.contains("staff") or wpn.contains("wand") or wpn.contains("hammer") or wpn.contains("club"):
		return "blunt"
	var model := String(u.def.get("model", ""))
	if model.begins_with("ashfang") or model.begins_with("cinder") or model.begins_with("mudling"):
		return "claw"
	return "blunt"

static func material_of(u: SimUnit) -> String:
	if u == null:
		return "flesh"
	if u.is_building():
		return "stone"
	if u.kind == SimConst.Kind.WARD:
		return "wood"
	return String(MATERIALS.get(String(u.def.get("model", "")), "leather"))

## The layers of one hit: [[group, dB], ...] by weapon and material.
static func layers(weapon: String, mat: String) -> Array:
	var hard := mat in ["plate", "metal"]
	match weapon:
		"blade":
			if hard:
				return [["metal_m", -6.0], ["clang", -14.0]]
			if mat == "stone":
				return [["stone", -6.0], ["metal_l", -12.0]]
			if mat == "wood":
				return [["wood_m", -6.0], ["chop", -10.0]]
			if mat == "spirit":
				return [["slice", -10.0]]
			return [["slice", -7.0], ["soft_m", -10.0]]
		"claw":
			if hard:
				return [["metal_l", -8.0]]
			return [["slice", -9.0], ["soft_m", -11.0]]
		"blunt":
			if hard:
				return [["plate_h", -6.0]]
			if mat == "stone":
				return [["stone", -5.0]]
			if mat == "wood":
				return [["wood_h", -6.0]]
			return [["punch_m", -6.0], ["soft_h", -12.0]]
		"arrow":
			if hard:
				return [["metal_l", -8.0]]
			if mat == "stone":
				return [["generic", -8.0]]
			if mat == "wood":
				return [["wood_l", -7.0]]
			if mat == "spirit":
				return [["cloth", -12.0]]
			return [["soft_m", -7.0]]
		"magic":
			if hard:
				return [["plate_l", -12.0]]
			if mat == "stone":
				return [["generic", -12.0]]
			return [["soft_m", -14.0]]
		"siege":
			return [["slam", -4.0], ["stone" if mat == "stone" else "punch_h", -8.0]]
		"tower":
			return [["blast", -4.0], ["plate_m" if hard else ("stone" if mat == "stone" else "punch_h"), -10.0]]
	return [["generic", -10.0]]

## An attack landed: `src` hit `tgt` for `amount` at `pos`. Heroes' and towers' hits sound at full weight, creeps' and
## neutrals' quieter (a lane is a dozen swings a second).
func hit(src: SimUnit, tgt: SimUnit, amount: float, pos: Vector3) -> void:
	if audio == null or tgt == null:
		return
	var weapon := weapon_of(src)
	var mat := material_of(tgt)
	var share := clampf(amount / maxf(1.0, tgt.max_hp), 0.0, 1.0)
	var vol := lerpf(-3.0, 2.0, clampf(share * 6.0, 0.0, 1.0))
	if src != null and not src.is_hero() and weapon != "tower" and weapon != "siege":
		vol -= 7.0
	var pitch := clampf(1.18 - (src.hull if src else 24.0) / 160.0, 0.75, 1.2)
	var key := "hit:%s:%s" % [weapon, mat]
	var cd := 0.04 if (src != null and src.is_hero()) else 0.09
	var seen := _seen(pos)
	for l in layers(weapon, mat):
		var s := pick(String(l[0]))
		if s != null:
			audio.play_stream(s, pos, float(l[1]) + vol, key + String(l[0]), cd, 0.07, pitch, not seen)

## Something struck the ground or a tree (missed arrows, thrown units, felled trees): its own material.
func strike(mat: String, pos: Vector3, vol := -6.0) -> void:
	var g := {"wood": "wood_h", "stone": "stone", "metal": "metal_h", "ground": "thud"}.get(mat, "thud") as String
	var s := pick(g)
	if s != null and audio != null:
		audio.play_stream(s, pos, vol, "strike:" + mat, 0.06, 0.08, 1.0, not _seen(pos))

## Whether the player's team sees the spot (sounds from the fog are muffled).
func _seen(pos: Vector3) -> bool:
	if game == null or game.world == null:
		return true
	return game.sees_cell(View.to2(pos))

# ---- Room ------------------------------------------------------------------------------------------------------------

var _reverb: AudioEffectReverb
var _verb_target := Vector3(0.3, 0.5, 0.08)    # room size, damping, wet
var _verb_t := 0.0

func _setup_reverb() -> void:
	Options.ensure_buses()
	var bi := AudioServer.get_bus_index("Effects")
	if bi < 0:
		return
	for i in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) is AudioEffectReverb:
			_reverb = AudioServer.get_bus_effect(bi, i)
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.predelay_msec = 40.0
		_reverb.hipass = 0.15
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(bi, _reverb)
	_reverb.room_size = 0.3
	_reverb.damping = 0.5
	_reverb.wet = 0.08

## The area under the camera: deep forest rings longer and softer, the base's walls echo, the river is open and dry,
## the mountains a wide cold space.
func _room(p: Vector2) -> Vector3:
	var map: SimMap = game.map
	var river := absf(p.x + p.y) / sqrt(2.0)
	if river < 900.0:
		return Vector3(0.25, 0.3, 0.05)
	if map.level_at(p) == SimMap.MOUNTAIN or map.edge_distance(p) < 600.0:
		return Vector3(0.75, 0.35, 0.16)
	if map.level_at(p) == SimMap.HIGH and (map._in_base(p) or map._in_base(-p)):
		return Vector3(0.55, 0.45, 0.14)
	var cover := float(map.tree_cover(p, 3)) / 49.0
	return Vector3(lerpf(0.3, 0.6, cover), lerpf(0.5, 0.8, cover), lerpf(0.06, 0.15, cover))

# ---- Ambience --------------------------------------------------------------------------------------------------------

var _birds: Array[AudioStreamPlayer3D] = []
var _bird_next: Array[float] = []
var _crickets: Array[AudioStreamPlayer3D] = []
var _frog: AudioStreamPlayer3D
var _frog_next := 0.0
var _river: AudioStreamPlayer3D
var _ponds: Array[AudioStreamPlayer3D] = []
var _night_mix := 0.0                          # 0 day .. 1 night, eased

func _player3d(bus := "Ambience", unit := 10.0, max_d := 60.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.unit_size = unit
	p.max_distance = max_d
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.9
	add_child(p)
	return p

func _loop(file: String) -> AudioStream:
	var s := _res(file)
	if s == null:
		return null
	s = s.duplicate()
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		var wv := s as AudioStreamWAV
		wv.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wv.loop_end = int(wv.get_length() * wv.mix_rate)
	return s

func _build_ambience() -> void:
	for i in 5:
		_birds.append(_player3d("Ambience", 9.0, 55.0))
		_bird_next.append(0.0)
	for i in 3:
		var c := _player3d("Ambience", 8.0, 45.0)
		c.stream = _loop("amb_crickets.mp3")
		c.volume_db = -80.0
		_crickets.append(c)
	_frog = _player3d("Ambience", 7.0, 45.0)
	_river = _player3d("Ambience", 14.0, 70.0)
	_river.stream = _loop("loop_water_flowing.ogg")
	_river.volume_db = -9.0
	if game and game.world:
		for s in game.world.sites.of_kind("pond"):
			var pp := _player3d("Ambience", 6.0, 35.0)
			pp.stream = _river.stream
			pp.volume_db = -16.0
			pp.pitch_scale = 1.25
			pp.global_position = View.to3(s.pos, game.terrain.height_at(s.pos)) + Vector3(0, 0.3, 0)
			_ponds.append(pp)

func _process(dt: float) -> void:
	if game == null or game.camera == null or game.world == null or audio == null:
		return
	var lp: Vector3 = audio.listener.global_position
	var c2 := View.to2(game.camera.target)
	var night: bool = game.world.is_night()
	_night_mix = move_toward(_night_mix, 1.0 if night else 0.0, dt / 6.0)
	# the room
	_verb_t -= dt
	if _verb_t <= 0.0:
		_verb_t = 0.5
		_verb_target = _room(c2)
	if _reverb:
		_reverb.room_size = lerpf(_reverb.room_size, _verb_target.x, clampf(dt * 1.5, 0.0, 1.0))
		_reverb.damping = lerpf(_reverb.damping, _verb_target.y, clampf(dt * 1.5, 0.0, 1.0))
		_reverb.wet = lerpf(_reverb.wet, _verb_target.z, clampf(dt * 1.5, 0.0, 1.0))
	# the river: its sound comes from the nearest point of its course
	if _river.stream:
		var t := (c2.x - c2.y) * 0.5
		var rp := Vector2(t, -t)
		_river.global_position = View.to3(rp, game.terrain.height_at(rp)) + Vector3(0, 0.5, 0)
		if not _river.playing:
			_river.play(_rng.randf() * 4.0)
	for pp in _ponds:
		if pp.stream and not pp.playing and pp.global_position.distance_to(lp) < 40.0:
			pp.play()
		elif pp.playing and pp.global_position.distance_to(lp) > 45.0:
			pp.stop()
	var now := Time.get_ticks_msec() / 1000.0
	_update_steps(now, lp)
	_update_birds(now, c2)
	_update_crickets(dt, c2)
	_update_frogs(now, c2)

var _step_at := {}                             # hero id -> time of its next footstep

## Heroes walking near the camera tread on the grass, a step every ~0.33 s at 300 speed (faster heroes step faster).
func _update_steps(now: float, lp: Vector3) -> void:
	for h: SimUnit in game.world.heroes:
		if not h.alive or not h.moving or h.has_flag("hidden") or h.has_flag("flying"):
			continue
		if not game.sees(h) or game.map.level_at(h.pos) == SimMap.RIVER:
			continue
		var p3 := View.to3(h.pos, game.terrain.height_at(h.pos))
		if p3.distance_to(lp) > 22.0 or now < float(_step_at.get(h.id, 0.0)):
			continue
		_step_at[h.id] = now + clampf(100.0 / maxf(h.move_speed, 100.0), 0.2, 0.5)
		var s := pick("step")
		if s != null:
			audio.play_stream(s, p3, -20.0 if h.id != game.player_hero_id else -16.0, "step%d" % h.id, 0.15, 0.1)

## Birds sing from trees near the camera by day: each voice picks a tree, sings a few seconds of song or a chirp, rests.
func _update_birds(now: float, c2: Vector2) -> void:
	var day := 1.0 - _night_mix
	for i in _birds.size():
		var b := _birds[i]
		if b.playing and now >= _bird_next[i]:
			b.stop()
			_bird_next[i] = now + _rng.randf_range(2.0, 9.0)
			continue
		if b.playing or now < _bird_next[i] or day < 0.3:
			continue
		var spot := _tree_near(c2, 600.0, 2600.0)
		if spot == Vector2.INF:
			_bird_next[i] = now + 3.0
			continue
		b.global_position = View.to3(spot, game.terrain.height_at(spot)) + Vector3(0, 3.5, 0)
		var song := _rng.randf() < 0.6
		b.stream = _res("amb_birds.ogg") if song else _res("bird_chirps.wav")
		b.pitch_scale = _rng.randf_range(0.92, 1.12)
		b.volume_db = linear_to_db(day) + (-11.0 if song else -9.0)
		var length := b.stream.get_length() if b.stream else 1.0
		var dur := _rng.randf_range(2.5, 6.0) if song else minf(length, _rng.randf_range(0.8, 2.4))
		b.play(_rng.randf() * maxf(0.0, length - dur))
		_bird_next[i] = now + dur

## Crickets from the grass near the camera at night (three voices spread around it, drifting as it moves).
func _update_crickets(dt: float, c2: Vector2) -> void:
	var on := _night_mix
	for i in _crickets.size():
		var c := _crickets[i]
		if c.stream == null:
			continue
		if on <= 0.01:
			if c.playing:
				c.stop()
			continue
		var a := TAU * i / 3.0 + 0.6
		var want := c2 + Vector2(cos(a), sin(a)) * 1300.0
		var cur := View.to2(c.global_position)
		if not c.playing or cur.distance_to(want) > 2600.0:
			cur = want
		cur = cur.lerp(want, clampf(dt * 0.3, 0.0, 1.0))
		if game.map.level_at(cur) == SimMap.RIVER or game.map.level_at(cur) == SimMap.MOUNTAIN:
			c.volume_db = move_toward(c.volume_db, -80.0, dt * 30.0)
		else:
			c.volume_db = move_toward(c.volume_db, linear_to_db(on) - 12.0, dt * 20.0)
		c.global_position = View.to3(cur, game.terrain.height_at(cur)) + Vector3(0, 0.2, 0)
		if not c.playing:
			c.pitch_scale = 0.95 + 0.05 * i
			c.play(_rng.randf() * 8.0)

## Frogs croak by the river and the Lily Ponds, now and then by day, often at night.
func _update_frogs(now: float, c2: Vector2) -> void:
	if now < _frog_next:
		return
	_frog_next = now + _rng.randf_range(1.5, 4.0) * lerpf(4.0, 1.0, _night_mix)
	var spot := Vector2.INF
	var t := (c2.x - c2.y) * 0.5
	var bank := Vector2(t, -t) + Vector2(1, 1).normalized() * (_rng.randf_range(500.0, 800.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
	if bank.distance_to(c2) < 2600.0:
		spot = bank + Vector2(_rng.randf_range(-600, 600), _rng.randf_range(-600, 600))
	for s in game.world.sites.of_kind("pond"):
		if (s.pos as Vector2).distance_to(c2) < 2000.0 and _rng.randf() < 0.6:
			spot = (s.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 250.0
	if spot == Vector2.INF:
		return
	_frog.stream = pick("ribbit" if _rng.randf() < 0.5 else "croak")
	_frog.global_position = View.to3(spot, game.terrain.height_at(spot)) + Vector3(0, 0.2, 0)
	_frog.pitch_scale = _rng.randf_range(0.85, 1.15)
	_frog.volume_db = -12.0 + 4.0 * _night_mix
	_frog.play()

## A living tree near `c` (between `r0` and `r1` away), or INF.
func _tree_near(c: Vector2, r0: float, r1: float) -> Vector2:
	for attempt in 6:
		var p := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(r0, r1)
		var ti: int = game.map.tree_at(p, 260.0)
		if ti >= 0 and game.map.trees[ti].alive:
			return game.map.trees[ti].pos
	return Vector2.INF
