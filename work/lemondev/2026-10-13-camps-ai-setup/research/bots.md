# Dota 2 bot and team decision-making: research notes

Researched 2026-10-13 for the bot work in this run. Read-only web research. Facts labelled
**[Valve]** come from Valve's own wiki text or game files; **[community]** comes from guides and
open-source bot scripts; **[design]** marks my own recommendation, not a sourced fact.

Access notes: developer.valvesoftware.com now puts an anti-bot check in front of every request, so the wiki
text was read from verbatim GitHub mirrors of the same page ([S1b], [S1c]). Liquipedia rate-limited (HTTP 429),
and the Dota 2 Fandom wiki refused requests (402/403). Ping and chat strings were taken from the game's own
English localization file as tracked by SteamTracking ([S4]).

---

## 1. Valve's bot scripting architecture  (sources: [S1], [S1b], [S2], [S3])

**Three levels [Valve]**
- **Team level**: how much the team wants to push, defend or farm each lane, roam or kill Roshan. These desires
  are advisory only: they "do not dictate any actions taken by any of the bots" [S1].
- **Mode level**: each bot keeps scoring every mode, and the highest-scoring mode becomes the active mode. Only
  the active mode issues actions.
- **Action level**: move, attack, cast, buy, and so on (roughly one mouse click each).

**Override points (one file per element, each in its own Lua scope) [Valve]**

| File | Functions | Called |
|---|---|---|
| `bot_generic.lua` / `bot_<hero>.lua` | `Think()` (full takeover: no team or mode logic runs), `MinionThink(hMinion)` | every frame |
| `mode_<mode>_generic.lua` / `mode_<mode>_<hero>.lua` | `GetDesire()`, `OnStart()`, `OnEnd()`, `Think()` | GetDesire about every 300 ms; Think every frame while active |
| `ability_item_usage_generic.lua` / `_<hero>.lua` | `AbilityUsageThink`, `ItemUsageThink`, `CourierUsageThink`, `BuybackUsageThink`, **`AbilityLevelUpThink`** | every frame |
| `item_purchase_generic.lua` / `_<hero>.lua` | **`ItemPurchaseThink()`** | every frame |
| `team_desires.lua` | `TeamThink`, `UpdatePushLaneDesires`, `UpdateDefendLaneDesires`, `UpdateFarmLaneDesires`, `UpdateRoamDesire`, `UpdateRoshanDesire` | every frame |
| `hero_selection.lua` | `Think()` (picking), `UpdateLaneAssignments()` (10 PlayerID to lane pairs), `GetBotNames()` | every frame before the game starts |

If a function is missing, the game falls back to the built-in C++ code for that piece. Fully taken-over bots still
get the difficulty modifiers.

**Modes that can be overridden [Valve]**, with their enum values from the bot API constants [S3]:
`laning`(1), `attack`(2), `roam`(3), `retreat`(4), `secret_shop`(5), `side_shop`(6), `rune`(7),
`push_tower_top/mid/bot`(8/9/10), `defend_tower_top/mid/bot`(11/12/13), `assemble`(14), `team_roam`(16),
`farm`(17), `defend_ally`(18), `evasive_maneuvers`(19), `roshan`(20), `item`(21), `ward`(22). `NONE`=0.
Later patches added more (for example outpost and shrine modes appear in community scripts).

**Desire scale [Valve constants, via S3]**

| Constant (`BOT_MODE_DESIRE_*` and `BOT_ACTION_DESIRE_*`) | Value |
|---|---|
| NONE | 0.0 |
| VERYLOW | 0.1 |
| LOW | 0.25 |
| MODERATE | 0.5 |
| HIGH | 0.75 |
| VERYHIGH | 0.9 |
| ABSOLUTE | 1.0 |

- `GetDesire()` "needs to return a floating-point value between 0 and 1" [S1]. In practice community scripts return
  values above 1 (for example 3.33) to force a mode, and a modder reported the built-in modes reaching about 1.4 [S5].
