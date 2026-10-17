# Warriors of Aether: mechanics reference

The simulation (`src/sim/`) reproduces Dota 2's rules. This file lists each rule, where it lives in the code, and
where its numbers came from. Values marked **APPROX** in `src/sim/sim_const.gd` are best-known figures that could not
be checked against the game files. They are kept in one place so they are easy to correct.

## Sources

| Source | What it gave | Where kept |
|---|---|---|
| Dota 2 game data (`scripts/npc/npc_units.txt`, `npc_abilities.txt`, `items.txt`, `heroes/*.txt`) via the public d2vpkr mirror on GitHub | Exact unit stats (creeps, towers, barracks, Ancient, fountain, neutrals), creep attack classes (`creep_irresolute`, `creep_piercing`, `creep_siege`), backdoor protection, flagbearer aura, item stats and costs, hero base stats | `work/research/` (local research cache, not shipped) |
| Liquipedia Dota 2 wiki pages, fetched through the MediaWiki API before Liquipedia rate-limited the requests | Wave timing and composition, lane creep target priority and aggro rules, tower targeting, attack animation and turn-rate formulas, XP table, deny XP, gold sources, time of day, stacking | `work/research/*.txt` |

On 2026-10-13 (run d) Liquipedia's API answered 429; the status-effect rules came from the Dota 2 wiki on Fandom
(MediaWiki API, one batched request per set of pages, cached in `work/lemondev/2026-10-13-controls-mechanics/research/`)
checked against Valve's 7.41d game data. Fandom's pages are older than 7.41 in places; where they differ, the game data
wins.

Liquipedia later blocked plain page requests. On 2026-10-12 its MediaWiki API (gzip, spaced requests, as its API terms require) answered again; it gave the Trees, Quelling Blade, Tango, Iron Branch, Channeling, Lifesteal and Forced movement pages and four game constants: tree respawn time 180, tree respawn radius 150, item lifesteal creep factor 0.4, tree collision size 128. Global constants that only exist there as `{{G|...}}` templates (aggro radius, kill-gold formula and similar) use best-known values and are marked APPROX.

## Time and space

* Fixed 30 Hz tick, the same rate as Dota's server (`SimConst.TICK_RATE`). It is deterministic: given the same seed and the same order stream, a match plays out identically.
* Distances are Dota units; 1 unit renders as 1 cm. The map spans -9216..9216 on both axes (2026-10-17 d; it was
  -8192..8192). Lanes, bases and the jungle are unchanged; the extra ground is open beyond the top and bottom lanes and in
  the two river corners (see "Map sites"), rock beside the bases.
* The clock starts at -1:30 (pre-horn). It is night before the horn. Waves spawn at 0:00, then day and night alternate every 5 minutes.

## Units and stats

* Attributes follow 7.3x: 22 HP and 0.1 HP regen per strength, 1/6 armor and 1 attack speed per agility, 12 mana and 0.05 mana regen per intelligence. The primary attribute adds 1 damage per point. Heroes have 120 base HP, 75 base mana and 25% base magic resistance.
* **Owner's rule (2026-10-14, not Dota):** every 25 intelligence gives 1% magic resistance (0.04% per point; Dota gives
  0.1%) and every 20 intelligence gives 1% **magic amp** (0.05% per point). Both are continuous, not in steps.
