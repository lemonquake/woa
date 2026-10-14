# Run 2026-10-14 b: QA, performance, UI remake, multiplayer, Froster and Caziel

Baseline: a38afe7 plus the uncommitted 2026-10-14 work (Azrin run). Rollback point: `refs/lemondev/baseline-2026-10-14b`
(fb0b4b4, made with `git stash create`; tracked files only, the untracked Azrin assets were left in place). Engine
Godot 4.7.2 Forward+, Windows 10, RTX 4060, Ryzen 7 5700X, target 1920x1080 (also 3840x2160). Budget: 8 build/review
passes per component (lemondev default).

## Owner's request (2026-10-14, second message)

1. QA the logic and mechanics: everything sound and smooth.
2. Smooth FPS in every phase of the game whatever the number of players; a thorough FPS and performance pass.
3. Remake all UI, "epic", with our own textures and design, professionally designed for this game.
4. A comprehensive, low-latency multiplayer with its own UI.
5. Present only when confident that the UI is as good as it can be and every function works.
6. New heroes with the owner's names and numbers: Froster, the Winter Master (Ice, male) and Caziel, the Void
   Assassin (Dark, male), four abilities each (texts in the owner's message, copied into `heroes.md`).

## Components (one owner per file set; built by the orchestrator; critics are fresh subagents with packets only)

| ID | Component | Files | Acceptance gate |
|---|---|---|---|
| Q1 | Mechanics QA: lane creeps, stuck units, bot idling, game end | sim_* | headless tests; 5 v 5 bot games (3 seeds, 50 min): no script errors, no lane without creeps, an Ancient falls in each |
| P1 | Simulation cost | sim_* | `tests/tools/sim_profile.gd` 5 v 5, 3 seeds, 40 min: mean tick <= 3.5 ms, p95 <= 7 ms, max <= 25 ms on this CPU; every existing test still passes (rules unchanged) |
| P2 | Frame cost (views, HUD, effects, rendering) | src/game, src/ui | `--bench` 1080p, vsync off, 60 s windows at 10:00 and 25:00, 1 v 1 and 5 v 5: p95 frame <= 16.7 ms (60 fps) and mean >= 75 fps; the report lists p99, max and frames over 16.7 ms |
| H1 | Froster: kit, talents, bot, tests | sim_data, sim_abilities, sim_bot, sim_bot_kits | tests per ability with the owner's numbers; 12-min duels vs every hero, 3 seeds, no errors |
| H2 | Caziel: kit, talents, bot, tests | same | same |
| V3 | Froster and Caziel looks and spell effects | game_settings, unit_view, model_catalog, new froster_fx / caziel_fx | in-match captures of each spell at 1080p; Hero Select captures |
| N1 | Command funnel: every player action is a serialisable command applied by the simulation | sim_world (+ new sim_commands), input_controller, hud, shop_panel, chat_panel | tests: each command kind has the same effect as the old direct call; no UI code writes the simulation |
| N2 | Network session: host / join / LAN discovery, lobby, host-ticked lockstep, input delay, catch-up, hash checks, resync from a snapshot, drop / rejoin, pause, chat | new src/net/* | headless two-process test: 15 min 5 v 5 with random commands from both peers, 0 desyncs; forced desync recovers; command-to-execution latency on localhost <= 2 ticks + RTT; live two-window probe |
| U0 | UI skin: generated textures, 9-slice frames, buttons, bars, slots, ornaments, fonts, theme | tools/ui_skin.py, assets/ui/skin/*, ui_kit | see U-gate |
| U1 | Main menu and Hero Select | hero_select, splash | U-gate |
| U2 | Game Setup, Options, Hotkeys, Loading, Hero Creator | those screens | U-gate |
| U3 | In-match HUD, shop, scoreboard, pause and end screens, kill feed, chat, tooltips | hud, shop_panel, scoreboard, match_menus, kill_feed, chat_panel, unit_bars | U-gate + existing probes (menu, item flow, input, controls) pass |
| U4 | Multiplayer screens: browse, host, join, lobby, connection states | new src/ui/net_*.gd | U-gate + live two-window probe |
| G | Integration | all | tests, check.sh Names OK, probes, bench, export + cold start, 1080p and real 4K captures |

U-gate (frozen before any candidate capture): blind A/B by a fresh critic subagent against the Dota 2 frames in
`work/benchmark/` (Steam store screenshots; HUD frames 0-6 and 9, menu frames 7-8), same size (1920x1080), criterion
"which interface looks more professionally designed and finished for a fantasy MOBA (texture, depth, hierarchy,
ornament, readability)". PASS = our capture chosen with clear advantage, or (the owner's bar is "as epic as it can
be") at least chosen over the reference on two of three paired frames with no mandatory failure. Mandatory: every
visible control does its action (probes), no clipped or overlapping text at 1080p and 4K, text readable.

## Benchmarks

* Visual: `work/benchmark/dota_*.jpg` (10 Steam frames, 1920x1080), recorded in run 2026-10-12. Not used as assets.
* Mechanics: Dota 2 7.41d for every shared rule; the owner's numbers for the two heroes.
* Performance: the same machine, the baseline build (refs/lemondev/baseline-2026-10-14b) measured in this session.
  Baseline 2026-10-14 b: `--bench=45 --t=600 --autoplay`: 1 v 1 36 fps (p95 40.9 ms), 5 v 5 21 fps (p95 73.4 ms);
  headless 5 v 5 sim at 20:00 16.4 ms per tick with 388 units (lane creeps stuck, see Q1).

## Findings so far

* Q1-a: Ancient Light's top tier 3 tower stands on the top lane line at (-6550, -4050); wave creeps spawned at
  (-6550, -4210) inside its blocked footprint cells and could never step out, so from the second wave on Ancient
  Light's top lane and (mirrored) Black Sun's bottom lane got no creeps; 55 + 40 creeps piled up by 12:00. Fixed: wave
  spawns snap to walkable cells; a unit standing in a blocked cell may move within it to get out; units now slide
  along the tangent of a unit or building that blocks them.
