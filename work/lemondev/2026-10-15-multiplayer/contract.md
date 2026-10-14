# Run 2026-10-15: multiplayer (servers, lobbies, main server), HUD level pips, owner's bug reports

Baseline: a38afe7 plus the uncommitted 2026-10-14 and 2026-10-14 b work. Engine Godot 4.7.2 Forward+, Windows 10,
RTX 4060, target 1920x1080 (also 3840x2160). Budget: 8 build/review passes per component (lemondev default).

## Owner's requests (2026-10-14/15, this session)

1. Continue the multiplayer polish: solid, very convenient multiplayer UI with custom servers and lobbies plus a main
   lobby / main server; strict on UI design and function, epic and in the game's theme.
2. HUD: the ability level circles under Q W E R are obstructed and badly placed (screenshot).
3. Bug: a giant T-posed model and stacked health bars in the river (screenshot); the owner then found that neutrals
   "spawned at the centre of the map".
4. Neutrals aggro at most 125; lane creeps do not attack neutrals sitting in their camp, only aggro'd ones (an aggro
   state lasting at least 5 s); move the ogre camp by the bottom tier 2 tower away from the lane.
5. Holding Alt shows the neutral camps' spawn boxes (units in a box block its spawn; couriers do not).

## Components

| ID | Component | Files | Acceptance gate |
|---|---|---|---|
| B1 | Units drawn at the map centre (owner's bug) | unit_view, main | `tests/tools/view_place_probe.gd`: 5 v 5, camera over the river, 6 game min, 0 views away from their unit |
| B2 | Neutral aggro 125, lane creeps vs neutrals, camp positions, Alt boxes | sim_ai, sim_const, sim_unit, sim_map, camps | tests (calm camp ignored, aggressive one attacked, 5 s window, 125 wake), camp_layout 0 problems, team_probe Alt boxes, 5 v 5 bot game no script errors and creeps on every lane |
| H1 | HUD level pips, item and Teleport key tags | hud, tools/ui_skin.py (console art) | captures at 1080p and real 4K: pips in their own tray, nothing crosses them, key labels not clipped |
| N2 | Network: server with rooms (dedicated or hosted in game), relay lockstep, hash checks with snapshot repair from a good peer, rejoin, LAN and internet server queries, saved servers, main server entry | src/net/* | two-process (dedicated server + 2 clients) and listen-server headless tests: 0 unrepaired desyncs, a forced desync repaired, rejoin works; command latency on localhost <= 2 ticks + RTT |
| U4 | Multiplayer screens: server browser, host server, direct connect, server lobby (rooms, players, chat), room (teams, heroes, ready, leader controls, chat), connection states, in-match multiplayer menu and end screen | src/ui/net_*.gd | live two-window probe drives every control through real clicks; captures at 1080p and real 4K with no clipped or overlapping text; independent critic review of the captures |
| G | Integration | all | tests, check.sh Names OK, probes, export + cold start of the exported build as a dedicated server and as a client |

Benchmark for U4: the Dota 2 frames in `work/benchmark/` (menu frames 7-8) as the style bar; no Dota lobby frames are
on disk, so lobby layout follows Dota's custom-game lobby from memory (two team columns, slots with hero and ready
state, chat below, leader controls) and the blind A/B against a real lobby frame stays UNVERIFIED.
