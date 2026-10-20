class_name ChatMind
extends RefCounted
## What players say about what is really happening (run 2026-10-19 d; the owner: "make sure they really know what they
## are playing, the gameplay, mechanics, their hero ... missed shots, kills, revenge"). The line library of
## BotChatLines (the owner's lines and the 2026-10-18 h set) holds the general trash talk; these lines carry the facts
## of the moment: who killed whom and how often, the ability that did it, the ultimate the enemy just used, the item
## that just finished, the net worth gap, the seconds until a respawn, the player's own score, the bot's rank and
## home town, and what happened the last time the bot met you. SimBotChat picks the situation and fills the names;
## ChatStyle types it in the bot's own way.
##
## Each situation is a list of [text, "en" | "tl"]. Fields: {victim} {killer} {ally} {hero} {skill} {item} {item2} {n}
## {lane} {lane2} {sec} {pct} {min} {rank} {mmr} {city} {country} {kda} {lh} {me_hero} {name} {core} {bld} {why}
## {doing} {laugh} (the speaker's own laugh). A line whose fields are not all known is skipped.

const T := {
	# ---- kills, all chat ----------------------------------------------------------------------------------------------
	"revenge": [["revenge", "en"], ["payback {victim}", "en"], ["remember me {victim}?", "en"], ["thats for earlier", "en"],
		["who's laughing now {victim}", "en"], ["told u i'd get u back", "en"], ["u thought {laugh}", "en"],
		["now we're even {victim}", "en"], ["karma {victim}", "en"], ["missed me?", "en"], ["1-1 {victim}", "en"],
		["not so funny now huh", "en"], ["bawi", "tl"], ["bawi ako {victim}", "tl"], ["ganti lang {victim}", "tl"],
		["akala mo ha", "tl"], ["o ano ngayon {victim}", "tl"], ["quits na tayo {victim}", "tl"],
		["balik sayo {victim}", "tl"], ["sino tumatawa ngayon", "tl"], ["kala mo makakalimutan ko", "tl"],
		["bayad utang {victim}", "tl"]],
	"revenge_reply": [["lucky", "en"], ["enjoy it", "en"], ["u needed help for that", "en"], ["ok we even", "en"],
		["took u long enough", "en"], ["still ahead {laugh}", "en"], ["swerte mo lang", "tl"], ["isa isa lang", "tl"],
		["sige enjoy mo", "tl"], ["tinulungan ka pa ha", "tl"]],
	"rival": [["{n} times {victim} {laugh}", "en"], ["{victim} again?", "en"], ["my favorite {victim}", "en"],
		["{n}-0 {victim}", "en"], ["stop coming to me {victim}", "en"], ["free {victim} again", "en"],
		["{victim} ur my farm now", "en"], ["{victim} pls stay in lane i need gold", "en"], ["{n}th time lol", "en"],
		["{victim} why do u keep coming", "en"], ["{n} na {victim} {laugh}", "tl"], ["suki kita {victim}", "tl"],
		["ikaw na naman {victim}", "tl"], ["alaga kita {victim}", "tl"], ["{victim} paborito kita", "tl"],
		["{victim} ATM ko", "tl"], ["{n} beses na {victim}", "tl"]],
	"rival_reply": [["stop focusing me", "en"], ["why always me", "en"], ["ok u win", "en"], ["pick someone else", "en"],
		["u only kill me {laugh}", "en"], ["obsessed", "en"], ["bakit ako na naman", "tl"], ["ako na lang lagi", "tl"],
		["tama na po", "tl"], ["crush mo ba ako", "tl"], ["hanap ka iba", "tl"]],
	"double": [["double", "en"], ["2 for 1", "en"], ["double kill", "en"], ["two down", "en"], ["2 {laugh}", "en"],
		["dalawa agad", "tl"], ["doble", "tl"], ["dalawa isang bagsakan", "tl"]],
	"multi": [["{n} kills {laugh}", "en"], ["triple", "en"], ["who's next", "en"], ["{n} down", "en"],
		["{n} for 0", "en"], ["{n} agad", "tl"], ["sunod sunod", "tl"], ["isa pa", "tl"], ["sino pa", "tl"]],
	"skill_kill": [["{skill} diff", "en"], ["one {skill} gone", "en"], ["{skill} ez", "en"], ["felt that {skill}?", "en"],
		["{skill} too good", "en"], ["perfect {skill}", "en"], ["thats why u dodge {skill}", "en"],
		["isang {skill} lang", "tl"], ["{skill} lang katapat mo", "tl"], ["sarap ng {skill}", "tl"]],
	"skill_death": [["{skill} so broken", "en"], ["how is {skill} that strong", "en"], ["nerf {skill}", "en"],
		["{hero} {skill} is stupid", "en"], ["who balanced {skill}", "en"], ["that {skill} hurt", "en"],
		["grabe {skill}", "tl"], ["daya ng {skill}", "tl"], ["ang sakit ng {skill}", "tl"], ["{skill} na naman", "tl"]],
	"stun_death": [["cant even move", "en"], ["stunned the whole time", "en"], ["perma stun", "en"],
		["how do i play when im stunned", "en"], ["chain stun gg", "en"], ["0 buttons pressed", "en"],
		["di ako makagalaw", "tl"], ["stun lang alam niyo", "tl"], ["stun lock amp", "tl"], ["parang estatwa ako", "tl"]],
	"ks": [["ks", "en"], ["nice ks", "en"], ["ks {killer}", "en"], ["thanks for the ks", "en"], ["my kill bro", "en"],
		["stop stealing", "en"], ["ks again?", "en"], ["i did all the damage", "en"], ["{killer} the thief", "en"],
		["ks pa", "tl"], ["akin yun", "tl"], ["salamat sa ks ha", "tl"], ["ks master {killer}", "tl"],
		["ako pumalo ikaw kumuha", "tl"]],
	"ks_sorry": [["sorry", "en"], ["mb", "en"], ["my bad", "en"], ["sorry ks", "en"], ["it was gonna run", "en"],
		["oops", "en"], ["sorry po", "tl"], ["di sinasadya", "tl"], ["tatakas na kasi", "tl"]],
	"ks_proud": [["should've killed faster", "en"], ["too slow", "en"], ["gold is gold", "en"],
		["last hit is a skill", "en"], ["bagal mo kasi", "tl"], ["bilisan mo kasi", "tl"]],
	"ks_player": [["nice ks {name} {laugh}", "en"], ["ty for the ks {name}", "en"], ["{name} took my kill", "en"],
		["ks {name}", "en"], ["ks ni {name} {laugh}", "tl"], ["akin sana yun {name}", "tl"]],
	"ks_to_player": [["sorry {name}", "en"], ["mb {name} it was running", "en"], ["oops sorry", "en"],
		["sorry {name} tatakas na eh", "tl"]],
	"player_kill": [["nice {name}", "en"], ["gj {name}", "en"], ["nice one", "en"], ["clean", "en"], ["{name} diff", "en"],
		["galing {name}", "tl"], ["lodi {name}", "tl"], ["ayos {name}", "tl"], ["solid", "tl"]],
	"escape": [["1 hp {laugh}", "en"], ["SO CLOSE", "en"], ["how am i alive", "en"], ["almost", "en"], ["not today", "en"],
		["1 hp but alive", "en"], ["cant catch me", "en"], ["muntik na", "tl"], ["1 hp na lang", "tl"],
		["buhay pa", "tl"], ["kaba ko dun", "tl"], ["di pa oras ko", "tl"], ["hingal", "tl"]],
	"escape_enemy": [["how did he live", "en"], ["1 hp...", "en"], ["so lucky", "en"], ["next time", "en"],
		["run {victim} run", "en"], ["ang swerte", "tl"], ["isa na lang sana", "tl"], ["takbo {victim}", "tl"]],
	"tower_dive": [["worth", "en"], ["tower aggro sucks", "en"], ["too greedy", "en"], ["was worth it", "en"],
		["sulit naman", "tl"], ["takaw ko", "tl"], ["tower pala", "tl"]],
	"wipe": [["wipe", "en"], ["team wipe {laugh}", "en"], ["{n} for {n2}", "en"], ["ace", "en"], ["gg?", "en"],
		["clean sweep", "en"], ["ubos", "tl"], ["lahat patay", "tl"], ["walang natira", "tl"], ["linis", "tl"]],
	"wiped": [["what was that", "en"], ["who started that", "en"], ["why we fight there", "en"], ["we got wiped", "en"],
		["5 dead lol", "en"], ["anong nangyari", "tl"], ["sino nag go", "tl"], ["bakit tayo lumaban dun", "tl"],
		["ubos tayo", "tl"]],
	"miss_named": [["nice {skill} {laugh}", "en"], ["{skill} missed lol", "en"], ["aim {hero} aim", "en"],
		["dodged ur {skill}", "en"], ["u missed {skill} again?", "en"], ["{skill} into nothing", "en"],
		["who taught u {skill}", "en"], ["sablay {skill}", "tl"], ["mintis {skill} {laugh}", "tl"],
		["asan tama {skill} mo", "tl"], ["ilag lang {skill}", "tl"]],
	"miss_team": [["nice {skill} lol", "en"], ["how did {skill} miss", "en"], ["hit ur {skill} pls", "en"],
		["{skill} at the trees", "en"], ["sayang {skill}", "tl"], ["tamaan mo naman {skill}", "tl"]],
	"miss_self": [["how did that miss", "en"], ["ugh missed", "en"], ["my {skill}...", "en"], ["lag", "en"],
		["anlapit na eh", "tl"], ["sayang", "tl"], ["kainis sablay", "tl"]],
	# ---- the game, team chat --------------------------------------------------------------------------------------------
	"enemy_ult": [["{hero} used {skill}, go", "en"], ["{hero} no ult", "en"], ["{hero} ult down, fight now", "en"],
		["{skill} on cd", "en"], ["they used {skill}, push", "en"], ["{hero} wasted ult", "en"],
		["no {skill} for a while, go", "en"], ["wala na {skill} ni {hero}", "tl"], ["gamit na ult ni {hero}, laban", "tl"],
		["tara wala na ult", "tl"], ["cd {skill} ni {hero}", "tl"]],
	"ult_ready": [["ult ready", "en"], ["i have ult", "en"], ["6, gank?", "en"], ["{skill} ready", "en"],
		["ult up lets fight", "en"], ["{skill} up, need a target", "en"], ["may ult na ako", "tl"],
		["6 na, gank tayo", "tl"], ["ready na {skill}", "tl"]],
	"item_done": [["{item} done", "en"], ["got {item}", "en"], ["{item} up", "en"], ["finally {item}", "en"],
		["{item}, lets fight", "en"], ["{item} done, i can fight now", "en"], ["may {item} na ako", "tl"],
		["tapos na {item}", "tl"], ["{item} na, tara", "tl"]],
	"knife_done": [["knife ready, ill start", "en"], ["jump knife up, i go first", "en"], ["i can jump in now", "en"],
		["may knife na, ako mauuna", "tl"]],
	"shield_done": [["spell shield up, i can go in", "en"], ["shield ready", "en"], ["may shield na ko, sugod", "tl"]],
	"nw_up": [["we're {n}k up, push", "en"], ["{n}k ahead, group and push", "en"], ["we're winning, dont throw", "en"],
		["dont throw guys {n}k up", "en"], ["group and take towers", "en"], ["lamang tayo {n}k, push na", "tl"],
		["wag kayo mag throw", "tl"], ["{n}k lamang, tara tower", "tl"], ["lamang tayo, wag pabaya", "tl"]],
	"nw_down": [["they're {n}k up, play safe", "en"], ["farm up, they're ahead", "en"], ["dont fight 5v5 now", "en"],
		["we need farm", "en"], ["{n}k behind, def high ground", "en"], ["stop dying pls", "en"],
		["lamang sila {n}k, farm muna", "tl"], ["wag muna laban", "tl"], ["ingat lamang sila", "tl"],
		["depensa lang muna", "tl"]],
	"comeback": [["we're back in it", "en"], ["comeback is real", "en"], ["never give up", "en"], ["they're throwing", "en"],
		["bumabalik tayo", "tl"], ["kaya pa", "tl"], ["sabi ko sa inyo kaya pa", "tl"]],
	"fed_enemy": [["{hero} is fed, careful", "en"], ["focus {hero}, he has {item}", "en"], ["{hero} {n} kills already", "en"],
		["stop feeding {hero}", "en"], ["{hero} needs to die", "en"], ["fed na si {hero}", "tl"], ["ingat kay {hero}", "tl"],
		["{hero} na naman pumatay", "tl"]],
	"enemy_dead_push": [["{hero} dead {sec}s, push", "en"], ["their {hero} is dead, go", "en"], ["{hero} {sec}s, tower now", "en"],
		["patay si {hero} {sec}s, tara", "tl"], ["wala si {hero}, push na", "tl"]],
	# ---- moods ----------------------------------------------------------------------------------------------------------
	"give_up": [["im done", "en"], ["gg", "en"], ["afk", "en"], ["this team", "en"], ["why do i even try", "en"],
		["ff", "en"], ["unlucky game", "en"], ["just end it", "en"], ["ayoko na", "tl"], ["talo na to", "tl"],
		["suko na ako", "tl"], ["bahala kayo", "tl"], ["tapusin na natin", "tl"]],
	"encourage": [["its ok we can still win", "en"], ["farm up, late game ours", "en"], ["dont give up", "en"],
		["they will throw", "en"], ["one good fight", "en"], ["we scale better", "en"], ["just defend and farm", "en"],
		["kaya pa yan", "tl"], ["wag susuko", "tl"], ["late game tayo", "tl"], ["chill lang, kaya pa", "tl"],
		["isang laban lang", "tl"]],
	"brag": [["too easy", "en"], ["1v9 time", "en"], ["watch and learn", "en"], ["carry incoming", "en"],
		["who's gonna stop me", "en"], ["im just better", "en"], ["ako bahala", "tl"], ["sakay lang kayo", "tl"],
		["dalhin ko kayo", "tl"], ["relax lang kayo, ako na", "tl"]],
	"own_death_tilt": [["WHY", "en"], ["this game", "en"], ["unreal", "en"], ["no help again", "en"], ["ofc", "en"],
		["every time", "en"], ["BAKIT", "tl"], ["tangina", "tl"], ["wala na naman tulong", "tl"], ["lagi na lang", "tl"]],
	# ---- memories of the player ------------------------------------------------------------------------------------------
	"meet_friend": [["{name}!!", "en"], ["yo {name}", "en"], ["{name} lets go", "en"], ["my duo {name}", "en"],
		["{name} carry me again", "en"], ["uy {name}!", "tl"], ["tropa {name}", "tl"], ["tara {name}", "tl"]],
	"meet_won_with": [["{name} again, we won last time", "en"], ["u again {name}, carry me again", "en"],
		["lucky team, {name} is here", "en"], ["{name}! same as last game pls", "en"],
		["uy {name}, panalo tayo last time ah", "tl"], ["{name} ulitin natin last game", "tl"]],
	"meet_lost_with": [["{name}... we lost last time", "en"], ["pls dont feed this time {name}", "en"],
		["redemption game {name}", "en"], ["{name} lets win this one", "en"], ["{name} bawi tayo", "tl"],
		["{name} talo tayo last time, ayusin natin", "tl"]],
	"meet_lost_vs": [["{name}, revenge time", "en"], ["i remember u {name}", "en"], ["u got lucky last time {name}", "en"],
		["{name} again, not losing twice", "en"], ["{name}! bawi ako ngayon", "tl"], ["naalala kita {name}", "tl"],
		["{name} di na ako papayag", "tl"]],
	"meet_won_vs": [["{name} again {laugh}", "en"], ["{name} ready to lose again?", "en"], ["my favorite customer {name}", "en"],
		["{name} u again lol", "en"], ["ikaw na naman {name}", "tl"], ["talo ka na naman {name}", "tl"],
		["{name} suki", "tl"]],
	"meet_flamer": [["oh its the flamer", "en"], ["{name} pls no flame this time", "en"], ["its {name}, mute ready", "en"],
		["si {name} yung toxic", "tl"], ["wag ka na mag flame {name}", "tl"]],
	"meet_killer": [["{name} killed me {n} times last game", "en"], ["{name} stay away from me", "en"],
		["{name} pinatay mo ko {n} beses ah", "tl"]],
	"end_like": [["+rep {name}", "en"], ["gg {name} add me", "en"], ["{name} carried", "en"], ["nice game {name}", "en"],
		["gg wp {name}", "en"], ["{name} play again?", "en"], ["salamat {name}", "tl"], ["add kita {name}", "tl"],
		["gg {name} lodi", "tl"], ["{name} laro ulit tayo", "tl"]],
	"end_dislike": [["{name} uninstall", "en"], ["report {name}", "en"], ["never again with {name}", "en"],
		["{name} is the reason", "en"], ["report si {name}", "tl"], ["sana di na kita kakampi {name}", "tl"]],
	"end_respect": [["gg {name}, u were good", "en"], ["wp {name}", "en"], ["{name} too strong", "en"],
		["galing mo {name}", "tl"], ["gg {name} lakas mo", "tl"]],
	# ---- answers to the player -------------------------------------------------------------------------------------------
	"r_greet": [["hi", "en"], ["hello", "en"], ["yo", "en"], ["hey", "en"], ["glhf", "en"], ["gl hf", "en"],
		["hi {name}", "en"], ["sup", "en"], ["hey {name}", "en"], ["musta", "tl"], ["uy", "tl"], ["hello po", "tl"],
		["glhf mga lods", "tl"], ["uy {name}", "tl"]],
	"r_rank": [["{rank}", "en"], ["im {rank}", "en"], ["{rank} lol", "en"], ["{mmr} mmr", "en"], ["{rank}, u?", "en"],
		["{rank} ako", "tl"], ["{rank} lang po", "tl"], ["{mmr} mmr ko", "tl"]],
	"r_rank_none": [["dont play ranked", "en"], ["just casual", "en"], ["no rank lol", "en"], ["casual lang ako", "tl"]],
	"r_from": [["{city}", "en"], ["from {city}", "en"], ["{country}", "en"], ["{city}, u?", "en"], ["taga {city}", "tl"],
		["{city} lods", "tl"], ["{city} po", "tl"]],
	"r_where_seen": [["{hero} {lane} {sec}s ago", "en"], ["{hero} was {lane}", "en"], ["saw {hero} {lane}", "en"],
		["{hero} {lane}", "en"], ["{hero} {lane} a moment ago", "en"], ["nasa {lane} si {hero} kanina", "tl"],
		["{hero} {lane} kanina", "tl"]],
	"r_where_lost": [["no idea", "en"], ["{hero} missing since {min} min", "en"], ["idk, been missing", "en"],
		["no vision", "en"], ["havent seen {hero}", "en"], ["di ko alam", "tl"], ["nawawala si {hero}", "tl"],
		["walang ward kaya di ko alam", "tl"]],
	"r_item": [["{item} next", "en"], ["going {item}", "en"], ["{item} then {item2}", "en"], ["saving for {item}", "en"],
		["{item} sunod", "tl"], ["ipon para {item}", "tl"]],
	"r_why_dead": [["i was dead", "en"], ["i was dead bro", "en"], ["dead, couldnt", "en"], ["patay ako nun", "tl"]],
	"r_why_far": [["too far", "en"], ["i was {doing}", "en"], ["no tp", "en"], ["u dove alone", "en"],
		["u didnt ping", "en"], ["was {doing}, sorry", "en"], ["malayo ako", "tl"], ["wala akong tp", "tl"],
		["di ka nag ping", "tl"], ["nag {doing} ako", "tl"]],
	"r_insult_fact": [["says the {kda} {me_hero}", "en"], ["{kda} and talking?", "en"], ["look at ur score first", "en"],
		["{lh} cs at {min} min btw", "en"], ["{kda} lol", "en"], ["{kda} ka tapos ganyan ka", "tl"],
		["tingnan mo score mo", "tl"], ["{lh} cs ka lang", "tl"]],
	"r_praise": [["ty", "en"], ["thanks", "en"], ["ty {name}", "en"], ["ez", "en"], ["thx", "en"], ["i know", "en"],
		["salamat", "tl"], ["salamat lods", "tl"], ["thank u po", "tl"]],
	"r_thanks": [["np", "en"], ["welcome", "en"], ["anytime", "en"], ["np {name}", "en"], ["walang anuman", "tl"],
		["sige lang", "tl"]],
	"r_sorry_kind": [["np", "en"], ["its ok", "en"], ["all good", "en"], ["dont worry", "en"], ["happens", "en"],
		["okay lang", "tl"], ["goods lang", "tl"], ["sige lang", "tl"]],
	"r_sorry_rude": [["sorry doesnt give mmr", "en"], ["just play better", "en"], ["uninstall", "en"], ["sure", "en"],
		["sorry ka diyan", "tl"], ["ayusin mo kasi", "tl"]],
	"r_gg_early": [["gg already? {laugh}", "en"], ["too early", "en"], ["its not over", "en"], ["maaga pa", "tl"],
		["di pa tapos", "tl"]],
	"r_ff_no": [["no ff, we can win", "en"], ["dont give up", "en"], ["they will throw", "en"], ["wag ff", "tl"],
		["kaya pa yan", "tl"]],
	"r_ff_yes": [["yes ff", "en"], ["ff this team", "en"], ["agree", "en"], ["sige ff", "tl"], ["tapusin na", "tl"]],
	"r_bot": [["im not a bot", "en"], ["{laugh} im real", "en"], ["beep boop", "en"], ["u are the bot", "en"],
		["yes im a bot, beep", "en"], ["hindi ako bot", "tl"], ["tao ako uy", "tl"], ["ikaw bot", "tl"]],
	"r_report": [["report who", "en"], ["dont report me", "en"], ["report {ally}", "en"], ["sino ireport", "tl"],
		["wag ako", "tl"]],
	"r_lag": [["lag here too", "en"], ["my ping is {n}", "en"], ["smooth for me", "en"], ["lag din ako", "tl"],
		["{n} ping ko", "tl"]],
	"r_laugh": [["{laugh}", "en"], ["lol", "en"], ["xd", "en"]],
	"r_huh": [["?", "en"], ["what", "en"], ["??", "en"], ["huh", "en"], ["ano", "tl"], ["bakit", "tl"], ["ano yun", "tl"]],
	"r_ok": [["ok", "en"], ["k", "en"], ["true", "en"], ["yeah", "en"], ["sure", "en"], ["sige", "tl"], ["oo nga", "tl"]],
	"r_name": [["what", "en"], ["yes?", "en"], ["huh", "en"], ["?", "en"], ["bakit", "tl"], ["ano yun", "tl"], ["oy", "tl"]],
	# ---- bot to bot ---------------------------------------------------------------------------------------------------
	"t_sorry": [["sorry", "en"], ["my bad", "en"], ["ok ok", "en"], ["mb", "en"], ["sorry guys", "en"], ["sorry na", "tl"],
		["pasensya", "tl"], ["ok na ok na", "tl"]],
	"t_argue": [["u died more", "en"], ["look at ur score", "en"], ["says the {kda}", "en"], ["at least i tried", "en"],
		["u didnt help", "en"], ["talk less play more", "en"], ["ikaw nga {kda}", "tl"], ["tingnan mo sarili mo", "tl"],
		["kala mo naman", "tl"], ["ikaw kaya", "tl"]],
	"t_calm": [["stop fighting", "en"], ["focus guys", "en"], ["just play", "en"], ["chill, we can win", "en"],
		["mute and play", "en"], ["tama na away", "tl"], ["laro na lang", "tl"], ["focus tayo", "tl"]],
}

