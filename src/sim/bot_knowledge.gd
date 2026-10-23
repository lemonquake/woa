class_name BotKnowledge
extends RefCounted
## What the bots know about the game, so their talk makes sense (run 2026-10-23, the owner: "add more context to the AI
## player's thoughts/logic, making them have vast knowledge about the heroes and mechanics of the game, not just blabber
## random stuff that make no sense like mentioning an item not even worth mentioning").
##   * Items: only the ones worth talking about (a finished big item or a real counter) have a purpose here; starting
##     items, parts and consumables are never named in chat (Iron Branch, Tango, Circlet, a recipe...).
##   * Heroes: for each, what makes it dangerous, how to beat it, when it gets strong and the items that answer it.
##   * Rules: the mechanics players argue about (bounties, buyback, Fortify, orbs, night, high ground...).
##   * A digest of the match as a player sees it: levels, scores, the items that matter, ultimates up, who is dead.
## Used by SimBotChat (its own lines), LlmChat (the online chat writer) and the forum writer.

## Items worth naming, and what they are for, in a player's words.
const ITEM_WHY := {
	"jump_knife": "blink in to start a fight or out to escape", "crash_knife": "blink in with a stomp that slows",
	"spell_shield": "spell immunity: magic and disables stop working on you", "glimmer_cape": "turn an ally invisible with a magic shield",
	"push_staff": "push yourself or an ally 600 away to escape", "hex_staff": "turn an enemy into a harmless critter (hex)",
	"silence_staff": "silence an enemy so it cannot cast", "root_staff": "root an enemy in place",
	"net_staff": "an area net that holds enemies", "halberd": "disarm an enemy carry so it cannot attack",
	"stun_club": "a chance to bash (stun) on attacks", "stun_blade": "bash on attacks and an active stun on one target",
	"crit_sword": "critical strikes", "crit_bow": "big critical strikes", "armor_breaker": "attacks strip armor",
	"cleave_axe": "attacks cleave around the target", "twin_swords": "attack speed, health and status resistance",
	"igit_atuli": "attack speed, move speed and magic amp", "kugmo_atuli": "health, magic amp and slow resistance",
	"heavy_sword": "strength and slow resistance", "spell_sword": "intelligence and magic amp", "yasha": "agility and move speed",
	"frost_plate": "armor and an icy blast that slows everyone around", "storm_hammer": "chain lightning on attacks",
	"shock_hammer": "chain lightning on attacks", "refresh_stone": "refresh every cooldown for a second ultimate",
	"sure_hit_staff": "attacks never miss (beats evasion)", "leech_blade": "huge lifesteal burst when activated",
	"time_crystal": "shorter cooldowns", "battle_armor": "armor and attack speed for the team",
	"giant_heart": "a lot of health and regeneration", "moth_blade": "evasion: attacks miss you",
	"break_blade": "go invisible and break passives", "sneak_blade": "go invisible to get in or out",
	"burning_cape": "burns everything near you and makes them miss", "team_shield": "a magic barrier for the whole team",
	"guard_boots": "heal and armor for the team", "spike_armor": "return damage to whoever hits you",
	"upgrade_staff": "upgrades your ultimate or a spell", "dagon": "a burst of magic damage", "dagon_2": "a burst of magic damage",
	"dagon_3": "a burst of magic damage", "dagon_4": "a big burst of magic damage", "dagon_5": "a huge burst of magic damage",
	"travel_boots": "teleport to any allied creep or building", "gold_glove": "early gold and experience",
	"mask_of_madness": "attack speed and lifesteal, but you take more damage", "dragon_lance": "longer attack range",
	"leech_totem": "lifesteal and armor aura for the team", "medic_kit": "heals and armor for the team",
	"war_drum": "move and attack speed for the team", "reveal_dust": "reveal invisible enemies around you",
	"reveal_ward": "true sight on a spot (invisible heroes)", "observer_ward": "vision on a spot",
	"long_lens": "longer cast range", "relic": "big attack damage", "huge_sword": "big attack damage",
	"soul_gem": "health and mana", "feather": "agility", "war_axe": "strength", "long_staff": "intelligence",
}
## Items that matter even though they are cheap (counters and vision).
const TACTICAL := ["reveal_dust", "reveal_ward", "observer_ward", "glimmer_cape", "push_staff", "jump_knife"]
## Worth advising ("buy dust") but not worth naming as something a hero has.
const CONSUMABLE := ["reveal_dust", "reveal_ward", "observer_ward"]

