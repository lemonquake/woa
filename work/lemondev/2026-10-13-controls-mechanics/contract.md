# Run 2026-10-13 d: controls, HUD, and a Dota mechanics pass (status effects, bash, critical strike)

Baseline revision: 93b2efc (clean). Engine Godot 4.7.2, Windows, 1920x1080 target (also 3840x2160). Single agent
builds; no subagents were requested for this run.

## Owner's request (points, paraphrased closely)
1. Edge scrolling is unreliable. In exclusive fullscreen or borderless the mouse must be trapped in the window so a
   hard push at the edge never loses it.
2. The shop must close when the player clicks away.
3. Health and mana regeneration always show their bonus (fountain included) as a separate coloured "+N".
4. Where are Teleport Scrolls bought? Put them in the shop and add a "," key that buys one for 100 gold.
5. Holding S (Stop) must really stop: a repeated stop, the hero does nothing while it is held.
6. Deep dive Dota 2 again: port the mechanics and nuances exactly, including Bash (with a timer bar), Critical Strike,
   other debuffs, and other advanced mechanics.

## Root causes found before building
* Edge pan read the canvas mouse position, which Godot only updates on motion events, and required
  MOUSE_MODE_VISIBLE; nothing confined the cursor, so a push past the edge left the window (second monitor) and the
  last known position stopped short of the edge band.
* The shop had no "click elsewhere" handling; it only toggled.
* The HUD showed `hp_regen` (base + items) and ignored modifiers (fountain, salve, auras).
* The Teleport Scroll was in the shop data (Consumables) but not first and with no hotkey; a scroll bought anywhere
  went straight into the Teleport slot (Dota: away from the shop it goes to the stash).
* Holding S sent one hard stop after 0.35 s; orders given meanwhile went through.
* Mechanics: every chance effect used true random; no critical strike or bash existed; stuns stacked as separate
  modifiers; no status resistance, hex, break, spell amplification; uphill misses applied to melee attacks; evasion
  and magic resistance from items added up instead of multiplying; the fountain healed 4% (APPROX); no true sight,
  so invisibility had no counter; no projectile disjoint; neutral creeps had none of their Dota abilities.

## Components, owners, acceptance
| Id | Component | Files | Acceptance (gate) |
|---|---|---|---|
| U1 | Cursor lock and edge pan | camera_rig.gd, options.gd, options_agent.gd, options_panel.gd | controls_probe: cursor CONFINED in Borderless and Fullscreen (and Windowed with the lock), free otherwise; the OS keeps a warped cursor inside the window; the cursor at the right edge pans the camera and keeps panning when pushed further |
| U2 | Shop closes on click away | hud.gd | controls_probe: left or right click on the world closes it, Esc closes it, clicks inside the shop or on the bottom panel keep it |
| U3 | Regen with bonus | sim_world.gd (regen_rates), sim_unit.gd, hud.gd | test: the fountain bonus equals 5% max HP / 6% max mana and lingers 3 s; probe capture shows "+own +bonus" on both bars, readable |
| U4 | Teleport Scroll purchase | sim_shop.gd, keybinds.gd, input_controller.gd, hud.gd, sim_data.gd, sim_bot.gd | test + probe: "," buys one for 100 gold; away from the shop it goes to the stash and into the slot on arrival; first item in Consumables; bots count stashed scrolls |
| U5 | Hold Stop | input_controller.gd | probe: orders refused and re-stopped every frame while held; hard stop after 0.35 s; orders work after release |
| M1 | Status system | new sim_status.gd, sim_unit.gd, sim_world.gd, sim_items.gd, sim_abilities.gd | tests: PRD constants match Valve's table and the proc rate; stuns refresh to the longer; status and slow resistance; hex, silence, root, disarm, break effects; basic and strong dispel |
| M2 | Critical strike and bash | sim_combat.gd, sim_orders.gd, sim_items.gd, sim_data.gd | tests: crit rolled at attack start, strongest first, never on buildings; bash 25% / 10%, 1.2 s, +damage, 2.3 s cooldown with no roll, pierces debuff immunity, one bash item only |
| M3 | Items | sim_data.gd, sim_items.gd, hud.gd, ui_kit.gd, shop_panel.gd | tests: Dota 7.41d prices and recipes; every active works (Stun Blade, Silence Staff burst, Root Staff projectile, Halberd, Hex Staff, Break Blade); shop shows every item, panes fit |
| M4 | Neutral abilities | sim_ai.gd, sim_abilities.gd, sim_data.gd | tests: Stomp stuns 1.6 s heroes, Alpha Wolf crit and aura, Swamp Troll break with cooldown, Ogre Smash wind-up can be walked out of |
| M5 | Rules fixes | sim_combat.gd, sim_unit.gd, sim_vision.gd, sim_orders.gd | tests: uphill miss only for ranged, evasion multiplies, spell amp, true sight (towers, Reveal Ward, Reveal Dust), disjoint, invisible heroes never auto-attack |
| V | Visuals | unit_bars.gd, status_fx.gd, fx.gd, main.gd, audio.gd | captures: disable timer bar with label and seconds, sheep for hex, roots, silence ring, disarm blades, red crit number, Smash warning ring |
| G | Integration | all | tests pass (115 old + new), check.sh Names OK, probes (controls, input, item flow), 5v5 bot games without script errors, bench at 1080p no worse than 10% below the same-session baseline, export + cold start |

Benchmarks:
* Rules: Valve's game data `work/research/d2_items.txt`, `d2_npc_abilities.txt`, `d2_npc_units.txt` (cached from the
  public d2vpkr mirror, 7.41d) and the Dota 2 wiki on Fandom (Pseudo-random distribution, Critical Strike, Bash, Stun,
  Status Resistance, Evasion, Hex, Root, Silence, Disarm, Break, Dispel, Fountain, Invisibility, Disjoint, Sentry Ward,
  Dust of Appearance), cached in `research/fandom*.json`. Liquipedia's API answered 429 (rate limit) this session.
* Visual blind review needs real Dota frames of a stun timer, hex and crit numbers; none are on disk and downloading
  them needs the owner's OK, so the visuals stay UNVERIFIED for blind review.
Budget: 8 passes per component.
