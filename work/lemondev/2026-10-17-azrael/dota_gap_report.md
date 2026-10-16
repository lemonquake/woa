# Dota 2 gap report: what Warriors of Aether still lacks

Run 2026-10-17 (azrael). Read-only review of `src/sim/`, `docs/MECHANICS.md`, `docs/HANDOFF.md` against current Dota 2
(7.38 to 7.41 era). Every "we have / we lack" line was checked with a grep or a read of the code; file evidence is
given. Dota numbers come from the sources listed at the end. Where sources disagree or are older than 7.40, it says so.

Legend. **Impact**: how much a Dota player would notice (High / Medium / Low). **Size**: rough work (S = a day or less,
M = a few days, L = a week or more, art and bots included).

## 1. Summary: top 10 gaps by player impact

| # | Gap | Impact | Size |
|---|---|---|---|
| 1 | **Kill economy numbers differ from Dota**: hero kill XP base 40 (Dota 100), kill gold base 110 / first blood 150 (Dota 125 / 135), wrong streak bounty table, no streak XP, assist radius 1200 (Dota 1500) and an older assist formula, respawn at levels 1-5 is 6-16 s (Dota 12-24 s), no buyback respawn penalty | High | S |
| 2 | **Eye Wards are free and unlimited** (no stock), give no bounty when killed, and die to ordinary damage (Dota: stock 2 / max 4, restock 135 s; 2 hero hits / 8 other hits; 100 + 4/min gold) | High | S |
| 3 | **No Attribute Bonus, talents cost ability points, no talent points at 27-30**: after about level 19 our heroes earn points with nothing to spend them on; Dota gives +2 all stats x7 and (7.40) separate talent points at 10/15/20/25/27/28/29/30 | High | S-M |
| 4 | **No Roshan** (pit boss, Aegis, Cheese / Banner, Refresher Shard, day/night pit swap) | High | L |
| 5 | **Upgrade Staff / Upgrade Gem do nothing for 8 of 10 heroes**, and only 2 of 10 heroes have an innate. Dota gives every hero a Scepter and a Shard upgrade and an innate | High | M-L |
| 6 | **No illusions** (Illusion rune, Manta-style item, illusion damage rules), so a whole Dota layer (illusion heroes, split push, dodging with illusions) is missing | High | L |
| 7 | **No Smoke of Deceit and no Scan**: the gank / anti-gank loop of Dota's mid game is absent | High | M |
| 8 | **Missing defensive and control item families** and the status effects they need: spell block, spell reflect, cyclone, ethereal, purge + mana burn, fear, taunt, sleep, leash, blind, a team magic barrier, a "can't die" disc | High | L |
| 9 | **No neutral items** (7.38+ Madstone crafting of artifact + enchantment, tiers by game time) | Medium | L |
| 10 | **7.38-7.41 map layer missing**: Tormentor, Wisdom Shrines (they replaced Wisdom runes), Lotus Pools, Twin Gates, Watchers, streams with currents, Defender's Gates; plus patch drift in things we do have (Haste and Stealth orbs, courier respawn, item lifesteal vs creeps 40% instead of 60%) | Medium | M-L |

Quick wins (all S, mostly constant changes): items 1, 2, the patch drift list in section 11, and the Attribute Bonus.

Note on facets: Dota **removed facets in 7.41** (dota2protips 7.41; GosuGamers). Not having facets is not a gap.

## 2. What the game already matches (inventory, so nobody re-does it)

Checked in code and `docs/MECHANICS.md`: 30 Hz deterministic tick; attribute formulas; armor formula; damage/armor
type table; attack point / backswing scaling, free backswing cancel (orb walking, stutter step), windup cancel with no
cooldown, 250 attack range buffer, edge-to-edge range, turn rate with 11.5 degree facing tolerance; attack-move and hold
position; creep target priority, hero aggro (500 radius, 2.3 s, 3 s cooldown), de-aggro by attacking own unit, tower
hero protection; denies (< 50% creeps, < 10% buildings) and 50% deny XP; wave timings, siege and flagbearer creeps,
super creeps, creep upgrades every 7:30; tower invulnerability chain, backdoor protection, Fortify (Glyph, owner's
version); neutral camps (14 a side), spawn boxes and Alt view, stacking (20% stack penalty, 30% stacker share), pulls,
neutral leash and sleep at night; PRD for every chance effect; crit rolled at attack start; bash rules; evasion and
true strike; uphill miss for ranged attacks; stun groups, hex, silence, mute, disarm, root, break, debuff immunity,
status and slow resistance, basic and strong dispels, spell amp, health restoration amp, burns; true sight sources;
disjoint for attack projectiles; trees (block path and sight, 180 s regrow, Tango, Quelling, Branch); day/night vision;
high-ground ray-cast vision; bounty, water, wisdom and six power orbs on Dota timers; Bottle; Town Portal with
double tap, channel rules; buyback cost and 480 s cooldown; courier (7.35 hit-based health, upgrades); stash, To
Buy, 10 s refund, backpack 6 s; item disassemble; 125 items incl. Aghanim's Scepter / Shard stand-ins; control
groups; pings with danger ping; bots that chat and answer pings; Sentry Ward / Dust (Reveal Ward / Reveal Dust).

