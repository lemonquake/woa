# Run 2026-10-13 b: Sludge input fixes, targeting cursors, To Buy, stash, courier, HUD

Baseline revision: 8310428 (main, clean). Engine Godot 4.7.2, Windows, 1920x1080 target (also 3840x2160).
Owner's request (verbatim points): Stench, Blubber, Chomp do nothing; Chomp cannot target; a pulsing red crosshair for
spells on enemies, green for support spells, items too; Shift-click in the shop breaks an item into a "To Buy" side
list (8 shown); right click there auto-buys when gold allows and the courier holds it if it is at the fountain; a
deliver order also picks up the player's items lying in the fountain area; a Dota 2 stash; all item and courier
mechanics; HUD: level and XP always visible (obstructed now), the hero's name over the portrait like Dota; build.

## Root causes found before building (evidence: code read, `input_controller.gd`)
* Stench: `begin_ability` matches "no_target", "point", "unit", "autocast_attack"; "toggle" falls through: no order.
* Chomp: `begin_ability` calls `cast_error(h, aid, -1, null, ...)`; for a unit spell with no target yet this returns
  "Must target a unit", which is not the one string let through ("Must target an enemy unit"), so targeting never
  starts.
* Blubber: the sim path works (instant cast); the feedback is one 0.45 s ring, no lingering sign and no status icon.
  To be confirmed with the live probe through the real input controller.
* HUD: the portrait SubViewportContainer is a child drawn over the panel's own `_draw`, covering the level ring and
  the name.
* Talents: no player UI calls `learn_talent` (bots only).

## Components, owners (single agent, separate files), acceptance
| Id | Component | Files | Acceptance (gate) |
|---|---|---|---|
| A1 | Ability input | input_controller.gd, sim_abilities.gd | Live probe through InputController with Sludge lvl 18 next to an enemy hero: W turns Stench on (toggle true, damage ticks) and off; E puts the Blubber modifier on and spends mana; R enters targeting, a click on the enemy starts the Chomp channel; Q hook launches. Same for Blood Ranger and Ezee's kits. Unit spells keep targeting on a ground click with an error. |
| A2 | Talent tree | hud.gd | Player can open it at level 10+ and learn one per tier; test + capture |
| B  | Targeting cursor | input_controller.gd, new targeting_cursor.gd | Red pulsing crosshair for hostile spells/items, green for support (ally/self/point-friendly), per ability/item data `target_team`; capture of both |
| C1 | To Buy list (sim) | sim_shop.gd, sim_unit.gd | Tests: shift-add expands to missing basic parts, max 8 shown, auto-buy fires when gold allows, goes to courier when it waits at the fountain, removed when owned |
| C2 | Stash and items (sim) | sim_shop.gd, sim_world.gd | Tests: stash 6 slots, purchases away from shop -> stash (or waiting courier), Grab All, move to stash in base, drop / pick up / give, backpack swap cooldown |
| C3 | Courier (sim) | sim_world.gd, sim_combat.gd, sim_const.gd | Tests: speed 290 + 10/level, flying from owner level 4 (ground pathing before), dies to 1 melee hero / 2 ranged hero / 6 other attacks, respawn 60 + 6 x level, items kept while dead, abilities: Return to Base, Retrieve, Return to Stash, Transfer, Deliver, Auto Deliver, Speed Burst (lvl 10, +50% 6 s, 120 s), Shield (lvl 20, 2 s, 200 s); deliver picks up the owner's ground items within the fountain area |
| D  | HUD overhaul | hud.gd, shop_panel.gd, new hud panels | Name over the portrait, level circle with XP ring (and numbers) never covered, talent button, stash panel, To Buy panel, courier panel when selected, drag and drop; readable at 1080p and 2160p (captures) |
| G  | Integration | all | tests pass (92 old + new), check.sh Names OK, duels complete, bench no worse than 10% below 82 fps / p95 14.2 ms, export + cold start |

Benchmark for B, C, D: Dota 2 itself (behaviour from Dota's game data in `work/research/d2_npc_units.txt`,
`d2_npc_abilities.txt`, the 7.23/7.27/7.35 courier changelog entries via web search; HUD layout from
`work/benchmark/dota_2.jpg`). Blind visual review needs Dota frames of the stash and quick buy, which we do not have:
those gates stay UNVERIFIED unless such frames are supplied.
Budget: 8 passes per component.