## Team calls (SimTeamAI and SimBot) the way players type them: the same facts, a few words.
const CALLS := {
	"lane_mid": [["mid", "en"], ["i'll mid", "en"], ["mid pls", "en"], ["im mid", "en"], ["mid", "en"], ["ako mid", "tl"],
		["mid ako", "tl"], ["akin mid", "tl"]],
	"lane_safe": [["safe", "en"], ["safe lane", "en"], ["carry {lane}", "en"], ["i'll farm {lane}", "en"],
		["ako safe", "tl"], ["safe lane ako", "tl"]],
	"lane_off": [["off", "en"], ["offlane", "en"], ["i'll go {lane}", "en"], ["{lane}", "en"], ["ako off", "tl"],
		["off lane ako", "tl"]],
	"lane_sup": [["support", "en"], ["i'll sup {core}", "en"], ["sup {lane}", "en"], ["support {core}", "en"],
		["ako support", "tl"], ["support ako kay {core}", "tl"]],
	"lane_swap": [["ok u {lane}, i'll go {lane2}", "en"], ["fine, {lane2}", "en"], ["ok {lane2} then", "en"],
		["u {lane}? ok {lane2}", "en"], ["sige ikaw {lane}, ako {lane2}", "tl"], ["ok {lane2} na lang ako", "tl"]],
	"lane_sup_you": [["i'll sup u", "en"], ["support u {lane}", "en"], ["sup ka namin", "tl"]],
	"lane_fill": [["i'll go {lane2} then", "en"], ["ok {lane2}", "en"], ["ako na lang {lane2}", "tl"]],
	"def": [["{lane} needs def", "en"], ["help {lane} tower", "en"], ["{lane} being pushed", "en"], ["def {lane} guys", "en"], ["sino mag def {lane}", "tl"], ["tulong {lane} tower", "tl"], ["def {lane}", "en"], ["{lane} tower", "en"], ["defend {lane}", "en"], ["they're hitting {lane}", "en"],
		["def {lane} pls", "en"], ["{lane} {bld}!", "en"], ["depensa {lane}", "tl"], ["tara {lane} tower", "tl"]],
	"def_go": [["on the way", "en"], ["{sec}s", "en"], ["ill def", "en"], ["ako na sa {lane}", "tl"], ["otw {lane}", "en"], ["coming {sec}s", "en"], ["omw", "en"], ["tp {lane}", "en"], ["coming", "en"], ["papunta na", "tl"],
		["tp ako", "tl"]],
	"def_tp": [["tp def", "en"], ["tping {lane}", "en"], ["tp na ako {lane}", "tl"], ["tp", "en"], ["tping", "en"], ["tp {lane}", "en"], ["tp na", "tl"]],
	"gank": [["{hero} {lane} no escape", "en"], ["{hero} low, {lane}", "en"], ["easy kill {hero} {lane}", "en"], ["go {hero}", "en"], ["si {hero} sa {lane}, tara", "tl"], ["libre si {hero} {lane}", "tl"], ["gank {hero} {lane}", "en"], ["{hero} {lane}, kill", "en"], ["{hero} alone {lane}", "en"],
		["lets kill {hero}", "en"], ["{hero} {lane} go", "en"], ["tara {hero} {lane}", "tl"],
		["patayin natin si {hero}", "tl"], ["mag isa si {hero} sa {lane}", "tl"]],
	"gank_go": [["coming", "en"], ["right behind u", "en"], ["wait for me", "en"], ["sunod ako", "tl"], ["ge", "tl"], ["omw", "en"], ["coming", "en"], ["otw", "en"], ["ok", "en"], ["papunta", "tl"], ["tara", "tl"]],
	"gank_tp": [["tp in", "en"], ["tp sa kanila", "tl"], ["tp", "en"], ["tping", "en"], ["tp na", "tl"]],
	"save": [["dont die {ally}", "en"], ["run {ally} im here", "en"], ["{ally} come this way", "en"], ["almost there", "en"], ["andito na ako {ally}", "tl"], ["wag ka mamatay {ally}", "tl"], ["hold {ally}", "en"], ["coming {ally}", "en"], ["hang on", "en"], ["wait coming", "en"], ["run to me", "en"],
		["kapit {ally}", "tl"], ["papunta na {ally}", "tl"], ["takbo dito {ally}", "tl"]],
	"save_tp": [["tp to u {ally}", "en"], ["tp {ally} hold on", "en"], ["tp ako sayo {ally}", "tl"], ["tp {ally}", "en"], ["tping to u", "en"], ["tp na {ally}", "tl"]],
	"save_run": [["they are diving me", "en"], ["need help here", "en"], ["2 on me", "en"], ["saklolo", "tl"], ["hinahabol ako", "tl"], ["help", "en"], ["help me", "en"], ["they're on me", "en"], ["help pls", "en"], ["tulong", "tl"],
		["tulungan niyo ko", "tl"], ["habol ako", "tl"]],
	"teamfight": [["all in", "en"], ["{hero} first", "en"], ["burst {hero}", "en"], ["sugod", "tl"], ["patayin si {hero}", "tl"], ["fight", "en"], ["go go", "en"], ["focus {hero}", "en"], ["kill {hero} first", "en"], ["now", "en"],
		["go", "en"], ["laban", "tl"], ["tara na", "tl"], ["si {hero} una", "tl"]],
	"push": [["take {lane} {bld}", "en"], ["{lane} now", "en"], ["hit {lane} {bld}", "en"], ["{lane} {bld} tara", "tl"], ["push {lane}", "en"], ["group {lane}", "en"], ["lets push {lane}", "en"], ["{lane} tower now", "en"],
		["{why}, push {lane}", "en"], ["tara {lane}", "tl"], ["push {lane} na", "tl"]],
	"push_on": [["keep going", "en"], ["{bld} next", "en"], ["go {bld}", "en"], ["tuloy", "tl"], ["{bld} na", "tl"]],
	"miss": [["no {hero}", "en"], ["where is {hero}", "en"], ["{hero} gone from {lane}", "en"], ["{hero} not visible", "en"], ["wala si {hero} sa {lane}", "tl"], ["asan si {hero}", "tl"], ["{hero} ss", "en"], ["{hero} mia", "en"], ["ss {hero}", "en"], ["{hero} missing", "en"],
		["careful {hero} missing", "en"], ["{hero} not {lane}", "en"], ["nawala si {hero}", "tl"],
		["ingat wala si {hero}", "tl"]],
	"danger": [["they are grouped", "en"], ["dont fight", "en"], ["{n} of them", "en"], ["takbo", "tl"], ["umatras kayo", "tl"], ["b", "en"], ["back", "en"], ["b b b", "en"], ["{n} there careful", "en"], ["dont go {lane}", "en"],
		["atras", "tl"], ["balik", "tl"], ["{n} sila dun", "tl"]],
	"ok_back": [["ok", "en"], ["k", "en"], ["backing", "en"], ["sige", "tl"]],
	"abort": [["nvm", "en"], ["nope", "en"], ["too risky", "en"], ["wag na", "tl"]],
	"juke": [["he got away", "en"], ["trees juke", "en"], ["lost", "en"], ["nakatakas sa puno", "tl"], ["lost him", "en"], ["he juked me", "en"], ["nvm lost him", "en"], ["nawala", "tl"], ["nakatakas", "tl"]],
	"heal": [["back to base", "en"], ["need regen", "en"], ["base", "en"], ["uwi muna ako", "tl"], ["b", "en"], ["going base", "en"], ["heal", "en"], ["uwi muna", "tl"], ["heal muna ako", "tl"]],
	"go": [["{hero}", "en"], ["going {hero}", "en"], ["{hero} mine", "en"], ["kill {hero}", "en"], ["si {hero}", "tl"]],
	"bb": [["bb", "en"], ["buying back", "en"], ["bb def", "en"], ["bb ako", "tl"]],
	"stack": [["stacked for u {core}", "en"], ["stack ready {core}", "en"], ["naka stack {core}", "tl"]],
	"six": [["6", "en"], ["6 gank?", "en"], ["ult up", "en"], ["6 na", "tl"], ["may ult na", "tl"]],
	"item": [["{item} ready", "en"], ["{item} finally", "en"], ["{item} done lets go", "en"], ["{item} na ako", "tl"], ["{item} done", "en"], ["got {item}", "en"], ["{item} up", "en"], ["may {item} na", "tl"]],
	"dust_buy": [["got dust", "en"], ["dust bought, they have invis", "en"], ["may dust ako", "tl"]],
	"counter": [["{item} for {why}", "en"], ["need {item}, {why}", "en"], ["bili ako {item}", "tl"], ["getting {item} vs {why}", "en"], ["{item} vs {why}", "en"], ["{item} para sa {why}", "tl"]],
	"fade_cape": [["{ally} run!", "en"], ["cape on u {ally}, run", "en"], ["takbo {ally}!", "tl"]],
	"dust_use": [["dusting {hero}", "en"], ["dust", "en"], ["dust kay {hero}", "tl"]],
	"nogank": [["no one to gank", "en"], ["nobody visible", "en"], ["walang makita", "tl"]],
	# ping replies
	"p_dead": [["dead {sec}s", "en"], ["im dead {sec}", "en"], ["{sec}s", "en"], ["dead, {sec}s", "en"],
		["patay pa ako {sec}s", "tl"], ["{sec}s pa", "tl"]],
	"p_low": [["low hp", "en"], ["{pct}% hp", "en"], ["need heal", "en"], ["no hp", "en"], ["lowbat ako", "tl"],
		["wala na hp ko", "tl"]],
	"p_defending": [["defending {lane}", "en"], ["im {lane} tower", "en"], ["nasa {lane} ako", "tl"]],
	"p_no_tp": [["no tp, too far", "en"], ["no tp", "en"], ["too far, no tp", "en"], ["wala tp, layo", "tl"]],
	"p_tp_cd": [["tp cd {sec}s", "en"], ["tp on cd", "en"], ["no tp {sec}s", "en"], ["cd tp ko {sec}s", "tl"]],
	"p_no_mana_tp": [["no mana for tp", "en"], ["oom", "en"], ["wala mana", "tl"]],
	"p_far": [["too far {sec}s", "en"], ["too far", "en"], ["ang layo", "tl"]],
	"p_risky": [["{n} there, no", "en"], ["too many", "en"], ["{n} heroes there", "en"], ["{n} sila, wag", "tl"]],
	"p_oom": [["oom", "en"], ["no mana", "en"], ["wala mana", "tl"]],
	"p_ult_cd": [["ult cd {sec}", "en"], ["no ult {sec}s", "en"], ["wait ult", "en"], ["cd ult {sec}s", "tl"]],
	"p_more_up": [["they have more up", "en"], ["they're all alive", "en"], ["not now", "en"], ["kumpleto sila", "tl"]],
	"p_farm": [["farming", "en"], ["after this wave", "en"], ["need farm", "en"], ["later", "en"], ["farm muna", "tl"],
		["mamaya", "tl"]],
	"p_timing": [["not now", "en"], ["later", "en"], ["mamaya na", "tl"]],
	"p_tp": [["tp now", "en"], ["tping there", "en"], ["sige tp", "tl"], ["tp", "en"], ["tping", "en"], ["tp coming", "en"], ["tp na", "tl"]],
	"p_push": [["ok {lane}", "en"], ["omw {lane}", "en"], ["coming {sec}s", "en"], ["sige {lane}", "tl"]],
	"p_def": [["coming", "en"], ["omw def", "en"], ["{sec}s", "en"], ["papunta", "tl"]],
	"p_omw": [["on the way", "en"], ["{sec}s away", "en"], ["papunta {sec}s", "tl"], ["omw", "en"], ["otw", "en"], ["coming {sec}s", "en"], ["papunta na", "tl"]],
	"p_enough": [["enough going, im staying", "en"], ["u guys go", "en"], ["kayo na", "tl"]],
}

