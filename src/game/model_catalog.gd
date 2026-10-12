class_name ModelCatalog
extends RefCounted
## How each simulation model key looks: which GLB, its scale, the weapons in its hands, which clips it plays and how
## its attack is drawn. Clip timings (hits, release, ground speed) come from the GLB's anim_meta.json.

const UNITS := "res://assets/characters/units/"
const WEAPONS := "res://assets/weapons/"

## scale: model scale (1.0 = the 1.8 m rig). attack: clip names tried in order (cycled per swing).
## proj: projectile style for ranged units. bar: health bar height above the ground (m).
const MODELS := {
	"hero": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.0, "attack": ["bow_1"], "cast": "cast_quick",
		"idle": "idle_bow", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72, "death": "death", "R": "", "L": "bow",
		"proj": "arrow", "bar": 2.25, "hero": true},
	"hero_ezee": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.0, "attack": ["gs_1", "gs_2", "gs_3", "gs_4"],
		"cast": "cast_quick", "idle": "idle_2h", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72,
		"death": "death", "R": "greatsword", "L": "", "bar": 2.4, "hero": true, "weapon_tint": Color(0.5, 0.44, 0.62),
		"weapon_glow": Color(0.55, 0.2, 1.0), "swing_trail": true},
	# Sludge: his own body (tools/blender/sludge.py) on the hero skeleton; cleaver right, shuriken hook left
	"hero_sludge": {"scene": "res://assets/characters/hero/sludge.glb", "scale": 1.22, "attack": ["axe_1", "axe_2", "axe_3"],
		"cast": "cast_quick", "idle": "idle_1h", "run": "hero_run", "run_female": "hero_run", "run_min": 0.72,
		"death": "death", "R": "cleaver", "L": "shuriken_hook", "bar": 2.95, "skin_shader": "res://src/game/sludge_skin.gdshader",
		"gear_materials": true, "swing_trail": true},
	"dawn_melee": {"scene": UNITS + "knight.glb", "scale": 0.86, "attack": ["sword_1", "sword_2", "sword_3"], "idle": "idle_shield",
		"run": "run", "death": "death", "R": "sword", "L": "shield", "bar": 2.0, "tint": Color(1.0, 0.97, 0.88)},
	"dawn_ranged": {"scene": UNITS + "mage.glb", "scale": 0.86, "attack": ["staff_1", "staff_2"], "idle": "idle_staff",
		"run": "run", "death": "death", "R": "staff_aether", "L": "", "proj": "sun_orb", "bar": 2.0},
	"dawn_flag": {"scene": UNITS + "knight.glb", "scale": 0.92, "attack": ["sword_1", "sword_2"], "idle": "idle_shield",
		"run": "run", "death": "death", "R": "sword_aether", "L": "shield", "bar": 2.1, "banner": Color(1.0, 0.82, 0.3)},
	"dawn_siege": {"scene": UNITS + "rune_golem.glb", "scale": 1.15, "attack": ["boss_slam"], "idle": "idle", "run": "walk",
		"death": "death", "R": "", "L": "", "proj": "boulder_sun", "bar": 2.9},
	"dusk_melee": {"scene": UNITS + "ghoul_brute.glb", "scale": 0.86, "attack": ["axe_2"], "idle": "idle", "run": "run",
		"death": "death", "R": "axe", "L": "", "bar": 2.0},
	"dusk_ranged": {"scene": UNITS + "necromancer.glb", "scale": 0.86, "attack": ["staff_1", "staff_2"], "idle": "idle_staff",
		"run": "run", "death": "death", "R": "staff", "L": "", "proj": "doom_orb", "bar": 2.0},
	"dusk_flag": {"scene": UNITS + "warband_chieftain.glb", "scale": 0.92, "attack": ["axe_1", "axe_2"], "idle": "idle",
		"run": "run", "death": "death", "R": "axe", "L": "", "bar": 2.1, "banner": Color(0.6, 0.1, 0.2)},
	"dusk_siege": {"scene": UNITS + "obsidian_golem.glb", "scale": 1.1, "attack": ["boss_slam"], "idle": "idle", "run": "walk",
		"death": "death", "R": "", "L": "", "proj": "boulder_doom", "bar": 2.9},
	"courier": {"scene": UNITS + "aether_wisp.glb", "scene_dusk": UNITS + "star_mote.glb", "scale": 1.6, "attack": [],
		"idle": "idle", "run": "idle", "death": "death", "R": "", "L": "", "bar": 2.4, "float": 1.5},
	"mudling": {"scene": UNITS + "goblin_skulker.glb", "scale": 0.8, "attack": ["dagger_1", "dagger_2"], "idle": "idle",
		"run": "run", "death": "death", "R": "dagger", "L": "", "bar": 1.6},
	"mudling_digger": {"scene": UNITS + "goblin_sapper.glb", "scale": 0.85, "attack": ["dagger_1", "dagger_2"], "idle": "idle",
		"run": "run", "death": "death", "R": "dagger", "L": "", "bar": 1.7},
	"mudling_foreman": {"scene": UNITS + "goblin_summoner.glb", "scale": 0.95, "attack": ["staff_1", "wand_1", "dagger_1"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "bar": 1.9},
	"ashfang": {"scene": UNITS + "dire_wolf.glb", "scale": 0.8, "attack": ["wolf_bite"], "idle": "idle", "run": "run",
		"death": "death", "R": "", "L": "", "bar": 1.5},
	"ashfang_alpha": {"scene": UNITS + "dire_wolf.glb", "scale": 1.05, "attack": ["wolf_bite", "wolf_pounce"], "idle": "idle",
		"run": "run", "death": "death", "R": "", "L": "", "bar": 1.8, "tint": Color(0.75, 0.68, 0.62)},
	"strider": {"scene": UNITS + "orc_reaver.glb", "scale": 0.92, "attack": ["axe_1", "axe_3"], "idle": "idle", "run": "run",
		"death": "death", "R": "axe", "L": "", "bar": 2.1},
	"strider_warlord": {"scene": UNITS + "orc_shaman.glb", "scale": 1.15, "attack": ["staff_1", "cast_quick"], "idle": "idle",
		"run": "run", "death": "death", "R": "staff", "L": "", "bar": 2.5},
	"hill_troll": {"scene": UNITS + "mire_troll.glb", "scale": 0.95, "attack": ["spear_1", "staff_1", "cast_quick"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "proj": "spear", "bar": 2.2},
	"ogre_brute": {"scene": UNITS + "ogre_crusher.glb", "scale": 1.0, "attack": ["boss_slam", "axe_1"], "idle": "idle",
		"run": "run", "death": "death", "R": "", "L": "", "bar": 2.6},
	"cinder_wyrmling": {"scene": UNITS + "cinder_imp.glb", "scale": 1.0, "attack": ["wand_1", "cast_quick"], "idle": "idle",
		"run": "run", "death": "death", "R": "wand", "L": "", "proj": "fire", "bar": 2.0},
	"elder_cinder_wyrm": {"scene": UNITS + "magma_golem.glb", "scale": 1.35, "attack": ["cast_heavy", "boss_slam"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "proj": "fire_big", "bar": 3.2},
}

static var _meta := {}
static var _scenes := {}

static func info(model_key: String) -> Dictionary:
	return MODELS.get(model_key, {})

static func scene(model_key: String) -> PackedScene:
	var path: String = MODELS[model_key].scene
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## Timing data for a clip: {length, hits, release, ground_speed, ...} (empty if unknown).
static func clip(name: String) -> Dictionary:
	if _meta.is_empty():
		for f in [UNITS + "anim_meta.json", UNITS + "creature_meta.json", "res://assets/characters/hero/hero_meta.json"]:
			var d = JSON.parse_string(FileAccess.get_file_as_string(f))
			if d is Dictionary and d.has("animations"):
				for k in d.animations:
					if not _meta.has(k):
						_meta[k] = d.animations[k]
	return _meta.get(name, {})

## The moment within an attack clip (seconds at 1x) when the blow lands or the shot leaves.
static func strike_time(name: String) -> float:
	var c := clip(name)
	if c.has("release"):
		return float(c.release)
	if c.has("hits") and not (c.hits as Array).is_empty():
		var h: Array = c.hits[0]
		return (float(h[0]) + float(h[1])) * 0.5
	return float(c.get("length", 0.5)) * 0.5

static func weapon(name: String) -> PackedScene:
	if name == "":
		return null
	var path := WEAPONS + name + ".glb"
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]
