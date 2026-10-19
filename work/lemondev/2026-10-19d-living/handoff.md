# Run 2026-10-19 d: living players: handoff

Revision: working tree on top of d70a22b (uncommitted, with run 2026-10-19 c's Araki work). Godot 4.7.2, Windows 10,
RTX 4060. Contract: `contract.md`.

## State per component

| Id | Component | Passes | Gate evidence | State |
|---|---|---|---|---|
| P1 | Persona, living ladder | 2 | test_persona_basics, test_ranked_living_upgrade (an old 160-bot file keeps MMR, records, names; grows to 300), test_ranked_living_rounds (feed kinds, 20+ statuses, moods, K/D/A lines, heroes kept), test_matchmaker_presence; Players screen captures | PASS (gates) |
| P2 | Match memory, friends | 1 | test_ranked_match_memory; ranked_probe 45/45 through real clicks and a real ranked match: 18 bots remember you afterwards (one teammate at rep -0.56 after you left the second match) | PASS (gates) |
| P3 | Chat brain, typing, team calls | 4 | test_chat_* (revenge, rivals, kill steal, skills, ultimates, answers, threads, typing, same chat on two machines); talk_probe 6/6 in a live window; blind A/B by a fresh critic: candidate won with a clear advantage; recheck of its largest gap measured by `recheck.py` | PASS (blind A/B vs the previous system); recheck: see below |
| P4 | Players tab, profiles | 2 | captures 1080p and 4K (`ui/`), hover card; Accept / Ignore / Add friend wired (living_ladder.gd + probe ladder) | IMPLEMENTED; no blind review of the screens |
| P5 | Online writer (OpenRouter, DeepSeek V4.1 Flash default; Anthropic API too) | 3 | llm_probe 17/17 against `tools/llm_mock.py` (request shapes for both services, answers used, cap, slow and failed answers fall back, cost from OpenRouter's report) | IMPLEMENTED, UNVERIFIED against the real services (the owner's key was not used by the agent) |
| X | Integration | 1 | full suite, check.sh, names, export | see docs/HANDOFF.md |

## Blind review

Packet `review/log_A.txt`, `review/log_B.txt` (seed 7, first 14 minutes; the old system and pass 1 of the new),
mapping in `review/mapping_private.json` (A = candidate). Brief: which reads more like real human players chatting in
an online ranked match, reacting to the game. Critic (fresh context, instruction-enforced isolation, read only the two
files): winner A, clear advantage; mandatory constraints pass for both. Largest gap in the winner: lines echoed word
for word by different players, filler words after end punctuation, one player repeating a call. Critic also flagged
the owner's example bot name "BISAKOL SLAYER" ("bisakol" is a derogatory term for Visayans and Bicolanos); owner names
are never changed by an agent, so this is left to the owner, and BotNames.FIL still contains "bisakol".

Recheck condition (14 minutes): no line of 3+ words from two players; no filler after end punctuation; no player sends
the same line 3+ times. `python work/lemondev/2026-10-19d-living/recheck.py <transcript> 14`:

| Transcript | echoes | filler after punctuation | a player 3+ times |
|---|---|---|---|
| baseline (old system), seed 7 | 24 | 0 | 13 |
| pass 1 (reviewed), seed 7 | 4 | 6 | 1 |
| pass 2, seeds 3 / 7 | 2 / 5 | 0 / 0 | 0 / 0 |
| pass 3 (match-wide no-echo rule), seeds 3 / 7 | 1 / 1 | 0 / 0 | 0 / 0 |
| pass 4 (the rule on hero lines and refusals too), seeds 3 / 7 | 0 / 0 | 0 / 0 | 0 / 0 (RECHECK PASS) |

## Not verified

* The real OpenRouter / DeepSeek output: no real call was made. Quality of DeepSeek's Taglish and persona voice unknown.
* How the chat feels to the owner in a long real match (bots against bots and two short live sessions only).
* The Players screen against a commercial client (no benchmark); the 4K check is one capture.
* Balance of the new ladder dynamics over weeks of real time (simulated rounds only).

## Smallest next actions

1. Owner: put the OpenRouter key in `llm.json` (docs/LLM_CHAT.md), play a match with Online bot chat on, read the log's
   cost line; veto names.
2. Decide on "bisakol" in bot names.
3. Party queue with friends (they appear online but cannot be invited yet).
