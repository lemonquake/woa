# Dota 2 neutral camps: current rules (research, 2026-10-13)

Current live patch: **7.41f** (Valve patch list, [V-list]). Names below are Dota's names, kept only for
reference; per CLAUDE.md the game must rename every one of them plainly.

Source keys are listed at the end. "Unconfirmed" means no source I could reach states it.
Liquipedia blocked direct fetches (HTTP 429), so I used the cached copy in `work/research/Neutral_Creeps.txt`
plus Wayback snapshots from March 2026 (post 7.40, pre 7.41). Fandom returned HTTP 402, so I used its Wayback copy.

---

## 1. Camps per side, by tier and place

### What the wiki says (7.38-7.39 layout, still on Liquipedia unchanged)
[L1] "Small: 4 spots, 2 dry + 2 flooded, one of each per side. Medium: 10 = 6 dry + 4 flooded, per side 3 dry + 2 flooded.
Large: 10 dry, 5 per side. Ancient: 4 dry, 2 per side." That is **14 camps per side, 28 total**, the same total as 7.33's
"16 → 28 camps" [GOSU]. "Flooded" camps sit in the streams (added 7.38) and evolve over time (section 2).

### Valve's tier changes since then (these override the wiki counts)
| Patch | Change (quoted or condensed from Valve notes) | Src |
|---|---|---|
| 7.40 | "The Hard camp nearest to Tier 3 towers where the streams used to start" demoted to medium | [V7.40] |
| 7.40 | "The Hard camp in the 'triangle'" demoted to medium | [V7.40] |
| 7.40 | Safe-lane flooded medium near T2 moved up the stream towards the base; hard camps near Wisdom Shrines moved back towards bases | [V7.40] |
| 7.41 | "Ancient neutral camps near stream ends demoted to medium camps" and moved towards bases | [V7.41] |
| 7.41 | "Medium neutral camp near offlane defender's gate" demoted to **small** | [V7.41] |
| 7.41 | Flooded medium near safe-lane T2 now evolves only once (to large); flooded medium near bounty runes evolves twice (to ancient) | [V7.41] |
| 7.41 | Safe-lane T1 towers moved slightly away from their pull camps; Radiant safe small camp moved north, away from the lane | [V7.41] |

### Derived 7.41 table, one side (Radiant; Dire is the rough mirror)
Counts are **derived** (wiki 7.39 counts + Valve deltas); no source gives a 7.41 per-side count, so the count is unconfirmed.
Place names come from Valve/Liquipedia notes that name each camp, e.g. "Radiant Safelane tier 1 hard pull camp" [V7.38b].

| # | Tier now | Kind | Rough place | Evidence |
|---|---|---|---|---|
| 1 | Small | dry | Safe lane, next to the T1 tower: the **small pull camp** | [V7.39], [V7.41], [L3] |
| 2 | Small (flooded, evolves → medium at 15:00, → large at 30:00) | river/stream | Outer rim stream on the safe-lane side, between T1 and T2 | [V7.38], [L1] |
| 3 | Small (was medium until 7.41) | dry | Near the "offlane defender's gate"; exact spot unconfirmed (the gates sit at the stream outside each safe lane near the base [V7.40]) | [V7.41] |
| 4 | Large | dry | Safe lane by T1: the **hard pull camp** | [V7.38b], [V7.41] |
| 5 | Large | dry | Main jungle, by the mid T1 tower | [V7.38b] |
| 6 | Large | dry | Offlane side ("triangle" area), near the Wisdom Shrine / offlane T1 | [V7.38b], [V7.40] |
| 7 | Ancient | dry | **Triangle** (offlane jungle) ancient; spawn box enlarged in 7.39d | [V7.39d], [V7.39] |
| 8 | Medium (was ancient until 7.41) | dry | Safe-lane side, at the stream end by the safe T1 tower | [V7.38b] "Dire Ancient camp by Safelane Tier 1 Tower", [V7.41] |
| 9 | Medium (was hard until 7.40) | dry | **Triangle** hard camp, demoted | [V7.40] |
| 10 | Medium (was hard until 7.40) | dry | Near the T3 towers where the safe-lane stream starts | [V7.40] |
| 11 | Medium | dry | Main jungle, between the mid and safe-lane T2 towers | [V7.38b] |
| 12 | Medium | dry | Main jungle high ground ("Jungle high-ground Medium camp") | [V7.38b] |
| 13 | Medium (flooded; evolves once → large at 15:00) | stream | Safe-lane rim stream near the T2 tower | [V7.38], [V7.41] |
| 14 | Medium (flooded; evolves → large 15:00, → ancient 30:00) | stream | Main jungle stream near the bounty rune (was a hard camp before 7.38) | [V7.38], [V7.41] |