## Cities by country for "where are you from" (players answer with a city more often than a country).
const CITIES := {"PH": ["manila", "cebu", "davao", "qc", "laguna", "cavite", "pampanga", "iloilo", "bacolod", "baguio",
	"bulacan", "taguig", "makati", "cdo", "batangas"], "ID": ["jakarta", "bandung", "surabaya"], "MY": ["kl", "penang", "johor"],
	"TH": ["bangkok", "chiang mai"], "VN": ["hanoi", "saigon"], "SG": ["sg"], "PE": ["lima", "peru"], "BR": ["sao paulo", "rio", "br"],
	"RU": ["moscow", "russia"], "UA": ["kyiv", "ukraine"], "US": ["texas", "cali", "ny", "us"], "DE": ["berlin", "germany"],
	"SE": ["stockholm", "sweden"], "CN": ["shanghai", "china"], "KR": ["seoul", "korea"], "AU": ["sydney", "melbourne", "aus"]}

## Words that mark a line as rude (a flame at someone).
const RUDE := ["noob", "trash", "report", "stfu", "bobo", "tanga", "gago", "ulol", "pota", "tangina", "weak", "feed",
	"feeder", "loser", "uninstall", "idiot", "stupid", "dumb", "useless", "bano", "inutil", "putang", "bulok", "kupal",
	"engot", "ampota", "shut up", "wtf", "worst", "garbage", "pathetic", "dogshit", "fck", "fuck",
	# run 2026-10-20 (the owner's own trash talk went unanswered): no word here may hide inside an ordinary word
	"ur mom", "your mom", "ur mother", "yo mama", "suck", "clown", "bozo", "braindead", "brain dead", "crybaby", "boosted",
	"hardstuck", "hard stuck", "low iq", "scrub", "potato", "tarantado", "ungas", "bwisit", "pakyu", "putangina", "baho",
	"panget", "pangit", "shit", "bitch", "asshole", "moron", "jerk", "kingina", "leche", "peste", "walang kwenta"]
