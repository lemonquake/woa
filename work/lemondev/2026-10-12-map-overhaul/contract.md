# Map overhaul: component contract (run 2026-10-12-map-overhaul)

Request (user, 2026-10-12): "Total overhaul of the map. Add some elevated grounds and ramps, more and more details ...
both teams' bases should have more details like trees and objects and stuff and mountains ... I don't want a flat map."

Baseline: bbae1d3 / 0612ce9. Engine Godot 4.7.2 Forward+, target 1920x1080 on RTX 4060.
Baseline captures: work/shots/map0/base.png (flat empty base, grey void past the map edge), map0/jungle.png.

Benchmarks (local, Dota 2 frames used in earlier runs; work/benchmark/):
* dota_2.jpg: a ramp built as stone stairs between cliffs, torches on posts, props around a side shop.
* dota_3.jpg: the Radiant base: paved stone paths, an emblem plaza, a cliff edge with a stone wall and banners,
  flowering trees, a building with props.
Comparison: candidate captures at the same gameplay camera pitch (55 deg), default zoom, 1920x1080, HUD on.

Components (one owner each, Orchestrator = this session; builders = this session; critics = fresh subagents):
* M1 Elevation and ramps (src/sim/sim_map.gd levels, src/game/terrain_builder.gd, ramp dressing): jungle plateaus
  on high ground, reached by ramps where walkways cross their edges; ramps dressed as stone stairs with torches.
  Gates: lanes walkable, every camp reachable from both fountains, map symmetric, existing tests pass, bots still
  play 12-min duels.
* M2 Mountains (terrain_builder, sim_map): no void past the map edge; a ring of rocky mountains frames the map and
  rises behind both bases; mountain cells are unwalkable and block sight.
* M3 Base detail (dressing.gd + new base dressing): walls with banners on base cliffs, paved roads between base
  buildings, emblem plazas, braziers, statues, gardens and trees inside the base; Dusk variant (dark stone, red fire,
  dead trees, bones).
* M4 Integration: tests, bot duel, benchmark (1080p, --bench=50 --t=240 --autoplay, HUD on: average fps and
  p95 frame time must not regress by more than 10% against 76 fps / p95 16.67 ms), export build cold start.

Review: blind A/B, critic sees two anonymised images only; PASS needs the candidate chosen as at least as good as
the benchmark on the stated criterion. Budget: 8 passes per component, plateau rule applies.