## Each hero: threat (what makes it dangerous), beat (how to play against it), spike (when it is strong), counter (items
## that answer it), tip (a short warning a player types in chat).
const HEROES := {
	"blood_ranger": {"threat": "long range right-click carry; Burst Shot rains arrows on a whole area and Gale Impact hurls you into walls",
		"beat": "jump on her, she is fragile; step out of Burst Shot, it is channelled so a stun or silence ends it",
		"spike": "her ultimate (lifesteal and extra range) and attack items", "counter": ["jump_knife", "halberd", "moth_blade"],
		"tip": "stun the ranger when she starts burst shot"},
	"ezee": {"threat": "dark paladin who leaps onto the lowest-health hero and stomps people into walls for stuns",
		"beat": "do not stand next to trees or walls near him; kite him after Unholy Might ends (it slows him)",
		"spike": "Leap Strike and Tainted Touch up, a Jump Knife", "counter": ["halberd", "spell_shield", "hex_staff"],
		"tip": "ezee leaps on the lowest hp, careful when hurt"},
	"sludge": {"threat": "the hook: Shuriken Hook pulls you out of position, then Chomp eats you for 2.75 seconds",
		"beat": "stand behind your creeps so the hook hits them; ward the fog; a stun or hex breaks Chomp",
		"spike": "level 6 (Chomp) and a Jump Knife", "counter": ["glimmer_cape", "push_staff", "spell_shield"],
		"tip": "stay behind creeps, sludge hooks from the fog"},
	"azrin": {"threat": "fire mage: javelin drags you, Touch of Ember stuns when you cast, Divine Smite bursts hard",
		"beat": "do not cast while her flames are on you; spread out; jump her, she is squishy",
		"spike": "five spirits charged and level 6 Divine Smite", "counter": ["spell_shield", "team_shield", "glimmer_cape"],
		"tip": "dont cast with azrin's flames on you, they stun"},
	"froster": {"threat": "frost mage with a cone slow, an armor curse and Endless Winter that freezes everyone inside",
		"beat": "walk out of Endless Winter fast, it is channelled: stun or silence him to stop it",
		"spike": "level 6 Endless Winter with a Jump Knife", "counter": ["spell_shield", "hex_staff", "silence_staff"],
		"tip": "get out of froster's blizzard before it freezes you"},
	"caziel": {"threat": "invisible assassin: Master of Shadows hides him, Swift Dagger jumps you, Death Order kills anyone low",
		"beat": "buy Reveal Dust or a Reveal Ward; stay together, do not walk alone with low health",
		"spike": "Master of Shadows and a crit or Moth Blade", "counter": ["reveal_dust", "reveal_ward", "halberd"],
		"tip": "caziel goes invisible, buy dust"},
	"tock": {"threat": "clockmaker: Stop Time freezes an area, Time Bolt slows your cooldowns, Rewind saves him",
		"beat": "spread out against Stop Time; burst him twice, Rewind brings him back once",
		"spike": "level 6 Stop Time", "counter": ["spell_shield", "hex_staff"],
		"tip": "spread out, tock's stop time freezes everyone"},
	"kragg": {"threat": "magnet knight: Iron Grip pulls and stuns, Magnet Field drags the whole team in and stuns at the end",
		"beat": "walk out of Magnet Field away from him; do not fight him with many Charges on you",
		"spike": "level 6 Magnet Field and a Jump Knife", "counter": ["spell_shield", "push_staff"],
		"tip": "kragg's magnet field pulls, get out early"},
	"roydo": {"threat": "Grip of the Ruler throws a hero into the middle and stuns; as the Anomaly he attacks from range",
		"beat": "fight him after Anomaly ends; spread so Grip catches one",
		"spike": "Anomaly up", "counter": ["halberd", "spell_shield"], "tip": "dont fight roydo while he is the anomaly"},
	"blau": {"threat": "tactician: bouncing bullet, rolling boulders, hidden traps and a turret",
		"beat": "do not chase him blindly, his traps hold you; kill the turret first",
		"spike": "the turret and Upgrade Staff", "counter": ["jump_knife", "reveal_dust"],
		"tip": "blau leaves traps when he jumps back, dont chase"},
	"azrael": {"threat": "death dealer: Death Scythe pure crits that heal her, flies over cliffs with Divine Darkness",
		"beat": "focus her when Divine Darkness is down; disarm or hex her",
		"spike": "Divine Darkness and attack items", "counter": ["halberd", "hex_staff", "moth_blade"],
		"tip": "azrael flies over cliffs with her ult, watch the flanks"},
	"airah": {"threat": "wind goddess: Hurricane drags and throws the team, Wind Wall blocks ranged attacks",
		"beat": "fight her with melee heroes or walk around the wall; get out of the Hurricane's middle",
		"spike": "level 6 Hurricane", "counter": ["spell_shield", "jump_knife"],
		"tip": "airah's wall blocks ranged attacks, walk around it"},
	"burak": {"threat": "berserker who gets stronger the more he hits; Berserk makes him ignore slows",
		"beat": "do not trade hits with him at full Rage; kite him while Berserk is down; disarm him",
		"spike": "Berserk and Reckless Swing together", "counter": ["halberd", "hex_staff", "spike_armor"],
		"tip": "dont trade with burak at full rage"},
	"emelrich": {"threat": "heavy knight whose Overhead Cut and Giant Swing hit like a truck after a red wind-up",
		"beat": "step out of the red line or cone, he cannot turn it; hit him from behind (Steel Stance only blocks the front)",
		"spike": "level 6 Giant Swing", "counter": ["halberd", "spell_shield"],
		"tip": "move out of emelrich's red cone, it hurts"},
	"feran": {"threat": "jester: Swap trades places to pull you into his team, Shuffle stuns and scrambles everyone",
		"beat": "stay spread out, kill him first, he is fragile", "spike": "level 6 Shuffle",
		"counter": ["spell_shield", "glimmer_cape"], "tip": "feran swaps you into his team, careful"},
	"ghorman": {"threat": "beast king with a pack of tamed creeps and a huge Beast Form",
		"beat": "kill his beasts (he heals when they die, so burst him first) and fight after Beast Form",
		"spike": "five beasts and Beast Form", "counter": ["cleave_axe", "frost_plate", "burning_cape"],
		"tip": "ghorman's pack is strong, focus him not the beasts"},
	"araki": {"threat": "the Blur: Blur Strike dashes through you, ghosts chase you, The Blur halves his cooldowns",
		"beat": "do not let his stacks build (Senryukai); stun him during The Blur",
		"spike": "The Blur and attack items", "counter": ["halberd", "moth_blade", "hex_staff"],
		"tip": "araki's blur strike comes back fast during his ult"},
	"blackfire": {"threat": "unfallen knight: grip stuns him and you and takes 25% of your health; he gets up once after dying and explodes",
		"beat": "do not fight him alone; when he rises after dying, back off until he blows up",
		"spike": "Rise Up in a big fight", "counter": ["sure_hit_staff", "hex_staff"],
		"tip": "blackfire gets up after dying, back off till he explodes"},
	"thyrandael": {"threat": "seraph who gets a barrier every spell; Holy Beam burns and drains mana, False Judgement grows with damage taken",
		"beat": "burst him before he fills his charges; walk out of the beam sideways",
		"spike": "a full False Judgement", "counter": ["spell_shield", "silence_staff"],
		"tip": "dont dump damage on thyrandael, it charges his judgement"},
	"gancho": {"threat": "tree man: roots you with a vine then a seed bomb; Angry Forest makes every tree whip and root you",
		"beat": "never fight him near trees; buy dust, he walks through the forest",
		"spike": "Angry Forest near a forest", "counter": ["spell_shield", "jump_knife"],
		"tip": "dont fight gancho near the trees"},
	"kaileh": {"threat": "lance knight: Lance Charge carries a hero into his team; Cavalry Charge stuns a whole line",
		"beat": "do not stand alone in a line in front of him; kill the War Banner (four hits)",
		"spike": "level 6 Cavalry Charge", "counter": ["spell_shield", "push_staff"],
		"tip": "kaileh's charge carries you into his team, dont stand alone"},
	"dracoxinia": {"threat": "dragon carry: dashes in, throws you in the air with Rising Slash, swaps swords to beat your element",
		"beat": "stun her before she gets her strikes off; she leaps out, so save your disable for after the leap",
		"spike": "five swords open and attack items", "counter": ["halberd", "hex_staff", "frost_plate"],
		"tip": "dracoxinia's every 4th hit is a big strike, careful"},
}

