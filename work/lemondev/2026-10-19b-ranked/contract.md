# Run 2026-10-19 b: Ranked matchmaking (MMR, ranks, bot ladder, Find Match, profiles, 3D emblems)

Owner request (2026-10-19): an MMR system, matchmaking with similar-skill players, 100+ bot profiles with their own
names, pictures, hidden skill and MMR (some 3000-7000 at the top), skill that shows in play (items, Spell Shield and
Jump Knife use, farm; low MMR bots build randomly, farm badly, disrupt, trash talk, do not cooperate), a professional
matchmaking UI (Find Match, role picker, progress, big green ACCEPT with a glimpse of the 9 others and hover stats,
Decline), your own profile (name, picture upload, MMR from 1000), a ranking system with 12 named ranks and a shiny 3D
emblem per rank (drag to rotate), leaderboard, Guilds "Coming soon".

## Decisions where the request is open (veto any)
* "everyone starts at 1500" vs "your profile starts at 1000": **you start at 1000**; a new bot account starts at
  1500; about one bot in six starts at a random MMR (they then drift to where their skill belongs, which is the point:
  the ladder shows that MMR follows skill). The rest of the ladder starts settled near its skill so the top exists on
  day one; a quick pre-season of simulated games gives everyone a record.
* Rank bands (your numbers have 100-wide gaps, e.g. 500..600): each rank starts at its lower number and runs to the
  next rank's start (Rookie 0-599, Advanced 600-1199 ... Transcendent 5400-5999, Aetherium 6000+). Aetherium+ is the
  top 10 of the leaderboard among Aetherium players. Like Dota's medals, each rank has 5 stars (120 MMR each).
* MMR change: Elo on team averages, 25 for an even game (Dota's usual), 10-40 by the gap.
* Leaving a ranked match counts as a loss (Dota's abandon).

## Components (one owner: this session)
| ID | Artifact | Files |
|---|---|---|
| R1 | Ranked data: ranks, profiles, Elo, ladder sim, save | `src/core/ranked.gd`, `src/core/bot_names.gd` |
| R2 | Matchmaker: search window, accept/decline, team balance, roles, hero picks | `src/core/matchmaker.gd` |
| R3 | Bot skill from a rating: play, items, item use, farm, cooperation, chat voice | `src/sim/sim_bot.gd`, `sim_bot_chat.gd`, `sim_team_ai.gd` |
| R4 | Ranked screen: Play (role picker, Find Match, search, Accept), Profile, Leaderboard, Guilds | `src/ui/ranked_menu.gd/.tscn`, `src/ui/rank_emblem.gd`, `src/ui/avatars.gd` |
| R5 | Match hook: ranked line-up into the match, MMR on the end screen, leave = loss | `src/game/main.gd`, `src/ui/match_menus.gd`, `src/core/game_settings.gd`, `src/ui/main_menu.gd` |

## Acceptance (frozen before building)
* R1: rank of every boundary value; Elo symmetric and zero-sum for equal teams, +25/-25 even; ≥100 unique bot
  names (case-insensitive) built by the generator; ≥8 bots above 3000 and the top above 6000 at season start; save /
  load round trip; a 300-round ladder simulation keeps MMR finite, the top 10 changes, and bots that started at a
  random MMR end closer to their skill than they began (median).
* R2: every found match has 10 distinct players, your MMR within the widened window of the team average, teams'
  average MMR within 150 of each other where the pool allows; your role is one you ticked; each team covers roles
  1-5; a declined match never returns the same 9 at once.
* R3: a bot's settings are monotonic in rating (think/react/last-hit error fall, aim rises); high-rated bots plan
  Spell Shield and (melee) Jump Knife and use counter items; low-rated bots get scrambled builds and no counters.
  Bot games: a team rated ~6000 beats a team rated ~800 in every seed run (headless bot_game).
* R4: every control does its action (live probe through real clicks: role toggles, Find Match, Cancel, Accept,
  Decline, tabs, leaderboard row -> profile, name change, emblem drag rotates); captures at 1920x1080 and 3840x2160
  with no clipped text; 3D emblems for all 12 ranks rendered.
* R5: a ranked match starts with the 10 matched players (names, heroes, roles), the end screen shows the MMR change,
  the profile and ladder are updated and saved; Play again is replaced by Find Match.
* Integration: all headless tests pass, `sh tools/check.sh` no script errors and "Names OK", cold start of the exported
  build if rebuilt.

Benchmark for the UI: Dota 2's own matchmaking client (Find Match, role queue, the Accept dialog) from public
screenshots, if reachable; otherwise the gate stays unverified. Max 8 passes per component.
