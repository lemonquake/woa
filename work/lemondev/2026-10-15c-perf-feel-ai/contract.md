# Run 2026-10-15 c: performance in fights, game feel, bot play and learning

## The owner's request (2026-10-15)

> Further enhance game performance from all levels and all situations: a stable FPS, especially in clashes and
> teamfights. Use any third-party library or system the game needs. Big improvements to the feel of the game, how it
> responds, the UI (easy to navigate and control). Big improvements to the bots: early laning (harass, deny, last
> hits), mid and late game decisions, how they set up ganks, and their learning, so they play better with experience.

## Component contracts

| ID | Component | Owned files | Acceptance (frozen before measuring) | Benchmark / evidence |
|---|---|---|---|---|
| P1 | Teamfight frame time | `src/game/main.gd` (bench), `src/game/bench_probe.gd`, the hot paths it finds | Same-session A/B against the last commit (`81efd48` + the same bench harness) in a real 10-hero teamfight (`--fight`, every bot brawls): higher average fps, lower p99 and worst frame, no script errors | `ab_*.log` in the scratch run; numbers below |
| P2 | Simulation spikes | `sim_world.gd`, `sim_vision.gd`, `sim_bot.gd`, `sim_team_ai.gd`, `sim_bot_kits.gd`, `sim_abilities.gd`, `sim_ai.gd`, `sim_unit.gd` | Headless `sim_profile.gd --fight`: worst tick and count of ticks over 15 ms drop; mean tick not higher; all tests pass; snapshots stay valid (caches are TRANSIENT) | `sim_profile` runs below |
| P3 | Interface cost | `src/ui/hud.gd` (portrait, minimap), `kill_feed.gd`, `scoreboard.gd`, `chat_panel.gd`, `input_controller.gd` (pick), `camera_rig.gd` (ground_at), `item_fx.gd`, `trail3d.gd` | Bench per-panel `_draw` means drop; draw calls drop; HUD looks the same in a capture | bench lines `ui_*`, `shots/hud_lane.png` |
| A1 | Last hits | `sim_bot.gd` `_last_hit_target`, `tests/tools/lh_lab.gd` | Lone bot in mid for 8 min (`lh_lab`), five heroes: more last hits than before at every hero | lab table below |
| A2 | Teamfights | `sim_team_ai.gd` `_call_teamfight`, `fight_odds`, `_focus_target`; `sim_bot.gd` task "fight" | Mirrored 5 v 5 bot games, team engage on for one side only (`--tf_off`), swapped across seeds: the side with it ahead in most games | `ai/tf_*.txt`, `ai/tf2_*.txt` |
| A3 | Ganks | `sim_team_ai.gd` `_call_ganks`, `_gank_rally`, `_gank_strikes`; `sim_bot.gd` task "gank" | Tests: rally point out of the target team's sight, on its way home; laning-phase ganks only with a hero from another lane | `test_gank_rally_out_of_sight` |
| A4 | Farming and laning | `sim_bot.gd` `_clear_wave`, `_aoe_farm`, `_can_clear`, `_tp_out`, heal and regen | Carry last hits at 10:00 and 20:00 in 5 v 5 bot games higher than the session's first games (`g1_*`) | `ai/g1_*` vs later `ai/g*_*` |
| A5 | Mid and late game | `sim_team_ai.gd` `_call_push`, `_advance_pushes`; `sim_bot.gd` `_unstick` | Pushes chain to the next building; fewer stuck bots; games end (an Ancient falls) within 60 minutes | `ai/g5_*.txt` |
| L1 | Learning | `src/sim/bot_memory.gd`, hooks in `sim_bot.gd` and `sim_team_ai.gd` | Tests: last-hit lead, engage bar and gank rate move the right way; learning off in automated runs | `test_bot_memory_learns_timing_fights_ganks` |
| U1 | Quick cast, trails, shadows option | `input_controller.gd`, `options.gd`, `options_panel.gd`, `trail3d.gd` | Quick cast fires a targeted spell at the cursor through the real input path; options persist | input probe below |

## Measurement conditions

* PC: AMD Ryzen 7 5700X (8 cores, 16 threads), NVIDIA RTX 4060, Windows 10. Godot 4.7.2, Forward+, 1920 x 1080
  window, V-Sync off, no frame cap (the bench sets these). A background process (`UninstallMonitor`, not ours) kept one
  core busy the whole session, so run-to-run spread is wide: compare A and B from the same session only.
* Teamfight bench: `godot --path . res://src/game/main.tscn -- --bench=40 --t=600 --fight --autoplay
  --lineup=ezee,azrin,froster,sludge,tock,blood_ranger,caziel,kragg,azrin,froster` (10:00, all heroes level 16 with
  five items of their first bot build, staged face to face in mid every 20 s, every bot fights the nearest enemy).
* The baseline is a worktree of `81efd48` with only the bench harness added (fight staging, lineup, probes).

## Guide deviations

* No blind critic review: the owner did not ask for subagents, and these components are measured (frame times, bot
  game statistics, tests), not judged by eye. Visual changes are small (portrait backdrop, trails); they are builder
  self-checks, UNVERIFIED for blind review.
* Third-party libraries: none were needed. The bottlenecks were our own scripts (an error printed every frame, caches
  wiped, a second render of the world for the portrait), not the engine. A C++ (GDExtension) port of the simulation
  would need a compiler toolchain on this PC and risks lockstep determinism; it is the next step only if GDScript
  stops being enough.
