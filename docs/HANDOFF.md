# Warriors of Aether: handoff

*A Dota 2-style lane battle game by Aljay Leodones. Godot 4.7.2 (Forward+), Blender 5.2 for building models.*

## Status (keep this section current)

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
| T | Town Portal: target a point or the minimap; the hero teleports beside the nearest allied building after a 3 s channel |
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

## Names added 2026-10-15 b (veto any you dislike)

* Heroes: **Tock**, title the Clockmaker; skills Time Bolt, Fast Forward, Rewind, Slow Field, Quick Hands, Stop Time.
  **Kragg**, title the Magnet Knight; skills Iron Grip, Repel, Magnetize, Overload, Magnet Field; Charges. Talents:
  "+70 Time Bolt damage", "+2 Mana Regen", "+15% Slow Field slow", "+30% Fast Forward speed", "-6s Rewind cooldown",
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
