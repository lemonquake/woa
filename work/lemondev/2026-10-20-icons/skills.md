# Skill icon inventory

2026-10-20. Audit of the live data and simulation. No gameplay or interface changes. Existing names preserved; no new player-visible names.

## Coverage

- 17 playable heroes: 68 four-core icons, 4 innate icons and 4 extra icons = 76 hero icons.
- Extras: Tock has Slow Field (D) and Quick Hands (F); Blau gains Pilot Turret (D) with Upgrade Staff; Ghorman has Blessing of the Beast King (D) as an ordinary fifth learned ability.
- Innates: Sludge Growing Gut, Kragg Magnetize, Burak Rage, Araki Senryukai.
- 3 neutral spells, 4 neutral auras, 4 neutral attack passives and 1 Ancient classification icon = 12 neutral entries.
- Total: 88 distinct image keys. All 79 SimData ability definitions are covered exactly once. All existing baseline icon paths exist.

`skills.json` is a flat array for generation. Its `id` is the output image key. `ability_id` is the exact SimData ability ID where one exists; neutral passives use their existing modifier ID or an explicitly marked image-only key. Crit/Splash use `neutral_crit` / `neutral_splash`, while `data_key` records the exact unit-definition member. `current_icon` records the baseline path before concurrent replacement work. Core order is Q/W/E/R; Tock D/F and Ghorman D are extras. This is image-sheet grouping, not a change to runtime slot order.

## Evidence and cautions

Inputs read: AGENTS.md; lemondev/SKILL.md and its naming, roles-and-review, visuals-and-ui references; docs/HANDOFF.md; docs/MECHANICS.md; src/sim/sim_data.gd; the relevant effect, combat, aura and attack helpers in sim_abilities.gd, sim_kits2.gd through sim_kits7.gd, sim_ai.gd and sim_combat.gd; baseline UiKit ability tables, HUD unit_skills and BuffBar routing. Mechanics prose was compared with implementation where presentation could imply the wrong behavior. This is a data audit, not a runtime mechanics test or rendered-art quality acceptance.

Important distinctions: Master of Shadows hides only the minimap marker; Void Rush does not move Roydo; Djin Bomb deals no direct damage; Soul Tap scans units to charge a future attack rather than directly draining them; Death Order changes attack damage type rather than guaranteeing execution; Time Bolt slows cooldowns rather than movement; Lava Golem Splash is circular magical damage rather than a melee cleave cone. Sweet Poison description mentions a second blow, but implementation applies only a renewing poison effect. Rewind only restores health/mana upward. Bounce Shot gains distance per bounce; the older fixed-total-path mechanics paragraph is stale.

Baseline semantic warnings below describe risks from reused icon routing and source geometry. They do not claim a blind visual review. Fiery Javelin is a concrete mismatch: its legacy storm_javelin SVG contains purple glow and yellow lightning geometry despite the skill using Fire. Neutral aura artwork is shared among four mechanically distinct bonuses.

## Secondary casts sharing an existing icon

| Exact ability ID | Secondary behavior | Source |
|---|---|---|
| `pilot_turret` | Same button becomes Leave Turret while piloting; free exit, or exit on movement. | sim_abilities.gd execute; sim_kits3.gd leave_turret; hud.gd _ability_tip |
| `door_of_the_end` | Second cast places the exit, free, up to exit range from the door; early unit movement exits without explosion. | sim_kits4.gd try_exit_cast, _set_exit, leave_door |
| `axe_throw` | Free recast leaps to a planted axe while its window is open. Staff permits two axes but creates no separate spell ID. | sim_kits5.gd try_axe_recast, leap_axe |
| `blur_strike` | A successful hit refreshes a second dash in the six-second window; talent permits another refresh. | sim_kits7.gd _blur_strike, _lapse |
| `swap` | With Staff, first mark an allied hero, then swap it with an enemy; Feran stays put. Same ID. | sim_kits6.gd try_swap_mark, _swap |

No separate recast icon is currently selected by these UI paths, so the inventory preserves one image per ability ID. Toggle on/off and charged states likewise share their base art. Teleport (`tp`), map-site channels (`site_gate`, `site_lamp`), team Fortify, courier commands and generic building/ward traits are shared actions outside this hero/neutral skill inventory. Item actives belong to the item audit.

## Hero and neutral entries

### Jayla

**burst_shot — Burst Shot** (core; point).

Mechanic: Jayla plants her feet and looses 30 arrows over five waves of four to seven into the target area. Each arrow strikes a random enemy there for a share of her attack damage. Channelled: moving, attacking, stopping, a stun, silence or a push ends it.

Visual brief: Longbow firing a dense fan of many red-fletched arrows in repeated curved volleys toward several enemies; repeated arrows dominate.

Baseline icon: `assets/ui/skills/multishot.svg`. Data: `src/sim/sim_data.gd:483`. Implementation: `src/sim/sim_abilities.gd:1049 (_start_burst)`.

**gale_impact — Gale Impact** (core; point).

Mechanic: Looses a great arrow toward the target point; it always flies its full 2000 range. Every enemy it passes is struck for magic damage and hurled aside; an enemy that crashes into a wall, unit, building or tree takes another 20% of that damage. The arrow fells every tree in its path, and so do the units it throws.

Visual brief: One huge glowing green arrow flying through targets, hurling a struck figure sideways into a tree; straight flight and side impact.

Baseline icon: `assets/ui/skills/power_shot.svg`. Data: `src/sim/sim_data.gd:490`. Implementation: `src/sim/sim_abilities.gd:689 (_update_line)`.

Caution: Show piercing arrow plus sideways pushes and crashes; it is not merely one high-damage arrow.

**masterful_archery — Masterful Archery** (core; passive).

Mechanic: Her attacks have a chance to burst for bonus physical damage based on her agility. Cooldown after each burst.

Visual brief: Bow and arrowhead hitting one precise bright weak point with a sharp physical impact burst; empowered single arrow.

Baseline icon: `assets/ui/skills/deadeye.svg`. Data: `src/sim/sim_data.gd:496`. Implementation: `src/sim/sim_abilities.gd:1111 (masterful_bonus)`.

**blood_ranger_ult — Blood Ranger** (core; no_target).

Mechanic: Jayla gives in to the hunt: for 15 seconds her attacks steal life and reach much further. When an attack hits her she may leap back out of reach.

Visual brief: Red longbow draining blood-red energy back from a distant target to the archer; subtle backward retreat silhouette, long reach.

Baseline icon: `assets/ui/skills/bs_blood_eclipse.svg`. Data: `src/sim/sim_data.gd:501`. Implementation: `src/sim/sim_abilities.gd:1125 (on_attacked)`.

Caution: Legacy art bs_blood_eclipse cannot explain lifesteal, range and reactive retreat; no eclipse mechanic exists.

### Ezee

**dark_stomp — Dark Stomp** (core; no_target).

Mechanic: Ezee slams the ground with unholy force, damaging nearby enemies and hurling them away. Enemies that crash into a unit, tree, cliff or wall take impact damage and are stunned.

Visual brief: Black armored boot slamming cracked ground; purple circular shockwave throws nearby enemies outward toward rocks.

Baseline icon: `assets/ui/skills/tempo_wd_quake.svg`. Data: `src/sim/sim_data.gd:509`. Implementation: `src/sim/sim_abilities.gd:741 (_dark_stomp)`.

**leap_strike — Leap Strike** (core; no_target).

Mechanic: Ezee picks the visible enemy in range with the lowest health (the nearest one if none is hurt), leaps onto it and strikes for pure damage plus 60% of his strength, slowing it. Does nothing if no enemy is in sight.

Visual brief: Dark armored swordsman leaping downward onto one weakened enemy, raised blade and curved jump trail; single landing target.

