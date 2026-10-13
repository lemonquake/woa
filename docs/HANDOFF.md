# Warriors of Aether: handoff

*A Dota 2-style lane battle game by Aljay Leodones. Godot 4.7.2 (Forward+), Blender 5.2 for building models.*

## Status (keep this section current)

**IMPLEMENTED, NOT FULLY VERIFIED** (2026-10-13 c: camera, neutral camps, Game Setup, team bots, chat, pings,
learning; run `work/lemondev/2026-10-13-camps-ai-setup/`, contract in `contract.md` there). The owner asked to cut the
remaining tests and finish; the final integration gate was **not** completed.

Built (details in the sections "Neutral camps" and "Game Setup, bots, chat, pings, learning" below):
* Camera starts on your hero; Options > Game "Center camera on hero at respawn". Edge pan no longer runs under the
  loading screen or with the cursor outside the window.
* 14 neutral camps a side with modelled camp props (`tools/blender/camps.py`), spawn boxes on Shift and the minimap.
* Game Setup screen (two teams of five: You / Bot / Empty, hero, bot skill, lane; duplicates allowed).
* Team brain and hero bots (`sim_team_ai.gd`, `sim_bot.gd`, `sim_bot_kits.gd`), team chat and pings with replies,
  typed chat, bot learning saved in `user://bot_memory.json` (on by default, can be turned off and cleared).

Evidence on disk (from before the cut-off):
* Captures in `shots/`: camera start and respawn, camps by size and at night, spawn boxes, Game Setup (1080p and 4K),
  Options, team chat, pings, typed chat (4K in `shots/4k/`).
* `python tools/check_names.py`: "Names OK" (rerun at the end).

Not met (known failures, left for the next session):
* 5 v 5 bot games (`games/r3_*`, `r4_*`, 10 games at 40 min): **no Ancient fell in any game**, so the AI2 gate
  "an Ancient falls within 60 min" fails. Stuck heroes are reported in every game; two (`Bot Cat`, `Bot Jo`) stand
  still in a lane from 0:21 in all ten games at the same spots, which looks like one bug, not bad play.
* Benchmark with 10 heroes (`bench_5v5.txt`): 39-58 fps, p95 24-36 ms (with 2 heroes, `bench_1v1.txt`: 48-53 fps).
  Earlier sessions measured 76-82 fps with 2 heroes, so this run is slower; the 10% gate fails. Profile shows the sim
  (4-7 ms) and physics process as the large parts.
* Not rerun at the end: the 100+ headless tests, input and HUD probes, camera and team probes, learning A/B games.
* Blind visual review of camps and Game Setup: no Dota frames, UNVERIFIED.
* Earlier results still stand: Shuriken Hook visuals STOPPED: PLATEAU, base environment and ramps STOPPED: PLATEAU,
  Burst Shot VFX and Hero Select STOPPED: PLATEAU, Dark Stomp VFX STOPPED: LIMIT, tower scale UNVERIFIED.

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
* Tests (headless, about 1 minute): `godot --headless --path . -s tests/run_tests.gd`. Add `-- --only=<name>` for a subset. 59 tests.
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
* 5 v 5 bot games (headless): `godot --headless --path . -s tests/tools/bot_game.gd -- --seeds=3,7 --min=40 [--chat]
  [--skill=hard] [--learn=work/mem.json --learn_teams=1,0] [--out=file]` prints the result, each hero's line, LH and net
  worth at 10:00 and 20:00, time per bot mode, stuck heroes and the team chat. `tests/tools/trace_game.gd` prints each
  bot's mode, desires, order and target every few seconds; `tests/tools/bot_profile.gd` the cost of each step part.
* Camp layout check: `godot --headless --path . -s tests/tools/camp_layout.gd` (clearances, reachability, plot).
* Live probes (open a window, play a real match, print PASS / FAIL):
  `godot --path . -s tests/tools/camera_probe.gd` (camera at the start and at respawn),
  `godot --path . -s tests/tools/team_probe.gd -- --bots=5v5 --nolearn --out=work/shots` (bot chat in the HUD, ping
  replies, Shift spawn boxes, typed chat),
  `godot --path . -s tests/tools/input_probe.gd -- --hero=sludge --nobot` (every ability through the input
  controller), `godot --path . -s tests/tools/item_flow_probe.gd -- --hero=sludge` (shop, To Buy, drag and drop,
  talents, courier), `godot --path . -s tests/tools/ui_probe.gd -- --hero=sludge --out=work/shots` (HUD captures).