## 3. Map objectives

| Dota feature | What Dota does (key numbers) | Our game | Impact | Size |
|---|---|---|---|---|
| Roshan | Pit boss. 6000 HP base, armor 30, 55% magic resist, 25% status resist; grows every minute (+0.4 armor, +7 damage, +130 HP per minute as of 7.39). Abilities: Bash (15%, 1.65 s), Slam (AoE slow, every 10 s), Spell Block (one targeted spell per 15 s), Roar of Retribution vs the team that last killed him (7.38: 600 radius, 2 s disarm). Moves between a top pit (night) and bottom pit (day) from 15:00 (7.38); while moving he throws heroes who run into him. Respawn 8-11 min (game constants 480-660 s). Rewards: 135 team gold each + 200-290 to the killer, XP; drops Aegis every kill (5 min, revive after 5 s), Cheese or Banner from 2nd kill (pit-dependent), Refresher Shard from 3rd. Attacks on him only from inside the pit; pit blocks ground vision; wards cannot be placed inside | Not found: `grep -i roshan src` hits only a comment; the Titan armor type exists in `sim_const.gd` "unused until Roshan is in". Backlog item 8 in HANDOFF | High | L |
| Aegis / Cheese / Refresher Shard / Banner | Aegis: revive at death spot with full HP/mana after 5 s, expires after 5 min (heals instead), can be denied. Cheese: big instant heal, shareable. Refresher Shard: reset cooldowns once. Banner (7.37+): team buff placed on the ground | Not found (`grep -i "aegis\|cheese" src` empty) | High (with Roshan) | M |
| Tormentor | One active at a time, first at 20:00 (7.39), respawn 10 min (game constant 600 s), side follows day/night, always opposite Roshan (7.38; 7.41 swapped side preference). Cannot move or attack. All-damage barrier 3000 + 50 per minute, regen 20 + 5 per minute (7.41). Reflects 30% of damage taken to heroes within 1200, split among them (7.41). The Shining: 20 + 2/min magic DPS near it once hit (7.40/7.41). Reward: an Aghanim's Shard to one of the two lowest net worth heroes without one; if all have it, team gold (415 in 7.41) and XP. Alleviation: heal aura 2.25%/s for 15 s after death (7.41c) | Not found (`grep -i tormentor src` empty). Its reward would also be useless today for 9 of 10 heroes (see section 5) | Medium | M (after shards) |
| Wisdom Shrines | Replaced Wisdom runes in 7.38. Two shrines in the off-lane side jungles; activate every 7 min; a hero must stand within 300 for 3 s; enemy presence pauses (7.41: reverses) the countdown. XP to a random hero in range plus the team's lowest-XP hero; 7.41 amount 200 base +300 per later shrine (200/500/800...) | We still use the pre-7.38 Wisdom rune: `sim_orbs.gd` "Wisdom Orb: 7:00 and every 7:00 ... 280 experience per 7 minutes" (MECHANICS "Orbs") | Medium | S-M (reuse orb spots, add stand-and-hold timer) |
| Lotus Pools | 2 neutral pools at the map's west and east edges. One Healing Lotus every 3 min, max 6 (18 min to fill). 7.38: walk within 350 of the centre to collect, first lotus 1.5 s, each next 30% faster; enemies pause (7.41: reverse) the timer. A lotus restores 125 health and 125 mana at once, can be used on an ally within 400; Great / Greater lotuses unlock with tier 4 / 5 neutral items | Not found (`grep -i lotus src` empty) | Medium | M |
| Twin Gates | Two linked gates near the map corners: channel 4 s within 200, teleports to the other gate; 7.40 cost 30 mana, refunded if interrupted; does not disjoint; Roshan uses them | Not found; "gate" hits are only wall art in `landscape.gd` | Medium | M |
| Watchers | Neutral lanterns: channel 1 s (7.40) within 300 to turn on for your team for 7 min (vision, no true sight; 7.40 night vision 450); channelling an enemy-held one turns it off for 2 min | Not found (`grep -i watcher src` empty) | Medium | S-M |
| Streams and currents | 7.38: outer-rim streams from T3 to T1 give up to +150 (strong) / +100 (moderate) speed going downstream, scaled by facing; jungle streams join them | Not found (`grep -i "stream\|current" src/sim/sim_map.gd` empty) | Low-Medium | M |
| Defender's Gates | One-way base exits to the side paths (7.36+), 700 vision (7.40) | Not found | Low | M |
| Outposts | Removed from Dota in 7.38 ("corner outposts removed"), so not a gap | n/a | - | - |
| Old healing shrines | Gone from Dota; not a gap | n/a | - | - |
| Secret shop | Some parts (Hyperstone, Ultimate Orb, Mystic Staff and similar) are only sold at the secret shops | Only the base shop: `sim_map.gd:62` `shops := [two base positions]`; `sim_shop.gd:25` checks base shop or fountain only | Low-Medium | S-M |