Baseline icon: `assets/ui/skills/leap_slam.svg`. Data: `src/sim/sim_data.gd:515`. Implementation: `src/sim/sim_abilities.gd:965 (leap_target)`.

Caution: No user-selected target: automatically chooses the weakest visible enemy, then nearest when all are healthy.

**tainted_touch — Tainted Touch** (core; no_target).

Mechanic: Purple lightning from the sky enchants Ezee's sword. His attacks deal bonus magic damage and curse the target, revealing it and granting sight around it, even through invisibility.

Visual brief: Black sword held upright receiving purple lightning from the sky; eye-shaped glow around a struck target suggests revealed sight.

Baseline icon: `assets/ui/skills/shadow_curse.svg`. Data: `src/sim/sim_data.gd:521`. Implementation: `src/sim/sim_abilities.gd:1026 (tainted_hit)`.

Caution: Purple Lightning sword enchantment and revealed vision matter; a generic shadow curse misses the weapon and element.

**unholy_might — Unholy Might** (core; no_target).

Mechanic: Ezee roars and is wrapped in a dark aura. Each instance of damage he takes has a chance to be halved, the other half striking a random nearby enemy as pure damage. When the aura fades he is slowed for 2 seconds.

Visual brief: Dark armored torso absorbs an incoming blow, half its energy branching back toward a nearby enemy; protective purple aura.

Baseline icon: `assets/ui/skills/dg_black_dominion.svg`. Data: `src/sim/sim_data.gd:527`. Implementation: `src/sim/sim_abilities.gd:340 (execute)`.

Caution: A chance to halve damage and redirect the remainder to a random nearby enemy; not a universal immunity shield.

### Sludge

**shuriken_hook — Shuriken Hook** (core; point).

Mechanic: Sludge hurls a chain tipped with a spinning shuriken. It always flies its full 1300 range and catches the first unit it touches, dragging it back to where he threw it. Enemies take pure damage and are stunned while dragged; enemy creeps die at once; allies are pulled to safety unharmed. The chain flies over cliffs and trees.

Visual brief: Spinning four-point steel shuriken on a heavy chain, catching a distant enemy and pulling inward; chain prominent.

Baseline icon: `assets/ui/skills/crippling_star.svg`. Data: `src/sim/sim_data.gd:538`. Implementation: `src/sim/sim_abilities.gd:1408 (_start_hook)`.

Caution: Legacy crippling_star must show attached chain and pulling; a lone throwing star omits its defining mechanic.

**stench — Stench** (core; toggle).

Mechanic: A toxic cloud pours off Sludge, damaging and slowing nearby enemies, and hurting Sludge himself (it can never kill him). Toggle it on and off. Keeps working while he is stunned.

Visual brief: Thick sickly green toxic cloud pouring from a heavy butcher and enveloping foes; choking fumes, no projectile.

Baseline icon: `assets/ui/skills/venomcraft.svg`. Data: `src/sim/sim_data.gd:546`. Implementation: `src/sim/sim_abilities.gd:1548 (_update_pulse)`.

**blubber — Blubber** (core; no_target).

Mechanic: Sludge's fat thickens: every instance of damage he takes, from any source, is reduced by a flat amount for a few seconds. Does not interrupt Chomp.

Visual brief: Thick folded flesh absorbing and flattening an incoming sharp impact; fleshy cushioning, no metal shield.

Baseline icon: `assets/ui/skills/iron_skin.svg`. Data: `src/sim/sim_data.gd:553`. Implementation: `src/sim/sim_abilities.gd:340 (execute)`.

Caution: Organic flat damage block per damage instance; legacy iron_skin suggests metallic armor rather than cushioning flesh.

**chomp — Chomp** (core; unit).

Mechanic: Sludge grabs an enemy and eats it alive. Channelled for 2.75 seconds: the victim is stunned and pulled in, taking magic damage that grows with his strength, and Sludge heals for all of it.

Visual brief: Huge butcher mouth biting and holding an enemy silhouette, warm healing energy returning to the butcher; teeth and sustained grasp.

Baseline icon: `assets/ui/skills/eviscerate.svg`. Data: `src/sim/sim_data.gd:557`. Implementation: `src/sim/sim_abilities.gd:1589 (_update_chomp)`.

**growing_gut — Growing Gut** (innate; innate).

Mechanic: Sludge gains 2 strength for good whenever an enemy hero dies within 450 of him, or anywhere if he gets the kill.

Visual brief: Broad fleshy belly growing beneath a butcher belt as a departing enemy soul becomes warm strength energy; organic fat.

Baseline icon: `assets/ui/skills/toughness.svg`. Data: `src/sim/sim_data.gd:534`. Implementation: `src/sim/sim_abilities.gd:1393 (on_hero_death)`.

### Azrin

**fiery_javelin — Fiery Javelin** (core; point).

Mechanic: Azrin hurls a great flaming javelin up to 1000 range. Every enemy near its path is caught and dragged along to where it lands, and burns for magic damage every second for 5 seconds. Trees in its path are knocked down.

Visual brief: Long burning javelin flying diagonally and carrying an enemy toward its landing point; orange fire and dragged silhouette.

Baseline icon: `assets/ui/skills/storm_javelin.svg`. Data: `src/sim/sim_data.gd:570`. Implementation: `src/sim/sim_abilities.gd:1243 (_update_javelin)`.

Caution: Legacy storm_javelin has purple shaft glow and yellow lightning shapes in SVG; this ability burns with Fire and drags units.

**touch_of_ember — Touch of Ember** (core; point).

Mechanic: Spirit flames burst over a 300 area: enemies take 100 magic damage and carry the flames. When one of them casts a spell, or after 4 seconds, the flames explode for more magic damage and stun it.

Visual brief: Enemy carrying orange spirit flames that burst into a delayed fire explosion; hovering flames then detonation, no melee hand strike.

Baseline icon: `assets/ui/skills/inner_fire.svg`. Data: `src/sim/sim_data.gd:576`. Implementation: `src/sim/sim_abilities.gd:1288 (_touch_of_ember)`.

**spirit_of_fire — Spirit of Fire** (core; point).

Mechanic: Each other spell Azrin casts stores a circling fire spirit, up to five. Cast to launch all stored spirits at one area, each applying a five-second burn and slow.

Visual brief: Five distinct small fire spirits circling a caster and streaming together toward a ground target; bright purposeful flight arcs.

Baseline icon: `assets/ui/skills/flame_sentinel.svg`. Data: `src/sim/sim_data.gd:582`. Implementation: `src/sim/sim_abilities.gd:1338 (_shoot_spirits)`.

**divine_smite — Divine Smite** (core; unit).

Mechanic: Azrin hurls a burning hammer at an enemy. It strikes for 250 plus twice her intelligence as magic damage and sets the ground around it alight: every Fire burn on enemies there lasts longer.

Visual brief: Large burning hammer flying onto an enemy surrounded by persistent orange ground flames; hammer silhouette dominant.

Baseline icon: `assets/ui/skills/blessed_hammer.svg`. Data: `src/sim/sim_data.gd:588`. Implementation: `src/sim/sim_abilities.gd:1369 (_update_hammer)`.

### Froster

**breath_of_cold — Breath of Cold** (core; point).

Mechanic: Froster breathes a cone of bitter cold up to 800 ahead. Every enemy in it takes magic damage and is slowed for 3 seconds.

Visual brief: Broad icy breath cone spreading from a caster toward foes; blue frost mist widens forward, no circular explosion.

Baseline icon: `assets/ui/skills/frost_nova.svg`. Data: `src/sim/sim_data.gd:601`. Implementation: `src/sim/sim_abilities.gd:1621 (_breath)`.

Caution: Cone of moving breath; legacy frost_nova suggests a circular burst.

**ice_pulse — Ice Pulse** (core; unit).

Mechanic: Curses an enemy: its defense drops (armor and every resistance count less, so it takes more physical and magic damage) for 3.5 seconds. Then the curse bursts in an ice blast that deals 100 magic damage to it and every enemy within 300.

