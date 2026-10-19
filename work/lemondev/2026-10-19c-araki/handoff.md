# Run 2026-10-19 c: handoff (Araki, the Blur; Blau's turrets; Airah and Tock facing; build)

State: IMPLEMENTED; component gates measured (below); no blind critic review (none asked for); no Dota 2 client, so
the benchmark comparison is UNVERIFIED. The owner's requests are in `contract.md`. The summary for the owner is the
top entry of `docs/HANDOFF.md`.

## What was found and fixed along the way
* The owner first supplied an unrigged posed model (Cyber Samurai), then asked for "a rigged model that you can get
  anywhere". Chosen: Shadowflame Samurai (dark_igorek, CC BY 4.0, Character Creator rig, its own katana), an undead
  samurai bound to a green soul-flame (fits "centuries of battle in the Undead realm"). Downloaded with the owner's
  Sketchfab sign-in in the app's browser (GLB, 4K textures, 163 MB) into `work/downloads/sf_heroes/` (git-ignored).
* Its rest skeleton is broken in the Sketchfab conversion (Y-up, the upper arms at the origin): `araki_prep.py` bakes
  the shown pose as the rest and flattens the converter's empties (a .blend loses their scale chain: it read 85 m).
* `hero_body.py` did not know CC rigs' neck (`NeckTwist01`); added. The arm split tore the back armour and flung the
  scabbard: built with `--split=0` (as Azrael). At 2048 textures the GLB was 113 MB, over GitHub's 100 MB file limit:
  1536 (71 MB).
* `prep_weapon.py` picked the katana's guard as its head (widest end): `--flip_head`.
* Blur Strike aimed past 600 made him walk into range: it is a direction cast now (as Gust).
* Ghosts died a tick after spawning: every summon dies at `ward_expires` (Blau's turret timer); ghosts set their own.
* New class names need `godot --headless --path . --import` before scripts that use them run (the first bot game
  failed on `SimBot19`).
* A `--pick=` Hero Select capture saves the selection: the owner's `user://hero.json` was restored to Azrael.

## Gates (numbers; logs in `logs/`)
* Kit tests: `test_araki_data`, `_senryukai`, `_blur_strike`, `_djin_bomb`, `_ghosts`, `_the_blur`.
* Full suite: see `logs/tests2.log` (first run `tests1.log`: 297 passed, 0 failed).
* `sh tools/check.sh`: no script errors, "Names OK" (`logs/check.log`).
* Body collision (`collide_fix.log`): every clip he plays 0 cm after the fix (worst before 35.7 cm, gs_4's katana in
  the floor); leap_slam 3.2 cm on one frame (he never plays it).
* Animation joins (`joins.log`): 42 joins and 3 loops, 0 failures, worst snap 10.6 degrees, feet planted on the run.
* Bot games (30 min, hard, `bot_game*.log`), Araki's team araki, ezee, tock, kragg, froster vs caziel, azrin, sludge,
  roydo, blood_ranger: that line-up loses the kills about 1 to 3 whichever side it plays (22-65, 19-60, swapped
  17-66). Araki before the bot fixes 5/15/4 and 6/13/7; after 6/11/6, 8/11/8, 6/14/4, 9/12/5. With Araki and Caziel
  traded between the teams: Araki 8/4/10, 76 last hits, 14.5k; Caziel 6/11/10, 46, 11.5k. His results follow his team
  as Caziel's do.
* Death probe (`probe1..4.log`, 20 min): deaths 10 -> 8 -> 9 -> 9; Ghosts of the Will cast 1 -> 8 times after it was
  moved ahead of the bomb and dashes; the traced deaths before the fix were dashes and bombs spent with the escape on
  9% mana.
* Blau's turrets per 25-minute bot game (`kit_casts*.log`): 13 and 16 before; 24, 38, 28, 33 after.
* Captures: `shots/strike_*.png` (echoes, streak, slashes), `combo_*`, `bomb4_*` (the cloud), `ui/select_araki.png`,
  `ui/select2.png` (17 heroes), `ui/pick.png` (ranked pick), `versus/after/`, `portraits/all.png`.

## Not done / not verified
* No blind critic review; no Dota 2 comparison.
* The demon cloud's rising smoke does not show in captures (the ground swirl and the burst do); its eyes are hard to
  see behind units.
* Bot strength against human players is not measured; the bot games are bot against bot.
* The exported build's Araki was cold-started into a match only (see `docs/HANDOFF.md`); the menus were not clicked.
* The owner's own Cyber Samurai and katana downloads are unused (kept in `work/downloads/sf_heroes/araki_the_blur/`).
