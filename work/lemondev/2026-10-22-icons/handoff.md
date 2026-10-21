# New icon artwork and Game Icons skill

Status: IMPLEMENTED — UNVERIFIED against the complete commercial/performance/lifecycle standard. Artwork coverage, project-baseline visual review, integration checks and Windows build pass. No fresh commercial A/B or performance claim.

## Result

Scanned all22 heroes,106 ability definitions,14 unit/neutral traits,5 sword states and180 item/recipe/held entries. The305 runtime routes resolve to259 distinct256px painted PNGs (125 skill/unit/state +134 item/state identities). No source image or route gaps remain. All items already had art, so their images were retained.

Built-in image generation produced34 images in three source sheets:27 skills of Blackfire, Thyrandael, Gancho, Lord Kaileh and Dracoxinia;5 current-sword states; Giant Swing's updated downward overhead cut; Death Order. The owner's explicit correction—"No! Change the Death Order"—revokes the older retained-SVG choice. Death Order now has painted artwork with a nearly-empty life bar and bright dagger; all old hardcoded exceptions were removed from lookup and probe. No gameplay values or existing names changed.

`sheets/`, `plan.json` and `manifest.json` preserve generation sources, prompts, cell IDs, crop bounds and hashes. Only this run's34 IDs are packaged; existing accepted art is retained. `before/giant_swing.png` keeps the replaced prior version. The original SVGs still provide missing-file fallbacks.

## Reusable skill

Canonical: `A:/Python/woa/lemondev/game-icons/SKILL.md`. Personal installation: `C:/Users/Lemon PC/.codex/skills/game-icons/`. Both copies and metadata validate; implicit invocation enabled. AGENTS.md and CLAUDE.md instruct future agents to use it for new/missing/revised skill or item icons. Call `$game-icons` explicitly if desired.

The skill follows current source mechanics and identity maps, uses built-in generation, preserves art and evidence, includes states beyond the ability table, checks runtime routes and exports only when authorized. `tools/icon_audit.py` reports current PNG/route gaps and optional baseline definition changes; numeric-only edits require review, never automatic regeneration. `tools/icon_art.py --run <folder> [--check]` requires an explicit run, validates the final revision of each cell and checks actual output pixels. A separate agent successfully followed the skill for a dry audit (`skill-test/`), found no remaining coverage gaps and no instruction bug. Isolated packaging fixtures verified later-revision selection and rejection of modified output pixels (`helper-test/`).

## Verification

* Full gameplay regression:352 passed,0 failed, exit0 (`tests.log`). Existing ObjectDB/resource-cycle warnings remain on teardown (`tests.err`); they are not new texture or script-load errors.
* Final scanner:305 entries,259 expected unique painted sources,0 missing PNGs,0 route mismatches; all305 routes backed by fresh runtime data (`after/data.json`, `after/audit.json`). Prior audit evidence remains in `before/` and initial semantic audit in `audit.*` (owner correction annotated).
* Source runtime icon probe at1920x1080 and3840x2160:2079 checks,0 failures (`gallery_1080.log`, `gallery_4k.log`). It exercises hero/unit skills, all item records/recipes, boot attributes, empty/full Flask, legacy aliases, all five live SimKits11 sword modifiers, HUD current-sword inset and BuffBar route agreement. Galleries: `final-gallery/`.
* Fresh-context raw anonymous A/B comparison accepted the new set against the existing project set (`review/review.md`). Every cell populated, Death Order low-life cue visible, Giant Swing downward, Dragon Leap traversal without impact explosion, Dragon Hide scales, sword effects distinct. Blue Sword's fine root detail is less clear at32px. Reviewer isolation was instruction-enforced on shared filesystem; available trace inspected only packet images. The review's incidental "mounted" wording is not a mechanics assertion: source art and implementation use ghost knight copies, no horse model was added.
* HUD, Shop, talents and courier inspected at1920x1080 and3840x2160 (`ui/`). The diagnostic ui_probe now explicitly requests borderless1080 for its1080 tag; initial windowed1920x1017 evidence was replaced with exact1080 captures. No product display settings changed.
* Release export exit0, stderr empty (`export.log`, `export.err`). Exported pack passes2079 checks,0 failures, exit0, stderr empty (`packed_probe.*`).
* Exact executable cold-starts with Dracoxinia and Caziel: both exit0, no script/resource-loading errors, captures in `ui/export_dracoxinia.png` and `ui/export_caziel.png`. Match readiness17209ms/17720ms in these captures. Teardown still reports pre-existing ObjectDB/resource warnings (`cold_*.err`). No claim of leak-free lifecycle.
* Names checker printsNames OK. Changed-file whitespace checks and skill validators pass. Packaging/source-pixel check passes all34 images. No commit or publication requested/performed; owner's unrelated working changes preserved.

## Build

Run `A:/Python/woa/build/WarriorsOfAether.exe`, with its matching `WarriorsOfAether.pck` alongside it. Previous executable/pack recoverable in `previous_build/`.

EXE SHA256: `7BFBBBAE2DD7D8138C8BE5B747408ED13831C200AB6C6431AF2BED626AEC36B3`

PCK SHA256: `2119207183BF0EA144AC6A102F45B52FD48FA431F24E0FADF5964B42924BFC6B`

Engine: Godot4.7.2, Vulkan Forward+, RTX4060. Export command: console Godot with `--headless --path A:/Python/woa --export-release "Windows Desktop" build/WarriorsOfAether.exe`. Run via Start-Process Hidden/Wait with redirected logs. Packed probe: `--headless --main-pack A:/Python/woa/build/WarriorsOfAether.pck --script A:/Python/woa/tests/tools/icon_art_probe.gd`.

No fresh performance measurement or matched commercial comparison this run. The older benchmark-exit issue is outside this icon change; ordinary captured launches exit normally. Full lemondev VERIFIED is withheld for these missing/remaining gates.

Passes: generated sheets/state routing1; all accepted after one visual review. The newly authorized Death Order attempt is pass1, not an unannounced continuation of the stopped20October loop. Skill creation1, validator and independent dry-audit pass. New names/code helpers listed in docs/HANDOFF.md.
