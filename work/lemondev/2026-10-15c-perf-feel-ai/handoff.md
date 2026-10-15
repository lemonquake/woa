# Run 2026-10-15 c: handoff

Read `contract.md` first (request, components, measurement conditions). This file is the map of what changed and
how to check it again.

## Tools added this run

| Tool | What it does |
|---|---|
| `main.tscn -- --bench=N --fight [--lineup=a,...,j] [--restage=20] [--lvl=16] [--bench_shot=png]` | Teamfight benchmark: ten heroes (Ancient Light's five, then Black Sun's), levelled with items, staged face to face in mid every 20 s; the Debug flag `brawl` makes every bot fight the nearest enemy hero. Prints frame times (avg, p50, p95, p99, max), frames with and without a sim tick, and per-frame means of every timed part (`sim`, `events`, `sync`, `views`, `fx`, `fx_azrin`, `fx_froster`, `fx_other`, `script_proc`, `script_phys`, `flush`, `draw`, `gap`, `gpu`, `rcpu`, draw calls, each HUD panel's `_draw` as `ui_*`) and the worst frame of each part. |
| `src/game/bench_probe.gd` | Two nodes that run first and last in `_process` / `_physics_process` (the whole script time of a frame) and stamp `RenderingServer.frame_pre_draw` / `frame_post_draw` (deferred work and the draw itself). |
| `tests/tools/sim_profile.gd -- --fight=600` | The same teamfight in the headless simulation; prints every tick over 15 ms with what it was made of. |
| `python tools/gd_profile.py [--game] -- <args>` | Function-level profile: copies the scripts to a scratch project, wraps every function with a timing scope, runs `sim_profile.gd` (or with `--game` the whole game in a window) and prints self time and call counts. Static functions can read inflated: time a suspect one directly before acting on it. |
| `tests/tools/bot_game.gd -- --tf_off=0|1` | One side plays without the team engage (A/B). The report now prints each side's teamfights, ganks, pushes (and how many went on to the next building), towers lost and how often bots got themselves unstuck. |
| `tests/tools/lh_lab.gd -- --lead=S --bias=K` | Last-hit lab with the forecast lead and the damage bias as parameters. |
| `tests/tools/input_probe.gd` | Now also checks Quick cast (the key alone casts at the mouse). |

## What changed, by component

### Performance
* `froster_fx.gd` (and 48 more places in the effect scripts): a typed variable took an effect node that something else
  had freed, a script error that aborted the update every frame; printing the error cost ~10 ms per frame whenever a
  Froster had frozen or chilled someone. `View.live(x)` returns null for a freed node; every such site uses it.
* HUD portrait: its camera drew the whole shared world again each frame (~460 draw calls, ~2 ms). It now sees only the
  shown unit's meshes (render layer 20, set on the unit's meshes), has its own light environment (no SSAO, glow or
  fog) and renders every other frame.
* Simulation: bots start their think cycles on different ticks; the two team brains think a quarter second apart;
  sight shapes are invalidated only near a changed tree (were all dropped on every felled tree: 20-30 ms ticks) and
  the full cache drops its oldest quarter instead of everything; building sight comes from the same cached shapes;
  power estimates, nearest buildings and ability values are cached (per tick, per tick, per unit until its stats
  change; all TRANSIENT in snapshots); neutral spawns check camp stacking in one pass; creeps at full health skip the
  regeneration maths; `is_building()` / `is_lane_creep()` compare instead of building an array.
* Interface: the minimap draws dots, buildings and camp marks as one triangle batch and one line batch; the kill feed
  and scoreboard redraw only while they show something; the chat fade redraws at 30 Hz; the hover pick tests only
  units near the ground under the cursor; `ground_at` starts its ray march at the highest ground.
* Spike Armor thorns share one mesh and material. Ribbon trails restart after a jump (they streaked across the map
  after a teleport).
* Options > Video quality: Low and Medium draw the sun's shadow in one cascade (High and Ultra two).

### Bots
* Last hits: the creep-health forecast fired too late; a -0.2 s lead (lab-calibrated).
* Teamfights: `SimTeamAI._call_teamfight` (odds by Lanchester's square law, ultimates, towers), focus target shared by
  the team, hysteresis; bots in a teamfight ignore the solo "outnumbered" retreat but keep the low-health one.
* Ganks: a rally point out of the target team's sight on its way home, strike when gathered; in the laning phase only
  with a hero from another lane and once a minute per enemy; carries stay on farm before 15:00; from 20:00 no
  teleport-ganks across the map unless the target is low; heroes on a push only join ganks beside them.
* Farming: waves are cleared after the laning phase (area spells on three or more creeps); the camp check counts the
  camp as it stands (growth, stacks) and keeps half health; a camp kind that nearly killed a bot waits two levels;
  bots teleport back to a far lane or camp from the base; they wait for regen the courier brings instead of walking
  home; casters buy and drink Mana Potions.
* Mid and late game: from 20:00 the team pushes when about as strong, from 30:00 with three heroes up; a push goes on
  to the next building; from 25:00 the whole team joins pushes (also bots that come back later) for 90 s; a pushing
  group tanks tower shots in turn (no retreat from tower aggro alone with two allies beside and over 45% health);
  supports stop stacking late; defenders need half health; a stuck bot (an order out of reach, not moving for 6 s)
  drops the camp, wave and play and walks out.

### Learning (`BotMemory`, saved in `user://bot_memory.json`)
New: the teamfight engage bar and gank success by number of gankers (per-hero last-hit timing was tried and
removed: it drifted the wrong way in contested lanes). Two learning A/B runs did not show learned bots stronger. Options > Game shows the
counts. Automated runs and tests never read or write it.

### Feel and controls
* Quick cast (Options > Game): a spell or item key casts at the mouse at once (on the unit under it); with the mouse
  over the interface or no valid unit under it, the targeting cursor stays up with the reason, as before.

## State

See `docs/HANDOFF.md`, "Status", for the evidence and what is not verified.