Visual brief: Enemy enclosed in a cracked blue ice curse, armor splitting before a circular outward ice blast; marked target and bursting ring.

Baseline icon: `assets/ui/skills/frost_orb.svg`. Data: `src/sim/sim_data.gd:608`. Implementation: `src/sim/sim_abilities.gd:1677 (_update_ice_pulse)`.

Caution: Target curse and delayed blast; not a flying ice orb.

**frost_heart — Frost Heart** (core; passive).

Mechanic: Damage Froster deals to enemies builds a Frost Heart (one per 500 / 450 / 400 / 350 damage, up to 3). His next attack spends one: 200 extra magic damage and a 40% slow for 1.5 seconds.

Visual brief: Three crystalline ice hearts gathering around an empowered arrow, one breaking into its frosty strike; heart silhouette clear.

Baseline icon: `assets/ui/skills/frost_mastery.svg`. Data: `src/sim/sim_data.gd:614`. Implementation: `src/sim/sim_abilities.gd:1698 (frost_heart_charge)`.

**endless_winter — Endless Winter** (core; no_target).

Mechanic: Froster stands still and calls a blizzard for up to 7 seconds. Enemies within 600 take magic damage every second; one that stays inside for 2 seconds is Frosted, frozen solid for 2 seconds (once every 1.5 seconds after that). Channelled.

Visual brief: Stationary ice caster inside a broad sustained blizzard; surrounding foes freezing solid in falling ice.

Baseline icon: `assets/ui/skills/blizzard.svg`. Data: `src/sim/sim_data.gd:620`. Implementation: `src/sim/sim_abilities.gd:1748 (_update_winter)`.

### Caziel

**swift_dagger — Swift Dagger** (core; unit).

Mechanic: Caziel flashes to an enemy in a trail of shadows and stabs it at once with his attack plus bonus physical damage, cutting its armor for 3 seconds.

Visual brief: Dark assassin flashing directly into a dagger stab along a purple trail; cracked armor at one impact point.

Baseline icon: `assets/ui/skills/ns_umbral_lunge.svg`. Data: `src/sim/sim_data.gd:632`. Implementation: `src/sim/sim_abilities.gd:1787 (_swift_dagger)`.

**sweet_poison — Sweet Poison** (core; passive).

Mechanic: Attacks can apply a renewing Nature poison damage-over-time effect for 2 seconds. A new proc renews, never stacks; the implementation does not make a second physical attack.

Visual brief: Dagger making a second green poisoned cut; droplets spreading along a lingering poison trail on one target.

Baseline icon: `assets/ui/skills/venom_strike.svg`. Data: `src/sim/sim_data.gd:637`. Implementation: `src/sim/sim_abilities.gd:1815 (sweet_poison_hit)`.

Caution: Description says a second poisoned blow, but sweet_poison_hit applies a renewing Nature damage-over-time effect only; do not imply a second physical hit.

**master_of_shadows — Master of Shadows** (core; no_target).

Mechanic: Caziel wraps himself in shadows for 12 seconds: he vanishes from the enemy minimap, evades attacks more often and moves faster.

Visual brief: Dark assassin stepping through smoky afterimages while arrows miss; speed and evasion, no empty invisible silhouette.

Baseline icon: `assets/ui/skills/ns_gloom_veil.svg`. Data: `src/sim/sim_data.gd:642`. Implementation: `src/sim/sim_abilities.gd:340 (execute)`.

Caution: Only hidden on the enemy minimap, with evasion and speed; it does not grant invisibility.

**death_order — Death Order** (core; passive).

Mechanic: Caziel strikes hardest when an enemy is about to die: his attacks deal pure damage to enemies below 10 / 12 / 14% health.

Visual brief: Dagger delivering a clean finishing strike to a weakened enemy with a near-empty red life shape; no summoned reaper.

Baseline icon: `assets/ui/skills/ns_marked_execution.svg`. Data: `src/sim/sim_data.gd:647`. Implementation: `src/sim/sim_abilities.gd:1828 (death_order)`.

Caution: Converts low-health attacks to pure damage; no instant kill or execution threshold guarantee.

### Tock

**time_bolt — Time Bolt** (core; point).

Mechanic: Tock fires a bolt of slowed time up to 1000 ahead. Every enemy it passes takes magic damage, and for 4 seconds its spell and item cooldowns run 30 / 40 / 50 / 60% slower.

Visual brief: Gold clock-faced bolt streaking through enemy silhouettes, leaving slowed clock hands on its trail.

Baseline icon: `assets/ui/skills/gen/time_bolt.svg`. Data: `src/sim/sim_data.gd:657`. Implementation: `src/sim/sim_kits2.gd:104 (_update_bolt)`.

Caution: Slows cooldown progression, not enemy movement; keep distinct from Slow Field.

**fast_forward — Fast Forward** (core; unit).

Mechanic: Winds an ally (or Tock) forward: 2 / 3.5 / 5 / 6.5 seconds come off the cooldowns of its basic spells (not its ultimate, not items), and it moves 10 / 14 / 18 / 22% faster for 5 seconds.

Visual brief: Friendly figure in warm gold, two forward time arrows and a rapidly turning clock; movement flowing forward.

Baseline icon: `assets/ui/skills/gen/fast_forward.svg`. Data: `src/sim/sim_data.gd:663`. Implementation: `src/sim/sim_kits2.gd:36 (cast)`.

Caution: Cuts basic spell cooldowns, excludes ultimate and items; icon should not promise full refresh.

**rewind — Rewind** (core; no_target).

Mechanic: Returns to a position sampled three seconds earlier, restores past health and mana only if higher (mana less cast cost), basic-dispels and dodges projectiles.

Visual brief: Clock hand curving backward toward a translucent previous position of a tinkerer; green and blue restored energy returning.

Baseline icon: `assets/ui/skills/gen/rewind.svg`. Data: `src/sim/sim_data.gd:668`. Implementation: `src/sim/sim_kits2.gd:131 (_rewind)`.

Caution: Current implementation only restores health/mana when past values are higher; do not depict self-damage from reverting.

**stop_time — Stop Time** (core; point).

Mechanic: Time stops in a 400 area: every enemy there is frozen (stunned) and its cooldowns stand still for 2.5 / 3 / 3.5 seconds. Tock's allies keep moving.

Visual brief: Large stopped clock above enemies frozen mid-swing inside a gold circle; friendly figure still moving outside.

Baseline icon: `assets/ui/skills/gen/stop_time.svg`. Data: `src/sim/sim_data.gd:682`. Implementation: `src/sim/sim_kits2.gd:175 (_stop_time)`.

Caution: Freezes enemies and cooldowns while allies act; time theme, not Ice-element freeze.

**slow_field — Slow Field** (extra; point).

Mechanic: A field of slowed time for 5 seconds: enemies inside move 30 / 35 / 40 / 45% slower and attack slower.

Visual brief: Circular gold ground field holding slowed enemy silhouettes under drooping clock hands; stationary area, no ice.

Baseline icon: `assets/ui/skills/gen/slow_field.svg`. Data: `src/sim/sim_data.gd:672`. Implementation: `src/sim/sim_kits2.gd:159 (_update_field)`.

**quick_hands — Quick Hands** (extra; passive).

Mechanic: Every spell Tock casts takes 1 / 1.5 / 2 / 2.5 seconds off the cooldowns of his other spells.

Visual brief: Tinkerer hands rapidly turning clock gears while several small cooldown dials advance; hand and gear motion.

Baseline icon: `assets/ui/skills/gen/quick_hands.svg`. Data: `src/sim/sim_data.gd:678`. Implementation: `src/sim/sim_kits2.gd:195 (on_cast)`.

### Kragg

**iron_grip — Iron Grip** (core; unit).