- Ability usage uses the same pattern. Each `ConsiderX()` returns `(desire, target)` and the highest desire is cast
  (Valve's Lina example, [S2]).
- Helpers: `RemapValClamped(v, inMin, inMax, outMin, outMax)` turns a raw score into a desire band. Valve's
  `defend_ally` example returns `RemapValClamped(score, 0, 1, NONE, HIGH)`, so the mode is capped at HIGH and
  retreat (which can go higher) still wins [S2].
- `GetActiveMode()` and `GetActiveModeDesire()` let one mode read another. A common pattern is "if retreat is
  active at >= HIGH, return NONE" in rune, ward, farm and shop modes [S6].

**Bonus for the current mode**: Valve's documentation does **not** describe a stickiness bonus or hysteresis for the
active mode, and I found no source that confirms one. **[design]** Add one yourself: for example +0.05 to +0.1, or
x1.1, on the active mode's desire, plus a minimum commitment time of 1 to 2 s. Without it, two close modes flip back
and forth every 300 ms. The utility-AI talks recommend the same thing ([S20]).

**Team desires: shape and use [Valve]**
- `UpdatePushLaneDesires()`, `UpdateDefendLaneDesires()` and `UpdateFarmLaneDesires()` each return
  `{top, mid, bot}` floats in 0..1. `UpdateRoamDesire()` returns `{desire, hTargetUnit}`.
  `UpdateRoshanDesire()` returns one float. Valve's stub file returns constants such as `{0.0, 0.5, 1.0}` [S2].
- Modes read them through globals: `GetPushLaneDesire(lane)`, `GetDefendLaneDesire(lane)`, `GetFarmLaneDesire(lane)`,
  `GetRoamDesire()`, `GetRoamTarget()`, `GetRoshanDesire()`. For example, `push_tower_mid` uses the team's mid push
  desire as an input, and `team_roam` uses the roam desire and target. The exact way the C++ modes blend team and
  bot desire is not documented.
- Useful world queries: `GetLaneFrontLocation(team, lane, delta)` and `GetLaneFrontAmount` (0..1 along the lane),
  `GetUnitPotentialValue` (fog-of-war "potential location" grid, 0..255), and hero "power" (estimated damage to
  enemies over 5 s plus stun duration plus half the slow duration) [S1].

**Example of a real push-desire function** (OpenHyperAI, [S6]). It is a good model of the factors that matter:
- Hard gates (return NONE or near-NONE): an enemy is at our Ancient; we are alone while 3 or more enemies are alive;
  we have 2 or more fewer heroes alive than the enemy; any teammate is below level 6; it is a core's laning phase
  and the lane is not its own; the team is doing Roshan.
- Caps: our HP is under 50%, so the cap is 0.25. All 5 enemies are alive and we do not have more, so 0.41. The lane
  front is deep in the enemy base and we lack numbers, so 0.08. A key spell or item is on cooldown and the enemy
  has equal numbers, so 0.5.
- Score: 0.5 base, plus 0.3 with Aegis, plus net-worth lead (3k to 20k maps to 0 to 1.5), plus level lead (0 to 8
  maps to 0 to 0.8), plus more alive heroes (1 to 3 maps to 0.1 to 0.4). Then multiply by own HP% and remap into
  [0, cap] (cap 0.82).
- A human **danger ping** near a tower forces push desire to 0.9 for that lane, and a recent defend ping suppresses
  pushing.

**Item purchase and level-up hooks [Valve]**: Valve's `item_purchase_lina.lua` is just an ordered list of components
(recipes included). Each frame it calls `SetNextItemPurchaseValue(cost)`, buys the head of the list when gold allows,
and pops it [S2]. `AbilityLevelUpThink` is normally a fixed per-hero skill order, and talents go into the same list.

**Difficulty [Valve]**: see section 6.

---

## 2. Positions 1 to 5 and lane setup  (sources: [S4] glossary, [S7], [S8], [S9])

Safe lane = Radiant bottom / Dire top; off lane = Radiant top / Dire bottom [S4]. Standard setup:
**safe lane 1+5, mid 2 (solo), off lane 3+4**. Position 4 often leaves the lane to roam.

| Pos | Role | Laning (0 to ~10 min) | Mid game (~10 to 30) | Late game (30+) |
|---|---|---|---|---|
| 1 | Carry, farm priority 1 | Every last hit, few deaths, keep the wave near own tower | Farm lanes and jungle, join fights only near farm or on a power-spike item, flash-farm safe lanes | Strongest hero; fight around carry's items; take objectives; keep buyback gold |
| 2 | Mid, farm priority 2 | Solo XP and last hits, control the power runes, kill the enemy mid if possible | Tempo: gank side lanes on level 6 and rune timings, start teamfights | Second core; often the playmaker or nuker |
| 3 | Off lane, farm priority 3 | Survive, take XP, harass and pressure the enemy carry, keep a tower to fall back to | Initiator and front line, tower pressure with supports, draws attention so pos 1 can farm | Initiation items (jump, aura items), soak damage |
| 4 | Soft support / roamer | Harass, contest the enemy pull, check runes, rotate to gank mid and the other lanes | Smoke ganks, vision, picks, small jungle farm | Utility items, save and initiate, vision |
| 5 | Hard support | Protect the carry, pull and stack, deny, wards, stop the off-lane harass | Wards and dewards, smoke, team utility items, stay with the cores | Weakest hero; vision, saves, buyback-free sacrifice |

Farm priority falls from 1 to 5. Supports pay for wards, smoke and shared items. OpenAI Five even assigned
"who buys wards" to whichever hero it predicted would have the lowest net worth [S10].

---

## 3. Laning fundamentals for bots  (sources: [S4] glossary, [S11], [S12], [S13]; numbers in `docs/MECHANICS.md`)

- **Last hit**: attack so the hit lands when creep HP <= your damage. Predict incoming damage from the other
  creeps. Lane creeps should not be auto-attacked; every extra hit pushes the wave.
- **Deny**: hit own creeps under 50% HP. Deny ranged creeps first (more XP). Every deny also slows your own
  wave's push.
- **Equilibrium**: the ideal meeting point is just outside your own tower's range, so the enemy must overextend
  to farm. Push state means you are exposed; freeze state (just in front of your tower) is safest for the carry.
  Last hits push the lane; denies, pulls and aggro pull it back.
- **Creep aggro**: an attack order on an enemy hero within 500 of enemy creeps draws them for about 2.3 s, with a
  3 s cooldown. Spells do not draw aggro. Attack-ordering your own unit sheds aggro. Use aggro to drag the
  meeting point toward your tower, and harass with spells or from outside the 500 range [S4], [S12].
- **Tower aggro**: attacking a hero near an enemy tower draws the tower. Shed it by attack-ordering an allied
  creep that is closer to the tower. Never stand under an enemy tower without creeps around.
- **Harass timing**: hit or cast on the enemy when they walk up for a last hit (their attack is committed and
  their position is known). Trade only when your creeps outnumber theirs.
- **Pull** (pos 5): aggro the small or hard camp so the next lane wave fights neutrals. This denies the wave and
  resets equilibrium. Stack then pull to kill the whole wave. It is risky if the enemy can dive while your wave is
  away [S12].
- **Stack**: pull a camp out of its spawn box at about xx:53 to xx:55 so it respawns. Supports stack, and cores
  or AoE heroes clear the stack.
- **Leave the lane when**: the lane is lost (tower down, or repeated deaths, so go to the jungle or another lane);
  an item needs a secret-shop or base trip (use the courier first); you hit level 6 or a rune or power spike and
  a nearby lane is gankable; the wave just pushed into the enemy tower (free window to gank, stack or jungle); or
  HP or mana is low with no regen (back off or recall rather than die).
- **Lane vs jungle**: always take the lane wave first (it is worth more and pushes the tower). Clear it near
  mid-lane, then farm the nearest jungle camps while the next wave walks, and come back. Mid-game cores loop:
  wave, camp, camp, wave.
- **Split push**: one durable or escape-capable hero pushes a far lane while the team shows on the other side.
  This works only with vision and a teleport ready. Retreat as soon as more than one enemy goes missing.

---

## 4. Fights, ganks, objectives  (sources: [S4], [S6], [S10], [S14])

**Fight/gank inputs used by humans and good scripts**

| Factor | How it enters the score |
|---|---|
| Numbers (alive and nearby) | Strongest single term. Do not engage while 2 or more down. OpenHyperAI gates pushes on alive counts [S6] |
| Power spikes | Level 6 (ultimates), key items (jump, BKB, carry core item), Aegis. Compare average levels and net worth |
| Cooldowns | Wait while a key spell or item is on cooldown (OpenHyperAI `ShouldWaitForImportantItemsSpells`) |
| HP and mana | Scale desire by HP%. Below ~30% HP with 2 or more enemies on you, retreat at HIGH to ABSOLUTE |
| Estimated damage | `GetEstimatedDamageToTarget(..., 3 s)`: can we kill them before they kill us? (Valve `defend_ally`) |
| Buyback | Can the enemy cores buy back? Forcing buybacks is an objective in itself [S4] |
| Vision | Unknown enemies count as present near the fog-of-war "potential location" (Valve grid) |
| Tower proximity | Fight under your tower, not theirs. Dive only with clear advantage |
| Respawn timers | A pick on an enemy core opens a window for towers or Roshan of about the respawn time |

**Retreat triggers**: HP falling fast; outnumbered nearby; key spells used and an enemy ultimate unknown; enemy
team missing; tower diving without creeps. Defend-ally triggers when a teammate is in retreat and the nearby
enemy is not too strong for us [S2].

**When to take towers**: after a won fight or a pick, while enemies are dead (the respawn window), with a creep
wave (backdoor protection makes towers past tier 1 hard without creeps [S4]), with Aegis, and when enemy
glyph is down.

**Defend**: send the nearest heroes; teleport in when the attacking group is small enough. If the enemy has 2 or
more more alive, give up the outer tower and defend high ground instead. Use glyph to stall a wave. Clear waves
before they reach high ground.

**Regroup**: before a push or Roshan, gather (`assemble` mode) at a point near the target and wait for key
cooldowns. After a fight, split back to farm when the map is quiet ("Split up and farm").

**OpenAI Five's style lessons** [S10]: it pressed hard when ahead and avoided fights and farmed when behind. It
put resources on its strongest heroes. It rotated heroes across the map much more than humans. It spent long
cooldowns and consumables freely. It knew finely when a low-HP attack was still worth it. Early versions all
grouped as 5 in one lane, a local optimum that lost the other lanes' resources.

---

## 5. Pings and chat wheel  (source: game localization [S4], in-game glossary)

**Controls**: Alt+Left Click on world or minimap gives a normal ping. Holding Alt+Left Click opens the **ping wheel**
(the delay is configurable). Ctrl+Alt+Click gives the **danger/warning** ping (Valve's bot API reports this as
`normal_ping = false`). Alt+click on HUD elements (abilities, items, HP bar, glyph, buyback, shop items, runes)
posts a status line to team chat. Bot API: `ActionImmediate_Ping(x, y, bNormal)`, `ActionImmediate_Chat(msg,
bAllChat)`, `GetMostRecentPing()` [S1].

**World ping messages** (format: label plus location):

| Ping | Chat text |
|---|---|
| Ground (normal) | "Pinged (location)" |
| Danger | "Warning (location)" |
| Ping wheel | On My Way, Caution (retreat), Attack, Defend, Assist, Enemy Has Vision, We Need Vision, Stack Creeps, Pull Creeps, Heal me! |
| On an enemy hero or building | "Attack <target>" |
| On an allied hero or building | "Defend <target>" / "Assist <target>" |
| Confirmation | "N Teammates Are Attacking X (M disagree)"; smoke: "X Is Calling For Smoke (N Agree, M Disagree)" |

**Alt+click status templates** (placeholders mine):
- Ability: `<Name> (Level N) Ready`, `... Not Enough Mana ( Need N more )`, `... On Cooldown ( N seconds remain )`,
  `... Not Learned`, `I need N more levels to Learn <Name> ( Level L )`.
- Item: `<Item> Ready`, `<Item> Charges remaining: N`, `... On Cooldown ( N seconds remain )`, `In Backpack`, `In Stash`,
  `On Courier`.
- HP bar: `I have N HP and M Mana`; on others `Ally/Enemy <Hero> has N HP and M Mana`; dead: `... will respawn in N
  seconds!`.
- Shop item: `Need N gold for <Item>` / `I have enough gold for <Item>` (optionally "and Buyback").
- Buyback: `Buyback Ready`, `Buyback Not Enough Gold ( Need N )`, `Buyback On Cooldown ( N seconds remain )`.
- Glyph: `Glyph of Fortification Ready` / `On Cooldown ( N seconds remain )` / `Don't Use Yet`.
- Rune timers: `Power Rune spawns in T (at mm:ss)`; spotted: `Haste rune here (location)`.
- Enemy ability: prefixed "Beware ..." and may add "(Potentially on Cooldown)".

**Typical chat wheel lines**: Okay. / Careful! / Get Back! / Help! / Push now / Missing! (also Missing
top/mid/bottom) / Go! / Initiate! / Follow me / Group up / Spread out / Split up and farm / Attack now! / On my
way / Get ready / Bait / Out of mana / Skills on cooldown / Ultimate ready / Enemy returned / All enemy heroes
missing! / Enemy incoming! / Invisible enemy nearby! / We need wards. / We need detection / Stack neutrals /
Pull creeps please / Roshan / Let's smoke gank! / Fight under the tower / Deny the tower! / Wait / Well played! /
Good game.

**Valve's built-in bot chat lines** (good templates for bot callouts): "Attacking X!", "Pushing X",
"Defending X", "Roaming to X to gank", "Go on X!", "I'm retreating", "Checking top rune", "Doing Roshan!",
"Leaving Roshan", "Going back to X", "I think we should use Glyph".

---

## 6. OpenAI Five, and Dota's bot difficulties  (sources: [S10], [S15], [S1b])

**OpenAI Five** [S10]
- Beat world champions OG 2-0 (April 2019). In Arena it won 99.4% of 7,257 public games (abandons counted as wins).
- Acts every 4th frame (~7.5 Hz). Average reaction time is 217 ms. 17-hero pool; illusions and summons removed.
- **Still scripted** even at superhuman level: ability build order, item purchase order (with consumable refills),
  inventory/backpack swaps, and courier control. Build orders were randomly perturbed in training for robustness.
- **Measurement**: TrueSkill against a fixed pool of reference agents. 0 is random, a hand-coded scripted bot is
  about 100, and the final agent is 254. 8.3 TrueSkill is about an 80% win rate. Auxiliary heads predicted win
  probability, final net-worth rank and "will I help kill building X".
- **Reward shaping** (zero-sum, decays by 0.6 per 10 min of game time): win 5; hero death -1; gold 0.006/gold;
  XP 0.002; last hit about 0.4 net; deny 0.15; T1/T2/T3 tower 2.25/3/4.5; barracks 6; Aegis 5; courier death -2;
  HP change 2 (weighted toward low HP). **Team spirit** blends each hero's reward with the team mean, raised
  from 0.3 to 0.8 during training. The horizon was raised from 180 s to 360 s, and the agent effectively planned
  6 to 12 minutes ahead.
- **Learned behaviours**: fast, early aggression and rotations; contesting the enemy safe lane rather than holding
  its own [S15]; frequent hero reassignment across the map; free use of long cooldowns; finely judged low-HP
  aggression. Early runs grouped as 5 in one lane (a local optimum), which led to random **lane assignments** in
  training with a small penalty for leaving the assigned lane (an ablation later showed this was not needed).

**Built-in difficulty levels [Valve]** [S1b]

| Level | Ability/item use | Last-hit timing error | Other |
|---|---|---|---|
| Passive | none (no abilities, items or courier) | ±0.4 s (enemy creeps), ±0.2 s (denies) | stays in laning mode |
| Easy | 0.5 to 1.0 s delay; blocked 6 s every 8 s; 6 s lockout after each use | ±0.4 s / ±0.2 s | |
| Medium | 0.3 to 0.6 s delay; blocked 3 s every 10 s; 3 s lockout after each use | ±0.2 s / ±0.1 s | |
| Hard | 0.1 to 0.2 s delay | exact | |
| Unfair | 0.075 to 0.15 s delay | exact | **+25% gold and XP** |

---

## 7. Lightweight "learn between matches" ideas  (sources: [S16] to [S21])

| Technique | What to store | Update | Use |
|---|---|---|---|
| **Elo/TrueSkill matchup table** [S16] | Rating per hero (and per hero pair or lane matchup) | After each match: `R += K*(result - expected)` | Picks, lane assignment, fight confidence |
| **Bandit item-build choice** (UCB1 or Thompson) [S17], [S18] | Per hero: wins/plays per build variant (or per first core item vs enemy comp) | Credit at match end | Choose a build; keep exploring with UCB1 `mean + sqrt(2 ln N / n)` |
| **Dynamic scripting** [S19] | Weight per rule (for example "dive when +2 levels") | Rules used in a win gain weight, losses lose it; clamp and keep the total fixed | Rules sampled by weight next match; gives variety and adaptation |
| **Online logistic regression on fights** [S21], [S22] | Features: alive-count diff, level/net-worth diff, ultimates ready, HP sums, tower distance | One SGD step per fight with outcome (won/lost/traded) | Predicted P(win fight) feeds attack/push/retreat desires |
| **Danger heatmap / influence map** [S20], [S1] | Coarse grid of deaths and ganks taken (per team side) | Add on death, decay each match (x0.9) | Raise retreat desire, avoid paths, place wards |

Notes **[design]**:
- Keep learned terms as small additive biases (±0.1 desire) on top of the hand-written desires. OpenAI Five kept
  builds and item purchases scripted even at superhuman level [S10].
- Win-prediction work shows that game state predicts outcomes well: up to 85% accuracy 5 minutes in with standard
  models [S22]. Hero picks alone reach about 60 to 70% [S21]. So a fight-outcome model on state features is
  realistic.
- Persist per-matchup records in a small JSON file and cap the counts (or decay them) so old patches fade.

---

## Sources

- [S1] Valve Developer Community, "Dota Bot Scripting": https://developer.valvesoftware.com/wiki/Dota_Bot_Scripting
- [S1b] Verbatim mirror of S1 (with difficulty, potential-location and hero-power sections): https://github.com/p6668/dota2bot-and-fretbots/blob/main/BOT_API.md
- [S1c] Second mirror of S1's architecture text: https://github.com/hetong007/SiriusAI-customized
- [S2] Valve example bot scripts (team_desires.lua, item_purchase_lina.lua, ability_item_usage_lina.lua, mode_defend_ally_generic.lua), tracked by SteamTracking: https://github.com/SteamTracking/GameTracking-Dota2/tree/master/game/dota/scripts/vscripts/bots_example
- [S3] Bot API constant values (desire scale, mode enums): https://github.com/ellysh/dota2-oma-bots/blob/master/bots/tests/global_constants.lua and https://github.com/adam3q/Vscode-dota2-bot-script-snippets ; ModDota bot API index: https://docs.moddota.com/lua_bots/
- [S4] Dota 2 English localization (chat wheel, ping, alt-click, bot chat strings, in-game glossary): https://github.com/SteamTracking/GameTracking-Dota2/blob/master/game/dota/pak01_dir/resource/localization/dota_english.txt
- [S5] r/dota2AI, "Calling different modes" (desire ranges in practice): https://www.reddit.com/r/dota2AI/comments/5mdi7r/calling_different_modes/
- [S6] OpenHyperAI bot script (push, retreat, and other modes): https://github.com/forest0xia/dota2bot-OpenHyperAI (see `bots/FunLib/aba_push.lua`, `bots/mode_retreat_generic.lua`)
- [S7] ProGameGuides, "All Dota 2 Positions, Explained": https://progameguides.com/dota-2/all-dota-2-positions-explained/
- [S8] esports.net, "Dota 2 Positions and Roles Explained": https://www.esports.net/news/dota/positions-in-dota-2
- [S9] Hotspawn, "All Positions in Dota 2 Explained": https://www.hotspawn.com/dota2/guide/all-positions-in-dota-2-explained
- [S10] Berner et al. (OpenAI), "Dota 2 with Large Scale Deep Reinforcement Learning", 2019: https://arxiv.org/abs/1912.06680
- [S11] ProSettings, "Dota 2 Laning: 10 Common Questions Answered": https://prosettings.net/blog/dota-2-laning-tips/
- [S12] Profilerr, "Dota 2 creep equilibrium guide": https://profilerr.net/dota-2-creep-equilibrium-guide/
- [S13] Liquipedia, "Creep control techniques" (rate-limited during this run; cited for completeness): https://liquipedia.net/dota2/Last_hit
- [S14] OpenAI Five 2018 behaviour summary, GamesBeat: https://gamesbeat.com/?p=159913
- [S15] Same as S14 (safe-lane contest), plus OpenAI blog https://openai.com/index/openai-five/ (blocked during this run)
- [S16] Herbrich, Minka, Graepel, "TrueSkill: A Bayesian Skill Rating System", NeurIPS 2006: https://www.microsoft.com/en-us/research/publication/trueskilltm-a-bayesian-skill-rating-system/
- [S17] Auer, Cesa-Bianchi, Fischer, "Finite-time Analysis of the Multiarmed Bandit Problem" (UCB1), Machine Learning 47, 2002: https://link.springer.com/article/10.1023/A:1013689704352
- [S18] Tavares et al., "Rock, Paper, StarCraft: Strategy Selection in Real-Time Strategy Games", AIIDE 2016: https://ojs.aaai.org/index.php/AIIDE/article/view/12857
- [S19] Spronck et al., "Adaptive game AI with dynamic scripting", Machine Learning 63(3), 2006: https://link.springer.com/article/10.1007/s10994-006-6205-6
- [S20] Dave Mark, "Modular Tactical Influence Maps", Game AI Pro 2, ch. 30: https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter30_Modular_Tactical_Influence_Maps.pdf ; Mark & Dill, "Improving AI Decision Modeling Through Utility Theory", GDC 2010: https://gdcvault.com/play/1012410/Improving-AI-Decision-Modeling-Through
- [S21] Conley & Perry, "How Does He Saw Me? A Recommendation Engine for Picking Heroes in Dota 2", Stanford CS229, 2013: https://cs229.stanford.edu/proj2013/PerryConley-HowDoesHeSawMeARecommendationEngineForPickingHeroesInDota2.pdf
- [S22] Hodge et al., "Win Prediction in Multi-Player Esports: Live Professional Match Prediction", IEEE Trans. Games 2021: https://eprints.whiterose.ac.uk/id/eprint/152931/
