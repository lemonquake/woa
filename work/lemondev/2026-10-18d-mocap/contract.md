# Run 2026-10-18 d: Mixamo motion capture for the heroes, hand remnants, build

Owner's request: "go and use everything and anything as you can. You can download free animations from Maximo or any
other sites and apply them to our heroes, but please make sure they look great and they don't look like their limbs
and body parts go through anything and clip through anything. There are also remnants in most of our hero models like
remnants of hands when animating. then build the game"

Baseline: commit `b0492ea` (tests 249/249, Names OK). Before evidence: `work/lemondev/2026-10-18b-hands/before/`
(contact sheets of every hero, rendered by an earlier session that was deleted), `remnants_before/`.

## Components

| Id | Component | Owner files | Gate |
|---|---|---|---|
| M1 | Mixamo download | `work/downloads/mixamo/raw/` (git-ignored: Mixamo's terms forbid loose redistribution) | 181 FBX, names checked by content hash against the pane's named saves |
| M2 | Retarget tool | `tools/blender/mocap_retarget.py`, `tools/mocap_sheet.py`, `tools/blender/mocap_clips.json` | survey sheets of every clip; clips keep both hands on two-handed grips |
| M3 | Game integration | `src/game/mocap_clips.gd`, `repaired_clips.gd`, `model_catalog.gd` (MOCAP), `unit_view.gd`, `hero_stage.gd`, `tests/tools/mocap_import.gd` | test_mocap_clips; the game falls back to the old clips without the library |
| M4 | Hand remnants | `tools/blender/arm_split.py`, `tools/blender/hero_body.py` (`--split`, `--sleeve`), `tools/blender/remnant_check.py`, `work/rebuild_qa.sh` | remnant_check on Ezee, Caziel, Azrin: fewer vertices left at the hips and torn faces than before; renders by eye |
| M5 | Body collision for the new clips | `tests/tools/body_collide.gd` | `--applied` worst depth per body, compared with the 2026-10-18 b numbers |
| X1 | Integration and build | all | tests, check.sh, a live match per changed hero, Hero Select capture, release export, cold start |

## Benchmark and conditions

No commercial reference footage on disk; the comparison is before/after on our own models (same camera, same
contact-sheet tool `tests/tools/anim_sheet.gd`), plus the measured gates above. Independent blind critic: not run
unless the owner asks (as in earlier runs). Budget: at most 8 passes per component.
