# Run 2026-10-18 g: handoff

State: **IMPLEMENTED — UNVERIFIED** (all gates below passed on the working tree; no blind critic review was run, and
no Dota spectator capture was compared).

## What changed

* 150% experience and gold: `SimConst.XP_RATE` / `GOLD_RATE` (1.5), `SimWorld.xp_rate` / `gold_rate` applied in
  `SimCombat.give_xp` / `give_gold` (which now return the amount given) and passive gold. Debug gifts pass `raw`.
  Popups, kill banners, Gold Glove and orb notes show the paid amount. Game Setup "Match" row: Experience, Gold
  (100 / 150 / 200 / 300%), saved in `user://setup.json` (`xp_rate`, `gold_rate`). Tests' `world()` and
  `_courier_world()` set 1.0 to keep checking Dota's numbers; `test_match_rates` checks 150%.
* All-Bot matches: Game Setup allows no You slot ("Watch bots" preset; Start reads "Watch"). `Main.spectator`: every
  hero a bot's, `act()` refuses everything, `player_hero_id` / `player_team` follow the watched hero (`watch()`).
* Spectator view: `src/ui/watch_panel.gd` (hero, camera Free / Follow hero / Hero view / Auto, sight, orders, plans,
  speed, pause). Sight goes through `Main.sees()`, `sees_cell()`, `own_team()`, `fog_bytes()` everywhere the screen
  read `vision.*(player_team, ...)` (main, fx, fortify, orbs, sites, Airah's/hero16 effects, ambience, minimap, top
  bar). Orders: the HUD's Shift-queue waypoints for one or every shown hero; plans: `SimBot.plan_text()` (read only).
* Camera: `CameraRig.distance` 13.6 -> 15.6; `user_moved` frees the spectator camera on any pan or minimap click.
* Debug panel "Bots" (after the hero section): every bot / a team's bots / one bot; `SimDebug.bot_heroes`,
  `give_item`, `take_gold`, `set_bot_skill`, `set_bot_still`.

## Evidence

* `logs/tests.log`: headless tests (final run after the paid-amount fix; see the status line in docs/HANDOFF.md).
* `logs/check.log`: `sh tools/check.sh` (script errors, "Names OK").
* `logs/watch_probe.log`: 24/24 with `--watch --bots=5v5`; `logs/watch_probe_setup.log`: 24/24 through a saved Game
  Setup with no You slot (random heroes). The owner's `setup.json` was backed up and put back (`setup_backup.json`).
* `shots/watch_auto_both.png`, `watch_hero_view.png`, `watch_debug.png`, `setup_watch.png`, `export_watch.png`
  (release build, cold start with `-- --match --watch --bots=5v5`).
* `logs/export.log`: release export to `build/WarriorsOfAether.exe` + `.pck`.

## Not verified / next

* No blind critic review; looks checked by the builder at 1920x1080 only (not 4K).
* Auto camera's choice is a simple score (heroes near, recent hero damage, low health); not tuned against real
  directed-camera footage.
* Bots' balance at 150% was not re-measured in long bot games (levels and items come about a third sooner).
* Multiplayer always plays 150% (no lobby setting); spectating is single player only.
