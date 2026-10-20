# Run 2026-10-20 b: the social makeover (Profile, Ranked, Forums, performance MMR, profile-aware players)

## Request (the owner)

"the most epic makeover ever with BIG SIGNIFICANT IMPROVEMENTS AND OVERALL POLISH in ALL the Ranked UI, Profile UI,
Forums ... Profile needs to include Player averages like LH/D, KDA, Fave lanes ... MMR gain should be based on
performance and should give around 23 up to 41 (perfect game, no deaths, 10+ assists, 10+ kills, 150 LH). AI players
should be MORE AWARE ... your last games (at least 5 ... with YOUR STATS ... THEY WILL ACKNOWLEDGE IF YOU PLAYED GOOD,
but some trolls will still troll you). AI players will REALLY CHECK each others' profiles especially the player ...
toxic as ever, but also with more kind people ... an upgraded and polished Profile UI ... actual professionally made
texture that is themed with the game ... Clean, professional UI, very very interactive like Rightclick functions all
over especially for profiles. Then build the game." Mid-run: "add to player stats: First Bloods, Triple Kills,
Rampages. also track my own record ... Also update the profiles of all AI players and give them their respective
stats, also update their MVPs record especially for the high rankers ... add 'View As' in your player profile".

## Components and acceptance

| ID | Component | Files | Acceptance (measured) |
|---|---|---|---|
| K1 | Career stats | src/core/career.gd, sim counters (sim_unit, sim_combat, sim_world), ranked.gd hooks, match_menus.gd | every finished match (ranked or not) adds a line with farm, lane, first blood, multi-kills; averages / lifetime / lanes / form correct (test_career_averages); v4 save upgrades without MMR change (test_ranked_upgrade_careers) |
| K2 | Performance MMR | Career.perf / mmr_change, Ranked.finish_match / simulate_rounds | win 23..41, perfect = 41, loss -41..-23, leave -41 (test_career_mmr_range); the nine move by their own games (test_ranked_match_result); ladder average drifts < 60 over 60 rounds (test_ladder_careers) |
| K3 | AI careers and MVPs | Career.estimate, Ranked._make_bot / _upgrade_careers | every ladder player has a career counting its games; top ten 100+ MVPs; low ranks with 100+ games have MVPs (test_ladder_careers) |
| K4 | Profile reading and talk | profile_talk.gd, profile_lines.gd, chat_profile.gd, hero_draft.gd, forum.gd, llm_chat.gd, forum_writer.gd | kind ones acknowledge good profiles and never flame bad ones, rough ones flame bad averages and call good ones smurfs (with some credit), trolls troll good profiles (test_profile_talk); a match start brings 2+ profile remarks matching the profile; "check my profile" is answered; dying far above your average is noticed (test_chat_profiles_in_match) |
| K5 | Walls, visitors, menu acts | ProfileTalk walls, Ranked.commend / report / toggle_block | after-match comments (max 4), visitors, write -> answer, commend / report once a day, block hides (test_profile_walls) |
| K6 | Profile UI, View As, Compare | src/ui/profile_page.gd | renders at 1080p with real data (captures ui/); View As hides private parts (test_profile_walls); live probe edits name / picture, View As, wall post, right-click -> Compare (ranked_probe.gd) |
| K7 | Right-click menus | src/ui/player_menu.gd + rows in ranked_menu, forums, ranked_draft, profile | a right-click on a row opens one menu; its actions work (probe) |
| K8 | Themed skin | tools/ui_skin_social.py (assets/ui/skin soc_*, ic_*, gl_*) | generated, imported, used by Ranked, Profile, Players, Forums (captures) |
| X | Integration | all | full headless suite, names check, parse check of changed scripts, Windows export builds and opens |

Benchmark: no commercial reference captured this run (Dota 2's own profile pages and OpenDota-style match lists are
the model, but no screenshot of them is in the project) — the benchmark gate is UNVERIFIED. No fresh-context critic
pass this run: acceptance is by measured gates and captures inspected by the builder.

Budget: one pass per component unless a gate fails.