* `--showqueue` (capture flag) queues a few orders for your hero and draws the Shift waypoints.
* Parse-check every script: `sh tools/check.sh`.
* Rebuild the building models: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/buildings.py`.
* Re-bake the terrain texture arrays (needs the GPU, not headless): `godot --path . -s tests/tools/bake_terrain_arrays.gd`.

## Controls (Dota defaults)

Every hotkey can be changed on the **Hotkeys** screen shown before each match ("Are you good to go?"): one key, Mouse 4 / 5, or a combination with Ctrl, Alt or Ctrl + Alt. Shift is never part of a hotkey because it queues. Esc, F10, Ctrl + 1-9, Alt + F4 and Alt + Tab are refused. Layouts can be saved as named templates (`user://keybinds.json`). The table shows the defaults.

| Key | Action |
|---|---|
| Left click / left drag | Select. A drag draws a green box: your own units inside it are selected (hero first); with none of yours inside, the one unit nearest the box centre |
| Right click | Move, attack an enemy, deny an ally below 50% HP, follow an ally. Orders go to the selected units you control (hero, courier), as in Dota |
| A, then left click | Attack-move (ground) or attack (unit). On an ally the order is accepted: your hero waits in range and only swings once the ally can be denied. Shows your attack range |
| S | Stop (the hero still auto-attacks enemies in range). Hold S: hard stop, no auto-attack until your next order |
| H | Hold position |
| Shift + any order or hotkey | Queue it, as in Dota: orders run one after another; a queued spell still cooling down is checked again when its turn comes. Holding Shift shows the queue as numbered waypoints (green move, red attack, blue spell or item, gold hold) |
| Q W E R | Abilities. No-target spells and toggles (Stench) act at once. Point and unit spells show a pulsing crosshair: red for spells aimed at enemies, green for support (allies, yourself, a place); items too. A click that misses a valid target keeps the cursor and says why; right click or Esc cancels |
| Ctrl + an ability's hotkey, or the "+" above an ability | Learn the ability (unless that Ctrl combination is bound to something else) |
| Right click an ability button | Toggle autocast (Frost Quiver) |
| Z X C V B N | Items. Right click an item slot to move it between the inventory and the backpack. Drag an item to another slot, to the stash (in the base), onto the ground (the hero walks over and drops it) or onto an allied hero or your courier (gives it) |
| Right click an item on the ground | Pick it up |
| Talents button (star left of the abilities) | Opens the talent tree from level 10: one of two talents per tier, costs an ability point |
| Stash (above the items) | Shown when it holds something or you are in the base: click an item to take it, drag it to a slot, Grab All |
| Shift + click in the shop | Adds the item to **To Buy** (right side of the screen), broken into the parts you still need. In To Buy: left click buys, right click buys it automatically once you have the gold (into the courier if it waits at the fountain), Ctrl + click or x removes |
| F4, the Shop button, or B with an empty slot 5 | Shop |
| J, or the button above the minimap | Glyph |
| T | Town Portal: target a point or the minimap; the hero teleports beside the nearest allied building after a 3 s channel |
| F3, or the Deliver button | Courier picks up your items lying in the fountain area, takes the stash and flies it all to you |
| F2 (courier selected) | Q Return to Base, W Retrieve Items, E Return Items to Stash, R Deliver, Z Transfer, X Speed Burst (level 10), C Shield (level 20), V Auto Deliver; right click moves it |
| Buyback button (while dead) | Buy back: 200 + net worth / 13 gold, 8 minute cooldown |
| F1 | Select your hero; press twice to centre on it |
| Portrait | Click: select your hero and centre the camera on it. Hold: the camera follows your hero |
| Ctrl + 1..9, then 1..9 | Control groups (double tap centres the camera) |
| Alt + click | Ping (ground or minimap). On an enemy hero or building: "attack"; on one of ours: "defend"; Ctrl + Alt + click: danger. Your bots answer in chat, and agree or say why not |
| Enter | Type to your team (Enter sends, Esc closes). Bots understand "push top", "defend mid", "gank" or "kill <hero>", "back", "group" |
| Shift (hold) | Also shows every neutral camp's spawn box: yellow, red while something blocks it, with its size and the pull camps named |
| Tab (hold) | Scoreboard with damage tables |
| Top-bar hero tiles | Click to look at a visible hero; dead heroes show their respawn timer |
| Space (hold) | Follow your hero |
| Screen edges, arrow keys, middle-drag | Pan the camera |
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
  camps (neutral camp props, fires, spawn boxes on Shift), fx, sludge_fx (shuriken hook and chain, Stench cloud,
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
* Hold Shift: spawn boxes on the ground (yellow; red while something other than the camp's creeps blocks them) with a
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
* Difficulty follows Dota's bot levels (reaction delay, last hit error, spell lockouts; Unfair +25% gold and xp).
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

## Backlog: smallest next actions first

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
   table. Still deferred: secret shop, runes, Roshan, scan, wards UI polish.
9. More heroes (the bot plays Blood Ranger, Ezee and Sludge, mid only). Mana Boots in a bot build.
