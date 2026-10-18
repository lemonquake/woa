# Bot chat edit

- Scope: polish `bot_trashtalk_chat_lines.json` in place. Preserve its JSON shape and ten category keys; recount metadata. Do not wire the library into the game or edit gameplay.
- Baseline: HEAD `8dbcbce`, supplied untracked JSON preserved in `before.json`; unrelated working changes remain owned by their existing authors.
- Benchmark: user's short examples and screenshot of rejected repetitive lines. Supporting research: actual SEA Dota chat transcripts, Filipino field observations, community language examples. Sources and limitations will be recorded in `research.md`.
- Frozen criteria: short, natural Filipino/Taglish and English reactions; one thought per line; gameplay context matches category; no generated prefix/setup/suffix combinations; occasional longer role-specific complaints allowed. Retain requested profanity and informal spelling.
- Measured gates: valid UTF-8 JSON; same top-level and metadata field keys, same ordered category keys; nonempty strings and categories; no exact or punctuation/case-only duplicates; metadata totals match; at least 80% of entries at most six words; no entry beyond 110 characters; naming check prints Names OK.
- Review: one fresh critic using anonymous before/after excerpts, the user's text style reference, and these criteria; maximum two build/review passes. Critic only owns review notes and may not edit candidate or read builder context. Isolation is instruction-enforced in the shared workspace.
- Platform: standalone text data for Windows/Godot 4.7.2; no engine changes. Rendering, frame time, cold launch, multiplayer and simulation tests N/A because this file is not referenced by game code. Runtime chat scheduling/channel/role checks remain outside scope.
- New names: none; existing category identifiers remain intact. Transcript references to other games' named heroes/items are not added.
