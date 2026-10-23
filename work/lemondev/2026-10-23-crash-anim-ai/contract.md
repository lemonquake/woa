# Run 2026-10-23: new-hero crashes, hit effects, hand-made animations, bot knowledge, build

Request (owner, 2026-10-23): "deep dive and QA on why the new heroes crash when using some of their skills + total
improvement on the overall aesthetics and effects of attacks/hits. Replace Run animations of Dracoxinia and make it by
yourself, make sure it's a perfect run animation, as well as her Idle animations and attack animations, no clipping no
weird twists. Also do this for the melee heroes who have identical animations to Ezee. ... Then add more context to the
AI player's thoughts/logic, making them have vast knowledge about the heroes and mechanics of the game, not just blabber
random stuff that make no sense like mentioning an item not even worth mentioning. Then build the game"

Baseline revision: `15e38a2` (clean tree).

## Components

| Id | Component | Gate (fixed before the work) |
|---|---|---|
| C | Skill crashes | every new hero's skills spammed in live windowed matches (`--storm`, 3-4 min each): 0 SCRIPT ERROR, no STALL, "storm done"; the same in the exported (release) build; each fault found gets a test that fails without the fix |
| F | Hit and attack effects | no opaque or flat-shaded hit shapes; melee blows show a weapon-coloured cut, flare and sparks, crits more; captures by eye; no new script errors in the storms |
| A1 | Dracoxinia's own idle, run, attacks (and the moves that join them) | hand-made (no Mixamo); `body_collide.gd --applied` 0 cm; `anim_joins.gd` slide check passes (planted foot), no new join failures; `anim_audit.gd` (wrist 75 deg, forearm twist 95, elbow 125, pops 45 deg/frame) clean or each overage listed |
| A2 | Melee heroes with Ezee's clips | which heroes use Ezee's great sword pack (by source file), each given its own clips under the A1 gates, or a reason |
| B | Bot knowledge | rule lines and the online writer never name parts, starters or consumables; bots warn about enemy heroes and call real counters; prompt built and checked offline (no key read, nothing sent) |
| X | Integration | full suite 0 failed; `sh tools/check.sh` Names OK; release export exit 0; the exe cold-starts into a match; a storm in the exe |

Budget: at most 8 build/review passes per component (lemondev default).

## Benchmarks

* Animation: no commercial capture (gate UNVERIFIED); the project's own measuring tools are the gates above.
* Frame time: teamfight bench A and B from run 2026-10-22 c (`work/lemondev/2026-10-22c-qa-perf/contract.md`), to check
  the new effects cost nothing visible.
