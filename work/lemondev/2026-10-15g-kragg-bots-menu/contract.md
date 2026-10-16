# Run 2026-10-15 g: Kragg rework, varied bot picks, smarter bots, title and Main Menu

## Request (owner, 2026-10-15)

1. Kragg is too strong. Magnetize becomes his innate (learned at level 1, grows with hero level; innates show when
   hovering Talents): spell amp per attack 0.10% (+0.05 per hero level), up to 4 stacks, debuff 8 s. Overload becomes:
   every 6th/5th/4th/3rd attack, a 200 burst round him: 80% slow for 0.8 s, 60/75/90/105 electric magic damage.
2. Bots must not pick 3+ of one hero on a team: varied picks.
3. Much smarter bots: know items (what, when, counters: magic defence, armor), assess fights, counter-gank when allies
   are near instead of running, use trees / line of sight / fog to escape, and once juked for 2+ s teleport home from
   the fog.
4. Main Menu overhaul: an animated title screen with "by Aljay Leodones"; remade UI with textures made for the game.

## Components (one owner each; builder = this agent; no critic subagents were asked for)

| Id | Component | Files | Acceptance (fixed before results) |
|---|---|---|---|
| K1 | Kragg rework | sim_data.gd, sim_kits2.gd, sim_bot*.gd, hero15_fx.gd, hud.gd, buff_bar.gd, hero_select.gd | tests: innate at level 1, no slot/points, amp formula, 4 Charges 8 s, Overload every N attacks, 200 radius, slow 80% 0.8 s, damage by level |
| P1 | Varied picks | game_settings.gd, net_server.gd | test: 300 seeds, 10 Random slots: no hero twice in a team, none 3x in a match |
| I1 | Magic defence items | sim_data.gd, sim_items.gd, sim_orbs.gd, sim_combat.gd, item_icons.py | test: Dota costs, recipe sum, icons, Fade Cape fade 0.5 s, barrier magic only |
| B1 | Bot item knowledge | sim_bot_items.gd, sim_bot.gd | test: magic answer vs fed nukers, armor vs fed hitters, Reveal Dust vs Sneak Blade; bot games: counter items bought |
| B2 | Counter-ganks | sim_team_ai.gd, sim_bot.gd | test: save called with helpers near, none when far; bot games: saves called and fought |
| B3 | Jukes and fog teleport | sim_bot_tactics.gd, sim_map.gd, sim_bot.gd | tests: juke spots hidden from the chaser much more often than the straight run; TP only when unseen 2 s, hurt, nobody near |
| M1 | Title card | title_card.gd | captures at 1080p and a real 4K window; animation timeline frames; no script errors |
| M2 | Main Menu | main_menu.gd, ui_skin.py (menu art) | captures 1080p / 4K, hover state; all entries reachable; names OK |

Benchmark: none on disk for the menu (no Dota menu frames); looks are builder self-checks, UNVERIFIED for blind review.
Budget: 8 passes per component.