Mechanic: Kragg magnetizes an enemy: the two snap together and meet halfway. The enemy takes magic damage, is stunned and gets 2 Charges.

Visual brief: Iron gauntlet and enemy pulled toward a bright magnetic meeting point; opposing inward arcs show both moving.

Baseline icon: `assets/ui/skills/gen/iron_grip.svg`. Data: `src/sim/sim_data.gd:688`. Implementation: `src/sim/sim_kits2.gd:281 (_iron_grip)`.

**repel — Repel** (core; no_target).

Mechanic: A magnetic blast throws enemies near Kragg away, 25% further for each Charge they carry, and slows them. One that crashes into a tree, wall or unit takes more damage and is stunned. Adds a Charge.

Visual brief: Iron gauntlet releasing blue magnetic force outward, shoving nearby enemies away and one against a rock.

Baseline icon: `assets/ui/skills/gen/repel.svg`. Data: `src/sim/sim_data.gd:694`. Implementation: `src/sim/sim_kits2.gd:309 (_repel)`.

**overload — Overload** (core; passive).

Mechanic: Every 6th / 5th / 4th / 3rd attack, Kragg overloads and bursts electric charge around him: enemies within 200 are slowed by 80% for 0.8 seconds and take 60 / 75 / 90 / 105 electric magic damage (Lightning element).

Visual brief: Armored fist releasing a short-range blue electric circular burst; small charge beads feed a sudden discharge around the knight.

Baseline icon: `assets/ui/skills/gen/overload.svg`. Data: `src/sim/sim_data.gd:707`. Implementation: `src/sim/sim_kits2.gd:335 (_overload)`.

**magnet_field — Magnet Field** (core; no_target).

Mechanic: For 6 seconds Kragg is a giant magnet: enemies within 700 are dragged toward him (harder with each Charge) and gain a Charge every second. When it ends, enemies within 300 take magic damage and are stunned.

Visual brief: Magnetic armored knight at center of broad blue field lines drawing enemies inward; compact final blast at his feet.

Baseline icon: `assets/ui/skills/gen/magnet_field.svg`. Data: `src/sim/sim_data.gd:713`. Implementation: `src/sim/sim_kits2.gd:353 (_update_magnet)`.

**magnetize — Magnetize** (innate; innate).

Mechanic: Kragg's attacks give enemies a Charge (up to 4, for 8 seconds). Each Charge makes the enemy take 0.10% more damage from his spells, +0.05% per hero level.

Visual brief: Iron weapon touching an enemy and leaving several bright electric charge beads on its body; applied charges, no burst.

Baseline icon: `assets/ui/skills/gen/magnetize.svg`. Data: `src/sim/sim_data.gd:703`. Implementation: `src/sim/sim_kits2.gd:254 (on_attack_landed)`.

### Roydo

**grip_of_the_ruler — Grip of the Ruler** (core; point).

Mechanic: Roydo's gravity seizes one unit in a 400 area, enemy heroes first, and throws it to the middle over 0.8 seconds. Then every enemy there takes magic damage and is stunned for 1 second. With no enemy in the area, an ally is thrown instead and comes to no harm.

Visual brief: Gravity hand lifting one enemy and throwing it in an arc to a central ground impact circle.

Baseline icon: `assets/ui/skills/gen/grip_of_the_ruler.svg`. Data: `src/sim/sim_data.gd:724`. Implementation: `src/sim/sim_kits3.gd:125 (_grip)`.

**void_rush — Void Rush** (core; no_target).

Mechanic: A wave of gravity rolls out 650 around Roydo for 7 seconds. Enemies lose 20 / 30 / 40 / 50% status resistance and deal 10 / 15 / 20 / 25% less damage. Allies gain 7 / 9 / 11 / 13 armor and move 7 / 9 / 11 / 13% faster.

Visual brief: Violet gravity wave strengthening friendly armor while enemies slump under pressure; circular team benefit and enemy weakening.

Baseline icon: `assets/ui/skills/gen/void_rush.svg`. Data: `src/sim/sim_data.gd:730`. Implementation: `src/sim/sim_kits3.gd:189 (_void_rush)`.

Caution: Despite its name, no dash occurs; it is an area buff/debuff around Roydo.

**dark_matter_skin — Dark Matter Skin** (core; passive).

Mechanic: Damage Roydo takes has a 9 / 13 / 17 / 21% chance to burst back out: 25 / 28 / 31 / 34% of it hits every enemy within 650 as magic damage and slows their movement and attacks by 80% for 0.3 seconds.

Visual brief: Dark alien torso taking a hit then pulsing violet impact energy outward toward several enemies; reactive skin burst.

Baseline icon: `assets/ui/skills/gen/dark_matter_skin.svg`. Data: `src/sim/sim_data.gd:736`. Implementation: `src/sim/sim_kits3.gd:212 (on_damaged)`.

Caution: Reactive pulse after damage, not passive damage resistance.

**anomaly — Anomaly** (core; no_target).

Mechanic: Roydo becomes the Anomaly, a hulking monster, for 30 seconds: his base attack time is 0.25 seconds shorter, he deals 60 / 120 / 180 more attack damage and he attacks from range (650).

Visual brief: Small alien transforming into a hulking muscular purple creature, massive arm launching a ranged energy attack.

Baseline icon: `assets/ui/skills/gen/anomaly.svg`. Data: `src/sim/sim_data.gd:742`. Implementation: `src/sim/sim_kits3.gd:60 (cast)`.

### Blau

**bounce_shot — Bounce Shot** (core; point).

Mechanic: Rifle bullet pierces enemies, reflects from trees, cliffs, buildings, boulders and allied units, and gains 400 travel distance per ricochet; an enemy takes magic damage at most twice.

Visual brief: Rifle bullet ricocheting in a clear zigzag between rock and tree, then passing through an enemy; angled reflections.

Baseline icon: `assets/ui/skills/gen/bounce_shot.svg`. Data: `src/sim/sim_data.gd:749`. Implementation: `src/sim/sim_kits3.gd:292 (_update_bullet)`.

Caution: Enemies are pierced, allies and obstacles reflect; each bounce adds travel distance. Older mechanics prose describing a fixed total path is stale.

**summon_boulders — Summon Boulders** (core; point).

Mechanic: 3 / 4 / 5 / 6 boulders roll out toward the target point at random angles, as far as it (at most 700), bouncing off each other, walls and units. An enemy they hit takes magic damage once and is knocked 200 back. They stay for 10 seconds and block every unit, even phased ones. Bounce Shot ricochets off them.

Visual brief: Several substantial gray round boulders rolling forward in a fan, collision sparks and a knocked-back enemy; no falling meteors.

Baseline icon: `assets/ui/skills/gen/summon_boulders.svg`. Data: `src/sim/sim_data.gd:756`. Implementation: `src/sim/sim_kits3.gd:453 (_summon_boulders)`.

**lay_trap — Lay Trap** (core; no_target).

Mechanic: Blau leaps 400 backwards and leaves a hidden trap where he stood. The first enemy to step on it is caught and cannot move for 1.2 / 1.6 / 2 / 2.4 seconds. The trap lasts 25 seconds.

Visual brief: Open metal ground trap beneath a fading gunner position, gunner leaping backward; toothed jaws and retreat arc.

Baseline icon: `assets/ui/skills/gen/lay_trap.svg`. Data: `src/sim/sim_data.gd:765`. Implementation: `src/sim/sim_kits3.gd:636 (_lay_trap)`.

**place_turret — Place Turret** (core; point).

Mechanic: Blau builds a turret that shoots enemies within 650 every 1.5 seconds for 25 / 30 / 35% of his attack damage (40% at level 3 with the Upgrade Staff); his attack effects work with its shots. It has 900 / 1500 / 2100 health, no regeneration and lasts 35 seconds.

