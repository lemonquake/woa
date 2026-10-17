# Handoff for the next agent: hero models run (2026-10-17 e)

Read first: `CLAUDE.md`, `docs/HANDOFF.md` (top section "2026-10-17 e"), `work/lemondev/2026-10-17e-hero-models/contract.md`,
this file. Last commits: `fe25e2c` (Burak, Airah, Beast Form) and the one after it (old exporter removed). Working tree
is clean except the owner's own untracked files (`Update.txt`, `audio/`, `hero_ideas.txt`, `tests/tools/_stuck.gd`):
never commit those.

## What the owner asked (keep these in mind)
* Five new heroes from `hero_ideas.txt` (Airah, Burak, Ser Emelrich, Feran Mock, Ghorman): "PERFECT and EPIC" models,
  researched non-common free models, own textures, effects, animations. CC BY 4.0 approved (credit every artist in
  `docs/ASSET_CREDITS.md`, then `python tools/build_credits.py` for the in-game Credits screen).
* Owner downloads models into `work/downloads/sf_heroes/` (Sketchfab needs their login; never sign in yourself).
* Owner's assignments (their words win): Emelrich = `bulky_knight.glb`; Ezee = fallen paladin zip; Azrin = `azrin.zip`
  recoloured **red + black**, float animation must lean forward when gliding; Caziel = `caziel.zip`; Burak =
  `burak.glb` + `burak_axe1/2.glb`; Airah = `airah.glb`; Ghorman = `northern_outsider.glb` (+ `druid_clothes.glb`
  parts) and Beast Form = `ghorman_transform.glb` (the troll). `blackfire_the_unfallen.zip` = future hero, DO NOT
  TOUCH. `thyrandael_the_forsaken_seraph.zip` = not assigned, leave it.
* The five kits (abilities, bots, talents) were proposed as a separate session (card "Build the five new hero kits");
  it may or may not have been started. Check `git log` / `src/sim/sim_data.gd` for `airah|burak|emelrich|feran|ghorman`
  before touching sim code. This run only did MODELS.

## State
| Hero | Body file | In game? | Notes |
|---|---|---|---|
| Ezee | `assets/characters/heroes17/ezee.glb` | YES (`hero_ezee`) | baked AI mesh, sword cut away; tiny gold speck left in left fist |
| Azrin | `heroes17/azrin.glb` + `assets/weapons/azrin_staff.glb` | YES (`hero_azrin`) | red/black; staff on weapon.R; `glide_fwd` clip; UnitView leans 7-13 deg with speed and banks in turns |
| Caziel | `heroes17/caziel.glb` | YES (`hero_caziel`) | greys lifted (`--gray=1.45`); could use violet accents |
| Emelrich | `heroes17/emelrich.glb` + `assets/weapons/heavy_greatsword.glb` | catalog only (`hero_emelrich`) | whiter steel, cream cloth; TODO Ancient Light sun on tabard |
| Feran | `heroes17/feran.glb` + `throwing_knife.glb`, `assets/props/joke_box.glb` | catalog only (`hero_feran`) | TODO jester restyle: red/black patched coat, three-point bell hat, half-smile mask (hood still on the shawl piece) |
| Burak | `heroes17/burak.glb` + `burak_axe.glb` (R), `burak_axe_long.glb` (L) | catalog only (`hero_burak`) | TODO fur mantle, red war paint, glowing eyes/steam FX (kit) |
| Airah | `heroes17/airah.glb` | catalog only (`hero_airah`) | posed dancer; scarves stretch in run (reads as wind); tail locked to hips |
| Ghorman Beast Form | `heroes17/ghorman_beast.glb` | catalog only (`hero_ghorman_beast`) | troll + mace, `--posture` keeps the hunch; uses boss_* hero clips |
| Ghorman human | none | NO | `northern_outsider.glb` is corrupt (legs/feet/pelvis/axe pieces tens of metres off even on its own clips). Owner was asked to re-download in "Original format" (pending answer). Druid skull/antlers (`druid_clothes.glb`, Head piece) to be added as bone armour |

Every body has its repaired arm clips in `assets/characters/heroes17/anim_fixed/<name>.res`
(`godot --headless --path . -s tests/tools/anim_repair.gd -- --model=res://assets/characters/heroes17/<name>.glb`);
rerun after ANY rebuild of a body. Godot console: `A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe`.
Import after rebuilding: `godot --headless --path . --import`.