## The rules players talk about, for the online writer (one line each).
const RULES := [
	"A hero kill pays a bounty that grows with the victim's kill streak; ending a streak (a shutdown) pays extra.",
	"Buyback costs 200 + net worth / 13 gold and has an 8 minute cooldown; a team without buyback is weak late.",
	"Fortify (the Glyph) makes every tower and building invulnerable for a few seconds; it has a long cooldown.",
	"Orbs appear in the river every few minutes; the one who takes it gets its power.",
	"At night everyone sees less; heroes with night vision gank better.",
	"High ground hides who stands on it from those below; pushing up a ramp without vision is dangerous.",
	"Stacking a neutral camp (pulling it just before the minute) makes more creeps spawn for the carry to farm.",
	"Denies (killing your own creep or hero) take gold and experience away from the enemy.",
	"Spell immunity stops magic and most disables but not pure damage or attacks; evasion is beaten by a never-miss item.",
	"Stuns and silences stop channelled spells (Chomp, Burst Shot, Endless Winter, Holy Beam).",
	"Town Portal scrolls take 3 seconds; a stun or silence cancels them.",
	"A tower that is losing can be denied by its own team below 10% health; the enemy then gets less gold.",
]

## Whether an item is worth naming in chat (a finished big item or a real counter; never parts, starters or potions).
static func notable(id: String) -> bool:
	if not ITEM_WHY.has(id):
		return false
	return id in TACTICAL or int(SimData.item(id).get("cost", 0)) >= 1900