Visual brief: Compact solid gun turret on stable mechanical base firing toward a distant enemy; barrel and mount dominate.

Baseline icon: `assets/ui/skills/gen/place_turret.svg`. Data: `src/sim/sim_data.gd:772`. Implementation: `src/sim/sim_kits3.gd:708 (_place_turret)`.

**pilot_turret — Pilot Turret** (extra; unit).

Mechanic: Upgrade Staff: Blau climbs into one of his turrets and pilots it. The turret gains 300 / 600 / 900 health and shoots what Blau attacks; Blau cannot be hurt inside and still attacks and casts from it. Cast again or move to get out. 5 second cooldown to get in.

Visual brief: Gunner seated inside his armored turret with hands on controls; occupied cockpit distinct from empty turret.

Baseline icon: `assets/ui/skills/gen/pilot_turret.svg`. Data: `src/sim/sim_data.gd:779`. Implementation: `src/sim/sim_kits3.gd:808 (enter_turret)`.

### Azrael

**soul_tap — Soul Tap** (core; toggle).

Mechanic: Toggle. Every 4.5 seconds Azrael scans 600 around her for souls (every unit but herself, allies and enemies alike). If at least one unit is found, it spends 80 mana and grants bonus attack damage on her next strike for each unit and each hero scanned. Her next attack deals pure damage in a 100% cleave over a 400 area, slowing hit enemies by 80% for 0.8 seconds.

Visual brief: White soul wisps drawn into a black scythe, charging one broad white cleaving strike; gathering then striking, no direct life drain.

Baseline icon: `assets/ui/skills/gen/soul_tap.svg`. Data: `src/sim/sim_data.gd:812`. Implementation: `src/sim/sim_kits4.gd:93 (_try_soul_scan)`.

Caution: Charges the next attack from nearby units; it does not directly damage or drain scanned units.

**door_of_the_end — Door of the End** (core; point).

Mechanic: Azrael opens a door to the spirit world. She and up to two allied heroes can walk into it, hidden and unharmed, and may move to step out early without setting off the blast. Cast again to place the exit, up to 800 away. When the door closes, everyone inside steps out in a spirit blast that heals nearby allies, deals magic damage to enemies, stuns them for 1 second, and strips their elemental resistances for 4 seconds.

Visual brief: Two upright spirit doors joined by a pale path; allied silhouettes emerging beside a white blast with green healing light.

Baseline icon: `assets/ui/skills/gen/door_of_the_end.svg`. Data: `src/sim/sim_data.gd:822`. Implementation: `src/sim/sim_kits4.gd:260 (_update_door)`.

Caution: Travel/shelter plus expiry heal/blast; early manual exit does not cause the blast.

**death_scythe — Death Scythe** (core; passive).

Mechanic: Azrael's attacks and spells have a chance to strike as pure damage, adding bonus pure damage and healing her for 50% of the damage done. 1 second cooldown after each strike.

Visual brief: Black scythe with brilliant white edge cutting a foe; white-red healing stream returning along the haft.

Baseline icon: `assets/ui/skills/gen/death_scythe.svg`. Data: `src/sim/sim_data.gd:831`. Implementation: `src/sim/sim_kits4.gd:342 (death_scythe)`.

**divine_darkness — Divine Darkness** (core; no_target).

Mechanic: Azrael spreads her white wings for 25 seconds: she flies over cliffs and trees, moves 15% faster, sees further day and night and attacks faster. Enemies within 700 of her lose part of their sight.

Visual brief: Hooded white-flame soul spreading white wings above terrain, dark ring dimming enemies below; free flight and sight aura.

Baseline icon: `assets/ui/skills/gen/divine_darkness.svg`. Data: `src/sim/sim_data.gd:837`. Implementation: `src/sim/sim_kits4.gd:358 (_divine_darkness)`.

Caution: White wings and free flight, increased own sight and reduced enemy sight; no damage pulse.

### Airah

**gust — Gust** (core; point).

Mechanic: A blast of wind rushes 900 ahead, then turns back to Airah wherever she is. Every enemy it hits takes magic damage and is dragged along toward its head; enemies can still move and act, and can pull free by walking away. An enemy dragged into a tree, cliff, building or unit takes more damage. Trees it hits fall.

Visual brief: Blue-white wind stream sweeping forward and curling back toward its caster, dragging an enemy along its moving head.

Baseline icon: `assets/ui/skills/gen/gust.svg`. Data: `src/sim/sim_data.gd:851`. Implementation: `src/sim/sim_kits5.gd:154 (_update_gust)`.

Caution: Returning wind projectile with non-disabling drag, not a stun or one-way knockback.

**tailwind — Tailwind** (core; unit).

Mechanic: Wind at an ally's back (or Airah's) for 5 seconds: it moves 16 / 22 / 28 / 34% faster, walks through units, and ranged attacks against it miss 25 / 30 / 35 / 40% of the time. Removes slows when cast.

Visual brief: Friendly runner with a bright wind ribbon at its back while arrows bend away; movement and ranged defense.

Baseline icon: `assets/ui/skills/gen/tailwind.svg`. Data: `src/sim/sim_data.gd:858`. Implementation: `src/sim/sim_kits5.gd:237 (_tailwind)`.

**wind_wall — Wind Wall** (core; point).

Mechanic: A wall of wind 600 wide rises across Airah's aim for 4 / 4.5 / 5 / 5.5 seconds. Enemy ranged attacks that touch it stop. Enemies walking through it are slowed by 30%.

Visual brief: Tall translucent blue-white wind barrier catching and stopping incoming arrows; clear vertical barrier plane.

Baseline icon: `assets/ui/skills/gen/wind_wall.svg`. Data: `src/sim/sim_data.gd:863`. Implementation: `src/sim/sim_kits5.gd:275 (_update_wall)`.

Caution: Stops ranged attack projectiles, not every spell projectile.

**hurricane — Hurricane** (core; point).

Mechanic: A hurricane 450 wide for 6 seconds; Airah keeps moving and casting. Trees inside fall. Enemies inside are dragged toward its middle and take magic damage every second; allies inside move 25% faster. When it ends, every enemy still inside is thrown 450 straight out, and one that crashes into a tree, cliff, building or unit is stunned for 1 second.

Visual brief: Broad upright tornado pulling enemies toward its center; debris circling and outward release streaks; no channeling caster pose.

Baseline icon: `assets/ui/skills/gen/hurricane.svg`. Data: `src/sim/sim_data.gd:867`. Implementation: `src/sim/sim_kits5.gd:331 (_update_hurricane)`.

Caution: Persistent point storm while Airah keeps moving/casting; no channel.

### Burak

**axe_throw — Axe Throw** (core; point).

Mechanic: Burak throws an axe up to 1000. The first enemy hit takes physical damage and is slowed by 30% for 2 seconds; the axe sticks in it, or in the first tree or cliff, or drops at the end. For 4 seconds he can cast it again for free to leap to the axe, landing beside it and attacking at once. Walking over a dropped axe picks it up and halves the cooldown left. While the axe is gone he deals 20% less attack damage. A hero hit gives 15 Rage. Upgrade Staff: both axes fly in a fork; he can leap to either.

Visual brief: Heavy thrown axe lodged in a target, curved berserker leap trail toward its haft; axe and follow-up jump.

Baseline icon: `assets/ui/skills/gen/axe_throw.svg`. Data: `src/sim/sim_data.gd:879`. Implementation: `src/sim/sim_kits5.gd:547 (_axe_throw)`.

**reckless_swing — Reckless Swing** (core; no_target).

Mechanic: For 8 seconds Burak's attacks cleave 50 / 60 / 70 / 80% of their damage to the enemies behind his target and heal him for 15 / 20 / 25 / 30% of the damage, but he takes 15% more damage.

Visual brief: Wide axe sweep cleaving through foes behind its first target, red life energy returning; exposed torso suggests risk.

