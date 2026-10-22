# Run 2026-10-22 c: leftovers, deep QA, performance, build

Request (owner, 2026-10-22): "let's continue. there might be some stuff that were not finished. then do a deep QA on
mechanics from UI, heroes, gameplay, etc and a QA for performance and how we can achieve blazing fast buttery smooth
FPS without much compromise then do it to the very best of your abilities. then build the game"

Baseline revision: `6cf1045` (clean tree).

## Components

| Id | Component | Owner | Gate |
|---|---|---|---|
| L | Leftovers from earlier runs | root | each item done or written down as blocked |
| Q1 | Hero kits QA | auditor (fresh context) -> root fixes | every confirmed finding fixed with a test, or listed |
| Q2 | Core rules QA (combat, orders, status, items, shop, AI) | auditor -> root | same |
| Q3 | Interface and controls QA | auditor -> root | same |
| Q4 | Runtime errors in real games | root | 0 SCRIPT ERROR lines in headless bot games with all 22 heroes |
| P | Frame rate | root | see below |
| X | Integration | root | full suite 0 failed, `sh tools/check.sh` Names OK, export exit 0, exe cold start into a match |

Budget: at most 8 build/review passes per component (lemondev default).

## Performance measurement conditions (fixed before the first run)

* PC: RTX 4060, Windows 10, Godot 4.7.2 Forward+ (Vulkan), 1920x1080 window, V-Sync off, no frame cap, quality High
  (project settings: 4x MSAA + FXAA, SSAO, glow, 4096 shadow atlas, two cascades).
* Teamfight bench A (comparable with earlier runs):
  `main.tscn -- --bench=40 --t=600 --fight --autoplay --lineup=ezee,azrin,froster,sludge,tock,blood_ranger,caziel,kragg,azrin,froster`
* Teamfight bench B (the newest heroes, heaviest effects):
  `--lineup=blackfire,thyrandael,gancho,kaileh,dracoxinia,araki,azrael,azrin,froster,sludge`, same flags.
* Lane bench: `main.tscn -- --bench=40 --t=240 --autoplay --bots=5v5 --nolearn`.
* Each bench run at least twice, alternating, because this PC's run-to-run spread is wide.
* Numbers read: average, p50, p95, p99, max frame time, frames over 16.7 ms, per-part means printed by the bench.

Targets: lane bench p99 under 16.7 ms; teamfight average under 16.7 ms (60 fps) with p95 as low as reachable; no
visible quality loss on High (any change in look must be optional or invisible in a side-by-side capture).
A 30 Hz simulation alone is not evidence of 60 FPS; only the frame numbers above count.
