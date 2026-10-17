# Run 2026-10-17e: hero models from owner-picked downloads

Owner request (2026-10-17): the five new heroes (hero_ideas.txt) get researched, non-common free models with own
textures, effects and animations; the owner later added new bodies for Azrin, Ezee and Caziel.
Licence: CC BY 4.0 approved by the owner (credit every artist in docs/ASSET_CREDITS.md and in-game credits).
Downloads: work/downloads/sf_heroes/ (gitignored).

## Assignments (owner's words win)
| Hero | Source download | Notes |
|---|---|---|
| Feran Mock | assassin_character_model.glb (glenfernandes66) | hood off, jester hat and half-smile mask, red/black patched coat |
| Ser Emelrich | bulky_knight.glb (OptiCube) | owner's choice over Andywoodhead's knight; own greatsword (heavy_greatsword.glb) |
| Ezee | fallen-paladin-in-corrupted-black-plate-armor.zip (s8819296, Tripo AI mesh) | owner: "fallen paladin is for Ezee" |
| Azrin | azrin.zip (s8819296, Tripo AI mesh) | owner: recolour red + black; float animations must fit (lean forward when gliding) |
| Caziel | caziel.zip | owner: "use the newly downloaded caziel for Caziel" |
| Ghorman | northern_outsider.glb (Splodeman), druid_clothes.glb (aptyphawk22) | plus Beast Form |
| Burak, Airah | not downloaded yet | |
| (none) | blackfire_the_unfallen.zip | owner: future hero, do not touch |
| (none) | thyrandael_the_forsaken_seraph.zip | not assigned; owner said Emelrich has bulky_knight |

## Acceptance
* Each body on the 24-bone hero skeleton (tools/blender/hero_body.py) plays every hero clip without crumpled
  shoulders, ballooning cloth or weapons through the body (anim audit + renders of idle, run, attack, cast).
* Own textures (recolour/repaint passes), own effects, signature clips where the kit needs them.
* Readable at the game camera; within budget (about 30k triangles, 2k textures per hero).
* Names checker passes; credits list every artist.
