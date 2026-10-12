# Design notes (Plan review, 2026-10-13) — implementation guide

## Traps (places that switch on one ability/hero)
- sim_orders.gd:182-197 channel tick always calls update_burst; root cancels every channel (Burst-only rule -> data flag channel_breaks_on_root).
- sim_orders.gd:48-53 only instant items skip channel-cancel (Rot, Meat Shield must too).
- cancel_channel has no cleanup hook (Dismember target stun must be removed).
- cast_error: hard-coded leap_strike; no unit-target validation; silence check blocks toggles.
- is_instant / item_target: items only, hard-coded use strings; no "unit" kind. cast_range matches item use strings.
- execute: always spends mana/cd, emits cast, charges sticks -> toggles bypass.
- update_effects: match kind (line, delayed).
- _impact: aid in [dark_stomp, gale_impact].
- sim_unit.is_stunned: any knock = stun (Force Staff must not disable -> knock.disable flag).
- _item_stats sums everything (boots stack).
- stick_charges on unit (hud.gd:544, tests 1137,1141) -> property shim mapping to item charges.
- sim_world.gd:331 respawn clears modifiers -> Flesh Heap/talents/shard not modifiers (perm_stats).
- sim_combat.gd:373 same-team killer = deny path; Flesh Heap check must run before; Rot self-damage non_lethal.
- sim_shop.gd:117 skips recipe_cost>0; bot double-buys zero-recipe items.
- sim_bot.gd:45,223,375 kit == "ezee" else ranger.
- sim_debug.gd:94 masterful special case.
- hud.gd:228 channel bar reads channel.interval * waves.size() (crashes for other channels) -> ch.dur.
- main.gd:335 every effect_move -> fx.gale_move; main.gd:350-363 every channel_start -> burst fx.
- unit_view.gd:295,379 Burst-only channel pose.
- input_controller.gd:381-385 no toggle; 452-454 item clicks always CAST_POINT.
- targeting_fx.gd:115-124 values.radius -> ring, else width+distance -> line. Hook search radius must be "width". unit ring uses attack_range -> use a.range.
- game_settings.gd:8,18; main.gd:162-180; hero_creator.gd:55,329; hero_select.gd:12; audio.gd:122,170-180 per-hero branches.

## Build order
0. Refactors with zero behaviour change:
   - SimUnit: talents{}, stacks{}, perm_stats{}, shard, toggles{}, spell_lifesteal, cached phased/face_locked/debuff_immune, attack_block, attack_procs. stick_charges -> property over item charges. refresh_stats adds perm_stats and caches. add_modifier: refresh with only expires changed doesn't dirty stats. is_stunned honours knock.disable; rooted while any knock.
   - SimData._unit defaults ancient/talents/innate; ancient=true on cinder_wyrmling, elder_cinder_wyrm.
   - SimAbilities.val(u, aid, key) = level value + talent add, x talent mult, + scepter/shard overrides. ability_mana/ability_cooldown through val.
   - Generic channel: channel_tick(u) dispatch; channel_cleanup(u, ch, cancelled); _start_burst stores start/dur.
   - deal_damage(..., opts={}): attack block (attack, enemy, pre-armor) -> type mult (opts.ignore_armor) -> backdoor -> unholy split -> instance block (max block_all) -> opts.non_lethal -> apply/ledger/events -> spell lifesteal (100% heroes, 20% creeps, not attacks, not reflected) -> kill -> unholy reflect -> damage return (reflected=true).
   - heal(): heal reduction (max heal_reduction); returns healed amount.
   - HUD channel bar uses ch.dur; main.gd routes by ability.
   - test_determinism_same_seed.
1. Shop/recipes: recipes [[...]] alt sets; auto recipe_<id> items (category recipes, recipe_for); carry (charges), attr_from, consume_on_buy. price = min over sets. Composite buy buys missing pieces + scroll then _combine_all. Combine pool: inventory (+ stash when in shop); stash alone; insertion order; result in first component's slot; loop. Bot skips owned. Tests: scroll first, stash rules, treads alt sets, bot no double buy.
2. Stats: boot_ms max; stats_melee/stats_ranged; attr; max_mana_pct; souls; treads toggle; wand carries stick charges.
3. Status systems: can_affect(t, src_team, pierces); mute; face lock; phase in _free (cached bools); knock {disable, cut_trees, drag, seq}; vision sources {team,pos,r,until}; auras every 6 ticks (source -1, expires +0.5); integer next_tick.
4. Items A: treads, phase, arcane, mekansm, vanguard, blade mail, bkb (levels 9/8/7? verify), scepter, shard.
5. Items B: blink (clamp 960 if >1200, 3 s hero-damage lockout, root), force staff (600 over 0.5 s, non-disabling, cuts trees, ally/enemy/self), midas (charges).
6. Items C: corruption (shared id, strongest wins), cleave (trapezoid 150->360 over 650, 60% heroes?/verify), maelstrom chain (rng only if equipped), desolator souls, shadow blade (fade 0.3, break on attack +175).
7. Talents, toggles, Sludge sim. Innate not in u.abilities. Hook effect states out/back, hook_first_hit (min along-track, ties by id), drag via knock {drag}, events hook_launch/move/latch/end. Rot pulse every 6 ticks. Dismember channel next_tick every 15 ticks? (6 ticks over 2.75 s -> verify spacing). _target_error validator.
8. Bot: match kit; harass on not ranged; SLUDGE_SKILLS/BUILD; hook when first-hit would be the enemy hero.
9. Presentation; add sludge to HEROES last.

## Risks
- Determinism: w.rng only inside equipped/learned branches; insertion-ordered loops; integer tick schedules; null-check units by id.
- Data to confirm vs 7.41d: hook/dismember pierce debuff immunity (Liquipedia: both yes), Midas XP, Desolator souls on death, Blade Mail return basis, Meat Shield mana/cd (Liquipedia 7.41d: CD 20/19/18/17, mana 65/70/75/80).
- Hook self-lock: Liquipedia formula MaxTravelDistance / HookSpeed * 0.65 = 0.528 s (game data self_stun_duration_percent 65). Keep.
