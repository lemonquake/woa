# Run 2026-10-18 d: handoff (Mixamo clips, hand remnants, build)

State: IMPLEMENTED; component gates measured (below); no blind critic review (none asked for).

## Mixamo download (how, for the next time)
* The owner signs in to mixamo.com in the app's built-in browser (never type credentials). The page's localStorage
  `access_token` authorises Mixamo's own API from page JavaScript (headers `Authorization: Bearer <token>`,
  `X-Api-Key: mixamo2`): `GET /api/v1/products?type=Motion|MotionPack&query=...`, `GET /api/v1/products/<id>?similar=0
  &character_id=<Y Bot 4f5d21e1-4ccc-41f1-b35b-fb2547bd8493>` (packs list `details.motions[].gms_hash`),
  `POST /api/v1/animations/export` with `{character_id, gms_hash:[{model-id, mirror, trim, overdrive:0, params:"0",
  arm-space, inplace:false}], preferences:{format:"fbx7_2019", skin:"false", fps:"30", reducekf:"0"}, product_name,
  type:"Motion"}` (one motion per job; packs as MotionPack fail with "Invalid Pose option"), then poll
  `GET /api/v1/characters/<id>/monitor` until `status == completed` AND `job_result` names the new file (it returns
  the previous job's result for a moment).
* `job_result` is a signed S3 link valid 5 minutes, each with its own credentials. The pane cannot reach localhost;
  clicking the link makes the pane save the file under its own name in the last download folder it used
  (`work/downloads/sf_heroes/`, the owner's Sketchfab folder) via a `.tmp` in `C:\Users\Lemon PC\Downloads`, and the
  last few arrive late. I moved them to `work/downloads/mixamo/raw/` (git-ignored) and checked names by content hash.
* 181 files: Great Sword, Pro Sword and Shield, Pro Melee Axe, Pro Longbow, Pro Magic packs (selected motions) and 57
  single clips (`x_*`). License: Mixamo clips may ship inside the game, not as loose files; the repo is public, so
  `work/downloads/mixamo/` and `assets/characters/hero/mocap/` are git-ignored.

## Commands
```
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; G=A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe
"$B" -b --factory-startup --python tools/blender/mocap_retarget.py -- --survey --src=work/downloads/mixamo/raw --cells=work/lemondev/2026-10-18d-mocap/survey --frames=7
python tools/mocap_sheet.py work/lemondev/2026-10-18d-mocap/survey work/lemondev/2026-10-18d-mocap/survey_sheets --per=5
"$B" -b --factory-startup --python tools/blender/mocap_retarget.py -- --spec=tools/blender/mocap_clips.json --src=work/downloads/mixamo/raw --out=work/mocap/hero_mocap.glb
"$G" --headless --path . -s tests/tools/mocap_import.gd          # -> assets/characters/hero/mocap/hero_mocap.res + mocap_meta.json
"$G" --headless --path . -s tests/tools/body_collide.gd -- --fix  # also writes assets/characters/hero/mocap/collide/<model>.res
"$G" --headless --path . -s tests/tools/body_collide.gd -- --applied
"$B" -b --factory-startup --python tools/blender/remnant_check.py -- --glb=assets/characters/heroes17/ezee.glb --png=x.png --weights=w.png
LOG=<dir> sh work/rebuild_qa.sh <out dir> ezee azrin caziel        # own bodies with the arm split (Azrael: --split=0)
```

## Gates (numbers)
* Remnants (remnant_check: both arms lifted out and the elbows bent; "left" = vertices at a hand or forearm that did
  not move with it; "torn" = edges stretched over 3x), before -> after: Ezee left 160+2 -> 10+2, torn 52+0 -> 68+4;
  Azrin left 53+7 -> 1+0, torn 10+54 -> 59+127 (her sleeves now lift whole; their ragged hems and the armpit stretch
  count as torn); Caziel left 151+207 -> 294+698, torn 1+20 -> 31+42 (the "left" count is coat where his hands
  rested, which correctly stays: the renders show the dagger-like shards and torn coat strips gone). Azrael kept her
  weights (her own rig's; the split moved her dress to an arm). Renders: `remnants_before/`, `rebuild2/*_cmp.png`.
* Body collision with every fix applied, clips as the game plays them with the mocap library: every mocap clip on
  every body 0.9 cm or less. Old clips kept for a game without the library, now worse on the rebuilt bodies: Ezee's
  old ground slam 42 cm (sword in the floor, 3 frames), Azrin's old casts up to 21 cm; none is played while the
  library is present.

## Not done / next
* Blind critic review; Leap Strike, runs, glides and knockbacks still use the old clips (the leap's timing is tied to
  the simulation; runs are the owner's own mocap).
* Azrin's sleeves: ragged hems and an armpit stretch in very high arm poses; Ezee: one plate inside the left elbow.
* The catalog-only bodies (Emelrich, Feran, Burak, Airah, Ghorman) were not rebuilt and have no mocap mapping yet.
