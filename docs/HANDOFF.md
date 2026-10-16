# Warriors of Aether: handoff

*A Dota 2-style lane battle game by Aljay Leodones. Godot 4.7.2 (Forward+), Blender 5.2 for building models.*

## Status (keep this section current)

**2026-10-17 c: Double-click self-cast and Azrael skill rework (your list).**
* **Double-click / double-tap self-cast** (`src/game/input_controller.gd`, `src/sim/sim_orders.gd`): double-clicking or
  double-tapping any targeted skill (`point`, `unit`, `autocast_attack`) or active item (`unit` or `point`) within 0.5 s
  while its targeting cursor is up casts it on the hero at once (`h` for unit targets, `h.pos` for point targets,
  `own_turret` for Pilot Turret), without requiring a turn for point self-casts. Town Portal (`tp`) keeps its
  double-click / double-tap teleport to the fountain.
* **Azrael's 1st skill (`soul_tap` - Soul Tap) rework** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_combat.gd`, `src/sim/sim_abilities.gd`, `src/sim/sim_bot17.gd`): changed to a **Toggle** skill. While
  toggled on, every 4.5 s Azrael scans a 600 area around her for souls (all living units including allies and enemies,
  excluding herself, buildings, wards, couriers and units inside a door). If there are no valid targets in range, no
  mana is spent and it continues scanning every 4.5 s; if there is at least one valid target (and she has 80 mana), it
  consumes 80 mana and grants +20/25/30/35 bonus attack damage per unit scanned plus +40 more per hero scanned for her
  next strike. That next attack deals **Pure** damage in a **100% cleave over a 400 area**, slowing the primary target
  and all cleaved enemies by **80% for 0.80 s**.
* **Azrael's 2nd skill (`door_of_the_end` - Door of the End)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_orders.gd`, `src/sim/sim_unit.gd`, `src/sim/sim_combat.gd`, `src/ui/buff_bar.gd`, `src/ui/hud.gd`):
  units inside the door can **prematurely step out** by issuing a move, attack or pickup order while inside (bringing
  that unit out at the exit, or entrance if no exit was set, without triggering the explosion). When the door explodes
  at the end of its duration, in addition to its 150/250/350/450 magic damage in a 450 area, it **heals nearby allies
  for 100/150/200/250**, **stuns all affected enemies for 1 s**, and **strips 10/16/22/28% of their Elemental
  resistances for 4 s** (`element_resist_loss`).
* **Azrael's 3rd skill (`death_scythe` - Death Scythe)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_combat.gd`): also **lifesteals 50%** of the damage done when it strikes; cooldown lowered to **1 s**
  (was 1.5 s).
* **Azrael's Ultimate (`divine_darkness` - Divine Darkness)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`): she
  moves **15% faster** at all levels while Divine Darkness is active.
Evidence: headless tests 244 passed, 0 failed (updated `test_azrael_data`, `test_azrael_soul_tap_charge_and_cleave`,
`test_azrael_door_of_the_end`, `test_azrael_death_scythe`, `test_azrael_divine_darkness`); live `input_probe.gd --
--hero=azrael --lvl=18 --nobot` 19 passed, 0 failed (including Soul Tap toggle on/off, quick cast, double-click skill
self-cast, double-click Push Staff self-cast, and Town Portal double-tap to fountain); `modifier_census.gd` 0 unnamed;
`python tools/check_names.py` "Names OK"; `build/WarriorsOfAether.exe` rebuilt 2026-10-17.
Names added (veto any): "Elemental resistance -N%" (buff tooltip / stat sheet line).

**2026-10-17 b: Azrael, talent trees, tree-felling spells, player labels, kill card, Bot Log, Blau's bot, Dota gap
report (your list).** Run `work/lemondev/2026-10-17-azrael/` (captures in `shots/`, Blender previews in `preview/`).
* **Talent trees for Blood Ranger and Ezee** (the two heroes without one). Their spells read the old way and ignored
  talents; they now go through `SimAbilities.val` / `_cv`, so talents and the Wide Stone family count. Blood Ranger:
  +10% Masterful Archery chance or +20 Attack Speed; +100 Gale Impact damage or +15% Burst Shot damage; +150 Blood
  Ranger attack range or -4s Gale Impact cooldown; +20% Blood Ranger lifesteal or +25% Masterful Archery damage.
  Ezee: +10 Strength or +60 Dark Stomp damage; +0.6s Dark Stomp stun or +50 Tainted Touch damage; -4s Leap Strike
  cooldown or +40% Leap Strike strength damage; +10% Unholy Might chance or +4s Unholy Might. Bots pick them.
* **Trees**: Fiery Javelin knocks down every tree on its path; Bounce Shot fells the tree it ricochets off.
* **Player names**: heroes read "lemonQ (Ezee)": the player in their player colour (Dota's ten slot colours, by team
  and order), the hero in its team's colour, over the health bar, in the kill feed, kill card, chat and scoreboard.
  Your own name is the name in Multiplayer settings (it starts as your Windows user name).
* **Kill card**: a hero kill shows both portraits sliding in, a blade slash across the fallen hero, a few sparks off
  the blade, a light sweeping the band and your gold counting up (First Blood, Shutdown and multi-kills as its title);
  2.8 s, shortened to 1.9 s while more kills wait. New kill-feed lines get a soft light running across them once.
* **Bot Log** (Debug panel, F9): per bot, thoughts, orders and whether its own thinking or a team call gave them,
  orders by kind, skills used out of ordered, items used, time in each mode, mode changes with the scores behind them,
  team calls, lines said, and its latest 24 steps; "Every bot" lists the summaries; **Save Bot Log** writes all of it
  to `user://bot_log.txt`. Headless: `bot_game.gd -- --botlog[=Bot Ann]`, `bot_duel.gd -- --log=A`.
* **Blau's bot** (the log showed it: 12 Bounce Shots in 14 minutes, 11 s fighting, lane/retreat flips every second or
  two): it pokes with every sure Bounce Shot (a pending last hit no longer stops a shot that passes the hero squarely),
  drops a turret on the enemy laner near its wave from level 6, goes for the kill with boulders, turret, shot and
  attacks when its spells and three seconds of attacks can finish the laner (not under a tower, not into more heroes),
  and its damage estimate counts the shot's usual two passes. **Every bot**: backing off from a stronger enemy now
  holds 2.5 s (or until it is 1400 away) instead of flipping back into lane the moment it steps out of 1000. Duels
  (12 min, 3 seeds, `blau_duels_before.txt` / `blau_duels_after2.txt`): deaths against Azrin 9 -> 3, Roydo 1-2 ->
  2-2 in kills, last hits against Ezee even (it was behind). Azrin still out-farms him.
* **Azrael, the Death Dealer** (your kit and numbers; melee 150, Dark): Soul Tap, Door of the End, Death Scythe,
  Divine Darkness as you wrote them (`src/sim/sim_kits4.gd`). How the open points were settled (veto any): Soul Tap
  counts every unit in the area but her (not buildings, wards, couriers); the charged blow cleaves with Dota's cleave
  cone (150 to 360 wide, 650 long) and ignores armor; recasting replaces the charge. Door of the End: she and allied
  heroes step in by walking onto the door (a move order ending there, or standing on it), two allies at most; inside
  they are hidden, invulnerable and cannot act; the second cast places the exit (no mana, no cooldown, castable from
  inside); with no exit placed they come out of the entrance; the blast is at the exit. Death Scythe works on her
  attacks and her spells' damage (not items), pseudo-random, 1.5 s apart. Divine Darkness: her night sight becomes
  her day sight, then +30/50/70%; enemies within 700 lose 30/40/50% of their sight; she flies straight over cliffs,
  trees and units and lands on open ground (felling trees she lands among).
  * **Look**: your female body (Azrin's) as a soul of white flame: a spirit mode in its shader (pale, glowing edges,
    flame rising through her, red eyes in darkened sockets, the legs gone below the hips), long white hair falling
    from a black hood, a long black robe, white soul fire streaming off the hem as she floats, motes and a cold light,
    red eye glints. The great scythe (carved dark shaft, leather wraps, old silver fittings, crescent blade with an
    etched band and a bright edge, a back spike) and the wings (white feathers, three jointed parts each, they open,
    beat and fold) are modelled in `tools/blender/azrael.py`. **Fixed after your report**: the blade faced the wrong
    way. Measured with `tests/tools/swing_dir.gd`: in her swings the head moves toward the weapon's +X, so the blade
    now points that way and its tip leads; the one backhand clip (gs_2) is left out of her attacks.
  * **Effects** (`src/game/azrael_fx.gd`): Soul Tap's crimson ring with a soul wisp flying from every unit to her and
    the crimson charge on her blade; the charged slash, a black-and-crimson crescent; a thin white crescent on every
    blow; Death Scythe's silver slash; the spirit door (a dark swirling void with white threads and red veins in a
    bright arch) at both ends, units fading in and out, the spirit blast; the wings with darkness pooled round her and
    a dark haze on blinded enemies. All particles and small shaders, freed with what they show.
  * **Bots** (`src/sim/sim_bot17.gd`): wings when a fight is on; Soul Tap where it gathers the most souls with the
    target among them, then the slash; in lane Soul Tap on the laner standing among its creeps; Door of the End to
    escape (a door at her feet, the exit toward safety) and, with the door at level 3+, to dive (the exit placed on
    the weakest enemy in reach in the last 0.9 s); Soul Tap on creep packs to cleave them; allied bots that are
    running walk into her open door. Duels (12 min, `azrael_duels*.txt`): she trades evenly with Ezee and Caziel in
    kills but out-farmed by them; Azrin wins the lane as he does against most heroes.
  * Chosen numbers (veto any): agility, str 19 (+2.2) / agi 22 (+3.0) / int 17 (+1.7), 27-31 damage, armor 1, 300
    speed, attack point 0.35; Door of the End mana 100-130, entry reach 110; Divine Darkness mana 100/150/200; cast
    points; talents: +25 Attack Speed / +6 Soul Tap damage per unit; +250 Health / +1s Door of the End; +8% Death
    Scythe chance / +40 Death Scythe damage; +150 Door of the End damage / -20s Divine Darkness cooldown.
* **Dota 2 gap report** (`work/lemondev/2026-10-17-azrael/dota_gap_report.md`): what the game has, the top 10 gaps
  (kill economy numbers, ward stock, the Attribute Bonus and talent points, Roshan, Upgrade Staff and Gem for 8 of 10
  heroes, illusions, Smoke and Scan, control items and effects, neutral items, the 7.38-7.41 map layer) and tables by
  area with Dota's numbers and sources. Its numbers are from the Fandom wiki and patch summaries (Liquipedia rate
  limited); see its last section for what could not be confirmed. Nothing in it is implemented yet.