## Exact build commands (Blender: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/hero_body.py -- ...)
* Ezee: `--src=<fallen paladin fbx in .../source/x/> --name=ezee --yaw=-90 --height=1.9 --faces=40000 --tex=2048 --bake --cut="0.175,0.27,-0.24,-0.135,-0.50,-0.30;0.15,0.24,-0.26,-0.10,-0.30,-0.05;0.13,0.185,-0.26,-0.12,-0.075,0.135;0.10,0.20,-0.26,-0.12,-0.08,-0.02" --joints=tools/blender/joints/fallen_paladin.json --out=assets/characters/heroes17/ezee.glb`
* Azrin: `--src=<azrin fbx> --name=azrin --height=1.78 --faces=52000 --tex=2048 --bake --hue=275:356:80:1.6:1.1 --glide=idle_staff --cut="cap:-0.19,-0.27,1.0,-0.015,-0.075,-0.01,0.024;ball:-0.185,-0.245,0.885,0.115" --joints=tools/blender/joints/azrin.json --out=assets/characters/heroes17/azrin.glb`
  Staff: `tools/blender/extract_prop.py -- --src=<azrin fbx> --out=assets/weapons/azrin_staff.glb --shapes="cap:-0.19,-0.27,1.0,-0.015,-0.075,-0.01,0.016;ball:-0.185,-0.245,0.885,0.115" --grip=-0.134,-0.204,0.64 --tip=-0.185,-0.26,0.93 --height=1.78 --faces=5000 --tex=1024 --hue=275:356:80:1.6:1.1`
* Caziel: `--src=<caziel fbx> --name=caziel --height=1.85 --faces=40000 --tex=2048 --bake --gray=1.45 --joints=tools/blender/joints/caziel.json --out=assets/characters/heroes17/caziel.glb`
* Emelrich: `--src=work/downloads/sf_heroes/bulky_knight.glb --name=emelrich --height=1.95 --faces=34000 --drop="Axe|pasted" --joints=tools/blender/joints/bulky_knight.json --hue=345:42:45:0.35:3.2 --gray=1.35 --out=assets/characters/heroes17/emelrich.glb`
* Feran: `--src=work/downloads/sf_heroes/assassin_character_model.glb --name=feran --height=1.82 --faces=34000 --drop="^cloth13_" --cloth="^cloth" --out=assets/characters/heroes17/feran.glb`
* Burak: `--src=work/downloads/sf_heroes/burak.glb --name=burak --norig --joints=tools/blender/joints/burak.json --move="^Object_1[468]$:0,0,-0.082" --rigid="hips:ball:0.23,-0.125,0.915,0.115" --height=1.88 --faces=42000 --tex=2048 --drop="^Axe [LR]" --out=assets/characters/heroes17/burak.glb`
  Axes: `tools/blender/prep_weapon.py -- --src=work/downloads/sf_heroes/burak_axe2.glb --out=assets/weapons/burak_axe.glb --length=0.62 --grip=0.12` and `... burak_axe1.glb --out=assets/weapons/burak_axe_long.glb --length=0.78 --grip=0.14`
* Airah: `--src=work/downloads/sf_heroes/airah.glb --name=airah --joints=tools/blender/joints/airah.json --drop="lampu" --capture --rigid="hips:cap:-0.6,0.06,0.95,-0.55,0.73,0.72,0.11;hand.R:cap:-0.665,-0.066,1.30,-0.62,-0.085,1.35,0.034" --height=1.76 --faces=60000 --tex=2048 --out=assets/characters/heroes17/airah.glb`
* Beast: `--src=work/downloads/sf_heroes/ghorman_transform.glb --name=ghorman_beast --norig --posture --keep="mace" --joints=tools/blender/joints/troll.json --rigid="hand.R:cap:-48,-15,68,-52,-55,42,11;hand.R:ball:-55,-75,27,33;hips:cap:2,20,72,8,62,72,12" --height=2.4 --faces=30000 --tex=2048 --out=assets/characters/heroes17/ghorman_beast.glb`
Add `--preview=<dir>` to render idle/run/gs_1 front+side. The Tripo zips must be unzipped first:
`(cd work/downloads/sf_heroes/<name> && unzip <zip>; cd source && unzip *.zip -d x)` (fbx in `source/x/`).

