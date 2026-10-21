---
name: game-icons
description: "Scan, generate and integrate skill and item icon artwork for Warriors of Aether. Use whenever the owner requests new or missing Skills/Items icons in this project, including hero innates, extra abilities and held-item or sword states."
---

# Game Icons

Use this workflow for the game in `A:/Python/woa` (or its current checkout). The project copy of this file is canonical; keep the personal installed copy in sync when updating the workflow.

Read the project's `AGENTS.md`, `docs/HANDOFF.md`, `docs/MECHANICS.md`, `lemondev/SKILL.md` and `lemondev/references/naming.md`. Apply the lemondev contract/review/ledger rules. Preserve existing display names and gameplay values. The owner wants built-in image generation for painted skill/item artwork; apply the available imagegen skill. Do not substitute procedural symbols or a CLI/API generation path without an explicit user change.

## Find the actual gaps

Create a dated run under `work/lemondev/` with a contract and before/after evidence. Inspect the live data and implementation, not an old list or ability names alone. Include every playable hero's innate, learned and upgrade ability; neutral/unit skills; item levels, recipes, Switch Boots attributes, empty/full Flask, and separate HUD/buff states such as current swords. State/secondary actions can sit outside `SimData._abilities`.

Export current routes and pixels with `tests/tools/icon_art_dump.gd`, then run:

```text
python tools/icon_audit.py --data <run>/before/data.json --out <run>/before/audit.json
```

`--baseline <previous-dump.json>` flags definition changes and new entries for review. Exit1 means audit findings, not necessarily a tool failure. A changed number alone does not require new art; compare the actual represented action. A missing source PNG, generic fallback or wrong resolved route does need attention. Read the report's `summary` and `records`. Do not hardcode roster or icon counts. The old Death Order SVG exception was explicitly revoked by the owner on22October2026; it now uses painted artwork like other skills. Any later owner decision takes precedence.

## Generate and package

For each gap, record exact ID, current effect, visual subject and route. Retain suitable accepted images. Generate original art with the built-in image tool. Use a hero sheet or small related group with an explicit equal grid, row-major cell mapping, no text, no gutters, strong large subjects, quiet backgrounds and enough safe margin for cropping. Match the existing painted set; judge at32/44/64px, including dim and cooldown states. Show the primary action without contradicting mechanics: traversal-only leaps must not suggest a damage explosion; a low-health pure-damage passive is not a guaranteed execution. Distinguish Pink/Lightning, Gold/Light, Blue/Water, Red/Fire and Green/Nature sword powers from code rather than color guesses.

Copy the generated originals into `<run>/sheets/`. Write `<run>/plan.json` as an array of `{key, kind, grid, ids, prompt}`: `key` names the PNG in `sheets/`, `kind` is `skills` or `items`, `grid` is the number of equal rows/columns, and `ids` lists cells row-major (null means unused). Use `replace: true` only for an intentional later revision of an earlier ID in the same plan. Back up an existing image before replacement. Crop/resize as packaging, keeping generation originals intact:

```text
python tools/icon_art.py --run <run>
python tools/icon_art.py --run <run> --check
```

Only the current run's IDs are written. The checker verifies output pixels against source cells and the manifest records hashes. Never regenerate an older run over newer accepted artwork. Output paths are `assets/ui/art/skills/<id>.png` and `assets/ui/art/items/<id>.png` (256px). Recipes normally share `art/items/recipe`; charge numbers, cooldowns and orb dots remain live overlays.

## Integrate, review and build

Use `src/ui/ui_kit.gd` as the common lookup. Keep unique ability/state routes plus original SVG fallbacks. Check direct legacy paths in `src/ui/hud.gd` and `src/ui/buff_bar.gd`; a PNG file alone does not prove the HUD uses it. Extend identity maps and coverage checks for genuinely new state families. Existing `STATE_SKILL_ICONS` covers sword states.

Import assets, rerun the dump and scanner, and run `tests/tools/icon_art_probe.gd`. Normal probe mode requires painted routes; `--fallback` merely relaxes checks and does not force old SVGs. Use `-- --gallery=<run>/gallery [--4k]` without `--headless` for real rendered galleries. Inspect representative actual HUD/Shop captures at1080p and4K. Compare anonymous matching raw evidence with a fresh critic as prescribed by lemondev; do not ask a static icon to prove every rule or numerical threshold. Keep failed reviews and honor the stop rules.

Use the project's current documented Godot path/version/export preset. On this Windows machine, launch the console executable with `Start-Process -WindowStyle Hidden -Wait -PassThru` and redirected stdout/stderr so completion is observed reliably. Run the impacted tests, name checker and required checks; review stderr even when exit0. Before a commit, run `python tools/normalize_eol.py`. Preserve the previous executable and pack before rebuilding `build/WarriorsOfAether.exe` with the Windows Desktop release preset. Verify the exact exported pack with the icon probe (external script path) and cold-start the executable into a match using `-- --match` and a capture flag. Exported builds ignore source scene arguments.

Update credits if needed, `docs/HANDOFF.md`, `work/lemondev/ledger.md` and the run handoff with artwork counts, new code names, hashes, actual tests/captures and remaining limitations. Report the real build path. Do not claim commercial quality, clean lifecycle or60FPS without current evidence. Build only when requested or already authorized; the skill does not authorize publishing, commits or unrelated gameplay work.