## 4. Orbs (Dota's runes)

| Dota feature | What Dota does | Our game | Impact | Size |
|---|---|---|---|---|
| Illusion rune | Power rune: 2 illusions, 35% damage dealt, 200% (melee) / 300% (ranged) damage taken, 75 s, basic dispel and disjoint on pickup | Missing; `sim_orbs.gd:18` "Dota's Illusion rune is not in the cycle yet: the game has no illusions" | Medium | M (after illusions) |
| Haste rune duration | 7.40: always 22 s ("no longer +3 s per rune cycle") | `MECHANICS.md` Orbs: "22 s (+3 s per cycle)" (Fandom's pre-7.40 value) | Low | S |
| Invisibility rune damage reduction | 7.40: "no longer grants incoming damage reduction" | `sim_orbs.gd:186` `"resist": 0.25 + 0.05 * cycles` | Low | S |
| Wisdom rune | Replaced by Wisdom Shrines in 7.38 (section 3) | Old rune kept | Medium | S-M |
| Destroying runes | Force-attack a rune to destroy it (no last hit) | Missing (HANDOFF backlog item 8) | Low | S |
| Stored bounty value | 7.40: gold is fixed by when the rune spawned, not when it is drunk | Not checked in `sim_orbs.gd`; Fandom (pre-7.40) said activation time | Low | S |

Bounty (40 + 6 per 4 min), Water (2:00 and 4:00), power cycle rules (6:00, every 2:00, no repeat in a cycle) all
match the Fandom Runes page.

## 5. Hero systems

| Dota feature | What Dota does | Our game | Impact | Size |
|---|---|---|---|---|
| Attribute Bonus | Passive in the talent menu: +2 all attributes per level, 7 levels; 7.38 skillable from level 2; 7.40 fully skilled by level 22 | Not found. `sim_combat.gd` `give_xp`: every level gives `ability_points += 1`; `sim_abilities.gd can_learn` only allows abilities and talents. A 4-skill hero has 10 + 3 + 4 = 17 or so places for 30 points, so about 13 points are wasted late game | High | S |
| Talent points | 7.40: talents no longer use skill points; their own points at 10, 15, 20, 25, 27, 28, 29, 30 (the last four let you take the other side of each tier) | `sim_abilities.gd:51-59` talents cost an ability point; `TALENT_LEVELS := [10, 15, 20, 25]` only | Medium | S |
| Aghanim's Scepter / Shard per hero | Every hero has a Scepter upgrade and a Shard upgrade; Shard buyable from 15:00 for 1400 (also granted by Tormentor) | `sim_data.gd`: only Sludge (Shuriken Hook shard, Stench scepter, lines 436/443) and Blau (Place Turret / Pilot Turret, 669/672) have upgrades. The Upgrade Gem (`sim_data.gd:950`, 15:00, 1400) gives nothing to the other 8 heroes | High | M-L (design 16 upgrades) |
| Innate abilities | Every hero has one (7.36+); 7.41 made them fixed or level-scaling rather than tied to other abilities | Only Sludge (`growing_gut`) and Kragg (`magnetize`) have `"innate"` in `sim_data.gd` (lines 240, 312) | Medium | M |
| Universal heroes | No primary attribute; 0.45 damage per point of every attribute (7.38; was 0.7) | No hero uses it; `sim_data.gd` heroes are str/agi/int only | Low | S (rule) |
| Facets | Removed in 7.41 | Not present; nothing to do | - | - |
| Hero count | ~127 heroes | 10 heroes (`sim_data.gd:216-337`) | High for variety, but content, not a rule | L |
| Strength HP regen | Fandom Attributes page: 0.09 per point | `sim_const.gd:120 STR_HP_REGEN := 0.1` | Low | S (verify first) |

## 6. Items and neutral items

### 6a. Neutral items (Dota 7.38+)

What Dota does: killing a whole neutral camp gives Madstone (2 to the hero who cleared it, 1 to a random ally); it is
picked up automatically if no enemy hero is within 800 and an ally within 1200. Madstone has a cap that rises with time
(dota2protips 7.38: 5 at 5:00, 15 at 15:00, 25 at 25:00, 35 at 35:00, 45 at 60:00, unlimited at 70:00). Crafting a
tier costs Madstone (7.41: tier 1 = 6; tiers 2-5 = 10 each; tier 5 re-crafts cost more) and lets you pick one
**artifact** (the active or passive) and one **enchantment** (stats; 7.41: based on primary attribute) from 5 choices
each (7.41). One dedicated neutral slot; crafting replaces the old item. 7.41: tier 1 available from 0:00.

Our game: not found (`grep -i "neutral item\|neutral_item\|madstone" src` empty; HANDOFF backlog item 8).
Impact Medium (Dota players expect a 7th slot and jungle reward). Size L (slot, UI, about 40 artifacts and
enchantments, bot choices).

Sources disagree on tier times (esports.gg: 2:30 / 7:30 / 12:30 / 17:30 / 30:00 for availability; dota2protips gives
the Madstone cap times above). Check against Valve's 7.41 notes before building.

### 6b. Missing Dota item families (and the mechanic each one needs)

Dota names are the reference only; suggested plain names are in section 13.

| Dota item | Mechanic it brings | Our game | Impact | Size |
|---|---|---|---|---|
| Smoke of Deceit | Team invisibility 45 s in 1200, +15% speed, true sight cannot see it, broken within 1025 of enemy heroes/towers; 50 gold, stock 2 / max 3 | Not found (`grep -i smoke src/sim` empty) | High | M |
| Gem of True Sight | Carried true sight, dropped on death | Not found | Medium | S-M |
| Linken's Sphere | Spell block (one targeted spell, 14 s) | Not found (`spell_block` empty) | High | M |
| Lotus Orb | Spell reflect + basic dispel on an ally | Not found | Medium | M |
| Eul's Scepter / Wind Waker | Cyclone: target is lifted, invulnerable, dispelled; self-cast dodge | Not found (`cyclone` empty) | High | M |
| Ghost Scepter / Ethereal Blade | Ethereal: immune to physical, cannot attack, takes more magic damage | Not found (`ethereal` empty) | Medium | M |
| Diffusal Blade / Disperser, Nullifier, Bloodthorn | Mana burn on hit, purge (enemy dispel with slow) | Mana burn not found; enemy dispel exists (`SimStatus.dispel(by_team)`) | Medium | M |
| Manta Style | Illusions + self dispel | No illusions | High | L (after illusions) |
| Aeon Disk | Strong dispel + damage immunity when HP drops low | Not found | Medium | S-M |
| Pipe of Insight / Eternal Shroud | Team magic barrier | Fade Cape has a magic barrier on one unit; no team version | Medium | S |
| Urn of Shadows / Spirit Vessel | Charges from nearby hero deaths; heal ally or damage enemy, healing cut | Not found | Medium | S-M |
| Solar Crest / Medallion | Armor swap on a target | Not found | Low-Medium | S |
| Armlet of Mordiggian | Toggle: +strength, drains HP; toggle tricks | Not found | Low | S |
| Divine Rapier | Huge damage, drops on death and can be taken by the enemy | Not found | Low | S |
| Moon Shard | Consumable attack speed | Not found | Low | S |
| Orb of Venom / Frost / Corrosion | Attack modifiers (stacking slows, healing cut; 7.38 Orb of Frost) | Not found (Rust Stone exists) | Low | S |
| Blood Grenade, Soul Ring, Tranquil Boots, Boots of Bearing, Echo Sabre / Harpoon, Mage Slayer, Skadi, Veil of Discord, Bloodstone, Hurricane Pike, Khanda / Parasma, Witch Blade | Various; most reuse rules we already have | Not found in the item list (125 `_it(` entries in `sim_data.gd`) | Low each | S each |
| 7.41 new items | 7.41 added nine new items (GosuGamers) | Not reviewed here | Low | - |

## 7. Status effects and dispels

| Effect | Dota rule | Our game | Impact | Size |
|---|---|---|---|---|
| Fear | Target runs away from the source, cannot act; dispellable | Not found (`grep -i fear src/sim` empty) | Medium | S |
| Taunt | Target is forced to attack the source | Not found | Medium | S |
| Sleep | Disabled until damaged | Not found as a status (neutral "sleep" at night is unrelated) | Low | S |
| Cyclone | Lifted, invulnerable, cannot act, dispels on cast | Not found | Medium | S-M |
| Ethereal / banish | Physical immunity, no attacks, more magic damage taken | Not found | Medium | S |
| Leash / tether | Cannot move beyond a radius, blocks blink/TP-like moves; Twin Gates cannot be started while leashed | Not found as a status (`leash` only in neutral AI) | Low | S |
| Blind | Attacker's own miss chance | Not found (`grep -i blind src/sim` empty) | Low | S |
| Spell block / spell reflect | Blocks or bounces a targeted spell | Not found | Medium | M |
| Spell lifesteal vs creeps | 7.38: reduced 80% vs non-heroes | Matches: `sim_combat.gd:463` 20% vs creeps | - | - |
| Item lifesteal vs creeps | Fandom: items heal 60% of their value against creeps (7.33c); 7.38: physical lifesteal reduced 40% vs non-heroes (all sources) | `sim_combat.gd:250` heals 40% (`ITEM_LIFESTEAL_CREEP_FACTOR := 0.4`) and ability lifesteal at 100%: the factor looks inverted | Medium | S |
| Lifesteal on a killing blow | Fandom: heal is based on the target's remaining health; 7.41: lifesteal counts overall damage reductions/amps, no lifesteal from attacks that deal no damage | MECHANICS: "in full even when the blow kills" (from Liquipedia). Sources conflict; check the game data | Low | S |
| 7.41 reflect rule | Reflected damage cannot be reflected back, no lifesteal, does not affect debuff-immune units | Partly: `sim_combat.gd:373` "reflected damage is not reflected again"; debuff-immune part not checked | Low | S |
| 7.39 "Bind" | Root and disarm both show as "Bound" | We show "Rooted"/"Disarmed" separately. Cosmetic | Low | S |
| Hero denies | Possible under some debuffs (e.g. Doom-style damage over time) | Not found; only matters once such debuffs exist | Low | S |

## 8. Combat quirks and pro tricks

| Quirk | Dota | Ours | Impact | Size |
|---|---|---|---|---|
| Animation cancel, orb walk, stutter step | Free backswing cancel; windup cancel costs nothing | Have (`sim_orders.gd`, MECHANICS "Orders and attacks") | - | - |
| Turn rate and facing | Radians per 0.03 s, 11.5 degree tolerance | Have (`sim_const.gd:101-103`) | - | - |
| Creep aggro pull / de-aggro | Attack order on enemy hero pulls creeps 500 for 2.3 s, 3 s cooldown; attack own unit to drop aggro | Have (`sim_ai.gd attack_order_aggro`, `deaggro`) | - | - |
| Tower hero protection | Hitting a hero near a tower draws it | Have (700, APPROX) | - | - |
| Deny rules | < 50% creeps, < 10% buildings, 50% deny XP, denied tower gives both teams 50% team bounty | Have (`sim_combat.gd _building_death` pays 50% to all heroes: matches Fandom) | - | - |
| Stack timing :53-:55, pulls | Spawn box must be empty at :00 | Have (measured :53.5) | - | - |
| Creep block at the start | Heroes body-block the first wave | Partial: unit collision exists (`sim_orders.gd _resolve/_blocker`) but creeps sidestep up to 1.4 rad (80 degrees) and no test shows a block works | Medium | S (test + tune) |
| Tree juking | Trees block sight and paths; fog hides you | Have | - | - |
| Uphill miss | 25% for attacks from low ground; 7.41: free-movement (flying) units can now miss too | Ranged only, flying never (`sim_combat.gd` snapshot `flying`); value APPROX | Low | S |
| Disjoint of spell projectiles | Most targeted spell projectiles are dodged by blink, TP arrival, invisibility, Manta | Partial: `SimCombat.disjoint` only walks `w.projectiles` (attacks, `launch_effect` items like Root Staff); homing spells in `w.effects` (Divine Smite "hammer", Touch of Ember "ember", Ice Pulse) are not checked, so they likely cannot be dodged | Medium | S |
| TP cancel and double tap | Cancel any time; double tap goes home | Have | - | - |
| Multiple heroes TP to one place | (Not verified: some sources say later TPs take longer) | Not checked | Low | - |
| Alt-click ability / item to tell team its cooldown or "ready" | Standard Dota habit | Not found (only map pings in `input_controller.gd:542`) | Medium | S |
| Double-tap / Alt to self-cast | Standard | Not found (`grep -i "self" input_controller.gd` finds only Push Staff) | Low-Medium | S |
| Backpack 3 s grace on first entry | 7.38: an item entering the backpack for the first time can come back with no cooldown within 3 s | Not found (`BACKPACK_SWAP_COOLDOWN := 6.0` always) | Low | S |
| Buyback respawn penalty | Next respawn +25 s after a buyback | Not found (`sim_world.gd buyback` sets cooldown only) | Medium | S |
| Neutral death minimum | Dying to neutral creeps sets respawn to at least 26 s | Not found | Low | S |

## 9. Vision

| Dota feature | Dota | Ours | Impact | Size |
|---|---|---|---|---|
| Observer Ward stock | 0 gold, stock 2 initial / 4 max, +1 per 135 s | Free, no stock: `sim_data.gd:799 _it("observer_ward", "Eye Ward", 0, ...)`; `stock` field never read (`grep stock src/sim` hits only the default in `sim_data.gd:776`) | High | S |
| Sentry Ward stock | 50 gold, restock 70 s (7.38) | 50 gold, no stock | Medium | S |
| Ward durability | Observer: 2 hero hits / 8 non-hero hits; 100 HP | `ward_observer` 200 HP, normal damage (`sim_data.gd:158`) | Medium | S |
| Ward bounty | Observer 100 + 4/min gold and 70 + 8/min XP to the killer | Not found (ward def `xp: 0`, no gold) | Medium | S |
| Ward placement rules | Not inside fountain area, Roshan pit, on trees or cliffs; 7.40: not within 300 of a same-type ward placed in the last second | Not checked in `sim_abilities.gd` "ward" case (spawns where clicked) | Low | S |
| Scan | Global 900-radius check for 8 s, 1 s ticks, 2 charges, 210 s replenish (7.34), starts with 1 | Not found (`scan` hits are other words) | Medium | S |
| Smoke vs true sight | Smoke is not seen by true sight | n/a until Smoke exists | - | - |
| Roshan pit vision blocker | Pit blocks ground vision both ways; 7.41c flying vision blocked too | n/a until Roshan | - | - |
| Watchers | See map objectives | Missing | Medium | S-M |
| True sight radii of towers, Ancient, fountain | Still APPROX here (`sim_const.gd:253-255`) | Not verified this run | Low | S |

Day/night (5 min each), hero 1800 / 800 sight, tower sight, high ground and tree blocking, flying vision for couriers:
present.

## 10. Creeps and lanes

| Dota feature | Dota | Ours | Impact | Size |
|---|---|---|---|---|
| Mega creeps | All six barracks dead: mega creeps in every lane | Not found (`grep -i mega src/sim` empty); only super creeps | Medium | S |
| Tier 4 armor per barracks | 7.40: +4 armor per allied barracks alive (+24 max) | Not found | Low | S |
| Early lane speed tweak | 7.41: until 7:30 off-lane creeps slowed briefly, safe-lane sped up; meeting point toward the off lane | Not found | Low-Medium | S |
| Flagbearer 7.40 | Bounty +1 per upgrade, AoE bounty radius 1500, magic resist aura rising 4% per interval (max 15) | Flagbearer exists; these details not verified | Low | S |
| Neutral variety | Many camp types, ancients with abilities | 9 neutral kinds; Lava Golem's Fireball and Fire Imp aura not in (HANDOFF backlog 8) | Low | M |
| Building bounties | Fandom: T1 90 team / 110-130 last hit; T2 110 / 130; T3 125 / 150; T4 145 / 170; ranged barracks 90 / 90-135; melee barracks 155 / 90-135 | `sim_const.gd:209` APPROX: T4 125 / 150, melee rax 90, ranged rax 50, last hits fixed 150 | Low | S |

## 11. Economy and experience

| Rule | Dota | Ours | Impact | Size |
|---|---|---|---|---|
| Hero kill XP | (100 + 0.13 x victim XP) / heroes sharing + streak XP; capped at level 25 values | `sim_const.gd:149` base 40 (APPROX) | High | S |
| Streak XP | (1.25 s^2 - 2.5 s + 10) x victim level, s = streak 3..10 (13.75 x L at 3 up to 110 x L at 10+) | Not found | Medium | S |
| Kill gold base / first blood | 125 + 8 x victim level + streak; first blood +135 | 110 + 8 x level; FB 150 (`sim_const.gd:156-158`, APPROX) | Medium | S |
| Streak (shutdown) gold | 60, 100, 150, 210, 280, 360, 450, 550 for streaks 3..10+ | `sim_combat.gd _streak_gold`: 60 x (streak - 2), cap 480 (APPROX) | Medium | S |
| Assist gold | 7.40: 15 + (50 + victim NW x 0.037) / N, times a net worth factor k (losing team 1 + diff/leader NW, leading 1 - diff/leader NW); radius 1500 | 40 + (140 + NW x 0.037) / N, ratio clamped 0.5-2, radius 1200 (`sim_const.gd:159-162`) | Medium | S |
| Respawn levels 1-5 | 12, 15, 18, 21, 24 s (rest matches ours) | 6, 8, 10, 14, 16 (`sim_const.gd:170`) | Medium | S |
| Buyback penalty | +25 s on next respawn | Missing | Medium | S |
| Courier respawn | 7.40: 45 + 5 x level | 60 + 6 x level (`sim_const.gd:225-226`) | Low | S |
| Courier bounty | Fandom: 25 + 6 x level to each enemy | 25 + 5 x level (APPROX) | Low | S |
| Death gold loss | Net worth / 40, unreliable only | Matches | - | - |
| Buyback cost | 200 + NW / 13, 480 s | Matches | - | - |
| Passive gold, bounty orb, stack share, deny XP, XP table, XP radius 1500 | | Match | - | - |
| Tormentor / Roshan gold | Team gold from objectives | Missing with the objectives | - | - |

Note: the Fandom Gold and Experience pages predate 7.40 in places (they still show the old assist formula with 30 +
NW x 0.038). The 7.40 assist formula is from the dota2protips patch digest. Verify the hero kill gold base against
Valve's 7.41 data before changing it.

## 12. Bots and team UI

| Feature | Dota | Ours | Impact | Size |
|---|---|---|---|---|
| Chat wheel | Radial quick lines ("Missing", "Careful", "Get back", "Need wards"...) | Not found (`grep -i wheel src/ui src/game`: only the camera mouse wheel) | Medium | S-M |
| Ping wheel | Hold to choose ping type (attack, retreat, on my way, ward here, careful) | Two kinds only: normal and Ctrl+Alt danger (`input_controller.gd:542-557`) | Medium | S |
| Alt-click ability/item status | Tells team "X ready / on cooldown N s / need mana" | Not found | Medium | S |
| Roshan / Tormentor timers | 7.38: Roshan status icon; 7.40: Tormentor timer by the minimap, pingable | n/a (no objectives) | - | S with objectives |
| Bots using vision tools | Dota bots ward, deward, smoke | Bots buy Eye Wards (`sim_bot.gd:1694`); HANDOFF backlog 11: no Dust/Reveal Ward use against invisible heroes, no orb contesting as a team | Medium | M |
| Bots: lane control, pulls, creep block | Pros do these every game | HANDOFF backlog 0: carries farm about half of Dota's bots by 10:00, no lane control or pulls | High (for bot games) | M-L |
| Minimap drawing | Ctrl-drag to draw on the minimap | Not found | Low | S |
| Scoreboard | Hold Tab | Have (`scoreboard.gd`) | - | - |

## 13. Suggested plain names for new things (owner veto)

Checked against `lemondev/references/naming.md` (no banned words, no glued compounds, no Dota names). Dota's name is
the reference only.

| Dota (reference) | Suggested name |
|---|---|
| Roshan | Pit Boss |
| Aegis of the Immortal | Extra Life |
| Cheese | Health Cake |
| Refresher Shard | Reset Stone |
| Roshan's Banner | Battle Flag |
| Tormentor | Shield Cube |
| Wisdom Shrine | Learning Shrine |
| Lotus Pool / Healing Lotus | Lily Pond / Healing Lily |
| Twin Gate | Warp Gate |
| Watcher | Lookout Lamp |
| Defender's Gate | Base Gate |
| Mega creeps | Giant creeps |
| Smoke of Deceit | Smoke Bomb |
| Scan | Radar |
| Gem of True Sight | Seeing Gem |
| Neutral items / Madstone | Camp Loot / Camp Stone |
| Artifact / Enchantment | Trinket / Boost |
| Illusion (unit) / Illusion rune | Copy / Copy Orb |
| Linken's Sphere | Block Amulet |
| Lotus Orb | Bounce Amulet |
| Eul's Scepter | Wind Staff |
| Ghost Scepter | Ghost Staff |
| Manta Style | Split Blade |
| Diffusal Blade | Drain Blade |
| Aeon Disk | Last Stand Disc |
| Pipe of Insight | Team Cloak |
| Urn of Shadows | Soul Urn |
| Divine Rapier | Glass Sword |
| Moon Shard | Speed Pearl |
| Attribute Bonus | +2 Stats |
| Universal (attribute) | All-round |
| Chat wheel / ping wheel | Chat Wheel / Ping Wheel |
| Fear / Taunt / Sleep / Cyclone / Ethereal / Leash / Blind | Feared / Taunted / Asleep / Lifted / Ghosted / Tethered / Blinded (status labels) |

"Lifted" for cyclone and "Ghosted" for ethereal are the least obvious; "Cyclone" itself is an ordinary word and not
Dota-specific, so the owner may prefer it.

## 14. Suggested order

1. Constants and small rules (one run, S): kill XP/gold/streaks/assist, respawn 1-5, buyback +25 s, neutral 26 s
   minimum, item lifesteal 60% vs creeps, Haste 22 s fixed, Stealth orb without damage cut, courier respawn, ward
   stock + durability + bounty, Sentry stock, building bounties, T4 armor per barracks, mega creeps.
2. Attribute Bonus and 7.40 talent points (S-M).
3. Scan and Smoke Bomb (M), with bot use.
4. Upgrade Staff / Gem upgrades and innates for the 8 heroes without them (M-L, owner design input).
5. Roshan with Extra Life, Health Cake, Reset Stone (L); then the Shield Cube (Tormentor) once shards exist.
6. Status effects (fear, taunt, cyclone, ethereal, spell block, reflect, blind) with the items that use them (L).
7. Illusions, then the Copy Orb and Split Blade (L).
8. Wisdom Shrines, Lily Ponds, Warp Gates, Lookout Lamps, streams (M-L, map work).
9. Neutral items with Camp Stone crafting (L).

## 15. Could not verify

* Liquipedia's API answered "Rate Limited" on the first request of this run, so Liquipedia was not used. Numbers come
  from the Dota 2 Fandom wiki (MediaWiki API, rendered pages and `{{G|...}}` constants) and patch digests on
  dota2protips.com. Fandom is older than 7.40 in places (its Runes page still shows Haste +3 s per cycle and the
  Invisibility rune's damage cut; its Neutral Items page still describes the pre-7.38 token system; its Tormentor
  constants show the pre-7.41 barrier).
* Valve's own 7.38-7.41 patch notes were not fetched directly; the 7.40/7.41 changes above are from the dota2protips
  digests (which may be truncated; WebFetch read the first 100k characters of each).
* Neutral item tier times: sources disagree (see 6a).
* Hero kill gold base 125 and first blood 135 are Fandom values; not confirmed for 7.41.
* Strength HP regen 0.09 vs our 0.1: one source only.
* Lifesteal on a killing blow: Fandom and Liquipedia (as quoted in MECHANICS) disagree.
* Whether later TPs to the same spot take longer: not confirmed, left out of the tables.
* Creep blocking in our game: not tested, only the collision code was read.
* Ward placement validation in our game: not read in full.
* The nine new 7.41 items and 7.41 hero innate reworks: not reviewed.

## Sources

* Dota 2 Fandom wiki (via `dota2.fandom.com/api.php`, parse and expandtemplates):
  [Roshan](https://dota2.fandom.com/wiki/Roshan), [Tormentor](https://dota2.fandom.com/wiki/Tormentor),
  [Runes](https://dota2.fandom.com/wiki/Runes), [Lotus Pool](https://dota2.fandom.com/wiki/Lotus_Pool),
  [Healing Lotus](https://dota2.fandom.com/wiki/Healing_Lotus), [Watcher](https://dota2.fandom.com/wiki/Watcher),
  [Twin Gate](https://dota2.fandom.com/wiki/Twin_Gate), [Neutral Items](https://dota2.fandom.com/wiki/Neutral_Items),
  [Gold](https://dota2.fandom.com/wiki/Gold), [Experience](https://dota2.fandom.com/wiki/Experience),
  [Heroes (respawn, buyback)](https://dota2.fandom.com/wiki/Heroes), [Attributes](https://dota2.fandom.com/wiki/Attributes),
  [Scan](https://dota2.fandom.com/wiki/Scan), [Smoke of Deceit](https://dota2.fandom.com/wiki/Smoke_of_Deceit),
  [Observer Ward](https://dota2.fandom.com/wiki/Observer_Ward), [Lifesteal](https://dota2.fandom.com/wiki/Lifesteal),
  [Aegis of the Immortal](https://dota2.fandom.com/wiki/Aegis_of_the_Immortal). Game constants expanded:
  Tormentor spawn 1200 s, respawn 600 s, bounty 280; Roshan respawn 480-660 s; XP radius 1500.
* Patch digests: [7.38](https://www.dota2protips.com/patches/7-38), [7.39](https://www.dota2protips.com/patches/7-39),
  [7.40](https://www.dota2protips.com/patches/7-40), [7.41](https://www.dota2protips.com/patches/7-41).
* [Liquipedia 7.38 summary](https://www.liquipedia.net/dota2/7.38) (search result: universal 0.45 per attribute, slow
  resistance raises minimum speed).
* [esports.gg: 7.38 Madstone](https://esports.gg/news/dota-2/dota-2-patch-7-38-madstone/),
  [bo3.gg neutral items guide](https://bo3.gg/dota2/articles/neutral-items-guide-dota-2) (tier times and costs,
  conflicting).
* [GosuGamers: 7.41 removes facets and adds nine items](https://www.gosugamers.net/dota2/news/78166-dota-2-patch-7-41-removes-facets-and-adds-nine-new-items),
  [Hawk Live: 7.41c](https://hawk.live/posts/valve-released-patch-741c-changing-the-mechanics).
