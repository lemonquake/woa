# Run 2026-10-16: Roydo and Blau

## Request (owner, 2026-10-16)

Two new heroes, "perfect and awesome": custom textures, particles, models, animations with intent (no twisting
limbs); free models found online (Roydo's Anomaly form included); bots that really know how to play both (Blau most
of all); QA, build the game, push to main.

* **Roydo, the Anomaly**: intelligence, melee, Neutral element, a space-themed alien humanoid.
  * Grip of the Ruler: 650 cast range, 400 area; picks a random unit (enemy heroes first; with no enemies, an ally,
    unharmed), throws it to the centre on a parabola over 0.8 s (it plays a pulled / stagger clip), then 100/140/180/220
    magic damage and a 1 s stun in the area. 18/17/16/15 s, 100/110/120/130 mana.
  * Void Rush: 650 area. Enemies: status resistance -20/30/40/50%, damage dealt -10/15/20/25%. Allies: +7/9/11/13 armor
    and +7/9/11/13% move speed. 7 s. 15/14/13/12 s.
  * Dark Matter Skin: 9/13/17/21% chance to reflect 25/28/31/34% of damage taken to a 650 area as magic damage, slowing
    80% move and attack speed for 0.3 s.
  * Anomaly: becomes a hybrid monster: base attack time -0.25 s, +60/120/180 damage, ranged (650). 30 s, 65 s cooldown.
* **Blau, the Master Tactician**: agility, ranged 600, Neutral element, a gun mage with a scout sniper rifle.
  * Bounce Shot: point, 800; a magic bullet that passes through enemies and bounces off trees, units, walls, boulders;
    3/5/7/9 bounces; damages each enemy at most twice.
  * Summon Boulders: 3/4/5/6 boulders roll forward at random angles for 1-2 s with physics (bounce off each other,
    walls, units); block every unit (phased too); Bounce Shot bounces off them; 80/100/120/140 damage once per unit and
    a 200 push; last 10 s; 20/19/18/17 s.
  * Lay Trap: leaps 400 back, leaving a trap that roots one unit 1.2/1.6/2/2.4 s. 10/9/8/7 s.
  * Place Turret: a turret that attacks enemies within 650 every 1.5 s for 25/30/35/40% of Blau's attack (orbs and
    attack modifiers work); 35 s; 10 s cooldown; 900/1500/2100 health, no regen, no mana.
  * Item upgrade: a skill to pilot a turret (get out any time): +300/600/900 health to it; getting in: 5 s cooldown.

## Choices (owner's numbers kept; these fill gaps, listed in the handoff for veto)

* Upgrade item: the Upgrade Staff (Dota's Aghanim's Scepter) grants Pilot Turret.
* Place Turret: a 3-level ultimate (levels 6/12/18) like every other ultimate; health 900/1500/2100 by level; damage
  25/30/35% by level and the Upgrade Staff adds 5% (40% at level 3 with it), so all four given numbers are used.
* Missing numbers: mana and cooldowns where not given, Bounce Shot damage, distance and speed, trap life and trigger
  radius, turret armor and bounty, base stats of both heroes, talents. Marked *chosen* in `docs/HANDOFF.md`.

## Components (builder: this agent; one owner per file set)

| Id | Component | Files | Acceptance (fixed before results) |
|---|---|---|---|
| M1 | Models | tools/blender/roydo_blau.py, assets/characters/heroes16/* | CC0 sources logged; each glb loads in Godot; every clip the catalog names exists; anim_audit-style check: no bone turns > 90 degrees in one frame in any clip used; rifle in both hands in gun clips; frame sheets inspected |
| S1 | Roydo kit | sim_kits3.gd, sim_data.gd, sim_unit.gd, sim_combat.gd | tests: Grip picks enemy hero over creep over ally, 0.8 s toss, damage + 1 s stun, ally unharmed; Void Rush values both sides, 7 s; Skin chance/pct/650/slow; Anomaly BAT -0.25, damage, ranged 650 with projectiles, back to melee after 30 s |
| S2 | Blau kit | sim_kits3.gd, sim_map.gd, sim_orders.gd, sim_data.gd | tests: bullet reflects off a tree / wall / boulder / allied unit, passes enemies, bounce cap, 2 hits per enemy; boulders count, roll 1-2 s, block phased units and pathing, one hit per unit, 200 push, 10 s; trap leap 400 back, roots first enemy, durations; turret 650 range, 1.5 s, pct of Blau's attack with crit/lifesteal procs, health by level, no regen, 35 s; Pilot: needs Upgrade Staff, +health, Blau safe inside, exits on order / death, 5 s cooldown |
| V1 | Visuals | hero16_fx.gd, shaders, unit_view.gd, model_catalog.gd, item_icons.py | captures of every skill and both heroes at 1080p; Anomaly model swap both ways; no script errors |
| U1 | UI and menus | hero_select, hero_stage, game_settings, hud, buff_bar, main_menu, targeting_fx | captures: hero select, skill bar with granted Pilot slot, buff bar entries, tooltips; "Names OK" |
| B1 | Bots | sim_bot.gd, sim_bot_kits.gd, sim_bot_items.gd, sim_team_ai.gd | tests: bot Bounce Shot aims at bounce paths that hit, boulders cut escapes, trap on retreat, turret placement in fights / pushes, pilot when hurt with Upgrade Staff; duels and a 5 v 5 game with both heroes, no script errors |
| I1 | Integration | all | headless tests pass; check.sh; live match; export; cold start; commit and push |

Benchmark: Dota 2 behaviour from the wiki for the referenced mechanics (base attack time reductions: Alchemist's
Chemical Rage, Terrorblade's Metamorphosis; status resistance; summons); no Dota frames on disk, so looks are builder
self-checks unless a critic reviews them. Budget: 8 passes per component.
