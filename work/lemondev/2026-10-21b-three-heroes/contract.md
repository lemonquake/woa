# Run 2026-10-21 b: three new heroes and own animations for every hero (contract)

## The owner's request (verbatim points)
* Research Dota 2 and League of Legends; make three heroes: **Gancho, the Nature Whisperer** (ranged agility), **Lord
  Kaileh, the Grand Cavalier** (melee, 200 attack range), **Dracoxinia, the Blue Wyrm**. Download third-party models and
  effects for them (Sketchfab is signed in in the app's browser).
* Mid-run: models are provided in `work/downloads/sf_heroes/` (`gancho.zip`, `lord_kaileh.zip`, `dracoxinia.zip`).
* Mid-run: **Dracoxinia** has a **pink and really shiny gold** theme, she is **royalty**, a **dragonoid warrior** with a
  **big two-handed weapon**: `dracoxinia_swords_collection.zip` (one sword in many colours). She has **at least 7 skills:
  1 innate, 4 active skills, 1 passive, and an ultimate that is a toggle**: every click changes her sword, **up to 5
  kinds of swords**, each with its own modifier to her passive; the ultimate gives her versatility in every situation.
* **Overhaul the heroes so they do not use identical animations** (Ezee, Araki and the other melee heroes share one set):
  "Melee heroes with swords should not have identical animations". Each hero has some of its own animations and
  rigging; follow the strict animation rules (every limb collides, nothing clips; joins).
* Research deeply first; come back with something extraordinary.

## Research (work/lemondev/2026-10-21b-three-heroes/research/)
Dota 2 (Liquipedia, 7.41f): Hoodwink (agi ranged 575, tree evasion, net to trees), Windranger, Nature's Prophet
(Sprout trees), Treant Protector, Chaos Knight, Spirit Breaker (170 range, charge), Mars (250 range spear, pin),
Dragon Knight (dragon form), Jakiro, Winter Wyvern (flying). League (wiki): Hecarim (Warpath: damage from bonus move
speed, charge knockback, ghost riders in the ultimate), Kled / Rell (mounted), Ivern (root vine, brush), Zyra (seeds that
grow plants), Aurelion Sol (steerable breath), Smolder (stacks change his spells). Taken: tree play from Hoodwink and
Zyra, ghost riders and move-speed damage from Hecarim, a pin-carry from Mars, a form-switching weapon from Smolder's
stack tiers and Dota's element wheel. Every name is our own.

## Hero designs (numbers follow Dota templates; chosen, listed for the owner's veto)

### Gancho, the Nature Whisperer (ranged agility, Nature)
Model: bark-and-vine tree man (owner's `gancho.zip`, textured, Mixamo rig). Attack: hurls a thorn (no weapon), 600
range, projectile 1250. Str 18 +2.0, Agi 22 +3.2, Int 17 +1.9; damage 23-30; armor 1; 300 speed; BAT 1.7; point 0.4.
* Innate **Tree Walk**: walks through trees; 20% evasion while within 250 of a tree.
* Q **Root Snare** (line 1100, width 90, speed 1500): the first enemy hit takes 80/140/200/260 magic and is rooted
  1.2/1.4/1.6/1.8 s. 90/100/110/120 mana, 14/12/10/8 s.
* W **Seed Bomb** (point 900, radius 250): lands after 0.6 s: 60/100/140/180 magic, 30% slow 2 s, and a young tree
  grows there for 15 s. 80 mana, 13/12/11/10 s.
* E **Thorn Barbs** (passive): each attack adds a thorn (up to 5, 5 s): 4/6/8/10 magic a second and 4% slow per thorn.
* R **Angry Forest** (no target, 7 s): every second each tree within 1000 lashes the nearest enemy within 350 of it:
  35/50/65 magic and a 0.4 s root (a unit is rooted at most once per 1.5 s); Gancho gains +30/45/60 attack speed.
  150/200/250 mana, 90/80/70 s.

### Lord Kaileh, the Grand Cavalier (melee 200, strength, Earth)
Model: huge bald brute in plate (owner's `lord_kaileh.zip`, no textures: painted by us, steel and leather). Weapon:
jousting lance "Lance/Joust Weapon" by Rio.Puntar (CC BY 4.0, downloaded). Str 24 +3.4, Agi 15 +1.6, Int 17 +1.8;
damage 31-39; armor 3; 300 speed; BAT 1.8; point 0.45; range 200.
* Innate **Momentum**: +30% of his bonus move speed as attack damage.
* Q **Lance Charge** (point 700/800/900/1000, speed 1100): the first enemy hero met is carried on the lance to the
  end and stunned 1.2/1.4/1.6/1.8 s; other enemies in the path take the damage and are pushed aside. 75/150/225/300
  physical. 100 mana, 16/14/12/10 s.
* W **Lance Sweep** (no target, radius 350): 60/110/160/210 physical, pushed 150 away, 30% slow 2 s. 70 mana, 9 s.
* E **War Banner** (point 600, 12 s, 4 hits to kill): allies within 600 gain +3/4/5/6 armor and +10/15/20/25 attack
  speed; enemies within 600 move 10% slower. 90 mana, 24/22/20/18 s.
* R **Cavalry Charge** (point 1600, speed 1400, width 400): after 0.5 s Kaileh charges with six ghost riders at his
  sides; enemies in the path take 200/300/400 magic, are pushed aside and stunned 1.0/1.25/1.5 s; he cannot be slowed
  or moved during it. 150/200/250 mana, 100/90/80 s.

### Dracoxinia, the Blue Wyrm (melee, strength, Lightning)
Model: horned dragon-woman in armour, no tail (owner, 2026-10-22: "she should not have any tail at all") (owner's `dracoxinia.zip`, no textures: painted pink and shiny gold,
royal). Weapon: the owner's sword collection ("UTTVM Sword Color Pack" by EvesStudio2008, CC BY 4.0): five colours.
Str 23 +3.3, Agi 19 +2.2, Int 17 +1.7; damage 30-36; armor 2; 305 speed; BAT 1.7; point 0.45.
* Innate **Royal Scales**: 15% less damage from enemies whose element her sword beats.
* Q **Dragon Dash** (point 650): dashes through enemies: 70/130/190/250 physical and 0.5 s slow 50%. 80 mana, 13/11/9/7 s.
* W (replaced 2026-10-22 by Dragon Leap; E Dragon Breath by Dragon Hide: see docs/NEW_HEROES_22.md).
* E **Dragon Breath** (cone 650): 90/150/210/270 magic of her sword's element, with her sword's effect. 110 mana, 14 s.
* D **Rising Slash** (unit 200): throws the target into the air for 0.8/1.0/1.2/1.4 s (stunned), 60/100/140/180
  physical. 90 mana, 18/16/14/12 s.
* F **Dragon Blade** (passive): every 4th attack is a heavy strike: +20/35/50/65 damage, then the sword's modifier.
* R **Change Sword** (toggle, ultimate; levels 1/2/3: 3/4/5 swords; 1 s between clicks, no mana): each click takes the
  next sword; her attacks and Dragon Breath take its element; the next attack after a change is a Dragon Blade strike
  (once every 6/5/4 s). Swords and their Dragon Blade modifiers:
  * **Pink Sword** (Lightning, her own): the strike chains to 3 more enemies within 500 for 60% of it.
  * **Gold Sword** (Light): the strike gives her an All-damage Barrier of 100% of it for 6 s.
  * **Blue Sword** (Water): the strike roots for 0.6 s and slows 40% for 2 s.
  * **Red Sword** (Fire): the strike hits every enemy within 250 around the target and burns 30 a second for 3 s.
  * **Green Sword** (Nature): the strike heals her 60% of it.

## Animation overhaul (the owner's main point)
Sources: the Mixamo clips already downloaded (`work/downloads/mixamo/raw`, 181), new Mixamo downloads (needs the owner's
Mixamo sign-in), Quaternius Universal Animation Library 1 and 2 (CC0, downloaded), and our own edits:
`tools/blender/mocap_retarget.py` gains per-clip `speed`, `pose` (bone offsets in degrees), `upper` (upper body from
another clip over these legs) and `amp` (how strong the motion is), so a hero's stance and weight are its own.
Rule: no two sword or axe heroes share an idle, a run, or any attack clip; casts, hits and deaths vary where clips
allow. Per-hero rigging: Thyrandael's wings and Gancho's branches sway with spring bones
(Godot SpringBoneSimulator3D) where the collision gate allows.
Gates: `body_collide.gd --fix` then `--applied` (every limb and held weapon), `anim_joins.gd` (limit as before),
`anim_audit.gd`, close-up sheets by eye, and a table of who plays what with zero shared sword clips.

## Components, owners, gates
| Id | Component | Owner (files) | Gate |
|---|---|---|---|
| B1 | Bodies and weapons | `assets/characters/heroes17/{gancho,kaileh,dracoxinia}*`, `assets/weapons/{kaileh_lance,dracoxinia_sword_*}*`, `tools/blender/joints/*`, `bodies/` | collision, joins, close-up renders |
| K1 | Three kits | `src/sim/sim_kits10.gd` (new), data in `sim_data.gd`, hooks | tests per hero |
| A1 | Animation library | `tools/blender/mocap_retarget.py`, `mocap_clips.json`, `ModelCatalog.MOCAP` | no shared sword clips; collision; joins |
| V1 | Effects, UI, bots, chat | game FX, icons, bot brains | captures, bot games |
| I | Integration | all | full suite, check.sh, export, cold start |

Benchmark: no Dota 2 client on this machine (gate UNVERIFIED, as in earlier runs). Pass budget: 8 per component.
