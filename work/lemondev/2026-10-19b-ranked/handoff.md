# Run 2026-10-19 b: Ranked matchmaking — handoff

Status: **IMPLEMENTED — UNVERIFIED** against a commercial benchmark (no Dota 2 client screenshots were available to
compare against); every other gate below passed on the final working tree.

## What was built
* **Ranked data** (`src/core/ranked.gd`, `src/core/bot_names.gd`, saved in `user://ranked.json`): you start at 1000;
  160 bot profiles (skill bands up to 7300; 12 good enough for Aetherium) with generated unique names (the owner's five
  examples kept), favourite heroes and roles, pictures, behaviour score, cooperation, lane grabbing, toxicity,
  ragebaiters, a chat voice. New accounts start at 1500, about one bot in seven at a random MMR; the rest start near
  their skill. Elo on team averages, K 50 (+25/-25 even, clamped 5-45). The ladder plays itself: a round of bot matches
  every 3 minutes away (30 at most), and 3 after each of your matches. 12 ranks, 5 stars each below Aetherium;
  Aetherium+ = top 10 of the leaderboard in Aetherium. Leaving a ranked match (Leave match, Quit, closing the game or a
  crash) is a loss and -400 behaviour.
* **Matchmaker** (`src/core/matchmaker.gd`): role queue; window 100 MMR + 45/s; 9 from the 14 nearest; the split of
  C(9,4) with the closest averages and fewest players off role; your role from those you ticked; bots pick heroes for
  their role from their favourites (low, selfish bots sometimes anything); 15 s to accept; low behaviour bots are slower
  and sometimes fail (back in the queue); Decline keeps those nine out of your next 2 offers.
* **Bot skill in play** (`src/sim/sim_bot.gd` `RATED`, `set_rating`): reaction, last-hit error, aim, spell lockouts,
  stacking/pulling/wards/counter items from 1800, item sense (scrambled builds below 0.35; Spell Shield for cores, Jump
  Knife for melee, Fade Cape and Push Staff for supports from 0.8), item use chance, farming (jungle, wandering);
  selfish bots refuse team calls ("kayo na lang"), grab lanes ("mid or feed", `sim_team_ai.gd`), ragebaiters barely
  retreat; chat voice from the profile (`sim_bot_chat.gd`). No gold bonus.
* **UI**: main menu "Ranked" plate; `src/ui/ranked_menu.gd/.tscn` (Play, Profile, Leaderboard, Guilds coming soon,
  match offer, hero picker), `rank_emblem.gd` + `rank_metal.gdshader` (12 procedural 3D emblems, glint sweep,
  icons baked to images), `emblem_view.gd` (drag to turn, inertia, sway), `avatar.gd` (hero portrait, uploaded picture
  `user://ranked_avatar.png`, funny face generator, silhouette), `ranked_num.gd`. End screen shows the MMR change and
  rank up/down; Find Match / Main Menu replace Play again.

## Evidence (final working tree)
* Headless tests: `godot --headless --path . -s tests/run_tests.gd` -> see `logs/tests_final.txt` (288 with 9 new
  ranked tests: tiers, Elo, names, ladder, match result and abandon, lineup x6, search/decline/accept, rated
  settings, rated builds). Ladder test: random starters' median distance to their skill fell 1648-2038 -> 307-399 MMR
  over 300 rounds.
* Live probe through real clicks, a real ranked match end to end: `godot --path . -s tests/tools/ranked_probe.gd --
  --out=work/lemondev/2026-10-19b-ranked/probe` -> `logs/ranked_probe_final.txt` (38 checks).
* Bot games (`tests/tools/bot_game.gd --rating= --rating_b=`): 6200 vs 700, seeds 3,7: the 6200 team won both (77-13,
  65-14 kills; net worth 122k vs 63k, 118k vs 70k), every 6200 bot built Spell Shield, melee ones a Jump Knife
  (`logs/skill_6200_vs_700.txt`). 2600 vs 1600, seeds 11,13: no winner by 40:00, the 2600 team ahead in both (kills
  51-37, 33-20; net worth +53%, +28%) (`logs/skill_2600_vs_1600.txt`).
* Captures: `final/` at 1920x1080 and 3840x2160 (play, search, found + hover cards, ready, profile, bot profile,
  leaderboard, guilds, hero picker), `final/emblems_2.png`, `emblems_3.png`; main menu `shots/menu_after.png`.
* `sh tools/check.sh` -> `logs/check.txt` (no script errors expected, "Names OK").

## Review
One fresh-context critic (packet: the `final/` captures only, no source) — not a blind A/B (no benchmark). Its largest
defect: the hover card covered ACCEPT. Fixed (the card stays in its team's column); recheck at 1080p and 4K
(`final/recheck_sheet.png`, `final/hover9_4k.png`) passes. Its other notes also fixed: Guilds text overflow, Hero and
Transcendent emblems less grand than Mythic (Mythic is a spiked shield now; Hero and Transcendent gained rays, laurels,
bigger framing), "1 wins", a half-cut leaderboard row, background showing through the offer. Not changed: the "0/0/0,
0:00" history row (the probe forced a win at 0:00, real games fill it).

## Not verified / limits
* No comparison with Dota 2's real client (benchmark gate UNVERIFIED).
* MMR calibration of bot skill against human players is a guess (RATED anchors); how fast a real player climbs is
  untested. Bot games show the gradient, not exact MMR equivalence.
* Picture upload uses the native file dialog; only the import function was exercised (not a real dialog pick).
* No release export was rebuilt in this run.

## Additions after your corrections (same run)
* No hero before matchmaking: the Play tab shows your rank and your heroes; heroes are picked after everyone accepts.
* Hero Pick (`src/ui/ranked_draft.gd`, `src/core/hero_draft.gd`): random numbered turns, bot wants and changes of mind
  in team chat, reactions to your Gold+ heroes, enemy snipes, 30 s for you.
* 3D versus (`src/ui/versus_stage.gd`, `HeroStage.make_hero`): ten heroes on a lit field facing each other, name, rank
  and hero medal over each, VS slam; heroes placed as picked.
* Hero mastery (Ranked: `hero_xp_gain`, `hero_medal`, `hero_board`, `top_heroes`; `HeroBadge`): XP from result and
  performance, 5 stars a medal, Bronze to Diamond, Top 5 .. Top 1 Players; bots' records scaled to their play; countries.
* Evidence: tests 291 passed (`logs/tests_final3.txt`); live probe 45/45 (`logs/ranked_probe4.txt`, captures
  `probe4/`); `logs/check2.txt` no script errors, Names OK; captures `final2/` (versus 1080p and 4K, pick 4K, hero
  ranking, bot profile with Top 1 medals) and `draft/`.
* Not verified: versus frame rate on weaker GPUs; balance of the mastery curve over many real games.

## Release build
`godot --headless --path . --export-release "Windows Desktop" build/WarriorsOfAether.exe` (exit 0, 2026-10-19 05:47,
`logs/export.txt`). Cold start `build/WarriorsOfAether.exe -- --match --capture=... --t=20`: no script errors
(`export/match.png`). Ranked screens from the exported pack: `export/pck_ranked.png`, `export/pck_versus.png`.
