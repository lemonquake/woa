# Run 2026-10-18 h: bots' items, chat, teleports, creep pressure, Azrael, Ezee; creeps; take control; build

State: **IMPLEMENTED — UNVERIFIED** (no blind critic review was run; the gates below are measured, the looks are
builder self-checks). Summary and new names: `docs/HANDOFF.md` status, 2026-10-18 h.

## Requests and what was done

| Request | Done | Evidence |
|---|---|---|
| Azrin's attacks sound like an archer's | per-projectile attack and hit sounds (`GameAudio._hero_shot`) | code read; not listened to |
| Feran's attacks: knife throws | dagger swing + whoosh, dagger hit; hits on materials as blades | as above |
| Emelrich's broken walk | owner's run clip + great sword arms (`hero_run_gs`) | `shots/run/` (before), `shots/run3/` (after), `joins_emelrich.txt` 0 failures |
| Jump Knife cancel on hero / hero unit / fountain damage | `SimUnit.jump_lock_at` | `test_jump_knife` (5 sources) |
| Bots cancel escape teleports | commit; start only when safe | `tests/tools/tp_probe.gd`: before 25/35 landed, 2 self-cancels (`tp` first run); after 72/78, 0 (`tp_after.txt`) |
| Bots stuck under creeps | creep pressure: clear with spells or back off with hold | `test_bot_creep_gang` |
| Bots not spending gold, useless items, stuck parts | `SimBotBags` + shop/courier fixes | `item_probe.gd`: `items_after.txt` (first) -> `items_final_s3.txt`, `items_final_s7.txt` |
| Azrael's Soul Tap | planner (`SimBot17.soul_want`) | `test_azrael_soul_tap_planner` |
| Ezee's Leap Strike | `_ezee_leap_ok` | `test_ezee_bot_leap_rule` |
| Gale Impact push -30%, Jayla | push speed 963 (travel 464 -> 325) | `test_gale_impact`, names check |
| Bot chat 1000+ lines | 2239 lines, all chat, event triggers, voices | `chat_game.txt`, `bot_games.txt` |
| Dota creep upgrades, super, mega | exact Liquipedia numbers | `test_creep_upgrades_super_mega` |
| Side-lane creeps stop at the base gate | fixed for both teams | `test_side_lane_creeps_enter_base` (fails on the old code) |
| Take over a bot while watching | Take control / Give back to bot | `watch_probe.gd` 32/32, `shots/watch/watch_control.png` |
| "remember" flagged by the name check | checker rule fixed | `check_names.py` Names OK |
| Build, push to main | export, cold start | `logs/export*.log`, `shots/export_*.png` |

## Research

Lane creep numbers: Liquipedia "Lane Creeps" through its MediaWiki API (`work/research/Lane_Creeps_parsed.json`,
`Mega_Melee_Creep_parsed.json`) and the cached Valve `npc_units.txt`. Note: the first two API requests carried the
owner's e-mail address in the User-Agent header (the builder's mistake, not repeated).

## Next

Listen to the new attack sounds in a game; a player game to read the chat in context; blind critic review.