Baseline icon: `assets/ui/skills/gen/reckless_swing.svg`. Data: `src/sim/sim_data.gd:888`. Implementation: `src/sim/sim_kits5.gd:504 (_reckless_swing)`.

**unstoppable — Unstoppable** (core; passive).

Mechanic: When a stun, root or hex lands on Burak while he has 40 Rage or more, he spends 40 Rage and it lasts 40 / 50 / 60 / 70% shorter. Break stops it.

Visual brief: Berserker tearing through a snare and breaking a stun ring using stored red energy; reduced restraint, no immunity bubble.

Baseline icon: `assets/ui/skills/gen/unstoppable.svg`. Data: `src/sim/sim_data.gd:895`. Implementation: `src/sim/sim_kits5.gd:524 (unstoppable_cut)`.

Caution: Spends Rage to shorten stun/root/hex; not immunity.

**berserk — Berserk** (core; no_target).

Mechanic: For 12 seconds Burak's Rage stays full, he deals 40 / 60 / 80 more attack damage, moves 10% faster and slows do nothing to him. Half of the damage he takes is held back and comes back as pure damage over 6 seconds after Berserk ends. Every enemy hero he kills or helps kill during Berserk clears the held damage.

Visual brief: Dual-axe fighter glowing red with full energy; part of an incoming impact held in dark red bands behind him.

Baseline icon: `assets/ui/skills/gen/berserk.svg`. Data: `src/sim/sim_data.gd:899`. Implementation: `src/sim/sim_kits5.gd:764 (hold_damage)`.

Caution: Half damage is delayed, not deleted; kills/assists during effect can clear held damage.

**rage — Rage** (innate; innate).

Mechanic: Burak fills with Rage (up to 100): 1 for every 1% of his health he loses and 5 for every attack he lands on a hero. After 4 seconds without hitting or being hit by a hero he loses 10 a second. Every 10 Rage gives him 5 attack speed (50 when full).

Visual brief: Red-orange clenched fist with ten rising hot energy segments, fueled by received and landed blows; growing attack speed resource.

Baseline icon: `assets/ui/skills/gen/rage.svg`. Data: `src/sim/sim_data.gd:874`. Implementation: `src/sim/sim_kits5.gd:448 (_rage_tick)`.

### Ser Emelrich

**overhead_cut — Overhead Cut** (core; point).

Mechanic: Ser Emelrich raises his sword (this part can still be called off), then winds up for 0.6 seconds with a red line on the ground for everyone to see; from then on only a stun, hex or silence stops the swing. The cut, 450 long and 160 wide, deals physical damage plus 60% of his attack damage and stuns. Trees on the line fall.

Visual brief: Massive steel greatsword descending straight down onto a narrow red ground line; heavy vertical blow, stunned enemy.

Baseline icon: `assets/ui/skills/gen/overhead_cut.svg`. Data: `src/sim/sim_data.gd:906`. Implementation: `src/sim/sim_kits5.gd:901 (_overhead_cut)`.

**sweep — Sweep** (core; no_target).

Mechanic: A wide swing through the half circle in front of him (300): his attack damage plus 40 / 70 / 100 / 130 as physical damage. Enemies hit are shoved 200 to his left, so they pile up; one shoved into a tree, cliff, building or unit takes 40 / 60 / 80 / 100 more and is stunned for 0.5 seconds.

Visual brief: Broad sword sweeping horizontally across a half circle, pushing enemies together toward the swordsman's left.

Baseline icon: `assets/ui/skills/gen/sweep.svg`. Data: `src/sim/sim_data.gd:912`. Implementation: `src/sim/sim_kits5.gd:968 (_sweep)`.

**steel_stance — Steel Stance** (core; toggle).

Mechanic: Toggle (1 second between toggles). While on, Ser Emelrich moves 20% slower and turns half as fast, but has 4 / 6 / 8 / 10 more armor and takes 25 / 35 / 45 / 55% less damage from attacks and line shots that come from his front 120 degrees. Other slows do nothing to him. How he faces matters.

Visual brief: Armored swordsman braced behind a heavy blade deflecting arrows from directly ahead; front protection wedge.

Baseline icon: `assets/ui/skills/gen/steel_stance.svg`. Data: `src/sim/sim_data.gd:918`. Implementation: `src/sim/sim_kits5.gd:1005 (front_block)`.

**giant_swing — Giant Swing** (core; point).

Mechanic: Ser Emelrich winds up for 1.2 seconds (a red cone for everyone to see), then cuts through a cone 700 long and 100 degrees wide: physical damage that ignores 65% of armor, and every enemy hit is knocked down (stunned). Every tree in the cone falls. A stun, hex or silence breaks the wind-up; with Steel Stance on only a hex or silence does. Upgrade Staff: 0.5 seconds later he swings back the other way (a smaller cone, half damage).

Visual brief: Huge greatsword carving a broad forward cone through enemies and trees, knocking foes down; wide rather than straight strike.

Baseline icon: `assets/ui/skills/gen/giant_swing.svg`. Data: `src/sim/sim_data.gd:923`. Implementation: `src/sim/sim_kits5.gd:926 (_cone_cut)`.

Caution: Wide cone with partial armor bypass and optional Staff return swing; distinguish from Overhead Cut line.

### Feran Mock

**knife_juggle — Knife Juggle** (core; point).

Mechanic: Feran throws 4 / 5 / 6 / 7 knives 0.1 seconds apart, each at a random angle within 25 degrees of his aim, 800 far. Each knife deals magic damage to the first enemy it hits; one enemy is hit by at most 5 knives a cast.

Visual brief: Jester hand releasing a fan of separate throwing knives in close staggered paths; sharp metal and successive throws.

Baseline icon: `assets/ui/skills/gen/knife_juggle.svg`. Data: `src/sim/sim_data.gd:932`. Implementation: `src/sim/sim_kits6.gd:153 (_update_knife)`.

**joke_box — Joke Box** (core; point).

Mechanic: Feran throws a box that lands and pops after a 0.8 second fuse: enemies within 275 take magic damage and each rolls its own prank. Pie: its attacks miss half the time for 3 seconds. Spring: thrown 350 in a random direction (a crash into a tree, cliff or unit stuns for 0.6 seconds). Confetti: silenced. Glue: rooted.

Visual brief: Open wooden prank box popping with a pie, coiled spring, confetti and sticky glue; box central, varied prank contents.

Baseline icon: `assets/ui/skills/gen/joke_box.svg`. Data: `src/sim/sim_data.gd:939`. Implementation: `src/sim/sim_kits6.gd:230 (_prank)`.

**swap — Swap** (core; unit).

Mechanic: Feran and any hero, ally or enemy, trade places at once; projectiles aimed at either of them miss. A swapped enemy is turned to face away and slowed by 40% for 1.5 seconds. Upgrade Staff: cast it on an allied hero to mark it, then on an enemy hero: those two trade places and Feran stays put.

Visual brief: Two different figures exchanging positions along opposing curved violet arrows; reciprocal movement clear.

Baseline icon: `assets/ui/skills/gen/swap.svg`. Data: `src/sim/sim_data.gd:947`. Implementation: `src/sim/sim_kits6.gd:274 (_swap)`.

**shuffle — Shuffle** (core; point).

Mechanic: Every enemy hero and creep in the area trades places with another random enemy there, is stunned, then is dizzy for 3 seconds (turns half as fast and moves 25% slower). Then knives fly out of the middle in every direction: 6 Knife Juggles at its level, each hitting one enemy at most 5 times. With one enemy inside, it trades places with Feran instead.

Visual brief: Several enemies exchanging places around a circular swirl while knives fly outward from its center; multiple rearranged targets.

Baseline icon: `assets/ui/skills/gen/shuffle.svg`. Data: `src/sim/sim_data.gd:953`. Implementation: `src/sim/sim_kits6.gd:309 (_shuffle)`.