One camp from 8-12 is the medium that 7.41 turned into the small camp in row 3. My count assumed one each. Derived per-side
total: **3 small, 7 medium, 3 large, 1 ancient = 14**. Unconfirmed: verify in a 7.41 lobby with ALT held.

Lane-creep pulls: Liquipedia says lane creeps only attack neutrals from the small camps and one large camp per side, "the
only ones that can be used to pull" [L1]. These are the safe-lane small and hard pull camps (rows 1 and 4). Whether lane
creeps also fight row 3 (new small camp since 7.41) is unconfirmed.

---

## 2. Camp compositions (unit counts)

A camp picks a random group of its tier each spawn. All groups have equal odds, and "a camp cannot spawn the same set of
neutral creeps twice in a row" [L1][F1]. Dry spots only get dry groups; flooded spots only get frog groups [L1].

| Tier | Group | Units (count) | Src |
|---|---|---|---|
| Small | Kobolds | 3 Kobold + 1 Kobold Soldier + 1 Kobold Foreman (5) | [L1], [F1] "kobold camp which consists of five units" |
| Small | Hill Trolls | 2 Hill Troll Berserker + 1 Hill Troll Priest (3) | [L1] |
| Small | Hill Trolls + Kobold | 2 Hill Troll Berserker + 1 Kobold Foreman (3) | [L1] |
| Small | Vhoul Assassins | 3 Vhoul Assassin (3) | [L1] |
| Small | Ghosts | 2 Fell Spirit + 1 Ghost (3) | [L1] |
| Small | Harpies | 2 Harpy Scout + 1 Harpy Stormcrafter (3) | [L1] |
| Small (flooded) | Pollywogs | 3 Pollywog | [V7.38] |
| Medium | Centaurs | 1 Centaur Courser + 1 Centaur Conqueror (2) | [L1] |
| Medium | Wolves | 2 Giant Wolf + 1 Alpha Wolf (3) | [L1] |
| Medium | Satyrs | 2 Satyr Banisher + 2 Satyr Mindstealer (4) | [L1] |
| Medium | Ogres | 2 Ogre Bruiser + 1 Ogre Frostmage (3) | [L1] |
| Medium | Golems | 2 Mud Golem; each splits into 2 Shard Golems on death (2 → 4) | [L1] |
| Medium (flooded) | Froglets | 2 Boglet + 1 Marshmage Apprentice | [V7.38] |
| Large | Large Centaurs | 2 Centaur Courser + 1 Centaur Conqueror | [L1] |
| Large | Large Satyrs | 1 Banisher + 1 Mindstealer + 1 Satyr Tormenter | [L1] |
| Large | Hellbears | 1 Hellbear + 1 Hellbear Smasher (2) | [L1], [F1] "come in pairs" |
| Large | Wildwings | 2 Wildwing + 1 Wildwing Ripper | [L1] |
| Large | Trolls | 2 Hill Troll + 1 Dark Troll Summoner (+3 skeletons raised when aggroed) | [L1] |
| Large | Warpines | 2 Warpine Raider | [L1] |
| Large (flooded) | Frogs | 2 Croaker + 1 Marshmage | [V7.38] |
| Ancient | Black Dragons | 2 Ancient Black Drake + 1 Ancient Black Dragon | [L1] |
| Ancient | Rock Golems | 2 Ancient Rock Golem + 1 Ancient Granite Golem | [L1] |
| Ancient | Thunderhides | 2 Ancient Rumblehide + 1 Ancient Thunderhide | [L1] |
| Ancient | Frostbitten | 2 Ancient Frostbitten Golem + 1 Ancient Ice Shaman | [L1] |
| Ancient | Prowlers | 2 Ancient Prowler Acolyte + 1 Ancient Prowler Shaman (returned in 7.38) | [V7.38] |
| Ancient (flooded) | Ancient Frogs | 2 Ancient Croaker + 1 Ancient Marshmage | [V7.38] |

