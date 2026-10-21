# Run 2026-10-21: handoff (Blackfire, Thyrandael, barriers, Forums tab, matchmaking)

State: IMPLEMENTED; component gates measured (below); no blind critic, no Dota 2 benchmark (UNVERIFIED). The owner's
requests are in `contract.md`; the summary for the owner is the top entry of `docs/HANDOFF.md`.

## Files
* Sim: `src/sim/sim_barrier.gd`, `sim_kits8.gd` (Blackfire), `sim_kits9.gd` (Thyrandael), `sim_bot21.gd`; hooks in
  `sim_abilities.gd` (kits, cast range, channel, impact, `commands`), `sim_combat.gd` (barrier, charges, crit key,
  Fiend Edge drain, Unfallen catch, bodies, no-bounty Undead), `sim_orders.gd` (beam aim, untargetable), `sim_unit.gd`
  (`atk_crit_key`), `sim_world.gd` (ticks), `sim_data.gd` (heroes, abilities, talents), `sim_bot.gd`,
  `sim_bot_kits.gd`, `sim_bot_items.gd`, `sim_bot_chat.gd`, `chat_mind.gd`, `sim_commands.gd`.
* Game and UI: `src/game/hero21_fx.gd`, `main.gd`, `unit_view.gd` (Unfallen's held death), `fire_fx.gd` (ramp),
  `audio.gd`, `input_controller.gd`; `src/ui/barrier_bar.gd`, `unit_bars.gd`, `hud.gd`, `buff_bar.gd`,
  `hero_select.gd`, `hero_stage.gd`, `ui_kit.gd`, `forums.gd` (embedded), `ranked_menu.gd`, `main_menu.gd`;
  `src/core/matchmaker.gd`, `game_settings.gd`, `bot_names.gd`, `llm_chat.gd`, `forum_writer.gd`.
* Assets: bodies and swords (builder, see `bodies/`), skill icons (`tools/item_icons.py`), portraits.
* Tests: nine new tests at the end of `tests/run_tests.gd`.

## Traps
* World events are never cleared in tests or probes: clear them each step before counting.
* `anim_repair --model=` writes the shared `hero_anims_fixed.res`; heroes17 bodies use the shared set (builder note).
* `tests/tools/body_shapes.gd` fits Thyrandael's chest around his wings; the builder's copy
  `bodies/collide_tool/body_collide_wings.gd` ignores far skin. A real fix belongs in body_shapes.
* Select captures overwrite `user://hero.json`; it was backed up and restored.
* A relative `--out` in Blender tools lands on C:\ (grid renders went to `C:\work\...`).

## Not done / not verified
* No critic; no Dota comparison; no 4K capture; exe menus not clicked. (False Judgement and Unfallen captured live after
  the interruption: shots/judgement_sheet.png, unfallen_sheet.png.)
* Thyrandael: 2 animation joins over the limit; his blade can pass through his wings in big swings.
* (Fixed after the interruption) the two flaky ladder tests build a fixed ladder (`Ranked.seed_override`).

## Follow-up: fast matchmaking (the owner: matches kept cancelling for 30 minutes)
* Cause: on the owner's ladder about 1 offer in 4 had a bot fail to accept (`build_lineup` fail rate up to 8% a bot),
  and every failed offer waited out the 15 s timer. The Accept click itself works (ranked_probe 51/51).
* Now: searches 2-7 s, bots accept in about 2 s, fails about 1 offer in 50, a fail re-queues once everyone else has
  accepted, the re-queue searches twice as fast, no second fail in one queue. `tests/tools/mm_probe.gd` on a copy of the
  owner's ladder: 3% failed, never two in a queue, 8.8 s average, 17.8 s worst. `test_matchmaker_failed_accept`.

## Follow-up: portrait light
* The HUD portrait has its own lights and daytime sky (hud.gd `_portrait`); the battlefield camera skips its layer.
  Godot 4.7 culls lights by the camera's cull mask (checked with a small test), which is why it only had sky light.

## Final
* Suite 343/0 (logs/tests5.log), check.sh Names OK, ranked_probe 51/51 x2, export 06:27, exe night cold start
  (export/exe_night.png).
