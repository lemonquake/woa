# Build results

- Status: IMPLEMENTED — UNVERIFIED under the full Gauntlet standard; release export and build-only checks passed. Independent visual comparison and comprehensive lifecycle validation were not performed.
- Build source: `5f730623a9aa9fa731ff3600a34c225cecb729fe`. No gameplay or asset changes made during this run; the subsequent commit updates two test messages and records results. Tests and Markdown records are excluded from the export.
- Engine: Godot `4.7.2.stable.official.ed1daf0bf`; Windows Desktop release x86_64, existing export preset.
- Output: `A:/Python/woa/build/WarriorsOfAether.exe` and `WarriorsOfAether.pck`. Launch the executable with the pack beside it.
- Prior build: `build/previous-2026-10-18-build/`; candidate: `build/check/`.
- Export scope: existing working directory and all-resources preset, including existing untracked `audio/` resources. Untracked files were not staged or pushed.
- Import: exit 0, no loading errors.
- Full tests: `--headless --path . -s tests/run_tests.gd`, exit 0, 249 passed, 0 failed.
- The full test log also exposed two formatting errors in assertion messages. Escaped the literal percent signs and reran `--only=ranger_ezee_talents` and `--only=lily_pond`; each passed with exit 0 and no formatting errors. No assertion or gameplay logic changed. Final test script parse check and naming check passed.
- Parse and naming: `sh tools/check.sh`, exit 0, no script errors, Names OK.
- Export: `--headless --path . --export-release "Windows Desktop" build/check/WarriorsOfAether.exe`, exit 0.
- Render checks: exported normal startup (`select.png`) and Azrael match (`match.png`), both inspected and exited 0. NVIDIA RTX 4060, Vulkan Forward+, requested window size 1920x1080; capture viewport 1920x1017.
- Match command: `WarriorsOfAether.exe --resolution 1920x1080 --windowed -- --match --hero=azrael --capture=A:/Python/woa/work/lemondev/2026-10-18-build/match.png --t=95 --live --frames=120 --nolearn`.
- Match readiness: 18050 ms while the test suite and parse checks were running; not a performance benchmark.
- Remaining gap: shutdown cleanup warnings (1439 ObjectDB instances and 19 resources in the match; 32819 instances and 19 resources in the full tests). Earlier export logs also report this warning class. No script, shader, or resource-loading errors observed.
- Budget: export pass 1; one repair to test diagnostic messages, both affected tests rechecked. Commercial comparison, 4K interaction checks, and a new frame-time benchmark are outside this build-only scope. No independent review claimed.
- New player or code names: none. Evidence folder: `2026-10-18-build`; previous-build folder as listed above.
- Raw logs and captures remain local in this directory; executable and pack remain ignored by Git.

SHA256:

```text
WarriorsOfAether.exe 7BFBBBAE2DD7D8138C8BE5B747408ED13831C200AB6C6431AF2BED626AEC36B3
WarriorsOfAether.pck 01E3970BC7DC5FC0515922F94EF803C68B35969231F8ED64FB1BB69BC068ECB4
```