### Ghorman

**tame — Tame** (core; unit).

Mechanic: A neutral creep (not from the ancient camp) or an enemy lane creep becomes Ghorman's beast for good, with 20 / 30 / 40 / 50% more health and attack damage, and keeps its own ability. He can lead 1 / 2 / 3 / 5 at once; taming past that releases the oldest (it dies). Upgrade Staff: ancient creeps too, one of them at a time.

Visual brief: Beast leader's open hand reaching toward a wolf with a friendly green collar glow; creature joining, no cage or damage.

Baseline icon: `assets/ui/skills/gen/tame.svg`. Data: `src/sim/sim_data.gd:960`. Implementation: `src/sim/sim_kits6.gd:389 (_tame)`.

**roar — Roar** (core; no_target).

Mechanic: Enemies within 500 are slowed by 35 / 40 / 45 / 50% and deal 15 / 20 / 25 / 30% less attack damage for 6 seconds. His beasts within 900 attack 30 faster (and 2% more for each beast he leads) and move 20% faster for 6 seconds.

Visual brief: Beast leader roaring a pressure wave at foes, friendly wolves behind him surging forward; roaring mouth and pack.

Baseline icon: `assets/ui/skills/gen/roar.svg`. Data: `src/sim/sim_data.gd:965`. Implementation: `src/sim/sim_kits6.gd:526 (_roar)`.

**pack_leader — Pack Leader** (core; passive).

Mechanic: Each of his beasts within 900 gives Ghorman 3 / 4 / 5 / 6 attack damage and 1 / 1.5 / 2 / 2.5 armor. When one of his beasts dies, he heals 8 / 10 / 12 / 14% of his health.

Visual brief: Beast leader with several close wolves, their shared warm energy strengthening his weapon and armor; group pack composition.

Baseline icon: `assets/ui/skills/gen/pack_leader.svg`. Data: `src/sim/sim_data.gd:972`. Implementation: `src/sim/sim_kits6.gd:553 (_pack)`.

Caution: Each nearby beast gives damage and armor; beasts dying heal Ghorman. Distinguish from Pack Aura on Alpha Wolf.

**beast_form — Beast Form** (core; no_target).

Mechanic: Ghorman becomes a huge beast for 25 seconds: 300 / 600 / 900 more health, 40 / 60 / 80 more attack damage and 40 more speed; every 3rd attack is a maul for 100 / 150 / 200 more physical damage and a 0.6 second bash. His beasts grow too: 25% more health, and their abilities come back 25% faster.

Visual brief: Human beast leader transforming into a huge clawed beast, smaller friendly pack beasts growing beside him.

Baseline icon: `assets/ui/skills/gen/beast_form.svg`. Data: `src/sim/sim_data.gd:983`. Implementation: `src/sim/sim_kits6.gd:626 (maul)`.

**blessing_of_the_beast_king — Blessing of the Beast King** (extra; unit).

Mechanic: Ghorman blesses one of his beasts: it heals 30 / 40 / 50 / 60% of its health, is cleansed of slows, silences and roots, its ability is ready again, and for 8 seconds it deals 20 / 30 / 40 / 50% more attack damage and attacks 20 / 30 / 40 / 50 faster.

Visual brief: Large hand casting green-gold healing on one friendly wolf; broken restraints fall away as claws brighten with strength.

Baseline icon: `assets/ui/skills/gen/blessing_of_the_beast_king.svg`. Data: `src/sim/sim_data.gd:977`. Implementation: `src/sim/sim_kits6.gd:585 (_bless)`.

### Araki

**blur_strike — Blur Strike** (core; point).

Mechanic: Araki dashes up to 600 like a flash and slashes every enemy within 250 of his path: each one takes an attack (critical strikes, bashes and every other attack effect can happen) and 50 / 80 / 110 / 140 magic damage, and is slowed by 60% for 1 second. If he hits any enemy unit, Blur Strike's cooldown is refreshed once: he can dash a second time within 6 seconds.

Visual brief: Katana fighter flashing through several foes in one straight dash, broad blade trail and faint second dash afterimage.

Baseline icon: `assets/ui/skills/gen/blur_strike.svg`. Data: `src/sim/sim_data.gd:999`. Implementation: `src/sim/sim_kits7.gd:144 (_blur_strike)`.

**djin_bomb — Djin Bomb** (core; point).

Mechanic: Araki throws a bomb that sets a demon loose in a cloud of smoke (radius 450) for 5 seconds. Enemies inside lose 10 / 15 / 20 / 25% magic resistance and 10 / 15 / 20 / 25% status resistance, and are slowed by 5 / 8 / 11 / 14% more for every second they stay in it.

Visual brief: Small thrown bomb opening into dense purple smoke with a demon face; enemies slowed inside, no fiery blast.

Baseline icon: `assets/ui/skills/gen/djin_bomb.svg`. Data: `src/sim/sim_data.gd:1007`. Implementation: `src/sim/sim_kits7.gd:213 (_update_smoke)`.

Caution: Smoke reduces resistances and builds slow; the bomb deals no direct damage.

**ghosts_of_the_will — Ghosts of the Will** (core; unit).

Mechanic: Araki calls 3 / 5 / 7 / 9 ghosts from the Undead realm, one every 0.3 seconds. Each flies out at 650 (through units, over cliffs and trees), strikes the target once for 25 / 35 / 45 / 55% of Araki's attack damage, and is gone. Their hits add Senryukai stacks and renew them. One hit destroys a ghost. If the target dies, the ghosts left go for the nearest enemy.

Visual brief: Several translucent katana ghosts flying in sequence toward one marked foe; foremost strikes once then dissolves.

Baseline icon: `assets/ui/skills/gen/ghosts_of_the_will.svg`. Data: `src/sim/sim_data.gd:1015`. Implementation: `src/sim/sim_kits7.gd:307 (_ghost_hit)`.

Caution: Ghosts fly, strike once and disappear; they are not long-lived ordinary duplicate heroes.

**the_blur — The Blur** (core; no_target).

Mechanic: For 19 seconds Blur Strike and Djin Bomb cooldowns are halved, including cooldowns already running; the next 9/15/21 released normal attacks gain attack speed. Dash and ghost hits do not spend that attack count.

Visual brief: Focused katana fighter surrounded by rapid sword afterimages and accelerating cooldown arcs; concentration, no invisibility.

Baseline icon: `assets/ui/skills/gen/the_blur.svg`. Data: `src/sim/sim_data.gd:1022`. Implementation: `src/sim/sim_kits7.gd:361 (_the_blur)`.

**senryukai — Senryukai** (innate; innate).

Mechanic: Araki's katana grows sharper the longer the fight goes on. Each of his attacks (and his ghosts') on an enemy adds a stack: every stack deals 4 more physical damage on his hits on that enemy. The stacks last 15 seconds, renewed with every hit. Not on buildings.

Visual brief: Sharp katana repeatedly cutting one marked enemy, three accumulating slash marks deepening at the same point.

Baseline icon: `assets/ui/skills/gen/senryukai.svg`. Data: `src/sim/sim_data.gd:995`. Implementation: `src/sim/sim_kits7.gd:99 (senryukai_bonus)`.

### Wolf

**snarl — Snarl** (neutral spell; no_target).

Mechanic: The wolf snarls: nearby enemies deal 60% less attack damage for 4 seconds.

Visual brief: Snarling wolf muzzle emitting a low blue pressure wave toward weakened enemy weapon silhouettes; no fear symbols.

Baseline icon: `assets/ui/skills/war_cry.svg`. Data: `src/sim/sim_data.gd:790`. Implementation: `src/sim/sim_abilities.gd:761 (_neutral_spell)`.

Caution: Neutral icon has a separate routing table; direct ability_icon fallback was keen_eye.

### Orc Shaman

**stomp — Stomp** (neutral spell; no_target).

