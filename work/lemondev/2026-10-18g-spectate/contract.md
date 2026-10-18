# Run 2026-10-18 g: rates, All-Bot watching, camera, Debug Bots (contract)

Request (owner): "make the default EXP gained by players 50% higher, gold 50% higher. Allow the player to have an
All-Bot match and he can just sit back and watch, with all the spectator options available like Follow player, player
perspective (can see the AI's orders), team vision (team 1 or 2, or all), etc. Also the default camera view for the
player should be higher a bit. In the Debug options, add AI commands like Add Gold to specific AI or team or all AI,
level up specific or team or all, etc. then build the game." Baseline revision: `37130bf` plus the uncommitted 18 f work.

## Components

| id | Component | Files | Acceptance |
|---|---|---|---|
| R1 | 150% experience and gold | `sim_const.gd`, `sim_world.gd`, `sim_combat.gd`, `sim_debug.gd`, `game_settings.gd`, `game_setup.gd`, tests | earned XP and gold x1.5 by default; starting gold and Debug gifts unscaled; Dota's numbers still pass at 1.0; Game Setup rate pickers |
| S1 | All-Bot match | `game_settings.gd`, `game_setup.gd`, `main.gd`, `match_menus.gd`, `screen_fx.gd` | Game Setup allows no You slot (Watch bots preset); every hero a bot's; watcher commands refused |
| S2 | Spectator view | `main.gd`, `src/ui/watch_panel.gd`, `hud.gd`, fx/view files reading sight, `sim_bot.gd` (plan_text, read only) | hero pick, Free / Follow hero / Hero view / Auto camera, sight per team / both / whole map, order waypoints, plan lines, speed and pause |
| C1 | Higher camera | `camera_rig.gd` | default distance raised ~15% |
| D1 | Debug Bots | `debug_panel.gd`, `sim_debug.gd` | every bot / a team's bots / one bot: gold, level, refresh, respawn, kill, teleport, items, skill, stand still |
| X1 | Integration | tests, `tools/check.sh`, `watch_probe.gd`, export | all tests pass; Names OK; probe passes; release export cold starts |

Benchmark: Dota 2's spectator options (Free, Hero Chase, Directed camera; vision per team or both; "Player
perspective" showing the player's orders) as the reference for what is offered; no Dota capture compared (none
available here). Budget: 8 passes per component. No blind critic review was asked for.
