# Run 2026-10-15 e handoff: buff bar

State: **IMPLEMENTED — UNVERIFIED** for blind visual review (no critic subagent asked for, no Dota frames on disk).
Mechanics and layout gates pass on the working tree (uncommitted).

## Evidence (working tree)

* Headless tests: 197 passed, 0 failed (196 + `test_buff_bar_entries`).
* `sh tools/check.sh`: no parse errors, "Names OK".
* `tests/tools/buff_probe.gd`, Azrin: 1080p window (1920 x 1017) 29/29; real 3840 x 2160 frame 20/20 with the three
  hover checks skipped (the frame is larger than the monitor, so the cursor cannot reach the bar; hover is checked at
  1080p). Captures: `shots/buffs_hero*.png`, `buffs_tip_debuff*.png`, `buffs_tip_buff*.png`, `buffs_many*.png`,
  `buffs_overflow*.png`, `buffs_creep.png`.
* `census.txt`: 56 effect kinds in three 30-minute bot games (all eight heroes, seeds 3, 7, 11), plus three burn
  kinds. All named except `hook_lock` (Sludge's own lock while the hook flies), hidden like Dota hides it.

## Passes

| Component | Pass | Verdict | Largest gap found |
|---|---|---|---|
| B1 | 1 | PASS (gate) | none |
| B2 | 1 | REJECT (self-check) | 27 effects: 6 silently dropped (three rows full) |
| B2 | 2 | REJECT (self-check) | centred seconds hid the icon art |
| B2 | 3 | PASS (gate; self-check look) | none |
| B3 | 1 | REJECT | Frenzy Mask's berserk, Blood Ranger's ultimate, Weapon Grab, Break Strike unnamed; Kragg's Charge counted as a buff |
| B3 | 2 | PASS (gate) | none |

## How it works

* `BuffBar.entries(u, w)`: the unit's modifiers (minus `HIDDEN`) and its burns, in arrival order; each entry has its
  name, icon, buff or debuff, aura or not, time left and full length, and a counter.
* Debuff test (`is_debuff`): any disable, slow, damage-taken or healing cut, reveal, the modifier's `debuff` flag
  (enemy debuffs, enemy auras, Charge), or stats that are all negative.
* Full length: `dur` when `SimStatus.apply` set it (after status resistance), otherwise `expires - t0`; `t0` is stamped
  by `SimUnit.expire_modifiers` on the first tick it is seen and changes no stat (it is ignored when a refresh compares
  keys). Auras have no timer.
* Layout: from the type chips' end (or the first skill) to 20 px short of the items, lowest row at 4 px above the
  console; buffs fill from the left, debuffs from the right, up to three rows; 32 px icons, then 28 and 24 when
  crowded; then each side's last slot becomes "+N" with a list.
* Names: own table (`NAMES`), then auras (items and creeps), creep attack effects, item actives named after their use,
  then the ability or item the id (or the id without `_slow`, `_stun`, `_armor`, `_curse`, `_aura`) belongs to.

## Resume

Rerun `tests/tools/modifier_census.gd` after adding any new modifier id; it exits 1 when one has no name.
