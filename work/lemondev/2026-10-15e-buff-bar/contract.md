# Run 2026-10-15 e: buff bar

## The owner's request (2026-10-15, with a screenshot: a red box over the skill bar)

> You should also put all the Buffs and Debuffs for the specific unit selected in there. The player can hover over it
> to see what buff/debuff it is and there is a duration timer effect pretty much like cooldowns. Debuffs/buffs that
> stack will of course show individually. Auras both buff/debuff will show, etc etc. Status modifiers like Break,
> Armor Reduce, etc are considered debuffs so they should also show there much like Stuns and Slows. In other words,
> that location in the UI right there is our Buff/Debuff/Aura/Status container

## Component contract (frozen before captures)

| ID | Component | Owned files | Acceptance | Evidence |
|---|---|---|---|---|
| B1 | Effect data for the bar | `sim_unit.gd` (start stamp `t0`), `sim_status.gd` (`by`, burn `total`, `dots_on`), `sim_items.gd` / `sim_ai.gd` (aura flags), `sim_kits2.gd` (Charge is a debuff), `sim_data.gd` (`units()`) | Every timed effect knows its full length; auras are marked; refreshing an aura does not dirty stats; all tests pass | `test_buff_bar_entries`, full suite |
| B2 | Buff bar | `src/ui/buff_bar.gd` (new), `src/ui/hud.gd` (BottomPanel `_buff_bar`, hit test), `src/ui/ui_kit.gd` (neutral icons moved) | In the marked place over the skills for whatever unit the panel shows (hero, creep, courier); one icon per effect instance and per burn; buffs left, debuffs right; disables, slows, lowered stats, enemy auras, reveals and burns count as debuffs; hover shows name, source, effect, time left; a cooldown-like sweep on timed effects; no timer on auras; nothing overlaps the chips, stash or screen edge at 1080p and 4K; clicks on an icon give no world order; overflow is never silently dropped | `tests/tools/buff_probe.gd` (1080p + real 4K), captures in `shots/` |
| B3 | Names for every effect | `buff_bar.gd` tables, `tests/tools/modifier_census.gd` (new) | Every effect seen in three 30-minute 5 v 5 bot games with all eight heroes has a player-facing name (hidden internal marks excepted); "Names OK" | `census.txt` |

Benchmark: Dota 2's buff bar (buffs left, debuffs right, red rim on debuffs, a draining timer). No Dota reference
frames are on disk, so the comparison is by the description above and the owner's screenshot; blind review UNVERIFIED.
Budget: 8 passes per component.
