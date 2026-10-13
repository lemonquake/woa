# Run 2026-10-13 c: camera, neutral camps, Game Setup, team bots that think, chat, pings and learn

Baseline revision: 8310428 + the uncommitted, integration-passed working tree of run 2026-10-13 b (not committed by
that session; kept as is). Engine Godot 4.7.2, Windows, 1920x1080 target (also 3840x2160). Single agent builds;
research and blind review by fresh subagents.

## Owner's request (points, paraphrased closely)
1. The camera starts centred on your hero. An option to centre the camera when the hero respawns.
2. "Where are the neutrals?" Too few camps. Camps must look like camps, instantly recognisable as neutral camps.
   Holding Shift shows the square spawn box (the area that must be empty to stack / where pulls start). Research Dota.
3. An overhauled Game Setup: set up the player and bot players on both teams. Bots may pick the same hero.
4. Very advanced bots: know their hero (combos, skill and item builds), retreat, lane (leave the player's lane to the
   player, never leave a lane empty), farm lane vs jungle (and know when), push, defend, gank, TP.
5. Pings: bots respond to the player's pings (kill a hero, push a tower), often but not always; when they refuse they
   say why in chat (TP on cooldown, too far, dead...). Bots tell the team what they intend (push, kill chances seen on
   the minimap).
6. Bots learn from experience, saved on the player's machine; an option to turn it off, on by default. Customisable
   and improvable.

## Root causes found before building
* Camera: confirmed by `tests/tools/camera_probe.gd` on the baseline: the view opened 786 px off the hero. Edge pan
  ran while the loading screen was up, and it fired with the cursor outside the window (position < 0 counts as "at
  the left edge"). No respawn centring existed.
* Neutrals: they do spawn (12 camps, 3-4 units each at 1:05, headless check) but stand in the fog, and the camp
  props are a fire pit, a log (renders as a white box) and a lantern, some on plateau stairs. Only 6 camps a side.

## Components, owners, acceptance
| Id | Component | Files | Acceptance (gate) |
|---|---|---|---|
| CAM | Camera start and respawn | camera_rig.gd, main.gd, options.gd, options_panel.gd | camera_probe: hero within 5% of the screen height of the centre at the start and after respawn with the option on; the camera stays put with it off |
| NC1 | Neutral camps (rules) | sim_map.gd, sim_ai.gd, sim_const.gd, sim_data.gd | Camp count and kinds per side as researched (`research/camps.md`); every camp on open walkable ground, not on ramps, lanes or paths; spawn boxes as rectangles; spawn blocked by any unit in the box; stacking test (pull at :53-:55 makes 2 camps); pull test (lane creeps pulled into a camp fight it) |
| NC2 | Camp look and spawn boxes | dressing.gd (+ new props from Blender), hud.gd minimap, new spawn box overlay | Each camp reads as a camp (clearing, tents or den, fire with light, banner or totem, themed by creep kind) in captures by day and night; holding Shift draws every camp's spawn box on the ground (and a box turns red while something blocks it); minimap camp marks. Blind review vs a Dota camp frame if one can be obtained, else UNVERIFIED |
| GS | Game Setup screen | new src/ui/game_setup.gd, game_settings.gd, hero_select.gd, main.gd | Two teams of five slots: You / Bot / Empty, hero (Random or a hero; duplicates allowed), bot skill, lane for you; saved to user://setup.json; the match spawns exactly what was set up (probe), player may be on either team |
| AI1 | Team brain | new sim_team_ai.gd | Tests: every lane covered at 1:00 with 3+ heroes; the bot leaves the lane the human takes and announces it; ganks and pushes called with chat; defend calls when a tower is hit; ping responses with reasons |
| AI2 | Hero bots | sim_bot.gd (rewrite), new sim_bot_kits.gd | Mode system (lane, farm lane, jungle, stack, pull, push, defend, gank, fight, retreat, heal, follow ping) with desires; hero kits know their combos, skill, talent and item builds per role; TP use; 5v5 bot games finish (an Ancient falls) within 60 min across 3 seeds; no stuck bots (a hero idle > 20 s outside base = fail) |
| AI3 | Learning | new bot_memory.gd, options | Memory file in user://bot_memory.json; option "Bots learn from games" on by default; a measurable change after N simulated games (fight model weights, danger map, build choice) and better or equal results vs a fresh memory in A/B bot games; reset button |
| CH | Chat and pings | sim_world.gd (chat/ping API), input_controller.gd, hud.gd (chat log, ping kinds, chat input) | Alt+click ground / enemy hero / enemy building / own building, Ctrl+Alt danger; pings reach the team brain; bot replies appear in a chat log; the player can type to the team (Enter) |
| G | Integration | all | tests pass (100 old + new), check.sh Names OK, input/HUD probes, camera probe, 5v5 bot games, bench at 1080p with 10 heroes (no worse than 10% below the same-session baseline with 2 heroes...) export + cold start, 4K captures of new UI |

Benchmarks:
* Camps, spawn boxes, stacking and pulling: Dota 2 rules from `research/camps.md` (sources listed there).
* Bots: Valve's bot scripting architecture and Dota role conventions from `research/bots.md`; behaviour is gated by
  measured bot games, not by a visual comparison.
* Visual blind review needs real Dota frames (camp, spawn boxes); none are on disk. Downloading one needs the owner's
  OK, so NC2 and GS visual review stay UNVERIFIED unless frames are supplied.
Budget: 8 passes per component. Learning is off in tests and duels unless a test turns it on (deterministic results).
