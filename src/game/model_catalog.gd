class_name ModelCatalog
extends RefCounted
## How each simulation model key looks: which GLB, its scale, the weapons in its hands, which clips it plays and how
## its attack is drawn. Clip timings (hits, release, ground speed) come from the GLB's anim_meta.json.

const UNITS := "res://assets/characters/units/"
const WEAPONS := "res://assets/weapons/"
const H16 := "res://assets/characters/heroes16/"
const H17 := "res://assets/characters/heroes17/"

## scale: model scale (1.0 = the 1.8 m rig). attack: clip names tried in order (cycled per swing); every one must be in
## the model (tests/tools/anim_audit.gd --units reports MISSING clips).
## proj: projectile style for ranged units. bar: health bar height above the ground (m).
const MODELS := {
	"hero": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.0, "attack": ["bow_1"], "cast": "cast_quick",
		"idle": "idle_bow", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72, "death": "death", "R": "", "L": "bow",
		"proj": "arrow", "bar": 2.25, "hero": true},
	# Ezee (2026-10-17): his own body, the owner's fallen paladin in black plate (tools/blender/hero_body.py: baked,
	# bound in its own pose, every hero clip retargeted); his violet-glowing greatsword in the right hand
	"hero_ezee": {"scene": H17 + "ezee.glb", "scale": 1.0, "attack": ["gs_1", "gs_2", "gs_3", "gs_4"],
		"cast": "cast_quick", "idle": "idle_2h", "run": "hero_run", "run_min": 0.72,
		"death": "death", "R": "greatsword", "L": "", "bar": 2.45, "weapon_tint": Color(0.5, 0.44, 0.62),
		"weapon_glow": Color(0.55, 0.2, 1.0), "swing_trail": true},
	# Sludge: his own body (tools/blender/sludge.py) on the hero skeleton; cleaver right, shuriken hook left
	"hero_sludge": {"scene": "res://assets/characters/hero/sludge.glb", "scale": 1.22, "attack": ["axe_1", "axe_2", "axe_3"],
		"cast": "cast_quick", "idle": "idle_1h", "run": "hero_run", "run_female": "hero_run", "run_min": 0.72,
		"death": "death", "R": "cleaver", "L": "shuriken_hook", "bar": 2.95, "skin_shader": "res://src/game/sludge_skin.gdshader",
		"gear_materials": true, "swing_trail": true},
	# Azrin (2026-10-17): her own body, the owner's hooded sorceress recoloured red and black, with her staff (cut out
	# of the model as a weapon) in the right hand; she hovers over her fire (float, in metres) and glides instead of
	# running: glide_fwd is her staff idle with the chest leaning in and the legs trailing (UnitView leans and banks
	# her further as she moves)
	"hero_azrin": {"scene": H17 + "azrin.glb", "scale": 1.0, "attack": ["staff_1", "staff_2"],
		"cast": "cast_quick", "idle": "idle_staff", "run": "glide_fwd", "glide": true, "glide_clip": "glide_fwd",
		"float": 0.75, "bob": 0.08, "death": "death", "R": "azrin_staff", "L": "", "proj": "fireball", "bar": 2.85},
	# Azrael (2026-10-17 f): her own body, the owner's azrael.glb in a black dress and dark steel armour, silver-white
	# hair (tools/blender/azrael_prep.py, then hero_body.py), floating and gliding like Azrin, the great scythe in both
	# hands (tools/blender/azrael.py); her charged slash, soul flame and wings are AzraelFx. The blade points to the
	# weapon's +X, the way the head moves in gs_1 / gs_3 / gs_4 (tests/tools/swing_dir.gd), so its tip leads every
	# swing; gs_2 is a backhand (the head moves -X) and is left out
	"hero_azrael": {"scene": H17 + "azrael.glb", "scale": 1.0, "attack": ["gs_1", "gs_3", "gs_4"],
		"cast": "cast_quick", "idle": "idle_staff", "run": "glide_fwd", "glide": true, "glide_clip": "glide_fwd",
		"float": 0.42, "bob": 0.06, "death": "death", "R": "scythe", "L": "", "bar": 2.7},
	# Froster: the hero body with a frost staff; his bolts are ice
	"hero_froster": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.0, "attack": ["staff_1", "staff_2"],
		"cast": "cast_quick", "idle": "idle_staff", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72,
		"death": "death", "R": "staff_aether", "L": "", "proj": "frost_bolt", "bar": 2.45, "hero": true,
		"weapon_tint": Color(0.62, 0.82, 1.0)},
	# Caziel (2026-10-17): his own body, the owner's hooded assassin in a long coat, two daggers
	"hero_caziel": {"scene": H17 + "caziel.glb", "scale": 1.0, "attack": ["dual_1", "dual_2", "dual_3", "dual_4"],
		"cast": "cast_quick", "idle": "idle_shadowblade", "run": "hero_run", "run_min": 0.72,
		"death": "death", "R": "dagger", "L": "dagger", "bar": 2.35, "weapon_tint": Color(0.55, 0.45, 0.7),
		"swing_trail": true, "trail_color": Color(0.7, 0.4, 1.0, 0.6)},
	# Ser Emelrich and Feran Mock (2026-10-17, bodies only until their kits land): the white knight with his heavy
	# greatsword; the jester (assassin body, restyle pending) with throwing knives
	"hero_emelrich": {"scene": H17 + "emelrich.glb", "scale": 1.0, "attack": ["gs_1", "gs_3", "gs_4"],
		"cast": "cast_weapon", "idle": "idle_2h", "run": "hero_run", "run_min": 0.72, "death": "death",
		"R": "heavy_greatsword", "L": "", "bar": 2.6, "swing_trail": true, "trail_color": Color(1.0, 0.9, 0.6, 0.6)},
	# Burak, Airah and Ghorman's Beast Form (2026-10-17, bodies only until their kits land): the berserker with two
	# bearded axes; the dancer in flowing scarves (a hand-placed rig on a posed model); the troll with its mace, its
	# hunch kept under the hero clips
	"hero_burak": {"scene": H17 + "burak.glb", "scale": 1.0, "attack": ["dual_1", "dual_2", "dual_3", "dual_4"],
		"cast": "war_cry", "idle": "idle_dual", "run": "hero_run", "run_min": 0.72, "death": "death",
		"R": "burak_axe", "L": "burak_axe_long", "bar": 2.45, "swing_trail": true, "trail_color": Color(1.0, 0.3, 0.2, 0.6)},
	"hero_airah": {"scene": H17 + "airah.glb", "scale": 1.0, "attack": ["cast_quick"], "cast": "cast_area",
		"idle": "idle_mage", "run": "fem_run", "run_min": 0.72, "death": "death", "R": "", "L": "", "proj": "sun_orb",
		"bar": 2.35},
	# Ghorman (2026-10-17 f, body only until his kit lands): the owner's bodybuilder dressed as the Beast King
	# (tools/blender/ghorman_prep.py: the antlered deer skull over a hood, a golden mane, beard, belt, kilt, bracers,
	# boots), his knotted club with bone teeth in the right hand; Beast Form is his form
	"hero_ghorman": {"scene": H17 + "ghorman.glb", "scale": 1.0, "attack": ["axe_1", "axe_2", "axe_3"],
		"cast": "war_cry", "idle": "idle_1h", "run": "hero_run", "run_min": 0.72, "death": "death",
		"R": "ghorman_club", "L": "", "bar": 2.7, "swing_trail": true, "trail_color": Color(0.9, 0.75, 0.45, 0.5),
		"forms": {"beast_form": "hero_ghorman_beast"}},
	"hero_ghorman_beast": {"scene": H17 + "ghorman_beast.glb", "scale": 1.0, "attack": ["boss_slam", "hero_axe_smash"],
		"cast": "boss_roar", "idle": "idle", "run": "run_combat", "run_min": 0.6, "death": "death", "R": "", "L": "",
		"bar": 3.1},
	"hero_feran": {"scene": H17 + "feran.glb", "scale": 1.0, "attack": ["dagger_1", "dagger_2"],
		"cast": "cast_quick", "idle": "idle_dagger", "run": "hero_run", "run_min": 0.72, "death": "death",
		"R": "throwing_knife", "L": "", "proj": "knife", "bar": 2.4},
	# Tock: the hero body with a brass wand; his bolts are golden orbs
	"hero_tock": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.0, "attack": ["wand_1", "wand_2", "wand_3"],
		"cast": "cast_quick", "idle": "idle_wand", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72,
		"death": "death", "R": "wand", "L": "", "proj": "sun_orb", "bar": 2.3, "hero": true,
		"weapon_tint": Color(1.0, 0.8, 0.45), "weapon_glow": Color(1.0, 0.75, 0.3)},
	# Kragg: the hero body in heavy plate with a sword and a magnet shield crackling blue
	"hero_kragg": {"scene": "res://assets/characters/hero/hero.glb", "scale": 1.05, "attack": ["sword_1", "sword_2", "sword_3", "sword_4"],
		"cast": "shield_bash", "idle": "idle_shield", "run": "hero_run", "run_female": "fem_run", "run_min": 0.72,
		"death": "death", "R": "sword", "L": "shield", "bar": 2.55, "hero": true, "weapon_tint": Color(0.55, 0.62, 0.78),
		"weapon_glow": Color(0.35, 0.6, 1.0), "swing_trail": true, "trail_color": Color(0.45, 0.7, 1.0, 0.6),
		# the shield strapped along the forearm (it sat centred on the fist and covered his face and thighs):
		# 80% size, 15 cm toward the elbow, 8 cm lower, 6 cm off the arm (run 2026-10-15 g)
		"L_xform": [0.8, Vector3(0.15, -0.08, 0.06)]},
	# Roydo (run 2026-10-16): his own body (tools/blender/heroes16.py) with the night-sky skin; Anomaly is his form
	"hero_roydo": {"scene": H16 + "roydo.glb", "scale": 1.0, "attack": ["roydo_punch_jab", "roydo_punch_cross"],
		"cast": "roydo_cast_shoot", "idle": "roydo_idle", "run": "roydo_run", "run_min": 0.6, "death": "death", "R": "",
		"L": "", "bar": 2.45, "skin_shader": "res://src/game/roydo_skin.gdshader", "skin_material": "RoydoSkin",
		"skin_params": {"mode": 0.0}, "forms": {"anomaly": "hero_anomaly"}},
	"hero_anomaly": {"scene": H16 + "anomaly.glb", "scale": 1.2, "attack": ["anomaly_blast", "anomaly_cast_shoot"],
		"cast": "anomaly_cast_shoot", "idle": "anomaly_idle", "run": "anomaly_run", "run_min": 0.55, "death": "death",
		"R": "", "L": "", "proj": "gravity_orb", "bar": 2.95, "skin_shader": "res://src/game/roydo_skin.gdshader",
		"skin_material": "AnomalySkin", "skin_params": {"mode": 1.0, "glow": 0.8}},
	# Blau: his own body in the recoloured ranger coat with the rifle in both hands; tracer bullets
	"hero_blau": {"scene": H16 + "blau.glb", "scale": 1.0, "attack": ["blau_shoot"], "attack_aim": "blau_aim",
		"cast": "blau_cast_shoot", "idle": "blau_idle", "run": "blau_run_rifle", "run_min": 0.6, "death": "death", "R": "",
		"L": "", "proj": "bullet", "bar": 2.4},
	# his turret: the walker in his navy and steel (the pack's white shell blows out in daylight)
	"blau_turret": {"scene": H16 + "blau_turret.glb", "scale": 0.8, "attack": ["turret_attack"], "idle": "turret_idle",
		"run": "turret_idle", "death": "death", "R": "", "L": "", "proj": "turret_shot", "bar": 2.1,
		"tint": Color(0.42, 0.52, 0.78)},
	"dawn_melee": {"scene": UNITS + "knight.glb", "scale": 0.86, "attack": ["sword_1", "sword_2", "sword_3"], "idle": "idle_shield",
		"run": "run", "death": "death", "R": "sword", "L": "shield", "bar": 2.0, "tint": Color(1.0, 0.97, 0.88),
		"L_xform": [0.8, Vector3(0.15, -0.08, 0.06)]},
	"dawn_ranged": {"scene": UNITS + "mage.glb", "scale": 0.86, "attack": ["staff_1", "staff_2"], "idle": "idle_staff",
		"run": "run", "death": "death", "R": "staff_aether", "L": "", "proj": "sun_orb", "bar": 2.0},
	"dawn_flag": {"scene": UNITS + "knight.glb", "scale": 0.92, "attack": ["sword_1", "sword_2"], "idle": "idle_shield",
		"run": "run", "death": "death", "R": "sword_aether", "L": "shield", "bar": 2.1, "banner": Color(1.0, 0.82, 0.3),
		"L_xform": [0.8, Vector3(0.15, -0.08, 0.06)]},
	"dawn_siege": {"scene": UNITS + "rune_golem.glb", "scale": 1.15, "attack": ["boss_slam"], "idle": "idle", "run": "walk",
		"death": "death", "R": "", "L": "", "proj": "boulder_sun", "bar": 2.9},
	"dusk_melee": {"scene": UNITS + "ghoul_brute.glb", "scale": 0.86, "attack": ["axe_2"], "idle": "idle", "run": "run",
		"death": "death", "R": "axe", "L": "", "bar": 2.0},
	"dusk_ranged": {"scene": UNITS + "necromancer.glb", "scale": 0.86, "attack": ["staff_1", "cast_quick"], "idle": "idle_staff",
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
	"mudling_foreman": {"scene": UNITS + "goblin_summoner.glb", "scale": 0.95, "attack": ["staff_1", "cast_quick"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "bar": 1.9},
	"ashfang": {"scene": UNITS + "dire_wolf.glb", "scale": 0.8, "attack": ["wolf_bite"], "idle": "idle", "run": "run",
		"death": "death", "R": "", "L": "", "bar": 1.5},
	"ashfang_alpha": {"scene": UNITS + "dire_wolf.glb", "scale": 1.05, "attack": ["wolf_bite", "wolf_pounce"], "idle": "idle",
		"run": "run", "death": "death", "R": "", "L": "", "bar": 1.8, "tint": Color(0.75, 0.68, 0.62)},
	"strider": {"scene": UNITS + "orc_reaver.glb", "scale": 0.92, "attack": ["axe_1", "axe_3"], "idle": "idle", "run": "run",
		"death": "death", "R": "axe", "L": "", "bar": 2.1},
	"strider_warlord": {"scene": UNITS + "orc_shaman.glb", "scale": 1.15, "attack": ["staff_1", "cast_quick"], "idle": "idle",
		"run": "run", "death": "death", "R": "staff", "L": "", "bar": 2.5},
	"hill_troll": {"scene": UNITS + "mire_troll.glb", "scale": 0.95, "attack": ["axe_1", "axe_2"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "proj": "spear", "bar": 2.2},
	"ogre_brute": {"scene": UNITS + "ogre_crusher.glb", "scale": 1.0, "attack": ["boss_slam", "gs_1"], "idle": "idle",
		"run": "run", "death": "death", "R": "", "L": "", "bar": 2.6},
	"cinder_wyrmling": {"scene": UNITS + "cinder_imp.glb", "scale": 1.0, "attack": ["wand_1", "cast_quick"], "idle": "idle",
		"run": "run", "death": "death", "R": "wand", "L": "", "proj": "fire", "bar": 2.0},
	"elder_cinder_wyrm": {"scene": UNITS + "magma_golem.glb", "scale": 1.35, "attack": ["cast_heavy", "boss_slam"],
		"idle": "idle", "run": "run", "death": "death", "R": "", "L": "", "proj": "fire_big", "bar": 3.2},
}

## The motion-capture clips each hero plays (run 2026-10-18 d; MocapClips, tools/blender/mocap_clips.json), laid over
## its MODELS entry when the library is present: idle, attack, cast and deaths are replaced, and "anims" turns the old
## clip names the game asks for (ability clips, hit reactions, stun, the stage's idle and flourish) into mocap ones.
## Run 2026-10-18 e added the runs (one per weapon: great sword, sword and shield, axe, bow, spell), Leap Strike's leap,
## Caziel's dash-stab (his double stab) and the push clips (MOCAP_ALL). The spinning third great sword slash is left out:
## its body turns half round while it fades in, and no crossfade from a stance gets there without a flip. Azrin and Azrael keep their staff idle and glide; Azrael swings only
## the slashes whose blade head moves the way her scythe's blade faces (swing_dir.gd).
const MOCAP := {
	"hero": {"run": "bow_run", "run_female": "bow_run", "idle": "bow_idle", "attack": ["bow_shoot"], "death": "bow_death_1", "deaths": ["bow_death_1", "bow_death_2"],
		"anims": {"idle_bow": "bow_idle", "bow_1": "bow_shoot", "bow_draw_hold": "bow_hold", "bow_release": "bow_loose",
			"dodge_step": "bow_dodge", "hit_heavy": "hit_big", "hit_light": "bow_hit", "hit_front": "bow_hit",
			"idle_hurt": "dizzy"}},
	"hero_ezee": {"run": "greatsword_run", "run_female": "greatsword_run", "idle": "greatsword_idle", "cast": "greatsword_cast", "death": "greatsword_death_1",
		"attack": ["greatsword_slash_1", "greatsword_slash_2", "greatsword_slash_4"],
		"deaths": ["greatsword_death_1", "greatsword_death_2"],
		"anims": {"idle_2h": "greatsword_idle", "cast_quick": "greatsword_cast", "cast_weapon": "greatsword_cast",
			"boss_slam": "greatsword_slam", "leap_slam": "greatsword_leap", "boss_roar": "greatsword_power", "hit_heavy": "greatsword_hit",
			"hit_light": "greatsword_hit_small", "hit_front": "greatsword_hit_small", "idle_hurt": "dizzy"}},
	"hero_sludge": {"run": "axe_run", "run_female": "axe_run", "idle": "axe_idle", "attack": ["axe_chop", "axe_sweep", "axe_backhand"], "cast": "hook_throw",
		"death": "death_from_front", "deaths": ["death_from_front", "death_fall_back"],
		"anims": {"idle_1h": "axe_idle", "cast_quick": "hook_throw", "cast_channel": "neck_bite", "devour": "neck_bite",
			"hero_axe_smash": "axe_chest_thump", "hit_heavy": "axe_hit", "hit_light": "hit_small", "hit_front": "hit_small",
			"idle_hurt": "dizzy"}},
	"hero_azrin": {"attack": ["spell_strike_1", "spell_strike_2"], "cast": "spell_quick", "death": "spell_death_1",
		"deaths": ["spell_death_1", "spell_death_2"],
		"anims": {"cast_heavy": "javelin_throw", "cast_area": "spell_area", "cast_quick": "spell_quick",
			"cast_ultimate": "spell_big", "hit_heavy": "hit_big", "hit_light": "hit_small", "hit_front": "hit_small",
			"idle_hurt": "dizzy"}},
	"hero_froster": {"run": "spell_run", "run_female": "spell_run", "idle": "spell_idle", "attack": ["spell_strike_1", "spell_strike_2"], "cast": "spell_quick",
		"death": "spell_death_1", "deaths": ["spell_death_1", "spell_death_2"],
		"anims": {"idle_staff": "spell_idle", "cast_heavy": "spell_heavy", "cast_quick": "spell_quick",
			"cast_channel": "spell_channel", "cast_area": "spell_area", "hit_heavy": "hit_big", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_caziel": {"run": "spell_run", "run_female": "spell_run", "idle": "knife_idle", "attack": ["dagger_stab_1", "dagger_stab_2", "dagger_stab_3"],
		"death": "death_from_front", "deaths": ["death_from_front", "death_from_back"],
		"anims": {"idle_shadowblade": "knife_idle", "blink": "dagger_stab_1", "hit_heavy": "hit_big", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_tock": {"run": "spell_run", "run_female": "spell_run", "idle": "spell_idle_2", "attack": ["spell_strike_1", "spell_strike_2", "spell_strike_3"],
		"cast": "spell_quick", "death": "spell_death_1", "deaths": ["spell_death_1", "spell_death_2"],
		"anims": {"idle_wand": "spell_idle_2", "cast_quick": "spell_quick", "cast_area": "spell_area",
			"cast_ultimate": "spell_big", "wand_heavy": "spell_wave", "hit_heavy": "hit_big", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_kragg": {"run": "shield_run", "run_female": "shield_run", "idle": "shield_idle", "attack": ["shield_slash_1", "shield_slash_2", "shield_slash_3"],
		"cast": "shield_push", "death": "shield_death_1", "deaths": ["shield_death_1", "shield_death_2"],
		"anims": {"idle_shield": "shield_idle", "shield_bash": "shield_push", "war_cry": "shield_power",
			"boss_roar": "shield_slam", "hit_heavy": "shield_hit", "hit_light": "shield_hit", "hit_front": "shield_hit",
			"idle_hurt": "dizzy"}},
	# the five heroes of hero_ideas.txt (run 2026-10-18 e): Emelrich swings the great sword set, Burak swings both axes
	# (the two-weapon slashes; the axe set's one-handed swings left his second axe flopping) and keeps the axe idle,
	# Ghorman the axe set (he thumps his chest on the stage), Feran throws his knives overhand, Airah the spell set
	"hero_emelrich": {"run": "greatsword_run", "run_female": "greatsword_run", "idle": "greatsword_idle", "cast": "greatsword_cast", "death": "greatsword_death_1",
		"attack": ["greatsword_slash_1", "greatsword_slash_2", "greatsword_slash_4"],
		"deaths": ["greatsword_death_1", "greatsword_death_2"],
		"anims": {"idle_2h": "greatsword_idle", "cast_weapon": "greatsword_cast", "cast_quick": "greatsword_cast",
			"boss_roar": "greatsword_power", "hit_heavy": "greatsword_hit", "hit_light": "greatsword_hit_small",
			"hit_front": "greatsword_hit_small", "idle_hurt": "dizzy"}},
	"hero_burak": {"run": "axe_run", "run_female": "axe_run", "idle": "axe_idle", "attack": ["dual_slash_1", "dual_slash_2"], "cast": "axe_battle_cry",
		"death": "death_from_front", "deaths": ["death_from_front", "death_from_back"],
		"anims": {"idle_dual": "axe_idle", "war_cry": "axe_battle_cry", "hit_heavy": "axe_hit", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_ghorman": {"run": "axe_run", "run_female": "axe_run", "idle": "axe_idle", "attack": ["axe_chop", "axe_sweep", "axe_backhand"], "cast": "axe_battle_cry",
		"death": "death_from_front", "deaths": ["death_from_front", "death_fall_back"],
		"anims": {"idle_1h": "axe_idle", "war_cry": "axe_chest_thump", "hit_heavy": "axe_hit", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_feran": {"run": "spell_run", "run_female": "spell_run", "idle": "knife_idle", "attack": ["javelin_throw"], "cast": "spell_quick", "death": "death_from_front",
		"deaths": ["death_from_front", "death_from_back"],
		"anims": {"idle_dagger": "knife_idle", "cast_quick": "spell_quick", "hit_heavy": "hit_big", "hit_light": "hit_small",
			"hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_airah": {"run": "spell_run", "run_female": "spell_run", "idle": "spell_idle_2", "attack": ["spell_strike_1", "spell_strike_2", "spell_strike_3"],
		"cast": "spell_area", "death": "spell_death_1", "deaths": ["spell_death_1", "spell_death_2"],
		"anims": {"idle_mage": "spell_idle_2", "cast_area": "spell_area", "cast_quick": "spell_quick",
			"hit_heavy": "hit_big", "hit_light": "hit_small", "hit_front": "hit_small", "idle_hurt": "dizzy"}},
	"hero_azrael": {"attack": ["greatsword_slash_1", "greatsword_slash_2"], "cast": "greatsword_cast",
		"death": "spell_death_1", "deaths": ["spell_death_1", "spell_death_2"],
		"anims": {"cast_quick": "greatsword_cast", "cast_heavy": "spell_heavy", "cast_ultimate": "spell_big",
			"gs_heavy": "greatsword_power",
			"hit_heavy": "hit_big", "hit_light": "hit_small", "hit_front": "hit_small", "idle_hurt": "dizzy"}},
}

## The clips every motion-capture hero plays for being pushed (run 2026-10-18 e): a stagger back that stays on its
## feet (a push in Dota does not knock a hero down), its recovery, the stagger's peak held while thrown through the air,
## and a big hit from behind for slamming into a wall. A model's own "anims" win.
const MOCAP_ALL := {"knockback": "stagger_back", "getup": "stagger_recover", "launch": "stagger_air",
	"wall_impact": "hit_from_back"}

static var _meta := {}
static var _scenes := {}
static var _merged := {}

## A model's entry, with its MOCAP part laid over it when the motion-capture library is present (MocapClips).
static func info(model_key: String) -> Dictionary:
	var cfg: Dictionary = MODELS.get(model_key, {})
	if not MOCAP.has(model_key) or not MocapClips.available():
		return cfg
	if not _merged.has(model_key):
		var m := cfg.duplicate()
		var mc: Dictionary = MOCAP[model_key]
		for k in mc:
			m[k] = mc[k]
		var an: Dictionary = MOCAP_ALL.duplicate()
		an.merge(mc.get("anims", {}), true)
		m["anims"] = an
		_merged[model_key] = m
	return _merged[model_key]

## The clip a model plays for `clip` (its mocap stand-in, when it has one; see MOCAP).
static func anim(cfg: Dictionary, clip: String) -> String:
	return String(cfg.get("anims", {}).get(clip, clip))

static func scene(model_key: String) -> PackedScene:
	var path: String = MODELS[model_key].scene
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## Timing data for a clip: {length, hits, release, ground_speed, ...} (empty if unknown).
static func clip(name: String) -> Dictionary:
	if _meta.is_empty():
		for f in [UNITS + "anim_meta.json", UNITS + "creature_meta.json", "res://assets/characters/hero/hero_meta.json",
				H16 + "heroes16_meta.json", MocapClips.META]:
			if not FileAccess.file_exists(f):
				continue
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

## Where a prop sits on its weapon bone for this model: the catalog's "<side>_xform" [scale, offset] (offsets are
## written for the left hand; the right mirrors x), else where the bone is.
static func prop_transform(cfg: Dictionary, side: String) -> Transform3D:
	var x = cfg.get(side + "_xform", null)
	if x == null:
		return Transform3D()
	var off: Vector3 = x[1]
	if side == "R":
		off.x = -off.x
	return Transform3D(Basis().scaled(Vector3.ONE * float(x[0])), off)

static func weapon(name: String) -> PackedScene:
	if name == "":
		return null
	var path := WEAPONS + name + ".glb"
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]