## The best item worth naming that `h` holds (lower case), or "" when it has none.
static func best_notable(h: SimUnit) -> String:
	var best := ""
	var cost := -1
	for it in h.inventory:
		if it == null or not notable(String(it.id)) or String(it.id) in CONSUMABLE:
			continue
		var c := int(SimData.item(String(it.id)).get("cost", 0))
		if c > cost:
			cost = c
			best = String(SimData.item(String(it.id)).get("name", ""))
	return best.to_lower()

## Every item worth naming that `h` holds (names).
static func notable_items(h: SimUnit) -> Array:
	var out: Array = []
	for it in h.inventory:
		if it != null and notable(String(it.id)) and not (String(it.id) in CONSUMABLE):
			var nm := String(SimData.item(String(it.id)).get("name", ""))
			if nm != "" and not (nm in out):
				out.append(nm)
	return out

## The next items worth naming in a bot's build (its parts and cheap pieces left out).
static func next_notable(w: SimWorld, b) -> Array:
	var out: Array = []
	var h: SimUnit = b.hero()
	for i in range(int(b._build_i), (b.build as Array).size()):
		var id := String(b.build[i])
		if not notable(id) or (h != null and w.shop.owns(h, id)):
			continue
		var nm := String(SimData.item(id).get("name", "")).to_lower()
		if nm != "" and not (nm in out):
			out.append(nm)
		if out.size() >= 2:
			break
	return out

## A counter item against `hero` (lower case name and what it does), or {} when none is known.
static func counter(hero: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var k: Dictionary = HEROES.get(hero, {})
	var opts: Array = k.get("counter", [])
	if opts.is_empty():
		return {}
	var id := String(opts[rng.randi_range(0, opts.size() - 1)] if rng != null else opts[0])
	return {"id": id, "item": String(SimData.item(id).get("name", id)).to_lower(), "why": String(ITEM_WHY.get(id, ""))}

## A short warning about `hero` a player would type, "" when none.
static func tip(hero: String) -> String:
	return String(HEROES.get(hero, {}).get("tip", ""))

## The whole hero sheet in one line (the online writer's system prompt).
static func hero_line(hero: String) -> String:
	var k: Dictionary = HEROES.get(hero, {})
	if k.is_empty():
		return ""
	var items: Array = (k.get("counter", []) as Array).map(func(i): return String(SimData.item(String(i)).get("name", i)))
	return "dangerous: %s; beat it: %s; strong with: %s; answer with: %s" % [k.threat, k.beat, k.spike, ", ".join(items)]

## Every notable item and what it is for (the online writer's system prompt).
static func item_lines() -> Array:
	var out: Array = []
	var ids := ITEM_WHY.keys()
	ids.sort_custom(func(a, b): return int(SimData.item(String(a)).get("cost", 0)) < int(SimData.item(String(b)).get("cost", 0)))
	for id in ids:
		if notable(String(id)):
			out.append("%s (%s)" % [String(SimData.item(String(id)).get("name", id)), String(ITEM_WHY[id])])
	return out

## The match as one player on `team` sees it: both teams' heroes (level, score, the items worth naming, ultimate, dead or
## alive), the towers, the clock and night (the online writer's prompt).
static func digest(w: SimWorld, team: int) -> String:
	var lines: Array = []
	for side in [team, 1 - team]:
		var who: Array = []
		for h in w.heroes:
			if h.team != side:
				continue
			var bits: Array = ["lvl %d" % h.level, "%d/%d/%d" % [h.kills, h.deaths, h.assists]]
			var items := notable_items(h)
			if not items.is_empty():
				bits.append("has " + ", ".join(items))
			var ult := SimBotKits.ultimate(h)
			if ult != "" and h.ability_level_of(ult) > 0:
				var ready := w.abilities.cooldown_left(h, ult) <= 0.0
				if side == team or ready:
					bits.append("ult %s %s" % [String(SimData.ability(ult).get("name", ult)), "ready" if ready else "on cooldown"])
			if not h.alive:
				bits.append("dead %d s" % int(maxf(0.0, h.respawn_at - w.time)))
			who.append("%s (%s)" % [SimTeamAI.hero_label(h), ", ".join(bits)])
		lines.append("%s: %s" % ["Your team" if side == team else "Enemy team", "; ".join(who)])
	var towers := [0, 0]
	for u in w.units:
		if u.alive and u.kind == SimConst.Kind.TOWER:
			towers[u.team] += 1
	lines.append("Towers standing: yours %d, theirs %d. %s." % [towers[team], towers[1 - team],
		"Night" if w.is_night() else "Day"])
	return "\n".join(lines)