Flooded camps evolve [V7.38][L1]. Every 5 minutes, one creep in each flooded camp is permanently upgraded one tier. The
chains are Pollywog → Boglet → Croaker → Ancient Croaker and Pollywog → Marshmage Apprentice → Marshmage → Ancient
Marshmage. A camp has 3 units, so a camp moves up one full tier at 15:00 and another at 30:00, and each creep can be
upgraded at most twice. Upgrades are not lost while a camp is blocked or stacked; the next fresh spawn uses them. A stack
cannot create extra evolved creeps [L1]. 7.41 caps the T2-rim flooded medium at large [V7.41].

---

## 3. Spawn timing and what blocks a spawn

* First spawn is at **1:00** game time. Every camp then respawns on the game-clock minute (2:00, 3:00...), not on a timer
  that starts when the camp is cleared [L1][F1]. Sources disagree: [T] claims 0:30, against both wikis and the cached
  Oct-2026 Liquipedia copy. Treat 1:00 as correct.
* The spawn only checks whether the box is empty. A camp "does not respawn when there are units present within the camp
  area" [L1]. So:
  * Its **own neutrals** standing in the box block it. That is why an untouched camp never doubles, and why stacking works
    by pulling them out [F1].
  * **Heroes, lane creeps, summons and wards** block it [L1][F1]. A pulled lane wave and neutrals still fighting in the box
    stop the next spawn [D].
  * **Invisible, hidden, invulnerable, true-sight-immune and untargetable units still block** [L1]; fandom adds "not even
    when the unit is invulnerable or hidden" [F1].
  * Units that do **not** block (7.4x list) [L1]: couriers, Astral Spirit, Power Cogs, Stone Remnant, Fiend's Gate, Largo's
    Frogling, Raptor, Jex, Psionic Trap, Skeleton Archer, Leviathan's Fish, Treant's Eyes, Roshan's Banner, Spin Web,
    Techies' Sticky Bomb / Minefield Sign / Proximity Mine / M.A.D. Beastmaster's hawks are also on the older list [L1-arch][F1].
  * "Only units can block camps. Spells cannot block camps" [F1]. Whether items on the ground block is unconfirmed
    (they are not units, so probably not). Illusions are not on the exempt list, so they should block (inferred, unconfirmed).
* The check happens **at the minute tick only**. "If the area is empty on the next minute mark", the creeps spawn [F1][L5].
  Anything standing in the box at x:00 blocks that minute's spawn.
* A yellow particle effect appears in every camp about 3 s before the minute, even in blocked camps [L1].
* Roshan and the Tormentors always spawn and cannot be blocked [F1].

## 4. Spawn boxes

* Hold **ALT** to see the spawn boxes as a **yellow outline** [L1]. They are rectangles: "a yellow, rectangular spawn area
  for each camp" [G], "rectangular" [T]. Fandom says this needs the ALT option to be enabled [F1].
* The box itself does not change colour when blocked: unconfirmed, and no source says it does. A **ward's placement
  indicator turns from yellow to red** while hovering over a spawn box, meaning the ward would block the camp [G].
* The boxes extend upward as well as across the map [L2], and each camp has its own box size. Valve tunes them per camp
  (e.g. "Reduced spawnbox size for both Dire hard camps" 7.02 [L3]; "Increased spawnboxes of Triangle Ancient camps" 7.39d
  [V7.39d]). No source gives sizes in units (unconfirmed).

## 5. Stacking

* **Stack** = pull the camp's creeps out of the box before x:00, so a new group spawns. The pulled creeps then walk back
  in [L1].
* Timing:
  * Liquipedia: "Most camps can be stacked at around the 54-55 second mark", depending on box size and units [L2].
  * Older Liquipedia guide: aggro "around XX:53 to XX:55" [L5].
  * Per-tier windows from [T] (claims 7.41d, low reliability): small :53-:55, medium :53-:54, large :52-:54, ancient :51-:53.
  * Adjustments [L2]: about 1 s earlier for a melee hero against a long-ranged camp (Vhouls, Trolls); about 0.25 s
    earlier for a short-range ranged hero.
  * The Ghost camp's 20% slow makes the small camp harder to stack [L2].
  * 7.39 shortened the "pull timers" of the flooded camps in the main jungle by the bounty runes [V7.39].
