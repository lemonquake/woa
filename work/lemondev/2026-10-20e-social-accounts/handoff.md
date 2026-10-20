# Run 2026-10-20 e: accounts, the pick's quick stats, pro reactions, Players and friend chat, structures, Araki, Emelrich

Owner's request (one message): hero pick hover pop-ups; bots react to a beyond-pro player (awe, go pro, rooting,
honour, Aetherium+ comparisons, trolls and haters); destroyed structures removed so they never block; open the way
at the Black Sun tier 3 by the mid stairs; Araki's ghosts hit moving targets (800 speed, a poof instead of a death);
Ser Emelrich's Giant Swing reworked (2.5 / 3.5 / 4.5 s stun, 1.8 / 1.6 / 1.4 s channel, spell immunity with a
pierce list for the owner to fill); Players tab overhaul with friend counts and friend chat; multiple accounts (fresh
1500 MMR, same ladder, log in / out, 10+), comment on your own forum posts, bots know the current players (top 20,
profiles).

## Components and evidence

| Component | Evidence | State |
|---|---|---|
| S1 Destroyed buildings free their ground | `test_destroyed_building_opens_ground` (every tower and barracks, a standing neighbour keeps its ground) | tests pass |
| S2 Mid tier 3 out of the stairs' mouth | `captures/t3_old.png` vs `t3_b.png`; the forest is byte-identical (tree hash before = after) | owner's eye |
| A1 Araki's ghosts | `test_araki_ghosts_hit_runners` (9 of 9 hit a hero running away; before: 0 of 9) | tests pass |
| E1 Giant Swing | `test_emelrich_giant_swing_guard`, `..._and_stance`, `test_bots_dodge_giant_swing`; `captures/swing_30.png`, `swing_62.png` | tests pass |
| R1 Accounts | `test_ranked_accounts` (create, 20 max, log in/out, walls and forum posts follow, bots never write as you); `captures/accounts.png`, `alt_board.png` | tests pass |
| P1 Pick quick stats | `captures/peek_me.png`, `peek_foe.png` | owner's eye |
| B1 Pro reactions | `test_profile_pro` (every manner and side gives a full line; nobody reads a pro as a feeder) | tests pass |
| B2 Ladder knowledge | `test_chat_profiles_in_match` (who is top 1, a ladder player by name), `test_profile_pro` (ladder card, names) | tests pass |
| U1 Players tab and friend chat | `captures/players_chat.png`, `players_find.png` | owner's eye |

Not done: no fresh-context critic and no Dota 2 benchmark capture (owner's-eye items above are self-checked only);
no 4K capture; no live click-through probe of the Accounts panel or friend chat (captures use flags); the export
was not rebuilt.

## Numbers chosen where the owner gave none (veto any)

* Giant Swing damage 250 / 375 / 500 (was 150 / 250 / 350). Cooldown left at the owner's 20 / 15 / 10 s and the
  "-20 s" talent: with a 4.5 s stun that is very strong; say if it should change.
* Mid tier 3 moved from (-4700, -4250) to (-4600, -4550) (mirrored for Black Sun), 225 from the lane.
* Ghost strike: on contact, then follows the target for 0.2 s and puffs. Ghosts keep their target out of sight
  (not through invisibility).
* Accounts: 20 at most, new ones at 1500 MMR.
* A pro: 30+ games and KDA 7+ with 2.5 or fewer deaths, or MVP in 35%+ of games with KDA 5+, or 5 of 5 won with KDA 8+.
* Friend chat: online friends answer in 3-8 s, in a match after 40-150 s, away 4-25 min; a friend online may write first
  once per 30 minutes.
