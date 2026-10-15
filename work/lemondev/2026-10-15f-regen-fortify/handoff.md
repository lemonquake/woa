# Run 2026-10-15 f handoff: regen readout, Rejuvenation Orb, tower shots, Fortify, courier, Fast Forward

State: mechanics **VERIFIED by gate** (tests, probe, bot game); looks **IMPLEMENTED — UNVERIFIED** for blind review
(self-checked captures only, no Dota frames on disk). Working tree, uncommitted.

## Evidence

* Headless tests: 200 passed, 0 failed (197 + `test_rejuvenation_orb_only_at_2_and_4_minutes`,
  `test_fortify_towers_splash_mark_speed`, `test_bots_fortify_tower_in_danger`; courier and Fast Forward tests
  updated to the new rules).
* `tests/tools/fortify_probe.gd`: 1080p 14/14; real 3840 x 2160 12/12 (2 hover checks skipped: frame larger than the
  monitor). Captures in `shots/`: `regen_bonus`, `regen_cut`, `regen_tip`, `rejuvenation_orb`, `tower_shot_*`,
  `tower_hit_*`, `tower_shot_fortified_*`, `tower_splash_*`, `fortify_base_light`, `fortify_base_dark`,
  `fortify_button_tip` (and `_4k`).
* `bot_game.txt`: one 45-minute 5 v 5 bot game (seed 5), with the Fortify presses listed.
* `sh tools/check.sh` "Names OK".

## Passes

| Component | Pass | Verdict | Largest gap |
|---|---|---|---|
| R1 Regen readout | 1 | REJECT (self-check) | a healing cut only shrank the bonus; the "+" was too faint |
| R1 | 2 | PASS (gate; self-check look) | none |
| O1 Rejuvenation Orb | 1 | PASS (gate; self-check look) | none (timing was already right; now tested) |
| T1 Tower shots | 1 | REJECT (self-check) | Black Sun's corona edge-on from the game camera: read as a line and a pink streak |
| T1 | 2 | PASS (self-check) | none |
| F1 Fortify | 1 | REJECT (self-check) | shells far too big and opaque (white-out over the Ancient Light base, pink bubbles at Black Sun) |
| F1 | 2 | PASS (gate; self-check look) | none |
| C1 Courier | 1 | PASS (gate) | none |
| K1 Fast Forward | 1 | PASS (gate) | none |

## File map

* `src/ui/hud.gd`: `_bars`, `_regen_text`, `_regen_tip`, `_regen_num`, `_outlined_l`; Fortify button tooltip; Tip uses
  each panel's own hit test (`showing` for probes).
* `src/sim/sim_orbs.gd`, `src/game/orb_view.gd`: Rejuvenation Orb.
* `src/game/fx.gd`: `_tower_shot`, `_corona_mat`, `_light_spike`, `_implode`, tower impacts.
* `src/game/fortify_fx.gd` (new): shells, beam, halo / black sun, ring bursts, splash rings.
* `src/sim/sim_combat.gd`: `fortified_tower`, `fortify_mark`, `_fortify_splash`; `sim_const.gd` GLYPH_* values;
  `sim_world.gd` `glyph(team, by)`; `sim_team_ai.gd` `_glyph`; `src/game/main.gd` `_on_glyph`.
* `src/sim/sim_kits2.gd` `basic_spells`, Fast Forward; `sim_data.gd` values and talent; `sim_bot.gd` target choice.
* Tools: `tests/tools/fortify_probe.gd` (new), `tests/tools/bot_game.gd` (lists Fortify presses).
