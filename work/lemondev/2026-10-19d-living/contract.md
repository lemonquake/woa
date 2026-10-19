# Run 2026-10-19 d: living players (bot personalities, event-aware chat, a living ladder, optional LLM)

Owner's request: "REALLY LIVEN UP THE AI WORLD ... AI feel like real people ... expand their chat knowledge ... make sure
they really know what they are playing, the gameplay, mechanics, their hero ... missed shots, kills, revenge ... come up
with our own AI system for now ... insights on costs, disadvantages, advantages [of an LLM] ... feel like you are playing
online with tons of players, each with their own personalities and uniqueness and profiles that are also updating through
time since they are simulating playing some games and you also play with them through Matchmaking ... build the game".

Baseline: working tree after run 2026-10-19 c (commit d70a22b plus uncommitted Araki work). Godot 4.7.2, Windows, 1080p
target (4K checked).

## Components (one owner each; all mine, built in order)

| Id | Component | Files | Interface |
|---|---|---|---|
| P1 | Persona and living ladder | new `src/core/persona.gd`; `src/core/ranked.gd` | `Persona.make`, `presence`, `labels`, `status`; ranked profiles gain `persona`, `mood`, `status`, `learning`, `friends`, `met`, history K/D/A; `data.feed`; old ladders upgraded in place (never wiped) |
| P2 | Match memory | `ranked.gd`, `matchmaker.gd`, `match_menus.gd`, `main.gd` | `Ranked.finish_match(extra.rel)`; bots remember you (with / against, results, flames, kills); slots carry `persona` and `met` to the bot |
| P3 | Chat brain | `src/sim/sim_bot_chat.gd`, new `src/sim/chat_mind.gd` (templates, knowledge), new `src/sim/chat_style.gd` (typing) | same `SimBotChat` entry points; deterministic from the world's seed (multiplayer safe) |
| P4 | Players screen | `src/ui/ranked_menu.gd` | new tab Players (friends, recent players, activity, online now); profile shows personality, status, online state, record with you |
| P5 | Optional LLM writer | new `src/core/llm_chat.gd`, `main.gd`, `chat_panel.gd`, `docs/LLM_CHAT.md` | off unless a key is set; display-only rewrite of a bot line already chosen by P3; local line shown if no answer in time |

## Acceptance (frozen before results)

P1
* Every bot has a persona with traits, typing style, schedule, labels; the same seed gives the same persona.
* A ladder file from run 2026-10-19 b (version 4) loads, keeps every MMR, record and your profile, and gains personas.
* After simulated rounds: moods and statuses change, some bots pick up a new hero, history entries carry K/D/A and
  length, the activity feed gains entries (rank changes, streaks, medals, new heroes).
* Presence: at any hour some bots are online, some in a match, some offline (with last seen); matchmaking only offers
  online players and still finds a match at every hour (widening as before).

P2
* After a ranked match each of the nine remembers it (with or against you, won or lost, your K/D/A against them, who
  flamed whom); your profile lists them under recent players; a bot that liked the game can send a friend request.
* In the next match with them the greeting or a later line refers to the earlier one.

P3 (each by a headless test unless noted)
* Revenge: a hero that kills the hero that last killed it can say a revenge line naming it; the victim can answer.
* Rivalry: a third kill on the same enemy is called out with the count.
* Kill steal: a kill where another ally did most of the damage can draw "ks"-type lines from that ally.
* Missed skillshot: the dodger (or its team) names the caster's ability; the caster's own team may mock it.
* Knowledge: level 6 / ultimate ready, a finished big item by name, an enemy ultimate used ("{hero} used {skill}"),
  a missing enemy laner, net worth leads or deficits by amount, multi-kills, 1 HP escapes.
* Conversation: lines typed by the player get answers that fit what was asked (rank, where from, where is a hero, what
  item, why no help, greetings, thanks, apologies, insults, gg) and refer to real numbers (the player's K/D/A, the bot's
  rank, the hero's last seen lane).
* Threads: bot-to-bot flame gets a reply that fits the persona (sorry / argue / "stop fighting").
* Tilt: a bot that keeps dying talks differently (caps, blame or giving up; kind ones encourage).
* Typing: each persona writes in its own way (lowercase, laughs, stretched letters, typos, pet words); same seed, same
  text (two worlds stepped alike produce identical chat).
* Chat stays readable: all chat at most one line per 1.5 s; no bot line repeated within the match window.

P4
* Players tab and the new profile parts render at 1920x1080 and 3840x2160 with no clipped text; friend requests can be
  accepted and ignored by real clicks.

P5
* With no key: nothing is sent, nothing changes. With a key (tested against a local mock server): one request per
  rewritten line, model `claude-haiku-5-5`, cached system prompt, the reply shown in chat; a slow or failed answer shows
  the local line; a per-match call cap holds. The key is never written to the repo or the export.
* `docs/LLM_CHAT.md`: costs per line, per match, per month at stated assumptions; advantages, disadvantages, setup.

Integration
* `godot --headless --path . -s tests/run_tests.gd` all pass; `sh tools/check.sh` no script errors and "Names OK".
* A live match (window) shows the new chat in the HUD (capture); two 5v5 bot games' chat transcripts saved.
* Release export rebuilt and cold-started.

## Benchmark

No accessible commercial reference for bot chat; real-player chat evidence is the 2026-10-19 chat run's research (SEA
Dota 2 all-chat studies, `work/lemondev/2026-10-19-chat/research.md`), which cannot be copied in bulk. Comparison used:
a blind A/B by a fresh critic of a baseline transcript (current system) and a candidate transcript (new system) from
the same seeds, asked which reads more like real players reacting to the game. The commercial benchmark gate stays
UNVERIFIED.

## Budget

At most 8 build/review passes per component; stop on a repeated primary gap. Names: `lemondev/references/naming.md`.
