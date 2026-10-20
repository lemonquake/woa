# Generated skill and item icons

User outcome: inspect every live skill and item icon, generate original painted raster artwork with the built-in image generation tool, integrate it throughout the game and export Windows Desktop.

Baseline: 6090d3f7b85c2e9acd2f61d0d520949b10e897c7 plus the owner's existing working changes (preserved). Godot 4.7.2 Forward+, Windows, RTX 4060 project target, 1920x1080 and 3840x2160. No mechanics or names change.

Components: skill sheets (grouped by hero, extra/innate/neutral included); item sheets (ordered inventory, item levels and Switch Boots states included, shared recipe); UiKit routing and import; runtime and Windows export. Each sheet at most 16 cells, exact fixed grid, no text inside artwork. Source sheets retained here; final 256px PNG icons in assets/ui/art/{skills,items}. Existing SVG assets remain recoverable fallbacks. All item/skill identity comes from current SimData and implementation, not outside game balance.

Mandatory invariants: every live hero/neutral ability and purchasable item has a resolvable generated image; no wrong cell mapping; no text baked into icons; distinctive silhouettes and effect colors readable at 44 and 64 pixels; recipe and held variants resolve; imports and packed resources load. New display names: none. Source sheet extraction (crop and resize) is authorized asset packaging, not replacement of image generation.

Benchmark: official Dota 2 hero ability presentation https://www.dota2.com/hero/drowranger and official HUD https://www.dota2.com/700/hud/ . Commercial art is reference only, never included as game artwork. Capture accessible reference when possible. Freeze criterion: large readable subject, clear action/object identity, painted materials/light, cohesive style at gameplay sizes. A missing comparable reference leaves commercial gate unverified.

Checks: exhaustive live-data coverage probe; relevant GDScript parse checks and full gameplay regression suite; actual runtime gallery, match HUD and shop at 1080p and 4K; cold export launch and packed gallery; names checker. Performance target unchanged sustained 60 Hz; measure actual icon-heavy runtime where feasible, do not infer frame rate from simulation.

Review: fresh-context independent critic receives only anonymous raw image packet and neutral mechanic requirements. Isolation instruction-enforced on shared filesystem. Eight passes maximum per sheet, repeated primary rejection twice stops that component. No numeric subjective scores. Record all results in ledger.

Override: generated raster art explicitly requested by owner supersedes lemondev procedural-texture default. Built-in generation only; no paid CLI/API fallback. No user time/cost ceiling supplied. Source generation proceeds in bounded sheets; no external dependency installation needed.

Owner decision after review (20 October 2026): keep the existing Death Order icon. Two valid reviews rejected the same low-health cue at 32px, triggering the plateau breaker. This icon is exempt from the new-art criterion by explicit owner choice; its original SVG is retained and the generated candidate quarantined outside the pack. The three other revised subjects passed the focused tiny-size review. Final runtime coverage is 226 new PNGs plus the retained Death Order SVG, not 227 new active PNGs.

Commercial gate remains UNVERIFIED: the official page was inspected/captured, but its different subjects/framing do not support a matched commercial A/B. Baseline improvement reviews are genuine separate-context reviews, not commercial acceptance. The 60 FPS target is unmet in the measured heavy-fight workload; report the actual numbers and do not claim overall VERIFIED.
