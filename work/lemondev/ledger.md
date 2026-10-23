# Gauntlet ledger (private; not sent to critics)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Lane scene visuals | 1 | 8f4286a+bot | r1 (dota_3 vs candidate_r1 at 2:30 mid) | benchmark / true | REJECT | V1: open ground is empty (one flat gravel/grass texture with hard unshaded edges, no props, rocks or edge breakup) | Fix V1, recapture at the same framing, fresh critic |
| Lane scene visuals | 2 | dressing pass | r2 (same framing) | benchmark / true | REJECT | V2: props and terrain transitions not grounded (no contact AO under props, hard uniform path/grass edge, white river outline) | Fix V2 (contact shadows, edge breakup, wet bank), recheck with a fresh critic |
| Lane scene visuals | 3 | grounding pass | r3 | benchmark / true | REJECT | V3: lane is unconstructed ground (no curbed or built surface), no landmark structures near the lane; contact AO still weak (overlaps V2's AO element; primary defect judged new) | Fix V3. Note: benchmark frame shows base structures, so the next candidate is framed beside a tower to match scene complexity (benchmark itself unchanged) |
| Lane scene visuals | 4 | curbs + ruins + unit contact shadows (frame beside the tier 1 tower) | r4 | benchmark / true | REJECT | V4: style clash between photographic fine-grain terrain and building textures and flat stylized foliage (wants painterly, broad tonal variation) | Fix V4 (painterly mip-biased sampling, broad tone shifts, matched saturation) |
| Lane scene visuals | 5 | painterly sampling, warm and cool tone shifts | r5 | benchmark / true | REJECT | V5: lane is one uniform surface (needs worn paving and dirt variation across its width, grass bleeding into the edges, contact darkening at building bases). Related to V1–V3 but not identical to V4, so no plateau | Fix V5 |
| Lane scene visuals | 6 | worn paving, grass creep, building contact pools | r6 | benchmark / true | REJECT | V6: building materials photographic and stretched (want painted blocks with lit edges and dark joints); contact shading still weak (a recurring sub-theme since V2) | Fix V6 (procedural painted stone, stronger SSAO, toned curbs). 2 passes left |
| Lane scene visuals | 7 | painted masonry, stronger SSAO, toned curbs | r7 | benchmark / true | REJECT | V7: same primary defect as V6 (surfaces not hand-painted enough; contact AO and lighting depth weak; visible repetition) | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Best build is the current one. Next step needs authored hand-painted texture sets (terrain and masonry) plus baked or painted AO, not more procedural tuning |

## Visual review history (what improved per the critics)
r1 empty ground -> r2 scattered dressing, but not grounded -> r3 contact pools, dirt fringe, wet bank, but unconstructed lane -> r4 curbs, ruins, tower framing, but photo vs stylized clash -> r5 painterly sampling, but uniform lane -> r6 worn paving, grass creep, but photo-like tower -> r7 painted masonry; remaining gap is hand-painted material quality and AO depth.

## Session 2026-10-12 (Ezee, combat feedback, Dota controls)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Dark Stomp VFX | 1 | 0cb92dc | r8 vfx (e1_stomp_44 vs dota_9, 1600x900; note: capture predates the crack-shader rewrite in 0cb92dc) | benchmark / true | REJECT | S1: effect is a flat saturated ring decal with no height; reads as a range indicator, bends unevenly along the shore | Add vertical eruption (spikes, rising force wall), less saturated ring; recapture same framing, fresh critic |
| Hero Select screen | 1 | same | r8 menu (s1_select_ezee2 vs dota_7) | benchmark / true | REJECT | M1: hero's black armour blends into the dark backdrop; low-contrast silhouette, weak key/rim light | Stronger key and rim light, lighter backdrop; recapture, fresh critic |
| Dark Stomp VFX | 2 | 0cb92dc + working tree (spikes, force wall) | r9 vfx (s2_34 vs dota_9) | benchmark / true | REJECT | S2: spikes are flat, untextured single-tone cones with no ground contact or shading (placeholder look). Side observation: overlapping damage numbers ("15125") | Textured rock spikes with ground mounds and contact shading; fix overlapping numbers |
| Hero Select screen | 2 | same | r9 menu (s3_select_ezee vs dota_7) | benchmark / true | REJECT | M1 again: dark hero, low contrast against a flat backdrop | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Best build is the current one. Next step needs an art-direction decision: lighter or more reflective armour for Ezee (owner's call) |
| Dark Stomp VFX | 3 | working tree (pale stone shards, contact patches, stacked numbers) | r10 vfx (s5_36 vs dota_9) | benchmark / true | REJECT | S3: shards form a dense grey clump; the area's edge ring is near invisible, so there is no clean radial boundary showing what was hit | Evenly spaced shards on the area edge, leaning out; persistent bright rim on the ground; fresh critic |
| Dark Stomp VFX | 4 | working tree (edge-aligned shards, edge band) | r11 vfx (s7_37 vs dota_9) | benchmark / true | REJECT | S4: the area reads mainly as a thin flat violet circle; the shards that should carry volume are small, grey and half hidden by foliage | Fewer, much larger shards; softer edge line; lingering haze over the area; fresh critic |
| Dark Stomp VFX | 5 | working tree (large spike crown, haze disc) | r12 vfx (s8_37 vs dota_9) | benchmark / true | REJECT | S5: a flat uniform translucent purple disc paints over bushes like a screen overlay, not sitting on the ground (foliage near-fade dither lets it show through) | Remove the glow disc; scorched fissures reaching the spike ring; tighter foliage fade; fresh critic |
| Dark Stomp VFX | 6 | working tree (fissures to the ring, no disc, tent fix) | r13 vfx (s9_37 vs dota_9) | benchmark / true | REJECT | S6: spikes jut at chaotic mixed angles, partly under foreground foliage; saturated magenta fissures clash with the painted palette | Uniform outward lean and even heights; deeper, less saturated violet (caster-centred framing tried and dropped: foreground canopy covered the ring) |
| Dark Stomp VFX | 7 | working tree (uniform spike crown, calmer violet) | r14 vfx (s11_37 vs dota_9) | benchmark / true | REJECT | S7: spires are flat grey, texture-poor blocks that hide the enemies they hit and clash with the painted foliage | Final pass: hand-painted gradient spike shader, shorter spikes, none where an enemy stands |
| Dark Stomp VFX | 8 | working tree (painted spike shader, no spikes on units) | r15 vfx (s12_37 vs dota_9) | benchmark / true | REJECT | S8: ring partly hidden by canopy (top) and foreground foliage (bottom) in this jungle framing; crystals read flat and pastel with little visible impact on the units | **STOPPED: LIMIT** (8 of 8 passes). Best build is the current one. Next: capture in an open clearing, give the spikes a hand-painted texture and ground mounds, and show units being lifted |

### Session notes
* Review isolation was instruction-enforced (each critic was a fresh subagent told to read only its packet folder; packets held only the two anonymised images). Private mappings: work/private_mapping_r8..r15.txt.
* Pass 1 vfx evidence (e1_stomp_44) predates the crack-shader rewrite; later passes used captures from the revision under review.

## Session 2026-10-12 b (Blood Ranger, destructible trees, tower scale) — run `work/lemondev/2026-10-12-blood-ranger/`

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Tower scale (C1) | 1 | working tree after e4bfdc6 | r16 tower (br_tower3 vs dota_3) | candidate / true | UNVERIFIED | Benchmark invalid: the critic found no identifiable tower in dota_3, so scale could not be compared | Needs a Dota 2 frame that shows a lane tower beside heroes; no pass is claimed |
| Burst Shot VFX (C3) | 1 | same | r16 vfx (br_burst3 vs dota_9) | benchmark / true | REJECT | B1: the area reads as thin outline rings plus numbers; no volume, no visible effect on the units hit | Painted ground stain, bigger arrows, blood bursts, hit flinch |
| Burst Shot VFX (C3) | 2 | same + fix | r17 vfx (br_burst5_48 vs dota_9) | benchmark / true | REJECT | B1 again: a flat red ring on the ground and numbers; units inside show no hit, lift or impact | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Note: dota_9 is an eruption-type spell, a still frame of an arrow volley mostly shows arrows already landed. Next step needs a decision: an arrow-volley benchmark (or a motion clip comparison) and stronger per-hit reactions |

Review isolation: instruction-enforced (fresh subagents told to read only their packet folder; each reported only the two packet images in `files_read`). Private mappings: `work/lemondev/2026-10-12-blood-ranger/private_mapping_r16.txt`, `_r17.txt`.

## Session 2026-10-12 c (map overhaul, hotkeys, debug panel, loading screen) — run `work/lemondev/2026-10-12-map-overhaul/`

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Base environment (M3) | 1 | 792086f | r18 base (rv_base vs dota_3) | benchmark / true | REJECT | MB1: flat repeating cobble and grass with hard borders; props few and evenly spaced, no layered clutter or wear | Break paving edges (grass creep, worn flagstones), layered prop clusters (stall, crates, barrels, banners, shrubs) |
| Ramps and elevation (M1) | 1 | 792086f | r18 ramp (rv_ramp vs dota_2) | benchmark / true | REJECT | MR1: no visible steps, slope or height difference; the tier 3 tower stands in the framed corridor | Taller levels, stairs with clear risers and side walls; frame a ramp without a building on it |
| Base environment (M3) | 2 | 792086f + pass 2 (kerb greenery, paving edge breakup, supply clusters, quartermaster stall) | r19 base (p2_base vs dota_3) | benchmark / true | REJECT | MB2 (new): props look primitive and placed on the ground rather than set into it (box awning, flat rug, stubby torch pillars, loose bricks) | Ground the procedural props (contact shade, sunk edges, growth at their feet), richer stall and pillar shapes |
| Ramps and elevation (M1) | 2 | same (levels 1.28 -> 2 m, risers and side walls, plateau ramp framing) | r19 ramp (p2_ramp_a vs dota_2) | benchmark / true | REJECT | MR2 = MR1: no visible terrain height change (flat ground both sides); the steps read as a brick mass | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Next step needs a decision: much taller levels (3-4 m) with rock cliff faces flanking each ramp, which changes the look of the whole map |
| Base environment (M3) | 3 | 792086f + pass 3 (octagonal torch columns on plinths with growth at their feet, contact shade under towers, walls and the stall, no rug or loose stones, fountain uses the river water shader) | r20 base (p3_base vs dota_3) | benchmark / true | REJECT | MB3: flat, uniform materials with hard edges (repeating cobble tile cut sharply into the grass, plain striped awning, bare white geometry); props scattered rather than placed. Same identity as MB2 (primitive, low-detail props) | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Next step needs authored hand-painted texture sets and modelled props (stall, crates, pillars) from Blender or a CC0 pack, not more procedural meshes |

Review isolation: instruction-enforced (fresh subagents, packet folders only; each listed only its two packet images). Private mappings: `work/lemondev/2026-10-12-map-overhaul/private_mapping_r18.txt`, `_r19.txt`, `_r20.txt`. The r20 critic result was read from the subagent transcript after the previous session hit its usage limit.

Integration (M4), working tree after 792086f: 59 tests pass; benchmark 77 fps, p95 16.67 ms (gate passed); bot duels 3 x 12 min complete (`duel.txt`); export and cold start of the exe clean (`export_run.txt`) after fixing the boot loading screen, which was never shown (add_child while the root was busy).

## Session 2026-10-13 (Sludge, items, shop) — run `work/lemondev/2026-10-13-sludge-items/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Shuriken Hook visuals (S2) | 1 | f598fdf + working tree (sludge_fx.gd) | r21 hook (c1_26 vs Valve Meat Hook video frame 97) | benchmark / true | REJECT | H1: the hook does not visibly reach or hold the target; thin pale chain starting in the air beside the thrower; shuriken washed out by a white blur ring | Chain anchored to the fist from the live skeleton pose (the attachment lagged a frame), dark iron links, no white ring, shuriken lying flat, latched star kept in front of the victim |
| Shuriken Hook visuals (S2) | 2 | same + fixes | r22 hook (c6_31 vs frame 97) | benchmark / true | REJECT | H1 again: the hook sits beside the target instead of gripping it; also called out: chain shadow doubles the line, thrower looks flat grey | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Note: both candidate frames were taken a tick before the bite, while Valve's frame shows the hook already wrapped round the target. Next step needs your decision: recheck with the bite frame (and a shorter chain shadow), which is a new pass under a changed capture rule |

Review isolation: instruction-enforced (fresh subagents, packet folders only; both listed only their two images). Private mappings: `private_mapping_r21.txt`, `_r22.txt`. Benchmark: `work/benchmark/pudge/pudge_meat_hook.mp4` (Valve CDN, see contract.md), frames extracted with Blender (`frames.py`).
Evidence note: `research/liquipedia_pudge*.json` are Liquipedia rate-limit pages, not data; the Sludge numbers came from the Liquipedia wikitext read during the 2026-10-12 session and the game data file `npc_dota_hero_pudge.txt`.

Session resumed 2026-10-13 after a second cut-off (items and shop were in the working tree, uncommitted):

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Sludge mechanics (S1) | 1 | b68aecf + working tree | gate: headless tests | n/a | PASS (gate) | none | none |
| Sludge bot (S3) | 1 | d82bd68 + working tree | gate: 20 min duels vs both heroes, 3 seeds | n/a | PASS (gate) | none; hooks heroes 3-7 times a game | none |
| Items (I1) | 1 | working tree | gate: 92 tests (one per recipe path and active/passive) | n/a | PASS (gate) | spot-check against items.txt found Cleave Axe dealt 60% to creeps; Dota deals 40% (`cleave_damage_percent_creep`); fixed and tested before the gate | none |
| Shop UI (I2) | 1 | working tree | gate: readable at 1080p and 2160p, every item buyable by mouse | n/a | PASS (gate); blind review UNVERIFIED (no Dota shop frame set up) | none | benchmark frame of Dota's shop for a blind review |
| Integration (G) | 1 | working tree | tests 92/92, check.sh "Names OK", duels 9/9 complete, bench 82 fps p95 14.2 ms, export + cold start (Sludge match ready 9.7 s), Options persist across processes | n/a | PASS (gate) | ObjectDB leak warning at exit (188 instances, 184 before this run): pre-existing, not new | none |

## Session 2026-10-13 b (Sludge input fixes, cursors, To Buy, stash, courier, HUD) — run `work/lemondev/2026-10-13-fixes-items-courier/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Ability input (A1) | 1 | 8310428 | gate: live input probe through InputController | n/a | REJECT (baseline) | Stench never issued (toggle not handled); Chomp hotkey refused before a target was picked | fix begin_ability, cast_error check_target |
| Ability input (A1) | 2 | working tree | gate: live input probe, 3 heroes | n/a | PASS (gate) | none (Sludge 10/10, Blood Ranger 7/7, Ezee 4/4) | none |
| Talent tree (A2) | 1 | working tree | gate: HUD flow probe click learns +5 Armor; capture talents.png | n/a | PASS (gate); blind review UNVERIFIED | none | Dota talent tree frame for a blind review |
| Targeting cursor (B) | 1 | working tree | gate: cursor frames rendered (cursor_enemy.png, cursor_ally.png); colour per targeting_team | n/a | PASS (gate); blind review UNVERIFIED | none | — |
| To Buy, stash, items (C1, C2) | 1 | working tree | gate: 8 new sim tests + HUD flow probe 13/13 | n/a | PASS (gate) | test expectation error (parts order Headband first) fixed in the probe, not the code | none |
| Courier (C3) | 1 | working tree | gate: sim tests (speed, flying, burst, shield, hits, respawn, bounty, items kept, Well sweep) | n/a | PASS (gate) | old test expected undelivered items back in the stash; Dota keeps them on the courier: test updated to Dota | none |
| HUD overhaul (D) | 1 | working tree | gate: captures hud/talents/courier/shop at 1080p | n/a | REJECT (self-check) | Blubber shell opaque, Stench cloud invisible, two courier buttons both labelled "Return", shop hint overlapping, HUD stash under the open shop | fixed, recaptured |
| HUD overhaul (D) | 2 | working tree | gate: recaptures | n/a | PASS (gate); blind review UNVERIFIED (no Dota frames of stash / quick buy) | none | Dota frames for a blind review |

Notes: no critic subagent was run this session (no benchmark frames for the new UI); every visual gate above is a
builder self-check and is reported as UNVERIFIED for review.
| Integration (G) | 1 | working tree | tests 100/100, check.sh Names OK, input probes 3 heroes, HUD flow probe 13/13, duels 9/9 complete, bench 77/76 fps p95 15.15/16.67 vs same-session baseline 76 fps p95 16.67, export + cold start 12.6 s, true 4K captures | n/a | PASS (gate) | p95 gate against the old session's 14.2 ms failed on one run; a same-session control of the baseline matched the new build, so the machine, not the change, moved | none |

## Session 2026-10-13 c (camera, camps, Game Setup, team bots, chat, pings, learning) — run `work/lemondev/2026-10-13-camps-ai-setup/` (contract.md)

Session cut off during integration; on resume the owner asked to cut the remaining tests, finish and build.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| AI2 hero bots | n | working tree | gate: 10 x 5v5 bot games, 40 min | n/a | REJECT (gate) | no Ancient falls in any game; Bot Cat and Bot Jo idle in lane from 0:21 in all ten | fix the idle-in-lane bug first |
| Integration (G) | 1 | working tree | bench 1v1 48-53 fps, 5v5 39-58 fps; names OK; export | n/a | INCOMPLETE (cut by owner) | bench below the 10% gate; tests and probes not rerun | rerun tests, probes, bench |
| CAM, NC1, NC2, GS, AI1, AI3, CH | — | working tree | captures only | n/a | UNVERIFIED | gates not rerun at the end | rerun the probes |

## Session 2026-10-13 d (controls, HUD, status effects, bash, crit, items, neutral abilities, true sight, orbs) — run `work/lemondev/2026-10-13-controls-mechanics/` (contract.md)

No critic subagent was run (the owner did not ask for subagents, and no Dota frames of the new visuals are on disk);
every visual gate below is a builder self-check and is reported UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| U1 cursor lock, edge pan | 1 | 93b2efc + working tree | gate: controls_probe (live window on the owner's 2nd monitor) | n/a | PASS (gate) | none: CONFINED in Borderless/Fullscreen/locked Windowed; OS clamps a warped cursor; edge pans and keeps panning when pushed | none |
| U2 shop closes | 1 | working tree | gate: controls_probe | n/a | PASS (gate) | none | none |
| U3 regen with bonus | 1 | working tree | gate: test + capture | n/a | REJECT (self-check) | green "+bonus" low contrast on the green bar | outline the text |
| U3 regen with bonus | 2 | working tree | gate: recapture | n/a | PASS (gate) | none | none |
| U4 Teleport Scroll | 1 | working tree | gate: test + probe | n/a | PASS (gate) | none (one probe flake: waited 20 frames for a 0.5 s shop check; probe fixed) | none |
| U5 hold Stop | 1 | working tree | gate: controls_probe | n/a | PASS (gate) | none | none |
| M1 status system | 1 | working tree | gate: tests (PRD table and rate, stun groups, status/slow resistance, hex, silence burst, root, disarm, break, dispels) | n/a | PASS (gate) | none | none |
| M2 crit and bash | 1 | working tree | gate: tests + live crit in probe | n/a | PASS (gate) | none | none |
| M3 items | 1 | working tree | gate: tests (prices, recipes, actives) + shop captures | n/a | REJECT (self-check) | shop pane text ran into "Made from" for long items | reserve rows for parts, shorten texts |
| M3 items | 2 | working tree | gate: recaptures | n/a | PASS (gate) | none | none |
| M4 neutral abilities | 1 | working tree | gate: tests + Smash capture | n/a | PASS (gate) | none | none |
| M5 rules fixes, true sight, disjoint | 1 | working tree | gate: tests | n/a | PASS (gate) | test setup stood heroes behind trees (no sight); test fixed, not the code | none |
| M6 orbs and Flask | 1 | working tree | gate: tests (schedule, cycle, rewards, effects, Flask) + probe (right click take) + captures | n/a | PASS (gate) | none | Illusion rune needs illusions |
| V visuals | 1 | working tree | gate: captures (disable bars, sheep, roots, disarm, crit number, orbs, Smash ring) | n/a | REJECT (self-check) | disarm blades hidden behind the health bar | lower them to head height |
| V visuals | 2 | working tree | gate: recaptures | n/a | PASS (gate); blind review UNVERIFIED | none | Dota frames for a blind review |
| Integration (G) | 1 | working tree | tests 137/137, check.sh Names OK, controls_probe 31/31 (1080p) and 23/23 (true 4K), input probes 3 heroes, item flow 13/13, two 40-min 5v5 bot games without script errors, bench 60/55/62 fps vs same-session baseline 57/60, export + cold start 9.7 s | n/a | PASS (gate) | none new; old AI2 gate (an Ancient falls in 60 min) still fails, stuck bots late in games | blind review needs Dota frames |

## Session 2026-10-14 (elements, damage and armor types, magic amp, item menu, item effects, Azrin) — run `work/lemondev/2026-10-14-elements-azrin/` (contract.md)

No critic subagent was run (the owner did not ask for subagents and no Dota frames of these effects are on disk):
every visual gate is a builder self-check and is reported UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| E1 elements, types, magic amp, burns | 1 | a38afe7 + working tree | gate: headless tests | n/a | REJECT (gate) | old Dota-number tests broke on the element layer and the Int magic amp | tests isolate elements (`SimWorld.elements`), oracles include magic amp |
| E1 | 2 | working tree | gate: 154 tests | n/a | PASS (gate) | none | none |
| E2 Kugmo / Igit / Atuli | 1 | working tree | gate: tests (names, recipes, stats, diminishing amp, mana cost, cast speed) | n/a | PASS (gate) | none | none |
| E3 item menu, lock, disassemble | 1 | working tree | gate: tests + menu_probe 14/14 (real clicks), 1080p and real 4K captures | n/a | PASS (gate) | none | none |
| E3b full refund protection (owner's follow-up) | 1 | working tree | gate: test (accidental disassembly inside 10 s sells for 2400, half after, old parts + new recipe) | n/a | PASS (gate) | combined items had only their combine time: fixed with per-piece purchase records | none |
| E4 Azrin kit and bot | 1 | working tree | gate: tests (each ability with the owner's numbers), input probe 12/12, 12-min duels 3 seeds x 3 heroes, no errors | n/a | PASS (gate) | balance note: wins 16-1 vs Blood Ranger, 13-0 vs Ezee, 4-3 vs Sludge (owner's numbers kept) | owner to tune |
| V1 fire system and Azrin's look | 1-9 | working tree | self-check captures (fire_preview, in-match, Hero Select) | n/a | REJECT x8, then PASS (self-check) | in order: embers drawn huge (billboard scale); hard flame bases; white-out in daylight; pale cream tongues; sparse candles; blocky noise (sin hash); glare walls; robe hiding her | blind review UNVERIFIED |
| V1b female_generic body (owner's follow-up) | 1-4 | working tree | self-check: Blender previews, look lineup, Hero Select | n/a | REJECT x3, then PASS (self-check) | fit pose ignored (rig copied in REST mode); hair over face (head offset); face cut away (UV2 V flip) | blind review UNVERIFIED |
| V2 item effects | 1-2 | working tree | self-check captures (Spike Armor, Block Shield, corruption, rage, Spell Shield) | n/a | REJECT (rage and dome too strong), then PASS | — | blind review UNVERIFIED |
| U1 HUD chips and sheet | 1-2 | working tree | menu_probe captures at 1080p and real 4K | n/a | REJECT (two "Hero" chips ambiguous; tooltips missing from captures) then PASS | — | blind review UNVERIFIED |
| A1 creep death sounds | 1 | working tree | gate: test (-7.37 dB = Options.to_db(0.6)) | n/a | PASS (gate) | none | none |

## Session 2026-10-14 b (QA, performance, UI remake, multiplayer, Froster and Caziel) — run `work/lemondev/2026-10-14b-ui-net-heroes/` (contract.md)

Session interrupted; on resume the owner asked to wrap up and build. Only the end gates below were rerun.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Q1 lane creeps | 1 | working tree | finding Q1-a fixed (spawns inside tower footprint) | n/a | INCOMPLETE | 5 v 5 games not rerun | rerun 3 x 50-min games |
| H1 Froster, H2 Caziel | 1 | working tree | gate: tests + 12-min duels vs every hero, 3 seeds, no errors | n/a | PASS (gate) | none | owner to tune |
| N1 command funnel | 1 | working tree | gate: tests | n/a | PASS (gate) | none | none |
| N2 network session, U4 screens | — | working tree | none | n/a | INCOMPLETE | no net_menu screen; net_test not run | build U4, run net_test |
| U0 skin, U1 Main Menu | 1 | working tree | self-check: export_menu.png | n/a | UNVERIFIED | Multiplayer button pointed at a missing scene: hidden until it exists | blind review vs Dota frames |
| P1, P2, U2, U3 | — | working tree | none | n/a | INCOMPLETE (cut by owner) | not run | rerun profile and bench |
| Integration (G) | 1 | working tree | tests 170/170, check.sh Names OK (Froster and Caziel names added to the owner list), export + cold start Froster 10.1 s / Caziel 10.5 s / Main Menu, no script errors | n/a | PASS (gate, reduced) | probes and bench not rerun | none |

## Session 2026-10-15 (multiplayer, HUD pips, owner's bug reports) — run `work/lemondev/2026-10-15-multiplayer/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| H1 HUD level pips | 1 | working tree | self-check capture (Caziel, 1080p-ish window) | n/a | PASS (self-check) | pips sat across the health well's gold rim and under the slot frame | 4K capture at integration |
| B1 units at the map centre | 1 | working tree | gate: view_place_probe (6 game min, 268465 checks) | n/a | REJECT then PASS | views of units spawned off screen were never placed (origin = river), never animated (bind pose = giant T-pose); new views waited a frame | none |
| B2 neutral aggro, camps, Alt boxes | 1 | working tree | gate: 171 tests, camp_layout 0 problems, team_probe 11/11 | n/a | PASS (gate) | Gale Impact test picked a new tree spot after the camp move (test made robust) | 5 v 5 bot game |
| H1 HUD level pips | 2 | working tree | self-check: real 4K crop (net_match_4k) | n/a | REJECT then PASS (self-check) | a learnable pip at its brightest looked like a learned one | pulsing outline for learnable; blind review UNVERIFIED |
| N2 server, rooms, relay lockstep | 1 | working tree | gate: net_test dedicated (2 players), hosted (1 player), exported build as server; 2 server unit tests | n/a | PASS (gate) | first run's forced desync fell before the first wave (no creep to move): test frame moved to 3600 | none |
| N2 latency | 2 | working tree | gate: exported server, real time | n/a | REJECT (68.4 ms > 2 ticks + RTT) then PASS (35 / 38 ms) | gaps between frames counted as stalls raised the jitter buffer; packets waited for the next poll | none |
| U4 Multiplayer screens | 1-4 | working tree | gate: net_ui_probe (real clicks, two windows) + self-check captures 1080p and real 4K | n/a | REJECT x3, then PASS (gate; self-check look) | in order: titles and buttons on the frames' corner ornaments; empty rows drawn as buttons; frames lost (style box duplicate drops its texture); Stop Hosting stayed on the lobby list; the same server listed twice (127.0.0.1 and its network address); team titles on ornaments, muddy Ready pill, gear icon read as a dot, empty hero panel | blind review UNVERIFIED (no subagents asked for, no Dota lobby frames); 2 probe misses in 6 runs recorded |
| Integration (G) | 1 | working tree | tests 173/173, check.sh Names OK, net_ui_probe 35/35 + 17/17, view_place_probe PASS, team_probe 11/11, 20-min 5 v 5 bot game, export + dedicated server from the exported build | n/a | PASS (gate, reduced) | performance benchmarks not rerun | main server address from the owner |

## Session 2026-10-15 b (Debug panel, auto-select, unit panel, 10-skill bar, 20 items, icons, Tock and Kragg) — run `work/lemondev/2026-10-15b-ui-items-heroes/` (handoff.md)

No critic subagent was run (none asked for, no Dota reference frames on disk): visual gates are builder self-checks,
UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| D1 Debug panel | 1 | working tree | gate: hud15_probe 1080p + real 4K (panel inside screen, 27 controls uncut, rest scrolls) | n/a | PASS (gate) | cause: framed box margins ignored by the placement (panel 64 px past the right edge) | none |
| S1 Auto-select hero | 1 | working tree | gate: hud15_probe (right click, Stop, Hold with a creep / nothing selected) | n/a | PASS (gate) | none | none |
| S2 Unit panel | 1-2 | working tree | gate + self-check captures (creep, neutral, tower, Throne) | n/a | REJECT then PASS (self-check) | empty 0 / 0 mana bar and a doubled "Neutral" label | none |
| S3 Skill bar to 10 | 1 | working tree | gate: hud15_probe 6 and 10 skills, keys Q W E D F R / Q W E D F G Y U I R; console art per count | n/a | PASS (gate) | none | none |
| I1 Cooldown system | 1 | working tree | gate: tests (reduction no stack, rate slower / frozen / faster, items, AoE, cast range) | n/a | PASS (gate) | none | none |
| I2 Twenty items | 1-2 | working tree | gate: tests (prices and recipes vs items.txt, combine, actives, auras both sides) | n/a | REJECT then PASS | "strongest copy" passive rule changed the bash item order (test_only_one_bash_item_works): limited to chain and block | none |
| V1 Item and skill icons | 1-2 | working tree | self-check contact sheets (old vs new, 96 and 44 px) | n/a | REJECT then PASS (self-check) | Battle Armor read as Plate Armor | blind review UNVERIFIED |
| H1 Tock, H2 Kragg | 1-2 | working tree | gate: tests, input probes 13/13 and 6/6, captures | n/a | REJECT then PASS | Rewind refunded its own mana; Stop Time dome too bright | duels / 5 v 5 |
| T1 Tower ranges on Alt (owner's follow-up) | 1 | working tree | captures with and without Alt (ranges_alt, ranges_none) | n/a | PASS (self-check) | none | none |

## Session 2026-10-15 c (performance in teamfights, bots, learning, Quick cast) — run `work/lemondev/2026-10-15c-perf-feel-ai/` (contract.md)

No critic subagent was run (none asked for); these components are measured, not judged by eye. Visual changes
(portrait backdrop, trails) are builder self-checks, UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| P1 teamfight frame time | 1 | 81efd48 + working tree | gate: bench `--fight` (real brawl) | n/a | REJECT (baseline) | 24 fps; Froster's effects aborted on a freed node every frame and printed the error (~10-12 ms/frame) | View.live at 49 sites |
| P1 | 2 | working tree | gate: same-session A/B vs 81efd48 + harness | n/a | PASS (gate) | see the final A/B in docs/HANDOFF.md | none |
| P2 sim spikes | 1-3 | working tree | gate: sim_profile --fight (ticks > 15 ms) | n/a | REJECT x2 then PASS | in order: ten bots thinking on one tick; vision cache wiped on every felled tree (20-30 ms ticks); team brains on one tick and repeated power / building scans | none |
| P3 interface | 1 | working tree | gate: bench ui_* means, draws, capture | n/a | PASS (gate) | the portrait re-rendered the whole world (~460 draw calls) | none |
| A1 last hits | 1-2 | working tree | gate: lh_lab 8 min, five heroes | n/a | REJECT (baseline 17-31) then PASS (37-47) | the forecast fired late; -0.2 s lead | per-hero learning tried, drifted the wrong way, removed |
| A2 teamfights | 1 | working tree | gate: mirrored A/B, 8 games, tf_off swapped | n/a | PASS (gate, modest) | side with team engage ahead in net worth 6/8 (avg +4.5k), kills 5/8 (+4.9) | more games for confidence |
| A3 ganks | 1 | working tree | gate: tests (rally out of sight, way home) | n/a | PASS (gate) | laning-phase lane-partner "ganks" every 30-60 s pulled laners off the wave | none |
| A4 farm | 1-3 | working tree | gate: carry LH@10 in 5v5 | n/a | PARTIAL | carries 5-13 -> 16-23 at 10:00; still below Dota bots (~40) | lane equilibrium near the enemy tower; lane control |
| A5 ending games | 1-5 | working tree | gate: an Ancient falls within 60 min | n/a | REJECT x4 then PASS 3/4 | in order: pushes ended per tower; late ganks across the map; stuck bots; no group; every hero ran from tower aggro | games still long (50-60 min) |
| L1 learning | 1-2 | working tree | gate: learn_ab (3 trainers x 3 games, eval both sides vs control) | n/a | REJECT x2 (not shown to help) | v1: last-hit lead drifted to +0.3; v2: learned side better as Ancient Light (+2.9k), worse as Black Sun (-6.4k) | last-hit learning removed; engage / gank learning kept, benefit UNVERIFIED |
| U1 Quick cast | 1 | working tree | gate: input_probe sludge 12/12, azrin 14/14 | n/a | PASS (gate) | none | none |

## Session 2026-10-15 e (buff bar) — run `work/lemondev/2026-10-15e-buff-bar/` (contract.md, handoff.md)

No critic subagent was run (none asked for, no Dota reference frames on disk): the look is a builder self-check,
UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| B1 Effect data | 1 | working tree | gate: test_buff_bar_entries, full suite 197/197 | n/a | PASS (gate) | none | none |
| B2 Buff bar | 1-3 | working tree | gate: buff_probe 1080p 29/29, real 4K 20/20 (3 hover checks skipped: frame larger than the monitor) + self-check captures | n/a | REJECT x2 then PASS (gate; self-check look) | in order: overflow dropped silently; centred seconds hid the icons | blind review UNVERIFIED |
| B3 Effect names | 1-2 | working tree | gate: modifier_census (3 x 30 min, all heroes), Names OK | n/a | REJECT then PASS | four effects unnamed, Charge counted as a buff | none |

## Session 2026-10-15 f (regen readout, Rejuvenation Orb, tower shots, Fortify, courier, Fast Forward) — run `work/lemondev/2026-10-15f-regen-fortify/`

No critic subagent was run (none asked for, no Dota frames on disk): looks are builder self-checks, UNVERIFIED for
blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| R1 Regen readout | 1-2 | working tree | probe 1080p + 4K captures | n/a | REJECT then PASS (self-check) | healing cut hidden in the bonus; faint "+" | blind review UNVERIFIED |
| O1 Rejuvenation Orb | 1 | working tree | test (to 30:00) + capture | n/a | PASS | none | none |
| T1 Tower shots | 1-2 | working tree | probe captures both teams | n/a | REJECT then PASS (self-check) | Black Sun corona edge-on to the camera | blind review UNVERIFIED |
| F1 Fortify | 1-2 | working tree | tests (splash, marks, speed, bots), probe (tooltip 60/60 frames), captures, bot game | n/a | REJECT then PASS | shells too big and opaque | blind review UNVERIFIED |
| C1 Courier | 1 | working tree | test | n/a | PASS (gate) | none | none |
| K1 Fast Forward | 1 | working tree | test | n/a | PASS (gate) | none | none |

## Session 2026-10-15 g (Kragg rework, varied picks, smarter bots, title and Main Menu, hero animations) — run `work/lemondev/2026-10-15g-kragg-bots-menu/` (contract.md)

No critic subagent was run (none asked for, no Dota menu frames on disk): the menu and title are builder self-checks,
UNVERIFIED for blind review. The owner rejected the hero animations mid-run ("body parts rotating and twisting");
A1 was added then.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| K1 Kragg rework | 1 | working tree | gate: tests, kragg_probe 11/11 1080p, 8/8 4K, duels | n/a | PASS (gate) | none | none |
| P1 Varied picks | 1 | working tree | gate: test (300 seeds) | n/a | PASS (gate) | none | none |
| I1 Magic defence items | 1 | working tree | gate: test (costs, icons, fade, barrier) | n/a | PASS (gate) | none | none |
| B1 Bot items | 1-2 | working tree | gate: test + 2 bot games | n/a | REJECT then PASS (gate) | counters cycled every 30 s (Froster) | one counter at a time |
| B2 Counter-ganks | 1-2 | working tree | gate: test + bot games | n/a | REJECT then PASS (gate) | Town Portal saves for lane skirmishes at 1:00 | none before 10:00 |
| B3 Jukes | 1-2 | working tree | gate: tests + bot games | n/a | REJECT then PASS (gate) | juke teleport home at 0:51 | badly hurt only before 8:00 |
| M1 Title card | 1-2 | working tree | self-check captures 1080p / 4K | n/a | REJECT then PASS (self-check) | blocky hills (shader hash), seam beside the suns | blind review UNVERIFIED |
| M2 Main Menu | 1-2 | working tree | self-check captures, hover, 4K | n/a | REJECT then PASS (self-check) | Quit plate over the banner emblem; line through Play | blind review UNVERIFIED |
| A1 Hero animations | 1-6 | working tree | gate: anim_audit (352 -> 86 findings), frame sheets | n/a | PARTIAL | in order: elbow flips and forearm spins; snaps; reference degenerate on backswings; shield on the fist; Sludge's belly | lane creep clips; staff and shield edge frames; dual_4 spin |

## Session 2026-10-15 h (lane creep and unit animations) — run `work/lemondev/2026-10-15h-unit-anims/`

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| A2 Unit animations | 1-3 | working tree | gate: anim_audit --units (188 -> 44), frame sheets before / after | n/a | PARTIAL | in order: golem / ogre hands pushed out of a torso sized by their far-out shoulders; slams cut through the chest (straight-line hand path) | staff and shield edge frames; elbows at the top of overhead slams |
| C1 Missing attack clips | 1 | working tree | gate: audit MISSING lines gone | n/a | PASS (gate) | the hill troll had no attack clip at all | none |

## Session 2026-10-16 (two new heroes, Roydo and Blau) — run `work/lemondev/2026-10-16-roydo-blau/` (contract.md, sources.md)

No critic subagent was run (none asked for, no Dota frames on disk): the look of both heroes and their effects is a
builder self-check, UNVERIFIED for blind review. The session was interrupted before integration; a later session
ran the integration gate (tests, check.sh, duels, bot game, export, cold start).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| M1 Models | 1-n | working tree | gate: anim_pops16 (0 flips > 90 deg, 0 backward joints, 85 turns 45-60 deg), frame sheets in `preview/` | n/a | PASS (gate; self-check look) | none recorded | blind review UNVERIFIED |
| S1 Roydo kit | 1 | working tree | gate: tests (Grip, Rush, Skin, Anomaly) | n/a | PASS (gate) | none | none |
| S2 Blau kit | 1 | working tree | gate: tests (Bounce Shot x2, boulders, trap, turret, pilot) | n/a | PASS (gate) | none | none |
| V1 Visuals | 1 | working tree | self-check captures `shots/` (every skill, Anomaly swap) | n/a | PASS (self-check) | none | blind review UNVERIFIED |
| U1 UI | 1 | working tree | self-check `hud_blau.png`, `hud_roydo.png`, `portraits.png`, `icons16.png`; Names OK | n/a | PASS (self-check) | none | none |
| B1 Bots | 1-2 | working tree | gate: 6 bot tests, duels (`duels.txt`, `duels_final.txt`), 5 v 5 bot game (`bot_game.txt`) | n/a | REJECT (integration hang, see I1) then PASS (gate) | Blau loses lane to Azrin (0-12 kills over 3 seeds) | lane trading vs strong laners |
| I1 Integration | 1 | working tree | gate: tests 224/224, check.sh, export, cold start; Roydo duels and 5 v 5 bot game | n/a | REJECT | every game froze in one sim step once Roydo's bot used Anomaly in a lane (last-hit forecast divided by his zero projectile speed: infinite loop) | form projectile speed + guard; regression test |
| I1 Integration | 2 | working tree | gate: tests 225/225, check.sh, duels, bot game, export, cold start | n/a | PASS (gate) | none | Blau's laning (out-farmed by Roydo and Azrin) |

## Session 2026-10-16 b (the owner's mechanics list) — run `work/lemondev/2026-10-16b-mechanics/`

No critic subagent was run (none asked for); the Switch Boots icons are a builder self-check.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| G1 Grip target check | 1 | working tree | gate: tests, input_probe (Roydo) | n/a | PASS (gate) | none | none |
| T1 Town Portal double tap | 1-2 | working tree | gate: input_probe (Roydo, Blau) | n/a | PASS (gate) | probe read the channel too early (probe fix) | none |
| B1 Blau reach | 1-2 | working tree | gate: tests | n/a | REJECT then PASS (gate) | boulders bumped past the reach (758 at 700) | none |
| I1 Switch Boots icons | 1-2 | working tree | self-check `treads.png`, test | n/a | REJECT then PASS (self-check) | strength boot rendered grey | blind review UNVERIFIED |
| U1 Unfair bots | 1 | working tree | gate: tests, Unfair bot game | n/a | PASS (gate) | none | none |
| P1 Pushing and lead | 1 | working tree | gate: tests, bot games (2 seeds + before) | n/a | PASS (gate) | none | more seeds to show games end sooner |
| X1 Integration | 1 | working tree | gate: tests 235/235, check.sh, export, cold start | n/a | PASS (gate) | none | none |

## Session 2026-10-17 b (Azrael, talents, trees, labels, kill card, Bot Log, Blau bot, gap report) — run `work/lemondev/2026-10-17-azrael/`

No critic subagent was run (none asked for); looks and effects are builder self-checks. The gap report was written by
a research subagent (read-only on the code).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| T1 Talent trees | 1-2 | working tree | gate: tests | n/a | PASS (gate) | test read strength before refreshing stats | none |
| R1 Tree felling | 1-2 | working tree | gate: tests | n/a | PASS (gate) | felled trees and resting boulders leaked into later tests (shared map) | none |
| U1 Labels and kill card | 1-2 | working tree | self-check `kill_card_sheet.png` | n/a | PASS (self-check) | card title over the top bar | none |
| B1 Bot Log + Blau bot | 1-3 | working tree | gate: tests, duels before / after | n/a | PASS (gate) | lane / retreat flapping every 1-2 s | Blau vs Azrin lane |
| A1 Azrael kit | 1-2 | working tree | gate: 5 tests | n/a | PASS (gate) | test tolerances (cooldown timing, mana regen) | none |
| A2 Azrael look | 1-5 | working tree | self-check captures | n/a | PASS (self-check) | in order: blown-out face; base underwear through the robe; blade facing the wrong way (owner's report, measured with swing_dir.gd) | blind review UNVERIFIED |
| A3 Azrael effects | 1-3 | working tree | self-check captures | n/a | PASS (self-check) | swing trail as a flat plank; wings flat paper; door milky | blind review UNVERIFIED |
| A4 Azrael bot | 1-3 | working tree | gate: duels, 5 v 5 bot game | n/a | PASS (gate) | exit re-ordered every think (cast cancelled); early dives | out-farmed by Ezee / Caziel |
| X1 Integration | 1 | working tree | gate: tests 244/244, check.sh, bot game, export, cold start | n/a | PASS (gate) | none | none |

## Session 2026-10-17 c (Double-click self-cast and Azrael skill rework)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| U1 Double-click self-cast | 1-2 | working tree | gate: input_probe (skill and item self-cast, TP fountain) | n/a | PASS (gate) | point self-cast required turning to angle 0; open door from earlier probe stage intercepted second door cast | none |
| A1 Azrael kit rework | 1 | working tree | gate: 5 updated Azrael tests, full suite 244/244, modifier_census 0 unnamed | n/a | PASS (gate) | none | none |
| X1 Integration | 1 | working tree | gate: tests 244/244, input_probe 19/19, check_names, export | n/a | PASS (gate) | none | none |

## Session 2026-10-17 d (QA: performance, gameplay, bots, map; outer ground and map sites; 3D sound world) — run `work/lemondev/2026-10-17d-qa-map/` (contract.md)

No critic subagent was run (none asked for); looks are builder self-checks against the game's own captures
(merged vs unmerged units side by side, site captures).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| P1 Frame time | 1-6 | working tree | gate: teamfight and lane benches against baseline (`bench_fight_before*.txt`, `bench_fight_after*.txt`) | n/a | PASS (gate) | in order: shared clips re-flagged every tick (track caches dropped); per-surface draws and skins of heroes; merge cache missing on per-unit materials (65 ms hitch per creep); retired pieces freed with materials on them ("material is null") | the 30 Hz sim tick (~5 ms) still makes p95 ~29 ms in a ten-hero fight |
| P2 Quit crash | 1-2 | working tree | gate: bench exits 0 | n/a | PASS (gate) | bench probe lambdas left on the rendering server's signals; orphan core node from Azrin's javelin | none |
| M1 Outer map | 1-2 | working tree | gate: tests, camp_layout (sites reachable), captures | n/a | PASS (gate) | new map size reshuffled the whole forest (tests broke): classic forest now placed first with the classic rules | none |
| M2 Map sites | 1-2 | working tree | gate: 4 new tests, captures | n/a | PASS (gate; self-check look) | gate ring unreadable from the top-down camera; black rock material | blind review UNVERIFIED |
| B1 Bots and sites | 1-2 | working tree | gate: bot games | n/a | see handoff | sites unused in the first game (reach too short) | more games |
| S1 Sound world | 1 | working tree | gate: audio_probe (sounds load, every model has a material, Effects bus at 60%), day and night live runs without errors | n/a | PASS (gate) | none | listening test by the owner (not audible to the builder) |

## Session 2026-10-17 e (hero models from the owner's downloads) — run `work/lemondev/2026-10-17e-hero-models/` (contract.md)

No critic subagent was run (none asked for); looks are builder self-checks (Blender previews, live captures).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| T1 Body tool | 1-9 | working tree | gate: previews of every body in idle, run, swing | n/a | PASS (self-check) | in order: stale bone references; bone heat failing on loose pieces and tiny models; T-posing crushed rigid plates (fixed by binding in the model's own pose and retargeting); hip plates riding the hand; cloth ballooning; seam cracks; reach limit tearing big gauntlets (made opt-in); fused staff stretching into needles (split off, then cut out as a weapon); recolour lost on save | blind review UNVERIFIED |
| H1 Ezee body | 1-4 | working tree | gate: captures in match and Hero Select | n/a | PASS (self-check) | sword guard left in the fist | none |
| H2 Azrin body | 1-6 | working tree | gate: captures in match and Hero Select | n/a | PASS (self-check) | staff turned backward in empty-hand clips (now a weapon on staff clips); magenta instead of red | owner look |
| H3 Caziel body | 1-3 | working tree | gate: captures | n/a | PASS (self-check) | too dark at game distance (greys lifted) | violet accents if wanted |
| H4 Emelrich, Feran bodies | 1-4 | working tree | Blender previews only | n/a | IMPLEMENTED — UNVERIFIED | not in a match (no kits) | sun emblem; jester restyle |
| X1 Integration | 1 | working tree | gate: tests 248/248, parse, check_names | n/a | PASS (gate) | none | export rebuild |


## Session 2026-10-18 (run 2026-10-17 f: Ghorman's human body, Azrael's new body, strict animation QA) — run `work/lemondev/2026-10-17f-ghorman-azrael/`

No critic subagent was run (none asked for). New measured gate: `tests/tools/pose_compare.gd` (every own-body clip
against the hero body, per bone, 25 degree limit); looks are builder self-checks (contact sheets in `qa/`).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| A1 Azrael body | 1-4 | working tree | gate: sheets, Hero Select, live glide captures, pose_compare 4.2 deg | n/a | PASS (self-check) | in order: Biped bone names not recognised; hair bones' rest at the origin (hair at her feet); skin recolour bleeding into the shared atlas; skin too pale on the stage | owner look |
| G1 Ghorman body | 1-9 | working tree | gate: sheets, live captures, pose_compare 7.0 deg, no vertex at the origin | n/a | PASS (self-check) | in order: thighs through the kilt slits (trousers added); fur cards lost their UVs on join (one UV name); fur gone at a distance (thicker alpha); NaN trouser vertices from a negative power (made a plank to the floor); red knife stretched | kit; owner look |
| Q1 Arm repair on own bodies | 1-2 | working tree | gate: pose_compare before 239 deg worst, after 8.6 deg | n/a | PASS (gate) | the per-body arm repair measured twist and swivel from the own bodies' hanging-arm rest and flipped arms (Ezee 150-170 deg, Caziel 100, staff hands 55-60) | none |
| Q2 Coat webbing | 1-2 | working tree | sheets before / after (Ezee roar, Caziel heavy strike) | n/a | PASS (self-check), one flap left | the coats took arm weights; `--reach` (now defined) frees cloth beyond each arm bone's reach | Ezee's left forearm flap |
| X1 Integration | 1 | working tree | gate: tests 248/248, parse, check_names, export, cold start as Azrael and Ezee | n/a | PASS (gate) | none | none |

## Session 2026-10-18 c (release build and push) — run `work/lemondev/2026-10-18-build/`

Build-only scope, source `5f73062`. No gameplay or asset changes, new benchmark, or independent visual review.
Two test diagnostic messages corrected after the full suite; both affected tests rerun successfully.

| Component | Pass | Revision | Evidence | Verdict | Remaining gap |
|---|---|---|---|---|---|
| Release export | 1 | 5f73062 | import/export exit 0; tests 249/249; check.sh Names OK; exported menu and Azrael captures inspected | Build-only checks passed; full Gauntlet UNVERIFIED | Existing shutdown resource leaks; independent comparison and full lifecycle validation not performed |

## Session 2026-10-18 b (hero model QA after the owner's Azrael screenshot; body collision system) — run `work/lemondev/2026-10-18-model-qa/`

No critic subagent was run (none asked for). New measured gate: `tests/tools/body_collide.gd -- --applied` (worst
penetration of arms, hands and weapons into the body, other arm and floor, every frame of every clip in use).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Q3 Azrael hands | 1-5 | working tree | gate: close-up sheets, Hero Select, in-match capture | n/a | PASS (self-check) | in order: hand bone tail from the conversion (94 deg off); open claw hands; thumb claw straight out; claw tips glued to the hip by the cloth and reach rules | none |
| Q4 Coat webbing | 1-3 | working tree | sheets before / after (Caziel dual_heavy, Ezee roar, Azrin staff) | n/a | PASS (self-check), one plate left | arm and trunk weights mixed on cloth the hand touched; upper arm too | Ezee's left-hand plate |
| Q5 Cut remnants | 1 | working tree | bind-pose renders | n/a | PASS (self-check) | slivers and chips the capsule cut left loose | none |
| C1 Body collision | 1-7 | working tree | gate: body_collide before/after, --applied | n/a | PASS (gate) for 7 of 8 hero bodies under 6.8 cm; units 12/16 at 0 | in order: shapes centred on the bone not the skin; two-hand grips colliding with each other; elbow across the chest unsolvable by swing alone; single frames left after smoothing (rounds); Unreal rigs' tracks unnamed | golems' and ogre's fist slam; legs and cloth |
| X1 Integration | 1 | working tree | gate: tests 249/249, check.sh, export, cold start | n/a | PASS (gate) | none | none |


## Session 2026-10-18 d (Mixamo motion capture, hand remnants, build) — run `work/lemondev/2026-10-18d-mocap/`

No critic subagent was run (none asked for). Measured gates: `tools/blender/remnant_check.py` (arms lifted: vertices
left at a hand, torn faces), `tests/tools/body_collide.gd -- --applied`, tests, export and cold start. Looks are builder
self-checks (survey sheets, in-game contact sheets, Hero Select captures).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| M1 Mixamo download | 1-4 | working tree | 181 files, names checked by content hash | n/a | PASS (gate) | in order: pack export refused ("Invalid Pose option"); export race returned the previous job; per-link credentials (no compact pass-through); the pane cannot reach localhost (saved via its own download folder) | none |
| M2 Retarget | 1-3 | working tree | survey sheets of every clip; in-game sheets | n/a | PASS (self-check) | in order: hit frames found in wind-ups (set by hand); blows landing over 1 s in (trimmed to 0.4-0.8 s); a clip name clashing with an old clip | blind review UNVERIFIED |
| M3 Game integration | 1-2 | working tree | test_mocap_clips; fallback without the library | n/a | PASS (gate) | new class not registered until an import pass | none |
| M4 Hand remnants | 1-9 | working tree | remnant_check before/after, renders | n/a | PASS (self-check) Ezee, Caziel; Azrin improved with ragged sleeve hems left | in order: torso patches taken by the arm (ratio rule); hard elbow seams on added weights (blend); coat strip past the fingertips; whole dress flipped on Azrael's many-piece mesh (piece cap, Azrael `--split=0`); split run before the unmix inside hero_body (moved after) | Azrin's sleeve hems |
| M5 Body collision | 1-2 | working tree | `--applied` | n/a | PASS (gate) for every mocap clip (0.9 cm or less) | Froster's channel clip planted the staff 14 cm into the floor (clip swapped) | old fallback clips on rebuilt bodies (Ezee 42 cm, Azrin 21 cm) |
| X1 Integration | 1 | working tree | tests 250/250, check.sh, export, cold start | n/a | PASS (gate) | none | none |


## Session 2026-10-18 e (mocap for the remaining clips and the five new heroes, pickable heroes, Airah on the base body, joins) — run `work/lemondev/2026-10-18e-mocap2/`

No critic subagent was run (none asked for). New measured gate: `tests/tools/anim_joins.gd` (every crossfade and loop
seam). Looks are builder self-checks (contact sheets, close-ups, remnant renders, captures).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| B1 New bodies | 1-3 (+4 Airah) | working tree | gate: remnant_check before/after, renders | n/a | PASS (gate) Emelrich, Burak, Airah | in order: arm split scattered many-piece models; reach rule freed big hands; Airah's posed sculpt (rebuilt on base_female: generated top, briefs, collar; pinned tail, belt, hair; tail lifted off the floor) | Beast Form body |
| C1 Remaining clips | 1-4 | working tree | gate: test_new_heroes_and_blends, sheets | n/a | PASS (self-check) | in order: one-hand axe swings flopped Burak's second axe (two-weapon slashes); spinning slash unjoinable (dropped); dagger lunge 175 degrees off the stance (double stab) | none |
| Q1 Joins | 1-8 | working tree | gate: anim_joins 563 -> 23 (worst 76 -> 16) | n/a | IMPLEMENTED — 23 over the limit | in order: fixed 0.06 s crossfades; caps too short; hit clips while running; blind stretching flips near-opposite poses (simulated candidates); stale collision sets | 23 residual joins |
| Q2 Twists | 1-3 | working tree | gate: anim_audit (game-played clips), pops scan, close-ups | n/a | PASS (self-check) | Mixamo toe flips (hinge clamp); hips not scaled to leg length (floor sink, foot slide) | none |
| Q3 Clipping | 1-2 | working tree | gate: body_collide --applied | n/a | PASS (gate) 1.7 cm or less but Sludge 4.2 cm | push and hit clips never checked | Sludge's hook in the floor |
| X1 Integration | 1-2 | working tree | gate: tests 251/251, check.sh, exports (05:00 and final), cold start | n/a | PASS (gate) | Hero Select grid overflow at 16 heroes (four a row) | none |


## Session 2026-10-18 f (the five new heroes' kits, bots, icons, effects, build) — run `work/lemondev/2026-10-18f-kits/`

No critic subagent was run (none asked for). Measured gates: headless tests (a test per ability group checking the
file's numbers), `tests/tools/kit_casts.gd` (every skill cast by bots in 30-minute games), name check, export and cold
start. Looks are builder self-checks (in-game captures, icon sheet).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| K1-K3 Kits | 1-3 | working tree | gate: 23 new tests | n/a | PASS (gate) | in order: kit files did not compile; Frenzy Mask and Berserk shared an effect id; a stun broke Giant Swing's wind-up under Steel Stance | none |
| K4 Bots | 1-2 | working tree | gate: kit_casts, 3 games | n/a | PASS (gate) every skill cast | Shuffle and Blessing never cast (looser Shuffle rule, Blessing at 8, blessing out of fights) | Feran's Upgrade Staff Swap |
| K5 Presentation | 1-2 | working tree | captures, icon sheet | n/a | PASS (self-check) | Hurricane funnel hid the fight (smaller, fainter) | none |
| K6 Beast Form body | 0 | — | — | n/a | NOT DONE | old body kept | rebuild |
| X1 Integration | 1 | working tree | gate: tests 273/273, check.sh, export, cold start (2 heroes) | n/a | PASS (gate) | none | live click test of beast control |


## Session 2026-10-18 g (150% experience and gold, All-Bot watching, higher camera, Debug Bots, build) — run `work/lemondev/2026-10-18g-spectate/`

No critic subagent was run (none asked for). Measured gates: headless tests, `tests/tools/watch_probe.gd` (live
match, two ways in), name check, export and cold start. Looks are builder self-checks (captures at 1080p).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| R1 Rates | 1-2 | working tree | gate: test_match_rates + 11 Dota-number tests at 1.0 | n/a | PASS (gate) | popups and kill banners showed the unscaled gold | none |
| S1 All-Bot match | 1 | working tree | gate: watch_probe (--watch and Game Setup) | n/a | PASS (gate) | none | none |
| S2 Spectator view | 1-2 | working tree | gate: watch_probe 24/24; captures | n/a | PASS (self-check) | panel covered the team chat (compacted) | Auto camera tuning |
| C1 Camera | 1 | working tree | captures | n/a | PASS (self-check) | none | none |
| D1 Debug Bots | 1 | working tree | gate: watch_probe Bots checks; capture | n/a | PASS (gate) | none | none |
| X1 Integration | 1 | working tree | gate: tests, check.sh, export, cold start | n/a | see docs/HANDOFF.md status | none | 4K UI check |

## Session 2026-10-19 (shorter bot chat library) — run `work/lemondev/2026-10-19-chat/`

Standalone text edit; user examples and rejected screenshot are the style benchmark. Six research sources are
recorded in `research.md`. Two fresh critics read only anonymous equal-size excerpts; filesystem isolation was
instruction-enforced. Neither had builder context. Comparison scope: 80 entries per version, not the full library.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Chat wording | 1 | JSON `ffa63233` | `review_1.md` | candidate / true | PASS comparison; wording repaired | one unclear farm complaint | fresh review of corrected revision |
| Chat wording | 2 | JSON `b213452a` | `review_2.md` | candidate / true | PASS sampled comparison | baseline phrase combinations; no decisive candidate gap | owner can review full library |
| JSON integration | 2 | JSON `b213452a` | `validation.json`, name check | n/a | PASS standalone data gates | none | runtime integration outside request |

Result: 557 entries in unchanged ten category keys; median three words; 554/557 at most six words; metadata matches;
no case/punctuation-only duplicates. JSON contract OK; Names OK. New game names/identifiers: none. No engine code or
build changed; the JSON currently has no game loader. Original saved in `before.json`. Full details: run's `handoff.md`.

## Session 2026-10-18 h (bots' items, chat, teleports, creep pressure, Azrael, Ezee; creeps; take control; build) — run `work/lemondev/2026-10-18h-bots/`

No critic subagent was run (none asked for). Measured gates: headless tests, live watch probe, tp/item probes, bot
games, joins check, name check, export and cold start. Sounds and looks are builder self-checks.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| A1 Attack sounds | 1 | working tree | none (not listened to) | n/a | UNVERIFIED | none known | listen in game |
| A2 Emelrich run | 1-2 | working tree | sheets, anim_joins | n/a | PASS (self-check) | mocap runs hunched his body | none |
| M1 Jump Knife lock | 1 | working tree | test_jump_knife | n/a | PASS (gate) | hero units and fountain did not lock it | none |
| B1 Teleports | 1 | working tree | tp_probe | n/a | PASS (gate) | walk-off break rule | none |
| B2 Items | 1-6 | working tree | item_probe (3 games) | n/a | PASS (gate) | bought-but-unformed items; room sales of good items | 4K/long games |
| B3 Creep pressure | 1-2 | working tree | test_bot_creep_gang | n/a | PASS (gate) | none | none |
| B4 Azrael, Ezee | 1-2 | working tree | two tests | n/a | PASS (gate) | test enemy level | none |
| C1 Chat | 1-2 | working tree | bot games, names | n/a | PASS (self-check) | a slur and a banned word in drafted lines (removed) | player game |
| W1 Creeps | 1 | working tree | 2 tests | n/a | PASS (gate) | gate pacing at side lanes | none |
| S1 Take control | 1 | working tree | watch_probe 32/32 | n/a | PASS (gate) | none | none |
| X1 Integration | 1 | working tree | tests, check.sh, export, cold start | n/a | see docs/HANDOFF.md | none | blind review |

## Session 2026-10-19 b (ranked matchmaking) — run `work/lemondev/2026-10-19b-ranked/`

One fresh-context critic on the final captures (no source, no benchmark: not a blind A/B). Measured gates: headless
tests, live click probe with a real ranked match, bot games by rating, name check, captures at 1080p and 4K.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| R1 Ranked data | 1-3 | working tree | 4 tests | n/a | PASS (gate) | JSON roles as floats; `Ranked.set_name` hit Resource.set_name | none |
| R2 Matchmaker | 1 | working tree | 2 tests, probe | n/a | PASS (gate) | none | none |
| R3 Rated bots | 1 | working tree | 2 tests, 4 bot games | n/a | PASS (gate) | none | calibrate against players |
| R4 Ranked UI | 1-4 | working tree | critic 1 + recheck | n/a (no benchmark) | IMPLEMENTED, benchmark UNVERIFIED | hover card over Accept (fixed) | Dota 2 client comparison |
| R4b Emblems | 1-5 | working tree | critic 1 | n/a | self-check after fix | Hero/Transcendent less grand than Mythic (fixed) | none |
| R5 Match hook | 1-2 | working tree | probe 38/38 | n/a | PASS (gate) | icons blank/squashed after a window resize (baked with a validity check) | none |
| R6 Hero pick | 1-2 | working tree | test_hero_draft, probe | n/a | PASS (gate) | long names clipped (fit) | none |
| R7 3D versus | 1-2 | working tree | captures 1080/4K, probe | n/a | self-check (owner asked for 3D) | square embers, plates over titles, off-screen plate (fixed) | owner's look |
| R8 Hero mastery | 1-2 | working tree | 2 tests, probe | n/a | PASS (gate) | no Diamonds on the ladder (top bots' records deepened); first star in 2 wins (350 XP) | balance over real games |
| X Integration | 2 | working tree | tests 291, check.sh, probe 45/45 | n/a | see docs/HANDOFF.md | none | release export |

## Session 2026-10-19 c (Araki, the Blur; Blau's turrets; Airah and Tock facing; build) — run `work/lemondev/2026-10-19c-araki/`

No critic subagent was run (none asked for); no Dota 2 client here, so the benchmark gate is UNVERIFIED. Measured
gates: headless tests, kit tests, body collision, animation joins, bot games and a death probe, name check, captures.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| M1 Body, katana | 1-5 | working tree | close-ups, body_collide, anim_joins | n/a | PASS (gate) | broken source rest pose (fixed by araki_prep); arm split tore armour (off); 113 MB > GitHub limit (1536 tex) | none |
| K1 Kit | 1-2 | working tree | 6 tests | n/a | PASS (gate) | Blur Strike walked instead of dashing past 600 (direction cast); ghosts killed by the summon timeout (own expiry) | none |
| B1 Araki bot | 1-4 | working tree | 7 bot games, araki_probe x4 | n/a | IMPLEMENTED (gate measured) | mana starvation: escape dash unaffordable (reserve kept); Ghosts cast once in 20 min (cast earlier) | real players |
| V1 Look, FX, UI | 1-3 | working tree | captures 1080p | n/a | self-check | demon cloud read as a bright vortex (darkened); rising smoke not visible in captures | owner's eye |
| F1 Facing | 1-2 | working tree | versus_shot, portraits | n/a | PASS (self-check) | spell_idle_2 turns the body; portraits side-on in the great sword idle | none |
| F2 Blau turrets | 1 | working tree | kit_casts | n/a | PASS (gate) | built only in hero fights (13-16 a game) | none |
| X1 Integration | 1 | working tree | tests, check.sh, export | n/a | see docs/HANDOFF.md | none | blind review |

## Session 2026-10-19 d (living players: personas, living ladder, chat brain, Players tab, online writer) — run `work/lemondev/2026-10-19d-living/`

One fresh-context critic, blind A/B of chat transcripts (old system vs the new one, same seed), isolation by
instruction (shared filesystem). No commercial benchmark for bot chat (UNVERIFIED gate).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| P1 Persona, ladder | 1-2 | working tree | 4 tests, captures | n/a | PASS (gate) | same match minute for everyone online; feed flooded by "started learning" (fixed) | weeks of real time |
| P2 Memory, friends | 1 | working tree | test, ranked_probe 45/45 | n/a | PASS (gate) | bot history lacked K/D/A of matches with you (fixed) | none |
| P3 Chat brain | 1-4 | working tree | critic 1 + measured recheck | A (candidate) / true | PASS | echoes across players, filler after "!", repeated calls (fixed in 2-3, recheck measured) | owner's ear |
| P4 Players tab | 1-2 | working tree | captures 1080p/4K | n/a | IMPLEMENTED | none seen | blind review |
| P5 Online writer | 1-3 | working tree | llm_probe vs mock | n/a | IMPLEMENTED, UNVERIFIED (no real call) | "150%" broke the system prompt's formatting (fixed); probe wrote to the real usage file (fixed) | owner's key, one match |
| X Integration | 1 | working tree | full suite, check.sh, talk_probe, export | n/a | see docs/HANDOFF.md | none | none |

## Session 2026-10-19 e (the social world: crowd reactions, trash talk, friends, MVP, live stats, pick chat, Forums) — run `work/lemondev/2026-10-19e-social/`

One fresh-context critic, blind A/B of chat transcripts from the same match with the new social layer on and off
(`tests/tools/social_probe.gd --off`), two seeds, labels shuffled per pair (`review/mapping_private.json`). No
commercial benchmark here (UNVERIFIED gate).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| S1 Match stats | 1 | working tree | test_match_stats_counters, snapshot test | n/a | PASS (gate) | ChatSocial without a no-argument constructor broke snapshot restore (fixed) | none |
| S2 Live stats panel | 1-3 | working tree | captures 1080p | n/a | self-check | hover breakdown never drew (Tip redraws first; registered) | 4K capture |
| S3 MVP | 1-2 | working tree | test_mvp_support_can_win, test_ranked_mvp_and_memory, captures | n/a | PASS (gate) | hard seam in the MVP screen's shade (gradient) | owner's eye |
| S4 Social reactions | 1-2 | working tree | 6 tests, critic 1 + recheck.py | new / clear (both seeds) | see handoff | a dominating enemy bot drew no smurf talk, under-reacted multi-kills, a hero quip 4 times a match (pass 2) | owner's ear |
| S5 Memory, friends | 1 | working tree | test_ranked_mvp_and_memory, test_chat_add_me_makes_a_friend | n/a | PASS (gate) | none | real ranked match by clicks |
| S6 Pick chat | 1 | working tree | test_draft_pick_chat_and_calls | n/a | IMPLEMENTED | none seen | capture of the pick with chat |
| S7 Forums | 1-2 | working tree | test_forum_offline, captures | n/a | IMPLEMENTED | repeated titles, generic replies (fixed); a capture used the owner's real key (guarded) | blind review |

## Session 2026-10-20 (the player is always answered; trash talk answered in kind; forums answer you)

Bug fix run on the owner's report ("Bots (using LLM) not replying to any of the player's messages in all-chat ... they
try to pacify the player"). Root causes found in code and in the owner's own forums.json (two of their replies had no
answer queued). No critic pass: measured gates only.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| C1 Match chat answers | 1-2 | working tree | test_chat_player_always_answered (80 lines, quiet busy bots), talk_probe 22/22 offline and with the model | n/a | PASS (gate) | praise in all chat answered in team chat (fixed) | owner's ear |
| C2 No pacifying | 1 | working tree | test_chat_trash_talk_never_pacified (120 insults), talk_probe | n/a | PASS (gate) | "ur mom" etc. not read as trash talk (added) | owner's ear |
| C3 Online writer | 1 | working tree | test_llm_answers_the_player_first, llm_probe vs mock 19/19, one live probe with the real model | n/a | PASS (gate) | live probe used the owner's key (guarded: automated() ) | none |
| C4 Forums | 1 | working tree | forum checks in test_ranked_mvp_and_memory | n/a | PASS (gate) | own-thread replies without a target went to nobody (fixed); old ones answered on the next visit | owner's ear |

## Session 2026-10-20 b (the social makeover: Profile, performance MMR, careers, profile-aware players, right-click menus, themed skin) — run `work/lemondev/2026-10-20-profile/`

No fresh-context critic and no commercial benchmark capture this run (both gates UNVERIFIED); measured gates and
inspected captures only (`ui/`, before `before/`).

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| K1 Career stats | 1 | working tree | test_career_averages, test_ranked_upgrade_careers | n/a | PASS (gate) | none | a real unranked match by the owner |
| K2 Performance MMR | 1-2 | working tree | test_career_mmr_range, test_ranked_match_result, test_ladder_careers | n/a | PASS (gate) | the ladder inflated +62 over 60 rounds (fixed: rounds evened to zero sum) | owner's feel |
| K3 AI careers, MVPs | 1 | working tree | test_ladder_careers, captures | n/a | PASS (gate) | none | none |
| K4 Profile talk | 1 | working tree | test_profile_talk, test_chat_profiles_in_match, test_draft_pick_chat_and_calls | n/a | PASS (gate) | lines only named the last match (added last-five averages) | owner's ear |
| K5 Walls and acts | 1 | working tree | test_profile_walls | n/a | PASS (gate) | first visit showed an empty wall (seeded) | none |
| K6 Profile UI | 1-2 | working tree | captures 1080p / 4K, ranked_probe | n/a | self-check | role text clipped, title divider over rows (fixed) | blind review |
| K7 Right-click menus | 1 | working tree | captures, ranked_probe | n/a | self-check | none seen | forum overlay by clicks |
| K8 Skin | 1-2 | working tree | preview sheet, captures | n/a | self-check | flame and sword glyphs weak (redrawn) | owner's eye |
| X Integration | 1 | working tree | full suite 327/0, names, parse checks, ranked_probe, export | n/a | see docs/HANDOFF.md | ranked_probe's end step predated the MVP screen (fixed) | none |

## Session 2026-10-20 c — generated skill and item icons

Run: `work/lemondev/2026-10-20-icons/`. All 17 heroes and 176 item records audited. Built-in generation only. 227 images made; 226 used, original Death Order kept by explicit owner choice after plateau.

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| Skills | 1 | review/skills/review.md | new set preferred | four subjects unclear when small/dim | simplify subjects |
| Skills | 2 | review/final/review.md | REJECT | tiny action cues | one large subject/action |
| Skills | 3 | review/focus/review.md | three PASS; Death Order STOPPED — PLATEAU | low-health condition unclear | owner chose original SVG |
| Items | 1 | review/items/review.md | new set preferred; revise | Blast Rod pips | larger pips |
| Items | 2 | review/final/review.md | PASS | no mandatory failure | integrated |
| Routing / imports | 1-2 | accepted_gallery logs, packed_final_probe | 1806 checks / 0 failures | none | owner play |
| Snapshot regression | 1 | snapshot_tests.txt | PASS | global prof exclusion also dropped ChatProfile | fixed scope |
| Integration | 1-3 | handoff.md, final_results.txt | IMPLEMENTED — UNVERIFIED | commercial comparison and 60 FPS/lifecycle gates not passed | separate performance work |

## Session 2026-10-20 d — interface smoothness and the official icon border

Run: `work/lemondev/2026-10-20d-ui-smooth/` (handoff.md). Benchmark Dota 2 tiles by name only (commercial gate UNVERIFIED).

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| U1 Popups / Esc | 1-2 | ui_smooth_probe 34/34 x3, ranked_probe 51/51 | PASS (gate) | talent rows filled only at 20 Hz redraw (fixed) | owner play |
| U2 Fades / loading | 1 | ui_smooth_probe fade checks | PASS (gate) | none | owner's eye |
| B1-B3 Borders | 1 | critic/ | INVALID packet | state mismatch | matched packet |
| B1-B3 Borders | 2 | critic2/ | REJECT | frame inside frame (backpack, teleport) | tile-shaped slots |
| B1-B3 Borders | 3 | critic3/ | PASS | thin innate frame at 28 px | optional |
| P1 Passive hotkey | 1 | hud_passive capture | self-check | none | none |
| Integration | 1 | suite, probes, check.sh, export | see handoff | none | owner play |

## Session 2026-10-20 e — accounts, pick quick stats, pro reactions, Players and friend chat, structures, Araki, Emelrich

Run: `work/lemondev/2026-10-20e-social-accounts/` (handoff.md, captures). No commercial benchmark capture (gate UNVERIFIED).

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| S1/S2 Structures | 1 | test_destroyed_building_opens_ground, t3 captures | tests pass | none | owner play |
| A1 Araki ghosts | 1 | test_araki_ghosts_hit_runners | tests pass (0/9 -> 9/9 on a runner) | none | owner play |
| E1 Giant Swing | 1 | guard, stance and dodge tests; swing captures | tests pass | cooldown left at owner's 20/15/10 | owner veto |
| R1 Accounts | 1 | test_ranked_accounts; accounts captures | tests pass | no click-through probe | probe |
| P1 Pick quick stats | 1 | peek captures | self-check | no critic | critic |
| B1/B2 Pro reactions, ladder | 1 | test_profile_pro, test_chat_profiles_in_match | tests pass | none | owner play |
| U1 Players / friend chat | 1 | players captures | self-check | no critic, no probe | critic, probe |
| X Integration | 1 | suite 333/0, check.sh Names OK, export, export/exe_match.png | PASS (gate) | none | owner play |

## Session 2026-10-21 — Blackfire and Thyrandael, barriers, Forums tab, faster matchmaking

Run: `work/lemondev/2026-10-21-blackfire-thyrandael/` (contract.md, handoff.md, logs, shots, ui, bodies). No commercial
benchmark capture (gate UNVERIFIED). No blind critic run (none asked for).

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| C1 Barriers | 1 | test_barrier_kinds; shell and bar in shots/ | tests pass | none | owner play |
| C2 Blackfire kit | 1-2 | test_blackfire_* (grip timing fixed in pass 2) | tests pass | Unfallen not captured live | capture |
| C3 Thyrandael kit | 1 | test_thyrandael_* | tests pass | False Judgement not captured live | capture |
| C4 Bots and chat | 1 | logs/kit_casts1.log (every skill), bot_game_a/b.txt | self-check | bot vs human strength unmeasured | owner play |
| C5 Visuals, UI | 1 | shots/, ui/select_*.png, icons.png | self-check | no critic | critic |
| C6 Bodies | builder | bodies/report, collision 0 cm, joins 0 / 2 | builder gates | blade vs wings not checked; Thyrandael 2 joins | owner's eye |
| C7 Forums tab, matchmaking | 1 | ui/forums_tab.png | self-check | none | owner play |
| X Integration | 1 | suite 340/2 (2 flaky ladder tests), check.sh Names OK, export, export/exe_match.png | PASS with flaky tests | flaky career tests | seed them |
| X Integration | 2 | ladder tests seeded; suite 342/0 (logs/tests3.log) | PASS (gate) | none | none |
| M Fast matchmaking | 1 | mm_probe on the owner's ladder (3% fail, 1 max per queue, 8.8 s avg), test_matchmaker_failed_accept, ranked_probe | tests pass | none | owner play |

## Session 2026-10-21 b — Gancho, Lord Kaileh, Dracoxinia; own animations for every melee hero

Run: `work/lemondev/2026-10-21b-three-heroes/` (contract.md; hero sheet `docs/NEW_HEROES_22.md`). Interrupted once and
continued 2026-10-22. No commercial benchmark capture (gate UNVERIFIED); no blind critic.

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| B1 Bodies, weapons | 1 | bodies/*_sheet.png, weapons/weapons_sheet.png, collide_fix2 | builder gates | none (Dracoxinia has no tail, by design) | owner's eye |
| K1 Kits | 1-2 | test_gancho_*, test_kaileh_*, test_dracoxinia_* | tests pass | owner swapped W/E (Dragon Leap, Dragon Hide) | owner play |
| A1 Own animations | 1-2 | test_mocap_clips (8 late attacks trimmed), joins 5/115 over (13.3 deg) | PASS with joins over | 5 joins over the limit | owner's eye |
| V1 Effects, bots, chat | 1 | shots/, duel logs | self-check | no critic | owner play |
| I Integration | 1 | suite 352/0, check.sh Names OK, export, pck cold start | PASS (gate) | exe menus not clicked | owner play |


## Session 2026-10-22 — missing skill/state art and Game Icons skill

Run `work/lemondev/2026-10-22-icons/`. User explicitly reversed the old Death Order choice ("No! Change the Death Order"); new bounded pass authorized.34 generated images:27 new skills,5 sword states,Giant Swing,Death Order. All items retained.259 total active painted identities across305 routes.

| Component | Pass | Evidence | Verdict | Largest gap / next |
|---|---|---|---|---|
| Live inventory | 1 | audit.md, before/ and after/audit.json | coverage PASS | 33 missing PNGs filled; Giant Swing semantic replacement |
| Three artwork sheets | 1 | review/review.md, raw A/B galleries | PASS vs project baseline | Blue Sword fine roots less clear at32px; no mandatory failure |
| State routing | 1 | gallery logs, packed_probe | 2079/0 PASS | HUD inset and BuffBar use new sword images |
| Game Icons skill | 1 | skill-test/report.md, validator outputs | dry workflow PASS | no blocked/misrouted instruction; production workflow exercised by root |
| Packaging helper | 1 | helper-test fixture, --check | PASS | later revisions and changed pixels checked |
| Integration | 1 | tests.log352/0, ui/, export, packed probe, cold logs | IMPLEMENTED — UNVERIFIED globally | old teardown warnings; no new commercial/performance evidence |

## Session 2026-10-22 b — the official border on every new icon

Run `work/lemondev/2026-10-22-icons/border/`. Owner asked to apply the official border, build and push.

| Component | Pass | Evidence | Verdict | Largest gap / next |
|---|---|---|---|---|
| Border coverage | 1 | game_setup.png, exe_match.png, packed_probe.log 2079/0 | PASS (self-check) | Game Setup ultimate and the dragged item now framed; buff bar left out by design |
| Integration | 1 | tests.log 352/0, check.sh Names OK, export exit 0, exe cold start | PASS (gate) | no critic; drag ghost not captured live |

## Session 2026-10-22 c — deep QA, frame rate, build

Run `work/lemondev/2026-10-22c-qa-perf/` (contract.md, logs, bench). Interrupted once (session limit) and continued.
Three fresh-context auditors (kits, rules, interface); no commercial benchmark capture; no blind visual critic.

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| L Leftovers | 1 | ledger read; nothing open blocked | PASS | none | none |
| Q1 Hero kits | 1 | 12 confirmed fixed; test_qa_kits_*, test_qa_war_banner_* | tests pass | 7 plausible left (listed in HANDOFF) | owner play |
| Q2 Core rules | 1 | 11 confirmed + 3 deviations fixed; test_qa_* | tests pass | Midas XP, level 30 XP unconfirmed | research |
| Q3 Interface | 1 | 16 confirmed fixed | self-check | no live click-through | probe |
| Q4 Runtime errors | 1 | kc2_a/b/c: 3 x 25 min, all 22 heroes, 0 SCRIPT ERROR | PASS (gate) | none | none |
| P Frame rate | 1-2 | bench/a_q*, a_qbase*, lane_*, b_q*: A 21.6 -> 18.4-19.3 ms, lane 15.0 -> 13.1 | improved, targets not met | main thread bound (script, flush, draw) | render thread, draw calls |
| X Integration | 1-2 | snapshot regression fixed (metadata); suite 361/0 (logs/tests_fix2.log) | see run handoff | none | owner play |

## Session 2026-10-23 — skill crash, hit effects, hand-made animations, bot knowledge, build

Run `work/lemondev/2026-10-23-crash-anim-ai/` (contract.md). No commercial benchmark capture; no blind critic.

| Component | Pass | Evidence | Verdict | Primary gap | Next |
|---|---|---|---|---|---|
| C Skill crashes | 1-2 | logs/storm_*.txt, storm2_*, storm3_mix: 0 SCRIPT ERROR after fix; test fails on old code | PASS (gate) | none in debug | exe storm (X) |
| F Hit effects | 1-3 | fx/direct5, fx/swing1, fx/after2 | self-check | no critic; sizes tuned by eye | owner play |
| A1 Dracoxinia clips | 1-8 | collide 0 cm, joins 1 at 12.1 deg, slide 0.97x, audit 6/10 clean | IMPLEMENTED, near gate | cuts' wrists 84-105 deg a few frames | DP weights / poses |
| A2 Emelrich clips | 1-6 | idle/run/cast/hit clean everywhere | PASS for 4 clips | two-handed cuts fail wrist audit: not used | redesign with lean |
| B Bot knowledge | 1-2 | botgame_chat2.txt, llm_prompt.txt, test_bot_knowledge | tests pass | LLM output itself not sampled (no key used) | owner play |
| X Integration | 1 | suite 365/0, check.sh Names OK, export exit 0, exe storm 0 errors | PASS (gate) | bench B not re-run after the fx buffer fix | owner play |