Evidence: headless tests 244 passed, 0 failed (new: Blood Ranger and Ezee talents, Fiery Javelin and Bounce Shot fell
trees, Azrael data, Soul Tap charge and cleave, Door of the End (two allies, free exit, blast, no exit), Death Scythe
(pure, 1.5 s apart, not items), Divine Darkness (sight, blind, flight, landing), Blau hunt, Bot Log counters); every
test world now starts with the whole forest; `sh tools/check.sh` no parse errors, "Names OK"; a 20-minute 5 v 5 bot
game with two Azraels and two Blaus (`bot_game.txt`): no script errors, no hang (224 s), both Azraels used all four
skills (Soul Tap 18 and 31, Door 3 and 4 doors, the wings 3 and 5 times); captures `shots/` (kill card, Hero
Select, look variants, Soul Tap, the slash, the wings, the door, the swing sheet); `build/WarriorsOfAether.exe`
rebuilt 2026-10-17 04:01, cold start into a match as Azrael, no script errors (`shots/export_azrael.png`).
Not verified: no blind critic review (none asked for); the look and every effect are builder self-checks, not
compared with a commercial reference; the door shows its entry only to her team and to enemies who see the spot.
Names added (veto any): the talent names above; Bot Log, Save Bot Log, Every bot, "Going for <hero>." (bots),
"Opening the door.", "Into the door.", "No escape from me." (Azrael's bot lines), "Inside the door", "Cannot place a
door there" (cast errors). New owner names recorded in `lemondev/references/naming.md`.

**2026-10-17: Monitor option.** Options > Video has a new first row, **Monitor**: "Main monitor" (the one Windows
calls main, the default) or "Monitor 1 (1920 x 1080)", "Monitor 2 ..." for each plugged-in screen. The game opens on
that screen at boot and moves there at once when you change it, in every window mode; if the chosen monitor is
unplugged it falls back to the main one. A window you drag to another screen stays there until you change the choice.
Saved as `monitor` in `user://options.json` (`src/core/options.gd`, `src/ui/options_panel.gd`).
Evidence: on this PC (two 1920 x 1080 screens) a live probe moved the Fullscreen window to screen 2 and back (window
reported on the wanted screen each time); capture of the Video tab (`work/shots/monitor/options_video.png`);
parse check clean, "Names OK". `build/WarriorsOfAether.exe` rebuilt 2026-10-17 00:32; cold start to the menu, no
script errors. Not verified: Borderless and Windowed moves (same code path), no headless test (needs real screens).
Names added (veto any): Monitor, Main monitor, "Monitor N (W x H)".

**2026-10-16 b: your mechanics list.** Run `work/lemondev/2026-10-16b-mechanics/`.
* **Grip of the Ruler** needs someone to throw: on an area with no unit it does not go off, says "No valid target",
  keeps the targeting cursor and spends no mana or cooldown (also checked again when the cast point ends). It now
  seizes units hidden in the fog, but never an invisible enemy (unless your team has True Sight on it).
* **Town Portal double tap**: T twice within 0.5 s, or two clicks on the Teleport slot, teleports to your fountain
  (the usual 3 s channel).
* **Bots push** in lane when no enemy hero is near (none seen within 1600 in the last 3 s): they kill the wave (last
  hits first, then the weakest creep) and hit the tower while one of their creeps tanks it, from the start of the game
  (a support next to its core leaves the creeps to the core). **Ahead in net worth** (10% or more, gaps under 1000 gold
  ignored): bolder: lower retreat bar, fights taken on smaller chances, trades more often, kills chased on smaller
  leads, the lane push also with an enemy known nearby but out of sight, and a team 20% ahead calls pushes from 10:00
  ("We're ahead in gold. Let's push ...").
* **Blau**: Bounce Shot flies 400 further after every ricochet (aim line and bots include it). Summon Boulders rolls
  toward the point you click, as far as it, 200 at least and 700 at most (cast range 700, cast from where he stands);
  no boulder rolls past that distance. They rest within 2.5 s (was 1-2 s).
* **Switch Boots** (Power Treads): three icons for the attribute they are set to, in the inventory, backpack, stash,
  courier, drag and on the ground: red boot with a fist (strength), green boot with a feather (agility), blue boot
  with a star (intelligence). The shop keeps the old icon. `tools/item_icons.py`, sheet `treads.png`.
* **Unfair bots** (your numbers): +200% gold (bounties and passive gold) and +50% experience (was +25% of both); melee
  Unfair bots buy a Jump Knife right after their boots. Every bot with a Jump Knife (melee, not Sludge, who has his
  own) now jumps onto the enemy hero it fights from 300-1100 away when healthy, not onto an enemy tower unless the
  target is nearly dead and not into more enemies than allies; escapes with it as before.
Evidence: headless tests 235 passed, 0 failed (new: grip with no target, fog and invisible; bounce reach; boulders at
300 / 700 / 2000; Unfair gold, xp, passive gold; Unfair knife plans; jump-in; pushing alone and not with a hero near;
tower hits early; net worth lead; Switch Boots icons); `sh tools/check.sh` no parse errors, "Names OK"; live
`input_probe.gd` as Roydo 15/15 (grip on empty ground keeps the cursor, HUD shows "No valid target", nothing spent;
T, slow T, double T: the hero arrives at the fountain) and as Blau 17/17. 20-minute 5 v 5 bot games (`bot_game_*.txt`):
Hard seed 3 and Unfair seed 7: no script errors, no hangs; Unfair: every melee bot bought a Jump Knife, team net worth
88559 / 82991 at 20:00 against 19634 / 21034 on Hard. Same seed before the change (`bot_game_before.txt`): towers
lost 4 and 3 after, so pushing in real games is not shown to be stronger yet (one seed). `build/WarriorsOfAether.exe`
rebuilt 2026-10-16 22:19; cold start into a Blau match 20 s, no script errors (`export_blau.png`).
Not verified: no blind critic review (none asked for); the new icons are a builder self-check.

**2026-10-16: two new heroes, Roydo and Blau (your kits and numbers).** Run `work/lemondev/2026-10-16-roydo-blau/`
(contract.md, sources.md; captures in `shots/`, frame sheets in `preview/`).
* **Models**: free CC0 Quaternius packs (Universal Base Characters, Universal Animation Library 1 and 2, Modular
  Character Outfits - Fantasy, Sci-Fi Essentials Kit; list and upload ids in `sources.md`), built by
  `tools/blender/heroes16.py` into `assets/characters/heroes16/`. Roydo: an obsidian-skinned alien with a star-field
  skin shader (`src/game/roydo_skin.gdshader`) and a second, hulking monster body for the Anomaly (swapped in and
  out). Blau: a hooded gunner in a recoloured ranger coat with a scout sniper rifle held in both hands; his turret is
  the kit's four-legged Quad Shell walker. Animations come from the library clips (motion-captured style), not the
  procedural set: audit `anim_pops16.txt`: no joint flips (> 90 degrees in one frame) and no elbow or knee bent
  backwards in any clip used; 85 fast turns of 45-60 degrees remain in the quickest swings, get-ups and knockbacks.
* **Roydo, the Anomaly** (melee, intelligence): Grip of the Ruler, Void Rush, Dark Matter Skin, Anomaly as you gave
  them. **Blau, the Master Tactician** (ranged 600, agility): Bounce Shot, Summon Boulders, Lay Trap, Place Turret;
  the turret's shots carry his attack effects. Pilot Turret comes with the Upgrade Staff (Dota's Aghanim's Scepter).
* **Bots** (`src/sim/sim_bot16.gd`): Blau traces two dozen Bounce Shot angles through the trees, walls, boulders and
  units round him and fires the one that passes enemy heroes most; boulders roll ahead of a fleeing target to wall it
  in, or into a melee hero on top of him; when chased he faces the chaser so Lay Trap's leap leaves the snare in its
  path; turrets go down in every fight and in front of towers he pushes; with the Upgrade Staff he climbs into a turret
  when hurt. Roydo opens with Void Rush (lower status resistance makes the stun last longer), then Grip of the Ruler
  centred between the target and him, Anomaly once a real fight is on, Void Rush's speed to run. Every bot knocks down
  enemy turrets.
* **Chosen fill-ins (veto any)**: base stats: Roydo str 21 (+2.6) / agi 18 (+1.8) / int 24 (+3.2), 28-34 damage,
  armor 2, 305 speed; Blau 18 (+2.0) / 23 (+3.1) / 18 (+1.8), 22-28 damage, 295 speed, 3000 projectile. Mana: Void
  Rush 80-110, Anomaly 100/125/150, Bounce Shot 90-120 (12/11/10/9 s), Summon Boulders 100-130, Lay Trap 50-65,
  Place Turret 100/125/150. Bounce Shot damage 70/110/150/190, travel 1800 at 2400. Boulder cast range 600, roll
  speed 520-760. Trap: lasts 25 s, 110 trigger radius, arms after 0.6 s. Place Turret a 3-level ultimate, damage
  25/30/35% (+5% with the Upgrade Staff, so 40% at level 3). Pilot Turret 250 range. Anomaly projectile 1200.
  Talents as listed below.
Evidence: headless tests 225 passed, 0 failed (new: Grip target order, toss and stun, ally unharmed; Void Rush both
sides; Dark Matter Skin; Anomaly attack time, damage, range and the return to melee; Bounce Shot reflections off a
tree, wall, boulder and ally, passing enemies, bounce cap, two hits per enemy; boulders count, roll, blocking phased
units, one hit and push; trap leap, root and durations; turret range, interval, share of the attack with procs,
health, no regen, life; Pilot Turret needs the staff, health, safety, exit, cooldown; bots banking Bounce Shot,
trapping on escape, turret and pilot, Rush then Grip, bots knocking down turrets).
* **Found and fixed at integration: games froze once a Roydo bot used Anomaly in a lane.** In Anomaly he attacks at
  range, but as a melee hero he has no projectile speed of his own; the bots' last-hit forecast divided by it, got an
  infinite time and looped for ever (`sim_bot.gd` `_last_hit_target` / `_hp_when`). It now uses the form's projectile
  speed (`SimUnit.projectile_speed()`), and `_hp_when` caps an infinite time. Found with the new
  `tests/tools/stall_probe.gd` (prints slow steps and can trace each step); regression test
  `test_bot_roydo_anomaly_last_hit_forecast` (fails on the old line, passes now). This is why the interrupted
  session's Roydo duels and bot game never printed a result.
Bot duels, 12 min, 3 seeds each, after the fix (`duels_final.txt`; kills summed, last hits per seed): Roydo vs Ezee
1-0 (LH 42-48 against 11-30), vs Sludge 0-1 (27-34 against 18-32), vs Blood Ranger 2-3 (33-43 against 22-37), vs
Kragg 1-2 (Roydo far ahead in one seed, behind in the other two). Blau before the fix (`duels.txt`): vs Ezee 1-1, vs Kragg 0-2, vs Azrin 0-12. A 20-minute
5 v 5 bot game with two Roydos and two Blaus (`bot_game.txt`): ran to time in 178 s, no script errors, 39-24 kills;
one bot stuck (Roydo, from 11:19, a known issue). `sh tools/check.sh`: no parse errors, "Names OK".
Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-16 20:03 with the fix; cold start into a Blau match 12.6 s and a
Roydo match 12.5 s, no script errors (`shots/export_blau.png`, `export_roydo.png`). Blau vs Roydo (after the fix):
1-1 in kills, but Roydo out-farms him (LH 34-53 against 17-24).
Not verified: no blind critic review (none asked for, no Dota frames on disk); the look of both heroes and every
effect is a builder self-check (`shots/`). Left: in the trap capture a rooted creep's timer reads "Rooted 0.0" on its
last frame; Blau's bot loses his lane against Azrin and is out-farmed by Roydo in bot duels.

**2026-10-15 h: lane creep and unit animations repaired (follow-up to g).** Run `work/lemondev/2026-10-15h-unit-anims/`.
* The 16 humanoid unit models (lane knights and mages, Black Sun's ghouls, necromancers and chieftains, both siege
  golems, goblins, orcs, the troll, the ogre, the imp and the magma golem) played the same broken library clips as the
  heroes. `tests/tools/anim_repair.gd -- --units` now repairs each model's clips on its own rig, keeping hands and
  blades out of a body measured from that rig (shoulder width and height) and using the weapon the unit holds; one
  library per model in `assets/characters/units/anim_fixed/`. `RepairedClips` (was HeroAnims, now
  `src/game/repaired_clips.gd`) loads the right set for every model in matches, menus and the Hero Creator. The
  hand's speed limit now moves it on an arc round the shoulder (a too-fast slam swings forward and down instead of
  cutting through the chest); the hero clips were rebuilt with it too.
* Audit (`anim_audit.gd -- --units`): 188 findings on the original unit clips (bones flipping up to 180 degrees in one
  frame) -> 44 after; the largest turn left in one frame is 68 degrees. Heroes: 85 (was 86 in g), largest 73.
  Before/after sheets: `units_before_after.png`, `big_units.png` (golem and ogre slams).
* The lane knight's shield is strapped along its forearm at 80%, as Kragg's.
* Fixed an older bug the audit found: four units named attack clips their models do not have, so the hill troll
  attacked with no animation at all. Now: hill troll `axe_1` / `axe_2` (an overhead throw), ogre `boss_slam` /
  `gs_1`, goblin foreman and necromancer `staff_1` / `cast_quick`.
Evidence: headless tests 208 passed, 0 failed; `sh tools/check.sh` no parse errors, "Names OK"; a live match with
the repaired unit clips loaded, no script errors; `build/WarriorsOfAether.exe` rebuilt 2026-10-15 22:13 (the 16 unit
sets inside), cold start into a match in 24 s, no script errors.
Left: the knight's shield edge still touches its thigh in some sword frames (as Kragg's), staffs of the lane mage and
orc shaman pass the body in 12-28% of frames of their staff swings, golem and ogre slams show the elbows pointing
up in a few frames at the top of the swing (arms straight overhead, where "natural" is ill defined); no blind review.

**2026-10-15 g: Kragg rework, varied bot picks, smarter bots, animated title and new Main Menu, hero animations
repaired (your list and your report on the twisting limbs).** Run `work/lemondev/2026-10-15g-kragg-bots-menu/`
(contract.md; captures in `shots/`, `anim_before/`, `anim_after/`, `compare/before_after.png`).
* **Kragg** (your numbers): **Magnetize is his innate**: learned at level 1, no point, no slot; it shows in the small
  innate slot, in the Talents button's tooltip and at the head of the open talent tree. Attacks give a Charge (up to
  4, 8 s); each Charge makes the enemy take 0.10% + 0.05% per hero level more damage from his spells (level 30: 1.6%
  a Charge). I read "+0.05 per hero level" as times his level (level 1 = 0.15%); say if it should start at 0.10% at
  level 1. **Overload is passive**: every 6th / 5th / 4th / 3rd attack bursts round him: enemies within 200 take
  60 / 75 / 90 / 105 magic damage of the Lightning element and are slowed 80% for 0.8 s; his buff bar counts the
  attacks. Kragg now has four skills (Q W E R). Talent "+25 Overload damage per Charge" became "+40 Overload damage".
  Bot duels after the change (12 min, 3 seeds each, kills summed): Kragg vs Ezee 6-0, vs Caziel 8-4, vs Blood Ranger
  5-6, vs Sludge 1-4, vs Azrin 1-9 (`duels.txt`): no longer the strongest laner.
* **Varied picks**: Random slots are filled after the chosen ones; a team never gets a hero twice while another is
  free, prefers heroes nobody in the match has, and prefers ones that fill a missing role (single player and
  lobbies). Test: 300 seeds, no team duplicates, no hero three times in a match.
* **Smarter bots**:
  * Items (`sim_bot_items.gd`): every 30 s from 5:00 and after each death a bot reads the enemy team (magic, physical
    and pure damage weighted by how far ahead each enemy is, stunners, invisible heroes, evasion) and what killed it
    (damage by type in its last deaths, fading), and moves one counter item to the front of its build: magic
    resistance or Spell Shield against magic and stuns, armor or evasion against fed right-clickers, Sure Hit Staff
    against evasion, Jump Knife / Push Staff / Slip Boots after dying caught alone; supports get Fade Cape, Medic Kit,
    Guard Boots. Reveal Dust and Reveal Ward against invisible heroes. One counter at a time until bought. In the base
    late with every slot full it sells its cheapest early item. New uses: Fade Cape and Push Staff to save an ally
    being brought down, Reveal Dust on an enemy that just faded, Spell Shield when a stunner chases it.
  * **New items** (Dota 7.41d): Scarf (Shawl, 450, 10% magic resistance), Spell Cloak (Cloak, 900, 18%), Fade Cape
    (Glimmer Cape, 2150: 20%; on an ally or itself: invisible after 0.5 s for 5 s, 20% faster, a 375 magic-damage
    barrier). In the shop (Armaments / Upgrades) with icons.
  * **Counter-ganks** (`sim_team_ai.gd` `_call_saves`): an ally caught by enemy heroes is not left to run: the brain
    weighs the gankers against the victim plus every bot that can arrive before the victim would die (walking, or a
    Town Portal after 10:00), and when that fight is in our favour calls a save: helpers come, the victim runs toward
    them (pulling the gankers in), then everyone turns on the same ganker. Chat: "Hold on, <name>! Coming." / "TP
    coming", "Running to you, help me turn on them."
  * **Jukes** (`sim_bot_tactics.gd`): a bot on the run picks spots 350-800 away that a tree line or high ground hides
    from its chasers (where they were last seen; no peeking into the fog), among trees, out of the enemy's sight; once
    the enemy has not seen it for 2 s and nobody is in sight, it teleports home from the fog (hurt, or short of mana;
    before 8:00 only when badly hurt). "Lost them in the trees, going home."
  * Two 45-minute 5 v 5 bot games (`bot_game.txt`; the counters below were measured before three fixes from these
    games: no juke teleport before 8:00 unless badly hurt, no Town Portal saves before 10:00, one counter item at a
    time): no script errors; per game and team 33-58 counter-ganks called, helpers fought in 32-72 of them, 4-9 juke
    teleports home; counter items bought as above. No winner at 45:00 in either game (kills 92-33 and 93-31 for the
    same side, a lopsided lineup). Old issue still there: a few bots stuck (1-3 per game).