* Armor: `1 - 0.06a / (1 + 0.06|a|)`.
* Damage and armor types (owner's request 2026-10-14; `SimConst.DAMAGE_TABLE`). Every unit has a damage type for its
  attacks and an armor type. Every pairing that existed in Dota keeps Dota's number (Liquipedia "Attack Damage",
  `creep_siege`): the old classes Default (heroes), Runty, Piercing, Reinforced and Default (non-heroes) are now Hero,
  Slash, Piercing, Siege and Blunt; Dota's siege creep penalties are the Armored armor type. Magic is magic damage
  (spells, and the attacks of the Fire Imp and Lava Golem, which meet magic resistance instead of armor); Aether is
  pure damage. Titan is Roshan's (unused until Roshan is in).

  | Damage \ Armor | Hero | Organic | Structure | Armored | Titan |
  |---|---|---|---|---|---|
  | Hero (heroes) | 100% | 100% | 50% | 50% | 100% |
  | Slash (melee lane creeps) | 75% | 100% | 70% | 70% | 75% |
  | Piercing (ranged creeps, Swamp Troll) | 50% | 150% | 35% | 105% | 50% |
  | Siege (siege creeps, towers, fountain) | 100% | 100% | 250% | 70% | 50% |
  | Blunt (neutrals) | 100% | 100% | 70% | 70% | 100% |
  | Magic (magic damage) | 100% | 100% | 0% | 100% | 75% |
  | Aether (pure damage) | 100% | 100% | 100% | 100% | 100% |

  Armor types: heroes Hero; creeps, neutrals, wards and couriers Organic; buildings Structure; siege creeps Armored.
  Physical spell damage (Burst Shot's arrows, cleave) meets armor but no row, as in Dota.
* **Elements** (owner's request 2026-10-14; `SimConst.element_mult`): None, Fire, Water, Ice, Earth, Lightning,
  Nature, Dark, Light. Every unit has one, and so does every damage instance: an attack carries its attacker's, a spell
  its ability's (the hero's unless the ability names another), an item its own, returned damage the element that came
  in. A winning element deals x1.25, a losing one x0.75; every element but None resists itself (x0.75); Light and Dark
  beat each other; None is neutral both ways. Beats: Water > Fire, Fire > Ice, Fire > Nature, Earth > Fire,
  Ice > Nature, Ice > Earth, Water > Ice, Lightning > Water, Earth > Lightning, Nature > Water, Nature > Earth.
  * Heroes: Blood Ranger Nature, Ezee Dark (Tainted Touch is Lightning), Sludge Earth (Stench is Nature), Azrin Fire.
  * Lane creeps take their team's element (Ancient Light: Light, Black Sun: Dark), so both sides' creeps deal x1.25
    to each other and the lane stays even. Towers, barracks and statues are Earth; each Throne and fountain its team's.
  * Neutrals: Goblins Earth, Wolves Ice, Orc Nature, Orc Shaman Lightning (its Stomp is Earth), Swamp Troll Water,
    Ogre Earth, Fire Imp and Lava Golem Fire. Items: Shock Hammer Lightning, Silence Staff Dark, Reveal Dust Light;
    the rest carry no element. Couriers and wards: None.
  * The multiplier applies after amplification and before armor or magic resistance, to every damage type.
  * Mechanics tests of other rules switch it off (`SimWorld.elements`); matches always play with it.
* Attack speed is clamped to 20..700. Time between attack starts is `BAT / (AS/100)`. Attack point and backswing both scale with attack speed.

## Orders and attacks (`sim_orders.gd`)

* A unit turns before it walks, attacks or casts. It only acts once the target is within 11.5 degrees of its facing. Turn rate is radians per 0.03 s.
* Attack flow: windup (attack point), then release (melee hits instantly, ranged launches a homing projectile), then backswing.
  * Cancelling the windup costs no cooldown.
  * Cancelling the backswing is free, which is what makes orb walking and stutter stepping work.
  * Once a windup has started, the target may move up to 250 units beyond attack range before the attack is cancelled.
* Attack range is measured edge to edge (hull to hull).
* Attack-move fights the nearest enemy within acquisition range. Hold position attacks only within attack range.
* An idle hero auto-attacks the nearest visible enemy within acquisition range.
* Denies: allied lane creeps below 50% HP, allied buildings below 10%.
* Misses (Dota 2 wiki, Evasion): true strike (pierce) first, then the target's evasion, then for **ranged** attacks
  from lower ground (not flying attackers) the 25% uphill miss (APPROX value). Melee attacks never miss uphill. Each is
  its own pseudo-random roll, so they stack diminishingly. Evasion from several sources multiplies:
  1 - (1 - a)(1 - b). Buildings never evade.
* Critical strike (Dota 2 wiki, Critical Strike): rolled when the attack **starts** (the wind-up), not when it lands.
  Sources roll from the largest multiplier down and stop at the first proc, so two never stack; sources that did not
  roll keep their pseudo-random counters. The multiplier scales the attack damage, the bonus damage and the creep
  bonus (Mini-Axe), not bash damage, pierce damage or Masterful Archery. Never against buildings or wards (no roll is
  counted there). Cleave and lifesteal use the multiplied damage. The red number shows the damage before the target's
  armor.
* Bash (Dota 2 wiki, Bash): only one bash item works (the first in the bags; Dota: the one held longest). Chance by the
  holder's attack type (25% melee, 10% ranged), 1.2 s stun in the bash group, extra physical damage added to the attack
  (counted by armor and lifesteal, not by crits). While its 2.3 s cooldown runs it does not roll at all. Pierces debuff
  immunity; not against buildings or wards; works on allies being denied. Strong dispel removes it.

## Lane creeps (`sim_ai.gd`)

* Waves come every 30 s starting at 0:00. Each wave is 3 melee and 1 ranged creep.
  * +1 melee at waves 31, 61 and 91.
  * +1 ranged at wave 81.
  * Siege creeps on wave 11 and every 10th wave after it: 1 per lane, 2 from wave 61, 3 from wave 121.
  * A flagbearer replaces a melee creep on wave 5 and every 2nd wave after it.
* Upgrades every 7:30, capped at 30 for HP and damage. Gold and XP bounty upgrades have no cap.
* Destroyed barracks make the enemy's lane spawn super creeps.
* Targeting: the first enemy that enters acquisition range, ranked by unit type, then threat, then distance.
  * Unit type: heroes and units first, then siege creeps, buildings, wards. Siege creeps rank buildings first.
  * Threat: attacking this creep, then attacking one of its allies, then anything else.
  * The type check runs continuously. The distance and threat checks only run when the creep would have to move.
  * A started attack always finishes before the creep switches target.
* When a creep leaves its lane to chase, it remembers the spot and walks back to it afterwards.
* Hero aggro:
  * Type 1: an attack order on an enemy hero pulls enemy creeps within 500 of the attacker for 2.3 s, then starts a 3 s cooldown.
  * Type 2: starting an attack animation on any hero pulls nearby enemy creeps.
  * Hand-cast attack modifiers (the frost orb) draw no aggro.
  * De-aggro: attack-ordering one of your own units makes creeps and towers look for another target.

## Towers and buildings

* Tower targeting: unit type (checked continuously), then threat, then distance.
  * Hero protection: a hero within 700 of a tower who attacks another hero becomes the tower's target.
* Invulnerability chain:
  * Each tower tier needs the previous tier in its lane destroyed.
  * Barracks and effigies need their lane's tier 3 destroyed.
  * Tier 4 towers need any tier 3 destroyed.
  * The Ancient needs both tier 4 towers destroyed.
* Backdoor protection: tier 2 towers and in-base buildings take 50% less damage and regenerate what enemies dealt, unless enemy lane creeps are near. Tier 2 towers use a 900 radius around themselves; in-base buildings use 4000 around the Ancient. The protection lingers 15 s after creeps arrive.
* Fortify (Dota's Glyph): buildings are immune for 7 s and lane creeps for 3 s. Cooldown 5 min; first available at
  3:00. Owner's rules 2026-10-15, in place of Dota's 5 extra projectiles: while it lasts, tier 2+ towers' shots fly 50%
  faster, splash every other enemy within 300 of where they land (full attack damage, not buildings, wards or
  couriers), and mark each enemy they hit: a Fortify Mark lasts 15 s (a new one renews them), and every mark adds 50
  physical damage to Fortified towers' shots on that unit, the hit that adds it included (not added to debuff-immune
  units; marks they carry still count). The allies are told who pressed it. A team of bots presses it for a building
  in danger (under 35% with two attackers, under 60% with four including a hero, or a tier 2+ tower with three enemy
  heroes fighting under it); a team with a human leaves it to the humans.
* Building bounties: team gold to every enemy hero, plus last-hit gold. Denied towers pay a reduced amount.

## Gold and experience (`sim_combat.gd`)

* 600 starting gold. Passive gold is reliable, about 90 per minute rising over time (wiki table).
* Last hits pay the creep's bounty to the killing hero only. Creeps killed by creeps give no gold.
* Creep XP is shared by heroes within 1500. A denied creep gives 50%. A creep killed by a neutral gives full XP.
* XP table: levels 1..30 (`XP_TABLE`).
* Hero kills: base gold + level × 8 + streak bonus + first blood (APPROX). Assist gold is shared by heroes in range or who recently damaged the victim, scaled by team net worth.
  * Hero kill XP is shared, and the killer always gets a share.
  * Dying loses unreliable gold equal to net worth / 40 (APPROX).
  * Respawn time scales with level (APPROX table).
* Kill credit when a hero dies to creeps or a tower goes to the last enemy hero who damaged them within 20 s. If none did, the gold is split across the enemy team.

## Neutrals

Their Dota abilities (npc_units / npc_abilities 7.41d; our names; passives and auras are off while the creep is
broken):
* Goblin Digger (Kobold Soldier): Weapon Grab, its attack disarms for 3 s, 9 s apart.
* Goblin Boss (Kobold Foreman): Pace Aura, +12 movement speed to its camp (APPROX: flat).
* Wolf (Giant Wolf): Snarl, cast when an enemy hero is within 300: enemies there deal 60% less attack damage for 4 s.
* Alpha Wolf: Crit (20% for 200%) and Pack Aura (+20% base damage to its camp).
* Orc (Centaur Courser): Magic Armor Aura (+20% magic resistance to creeps, +10% to heroes).
* Orc Shaman (Centaur Conqueror): Stomp, 25 magic damage and a stun (1.6 s heroes, 3 s others) within 250, 12 s.
* Swamp Troll (Hill Troll Berserker): Break Strike, its attack breaks for 3 s, 10 s apart.
* Ogre (Ogre Bruiser): Smash, a 2.8 s wind-up (its area glows red on the ground), then 200 magic damage and a 2.4 s stun
  within 200 of the point; walking out avoids it.
* Lava Golem (Black Dragon): Splash (full attack damage to enemies within 250 of the target) and Thick Hide Aura
  (+3 armor). (Fireball not yet.)

Sources: Liquipedia "Neutral Creeps" and "Creep Stacking" (cached and Wayback copies, March 2026), Valve's 7.38-7.41
patch notes; details and links in `work/lemondev/2026-10-13-camps-ai-setup/research/camps.md`.

* Camps: 14 a side as in 7.41: 3 small, 7 medium, 3 large, 1 ancient. Two are pull camps beside the safe lane's tier 1
  (a small and a large one). The tier counts are derived from Liquipedia's 7.39 table plus Valve's 7.40 and 7.41 changes
  (*APPROX*: no source states the 7.41 count directly). Positions are our own map's.
* Each spawn picks one of the camp kind's groups at random, never the same group twice in a row: small = 3 Goblins, a
  Goblin Digger and a Goblin Boss, or 2 Swamp Trolls and a Goblin Boss; medium = 2 Wolves and an Alpha Wolf, an Orc and
  an Orc Shaman, or 2 Swamp Trolls and an Ogre; large = 2 Orcs and an Orc Shaman, or 2 Ogres and an Orc Shaman;
  ancient = 2 Fire Imps and a Lava Golem. (Dota has more groups per tier; we use the creeps we have models for.)
* Camps spawn at 1:00 and on every minute after, only when nothing stands inside the camp's spawn box at that moment:
  heroes, lane creeps, wards and the camp's own neutrals all block it; couriers do not. Spawn boxes are rectangles,
  each camp its own size (no source gives Dota's sizes: ours are 520 x 440 for small up to 720 x 600 for ancient).
* Holding Alt shows the spawn boxes in yellow, as in Dota (Alt + click still pings). A box turns red while something
  other than its own creeps stands in it (our addition: Dota's box does not change colour).
* Aggro: by day an enemy within 125 wakes a camp (the owner's rule, 2026-10-15: a neutral never picks a fight from
  farther than 125; it was 240); at night neutrals sleep. Damage wakes the neutral and its campmates
  within 500. A neutral chases until it has been outside its 400 guard radius for 5 s (the timer resets if it comes
  back inside), then walks home; for 3 s after that damage cannot wake it again. Woken again on the way home it chases
  for only 3 s. They do not attack wards, couriers or buildings, and they target the closest enemy.
* Lane creeps and neutrals (the owner's rule, 2026-10-15): lane creeps leave a camp sitting in its box alone. They
  attack a neutral only while it is aggressive: fighting anyone, and for 5 s after it stops. Pulling works by waking a
  camp and leading it into the lane creeps. Towers never attack neutrals. The large pull camp and the medium camp by
  the safe lane's tier 2 sit farther from the lane (their boxes no longer touch the lane), so passing waves do not
  wake them.
* Growth: every 7:30 from the horn, up to 30 times, every neutral gains +30 health, +0.5 armor, +3 damage,
  +5 attack speed, +1 gold and +5 experience (new spawns get the current count).
* Stacks: the creeps spawned by a stack give 20% less gold and experience (7.39e). When an ally kills them, the hero who
  first woke the stacked camp gets 30% of the gold and experience that ally got.
* Measured stacking window in tests: pulling at :53.5 stacks a medium camp. That matches Dota's usual :53-:55.
* *APPROX*: what wakes neutrals other than damage and walking close (single-target spells without damage wake them in
  Dota; we have none), and fleeing from invisible attackers (not done).

## Status effects (`sim_status.gd`)

Sources: Dota 2 wiki pages Pseudo-random distribution, Stun, Status Resistance, Dispel, Hex, Root, Silence, Disarm,
Break, Invisibility, Disjoint; Valve's game data for the numbers.

* **Pseudo-random distribution** for every chance effect: critical strike, bash, evasion, the uphill miss, pierce,
  chain lightning, damage block, Masterful Archery, Blood Ranger's back leap and Unholy Might. The N-th roll since the
  last proc succeeds with chance C x N; C is found by bisection so the average equals the listed chance (25% -> C
  0.0847, 30% -> 0.1189, as Valve's table). Each unit has its own counter per effect; a roll that cannot happen
  (on cooldown, against a building) does not count.
* **Debuffs from enemies** go through `SimStatus.apply`: refused by debuff immunity unless the effect pierces it (bash,
  the Stun Blade) and by invulnerability; their time is multiplied by (1 - status resistance). Effects from allies are
  never shortened.
* **Stun groups**: every regular stun shares one modifier ("stunned"), every bash another ("bashed"); a new one keeps the
  longer of the two times (a short stun never cuts a long one). Stuns keep the unit's orders, which resume afterwards.
* **Status resistance** and **slow resistance** multiply between sources; the Heavy Sword family (Heavy Sword, Twin
  Swords, Stun Blade) does not stack with itself: the largest value counts. Slow resistance shrinks movement slows.
* **Hex**: silence + mute + disarm, base movement speed 140 (flat and percentage bonuses still apply), ends channels.
  Only a strong dispel removes it.
* **Silence** ends channels and blocks spells, not items or passives. **Mute** blocks items. **Disarm** blocks attacks.
  **Root** blocks movement, Jump Knife and Teleport (and ends a Teleport channel), not attacks or spells. **Break**
  turns off the unit's own passive abilities (Masterful Archery, the neutrals' passives and auras), never item
  passives.
* **Buffs and debuffs** (the HUD's buff bar, `src/ui/buff_bar.gd`): a debuff is any disable, slow, extra damage
  taken, healing cut, reveal or burn, an enemy aura, Kragg's Charge, or an effect whose stats are all negative (armor
  or attack speed loss); everything else is a buff. Each instance shows on its own, as in Dota.
* **Dispels**: basic removes slows, silences, roots, disarms, mutes; strong also removes stuns and hexes. An enemy's
  dispel removes buffs instead. Auras are never dispelled.
* **Health restoration amplification** (Kugmo family, 12-16%) raises regeneration, heals and lifesteal; healing
  reduction (Stench with the Upgrade Staff) now also lowers regeneration. **Spell amplification** (the Damage Orb) raises
  every non-attack damage the unit deals, except returned damage and attack-derived procs (cleave, pierce, splash).
  **Mana regeneration amplification** (Atuli 20%, its pairs 30%; the largest counts) raises mana regeneration.
* **Magic amp** (owner's rule 2026-10-14) raises the magic damage a unit's spells and items deal (not attacks, returned
  damage or procs that Dota does not amplify), added to spell amplification: damage x (1 + spell amp + magic amp).
  Sources: intelligence (1% per 20), items (Atuli 10%, Kugmo and Atuli 12%, Igit and Atuli 12%) and talents. Item
  sources diminish: largest first, each one counting half as much as the one before (10% + 10% = 15%). The HUD's stats
  sheet shows the intelligence and item parts.
* **Burns** (`SimStatus.add_dot`): damage over time, magic, ticking every 0.5 s from 0.5 s after it starts, each cast
  its own instance; refused by debuff immunity; the unit shows "Burning". Divine Smite stretches every Fire burn in its
  area. Not removed by dispels.
* The HUD draws a timer bar under a disabled unit's health (stun, hex, silence, root, disarm, break, mute; the strongest
  one), with its name and the seconds left.

## True sight and disjoint (`sim_vision.gd`, `sim_combat.gd`)

* Invisible units are seen only under **True Sight** and only where the team has vision: towers (700, APPROX), the
  Throne (900, APPROX), the fountain (1200, APPROX), Reveal Wards (1050, Dota's Sentry Ward: invisible, 7 minutes, no
  sight of their own but 150 for their first 12 s) and Reveal Dust (Dota's Dust of Appearance: 1050 around the thrower
  for 12 s, the debuff lingers 8 s, 20% slow while invisible, 25 damage to units invisible when it is thrown).
* Invisible heroes never attack on their own; turning invisible disjoints projectiles once (unless the enemy has True
  Sight over the unit).
* **Disjoint**: a blink (Jump Knife), a teleport, and turning invisible make projectiles flying at the unit lose it and
  fall where it stood.

## Channelling, forced movement, lifesteal

* Teleport Scroll: an item, so mutes and hexes block it and end its channel; roots block it and end its channel
  (Dota's "root disables" flag). Bought at the shop it goes into the Teleport slot; bought away from the shop it waits
  in the stash (the courier brings it) and moves into the slot when it reaches the hero. Pressing its key (or clicking
  its slot) twice within 0.5 s teleports to your own fountain at once, as Dota's double tap does.
* Channels (Town Portal, Burst Shot): mana and cooldown are spent when the channel starts. Any new order ends it
  (move, attack, stop, hold, another cast), except an item that acts at once without a target (Zap Stick). Stuns,
  silence, roots and pushes end it too. Shift-queued orders wait until it finishes. The HUD shows a channel bar.
* Forced movement: a push (Dark Stomp, Gale Impact) disables the unit while it flies; Blood Ranger's back leap does
  not (she keeps her orders and can attack, but cannot walk until she lands).
* Lifesteal heals from the physical attack damage after armor (in full even when the blow kills), never from spells,
  buildings or wards. Item lifesteal heals 40% against creeps; ability lifesteal (Blood Ranger) does not.

## Trees (`sim_map.gd`, `sim_world.gd`)

* Trees block movement (one 64-unit pathing cell each) and sight (their 128-unit vision cell).
* Any tree that falls (Mini-Axe, Vegan Picker, Gale Impact, a unit hurled into it) grows back 180 s later. It waits
  while any unit stands within 150 of it, then grows the moment the ground is clear.
* Mini-Axe (Quelling Blade): 100 gold; +8 attack damage against creeps for melee heroes, +4 for ranged; Chop Tree
  from 350, 4 s cooldown, no cast point.
* Vegan Picker (Tango): 90 gold for 3; eats a tree within 165 for 7 HP/s over 16 s (32 s on a planted tree); a new
  one refreshes the buff.
* Tree Twig (Iron Branch): Plant Tree within 400, consumed; the planted tree stands 20 s, never regrows, cannot be
  planted in the fountain area, and units standing on its cell step aside.

## Vision (`sim_vision.gd`)

* Each team has a 128-unit vision grid. Sight is cast as rays that stop at trees and at higher ground. The grid updates at 10 Hz.
* Heroes see 1800 by day and 800 by night. Tier 1 towers see 1900 by day and 800 by night; higher-tier towers see 1100 at night.
* Units outside your team's vision cannot be targeted or seen. Buildings stay drawn in the fog.

## Orbs (`sim_orbs.gd`; Dota's runes, renamed because "rune" is a banned word)

Source: Dota 2 wiki pages Runes, Bounty Rune, Wisdom Rune, Water Rune, Haste, Amplify Damage, Invisibility,
Regeneration, Arcane and Shield Rune (cached in `research/fandom2.json`, `fandom4.json`).
* Spots on our map: two in the river (-1300, 1300) and (1300, -1300) (Dota's power rune spots), one gold spot in each
  jungle, one wisdom spot near each side edge. A hero takes an orb within 150 (a right click on it; orbs come before
  units under the cursor). Orbs are seen only in vision; the minimap shows the ones your team sees.
* Gold Orb (Bounty): 0:00 at the two gold spots and both river spots, then every 4:00 at the gold spots. Every hero of
  the team gets 40 + 6 per 4 minutes of reliable gold.
* Rejuvenation Orb (Dota's Water rune; named by the owner 2026-10-15): 2:00 and 4:00 in both river spots, never
  after: 40 health and 80 mana at once.
* Wisdom Orb: 7:00 and every 7:00 at both wisdom spots: 280 experience per 7 minutes to the hero who takes it and to
  the team's hero with the least experience (the next one if that is the taker), alive or dead.
* Power orbs from 6:00 every 2:00 in one river spot chosen at random; each cycle shows every kind once and the same
  kind never comes twice in a row. A river orb not taken vanishes when the next one comes; gold and wisdom orbs stay
  (a new one lies beside an old one).
  * Speed (Haste): 550 speed that slows cannot lower, 22 s (+3 s per cycle).
  * Damage (Amplify Damage): +80% base attack damage and +15% spell damage, 45 s.
  * Stealth (Invisibility): invisible after a 2 s fade for 45 s; 25% less damage taken while invisible (+5% per cycle);
    broken by attacking or casting.
  * Healing (Regeneration): 6% of max health and mana per second for 30 s, 1% for 3 s after damage from a hero; ends
    when both are full.
  * Magic (Arcane): 25% shorter cooldowns and 30% cheaper mana costs (spells and items), 50 s.
  * Shield: a barrier absorbing damage of every type up to 50% of max health, 75 s.
* Flask (Dota's Bottle; 675 gold, Consumables): 3 charges of 110 health and 60 mana over 2.7 s (lost to damage from an enemy hero),
  refilled to 3 at the fountain. An orb taken while carrying it is stored (gold and rejuvenation orbs refill it to 2 charges, the
  others to 3) and let out by drinking, or by itself after 90 s (lost if the hero is dead then).
* Not yet: the Illusion rune (the game has no illusions), destroying orbs by attacking them.

## Map sites (`sim_sites.gd`; Dota's Twin Gates, Lotus Pools and Watchers with plain names, 2026-10-17 d)

Sources: Liquipedia "Twin Gate", "Lotus Pool", "Healing Lotus", "Watcher", "Channel"; Dota 2 patch notes 7.38, 7.40,
7.41e (read through search summaries: Liquipedia and the Fandom wiki refused direct fetches that day).
* Where: the outer ground. Each river corner (north-west, south-east) holds a Warp Gate on one bank and a Lily Pond on
  the other; two Lookout Lamps a side, one beyond the bottom lane (Dusk: top) and one west of the top lane's north end
  (Dusk: east of the bottom lane's south end). Right click a gate or lamp to walk to it and channel; walk into a pond.
* Warp Gate (Twin Gate): a hero within 200 channels 4 s for 30 mana (given back when the channel breaks) and steps out
  beside the other gate. No cooldown, no disjoint beyond the teleport's own (projectiles in flight miss). Stuns,
  silences, roots (7.41e) and any new order break it; damage does not. Units without mana pay nothing.
* Lily Pond (Lotus Pool): a Healing Lily grows every 3:00 (the first at 3:00 here; APPROX), at most 6. Heroes of one
  team within 350 of the pond gather: the first lily after 1.5 s, each next one in a row 30% faster (1.05, 0.74 s...).
  An enemy hero in the area pauses it (7.38; 7.41 makes it run backwards: not done). Each lily goes to a random hero of
  the gathering team there: 125 health and 125 mana at once (Dota's lotus is an item usable on an ally within 400: here
  it is taken at once).
* Lookout Lamp (Watcher): a hero within 300 channels 1 s (7.40) to light it for its team for 7:00: ground sight 800 by
  day, 450 by night (7.40). Channelling a lamp the other team holds puts it out for 2:00, during which nobody can light
  it. Lamps give no true sight.
* Bots: gather lilies when hurt (or low on mana) near a pond with lilies and no enemy hero near; light a dark lamp they
  pass within 1100 when nothing threatens; take a Warp Gate when it shortens a walk of 5000+ by 30% or more (the 4 s
  channel counted as walking), never while fighting or running.
* Not yet: Tormentors (they need Upgrade Gem effects for every hero first), Wisdom Shrines, streams with currents.

## Regeneration and the fountain (`sim_world.gd`)

* Each tick a unit restores `regen_rates(u)`: its own regeneration (base + attributes) plus the bonus (items, talents,
  auras, consumables, the fountain), times (1 + health restoration amplification) x (1 - healing reduction). The HUD
  shows the two parts separately ("+2.5 +32.4").
* Fountain (Rejuvenation Aura, Dota 2 wiki): 5% of max health and 6% of max mana per second within 1200; the buff
  lingers 3 s after leaving.

## Azrin, the Flamemander (`sim_abilities.gd`; the owner's hero, 2026-10-14)

Ranged intelligence, Fire, range 665 (owner's). Chosen: Str 18 +2.2, Agi 21 +1.8, Int 27 +3.4, damage 24-30, BAT 1.6,
attack point 0.6, projectile 1000, speed 290. Owner's numbers below; mana, cast ranges, speeds and widths are chosen.
* **Fiery Javelin (Q)**: flies 300-1000 toward the point (1400 speed, 150 wide). Every enemy near its path is caught
  once: it burns for 35/70/105/140 magic damage per second for 5 s and, unless debuff-immune, is dragged along with the
  javelin to where it lands. 12 s, mana 100-130.
* **Touch of Ember (W)**: 300 area within 700: 100 magic damage, then spirit flames for 4 s. When the enemy casts a
  spell, or when the 4 s end, the flames explode for 100/200/300/400 magic damage and a 1.7 s stun. 9 s, mana 110-140.
* **Spirit of Fire (E)**: every other spell Azrin casts adds a spirit (up to 5; lost on death). Cast at a 250 area
  within 800: all spirits fly there; each burns enemies for 100/150/200/250 over 5 s and slows them 20/25/30/35% for
  the burn. 4 s, 50 mana (chosen). Needs a spirit.
* **Divine Smite (R)**: a hammer homes on an enemy within 700 (1100 speed). On arrival every Fire burn on enemies within
  400 lasts 2 / 3.5 / 5 s longer, then the target takes 250 + 2 x intelligence magic damage. 45 s, mana 150-250.
* Talents (chosen): +30 Fiery Javelin burn / +25 damage; +6% magic amp / -2 s Touch of Ember; +2 spirits / +200 Divine
  Smite damage; +0.8 s Touch of Ember stun / -15 s Divine Smite.

## Items and shop (`sim_shop.gd`, `sim_items.gd`)

* **Item menu** (right click an item in the bags or the stash): Sell (shows the gold; in a shop, or from the stash
  anywhere), Disassemble, Lock / Unlock, Move to Backpack / Inventory. **Locked items never combine**. **Disassemble**
  follows Dota's rule (`ItemDisassembleRule`): every combined item can be taken apart, anywhere, except the ones Dota
  marks never (Gold Glove = Hand of Midas, Upgrade Staff = Aghanim's Scepter); only the buyer can. The parts and the
  recipe scroll take the item's slot and free slots (bags, then the stash; refused if they do not fit), keep its
  purchase time for selling, and are **locked** so they do not combine straight back. Switch Boots come apart into the
  recipe they were built with.
* Kugmo and Atuli also makes spells and items cost 25% less mana; Igit and Atuli casts 25% faster (cast points / 1.25)
  (Dota 7.41d `manacost_reduction`, `cast_speed_pct`).

* Stats, prices, recipes, actives and passives come from Dota 7.41d `items.txt`, checked against Liquipedia
  (`work/lemondev/2026-10-13-sludge-items/research/`). Names are ours.
* Inside the base shop's radius, purchases go straight to the inventory (then the stash). Elsewhere they go to the
  stash (6 slots), which empties into your bags when you arrive in the shop's range (or when you respawn). After that,
  items stay where you put them: in the base you can drag items between the bags and the stash, click a stashed item
  to take it, or use Grab All (also while dead). Stashed items can be sold from anywhere.
* Full refund within 10 s of buying, half after that (accidental buy protection). A combined item remembers the pieces
  it was made of and when each was bought: each piece refunds in full during its own first 10 s (a recipe bought on old
  parts refunds only the recipe in full), and disassembling gives those same pieces back, so an item taken apart by
  mistake still sells for its full price inside the 10 s. Only the buyer can sell an item. The item menu shows the price
  and the seconds of full refund left.
* Backpack: 3 slots that give no bonuses; an item moved from the backpack to a main slot waits 6 s before it can be
  used (*APPROX*: Dota's swap cooldown).
* Items on the ground (Dota: drag an item out of the inventory): the hero walks within 150 and drops it; anyone can
  pick it up (right click) and it keeps its owner. Giving: drag onto an allied hero or your own courier; the hero walks
  within 150 and hands it over if they have a free slot. Never to enemies.
* To Buy (Dota's quick buy): Shift + click an item in the shop adds it broken into the parts you still miss (parts
  already listed count as owned). Up to 24 entries are kept and 8 shown. Left click buys an entry now, right click
  sets it to buy itself as soon as gold allows. **Owner's rule (not Dota):** an auto-buy made away from the shop goes
  to your courier if it waits at the fountain; otherwise to the stash. A purchase removes its entries.
* Courier (one per player; Dota 7.23 rework, 7.27 and 7.35 changes; `npc_units.txt`, `npc_abilities.txt`):
  * Its level is its owner's. Speed 290 + 20 per level (owner's rule 2026-10-15; Dota: + 10); walks with pathing until
    its owner reaches level 6 (owner's rule; Dota: 4), then flies straight over trees, cliffs and walls (flying
    vision). Vision 200. Passes through units.
  * Dies to hits, not damage (7.35): one melee hero attack, two ranged hero attacks, six of anything else (*APPROX*:
    a spell counts as one hit). Heals only in the fountain. Respawns after 60 + 6 x level (7.35). Every enemy hero
    gets 25 + 5 x level gold (*APPROX*, 7.23 notes). It keeps what it carries while dead.
  * Commands (`courier_*` abilities): Return to Base, Retrieve Items, Return Items to Stash, Transfer Items, Deliver
    Items (retrieve then transfer), Auto Deliver (toggle: sets out whenever the stash, its bags or the Well hold
    something), Speed Burst from level 10 (+50% for 6 s, 120 s), Shield from level 20 (invulnerable 2 s, 200 s).
  * Retrieve and Deliver first pick up the owner's items lying in the fountain area (the Well, within 1000 of the
    fountain), nearest first, then take the stash. What does not fit in the hero's bags stays on the courier.
  * Items on the courier count as owned for the shop's plans and combine with each other there.
* Recipes: an item with a recipe cost needs its scroll ("Recipe: X"), bought like any item. Parts combine on their own
  the moment the last one arrives: in the inventory, in the stash alone, or across both while in the base. The result
  takes the first part's slot. Buying a finished item buys only the parts (and scroll) you are missing, and is undone
  when the result would not fit. Switch Boots have three recipes; the third part sets the starting attribute.
* Boot speed does not stack (the fastest pair counts). Auras from two copies of an item do not stack; auras refresh
  every 6 ticks and linger 0.5 s. Random procs roll only when the item is carried, so replays stay exact.
* Spell Shield: debuff immunity, 60% magic resistance and a basic dispel for 9 s, one second less each use down to 7.
  Jump Knife: 1200 range (farther points land 960 toward them), off for 3 s after damage from an enemy hero. Push
  Staff: 600 over 0.5 s the way the target faces, not a disable, cuts trees. Cleave Axe (melee only): 60% of the attack
  to other enemies in a cone (150 wide at the attacker, 360 wide 650 away), 40% to creeps, ignoring armor. Shock
  Hammer: 25% for 110 magic damage chaining to 4 enemies within 650. Armor Breaker: -6 armor for 7 s, +2 damage per
  hero kill (+1 per assist, up to 30). Spike Armor: returns 10 + 15% of attacks; active returns 85% of all damage for
  5.5 s. Block Shield: 60% chance to block 50 (25 ranged). Sneak Blade: invisible after 0.3 s for 17 s, +20% speed, the
  breaking attack deals 175 extra. Gold Glove: kills a non-ancient enemy creep for 160 gold, 2 charges, 90 s each.

| Our name | Dota 2 | Our name | Dota 2 |
|---|---|---|---|
| Tough Band | Bracer | Spell Shield | Black King Bar |
| Smart Band | Null Talisman | Jump Knife | Blink Dagger |
| Swift Band | Wraith Band | Cleave Axe | Battle Fury |
| Zap Wand | Magic Wand | Shock Hammer | Maelstrom |
| Switch Boots | Power Treads | Gold Glove | Hand of Midas |
| Slip Boots | Phase Boots | Spike Armor | Blade Mail |
| Mana Boots | Arcane Boots | Upgrade Staff | Aghanim's Scepter |
| Armor Breaker | Desolator | Upgrade Gem | Aghanim's Shard |
| Push Staff | Force Staff | Sneak Blade | Shadow Blade |
| Block Shield | Vanguard | Medic Kit | Mekansm |
| Mana Ring | Ring of Basilius | Leaf Hat | Headdress |
| Steady Ring | Perseverance | Greatsword | Claymore |
| Steel Hammer | Mithril Hammer | Spear | Javelin |
| Giant Axe | Ogre Axe | Rust Stone | Blight Stone |
| Big Healing Ring | Ring of Health | Mana Stone | Void Stone |
| Health Crystal | Vitality Booster | Big Gem | Point Booster |
| Wizard Staff | Staff of Wizardry | Pointy Hat | Wizard Hat |
| Sneak Charm | Shadow Amulet | Brass Knuckles | Blitz Knuckles |
| Fur Hat | Fluffy Hat | Plate Vest | Splintmail |
| Mini-Axe | Quelling Blade | Vegan Picker | Tango |
| Crit Sword | Crystalys | Crit Bow | Daedalus |
| Stun Club | Skull Basher | Stun Blade | Abyssal Blade |
| Sure Hit Staff | Monkey King Bar | Huge Sword | Demon Edge |
| Silence Staff | Orchid Malevolence | Root Staff | Rod of Atos |
| Halberd | Heaven's Halberd | Hex Staff | Scythe of Vyse |
| Break Blade | Silver Edge | Kugmo (owner's name) | Sange |
| Atuli (owner's name) | Kaya | Kugmo and Igit | Sange and Yasha |
| Igit (owner's name) | Yasha | Kugmo and Atuli | Kaya and Sange |
| Igit and Atuli | Yasha and Kaya | | |
| Battle Staff | Oblivion Staff | Dodge Charm | Talisman of Evasion |
| Long Staff | Mystic Staff | Mana Tiara | Tiara of Selemene |
| Reveal Ward | Sentry Ward | Reveal Dust | Dust of Appearance |
| Tree Twig | Iron Branch | Frenzy Mask | Mask of Madness |
| Travel Boots | Boots of Travel | Blast Rod (1-5) | Dagon (1-5) |
| Net Staff | Gleipnir | Storm Hammer | Mjollnir |
| Soul Gem | Soul Booster | Time Crystal | Octarine Core |
| Battle Armor | Assault Cuirass | Small Shield | Buckler |
| Leech Totem | Vladmir's Offering | Frost Plate | Shiva's Guard |
| Burning Cape | Radiance | Giant Heart | Heart of Tarrasque |
| Leech Blade | Satanic | Moth Blade | Butterfly |
| Refresh Stone | Refresher Orb | Guard Boots | Guardian Greaves |
| Team Shield | Crimson Guard | War Drum | Drum of Endurance |
| Long Lens | Aether Lens | Crash Knife | Overwhelming Blink |
| Mana Gem | Energy Booster | Swift Stone | Hyperstone |
| Plate Armor | Platemail | Gold Band | Crown |
| Wide Stone | Chasm Stone | Relic | Sacred Relic |
| War Axe | Reaver | Troll Ring | Ring of Tarrasque |
| Feather | Eaglesong | Iron Helm | Helm of Iron Will |
| Speed Ribbon | Wind Lace | Scarf | Shawl |
| Spell Cloak | Cloak | Fade Cape | Glimmer Cape |

### Magic defence items (run 2026-10-15 g; Dota 7.41d items.txt)

* **Scarf** (Shawl, 450): +10% magic resistance. **Spell Cloak** (Cloak, 900): +18% magic resistance. Magic
  resistance from items stacks multiplicatively with the hero's own.
* **Fade Cape** (Glimmer Cape, 2150 = Sneak Charm 900 + Scarf 450 + recipe 800): +20% magic resistance. Use (15 s,
  125 mana) on an ally or itself within 600: after 0.5 s it is invisible for 5 s and moves 20% faster; at once it gets a
  barrier that takes the next 375 magic damage (physical and pure go through) for 5 s. Attacking or casting ends the
  invisibility, not the barrier. Turning invisible dodges projectiles in flight unless the enemy has true sight there.

### Cooldowns, spell area, cast range (run 2026-10-15 b)

* **Cooldown reduction** (Time Crystal = Octarine Core, 25%): a spell or item cooldown starts that much shorter. Several
  items do not stack (the largest counts); the Magic Orb's cut multiplies with it. Teleport cooldowns too.
* **Cooldown rate** (ours, for Tock): a modifier stat `cooldown_rate` moves every running cooldown of a unit each tick:
  +1 runs twice as fast, -0.4 runs 40% slower, -1 stands still. Time Bolt (slower) and Stop Time (frozen) use it; Refresh Stone finishes every spell cooldown (not items, as Refresher Orb in this patch).
* **Spell area** (Wide Stone = Chasm Stone +40, Net Staff and Frost Plate +75; largest counts): added to every
  `radius` or `*_radius` value of a hero's spells (not sight radii). **Cast range** (Long Lens = Aether Lens +225,
  Blast Rod +60..+180): added to spell and item cast ranges, to the reach of line shots that always fly their full
  distance (Shuriken Hook, Gale Impact, Fiery Javelin...; as Dota's Meat Hook), to Leap Strike's search radius and to
  Jump Knife's 1200 / 960. Copies of one source stack with diminishing returns (owner's rule 2026-10-15 c, not
  Dota's): the largest counts in full, each next copy half the one before (two Long Lenses +337.5, three +393.75;
  Blast Rods of any level are one source). Different sources add fully: items, talents (a `cast_range` stat or an
  ability's own `range`) and buffs (`cast_range` in a modifier's stats). The ability tooltip shows the cast range now,
  and the stat sheet the bonus.
* **Item auras with a target side**: Small Shield (+2 armor), Leech Totem (allies +2 armor, +1 mana regen, 20% lifesteal
  for heroes / 12% for creeps, +18% base damage; its owner gets only the armor and mana), Battle Armor (allies and
  allied buildings +30 attack speed and +5 armor; enemies and enemy buildings -5 armor), Frost Plate (enemies -40
  attack speed), Guard Boots (+2.5 health regen, +17 below 25% health, +1.5 mana regen), War Drum (+15 speed, +2.5
  regen). Burning Cape burns enemies within 650 for 60 magic damage a second (Fire). One copy of each aura counts.
* Actives: Blast Rod 400/500/600/700/800 magic damage (27-15 s); Net Staff roots every enemy in a 325 area for 2 s
  (a net flies at each at 1900); Storm Hammer's chain lightning 25% for 180 to 12 targets, Static Charge on an ally for
  12 s (20% when attacked, 225 to up to 4 enemies within 900, 1 s apart); Frost Plate's ring spreads at 400 to 825:
  225 damage and -40% speed for 4 s; Leech Blade +145% lifesteal for 6 s; Guard Boots heal 325 and 200 mana in 1200
  and basic dispel their owner; Team Shield: allies within 1200 block 70 + 2% of its owner's health from every attack
  for 7 s; War Drum: +35 attack speed and +13% speed for 6 s in 1200 (Dota's charges are left out: *chosen*); Crash
  Knife jumps like the Jump Knife, then 100 + 50% strength magic damage, 100% strength over 6 s and a 50% / -50 slow
  within 800. Travel Boots teleport with no scroll to an allied building or creep (40 s cooldown).
* Giant Heart regenerates 1% of max health and 1.5% of missing health a second (this patch's values).

## Tock, the Clockmaker and Kragg, the Magnet Knight (`sim_kits2.gd`; ours, run 2026-10-15 b)

Every number below is *chosen* (no Dota hero is copied); the owner may tune them in `sim_data.gd`.
* **Tock** (ranged intelligence, Light; Str 19 +2.0, Agi 17 +1.7, Int 25 +3.2, damage 21-27, range 575, speed 295):
  Time Bolt (Q, line 1000 at 1400, 120 wide: 90/150/210/270 magic, enemy cooldowns 30/40/50/60% slower for 4 s;
  10-7 s), Fast Forward (W, ally 700: 2/3.5/5/6.5 s off the
  target's basic spell cooldowns at once, not its ultimate or items (owner's rule 2026-10-15), and 10-22% speed for 5 s;
  18-12 s), Rewind (E: back
  to where he stood 3 s ago with that health, and that mana less the cost, basic dispel, disjoint; 28-16 s), Slow
  Field (D, 350 area for 5 s: 30-45% slower, -40 to -100 attack speed; 18-12 s), Quick Hands (F, passive: each spell
  cuts his other cooldowns by 1/1.5/2/2.5 s), Stop Time (R, 400 area: enemies stunned and their cooldowns frozen for
  2.5/3/3.5 s, through Spell Shield; 110/95/80 s).
* **Kragg** (melee strength, Lightning; Str 25 +3.1, Agi 14 +1.6, Int 17 +1.8, damage 31-37, armor 2, speed 300):
  four skills and an innate (owner's rework, run 2026-10-15 g). Charges on enemies (one counter per unit, up to 4,
  8 s). **Magnetize** (innate: learned at level 1, no point, no slot; shown in the bottom panel's small slot, in the
  talent button's tooltip and at the head of the talent tree): his attacks add a Charge; each Charge makes the enemy
  take 0.10% + 0.05% per hero level more damage from his spells (level 1: 0.15%, level 30: 1.6%, so 6.4% at 4
  Charges); Break stops it. Iron Grip (Q, enemy 650: both slide to meet halfway in 0.3 s, 80-200 magic, stun
  0.8-1.4 s, +2 Charges; 14-11 s), Repel (W, 375: 60-180 magic, a physics push 25% stronger per Charge, 30% slow 2 s,
  crashes 40-130 and 0.8 s stun, +1 Charge; 13-10 s), **Overload** (E, passive: every 6th / 5th / 4th / 3rd attack he
  lands on an enemy unit (not buildings or wards) bursts electric charge round him: enemies within 200 take
  60/75/90/105 magic damage of the Lightning element (raised by their Charges) and are slowed 80% for 0.8 s (status
  resistance shortens it); the count shows in his buff bar; Break stops it), Magnet Field (R, 6 s: enemies within
  700 dragged toward him at 60/80/100 + 15 per Charge, +1 Charge a second; at the end 100/175/250 and a 1/1.5/2 s
  stun within 300; 100/90/80 s). Talent "+40 Overload damage" replaces "+25 Overload damage per Charge"; "+2 max
  Charges" now makes 6. Interpretation of "0.10% (+0.05 per hero level)": the per-level part is multiplied by his
  current level (say if you meant it to start at level 1 with 0.10%).

## Roydo, the Anomaly and Blau, the Master Tactician (`sim_kits3.gd`; the owner's heroes, run 2026-10-16)

The owner gave the kits and their numbers; *chosen* marks what he left open (tune in `sim_data.gd`).
* **Roydo** (melee intelligence, no element ("Neutral"); *chosen*: Str 21 +2.6, Agi 18 +1.8, Int 24 +3.2, damage
  28-34, armor 2, base attack time 1.7, attack point 0.4, speed 305).
  * **Grip of the Ruler** (Q, point 650, area 400): one unit in the area is picked at random among the enemy heroes
    Roydo's team sees; with none, among the other enemies (creeps, summons; not buildings, wards, couriers, debuff
    immune or invulnerable units); with no enemy at all, among allies (Roydo himself excluded). It is thrown to the
    area's middle (open ground nearest it) on an arc over 0.8 s, over trees and cliffs, disabled in the air (it plays
    its knockback clip). When it lands, every enemy in the area takes 100/140/180/220 magic damage and is stunned 1 s
    (status resistance applies). A thrown ally is neither hurt nor stunned. 18-15 s, 100-130 mana.
  * **Void Rush** (W, no target, 650 round him, 7 s): enemies get -20/30/40/50% status resistance (their debuffs
    last longer: 1 / (1 - (-0.5)) = 1.5 times at level 4) and deal 10/15/20/25% less damage of every kind (a
    "damage dealt" modifier on the source, applied before the target's reductions; reflected damage is not
    changed). Allies, Roydo too, get +7/9/11/13 armor and +7/9/11/13% move speed. Basic dispel removes either.
    15-12 s, *chosen* 80/90/100/110 mana.
  * **Dark Matter Skin** (E, passive): each instance of damage he takes from an enemy has a 9/13/17/21% chance
    (pseudo-random, like Dota's chance passives) to send 25/28/31/34% of the damage he actually took (after his
    reductions) to every enemy within 650 as magic damage, with an 80% move speed and 80% attack speed slow for
    0.3 s. Break stops it; the returned damage is never returned again.
  * **Anomaly** (R, 30 s, 65 s, *chosen* 100/125/150 mana): base attack time -0.25 s (1.7 -> 1.45; Dota's
    Chemical Rage and Metamorphosis also lower the base attack time rather than raise attack speed), +60/120/180
    attack damage, ranged attacks at 650 (*chosen* projectile speed 1200). His items count as a ranged hero's while
    it lasts.
* **Blau** (ranged agility 600, no element; *chosen*: Str 18 +2.0, Agi 23 +3.1, Int 18 +1.8, damage 22-28, attack
  point 0.35, projectile speed 3000, speed 295).
  * **Bounce Shot** (Q, point 800): a bullet (*chosen* speed 2400, path 1800 in all) flies toward the point and
    passes through enemies, hurting each *chosen* 70/110/150/190 magic damage at most twice (once per pass). It
    ricochets like a mirror off trees, cliff walls, buildings, boulders and units of Blau's team (not Blau himself),
    3/5/7/9 times; the next thing it meets after the last bounce stops it. *Chosen* 12-9 s, 90-120 mana.
  * **Summon Boulders** (W, aimed by direction): 3/4/5/6 boulders (radius 58) roll out within 0.6 rad either side of
    the aim for a random 1-2 s each (*chosen* starting speed 520-760, slowing evenly to a stop), bouncing off walls,
    trees, buildings, each other and units. An enemy they run into takes 80/100/120/140 magic damage once per cast
    and is knocked 200 back (a 0.3 s disabling slide; not debuff immune enemies). Resting boulders block every
    walking unit, phased ones too (exact circles for movement, their cells closed for paths), and Bounce Shot
    bounces off them. 10 s, 20-17 s, *chosen* 100-130 mana.
  * **Lay Trap** (E, no target): Blau leaps 400 straight back (over trees and units, 0.5 s, landing on open ground)
    and leaves a trap where he stood. *Chosen*: it arms after 0.6 s, is then hidden from enemies (True Sight shows
    it), lasts 25 s and catches the first enemy unit within 110: rooted 1.2/1.6/2/2.4 s (status resistance applies).
    10-7 s, *chosen* 50-65 mana.
  * **Place Turret** (R, point 600, 3 levels at 6/12/18): a turret (a summon) with 900/1500/2100 health, no
    regeneration, no mana, *chosen* 4 armor, shoots enemies within 650 every 1.5 s (base attack time 1.5, attack
    speed fixed) for 25/30/35% of Blau's attack damage (+5% with the Upgrade Staff, so 40% at level 3: the owner's
    four numbers). Each shot is a copy of Blau's attack at that share: his critical strike, lifesteal and item
    attack effects apply, and kills are his. Its target: the enemy hero Blau is fighting, else the weakest enemy
    hero, another turret, a creep it can finish, the weakest enemy, then buildings. 35 s; 10 s cooldown, *chosen*
    100/125/150 mana; *chosen* bounty 40-50 gold, 40 experience (none when it runs out of time).
  * **Pilot Turret** (Upgrade Staff, D, one of his turrets within 250): Blau climbs in: hidden, invulnerable, he
    stays on the turret and still attacks and casts from it; the turret gains 300/600/900 health (Place Turret's
    level) and shoots what he attacks. He gets out by casting it again (free, no cooldown), by any move order, or
    when the turret falls or runs out. 5 s cooldown to get in. The skill sits before the ultimate (key D).

## Azrael, the Death Dealer (`sim_kits4.gd`; the owner's hero and 2026-10-17 c rework)

* **Double-click / double-tap self-cast** (`input_controller.gd`): pressing or clicking a targeted spell (`point`, `unit`, `autocast_attack`) or active item (`unit` or `point`) a second time within 0.5 s while its targeting cursor is up casts it on the hero at once (`h` for unit targets, `h.pos` for point targets, `own_turret` for Pilot Turret). Town Portal (`tp`) keeps its double-tap to the team's fountain.
* **Azrael** (melee agility 150, Dark; *chosen*: Str 19 +2.2, Agi 22 +3.0, Int 17 +1.7, damage 27-31, armor 1, attack point 0.35, speed 300).
  * **Soul Tap** (Q, toggle): while toggled on, every 4.5 s Azrael scans a 600 radius around her for living units (allies and enemies, not herself, buildings, wards, couriers or units inside a door). If no valid unit is in range, no mana is spent and it scans again in 4.5 s. If at least one valid unit is in range (and she has 80 mana), it spends 80 mana and grants +20/25/30/35 bonus attack damage per unit scanned plus +40 more per hero scanned for her next attack (15 s duration). That next attack deals **Pure** damage in a 100% cleave over a 400 area (`cleave_distance: 400`), slowing the primary target and all cleaved enemies by 80% for 0.80 s.
  * **Door of the End** (W, point 650, blast radius 450): opens a spirit door for 5/6/7/8 s. Azrael and up to two allied heroes can walk into it (hidden, invulnerable). Any move, attack or item-pickup order issued to a unit inside brings that unit out early at the exit (or entrance if no exit was set) without setting off the explosion. A second cast while the door is open places the exit up to 800 away (free, no cooldown). When the door's duration expires, everyone still inside steps out at the exit in a blast that **heals nearby allies for 100/150/200/250**, deals **150/250/350/450 magic damage** to enemies, **stuns them for 1 s**, and **strips 10/16/22/28% of their elemental resistances for 4 s** (`element_resist_loss`, added to the incoming elemental damage multiplier when hit by an element).
  * **Death Scythe** (E, passive): her attacks and spells (`attack`, `soul_tap`, `door_of_the_end`) have a 15/18/21/24% pseudo-random chance to strike as **Pure** damage with +30/40/50/60 bonus pure damage and **50% lifesteal** of the damage dealt. **1.0 s cooldown** (`proc_cooldown: 1.0`).
  * **Divine Darkness** (R, no target, 25 s duration, 60 s cooldown): free flight over cliffs, trees and units, **+15% movement speed** at all levels, night vision equal to day vision plus +30/50/70% bonus vision, +30/40/50 attack speed, and enemies within 700 lose 30/40/50% of their vision.