## Words of trash talk ("ez", "sit", "too easy", "1v9"): the enemy answers (ChatSocial.trash_talk).
const TAUNT := ["ez", "ezz", "ezzz", "ezzzz", "eazy", "too easy", "gg ez", "ggez", "sit", "sit down", "rekt", "get rekt",
	"1v9", "1v5", "outplayed", "cry", "cope", "so bad", "too bad", "bye bye", "byebye", "noobs", "trash team", "free win",
	"no match", "walang laban", "dali", "ang dali", "hina", "ang hina", "mahina", "talo kayo", "lampa", "boring", "where is your",
	"wheres ur", "uninstall", "go next", "ez game", "ez mid", "ez lane", "dog", "kids", "bots", "skill issue", "diff",
	"ezpz", "ez pz", "too ez", "get good", "git gud", "get gud", "l2p", "learn to play", "stay mad", "cry more", "mad?", "ratio",
	"free mmr", "1v1 me", "noob team", "u mad", "who's ez", "sit dog", "sit dogs"]
const PRAISE := ["nice", "gj", "wp", "good job", "well played", "galing", "lodi", "idol", "ganda", "clean", "solid",
	"great", "awesome", "ayos", "lakas", "thanks", "ty", "salamat", "thx", "tnx", "sheesh"]