* **Title and Main Menu** (your request): an animated title the first time the menu opens: the gold sun of Ancient
  Light and the black sun of Black Sun rise either side, sparks drift up, the title burns in and a light sweeps across
  it, "by Aljay Leodones" is written out between gold rules, then "Press any key". The menu is remade with new art
  from `tools/ui_skin.py`: a hanging banner with the title and an emblem of the two suns, the menu as blade-shaped
  plates (gold for Play) that slide in one by one and light up on hover, a framed nameplate for the hero on the stage
  with Choose Hero, and a footer with the credit and rotating tips. Up / Down and Enter work too. Captures at 1080p
  and a real 3840 x 2160 window (`shots/title_*.png`, `menu_after.png`, `menu_4k.png`, `menu_hover.png`).
* **Hero animations (your report)**: measured, not guessed. `tests/tools/anim_audit.gd` checks every clip each hero
  plays, frame by frame. On the clips as built (they come from the beyond-heroes procedural library, and the lane
  knight has the same faults, so they are in the library, not the hero body) it found elbows flipping to the other side
  of the arm and forearms spinning up to 177 degrees between two frames 1/30 s apart, wrists bent up to 154 degrees,
  forearms twisted 130, and Kragg's shield and sword through his body: 352 findings over the eight heroes.
  `tests/tools/anim_repair.gd` solves every arm again (hand path kept, elbow continuous and within a natural range,
  forearm twist where a real arm turns, wrist clamped, snaps speed-limited, hands and blades kept out of the body;
  Sludge gets his own set solved round his belly) into `assets/characters/hero/hero_anims_fixed*.res`, which
  `HeroAnims` lays over the built-in clips in matches, menus and the Hero Creator. After: 86 findings, no flips (the
  largest turn left is 76 degrees in one frame, most leftovers 45-66 in the fastest swings), Blood Ranger 1, Sludge 3.
  Kragg's shield is strapped along his forearm at 80% (it sat on his fist and covered his face) and his stage idle is
  `idle_shield` (the hands-on-a-planted-sword idle put the blade through his chest). Your beyond-heroes repo was not
  touched (it had your uncommitted work).
Evidence: headless tests 208 passed, 0 failed (new: Kragg innate and Overload, varied picks, magic defence items,
bot counter items, juke spots and juke teleport, counter-gank calls); `sh tools/check.sh` no parse errors, "Names
OK"; `tests/tools/kragg_probe.gd` 11/11 at 1080p, 8/8 at 4K (3 hover checks skipped there: frame larger than the
monitor); audit files `anim_audit_before.txt` / `anim_audit_raw.txt` (352) and `anim_audit_final.txt` (86).
Not verified: no blind critic review (none asked for); the bot game counters predate the three fixes above;
animations still left: the lane creeps' clips (same library faults) are not repaired yet, Froster's staff passes
through his body in about 6-22% of frames in three casts, Kragg's shield edge touches his thigh in some attack
frames, Caziel's spin attack (`dual_4`) turns his whole body 61 degrees in one frame.

**2026-10-15 f: regen readout, Rejuvenation Orb, tower shots, Fortify, courier, Fast Forward (your list).**
* **Regen readout**: each bar shows the total per second, large, at its right end (+43.5); at its left end, how it adds
  up: own + bonus (3.5 + 40.0), and a healing cut as its own red term (3.5 - 2.1). Nothing to add: the total alone.
  Hover a bar: "Regenerates 43.5 per second", "Own 3.5 + bonus 40.0", the cut if any, "Full in 6 s at this rate".
* **Rejuvenation Orb** (your name; was Water Orb): already came only at 2:00 and 4:00, and a test now holds it to that
  (none to 30:00). New look: a bright purple heart in a glassy rim-lit shell with a turning halo and motes.
* **Tower shots**: Ancient Light fires a lance of sunlight (white-hot core, gold sheath, gold trail) that strikes with a
  spike of light, gold sparks and a small ring; Black Sun fires a small black sun with a crimson corona (it faces the
  camera, so it reads as an eclipse from any angle) that swells and collapses on impact, bursts crimson and cracks the
  ground. Fortified shots are a third bigger.
* **Fortify**: every building of the team stands in light while it lasts: Ancient Light a gold shell with light rising
  through it, a beam from the sky and a turning halo; Black Sun a shadowy violet veil with a crimson rim and a black sun
  over the roof. Both fade in and out. Tier 2+ towers meanwhile: splash 300, shots 50% faster, Fortify Mark (15 s,
  each adds 50 physical damage to their shots; it shows in the buff bar). This replaces Dota's "5 extra targets" (say
  if you want both). Allies see "<name> used Fortify" in the kill feed and a note over the panel. A team of bots
  presses it for a building in danger; a team with a human leaves it to the humans. The button's tooltip no longer
  blinks (it vanished between the minimap's redraws because the button is outside the minimap's rectangle).
* **Courier**: 290 + 20 speed per hero level; flies straight over trees, cliffs and walls from its hero's level 6.
* **Fast Forward**: no more faster cooldowns; it takes 2 / 3.5 / 5 / 6.5 s off the target's basic spell cooldowns at
  once (not the ultimate, not items) and keeps its 5 s speed boost. Talent: "+1.5s Fast Forward cooldown cut".
Run `work/lemondev/2026-10-15f-regen-fortify/` (contract.md, handoff.md). Evidence: headless tests 200 passed,
0 failed (new: Rejuvenation timing, Fortify splash / marks / speed, bot Fortify, updated courier and Fast Forward);
`tests/tools/fortify_probe.gd` 14/14 at 1080p (the Fortify tooltip up on 60 of 60 frames while hovered) and 12/12 in a
real 4K frame (two hover checks skipped there: frame larger than the monitor); a 45-minute 5 v 5 bot game (`bot_game.txt`): bots pressed Fortify 10 times (5 each side, from
12:28), no script errors, no winner at 45:00 (Black Sun far ahead; earlier games ended at 50-60 min, and stronger
Fortified towers may lengthen them: watch this); "Names OK"; `build/WarriorsOfAether.exe` rebuilt 2026-10-15 15:14, cold start into a Kragg match in 9.8 s,
no script errors (`shots/export_f.png`). Not done: blind critic review.

**2026-10-15 e: buff bar (your request and screenshot).** The place you marked over the skills now shows every buff,
debuff, aura and status on the unit the bottom panel shows (your hero, an ally, an enemy, a creep, a tower, your
courier). Buffs sit on the left with a green rim, debuffs on the right with a red rim, like Dota. Each instance is its
own icon (Stench from two Sludges is two icons, every burn is its own); Kragg's Charges show their count. Timed
effects darken clockwise as they run out, like a cooldown, with the seconds along the bottom; auras have no timer and a
thin inner rim. Hover: name, buff or debuff (or ally / enemy aura), who applied it, what it does ("Moves 20% slower.",
"-5 armor.", "Broken: its passive abilities do nothing."), time left of its full length, and whether a dispel removes
it. Debuffs include stuns, slows, silences, roots, disarms, hexes, mutes, Break, lowered stats (armor and attack speed
loss), more damage taken, healing cuts, reveals, burns and enemy auras. When a row fills it grows upward (three rows),
then the icons shrink, then each side's last slot becomes "+N" listing the rest. Clicking an icon gives no move order.
The creep panel's old small status icons are replaced by the bar. Run `work/lemondev/2026-10-15e-buff-bar/`
(contract.md, handoff.md). Evidence: headless tests 197 passed, 0 failed (new `test_buff_bar_entries`);
`tests/tools/buff_probe.gd` 29/29 at 1080p and 20/20 in a real 4K frame (hover checked at 1080p only: the 4K frame is
larger than this monitor); `tests/tools/modifier_census.gd` (three 30-minute bot games, all eight heroes): all 56
effect kinds seen have names except Sludge's own hook lock, which is hidden as in Dota; "Names OK". Captures in the
run's `shots/`. Not done: blind critic review (none asked for); the exported build was not rebuilt.

