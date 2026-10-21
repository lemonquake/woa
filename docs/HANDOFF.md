# Warriors of Aether: handoff

*A Dota 2-style lane battle game by Aljay Leodones. Godot 4.7.2 (Forward+), Blender 5.2 for building models.*

## Status (keep this section current)

**2026-10-22 b: the official border on every new icon (your request).** The new skill, sword and item art is framed
by the Default border pack wherever a skill or item tile is drawn (HUD, shop, talents, Hero Select, ranked pick,
lobby). Two places still drew a bare picture and now use `IconBorder`: the ultimate beside each slot in **Game Setup**
(an `IconFrame`; Random and empty slots show nothing) and the item you drag in the inventory. Evidence in
`work/lemondev/2026-10-22-icons/border/`: suite 352 passed, 0 failed; check.sh clean, Names OK; release export exit 0;
packed icon probe 2079 checks, 0 failures; `game_setup.png`, `exe_match.png` (exe cold start into a match). The buff
bar stays unframed on purpose (status effects, see `docs/CUSTOM_UI.md`). PCK SHA256 `37AD6916...6E8007`. No new names.

**2026-10-22: all new skill/state artwork and the reusable Game Icons skill (your request).** Run
`work/lemondev/2026-10-22-icons/` (contract, audit, source sheets, plan/manifest, review, skill-test, logs, captures).
* Scanned all22 heroes and305 live entries:120 skills/unit traits,180 item/recipe/held entries and5 sword states.
  Every item already had suitable artwork; no item image was needlessly replaced. Built-in image generation made
  **34 images**:27 new hero skills,5 sword states, the updated **Giant Swing** (overhead downward cut) and
  **Death Order** (your correction: "No! Change the Death Order"). That correction revokes the old retained-SVG
  choice; its new image includes an almost-empty life bar and a bright dagger. All125 skill/state identities now
  use painted PNGs, alongside134 item/state images (259 active unique PNGs).
* Blackfire, Thyrandael, Gancho, Lord Kaileh and Dracoxinia have full sets, including their innates and extra keys.
  Sword icons work in the HUD's current-sword inset and BuffBar through the shared UiKit routes. Dragon Leap shows
  traversal, Dragon Hide defensive scales, Pink Sword lightning, Gold barrier, Blue water/root, Red fire and Green
  healing. Suitable existing art is retained; numerical-only changes are audit flags, not automatic replacements.
* **Game Icons**: canonical `lemondev/game-icons/SKILL.md`, installed in
  `C:/Users/Lemon PC/.codex/skills/game-icons/` with automatic invocation enabled. Both AGENTS.md and CLAUDE.md
  require it for future skill/item icon requests. Both skill copies validate; a fresh-agent dry audit followed the
  skill successfully (`skill-test/`). Helpers: `tools/icon_audit.py` reads current route dumps and flags missing
  source art, wrong routes and changed definitions; `tools/icon_art.py --run <run> [--check]` packages only the
  selected run and checks pixels against source cells. It no longer silently selects the20October run.
* Evidence: full suite352 passed,0 failed; source/packed icon probe2079 checks,0 failures; scanner305 entries,
  259 expected unique sources,0 missing images,0 wrong routes. Actual galleries at1080p/4K, HUD/Shop/talents/courier
  captures, source sheets and hashes retained. The independent raw A/B review accepted the new set including
  Death Order; minor Blue Sword root detail is less clear at32px. Detailed build/cold-start results are recorded
  in the run handoff. Existing teardown ObjectDB/resource warnings remain; no new commercial-quality or60FPS claim.
* New player-facing name: **Game Icons** (skill label only). New code/helper names for veto: `STATE_SKILL_FALLBACKS`,
  `STATE_SKILL_ICONS`, `icon_audit`, `read_json`, `gd_map`, `rows_of`, `resource_file`, `png_size`, `old_route`,
  `differences`, `audit`, `chosen`; new icon files reuse existing game IDs. No hero/item names or gameplay numbers changed.

**2026-10-21 b: three new heroes, Gancho, the Nature Whisperer, Lord Kaileh, the Grand Cavalier and Dracoxinia, the
Blue Wyrm (your models and names; kits from research on Dota 2 and League), and every melee hero with moves of its own
(your request: "Melee heroes with swords should not have identical animations").** Run
`work/lemondev/2026-10-21b-three-heroes/` (contract.md, anim, bodies, weapons, logs). The full sheet of the three
heroes (stats at levels 1 and 25, every skill, the five swords, talents, bots, looks, where to change things) is
**`docs/NEW_HEROES_22.md`**.
* **Gancho** (ranged agility, Nature; `src/sim/sim_kits10.gd`): Tree Walk, Root Snare, Seed Bomb, Thorn Barbs, Angry
  Forest. **Lord Kaileh** (melee 200 reach, strength, Earth; `sim_kits10.gd`): Momentum, Lance Charge, Lance Sweep,
  War Banner, Cavalry Charge. **Dracoxinia** (melee strength, Lightning; `sim_kits11.gd`): Royal Scales, Dragon Dash,
  Dragon Leap, Dragon Hide, Rising Slash, Dragon Blade, Change Sword (Pink, Gold, Blue, Red, Green Sword); your
  follow-up swapped her spinning sweep and Dragon Breath for Dragon Leap (W: over trees and cliffs, no damage) and Dragon
  Hide (E: +2-5 armor, +1.5-6 health regen), so she has less burst than before. Bots
  `src/sim/sim_bot22.gd`; chat reactions in `chat_mind.gd`.
* **Bodies**: your three Tripo models on the hero skeleton (`assets/characters/heroes17/gancho.glb`, `kaileh.glb`,
  `dracoxinia.glb`); Kaileh painted steel, leather and gold, Dracoxinia pink and shiny gold (`tools/blender/
  paint_prep.py`). **Weapons**: Kaileh's lance "Lance/Joust Weapon" by Rio.Puntar (CC BY 4.0;
  `tools/blender/kaileh_lance.py`), Dracoxinia's five swords from your "UTTVM Sword Color Pack" by EvesStudio2008
  (CC BY 4.0; `tools/blender/dracoxinia_swords.py`); the sword in her hand follows Change Sword. **Thyrandael's wings**
  now have their own bones and beat as he flies (`src/game/body_sway.gd`).
* **Own animations** (`work/lemondev/2026-10-21b-three-heroes/anim/hero_clips.py` -> `tools/blender/mocap_clips.json`,
  `ModelCatalog.MOCAP`): Ser Emelrich, Araki, Blackfire, Thyrandael and the three new heroes each have their own idle,
  run, attacks, ability moves, hits and deaths; Burak, Ghorman, Feran and Azrael their own idle or run and attacks;
  Caziel his own run (his dagger stabs were already his alone). Ezee keeps the old great sword set, which nobody else
  uses now; a hero's own ability clip plays for that ability (`"casts"`), Kaileh and
  Dracoxinia play their charge clip while they charge or dash. Eight of the new attacks landed 1.1-1.9 s in and were
  trimmed to land at 0.5 s.
