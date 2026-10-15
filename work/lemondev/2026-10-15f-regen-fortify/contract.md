# Run 2026-10-15 f: regen readout, Rejuvenation Orb, tower shots, Fortify, courier, Fast Forward

## The owner's request (2026-10-15)

> Please also do a BIG IMPROVEMENT and overhaul for the HP and Mana regen in the UI showing their pluses ... It should
> show the Overall combined regen value then also show at the side the original value + bonus value so it is much
> more easier to read.
> Water runes only spawn in the 2 minute mark and 4 minute mark, after that there is no more - also rename and remake
> the model to a purple glowing "Rejuvenation Orb". Also remake the Towers' projectile for both sides, each with their
> own unique projectile + impact effects (not too much, but still beautiful enough). Using Fortify also envelops all
> the player's towers and structures with a divine light and different for the Black Sun team. Fix the Fortify button
> glitching and blinking nonstop when hovered. Using the Fortify with buff all Towers from Tier 2 onwards splash
> attack (300 AoE) and a stacking 50 Physical damage per attack (debuff lasts 15 seconds), also buffs the Towers'
> projectile speed for +50%. Notify all the allies when Fortify is used and who used it. AI will also use Fortify for
> their Towers in danger (if there are no human players). Buff all the Couriers movespeed by +20 per Hero level, then
> the Courier will have Flying Movespeed (ignores collision and flies through walls) the moment the owner hero hits
> Level 6.
> Nerf the skill that forwards time and refreshes cooldown by 100% -> instead percentages, that skill should remove
> flat seconds: 2/3.5/5/6.5 seconds on the cooldown of Basic Skills (Ulti not included and Items)

## Readings (disclosed; the owner can overrule)

* Fortify's tower buff lasts as long as the buildings' protection (7 s). It replaces the old "5 extra targets": with
  splash and stacks on top the towers would be far stronger than asked.
* The stacking debuff: every hit from a Fortified tower (main target and splash) adds a stack to the enemy hit, for
  15 s (each new stack renews the time); each stack adds 50 physical damage to the Fortified towers' attacks on it,
  the hit that adds it included. Splash: full attack damage to enemies within 300 of the target (no buildings).
* Fast Forward keeps its move speed for 5 s; its cooldown part becomes the flat cut.
* "No human players": a team with no human on it (as before).

## Component contracts

| ID | Component | Owned files | Acceptance |
|---|---|---|---|
| R1 | Regen readout | `hud.gd` `_bars`, `_regen_text` | Each bar shows the total per second, large; beside it own + bonus (red minus for a cut); hidden bonus when zero; readable at 1080p and 4K (captures) |
| O1 | Rejuvenation Orb | `sim_orbs.gd`, `orb_view.gd`, tests | Spawns at 2:00 and 4:00 only (test to 20:00); name everywhere; purple glowing model (capture) |
| T1 | Tower shots | `fx.gd` | Each team's tower shot and impact look different (captures); no script errors in a match |
| F1 | Fortify | `sim_world.gd`, `sim_combat.gd`, `sim_const.gd`, `sim_team_ai.gd`, `sim_commands.gd`, `main.gd`, new `fortify_fx.gd`, `hud.gd` (button, notice) | Tests: splash 300, +50 per stack, stacks 15 s, projectile speed x1.5, T2+ only, only while Fortified; notice names who used it to the allies; a bot team uses it on a tower in danger, a team with a human does not; light over every building of the team (captures, both teams); button tooltip steady while hovered (probe) |
| C1 | Courier | `sim_world.gd`, `sim_const.gd`, `hud.gd` text | Speed 290 + 20 x hero level; flies from hero level 6 (test) |
| K1 | Fast Forward | `sim_kits2.gd`, `sim_data.gd`, `sim_bot.gd`, tests | Cuts 2 / 3.5 / 5 / 6.5 s off the target's basic skill cooldowns; not the ultimate, not items (test) |

Benchmark: Dota 2 (glyph, tower attacks, courier, runes) for behaviour where the request does not say otherwise; no
Dota frames on disk, so looks are self-checked, blind review UNVERIFIED. Budget: 8 passes per component.
