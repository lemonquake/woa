# Component contract: Blood Ranger, trees, tower scale (run 2026-10-12-blood-ranger)

Baseline revision: e4bfdc6. Engine: Godot 4.7.2 (Forward+), Windows, 1920x1080 target on RTX 4060.
Pass budget: 8 build/review passes per component (lemondev default). Plateau rule applies.

## Research (Dota 2 reference data, gathered before building)

Sources: Valve game data `work/research/d2_items.txt` (items.txt), Liquipedia wiki pages fetched through its API into
`work/research/{Trees,Quelling_Blade,Tango,Iron_Branch,Channeling,Lifesteal,Forced_movement}.json`, and the wiki's
game-constant template expanded via the API: tree respawn time 180, tree respawn radius 150, item lifesteal creep
factor 0.4, tree collision size 128.

| Rule | Value | Source |
|---|---|---|
| Destroyed trees regrow | 180 s; a tree waits while any unit stands within 150 of it | Trees page + constants |
| Quelling Blade (renamed Mini-Axe) | 100 gold; +8 melee / +4 ranged damage vs non-hero units; Chop Tree: range 350, cooldown 4 s, cast point 0 | items.txt + wiki |
| Tango (renamed Vegan Picker) | 90 gold, 3 charges; eats a tree within 165; 7 hp/s for 16 s, 32 s on a planted tree; refreshes, no stacking | items.txt + wiki |
| Iron Branch (Ironwood Twig) | Plant Tree: point, range 400, a planted tree for 20 s; the branch is consumed | items.txt + wiki |
| Channeling | Ended by any new order (move, attack, stop, hold, other casts), stuns, silence, roots, and disabling forced movement. Instant no-target items do not break it | Channeling page |
| Lifesteal | Heals from physical attack damage after reductions (the full blow even when it kills); not from spells; item lifesteal heals 40% against creeps; not against buildings | Lifesteal page |
| Forced movement | Non-disabling forced movement still lets the unit attack and turn, but not walk; move orders are kept | Forced movement page |

## Components

### C1 Tower scale (Asset)
Tower models 40% smaller (scale 0.6, tier growth kept). Health bar, crystal light and tower bolt launch height follow
the scale. Simulation footprint unchanged (hull 144).
Accept: a rendered lane capture shows the tower at about 2.3 hero heights, no gap or overlap artefacts at its base,
bolts leaving the crystal.

### C2 Destructible trees (System + Asset)
* Trees regrow 180 s after they fall (all causes), waiting while a unit is within 150. Regrowth animates in.
* Mini-Axe (`quelling_blade`) and Vegan Picker (`tango`) renamed everywhere players see them.
* Ironwood Twig can plant a 20 s tree (range 400); Vegan Picker on a planted tree lasts 32 s.
* Gale Impact's arrow and units it hurls destroy trees.
Accept: headless tests for regrowth timing, the stand-on-it wait, planted tree expiry and pathing/vision updates,
Mini-Axe / Vegan Picker rules; rendered capture of a fallen tree and a regrowing tree.

### C3 Blood Ranger (System + Asset), replaces Galewarden
Ranged agility hero (Galewarden's base stats), female. Numbers the user did not give are marked "chosen".
* Q Burst Shot: channelled, 17 s cooldown. 30 arrows in 5 waves, each wave a random 4-7 arrows (they sum to 30).
  Each arrow deals (55% + 10% per level) of her attack damage as physical damage. Target area: point, cast range 900,
  radius 400 (chosen); arrows strike random enemies in the area, or the ground when none. Channel 2.0 s, a wave every
  0.4 s (chosen). Ended by a move, attack, stop or hold order, another cast, a stun, silence or a push.
* W Gale Impact: a big arrow to the target point, at most 2000 range, 12 s cooldown. Enemies hit take 120 + 80 per
  level magic damage and are hurled sideways off the arrow's line; a hurled enemy that hits a wall, unit, building or
  tree takes another 20% of that damage. Trees on the arrow's path and trees units crash into are destroyed.
* E Masterful Archery: passive; an attack has a chance (30%, chosen) to deal bonus physical damage equal to
  (15% + 10% per level) of her agility (buffed from 8% on request); 0.8 s cooldown; burst effect on hit.
* R Blood Ranger: 15 s; lifesteal 40% + 10% per level and +200 + 100 per level attack range; while active each attack
  that hits her has a 30% chance to make her leap 300 backwards (away from the attacker). 30 s cooldown.
  Chosen: 1.0 s minimum between leaps so creep fire cannot chain them; the leap keeps her orders (non-disabling).
Accept: headless tests for every number and rule above (wave split, damage per arrow, every channel interrupt,
sideways push, impact bonus once, tree destruction, proc chance/cooldown, lifesteal, range, leap chance/ICD,
leap blocked by cliffs); rendered captures of each ability; bot plays the hero.

## Benchmarks (visual)
Dota 2 frames already in the project's benchmark set (`work/benchmark/`), used under the same blind A/B protocol
as earlier runs. Tower scale is compared against a Dota 2 lane frame that shows a tower beside heroes.

## Gates
Integration: `tools/check.sh` clean, full `tests/run_tests.gd` green, exported build cold start and a match smoke
test, capture review of new effects, benchmark run under the same conditions as the last measurement
(1080p, `--bench=60 --t=240 --autoplay`).
