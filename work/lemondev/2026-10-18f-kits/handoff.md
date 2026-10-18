# Run 2026-10-18 f: handoff (the five new heroes' kits, bots, icons, effects, build)

State: IMPLEMENTED; component gates measured (below); no blind critic review (none asked for). Owner's request this
session: "Build the game NOW! Finish implementing the new 5 heroes including their skill mechanics, proper icons,
proper AI and everything". An earlier session had written the ability data, talents, `SimKits5` / `SimKits6` and the
sim hooks and stopped before any of it compiled; this session finished it.

## What was found and fixed
* The kit files did not compile (four untyped loop variables in `sim_kits6.gd`), so every sim script failed to load.
* **Frenzy Mask clash**: the item's active adds a modifier with the id `berserk`; Burak's Berserk used the same id, so
  any Frenzy Mask user would have been treated as in Berserk (held damage read a missing key: a script error in every
  game with that item). Burak's modifier is now `burak_berserk` (`SimKits5.BERSERK`); the buff bar maps both.
* **Steel Stance and stuns**: `SimStatus.apply` ended every channel the moment a stun landed, so Giant Swing's
  wind-up broke under Steel Stance anyway. Locked wind-ups now ask `SimKits5.windup_breaks`.
* The old test that kept the five heroes out of the random pool now checks they are in it.

## Gates (numbers)
* Tests 273 passed, 0 failed: `logs/tests2.log` (new: `test_new5_data`, 4 Airah, 5 Burak, 4 Ser Emelrich, 4 Feran, 3 Ghorman tests,
  each checking the file's numbers at max level).
* Bots in real games (`tests/tools/kit_casts.gd`, 30 min, hard bots): every skill of every new hero cast
  (`logs/kit_casts2.log`, `kit_casts3.log` with the sides swapped). Swapped sides the new team won the kills 41-32;
  on the Dawn side it lost both games, the same side and Azrin as in the old line-ups.
* Visual checks in the real game (`shots/`): Airah (Hurricane tuned down after the first capture hid the fight),
  Burak, Feran, Ghorman (Beast Form swaps the body), Ser Emelrich's wind-up line and cone (`sheet_em.png`).
* Icons: 22 new, rendered with the game's own SVG loader (`icons/new_icons_godot.png`).
* `sh tools/check.sh`: no script errors, "Names OK" (`logs/check.log`). Export exit 0 (`logs/export.log`); cold
  starts of the exported build as Ghorman and Ser Emelrich, no script errors (`shots/export_sheet.png`).

## Chosen fill-ins (owner may veto)
* "Tailwind" added to the name checker's real-word list (it is a dictionary word, like "windward"; the checker
  flagged it as a wind compound).
* Blessing of the Beast King had no effect in the file: it heals the beast 30-60%, cleanses it, readies its spell and
  gives it +20-50% damage and +20-50 attack speed for 8 s (from the earlier session).
* Airah's talents (her section had none), Gust's drag strength (650 a second at the head, nothing at 420), cast
  points, Hurricane's damage every 0.5 s: from the earlier session, unchanged.
* Bot skill orders and talent picks for the five; Ghorman takes a point of Blessing at level 8.

## Not done / not verified
* Beast Form keeps its old body (its remnant counts 127+462 torn); it is now seen in every Ghorman game.
* No blind critic review; no benchmark comparison against Dota's own heroes beyond the rules named in the file.
* Feran's Upgrade Staff Swap (mark an ally, then swap it with an enemy) is in the sim but the bots never use it.
* The player can select and order Ghorman's beasts (right click, minimap, Stop, Hold, box select, control groups),
  checked by reading the code paths only, not clicked in a live match; beasts cast their own spell by themselves.
