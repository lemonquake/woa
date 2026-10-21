# Dry icon audit contract

Input: work/lemondev/2026-10-22-icons/after/data.json supplied live dump.
Scope: inspect current source coverage and runtime routes; report required art/routing work and workflow runnability.
Allowed writes: this skill-test directory only (and temporary files).
Excluded: generation, image changes, gameplay edits, builds, global handoff/ledger edits, visual acceptance or independent artwork review.
Checks: tools/icon_audit.py; inspect dump exporter, lookup and direct HUD/buff routes for coverage limitations.
Revision: current working tree; no implementation passes.
Overrides: supplied dump replaces export step; contract/report here replace global ledger updates because writes are restricted. Integration, rendered gallery, image-generation and build stages are outside the requested dry audit.
