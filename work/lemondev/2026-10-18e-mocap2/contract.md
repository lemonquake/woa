# Run 2026-10-18 e: motion capture for the remaining clips and the five new heroes' bodies, strict animation QA, build

Owner's request: "continue. Mocap for the remaining clips and five new heroes. then build the game. make sure you
STRICTLY QA all animations, if they connect properly, if they look right, no remnants, no weird twists, no clipping"
Clarified: "dont add NEW heroes, I meant FOR THE NEW HEROES" - the five bodies already in the catalog (Ser Emelrich,
Feran Mock, Burak, Airah, Ghorman and his Beast Form) get motion capture; no kits, no new heroes.

Baseline: commit `e23c7a5` (tests 250/250, Names OK, mocap on nine heroes). Remaining old clips from run 18d: runs,
glides, Leap Strike's leap, Caziel's dash (blink), knockbacks (knockback, launch, getup, wall_impact, drag).

## Components

| Id | Component | Owner files | Gate |
|---|---|---|---|
| B1 | Five bodies rebuilt with the current pipeline (hand fit, unmix, arm split) | `assets/characters/heroes17/{emelrich,feran,burak,airah,ghorman,ghorman_beast}.glb` | remnant_check before/after (left and torn counts), close-up renders by eye |
| C1 | Mocap for the remaining clips (runs, leap, dash, knockbacks, glides) | `tools/blender/mocap_clips.json`, `tools/blender/mocap_retarget.py`, `src/game/model_catalog.gd` (MOCAP), `src/game/unit_view.gd` | clips mapped for every hero; run ground speed measured from the capture (no foot sliding); leap timing meta |
| C2 | Mocap for the five bodies | `model_catalog.gd` (MOCAP), `src/game/mocap_clips.gd` (posture for the beast) | every clip each body plays resolves to a mocap clip |
| Q1 | Joins and loops (new gate) | `tests/tools/anim_joins.gd` | loop seams (last frame to first) and every crossfade the game makes (idle/run/attack/cast/hit/stun/knock in and out) under limits; worst bone angle per frame of blend |
| Q2 | Twists and pops | `tests/tools/anim_audit.gd` (now with model keys) | anim_audit findings on every mocap clip of every body |
| Q3 | Clipping | `tests/tools/body_collide.gd` (now with the catalog-only bodies) | `--applied` worst depth per body, every clip in use |
| X1 | Integration and build | all | tests, check.sh, contact sheets, live captures, release export, cold start |

## Benchmark and conditions

Before/after on our own models with the same tools (anim_sheet contact sheets, remnant_check renders). No commercial
reference footage on disk; no blind critic (none asked for, as in earlier runs). Budget: at most 8 passes per component.
