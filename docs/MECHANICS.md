# Warriors of Aether: mechanics reference

The simulation (`src/sim/`) reproduces Dota 2's rules. This file lists each rule, where it lives in the code, and
where its numbers came from. Values marked **APPROX** in `src/sim/sim_const.gd` are best-known figures that could not
be checked against the game files. They are kept in one place so they are easy to correct.

## Sources

| Source | What it gave | Where kept |
|---|---|---|
| Dota 2 game data (`scripts/npc/npc_units.txt`, `npc_abilities.txt`, `items.txt`, `heroes/*.txt`) via the public d2vpkr mirror on GitHub | Exact unit stats (creeps, towers, barracks, Ancient, fountain, neutrals), creep attack classes (`creep_irresolute`, `creep_piercing`, `creep_siege`), backdoor protection, flagbearer aura, item stats and costs, hero base stats | `work/research/` (local research cache, not shipped) |
| Liquipedia Dota 2 wiki pages, fetched through the MediaWiki API before Liquipedia rate-limited the requests | Wave timing and composition, lane creep target priority and aggro rules, tower targeting, attack animation and turn-rate formulas, XP table, deny XP, gold sources, time of day, stacking | `work/research/*.txt` |

Liquipedia later blocked plain page requests. On 2026-10-12 its MediaWiki API (gzip, spaced requests, as its API terms require) answered again; it gave the Trees, Quelling Blade, Tango, Iron Branch, Channeling, Lifesteal and Forced movement pages and four game constants: tree respawn time 180, tree respawn radius 150, item lifesteal creep factor 0.4, tree collision size 128. Global constants that only exist there as `{{G|...}}` templates (aggro radius, kill-gold formula and similar) use best-known values and are marked APPROX.

## Time and space

* Fixed 30 Hz tick, the same rate as Dota's server (`SimConst.TICK_RATE`). It is deterministic: given the same seed and the same order stream, a match plays out identically.
* Distances are Dota units; 1 unit renders as 1 cm. The map spans -8192..8192 on both axes.
* The clock starts at -1:30 (pre-horn). It is night before the horn. Waves spawn at 0:00, then day and night alternate every 5 minutes.

## Units and stats

* Attributes follow 7.3x: 22 HP and 0.1 HP regen per strength, 1/6 armor and 1 attack speed per agility, 12 mana, 0.05 mana regen and 0.1% magic resistance per intelligence. The primary attribute adds 1 damage per point. Heroes have 120 base HP, 75 base mana and 25% base magic resistance.
* Armor: `1 - 0.06a / (1 + 0.06|a|)`.
* Attack classes (Liquipedia "Attack Damage"): Default, Runty (melee creeps), Piercing (ranged creeps), Reinforced (siege creeps and towers), applied against Hero, Non-hero and Structure defense. Siege creeps take 50% damage from heroes and 70% from basic attacks.
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
* Attacks on higher ground miss 25% of the time (APPROX). Evasion rolls first.

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
* Glyph: buildings are immune for 7 s and lane creeps for 3 s. Tier 2+ towers fire 5 extra projectiles. Cooldown 5 min; first available at 3:00.
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

* Camps spawn at 1:00 and every minute after, but only when nothing (unit, hero or ward) stands inside the camp's spawn box. Pulling a camp out of its box just before the minute stacks it.
* Neutrals ignore you until attacked or damaged. Then the whole camp fights back.
  * They give up when they get 1100 from home (APPROX).
  * They also give up when the target has been out of acquisition range for 3 s (APPROX).
* Measured stacking window in tests: pulling at :53.5 stacks a medium camp. That matches Dota's usual :53–:55.

## Channelling, forced movement, lifesteal

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

## Items and shop (`sim_shop.gd`, `sim_items.gd`)

* Stats, prices, recipes, actives and passives come from Dota 7.41d `items.txt`, checked against Liquipedia
  (`work/lemondev/2026-10-13-sludge-items/research/`). Names are ours.
* Inside the base shop's radius, purchases go straight to the inventory. Elsewhere they go to the stash, which empties into your bags when you return.
* Full refund within 10 s of buying, half after that.
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
| Tree Twig | Iron Branch | Frenzy Mask | Mask of Madness |