* Distance: no fixed number. All creeps must be outside the box at x:00. Neutrals chase until they are **400** from their
  spot plus **5 s** (section 7), roughly 1750-2200 range at most [L1].
* Multi-stacks: "There is no limit to how often a creep camp be stacked" [L1]. In practice it stops when you can no longer
  drag every creep out of the box [F1]. [T] says about 4 stacks is the usual practical ceiling (5-6 on ancients).
* Stack bounty (current):
  * The new creeps from a stack get a buff. They give **20% less gold and XP** to whoever kills them. The penalty rose from
    15% to 20% in **7.39e** [V7.39e][L1].
  * If an ally kills them, the stacker gets **30%** of the gold that ally got and 30% of the reduced XP [L1]. 7.33c added
    the XP share [F1].
  * Credit goes to whoever first drew aggro. Moving creeps with non-damaging forced movement, or lane-creep aggro alone,
    gives no credit [L1].
  * Fandom's 15% and [T]'s 35% are out of date or wrong.
  * A sound plays on a successful stack [L1].

## 6. Pulling lane creeps

* What a pull does: aggro the pull camp, then lead the neutrals into your own lane wave. Your creeps chase them into the
  jungle and die there. This resets the creep equilibrium and denies the enemy laners the XP and gold of that wave [L4][L5].
* Waves spawn every 30 s from 0:00 [L6], which is why pull times come in pairs (:15 and :45).
* Times (older map, verify in game):
  * Safe-lane small camp: **x:14-:17 or x:44-:47** [D, 2020]. Pull at :15 and the camp is cleared by about :45, so you
    can pull again next minute. At :45, the fight in the box blocks the next spawn [D].
  * Liquipedia: attack the camp "at the -:17 mark" and walk to the wave [L2].
  * Offlane large camp: **x:18-:19 / x:48-:49** [D].
  * [T] (7.41d): small x:17-:22, hard x:15-:20, on odd minutes.
* Map changes affect timings. Valve moved both safe-lane pull areas in 7.38c, 7.39 and 7.41 [V7.38c][V7.39][V7.41].
  No source gives exact seconds for 7.41: unconfirmed.
* Stack-and-pull: stack the small camp at about :55, then pull it at :15 [D]. One small camp often cannot kill a whole
  wave, which leaves a "double wave" in lane [L4].
* **Double pull / chain pull** ("connecting the pull"): when the neutrals are nearly dead, aggro the next camp (small →
  hard or medium) and lead the surviving lane creeps into it, so no lane creeps walk back [L4][D].
* How they fight [L1]:
  * Lane creeps only fight neutrals from the pull camps and ignore all other neutrals.
  * Neutrals always attack lane creeps.
  * Siege creeps rank below other targets for neutrals. Towers never attack neutrals.
  * Lane creeps get full XP credit when a neutral kills them; a deny gives 50% [L6].
* Counter-play: put a ward in the pull camp's box to block it [L5].

## 7. Aggro, leash and return (all from [L1], matches [F1] March 2026)

| Rule | Value |
|---|---|
| Aggro by walking close (day only) | within **240** (Roshan 140) |
| Aggro by damage or a single-target spell | from up to **1800** range |
| Nearby camp-mates join | neutrals within **500** of a damaged neutral |
| Guard distance (leash) | **400** from its own spawn spot |
| Chase limit | aggro drops **5 s** after leaving 400. The timer resets if it re-enters 400 |
| Effective max chase | about 1750-2200 range (400 + 5 s × 270-360 move speed) |
| After a leash | cannot be aggroed by proximity until it is back on its spot. Cannot be re-aggroed by damage for **3 s**. If re-aggroed while returning, the chase lasts only 3 s |
| Damaged by an invisible unit | that creep and neutrals within 500 **flee** to a random spot 750 from the camp for up to 5 s |
| Target turns invulnerable, ethereal or hidden | aggro drops at once. While walking back they still attack enemies within 500 |
| Night | neutrals sleep (aggro range 0). Damage or a single-target spell still wakes them |
| Disarmed | cannot be aggroed and casts nothing |
| Targeting | the closest enemy first. Special case: if a hero orders an attack on an enemy hero, the neutrals switch to the attacker |

