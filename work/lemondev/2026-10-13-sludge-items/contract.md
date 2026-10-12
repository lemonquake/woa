# Sludge, items and shop: component contract (run 2026-10-13-sludge-items)

Request (user, 2026-10-12): plain names and a strict naming rule; Pudge recreated 1:1 as Sludge with a spinning
shuriken hook tip; all sound 50% quieter by default; an Options menu; Dota's combination items with new names. Plan:
`C:\Users\Lemon PC\.claude\plans\lemondev-skill-md-humanize-all-naming-transient-horizon.md` (approved).
Session resumed 2026-10-13 after a usage cut-off; this contract is written at the resume, before any candidate of the
components below is reviewed.

Baseline: dd7bbcf (names), e14e66a (audio, Options), b68aecf (Sludge sim), f598fdf (Sludge body). Godot 4.7.2,
1920x1080, RTX 4060.

Components:
* S1 Sludge mechanics (sim): every number from Dota 7.41d covered by a headless test. Gate: tests pass.
* S2 Shuriken Hook visuals (src/game/sludge_fx.gd): shuriken spins on the way out, a chain of links from the fist,
  bites into the victim and drags it back; miss rings off; Stench cloud; Blubber, Chomp, Growing Gut feedback.
  Benchmark: Valve's Meat Hook ability video (https://cdn.akamai.steamstatic.com/apps/dota2/videos/dota_react/
  abilities/pudge/pudge_meat_hook.mp4, local work/benchmark/pudge/), frame 97 (chain fully out, hook at the target),
  1920x1080. Candidate: same moment (hook at the target, chain out), daytime, gameplay camera, health bars on,
  other HUD off, 1920x1080. Criterion for the critic: which image shows a hook-and-chain ability that reads more
  clearly and looks more finished at gameplay distance.
* S3 Sludge bot (sim_bot.gd): plays the kit; lands hooks; finishes 12-minute duels against both other heroes.
* I1 Item systems and the Core 20 items (sim): recipe scrolls, Dota auto-combine, alt recipes, item charges, every
  active and passive in the plan. Gate: one test per recipe path and per active/passive; old tests stay green.
* I2 Shop UI: Dota-style shop (tabs, recipe panel, sell). Gate: readable at 1920x1080 and 3840x2160; every new item
  buyable by mouse. Benchmark review only if an accessible Dota shop frame is found.
* G Integration: tests, `sh tools/check.sh` (parse + "Names OK"), bot duels (Sludge vs both, 12 min, 3 seeds),
  benchmark `--bench=50 --t=240 --autoplay` no worse than 10% below 77 fps / p95 16.67 ms, export and cold start.

Review: blind A/B, the critic sees two anonymised images only. PASS needs the candidate chosen. Budget 8 passes per
component; plateau rule (same primary defect in two consecutive valid rejections) stops the loop.