**2026-10-15 d: cast range fixed (your report).** Long Lens and other cast range bonuses now reach everything that
should grow: spell cast ranges (talents and upgrades that change a spell's range count too; they were ignored), line
shots' reach (hook, arrow, javelin), Leap Strike's search radius and Jump Knife. The targeting ring showed the bare
range (and unit spells showed your attack range): it now shows the real cast range, and the ability tooltip says
"Cast range N (+bonus)". Stacking (your rule): copies of one item add half as much each (two Long Lenses +337.5),
Blast Rod levels count as one source, different sources add fully. Rules: `docs/MECHANICS.md`, "Cooldowns, spell area,
cast range". Evidence: headless tests 196 passed, 0 failed (new `test_cast_range_stacking_and_reach`); input probes
Sludge 12/12, Kragg 8/8; "Names OK"; `build/WarriorsOfAether.exe` rebuilt (below).

**2026-10-15 c: performance in teamfights, bot laning / teamfights / ganks / pushes, more learning, Quick cast.**
Run `work/lemondev/2026-10-15c-perf-feel-ai/` (contract.md: request, components, conditions; handoff.md: tools and
file map). Evidence on the final working tree:
* **Teamfight frame time** (a new real teamfight bench: ten heroes at level 16 with items brawling in mid at 10:00,
  ~220 units, 1080p, RTX 4060, V-Sync off; three alternating runs each against `81efd48` plus the same bench harness,
  `bench_ab_final.txt`): average **41 -> 48 fps** (24.2 -> 20.7 ms), p95 39 -> 33 ms, p99 53-61 -> 41-43 ms, worst
  frame 102-134 -> 61-66 ms, script errors ~510 per run -> 0. This is better, not "perfect": a full level-16 brawl is
  still under 60 fps on this PC (what is left, per frame: the 30 Hz simulation tick ~8 ms when it runs, engine
  deferred work ~5 ms, drawing ~6 ms). A background process (`UninstallMonitor`, not ours) held one CPU core all session.
* Simulation in that fight (headless `sim_profile.gd --fight`): ticks over 15 ms in two minutes 24 -> 2, worst tick
  30 -> 17 ms, mean tick 5.1 -> 4.7 ms.
* **Bots**: lone last hits in 8 minutes of mid (`lh_lab.gd`, five heroes): 17-31 -> 37-47. Teamfight A/B (mirrored
  lineups, team engage on for one side only, sides swapped, 8 games): the side with it ahead in net worth 6 of 8
  (average +4.5k) and kills 5 of 8 (+4.9). **Games end now: 3 of 4 60-minute games had a winner** (50:02, 57:07,
  59:55; the fourth was 99-54 in kills at 60:00); before this run no bot game had ended. Carries' last hits at 10:00
  rose from 5-13 to 16-23 (Dota's bots get ~40: still the largest gap).
* **Learning**: not shown to help yet. Two learning A/B runs (`learn_ab_v1`, `learn_ab_v2`: three memories trained
  over three games each, then played against fresh bots from both sides, against a control): the learned side did
  better than the control as Ancient Light (+2.9k net worth) and worse as Black Sun (-6.4k). Per-hero last-hit timing
  learning drifted the wrong way in contested lanes and was removed; teamfight and gank learning are kept.
* Headless tests: 195 passed, 0 failed (188 + 7 new). `sh tools/check.sh`: no parse errors, "Names OK".
* Input probes with Quick cast: Sludge 12/12, Azrin 14/14 (the key alone casts at the mouse).
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 12:29; cold start into a Froster match in 11.6 s, no script
  errors (`shots/export_froster.png`).

What changed (details and the file map in the run's `handoff.md`):
* **Fight lag**: Froster's effects hit a script error every frame once he froze or chilled anyone (a freed effect node
  put into a typed variable), and printing it cost ~10 ms a frame; the same pattern was fixed in 48 more places
  (`View.live`). The HUD portrait drew the whole world a second time (now only the shown unit, every other frame).
  Simulation spikes: bots and team brains no longer all think on the same tick; the sight cache is no longer wiped
  when a tree falls; repeated estimates are cached; the minimap, kill feed, chat and scoreboard draw less often or in
  one batch; the hover pick and ground ray are cheaper; Spike Armor thorns share one mesh. Options > Video: Low and
  Medium use one shadow cascade.
* **Bots**: better last-hit timing; **teamfights as a team** (the team brain weighs both groups, calls "Fight! Focus
  their ...", and everyone near commits to one target); **ganks** gather out of sight behind the target and strike
  together, and laning-phase "ganks" by the lane partner are gone; wave clearing after the laning phase; honest camp
  checks (no more walking back to a camp that nearly killed them); teleport back to lane from the base; regen by
  courier instead of walking home; Mana Potions used; from 20:00 pushes when even, from 25:00 the whole team pushes
  together and goes on building after building, tanking tower shots in turn; stuck bots walk out; supports stop
  stacking late.
* **Quick cast** (Options > Game, off by default): a spell or item key casts at the mouse with no second click.
* Ribbon trails no longer streak across the map after a teleport.

Needs you: veto any name in "Names added 2026-10-15 c"; try Quick cast. Known issue (not new: the old build does it
too): after a long fight benchmark the game can crash on quit (an engine "Leaked instance dependency" warning first);
normal quits are clean.
Not verified: no blind critic review (none asked for; the changes are measured, the small visual ones are self-checks).

**2026-10-15 b: Debug panel fix, auto-select, unit panel, 10-skill bar, cooldown system, 20 items, new icons, Tock
and Kragg, tower ranges on Alt.** Run `work/lemondev/2026-10-15b-ui-items-heroes/` (handoff.md there: plan, file map,
how-to, state). Evidence on the final working tree (uncommitted):
* Headless tests: 188 passed, 0 failed (173 + 15 new: items, cooldowns, AoE / cast range, both heroes).
  `sh tools/check.sh`: no parse errors, "Names OK".
* `tests/tools/hud15_probe.gd` (new) 17/17 at 1080p and in a real 3840 x 2160 frame: Debug panel inside the screen
  (it ran 64 px off the right edge: the framed box's margins were not counted), every control reachable; a right
  click, Stop or Hold with a creep or nothing selected selects your hero and runs the command; a lane creep, neutral,
  tower and the Throne show in the bottom panel; 6 and 10 skills fit (keys Q W E D F R, Q W E D F G Y U I R).
* Input probes through real hotkeys: Tock 13/13, Kragg 6/6. Item flow probe 13/13 (no regression).
* Captures in `work/lemondev/2026-10-15b-ui-items-heroes/shots/`: debug panel, unit panels, 6- and 10-skill bars,
  icon sheets (old next to new), the 5-column shop, both heroes casting, tower ranges with and without Alt.
* Bot duels, 12 min, 3 seeds each, no script errors (`duels.txt`, kills over the three games): Tock vs Sludge 1-2,
  Kragg vs Ezee 1-0, Tock vs Kragg 0-2, Kragg vs Blood Ranger 1-2, Tock vs Azrin 1-7, Kragg vs Caziel 1-3. Kragg
  out-farms Ezee and Tock; Tock (a support) loses the mid-style duel to Azrin badly. Tune if you want them stronger
  one on one (all numbers chosen). A 25-minute 5 v 5
  bot game with two Tocks and two Kraggs: no script errors, bots fill roles 3 and 5 with them and call them by name in
  chat (`bot_game_5v5.txt`); the old late-game "stuck in task" bots showed up again (2 bots from 16:00).
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 04:36; cold start straight into a Kragg match in 9.7 s and a
  Tock match in 12.4 s, no script errors.

What changed:
* **Debug panel** (F9): sized from its real frame, two columns, capped above the bottom panel, scrolls if needed.
* **Auto-select**: with nothing of yours selected, any command selects your hero first and goes to it.
* **Bottom panel for any unit**: creeps, neutrals, towers, barracks, the Throne, wards show like a hero: portrait,
  level, health and mana with regen, damage, armor, speed, range, attack rate, magic resistance, the type chips and
  stat sheet, their spells / auras / attack effects / true sight as skill slots with tooltips and cooldowns, bounty,
  experience and sight, status effects. The innate skill (Growing Gut) has its own small slot.
* **Skill bar up to 10**: the console art comes in 7 widths (`tools/ui_skin.py --consoles`), slots shrink from 7
  skills; six new hotkeys (Extra ability 1-6: D F G Y U I) on the Hotkeys screen; with more than 4 skills the
  ultimate stays on R (Dota's Q W E D F R). "The ultimate" is now the skill with level requirements, not slot 4.
* **Cooldown system**: cooldown reduction (Time Crystal), cooldown rate (faster, slower or frozen), spell area bonus
  and cast range bonus. Rules in `docs/MECHANICS.md` "Cooldowns, spell area, cast range".
* **20 items + 11 parts** from Valve's items.txt (`work/research/d2_items.txt`), with recipes, shop groups (the shop
  is 5 columns now: Casting, Big Weapons, Boots added), tooltips, item effects, bot builds and bot use. Table of Dota
  names in `docs/MECHANICS.md`.
* **Icons**: `tools/item_icons.py` draws 78 item icons (every combination item, the new items and parts) and 11 skill
  icons in one style: a backdrop coloured by role, the object lit and outlined, a badge saying what it does.
* **Tower ranges**: the attack range circles of towers and fountains show only while you hold **Alt** (enemy yellow,
  red while it targets you; yours pale blue). They used to appear near enemy towers on their own.

Needs you: veto any name in "Names added 2026-10-15 b"; tune Tock's and Kragg's numbers if you like (all chosen).
Not verified: no blind critic review (no Dota frames on disk, no subagents asked for): visuals are builder
self-checks, UNVERIFIED for blind review. Performance benchmarks were not rerun.

**2026-10-15: multiplayer (servers, lobbies, a main server entry), HUD level pips, your bug reports.** Run
`work/lemondev/2026-10-15-multiplayer/` (contract.md there). Evidence on the final working tree (uncommitted):
* Headless tests: 173 passed, 0 failed (171 + 2 new server tests). `sh tools/check.sh`: no parse errors, "Names OK".
* Multiplayer, two windows on this PC driven by real clicks and typing (`tests/tools/net_ui_probe.gd`): host 35/35,
  guest 17/17 at 1080p; host 31/31 and guest 16/16 with the host's window at a real 3840 x 2160 (before the rejoin
  steps were added). Covered: host a server, the server list finds it on the local network, join it, create a lobby,
  join it with a double click, chat both ways, pick heroes and lanes, the leader's slot menu, Fill with Bots, Ready,
  Start Match, both load and play, Pause Game / Unpause Game reach both, Leave Game hands the hero to a bot, joining
  the running match again from the lobby list gives the hero back, Stop Hosting, the guest plays on with bots when
  the server goes. Two one-off misses in 6 runs (once the Ready click and once the guest's chat line did not register
  in the probe); both passed on every rerun, so they are recorded, not hidden.
* Lockstep (`tests/tools/net_test.gd`, headless, real UDP): a dedicated server with two players, a hosted server with
  one player, and the **exported build** as a dedicated server with two players: every player ends on the same world
  fingerprint; forced desyncs repaired from a player in the majority (in 9 to 31 frames); a player who drops and
  connects again gets a snapshot and their hero back. Command to execution at real time against the exported server:
  35 and 38 ms average (p95 56 and 80 ms) on this PC; a hosting player's own commands about 5 ms.
* Your bug "giant T-posed model in the river": unit views of units that spawned or moved off screen were never placed
  (they stood at the world origin, the river in the map's centre) and never animated (a bind pose, at the model's raw
  size). Fixed in `unit_view.gd` / `main.gd`; `tests/tools/view_place_probe.gd` (5 v 5, camera over the river, 6 game
  minutes, 268,465 checks) finds 0 misplaced views; it found them at the map centre before the fix.
* Your neutral rules: neutrals wake for an enemy within 125 (was 240); lane creeps leave a calm camp alone and fight a
  neutral only while it is aggressive and for 5 s after; the large pull camp and the medium camp by the safe lane's
  tier 2 moved away from the lane (both sides). Holding **Alt** shows the camps' spawn boxes (was Shift). Tests,
  `camp_layout.gd` (0 problems), `team_probe.gd` 11/11 and a 20-minute 5 v 5 bot game (no script errors) pass.
* HUD: the ability level pips sit in their own carved tray under each slot (the console art got a tray, the slots
  moved up 4 px and the health and mana well down); learned levels are gold bars, the next learnable one a pulsing
  gold outline. Item and Teleport hotkeys are on dark tags inside the slots (they were cut by the frames). Checked at
  1080p and a real 4K frame.
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 01:25 and run as a dedicated server (above).

Needs you:
* **The main server's address.** The Multiplayer screen lists a "Main server" first, but this build has no address
  for it (it shows "Not set up in this build yet"). Run the server on a machine with a public address
  (`WarriorsOfAether.exe --headless -- --server --name="Warriors of Aether" --motd="..."`, UDP ports 27850 and 27851
  open) and put its address in `src/net/main_server.json`, then rebuild.
* Veto any new names below ("Names added 2026-10-15").

Not verified: no independent (blind) critic review of the new screens was run (no subagents were asked for and there
are no Dota lobby frames on disk), so their look is a builder self-check: UNVERIFIED for blind review. Performance
benchmarks were not rerun this session.

**Previous status (2026-10-14 b):**
**2026-10-14 b (wrapped up early on your request, "just wrap up and build"): Froster and Caziel, Main Menu, UI
skin, mechanics fixes, multiplayer groundwork.** Run `work/lemondev/2026-10-14b-ui-net-heroes/` (contract.md there).
The run was interrupted and then cut short, so only these gates were rerun at the end:
* Headless tests: 170 passed, 0 failed. `sh tools/check.sh`: no parse errors, "Names OK".
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-14 23:10. Cold start straight into a match: Froster ready in
  10.1 s, Caziel 10.5 s, no script errors (`export_froster.png`, `export_caziel.png`); the Main Menu opens with no
  script errors (`export_menu.png`).
* Bot duels, 12 min, 3 seeds, Froster and Caziel against every hero: no script errors (`duels_heroes.txt`).

What is in this build:
* **Froster, the Winter Master** (Ice, ranged Int): Breath of Cold, Ice Pulse, Frost Heart, Endless Winter.
  **Caziel, the Void Assassin** (Dark, melee Agi): Swift Dagger, Sweet Poison, Master of Shadows, Death Order. Your
  names and numbers; Caziel's base stats are *chosen* (classic melee-agility template). Talents are plain texts
  ("+80 Breath of Cold damage", "+25 Attack Speed"...), listed in `src/sim/sim_data.gd` near line 506.
* A new **Main Menu** (Play, Hero Creator, Options, Quit) with your hero on a lit stage and a "Choose hero" button,
  plus generated UI textures in `assets/ui/skin/` (`tools/ui_skin.py`).
* Mechanics fix: Ancient Light's top and Black Sun's bottom lane creeps spawned inside a tower's footprint and never
  left (no creeps on those lanes from the second wave). Spawns now snap to walkable cells and blocked units slide out.
* Every player action now goes through serialisable commands (`src/sim/sim_commands.gd`), and `src/net/` plus
  `sim_snapshot.gd` hold the lockstep session code.

Not done or not verified (the cut parts of the run):
* **Multiplayer has no screens yet** (browse, host, join, lobby). The Main Menu hides its Multiplayer button until
  `src/ui/net_menu.tscn` exists. The two-process desync test (`tests/tools/net_test.gd`) was not run.
* Performance gates (sim profile, 5 v 5 bench at 10:00 and 25:00) were not rerun after the changes.
* The HUD, shop, Hero Select and Game Setup remake (U2, U3) and the blind UI review against Dota frames: not done.
* Live probes (menu, item flow, input, controls) were not rerun; the 5 v 5 "an Ancient falls" gate (Q1) not rerun.

**Previous status (2026-10-14, first run):**

**IMPLEMENTED, GATES PASSED, VISUALS NOT BLIND-REVIEWED** (2026-10-14: elements, damage and armor types, magic amp,
Kugmo / Igit / Atuli, item menu with lock and disassemble, 10 s full-refund protection, item effects, HUD readouts,
quieter creep deaths, Azrin with your female_generic body and particle fire; run
`work/lemondev/2026-10-14-elements-azrin/`, contract in `contract.md` there; details in "Elements, armor and damage
types, magic amp, item menu, Azrin" below).

Evidence (all on the final working tree, uncommitted):
* Headless tests: 155 passed, 0 failed (137 earlier + 18 new). `sh tools/check.sh`: no parse errors, "Names OK".
* Live probes: `menu_probe` 14/14 at 1080p and in a real 3840 x 2160 frame (captures in `work/shots/menu/`, `4k/`);
  input probes Azrin 12/12, Sludge 10/10, Ezee 4/4, Blood Ranger 7/7; item flow probe 13/13.
* Bot duels, 12 min, 3 seeds each, no script errors: Azrin beats Blood Ranger 16-1 and Ezee 13-0 and is even with
  Sludge 4-3 (your numbers kept; she is strong, partly from Fire beating Nature): `duels_pass1.txt`.
* Two 30-minute 5 v 5 bot games with two Azrins a side (seeds 3 and 7): no script errors; the Azrin mids led their
  teams (16/4/6 and 10/8/3 in game 1) and bots bought Atuli, Mana Boots, Push Staff and Spell Shield for her. Game 2
  flagged four bots stuck in "task" mode after 23:00, the known late-game AI problem (old AI2 gate), not new
  (`bot_game_5v5.txt`).
* Benchmark, 1080p, RTX 4060, `--bench=60 --t=240 --autoplay`, alternating with an a38afe7 checkout in the same
  session (`bench.txt`): after the first warm-up pair, this build 51 / 47 fps (p95 26.3 / 28.6 ms) vs the baseline
  53 / 51 (p95 26.7 / 26.7): about 6% slower, inside the 10% gate. With Azrin playing: 45 fps (p95 33 ms) before the
  flame shader went from 4 to 3 noise octaves, 64 fps (p95 20.8 ms) after, baseline 52 in the next run. This machine's
  run-to-run spread is wide (35-64 fps), so read it as no measurable slowdown, not a gain.
* Export + cold start of `build/WarriorsOfAether.exe -- --match --hero=azrin`: match ready in 11.3 s on the final build (12.0 s earlier with the bot
  games running on the same CPU), no script errors (`export_run.txt`, `export_start.png`).

Not verified:
* Blind visual review of the fire, Azrin's look, the item effects and the HUD chips: no Dota frames on disk, so
  UNVERIFIED (builder self-checks with captures only, see the ledger).
* Balance: Azrin with your numbers is far ahead in 1 v 1 lanes; the element table also shifts matchups (Fire vs
  Nature, Earth vs Fire). Numbers are easy to change in `src/sim/sim_data.gd` and `SimConst.ELEMENT_*`.
* Earlier results still stand (Shuriken Hook visuals, base environment, ramps, Burst Shot VFX, Hero Select STOPPED;
  Dark Stomp VFX STOPPED: LIMIT; tower scale UNVERIFIED; old AI2 gate failed).

## Run it

```
"C:\Users\Lemon PC\Desktop\Godot.exe" --path A:\Python\woa
```
or open `A:\Python\woa\project.godot` in the editor and press F5.

* Or run the exported build: `build/WarriorsOfAether.exe` (rebuild it with
  `godot --headless --path . --export-release "Windows Desktop" build/WarriorsOfAether.exe`).
* The game opens on **Hero Select** (`src/ui/hero_select.tscn`): pick your hero, change its look with **Customize look**
  (the Hero Creator), then **Play** opens **Game Setup** (`src/ui/game_setup.tscn`): two teams of five slots, each You,
  Bot or Empty, with a hero (or Random; bots may play the same hero), a bot skill (Passive, Easy, Medium, Hard, Unfair)
  and name, and the lane you want. Presets: 5 vs 5, 1 vs 1 mid. **Start** goes to the Hotkeys screen and the match.
* Exported builds ignore scene paths on the command line: `build/WarriorsOfAether.exe -- --match [capture flags]` jumps straight into a match (for automation; `--match` must come after `--`).
* Tests (headless, about 1 minute): `godot --headless --path . -s tests/run_tests.gd`. Add `-- --only=<name>` for a subset. 155 tests.
* Teamfight benchmark (the one that matters for lag in fights): `godot --path . res://src/game/main.tscn -- --bench=40
  --t=600 --fight --autoplay --lineup=ezee,azrin,froster,sludge,tock,blood_ranger,caziel,kragg,azrin,froster
  [--bench_shot=png]`: prints frame times and the cost of every part (see `work/lemondev/2026-10-15c-perf-feel-ai/
  handoff.md`). Function-level profile: `python tools/gd_profile.py [--game] -- <args>`.
* Benchmark: `godot --path . res://src/game/main.tscn -- --bench=60 --t=240 --autoplay` writes `work/bench.txt`. Last measured 2026-10-12 on the new map at 1080p on the RTX 4060 with the HUD (`--bench=50`): 77 fps average, p95 16.67 ms.
* Screenshot capture (renders, saves, quits): `godot --path . res://src/game/main.tscn -- --capture=work/shots/x.png --t=95 --cam=-1500,-1300 [--autoplay] [--zoom=1.1]`. `--autoplay` lets a bot drive your hero too.
  * `--hero=sludge --bot_hero=blood_ranger` pick the heroes (blood_ranger, ezee, sludge); `--frames=30,34,38` saves several frames;
    `--live` keeps the simulation running while capturing. `--bots=5v5` plays full teams; `--reveal` lifts the fog;
    `--boxes` shows the camps' spawn boxes; `--nolearn` keeps the bots' memory untouched.
  * Demo staging: `--lvl=18` levels your hero and learns its kit; `--at=wave,170 | tree | hero,520` places it beside
    the enemy wave, between a creep and a tree, or beside the enemy hero (`--weaken=0.12`); `--cast=dark_stomp@4`
    (or `attack`) issues it at capture frame 4. `--board` shows the scoreboard, `--endscreen` the end screen,
    `--drag=x,y,w,h` a selection box, `--marker=x,y` a move marker.
* Bot duels: `godot --headless --path . -s tests/tools/bot_duel.gd -- --a=blood_ranger --b=ezee --min=12`.
* A game that stops advancing: `godot --headless --path . -s tests/tools/stall_probe.gd -- --a=roydo --b=ezee --min=10
  [--trace=348] [--seed=3]` prints a line per game minute with the real time, every step over 50 ms, and with
  `--trace` the heroes' state before each step from that second (the last line printed is the step that hangs).
* Animations (runs 2026-10-15 g, h): audit every hero clip `godot --headless --path . -s tests/tools/anim_audit.gd --
  [--heroes=kragg] [--units] [--raw] [--out=x.txt]`; rebuild the repaired arms after any change to the clips or the
  models: `godot --headless --path . -s tests/tools/anim_repair.gd`, `... -- --body=sludge` and `... -- --units`;
  frame sheets `godot --path . -s tests/tools/anim_sheet.gd -- --heroes=kragg,unit:dawn_melee --clips=sword_1
  --yaws=30,-70 [--fov=14] [--raw]`.
* Title and menu captures: `godot --path . res://src/ui/main_menu.tscn -- --capture=x.png [--title --title-at=5]
  [--focus=1] [--4k]`.
* 5 v 5 bot games (headless): `godot --headless --path . -s tests/tools/bot_game.gd -- --seeds=3,7 --min=40 [--chat]
  [--skill=hard] [--learn=work/mem.json --learn_teams=1,0] [--out=file]` prints the result, each hero's line, LH and net
  worth at 10:00 and 20:00, time per bot mode, stuck heroes and the team chat. `tests/tools/trace_game.gd` prints each
  bot's mode, desires, order and target every few seconds; `tests/tools/bot_profile.gd` the cost of each step part.
* Camp layout check: `godot --headless --path . -s tests/tools/camp_layout.gd` (clearances, reachability, plot).
* Live probes (open a window, play a real match, print PASS / FAIL):
  `godot --path . -s tests/tools/camera_probe.gd` (camera at the start and at respawn),
  `godot --path . -s tests/tools/team_probe.gd -- --bots=5v5 --nolearn --out=work/shots` (bot chat in the HUD, ping
  replies, Alt spawn boxes, typed chat),
  `godot --path . -s tests/tools/input_probe.gd -- --hero=sludge --nobot` (every ability through the input
  controller), `godot --path . -s tests/tools/item_flow_probe.gd -- --hero=sludge` (shop, To Buy, drag and drop,
  talents, courier), `godot --path . -s tests/tools/ui_probe.gd -- --hero=sludge --out=work/shots` (HUD captures).
* `--showqueue` (capture flag) queues a few orders for your hero and draws the Shift waypoints.
* Parse-check every script: `sh tools/check.sh`.
* Multiplayer: Main Menu > Multiplayer. A dedicated server (no window):
  `build/WarriorsOfAether.exe --headless -- --server [--port=27850] [--name="My server"] [--motd="Welcome"]
  [--password=x] [--max=64]`; it answers the server list on the port above its game port and prints joins, lobbies
  and matches. Lockstep tests (one shell each): `godot --headless --path . -s tests/tools/net_test.gd -- --role=server`
  then `-- --role=client --lead --name=A` and `-- --role=client --name=B [--corrupt=3600] [--drop=5200] [--lag=60]`
  (or `--role=host` plus one client); every player prints `HASH@<frame>` and they must match. The screens through
  real clicks (two windows): `godot --path . -s tests/tools/net_ui_probe.gd -- --role=host [--4k]` and
  `-- --role=guest`.
* Units drawn where they are: `godot --path . -s tests/tools/view_place_probe.gd -- --hero=froster --bots=5v5
  --autoplay --nolearn --min=6`.
* Rebuild Azrin's body from your female_generic model (about a minute; `-- --preview=dir` renders checks):
  `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/azrin_body.py`
* Azrael's scythe and wings: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup
  --python tools/blender/azrael.py`; her look variants side by side: `godot --path . -s tests/tools/azrael_look.gd --
  --out=x.png [--close]`; which way a weapon's head moves in a swing: `godot --headless --path . -s
  tests/tools/swing_dir.gd -- [--clips=gs_1,gs_3]`.
* Rebuild the building models: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/buildings.py`.
* Re-bake the terrain texture arrays (needs the GPU, not headless): `godot --path . -s tests/tools/bake_terrain_arrays.gd`.

## Controls (Dota defaults)

Every hotkey can be changed on the **Hotkeys** screen shown before each match ("Are you good to go?"): one key, Mouse 4 / 5, or a combination with Ctrl, Alt or Ctrl + Alt. Shift is never part of a hotkey because it queues. Esc, F10, Ctrl + 1-9, Alt + F4 and Alt + Tab are refused. Layouts can be saved as named templates (`user://keybinds.json`). The table shows the defaults.

| Key | Action |
|---|---|
| Left click / left drag | Select. A drag draws a green box: your own units inside it are selected (hero first); with none of yours inside, the one unit nearest the box centre |
| Right click | Move, attack an enemy, deny an ally below 50% HP, follow an ally, take an orb (orbs come first under the cursor). Orders go to the selected units you control (hero, courier), as in Dota |
| A, then left click | Attack-move (ground) or attack (unit). On an ally the order is accepted: your hero waits in range and only swings once the ally can be denied. Shows your attack range |
| S | Stop (the hero still auto-attacks enemies in range). Hold S: the hero is stopped again every frame and every order is refused until you let go; held over 0.35 s it stays a hard stop (no auto-attack until your next order) |
| H | Hold position |
| Shift + any order or hotkey | Queue it, as in Dota: orders run one after another; a queued spell still cooling down is checked again when its turn comes. Holding Shift shows the queue as numbered waypoints (green move, red attack, blue spell or item, gold hold) |
| Quick cast (Options > Game) | With it on, an ability or item key casts at once at the mouse (on the unit under it), with no click; over the interface, or with no valid unit under the cursor, the targeting cursor shows as usual |
| Q W E R (D F G Y U I) | Abilities. Heroes with more than 4 skills use Dota's layout: the last (ultimate) stays on R, the extra ones take D, F, G, Y, U, I (Tock: Q W E D F R; Kragg: Q W E D R). With nothing of yours selected, an ability, item, Stop, Hold, Attack, Teleport key or a right click selects your hero first. No-target spells and toggles (Stench) act at once. Point and unit spells show a pulsing crosshair: red for spells aimed at enemies, green for support (allies, yourself, a place); items too. A click that misses a valid target keeps the cursor and says why; right click or Esc cancels |
| Ctrl + an ability's hotkey, or the "+" above an ability | Learn the ability (unless that Ctrl combination is bound to something else) |
| Right click an ability button | Toggle autocast (Frost Quiver) |
| Z X C V B N | Items. Right click an item slot to move it between the inventory and the backpack. Drag an item to another slot, to the stash (in the base), onto the ground (the hero walks over and drops it) or onto an allied hero or your courier (gives it) |
| Right click an item on the ground | Pick it up |
| Talents button (star left of the abilities) | Opens the talent tree from level 10: one of two talents per tier, costs an ability point |
| Stash (above the items) | Shown when it holds something or you are in the base: click an item to take it, drag it to a slot, Grab All |
| Shift + click in the shop | Adds the item to **To Buy** (right side of the screen), broken into the parts you still need. In To Buy: left click buys, right click buys it automatically once you have the gold (into the courier if it waits at the fountain), Ctrl + click or x removes |
| F4, the Shop button, or B with an empty slot 5 | Shop. A click anywhere else (world, minimap, top bar) or Esc closes it; clicks on your items, stash and To Buy keep it open |
| , (comma), or right click the Teleport slot | Buy a Teleport Scroll for 100 gold (also first in the shop's Consumables). At the shop it goes into the Teleport slot; elsewhere into the stash, and into the slot once it reaches you (F3 sends the courier) |
| J, or the button above the minimap | Glyph |
| T | Town Portal: target a point or the minimap; the hero teleports beside the nearest allied building after a 3 s channel. Press T (or click the Teleport slot) twice quickly: straight to your fountain |
| F3, or the Deliver button | Courier picks up your items lying in the fountain area, takes the stash and flies it all to you |
| F2 (courier selected) | Q Return to Base, W Retrieve Items, E Return Items to Stash, R Deliver, Z Transfer, X Speed Burst (level 10), C Shield (level 20), V Auto Deliver; right click moves it |
| Buyback button (while dead) | Buy back: 200 + net worth / 13 gold, 8 minute cooldown |
| F1 | Select your hero; press twice to centre on it |
| Portrait | Click: select your hero and centre the camera on it. Hold: the camera follows your hero |
| Ctrl + 1..9, then 1..9 | Control groups (double tap centres the camera) |
| Alt + click | Ping (ground or minimap). On an enemy hero or building: "attack"; on one of ours: "defend"; Ctrl + Alt + click: danger. Your bots answer in chat, and agree or say why not |
| Enter | Type to your team (Enter sends, Esc closes). Bots understand "push top", "defend mid", "gank" or "kill <hero>", "back", "group" |
| Alt (hold) | Shows every neutral camp's spawn box: yellow, red while something blocks it (couriers never do), with its size and the pull camps named; and the attack range of every tower and fountain (enemy yellow, red while it targets your hero; yours pale blue). Without Alt no range circles show |
| Tab (hold) | Scoreboard with damage tables |
| Top-bar hero tiles | Click to look at a visible hero; dead heroes show their respawn timer |
| Space (hold) | Follow your hero |
| Screen edges, arrow keys, middle-drag | Pan the camera. In Borderless and Fullscreen the cursor is kept inside the game window, so pushing past an edge keeps panning (Windowed: Options > Game "Lock cursor to window (Windowed)") |
| Mouse wheel | Zoom |
| Hold right click | Repeats the move or attack order at the cursor |
| F9, or the Debug button (top right) | Debug panel: force start, creep waves, camps, level up, gold, refresh, god mode, free spells, reveal map, skip time, game speed |
| Minimap | Left click or drag moves the camera; right click moves your hero |

## Architecture

```
src/sim/      deterministic 30 Hz simulation (no nodes). Rules, numbers and sources: docs/MECHANICS.md
  sim_const   rules constants (APPROX marks unverified values)    sim_data   unit, hero, ability and item data
  sim_map     terrain levels, river, bases, ramps, trees, A* grid, lanes, camps
  sim_world   tick loop, clock, waves, regen, backdoor, respawn, invulnerability chain, glyph
  sim_orders  turning, movement and collision, attack point and backswing, chase, hold, attack-move, casting
  sim_combat  projectiles, attack classes, armor, damage, deaths, bounties, XP, kill and assist gold
  sim_ai      waves, lane creep targeting and aggro, towers, neutral camps (stacking)
  sim_vision  fog of war (raycast grid, trees and high ground block sight, day and night ranges)
  sim_abilities  the heroes' kits, talents, toggles, channels, pushes and leaps, item actives (trees, planting)
  sim_items   combination items' actives, passives, auras and attack procs
  sim_shop    buying, recipe scrolls, alternative recipes, combining, stash, selling
  sim_bot     a hero bot: modes scored by desire (lane, farm, jungle, stack, pull, ward, fight, retreat, heal, the
              team's plays), last hits, combos, escapes, TP, items, difficulty, learning hooks
  sim_bot_kits   what bots know about each hero: roles, skill and talent orders, builds per role, burst and power
  sim_team_ai    one team's brain: roles and lanes (around the player), what the team saw, ganks, pushes, defence,
                 danger calls, Fortify, ping answers, team chat, scoring a finished game into the bots' memory
  bot_memory     what bots learn, saved in user://bot_memory.json (fight model, danger map, builds, skill shots,
                 retreat bar, lane matchups, the player's lanes)
src/game/     presentation (reads the sim, never writes it except through commands)
  main        boot, 30 Hz stepping in _physics_process, event dispatch, fog texture, capture mode
  terrain_builder + terrain.gdshader   9-layer splat terrain from the sim map, river water
  foliage + foliage.gdshader           Quaternius trees (one instance per sim tree), grass and plants
  building_view + building/crystal shaders   Blender-built faction buildings
  unit_view + model_catalog            animated units, attack swings timed to the sim's attack point
  camps (neutral camp props, fires, spawn boxes on Alt), fx, sludge_fx (shuriken hook and chain, Stench cloud,
  Chomp), item_fx (item actives and procs), camera_rig,
  atmosphere (day/night), fog_of_war.gdshader, input_controller, audio (Effects, Interface, Ambience buses)
src/core/     options (user://options.json), game_settings (heroes and looks)
src/hero/     customisable hero body ported from beyond-heroes (HeroLook, HeroAppearance)
  fx (projectiles, arrows that stick or miss into the ground, sparks, debris "bits", shockwaves, cracks, lightning,
     spikes, force walls, ability visuals), status_fx (stun stars, curse sigil, enchanted blade, Unholy aura),
     targeting_fx (cast range, area and line previews), trail3d (ribbon trails)
src/ui/       hero_select (main menu), hero_creator, hud (bottom panel shows the selected hero, minimap with pings,
              top bar with hero tiles, shop, tooltips), kill_feed (kill log and banners), scoreboard (Tab, damage
              tables, death recap), unit_bars (health with damage ghosts, status icons, floating damage numbers),
              screen_fx (death desaturation, low-health pulse), match_menus (pause, end screen), ui_kit,
              shop_panel (the Dota-style shop), options_panel (Options screen), game_setup (Game Setup),
              chat_panel (team chat above the minimap)
src/net/      multiplayer: net (autoload Net: ENet messages, the player's session, server queries, UPnP),
              net_server (a server's lobby list, rooms, the relayed lockstep, desync repair, rejoin), net_match (a
              player's lockstep: frames, jitter buffer, fingerprints, snapshots), net_browser (the server list, saved
              servers and the player's multiplayer settings in user://multiplayer.json), main_server.json (the main
              server's address); src/sim/sim_commands (every player action as data), sim_snapshot (the world as bytes)
src/ui/net_*  the Multiplayer screens: net_menu (shell, dialogs, notices), net_servers_page, net_hub_page,
              net_room_page, net_list (tables), net_chat
tests/        run_tests.gd (mechanics), tools/ (bakes, probes)
tools/        blender/buildings.py, build_wear_catalog.py, itch_dl.sh, kv.py (research), check.sh
```

## The customisable hero (your request: "very very customisable and dressable")

`HeroAppearance` drives `assets/characters/hero/hero.glb`, the body you supplied in beyond-heroes. It has 132 animations, including the full bow set and female locomotion.

* **Look** (`HeroLook`):
  * 20 shape keys: the female figure, muscle, belly, build, rear, and 15 face shapes.
  * Height, head, hands and feet size.
  * Skin, eye, lip, brow and marking colours, plus 12 skin patterns, 10 eye styles, 7 brow styles and 8 markings.
  * 16 hair styles and 8 beards, each with a length slider.
  * 13 presets (Huntress, Shieldmaiden, Moon Elf, Goblin King and more).
* **Outfit**: 143 worn pieces in 10 slots (inner garment, armor, leggings, helm, gloves, boots, 4 accessories), listed in `assets/characters/hero/wear/catalog.json`. Every piece follows the body sliders, the female shape included. Each slot can be dyed (cloth, trim, leather, metal, gold).
* Heroes are set up in `main.gd` `_spawn_heroes()`. A hero creator screen is the next UI step (see the backlog below).

## Assets and licences

See `docs/ASSET_CREDITS.md`.

## Blood Ranger (replaced Galewarden on 2026-10-12)

Ranged agility hero (Galewarden's base stats), crimson-haired huntress. Your numbers are used as given; level 1
takes the base value ("55% + 10% per level" = 55/65/75/85%). Numbers you did not give are marked *chosen*:

* **Burst Shot (Q)**: point target, cast range 900 *chosen*, area radius 400 *chosen*. Channels 2 s *chosen*: 5 waves
  0.4 s apart, each a random 4-7 arrows, 30 in all. Each arrow hits a random enemy in the area (or the ground) for
  55/65/75/85% of her average attack damage as physical damage (a spell: no lifesteal, no Masterful Archery).
  Ended by move, attack, stop or hold orders, other casts, stuns, silence, roots and pushes. 17 s cooldown, mana
  90-120 *chosen*.
* **Gale Impact (W)**: a great arrow to the target point (300-2000 range), speed 2000 and radius 110 *chosen*,
  pierces. 120/200/280/360 magic damage, then hurls each enemy sideways off the arrow's line (with a little forward
  push). A thrown enemy that hits a cliff, tree, building or unit takes another 20% of the arrow's damage once.
  Trees on the path and trees that thrown units hit are felled. 12 s cooldown, mana 100-130 *chosen*.
* **Masterful Archery (E)**: passive, 30% chance *chosen* per attack to add 15/25/35/45% of her agility as physical
  damage (charged arrow, crimson burst, a red "+N!" number), 0.8 s cooldown (the E icon shows it).
* **Blood Ranger (R)**: 15 s of 40/50/60% lifesteal and +200/300/400 attack range. Each attack that hits her has a 30%
  chance to make her leap 300 back, away from the attacker (stopped short by cliffs, trees and buildings). *Chosen*:
  at most one leap per second, so creep fire cannot chain them; the leap keeps her orders. 30 s cooldown, mana
  100-150 *chosen*.
* Masterful Archery was buffed on request from (8% + 10% per level) to (15% + 10% per level) of agility.

## Trees, Mini-Axe and Vegan Picker

Trees are destructible as in Dota (see `docs/MECHANICS.md`, "Trees"): they fall to the Mini-Axe (Quelling Blade),
Vegan Picker (Tango), Gale Impact and thrown units, and grow back after 180 s (current Dota value; it was 5 minutes in
older patches), waiting while a unit stands within 150. Tree Twig (Iron Branch) plants a 20 s tree. Regrowth and
planting animate in; eaten trees shrink away; felled trees topple away from the blow.

## Towers

Tower models are 40% smaller (scale 0.6; tier growth kept); the health bar, crystal light and bolt launch point
follow. Their footprint in the simulation is unchanged.

## Ezee, the Dark Paladin (added 2026-10-12)

Melee strength hero (`src/sim/sim_data.gd`, abilities in `src/sim/sim_abilities.gd`). Numbers you did not specify are
marked here so you can change them:

* **Dark Stomp (Q)**: 60/90/120/150 magic damage in 350 radius (damage and radius chosen), then a physics push away
  from Ezee: velocity falls off with distance and mass (creeps 1, heroes 1.2, siege 1.8), units fly in an arc, slide,
  bounce off walls and transfer momentum to units they hit. An enemy that crashes into a unit, tree, cliff or building
  takes 50/75/100/125 impact damage (chosen) and is stunned 0.7 s per level once it stops; a tree it hits is smashed.
  Cooldown 12 s, mana 100-130 (chosen).
* **Leap Strike (W)**: picks the visible enemy within 800 (range chosen) with the lowest health fraction, the nearest
  if none is hurt; nothing happens (no mana or cooldown spent) if no enemy is in sight. Leaps in 0.55 s and deals
  100/125/150/175 + 60% strength pure damage, slowing 40% (amount chosen) for 1.5 s. Cooldown 16/15/14/13 s.
* **Tainted Touch (E)**: lightning enchants the sword for 7 s; attacks add 60/90/120/150 magic damage and curse the
  target for 5 s (revealed to Ezee's team even when invisible, 300 sight radius around it). Cooldown 11 s.
* **Unholy Might (R)**: roar, 0.5 s screen shake, dark aura for 10 s. Each damage instance has a 30/40/50% chance
  (chosen) to be halved, the other half dealt as pure damage to a random enemy within 700 (chosen). Then a 50% slow
  for 2 s. Cooldown 25 s.
* Look: the customisable hero body in full plate (Warden Plate), visored greathelm, violet dyes and a darkened
  greatsword (`GameSettings.default_look("ezee")`). The bot plays Ezee with its own skill and item build.

## Map (overhauled 2026-10-12)

* Elevation: six jungle plateaus per side on high ground, reached by stone stairs with torch columns wherever a
  walkway crosses their edge. Each terrain level renders 2 m high (`LEVEL_HEIGHT` 200, visual only;
  the rules use levels).
* Mountains: impassable massifs in the corners (the river leaves through gorges) and along the edges, with a ring of
  peaks past the map edge, so there is no grey void. Mountain cells block movement and sight.
* Bases: crenellated walls with towers, roofs and banners; gate towers at ramps; emblem plazas (sun for Ancient
  Light, crescent for Black Sun); paved roads with kerbs and braziers; a quartermaster stall and supply clusters.
  Ancient Light has blossom gardens and flower beds, Black Sun has dead trees, graves and basalt.
* Shift queue and hotkey combinations: see Controls.

## Options and sound (added 2026-10-12)

Options from Hero Select and the pause menu, saved in `user://options.json`:
* **Audio**: Master, Effects, Interface, Ambience (0-100%; 50% sounds half as loud, -10 dB). Master starts at 50%, so
  the whole game is half as loud as before. "Mute when the game window is in the background".
* **Video**: window mode, resolution, V-Sync, frame limit, render scale, quality preset (Low, Medium, High, Ultra),
  show FPS. **Game**: edge pan, camera speed, screen shake, damage numbers. **Controls**: opens the Hotkeys screen.
* Captures and benchmarks ignore the saved window and quality settings so results stay comparable.

## Sludge, the Butcher (added 2026-10-13; Dota 2's Pudge, patch 7.41d)

Melee strength hero: Str 25 +3.0, Agi 13 +1.4, Int 16 +1.8, damage 45-51, armor 0, regen 2.5, speed 280, turn 0.7,
range 175, BAT 1.7, attack point 0.5. Numbers follow Dota exactly; only the names and the look are ours.
* **Growing Gut (innate)**: +2 strength for good whenever an enemy hero dies within 450 of him, or anywhere if he gets
  the kill. Kept through death.
* **Shuriken Hook (Q)**: always flies its full 1300 at 1600 speed, catches the first unit within 100 of the tip
  (enemy or ally, not ancients or buildings) and drags it back to where he threw it. Enemies take 150/220/290/360
  pure damage and are stunned while dragged; enemy creeps die at once; allies come back unharmed. Flies over cliffs
  and trees. A miss roots and disarms him for 0.53 s. 500 vision for 4 s where it catches. 18/16/14/12 s, 120 mana.
  Upgrade Gem: +20% of the drag distance as damage; catching an ally halves the cooldown.
* **Stench (W)**: toggle, works while stunned or channelling. 30/60/90/120 magic damage per second within 250 to
  enemies and to himself (never lethal), 14/20/26/32% slow. Upgrade Staff: +200 radius, +90 damage, -20% healing.
* **Blubber (E)**: blocks 8/14/20/26 of every damage instance for 4/5/6/7 s; does not break Chomp.
  20/19/18/17 s, 65/70/75/80 mana.
* **Chomp (R)**: channel 2.75 s on an enemy within 200: 80/100/120 + 0.3/0.6/0.9 x strength magic damage per second in
  6 ticks, healed back to him; the victim is stunned and pulled in. 30/25/20 s, 100/130/170 mana.
* **Talents** (levels 10/15/20/25, picked from the HUD; bots pick their own): +10% Stench slow / +5 armor; +150 hook
  damage / 8% spell lifesteal; -4 s hook cooldown / +0.75 s Chomp; 1.5x Growing Gut and Blubber / 1.5x Chomp.
* Look: a MakeHuman (CC0) butcher built in Blender (`tools/blender/sludge.py`, gear in `sludge_gear.py`) on the hero
  skeleton, so he uses all 132 hero animations; cleaver, apron, chain and a four-bladed shuriken on the hook.

## Combination items and the shop (added 2026-10-13)

Dota 2's items with plain names; prices, recipes, stats, actives and passives follow 7.41d (table with the Dota
names in `docs/MECHANICS.md`, "Items and shop").
* Recipe scrolls are bought like any item ("Recipe: Tough Band") and parts combine on their own as in Dota, in the
  inventory, and with the stash while in the base. Buying a finished item buys only the parts you are missing.
* Switch Boots have three recipes (Heavy Belt, Wizard Robe or Elf Band); the part you used decides the starting
  attribute, and the active switches strength, intelligence, agility. Boot speed does not stack.
* Shop (F4, Shop button): Basics and Upgrades tabs with columns like Dota's, a search box, a side pane with the item's
  bonuses, what it is made from and what it builds into, Buy (only the missing gold) and Sell. Left click selects,
  right click or double click buys; click an item in "Your items" to sell it; click a stashed item to take it.
* Capture flag `--shop=tab[,item[,search]]` opens the shop in the base with some gold and parts.

## Names added 2026-10-12 and 2026-10-13 (veto any you dislike)

* Teams Ancient Light and Black Sun; buildings Throne, Statue, Eye Ward; creeps Footman, Archer, Stone Golem, Flag
  Bearer, Ghoul, Skeleton Archer, Bone Golem, "Super" creeps; neutrals Goblin, Goblin Digger, Goblin Boss, Wolf,
  Alpha Wolf, Orc, Orc Shaman, Swamp Troll, Ogre, Fire Imp, Lava Golem.
* Old items renamed: Healing Paste, Mana Potion, Ripe Mango, Firefly Jar, Teleport Scroll, Tree Twig, Slippers, Heavy
  Gloves, Thinking Cap, Headband, Elf Band, Heavy Belt, Wizard Robe, Quick Blade, Fist Blades, Long Sword, Fast
  Gloves, Armor Ring, Chain Shirt, Healing Ring, Running Shoes, Zap Stick, Leech Mask, Swift Band, Zap Wand, Switch
  Boots, Dancer Sword, Long Spear.
* New parts: Giant Axe, Wizard Staff, Greatsword, Steel Hammer, Spear, Rust Stone, Brass Knuckles, Plate Vest, Big
  Healing Ring, Mana Stone, Health Crystal, Big Gem, Pointy Hat, Fur Hat, Sneak Charm, Jump Knife.
* New items: Tough Band, Smart Band, Mana Ring, Leaf Hat, Steady Ring, Slip Boots, Mana Boots, Medic Kit, Block
  Shield, Spike Armor, Gold Glove, Push Staff, Spell Shield, Armor Breaker, Shock Hammer, Cleave Axe, Sneak Blade,
  Upgrade Staff, Upgrade Gem; recipe scrolls "Recipe: <item>".
* Sludge "the Butcher", Growing Gut, Shuriken Hook, Stench, Blubber, Chomp (yours); Blood Ranger's title "the Archer".
* Shop: Basics, Upgrades, Consumables, Attributes, Armaments, Magic, Accessories, Support, Weapons, Armor, Abilities,
  Stash, Your items. Options: Audio, Video, Game, Controls, Effects, Interface, Ambience, Fortify (was Glyph of
  Fortification). Hero Creator presets Elf, Guard; styles Stars, Lava, Ghostly, Metal, Spotted, Tattoos,
  Mohawk, Wild Hair; outfit pieces named by colour and piece ("Sea Coat", "Heavy Plate").

## Names added 2026-10-13 b (veto any you dislike)

* HUD: To Buy, Clear, Auto, Stash, Grab All, Talents, Backpack, Carrying, Deliver, "Choose an enemy", "Choose an ally
  or a place".
* Courier commands: Return to Base (Home), Retrieve Items (Retrieve), Return Items to Stash (To Stash), Deliver Items
  (Deliver), Transfer Items (Transfer), Speed Burst (Burst), Shield, Auto Deliver (Auto); states Waiting, Moving,
  Going home, Fetching the stash, Picking up items, Delivering, Returning items.

## Neutral camps (2026-10-13 c)

* 14 camps a side as in Dota 7.41 (3 small, 7 medium, 3 large, 1 ancient), two of them pull camps by the safe lane's
  tier 1. Each spawn picks one of its kind's creep groups, never the same twice. Rules and sources: `docs/MECHANICS.md`,
  "Neutrals" (proximity aggro by day, sleep at night, 400 guard radius and 5 s chase, growth every 7:30, stack bounty).
* Each camp is a trampled clearing with a fire that burns day and night (with light), tents or round huts, a drying
  rack, stakes, bones, and a horned-skull totem whose cloth shows the size: small yellow, medium orange, large red,
  ancient violet. Props: `tools/blender/camps.py` (Blender) -> `assets/props/camp_*.glb`; placed by `src/game/camps.gd`.
* Hold Alt: spawn boxes on the ground (yellow; red while something other than the camp's creeps blocks them) with a
  label, and on the minimap. The minimap always shows Dota's camp marks (a triangle, bars for medium and large).

## Game Setup, bots, chat, pings, learning (2026-10-13 c)

* Bots follow Valve's bot design (research in `work/lemondev/2026-10-13-camps-ai-setup/research/bots.md`): a team
  brain hands out roles (1 safe lane carry, 2 mid, 3 off lane, 4 roamer, 5 safe lane support) so every lane is covered
  from three heroes up, and leaves the player's lane to the player (chosen in Game Setup, remembered from earlier games,
  or noticed in the first 2:30; the bot that gives way says so). Each bot scores its modes about 3-7 times a second.
* Bots chat to their team: lanes before the horn, missing enemies, ganks on heroes seen low or alone ("Their Sludge is
  low (35%) in the bottom lane. Going for the kill, Bot Doris come too."), pushes when enemies are dead, defence when a
  building is hit, danger when enemies gather, items they just finished, level 6, stacks. They ping what they call.
* Pings and typed calls from the player are answered: the quickest two or three bots go (by teleport when that is
  faster); others say why not: dead (and when they are back), low health, out of mana, TP on cooldown or none and too
  far, defending elsewhere, too many enemies there, ultimate on cooldown, the carry farming early, or simply not now.
* Difficulty follows Dota's bot levels (reaction delay, last hit error, spell lockouts). Unfair (your numbers, 2026-10-16 b):
  +200% gold (passive gold too) and +50% experience; melee Unfair bots buy a Jump Knife right after their boots.
* Learning (Options > Game, "Bots learn from games", on by default; "Forget what bots learned" clears it): a fight
  model trained on every fight a bot starts, a danger map of where heroes died, item builds chosen by UCB1 from their
  results, Shuriken Hook hit rates by distance, a retreat bar per hero, lane matchups, the player's usual lane.
  Options shows a summary. Automated runs and tests never read or write it.
* Adding a hero to the bots: roles, skill order, talents and builds in `src/sim/sim_bot_kits.gd` (and `burst`), the
  combo in `SimBot._spells_on`, AoE farming in `_farm_camp`, escapes in `_escape_spells`.

## Names added 2026-10-13 c (veto any you dislike)

* Screens and buttons: Game Setup, Presets, 5 vs 5, 1 vs 1 mid, Fill with bots, Remove bots, All bots, Set skill,
  Player, Hero, Skill or lane, Name, You, Bot, Empty, Random, Any lane, Safe lane, Mid, Off lane, Start.
* Bot skills (Dota's): Passive, Easy, Medium, Hard, Unfair. Bot names: Bot Kevin, Bot Doris, Bot Nigel, Bot Wanda,
  Bot Mabel, Bot Hank, Bot Tilly, Bot Barry, Bot Pip (with your Bot Gerald).
* Options: Center camera on hero at respawn, Show bot chat, Bots learn from games, Forget what bots learned.
* Camps: Small camp, Medium camp, Large camp, Ancient camp, (pull camp). Chat line: "Say to your team".

## Status effects, bash, critical strike, orbs, true sight (2026-10-13 d)

Run `work/lemondev/2026-10-13-controls-mechanics/` (contract in `contract.md`). Rules and sources: `docs/MECHANICS.md`
("Status effects", "True sight and disjoint", "Orbs", the attack and neutral sections).
* **Controls and HUD**: the cursor lock and edge pan above; the shop closes on a click elsewhere; health and mana show
  your own regeneration and the bonus (items, auras, consumables, the fountain) as a second, brighter "+N"; the comma
  buys a Teleport Scroll; holding S really stops.
* **Pseudo-random chances** (Dota's PRD) for every chance effect; **critical strike** decided when the attack starts
  (red "312!" number); **bash** (only one bash item works, 2.3 s apart, through debuff immunity).
* **Disables**: stun groups refresh to the longer time; hex (the unit becomes a sheep), silence, root, disarm, break,
  mute; status and slow resistance; basic and strong dispels; spell amplification; health restoration amplification.
  A disabled unit shows a **timer bar** under its health with the disable's name and seconds left ("Bashed 0.6",
  "Rooted 1.1"), and a mark on the model (stars, roots at the feet, a violet ring for silence, crossed blades for
  disarm, a red cracked ring for break).
* **New items** (Dota 7.41d numbers, our names; the Dota names are in `docs/MECHANICS.md`): Crit Sword, Crit Bow, Stun
  Club, Stun Blade, Sure Hit Staff, Silence Staff, Root Staff, Halberd, Hex Staff, Break Blade, Heavy Sword, Spell
  Sword, Twin Swords, Battle Staff; parts Huge Sword, Dodge Charm, Long Staff, Mana Tiara (shop: Basics > Big Parts);
  Reveal Ward and Reveal Dust (Consumables). Bots buy some of them and use the disables in fights.
* **Neutral creeps' abilities**: Alpha Wolf crit and aura, Goblin Boss speed aura, Goblin Digger disarm on hit,
  Swamp Troll break on hit, Orc magic resistance aura, Orc Shaman Stomp, Ogre Smash (red ring on the ground during its
  2.8 s wind-up), Wolf Snarl, Lava Golem splash and armor aura.
* **True sight**: towers, the Throne, the fountain, Reveal Wards and Reveal Dust see invisible heroes; invisible heroes
  never auto-attack; blinking, teleporting and turning invisible disjoint projectiles.
* **Orbs** (Dota's runes; "rune" is a banned word here): Gold, Water and Wisdom Orbs and six power orbs (Speed,
  Damage, Stealth, Healing, Magic, Shield) on Dota's timers at our map's spots (river at (-1300, 1300) and (1300,
  -1300), a gold spot in each jungle, a wisdom spot near each side edge). Right click to take one; the kill feed tells
  everyone; bots take the ones they see nearby. A Flask (Dota's Bottle) stores an orb and refills at the fountain.
  Dota's Illusion rune is not in yet (no illusions).
* Other rule fixes: uphill misses only for ranged attacks; evasion and magic resistance from several items multiply;
  the fountain heals 5% / 6% per second and lingers 3 s; Teleport is blocked by roots, mutes and hexes and a root ends
  its channel; healing reduction also lowers regeneration.
* Probes: `godot --path . -s tests/tools/controls_probe.gd -- --out=work/shots` (cursor lock, edge pan, hold Stop, shop
  close, comma, regen, disable bars, crit number, orbs, Smash warning).

## Names added 2026-10-13 d (veto any you dislike)

* Items: Crit Sword, Crit Bow, Stun Club, Stun Blade, Sure Hit Staff, Silence Staff, Root Staff, Halberd, Hex Staff,
  Break Blade, Heavy Sword, Spell Sword, Twin Swords, Battle Staff, Huge Sword, Dodge Charm, Long Staff, Mana Tiara,
  Reveal Ward, Reveal Dust, Flask.
* Orbs: Gold Orb, Water Orb, Wisdom Orb, Speed Orb, Damage Orb, Stealth Orb, Healing Orb, Magic Orb, Shield Orb.
* Neutral abilities: Crit, Pack Aura, Pace Aura, Weapon Grab, Break Strike, Magic Armor Aura, Thick Hide Aura, Splash,
  Snarl, Stomp, Smash.
* Shop groups: Big Parts, Swords, Magic (Upgrades). Hotkey: Buy Teleport Scroll. Option: Lock cursor to window
  (Windowed). Disable labels: Stunned, Bashed, Hexed, Silenced, Rooted, Disarmed, Broken, Muted.

## Elements, armor and damage types, magic amp, item menu, Azrin (2026-10-14)

Run `work/lemondev/2026-10-14-elements-azrin/` (contract in `contract.md`). Rules and tables: `docs/MECHANICS.md`
("Units and stats", "Status effects", "Azrin", "Items and shop").
* **Elements**: None, Fire, Water, Ice, Earth, Lightning, Nature, Dark, Light, on every unit and every damage source.
  Strong x1.25, weak x0.75, each element resists itself, Light and Dark beat each other. Damage numbers show "+25%" or
  "-25%" in the element's colour when it matters.
* **Damage and armor types**: Hero, Slash, Piercing, Siege, Blunt, Magic, Aether (pure) against Hero, Organic,
  Structure, Armored, Titan. Every old Dota pairing keeps its number; Fire Imp and Lava Golem attacks are Magic.
* **Magic amp**: 1% per 20 intelligence; items (Atuli family) stack with diminishing returns (each one half the one
  before). Intelligence magic resistance is now 1% per 25 (was Dota's 0.1% per point).
* **Kugmo, Igit, Atuli** (Sange, Yasha, Kaya) with the pairs Kugmo and Igit (was Twin Swords), Kugmo and Atuli, Igit
  and Atuli (shop: Upgrades > Swords).
* **Item menu**: right click an item (bags or stash): Sell (with the price), Disassemble (parts and scroll come back
  locked), Lock / Unlock, Move to Backpack / Inventory. Locked items show a padlock and never combine.
* **Accidental buy protection**: anything sells for its full price for 10 s after it is bought, and the menu counts the
  seconds down. A combined item keeps the pieces it was made of with their purchase times, so an item disassembled by
  mistake still sells for full price inside the 10 s, and a recipe bought on old parts refunds only the recipe in full.
* **Item effects**: Spike Armor (a turning crown of spikes while active; thorns fly back at attackers), Block Shield
  (a shield flash per block), Spell Shield (golden dome), Rust Stone / Armor Breaker (rust ring under the target),
  Frenzy Mask (red rage), Slip Boots (wind at the feet), Cleave Axe (a sweep across the cone).
* **HUD**: chips above the stats (element, damage type, armor type), each with a hover that explains it from the tables;
  the stats hover is a full sheet (attack; armor and magic resistance with the intelligence part; which elements hurt or
  are resisted; magic amp split into intelligence and items; spell, healing and mana regen amp; cast speed, mana cost,
  lifesteal, evasion, status and slow resistance; burns). The selected unit's card has the same chips and sheet.
* **Creep death sounds** (lane and neutral) 40% quieter: -7.4 dB, the volume sliders' loudness rule.
* **Azrin, the Flamemander**: see MECHANICS.md for every number. Your female_generic model is her body
  (`tools/blender/azrin_body.py`: 2 million faces decimated to 30,000, colours baked from the full mesh into a 2048
  texture with the head given 2.5x the texture space, her joints found from the mesh and fitted onto the hero
  skeleton, so she plays all 132 hero animations). In the Hero Creator it is the body choice "Athletic" (Body tab);
  hair, outfits, dyes and height work on it as on Blood Ranger, and worn pieces hide the skin under them. Face, skin,
  eye and shape sliders only change the standard body. Her default look: dragonhide armour, dark crimson silks, a
  circlet, flame-orange long hair. She hovers 0.75 m up (gliding, leaning into moves) over a pyre on scorched ground,
  with fire in her hands and hair, sparks and a warm light, in matches and on Hero Select.
* **Fire**: `src/game/fire_fx.gd` is a particle fire system used by all Fire: noise-shaded flame tongues (premultiplied,
  so they stay orange in daylight), embers on turbulence, smoke, flickering light, ember beds under burning ground.
  Azrin's spells (`src/game/azrin_fx.gd`): the javelin of fire dragging enemies, spirit-flame marks with a closing
  timer ring and their explosion, orbiting spirits that arc to their target, the tumbling burning hammer and the field
  of fire where it lands; any burning unit is wreathed in flame. Fire Imp and Lava Golem attacks use it too.
* New tools: `tests/tools/menu_probe.gd` (item menu and HUD readouts through real clicks, captures; `--4k`),
  `tests/tools/look_lineup.gd` (a hero's look in several outfits side by side), `tests/tools/fire_preview.gd` (the fire
  on its own). Capture flags: `--items=a,b,c` gives the hero items, `--cast=item:N` uses slot N.

## Names added 2026-10-14 (veto any you dislike)

* Yours (kept as given, now on the owner list): Azrin, the Flamemander, Fiery Javelin, Touch of Ember, Spirit of Fire,
  Divine Smite, Kugmo, Igit, Atuli, the Aether damage type.
* Items: Kugmo and Igit (was Twin Swords), Kugmo and Atuli, Igit and Atuli.
* Elements: None, Fire, Water, Ice, Earth, Lightning, Nature, Dark, Light. Damage types: Hero, Slash, Piercing,
  Siege, Blunt, Magic. Armor types: Hero, Organic, Structure, Armored, Titan.
* HUD: Sell for N gold, Disassemble, Lock, Unlock, Move to Backpack, Move to Inventory, Locked; chips "<type> attack",
  "<type> armor"; sheet headings Attack, Defense, Amplification; Magic Amp, Spell Amp, Healing Amp, Mana Regen Amp,
  Cast Speed, Mana Cost Reduction, Burning; status Burning.
* Hero Creator: Body (Standard, Athletic).
* Azrin's talents: +30 Fiery Javelin burn, +25 Attack Damage, +6% Magic Amp, -2s Touch of Ember cooldown, +2 Spirits of
  Fire, +200 Divine Smite damage, +0.8s Touch of Ember stun, -15s Divine Smite cooldown. Errors: "No spirits of fire",
  "Not enough room", "Cannot be disassembled".
* Elements chosen for existing units (veto freely): Blood Ranger Nature, Ezee Dark, Sludge Earth; creeps by team (Light,
  Dark); towers Earth; neutrals as listed in MECHANICS.md.

## Names added 2026-10-16 b (veto any you dislike)

* Error: "No valid target". Bot chat: "We're ahead in gold. Let's push <lane> and take their <building>."
* Code: `SimKits3.grip_pool`, `SimTeamAI.networth_lead`, `SimBot._boldness`, `_jump_in`, `_plan_knife`,
  `BOOT_UPGRADES`, `SimUnit.gold_mult` / `xp_mult` (was `gain_mult`), `UiKit.held_item_icon`, ability values
  `bounce_distance`, `min_distance`, icons `power_treads_str` / `_agi` / `_int`.

## Names added 2026-10-16 (veto any you dislike)

* Yours: Roydo, the Anomaly, Grip of the Ruler, Void Rush, Dark Matter Skin, Anomaly; Blau, the Master Tactician,
  Bounce Shot, Summon Boulders, Lay Trap, Place Turret.
* Ours: **Pilot Turret** (the Upgrade Staff skill), **Turret** (the unit), **Leave Turret** (the skill's tooltip while
  inside), buff bar "In a Turret", "Piloted", "Caught" (the trap's root).
* Talents (chosen): Roydo "+80 Grip of the Ruler damage" / "+250 Health", "-3s Void Rush cooldown" / "+6% Dark Matter
  Skin chance", "+0.6s Grip of the Ruler stun", "+10% Void Rush damage cut", "+12% Dark Matter Skin reflect", "-0.15s
  Anomaly attack time"; Blau "+50 Bounce Shot damage" / "+25 Attack Speed", "+2 Boulders" / "+0.8s Lay Trap root",
  "+4 Bounce Shot bounces", "+1 Bounce Shot hit per enemy", "+10% Turret damage", "+700 Turret health".
* Errors and tooltips: "Cannot build there", "Must target one of your turrets", "Needs the Upgrade Staff", "Blau
  climbs out of the turret. Moving does the same." Bot chat: "Into the turret."
* Code: SimKits3, SimBot16, Hero16Fx, roydo_skin shader, tools/blender/heroes16.py, tests/tools hero16_probe,
  anim_pops16, _cost16, stall_probe.

## Names added 2026-10-15 g (veto any you dislike)

* Items: **Scarf** (Dota's Shawl), **Spell Cloak** (Cloak), **Fade Cape** (Glimmer Cape). Talent: "+40 Overload
  damage".
* Menu and title: "Press any key", "Choose Hero" (was "Choose hero"), "Tip: ..." (eight tips in `main_menu.gd`).
* Tooltips: "Innate: always learned, from level 1", "Innate: <name>", "Grows with hero level", "Always on",
  "<Value> at level N", "N of M attacks: attack M bursts in an Overload.", "Takes N% more damage from Kragg's
  spells.", Overload's and Magnetize's new descriptions.
* Bot chat: "Getting <item> against their magic damage / their right clicks / their stuns / their invisible heroes /
  their evasion / getting caught.", "Bought <item>, they have invisible heroes.", "Dusting their <hero>.", "Fade Cape
  on you, <name>, run!", "Hold on, <name>! Coming." / "TP coming.", "Running to you, help me turn on them.", "Lost
  them in the trees, going home."
* Code: SimBotItems, SimBotTactics, RepairedClips (was HeroAnims, run h), TitleCard, MenuPlate; skin pieces menu_plate, menu_plate_gold,
  menu_banner, menu_footer, menu_nameplate; tools anim_audit, anim_repair, anim_sheet, kragg_probe.

## Names added 2026-10-15 f (veto any you dislike)

* **Rejuvenation Orb** (your name). **Fortify Mark** (the tower mark in the buff bar).
* Talent: "+1.5s Fast Forward cooldown cut".
* Texts: "Regenerates N per second", "Own N + bonus N", "Healing cut: -N", "Full in N s at this rate", "<name> used
  Fortify", "You used Fortify: buildings protected for 7 s", "Ready in N s", "Fortified towers hit it for N more
  physical damage (N marks).", Fortify's new tooltip lines.

## Names added 2026-10-15 e (veto any you dislike)

* Buff bar effect names: Stunned, Bashed, Frozen, Burning, Fountain, Flying, Health Regen Aura, Mana Regen Aura,
  Invisible (wards), Revealed (Reveal Dust), Armor Loss (corruption), Charge (Kragg's counter), Tired (after Unholy
  Might), Curse (Tainted Touch's curse), Static Charge. Everything else uses its ability, item or aura name.
* Tooltip words: Buff, Debuff, Aura (ally), Aura (enemy), "from <name>", "its own", "N s left of M", "Lasts while in
  range", "Any dispel removes it", "Only a strong dispel removes it", "N more buffs" / "N more debuffs".

## Names added 2026-10-15 c (veto any you dislike)

* Options > Game: **Quick cast** (with the note "Quick cast: a spell or item key casts at once where the mouse points
  (on the unit under it), with no second click."). The bots' learning summary adds "Teamfights called: N (won M)".
* Bot chat: "Fight! Focus their <hero>." (a teamfight call), "Keep going, their <building> next." (a push moving on).

## Names added 2026-10-15 b (veto any you dislike)

* Heroes: **Tock**, title the Clockmaker; skills Time Bolt, Fast Forward, Rewind, Slow Field, Quick Hands, Stop Time.
  **Kragg**, title the Magnet Knight; skills Iron Grip, Repel, Magnetize, Overload, Magnet Field; Charges. Talents:
  "+70 Time Bolt damage", "+2 Mana Regen", "+15% Slow Field slow", "+1.5s Fast Forward cooldown cut" (was "+30% Fast Forward speed"), "-6s Rewind cooldown",
  "+1s Quick Hands", "+1s Stop Time", "+30% Time Bolt delay", "+80 Iron Grip damage", "+6 Armor", "-3s Repel
  cooldown", "+2 max Charges", "+25 Overload damage per Charge", "+40 Magnet Field pull", "+1s Magnet Field stun",
  "+2 Iron Grip Charges".
* Items: Travel Boots, Blast Rod (2-5), Net Staff, Storm Hammer, Soul Gem, Time Crystal, Battle Armor, Small Shield,
  Leech Totem, Frost Plate, Burning Cape, Giant Heart, Leech Blade, Moth Blade, Refresh Stone, Guard Boots, Team
  Shield, War Drum, Long Lens, Crash Knife. Parts: Mana Gem, Swift Stone, Plate Armor, Gold Band, Wide Stone, Relic,
  War Axe, Troll Ring, Feather, Iron Helm, Speed Ribbon. Item powers: Static Charge, Blood Rage, Mend, Guard,
  Endurance; auras Armor Aura, Leech Aura, Battle Aura, Armor Loss Aura, Freezing Aura, Guard Aura, March Aura.
* Shop groups: Casting, Big Weapons, Boots. Stats: Cooldown Reduction, Spell Area, Cast Range, Cooldown Speed.
* Hotkeys: Extra ability 1-6. Debug: God mode, Free spells (shortened), Shop: open.
* Unit panel: Range, Attacks/s, Magic res., Level, Bounty, Experience, Sight day / night, Health regen, Mana regen,
  Invulnerable, Backdoor protection, Grown, Ally, Enemy, Neutral, Lane creep, Siege creep, Neutral creep, Ancient
  creep, Tower, Barracks, Throne, Building, Ward, Courier, No mana, Innate (always on); skill slots True Sight, Sight,
  Backdoor Protection, Fortify, Ancient, Flying; kinds Spell, Aura, Passive, Team.

## Names added 2026-10-15 (veto any you dislike)

* Multiplayer screens: Multiplayer, Servers, Main Server, Main server, Your Servers, Local Network, Join by Address,
  Address, Server password, Save to List, Connect, Host a Server, Server name, Password, Port, Players, Host Server,
  Open the port on my router (UPnP), Add Server, Remove, Refresh, Join Server, Your name, Server Password, Different
  Version, Could Not Connect, Could Not Host, Connecting to ..., Disconnected.
* Server lobby list: Lobbies, Lobby, Leader, Status, Waiting for players, Starting, In a match, Your hero waits, Join to
  play on, Players Online, Name, Where, Lobby list, Server Chat, Create Lobby, Quick Join, Join Lobby, Leave Server,
  Stop Hosting, Hosting, n online, Ping n ms, Lobby name, Teams, 5 vs 5, 1 vs 1 mid, Create, Lobby Password.
* Lobby: Your Hero, Random Hero, Your lane, Ready, Not Ready, Not ready, You are ready, Lobby Chat, Leave Lobby, Fill
  with Bots, Start Match, Lobby Settings, You lead this lobby, Slot, Add Bot, Remove Bot, Remove Player, Open Slot,
  Close Slot, Open, Closed, Click to move here, Waiting for a player, Nobody plays here, (you), Save.
* In a match: Menu, Pause Game, Unpause Game, Leave Game, Back to Lobby, Game Paused, Paused by ..., Waiting for the
  server, Catching up, Waiting for every player to load, Lost the connection to the server.
* Server messages: "... joined", "... left", "... joined the lobby", "... left the lobby", "... leads the lobby now",
  "... is back", "a bot plays their hero until they come back", "That lobby is full", "Wrong lobby password",
  "This server needs a password", "The server is full", "The lobby leader removed you".

## Backlog: smallest next actions first

0. Bots (2026-10-15 c): carries still farm about half what Dota's bots do by 10:00 (the safe-lane wave drifts to the
   enemy's tower and the carry gets zoned: lane control, pulls, standing back); games end but late (50-60 min);
   learning has not yet been shown to make bots stronger (`tests/tools/learn_ab.sh`, more games per arm).
0. Performance: a level-16 ten-hero brawl runs at ~48 fps on the RTX 4060 PC; the rest is the 30 Hz simulation tick
   (~8 ms when it runs), engine deferred work and drawing. Next levers: spread the bots' thinking across frames,
   animate crowds of creeps at a lower rate, or move the simulation's hot loops to C++ (GDExtension; needs a compiler
   and lockstep checks).

0. Multiplayer: set the main server's address (see Status); a blind review of the new screens; a test over the
   internet between two real machines (only this PC was used).

1. Bots: find why two bots stand still in a lane from 0:21 in every 5 v 5 game, then make games end (an Ancient
   falls within 60 min); then the frame time with 10 heroes.
1. Shuriken Hook: recheck the blind review with the frame where the hook has bitten (needs your OK, it changes the
   capture rule), with a shorter chain shadow.
2. Blind reviews not yet run: the shop, Sludge on Hero Select, the Options screen.
3. Map art (both reviews plateaued): modelled props and hand-painted paving instead of procedural boxes; decide
   whether to raise levels to 3-4 m with rock cliff faces beside the ramps.
4. Ezee's look on Hero Select: lighter or more reflective armour (the review plateaued on a dark silhouette).
5. Dark Stomp art: hand-painted spike texture with ground mounds; units visibly lifted by the eruption.
6. Performance: find the p95 spikes (p99 about 22-28 ms in both old and new builds).
7. Art pass on buildings:
   * Better Ancient design: floating crystal and rune ring instead of the stick arms.
   * Larger stone blocks on towers.
   * Replace the paving texture, which reads as a checkerboard.
8. Done: Hero Creator, Hero Select, Town Portal, buyback, courier, pause and settings menus, end screen with damage
   table, orbs (runes), Flask (Bottle), Reveal Ward and Dust. Still deferred: Roshan (pit, Aegis, cheese), illusions
   (and with them the Illusion orb and a Manta-style item), neutral items, Tormentors, shrines and outposts, scan,
   destroying orbs by attacking them, the Lava Golem's Fireball, the Fire Imp's spell aura, wards UI polish.
10. Dota mechanics still marked APPROX in `sim_const.gd` (hero kill gold, respawn times, true sight radii of towers,
   the Throne and the fountain, the Goblin Boss aura as flat speed): check them against Liquipedia when its API answers
   again (it returned 429 on 2026-10-13).
11. Bots: buy and use the Flask, Reveal Dust and Reveal Wards against invisible heroes; contest the river orbs as a team.
9. More heroes (the bot plays Blood Ranger, Ezee and Sludge, mid only). Mana Boots in a bot build.