* Area spells: "dealing damage to" a neutral aggroes it, so damaging AoE spells aggro too. Non-damaging forced movement
  does not [L1].
* Regeneration: neutrals only have base HP regen (e.g. 0.5 for Kobold, 2 for Black Dragon in the datamined `npc_units`
  [NPC]). Whether they heal fully on returning: unconfirmed. Liquipedia's leash section mentions no reset.

## 8. Bounty and stat growth over time

"Neutral Upgrade" passive on every neutral [L1][F1], running from the 0:00 horn:

| Every 7:30, up to 30 times | +30 HP, +0.5 armor, +3 base damage, +5 attack speed, **+1 gold, +5 XP** |
|---|---|
| Ability levels | creeps spawn with level 1 abilities until 14:59, level 2 from 15:00, level 3 from 30:00 |

* Existing and dominated neutrals get the stats at once. Ability level is fixed at spawn [L1].
* Gold is random between the unit's min and max. XP is fixed and split among all heroes within **1500**, enemies included [L1].
* No 7.40/7.41 note changes these numbers [V7.40][V7.41]. Since 7.40, lane melee and flagbearer creeps also gain +1 gold
  every 7:30 [V7.40].

## 9. How camps show on the map

* The minimap shows a tier icon for every camp [L1]:
  * small: a triangle
  * medium: a triangle with one bar
  * large: a triangle with two bars
  * ancient: a big triangle with an inner triangle
* The icons do **not** show whether a camp is empty, cleared or blocked [L1].
* In the world: the ALT spawn-box outline (section 4) and the yellow pre-spawn particles about 3 s before x:00 [L1].
  Sleeping creeps show floating "Z"s at night [L1].

---

## Sources
* [L1] Liquipedia, Neutral Creeps: https://liquipedia.net/dota2/Neutral_Creeps (local cache `work/research/Neutral_Creeps.txt`;
  Wayback 2026-03-04: https://web.archive.org/web/20260304224317/https://liquipedia.net/dota2/Neutral_Creeps). [L1-arch] = that snapshot.
* [L2] Liquipedia, Creep Stacking: https://liquipedia.net/dota2/Creep_Stacking (local `work/research/Creep_Stacking.txt`)
* [L3] Liquipedia, Map (version history 7.00-7.40): https://web.archive.org/web/20260311082119/https://liquipedia.net/dota2/Map
* [L4] Liquipedia, Creep control techniques: https://web.archive.org/web/20260325122248/https://liquipedia.net/dota2/Creep_control_techniques
* [L5] Liquipedia, Stacking#Pulling (redirect of Pulling, last edited 2018): https://liquipedia.net/dota2/Pulling
* [L6] Liquipedia, Lane Creeps (local `work/research/lane_creeps.txt`): https://liquipedia.net/dota2/Lane_Creeps
* [V-list] Valve patch list: https://www.dota2.com/datafeed/patchnoteslist?language=english
* [V7.38], [V7.38b], [V7.38c], [V7.39], [V7.39d], [V7.39e], [V7.40], [V7.41]: Valve patch notes,
  https://www.dota2.com/patches/7.41 (JSON: https://www.dota2.com/datafeed/patchnotes?version=7.41&language=english; swap the version)
* [F1] Dota 2 Wiki (Fandom), Neutral Creeps: https://web.archive.org/web/20260307185455/https://dota2.fandom.com/wiki/Neutral_Creeps
* [GOSU] GosuGamers, 7.33 jungle: https://gosugamers.net/dota2/news/67303-dota-2-patch-7-33-a-closer-look-at-jungle-gold-and-xp-with-the-12-new-neutral-camps
* [G] GamersDecide, How To Block Neutral Camps (2022): https://gamersdecide.com/articles/dota-2-how-to-block-neutral-camps
* [D] DotaFire, Support for Dummies (2020): https://www.dotafire.com/dota-2/guide/support-for-dummies-27966
* [T] Teamsmurf, stacking and pulling timings (claims 7.41d; a boosting-service blog with errors, low reliability):
  https://teamsmurf.com/stacking-and-pulling-masterclass-exact-timings/
* [NPC] Datamined unit file, local `work/research/d2_npc_units.txt` (version not stated)
