# Run 2026-10-20 d: interface smoothness and the official icon border

Owner's request: big improvements to how every UI behaves (example: the talent tree did not close on a click away);
an official default border for skill and item icons that can be replaced at any time (future custom and paid borders);
passive skills show no hotkey (added mid-run); build the game.

## Contract (frozen before review)
* Components: U1 popup dismissal and Esc across all screens (audit list from a read-only sweep of src/ui);
  U2 screen fades, loading screen on every match entry, overlay fade-ins, global button click;
  B1 border pack system (IconBorder, IconFrame, user:// packs, Options choice); B2 Default and Plain packs;
  B3 every skill/item icon routed through the border; P1 passive skills hide their hotkey.
* Benchmark: Dota 2's framed ability and item tiles, judged by name only (no local Dota capture: commercial gate
  UNVERIFIED). Baseline for the blind A/B: `work/lemondev/2026-10-20-icons/ui/shop_1080.png` (same ui_probe state).
* Criterion: icon presentation (frames, art filling slots, small-size readability, skill/item consistency).
  Mandatory: no frame inside a frame, no clipped/blurred/stretched art.
* Pass budget 8.

## Blind reviews (fresh critic each, raw crops only; mapping in mapping_private.txt)
| Pass | Packet | Winner | Verdict | Gap | Action |
|---|---|---|---|---|---|
| 1 | critic/ (A new, B old) | B | INVALID packet | new capture had unlearned (greyed) skills and no backpack item, baseline had both: state mismatch | rebuilt from the same ui_probe |
| 2 | critic2/ (X old, Y new) | Y (new) | REJECT | backpack / teleport slot: framed square inside a wider slot frame | backpack tiles 48x36, teleport slot one tile |
| 3 | critic3/ (P old, Q new) | Q (new) | PASS | innate icon frame thin at 28 px; skill frame heavier than item frame | recorded (not mandatory) |

## Evidence (final revision unless noted)
* `ui_smooth_probe.gd` 34/34, three runs in a row after the talent redraw fix (`ui_smooth_probe_1..3.txt`); before the
  fix it failed 1 in 3 (the tree's rows were filled only at the 20 Hz redraw: opening now redraws at once).
* `item_flow_probe.gd` 13/13 (`item_flow.txt`; its 150-gold step zeroes reliable gold now), `ranked_probe.gd` 51/51
  (`ranked_probe.txt`, run before the last HUD layout tweak), `sh tools/check.sh` clean + Names OK (`check.txt`).
* Full suite: `tests.txt` 326/3 (the 3 = one stale check expecting Switch Boots' old .svg path; fixed, `--only` 2/2);
  `tests_final.txt` final run: 327 passed, 0 failed.
* Captures: `ui2/` (matched ui_probe set), `probe/` (talents, item menu, shop, pause, user pack), `hero_select*.png`,
  `draft.png`, `hud_passive*.png`, `border_sheet_4k.png` (engine-drawn 2x scale), `borders_v1.png` (generator preview).
* Not verified: real 3840x2160 HUD window (monitor is 1080p; 4K covered by the 2x engine sheet only), Dota capture
  benchmark, FPS impact (fades and frames are 2D; no benchmark run), multiplayer dialogs clicked by hand.

## Resume
State: IMPLEMENTED; B1-B3 blind-reviewed PASS (pass 3 of 8); U1/U2/P1 measured by probes only.
Smallest next action: owner play-through; if wanted, a thicker passive frame at small sizes.
