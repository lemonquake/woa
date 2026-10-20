# Run 2026-10-19 e: the social world (reactions, memory, live stats, pick chat, Forums, MVP)

Owner's request (2026-10-19): "ALIVE AI PLAYERS THAT REALLY REPLY TO WHAT THE PLAYER SAY IF THEY NOTICE THE PLAYER IS
TRASHTALKING ... REALLY REACT when someone (ANYONE) is owning or dying too much ... Double, Triple, Rampage (most
reactions) ... remember those and remember the player ... ACTUALLY ADD THE PLAYER if they say they wanna add the player
... praise / mock / accuse of cheating ... upper-left: the Stats of the player in real time like Creep kills (hover:
lane creeps, neutrals ...) and KDA ... very particular with someone's KDA: mock, praise, accuse of smurfing, threaten to
report ... chat during the picking phase; Alt+click a hero: tell allies you want it; Shift+click: tell allies to pick it
... a FORUMS section (LLM, also works without) where AI players have their own personality and post, troll, contribute,
remember you and each other, reply when you post; high MMR players confident and arrogant (some kind) ... an MVP after
the game with epic UI and the stats that made them MVP; supports can be MVP (heals, wards, assists, saves) ... the versus
screen shows who were MVP in their previous game and bots react and expect you to be good ... simulate the toxicity of
the MOBA community ... then build the game".

Baseline: commit 6090d3f (clean). Godot 4.7.2, Windows, 1080p target (4K checked).

## Components (one owner each; all mine, built in order)

| Id | Component | Files | Interface |
|---|---|---|---|
| S1 | Match stats | `sim_unit.gd`, `sim_combat.gd`, `sim_status.gd`, `sim_abilities.gd`, item/kit heal sites | `SimUnit.lh_lane / lh_neutral / lh_other / heal_given / disable_given / wards_placed / saves`; deterministic |
| S2 | Live stats panel | `src/ui/hud.gd` (new `StatsPanel`) | top left, your K/D/A, last hits / denies, GPM; hover: the breakdown |
| S3 | MVP | new `src/sim/match_mvp.gd`, `match_menus.gd` (MVP screen), `ranked.gd` (MVP records, ladder MVPs), `ranked_draft.gd` (versus badge) | `MatchMvp.rank(w)`; `Ranked` history `mvp`, profile `mvps` |
| S4 | Social reactions | `sim_bot_chat.gd`, new `src/sim/chat_more.gd` (lines), `chat_mind.gd` (intents) | multi-kills and streaks for anyone, feeding, KDA reviews (smurf / boosted / report / cheating), trash talk answered with facts, MVP expectations, friend asks, bots knowing each other |
| S5 | Memory and friends | `ranked.gd`, `matchmaker.gd`, `main.gd`, `match_menus.gd`, `game_settings.gd`, `sim_bot.gd` | event `friend`; `Ranked.befriend`, `send_request`, `remember_casual`, profile `fame`, `seen`; casual matches filled with ladder players |
| S6 | Pick chat | `ranked_draft.gd`, `hero_draft.gd` | type in team chat; Alt+click "I want X"; Shift+click "pick X"; bots answer and change their picks |
| S7 | Forums | new `src/core/forum.gd`, `src/core/forum_writer.gd`, `src/ui/forums.gd/.tscn`, `main_menu.gd`, `ranked_menu.gd` | threads, replies, votes; posts made while you are away; replies to your posts; LLM when on, offline writer always |

## Acceptance (frozen before results)

S1: a lane creep, a camp creep and a summon killed by a hero count in their own counters; a heal on an allied hero by
another hero counts as heal_given; a stun on an enemy hero counts its seconds; a ward placed counts; a hero that heals
or disables for a low ally that survives 4 s counts a save; two worlds stepped alike keep the same state hash.

S2: the panel shows at 1920x1080 and 3840x2160 without covering the top bar or kill feed; hovering it shows lane
creeps, neutral creeps, others, denies, CS per minute, hero damage, building damage, healing, wards.

S3: MatchMvp picks one hero with reasons from real numbers; a support with heals, wards, assists and saves can win it
(test); the MVP screen renders (capture) before the scoreboard; Ranked keeps the MVP in history and counts; ladder
rounds give MVPs to bots; the versus plate marks players whose last game was MVP.

S4 (headless tests unless noted): a double, triple, ultra and rampage draw more reactions as the count rises (rampage:
both teams, more lines than a double); a hero with many deaths gets mocked by enemies; a review with a stand-out KDA
draws smurf / report / praise lines, a terrible one mock / boosted lines; a player's "ez" in all chat gets an enemy
reply that uses real numbers (score or gold gap); "add me" to a bot that likes the player produces a friend event and a
yes, to one that does not a no; a player who was MVP last game is called out at the start, and mocked if doing badly;
chat stays deterministic (two worlds, same lines).

S5: a friend event from a match makes a friend or a request on the ladder; casual matches with Options "Bots are ladder
players" on use ladder players and remember the match; bots record notable events about each other (fame) and refer to
them when they meet.

S6: typed lines show in pick chat and bots answer; Alt+click posts "I want to play X" and teammates stop going for X;
Shift+click posts "Pick X" and one teammate whose role fits agrees and changes its pick (test on HeroDraft).

S7: the Forums page renders at 1080p and 4K; threads exist on first open made from ladder events and personas; your
post gets replies in time (offline writer) from players whose tone follows their personality and rank; a reply can be
upvoted; new posts appear after time away; with the LLM on (mock server), a post body comes from the model, else the
offline line. Insults or praise to a player in the forum change what they think of you.

Integration: all headless tests pass; `sh tools/check.sh` clean with "Names OK"; a live match with the HUD panel, the
MVP screen and chat captured; the release export cold-starts.

Benchmark: no commercial client is available here (Dota 2 is not installed); the benchmark gate stays UNVERIFIED and is
reported as such. A fresh-context critic compares old vs new chat transcripts blind (A/B).

Budget: 8 passes per component.