## A random line of `sit` (from T or CALLS) in the speaker's language, with every field filled from `fill`; "" when none
## fits. want_tl: prefer Filipino and Taglish lines.
static func pick(sit: String, fill: Dictionary, want_tl: bool, rng: RandomNumberGenerator, avoid: Array = []) -> String:
	var lines: Array = T.get(sit, CALLS.get(sit, ChatMore.T.get(sit, ProfileLines.T.get(sit, []))))
	if lines.is_empty():
		return ""
	for attempt in 16:
		var i := rng.randi_range(0, lines.size() - 1)
		var e: Array = lines[i]
		if attempt < 10 and (String(e[1]) == "tl") != want_tl:
			continue
		var text := String(e[0])
		if attempt < 13 and text in avoid:
			continue
		var ok := true
		while text.contains("{"):
			var a := text.find("{")
			var b := text.find("}", a)
			if b < 0:
				break
			var key := text.substr(a + 1, b - a - 1)
			if key == "laugh":
				text = text.substr(0, a) + "\u0001" + text.substr(b + 1)    # the typist's own laugh (ChatStyle)
				continue
			if not fill.has(key) or str(fill[key]) == "":
				ok = false
				break
			text = text.substr(0, a) + str(fill[key]) + text.substr(b + 1)
		if ok:
			return text.replace("\u0001", "{laugh}")
	return ""

