# Run 2026-10-18 f: the five new heroes' kits (contract)

Request (from the session that started this one, for the owner): implement the skills of Airah, Burak, Ser Emelrich,
Feran Mock and Ghorman from `hero_ideas.txt` (the owner's annotations there win), with talents, bot kits, Hero Select
text, icons and effects; Ghorman's Beast Form with his form swap and the beast body rebuilt; tests for every ability's
numbers. Baseline revision: `37130bf`.

## Components

| id | Component | Files | Acceptance |
|---|---|---|---|
| K1 | Ability, talent and hero data | `src/sim/sim_data.gd` | every ability of the file with its numbers; talents 4 tiers x 2; names pass `check_names.py` |
| K2 | Airah, Burak, Ser Emelrich kits | `src/sim/sim_kits5.gd` (+ hooks in sim_abilities, sim_combat, sim_orders, sim_status, sim_unit) | a headless test per ability checks its numbers |
| K3 | Feran Mock, Ghorman kits | `src/sim/sim_kits6.gd` (+ hooks) | as K2; tamed beasts obey Ghorman and the player |
| K4 | Bots | `src/sim/sim_bot_kits.gd`, `src/sim/sim_bot18.gd` | skill and talent orders, builds, burst, disable; bots cast every skill in bot games |
| K5 | Presentation | `src/game/hero18_fx.gd`, `model_catalog.gd` (anims), `unit_view.gd`, `targeting_fx.gd`, `ui_kit.gd`, `buff_bar.gd`, `unit_bars.gd`, `hero_select.gd`, `tools/item_icons.py` | every ability has an icon, a clip and a visible effect; no script errors in a live match |
| K6 | Beast Form body | `assets/characters/heroes17/ghorman_beast.glb` | remnant_check left/torn counts lower than before (0 / 127+462) |
| K7 | Integration | tests, `tools/check.sh`, body_collide, anim_joins | `run_tests.gd` all pass; "Names OK"; collide and joins re-run |

Benchmark: Dota 2's own rules where the file names them (cleave cone, bash rule, cooldown rate, status resistance);
the owner's existing kits (Kragg's drag and crashes, Azrael's door recast) for how things are built here.
Budget: 8 passes per component. No blind critic review was asked for.
