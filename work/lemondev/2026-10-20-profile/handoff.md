# Handoff: run 2026-10-20 b (the social makeover)

State: **IMPLEMENTED — UNVERIFIED** for the blind-review and benchmark gates (no fresh-context critic, no captured
commercial reference); the measured gates below passed on the working tree.

## What changed

See `docs/HANDOFF.md` (Status, 2026-10-20 b) for the player-facing summary and every new name.

New files: `src/core/career.gd`, `src/core/profile_talk.gd`, `src/core/profile_lines.gd`, `src/sim/chat_profile.gd`,
`src/ui/social_ui.gd`, `src/ui/player_menu.gd`, `src/ui/profile_page.gd`, `tools/ui_skin_social.py` (+ 83 textures in
`assets/ui/skin`: `soc_*`, `ic_*`, `gl_*`, merged into `skin.json`).

Changed: `ranked.gd` (save version 5 and its upgrade, performance MMR in matches and ladder rounds, careers, commend /
report / block, profile walls after matches and on catch-up), `sim_unit.gd` / `sim_combat.gd` / `sim_world.gd`
(multi-kill counts, first blood, lane seconds), `sim_bot_chat.gd` (ChatProfile at the start, the review, "check my
profile"; bot lines in relations), `chat_mind.gd` (ProfileLines, profile intents), `hero_draft.gd` (profile reads in
the pick; a "chill" answer replaced), `matchmaker.gd` / `main.gd` (cards carry the profile), `forum.gd` (replies read
your profile), `llm_chat.gd` / `forum_writer.gd` (the profile in the prompts), `match_menus.gd` (your line, unranked
record, end-screen notes), `ranked_menu.gd` (ProfilePage, skin, right-click, hover card, Play-tab fixes), `forums.gd`
(skin, averages, right-click, profile overlay, blocks), `ranked_draft.gd` (right-click), `ui_skin.py` (calls the
social set), `tests/run_tests.gd` (8 tests, 2 updated), `tests/tools/ranked_probe.gd` (Edit profile, View As, wall,
right-click Compare, MVP screen).

## Evidence (this working tree)

* Headless suite: 327 passed, 0 failed (`tests.txt`), then the profile / chat / draft tests again after the last
  line changes: all pass.
* Live probe through real clicks and a real ranked match: `probe.log`, captures `probe/` (see the final count there).
* Captures inspected: `ui/profile_me2.png`, `profile_top.png`, `profile_viewas_b12.png`, `compare.png`, `menu.png`,
  `play.png`, `leaderboard.png`, `players.png`, `forums.png`, `profile_4k.png`; before: `before/`.
* `python tools/check_names.py`: Names OK.

## Open

* Your First Bloods / Triple Kills / Rampages before today were never recorded; Edit profile > Earlier record takes
  your own count.
* No critic pass, no Dota 2 profile screenshot as a benchmark.
* The Forums profile overlay and the hero-pick right-click were checked in code and by parse, not by clicks.
* Smallest next action: play one unranked and one ranked match and look at the profile, wall and end screen.
