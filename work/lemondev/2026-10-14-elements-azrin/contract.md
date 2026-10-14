# Run 2026-10-14: elements, armor and damage types, magic amp, item menu, item effects, Azrin

Baseline: a38afe7 (clean tree). Rollback point: that commit. Engine Godot 4.7.2 Forward+, Windows, RTX 4060,
target 1920x1080 (also checked at 3840x2160). Budget: 8 build/review passes per component (lemondev default).

## Owner's request (2026-10-14)

1. Right click an inventory item: a menu with Sell, Disassemble (parts are locked so they do not combine again),
   Lock / Unlock. Locked items never combine.
2. Animated effects for items such as Spike Armor, and effects that make sense.
3. Magic amp: every 20 Int = +1% magic amp; every 25 Int = +1% magic resistance. Items like Sange, Yasha, Kaya named
   Kugmo, Igit, Atuli. Magic amp from items stacks with diminishing returns.
4. Creep death sounds (lane and neutral) 40% quieter.
5. Elements (None, Fire, Water, Ice, Earth, Lightning, Nature, Dark, Light) with a strength / weakness table, for every
   unit (heroes, creeps, buildings) and every damage source (attacks, spells, passives, items).
6. Armor types (Hero, Organic, Structure, Armored, Titan) and damage types (Piercing, Blunt, Slash, Hero, Siege, Magic,
   Aether = pure) for every unit.
7. HUD overhaul to show element, armor, weapon; hover shows resistances and every amp.
8. New hero Azrin, the Flamemander (owner's numbers), Fire, 665 range, floating like a fire empress with a real
   particle fire system ("perfect fire effects").

## Components (one owner per file set; all built by the orchestrator in this session)

| ID | Component | Files | Acceptance gate |
|---|---|---|---|
| E1 | Elements, armor and damage types, magic amp, burns (DoT) | sim_const, sim_unit, sim_combat, sim_status, sim_data | headless tests: table values, every existing Dota pairing unchanged, int amp/resist, diminishing item amp, burn ticks and extension |
| E2 | Kugmo / Igit / Atuli family | sim_data, sim_unit, sim_orbs | tests: stats, recipes, diminishing amp across two items |
| E3 | Item menu: sell, disassemble, lock | sim_shop, hud | tests (lock blocks combine, disassemble places locked parts and the scroll, NEVER items refuse) + live click probe |
| E4 | Azrin kit + talents + bot | sim_data, sim_abilities, sim_bot, sim_bot_kits | tests per ability with the owner's numbers; 12-min bot duels vs each hero without errors |
| V1 | Fire particle system, Azrin's look and float, ability visuals | src/game/fire_fx.gd (new), azrin_fx.gd (new), unit_view, model_catalog, game_settings | captures at 1080p in a live window: idle hover, each spell, burning units |
| V2 | Item effects (Spike Armor and others) | item_fx, status_fx | captures of each effect |
| U1 | HUD: element, armor, weapon, resistances and amps | hud, unit_bars, shop texts | captures at 1080p and 4K, every tooltip readable, no overlap |
| A1 | Creep death sounds -40% | audio | code check: -7.4 dB (the project's loudness rule, 10 * log2(0.6)) |
| G | Integration | all | tests, check.sh Names OK, probes, bench vs same-session baseline, export + cold start |

## Benchmarks

* Mechanics: Dota 2 7.41d game data in `work/research/` for items; the owner's numbers for Azrin and the new systems.
* Visuals: no Dota frames of these effects are on disk. Blind review is UNVERIFIED unless frames are supplied;
  builder self-checks are labelled as such.

## Decisions (owner can veto; listed in docs/HANDOFF.md)

* Element table: strong = x1.25, weak = x0.75, every element except None resists itself (x0.75), Light and Dark beat
  each other. Beats: Water > Fire, Fire > Ice, Fire > Nature, Earth > Fire, Ice > Nature, Ice > Earth, Water > Ice,
  Lightning > Water, Earth > Lightning, Nature > Water, Nature > Earth, Light <> Dark.
* Armor x damage table keeps every existing Dota pairing exact (hero vs structure 0.5, melee creep vs hero 0.75,
  piercing 0.5 / 1.5 / 0.35, siege 2.5 vs structure, siege creeps' incoming 0.5 / 0.7 become the Armored type, magic
  never hurts structures). New cells (Titan column) are designed values; nothing uses Titan until Roshan exists.
* Magic amp: Int 1% per 20 (continuous, 0.05% per point); item sources sorted largest first, each counting half as
  much as the one before (10% + 10% = 15%). Int magic resistance 1% per 25 (0.04% per point, was Dota's 0.1%).
* Disassemble follows Dota's NEVER list (Gold Glove = Hand of Midas, Upgrade Staff = Aghanim's Scepter); all other
  combined items can be taken apart anywhere; parts are locked; the recipe scroll comes back.
