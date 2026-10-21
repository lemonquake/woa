# Gancho, Lord Kaileh, Dracoxinia: hero sheet

The three heroes as they are in the game right now (run 2026-10-21 b). Every number here comes from
`src/sim/sim_data.gd` (`_add_heroes_22`, `_build_abilities_22`, `_build_talents_22`, from about line 1143). Mark
anything you want changed and I will change it. The hero names are yours. Every skill, talent and item name below is
mine, so you can veto any of them.

**How to read the numbers.** Distances are in game units, as in Dota (100 = about 1 m; a melee attack reaches 150,
a tower about 700). A value written `a / b / c / d` is that value at skill levels 1 to 4. Ultimates have 3 levels and
are learned at hero levels 6, 12 and 18. Talents come at hero levels 10, 15, 20 and 25, one of two per level.
Every hero has the game's base 120 health, 75 mana and 25% magic resistance, plus attribute bonuses as in Dota: 22
health and 0.1 health regen per Strength, 1/6 armor and 1 attack speed per Agility, 12 mana and 0.05 mana regen per
Intelligence. The main attribute is also added to attack damage.

## At a glance

| | Gancho | Lord Kaileh | Dracoxinia |
|---|---|---|---|
| Title | the Nature Whisperer | the Grand Cavalier | the Blue Wyrm |
| Role (hero select) | Ranged · Agility · Carry, Disabler, Escape | Melee · Strength · Initiator, Disabler, Durable | Melee · Strength · Carry, Disabler, Durable |
| Element | Nature | Earth | Lightning (her sword's element while she holds another) |
| Strength | 18 + 2.0 | 24 + 3.4 | 23 + 3.3 |
| Agility | 22 + 3.2 | 15 + 1.6 | 19 + 2.2 |
| Intelligence | 17 + 1.9 | 17 + 1.8 | 17 + 1.7 |
| Base damage (before attribute) | 23-30 | 31-39 | 30-36 |
| Base armor (before Agility) | 1 | 2 | 2 |
| Base health regen | 0.25 | 0.75 | 0.5 |
| Attack range | 600 (ranged, projectile 1250) | 200 (lance) | 150 |
| Base attack time | 1.7 | 1.8 | 1.7 |
| Attack point / backswing | 0.4 / 0.5 | 0.45 / 0.5 | 0.45 / 0.5 |
| Move speed | 300 | 300 | 305 |
| Turn rate | 0.7 | 0.6 | 0.6 |
| Vision day / night | 1800 / 800 | 1800 / 800 | 1800 / 800 |
| Collision size | 24 | 26 | 24 |

Worked out with no items:

| | Gancho L1 | Gancho L25 | Kaileh L1 | Kaileh L25 | Dracoxinia L1 | Dracoxinia L25 |
|---|---|---|---|---|---|---|
| Health | 516 | 1572 | 648 | 2443 | 626 | 2368 |
| Mana | 279 | 826 | 279 | 797 | 279 | 769 |
| Armor | 4.7 | 17.5 | 4.5 | 10.9 | 5.2 | 14.0 (19.0 with Dragon Hide 4) |
| Damage | 45-52 | 122-129 | 55-63 | 137-145 | 53-59 | 132-138 |
| Attack speed | 122 | 199 | 115 | 153 | 119 | 172 |
| Seconds per attack | 1.39 | 0.85 | 1.57 | 1.18 | 1.43 | 0.99 |

The level-25 figures leave out talents. Dracoxinia's Dragon Hide adds 2-5 armor and 1.5-6 health regeneration on top.

---

## Gancho, the Nature Whisperer

A tree man who throws thorns with his bare hands. He fights from the trees.
Models from: Hoodwink and Windranger (Dota's ranged agility templates), with ideas from Zyra (League: seeds that grow
plants) and Ivern (League: root vine). Kit code: `src/sim/sim_kits10.gd`. Bot: `src/sim/sim_bot22.gd`.

**Story (hero select):** Gancho grew out of the oldest wood and still talks to it. The trees let him walk straight
through them, his thorns stick and bleed, his vines snatch whoever wanders near, and the seeds he throws grow into
trees in a moment. When he wakes the whole forest, every trunk around him lashes out.

| Key | Skill | Kind | What it does | Mana | Cooldown | Cast point |
|---|---|---|---|---|---|---|
| Innate | **Tree Walk** | passive | Walks through trees as if they were open ground. 20% evasion while within 250 of a tree. Turned off by Break. | none | none | none |
| Q | **Root Snare** | point, line | Throws a vine 1100 far (90 wide, 1500 a second). The first enemy it touches takes 80 / 140 / 200 / 260 magic damage and is rooted 1.2 / 1.4 / 1.6 / 1.8 s. | 90 / 100 / 110 / 120 | 14 / 12 / 10 / 8 | 0.3 |
| W | **Seed Bomb** | point, range 900 | The seed bursts 0.6 s after it lands. Enemies within 250 take 60 / 100 / 140 / 180 magic damage and are slowed 30% for 2 s. A young tree grows where it burst and lasts 15 s. | 80 | 13 / 12 / 11 / 10 | 0.35 |
| E | **Thorn Barbs** | passive | Each attack leaves a thorn in the enemy for 5 s (up to 5; a new one renews them all). Each thorn deals 4 / 6 / 8 / 10 magic damage a second and slows 4%. 5 thorns = 20-50 dps and a 20% slow. | none | none | none |
| R | **Angry Forest** | no target | For 7 s, every second, each tree within 1000 of Gancho lashes the nearest enemy within 350 of it: 35 / 50 / 65 magic damage and a 0.4 s root. A unit is rooted at most once every 1.5 s and takes at most 2 lashes a second. Gancho gets +30 / 45 / 60 attack speed meanwhile. | 150 / 200 / 250 | 90 / 80 / 70 | 0.4 |

| Level | Left talent | Right talent |
|---|---|---|
| 10 | +0.6s Root Snare root | +20 Attack Speed |
| 15 | +70 Seed Bomb damage | +100 Attack Range |
| 20 | +2 Thorn Barbs thorns | +6 Thorn Barbs damage |
| 25 | +3s Angry Forest time | +30 Angry Forest damage |

**Bots:** they snare when no creep blocks the vine, then seed the rooted target. They use Angry Forest when the fight
is beside trees. When running away they seed the chaser's path (the tree blocks the chaser, not Gancho), snare the
chaser and slip into the trees. Skill order: Thorn Barbs first, then Root Snare and Seed Bomb.

**Looks:** your `gancho.zip` model (bark and vines, its own textures) at 1.95 m. Animations of his own: a calm tai chi
stance, a quick light run, two sidearm thorn throws, a throw for the snare, a lob for the seed, hands forward for the
forest, his own hit and two deaths. Thorns fly as dark wooden spikes with green tips and stick in the target.

---

## Lord Kaileh, the Grand Cavalier

A huge bald knight in plate with a jousting lance. He reaches 200, farther than any sword.
Models from: Mars (250 range spear, pinning) and Spirit Breaker (170 range, charge), with ideas from Hecarim (League:
damage from bonus move speed, ghost riders in his ultimate). Kit code: `src/sim/sim_kits10.gd`.

**Story:** Lord Kaileh lost his horse long ago and never stopped charging. His jousting lance reaches farther than any
sword, and whoever stands in front of it rides it all the way into his army. He plants his house banner where the
fight is, and when he sounds the charge, the ghosts of his old cavalry ride beside him.

| Key | Skill | Kind | What it does | Mana | Cooldown | Cast point |
|---|---|---|---|---|---|---|
| Innate | **Momentum** | passive | Adds 30% of his bonus movement speed to his attack damage (e.g. 100 bonus move speed from boots and haste = +30 damage). Turned off by Break. | none | none | none |
| Q | **Lance Charge** | point, range 700 / 800 / 900 / 1000 | Charges at 1100 a second (140 wide). The first enemy hero he meets is carried on the lance to the end of the charge, takes 75 / 150 / 225 / 300 physical damage and is stunned 1.2 / 1.4 / 1.6 / 1.8 s. Other enemies in his way take the damage and are pushed 180 aside. | 100 | 16 / 14 / 12 / 10 | 0.3 |
| W | **Lance Sweep** | no target | Swings his lance round him (350): 60 / 110 / 160 / 210 physical damage, pushed 150 away, slowed 30% for 2 s. | 70 | 9 | 0.3 |
| E | **War Banner** | point, range 600 | Plants a banner for 12 s. Allies within 600 get +3 / 4 / 5 / 6 armor and +10 / 15 / 20 / 25 attack speed. Enemies within 600 move 10% slower. Four attacks of any kind bring it down (spells do not hurt it); killing it gives 25 gold. | 90 | 24 / 22 / 20 / 18 | 0.2 |
| R | **Cavalry Charge** | point, range 1600 | After a 0.5 s cast he charges at 1400 a second with six ghost riders at his sides, trampling trees in the way. Enemies in the 400-wide path take 200 / 300 / 400 magic damage, are pushed 220 aside and stunned 1 / 1.25 / 1.5 s. Nothing can slow or move him during it. | 150 / 200 / 250 | 100 / 90 / 80 | 0.5 |

| Level | Left talent | Right talent |
|---|---|---|
| 10 | +30 Damage | +250 Health |
| 15 | +0.5s Lance Charge stun | +15% Momentum |
| 20 | -4s Lance Sweep cooldown | +300 Lance Charge range |
| 25 | +0.5s Cavalry Charge stun | +150 Cavalry Charge damage |

**Bots:** they charge a lone enemy hero toward their own team or tower, charge for the kill, or charge to close in.
They sweep when enemies are round him and plant the banner between the teams in fights and pushes. They aim Cavalry
Charge along the line that crosses the most enemy heroes (two or more, or one for a kill). When running they charge
toward safety. Skill order: Lance Charge first, then Lance Sweep and War Banner.

**Looks:** your `lord_kaileh.zip` model at 2.3 m. It had no textures, so I painted it in black steel, leather, a gold
belt and a red loincloth. Lance: "Lance/Joust Weapon" by Rio.Puntar (Sketchfab, CC BY 4.0, needs credit), 2.4 m, held
just behind its hand guard. Animations of his own: a lance-high fighting stance, a heavy weighted run with the lance
held up, three thrusts, a charging run with the lance lowered (played for both charges), a wide sweep, a pointing
"charge!" for the banner, a threatening roar, his own hit and two deaths. The ghost riders are copies of his own body,
see-through and pale blue, charging beside him. A mounted rider would need a horse model, and none was downloaded; I
can add one if you want horses. The banner is a pole with a rippling red cloth with gold trim (violet for Dusk) and a
faint ring on the ground showing its reach.

---

## Dracoxinia, the Blue Wyrm

A royal dragon-woman in pink and shiny gold armour with a big two-handed sword in five colours. She has seven skills:
an innate, three active spells (Q W D), two passives (E F) and a toggle ultimate (R) that changes her sword.
**Changed 2026-10-22 (your call):** her old W (a spinning sweep) and E (Dragon Breath) are gone. In their place are Dragon Leap
(W, movement) and Dragon Hide (E, passive). Both of the old skills dealt area damage (with the push, slows and
sword effects) and neither new one deals any, so she has less burst and wave clear than before: she gets in and out
more and lasts longer, but kills more slowly.
Ideas from: Dragon Knight, Smolder (League: stacks change his spells) and Dota's element wheel. Kit code:
`src/sim/sim_kits11.gd`.

**Story:** Dracoxinia is a dragon princess in pink and gold, and she fights like one. She carries five swords, and each
changes who she is: lightning, light, water, fire or nature, whichever beats the enemy in front of her. She dashes
through her foes, leaps over trees and cliffs, shrugs off blows on her royal scales and throws her enemies into the sky.

### The five swords (Change Sword, R)

Each click of R takes the next sword in this order. The R level sets how many she can use: 3 swords at level 1,
4 at level 2, 5 at level 3. Clicks are 1 s apart and cost no mana. Her attacks take the sword's element. Her next attack after a change is a Dragon Blade strike, at most once every 6 / 5 / 4 s.

| Sword | Element | Dragon Blade strike (F) does |
|---|---|---|
| **Pink Sword** (her own) | Lightning | Lightning jumps to 3 more enemies within 500 for 60% of the strike (magic) |
| **Gold Sword** | Light | An All-damage Barrier as large as the strike for 6 s (stacks up to twice the strike) |
| **Blue Sword** | Water | Roots the target 0.6 s and slows it 40% for 2 s |
| **Red Sword** | Fire | Every enemy within 250 of the target takes the strike too, and all of them burn 30 a second for 3 s |
| **Green Sword** | Nature | She heals 60% of the strike |

Elements matter: a hit of an element that beats the target's deals 25% more, a hit the target's element beats deals
25% less, and the same element deals 25% less. Light and Dark beat each other.
Which element beats which: Water beats Fire, Fire beats Ice, Fire beats Nature, Earth beats Fire, Ice beats Nature,
Ice beats Earth, Water beats Ice, Lightning beats Water, Earth beats Lightning, Nature beats Water, Nature beats Earth.

### Skills

| Key | Skill | Kind | What it does | Mana | Cooldown | Cast point |
|---|---|---|---|---|---|---|
| Innate | **Royal Scales** | passive | 15% less damage from enemies whose element her current sword beats. | none | none | none |
| Q | **Dragon Dash** | point, range 650 | Dashes through enemies (1800 a second, 150 wide): each takes 70 / 130 / 190 / 250 physical damage and is slowed 50% for 0.5 s. Cannot be cast while rooted. | 80 | 13 / 11 / 9 / 7 | 0.15 |
| W | **Dragon Leap** | point, range 500 / 550 / 600 / 650 | Leaps to the point over trees and cliffs, 0.55 s in the air. No damage and no disable: it only moves her. Cannot be cast while rooted (or during her dash). | 70 | 22 / 19 / 16 / 13 | 0.1 |
| E | **Dragon Hide** | passive | +2 / 3 / 4 / 5 armor and +1.5 / 3 / 4.5 / 6 health regeneration. Turned off by Break. | none | none | none |
| D | **Rising Slash** | enemy unit, range 200 | Slashes upward and throws the enemy into the air (stunned) for 0.8 / 1.0 / 1.2 / 1.4 s, with 60 / 100 / 140 / 180 physical damage. Breaks channels. | 90 | 18 / 16 / 14 / 12 | 0.25 |
| F | **Dragon Blade** | passive | Every 4th attack is a heavy strike: +20 / 35 / 50 / 65 damage, then her sword's power (table above). | none | none | none |
| R | **Change Sword** | toggle, ultimate | The next sword (table above). | 0 | 1 | instant |

| Level | Left talent | Right talent |
|---|---|---|
| 10 | +25 Damage | +8 Strength |
| 15 | -4s Dragon Leap cooldown | +0.4s Rising Slash air time |
| 20 | +30 Dragon Blade damage | Dragon Blade every 3rd attack |
| 25 | -2s Change Sword strike wait | +15% Royal Scales |

**Bots:** they pick a sword by the fight: Gold when she is low (barriers), Green to sustain, Red against crowds, Blue to
hold a runner, otherwise the sword whose element beats the target's, and Pink by default. They dash in onto the
target, throw a hero in reach with Rising Slash (to hold it or break a channel), and leap after a runner the dash
cannot reach (never under an enemy tower unless it is a kill). When running they dash, then leap, toward safety.
Skill order: Dragon Blade first, Dragon Dash at 2, one point of Dragon Leap at 4 (her escape), then Rising
Slash and Dragon Hide; the rest of Dragon Leap last.

**Looks:** your `dracoxinia.zip` model at 2.0 m. It had no textures, so I painted it pink with shiny gold trim and
white horns. Swords: your "UTTVM Sword Color Pack" by EvesStudio2008 (Sketchfab, CC BY 4.0, needs credit): one sword
in pink, gold, blue, red and green, 1.6 m, with a glowing blade. The sword in her hand changes when she changes swords,
and her swing trail takes its colour. Animations of her own: admiring her sword (idle), a feminine run with the sword
held, three wide two-handed arcs, a slide-attack dash (played while she dashes), a jumping cut for Dragon Leap (its
time in the air fitted to the flight, then her landing), an upward cut, a sword flourish for Change Sword, a strike
for Dragon Blade, her own hit and two deaths. The leap leaves a trail in her sword's colour and a ring where she lands.

---

## Names to veto

Skills and passives: Tree Walk, Root Snare, Seed Bomb, Thorn Barbs, Angry Forest, Momentum, Lance Charge, Lance
Sweep, War Banner, Cavalry Charge, Royal Scales, Dragon Dash, Dragon Leap, Dragon Hide, Rising Slash, Dragon Blade,
Change Sword, Pink Sword, Gold Sword, Blue Sword, Red Sword, Green Sword. Unit: War Banner. Riders: "ghost riders"
(not a unit name).

## Where to change things

* Numbers, mana, cooldowns, ranges, talents, base stats: `src/sim/sim_data.gd` from `_add_heroes_22`. Change a value
  list such as `"damage": [80, 140, 200, 260]`; the tooltips are the `"desc"` strings next to them, so update those
  too (or tell me and I will).
* How a skill works: Gancho and Kaileh `src/sim/sim_kits10.gd`, Dracoxinia `src/sim/sim_kits11.gd`.
* Bots: `src/sim/sim_bot22.gd`, skill order and builds in `src/sim/sim_bot_kits.gd`.
* Animations per hero: `work/lemondev/2026-10-21b-three-heroes/anim/hero_clips.py` (the Mixamo clip behind each
  move) and `ModelCatalog.MOCAP` in `src/game/model_catalog.gd` (which move plays for which skill).
* Effects: `src/game/hero22_fx.gd`.