## "where are you from" etc.: what the player asked, from what they typed (lower case). The first intent that fits.
static func intent(t: String) -> String:
	var s := " " + t.to_lower().strip_edges() + " "
	for c in [",", ".", "!", ";", ":"]:
		s = s.replace(c, " ")
	var has := func(words: Array) -> bool:
		for wd in words:
			if s.contains(" " + String(wd) + " ") or (String(wd).contains(" ") and s.contains(String(wd))):
				return true
		return false
	# a friend request ("add me", "pa add", "duo after?") (run 2026-10-19 e)
	if has.call(["add me", "add u", "add you", "add ya", "add kita", "pa add", "paadd", "add mo ako", "add ko", "friend me",
			"can i add", "lets duo", "let's duo", "duo after", "duo?", "friend request", "be friends", "add each other", "add na"]):
		return "add"
	if has.call(["where", "san si", "saan", "nasaan", "asan", "wer"]) and not has.call(["where you from", "where u from", "where r u from"]):
		return "where"
	if has.call(["ss", "mia", "missing", "nawala"]):
		return "ss"
	# profiles (run 2026-10-20): "check my profile", "my stats?", "stalk me" / "check ur own profile"
	if has.call(["check ur profile", "check your profile", "ur profile", "your profile", "ur stats", "your stats", "ur avg",
			"your avg", "profile mo", "stats mo", "check ur own", "check your own"]):
		return "profile_you"
	if has.call(["my profile", "my stats", "my avg", "my average", "my history", "my record", "check me", "stalk me", "look me up",
			"check my", "profile ko", "stats ko", "tignan mo profile", "silipin mo profile", "my kda avg", "my mmr"]):
		return "profile_me"
	# the top of the ladder (run 2026-10-20 e): "who is top 1", "top 10?", "best player", "leaderboard"
	if has.call(["top 1", "top1", "top 5", "top 10", "top 20", "top10", "top20", "who is top", "whos top", "who's top",
			"number 1", "number one", "best player", "best players", "leaderboard", "sino top", "sino top 1", "pinaka magaling",
			"aetherium+ players", "top players", "highest mmr"]):
		return "ladder_top"
	if has.call(["rank", "mmr", "what rank", "anong rank", "rank mo", "ur rank", "your rank"]):
		return "rank"
	if has.call(["where you from", "where u from", "from where", "taga saan", "taga san", "san ka", "country", "where r u from", "wer u from"]):
		return "from"
	if has.call(["item", "items", "build", "anong item", "what buy", "what to buy", "bibilhin"]):
		return "item"
	# "bot" alone is the bottom lane ("push bot"): only "you bot", "bot ka", "are you a bot" ... count
	if has.call(["u bot", "you bot", "ur a bot", "ur bot", "are you a bot", "r u bot", "r u a bot", "bot ka", "robot",
			"npc", "is a bot", "such a bot", "like a bot", "bots", "ai", "u r bot", "you are bot", "you are a bot"]):
		return "bot"
	if has.call(["sorry", "sry", "my bad", "mb", "sorry po", "pasensya", "soz"]):
		return "sorry"
	if has.call(["ty", "thanks", "thank you", "salamat", "thx", "tnx", "tyty"]):
		return "thanks"
	if has.call(["why", "bakit", "bat", "where were you", "no help", "help me", "walang tulong", "di nyo ko tinulungan", "wtf team"]):
		return "why"
	# trash talk: "ez", "gg ez", "too easy", "sit" ... (insults are "insult", below)
	if has.call(TAUNT):
		return "taunt"
	if has.call(["ff", "surrender", "suko", "end it"]):
		return "ff"
	if has.call(["gg", "ggwp", "gg wp"]):
		return "gg"
	if has.call(["report"]):
		return "report"
	if has.call(["lag", "ping", "lagging", "nag lag"]):
		return "lag"
	for wd in RUDE:
		if s.contains(String(wd)):
			return "insult"
	for wd in PRAISE:
		if s.contains(" " + String(wd) + " ") or s.contains(" " + String(wd)):
			return "praise"
	if has.call(["hi", "hello", "hey", "yo", "sup", "musta", "kamusta", "glhf", "gl hf", "gl", "hf", "wassup", "helo"]):
		return "greet"
	if has.call(["haha", "hahaha", "lol", "xd", "lmao", "lmfao", "hahahaha", "wkwk", "kkkk"]):
		return "laugh"
	if s.strip_edges() == "?" or s.strip_edges() == "??":
		return "huh"
	return ""