Mechanic: Stomps the ground: enemies nearby take magic damage and are stunned (1.6 s heroes, 3 s others).

Visual brief: Broad orc foot striking earth, compact brown shockwave lifting stunned enemies; distinct from Ezee's dark outward throw.

Baseline icon: `assets/ui/skills/tempo_wd_quake.svg`. Data: `src/sim/sim_data.gd:794`. Implementation: `src/sim/sim_abilities.gd:761 (_neutral_spell)`.

Caution: Neutral icon has a separate routing table; direct ability_icon fallback was keen_eye.

### Ogre

**smash — Smash** (neutral spell; point).

Mechanic: Raises its club for 2.8 seconds, then smashes the ground: enemies in the area take magic damage and are stunned.

Visual brief: Huge ogre club raised overhead then slamming a ground circle with rock fragments and stunned enemies; blunt club.

Baseline icon: `assets/ui/skills/heavens_fist.svg`. Data: `src/sim/sim_data.gd:798`. Implementation: `src/sim/sim_abilities.gd:761 (_neutral_spell)`.

Caution: Neutral icon has a separate routing table; direct ability_icon fallback was keen_eye.

### Goblin Digger

**weapon_grab — Weapon Grab** (neutral passive; passive).

Mechanic: An attack disarms its living enemy target for 3 seconds, once every 9 seconds; Break stops the passive.

Visual brief: Goblin hand wrenching a sword away from an enemy fist, blade tilted out of control; lost attack ability, no armor fracture.

Baseline icon: `assets/ui/status/weakened.svg`. Data: `src/sim/sim_data.gd:189`. Implementation: `src/sim/sim_ai.gd:486 (on_creep_hit)`.

Exact data key: `mudling_digger.on_hit`. No standalone SimData ability ID.

Caution: Baseline HUD and BuffBar use different generic status paths for this on-hit skill; replace both consistently.

### Goblin Boss

**pace_aura — Pace Aura** (neutral aura; passive).

Mechanic: Allied units within 1200 gain 12 movement speed; aura includes its source, lingers briefly, and stops under Break.

Visual brief: Several goblin feet running together inside a shared green circular breeze; movement speed aura, no sword damage symbol.

Baseline icon: `assets/ui/status/aura_might.svg`. Data: `src/sim/sim_data.gd:193`. Implementation: `src/sim/sim_ai.gd:472 (_unit_auras)`.

Exact data key: `mudling_foreman.auras[0]`. No standalone SimData ability ID.

Caution: All four baseline neutral auras share aura_might art despite different stats; this needs a distinct icon.

### Alpha Wolf

**pack_aura — Pack Aura** (neutral aura; passive).

Mechanic: Allied units within 1200 gain 20% base attack damage; aura includes its source and stops under Break.

Visual brief: Alpha wolf head leading smaller wolves, their bright teeth joined by a red circular energy band; shared pack attack strength.

Baseline icon: `assets/ui/status/aura_might.svg`. Data: `src/sim/sim_data.gd:202`. Implementation: `src/sim/sim_ai.gd:472 (_unit_auras)`.

Exact data key: `ashfang_alpha.auras[0]`. No standalone SimData ability ID.

Caution: All four baseline neutral auras share aura_might art despite different stats; this needs a distinct icon.

### Orc

**magic_armor_aura — Magic Armor Aura** (neutral aura; passive).

Mechanic: Allied non-heroes within 1200 gain 20% magic resistance; heroes gain 10%; aura includes its source and stops under Break.

Visual brief: Orc silhouette inside a blue protective ring deflecting a glowing magic bolt, with smaller allies sharing the ring; magical defense.

Baseline icon: `assets/ui/status/aura_might.svg`. Data: `src/sim/sim_data.gd:206`. Implementation: `src/sim/sim_ai.gd:472 (_unit_auras)`.

Exact data key: `strider.auras[0]`. No standalone SimData ability ID.

Caution: All four baseline neutral auras share aura_might art despite different stats; this needs a distinct icon.

### Swamp Troll

**break_strike — Break Strike** (neutral passive; passive).

Mechanic: An attack applies Break for 3 seconds, disabling passives, once every 10 seconds; Break stops the attacker's passive.

Visual brief: A swamp troll projectile shattering a small glowing passive power circle on an enemy; suppressed inner power, no broken physical armor.

Baseline icon: `assets/ui/status/sundered.svg`. Data: `src/sim/sim_data.gd:216`. Implementation: `src/sim/sim_ai.gd:486 (on_creep_hit)`.

Exact data key: `hill_troll.on_hit`. No standalone SimData ability ID.

Caution: Baseline HUD and BuffBar use different generic status paths for this on-hit skill; replace both consistently.

### Lava Golem

**thick_hide_aura — Thick Hide Aura** (neutral aura; passive).

Mechanic: Allied units within 1200 gain 3 armor; aura includes its source and stops under Break.

Visual brief: Large stone-skinned creature radiating a brown protective ring around allies, their hides or armor thickening; shared physical armor.

Baseline icon: `assets/ui/status/aura_might.svg`. Data: `src/sim/sim_data.gd:229`. Implementation: `src/sim/sim_ai.gd:472 (_unit_auras)`.

Exact data key: `elder_cinder_wyrm.auras[0]`. No standalone SimData ability ID.

Caution: All four baseline neutral auras share aura_might art despite different stats; this needs a distinct icon.

### Alpha Wolf

**neutral_crit — Crit** (neutral passive; passive).

Mechanic: Attacks have a 20% chance to deal 200% damage; rolled when the attack starts, disabled by Break, not on buildings or wards.

Visual brief: Wolf jaws delivering one powerful bright red critical bite, sharp doubled fang impact; single high-damage hit, no bleed.

Baseline icon: `assets/ui/skills/lethality.svg`. Data: `src/sim/sim_data.gd:201`. Implementation: `src/sim/sim_combat.gd:349 (crit_sources)`.

Exact data key: `ashfang_alpha.crit`. No standalone SimData ability ID.

### Lava Golem

**neutral_splash — Splash** (neutral passive; passive).

Mechanic: Attacks also deal 100% of their pre-reduction damage to enemies within 250 of the target; the source's Magic weapon makes this magical splash damage; Break stops it.

Visual brief: Burning lava projectile bursting around its struck target in a circular orange splash that hits nearby foes; circular impact, no melee cone.

Baseline icon: `assets/ui/skills/cleave.svg`. Data: `src/sim/sim_data.gd:228`. Implementation: `src/sim/sim_ai.gd:486 (on_creep_hit)`.

Exact data key: `elder_cinder_wyrm.splash`. No standalone SimData ability ID.

Caution: Legacy cleave implies a melee cone; actual Lava Golem splash is a circular magical blast around the target.

### Fire Imp; Lava Golem

**ancient — Ancient** (neutral trait; passive).

Mechanic: Ancient-creep classification blocks ordinary Tame without Upgrade Staff and Gold Glove use; it is a targeting restriction, not an active spell.

Visual brief: Large old stone creature beneath a solid protective crest shape; sturdy creature classification, no active invulnerability bubble.

Baseline icon: `assets/ui/status/titan.svg`. Data: `src/sim/sim_data.gd:223`. Implementation: `src/sim/sim_kits6.gd:373 (tame_error)`.

Exact data key: `cinder_wyrmling.ancient; elder_cinder_wyrm.ancient`. No standalone SimData ability ID.

Caution: A unit classification, not a learned or cast ability.

## Verification

Checked all `_abilities` definitions against JSON IDs; 79/79 covered. Checked all 17 hero definitions and four innate references. Checked baseline resource existence for all 88 entries. Checked neutral HUD entries against unit definitions (spells, auras, on-hit effects, crit, splash and Ancient). Secondary casts reviewed as shared IDs, so they are not duplicated as invented abilities. No source files changed by this audit.