* **Effects** (`src/game/hero22_fx.gd`): vines, seeds, the angry forest, dust and sparks of the charges, six ghost
  riders (Kaileh's own body, see-through), the War Banner on its pole, the sword swaps and strike powers, the breath in
  the sword's colour, the rising cut. Gancho's thorns fly and stick.
* **New names for your veto**: Tree Walk, Root Snare, Seed Bomb, Thorn Barbs, Angry Forest, Momentum, Lance Charge,
  Lance Sweep, War Banner, Cavalry Charge, Royal Scales, Dragon Dash, Dragon Leap, Dragon Hide, Rising Slash, Dragon
  Blade, Change Sword, Pink Sword, Gold Sword, Blue Sword, Red Sword, Green Sword; code: Hero22Fx, BodySway, SimKits10,
  SimKits11, SimBot22, kaileh_ghost, war_banner.
* **Not done**: no horses for the ghost riders (none downloaded); no fresh critic, no Dota benchmark. Dracoxinia has
  no tail (your model has none, as you meant).
* **Also fixed after the interrupted session**: nine downloaded Mixamo clips were left in the browser's download folder
  (moved into the library); the bot chat file had a parse error; eight attack clips landed too late (trimmed); the
  HUD portrait could show a ghost rider (riders now stay off the portrait layer); baked portraits of Kaileh and
  Dracoxinia hide their long weapons (`"portrait_bare"`).
* Evidence (logs and shots in the run folder): full suite 352 passed, 0 failed (`logs/tests2.txt`); `sh tools/check.sh`
  no script errors, Names OK; body collision fixed for every hero (`logs/collide_fix2.txt`, Dracoxinia again after
  the swap: worst 85.6 cm -> 3.3 cm, Dragon Leap 24.2 -> 3.3 cm in 3 frames); joins for the three new heroes: 5 of 115
  over the 12 deg limit, worst 13.3 deg (`logs/joins.txt`); live captures of Cavalry Charge with its riders, the
  sword change and Gold barrier, Gancho's forest, seed tree and root, Dragon Leap (`shots/`); bot duels: Dracoxinia
  vs Gancho and vs Kaileh run clean, her bots leap 5-7 times in 12 minutes (`logs/duel_drac2.txt`); the Windows export
  rebuilt (`build/WarriorsOfAether.exe`, pack 862 MB) and the pack cold-starts into a match with no script errors
  (`shots/pck_match.png`). Not verified: no critic, no Dota benchmark, the exe's menus not clicked through.

**2026-10-21: two new heroes, Blackfire, the Unfallen and Thyrandael, the Forsaken Seraph (your kits and models),
barriers, Forums moved into the Ranked bar, 25% shorter matchmaking (your requests).** Run
`work/lemondev/2026-10-21-blackfire-thyrandael/` (contract.md, handoff.md, logs, shots, ui, bodies).
* **Blackfire** (dark, melee, strength; 3 / 1.1 / 2.9 a level; `src/sim/sim_kits8.gd`): **Underworld Presence** (a
  death within 1000 heals him 4%, a hero's 10%; a black soul with a violet core flies into his chest), **Sacrificial
  Grip** (both stunned 2-2.6 s, 25% of the target's current health as pure damage, never lethal; then both -30% attack
  damage for 2 s; his Undead go for it), **Rise Up** (bodies within 1000 rise as his **Undead** for 20 s, his to
  select and command; the roar's aura raises what dies near him for 20 s; not ancients, heroes, buildings, summons or
  tamed beasts), **Fiend Edge** (10-25% for a 2x crit; a crit heals every ally within 800 by 20-35% of it), **Unfallen**
  (a killing blow drops him for 3 s, he rises with full health and +25% damage, armor, move and attack speed for 3 / 4 /
  5 s, then dies for good with a blast that throws every unit within 400, allies too, 300 away; a slam into a wall,
  tree or unit stuns 0.5 s; the kill goes to whoever dropped him).
* **Thyrandael** (light, melee, intelligence; 2.8 / 2 / 4 a level; `src/sim/sim_kits9.gd`): **Divine Touch** (every
  spell adds an All-damage Barrier charge as large as his intelligence), **Holy Beam** (up to 7 s; right-click turns
  him and the beam, 60% slower turning; S stops it and the HUD says so: "Right-click to turn the beam · Press S to
  stop"; 50-110 magic and 30-60 mana burn a second, 30% slow in it), **Quick Flash** (500 around him, 30-90 magic, a 10 s
  mark; each mark adds 10-25 to the next Flash; it does not stop the beam), **Spirit Step** (there at once, 400-940;
  silence 1-2.2 s and 40% slow 1 s round where he lands), **False Judgement** (a charge per 300 / 250 / 200 damage taken,
  up to 10 / 11 / 12, circling over his head as small suns; the blast blinds, slows and burns by the share of charges;
  range and cooldown follow the charges).
* **Barriers** (new, `src/sim/sim_barrier.gd`): Magic, Physical and All-damage barriers are pools that take damage of
  their kind after armor and resistances, before health (All-damage takes pure too). Health bars draw them past the
  health (All-damage gold, Physical orange, Magic blue), the HUD shows "+N", the buff bar names them, and a soft shell
  in the barrier's colour wraps the unit. The Shield Orb's and Fade Cape's shields show on the bars too.
* **Bodies**: your two models on the hero skeleton with their swords as weapons (`assets/characters/heroes17/
  blackfire.glb`, `thyrandael.glb`, `assets/weapons/blackfire_sword.glb`, `thyrandael_sword.glb`; build script
  `work/lemondev/2026-10-21-blackfire-thyrandael/bodies/build.sh`). Thyrandael's wings and halo are locked to his chest
  and head; his sword is shrunk to 1.49 m (full size cut through the wings). Collision 0 cm in every clip after the fix
  (worst before 48 / 79.5 cm); joins: Blackfire 0 failures, Thyrandael 2 (idle and run into his cast, left hand 17.7
  deg). Not covered: the blade can pass through his wings in big swings (the collision check does not include wings).
  Skill icons drawn in `tools/item_icons.py` (dark and new "holy" backdrops); portraits baked.
* **Bots** (`src/sim/sim_bot21.gd`): Blackfire grips when someone can punish the held target (an ally, two Undead, a
  tower) or for the kill, grips enemies hitting a low ally, raises bodies in fights, pushes and camps, and fears death
  less with Unfallen up. Thyrandael spends charges at half full (any for a kill), steps in to silence, flashes enemy
  heroes in reach (keeping the beam's mana), beams held or lined-up targets, turns the beam onto the best target and
  flashes during it, stops it to run; escapes with Spirit Step. Every bot steps out of an enemy beam. Builds, roles,
  talents, spell damage estimates. Chat: enemies react to Blackfire getting up ("why is he still alive", "back off he
  blows up"), to a raised crowd and to being judged; the online chat and forum writers get a "how it plays" line for
  each (`SimBotKits.HOW_TO_PLAY`).
* **Forums** are now a tab in the Ranked top bar (Play, Profile, Leaderboard, Players, **Forums**, Guilds), the same
  forum inside the Ranked screen; the main menu plate is gone.
* **Matchmaking is fast now** (your follow-up: "this aint even a real online matchmaking so why the long waits"; "no
  failed accepts in a row"; "requeueing means 50% faster finding"; `src/core/matchmaker.gd`): a search takes 2-7 s, the
  bots accept within about 2 s, a bot fails an accept in about 1 offer in 50 (was about 1 in 4 on your ladder, which is
  what kept cancelling your matches), a failed accept goes back to the queue as soon as everyone else has accepted
  (no waiting out the 15 s timer), the re-queue searches twice as fast, and after one failed accept nobody fails again
  until you are in a match or leave the queue (declining keeps that). Measured on a copy of your ladder (4092 MMR, 400
  offers, `tests/tools/mm_probe.gd`): 3% of offers failed, never two in one queue, Find Match to everyone accepted
  8.8 s on average, 17.8 s at worst. Test `test_matchmaker_failed_accept`. The estimate on the Play tab matches.
* **Hero portrait lit the same by day and night** (your follow-up; `src/ui/hud.gd` `_portrait`): a camera's cull mask also
  culls lights, so the HUD portrait never saw the sun or moon and was lit by the world's sky alone, which darkens at
  night. It now has its own studio key, fill and rim lights (turning with the portrait camera; only the portrait camera
  sees them, the battlefield camera skips their layer) and its own daytime sky for ambient light and metal
  reflections. Captures `shots/portrait_compare.png` (Thyrandael day, night; Blackfire night), `portrait_azrin_night.png`,
  `export/exe_night.png`. The other portraits (top bar, kill feed, menus) are baked pictures and do not change at night.
* **Both heroes checked again** (your follow-up): four bot games with the two heroes on each side
  (`logs/kit_casts2.log`, `kit_casts3.log`): every skill cast by bots, and every passive fired (per game: Unfallen 3-5
  times, Fiend Edge 45-57 crits, Underworld Presence 280-370 heals, 76-127 Undead raised, Divine Touch 150-230 barriers,
  76-124 False Judgement charges). Thyrandael bots are strong (27/1, 17/1, 10/2, 15/4); Blackfire bots fight and assist
  but take few kills (0/5/13, 6/6/19, 1/8/9, 1/7/18 in these games, where every bot is sent mid; in a laned 5v5 he went
  12/4/27 as carry). Live captures of the two skills not seen before: `shots/unfallen_sheet.png` (falls, rises 3 s later,
  fights 5 s, dies with the blast) and `shots/judgement_sheet.png` (12 charges over his head, the blast). Capture
  options added: `--charges=N` and `--cast=die@F`.
* Evidence: tests `test_blackfire_thyrandael_data`, `test_barrier_kinds`, `test_blackfire_grip`, `_rise_up`,
  `_presence_and_edge`, `_unfallen`, `test_thyrandael_touch_and_flash`, `_holy_beam`, `_step_and_judgement`; full suite
  before the bodies landed 341 passed, 1 failed (the model check waiting for them, `logs/tests1.log`); after them
  340 passed, 2 failed (`logs/tests2.log`): `test_ladder_careers` and `test_ranked_upgrade_careers` read a random
  ladder and were flaky; they now build a fixed ladder (`Ranked.seed_override`, tests only), and the suite then passed
  342 of 342 (`logs/tests3.log`); every new test passes;
  `sh tools/check.sh` no script errors, Names OK; bot games (`logs/kit_casts1.log`: every skill cast by bots;
  `bot_game_a/b.txt`: the side with the two heroes won the kills 58-31 and, traded, 48-34); captures in `shots/`, `ui/`;
  the Windows export rebuilt, a cold start into a match with Blackfire has no script errors (`export/exe_match.png`).
  Not verified: no fresh critic, no Dota benchmark, no 4K capture, the exe's menus not clicked through.
  Final state (after the follow-ups): suite 343 passed, 0 failed (`logs/tests5.log`); `sh tools/check.sh` Names OK;
  ranked_probe 51/51 twice; export rebuilt 2026-10-21 06:27 (exit 0), cold start into a night match with Thyrandael
  has no script errors (`export/exe_night.png`).
* Known, not from this run: two bots got stuck at (-5065, 5308) in one game (the same spot as in run 2026-10-19 c).
* Chosen where open (veto any): base attributes and attack timing (melee strength / intelligence templates: Blackfire
  25 / 15 / 18, 30-36 damage, 2 armor, 300 speed; Thyrandael 21 / 16 / 24, 26-32, 1 armor, 305); Spirit Step 80 mana,
  stomp 300; False Judgement 100 / 125 / 150 mana, radius 400, range never under 300; Holy Beam 150 wide; Divine Touch
  up to 3 charges, gone 12 s after his last spell; bodies can be raised for 8 s after death; Undead give no gold or
  experience; Fiend Edge heals Blackfire too; Unfallen rises with full health and has no cooldown; Quick Flash marks
  have no cap (as written; a cap is easy if it is too strong); barrier colours; talents (Blackfire: -2s Grip cooldown /
  +2% Underworld Presence heal, +10s Undead time / +35 Damage, +10% Fiend Edge chance / +15% Fiend Edge heal, +3s
  Unfallen time / +1s Grip stun; Thyrandael: +30 Holy Beam damage / +2 Mana Regen, +40 Quick Flash damage / +250 Spirit
  Step range, +2 Divine Touch charges / +1s Spirit Step silence, -50 damage per False Judgement charge / +150 False
  Judgement radius).
* New names (veto any): **Undead** (and "Undead Melee Creep" etc.), **Weakened**, **Holding On**, **Fallen**, **Last
  Life**, **Flash Mark**, **Holding the Beam**, **Silenced**, "Right-click to turn the beam · Press S to stop", "No
  charges yet", "Target is immune to spells", **All-damage Barrier** / **Physical Barrier** / **Magic Barrier** (your
  words), the talents above, Hero Select roles "Durable, Initiator, Pusher" and "Nuker, Disabler, Escape" and both
  stories. Code: `SimKits8`, `SimKits9`, `SimBot21`, `SimBarrier`, `BarrierBar`, `Hero21Fx`, `commands`, `catch_death`,
  `untargetable`, `atk_crit_key`, `last_crit_key`, `HOW_TO_PLAY`, `QUEUE_GRACE`, `ONLINE_GRACE`, `seed_override`, `embedded`, `close_dialog`, fire ramp
  `underworld`, icon backdrop `holy`; weapons `blackfire_sword`, `thyrandael_sword`; tools
  `tools/blender/blackfire_sword_roll.py`, `tools/blender/thyrandael_rigid.py`.
* Credits: both models credit the artist profile (sketchfab.com/s8819296); the model page links were not in the
  downloads, so add them if you have them.

**2026-10-20 e: accounts, quick stats in the hero pick, players who know a pro when they see one, a new Players tab
with friend chat, destroyed buildings that leave nothing, Araki's ghosts and a new Giant Swing (your request).** Run
`work/lemondev/2026-10-20e-social-accounts/` (handoff.md, captures).
* **Accounts** (`Ranked.create_account`, `login`, `accounts`; `src/ui/accounts_panel.gd`): Ranked > **Accounts** (top
  bar) or right-click your chip > Accounts. Up to 20 accounts on the same ladder; a new one starts at 1,500 MMR with a
  fresh profile. **Log in** to any of them, **Log out** (then pick one). The accounts you are not on stay on the
  leaderboard and can be opened like anyone ("Your account · Last on ..."); the ladder never plays them and bots never
  write as them. Logging in swaps the ids in the save and the forums, so your walls, posts and friends follow each
  account, and every ladder player remembers each account apart. Each account has its own uploaded picture. On the
  Forums you can **reply to anyone, yourself included** (another of your accounts' posts, or your own).
* **Hero pick quick stats** (`src/ui/player_peek.gd`): rest the mouse on any player in the pick: rank, MMR and place,
  record and streak, the last 5 games (hero, won or lost, K/D/A, MVP), best heroes (games, W-L, win rate, medal),
  averages (K/D/A, KDA, last hits and gold a minute), MVPs / Rampages / Triples, and for ladder players what they are
  like and think of you.
* **They know a pro** (`ProfileTalk.elite`, `_pro_sit`; lines `pf_pro_*` in `profile_lines.gd`): a profile far past
  its rank (yours is) gets its own reading everywhere players look you up (the pick, match chat, walls, the online
  writer, forums): awe ("{mvpr}% mvp rate. thats not human"), **go pro**, teammates root for you ("carry us king", "im
  so proud to be on ur team"), enemies are honoured ("honored to lose to u"), show-offs compare you with the real top
  of the ladder ("{top} is top 1 and has worse numbers than u", "aetherium+ players avg like {topkda}"), rough ones
  hate ("stat padder", "overrated"), trolls troll ("bro bought the account", "report for scripts"). More teammates look
  you up in the pick when you are a pro. Forums: new threads about you ("Is {you} the best player on the ladder?",
  "{you} should go pro", "{you} is overrated, change my mind").
* **They know the ladder** (`Ranked.ladder_card`, `Ranked.named_in`, `SimWorld.ladder`, `ChatProfile.ladder_ask`):
  bots get the top 20 at match start and answer "who is top 1", "top 10?", "best player", or a question naming anyone
  on the ladder ("is dealer2007 good?"), with the facts and their take, in match chat, the pick and friend chat.
* **Players tab** (rebuilt): **Friends** with counts (friends, online, in a match, offline, requests), filters (All,
  Online, In a match, Offline, Requests), unread counts and a **Chat** button per friend; the middle panel is **Chat**
  (the conversation, typing, Send, your conversations) or **Ladder activity**; the right is **Online now**, **Recent**,
  **Top 20** and **Find player** (anyone by name). **Friend chat** (`src/core/friend_chat.gd`): friends answer what you
  write by its meaning and by who they are (online in seconds, in a match after it, away when back), and now and then
  write first (your last game, a duo, their streak). New messages show as a notice anywhere on the Ranked screen.
* **Destroyed buildings** leave nothing: the ground opens for walking and paths (a building still standing keeps its
  own; trees and cliffs stay), and the rubble sinks out of sight. **The mid tier 3** stood at the head of the mid stairs
  (Black Sun's, and Ancient Light's mirror): moved beside the lane, the stairs' top is open (forest unchanged).
* **Araki's Ghosts of the Will**: they stopped at the edge of reach each tick and a runner stepped out of it every time,
  so they trailed and never struck. Now they fly at **800** and strike the moment they reach the target, moving or
  not, keep their target out of sight (not through invisibility), and vanish in a puff (no death fall).
* **Giant Swing** (Ser Emelrich): wind-up **1.8 / 1.6 / 1.4 s**, stun **2.5 / 3.5 / 4.5 s**, damage 250 / 375 / 500.
  Through the wind-up he has **Spell Immunity**: debuffs on him are removed, none lands (piercing ones neither), enemy
  pushes and pulls are dropped, nothing stops the swing; he looms 30% larger under a gold shell, and the blow shakes
  the ground. **Your list**: `SWING_GUARD_PIERCE` at the top of `src/sim/sim_kits5.gd` (empty): put modifier ids
  ("stunned", "hex", "silenced") or ability / item ids ("shuriken_hook") there and those get through (and may break
  the swing). Every bot steps out of the red cone (or Overhead Cut's line) once it sees it.
* Evidence: tests (the new `test_ranked_accounts`, `test_profile_pro`, `test_araki_ghosts_hit_runners`,
  `test_emelrich_giant_swing_guard`, `test_bots_dodge_giant_swing`, `test_destroyed_building_opens_ground`, and in
  `test_chat_profiles_in_match`), captures in the run folder. Not verified: no fresh critic or Dota benchmark, no 4K
  capture, the Accounts panel and friend chat were not clicked through by a probe. 2026-10-21: full suite 333 passed, 0
  failed; `sh tools/check.sh` no script errors, Names OK; the Windows export rebuilt (`build/WarriorsOfAether.exe`), a
  cold start into a match has no script errors (`export/exe_match.png` in the run folder).
* Chosen where open (veto any): Giant Swing damage (above); its cooldown stays your 20 / 15 / 10 s; 20 accounts at
  most; a "pro" = 30+ games and KDA 7+ with 2.5 or fewer deaths a game, or MVP in 35%+ with KDA 5+; friend answer
  times 3-8 s / 40-150 s / 4-25 min.
* New names (veto any): **Accounts**, **Log in**, **Log out**, **Logged in**, **New account**, "New account name",
  "Log in to this account", "N of 20", "Your account", "(your account)", "Another of your accounts", "Logged out.
  Choose an account to log in."; Players **Friends**, **Online**, **In a match**, **Offline**, **Requests**, **All**,
  **Chat**, **Ladder activity**, **Online now**, **Recent**, **Top 20**, **Find player**, **Send**, **Back**, "Write to
  X (Enter)", "X is typing...", "Say hi to X."; pick card **Last 5 games**, **Best heroes**, **Averages**, **MVPs**,
  **Rampages**, **Triples**, "#N on the ladder", "Right-click for the profile and more". Code: `AccountsPanel`,
  `PlayerPeek`, `FriendChat`, `FriendCounts`, `ChatHead`, `Bubble`, `SWING_GUARD`, `SWING_GUARD_PIERCE`, `guard_sweep`,
  `pierces_guard`, `dodge_windups`, `open_building`, `GROVE_SPOT`, `ladder_card`, `named_in`, `ladder_ask`, `elite`,
  `elite_facts`; save fields `accounts`, `acc`, `account`, `last_login`, `yous`, `chats`, `unread`, `typing`,
  `chat_first`; line kinds `pf_pro_awe`, `pf_pro_gopro`, `pf_pro_compare`, `pf_pro_root`, `pf_pro_vs`,
  `pf_pro_respect`, `pf_pro_hater`, `pf_pro_troll`, `pf_wall_pro`, `pf_wall_pro_hate`; forum kind `you_pro`; chat
  intent `ladder_top`.

**2026-10-20 d: smoother interface everywhere, and the official icon border (your request: "the Talent UI ... doesn't
fucking close when you click away", "create our Official and Default BORDER for item/skill icons ... replaceable at
any time").** Run `work/lemondev/2026-10-20d-ui-smooth/` (handoff.md, captures, probe logs). **Why: the owner is
opening the game to custom UIs, free and paid. `docs/CUSTOM_UI.md` is the guide for every agent (the pack pattern,
the border reference, rules, roadmap, what paid needs).**
* **Popups close the way you expect** (an audit of every popup, menu and screen found the talent tree was not alone):
  * Talent tree: closes on a click anywhere outside it (world, minimap, top bar, the rest of the panel), on Esc (which
    no longer opens the pause menu behind it) and when you select another unit. Clicks in its gaps no longer move the
    hero; its invisible click area after selecting a creep is gone; an ally's tree is read-only (a click there used to
    learn the talent for your own hero).
  * Item menu: the mouse wheel no longer closes it. Pause menu: dims the game, a click outside it resumes, and game
    keys (Enter, hotkeys) wait while it, Options, the MVP or the end screen is up; Esc during the MVP screen no longer
    opens a pause menu under it. Debug panel: Esc closes it.
  * Options, Credits, multiplayer dialogs, the profile overlay: a click outside closes them. Profile: Esc closes
    Compare, then Edit profile (as Cancel), then the overlay; the overlay and right-click menus now close with their
    screen (they used to stay up after a scene change). Forums: the New post dialog dims and blocks the list behind
    it; a click outside puts it away and keeps your draft (Cancel throws it away). Multiplayer: Esc cancels Connecting.
  * Right-click player menu: a right click elsewhere closes it and opens the next one at once (it took two clicks), a
    left click outside closes it without pressing what is underneath, the wheel leaves it open.
  * Esc goes back on Hero Select, Game Setup, Hero Creator, Ranked (not while a match offer is up) and Hotkeys. The
    main menu no longer reacts to arrows / Enter behind Options or Credits.
* **Screens fade** instead of cutting (0.12 s out, 0.2 s in, clicks wait meanwhile); every way into a match now shows
  the loading screen (Hero Creator's Play, multiplayer, Play again used to freeze on the old screen). Overlays and menus
  fade in (0.09-0.14 s). Options > Game > **Menu animations** turns all of it off. Every button clicks (several were
  silent: Credits, Hotkeys, Hero Creator, Debug, the Watching panel).
* **Icon borders** (`src/ui/icon_border.gd`, `src/ui/icon_frame.gd`, generator `tools/icon_borders.py`): border packs
  are folders with `border.json` and PNGs, in `assets/ui/borders/<id>/` (shipped) or `user://borders/<id>/` (added
  later: bought, downloaded or made; a user pack with a shipped id replaces it). The format is documented at the top of
  `tools/icon_borders.py`. Kinds: skill (active), passive (passive and innate), item, optional ultimate; a missing kind
  falls back to skill. **Default**: a gold bevelled rim with cut corners and a bright inner line for active skills; a
  sunken bronze rim with round corners for passives (as Dota tells passives apart); a slimmer gold rim for items. A
  soft light-from-above sheen sits under each. **Plain**: a thin dark line. Options > Game > **Icon border** picks the
  pack (preview beside it) and it changes at once. Every skill and item icon goes through it: HUD abilities, innate,
  unit skills, inventory, backpack, stash, courier, To Buy, the whole shop, talent tree, Hero Select, the ranked pick,
  the multiplayer lobby. Item art now fills its slot (cropped to the slot like Dota's tiles; backpack slots keep a
  square). Preview any pack: `godot --path . -s tests/tools/icon_border_sheet.gd -- --out=x.png [--scale=2]`.
* Evidence: `ui_smooth_probe.gd` 34/34 through real input events (talents, item menu, shop, pause, Options, fades,
  Esc on screens, player menu, border packs incl. a user:// pack); `ranked_probe.gd` 51/51; `item_flow_probe.gd` 13/13
  (its 150-gold step now zeroes reliable gold: passive income pushed it past 155 before this run); captures at 1080p
  and a 2x (4K-scale) border sheet; names OK; full suite 327 passed, 0 failed (one stale Switch Boots
  check updated: it expected the old .svg); the Windows export rebuilt and its pack shows the new frames in a match. The real 4K window was not captured
  (1080p monitor); Dota itself was not captured as a benchmark.
* New names (veto any): options **Icon border**, **Menu animations**; border packs **Default**, **Plain**. Code:
  `IconBorder`, `IconFrame`, `icon_borders.py`, `icon_border_sheet.gd`, `ui_smooth_probe.gd`, options keys
  `icon_border`, `ui_motion`; `Options.go`, `UiKit.pop_in`, `UiKit.is_esc`, `blocks_input`, `close_talents`,
  `over_talents`, `overlay_mode`, `_hide_dialog`, `_back_btn`.
* Also: **passive skills show no hotkey** (HUD skill bar and Hero Select; your request mid-run). Backpack slots are
  now smaller tiles (48 x 36) and the Teleport slot one tile (Deliver got the room), so every item is one frame with
  its art filling it; hotkey tags on items are slimmer. Top-bar hero tiles glow under the mouse. The talent tree
  shows the moment you click (it waited for the next 20 Hz redraw).
* Blind review (fresh critic, same game state, raw crops): pass 1 invalid (my capture did not match the baseline's
  state), pass 2 new preferred but REJECT (frame inside a frame in the backpack and Teleport slot: fixed), pass 3 new
  preferred, **PASS**; leftover note: the innate icon's frame is thin at 28 px.

**2026-10-20 c: generated skill and item artwork (owner's request).** All 17 heroes audited against current
SimData and implementation, including innates and extra skills; all 176 item records (129 items, 47 recipes),
held states and neutral passives inspected. Built-in image generation produced 227 distinct 256px PNGs;
226 are used: 92 skill/unit-trait icons and 134 item/state icons in `assets/ui/art/`. The owner chose to keep
Death Order's existing SVG after its low-health cue failed the 32px review twice; its generated candidate is
preserved outside the game in the run's `quarantine/`. Recipes share a scroll. Switch Boots
have three attribute images; empty Flask is separate. Original SVGs remain recoverable fallbacks.
* `UiKit` routes the HUD, Hero Select, Shop, inventories, tooltips, buff bar, unit panel and teleport through
  the new art. No gameplay values or existing names changed. `tools/icon_art.py` packages the original sheets
  according to the explicit cell plan and writes a SHA-256 manifest; `--check` validates packaging/uniqueness.
* Audits, source sheets, prompts, cell mappings, baseline and final galleries, reviews and build evidence:
  `work/lemondev/2026-10-20-icons/`. All 227 resources passed the runtime probe's 1,806 checks. Full suite:
  327 passed, 0 failed. The suite exposed a pre-existing snapshot omission: a global `prof` exclusion dropped
  ChatProfile along with timing counters. It is now scoped to SimWorld; targeted snapshot determinism and
  restored references/state pass, as do match-profile and profile-talk tests. Some existing test/UI teardown
  resource leaks remain; these are recorded in the run handoff.
* Fresh critics preferred the generated sets over the project's old sets. Pass 2 adds large ascending Blast Rod
  pips; pass 3 gives Beast Form a half-human/half-wolf face, Break Strike a broken passive-power emblem and Weapon
  Grab a sword visibly leaving an open hand. These three passed the focused 32px normal/dimmed review. Death
  Order stopped at the skill's plateau rule; the owner's explicit choice is recorded in the contract.
  Commercial reference inspected (official Dota hero page),
  but no matched commercial A/B superiority claim. Final evidence/state is in this run's `handoff.md`.
* New player-visible names: **none**. New code/diagnostic names: `ABILITY_FALLBACKS`,
  `NEUTRAL_SKILL_FALLBACKS`, `UNIT_SKILL_FALLBACKS`, `UNIT_SKILL_ICONS`, `_skill_paths`, `icon_path`,
  `_item_fallback`, `_art_icons`, `icon_art.py`, `icon_art_probe.gd`, `icon_art_dump.gd`, `icon_art_focus.gd`, `bottle_empty`,
  `neutral_crit`, `neutral_splash`, `ancient`, `flying`, `true_sight`, `sight`, `backdoor_protection`, `fortify`.

**2026-10-20 b: the social makeover: a new Profile (averages, LH/D, KDA, favourite lanes, First Bloods, Triple Kills,
Rampages, MVPs, match history, a wall, View As, Compare), MMR by how well you play (23 to 41), AI players who read
your profile and each other's (your last five matches, your averages) and react kindly, toxically or as trolls,
right-click menus on every player, and a generated themed skin for Ranked, Profile, Players and Forums (your
request).** Run `work/lemondev/2026-10-20-profile/` (contract.md, handoff.md; captures `ui/`, before `before/`).
* **Your record** (`src/core/career.gd`): every match you finish now counts on your profile, ranked or not (Play vs
  bots too): K/D/A, last hits and denies, gold and experience a minute, hero and building damage, healing, wards, the
  lane you played (watched 0:30-10:00), first blood, double / triple / ultra kills and rampages (every kill past five
  is another rampage, as in Dota), MVP. Matches before today were never recorded (your 8 ranked ones kept K/D/A only),
  so your First Bloods, Triple Kills and Rampages start at 0: **Edit profile > Earlier record** adds your own count
  from before (your 20+ / 30+ / 12) to the totals.
* **MMR by performance** (`Career.perf`, `Career.mmr_change`): a win gives **23** (a carried game) to **41** (a perfect
  game: no deaths, 10+ kills, 10+ assists, 150 last hits; a support's wards, healing and assists may stand in for last
  hits); a loss takes 41 (poor) to 23 (great); leaving takes 41. Score = 25% kills/10 + 20% assists/10 + 30% (1 -
  deaths/10) + 25% last hits/150. The end screen shows "Your game: N%". The other nine move by their own games; the
  ladder's own rounds even out gains and losses so it does not drift (tested: average MMR within 60 over 60 rounds).
* **AI players' careers** (`Career.estimate`): all 300 get lifetime numbers from their games, skill and main role
  (top players: 400-600 MVPs, hundreds of triple kills, dozens of rampages; low ranks with 100+ games have MVPs too),
  commends, and their saved matches get farm, lanes and GPM. Ladder matches now record all of it. Your save upgrades in
  place on first load (version 5); nobody's MMR or record changes.
* **They read profiles** (`src/core/profile_talk.gd`, lines `src/core/profile_lines.gd`, match chat
  `src/sim/chat_profile.gd`): what anyone sees (averages over 20 matches, the last five with K/D/A, LH and MVP, the
  form, streak, MVPs, rampages, triples, first bloods, favourite lane, abandons). Kind players acknowledge good games
  ("saw ur 12/1/9 last game, gj") and cheer up bad ones; fair ones say what they see; rough ones flame bad averages
  ("9.5 deaths a game avg, pls dont", "lost 4 of ur last 5") and call good ones smurfs ("7/1/10 avg at expert 2?
  smurf"), now and then giving credit; show-offs compare; trolls troll even a great profile ("ur mvps are fake"). What
  they already think of you shades it. Where: the hero pick (a teammate or two looks you up; one reads an enemy or a
  teammate, who answers), the match start (teammates in team chat, an enemy in all chat; bots look each other up too),
  every few minutes your game against your averages ("9 deaths, right on ur avg", "whos playing on ur account"),
  "check my profile" / "my stats?" / "check ur profile" in any chat, forum replies to you (60% when you brag, ask, rant
  or trash talk), and the online writers (match chat and Forums) get your whole profile in words.
* **Profile walls**: after a match some of the nine look you up and leave a comment (+rep / -rep, "smurf reported",
  "talks a lot for 2/9/1"); players drop by while you are away (your **Visitors**, private). Write on anyone's wall and
  they answer (rude words cost their liking). Ladder players' walls have comments from the players they met.
* **Profile page** (`src/ui/profile_page.gd`, the Ranked Profile tab and an overlay anywhere else): banner (picture,
  name, status, presence, labels, what they think of you; trophies MVPs, Rampages, Triple Kills, First Bloods,
  Commends; 3D rank emblem, MMR, place, the way to the next rank); **Averages** (Last 20 / All matches: K/D/A, KDA,
  LH / DN, LH a minute, GPM, XPM, hero damage, win rate; favourite lanes as bars); **Match history** (All / Ranked /
  Unranked, the last ten as W/L plates, badges for MVP, Rampage, Triple Kill, First Blood; click a match for every
  number, right-click for more); **Wall / Heroes / MMR / Visitors**. Yours: **Edit profile** (name, picture, earlier
  record) and **View As** (Yourself, Public, or a friend / a player you met: their read of your profile and what they
  think of you; behaviour score, reports and visitors stay private). Theirs: Add friend, **Compare** (side by side, the
  better number lit), Write, More.
* **Right-click any player** (`src/ui/player_menu.gd`): leaderboard, top of the ladder, Players tab (friends, recent,
  activity, online), the match offer, the hero pick, your chip, profile walls and visitors, forum threads and authors:
  View profile, Match history, Compare with me, Write on profile, Add / Remove friend, Accept friend request, Commend
  (once a day), Report (once a day, -60 behaviour), Block (hides their posts and comments), Copy name. Forum names and
  pictures open the profile on a click.
* **The skin** (`tools/ui_skin_social.py`, run by `tools/ui_skin.py` too): the page backdrop, top bar, profile banner,
  ornate panels, stat cards, list rows (plain, hover, won, lost, yours, gold), the menu and its highlight, tabs, chips,
  the avatar frame, and 29 relief icons (medallions and bare gold glyphs) for every stat. Ranked (all tabs), the hover
  card (now with averages and trophies), Forums and the profile use it.
* Chosen where open (veto any): the MMR score weights above; ladder rounds scaled to zero sum; a comment after a match
  from up to 4 of the nine (25-50% each, more after flames or trash talk); a visit about every 90 minutes away (4 at
  most); estimates: MVP rate 4-24% of games by skill and role, commends 3-30% by manners; a lane counts from 60 seconds
  near it; profile reads: "good" = MVP / 3+ KDA with 8+ kills / a rampage last match, 4 of 5 won, 3.6+ KDA with 5.5 or
  fewer deaths, MVPs in 18%+ of games, 3+ rampages, 6+ LH a minute, 10+ first bloods; "bad" = 10+ deaths last match, 4
  of 5 lost, 8+ deaths a game, under 2.4 LH a minute (cores), under 1.9 KDA at Commander or higher, 2+ abandons;
  "smurf" = new or low-ranked with 4+ KDA and 60%+ wins lately.
* New names (veto any): **Back to Dashboard** (your words), **Edit profile**, **View As**, "View As: Yourself", **Public**, "Public: anyone", "As X",
  "As X (friend)", **Back to my view**, "Viewing as X: this is what they see", "Public: this is what any player sees",
  **Averages**, **Last 20**, **All matches**, **K / D / A**, **KDA**, **Last hits / denies**, **Last hits a minute**,
  **Gold a minute**, **Experience a minute**, **Hero damage**, **Win rate**, **Favourite lanes**, lanes **Safe lane**,
  **Middle lane**, **Off lane**, **Jungle**, **Roaming** (short **Safe**, **Mid**, **Off**, **Roam**), "X player",
  **Match history**, **All**, **Ranked**, **Unranked**, "Last N", "N won, N lost", **Wall**, **Heroes**, **MMR**,
  **Visitors**, "Write on your wall (Enter)", "Write a comment (Enter)", **Post**, trophies **MVPs**, **Rampages**,
  **Triple Kills**, **First Bloods**, **Commends**, **Compare**, **Write**, **More**, **Close**; menu **View profile**,
  **Match history**, **View As someone else**, **Compare with me**, **Write on profile**, **Add friend**, **Remove
  friend**, **Accept friend request**, **Commend**, **Report**, **Block**, **Unblock**, **Copy name**, "today", **Show
  details**, **Hide details**, **Copy this match**, "X ranking"; Edit profile **Name**, **Picture**, **Upload a
  picture**, **Use my hero**, **None**, "Earlier record (matches before 20 October 2026)", **Save**, **Cancel**; match
  details **Length**, **Net worth**, **XPM**, **Building damage**, **Healing**, **Wards**, **MMR after**, **Your game**,
  **Multi-kills**, **Double**, **Triple**, **Ultra**, **Rampage**; MMR tab **Highest MMR**, **Streak**, **Best
  streak**, **Left matches**, **Behaviour score**, **Private**, **Reports this season**, **Leaderboard**, "MMR over the
  last N matches"; visitors "looked N ago", "Players who looked at your profile lately (only you see this)."; compare
  rows **Ranked matches**, **Kills a match**, **Deaths a match**, **Assists a match**, **Last hits a match**; notes "You
  commended X.", "You already commended this player today.", "You reported X. Thank you.", "You already reported this
  player today.", "You blocked X: their posts and comments are hidden.", "You unblocked X.", "Name copied.", "Match
  copied.", "Profile saved.", "Picture changed.", "X answered on the wall."; end screen "Your game: N% (kills, assists,
  deaths, last hits) · a win gives 23 to 41, a loss takes 23 to 41", "On your profile: First Blood, Rampage, N Triple
  Kills, MVP"; Forums "N/N/N avg", "N MVP", "N replies from players you blocked hidden", "Click: profile · Right-click:
  more"; hover card **Averages**, "Right-click for more"; chips **Friend**, **Blocked**, "Known for: X"; Play tab "A win
  gives 23 to 41 MMR, a loss takes 23 to 41: kills, assists, last hits and few deaths decide how many." Code: `Career`,
  `ProfileTalk`, `ProfileLines`, `ChatProfile`, `SocialUi`, `PlayerMenu`, `ProfilePage`; skin `soc_*`, `ic_*`, `gl_*`;
  save fields `career`, `career_base`, `unranked`, `wall`, `wall_made`, `wall_t`, `visitors`, `commends`, `reports`,
  `commended`, `reported`, `blocked`; chat intents `profile_me`, `profile_you`; line kinds `pf_*`; unit counters
  `multi_n`, `first_blood`, `lane_secs`.
* **Ranked is the main mode** (your request, same day): the Main Menu has no **Play** any more; **Ranked** is its first,
  gold plate (Up / Down / Enter start on it). Casual matches are still one click away from **Choose Hero** (Hero Select >
  Play > Game Setup). Every match's end screen offers **Back to Dashboard** (the Ranked screen) instead of Find Match;
  an unranked match also keeps **Play again**; then **Main Menu** and **Quit** ("Hero Select" left the end screen).
* Also fixed: the Play tab's hero rows drew the record over the medal; a pick-chat answer to trash talk said "chill" /
  "relax" (now a comeback, your rule); right-click menus open where you click (they used the last known mouse
  position, which a click without a move does not update: the menu opened off-screen and blocked later clicks).
* Evidence: headless tests 327 passed, 0 failed (`tests.txt`; the profile, chat and pick tests again after the last
  changes); `ranked_probe.gd` 51/51 through real clicks and a real ranked match (offer, pick, match, +28 MMR for a win
  by performance, MVP screen, Back to Dashboard, Edit profile, View As, a wall post answered, right-click > Compare);
  captures at 1080p and 4K (`ui/`); `check_names.py` Names OK; the Windows export rebuilt (`build/WarriorsOfAether.exe`)
  and its pack opens the Main Menu and a profile with the new skin (`ui/pck_menu.png`, `ui/pck_profile.png`).
  Not verified: no fresh-context critic and no Dota 2 profile screenshot as a benchmark; the Forums profile overlay and
  the hero-pick right-click were not clicked through; no unranked match played by hand through to the profile.

**2026-10-20: the player is always answered, and trash talk gets trash talk back (your request: "the player should be
TOP PRIORITY to have them reply at all means ... If the player talks trash they try to pacify the player which is
STUPID", "even in the forums they dont reply to the player").**
* **Why they ignored you**: every answer went through the same dice as idle chatter (an unknown line had about a 1 in
  5 chance), a bot that was typing or had spoken in the last 2 s could not answer, and the online writer only reworded
  the brain's own line (often just "?"), so it never answered what you wrote. Lines after the Throne fell were never
  read.
* **Now** (`src/sim/sim_bot_chat.gd`): every line you type gets at least one answer: the bot you named, else the last
  one who spoke, else an enemy in all chat or a teammate in team chat. Answers skip the dice, the busy check and the
  one-line-at-a-time rule, and jump the chat queue (0.6 s gap instead of 1.5 s). The end screen answers too.
* **Trash talk** (`chat_social.gd`, `chat_more.gd`): "relax", "chill bro its a game", "be nice", "stop all chat",
  "just play" and "muted" are gone. A nice bot jabs back ("ez? the game isnt over", "love u too {name}"), the rest roast
  you with your numbers ("all that chat and still 0/6/0", "{lh} cs at {min} min and u talk?"); your rough teammates
  join in instead of telling you to stop. More of what you type counts as trash talk ("ur mom", "u suck", "git gud",
  "clown", "putangina", "baho" ...).
* **Online writer** (`src/core/llm_chat.gd`): every answer to you is sent to the model, past the share, the per-match
  cap (its own cap: `max_replies`, 400) and the three-at-a-time limit, and may wait 9 s (`reply_timeout`). The prompt
  gives the model who you are (hero, score, last hits, rank) and exactly what you wrote, and tells it to answer that;
  on trash talk to hit back with a witty comeback and never calm you down. Seen with the real model in a live probe:
  "0/6/0 ka nga tas kami pa trash? sheesh bea, last hit ka muna bago ka magsalita", "at least ur cat plays better than
  u 0/6".
* **Forums** (`src/core/forum.gd`, `forum_writer.gd`): the one you answer always answers back (it was 90%, and a reply
  in your own thread without picking someone went to nobody: now it goes to whoever you named, else the last writer);
  someone else joins in, and trash talk draws a second one. Flames are answered with roasts ("you flame better than you
  farm"), never "you got this". Your replies from the last three days that nobody answered get answered on your next
  visit. The model gets the same rule, and replies to you have 108 of the visit's 120 calls.
* **Key safety**: a test script driving the game (`godot -s ...`) never uses your key now, only a local stand-in
  (`--llm_endpoint=...`). This run's first live probe did use it once: 22 lines, $0.0041 (in `llm_usage.json`).
* New code names (chat kinds, not shown to players): `r_back`, `r_any`, `r_any_foe`, `r_insult_witty` (was
  `r_insult_calm`), `tt_witty` (was `tt_kind`); `tt_ally_stop` removed. New tests: `test_chat_player_always_answered`,
  `test_chat_trash_talk_never_pacified`, `test_llm_answers_the_player_first`, forum checks in
  `test_ranked_mvp_and_memory`; `talk_probe.gd` now types 8 more lines (22/22 with and without the model).

**2026-10-19 e: the social world: the crowd reacts to anyone owning or feeding (double .. rampage), stand-out and
terrible KDAs (smurf, cheating, boosted, report threats), your trash talk gets answered with your own numbers, "add me"
really adds you, MVP after every match (supports too) with a 3D MVP screen, MVP last game on the versus screen and in
chat, bots remember you and each other, live stats panel top left, chat in the hero pick with Alt+click / Shift+click,
and a Forums section (your request).** Run `work/lemondev/2026-10-19e-social/` (contract.md, handoff.md; transcripts
`review/`, captures `ui/`, `shots/`).
* **The crowd** (`src/sim/chat_social.gd`, lines `src/sim/chat_more.gd`): for **anyone**, a Double Kill draws a word
  or two, a Triple a few, an Ultra Kill more, a **Rampage** the whole lobby (the killer's team: "RAMPAGEEE", "+rep",
  "clip it"; the victims: "report", "{name} is hacking", "smurf", "no way {name} is {rank}", then they blame each other).
  Streaks of 5/7/9/11 are cheered and called out ("someone kill azrin"); a shutdown of 5+ is cheered. 5, 8, 11 ...
  deaths with a poor score: the enemy mocks the free gold ("thanks for the gold"), teammates flame (or, kind ones, help),
  the bot itself says sorry.
* **KDA review** every couple of minutes: a stand-out score (yours first) draws smurf accusations ("12/1/6 at expert 2?
  smurf"), cheating ("maphack", when you are far ahead or got an ultra kill) and report threats from the enemy; a
  high-rank show-off dismisses it ("im mythic 3, ur nothing"); a kind one respects it; your team praises it. A terrible
  one: "how are u {rank}", "boosted", "who boosted u". Ranks come from the ladder (both yours and theirs).
* **Your trash talk** ("ez", "gg ez", "sit", "too easy", insults) in all chat or at an enemy is answered with what they
  know: your score ("ez with 1/3/0?", "2/7/1 and talking"), the gold gap ("ez? ur 6k behind"), your death a moment ago
  ("says the guy who just died"), "lucky" when you really are winning; a second voice piles on (2026-10-20: nobody
  tells you to stop any more; a rough teammate joins in). They remember it: next time "{name} the trash talker", and
  at the end "who's ez now". Reports against you are listed on the end screen and cost 60 behaviour each in ranked.
* **"add me"** (also "duo after?", "pa add") to a bot by name, or the last one who spoke: it says yes or no by what it
  thinks of you (its memory, this match's praise or flames, your score) and a yes **makes you friends** on the ladder
  ("You and mika are now friends"); a no is a no ("after u stop feeding"). At the end, players who enjoyed the game
  offer ("{name} add me after") and send a real friend request. Works in the hero pick too.
* **MVP** (`src/sim/match_mvp.gd`): every match, from kills / assists / deaths, hero and building damage, **healing
  given, disables, wards, saves**, farm and the win; a support can win it (tested). The **MVP screen** (`src/ui/mvp_screen.gd`)
  comes before the scoreboard: the MVP in 3D on the versus field in gold light, MVP slamming down, name, hero, rank,
  K/D/A, the numbers it led the match in, and the other honours (Top support, Most damage, Best farm); Continue goes on.
  The scoreboard marks the MVP. Ranked keeps every player's MVPs and last game (ladder rounds give MVPs to bots too).
* **MVP last game**: a gold tag on the versus plates and pick slots; your team says it in the pick ("{you} was MVP last
  game, carry us", "careful, {enemy} was MVP last game"), both teams at the start ("lets test the MVP"), and if you
  then do badly: "MVP last game? lol", "boosted MVP"; do well: "MVP for a reason".
* **Memory**: bots remember your rampages, MVPs, trash talk, reports and accusations (Ranked "you"), and **each other**
  ("seen": the feeder, the rampage guy, the flamer, the MVP): at the start "{name} the feeder from last time" and the
  other answers. Each player has a "known for" (rampage, MVP, feeding, flaming, godlike) on the profile with its MVP
  count; rampages and godlike streaks go into the ladder activity.
* **Play uses ladder players** (Options > Game > "Bots are ladder players", on): bot slots you did not name are ladder
  players online now near your MMR, with their names, manners and memory; they play at your Game Setup skill; the match
  is remembered (no MMR), friends included.
* **Live stats** (top left): K / D / A, last hits / denies, GPM, XPM, LH per minute; hover for lane creeps, camp creeps,
  other units, denies, best streak and multi-kill, hero and building damage, healing to allies, disables, wards, saves,
  net worth. New counters in the simulation (`SimUnit.lh_lane / lh_neutral / lh_other / heal_given / disable_given /
  wards_placed / saves / best_multi / best_streak`); "Saved" pops over an ally you saved.
* **Hero pick chat**: type in team chat (Enter); teammates answer greetings, trash talk, rank, role calls, "add me";
  **Alt+click** a hero: "I want to play X" (a teammate who wanted it picks another, a rough one complains first; nobody
  on your team goes for it); **Shift+click**: "Pick X" (the teammate it suits takes it up, or says no). Typing a hero
  name works too ("froster me", "pick araki").
* **Forums** (Main Menu > Forums; `src/core/forum.gd`, `src/ui/forums.gd`): threads by the ladder's players while you are
  away, from what happened (ranks reached, rampages, Top 1, losing streaks, matches with **you**: "Just played against
  {you}, 14/2 on Araki, smurf?", "{you} trash talked all game"), the feeder or rampage they met, help, duo search, tier
  lists, items, jokes; replies by persona and rank (high-rank show-offs sneer, kind ones help, trolls troll, shot callers
  give real tips). Your post gets answers over the next minute ("... is typing"), a reply to someone gets them talking
  back, insults make them like you less (and remember you as a trash talker), praise more, a duo post can bring friend
  requests; votes, Hot / New, sections. With Online bot chat on, **ForumWriter** has the model (your OpenRouter /
  DeepSeek setting) write the replies to you and the newest threads; offline text otherwise (`docs/LLM_CHAT.md`).
* Online bot chat (in match) now also rewrites the new moments (trash talk answers, KDA, MVP, add, rampage) with their
  facts.
* Chosen where open (veto any): the MVP score weights (kill 3, assist 1.7, death -1.5, up to 9 for hero damage share, 4
  building, 9 healing at 350 a point, 6 disables, 7 wards, 2.5 a save, 4 farm, 5 a win, 3 a rampage); a save = a low
  ally (under 30%, hit in the last 3 s) healed or its attacker disabled, alive 4 s later, once per ally per 20 s;
  feeding thresholds 5/8/11/14/17/20 deaths; streak reactions 5/7/9/11/13/15/18/20/25+; review every 100-170 s,
  "great" = 6+ kills at 4+ (kills + half assists) per death, "terrible" = 7+ deaths at 0.45 or less; 60 behaviour a
  report (ranked); the "add me" yes threshold; casual ladder players from the 40 nearest your MMR who are online;
  a hero quip once per 15 minutes and team calls once per 7 minutes per player (was 150 s), no line a third time;
  forum: a new thread per 25 minutes away (6 at most a visit), 14 on a new forum, replies 4-7 to your post in the
  first minutes; 40 model calls a visit.
* New names (veto any): menu **Forums**; sections **Discussion**, **Heroes**, **Help**, **Looking for group**,
  **Match stories**, **Funny**; buttons **Hot**, **New**, **New post**, **Reply**, **Upvote**, **Voted**, **Post**,
  **Cancel**, **Continue**; "Replying to ...", "... is typing", "Write a reply (Enter to post)", "N threads · N players
  online", "Nothing here yet. Be the first to post."; **MVP**, "Most valuable player", **Core** / **Support**,
  honours **Top support**, **Most damage**, **Best farm**, reasons **Most kills**, **Most hero damage**, **Most
  healing**, **Saves**, **Most assists**, **Most wards**, **Most disables**, **Most building damage**, **Most last hits**,
  **Highest net worth**, **Deaths**, **Rampage**, **Ultra Kill**, **Triple Kill**; tag **MVP last game**; "(MVP)" on
  the scoreboard; "Friend requests from ...", "N players reported you this match", "You and X are now friends", "X sent
  you a friend request"; popup **Saved**; stats panel "K / D / A", "LH", "GPM", "XPM", "LH/min", tooltip **Your
  match** with "Creep kills", "Lane creeps", "Camp creeps", "Other units", "Denies", "Per minute", "Best streak", "Best
  multi-kill", "Hero damage", "Building damage", "Healing to allies", "Disables on heroes", "Wards placed", "Saves", "Net
  worth"; pick chat "Say to your team (Enter)", "Alt+click a hero: you want it    Shift+click: ask a teammate to pick
  it", "I want to play X", "Pick X"; profile "MVP N times", "Last game MVP", "Known for: Rampage, Godlike streak, MVP,
  Feeding, Flaming, Carrying"; feed "X got a Rampage on Y", "X went Godlike on Y"; option **Bots are ladder players**
  and its note; every line in `ChatMore.T`, `Forum.THREAD`, `Forum.REPLY` and the pick chat lines in `hero_draft.gd`;
  code `ChatSocial`, `ChatMore`, `MatchMvp`, `MvpScreen`, `Forum`, `ForumWriter`, `StatsPanel`, `Ranked.befriend /
  send_request / remember_casual / fame_of / mvp_last`, `Matchmaker.card_of / casual_identities`, `SimBot.set_identity`,
  `SimWorld.player_cards`, `SimCombat.help / note_disable / check_saves`, events `friend`, `save`, option
  `ladder_bots`, files `user://forums.json`, tools `tests/tools/social_probe.gd`, `work/.../recheck.py`, tests
  `test_match_stats_counters`, `test_mvp_support_can_win`, `test_chat_multikill_crowd`, `test_chat_feeding_and_kda_reviews`,
  `test_chat_trash_talk_answered`, `test_chat_add_me_makes_a_friend`, `test_chat_mvp_last_game`,
  `test_ranked_mvp_and_memory`, `test_forum_offline`, `test_draft_pick_chat_and_calls`.
Evidence: headless tests **317 passed, 0 failed** (307 + 10 new); `sh tools/check.sh` no script errors, "Names OK";
blind A/B by a fresh critic (same match, the new layer on vs off, two seeds, labels shuffled): **the new chat won both
with a clear advantage** (answers trash talk with the player's real score, MVP talk, a reasoned no to "add me"); its
largest gap (a dominating enemy bot drew no smurf talk, multi-kills under-reacted, a hero quip 4 times) measured by
`recheck.py`: before: accusations at the 25 / 29 streak enemy 0 / 0, under-reacted triple+ kills 0 / 2, lines said 3+
times by one player 2 / 2; after pass 2-3: accusations 5 / 2-3, under-reacted 0 / 0-1, repeats 0. Captures: live stats
panel and its breakdown, MVP screen (5v5 at 10 min and the duel), Forums at 1080p and 4K (offline and with replies),
the pick with chat (`ui/`, `shots/`). Forum writer tested against the local stand-in (8 requests, the stand-in key
only, your usage file untouched).
**Your key was used by mistake once**: the first Forums captures ran with Online bot chat on in your Options and your
key in `llm.json`, so ForumWriter made 8-10 real OpenRouter calls (about $0.0013-0.002, logged in your
`llm_usage.json`: 8 calls, "matches" +1). Captures and probes can no longer reach the real service (fixed in
`forum_writer.gd`).
Not verified: no Dota 2 comparison; the Forums and the pick chat had no blind review; no real ranked match played by
clicks this run (the ranked flow is covered by tests); reactions measured on bot-driven matches, not your play.
Release build: `build/WarriorsOfAether.exe` rebuilt 2026-10-20 00:02 (exit 0, pack 710 MB); the pack cold-starts into the
Forums and into a match with the MVP screen and no script errors (`shots/exe_forums.png`, `exe_mvp.png`).

**2026-10-19 d: living players: every bot has a personality, a typing style, a daily schedule, moods, friends and a
memory of you; a chat brain that knows the match (revenge, rivals, kill steals, abilities, ultimates, items, gold,
tilt) and answers what you type; team calls in players' words; a Players tab (friends, requests, recent players,
ladder activity, who is online); an optional online chat writer (Claude Haiku 5.5) wired in and off; new build
(your request).** Run `work/lemondev/2026-10-19d-living/` (contract.md, handoff.md, recheck.py; logs `logs/`, captures
`ui/`, `shots/`, blind review `review/`). Costs, advantages and setup of the online writer: **`docs/LLM_CHAT.md`**.
* **Persona** (`src/core/persona.gd`): traits (talk, kind, ego, temper, humor, focus), typing (lower case, short
  forms, typos, stretched letters, their laugh by country: haha / wkwk / kkkk / 555 / jaja, a pet word: lods, pre,
  bai, bro, mate ...), a daily schedule in their time zone (evening, night, after school, all day ...), labels
  ("Friendly", "Shot caller", "Flamer", "Quiet" ...), a bio. Ranked bots get theirs from the ladder; Game Setup and
  multiplayer bots get one from their name (the same on every machine).
* **The ladder lives** (`src/core/ranked.gd`): 300 players (an old ladder is upgraded in place: MMR, records and
  names kept; tested), two new accounts a day up to 420; who plays depends on who is online at that hour; each ladder
  game has K/D/A and a length; moods follow results; now and then a player learns a new hero and keeps it if it goes
  well; statuses ("On a 6 win streak", "Learning Araki", "Just reached Legendary", "Rough week: -140 MMR in 10 games",
  or their own words); friends; an activity feed (ranks reached, streaks, Gold+ medals, heroes learned, new Top 1
  players, the top ten). Matchmaking only finds players who are online and not in a match (a long search takes
  anyone, so it never stalls).
* **They remember you**: after a ranked match each of the nine keeps games with / against you, results, the kills
  between you, who flamed whom and how much it likes you; next time: "uy Bea, panalo tayo last time ah", "Bea, revenge
  time", "oh its the flamer", "Bea killed me 5 times last game". Bots that liked a game send **friend requests**;
  you can add players from their profile (a kind one or one who likes you says yes).
* **Chat brain** (`src/sim/sim_bot_chat.gd`, lines `src/sim/chat_mind.gd`, typing `src/sim/chat_style.gd`): revenge
  ("payback caziel", "bawi ako"), rivals ("6th time lol", "suki kita"), kill steals ("ks", "sorry ks"), the ability
  that landed ("felt that fiery javelin?", "nerf burst shot"), "perma stun", dodged spells named ("dodged ur shuriken
  hook"), double kills, wipes, 1 HP escapes, enemy ultimates ("ezee used unholy might, go"), ult ready, items done,
  the gold gap ("we're 9k up, push", "they're 7k up, play safe"), a fed enemy, an enemy core dead long enough to push;
  tilt (shouting, blaming, "ayoko na") or a kind bot cheering the team up; flamed teammates answer back ("ikaw nga
  1/6/0") and someone tells them to stop. Library lines naming a minute ("still holding tangos at 25 min") wait for a
  game that long.
* **Talking with them**: what you type is understood: greetings, "what rank", "where u from" (a city), "where is
  <hero>" (where the team last saw it), "what item", "why no help" (what they were doing when you died), insults (with
  your own score: "says the 0/7/0 froster"), praise, thanks, sorry, gg, ff, report, lag, "are you a bot" ("u are the
  bot"); "push bot" stays a lane call. Address a bot by its name or hero.
* **Team calls in players' words**: "I'm dead, back in 23 s." -> "dead 23s"; "Hold on, X! Coming." -> "hold sludge",
  "kapit araki"; "X is missing from mid! Careful." -> "kragg ss"; lane calls "mid", "ako safe", "sup kragg"; calls a
  player would not bother typing are left out sometimes (the plan still happens; answers to your pings always come);
  nobody echoes another's call word for word or repeats one within 150 s.
* **Players tab** (Ranked): Friends (requests with Accept / Ignore, friends with online state and status), Recently
  played with (with you / against you, what they think of you), Ladder activity, Online now (in a match as which hero,
  or free). Profiles show status, online state, labels, the record with you, Add friend / Remove friend; the hover card
  shows them too; the footer counts players online.
* **Hero pick chat** is typed in each player's style.
* **Online bot chat** (Options > Game, off; `src/core/llm_chat.gd`): your choice, **OpenRouter** with **DeepSeek
  V4.1 Flash** (`deepseek/deepseek-v4.1-flash`) by default; with your key in `llm.json` in the game's data folder (or
  `OPENROUTER_API_KEY`) it rewrites the lines you can read in each bot's voice with the match around it; the bots' own
  brain still decides; the bot's own line is shown if no answer comes in 4 s; single player only; per-match cap; the
  cost OpenRouter reports is logged in `llm_usage.json`. About $0.0015-0.005 a match (see the doc). `"model"` in
  `llm.json` picks any other OpenRouter model; a non-OpenRouter key uses Anthropic's API (`claude-haiku-5-5`). Tested
  against a local stand-in of both APIs (`tools/llm_mock.py`), not the real services: your key was not used here, so
  put it in `llm.json` yourself (steps in the doc).
* Chosen where open (veto any): ladder 300 / 420, two new accounts a day; the trait formulas; online 80% / away 12%
  chance to play a ladder round; learning chance 1 in 220 games, kept after 14 games at 50%+ wins (35% anyway); feed
  thresholds (Commander+, streaks 6/9/12, Gold+ medals); likes: +0.18 a win together, -0.22 a flame, +0.12 praise;
  friend request chances; call skip rates; the 150 s repeat rule and no line of 3+ words said by two players in a
  match; the online writer's 150 calls, 4 s wait, half of ordinary lines (OpenRouter and DeepSeek V4.1 Flash are
  yours).
* New names (veto any): tab **Players**; panels **Friends**, **Recently played with**, **Ladder activity**, **Online
  now**; **Add friend**, **Remove friend**, **Ignore**, **Back**; "Wants to be friends", "after a game with you /
  against you", "No friends yet ...", the empty-list hints, "N online · N in a match · N on the ladder", "Online", "In a
  match as <hero> · N min", "Last seen ...", labels **Friendly, Quiet, Talks a lot, Shot caller, Show-off, Tilts
  easily, Joker, Tryhard, Flamer, Troll, Plays alone, Chill, Team player, Calm**; feelings **Likes you, Friendly to
  you, Annoyed with you, Does not like you, No strong feelings**, "Never played with you", "With you N (N won)",
  "Against N (you won N)"; statuses "On a N win streak", "Lost N in a row", "Learning <hero>", "Just reached <rank>",
  "Climbing: +N MMR in 10 games", "Rough week: -N MMR in 10 games"; feed lines ("<name> reached <rank>", "... is on a N
  win streak", "... earned <medal> on <hero>", "... now plays <hero>", "... started learning <hero>", "... is the new
  Top 1 Player on <hero>", "... made the top ten", "You and <name> are now friends"); notices ("<name> accepted your
  friend request.", "<name> did not answer your friend request.", "Removed from your friends."); option **Online bot
  chat** and its note; the bios, pet words, laughs and cities in `persona.gd` / `chat_mind.gd`; every line in
  `ChatMind.T` and `ChatMind.CALLS`; code `Persona`, `ChatMind`, `ChatStyle`, `LlmChat`, `PresenceLine`, `PersonRow`,
  `FeedRow`, `SimBotChat.persona / mind / speak / casual / relations`, `SimBot.persona / pid / you_rec / card`,
  `Ranked.ask_friend / accept_request / ignore_request / remove_friend / recent_players / online_counts / feed_text /
  clock_override / stamp`, event `chat_intent`, option `llm_chat`, files `user://llm.json`, `user://llm_usage.json`;
  tools `tools/llm_mock.py`, `tests/tools/llm_probe.gd`, `talk_probe.gd`, `living_ladder.gd`, `options_shot.gd`,
  `bot_game.gd --names=ladder`; tests `test_persona_basics`, `test_ranked_living_*`, `test_ranked_match_memory`,
  `test_matchmaker_presence`, `test_chat_*` (five new).
Evidence: headless tests **307 passed, 0 failed** (297 + 10 new) on the final code; `sh tools/check.sh` no script
errors, "Names OK"; live window probes: `talk_probe.gd` 6/6 (lane calls in players' words; greeting, rank, where is a
hero, an insult, "are you a bot" in all chat all answered in the HUD), `ranked_probe.gd` 45/45 through real clicks and a
real ranked match (18 bots remember you afterwards); `llm_probe.gd` 17/17 against the stand-in API (both services);
blind A/B by a fresh critic of the old and new chat (same seed): **the new chat won with a clear advantage**; its
largest remaining gap (echoes between players, filler after "!", repeated calls) measured by `recheck.py`: old system
24 / 0 / 13, reviewed pass 4 / 6 / 1, final 0 / 0 / 0 on both seeds; distinct lines in a 25-minute game 59% -> 88%.
Captures: Players tab at 1080p and 4K, a bot profile, the hover card, Options, the chat in a live match (`ui/`, `shots/`).
Not verified: no real OpenRouter / DeepSeek call (your key was not used here); the Players screen has no blind review
and no commercial comparison; ladder dynamics over weeks of real time; the critic flagged your example bot name
"BISAKOL SLAYER" ("bisakol" is a regional slur) and BotNames still uses "bisakol": yours to decide.
Release build: `build/WarriorsOfAether.exe` rebuilt 2026-10-19 20:57 (exit 0, pack 710 MB); it cold-starts into a 5v5
match with no script errors and the new chat (`shots/exe_match.png`, `exe_match2.png`).

**2026-10-19 c: Araki, the Blur (your hero: kit, bot, body, effects, icons); Blau's bots spam turrets; Airah and Tock
face the right way (versus, portraits); every portrait looks at the camera; new build (your requests).** Run
`work/lemondev/2026-10-19c-araki/` (contract.md, handoff.md; logs `logs/`, captures `shots/`, `ui/`, `versus/`,
`portraits/`, `model/`).
* **Araki, the Blur** (your kit and numbers; Neutral, agility, melee 150; strength 20 +1.7, agility 24 +2.8,
  intelligence 18 +2.1; damage 49-53, armor 5, speed 305, attack point 0.3).
  * **Senryukai** (innate, Dota's Fury Swipes): each of his hits on an enemy adds a stack, +4 physical damage a stack
    on his hits on that enemy (the hit that adds it counts), 15 s renewed by every hit, no limit; ghosts' hits add
    stacks too. Break turns it off; not on buildings.
  * **Blur Strike** (Q, 90/110/120/130 mana, 10 s): an instant dash up to 600 (200 at least; aimed by direction, so a
    far click dashes the full 600) over trees and cliffs; every enemy within 250 of the path takes an attack (crit,
    bash, Cleave Axe and every item effect roll per enemy) plus 50/80/110/140 magic damage and a 60% slow for 1 s. A
    dash that hits anything refreshes the cooldown once: a second dash within 6 s, else the first cooldown runs on.
  * **Djin Bomb** (W, 90-120 mana, 12 s, 750 range): lands after 0.4 s; a demon cloud (radius 450) for 5 s: enemies
    inside lose 10/15/20/25% magic and status resistance and are slowed 5/8/11/14% more each second inside (5 s: up
    to 70%); it fades 0.5 s after they leave.
  * **Ghosts of the Will** (E, 110 mana and 21/20/19/18 s: your change mid-run, was 160 and 18 s; 650 range): 3/5/7/9 ghosts, one every 0.3 s; each flies at 650 through
    units and over terrain, strikes once for 25/35/45/55% of his attack damage (Senryukai's bonus scaled the same) and
    vanishes; one hit (any damage) destroys a ghost; if the target dies they go for the nearest enemy (a hero first)
    within 700. Ghost blows carry no item procs (no crit, bash, lifesteal).
  * **The Blur** (R, 75/100/125 mana, 80/60/40 s; no cast time): 19 s of half cooldowns for Blur Strike and Djin Bomb
    (the running ones halved at once), and his next 9/15/21 attacks 60/80/100 faster (each attack he releases spends
    one; Blur Strike's slashes and ghosts do not).
  * Talents: +2 Senryukai damage per stack / +50 Blur Strike damage; +2 Ghosts / -3s Djin Bomb cooldown; +15% Ghost
    damage / +10% Djin Bomb magic resistance cut; +8 The Blur attacks / Blur Strike refreshes twice.
  * **His bot** (`src/sim/sim_bot19.gd`): The Blur first when it commits; the bomb before the magic damage, placed to
    cover the most enemy heroes and never on its own cloud; Blur Strike along the line that slashes the most heroes,
    ending just past the target, never into a tower without the kill; the refresh slashes back through them, or is
    kept to escape when low; Ghosts on the enemy carrying the most stacks. Lane: a dash through the laner and its
    creeps (the creeps make the refresh sure), the second dash home. Farm: through 3+ creeps, then back. Running:
    the dash toward safety bent through an enemy unit for the second dash, the bomb on chasers only if it does not
    cost the dash. One Blur Strike of mana kept back when the fight can turn on him (the traced deaths were all
    dashes and bombs spent, escape on 9% mana). Skill order Q W Q E Q R, Q, E to 4, W last; talents left, left, left,
    right; builds: Cleave Axe line, bash and chain lightning line, Frenzy Mask line.
  * **Body**: the Shadowflame Samurai (dark_igorek, Sketchfab, CC BY 4.0; credited in ASSET_CREDITS and the Credits
    screen), downloaded with your Sketchfab sign-in. Its rest skeleton was broken (Y-up, bones at the origin), so
    `tools/blender/araki_prep.py` bakes the shown pose as the rest; `hero_body.py` binds it (the arm split is off: it
    tore the back armour), 50k triangles, 1536 textures (71 MB; 113 MB at 2048 was over GitHub's 100 MB limit). His
    katana is the model's own (`tools/blender/araki_katana.py`, `prep_weapon.py`). He swings the great sword motion
    capture (two hands on the grip). Collision fixed for every clip he plays (worst 35.7 -> 0 cm; leap_slam 3.2 cm,
    a clip he never plays); animation joins 42 + 3 loops, 0 failures.
  * **Effects** (`src/game/araki_fx.gd`): see-through echoes of his body along each dash, a green streak and scorch, a
    crossed cut on everything slashed; the bomb thrown on an arc with a spitting fuse, bursting in green fire into a
    dark swirling cloud with the demon's eyes and maw; ghosts drawn with `src/game/ghost.gdshader` (his body,
    see-through green, hovering), a green cut where they strike; The Blur's shockwave, katana glow and trailing
    streaks; green sparks on enemies with 4+ stacks. Sounds for each. Five icons (`tools/item_icons.py`, "soul").
* **Blau's bots spam the turret** (your report: never seen it). They did build turrets, but only every two minutes
  (13 and 16 in 25-minute games: only in fights against a hero). Now one goes down whenever it is ready and there is
  something to shoot: an enemy hero within 1100 (also when running), or 3+ enemy creeps or camp creeps beside him;
  half a Bounce Shot of mana kept. Same kind of game: 24 and 38 turrets.
* **Airah and Tock faced the wrong way** in the versus shot (and Airah showed the back of her head in her portrait):
  both stood in the motion-capture idle `spell_idle_2`, whose stance turns the body about 60 degrees away. They now
  stand in `spell_idle` (Froster's). **Portraits** now aim at the face whichever way a stance turns it (the great
  sword idle had Ser Emelrich and Araki side-on); all 17 re-baked.
* Hero Select fits 17 heroes (five a row of smaller cards when there are more than 16); the ranked pick's tiles narrow
  to keep two rows (17: nine a row).
* Chosen where open (veto any): his base attributes, damage, armor, speed, attack point; Djin Bomb's mana, range and
  throw time; The Blur's mana; Blur Strike's 200 minimum, cast point 0.1, path radius 250 read as a radius (500 wide),
  the 6 s window for the second dash; ghosts' 6 s life, 700 retarget, share applied to Senryukai, no item procs;
  The Blur halving running cooldowns; every talent; the bot's builds and orders; Clarity in his starting items.
* New names (veto any): yours: **Araki**, **the Blur**, **Senryukai**, **Blur Strike**, **Djin Bomb**, **Ghosts of the
  Will**, **The Blur**. Mine: the unit **Ghost**; buff names **Second Dash**, **Fast Attacks**; the eight talent
  labels above; Hero Select's "Melee · Agility · Carry, Escape, Nuker" and his story; bot line "Too slow."; code
  `SimKits7`, `SimBot19`, `ArakiFx`, `ghost.gdshader`, unit `araki_ghost`, weapon `araki_katana`, modifiers
  `senryukai`, `blur_strike_again`, `the_blur`, `the_blur_speed`, `djin_bomb`, `ghost_form`, effects `djin_smoke`,
  `ghost_call`, fire ramp `shadowflame`, icon backdrop `soul`; tools `tools/blender/araki_prep.py`, `araki_katana.py`,
  `tests/tools/araki_probe.gd`, `versus_shot.gd`; tests `test_araki_*`.
Evidence: headless tests 297 passed, 0 failed (`test_araki_*` six of them); `sh tools/check.sh` no script errors, "Names
OK"; body collision 0 cm in every clip he plays (was up to 35.7 cm); animation joins 0 failures; 30-minute bot games:
his line-up (with Ezee, Tock, Kragg, Froster) loses the kills about 1 to 3 to Caziel's whichever side it plays, and
Araki went 6/11/6, 8/11/8, 6/14/4, 9/12/5 there (before the bot's mana fix 5/15/4, 6/13/7); traded into Caziel's team
he went 8/4/10 with 76 last hits while Caziel went 6/11/10 with 46; every skill cast in every game (Ghosts of the
Will 8 times in 20 minutes, from once). Captures in a live match (`shots/`), Hero Select, the ranked pick, the versus
shot and all portraits (`ui/`, `versus/`, `portraits/`).
Not verified: no blind critic review; no Dota 2 comparison; bots measured against bots only; the demon cloud's rising
smoke does not show in captures (its ground swirl, burst and eyes do).
Release build: `build/WarriorsOfAether.exe` rebuilt 2026-10-19 16:42 (exit 0, pack 709 MB); it cold-starts into a match
as Araki with no script errors (`export/exe_araki_44.png`). The menus of the exe were not clicked through.

**2026-10-19 b: Ranked: MMR and 12 ranks with 3D emblems, a global ladder of 160 bot players with their own skill,
names, countries and pictures, role queue, Find Match and Accept, a hero pick with numbered turns, a 3D versus
shot, hero mastery medals (Bronze .. Diamond, Top 5 .. Top 1 Player), profile and leaderboard (your requests).** Run
`work/lemondev/2026-10-19b-ranked/` (contract.md, handoff.md; logs `logs/`, captures `final/`, `final2/`, `draft/`,
`probe4/`).
* **Main Menu > Ranked**: **Play** (your rank and your heroes, tick your roles: Carry, Mid, Off Lane, Soft Support, Hard
  Support; Find Match; the search with a progress bar, players found, Cancel), **Profile**, **Leaderboard**, **Guilds**
  (coming soon; from Licensed). No hero is chosen before matchmaking (your correction).
* **Match found**: a big green **Accept** and **Decline**, a 15 s ring, ten lights; both teams at the sides, hover a
  player for rank, MMR, W-L, behaviour score, roles, best medals, last ten games. Low-behaviour bots sometimes fail to
  accept (back into the queue); Decline keeps those nine out of your next offers.
* **Hero Pick** (`src/ui/ranked_draft.gd`, `src/core/hero_draft.gd`): each of the ten gets a random numbered turn; the
  one picking glows; heroes land in their slots with a flash and sparks; 30 s for you (Lock in, Random; then a hero
  for your role is picked for you). Your bots call their heroes in team chat ("Azrael ako", "I'll go Kragg carry") and
  pick them unless someone takes them first, then change their mind ("ok you take Azrael, I'll go Froster", or "bro
  Azrael was mine"). Your heroes with **Gold or better** are left to you, and your team says so ("wait, Bea is Diamond
  Azrael"), hurries you while enemies pick ("hurry, pick Azrael before they take it"), and reacts if a strong enemy
  snipes it (an enemy of 2500+ may take your Platinum+ hero to deny it). Every pick is logged in the chat.
* **Versus** (your request: fully rendered): all ten heroes in 3D on a battle field (`src/ui/versus_stage.gd`), your team
  on the left in blue light, the enemy on the right in red, in wedges facing each other across a seam of light, embers,
  fog, shadows; each plays its flourish and stands ready while the camera pushes in; over each hero the player's name,
  then their rank, then their medal on that hero; VS slams down with a flash and a shake; the match loads. Each hero is
  placed as it is picked, so the reveal does not stall. Then the match plays the picked heroes.
* **MMR**: you start at **1000**; Elo on team averages, +25 / -25 for an even game; leaving a ranked match is a loss.
  New bot accounts start at 1500, about one in seven at a random MMR (smurfs, boosted), the rest near their skill;
  the ladder keeps playing while you are away and after each of your games.
* **Ranks** (your names): Rookie 0 .. Transcendent 5400, Aetherium 6000, **Aetherium+** = top ten in Aetherium; 5 stars
  in each rank below Aetherium. Shiny 3D emblems, grander each rank; drag the profile's emblem to turn it.
* **Hero mastery** (your request): every hero has XP for every player. Each match gives a win 100 or a loss 20, plus up
  to 60 for how you played (KDA 35%, net worth place 25%, share of team hero damage 25%, last hits 15%); a left match
  gives none. 5 stars a medal: Bronze, Silver, Gold, Platinum, Diamond; the first star takes 350 XP (three wins at
  least), each next star 18% more (Gold about 75 wins, Diamond about 450). The five Diamonds with the most XP on a hero
  are its **Top 5 .. Top 1 Players**. Bots' records fit their years of play (the best have 2-4 thousand games, Diamond
  and Top medals on their mains). Medals show on profiles, hover cards, the pick, the versus and the end screen ("Jayla
  +115 hero XP", "New star", "New medal"). Leaderboard > **Heroes**: each hero's global ranking by mastery.
* **Global ladder**: each bot has a country (Philippines, Indonesia, Malaysia, Thailand, Vietnam, Singapore, Peru,
  Brazil, Russia, Ukraine, United States, Germany, Sweden, China, South Korea, Australia); Filipino-sounding names are
  Filipino; bots from elsewhere chat in English.
* **Bots play at their own skill** (`SimBot.RATED`): reactions, last hits, aim, spells, items (strong cores plan Spell
  Shield, melee ones a Jump Knife; supports Fade Cape and Push Staff; weak bots build random items), item use, farming;
  selfish bots refuse calls and grab lanes ("mid or feed"); ragebaiters dive and flame. 6200-skill bots beat 700-skill
  bots 2/2; 2600 led 1600 in both games.
* Chosen where open (veto any): you start at 1000, bot accounts 1500; 160 bots; K 50; the mastery XP numbers above; Top
  5 needs Diamond; enemy snipe chance 35%; 30 s pick time; countries and their shares.
* New names (veto any): **Ranked**, **Find Match**, **Accept**, **Decline**, **Cancel**, **Hero Pick**, **Lock in**,
  **Random**, "Choose your roles" and note, **Carry**, **Mid**, **Off Lane**, **Soft Support**, **Hard Support**, the
  role lines, "All roles", "Estimated wait", "Your rank", "Your heroes" and its note, "Top of the ladder", "Full
  leaderboard", "Your recent matches", "Finding match", "Players found", the search lines ("Searching for players near
  N MMR", "Widening the search...", "Matching roles", "Balancing teams", "Match found"), "Your match is ready", "Match
  ready", "Everyone accepted. Next: the hero pick", "Your team", "Enemy team", "Average MMR", "First ranked match",
  "Pick N of 10", "Your turn: pick a hero", "<name> is picking", "Picking...", "Wants <hero>", "Choose a hero", "Your
  teammates say in chat which heroes they want.", "Plays ...", "Your record", "Team chat", "<name> picked <hero>",
  "Wait for your turn", "Locked in", "All heroes picked", "Loading the match", "VS", **Bronze**, **Silver**, **Gold**,
  **Platinum**, **Diamond**, **Top N Player**, "Unranked", "hero XP", "New star", "New medal", "Best heroes", "Heroes",
  "Numbers", "Hero XP", "Medal", "On this hero", "No games on this hero yet", "Profile", "Player", "Change picture",
  "Use hero", "Name", "Save", "Playing since", "Behaviour score", "Good", "Fair", "Poor: often flames, feeds or leaves",
  "Last ten", "Drag to turn", "Leaderboard place", "Top rank: climb the leaderboard", "Top ten of the leaderboard",
  "Matches", "Wins", "Losses", "Win rate", "Highest MMR", "Streak", "Best streak", "Left matches", "MMR over the last N
  matches", "Recent matches", "Won", "Lost", "Left", "Everyone", "Top 100", "Near me", "(you)", "Back to leaderboard",
  **Guilds**, "Coming soon", "Soon", "Guild: coming soon", "Season 1" and the footer, "Leave match", "Leaving a ranked
  match counts as a loss.", "Ranked: +N MMR", "Rank up", "Rank down", "Main Menu"; notices ("Pick at least one role.",
  "A player failed to accept. You are back in the queue.", "You did not accept the match.", "You declined. Searching
  again.", "Your last ranked match was left before it ended: a loss", "Picture changed.", "Name saved.", "That file
  could not be read as a picture.", "Choose a picture", "Pictures"); bot chat in the pick and lanes (all lines in
  `src/core/hero_draft.gd`, `src/sim/sim_bot.gd` refusals, `src/sim/sim_team_ai.gd` lane grabs); the country names;
  the generated bot names and their word lists (`src/core/bot_names.gd`; your five examples kept); code `Ranked`,
  `BotNames`, `Matchmaker`, `HeroDraft`, `RankEmblem`, `EmblemView`, `Avatar`, `HeroBadge`, `VersusStage`,
  `RankedNum`, `HeroStage.make_hero`, `rank_metal.gdshader`, `SimBot.RATED`/`rated`/`set_rating`, `GameSettings.ranked`,
  `Main.ranked_match`, env `WOA_RANKED_FILE`, files `user://ranked.json`, `user://ranked_avatar.png`, scenes
  `ranked_menu.tscn`, `ranked_draft.tscn`; tools `tests/tools/ranked_probe.gd`, `emblem_sheet.gd`, `bot_game.gd
  --rating=`; tests `test_ranked_*`, `test_bot_names`, `test_matchmaker_*`, `test_rated_bot_*`, `test_hero_*`.
Evidence: headless tests 291 passed, 0 failed; live probe through real clicks and a real ranked match (search, decline,
accept, pick by click, 3D versus with ten heroes, match with the picked heroes, MMR and hero XP on a win, profile,
leaderboard, guilds, leaving = loss) 45/45; `sh tools/check.sh` no script errors, "Names OK"; captures at 1920x1080 and
3840x2160; bot games in `logs/`; one fresh-context critic pass on the earlier screens (its largest defect fixed).
Not verified: no comparison with Dota 2's client; how bot skill compares with a human player's MMR is a guess; the
versus scene's frame rate on weaker GPUs; the native picture dialog was not driven.
Release build: `build/WarriorsOfAether.exe` rebuilt 2026-10-19 05:47 (exit 0); it cold-starts into a match with no script
errors (`export/match.png`), and the exported pack opens the Ranked screen's offer and the 3D versus
(`export/pck_ranked.png`, `pck_versus.png`; loaded with `godot --main-pack build/WarriorsOfAether.pck <scene>`). A full
ranked match through the exe's own menus was not clicked through (the live probe ran on the project).

**2026-10-18 h: bots' items, chat, teleports, creep pressure, Azrael and Ezee; Dota creep upgrades and mega creeps;
side-lane creeps into the base; take over a bot while watching; Jayla; sounds; Emelrich's run; Jump Knife; new build
(your requests).** Run `work/lemondev/2026-10-18h-bots/` (handoff.md; probes' output and captures there).
* **Sounds.** Ranged heroes' attacks sound like what they throw (`GameAudio._hero_shot`, by ModelCatalog "proj"): only
  Jayla draws a bow; Azrin's fireballs whoosh and burst, Froster's bolts crackle with frost, Feran's knives whip
  (dagger swings, dagger hits; his hits ring as blades), others a spell shot.
* **Ser Emelrich's run.** Every motion-capture run bent his short-legged, long-bodied frame into a deep hunch with
  tiny steps. He now runs on your own run clip (the one most heroes had) with the great sword run's arms laid over it
  so the sword stays in both hands (`RepairedClips.COMPOSED`, clip `hero_run_gs`; joins check 0 failures, feet planted).
* **Jump Knife** (and Crash Knife) lock for 3 s on damage from an enemy hero, **a unit an enemy hero owns** (tamed
  beasts, turrets) or **the enemy fountain**; creeps and towers do not (`SimUnit.jump_lock_at`). Before, only heroes.
* **Jayla, the Blood Ranger** (your name; the hero id stays `blood_ranger`; a saved look named "Blood Ranger" becomes
  "Jayla"). **Gale Impact's push is 30% shorter** (push speed 1150 -> 963: 464 -> 325 units).
* **Creeps (Dota 2's numbers, Liquipedia "Lane Creeps" read 2026-10-18).** Upgrades every 7:30: melee +12 HP +1
  damage +1 gold; ranged +12 HP +2 damage **+3 gold +8 XP** (was +1, +4); super melee +19 HP +2 **+1.5 gold**, base
  **36-44** (was 41-49); super ranged +18 HP +3 **+6 gold**, base **41-46**. **Mega creeps** when all six enemy
  barracks are down: melee 1270 HP 96-104, ranged 1015 HP 131-136 (only their bounty grows). **Siege creeps +16 damage**
  once the lane's ranged barracks falls. Flagbearers stay plain. Super creeps are drawn 1.05x, megas 1.12x.
* **Top and bottom creeps walk into the base** after the tier 3 tower (both teams): they paced at the base's gate (the
  goal flipped back to the gate 220 units past it). Inside, they go for the nearest standing building, the Ancient last.
* **Bots commit to escape teleports** and only start one when no enemy hero they know of can reach them during the
  channel; the only break is a ready Jump Knife with an enemy on top. Two 25-minute games: escapes landed 72/78 (was
  25/35 in one game), self-cancels 0 (`tests/tools/tp_probe.gd`).
* **Creeps on a bot.** It reads how fast the creeps hitting it would kill it: with a clearing spell ready that can
  finish them (every hero's pack spells are listed, `SimBot.CLEAR_SPELLS`) it clears them (bot plan "Clearing
  creeps"); otherwise, low or losing fast, it backs off and keeps backing off 2.5 s instead of flipping every second.
* **Bots' items (deep fix, `src/sim/sim_bot_bags.gd`).** What each held item is worth now (early items fade from 7-20
  minutes, spare boots, parts of nothing planned); sold at the shop, from the stash anywhere, or handed to the courier
  to take home and sell; the six best (actives, boots, a support's Eye Ward) ride in the main slots; parts of the next
  item bought when the whole is out of reach; LATE lists per kind of hero once the build runs out (buyback gold kept
  after 35:00). Root causes fixed: an item bought away from the shop was marked bought while its pieces sat apart (the
  "parts that never complete"), and "Inventory full" skipped the item for good; the courier now combines what
  completes an item in full bags (as in Dota) and combines what it picks up from the stash. Dead bots shop too.
  Two 40-minute games: loose parts 0-2 (was 14), no bot sitting on gold for its next item.
* **Azrael's Soul Tap** is on only while a charge pays (a hero fight close by, a pack her cleave sweeps, a laning hit),
  off once charged, off for one creep or a passing ally, and her charged strike goes to the pack or the hero.
* **Ezee's Leap Strike** only when it is sure to land on the target and worth it: the target cursed by Tainted Touch
  and under 55% (or the blow finishes it), or alone and hurt or running. Tainted Touch now comes first.
* **Bot chat (`src/sim/sim_bot_chat.gd`): 2239 lines**, your 557 (`bot_trashtalk_chat_lines.json`, kept as is) and
  1682 more in 27 categories (`tools/bot_chat_extra.json`; `python tools/bot_chat.py` builds
  `assets/data/bot_chat.json` and `src/sim/bot_chat_lines.gd`). **All chat** (both teams read it; Shift+Enter types
  to everyone, lines marked "(All)"): kills, first blood, streaks, shutdowns, dodged skillshots (new `skill_miss`
  event), deaths to creeps or towers, buybacks, escapes, team fights, towers, megas, the greeting, the end. Team
  chat: anyone (you too) dying again and again or behind on farm, an ally who stood by, excuses, praise. Your lines
  get comebacks. Each bot has its own voice (Pinoy, Taglish or English; how often and how rough). Options > Game
  "Bot trash talk" hides it. About 3-4 all chat lines a minute in a bot game.
* **Take over a bot while watching**: the Watching panel's **Take control** gives you the watched hero with every
  right a player has (its bot sits out), **Give back to bot** returns it (`Main.take_control`, `give_back`).
* **Name checker** (your correction): "remember" was flagged for "ember"; a word now only counts as an invented
  compound when the part before the root is a word of four letters or more, and "Emberstrike"-style compounds are
  caught (they slipped through before).
* New names (veto any): **Jayla**, **the Blood Ranger** (yours); "Mega Footman", "Mega Archer", "Mega Ghoul", "Mega
  Skeleton Archer", "Super Stone Golem", "Super Bone Golem"; "Take control", "Give back to bot", "Played by you",
  "You control <hero>", "Clearing creeps", "(All)", "Say to everyone (Enter to send, Esc to close)", "Bot trash
  talk" and its note; the 1682 added chat lines; code `SimBotBags`, `SimBotChat`, `BotChatLines`, `SimWorld.botchat`,
  `all_rax_dead`, `SimUnit.jump_lock_at`, `is_mega`, `SimBot.human`, `CLEAR_SPELLS`, `_creep_choice`, `_run_clear`,
  `_ezee_leap_ok`, `_tp_safe`, `SimBot17.soul_want`, `soul_plan`, `best_pack`, `SimShop.combine_with`,
  `RepairedClips.COMPOSED`, clip `hero_run_gs`, `Main.take_control`, `give_back`, `controlling`, `watching_match`,
  option `bot_trash_talk`, event `skill_miss`, files `tools/bot_chat.py`, `tools/bot_chat_extra.json`,
  `assets/data/bot_chat.json`, `tests/tools/tp_probe.gd`, `tests/tools/item_probe.gd`; tests
  `test_creep_upgrades_super_mega`, `test_side_lane_creeps_enter_base`, `test_bot_creep_gang`,
  `test_ezee_bot_leap_rule`, `test_azrael_soul_tap_planner`.
Evidence: see the run's handoff.md (tests, probes, bot games, export).
Not verified: no blind critic review; chat lines read in bot games only (no player game); Take control checked by
the live probe and one capture at 1920x1080.

**2026-10-19: shorter bot chat library (text edit only).** Run `work/lemondev/2026-10-19-chat/`.
`bot_trashtalk_chat_lines.json` now contains **557 individually edited lines** in the same ten categories, replacing
1,632 mostly repetitive entries. Filipino/Taglish and English reactions cover kills, revenge, missed spells,
feeding, farm, role complaints and replies. Median length: **3 words** (was 8); **554/557** entries are six words or
fewer. Requested profanity and informal spelling remain; regional/ethnic slurs are omitted. A few longer specific
complaints remain, including the owner's tank/armor example. Metadata counts match; original file: run's `before.json`.
Research: six sources, including actual SEA Dota chat logs, Filipino field observations and player language examples;
links, editorial decisions and limitations in the run's `research.md`.
Validation: `python work/lemondev/2026-10-19-chat/validate.py` prints **JSON contract OK** (shape/category order,
counts, strings, uniqueness, length); `python tools/check_names.py` prints **Names OK**. Independent text comparison
records are in the run directory. This JSON is not referenced by the searched game sources/tools/tests: live bot
speech, chat channels and event/role selection are unchanged and were not runtime-tested. No build was requested.
New game names or identifiers: **none**; all existing category keys remain. New player-visible chat strings are
listed in full in `bot_trashtalk_chat_lines.json` for the owner's review. Unrelated working changes are preserved.

**2026-10-18 g: 150% experience and gold, All-Bot matches you watch, a higher camera, Bots commands in the Debug panel,
new build (your request).** Run `work/lemondev/2026-10-18g-spectate/` (contract.md, handoff.md; logs `logs/`, captures
`shots/`).
* **150% experience and gold by default.** Every hero earns 1.5x experience and gold (bounties, last hits, kills,
  assists, buildings, passive gold, orbs; Unfair bots' own bonus comes on top). Starting gold, Debug panel gifts and
  sell refunds are not scaled. Game Setup has a new **Match** row: Experience and Gold, 100% / 150% / 200% / 300%
  (multiplayer plays 150%). `SimConst.XP_RATE`, `GOLD_RATE`; `SimWorld.xp_rate`, `gold_rate`.
* **All-Bot matches you watch.** In Game Setup set no slot to You (or press the new **Watch bots** preset: five bots a
  side, random heroes); Start then reads **Watch**. In the match nothing you click reaches the game (orders, shop, chat
  are refused: "You are watching this match"), the end screen says which team won, and the **Watching** panel (top
  left, Hide / Show) has:
  * the hero to watch (or click a hero on the top bar), with what its bot is doing now;
  * Camera: **Free** (pan yourself; any pan switches to it), **Follow hero**, **Hero view** (the hero's own view: its
    team's sight, its orders, the camera on it), **Auto** (every 4 s the camera goes to the hero in the biggest fight,
    else the one in most danger; the default);
  * Sight: Hero's team, Ancient Light, Black Sun, **Both teams** (the default), Whole map (only what you see; the bots
    still see what they see);
  * Orders: Off, Watched hero (default), Every hero: each bot's current order and its queue as numbered waypoints (the
    Shift-queue drawing: green move, red attack, blue spell, gold hold);
  * "Show what each bot is doing": a line over every shown hero ("Laning top", "Farming camps", "Ganking Sludge",
    "Defending mid", "Retreating", "Saving Azrin", "Teleporting" ...);
  * Game speed x1, x2, x4 and Pause.
  The HUD (portrait, abilities, items, health) shows the watched hero.
* **The camera starts higher**: 15.6 m from the ground point instead of 13.6 (about 15% more of the map in view; the
  wheel zooms as before).
* **Debug panel > Bots** (F9): pick Every bot, Ancient Light bots, Black Sun bots or one bot, then +1000 gold, +10000
  gold, Take all gold, Level up, Level +5, Max level, Refresh, Respawn now, Kill, Teleport to camera, Stand still, Play
  again, Skill (Passive .. Unfair) and Give item (any shop item into its bags or stash). While watching, "Your hero"
  reads "Watched hero".
* New names (veto any): Game Setup "Watch bots", "Watch", "Match", "Experience", "Gold", "All bots: you watch"; panel
  "Watching", "Hide", "Show", "Free", "Follow hero", "Hero view", "Auto", "Sight", "Hero's team", "Both teams", "Whole
  map", "Orders", "Watched hero", "Every hero", "Show what each bot is doing", "Pause", "Resume"; bot plan lines "Dead",
  "Standing still", "Teleporting", "Retreating", "Going back to heal", "Fighting <hero>", "Saving <hero>", "Helping an
  ally", "Team fight", "Defending <lane>", "Ganking <hero>", "Pushing <lane>", "Grouping up", "Following a team call",
  "Laning <lane>", "Farming", "Farming camps", "Stacking a camp", "Pulling a camp", "Placing a ward"; Debug "Bots",
  "Every bot", "Ancient Light bots", "Black Sun bots", "Take all gold", "Stand still", "Play again", "Set skill", "Give
  item", "Watched hero", "You are watching this match"; end screen "<team> wins"; code `WatchPanel`
  (`src/ui/watch_panel.gd`), `Main.spectator`, `watch()`, `set_cam_mode()`, `cam_mode`, `vision_mode`, `vis_team()`,
  `sees()`, `sees_cell()`, `own_team()`, `fog_bytes()`, `show_orders`, `show_plans`, `CameraRig.user_moved`,
  `SimBot.plan_text()`, `SimDebug.bot_heroes`, `give_item`, `take_gold`, `set_bot_skill`, `set_bot_still`,
  `GameSettings.RATES`, `DEFAULT_RATE`, `watching()`, `xp_rate()`, `gold_rate()`; flags `--watch`, `--watch_cam=`,
  `--watch_vision=`, `--xp_rate=`, `--gold_rate=`, Game Setup capture `--preset=`; test `test_match_rates`, probe
  `tests/tools/watch_probe.gd`.
Evidence: headless tests **274 passed, 0 failed** (1 new, `test_match_rates`; the Dota-number tests run at 100%);
`sh tools/check.sh` no script errors, "Names OK"; `tests/tools/watch_probe.gd` 24/24 twice (`--watch --bots=5v5`, and
through a saved Game Setup with no You slot: your `setup.json` was backed up and put back); captures `shots/`; release
export `build/WarriorsOfAether.exe` rebuilt 2026-10-18 19:29, cold starts into a watched match and a player match with
no script errors (`shots/export_watch.png`, `export_player.png`).
Not verified: no blind critic review; the panel was checked at 1920x1080 only; the Auto camera's pick is a simple
score; bot balance at 150% not re-measured in long games; multiplayer always plays 150% (no lobby setting).

**2026-10-18 f: the five new heroes' kits, bots, icons and effects, new build (your request: "Finish implementing
the new 5 heroes including their skill mechanics, proper icons, proper AI and everything").** Run
`work/lemondev/2026-10-18f-kits/` (contract.md, handoff.md; logs `logs/`, captures `shots/`, icon sheet `icons/`).
* **Airah, Burak, Ser Emelrich, Feran Mock and Ghorman have their full kits** from `hero_ideas.txt` (your annotations
  there win), with talents, the Upgrade Staff upgrades and Burak's innate Rage (`src/sim/sim_kits5.gd`,
  `sim_kits6.gd`). Hero Select no longer says "Skills coming later", and random picks (yours and the bots') can land
  on them.
  * Airah: Gust drags the enemies it hits along with its head, out 900 and back to her (walk away to pull free; a
    crash into a tree, cliff, building or unit hurts more); Tailwind; Wind Wall stops enemy ranged attacks; Hurricane
    drags to its middle, burns, then throws everyone out (a crash stuns 1 s).
  * Burak: Rage (red bar under his mana; attack speed); Axe Throw sticks in the first enemy, tree or cliff, the free
    recast leaps to it and attacks at once, a dropped axe is picked up by walking over it; Reckless Swing (cleave,
    lifesteal, +15% damage taken); Unstoppable spends 40 Rage to shorten a stun, root or hex; Berserk holds half the
    damage back (a dark stretch on his health bar) and returns it over 6 s unless he takes a hero down.
  * Ser Emelrich: Overhead Cut and Giant Swing wind up with a red line or cone on the ground for everyone; once the
    wind-up starts orders wait for it (Stop does nothing), a stun, hex or silence breaks it, with Steel Stance on only
    a hex or silence breaks Giant Swing's; Sweep shoves enemies to his left; Steel Stance blocks from the front.
  * Feran: Knife Juggle (at most 5 knives on one enemy a cast), Joke Box (Pie, Spring, Confetti, Glue), Swap, Shuffle.
  * Ghorman: Tame (neutral or enemy lane creeps, his for good, they keep their spell), Roar, Pack Leader, Blessing of
    the Beast King (D), Beast Form (his body swaps, every 3rd attack mauls). **You can select and order his beasts**
    (click or box select, right click, minimap, Stop, Hold, control groups); left alone they follow him, fight what he
    fights and use their own spell.
* **Bots play all five** (`src/sim/sim_bot18.gd`): fight combos, escapes, farming, Burak's leap only when the fight
  is in his favour, Ser Emelrich's wind-ups only on targets that cannot step out, Steel Stance toward ranged heroes,
  Ghorman taming camp creeps with spells first and blessing hurt beasts. In 30-minute hard bot games every skill of
  every new hero is cast (`tests/tools/kit_casts.gd`).
* **22 new ability icons** (`tools/item_icons.py`, `assets/ui/skills/gen/`), buff bar names for the new effects.
* **Effects** (`src/game/hero18_fx.gd`): Gust's wind, Tailwind's streaks, the Wind Wall curtain, the Hurricane funnel,
  spinning and stuck axes, Rage's glow, Berserk's fire, the wind-up warnings, cut cracks, spinning knives, the gift
  box with its fuse and confetti, swap smoke, Pie and dizzy marks, spirit light on beasts, the roar, the Blessing.
* Fixed on the way: Frenzy Mask's active and Burak's Berserk shared one effect id (a script error in any game with the
  item); a stun ended Giant Swing's wind-up even under Steel Stance.
* New names (veto any): ability names are the file's; "Tailwind" added to the name checker's list of real words;
  buff names "Axe Away", "Pie", "Confetti", "Glue", "Dizzy", "Tamed"; bot chat "Hold on to something.", "RAAAH!",
  "Stand still.", "Everybody move!", "Come here.", "The beast is out."; the five heroes' Hero Select role lines and
  stories; code `SimBot18`, `Hero18Fx`, `SimKits5.BERSERK` (effect `burak_berserk`), icon backdrop `wind`, files
  `src/sim/sim_bot18.gd`, `src/game/hero18_fx.gd`, `tests/tools/kit_casts.gd`; tests `test_new5_data`,
  `test_airah_*`, `test_burak_*`, `test_emelrich_*`, `test_feran_*`, `test_ghorman_*`.
* Chosen where the file was silent (veto any): Blessing of the Beast King heals the beast 30-60%, cleanses it,
  readies its spell and gives +20-50% damage and +20-50 attack speed for 8 s; Airah's talents; Gust's drag strength;
  cast points; bot skill orders (Ghorman takes Blessing at level 8).
Evidence: headless tests **273 passed, 0 failed** (23 new); `sh tools/check.sh` no script errors, "Names OK"; three
30-minute bot games and one 25-minute game (`logs/kit_casts*.log`); in-game captures of every hero's skills
(`shots/`); release export `build/WarriorsOfAether.exe` rebuilt 2026-10-18 09:02, cold starts into Ghorman and Ser
Emelrich matches with no script errors (`shots/export_sheet.png`).
Not verified: no blind critic review; Beast Form still uses its old body (its torn faces at the hips are now seen in
every Ghorman game); bots never use Feran's Upgrade Staff Swap; balance against the older heroes is untested beyond
four bot games.

**2026-10-18 e: motion capture for the remaining clips and the five new heroes, the five made pickable, Airah rebuilt
on the base body, a strict check of every animation join (your requests).** Run `work/lemondev/2026-10-18e-mocap2/`
(contract.md, handoff.md; joins reports `joins_before.txt` -> `joins_final.txt`, remnant renders `remnants_*`, contact
sheets `sheets_all/`, close-ups `close1/`, `close2/`, Airah `airah_prep*/`, `sheets_airah4/`, captures `shots/`, `select2/`).
* **The five new heroes can be picked** (Hero Select, Game Setup, multiplayer): Airah, Burak, Ser Emelrich, Feran Mock and
  Ghorman with the names, titles, ranges, base stats and elements from `hero_ideas.txt` (Airah's element: Lightning, the
  file's pick for its open question). **Their skills are not in yet**: they fight with attacks and items, Hero Select says
  "Skills coming later", and a random pick (yours or a bot's) never lands on them. Bots can play them if picked (roles
  from the file, item builds borrowed from a hero who fights the same way). Hero Select's grid is four cards a row.
* **Airah on `base_female.glb` (your request).** `tools/blender/airah_prep.py` dresses the owner's clean base body in
  Airah's own hair (cat ears, ribbon, clips, head jewel), skirt strips (cut just below the knee), gold belt and tail; her
  top, briefs, collar and arm bands are made from the base body's own skin (her sculpt's garments left the base body
  bare). Tail, belt and hair are pinned to their bones (new `pin.<bone>` vertex groups, kept by `hero_body.py`); the tail
  rides the spine, carried level behind her so it never reaches the floor or her legs. Arms lifted: 0 vertices left
  behind, 0 torn (her old body: 11+7 left, 623+1340 torn). New portrait.
* **Remnants on the other new bodies.** Rebuilt with the unmix step (the arm split and the reach rule tore these
  models apart, so both are off for them; `work/rebuild_new5.sh`): Emelrich 19 vertices left at the hip and 143 torn ->
  0 and 25; Burak 0 and 4 -> 0 and 0. Feran and Ghorman were already clean. Ghorman's Beast Form keeps its old body (it
  needs his ultimate, so nobody can see it yet; its rebuild left finger chunks at the hips).
* **Motion capture for the remaining clips**: runs per weapon (great sword: Ezee, Emelrich; sword and shield: Kragg;
  axe: Sludge, Burak, Ghorman; bow: Blood Ranger; spell: Froster, Tock, Caziel, Feran, Airah), each with its own measured
  ground speed (your old "Running" clip slid its feet: at 300 move speed it was clamped to 0.72x and covered 4.0 m/s
  against the hero's 3.0; it stays the fallback without the library); Leap Strike's leap (the great sword jump attack,
  its own lift taken out because the game lifts Ezee, take-off and landing read from the feet); every push for every
  hero (`ModelCatalog.MOCAP_ALL`): a stagger back that stays on its feet, its recovery, the stagger held while thrown, a
  big hit from behind for wall slams. Caziel's dash-stab is his double stab. Burak swings both axes (Mixamo's two-weapon
  slashes; the one-handed axe swings left his second axe flopping). Azrin and Azrael keep their glide.
* **The five new heroes' motion capture**: Emelrich the great sword set, Burak the two-weapon slashes and the axe set,
  Ghorman the axe set (a chest thump on the stage), Feran an overhand knife throw and the knife idle, Airah the spell set.
* **Joins (your "if they connect properly").** New check `tests/tools/anim_joins.gd`: every crossfade the game makes
  (idle, run, attacks, casts, hits, stun, pushes, deaths, the stage flourish), replayed at 60 frames a second, and every
  loop's seam. The game crossfaded in a fixed 0.06 s however far apart the poses were, so a sword went round 170 degrees
  in a frame: **563 joins snapped** (over 12 degrees a frame beyond the clips' own motion; worst 76). The new
  `AnimBlend` (used by UnitView and Hero Select) plays out each candidate crossfade from the hero's real pose and picks
  the one that adds least to the motion, within the time before the blow lands (creeps use a cheaper gap rule; 0.6 ms a
  hero clip change). Also: no hit-reaction clip while running (the lean is the reaction; it yanked the legs out of the
  stride), the Hero Select flourish eases back to the idle (it was a cut), loops are eased shut at their seam, the
  spinning third great sword slash is left out (no crossfade reaches it without a flip). **Now 23 joins over the limit,
  worst 16 degrees** (the same clips with the old fixed blends: 584, worst 63). Finger bones count 40% (a hand closes in
  about 0.15 s; Roydo's and Blau's grips change 140 degrees between clips).
* **Twists and glitches**: Mixamo's toes curled to 145 degrees and flipped in one frame in falls: toes are now hinges
  (bend only, -50..60 degrees, at most 25 degrees a frame). Hip moves scale with each body's leg length (short-legged
  Emelrich sank 26 cm into the floor in his deaths and slid his feet). The animation audit now checks the clips as the
  game plays them; its remaining "elbow the wrong way" and "forearm twist" findings on the two-handed slashes are raised
  elbows and pronation in the swing, checked by eye on close-ups.
* **Nothing passes through the body**: the push and hit clips were never collision-checked; now every clip each hero
  plays is. With every fix applied, every motion-capture clip on every body is 1.7 cm or less, except Sludge's death
  falling forward (his hook 4.2 cm into the floor).
* New names (veto any): clips `greatsword_run`, `shield_run`, `axe_run`, `bow_run`, `spell_run`, `greatsword_leap`,
  `stagger_back`, `stagger_recover`, `stagger_air`, `hit_from_back`, `dual_slash_1`, `dual_slash_2`; Hero Select text
  "Skills coming later" and the five heroes' short descriptions; code `AnimBlend`, `ModelCatalog.MOCAP_ALL`,
  `MocapClips.leg_scale`, `GameSettings.random_pool`, `SimBotKits.BUILD_LIKE`, retarget options `run`, `seam`,
  `airborne`, `flat`, body-tool vertex groups `pin.<bone>`; Airah's materials `airah_top`, `airah_cloth`, `airah_gold`,
  `airah_skirt`; files `src/game/anim_blend.gd`, `tests/tools/anim_joins.gd`, `tools/blender/airah_prep.py`,
  `work/rebuild_new5.sh`; test `test_new_heroes_and_blends`.
Evidence: headless tests **251 passed, 0 failed**; `sh tools/check.sh` "Names OK"; joins, audit, collision and remnant
reports above; contact sheets of every hero checked by eye (small cells: the look is judged from stills, no video);
teamfight benchmark within its run-to-run spread with and without the new blends (17.5-20.6 ms frames).
Not verified: no blind critic review; 23 joins stay a little over the limit (Burak's run into his battle cry, Blau's run
into his casts, the Beast Form's old clips); the five heroes' kits; Beast Form's body.

**2026-10-18 d: motion-capture animations from Mixamo for nine heroes, the hand remnants, new build (your request).**
Run `work/lemondev/2026-10-18d-mocap/` (contract.md, handoff.md; clip survey `survey_sheets/`, in-game sheets
`game1/`, close-ups `after/` against `work/lemondev/2026-10-18b-hands/before/`, remnant renders `remnants_before/` and
`rebuild2/*_cmp.png`, Hero Select `select/select_grid.png`).
* **Mixamo** (you signed in in the app's browser): 181 motion-capture clips on Mixamo's "Y Bot" (Great Sword, Pro Sword
  and Shield, Pro Melee Axe, Pro Longbow and Pro Magic packs, plus daggers, throws, bites, roars, hits, deaths and a
  stun), downloaded into `work/downloads/mixamo/raw/`. `tools/blender/mocap_retarget.py` puts them on the hero skeleton
  (our rig and Mixamo's both rest in a T-pose facing the same way with almost the same proportions, so every bone takes
  its Mixamo bone's turn; palms and two-handed grips carry over). I rendered every clip on the hero body
  (`--survey`, `tools/mocap_sheet.py`) and picked 64 (`tools/blender/mocap_clips.json`), trimmed so each blow lands
  0.4-0.8 s in (the game speeds a clip so the blow meets the attack point); the hit frame is where the weapon's tip
  moves fastest, set by hand where that was wrong.
* **Who plays what** (`ModelCatalog.MOCAP`; the old clip names the game asks for are turned into these by
  `ModelCatalog.anim`):
  * Ezee: great sword idle, four great sword slashes, a one-hand cast (Tainted Touch, casts), the sword raised and
    slammed down to one knee (Dark Stomp), the sword raised in a power-up (Unholy Might and his Hero Select flourish),
    two great sword deaths, great sword hit reactions.
  * Azrael: three great sword slashes, the ones whose head moves the way her scythe's blade faces
    (`tests/tools/swing_dir.gd`); spells for Door of the End and Divine Darkness; her staff idle and glide stay.
  * Kragg: sword and shield idle, three slashes, a shield thrust (Iron Grip), a power-up (Repel), the sword raised and
    slammed down (Magnet Field), two deaths, a guarded hit.
  * Sludge: a one-handed axe idle and chop, sweep and backhand, a left-hand overhand throw (Shuriken Hook), a grab and neck
    bite (Chomp), a chest thump (Hero Select).
  * Caziel: a knife idle, two double-dagger stabs and a stab.
  * Blood Ranger: a bow idle, draw and loose (attacks, Gale Impact), the overdraw hold (Burst Shot) and its loose, a
    backward dodge (her back leap), bow deaths.
  * Froster, Tock, Azrin: one-hand spell strikes (attacks), one-hand cast, two-hand cast, a two-hand area slam, a wide
    two-hand wave, a big two-hand cast; Azrin throws her Fiery Javelin overhand; Froster channels Endless Winter with
    both hands. Azrin keeps her staff idle and glide.
  * Everyone: small and big hit reactions, a dizzy stun loop, deaths falling forward or back.
  * Kept: runs (your own mocap), Azrin's and Azrael's glide, Leap Strike's timed leap, Caziel's dash, knockbacks.
* **Mixamo's terms**: the clips may ship inside the game but not as loose files, and this repository is public, so the
  clip library and its collision fixes (`assets/characters/hero/mocap/`) and the downloads are left out of git. They
  are in the exported game. Without that folder every hero plays the old clips (tested). Rebuild: "Run it".
* **Hand remnants (your report).** Measured with a new check, `tools/blender/remnant_check.py` (both arms lifted out,
  the elbows bent; it counts mesh at a hand or forearm that does not follow it, and faces torn over 3x). The cause: the
  generated meshes are one fused surface where the hanging hands touch the hips and coats, and each vertex was given to
  the arm or the body on its own, so chips of gauntlet stayed at the hip (Ezee: 160 vertices), coat strips went with
  the hands as long shards (Caziel), and Azrin's sleeves tore off at the hips. `tools/blender/arm_split.py` now decides
  arm or body by which limb's surface a vertex is nearest (each bone's thickness measured from the mesh), switches a
  vertex only when it is clearly nearer the other side, gives every small cut-off piece to the side it is attached to,
  keeps sleeves with the arm (`--sleeve`, Azrin) and blends the weights it adds across elbow and wrist. It runs in
  `tools/blender/hero_body.py` after the old unmix step (`--split`, on by default). Ezee, Azrin and Caziel are rebuilt
  with it (`work/rebuild_qa.sh`). Arms lifted: Ezee 160+2 vertices left behind -> 10+2; Azrin 53+7 -> 1+0, and her
  sleeves now lift whole; Caziel's dagger-like shards and torn coat strips are gone. Azrael keeps her weights (her own
  rig's; the split broke her dress, so `--split=0`). Left: Azrin's sleeve hems are ragged and stretch at the armpit
  when her arms go very high; one plate inside Ezee's left elbow stretches in a deep bend.
* **Nothing passes through the body** (`tests/tools/body_collide.gd -- --fix`, now also for the mocap clips, their
  fixes beside the library): with every fix applied, every mocap clip on every body is 0.9 cm or less. The old clips,
  kept for a game without the library, got worse on the three rebuilt bodies (Ezee's old ground slam 42 cm, Azrin's
  old casts up to 21 cm); none of them plays while the library is present.
* New names (veto any): clips `greatsword_idle`, `greatsword_slash_1`-`4`, `greatsword_spin`, `greatsword_cast`,
  `greatsword_slam`, `greatsword_power`, `greatsword_death_1`/`2`, `greatsword_hit`, `greatsword_hit_small`,
  `shield_idle`, `shield_slash_1`-`3`, `shield_push`, `shield_power`, `shield_slam`, `shield_death_1`/`2`, `shield_hit`,
  `axe_idle`, `axe_chop`, `axe_sweep`, `axe_backhand`, `axe_chest_thump`, `axe_battle_cry`, `axe_hit`, `hook_throw`,
  `neck_bite`, `knife_idle`, `dagger_stab_1`-`3`, `bow_idle`, `bow_shoot`, `bow_hold`, `bow_loose`, `bow_dodge`,
  `bow_death_1`/`2`, `bow_hit`, `spell_idle`, `spell_idle_2`, `spell_strike_1`-`3`, `spell_quick`, `spell_heavy`,
  `spell_area`, `spell_wave`, `spell_big`, `spell_channel`, `javelin_throw`, `spell_death_1`/`2`, `hit_small`, `hit_big`,
  `dizzy`, `death_from_front`, `death_from_back`, `death_fall_back`; code `MocapClips`, `ModelCatalog.MOCAP` and
  `anim()`, body-tool options `--split`, `--sleeve`; files `src/game/mocap_clips.gd`, `tests/tools/mocap_import.gd`,
  `tools/blender/mocap_retarget.py`, `tools/blender/mocap_clips.json`, `tools/blender/arm_split.py`,
  `tools/blender/remnant_check.py`, `tools/mocap_sheet.py`, test `test_mocap_clips`.
Evidence: headless tests **250 passed, 0 failed** (new `test_mocap_clips`; `test_body_collision_sets` covers the mocap
sets); `sh tools/check.sh` no parse errors, "Names OK"; body_collide `--applied` (`collide_applied.txt`); contact
sheets of every hero in the game with its weapons; Hero Select captures of nine heroes; **`build/WarriorsOfAether.exe`
rebuilt 2026-10-18 04:22** (previous pair in `build/previous-2026-10-18d/`), the mocap library inside its package,
cold start into a match as Ezee and to the menu without script errors (the usual shutdown leak warnings).
Not verified: no blind critic review; the look is judged from contact sheets and captures (no video); Leap Strike,
runs and knockbacks are the old clips; the catalog-only bodies (Emelrich, Feran, Burak, Airah, Ghorman) were not
rebuilt and have no mocap mapping.

**2026-10-18 c: release rebuild and main push (owner's request).** Source revision `5f73062` rebuilt with
Godot `4.7.2.stable.official.ed1daf0bf`, Windows Desktop release, x86_64. Runnable output:
`build/WarriorsOfAether.exe` with its adjacent `.pck`; the previous pair is saved under
`build/previous-2026-10-18-build/`. Evidence: `work/lemondev/2026-10-18-build/` (contract, handoff, local logs and captures).
Full mechanics suite: **249 passed, 0 failed**. Two test diagnostic strings had unescaped percent signs; corrected
them and reran both affected tests (2 passed, no formatting errors). `sh tools/check.sh`: no script errors, **Names OK**.
Release export exited 0. Cold exported starts: normal menu and an Azrael match rendered successfully on the RTX 4060;
match ready in 18.05 s with the regression suite running, capture at game time 1:37, exit 0.
No script or loading errors. Known shutdown issue: match reports 1439 leaked ObjectDB instances and 19 resources still
in use; the test suite reports leaks too. Earlier export logs already contain the same class of cleanup warnings.
No gameplay or assets changed in this run; only test messages and build records changed. Independent visual review and a new performance benchmark were not run
(build-only scope). New names: none in game or code; evidence folder `2026-10-18-build` and backup folder above.
Build files remain local under the repository's existing `/build/` ignore rule; source and build records are pushed.

**2026-10-18 b: hero model and animation QA (your Azrael screenshot), and body collision for every clip (your list).**
Run `work/lemondev/2026-10-18-model-qa/` (close-up sheets `before/`, `after*/`, `final*/`, `collide1/`; reports
`collide_*.txt`; in-match capture `shots/export_azrael.png`).
* **Azrael's hands (your screenshot: scythe floating, arms like claws).** The download's hand bones point back into
  the wrist (a 3ds Max Biped converted by Sketchfab: the hand bone's tail is a guess), so every clip folded her hands
  94 degrees and nothing reached the scythe. `hero_body.py` now reads hands from the rig's fingers: the hand points
  from the wrist to the finger roots, rolls so the weapon's axis runs across the palm, and with `--fist` the fingers
  curl into a fist round the weapon and the weapon bone sits inside it. She now holds the scythe in both hands on
  Hero Select and in every swing. Claw tips no longer stick to her hip (they stretched into 25 cm needles): hand and
  finger skin stays on the arm (`hand_lock`).
* **Coats and sleeves webbing up with the arms** (Caziel's heavy strike, Ezee's roar, Azrin's sleeves tearing open):
  no vertex may mix an arm with the hips, spine or legs any more; each goes wholly to one side and the mesh is split
  where they meet (`--unmix`, on by default), so the arm leaves the coat instead of dragging it into sheets.
  Left: one plate by Ezee's left hand still rides his forearm in the roar (it is weighted wholly to the arm).
* **Leftovers of cut-out weapons**: Azrin's model kept a sliver of her old staff's shaft and a chip of its head beside
  her hand, Ezee a floating gold sword knob; a cut now also removes the small loose pieces it breaks off.
* **Sludge** closes his fists round the cleaver and the hook (they were open hands; `sludge.py` curls MakeHuman's
  finger bones before the bind).
* **Portraits** of Ezee, Azrin, Caziel and Azrael re-baked (they showed the old bodies).
* **Body collision (your request: nothing passes through anything).** `tests/tools/body_collide.gd` fits collision
  shapes to each body's own mesh (a solid capsule per bone, centred on its skin; the held weapons as clouds of small
  spheres from their meshes), plays every clip each hero and unit uses at 30 frames a second and finds every arm,
  hand and weapon inside the torso, head, legs, the other arm or the floor. `--fix` re-solves the arms where they
  are (wrist moved out, wrist turned to swing a blade clear, elbow swung away, two hands on one weapon moved
  together), spreads the corrections over the neighbouring frames so nothing pops, checks again, and bakes the
  result to `<model dir>/anim_fixed/<model>_collide.res`, which `RepairedClips` lays over the clips (no cost in a
  match). Worst depth in any frame, before -> after, measured on the clips as the game plays them (`--applied`):
  shared hero body 36.7 -> 0.0 cm, Caziel 23.6 -> 0.0, Roydo 5.2 -> 0.0, Blau 42.5 -> 0.0, Sludge 21.6 -> 2.8,
  Azrin 60.3 -> 3.1, Azrael 65.7 -> 5.3, Ezee 83.4 -> 6.8 (his ground slam: the sword tip in the floor for 3 frames).
  Units: 12 of 16 models 0.0 cm; the three golems and the ogre keep 8-26 cm in a double-fist slam (the fists meet
  with the arms at full stretch). Not covered: cloth, capes and hair against the body (they are skinned, not
  simulated), the legs against each other, two weapons against each other.
* **Also seen, not changed**: Froster's pink spiked crest and Blood Ranger's look are your saved Hero Creator looks
  (`custom` in `user://hero.json`); the capes of the shared outfit pieces are flat panels by design of those pieces;
  Tock's white hair glows bright from behind on the stage; Azrael's Hero Select text still describes her old spirit
  look ("a black robe, a soul of white flame").
* New names (veto any): body-tool options `--fist`, `--unmix`; files `tests/tools/body_collide.gd`,
  `tests/tools/body_shapes.gd`, `work/rebuild_qa.sh`, `anim_fixed/<model>_collide.res`; `RepairedClips.collide_path`.
* Commands: rebuild the own bodies `sh work/rebuild_qa.sh [out_dir] [azrael ezee azrin caziel]`; after any body or
  clip change run `godot --headless --path . -s tests/tools/body_collide.gd -- --fix` (heroes) and `-- --units --fix`,
  then `godot --headless --path . --import`; check with `-- --applied`. Close-up sheets:
  `godot --path . -s tests/tools/anim_sheet.gd -- --heroes=azrael --frames=4 --yaws=0,150 --cell=400x540 --page=4 --fov=20 --aim=1.4`.
Evidence: headless tests 249 passed, 0 failed (new `test_body_collision_sets`); `sh tools/check.sh` "Names OK";
body_collide reports above; close-up sheets of every hero checked by eye; `build/WarriorsOfAether.exe` rebuilt
2026-10-18, cold start into a match as Azrael without script errors. Not verified: no blind critic review; the
catalog-only bodies (Emelrich, Feran, Burak, Airah, Ghorman) were not rebuilt with the new hand and unmix steps.

**2026-10-18: Ghorman's human body, Azrael's new body, and a strict check of every hero animation (your list).** Run
`work/lemondev/2026-10-17f-ghorman-azrael/` (contact sheets in `qa/`, captures in `shots*/`).
* **Your report: Ezee, Azrin and Caziel looked broken. Found and fixed:**
  * **Flipped arms** (the big one). Each own body had its own repaired arm clips (`heroes17/anim_fixed/*.res`), made by
    `anim_repair.gd`, which measures twist and elbow swivel from the rest pose and assumes the hero body's T-pose. The
    own bodies rest with their arms hanging, so it turned arms and wrists the wrong way: Ezee's right arm 150-170
    degrees off in `gs_4` and `boss_slam`, Caziel's hand 100 in `dual_3`, the staff hand of Azrin and Azrael 55-60 even
    in the idle. The own bodies' bone tracks are the hero body's (the retarget keeps every bone's orientation), so they
    now use the hero body's repaired arms (`RepairedClips.path_for`); the per-body files are deleted.
  * **Coats webbing up with the arms** (Ezee's roar on Hero Select, Caziel's heavy strike): the cape and coat cloth
    beside the hanging arms took arm weights. `hero_body.py --reach` now works (its table was missing): skin farther
    from an arm bone than its reach (upper arm 15 cm, forearm 10.5, hand 10, for a 1.8 m hero) loses that bone. Ezee,
    Azrin, Caziel, Azrael and Ghorman are rebuilt with `--reach=1`. Left: one cloth flap still hangs from Ezee's left
    forearm in the roar (tighter reach made it worse).
  * **Flame over Azrin's face**: the "burning hair" flame of her old bare-headed body sat at the head bone, inside her
    new hood. The stage no longer draws it; in a match the hair flame streams behind the hood and the crown burns above.
  * Ezee's greatsword in his idle is the hero body's shouldered two-handed stance; at Hero Select's first angle the blade
    lines up with his helmet, and it clears as the stage turns. Not changed.
* **New check, `tests/tools/pose_compare.gd`**: every own body (and Roydo, Blau) plays every clip the game uses for it
  (idle, run, glide, attacks, casts, skills, Hero Select idle and flourish, death), and each bone's orientation is
  compared frame by frame with the hero body's; FAIL above 25 degrees (`--raw`: before the arm repair, `--all`: every bone).
  Now: every own body within 8.6 degrees. Expected differences it reports: Sludge's own wider-belly arm set (his axe
  clips), the Beast Form's kept hunch (skipped). `anim_sheet.gd` now includes the Hero Select flourish. Contact sheets of
  all 11 heroes plus Ghorman checked by eye: no other breaks. One look note, not animation: Froster wears a magenta crest.
* **Azrael** (your new base `azrael.glb`): her own body now (`assets/characters/heroes17/azrael.glb`,
  `tools/blender/azrael_prep.py` then `hero_body.py`): the two swords dropped, dress, gloves and cape black, the gold
  armour dark steel with pale edges, hair silver-white, lips dark wine; the great scythe in both hands as before. She
  floats (0.42 m) and glides on her own `glide_fwd` clip (chest forward, legs trailing) and the game leans her 7-13
  degrees further into the move with her speed and banks her into turns (your request; `shots_final/azrael_move_*`).
  The old spirit-flame body look is gone (her soul fire, motes, red eye glints and wings stay, eyes re-measured);
  Customize Look is off for her like the other own bodies.
* **Ghorman** (your `ghorman_human.zip`: a bare, bald bodybuilder): dressed as the Beast King by
  `tools/blender/ghorman_prep.py` from the druid pack: the antlered deer skull over the hood, the fur collar recoloured as
  a golden lion mane over the leather shoulder cape, belt and pouches, a knee-length leather kilt over trousers,
  bracers and boots, all fitted to his size; a full dark beard of fur cards and a knotted club with bone teeth and iron
  bands (`assets/weapons/ghorman_club.glb`) are new. In the catalog as `hero_ghorman` (2.05 m, club in the right hand,
  Beast Form as his form `beast_form`, the modifier name his kit must use). Not in matches until his kit lands.
* **Credits**: Azrael's model is "HIT2 Female swordsman" by enzohao, labelled CC BY 4.0 by the uploader. **Check this
  one**: HIT2 is a commercial game (NEXON), so it may be a game rip that the uploader cannot license. Ghorman's
  bodybuilder download carries no author or licence: tell me its Sketchfab page and I will fill in the row. The druid
  pack is ArtLeaving (aptyphawk22), CC BY 4.0.
* Tools: `hero_body.py` reads 3ds Max Biped bone names (`Bip001-R-UpperArm`), `--body_piece` sizes the hero by the body
  alone (antlers do not shrink him); `tests/tools/heroes17_look.gd -- --model=hero_ghorman` draws any catalog body in a
  match; `tests/tools/model_surfaces.gd` lists a model's surfaces as imported.
* New names (veto any): `hero_ghorman`, `ghorman_club`, the `beast_form` form key; files `azrael_prep.py`,
  `ghorman_prep.py`, `pose_compare.gd`, `model_surfaces.gd`.
Evidence: headless tests 248 passed, 0 failed; `sh tools/check.sh` "Names OK"; pose_compare 89 clips, only Sludge's own
arm set over the limit; contact sheets `qa/sheet3`, `qa/sheet_rest`, `qa/sheet7`; Hero Select `qa/select_after`;
`build/WarriorsOfAether.exe` rebuilt 2026-10-18, cold start into a match as Azrael and as Ezee without script errors.
Not verified: no blind critic review; Ghorman not seen with his own kit (none yet).

**2026-10-17 e: new hero models (your picks, CC BY approved), Ezee, Azrin and Caziel on their new bodies.** Run
`work/lemondev/2026-10-17e-hero-models/` (contract.md: who gets which download; captures in `shots/`).
* **In the game now**: Ezee (the black-plate fallen paladin), Azrin (the hooded sorceress, recoloured red and black,
  her crystal staff cut out of the model as her weapon) and Caziel (the hooded priest-assassin, greys lifted so he
  reads from the game camera). Each is its own model (`assets/characters/heroes17/<hero>.glb`), so Customize Look is
  off for them (the tooltip now says "<name> has a fixed look and cannot be customized"). Ser Emelrich (the Bulky
  Knight, whiter steel and cream cloth) and Feran Mock (the assassin body, hood off) are built and in ModelCatalog
  (`hero_emelrich`, `hero_feran`) for when their kits land.
* **How a body is made** (`tools/blender/hero_body.py`, one command per hero, listed in the run's contract): the model
  is bound to the hero skeleton **in its own pose**, and all 132 hero clips are retargeted onto that pose (every bone
  keeps the clip's orientation each frame), so rigid armour barely deforms when the arms hang. Joints come from the
  model's own rig, from a joints file read off grid renders (`tools/blender/grid_render.py` + `tools/grid_overlay.py`,
  files in `tools/blender/joints/`), or from the mesh. Weights come from bone heat on a watertight stand-in when the
  real mesh is made of loose pieces; small rigid pieces follow only the limb they sit on; hanging cloth follows the
  hips more than the legs; split seam vertices share weights. Dense generated meshes (2 million faces) are baked onto
  a clean 40k-triangle copy (colour, roughness, metal, normal; GPU). `--cut` removes weapons fused into hands,
  `--rigid` locks a held prop to one bone, `--hue` / `--gray` recolour. `tools/blender/extract_prop.py` cuts a held
  prop out as a game weapon (Azrin's staff). (Since 2026-10-18 the bodies use the hero body's repaired arm clips; their
  own sets flipped arms.)
* **Azrin's float** (your request): she holds her staff upright (staff idle), glides on a new clip `glide_fwd` (chest
  leaning in, head up, legs trailing with bent knees), and the game leans her 7-13 degrees forward with her speed and
  banks her into turns. Attacks swing the staff (staff_1 / staff_2); her ability clips are as before.
* **Own-made gear** (`tools/blender/heroes17_gear.py`): Ser Emelrich's greatsword (white blade, gold sun guard, gold
  blade plates, long leather grip), Feran's throwing knife (also his new tumbling "knife" projectile) and the Joke Box.
* **Credits**: a **Credits** button on the main menu lists every outside asset and its licence
  (`assets/ui/credits.txt`, written by `python tools/build_credits.py` from `docs/ASSET_CREDITS.md`; run it after
  editing the credits table).
* **About the picks**: the fallen paladin, the sorceress and the priest (and the two unassigned ones, Blackfire and
  Thyrandael) are generated meshes (their archives are named `tripo_convert_...`) by Sketchfab user s8819296 under CC BY;
  they are credited as such.
* **Later the same day**: Burak (the viking berserker with your two axes: "Viking battle axe" right, "Axe" left),
  Airah (Nara the dancer, scarves and tail kept, sparkle rings left out) and Ghorman's Beast Form (the troll with its
  mace, its hunch kept under the hero clips with `--posture`) are built and in ModelCatalog (`hero_burak`,
  `hero_airah`, `hero_ghorman_beast`) for their kits. Burak's and the troll's Sketchfab conversions break their own
  skeletons (3ds Max rigs), so both are rigged from hand-placed joints instead; Burak's eyes and beard were 8 cm too
  high in the download and are moved back. New body-tool options: `--norig`, `--move`, `--keep`, `--capture`,
  `--posture`, `--body_piece`; `tools/blender/prep_weapon.py` turns a downloaded weapon into a game weapon.
* **Not done yet**: (Ghorman's human body: done 2026-10-18 on your bodybuilder download); Feran's
  jester restyle (red and black patched coat, three-point bell hat, half-smile mask); the Ancient Light sun on Ser
  Emelrich's tabard; Ghorman's Beast Form; the five kits (proposed as their own session).
* New names (veto any): the "Credits" menu button and screen; ids `hero_emelrich`, `hero_feran`, `hero_burak`,
  `hero_airah`, `hero_ghorman_beast`, `heavy_greatsword`, `throwing_knife`, `azrin_staff`, `burak_axe`,
  `burak_axe_long`, `joke_box`, clip `glide_fwd`, Beast Form clips use the hero library's boss clips.
Evidence: headless tests 248 passed, 0 failed; changed scripts parse; `python tools/check_names.py` "Names OK";
live captures of Ezee, Azrin and Caziel idle, moving and attacking in a match and on Hero Select (`shots/`); Blender
previews of every body in idle, run and a greatsword swing. Not verified: no blind critic review; Feran and Emelrich
not seen in a match (no kits yet); the exported build not rebuilt.

**2026-10-17 d: QA pass (performance, gameplay, bots, map), the outer ground with map sites, and a 3D sound world
(your list).** Run `work/lemondev/2026-10-17d-qa-map/` (contract.md: baseline and conditions; captures in `shots/`).
* **Performance** (teamfight bench, ten level-16 heroes at 10:00, 1080p, RTX 4060, V-Sync off; same command as the
  baseline, `bench_fight_before*.txt` / `bench_fight_final*.txt`): average **22.1 -> 16.7-17.3 ms (45 -> 58-60 fps)**,
  p95 33.3 -> 28.3-28.8 ms, draw calls ~2290 -> ~1630. Lane bench (5 v 5 bots at 4:00): **15.1 -> 12.8 ms (66 -> 78
  fps)**, p95 20.0 -> 16.7, p99 30.2 -> 22.2. What did it:
  * Unit clips are shared by every unit of a model, and setting their loop mode every tick told every animation
    player to drop its track caches: now set only when it changes (`unit_view.gd _play`).
  * **MeshMerge** (`src/game/mesh_merge.gd`, `gear_merged.gdshader`): a unit's skinned pieces become one mesh with one
    skin, the look's shape keys baked, and every flat or gear surface joined into one surface (colour and material
    numbers per vertex, detail sets in texture arrays); creeps' weapons ride their hand bones inside it. Heroes went
    from ~35 surfaces and ~14 skins each to 3-12 surfaces and one skin; creeps from 7-16 surfaces to one. Creeps of a
    kind and team share one merged mesh, built while loading ("unit meshes prebuilt: 37 models"). `--nomerge` turns
    it off for comparisons; merged and unmerged captures look the same (`shots/hero_*`, `mage_compare.png`).
  * Small worn pieces cast no shadow (the body and anything 0.6 m long still do); Low quality turns unit shadows off.
  * Buildings re-set their damage shader parameter only when their health changes.
  * Not fixed: p99 is still ~50 ms in that bench: Blau's bot spends 40-60 ms in one think when it casts a point spell
    in a fight (seen with `sim_profile.gd`, the new `bot:*` labels); the next thing to fix.
* **Crash on quit fixed** (every benchmark quit with a segmentation fault): the bench probe's lambdas stayed on the
  rendering server's signals, and Azrin's javelin left an orphan mesh each throw (`azrin_fx.gd`). Also fixed: Roydo's
  and Blau's projectiles carried an extra white ball (`fx.gd`), and the Bot Log never counted toggles (Stench showed
  "0 of 57").
* **Map: the outer ground** (`sim_map.gd`). The map is 18432 across (was 16384); lanes, bases and jungle are unchanged.
  Beyond the bottom lane (Black Sun: the top lane) and in both river corners the giant rock massifs and the edge band
  gave way to open ground with forest, walkways and sites; beside the bases the old edge stays rock. The classic
  forest is placed exactly as before (only the 225 trees in the way of the new walkways went).
* **Map sites** (`sim_sites.gd`, `site_view.gd`; Dota's Twin Gates, Lotus Pools and Watchers with their numbers,
  MECHANICS "Map sites"): two linked **Warp Gates** (right click: 4 s channel, 30 mana back if broken, out at the
  other corner), two **Lily Ponds** (a **Healing Lily** every 3:00, up to 6; stand in the pond: 125 health and 125
  mana each, faster in a row, an enemy hero pauses it), four **Lookout Lamps** (1 s channel: your team's 800 / 450
  sight for 7:00; the other team can put one out for 2:00). Tooltips on hover, minimap marks, kill-feed lines. Bots
  light and contest lamps (5-7 lit a side per 25-minute game), gather lilies when hurt nearby, and take a gate when it
  shortens a long walk (seldom happens).
* **Sound world** (`src/game/audio_world.gd`): hits sound by what hits and what is hit (blade, blunt, claw, arrow,
  magic, siege, tower bolt on plate, metal, flesh, leather, cloth, stone, wood, spirit), louder for bigger hits, lower
  for big attackers, muffled and quieter from the fog; tower bolts land with a blast; footsteps of heroes near the
  camera; birds in the trees by day, crickets and frogs at night, the river and the ponds, all placed in 3D around the
  camera; reverb follows the area (forest, river, base walls, mountains). **Effects top out at 60%**: the slider's 100%
  plays effects at 60% of their level (`Options.EFFECTS_CEILING`). New sounds are CC0 (Kenney Impact Sounds and RPG
  Audio; OpenGameArt: isaiah658, syncopika, Wolfgang_, EZduzziteh, rubberduck, Eldritch Grim; `docs/ASSET_CREDITS.md`).
  I cannot listen: the mix and levels need your ears.
* Bots: Stench no longer flips every few seconds (it held 188 toggles in 25 minutes).
Evidence: headless tests 247 of 248 in the full run (the snapshot test failed once while I edited scripts during the run;
it passes on its own on the final code), bot tests 24/24, 4 new tests (outer ground, gate, pond, lamp);
`tests/tools/camp_layout.gd` all camps and sites reachable; `tests/tools/audio_probe.gd` 0 problems; day and night live
runs without script errors; two 25-minute bot games (`bot_game2.txt`); `build/WarriorsOfAether.exe` rebuilt, cold
start into a match without script errors (`shots/export_start.png`).
Not verified: no blind critic review (none asked for); the sites' look and the sound mix are self-checks. Known: two
bots stood idle by the small camp beyond the bottom lane for a minute in one game; bots rarely use Warp Gates.
Names added (veto any): Warp Gate, Lily Pond, Healing Lily, Lookout Lamp, "Use site" (Bot Log), "Lit by ...", "The
lamp is out for N s", "Your team already holds this lamp", "Only heroes can use that", "lit a / put out a Lookout Lamp".

**2026-10-17 c: Double-click self-cast and Azrael skill rework (your list).**
* **Double-click / double-tap self-cast** (`src/game/input_controller.gd`, `src/sim/sim_orders.gd`): double-clicking or
  double-tapping any targeted skill (`point`, `unit`, `autocast_attack`) or active item (`unit` or `point`) within 0.5 s
  while its targeting cursor is up casts it on the hero at once (`h` for unit targets, `h.pos` for point targets,
  `own_turret` for Pilot Turret), without requiring a turn for point self-casts. Town Portal (`tp`) keeps its
  double-click / double-tap teleport to the fountain.
* **Azrael's 1st skill (`soul_tap` - Soul Tap) rework** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_combat.gd`, `src/sim/sim_abilities.gd`, `src/sim/sim_bot17.gd`): changed to a **Toggle** skill. While
  toggled on, every 4.5 s Azrael scans a 600 area around her for souls (all living units including allies and enemies,
  excluding herself, buildings, wards, couriers and units inside a door). If there are no valid targets in range, no
  mana is spent and it continues scanning every 4.5 s; if there is at least one valid target (and she has 80 mana), it
  consumes 80 mana and grants +20/25/30/35 bonus attack damage per unit scanned plus +40 more per hero scanned for her
  next strike. That next attack deals **Pure** damage in a **100% cleave over a 400 area**, slowing the primary target
  and all cleaved enemies by **80% for 0.80 s**.
* **Azrael's 2nd skill (`door_of_the_end` - Door of the End)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_orders.gd`, `src/sim/sim_unit.gd`, `src/sim/sim_combat.gd`, `src/ui/buff_bar.gd`, `src/ui/hud.gd`):
  units inside the door can **prematurely step out** by issuing a move, attack or pickup order while inside (bringing
  that unit out at the exit, or entrance if no exit was set, without triggering the explosion). When the door explodes
  at the end of its duration, in addition to its 150/250/350/450 magic damage in a 450 area, it **heals nearby allies
  for 100/150/200/250**, **stuns all affected enemies for 1 s**, and **strips 10/16/22/28% of their Elemental
  resistances for 4 s** (`element_resist_loss`).
* **Azrael's 3rd skill (`death_scythe` - Death Scythe)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`,
  `src/sim/sim_combat.gd`): also **lifesteals 50%** of the damage done when it strikes; cooldown lowered to **1 s**
  (was 1.5 s).
* **Azrael's Ultimate (`divine_darkness` - Divine Darkness)** (`src/sim/sim_data.gd`, `src/sim/sim_kits4.gd`): she
  moves **15% faster** at all levels while Divine Darkness is active.
Evidence: headless tests 244 passed, 0 failed (updated `test_azrael_data`, `test_azrael_soul_tap_charge_and_cleave`,
`test_azrael_door_of_the_end`, `test_azrael_death_scythe`, `test_azrael_divine_darkness`); live `input_probe.gd --
--hero=azrael --lvl=18 --nobot` 19 passed, 0 failed (including Soul Tap toggle on/off, quick cast, double-click skill
self-cast, double-click Push Staff self-cast, and Town Portal double-tap to fountain); `modifier_census.gd` 0 unnamed;
`python tools/check_names.py` "Names OK"; `build/WarriorsOfAether.exe` rebuilt 2026-10-17.
Names added (veto any): "Elemental resistance -N%" (buff tooltip / stat sheet line).

**2026-10-17 b: Azrael, talent trees, tree-felling spells, player labels, kill card, Bot Log, Blau's bot, Dota gap
report (your list).** Run `work/lemondev/2026-10-17-azrael/` (captures in `shots/`, Blender previews in `preview/`).
* **Talent trees for Blood Ranger and Ezee** (the two heroes without one). Their spells read the old way and ignored
  talents; they now go through `SimAbilities.val` / `_cv`, so talents and the Wide Stone family count. Blood Ranger:
  +10% Masterful Archery chance or +20 Attack Speed; +100 Gale Impact damage or +15% Burst Shot damage; +150 Blood
  Ranger attack range or -4s Gale Impact cooldown; +20% Blood Ranger lifesteal or +25% Masterful Archery damage.
  Ezee: +10 Strength or +60 Dark Stomp damage; +0.6s Dark Stomp stun or +50 Tainted Touch damage; -4s Leap Strike
  cooldown or +40% Leap Strike strength damage; +10% Unholy Might chance or +4s Unholy Might. Bots pick them.
* **Trees**: Fiery Javelin knocks down every tree on its path; Bounce Shot fells the tree it ricochets off.
* **Player names**: heroes read "lemonQ (Ezee)": the player in their player colour (Dota's ten slot colours, by team
  and order), the hero in its team's colour, over the health bar, in the kill feed, kill card, chat and scoreboard.
  Your own name is the name in Multiplayer settings (it starts as your Windows user name).
* **Kill card**: a hero kill shows both portraits sliding in, a blade slash across the fallen hero, a few sparks off
  the blade, a light sweeping the band and your gold counting up (First Blood, Shutdown and multi-kills as its title);
  2.8 s, shortened to 1.9 s while more kills wait. New kill-feed lines get a soft light running across them once.
* **Bot Log** (Debug panel, F9): per bot, thoughts, orders and whether its own thinking or a team call gave them,
  orders by kind, skills used out of ordered, items used, time in each mode, mode changes with the scores behind them,
  team calls, lines said, and its latest 24 steps; "Every bot" lists the summaries; **Save Bot Log** writes all of it
  to `user://bot_log.txt`. Headless: `bot_game.gd -- --botlog[=Bot Ann]`, `bot_duel.gd -- --log=A`.
* **Blau's bot** (the log showed it: 12 Bounce Shots in 14 minutes, 11 s fighting, lane/retreat flips every second or
  two): it pokes with every sure Bounce Shot (a pending last hit no longer stops a shot that passes the hero squarely),
  drops a turret on the enemy laner near its wave from level 6, goes for the kill with boulders, turret, shot and
  attacks when its spells and three seconds of attacks can finish the laner (not under a tower, not into more heroes),
  and its damage estimate counts the shot's usual two passes. **Every bot**: backing off from a stronger enemy now
  holds 2.5 s (or until it is 1400 away) instead of flipping back into lane the moment it steps out of 1000. Duels
  (12 min, 3 seeds, `blau_duels_before.txt` / `blau_duels_after2.txt`): deaths against Azrin 9 -> 3, Roydo 1-2 ->
  2-2 in kills, last hits against Ezee even (it was behind). Azrin still out-farms him.
* **Azrael, the Death Dealer** (your kit and numbers; melee 150, Dark): Soul Tap, Door of the End, Death Scythe,
  Divine Darkness as you wrote them (`src/sim/sim_kits4.gd`). How the open points were settled (veto any): Soul Tap
  counts every unit in the area but her (not buildings, wards, couriers); the charged blow cleaves with Dota's cleave
  cone (150 to 360 wide, 650 long) and ignores armor; recasting replaces the charge. Door of the End: she and allied
  heroes step in by walking onto the door (a move order ending there, or standing on it), two allies at most; inside
  they are hidden, invulnerable and cannot act; the second cast places the exit (no mana, no cooldown, castable from
  inside); with no exit placed they come out of the entrance; the blast is at the exit. Death Scythe works on her
  attacks and her spells' damage (not items), pseudo-random, 1.5 s apart. Divine Darkness: her night sight becomes
  her day sight, then +30/50/70%; enemies within 700 lose 30/40/50% of their sight; she flies straight over cliffs,
  trees and units and lands on open ground (felling trees she lands among).
  * **Look**: your female body (Azrin's) as a soul of white flame: a spirit mode in its shader (pale, glowing edges,
    flame rising through her, red eyes in darkened sockets, the legs gone below the hips), long white hair falling
    from a black hood, a long black robe, white soul fire streaming off the hem as she floats, motes and a cold light,
    red eye glints. The great scythe (carved dark shaft, leather wraps, old silver fittings, crescent blade with an
    etched band and a bright edge, a back spike) and the wings (white feathers, three jointed parts each, they open,
    beat and fold) are modelled in `tools/blender/azrael.py`. **Fixed after your report**: the blade faced the wrong
    way. Measured with `tests/tools/swing_dir.gd`: in her swings the head moves toward the weapon's +X, so the blade
    now points that way and its tip leads; the one backhand clip (gs_2) is left out of her attacks.
  * **Effects** (`src/game/azrael_fx.gd`): Soul Tap's crimson ring with a soul wisp flying from every unit to her and
    the crimson charge on her blade; the charged slash, a black-and-crimson crescent; a thin white crescent on every
    blow; Death Scythe's silver slash; the spirit door (a dark swirling void with white threads and red veins in a
    bright arch) at both ends, units fading in and out, the spirit blast; the wings with darkness pooled round her and
    a dark haze on blinded enemies. All particles and small shaders, freed with what they show.
  * **Bots** (`src/sim/sim_bot17.gd`): wings when a fight is on; Soul Tap where it gathers the most souls with the
    target among them, then the slash; in lane Soul Tap on the laner standing among its creeps; Door of the End to
    escape (a door at her feet, the exit toward safety) and, with the door at level 3+, to dive (the exit placed on
    the weakest enemy in reach in the last 0.9 s); Soul Tap on creep packs to cleave them; allied bots that are
    running walk into her open door. Duels (12 min, `azrael_duels*.txt`): she trades evenly with Ezee and Caziel in
    kills but out-farmed by them; Azrin wins the lane as he does against most heroes.
  * Chosen numbers (veto any): agility, str 19 (+2.2) / agi 22 (+3.0) / int 17 (+1.7), 27-31 damage, armor 1, 300
    speed, attack point 0.35; Door of the End mana 100-130, entry reach 110; Divine Darkness mana 100/150/200; cast
    points; talents: +25 Attack Speed / +6 Soul Tap damage per unit; +250 Health / +1s Door of the End; +8% Death
    Scythe chance / +40 Death Scythe damage; +150 Door of the End damage / -20s Divine Darkness cooldown.
* **Dota 2 gap report** (`work/lemondev/2026-10-17-azrael/dota_gap_report.md`): what the game has, the top 10 gaps
  (kill economy numbers, ward stock, the Attribute Bonus and talent points, Roshan, Upgrade Staff and Gem for 8 of 10
  heroes, illusions, Smoke and Scan, control items and effects, neutral items, the 7.38-7.41 map layer) and tables by
  area with Dota's numbers and sources. Its numbers are from the Fandom wiki and patch summaries (Liquipedia rate
  limited); see its last section for what could not be confirmed. Nothing in it is implemented yet.
Evidence: headless tests 244 passed, 0 failed (new: Blood Ranger and Ezee talents, Fiery Javelin and Bounce Shot fell
trees, Azrael data, Soul Tap charge and cleave, Door of the End (two allies, free exit, blast, no exit), Death Scythe
(pure, 1.5 s apart, not items), Divine Darkness (sight, blind, flight, landing), Blau hunt, Bot Log counters); every
test world now starts with the whole forest; `sh tools/check.sh` no parse errors, "Names OK"; a 20-minute 5 v 5 bot
game with two Azraels and two Blaus (`bot_game.txt`): no script errors, no hang (224 s), both Azraels used all four
skills (Soul Tap 18 and 31, Door 3 and 4 doors, the wings 3 and 5 times); captures `shots/` (kill card, Hero
Select, look variants, Soul Tap, the slash, the wings, the door, the swing sheet); `build/WarriorsOfAether.exe`
rebuilt 2026-10-17 04:01, cold start into a match as Azrael, no script errors (`shots/export_azrael.png`).
Not verified: no blind critic review (none asked for); the look and every effect are builder self-checks, not
compared with a commercial reference; the door shows its entry only to her team and to enemies who see the spot.
Names added (veto any): the talent names above; Bot Log, Save Bot Log, Every bot, "Going for <hero>." (bots),
"Opening the door.", "Into the door.", "No escape from me." (Azrael's bot lines), "Inside the door", "Cannot place a
door there" (cast errors). New owner names recorded in `lemondev/references/naming.md`.

**2026-10-17: Monitor option.** Options > Video has a new first row, **Monitor**: "Main monitor" (the one Windows
calls main, the default) or "Monitor 1 (1920 x 1080)", "Monitor 2 ..." for each plugged-in screen. The game opens on
that screen at boot and moves there at once when you change it, in every window mode; if the chosen monitor is
unplugged it falls back to the main one. A window you drag to another screen stays there until you change the choice.
Saved as `monitor` in `user://options.json` (`src/core/options.gd`, `src/ui/options_panel.gd`).
Evidence: on this PC (two 1920 x 1080 screens) a live probe moved the Fullscreen window to screen 2 and back (window
reported on the wanted screen each time); capture of the Video tab (`work/shots/monitor/options_video.png`);
parse check clean, "Names OK". `build/WarriorsOfAether.exe` rebuilt 2026-10-17 00:32; cold start to the menu, no
script errors. Not verified: Borderless and Windowed moves (same code path), no headless test (needs real screens).
Names added (veto any): Monitor, Main monitor, "Monitor N (W x H)".

**2026-10-16 b: your mechanics list.** Run `work/lemondev/2026-10-16b-mechanics/`.
* **Grip of the Ruler** needs someone to throw: on an area with no unit it does not go off, says "No valid target",
  keeps the targeting cursor and spends no mana or cooldown (also checked again when the cast point ends). It now
  seizes units hidden in the fog, but never an invisible enemy (unless your team has True Sight on it).
* **Town Portal double tap**: T twice within 0.5 s, or two clicks on the Teleport slot, teleports to your fountain
  (the usual 3 s channel).
* **Bots push** in lane when no enemy hero is near (none seen within 1600 in the last 3 s): they kill the wave (last
  hits first, then the weakest creep) and hit the tower while one of their creeps tanks it, from the start of the game
  (a support next to its core leaves the creeps to the core). **Ahead in net worth** (10% or more, gaps under 1000 gold
  ignored): bolder: lower retreat bar, fights taken on smaller chances, trades more often, kills chased on smaller
  leads, the lane push also with an enemy known nearby but out of sight, and a team 20% ahead calls pushes from 10:00
  ("We're ahead in gold. Let's push ...").
* **Blau**: Bounce Shot flies 400 further after every ricochet (aim line and bots include it). Summon Boulders rolls
  toward the point you click, as far as it, 200 at least and 700 at most (cast range 700, cast from where he stands);
  no boulder rolls past that distance. They rest within 2.5 s (was 1-2 s).
* **Switch Boots** (Power Treads): three icons for the attribute they are set to, in the inventory, backpack, stash,
  courier, drag and on the ground: red boot with a fist (strength), green boot with a feather (agility), blue boot
  with a star (intelligence). The shop keeps the old icon. `tools/item_icons.py`, sheet `treads.png`.
* **Unfair bots** (your numbers): +200% gold (bounties and passive gold) and +50% experience (was +25% of both); melee
  Unfair bots buy a Jump Knife right after their boots. Every bot with a Jump Knife (melee, not Sludge, who has his
  own) now jumps onto the enemy hero it fights from 300-1100 away when healthy, not onto an enemy tower unless the
  target is nearly dead and not into more enemies than allies; escapes with it as before.
Evidence: headless tests 235 passed, 0 failed (new: grip with no target, fog and invisible; bounce reach; boulders at
300 / 700 / 2000; Unfair gold, xp, passive gold; Unfair knife plans; jump-in; pushing alone and not with a hero near;
tower hits early; net worth lead; Switch Boots icons); `sh tools/check.sh` no parse errors, "Names OK"; live
`input_probe.gd` as Roydo 15/15 (grip on empty ground keeps the cursor, HUD shows "No valid target", nothing spent;
T, slow T, double T: the hero arrives at the fountain) and as Blau 17/17. 20-minute 5 v 5 bot games (`bot_game_*.txt`):
Hard seed 3 and Unfair seed 7: no script errors, no hangs; Unfair: every melee bot bought a Jump Knife, team net worth
88559 / 82991 at 20:00 against 19634 / 21034 on Hard. Same seed before the change (`bot_game_before.txt`): towers
lost 4 and 3 after, so pushing in real games is not shown to be stronger yet (one seed). `build/WarriorsOfAether.exe`
rebuilt 2026-10-16 22:19; cold start into a Blau match 20 s, no script errors (`export_blau.png`).
Not verified: no blind critic review (none asked for); the new icons are a builder self-check.

**2026-10-16: two new heroes, Roydo and Blau (your kits and numbers).** Run `work/lemondev/2026-10-16-roydo-blau/`
(contract.md, sources.md; captures in `shots/`, frame sheets in `preview/`).
* **Models**: free CC0 Quaternius packs (Universal Base Characters, Universal Animation Library 1 and 2, Modular
  Character Outfits - Fantasy, Sci-Fi Essentials Kit; list and upload ids in `sources.md`), built by
  `tools/blender/heroes16.py` into `assets/characters/heroes16/`. Roydo: an obsidian-skinned alien with a star-field
  skin shader (`src/game/roydo_skin.gdshader`) and a second, hulking monster body for the Anomaly (swapped in and
  out). Blau: a hooded gunner in a recoloured ranger coat with a scout sniper rifle held in both hands; his turret is
  the kit's four-legged Quad Shell walker. Animations come from the library clips (motion-captured style), not the
  procedural set: audit `anim_pops16.txt`: no joint flips (> 90 degrees in one frame) and no elbow or knee bent
  backwards in any clip used; 85 fast turns of 45-60 degrees remain in the quickest swings, get-ups and knockbacks.
* **Roydo, the Anomaly** (melee, intelligence): Grip of the Ruler, Void Rush, Dark Matter Skin, Anomaly as you gave
  them. **Blau, the Master Tactician** (ranged 600, agility): Bounce Shot, Summon Boulders, Lay Trap, Place Turret;
  the turret's shots carry his attack effects. Pilot Turret comes with the Upgrade Staff (Dota's Aghanim's Scepter).
* **Bots** (`src/sim/sim_bot16.gd`): Blau traces two dozen Bounce Shot angles through the trees, walls, boulders and
  units round him and fires the one that passes enemy heroes most; boulders roll ahead of a fleeing target to wall it
  in, or into a melee hero on top of him; when chased he faces the chaser so Lay Trap's leap leaves the snare in its
  path; turrets go down in every fight and in front of towers he pushes; with the Upgrade Staff he climbs into a turret
  when hurt. Roydo opens with Void Rush (lower status resistance makes the stun last longer), then Grip of the Ruler
  centred between the target and him, Anomaly once a real fight is on, Void Rush's speed to run. Every bot knocks down
  enemy turrets.
* **Chosen fill-ins (veto any)**: base stats: Roydo str 21 (+2.6) / agi 18 (+1.8) / int 24 (+3.2), 28-34 damage,
  armor 2, 305 speed; Blau 18 (+2.0) / 23 (+3.1) / 18 (+1.8), 22-28 damage, 295 speed, 3000 projectile. Mana: Void
  Rush 80-110, Anomaly 100/125/150, Bounce Shot 90-120 (12/11/10/9 s), Summon Boulders 100-130, Lay Trap 50-65,
  Place Turret 100/125/150. Bounce Shot damage 70/110/150/190, travel 1800 at 2400. Boulder cast range 600, roll
  speed 520-760. Trap: lasts 25 s, 110 trigger radius, arms after 0.6 s. Place Turret a 3-level ultimate, damage
  25/30/35% (+5% with the Upgrade Staff, so 40% at level 3). Pilot Turret 250 range. Anomaly projectile 1200.
  Talents as listed below.
Evidence: headless tests 225 passed, 0 failed (new: Grip target order, toss and stun, ally unharmed; Void Rush both
sides; Dark Matter Skin; Anomaly attack time, damage, range and the return to melee; Bounce Shot reflections off a
tree, wall, boulder and ally, passing enemies, bounce cap, two hits per enemy; boulders count, roll, blocking phased
units, one hit and push; trap leap, root and durations; turret range, interval, share of the attack with procs,
health, no regen, life; Pilot Turret needs the staff, health, safety, exit, cooldown; bots banking Bounce Shot,
trapping on escape, turret and pilot, Rush then Grip, bots knocking down turrets).
* **Found and fixed at integration: games froze once a Roydo bot used Anomaly in a lane.** In Anomaly he attacks at
  range, but as a melee hero he has no projectile speed of his own; the bots' last-hit forecast divided by it, got an
  infinite time and looped for ever (`sim_bot.gd` `_last_hit_target` / `_hp_when`). It now uses the form's projectile
  speed (`SimUnit.projectile_speed()`), and `_hp_when` caps an infinite time. Found with the new
  `tests/tools/stall_probe.gd` (prints slow steps and can trace each step); regression test
  `test_bot_roydo_anomaly_last_hit_forecast` (fails on the old line, passes now). This is why the interrupted
  session's Roydo duels and bot game never printed a result.
Bot duels, 12 min, 3 seeds each, after the fix (`duels_final.txt`; kills summed, last hits per seed): Roydo vs Ezee
1-0 (LH 42-48 against 11-30), vs Sludge 0-1 (27-34 against 18-32), vs Blood Ranger 2-3 (33-43 against 22-37), vs
Kragg 1-2 (Roydo far ahead in one seed, behind in the other two). Blau before the fix (`duels.txt`): vs Ezee 1-1, vs Kragg 0-2, vs Azrin 0-12. A 20-minute
5 v 5 bot game with two Roydos and two Blaus (`bot_game.txt`): ran to time in 178 s, no script errors, 39-24 kills;
one bot stuck (Roydo, from 11:19, a known issue). `sh tools/check.sh`: no parse errors, "Names OK".
Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-16 20:03 with the fix; cold start into a Blau match 12.6 s and a
Roydo match 12.5 s, no script errors (`shots/export_blau.png`, `export_roydo.png`). Blau vs Roydo (after the fix):
1-1 in kills, but Roydo out-farms him (LH 34-53 against 17-24).
Not verified: no blind critic review (none asked for, no Dota frames on disk); the look of both heroes and every
effect is a builder self-check (`shots/`). Left: in the trap capture a rooted creep's timer reads "Rooted 0.0" on its
last frame; Blau's bot loses his lane against Azrin and is out-farmed by Roydo in bot duels.

**2026-10-15 h: lane creep and unit animations repaired (follow-up to g).** Run `work/lemondev/2026-10-15h-unit-anims/`.
* The 16 humanoid unit models (lane knights and mages, Black Sun's ghouls, necromancers and chieftains, both siege
  golems, goblins, orcs, the troll, the ogre, the imp and the magma golem) played the same broken library clips as the
  heroes. `tests/tools/anim_repair.gd -- --units` now repairs each model's clips on its own rig, keeping hands and
  blades out of a body measured from that rig (shoulder width and height) and using the weapon the unit holds; one
  library per model in `assets/characters/units/anim_fixed/`. `RepairedClips` (was HeroAnims, now
  `src/game/repaired_clips.gd`) loads the right set for every model in matches, menus and the Hero Creator. The
  hand's speed limit now moves it on an arc round the shoulder (a too-fast slam swings forward and down instead of
  cutting through the chest); the hero clips were rebuilt with it too.
* Audit (`anim_audit.gd -- --units`): 188 findings on the original unit clips (bones flipping up to 180 degrees in one
  frame) -> 44 after; the largest turn left in one frame is 68 degrees. Heroes: 85 (was 86 in g), largest 73.
  Before/after sheets: `units_before_after.png`, `big_units.png` (golem and ogre slams).
* The lane knight's shield is strapped along its forearm at 80%, as Kragg's.
* Fixed an older bug the audit found: four units named attack clips their models do not have, so the hill troll
  attacked with no animation at all. Now: hill troll `axe_1` / `axe_2` (an overhead throw), ogre `boss_slam` /
  `gs_1`, goblin foreman and necromancer `staff_1` / `cast_quick`.
Evidence: headless tests 208 passed, 0 failed; `sh tools/check.sh` no parse errors, "Names OK"; a live match with
the repaired unit clips loaded, no script errors; `build/WarriorsOfAether.exe` rebuilt 2026-10-15 22:13 (the 16 unit
sets inside), cold start into a match in 24 s, no script errors.
Left: the knight's shield edge still touches its thigh in some sword frames (as Kragg's), staffs of the lane mage and
orc shaman pass the body in 12-28% of frames of their staff swings, golem and ogre slams show the elbows pointing
up in a few frames at the top of the swing (arms straight overhead, where "natural" is ill defined); no blind review.

**2026-10-15 g: Kragg rework, varied bot picks, smarter bots, animated title and new Main Menu, hero animations
repaired (your list and your report on the twisting limbs).** Run `work/lemondev/2026-10-15g-kragg-bots-menu/`
(contract.md; captures in `shots/`, `anim_before/`, `anim_after/`, `compare/before_after.png`).
* **Kragg** (your numbers): **Magnetize is his innate**: learned at level 1, no point, no slot; it shows in the small
  innate slot, in the Talents button's tooltip and at the head of the open talent tree. Attacks give a Charge (up to
  4, 8 s); each Charge makes the enemy take 0.10% + 0.05% per hero level more damage from his spells (level 30: 1.6%
  a Charge). I read "+0.05 per hero level" as times his level (level 1 = 0.15%); say if it should start at 0.10% at
  level 1. **Overload is passive**: every 6th / 5th / 4th / 3rd attack bursts round him: enemies within 200 take
  60 / 75 / 90 / 105 magic damage of the Lightning element and are slowed 80% for 0.8 s; his buff bar counts the
  attacks. Kragg now has four skills (Q W E R). Talent "+25 Overload damage per Charge" became "+40 Overload damage".
  Bot duels after the change (12 min, 3 seeds each, kills summed): Kragg vs Ezee 6-0, vs Caziel 8-4, vs Blood Ranger
  5-6, vs Sludge 1-4, vs Azrin 1-9 (`duels.txt`): no longer the strongest laner.
* **Varied picks**: Random slots are filled after the chosen ones; a team never gets a hero twice while another is
  free, prefers heroes nobody in the match has, and prefers ones that fill a missing role (single player and
  lobbies). Test: 300 seeds, no team duplicates, no hero three times in a match.
* **Smarter bots**:
  * Items (`sim_bot_items.gd`): every 30 s from 5:00 and after each death a bot reads the enemy team (magic, physical
    and pure damage weighted by how far ahead each enemy is, stunners, invisible heroes, evasion) and what killed it
    (damage by type in its last deaths, fading), and moves one counter item to the front of its build: magic
    resistance or Spell Shield against magic and stuns, armor or evasion against fed right-clickers, Sure Hit Staff
    against evasion, Jump Knife / Push Staff / Slip Boots after dying caught alone; supports get Fade Cape, Medic Kit,
    Guard Boots. Reveal Dust and Reveal Ward against invisible heroes. One counter at a time until bought. In the base
    late with every slot full it sells its cheapest early item. New uses: Fade Cape and Push Staff to save an ally
    being brought down, Reveal Dust on an enemy that just faded, Spell Shield when a stunner chases it.
  * **New items** (Dota 7.41d): Scarf (Shawl, 450, 10% magic resistance), Spell Cloak (Cloak, 900, 18%), Fade Cape
    (Glimmer Cape, 2150: 20%; on an ally or itself: invisible after 0.5 s for 5 s, 20% faster, a 375 magic-damage
    barrier). In the shop (Armaments / Upgrades) with icons.
  * **Counter-ganks** (`sim_team_ai.gd` `_call_saves`): an ally caught by enemy heroes is not left to run: the brain
    weighs the gankers against the victim plus every bot that can arrive before the victim would die (walking, or a
    Town Portal after 10:00), and when that fight is in our favour calls a save: helpers come, the victim runs toward
    them (pulling the gankers in), then everyone turns on the same ganker. Chat: "Hold on, <name>! Coming." / "TP
    coming", "Running to you, help me turn on them."
  * **Jukes** (`sim_bot_tactics.gd`): a bot on the run picks spots 350-800 away that a tree line or high ground hides
    from its chasers (where they were last seen; no peeking into the fog), among trees, out of the enemy's sight; once
    the enemy has not seen it for 2 s and nobody is in sight, it teleports home from the fog (hurt, or short of mana;
    before 8:00 only when badly hurt). "Lost them in the trees, going home."
  * Two 45-minute 5 v 5 bot games (`bot_game.txt`; the counters below were measured before three fixes from these
    games: no juke teleport before 8:00 unless badly hurt, no Town Portal saves before 10:00, one counter item at a
    time): no script errors; per game and team 33-58 counter-ganks called, helpers fought in 32-72 of them, 4-9 juke
    teleports home; counter items bought as above. No winner at 45:00 in either game (kills 92-33 and 93-31 for the
    same side, a lopsided lineup). Old issue still there: a few bots stuck (1-3 per game).
* **Title and Main Menu** (your request): an animated title the first time the menu opens: the gold sun of Ancient
  Light and the black sun of Black Sun rise either side, sparks drift up, the title burns in and a light sweeps across
  it, "by Aljay Leodones" is written out between gold rules, then "Press any key". The menu is remade with new art
  from `tools/ui_skin.py`: a hanging banner with the title and an emblem of the two suns, the menu as blade-shaped
  plates (gold for Play) that slide in one by one and light up on hover, a framed nameplate for the hero on the stage
  with Choose Hero, and a footer with the credit and rotating tips. Up / Down and Enter work too. Captures at 1080p
  and a real 3840 x 2160 window (`shots/title_*.png`, `menu_after.png`, `menu_4k.png`, `menu_hover.png`).
* **Hero animations (your report)**: measured, not guessed. `tests/tools/anim_audit.gd` checks every clip each hero
  plays, frame by frame. On the clips as built (they come from the beyond-heroes procedural library, and the lane
  knight has the same faults, so they are in the library, not the hero body) it found elbows flipping to the other side
  of the arm and forearms spinning up to 177 degrees between two frames 1/30 s apart, wrists bent up to 154 degrees,
  forearms twisted 130, and Kragg's shield and sword through his body: 352 findings over the eight heroes.
  `tests/tools/anim_repair.gd` solves every arm again (hand path kept, elbow continuous and within a natural range,
  forearm twist where a real arm turns, wrist clamped, snaps speed-limited, hands and blades kept out of the body;
  Sludge gets his own set solved round his belly) into `assets/characters/hero/hero_anims_fixed*.res`, which
  `HeroAnims` lays over the built-in clips in matches, menus and the Hero Creator. After: 86 findings, no flips (the
  largest turn left is 76 degrees in one frame, most leftovers 45-66 in the fastest swings), Blood Ranger 1, Sludge 3.
  Kragg's shield is strapped along his forearm at 80% (it sat on his fist and covered his face) and his stage idle is
  `idle_shield` (the hands-on-a-planted-sword idle put the blade through his chest). Your beyond-heroes repo was not
  touched (it had your uncommitted work).
Evidence: headless tests 208 passed, 0 failed (new: Kragg innate and Overload, varied picks, magic defence items,
bot counter items, juke spots and juke teleport, counter-gank calls); `sh tools/check.sh` no parse errors, "Names
OK"; `tests/tools/kragg_probe.gd` 11/11 at 1080p, 8/8 at 4K (3 hover checks skipped there: frame larger than the
monitor); audit files `anim_audit_before.txt` / `anim_audit_raw.txt` (352) and `anim_audit_final.txt` (86).
Not verified: no blind critic review (none asked for); the bot game counters predate the three fixes above;
animations still left: the lane creeps' clips (same library faults) are not repaired yet, Froster's staff passes
through his body in about 6-22% of frames in three casts, Kragg's shield edge touches his thigh in some attack
frames, Caziel's spin attack (`dual_4`) turns his whole body 61 degrees in one frame.

**2026-10-15 f: regen readout, Rejuvenation Orb, tower shots, Fortify, courier, Fast Forward (your list).**
* **Regen readout**: each bar shows the total per second, large, at its right end (+43.5); at its left end, how it adds
  up: own + bonus (3.5 + 40.0), and a healing cut as its own red term (3.5 - 2.1). Nothing to add: the total alone.
  Hover a bar: "Regenerates 43.5 per second", "Own 3.5 + bonus 40.0", the cut if any, "Full in 6 s at this rate".
* **Rejuvenation Orb** (your name; was Water Orb): already came only at 2:00 and 4:00, and a test now holds it to that
  (none to 30:00). New look: a bright purple heart in a glassy rim-lit shell with a turning halo and motes.
* **Tower shots**: Ancient Light fires a lance of sunlight (white-hot core, gold sheath, gold trail) that strikes with a
  spike of light, gold sparks and a small ring; Black Sun fires a small black sun with a crimson corona (it faces the
  camera, so it reads as an eclipse from any angle) that swells and collapses on impact, bursts crimson and cracks the
  ground. Fortified shots are a third bigger.
* **Fortify**: every building of the team stands in light while it lasts: Ancient Light a gold shell with light rising
  through it, a beam from the sky and a turning halo; Black Sun a shadowy violet veil with a crimson rim and a black sun
  over the roof. Both fade in and out. Tier 2+ towers meanwhile: splash 300, shots 50% faster, Fortify Mark (15 s,
  each adds 50 physical damage to their shots; it shows in the buff bar). This replaces Dota's "5 extra targets" (say
  if you want both). Allies see "<name> used Fortify" in the kill feed and a note over the panel. A team of bots
  presses it for a building in danger; a team with a human leaves it to the humans. The button's tooltip no longer
  blinks (it vanished between the minimap's redraws because the button is outside the minimap's rectangle).
* **Courier**: 290 + 20 speed per hero level; flies straight over trees, cliffs and walls from its hero's level 6.
* **Fast Forward**: no more faster cooldowns; it takes 2 / 3.5 / 5 / 6.5 s off the target's basic spell cooldowns at
  once (not the ultimate, not items) and keeps its 5 s speed boost. Talent: "+1.5s Fast Forward cooldown cut".
Run `work/lemondev/2026-10-15f-regen-fortify/` (contract.md, handoff.md). Evidence: headless tests 200 passed,
0 failed (new: Rejuvenation timing, Fortify splash / marks / speed, bot Fortify, updated courier and Fast Forward);
`tests/tools/fortify_probe.gd` 14/14 at 1080p (the Fortify tooltip up on 60 of 60 frames while hovered) and 12/12 in a
real 4K frame (two hover checks skipped there: frame larger than the monitor); a 45-minute 5 v 5 bot game (`bot_game.txt`): bots pressed Fortify 10 times (5 each side, from
12:28), no script errors, no winner at 45:00 (Black Sun far ahead; earlier games ended at 50-60 min, and stronger
Fortified towers may lengthen them: watch this); "Names OK"; `build/WarriorsOfAether.exe` rebuilt 2026-10-15 15:14, cold start into a Kragg match in 9.8 s,
no script errors (`shots/export_f.png`). Not done: blind critic review.

**2026-10-15 e: buff bar (your request and screenshot).** The place you marked over the skills now shows every buff,
debuff, aura and status on the unit the bottom panel shows (your hero, an ally, an enemy, a creep, a tower, your
courier). Buffs sit on the left with a green rim, debuffs on the right with a red rim, like Dota. Each instance is its
own icon (Stench from two Sludges is two icons, every burn is its own); Kragg's Charges show their count. Timed
effects darken clockwise as they run out, like a cooldown, with the seconds along the bottom; auras have no timer and a
thin inner rim. Hover: name, buff or debuff (or ally / enemy aura), who applied it, what it does ("Moves 20% slower.",
"-5 armor.", "Broken: its passive abilities do nothing."), time left of its full length, and whether a dispel removes
it. Debuffs include stuns, slows, silences, roots, disarms, hexes, mutes, Break, lowered stats (armor and attack speed
loss), more damage taken, healing cuts, reveals, burns and enemy auras. When a row fills it grows upward (three rows),
then the icons shrink, then each side's last slot becomes "+N" listing the rest. Clicking an icon gives no move order.
The creep panel's old small status icons are replaced by the bar. Run `work/lemondev/2026-10-15e-buff-bar/`
(contract.md, handoff.md). Evidence: headless tests 197 passed, 0 failed (new `test_buff_bar_entries`);
`tests/tools/buff_probe.gd` 29/29 at 1080p and 20/20 in a real 4K frame (hover checked at 1080p only: the 4K frame is
larger than this monitor); `tests/tools/modifier_census.gd` (three 30-minute bot games, all eight heroes): all 56
effect kinds seen have names except Sludge's own hook lock, which is hidden as in Dota; "Names OK". Captures in the
run's `shots/`. Not done: blind critic review (none asked for); the exported build was not rebuilt.

**2026-10-15 d: cast range fixed (your report).** Long Lens and other cast range bonuses now reach everything that
should grow: spell cast ranges (talents and upgrades that change a spell's range count too; they were ignored), line
shots' reach (hook, arrow, javelin), Leap Strike's search radius and Jump Knife. The targeting ring showed the bare
range (and unit spells showed your attack range): it now shows the real cast range, and the ability tooltip says
"Cast range N (+bonus)". Stacking (your rule): copies of one item add half as much each (two Long Lenses +337.5),
Blast Rod levels count as one source, different sources add fully. Rules: `docs/MECHANICS.md`, "Cooldowns, spell area,
cast range". Evidence: headless tests 196 passed, 0 failed (new `test_cast_range_stacking_and_reach`); input probes
Sludge 12/12, Kragg 8/8; "Names OK"; `build/WarriorsOfAether.exe` rebuilt (below).

**2026-10-15 c: performance in teamfights, bot laning / teamfights / ganks / pushes, more learning, Quick cast.**
Run `work/lemondev/2026-10-15c-perf-feel-ai/` (contract.md: request, components, conditions; handoff.md: tools and
file map). Evidence on the final working tree:
* **Teamfight frame time** (a new real teamfight bench: ten heroes at level 16 with items brawling in mid at 10:00,
  ~220 units, 1080p, RTX 4060, V-Sync off; three alternating runs each against `81efd48` plus the same bench harness,
  `bench_ab_final.txt`): average **41 -> 48 fps** (24.2 -> 20.7 ms), p95 39 -> 33 ms, p99 53-61 -> 41-43 ms, worst
  frame 102-134 -> 61-66 ms, script errors ~510 per run -> 0. This is better, not "perfect": a full level-16 brawl is
  still under 60 fps on this PC (what is left, per frame: the 30 Hz simulation tick ~8 ms when it runs, engine
  deferred work ~5 ms, drawing ~6 ms). A background process (`UninstallMonitor`, not ours) held one CPU core all session.
* Simulation in that fight (headless `sim_profile.gd --fight`): ticks over 15 ms in two minutes 24 -> 2, worst tick
  30 -> 17 ms, mean tick 5.1 -> 4.7 ms.
* **Bots**: lone last hits in 8 minutes of mid (`lh_lab.gd`, five heroes): 17-31 -> 37-47. Teamfight A/B (mirrored
  lineups, team engage on for one side only, sides swapped, 8 games): the side with it ahead in net worth 6 of 8
  (average +4.5k) and kills 5 of 8 (+4.9). **Games end now: 3 of 4 60-minute games had a winner** (50:02, 57:07,
  59:55; the fourth was 99-54 in kills at 60:00); before this run no bot game had ended. Carries' last hits at 10:00
  rose from 5-13 to 16-23 (Dota's bots get ~40: still the largest gap).
* **Learning**: not shown to help yet. Two learning A/B runs (`learn_ab_v1`, `learn_ab_v2`: three memories trained
  over three games each, then played against fresh bots from both sides, against a control): the learned side did
  better than the control as Ancient Light (+2.9k net worth) and worse as Black Sun (-6.4k). Per-hero last-hit timing
  learning drifted the wrong way in contested lanes and was removed; teamfight and gank learning are kept.
* Headless tests: 195 passed, 0 failed (188 + 7 new). `sh tools/check.sh`: no parse errors, "Names OK".
* Input probes with Quick cast: Sludge 12/12, Azrin 14/14 (the key alone casts at the mouse).
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 12:29; cold start into a Froster match in 11.6 s, no script
  errors (`shots/export_froster.png`).

What changed (details and the file map in the run's `handoff.md`):
* **Fight lag**: Froster's effects hit a script error every frame once he froze or chilled anyone (a freed effect node
  put into a typed variable), and printing it cost ~10 ms a frame; the same pattern was fixed in 48 more places
  (`View.live`). The HUD portrait drew the whole world a second time (now only the shown unit, every other frame).
  Simulation spikes: bots and team brains no longer all think on the same tick; the sight cache is no longer wiped
  when a tree falls; repeated estimates are cached; the minimap, kill feed, chat and scoreboard draw less often or in
  one batch; the hover pick and ground ray are cheaper; Spike Armor thorns share one mesh. Options > Video: Low and
  Medium use one shadow cascade.
* **Bots**: better last-hit timing; **teamfights as a team** (the team brain weighs both groups, calls "Fight! Focus
  their ...", and everyone near commits to one target); **ganks** gather out of sight behind the target and strike
  together, and laning-phase "ganks" by the lane partner are gone; wave clearing after the laning phase; honest camp
  checks (no more walking back to a camp that nearly killed them); teleport back to lane from the base; regen by
  courier instead of walking home; Mana Potions used; from 20:00 pushes when even, from 25:00 the whole team pushes
  together and goes on building after building, tanking tower shots in turn; stuck bots walk out; supports stop
  stacking late.
* **Quick cast** (Options > Game, off by default): a spell or item key casts at the mouse with no second click.
* Ribbon trails no longer streak across the map after a teleport.

Needs you: veto any name in "Names added 2026-10-15 c"; try Quick cast. Known issue (not new: the old build does it
too): after a long fight benchmark the game can crash on quit (an engine "Leaked instance dependency" warning first);
normal quits are clean.
Not verified: no blind critic review (none asked for; the changes are measured, the small visual ones are self-checks).

**2026-10-15 b: Debug panel fix, auto-select, unit panel, 10-skill bar, cooldown system, 20 items, new icons, Tock
and Kragg, tower ranges on Alt.** Run `work/lemondev/2026-10-15b-ui-items-heroes/` (handoff.md there: plan, file map,
how-to, state). Evidence on the final working tree (uncommitted):
* Headless tests: 188 passed, 0 failed (173 + 15 new: items, cooldowns, AoE / cast range, both heroes).
  `sh tools/check.sh`: no parse errors, "Names OK".
* `tests/tools/hud15_probe.gd` (new) 17/17 at 1080p and in a real 3840 x 2160 frame: Debug panel inside the screen
  (it ran 64 px off the right edge: the framed box's margins were not counted), every control reachable; a right
  click, Stop or Hold with a creep or nothing selected selects your hero and runs the command; a lane creep, neutral,
  tower and the Throne show in the bottom panel; 6 and 10 skills fit (keys Q W E D F R, Q W E D F G Y U I R).
* Input probes through real hotkeys: Tock 13/13, Kragg 6/6. Item flow probe 13/13 (no regression).
* Captures in `work/lemondev/2026-10-15b-ui-items-heroes/shots/`: debug panel, unit panels, 6- and 10-skill bars,
  icon sheets (old next to new), the 5-column shop, both heroes casting, tower ranges with and without Alt.
* Bot duels, 12 min, 3 seeds each, no script errors (`duels.txt`, kills over the three games): Tock vs Sludge 1-2,
  Kragg vs Ezee 1-0, Tock vs Kragg 0-2, Kragg vs Blood Ranger 1-2, Tock vs Azrin 1-7, Kragg vs Caziel 1-3. Kragg
  out-farms Ezee and Tock; Tock (a support) loses the mid-style duel to Azrin badly. Tune if you want them stronger
  one on one (all numbers chosen). A 25-minute 5 v 5
  bot game with two Tocks and two Kraggs: no script errors, bots fill roles 3 and 5 with them and call them by name in
  chat (`bot_game_5v5.txt`); the old late-game "stuck in task" bots showed up again (2 bots from 16:00).
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 04:36; cold start straight into a Kragg match in 9.7 s and a
  Tock match in 12.4 s, no script errors.

What changed:
* **Debug panel** (F9): sized from its real frame, two columns, capped above the bottom panel, scrolls if needed.
* **Auto-select**: with nothing of yours selected, any command selects your hero first and goes to it.
* **Bottom panel for any unit**: creeps, neutrals, towers, barracks, the Throne, wards show like a hero: portrait,
  level, health and mana with regen, damage, armor, speed, range, attack rate, magic resistance, the type chips and
  stat sheet, their spells / auras / attack effects / true sight as skill slots with tooltips and cooldowns, bounty,
  experience and sight, status effects. The innate skill (Growing Gut) has its own small slot.
* **Skill bar up to 10**: the console art comes in 7 widths (`tools/ui_skin.py --consoles`), slots shrink from 7
  skills; six new hotkeys (Extra ability 1-6: D F G Y U I) on the Hotkeys screen; with more than 4 skills the
  ultimate stays on R (Dota's Q W E D F R). "The ultimate" is now the skill with level requirements, not slot 4.
* **Cooldown system**: cooldown reduction (Time Crystal), cooldown rate (faster, slower or frozen), spell area bonus
  and cast range bonus. Rules in `docs/MECHANICS.md` "Cooldowns, spell area, cast range".
* **20 items + 11 parts** from Valve's items.txt (`work/research/d2_items.txt`), with recipes, shop groups (the shop
  is 5 columns now: Casting, Big Weapons, Boots added), tooltips, item effects, bot builds and bot use. Table of Dota
  names in `docs/MECHANICS.md`.
* **Icons**: `tools/item_icons.py` draws 78 item icons (every combination item, the new items and parts) and 11 skill
  icons in one style: a backdrop coloured by role, the object lit and outlined, a badge saying what it does.
* **Tower ranges**: the attack range circles of towers and fountains show only while you hold **Alt** (enemy yellow,
  red while it targets you; yours pale blue). They used to appear near enemy towers on their own.

Needs you: veto any name in "Names added 2026-10-15 b"; tune Tock's and Kragg's numbers if you like (all chosen).
Not verified: no blind critic review (no Dota frames on disk, no subagents asked for): visuals are builder
self-checks, UNVERIFIED for blind review. Performance benchmarks were not rerun.

**2026-10-15: multiplayer (servers, lobbies, a main server entry), HUD level pips, your bug reports.** Run
`work/lemondev/2026-10-15-multiplayer/` (contract.md there). Evidence on the final working tree (uncommitted):
* Headless tests: 173 passed, 0 failed (171 + 2 new server tests). `sh tools/check.sh`: no parse errors, "Names OK".
* Multiplayer, two windows on this PC driven by real clicks and typing (`tests/tools/net_ui_probe.gd`): host 35/35,
  guest 17/17 at 1080p; host 31/31 and guest 16/16 with the host's window at a real 3840 x 2160 (before the rejoin
  steps were added). Covered: host a server, the server list finds it on the local network, join it, create a lobby,
  join it with a double click, chat both ways, pick heroes and lanes, the leader's slot menu, Fill with Bots, Ready,
  Start Match, both load and play, Pause Game / Unpause Game reach both, Leave Game hands the hero to a bot, joining
  the running match again from the lobby list gives the hero back, Stop Hosting, the guest plays on with bots when
  the server goes. Two one-off misses in 6 runs (once the Ready click and once the guest's chat line did not register
  in the probe); both passed on every rerun, so they are recorded, not hidden.
* Lockstep (`tests/tools/net_test.gd`, headless, real UDP): a dedicated server with two players, a hosted server with
  one player, and the **exported build** as a dedicated server with two players: every player ends on the same world
  fingerprint; forced desyncs repaired from a player in the majority (in 9 to 31 frames); a player who drops and
  connects again gets a snapshot and their hero back. Command to execution at real time against the exported server:
  35 and 38 ms average (p95 56 and 80 ms) on this PC; a hosting player's own commands about 5 ms.
* Your bug "giant T-posed model in the river": unit views of units that spawned or moved off screen were never placed
  (they stood at the world origin, the river in the map's centre) and never animated (a bind pose, at the model's raw
  size). Fixed in `unit_view.gd` / `main.gd`; `tests/tools/view_place_probe.gd` (5 v 5, camera over the river, 6 game
  minutes, 268,465 checks) finds 0 misplaced views; it found them at the map centre before the fix.
* Your neutral rules: neutrals wake for an enemy within 125 (was 240); lane creeps leave a calm camp alone and fight a
  neutral only while it is aggressive and for 5 s after; the large pull camp and the medium camp by the safe lane's
  tier 2 moved away from the lane (both sides). Holding **Alt** shows the camps' spawn boxes (was Shift). Tests,
  `camp_layout.gd` (0 problems), `team_probe.gd` 11/11 and a 20-minute 5 v 5 bot game (no script errors) pass.
* HUD: the ability level pips sit in their own carved tray under each slot (the console art got a tray, the slots
  moved up 4 px and the health and mana well down); learned levels are gold bars, the next learnable one a pulsing
  gold outline. Item and Teleport hotkeys are on dark tags inside the slots (they were cut by the frames). Checked at
  1080p and a real 4K frame.
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-15 01:25 and run as a dedicated server (above).

Needs you:
* **The main server's address.** The Multiplayer screen lists a "Main server" first, but this build has no address
  for it (it shows "Not set up in this build yet"). Run the server on a machine with a public address
  (`WarriorsOfAether.exe --headless -- --server --name="Warriors of Aether" --motd="..."`, UDP ports 27850 and 27851
  open) and put its address in `src/net/main_server.json`, then rebuild.
* Veto any new names below ("Names added 2026-10-15").

Not verified: no independent (blind) critic review of the new screens was run (no subagents were asked for and there
are no Dota lobby frames on disk), so their look is a builder self-check: UNVERIFIED for blind review. Performance
benchmarks were not rerun this session.

**Previous status (2026-10-14 b):**
**2026-10-14 b (wrapped up early on your request, "just wrap up and build"): Froster and Caziel, Main Menu, UI
skin, mechanics fixes, multiplayer groundwork.** Run `work/lemondev/2026-10-14b-ui-net-heroes/` (contract.md there).
The run was interrupted and then cut short, so only these gates were rerun at the end:
* Headless tests: 170 passed, 0 failed. `sh tools/check.sh`: no parse errors, "Names OK".
* Export: `build/WarriorsOfAether.exe` rebuilt 2026-10-14 23:10. Cold start straight into a match: Froster ready in
  10.1 s, Caziel 10.5 s, no script errors (`export_froster.png`, `export_caziel.png`); the Main Menu opens with no
  script errors (`export_menu.png`).
* Bot duels, 12 min, 3 seeds, Froster and Caziel against every hero: no script errors (`duels_heroes.txt`).

What is in this build:
* **Froster, the Winter Master** (Ice, ranged Int): Breath of Cold, Ice Pulse, Frost Heart, Endless Winter.
  **Caziel, the Void Assassin** (Dark, melee Agi): Swift Dagger, Sweet Poison, Master of Shadows, Death Order. Your
  names and numbers; Caziel's base stats are *chosen* (classic melee-agility template). Talents are plain texts
  ("+80 Breath of Cold damage", "+25 Attack Speed"...), listed in `src/sim/sim_data.gd` near line 506.
* A new **Main Menu** (Play, Hero Creator, Options, Quit) with your hero on a lit stage and a "Choose hero" button,
  plus generated UI textures in `assets/ui/skin/` (`tools/ui_skin.py`).
* Mechanics fix: Ancient Light's top and Black Sun's bottom lane creeps spawned inside a tower's footprint and never
  left (no creeps on those lanes from the second wave). Spawns now snap to walkable cells and blocked units slide out.
* Every player action now goes through serialisable commands (`src/sim/sim_commands.gd`), and `src/net/` plus
  `sim_snapshot.gd` hold the lockstep session code.

Not done or not verified (the cut parts of the run):
* **Multiplayer has no screens yet** (browse, host, join, lobby). The Main Menu hides its Multiplayer button until
  `src/ui/net_menu.tscn` exists. The two-process desync test (`tests/tools/net_test.gd`) was not run.
* Performance gates (sim profile, 5 v 5 bench at 10:00 and 25:00) were not rerun after the changes.
* The HUD, shop, Hero Select and Game Setup remake (U2, U3) and the blind UI review against Dota frames: not done.
* Live probes (menu, item flow, input, controls) were not rerun; the 5 v 5 "an Ancient falls" gate (Q1) not rerun.

**Previous status (2026-10-14, first run):**

**IMPLEMENTED, GATES PASSED, VISUALS NOT BLIND-REVIEWED** (2026-10-14: elements, damage and armor types, magic amp,
Kugmo / Igit / Atuli, item menu with lock and disassemble, 10 s full-refund protection, item effects, HUD readouts,
quieter creep deaths, Azrin with your female_generic body and particle fire; run
`work/lemondev/2026-10-14-elements-azrin/`, contract in `contract.md` there; details in "Elements, armor and damage
types, magic amp, item menu, Azrin" below).

Evidence (all on the final working tree, uncommitted):
* Headless tests: 155 passed, 0 failed (137 earlier + 18 new). `sh tools/check.sh`: no parse errors, "Names OK".
* Live probes: `menu_probe` 14/14 at 1080p and in a real 3840 x 2160 frame (captures in `work/shots/menu/`, `4k/`);
  input probes Azrin 12/12, Sludge 10/10, Ezee 4/4, Blood Ranger 7/7; item flow probe 13/13.
* Bot duels, 12 min, 3 seeds each, no script errors: Azrin beats Blood Ranger 16-1 and Ezee 13-0 and is even with
  Sludge 4-3 (your numbers kept; she is strong, partly from Fire beating Nature): `duels_pass1.txt`.
* Two 30-minute 5 v 5 bot games with two Azrins a side (seeds 3 and 7): no script errors; the Azrin mids led their
  teams (16/4/6 and 10/8/3 in game 1) and bots bought Atuli, Mana Boots, Push Staff and Spell Shield for her. Game 2
  flagged four bots stuck in "task" mode after 23:00, the known late-game AI problem (old AI2 gate), not new
  (`bot_game_5v5.txt`).
* Benchmark, 1080p, RTX 4060, `--bench=60 --t=240 --autoplay`, alternating with an a38afe7 checkout in the same
  session (`bench.txt`): after the first warm-up pair, this build 51 / 47 fps (p95 26.3 / 28.6 ms) vs the baseline
  53 / 51 (p95 26.7 / 26.7): about 6% slower, inside the 10% gate. With Azrin playing: 45 fps (p95 33 ms) before the
  flame shader went from 4 to 3 noise octaves, 64 fps (p95 20.8 ms) after, baseline 52 in the next run. This machine's
  run-to-run spread is wide (35-64 fps), so read it as no measurable slowdown, not a gain.
* Export + cold start of `build/WarriorsOfAether.exe -- --match --hero=azrin`: match ready in 11.3 s on the final build (12.0 s earlier with the bot
  games running on the same CPU), no script errors (`export_run.txt`, `export_start.png`).

Not verified:
* Blind visual review of the fire, Azrin's look, the item effects and the HUD chips: no Dota frames on disk, so
  UNVERIFIED (builder self-checks with captures only, see the ledger).
* Balance: Azrin with your numbers is far ahead in 1 v 1 lanes; the element table also shifts matchups (Fire vs
  Nature, Earth vs Fire). Numbers are easy to change in `src/sim/sim_data.gd` and `SimConst.ELEMENT_*`.
* Earlier results still stand (Shuriken Hook visuals, base environment, ramps, Burst Shot VFX, Hero Select STOPPED;
  Dark Stomp VFX STOPPED: LIMIT; tower scale UNVERIFIED; old AI2 gate failed).

## Run it

```
"C:\Users\Lemon PC\Desktop\Godot.exe" --path A:\Python\woa
```
or open `A:\Python\woa\project.godot` in the editor and press F5.

* Or run the exported build: `build/WarriorsOfAether.exe` (rebuild it with
  `godot --headless --path . --export-release "Windows Desktop" build/WarriorsOfAether.exe`).
* The game opens on **Hero Select** (`src/ui/hero_select.tscn`): pick your hero, change its look with **Customize look**
  (the Hero Creator), then **Play** opens **Game Setup** (`src/ui/game_setup.tscn`): two teams of five slots, each You,
  Bot or Empty, with a hero (or Random; bots may play the same hero), a bot skill (Passive, Easy, Medium, Hard, Unfair)
  and name, and the lane you want. Presets: 5 vs 5, 1 vs 1 mid. **Start** goes to the Hotkeys screen and the match.
* Exported builds ignore scene paths on the command line: `build/WarriorsOfAether.exe -- --match [capture flags]` jumps straight into a match (for automation; `--match` must come after `--`).
* Ranked (2026-10-19 b): Main Menu > Ranked, or `godot --path . res://src/ui/ranked_menu.tscn -- [--capture=x.png --tab=play|profile|leaderboard|guilds --state=search|found|ready --hover=n --profile=b12 --view=heroes --board=heroes --hero=azrael --4k]`; the pick and versus alone: `godot --path . res://src/ui/ranked_draft.tscn -- [--capture=x.png --at=8 | --phase=versus --frames=330] [--4k]`; live probe `godot --path . -s tests/tools/ranked_probe.gd -- --out=dir` (its own ladder file); emblems `godot --path . -s tests/tools/emblem_sheet.gd -- --out=x.png`; set `WOA_RANKED_FILE=user://other.json` to keep your ladder untouched.
* Profile and social screens (2026-10-20 b): the Ranked screen's capture flags above plus `--view_as=public|<id>
  --side=wall|heroes|mmr|visitors --open_match=n --compare --menu=<id>`; Forums `godot --path . res://src/ui/forums.tscn
  -- --capture=x.png` (set `WOA_FORUM_FILE=user://other.json` and `WOA_RANKED_FILE` to keep yours untouched); the social
  skin `python tools/ui_skin_social.py [--preview x.png]` (then `godot --headless --path . --import`).
* Tests (headless, about 8 minutes, most of it the vision-cache test): `godot --headless --path . -s tests/run_tests.gd`. Add `-- --only=<name>` for a subset. 327 tests (2026-10-20 b).
* Teamfight benchmark (the one that matters for lag in fights): `godot --path . res://src/game/main.tscn -- --bench=40
  --t=600 --fight --autoplay --lineup=ezee,azrin,froster,sludge,tock,blood_ranger,caziel,kragg,azrin,froster
  [--bench_shot=png]`: prints frame times and the cost of every part (see `work/lemondev/2026-10-15c-perf-feel-ai/
  handoff.md`). Function-level profile: `python tools/gd_profile.py [--game] -- <args>`.
* Benchmark: `godot --path . res://src/game/main.tscn -- --bench=60 --t=240 --autoplay` writes `work/bench.txt`. Last measured 2026-10-12 on the new map at 1080p on the RTX 4060 with the HUD (`--bench=50`): 77 fps average, p95 16.67 ms.
* Screenshot capture (renders, saves, quits): `godot --path . res://src/game/main.tscn -- --capture=work/shots/x.png --t=95 --cam=-1500,-1300 [--autoplay] [--zoom=1.1]`. `--autoplay` lets a bot drive your hero too.
  * `--hero=sludge --bot_hero=blood_ranger` pick the heroes (blood_ranger, ezee, sludge); `--frames=30,34,38` saves several frames;
    `--live` keeps the simulation running while capturing. `--bots=5v5` plays full teams; `--reveal` lifts the fog;
    `--boxes` shows the camps' spawn boxes; `--nolearn` keeps the bots' memory untouched.
  * Demo staging: `--lvl=18` levels your hero and learns its kit; `--at=wave,170 | tree | hero,520` places it beside
    the enemy wave, between a creep and a tree, or beside the enemy hero (`--weaken=0.12`); `--cast=dark_stomp@4`
    (or `attack`) issues it at capture frame 4. `--board` shows the scoreboard, `--endscreen` the end screen,
    `--drag=x,y,w,h` a selection box, `--marker=x,y` a move marker.
* Watch an All-Bot match without the menus: `godot --path . res://src/game/main.tscn -- --watch --bots=5v5 --nolearn
  [--watch_cam=auto|follow|hero|free] [--watch_vision=-1|0|1|2|3]`; live checks: `godot --path . -s
  tests/tools/watch_probe.gd -- --watch --bots=5v5 --nolearn [--min=4] [--out=dir]`.
* Bot duels: `godot --headless --path . -s tests/tools/bot_duel.gd -- --a=blood_ranger --b=ezee --min=12`.
* A game that stops advancing: `godot --headless --path . -s tests/tools/stall_probe.gd -- --a=roydo --b=ezee --min=10
  [--trace=348] [--seed=3]` prints a line per game minute with the real time, every step over 50 ms, and with
  `--trace` the heroes' state before each step from that second (the last line printed is the step that hangs).
* Animation joins (run 2026-10-18 e): `godot --headless --path . -s tests/tools/anim_joins.gd -- [--models=ezee,hero_burak]
  [--all] [--fixed] [--out=x.txt]` (every crossfade and loop seam; `--fixed`: the old fixed blends). Motion capture: the
  commands in `work/lemondev/2026-10-18d-mocap/handoff.md` (retarget, import, then `body_collide.gd -- --fix`).
  Airah's body: `blender -b --factory-startup --python tools/blender/airah_prep.py`, then the hero_body command in that
  file's header. The other new bodies: `sh work/rebuild_new5.sh [out_dir] [names]` (the arm split off by default).
* Animations (runs 2026-10-15 g, h): audit every hero clip `godot --headless --path . -s tests/tools/anim_audit.gd --
  [--heroes=kragg] [--units] [--raw] [--out=x.txt]`; rebuild the repaired arms after any change to the clips or the
  models: `godot --headless --path . -s tests/tools/anim_repair.gd`, `... -- --body=sludge` and `... -- --units`;
  frame sheets `godot --path . -s tests/tools/anim_sheet.gd -- --heroes=kragg,unit:dawn_melee --clips=sword_1
  --yaws=30,-70 [--fov=14] [--raw]`.
* Title and menu captures: `godot --path . res://src/ui/main_menu.tscn -- --capture=x.png [--title --title-at=5]
  [--focus=1] [--4k]`.
* 5 v 5 bot games (headless): `godot --headless --path . -s tests/tools/bot_game.gd -- --seeds=3,7 --min=40 [--chat]
  [--skill=hard] [--learn=work/mem.json --learn_teams=1,0] [--out=file]` prints the result, each hero's line, LH and net
  worth at 10:00 and 20:00, time per bot mode, stuck heroes and the team chat. `tests/tools/trace_game.gd` prints each
  bot's mode, desires, order and target every few seconds; `tests/tools/bot_profile.gd` the cost of each step part.
* Camp layout check: `godot --headless --path . -s tests/tools/camp_layout.gd` (clearances, reachability, plot).
* Live probes (open a window, play a real match, print PASS / FAIL):
  `godot --path . -s tests/tools/camera_probe.gd` (camera at the start and at respawn),
  `godot --path . -s tests/tools/team_probe.gd -- --bots=5v5 --nolearn --out=work/shots` (bot chat in the HUD, ping
  replies, Alt spawn boxes, typed chat),
  `godot --path . -s tests/tools/input_probe.gd -- --hero=sludge --nobot` (every ability through the input
  controller), `godot --path . -s tests/tools/item_flow_probe.gd -- --hero=sludge` (shop, To Buy, drag and drop,
  talents, courier), `godot --path . -s tests/tools/ui_probe.gd -- --hero=sludge --out=work/shots` (HUD captures).
* `--showqueue` (capture flag) queues a few orders for your hero and draws the Shift waypoints.
* Parse-check every script: `sh tools/check.sh`.
* Multiplayer: Main Menu > Multiplayer. A dedicated server (no window):
  `build/WarriorsOfAether.exe --headless -- --server [--port=27850] [--name="My server"] [--motd="Welcome"]
  [--password=x] [--max=64]`; it answers the server list on the port above its game port and prints joins, lobbies
  and matches. Lockstep tests (one shell each): `godot --headless --path . -s tests/tools/net_test.gd -- --role=server`
  then `-- --role=client --lead --name=A` and `-- --role=client --name=B [--corrupt=3600] [--drop=5200] [--lag=60]`
  (or `--role=host` plus one client); every player prints `HASH@<frame>` and they must match. The screens through
  real clicks (two windows): `godot --path . -s tests/tools/net_ui_probe.gd -- --role=host [--4k]` and
  `-- --role=guest`.
* Units drawn where they are: `godot --path . -s tests/tools/view_place_probe.gd -- --hero=froster --bots=5v5
  --autoplay --nolearn --min=6`.
* Rebuild Azrin's body from your female_generic model (about a minute; `-- --preview=dir` renders checks):
  `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/azrin_body.py`
* Motion-capture clips (2026-10-18 d; B = the Blender command below, G = the Godot console): survey every downloaded
  clip `B -b --factory-startup --python tools/blender/mocap_retarget.py -- --survey --src=work/downloads/mixamo/raw
  --cells=<dir>` then `python tools/mocap_sheet.py <dir> <sheets>`; build the clips in `tools/blender/mocap_clips.json`
  with `B ... mocap_retarget.py -- --spec=tools/blender/mocap_clips.json --src=work/downloads/mixamo/raw
  --out=work/mocap/hero_mocap.glb`, then `G --headless --path . -s tests/tools/mocap_import.gd` (writes
  `assets/characters/hero/mocap/`), then the body collision `--fix`. How the Mixamo download works:
  `work/lemondev/2026-10-18d-mocap/handoff.md`. Hand remnants of a body: `B ... --python tools/blender/remnant_check.py
  -- --glb=<body.glb> --png=x.png --weights=w.png`.
* Strict animation check (2026-10-18): `godot --headless --path . -s tests/tools/pose_compare.gd [-- --models=hero_ezee]
  [--limit=25] [--all] [--raw]`; contact sheets `godot --path . -s tests/tools/anim_sheet.gd -- --heroes=ezee,unit:hero_ghorman`.
* Rebuild Azrael's body (B = the Blender command above): `B --python tools/blender/azrael_prep.py --
  --src=A:/Python/woa/work/downloads/sf_heroes/azrael.glb --out=A:/Python/woa/work/azrael_src`, then `B --python
  tools/blender/hero_body.py -- --src=A:/Python/woa/work/azrael_src/azrael_src.blend --name=azrael --height=1.8
  --faces=50000 --tex=2048 --glide=idle_staff --reach=1 --out=A:/Python/woa/assets/characters/heroes17/azrael.glb`.
* Rebuild Ghorman's body: `B --python tools/blender/ghorman_prep.py -- --out=A:/Python/woa/work/ghorman_src [--preview]`,
  then `B --python tools/blender/hero_body.py -- --src=A:/Python/woa/work/ghorman_src/ghorman_src.blend --name=ghorman
  --body_piece="^ghorman_body" --height=2.05 --faces=80000 --tex=2048 --reach=1 --cloth="^no_hanging_cloth$"
  --out=A:/Python/woa/assets/characters/heroes17/ghorman.glb`; his club: `B --python tools/blender/heroes17_gear.py -- --only=club`.
  Ezee, Azrin and Caziel: the commands in `work/lemondev/2026-10-17e-hero-models/NEXT_AGENT.md` plus `--reach=1`.
  After any body rebuild: `godot --headless --path . --import` (no arm repair needed for these bodies).
* Azrael's scythe and wings: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup
  --python tools/blender/azrael.py`; her look variants side by side: `godot --path . -s tests/tools/azrael_look.gd --
  --out=x.png [--close]`; which way a weapon's head moves in a swing: `godot --headless --path . -s
  tests/tools/swing_dir.gd -- [--clips=gs_1,gs_3]`.
* Araki's body (2026-10-19 c; B = the Blender command): `B -b --factory-startup --python tools/blender/araki_prep.py --
  --src=A:/Python/woa/work/downloads/sf_heroes/shadowflame_samurai.glb --out=A:/Python/woa/work/araki_src`, then `B -b
  --factory-startup --python tools/blender/hero_body.py -- --src=A:/Python/woa/work/araki_src/araki_src.blend
  --name=araki --drop="katana" --height=1.88 --faces=50000 --tex=1536 --split=0
  --out=A:/Python/woa/assets/characters/heroes17/araki.glb`; katana: `B ... --python tools/blender/araki_katana.py --
  --src=<that glb> --out=<x.glb>` then `prep_weapon.py -- --src=<x.glb> --out=assets/weapons/araki_katana.glb
  --length=1.0 --grip=0.13 --flip_head`; then `godot --headless --path . --import` and `body_collide.gd --
  --heroes=araki --fix`. His deaths and casts in a bot game: `godot --headless --path . -s tests/tools/araki_probe.gd --
  [--min=20] [--seed=3]`. The versus shot with chosen heroes: `godot --path . -s tests/tools/versus_shot.gd --
  --a=airah,tock,araki,ezee,feran --b=... --out=dir`.
* Rebuild the building models: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/buildings.py`.
* Re-bake the terrain texture arrays (needs the GPU, not headless): `godot --path . -s tests/tools/bake_terrain_arrays.gd`.

## Controls (Dota defaults)

Every hotkey can be changed on the **Hotkeys** screen shown before each match ("Are you good to go?"): one key, Mouse 4 / 5, or a combination with Ctrl, Alt or Ctrl + Alt. Shift is never part of a hotkey because it queues. Esc, F10, Ctrl + 1-9, Alt + F4 and Alt + Tab are refused. Layouts can be saved as named templates (`user://keybinds.json`). The table shows the defaults.

| Key | Action |
|---|---|
| Left click / left drag | Select. A drag draws a green box: your own units inside it are selected (hero first); with none of yours inside, the one unit nearest the box centre |
| Right click | Move, attack an enemy, deny an ally below 50% HP, follow an ally, take an orb (orbs come first under the cursor). Orders go to the selected units you control (hero, courier), as in Dota |
| A, then left click | Attack-move (ground) or attack (unit). On an ally the order is accepted: your hero waits in range and only swings once the ally can be denied. Shows your attack range |
| S | Stop (the hero still auto-attacks enemies in range). Hold S: the hero is stopped again every frame and every order is refused until you let go; held over 0.35 s it stays a hard stop (no auto-attack until your next order) |
| H | Hold position |
| Shift + any order or hotkey | Queue it, as in Dota: orders run one after another; a queued spell still cooling down is checked again when its turn comes. Holding Shift shows the queue as numbered waypoints (green move, red attack, blue spell or item, gold hold) |
| Quick cast (Options > Game) | With it on, an ability or item key casts at once at the mouse (on the unit under it), with no click; over the interface, or with no valid unit under the cursor, the targeting cursor shows as usual |
| Q W E R (D F G Y U I) | Abilities. Heroes with more than 4 skills use Dota's layout: the last (ultimate) stays on R, the extra ones take D, F, G, Y, U, I (Tock: Q W E D F R; Kragg: Q W E D R). With nothing of yours selected, an ability, item, Stop, Hold, Attack, Teleport key or a right click selects your hero first. No-target spells and toggles (Stench) act at once. Point and unit spells show a pulsing crosshair: red for spells aimed at enemies, green for support (allies, yourself, a place); items too. A click that misses a valid target keeps the cursor and says why; right click or Esc cancels |
| Ctrl + an ability's hotkey, or the "+" above an ability | Learn the ability (unless that Ctrl combination is bound to something else) |
| Right click an ability button | Toggle autocast (Frost Quiver) |
| Z X C V B N | Items. Right click an item slot to move it between the inventory and the backpack. Drag an item to another slot, to the stash (in the base), onto the ground (the hero walks over and drops it) or onto an allied hero or your courier (gives it) |
| Right click an item on the ground | Pick it up |
| Talents button (star left of the abilities) | Opens the talent tree from level 10: one of two talents per tier, costs an ability point |
| Stash (above the items) | Shown when it holds something or you are in the base: click an item to take it, drag it to a slot, Grab All |
| Shift + click in the shop | Adds the item to **To Buy** (right side of the screen), broken into the parts you still need. In To Buy: left click buys, right click buys it automatically once you have the gold (into the courier if it waits at the fountain), Ctrl + click or x removes |
| F4, the Shop button, or B with an empty slot 5 | Shop. A click anywhere else (world, minimap, top bar) or Esc closes it; clicks on your items, stash and To Buy keep it open |
| , (comma), or right click the Teleport slot | Buy a Teleport Scroll for 100 gold (also first in the shop's Consumables). At the shop it goes into the Teleport slot; elsewhere into the stash, and into the slot once it reaches you (F3 sends the courier) |
| J, or the button above the minimap | Glyph |
| T | Town Portal: target a point or the minimap; the hero teleports beside the nearest allied building after a 3 s channel. Press T (or click the Teleport slot) twice quickly: straight to your fountain |
| F3, or the Deliver button | Courier picks up your items lying in the fountain area, takes the stash and flies it all to you |
| F2 (courier selected) | Q Return to Base, W Retrieve Items, E Return Items to Stash, R Deliver, Z Transfer, X Speed Burst (level 10), C Shield (level 20), V Auto Deliver; right click moves it |
| Buyback button (while dead) | Buy back: 200 + net worth / 13 gold, 8 minute cooldown |
| F1 | Select your hero; press twice to centre on it |
| Portrait | Click: select your hero and centre the camera on it. Hold: the camera follows your hero |
| Ctrl + 1..9, then 1..9 | Control groups (double tap centres the camera) |
| Alt + click | Ping (ground or minimap). On an enemy hero or building: "attack"; on one of ours: "defend"; Ctrl + Alt + click: danger. Your bots answer in chat, and agree or say why not |
| Enter | Type to your team (Enter sends, Esc closes). Bots understand "push top", "defend mid", "gank" or "kill <hero>", "back", "group" |
| Alt (hold) | Shows every neutral camp's spawn box: yellow, red while something blocks it (couriers never do), with its size and the pull camps named; and the attack range of every tower and fountain (enemy yellow, red while it targets your hero; yours pale blue). Without Alt no range circles show |
| Tab (hold) | Scoreboard with damage tables |
| Top-bar hero tiles | Click to look at a visible hero; dead heroes show their respawn timer |
| Space (hold) | Follow your hero |
| Screen edges, arrow keys, middle-drag | Pan the camera. In Borderless and Fullscreen the cursor is kept inside the game window, so pushing past an edge keeps panning (Windowed: Options > Game "Lock cursor to window (Windowed)") |
| Mouse wheel | Zoom |
| Hold right click | Repeats the move or attack order at the cursor |
| F9, or the Debug button (top right) | Debug panel: force start, creep waves, camps, level up, gold, refresh, god mode, free spells, reveal map, skip time, game speed; Bots: gold, levels, refresh, respawn, kill, teleport, items, skill, stand still for every bot, one team's bots or one bot |
| Watching an All-Bot match | The Watching panel (top left): hero, camera (Free, Follow hero, Hero view, Auto), sight, bot orders, what each bot is doing, game speed. Click a hero on the top bar to watch it; any pan frees the camera |
| Minimap | Left click or drag moves the camera; right click moves your hero |

## Architecture

```
src/sim/      deterministic 30 Hz simulation (no nodes). Rules, numbers and sources: docs/MECHANICS.md
  sim_const   rules constants (APPROX marks unverified values)    sim_data   unit, hero, ability and item data
  sim_map     terrain levels, river, bases, ramps, trees, A* grid, lanes, camps
  sim_world   tick loop, clock, waves, regen, backdoor, respawn, invulnerability chain, glyph
  sim_orders  turning, movement and collision, attack point and backswing, chase, hold, attack-move, casting
  sim_combat  projectiles, attack classes, armor, damage, deaths, bounties, XP, kill and assist gold
  sim_ai      waves, lane creep targeting and aggro, towers, neutral camps (stacking)
  sim_vision  fog of war (raycast grid, trees and high ground block sight, day and night ranges)
  sim_abilities  the heroes' kits, talents, toggles, channels, pushes and leaps, item actives (trees, planting)
  sim_items   combination items' actives, passives, auras and attack procs
  sim_shop    buying, recipe scrolls, alternative recipes, combining, stash, selling
  sim_bot     a hero bot: modes scored by desire (lane, farm, jungle, stack, pull, ward, fight, retreat, heal, the
              team's plays), last hits, combos, escapes, TP, items, difficulty, learning hooks
  sim_bot_kits   what bots know about each hero: roles, skill and talent orders, builds per role, burst and power
  sim_team_ai    one team's brain: roles and lanes (around the player), what the team saw, ganks, pushes, defence,
                 danger calls, Fortify, ping answers, team chat, scoring a finished game into the bots' memory
  bot_memory     what bots learn, saved in user://bot_memory.json (fight model, danger map, builds, skill shots,
                 retreat bar, lane matchups, the player's lanes)
src/game/     presentation (reads the sim, never writes it except through commands)
  main        boot, 30 Hz stepping in _physics_process, event dispatch, fog texture, capture mode
  terrain_builder + terrain.gdshader   9-layer splat terrain from the sim map, river water
  foliage + foliage.gdshader           Quaternius trees (one instance per sim tree), grass and plants
  building_view + building/crystal shaders   Blender-built faction buildings
  unit_view + model_catalog            animated units, attack swings timed to the sim's attack point
  camps (neutral camp props, fires, spawn boxes on Alt), fx, sludge_fx (shuriken hook and chain, Stench cloud,
  Chomp), item_fx (item actives and procs), camera_rig,
  atmosphere (day/night), fog_of_war.gdshader, input_controller, audio (Effects, Interface, Ambience buses)
src/core/     options (user://options.json), game_settings (heroes and looks)
src/hero/     customisable hero body ported from beyond-heroes (HeroLook, HeroAppearance)
  fx (projectiles, arrows that stick or miss into the ground, sparks, debris "bits", shockwaves, cracks, lightning,
     spikes, force walls, ability visuals), status_fx (stun stars, curse sigil, enchanted blade, Unholy aura),
     targeting_fx (cast range, area and line previews), trail3d (ribbon trails)
src/ui/       hero_select (main menu), hero_creator, hud (bottom panel shows the selected hero, minimap with pings,
              top bar with hero tiles, shop, tooltips), kill_feed (kill log and banners), scoreboard (Tab, damage
              tables, death recap), unit_bars (health with damage ghosts, status icons, floating damage numbers),
              screen_fx (death desaturation, low-health pulse), match_menus (pause, end screen), ui_kit,
              shop_panel (the Dota-style shop), options_panel (Options screen), game_setup (Game Setup),
              chat_panel (team chat above the minimap)
src/net/      multiplayer: net (autoload Net: ENet messages, the player's session, server queries, UPnP),
              net_server (a server's lobby list, rooms, the relayed lockstep, desync repair, rejoin), net_match (a
              player's lockstep: frames, jitter buffer, fingerprints, snapshots), net_browser (the server list, saved
              servers and the player's multiplayer settings in user://multiplayer.json), main_server.json (the main
              server's address); src/sim/sim_commands (every player action as data), sim_snapshot (the world as bytes)
src/ui/net_*  the Multiplayer screens: net_menu (shell, dialogs, notices), net_servers_page, net_hub_page,
              net_room_page, net_list (tables), net_chat
tests/        run_tests.gd (mechanics), tools/ (bakes, probes)
tools/        blender/buildings.py, build_wear_catalog.py, itch_dl.sh, kv.py (research), check.sh
```

## The customisable hero (your request: "very very customisable and dressable")

`HeroAppearance` drives `assets/characters/hero/hero.glb`, the body you supplied in beyond-heroes. It has 132 animations, including the full bow set and female locomotion.

* **Look** (`HeroLook`):
  * 20 shape keys: the female figure, muscle, belly, build, rear, and 15 face shapes.
  * Height, head, hands and feet size.
  * Skin, eye, lip, brow and marking colours, plus 12 skin patterns, 10 eye styles, 7 brow styles and 8 markings.
  * 16 hair styles and 8 beards, each with a length slider.
  * 13 presets (Huntress, Shieldmaiden, Moon Elf, Goblin King and more).
* **Outfit**: 143 worn pieces in 10 slots (inner garment, armor, leggings, helm, gloves, boots, 4 accessories), listed in `assets/characters/hero/wear/catalog.json`. Every piece follows the body sliders, the female shape included. Each slot can be dyed (cloth, trim, leather, metal, gold).
* Heroes are set up in `main.gd` `_spawn_heroes()`. A hero creator screen is the next UI step (see the backlog below).

## Assets and licences

See `docs/ASSET_CREDITS.md`.

## Blood Ranger (replaced Galewarden on 2026-10-12)

Ranged agility hero (Galewarden's base stats), crimson-haired huntress. Your numbers are used as given; level 1
takes the base value ("55% + 10% per level" = 55/65/75/85%). Numbers you did not give are marked *chosen*:

* **Burst Shot (Q)**: point target, cast range 900 *chosen*, area radius 400 *chosen*. Channels 2 s *chosen*: 5 waves
  0.4 s apart, each a random 4-7 arrows, 30 in all. Each arrow hits a random enemy in the area (or the ground) for
  55/65/75/85% of her average attack damage as physical damage (a spell: no lifesteal, no Masterful Archery).
  Ended by move, attack, stop or hold orders, other casts, stuns, silence, roots and pushes. 17 s cooldown, mana
  90-120 *chosen*.
* **Gale Impact (W)**: a great arrow to the target point (300-2000 range), speed 2000 and radius 110 *chosen*,
  pierces. 120/200/280/360 magic damage, then hurls each enemy sideways off the arrow's line (with a little forward
  push). A thrown enemy that hits a cliff, tree, building or unit takes another 20% of the arrow's damage once.
  Trees on the path and trees that thrown units hit are felled. 12 s cooldown, mana 100-130 *chosen*.
* **Masterful Archery (E)**: passive, 30% chance *chosen* per attack to add 15/25/35/45% of her agility as physical
  damage (charged arrow, crimson burst, a red "+N!" number), 0.8 s cooldown (the E icon shows it).
* **Blood Ranger (R)**: 15 s of 40/50/60% lifesteal and +200/300/400 attack range. Each attack that hits her has a 30%
  chance to make her leap 300 back, away from the attacker (stopped short by cliffs, trees and buildings). *Chosen*:
  at most one leap per second, so creep fire cannot chain them; the leap keeps her orders. 30 s cooldown, mana
  100-150 *chosen*.
* Masterful Archery was buffed on request from (8% + 10% per level) to (15% + 10% per level) of agility.

## Trees, Mini-Axe and Vegan Picker

Trees are destructible as in Dota (see `docs/MECHANICS.md`, "Trees"): they fall to the Mini-Axe (Quelling Blade),
Vegan Picker (Tango), Gale Impact and thrown units, and grow back after 180 s (current Dota value; it was 5 minutes in
older patches), waiting while a unit stands within 150. Tree Twig (Iron Branch) plants a 20 s tree. Regrowth and
planting animate in; eaten trees shrink away; felled trees topple away from the blow.

## Towers

Tower models are 40% smaller (scale 0.6; tier growth kept); the health bar, crystal light and bolt launch point
follow. Their footprint in the simulation is unchanged.

## Ezee, the Dark Paladin (added 2026-10-12)

Melee strength hero (`src/sim/sim_data.gd`, abilities in `src/sim/sim_abilities.gd`). Numbers you did not specify are
marked here so you can change them:

* **Dark Stomp (Q)**: 60/90/120/150 magic damage in 350 radius (damage and radius chosen), then a physics push away
  from Ezee: velocity falls off with distance and mass (creeps 1, heroes 1.2, siege 1.8), units fly in an arc, slide,
  bounce off walls and transfer momentum to units they hit. An enemy that crashes into a unit, tree, cliff or building
  takes 50/75/100/125 impact damage (chosen) and is stunned 0.7 s per level once it stops; a tree it hits is smashed.
  Cooldown 12 s, mana 100-130 (chosen).
* **Leap Strike (W)**: picks the visible enemy within 800 (range chosen) with the lowest health fraction, the nearest
  if none is hurt; nothing happens (no mana or cooldown spent) if no enemy is in sight. Leaps in 0.55 s and deals
  100/125/150/175 + 60% strength pure damage, slowing 40% (amount chosen) for 1.5 s. Cooldown 16/15/14/13 s.
* **Tainted Touch (E)**: lightning enchants the sword for 7 s; attacks add 60/90/120/150 magic damage and curse the
  target for 5 s (revealed to Ezee's team even when invisible, 300 sight radius around it). Cooldown 11 s.
* **Unholy Might (R)**: roar, 0.5 s screen shake, dark aura for 10 s. Each damage instance has a 30/40/50% chance
  (chosen) to be halved, the other half dealt as pure damage to a random enemy within 700 (chosen). Then a 50% slow
  for 2 s. Cooldown 25 s.
* Look: the customisable hero body in full plate (Warden Plate), visored greathelm, violet dyes and a darkened
  greatsword (`GameSettings.default_look("ezee")`). The bot plays Ezee with its own skill and item build.

## Map (overhauled 2026-10-12)

* Elevation: six jungle plateaus per side on high ground, reached by stone stairs with torch columns wherever a
  walkway crosses their edge. Each terrain level renders 2 m high (`LEVEL_HEIGHT` 200, visual only;
  the rules use levels).
* Mountains: impassable massifs in the corners (the river leaves through gorges) and along the edges, with a ring of
  peaks past the map edge, so there is no grey void. Mountain cells block movement and sight.
* Bases: crenellated walls with towers, roofs and banners; gate towers at ramps; emblem plazas (sun for Ancient
  Light, crescent for Black Sun); paved roads with kerbs and braziers; a quartermaster stall and supply clusters.
  Ancient Light has blossom gardens and flower beds, Black Sun has dead trees, graves and basalt.
* Shift queue and hotkey combinations: see Controls.

## Options and sound (added 2026-10-12)

Options from Hero Select and the pause menu, saved in `user://options.json`:
* **Audio**: Master, Effects, Interface, Ambience (0-100%; 50% sounds half as loud, -10 dB). Master starts at 50%, so
  the whole game is half as loud as before. "Mute when the game window is in the background".
* **Video**: window mode, resolution, V-Sync, frame limit, render scale, quality preset (Low, Medium, High, Ultra),
  show FPS. **Game**: edge pan, camera speed, screen shake, damage numbers. **Controls**: opens the Hotkeys screen.
* Captures and benchmarks ignore the saved window and quality settings so results stay comparable.

## Sludge, the Butcher (added 2026-10-13; Dota 2's Pudge, patch 7.41d)

Melee strength hero: Str 25 +3.0, Agi 13 +1.4, Int 16 +1.8, damage 45-51, armor 0, regen 2.5, speed 280, turn 0.7,
range 175, BAT 1.7, attack point 0.5. Numbers follow Dota exactly; only the names and the look are ours.
* **Growing Gut (innate)**: +2 strength for good whenever an enemy hero dies within 450 of him, or anywhere if he gets
  the kill. Kept through death.
* **Shuriken Hook (Q)**: always flies its full 1300 at 1600 speed, catches the first unit within 100 of the tip
  (enemy or ally, not ancients or buildings) and drags it back to where he threw it. Enemies take 150/220/290/360
  pure damage and are stunned while dragged; enemy creeps die at once; allies come back unharmed. Flies over cliffs
  and trees. A miss roots and disarms him for 0.53 s. 500 vision for 4 s where it catches. 18/16/14/12 s, 120 mana.
  Upgrade Gem: +20% of the drag distance as damage; catching an ally halves the cooldown.
* **Stench (W)**: toggle, works while stunned or channelling. 30/60/90/120 magic damage per second within 250 to
  enemies and to himself (never lethal), 14/20/26/32% slow. Upgrade Staff: +200 radius, +90 damage, -20% healing.
* **Blubber (E)**: blocks 8/14/20/26 of every damage instance for 4/5/6/7 s; does not break Chomp.
  20/19/18/17 s, 65/70/75/80 mana.
* **Chomp (R)**: channel 2.75 s on an enemy within 200: 80/100/120 + 0.3/0.6/0.9 x strength magic damage per second in
  6 ticks, healed back to him; the victim is stunned and pulled in. 30/25/20 s, 100/130/170 mana.
* **Talents** (levels 10/15/20/25, picked from the HUD; bots pick their own): +10% Stench slow / +5 armor; +150 hook
  damage / 8% spell lifesteal; -4 s hook cooldown / +0.75 s Chomp; 1.5x Growing Gut and Blubber / 1.5x Chomp.
* Look: a MakeHuman (CC0) butcher built in Blender (`tools/blender/sludge.py`, gear in `sludge_gear.py`) on the hero
  skeleton, so he uses all 132 hero animations; cleaver, apron, chain and a four-bladed shuriken on the hook.

## Combination items and the shop (added 2026-10-13)

Dota 2's items with plain names; prices, recipes, stats, actives and passives follow 7.41d (table with the Dota
names in `docs/MECHANICS.md`, "Items and shop").
* Recipe scrolls are bought like any item ("Recipe: Tough Band") and parts combine on their own as in Dota, in the
  inventory, and with the stash while in the base. Buying a finished item buys only the parts you are missing.
* Switch Boots have three recipes (Heavy Belt, Wizard Robe or Elf Band); the part you used decides the starting
  attribute, and the active switches strength, intelligence, agility. Boot speed does not stack.
* Shop (F4, Shop button): Basics and Upgrades tabs with columns like Dota's, a search box, a side pane with the item's
  bonuses, what it is made from and what it builds into, Buy (only the missing gold) and Sell. Left click selects,
  right click or double click buys; click an item in "Your items" to sell it; click a stashed item to take it.
* Capture flag `--shop=tab[,item[,search]]` opens the shop in the base with some gold and parts.

## Names added 2026-10-12 and 2026-10-13 (veto any you dislike)

* Teams Ancient Light and Black Sun; buildings Throne, Statue, Eye Ward; creeps Footman, Archer, Stone Golem, Flag
  Bearer, Ghoul, Skeleton Archer, Bone Golem, "Super" creeps; neutrals Goblin, Goblin Digger, Goblin Boss, Wolf,
  Alpha Wolf, Orc, Orc Shaman, Swamp Troll, Ogre, Fire Imp, Lava Golem.
* Old items renamed: Healing Paste, Mana Potion, Ripe Mango, Firefly Jar, Teleport Scroll, Tree Twig, Slippers, Heavy
  Gloves, Thinking Cap, Headband, Elf Band, Heavy Belt, Wizard Robe, Quick Blade, Fist Blades, Long Sword, Fast
  Gloves, Armor Ring, Chain Shirt, Healing Ring, Running Shoes, Zap Stick, Leech Mask, Swift Band, Zap Wand, Switch
  Boots, Dancer Sword, Long Spear.
* New parts: Giant Axe, Wizard Staff, Greatsword, Steel Hammer, Spear, Rust Stone, Brass Knuckles, Plate Vest, Big
  Healing Ring, Mana Stone, Health Crystal, Big Gem, Pointy Hat, Fur Hat, Sneak Charm, Jump Knife.
* New items: Tough Band, Smart Band, Mana Ring, Leaf Hat, Steady Ring, Slip Boots, Mana Boots, Medic Kit, Block
  Shield, Spike Armor, Gold Glove, Push Staff, Spell Shield, Armor Breaker, Shock Hammer, Cleave Axe, Sneak Blade,
  Upgrade Staff, Upgrade Gem; recipe scrolls "Recipe: <item>".
* Sludge "the Butcher", Growing Gut, Shuriken Hook, Stench, Blubber, Chomp (yours); Blood Ranger's title "the Archer".
* Shop: Basics, Upgrades, Consumables, Attributes, Armaments, Magic, Accessories, Support, Weapons, Armor, Abilities,
  Stash, Your items. Options: Audio, Video, Game, Controls, Effects, Interface, Ambience, Fortify (was Glyph of
  Fortification). Hero Creator presets Elf, Guard; styles Stars, Lava, Ghostly, Metal, Spotted, Tattoos,
  Mohawk, Wild Hair; outfit pieces named by colour and piece ("Sea Coat", "Heavy Plate").

## Names added 2026-10-13 b (veto any you dislike)

* HUD: To Buy, Clear, Auto, Stash, Grab All, Talents, Backpack, Carrying, Deliver, "Choose an enemy", "Choose an ally
  or a place".
* Courier commands: Return to Base (Home), Retrieve Items (Retrieve), Return Items to Stash (To Stash), Deliver Items
  (Deliver), Transfer Items (Transfer), Speed Burst (Burst), Shield, Auto Deliver (Auto); states Waiting, Moving,
  Going home, Fetching the stash, Picking up items, Delivering, Returning items.

## Neutral camps (2026-10-13 c)

* 14 camps a side as in Dota 7.41 (3 small, 7 medium, 3 large, 1 ancient), two of them pull camps by the safe lane's
  tier 1. Each spawn picks one of its kind's creep groups, never the same twice. Rules and sources: `docs/MECHANICS.md`,
  "Neutrals" (proximity aggro by day, sleep at night, 400 guard radius and 5 s chase, growth every 7:30, stack bounty).
* Each camp is a trampled clearing with a fire that burns day and night (with light), tents or round huts, a drying
  rack, stakes, bones, and a horned-skull totem whose cloth shows the size: small yellow, medium orange, large red,
  ancient violet. Props: `tools/blender/camps.py` (Blender) -> `assets/props/camp_*.glb`; placed by `src/game/camps.gd`.
* Hold Alt: spawn boxes on the ground (yellow; red while something other than the camp's creeps blocks them) with a
  label, and on the minimap. The minimap always shows Dota's camp marks (a triangle, bars for medium and large).

## Game Setup, bots, chat, pings, learning (2026-10-13 c)

* Bots follow Valve's bot design (research in `work/lemondev/2026-10-13-camps-ai-setup/research/bots.md`): a team
  brain hands out roles (1 safe lane carry, 2 mid, 3 off lane, 4 roamer, 5 safe lane support) so every lane is covered
  from three heroes up, and leaves the player's lane to the player (chosen in Game Setup, remembered from earlier games,
  or noticed in the first 2:30; the bot that gives way says so). Each bot scores its modes about 3-7 times a second.
* Bots chat to their team: lanes before the horn, missing enemies, ganks on heroes seen low or alone ("Their Sludge is
  low (35%) in the bottom lane. Going for the kill, Bot Doris come too."), pushes when enemies are dead, defence when a
  building is hit, danger when enemies gather, items they just finished, level 6, stacks. They ping what they call.
* Pings and typed calls from the player are answered: the quickest two or three bots go (by teleport when that is
  faster); others say why not: dead (and when they are back), low health, out of mana, TP on cooldown or none and too
  far, defending elsewhere, too many enemies there, ultimate on cooldown, the carry farming early, or simply not now.
* Difficulty follows Dota's bot levels (reaction delay, last hit error, spell lockouts). Unfair (your numbers, 2026-10-16 b):
  +200% gold (passive gold too) and +50% experience; melee Unfair bots buy a Jump Knife right after their boots.
* Learning (Options > Game, "Bots learn from games", on by default; "Forget what bots learned" clears it): a fight
  model trained on every fight a bot starts, a danger map of where heroes died, item builds chosen by UCB1 from their
  results, Shuriken Hook hit rates by distance, a retreat bar per hero, lane matchups, the player's usual lane.
  Options shows a summary. Automated runs and tests never read or write it.
* Adding a hero to the bots: roles, skill order, talents and builds in `src/sim/sim_bot_kits.gd` (and `burst`), the
  combo in `SimBot._spells_on`, AoE farming in `_farm_camp`, escapes in `_escape_spells`.

## Names added 2026-10-13 c (veto any you dislike)

* Screens and buttons: Game Setup, Presets, 5 vs 5, 1 vs 1 mid, Fill with bots, Remove bots, All bots, Set skill,
  Player, Hero, Skill or lane, Name, You, Bot, Empty, Random, Any lane, Safe lane, Mid, Off lane, Start.
* Bot skills (Dota's): Passive, Easy, Medium, Hard, Unfair. Bot names: Bot Kevin, Bot Doris, Bot Nigel, Bot Wanda,
  Bot Mabel, Bot Hank, Bot Tilly, Bot Barry, Bot Pip (with your Bot Gerald).
* Options: Center camera on hero at respawn, Show bot chat, Bots learn from games, Forget what bots learned.
* Camps: Small camp, Medium camp, Large camp, Ancient camp, (pull camp). Chat line: "Say to your team".

## Status effects, bash, critical strike, orbs, true sight (2026-10-13 d)

Run `work/lemondev/2026-10-13-controls-mechanics/` (contract in `contract.md`). Rules and sources: `docs/MECHANICS.md`
("Status effects", "True sight and disjoint", "Orbs", the attack and neutral sections).
* **Controls and HUD**: the cursor lock and edge pan above; the shop closes on a click elsewhere; health and mana show
  your own regeneration and the bonus (items, auras, consumables, the fountain) as a second, brighter "+N"; the comma
  buys a Teleport Scroll; holding S really stops.
* **Pseudo-random chances** (Dota's PRD) for every chance effect; **critical strike** decided when the attack starts
  (red "312!" number); **bash** (only one bash item works, 2.3 s apart, through debuff immunity).
* **Disables**: stun groups refresh to the longer time; hex (the unit becomes a sheep), silence, root, disarm, break,
  mute; status and slow resistance; basic and strong dispels; spell amplification; health restoration amplification.
  A disabled unit shows a **timer bar** under its health with the disable's name and seconds left ("Bashed 0.6",
  "Rooted 1.1"), and a mark on the model (stars, roots at the feet, a violet ring for silence, crossed blades for
  disarm, a red cracked ring for break).
* **New items** (Dota 7.41d numbers, our names; the Dota names are in `docs/MECHANICS.md`): Crit Sword, Crit Bow, Stun
  Club, Stun Blade, Sure Hit Staff, Silence Staff, Root Staff, Halberd, Hex Staff, Break Blade, Heavy Sword, Spell
  Sword, Twin Swords, Battle Staff; parts Huge Sword, Dodge Charm, Long Staff, Mana Tiara (shop: Basics > Big Parts);
  Reveal Ward and Reveal Dust (Consumables). Bots buy some of them and use the disables in fights.
* **Neutral creeps' abilities**: Alpha Wolf crit and aura, Goblin Boss speed aura, Goblin Digger disarm on hit,
  Swamp Troll break on hit, Orc magic resistance aura, Orc Shaman Stomp, Ogre Smash (red ring on the ground during its
  2.8 s wind-up), Wolf Snarl, Lava Golem splash and armor aura.
* **True sight**: towers, the Throne, the fountain, Reveal Wards and Reveal Dust see invisible heroes; invisible heroes
  never auto-attack; blinking, teleporting and turning invisible disjoint projectiles.
* **Orbs** (Dota's runes; "rune" is a banned word here): Gold, Water and Wisdom Orbs and six power orbs (Speed,
  Damage, Stealth, Healing, Magic, Shield) on Dota's timers at our map's spots (river at (-1300, 1300) and (1300,
  -1300), a gold spot in each jungle, a wisdom spot near each side edge). Right click to take one; the kill feed tells
  everyone; bots take the ones they see nearby. A Flask (Dota's Bottle) stores an orb and refills at the fountain.
  Dota's Illusion rune is not in yet (no illusions).
* Other rule fixes: uphill misses only for ranged attacks; evasion and magic resistance from several items multiply;
  the fountain heals 5% / 6% per second and lingers 3 s; Teleport is blocked by roots, mutes and hexes and a root ends
  its channel; healing reduction also lowers regeneration.
* Probes: `godot --path . -s tests/tools/controls_probe.gd -- --out=work/shots` (cursor lock, edge pan, hold Stop, shop
  close, comma, regen, disable bars, crit number, orbs, Smash warning).

## Names added 2026-10-13 d (veto any you dislike)

* Items: Crit Sword, Crit Bow, Stun Club, Stun Blade, Sure Hit Staff, Silence Staff, Root Staff, Halberd, Hex Staff,
  Break Blade, Heavy Sword, Spell Sword, Twin Swords, Battle Staff, Huge Sword, Dodge Charm, Long Staff, Mana Tiara,
  Reveal Ward, Reveal Dust, Flask.
* Orbs: Gold Orb, Water Orb, Wisdom Orb, Speed Orb, Damage Orb, Stealth Orb, Healing Orb, Magic Orb, Shield Orb.
* Neutral abilities: Crit, Pack Aura, Pace Aura, Weapon Grab, Break Strike, Magic Armor Aura, Thick Hide Aura, Splash,
  Snarl, Stomp, Smash.
* Shop groups: Big Parts, Swords, Magic (Upgrades). Hotkey: Buy Teleport Scroll. Option: Lock cursor to window
  (Windowed). Disable labels: Stunned, Bashed, Hexed, Silenced, Rooted, Disarmed, Broken, Muted.

## Elements, armor and damage types, magic amp, item menu, Azrin (2026-10-14)

Run `work/lemondev/2026-10-14-elements-azrin/` (contract in `contract.md`). Rules and tables: `docs/MECHANICS.md`
("Units and stats", "Status effects", "Azrin", "Items and shop").
* **Elements**: None, Fire, Water, Ice, Earth, Lightning, Nature, Dark, Light, on every unit and every damage source.
  Strong x1.25, weak x0.75, each element resists itself, Light and Dark beat each other. Damage numbers show "+25%" or
  "-25%" in the element's colour when it matters.
* **Damage and armor types**: Hero, Slash, Piercing, Siege, Blunt, Magic, Aether (pure) against Hero, Organic,
  Structure, Armored, Titan. Every old Dota pairing keeps its number; Fire Imp and Lava Golem attacks are Magic.
* **Magic amp**: 1% per 20 intelligence; items (Atuli family) stack with diminishing returns (each one half the one
  before). Intelligence magic resistance is now 1% per 25 (was Dota's 0.1% per point).
* **Kugmo, Igit, Atuli** (Sange, Yasha, Kaya) with the pairs Kugmo and Igit (was Twin Swords), Kugmo and Atuli, Igit
  and Atuli (shop: Upgrades > Swords).
* **Item menu**: right click an item (bags or stash): Sell (with the price), Disassemble (parts and scroll come back
  locked), Lock / Unlock, Move to Backpack / Inventory. Locked items show a padlock and never combine.
* **Accidental buy protection**: anything sells for its full price for 10 s after it is bought, and the menu counts the
  seconds down. A combined item keeps the pieces it was made of with their purchase times, so an item disassembled by
  mistake still sells for full price inside the 10 s, and a recipe bought on old parts refunds only the recipe in full.
* **Item effects**: Spike Armor (a turning crown of spikes while active; thorns fly back at attackers), Block Shield
  (a shield flash per block), Spell Shield (golden dome), Rust Stone / Armor Breaker (rust ring under the target),
  Frenzy Mask (red rage), Slip Boots (wind at the feet), Cleave Axe (a sweep across the cone).
* **HUD**: chips above the stats (element, damage type, armor type), each with a hover that explains it from the tables;
  the stats hover is a full sheet (attack; armor and magic resistance with the intelligence part; which elements hurt or
  are resisted; magic amp split into intelligence and items; spell, healing and mana regen amp; cast speed, mana cost,
  lifesteal, evasion, status and slow resistance; burns). The selected unit's card has the same chips and sheet.
* **Creep death sounds** (lane and neutral) 40% quieter: -7.4 dB, the volume sliders' loudness rule.
* **Azrin, the Flamemander**: see MECHANICS.md for every number. Your female_generic model is her body
  (`tools/blender/azrin_body.py`: 2 million faces decimated to 30,000, colours baked from the full mesh into a 2048
  texture with the head given 2.5x the texture space, her joints found from the mesh and fitted onto the hero
  skeleton, so she plays all 132 hero animations). In the Hero Creator it is the body choice "Athletic" (Body tab);
  hair, outfits, dyes and height work on it as on Blood Ranger, and worn pieces hide the skin under them. Face, skin,
  eye and shape sliders only change the standard body. Her default look: dragonhide armour, dark crimson silks, a
  circlet, flame-orange long hair. She hovers 0.75 m up (gliding, leaning into moves) over a pyre on scorched ground,
  with fire in her hands and hair, sparks and a warm light, in matches and on Hero Select.
* **Fire**: `src/game/fire_fx.gd` is a particle fire system used by all Fire: noise-shaded flame tongues (premultiplied,
  so they stay orange in daylight), embers on turbulence, smoke, flickering light, ember beds under burning ground.
  Azrin's spells (`src/game/azrin_fx.gd`): the javelin of fire dragging enemies, spirit-flame marks with a closing
  timer ring and their explosion, orbiting spirits that arc to their target, the tumbling burning hammer and the field
  of fire where it lands; any burning unit is wreathed in flame. Fire Imp and Lava Golem attacks use it too.
* New tools: `tests/tools/menu_probe.gd` (item menu and HUD readouts through real clicks, captures; `--4k`),
  `tests/tools/look_lineup.gd` (a hero's look in several outfits side by side), `tests/tools/fire_preview.gd` (the fire
  on its own). Capture flags: `--items=a,b,c` gives the hero items, `--cast=item:N` uses slot N.

## Names added 2026-10-14 (veto any you dislike)

* Yours (kept as given, now on the owner list): Azrin, the Flamemander, Fiery Javelin, Touch of Ember, Spirit of Fire,
  Divine Smite, Kugmo, Igit, Atuli, the Aether damage type.
* Items: Kugmo and Igit (was Twin Swords), Kugmo and Atuli, Igit and Atuli.
* Elements: None, Fire, Water, Ice, Earth, Lightning, Nature, Dark, Light. Damage types: Hero, Slash, Piercing,
  Siege, Blunt, Magic. Armor types: Hero, Organic, Structure, Armored, Titan.
* HUD: Sell for N gold, Disassemble, Lock, Unlock, Move to Backpack, Move to Inventory, Locked; chips "<type> attack",
  "<type> armor"; sheet headings Attack, Defense, Amplification; Magic Amp, Spell Amp, Healing Amp, Mana Regen Amp,
  Cast Speed, Mana Cost Reduction, Burning; status Burning.
* Hero Creator: Body (Standard, Athletic).
* Azrin's talents: +30 Fiery Javelin burn, +25 Attack Damage, +6% Magic Amp, -2s Touch of Ember cooldown, +2 Spirits of
  Fire, +200 Divine Smite damage, +0.8s Touch of Ember stun, -15s Divine Smite cooldown. Errors: "No spirits of fire",
  "Not enough room", "Cannot be disassembled".
* Elements chosen for existing units (veto freely): Blood Ranger Nature, Ezee Dark, Sludge Earth; creeps by team (Light,
  Dark); towers Earth; neutrals as listed in MECHANICS.md.

## Names added 2026-10-16 b (veto any you dislike)

* Error: "No valid target". Bot chat: "We're ahead in gold. Let's push <lane> and take their <building>."
* Code: `SimKits3.grip_pool`, `SimTeamAI.networth_lead`, `SimBot._boldness`, `_jump_in`, `_plan_knife`,
  `BOOT_UPGRADES`, `SimUnit.gold_mult` / `xp_mult` (was `gain_mult`), `UiKit.held_item_icon`, ability values
  `bounce_distance`, `min_distance`, icons `power_treads_str` / `_agi` / `_int`.

## Names added 2026-10-16 (veto any you dislike)

* Yours: Roydo, the Anomaly, Grip of the Ruler, Void Rush, Dark Matter Skin, Anomaly; Blau, the Master Tactician,
  Bounce Shot, Summon Boulders, Lay Trap, Place Turret.
* Ours: **Pilot Turret** (the Upgrade Staff skill), **Turret** (the unit), **Leave Turret** (the skill's tooltip while
  inside), buff bar "In a Turret", "Piloted", "Caught" (the trap's root).
* Talents (chosen): Roydo "+80 Grip of the Ruler damage" / "+250 Health", "-3s Void Rush cooldown" / "+6% Dark Matter
  Skin chance", "+0.6s Grip of the Ruler stun", "+10% Void Rush damage cut", "+12% Dark Matter Skin reflect", "-0.15s
  Anomaly attack time"; Blau "+50 Bounce Shot damage" / "+25 Attack Speed", "+2 Boulders" / "+0.8s Lay Trap root",
  "+4 Bounce Shot bounces", "+1 Bounce Shot hit per enemy", "+10% Turret damage", "+700 Turret health".
* Errors and tooltips: "Cannot build there", "Must target one of your turrets", "Needs the Upgrade Staff", "Blau
  climbs out of the turret. Moving does the same." Bot chat: "Into the turret."
* Code: SimKits3, SimBot16, Hero16Fx, roydo_skin shader, tools/blender/heroes16.py, tests/tools hero16_probe,
  anim_pops16, _cost16, stall_probe.

## Names added 2026-10-15 g (veto any you dislike)

* Items: **Scarf** (Dota's Shawl), **Spell Cloak** (Cloak), **Fade Cape** (Glimmer Cape). Talent: "+40 Overload
  damage".
* Menu and title: "Press any key", "Choose Hero" (was "Choose hero"), "Tip: ..." (eight tips in `main_menu.gd`).
* Tooltips: "Innate: always learned, from level 1", "Innate: <name>", "Grows with hero level", "Always on",
  "<Value> at level N", "N of M attacks: attack M bursts in an Overload.", "Takes N% more damage from Kragg's
  spells.", Overload's and Magnetize's new descriptions.
* Bot chat: "Getting <item> against their magic damage / their right clicks / their stuns / their invisible heroes /
  their evasion / getting caught.", "Bought <item>, they have invisible heroes.", "Dusting their <hero>.", "Fade Cape
  on you, <name>, run!", "Hold on, <name>! Coming." / "TP coming.", "Running to you, help me turn on them.", "Lost
  them in the trees, going home."
* Code: SimBotItems, SimBotTactics, RepairedClips (was HeroAnims, run h), TitleCard, MenuPlate; skin pieces menu_plate, menu_plate_gold,
  menu_banner, menu_footer, menu_nameplate; tools anim_audit, anim_repair, anim_sheet, kragg_probe.

## Names added 2026-10-15 f (veto any you dislike)

* **Rejuvenation Orb** (your name). **Fortify Mark** (the tower mark in the buff bar).
* Talent: "+1.5s Fast Forward cooldown cut".
* Texts: "Regenerates N per second", "Own N + bonus N", "Healing cut: -N", "Full in N s at this rate", "<name> used
  Fortify", "You used Fortify: buildings protected for 7 s", "Ready in N s", "Fortified towers hit it for N more
  physical damage (N marks).", Fortify's new tooltip lines.

## Names added 2026-10-15 e (veto any you dislike)

* Buff bar effect names: Stunned, Bashed, Frozen, Burning, Fountain, Flying, Health Regen Aura, Mana Regen Aura,
  Invisible (wards), Revealed (Reveal Dust), Armor Loss (corruption), Charge (Kragg's counter), Tired (after Unholy
  Might), Curse (Tainted Touch's curse), Static Charge. Everything else uses its ability, item or aura name.
* Tooltip words: Buff, Debuff, Aura (ally), Aura (enemy), "from <name>", "its own", "N s left of M", "Lasts while in
  range", "Any dispel removes it", "Only a strong dispel removes it", "N more buffs" / "N more debuffs".

## Names added 2026-10-15 c (veto any you dislike)

* Options > Game: **Quick cast** (with the note "Quick cast: a spell or item key casts at once where the mouse points
  (on the unit under it), with no second click."). The bots' learning summary adds "Teamfights called: N (won M)".
* Bot chat: "Fight! Focus their <hero>." (a teamfight call), "Keep going, their <building> next." (a push moving on).

## Names added 2026-10-15 b (veto any you dislike)

* Heroes: **Tock**, title the Clockmaker; skills Time Bolt, Fast Forward, Rewind, Slow Field, Quick Hands, Stop Time.
  **Kragg**, title the Magnet Knight; skills Iron Grip, Repel, Magnetize, Overload, Magnet Field; Charges. Talents:
  "+70 Time Bolt damage", "+2 Mana Regen", "+15% Slow Field slow", "+1.5s Fast Forward cooldown cut" (was "+30% Fast Forward speed"), "-6s Rewind cooldown",
  "+1s Quick Hands", "+1s Stop Time", "+30% Time Bolt delay", "+80 Iron Grip damage", "+6 Armor", "-3s Repel
  cooldown", "+2 max Charges", "+25 Overload damage per Charge", "+40 Magnet Field pull", "+1s Magnet Field stun",
  "+2 Iron Grip Charges".
* Items: Travel Boots, Blast Rod (2-5), Net Staff, Storm Hammer, Soul Gem, Time Crystal, Battle Armor, Small Shield,
  Leech Totem, Frost Plate, Burning Cape, Giant Heart, Leech Blade, Moth Blade, Refresh Stone, Guard Boots, Team
  Shield, War Drum, Long Lens, Crash Knife. Parts: Mana Gem, Swift Stone, Plate Armor, Gold Band, Wide Stone, Relic,
  War Axe, Troll Ring, Feather, Iron Helm, Speed Ribbon. Item powers: Static Charge, Blood Rage, Mend, Guard,
  Endurance; auras Armor Aura, Leech Aura, Battle Aura, Armor Loss Aura, Freezing Aura, Guard Aura, March Aura.
* Shop groups: Casting, Big Weapons, Boots. Stats: Cooldown Reduction, Spell Area, Cast Range, Cooldown Speed.
* Hotkeys: Extra ability 1-6. Debug: God mode, Free spells (shortened), Shop: open.
* Unit panel: Range, Attacks/s, Magic res., Level, Bounty, Experience, Sight day / night, Health regen, Mana regen,
  Invulnerable, Backdoor protection, Grown, Ally, Enemy, Neutral, Lane creep, Siege creep, Neutral creep, Ancient
  creep, Tower, Barracks, Throne, Building, Ward, Courier, No mana, Innate (always on); skill slots True Sight, Sight,
  Backdoor Protection, Fortify, Ancient, Flying; kinds Spell, Aura, Passive, Team.

## Names added 2026-10-15 (veto any you dislike)

* Multiplayer screens: Multiplayer, Servers, Main Server, Main server, Your Servers, Local Network, Join by Address,
  Address, Server password, Save to List, Connect, Host a Server, Server name, Password, Port, Players, Host Server,
  Open the port on my router (UPnP), Add Server, Remove, Refresh, Join Server, Your name, Server Password, Different
  Version, Could Not Connect, Could Not Host, Connecting to ..., Disconnected.
* Server lobby list: Lobbies, Lobby, Leader, Status, Waiting for players, Starting, In a match, Your hero waits, Join to
  play on, Players Online, Name, Where, Lobby list, Server Chat, Create Lobby, Quick Join, Join Lobby, Leave Server,
  Stop Hosting, Hosting, n online, Ping n ms, Lobby name, Teams, 5 vs 5, 1 vs 1 mid, Create, Lobby Password.
* Lobby: Your Hero, Random Hero, Your lane, Ready, Not Ready, Not ready, You are ready, Lobby Chat, Leave Lobby, Fill
  with Bots, Start Match, Lobby Settings, You lead this lobby, Slot, Add Bot, Remove Bot, Remove Player, Open Slot,
  Close Slot, Open, Closed, Click to move here, Waiting for a player, Nobody plays here, (you), Save.
* In a match: Menu, Pause Game, Unpause Game, Leave Game, Back to Lobby, Game Paused, Paused by ..., Waiting for the
  server, Catching up, Waiting for every player to load, Lost the connection to the server.
* Server messages: "... joined", "... left", "... joined the lobby", "... left the lobby", "... leads the lobby now",
  "... is back", "a bot plays their hero until they come back", "That lobby is full", "Wrong lobby password",
  "This server needs a password", "The server is full", "The lobby leader removed you".

## Backlog: smallest next actions first

0. Bots (2026-10-15 c): carries still farm about half what Dota's bots do by 10:00 (the safe-lane wave drifts to the
   enemy's tower and the carry gets zoned: lane control, pulls, standing back); games end but late (50-60 min);
   learning has not yet been shown to make bots stronger (`tests/tools/learn_ab.sh`, more games per arm).
0. Performance: a level-16 ten-hero brawl runs at ~48 fps on the RTX 4060 PC; the rest is the 30 Hz simulation tick
   (~8 ms when it runs), engine deferred work and drawing. Next levers: spread the bots' thinking across frames,
   animate crowds of creeps at a lower rate, or move the simulation's hot loops to C++ (GDExtension; needs a compiler
   and lockstep checks).

0. Multiplayer: set the main server's address (see Status); a blind review of the new screens; a test over the
   internet between two real machines (only this PC was used).

1. Bots: find why two bots stand still in a lane from 0:21 in every 5 v 5 game, then make games end (an Ancient
   falls within 60 min); then the frame time with 10 heroes.
1. Shuriken Hook: recheck the blind review with the frame where the hook has bitten (needs your OK, it changes the
   capture rule), with a shorter chain shadow.
2. Blind reviews not yet run: the shop, Sludge on Hero Select, the Options screen.
3. Map art (both reviews plateaued): modelled props and hand-painted paving instead of procedural boxes; decide
   whether to raise levels to 3-4 m with rock cliff faces beside the ramps.
4. Ezee's look on Hero Select: lighter or more reflective armour (the review plateaued on a dark silhouette).
5. Dark Stomp art: hand-painted spike texture with ground mounds; units visibly lifted by the eruption.
6. Performance: find the p95 spikes (p99 about 22-28 ms in both old and new builds).
7. Art pass on buildings:
   * Better Ancient design: floating crystal and rune ring instead of the stick arms.
   * Larger stone blocks on towers.
   * Replace the paving texture, which reads as a checkerboard.
8. Done: Hero Creator, Hero Select, Town Portal, buyback, courier, pause and settings menus, end screen with damage
   table, orbs (runes), Flask (Bottle), Reveal Ward and Dust. Still deferred: Roshan (pit, Aegis, cheese), illusions
   (and with them the Illusion orb and a Manta-style item), neutral items, Tormentors, shrines and outposts, scan,
   destroying orbs by attacking them, the Lava Golem's Fireball, the Fire Imp's spell aura, wards UI polish.
10. Dota mechanics still marked APPROX in `sim_const.gd` (hero kill gold, respawn times, true sight radii of towers,
   the Throne and the fountain, the Goblin Boss aura as flat speed): check them against Liquipedia when its API answers
   again (it returned 429 on 2026-10-13).
11. Bots: buy and use the Flask, Reveal Dust and Reveal Wards against invisible heroes; contest the river orbs as a team.
9. More heroes (the bot plays Blood Ranger, Ezee and Sludge, mid only). Mana Boots in a bot build.