## Tools written this run (all in tools/, documented in their headers)
* `tools/blender/hero_body.py`: the body pipeline. Default bind is **native** (model's own pose; 132 hero clips
  retargeted so each bone has the clip's armature-space orientation). Joints: source rig (UE/Mixamo names, Sketchfab
  `_NNN` suffixes stripped), `--joints` file, or mesh estimate. Weights: bone heat, fallback watertight voxel stand-in
  + KD copy; island gating; cloth rule (`--cloth` regex limits it); arm capture; smoothing; seam weight sharing;
  `--rigid` (split + lock), `--cut` (box/cap/ball), `--bake` (dense meshes, GPU OptiX), `--hue/--gray` (texops.py),
  `--glide`, `--norig`, `--move`, `--keep`, `--capture`, `--posture`, `--body_piece`, `--reach` (opt-in, hurt big
  gauntlets).
* `tools/blender/grid_render.py` + `tools/grid_overlay.py`: ortho front/side with measuring grid; `--marks` json to
  check joints. Workflow: render grid -> read joints -> write `tools/blender/joints/<x>.json` -> overlay -> build.
* `tools/blender/pose_render.py` (body + weapons in chosen clips; `--dist --aim` for close-ups),
  `look_render.py`, `extract_prop.py`, `prep_weapon.py` (blade to +X like the game's axe), `heroes17_gear.py`,
  `texops.py`, `tools/build_credits.py`.
* Game: `ModelCatalog` H17 entries; `RepairedClips.path_for` handles `/heroes17/`; `GameSettings.OWN_BODY` now has
  ezee, azrin, caziel (add new heroes there when their kits land); `UnitView` glide clip + lean + bank; `fx.gd`
  "knife" projectile; `src/ui/credits_panel.gd` + Credits plate on the main menu; probes
  `tests/tools/heroes17_look.gd -- --hero=<id>` and `tests/tools/select_shot.gd -- --heroes=a,b`.

## Traps learned (do not relearn)
* Bash `-c` breaks on apostrophes inside heredocs: write patch scripts with the Write tool, then `python -I file`.
* Blender: bone references go stale after edit/pose apply -> use names. Bone heat fails on tiny-scale or
  many-island meshes (scale first; stand-in). A skinned child ignores its object offset until the armature modifier
  is applied (that is why `--move` runs after). Saving edited pixels of a baked/loaded image keeps old pixels:
  copy into a new generated image and save that. glTF splits verts at UV seams (weld before island finding).
* Sketchfab conversions of 3ds Max CAT rigs are broken (Northern Outsider, Troll, Burak's rig): use `--norig` +
  hand joints. Sketchfab helper "Icosphere" meshes are dropped automatically.
* Posed models with limbs touching the body need `--capture` and `--rigid` hand locks (Airah).
* Hero clips impose the hero's upright posture; `--posture` keeps a hunch.
* Monitor greps: the Cycles "HIP ... Error" warning matches "Error"; filter it out.

## Next steps (in order)
1. Ghorman human: wait for the owner's original-format Northern Outsider (or another model they name). Build with
   hand joints, add the druid deer-skull/antlers (`druid_clothes.glb` "Head" piece) and a golden lion-mane recolour
   of the fur cloak; club = troll mace or own. Add Ghorman to catalog with `forms: {"beast": "hero_ghorman_beast"}`
   like Roydo's Anomaly.
2. Feran jester restyle (own coat/hat/mask: recolour cloth pieces red/black diamonds via texops or new textures; model
   the three-point bell hat and half-smile mask in `heroes17_gear.py` and attach to the head bone).
3. Emelrich: paint the Ancient Light sun on the tabard (texture edit on emelrich cloth image) and gold trims.
4. Burak: fur mantle, red war paint; Rage eye glow/steam belong to the kit FX.
5. In-match captures for the catalog-only bodies once kits exist; `sh tools/check.sh`; tests
   (`godot --headless --path . -s tests/run_tests.gd`, last 248/248); rebuild the exe; update HANDOFF + ledger;
   `python tools/normalize_eol.py`; commit (local commits allowed, end message with the Co-Authored-By line).
