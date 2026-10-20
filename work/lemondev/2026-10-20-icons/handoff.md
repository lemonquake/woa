# Generated skill and item icons

Status: IMPLEMENTED — UNVERIFIED for the full lemondev commercial/performance standard. The requested icon inventory, image generation, integration and Windows build are implemented. The owner explicitly retained Death Order's existing icon.

## Result

17 playable heroes, all 79 ability definitions, neutral passives/auras and visible unit traits were inspected. All 176 item database records (129 non-recipe items, 47 recipes), three Switch Boots attributes and full/empty Flask states are covered. Built-in image generation made 227 unique images; 226 are active PNGs (92 skills/traits, 134 item/state images) at 256px. All recipes use one scroll image. The original Death Order SVG remains active by owner choice; its generated candidate is in `quarantine/`.

Art is in `assets/ui/art/`. Original sheets and their prompts/cell assignments are in `sheets/` and `plan.json`; `manifest.json` records source/output hashes. Rebuild the packaged PNGs with `python tools/icon_art.py`; check them with `python tools/icon_art.py --check`. Original SVG fallbacks are preserved. Credits updated. No mechanics numbers or existing display names changed.

UiKit, HUD unit skills and BuffBar now share identity-specific lookup. Item state art includes recipes, empty Flask and the three boot attributes. A regression exposed a snapshot transient-field collision: `prof` now excludes only world timing counters, preserving ChatProfile ownership and state.

## Launch

Run `A:/Python/woa/build/WarriorsOfAether.exe`; keep its matching `.pck` beside it. Source: open `project.godot` in Godot 4.7.2. Re-export with `--headless --path A:/Python/woa --export-release "Windows Desktop" build/WarriorsOfAether.exe` using the documented Godot executable. The previous executable/pack are recoverable under `previous_build/`.

## Evidence

* Full regression suite: 327 passed, 0 failed (`tests.log`). This first run exposed the old ChatProfile nil-world error in snapshot restore. After the scoped fix, the existing three-minute every-tick snapshot determinism test and new restored-reference/state assertions passed (`snapshot_tests.txt`); profile-talk and match-profile tests passed too. No post-fix script errors.
* Runtime icon probe: 1,806 checks across 93 skills/traits and 134 item states, including distinct art, held states, recipes, legacy aliases, buff bar and unit-panel routes. Final logs: `accepted_gallery_1080.log`, `accepted_gallery_4k.log`, `packed_final_probe.log`. The retained SVG is explicitly checked, not silently counted as new artwork.
* Actual Godot galleries at 1920x1080 and 3840x2160: `accepted_gallery/`. HUD, Shop, talents and courier captures at both resolutions: `ui/`; packed cold-start captures there too. Some staging tools emit ObjectDB/resource warnings on teardown; resource-clean lifecycle is not claimed.
* Names checker: Names OK. Packaging check: 227 unique generated images, no missing source sheets, one outside the pack by owner choice. Targeted changed-file whitespace check clean; repository-wide check reports pre-existing CRLF/trailing whitespace in unrelated skin JSON.
* Independent reviews: initial skill and item A/B preferred new art over the old set. Pass 2 fixed Blast Rod differentiation (all five pip counts passed). The final set comparison rejected four skill action cues at 32px; pass 3 improved three and the focused review passed those. Death Order's low-health cue failed twice; loop stopped at plateau and the owner chose its existing icon. All review records retained under `review/`. Critic contexts were fresh and isolation instruction-enforced; available traces reported no forbidden reads.
* Official Dota hero-page image is supplemental reference only (`review/reference.png`); no matched commercial superiority gate passed.

## Performance and limits

RTX 4060, Vulkan Forward+, 1920x1080, 10 heroes staged in a level-16 fight, 202 units, 30-second measurement after warm-up, t=120, restage every 15 seconds, uncapped rendering. Intermediate icon build: 53 FPS average, p50 18.18 ms, p95 30.00 ms, p99 36.07 ms (`bench.log`). Prior executable under the same scenario: 58 FPS average, p50 16.67 ms, p95 29.14 ms, p99 36.11 ms (`bench_baseline.log`). These single runs do not isolate an icon-caused regression; GPU mean was 8.59 vs 8.45 ms and simulation/scene work also differed. Neither meets sustained 60 FPS. Both exited with 0xC0000005 after printing measurements; ordinary capture launches exit normally. This benchmark-exit issue predates the new icon pack and remains unresolved. Final-build measurement, hashes and cold-start outcomes are recorded in `final_results.txt`.

No gameplay-quality or 60 FPS claim. No commit or publishing operation requested or performed. The owner's unrelated working changes remain in place.

Exact final pack recheck: 57 FPS average, p50 16.67 ms, p95 27.70 ms, p99 38.88 ms over 30 seconds; benchmark-exit crash reproduced. Final packed icon probe is clean (1,806/0), ordinary Caziel cold capture exits 0. Artifact hashes and full conditions: `final_results.txt`.

## Pass ledger

Skills 1: preferred to baseline, mandatory populated-cell check passed, small-size gap observed. Skills 2: action-cue rejection. Skills 3: three corrected subjects passed; Death Order repeated low-health gap, STOPPED — PLATEAU, then explicit owner choice to retain original. Items 1: preferred overall, Blast Rod gap; items 2: PASS including all state cues. Integration: runtime routing/import/export passes; commercial/performance/full lifecycle gates remain unverified or failed as described.

New player-visible names: none. New code and diagnostic names are listed in `docs/HANDOFF.md`.
