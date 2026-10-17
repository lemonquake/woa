# Run 2026-10-17 d: QA pass (performance, gameplay, bots, map) and the outer map

## Request (owner, verbatim)

> QA this game on performance, gameplay, AI behavior, Map design flaws and expansion possibilities (maybe more to
> explore at top and more at bottom) then implement it. The game should run as smooth as possible. If you need any
> 3rd party libraries or 3rd party systems, implement them. then build the game, push to main

## Baseline (revision c1e4cc8, this PC: RTX 4060, 16 threads, 1080p, V-Sync off)

* Headless tests: 244 passed, 0 failed (`tests_before.txt`).
* Teamfight bench (`--bench=40 --t=600 --fight --autoplay --nolearn --lineup=ezee,azrin,froster,sludge,tock,
  blood_ranger,caziel,kragg,azrael,blau`), two runs: avg 22.1 / 22.2 ms (45 fps), p95 33.3, p99 39.0 / 40.6, max 79.
  Frames without a sim tick 18.5 ms; draw calls ~2290 a frame, ~2.0 M primitives.
* Lane bench (`--bench=50 --t=240 --autoplay --bots=5v5 --nolearn`): avg 15.1 ms (66 fps), p95 20.0, p99 30.2.
* Every benchmark run crashes on quit (segmentation fault after "Leaked instance dependency" warnings).

## Components

| Id | Component | Owner files | Gate |
|---|---|---|---|
| P1 | Frame time | `project.godot`, `src/game/*` views | teamfight and lane bench, same command, 2+ runs each, against the baseline; no new script errors |
| P2 | Quit crash | `src/game/main.gd` teardown | bench exits with code 0 (no segfault) |
| M1 | Outer map: larger square (18432), new open ground beyond the top and bottom lanes and in the two river corners | `src/sim/sim_map.gd`, `sim_const.gd`, `sim_vision.gd` | tests; camp_layout reachability; capture of both new areas |
| M2 | Map sites: Warp Gates (Dota's Twin Gates), Lily Ponds (Lotus Pools), Lookout Lamps (Watchers) with Dota's numbers | new `src/sim/sim_sites.gd`, orders, views, HUD, minimap | new tests per site; input through right click |
| B1 | Bots use the sites (lilies when hurt, lamps on the way, gates for long walks) | `src/sim/sim_bot.gd` | bot game: sites used, no stuck bots at the sites |
| Q1 | QA fixes found on the way | as found | tests, bot game |
| X1 | Integration | all | tests, check.sh, bot game, both benches, export, cold start |

## Mechanics (sources)

* Twin Gate: 4 s channel within 200, 30 mana refunded when interrupted, no cooldown, roots break it (7.41e).
  Sources: Liquipedia "Twin Gate" (search summary: 30 mana, refund on interrupt), Liquipedia "Channel" (Warp does
  nothing when interrupted), 7.41e notes (root interrupts), gap report `../2026-10-17-azrael/dota_gap_report.md`.
* Watcher: 1 s capture within 300 (7.40: 1.5 -> 1 s), 420 s on, vision 800 day / 450 night (7.40), capturing an enemy
  one turns it off for 120 s. Sources: Dota 7.40 patch notes, Fandom / Liquipedia "Watcher" (search summaries).
* Lotus Pool: one lotus every 180 s, at most 6; collected by a hero within 350 of the centre, the first after 1.5 s,
  each next one 30% faster; an enemy hero in the area pauses it; a lotus restores 125 health and 125 mana.
  Sources: Liquipedia "Lotus Pool", "Healing Lotus", 7.38 notes (search summaries).

## Measurement conditions

Same commands as the baseline, nothing else running, window on the main monitor. Pass: teamfight average and p95
better than the baseline on every run, lane average not worse; tests all pass.
