"""Write individually edited chat entries, without phrase combinations."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
path = ROOT / 'bot_trashtalk_chat_lines.json'
data = json.loads(path.read_text(encoding='utf-8-sig'))

text = {
'casual_short_mockery': '''
?
haha
lol
ez
gg
xd
sit
weak
basic
free
lmao
nice try
too easy
not even close
skill issue
try again
that's it?
you good?
no chance
keep trying
apaka basic ampota
matic na yan
pota weak
ulol!
tangaaaaaa
ampota
potakte
awit
olats
engot
asa ka
panis
ge nga
ano na?
ano yun lods
yun na yon?
weh
umay
nyeta
gagi
hanep
wala eh
kaya pa?
parang wala lang
di ramdam
ano ba yan
hahahaha gago
ang hina mo
waley
toinks
''',
'missed_skillshot_and_whiffs': '''
nice aim
all that mana for what
not even moving bro
hit something
wrong way
aim where i'm standing
you missed again
free dodge
that's your ult?
stand closer next time
cooldown wasted
point blank miss
who was that for
try the other direction
airball
san mo binato yun
wala kang tinamaan gago
hangin ampota
tutok mo kasi
tumama ka muna
sayang ulti mo
ayun lumagpas
nakahinto na ko nun
di pa tumama pota
sa lupa ba kalaban
kanino yun lods
anlayo ng tutok
minadali mo kasi
ulti sa wala
mana lang naubos mo
puro sablay
katabi mo na namiss pa
sumablay pa si idol
di mo ko abot
san ka nakatingin
cooldown na sayang pa
walang tama kahit isa
kalmahan mo tutok
nasayang stun mo
pindot pa pota
ako nandito oh
sa creep mo tinama
hinook mo hangin
kulang sa range lods
pa-skillshot ka pa
sayang combo walang tinamaan
di ako gumagalaw nyan ah
buong combo sablay
pano mo namiss yun
''',
'killed_enemy_all_chat': '''
sit down
thanks for the gold
free kill
back to base
same spot again?
worth the walk
got you
no escape
that's mine
easy pick
you walked into that
try running earlier
stay down
outplayed
you came back for more?
patay ka tuloy
balik ka pa
isa pa nga
sarap ng gold mo
salamat sa gold lods
ayan ka na naman
nahuli ka gago
takbo pa
san ka pupunta
abot kita
di ka nakatakas
akala mo ligtas ka na
wala kang kawala
tiklop
laglag ka boy
dasurv
ganyan lang yan
binura ampota
ambilis mo naman matunaw
ang lambot mo
di na nakapindot
tulog ka muna
balik fountain
balik base ulit
di ka umabot lods
wala na ubos na
may kasama ka pa nyan
dinagdagan mo lang gold ko
hinabol kita eh
wag ka kasi lumapit
buti lumabas ka
bwisit ka ha
yan ganti ko
nakaganti rin pota
ako naman ngayon
kanina ka pa eh
naalala kita gago
di na makulit ngayon ah
ikaw pala yun kanina
''',
'dying_too_much_and_feeding': '''
stop feeding
dead again?
play back
stop going alone
wait for us
you're feeding their carry
same death again
stop walking in
back before you die
not that fight again
how do you keep dying
you're just giving gold
respawn then feed
buy something defensive
stop chasing that
patay na naman
feed pa gago
tama na kakafeed
wag ka na sumolo
atras kasi pota
hintay ka naman samin
di ka na nadala
paulit ulit ka namamatay
di ka pa nadala
parang walang natutunan
wag ka na lumabas magisa
hinabol mo pa kasi
alam nang may abang
papasok ka na naman?
wag ka nang dumagdag
buhay ka pa ba dyan
respawn tapos patay ulit
naubos ka agad pota
sayang buhay mo
libre na naman sa kanila
pinayaman mo carry nila
di ka na natuto lods
namatay ka pa sa creep
umabot ka naman sana samin
tigil mo yan pre
di mo kaya magisa
patay ka bago kami dumating
lakad ka kasi nang lakad
ward muna bago pasok
sige feed mo pa
''',
'failing_lane_and_no_farm': '''
where are your items
free lane and still no farm
last hit something
you missed the whole wave
all that space for what
carry with no items
no farm no damage
lost lane already?
you're behind their support
stop buying random shit
still farming?
what's that build
hit the creeps bro
wave's right there
check your inventory
carry ampota baog
mid pa ulol
farm ka naman
walang item si gago
baog sa lane
puro ka jungle
di ka makalast hit
wala ka pang item?
anong build yan pota
kanina ka pa nagfafarm
ubos creep walang last hit
di ka na makalabas
deny pa more
pati ranged creep wala
sayang free lane mo
asan farm mo lods
boots lang item mo?
bumili ka naman
ipon para sa next game?
di ka makahawak ng creep
last hit naman pota
anong oras ka lalakas
may carry ba tayo
pa-mid ka pa
mid diff lods
carry diff pota
free lane na natalo pa
di ka man lang naka-level
ang layo ng farm nyo
wala kang damage pre
inuunahan ka pa ng support
kanino build mo galing
di ka pa lalaban nyan?
nakafarm ka ba talaga
ano yan puro boots
bumalik ka muna sa lane
sayang wave sa tore
creep lang yun lods
isang last hit naman
''',
'teammate_roast_and_blame': '''
where's our support
carry do something
mid wake up
stop farming we're fighting
wrong target
use your stun
ward first
we need detection
why did you go in
we said back
no follow up
press your buttons
hit the carry
stop hitting the tank
look at the map
save your tp
no damage carry
tank buy armor
support stop taking farm
nice stun after we died
nakakasuka laro mo lods
pabigat ka
wala kang ambag
kakampi ba kita
laro laro din
puro ka nood
san na potanginang support?!
support anong ginagawa mo
ward naman pota
wala tayong vision gago
may ward ka ilapag mo
pa-support di naman tumutulong
support ka last hit ka nang last hit
carry galaw naman
carry ka tas takot lumaban
farm ka nang farm wala namang damage
mid dalaw naman
mid di ka gagalaw?
pa-mid ka wala ka namang rotate
offlane anong plano mo
tank ka bat nasa likod
tangina mo tank ka pa nyan wala kang armor pota ka
pa-tank ka ang lambot mo
bili armor pota
wala ka namang tibay
san yung stun mo
stun mo na gago
may ulti ka pa pala
ginamit mo sana kanina
bat ngayon ka lang dumating
kanina pa ko nagping
tingin mapa naman
wala bang minimap dyan
atras sabi eh
bat ka pumasok dun
wala kami dyan tanga
iniwan mo ko pota
sabay kasi tayo
wag paisa isa
isa isa tayong inuubos
wala man lang sumunod
ako na naman una
bat ako lagi tank nyo
support ako ako pa una
tatlo na nga lang tayo
damage dealer unahin mo
tank lang hinahampas mo gago
heal mo sana ko
tinipid mo pa heal
may save ka bat di ginamit
nakita mo nang hinahabol ako
tp naman may laban
san ka nagtp pota
patay na kami saka ka nagtp
tapos na laban saka ka pasok
wag mo agawan ng farm
mas may ambag pa creep
sayang oras kakahintay sayo
ang gulo nyo maglaro
wala tayong focus pota
''',
'gen_z_brainrot_and_slang': '''
bro what
nah bro
aint no way
bruh
we're cooked
let him cook
bro is lost
who let bro cook
bro folded
bro sold
actual bot
paid actor?
nice throw bro
bro panicked
stop yapping
bro had one job
that's crazy
pack it up
bro forgot to play
gg go next
bro thinks he's good
that's embarrassing
bro where are you going
all that for nothing
bro just watched
''',
'ragebait_and_trolling': '''
come out
scared?
run it back
all five for me?
needed help for that?
bring more next time
still lost that trade
your tower can't help you
no team this time?
keep running
you started it
that was your chance
try without your team
one more?
show me then
just end already
we still win this
habol ka pa
tara isa pa
labas ka nga
duwag ampota
takbo nang takbo
wala bang mas malakas
lima para sakin?
pahelp ka pa
kelangan mo pa kasama
pag magisa ka wala ka
labas sa tore lods
yumakap ka na sa tore
ayaw lumabas ni idol
ikaw nga lumapit
wag ka magtago dyan
yan na best mo?
partida pa yan
kayo pa lamang nyan
mayabang ka lang pag marami
san na tropa mo
dami nyo namang kailangan
sugod ka ulit dali
ge end nyo
tapos nyo kung kaya
kaya pala tahimik
isa lang kaya mo?
tapangan mo naman
''',
'responses_and_comebacks': '''
scoreboard
you died first
still talking?
you started typing first
win first talk later
keep typing
less chat more farm
say that again
check your own items
your carry did that
that wasn't you
you got carried
still lost though
excuses already?
play the game
tahimik ka muna
di mo gets kasi tanga ka
ikaw pa maingay
ikaw nga una namatay
score mo muna tignan mo
laro muna bago dada
puro ka chat
chat pa more
di ka na nakapagchat ah
nasaan yabang mo kanina
maingay ka kanina ah
biglang tahimik si gago
iyak ka na?
galit na si idol
bat ka pikon
pikon talo
ikaw naman nauna
ikaw lang naman kausap ko
wag ka magpalusot
lag na naman dahilan mo
ping na naman sisi mo
wag ka umasa sa kakampi
binuhat ka lang naman
kakampi mo pumatay sakin
wala ka ngang ginawa dun
kill mo ba yun
nakisali ka lang gago
di ikaw kausap
laro mo ayusin mo
galing mo magchat ah
nanalo ka lang bumoses ka na
naubusan ka na dahilan?
wag mo isisi sakin
introboys
''',
'tagalog_trashtalk_and_kanal_humor': '''
tanginamo ka bai
tangina mo
tangina ka
putangina
putangina mo
pota ka
pota naman
puta naman oh
amputa ka
tangina naman eh
potek
punyeta
leche
bwisit
lintik
gago ka ba
gago amputa
gagoooo
ulol ka
ulol mo
ulul
bobo mo
ambobo
bobo ampota
bobong to
obob
tanga ka ba
apakatanga
tanga amp
engot ampota
bugok ka
hinayupak
hayop ka
animal ka
bano ampota
bonak
kamote ka
pulpol
walang silbi
walang kwenta
apakahina
hina mo pota
lakas mo ah
lakas magyabang
feeling magaling
paangas ka pa
angas lang pala
hanggang dyan ka lang
wala ka talaga
di ka marunong
ano ginagawa mo gago
ano trip mo
ayusin mo naman
umayos ka pre
sakit mo sa mata
umay sayo lods
laro mo bulok
galawang bano
galawang tanga
larong ewan
parang di nagiisip
may utak ka ba
gamitin mo naman utak mo
di ka nagiisip pota
bat ganyan ka maglaro
pano ka nanalo dati
nakachamba lang pala
chamba pa more
tsamba lang yan
sinwerte ka lang
swerte mo naman
di na mauulit yan
walanjo
langya ka
nakakabwisit ka
nakakainit ka ng ulo
ano na naman to
umay na umay na ko
ayoko na sa inyo
laruin nyo naman
seryoso ka ba dyan
talaga ba lods
yan seryoso mong laro?
ayos ah
galing naman ni idol
idol ano yon
iba ka talaga
ikaw na magaling
ge ikaw na
edi wow
wew
aw aw
nyemas
buset ka
kalat mo pota
daming sablay
wala sa hulog
di ko na alam sayo
tigil mo na yan
sayang oras sayo
sayang laro
gg sa inyo
walang pagasa to
kahit minsan gumaling ka
di ka na nahiya
ano ba naman yan pre
hayup na laro yan
''',
}

assert list(text) == list(data['chat_lines'])
data['chat_lines'] = {key: block.strip().splitlines() for key, block in text.items()}
data['metadata']['description'] = 'Short Filipino, Taglish, and English bot chat for kills, missed spells, lane mistakes, teammate complaints, and replies.'
data['metadata']['category_breakdown'] = {key: len(lines) for key, lines in data['chat_lines'].items()}
data['metadata']['categories_count'] = len(data['chat_lines'])
data['metadata']['total_lines'] = sum(data['metadata']['category_breakdown'].values())
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(data['metadata']['total_lines'], 'individually edited lines')
