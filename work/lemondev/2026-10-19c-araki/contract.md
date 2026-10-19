# Run 2026-10-19 c: contract (Araki, the Blur; Blau's turrets; Airah and Tock facing)

Owner's requests this session (their words win):
1. "Implement this hero idea of mine" (Araki, the Blur: Neutral, agility, melee samurai; gains agi 2.8, int 2.1, str
   1.7; innate Senryukai; Blur Strike, Djin Bomb, Ghosts of the Will, The Blur, with their numbers). "Make sure you
   update the AI to know how to use this new hero very very effectively and smartly. After that, build the game."
2. Mid-run: "I change my mind. Go and use a rigged model that you can get anywhere. do it" (instead of the owner's
   unrigged Cyber Samurai download). The owner signed in to Sketchfab in the app's browser for the download.
3. Mid-run: "Airah is not facing forward in her picture profile, and in the versus screen Airah and Tock are facing the
   wrong way".
4. Mid-run: Blau bots never seem to use their ultimate (Place Turret); it is spammable and should be spammed.

Engine and target: Godot 4.7.2 Forward+, Windows, 1920x1080 and 3840x2160; RTX 4060.

## Components, owners (one builder: this session), acceptance

| Id | Component | Files | Acceptance (gate) |
|---|---|---|---|
| M1 | Body and katana | `tools/blender/araki_prep.py`, `araki_katana.py`, `hero_body.py` (CC neck name), `assets/characters/heroes17/araki.glb`, `assets/weapons/araki_katana.glb` | builds; plays the hero clips without tearing (close-ups front and back); < 100 MB (GitHub limit); credited CC BY |
| K1 | Kit (sim) | `src/sim/sim_data.gd`, `src/sim/sim_kits7.gd`, hooks in `sim_abilities.gd`, `sim_combat.gd`, `sim_world.gd` | the owner's numbers at every level; tests `test_araki_*` pass |
| B1 | Araki's bot | `src/sim/sim_bot19.gd`, `sim_bot.gd` hooks, `sim_bot_kits.gd`, `sim_bot_items.gd` | casts all four skills in real bot games; no feeding pattern (deaths traced, `tests/tools/araki_probe.gd`); KDA and farm in line with Caziel (the nearest kit) in the same games |
| V1 | Look, effects, sound, UI | `src/game/araki_fx.gd`, `ghost.gdshader`, `unit_view.gd` (ghosts), `model_catalog.gd`, `audio.gd`, `fire_fx.gd` ("shadowflame"), icons (`tools/item_icons.py`), `hero_select.gd`, `hero_stage.gd`, `buff_bar.gd`, `ui_kit.gd`, portrait | captures in a live match show each skill; icons rendered by Godot's own loader; names pass `tools/check_names.py` |
| F1 | Airah and Tock facing | `model_catalog.gd` (idle clip), `hero_stage.gd` (portrait aims at the face) | versus capture with both; portraits face the camera |
| F2 | Blau spams turrets | `src/sim/sim_bot16.gd` | turrets per 25-minute bot game well above the 13-16 measured before |
| X1 | Integration and build | all | `tests/run_tests.gd` all pass; `sh tools/check.sh` clean and "Names OK"; export exit 0 and the exe cold-starts into a match as Araki |

Benchmark: Dota 2's own heroes for the mechanics (Fury Swipes for Senryukai, Void Spirit's Astral Step and Ember
Spirit's Sleight of Fist for Blur Strike's instant attacks, Ursa's Overpower for The Blur's attack count). No Dota 2
client is available here, so no visual benchmark comparison; that gate stays UNVERIFIED. No blind critic was asked for.
Budget: 8 passes a component (lemondev default).
