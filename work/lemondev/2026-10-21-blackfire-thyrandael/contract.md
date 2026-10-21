# Run 2026-10-21: Blackfire and Thyrandael (contract)

## The owner's request (verbatim points)
* Two new heroes from the owner's models in `work/downloads/sf_heroes/`:
  * **Blackfire, the Unfallen**: dark, melee, strength; 3 / 1.1 / 2.9 strength / agility / intelligence a level.
    Innate **Underworld Presence** (a unit dying within 1000 heals him 4% max health, heroes 150% more; black souls fly
    to him). **Sacrificial Grip** (650 range, 100-130 mana, 8 s; both stunned 2-2.6 s; 25% current health as pure,
    non-lethal; then both -30% attack damage for 2 s; his Undead go for the target). **Rise Up** (instant, 100 mana,
    38-32 s; raises nearby dead units for 20 s, not ancients, heroes, buildings, summons or mind-controlled units;
    a 1000 aura for 20 s; raised units stay when it ends; they are Undead). **Fiend Edge** (10-25% for a 2x crit;
    20-35% of the damage heals allies within 800). **Unfallen** (ultimate: up again 3 s after dying with 25% more
    damage, armor, move and attack speed for 3 / 4 / 5 s, then dies; at the end a blast pushes all units within 400,
    allies too, 300 away; a crash into walls, trees or units stuns 0.5 s).
  * **Thyrandael, the Forsaken Seraph**: light, melee, intelligence; 2.8 / 2 / 4 a level. Innate **Divine Touch**
    (every spell cast: a charge, an All-damage Barrier equal to his intelligence). New feature: barriers that work
    like health but yellow, blocking damage kinds: Magic, All-damage, Physical. **Holy Beam** (800, 120 mana, 15 s;
    channel up to 7 s, S stops it and the player is told so; turn rate 60% slower, cannot move, a move order turns
    him with the beam; 50-110 magic damage and 30-60 mana burn a second, 30% slow while touched). **Quick Flash**
    (instant, 2.2 s, 60 mana, 500: 30-90 magic, 10 s mark, +10-25 stacking per later hit). **Spirit Step** (teleport,
    400-940, 15-9 s; silence 1-2.2 s and 40% slow 1 s). **False Judgement** (a charge per 300 / 250 / 200 damage
    taken, up to 10 / 11 / 12, shown over him; a light blast at a point: up to 40 / 70 / 100% miss, 55% slow, 60-100
    magic a second for 5 s; up to 800 / 1200 / 1600 range; cooldown 10 / 9 / 8 down to 6 / 5 / 4 at max charges).
* Wire them into the game, the AI players' brains and chat context (bots know how to use them and are good with them).
* Mid-run: **Forums moved into the Ranked top bar** (screenshot of Play / Profile / Leaderboard / Players / Guilds).
* Mid-run: **25% quicker matchmaking waits**.
* Build the game.

## Components, owners, gates
| Id | Component | Owner (files) | Gate |
|---|---|---|---|
| C1 | Barrier system | `src/sim/sim_barrier.gd`, `sim_combat.gd` hook, `src/ui/barrier_bar.gd`, bars | `test_barrier_kinds`; capture of a barrier on a bar |
| C2 | Blackfire kit | `src/sim/sim_kits8.gd`, data in `sim_data.gd`, hooks in combat / orders / abilities | `test_blackfire_*` |
| C3 | Thyrandael kit | `src/sim/sim_kits9.gd`, data, order hook (beam aim) | `test_thyrandael_*` |
| C4 | Bots and chat | `src/sim/sim_bot21.gd`, `sim_bot.gd`, `sim_bot_kits.gd`, `sim_bot_items.gd`, `chat_mind.gd`, `sim_bot_chat.gd`, `llm_chat.gd`, `forum_writer.gd` | `kit_casts.gd` every skill cast; bot games with the heroes traded between teams |
| C5 | Visuals, sound, UI | `src/game/hero21_fx.gd`, `audio.gd`, `unit_view.gd` (Unfallen fall), `hud.gd` (S hint, barrier), `buff_bar.gd`, Hero Select texts, icons (`tools/item_icons.py`) | captures in a match |
| C6 | Bodies and swords | builder agent: `tools/blender/joints/*`, `assets/characters/heroes17/blackfire*`, `thyrandael*`, `assets/weapons/*_sword*`, ModelCatalog entries | collision and joins numbers, close-up renders |
| C7 | Forums tab, matchmaking | `src/ui/forums.gd` (embedded), `ranked_menu.gd`, `main_menu.gd`, `matchmaker.gd` | capture of the tab; matchmaking expect x0.75 |
| I | Integration | all | full suite, `sh tools/check.sh`, export, cold start |

## Chosen where the owner left it open (listed in docs/HANDOFF.md for veto)
Base attributes and attack timing (templates), Spirit Step mana 80 and stomp radius 300, False Judgement mana
100 / 125 / 150 and radius 400, its range never under 300, Holy Beam width 150, Divine Touch up to 3 charges for 12 s,
bodies raisable for 8 s after death, Undead give no bounty, Fiend Edge heals Blackfire too, Unfallen rises with full
health and has no cooldown, barrier colours (All gold, Physical orange, Magic blue), talents.

Benchmark: no Dota 2 client on this machine; benchmark gate UNVERIFIED (as earlier runs).
Pass budget: 8 per component.
