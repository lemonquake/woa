# Build contract

- Scope: export the existing committed game, validate it, and push main without force.
- Source: 5f73062; current branch main; existing untracked files remain local.
- Engine: Godot 4.7.2, Windows Desktop release, x86_64, existing export preset.
- Checks: resource import; full headless tests; tools/check.sh; Names OK; release export; cold rendered start into an Azrael match and inspect its capture and logs.
- Artifact: build/WarriorsOfAether.exe and adjacent .pck. Export a candidate under build/check first; preserve the prior build until checks pass.
- Benchmark: existing source and export behavior; no gameplay, visual, or performance changes requested. Commercial comparison and new performance targets are outside this build-only scope.
- Pass budget: one build, up to two repairs for build failures. Independent visual review is not claimed.
- New names: none in game or code; evidence directory 2026-10-18-build.
