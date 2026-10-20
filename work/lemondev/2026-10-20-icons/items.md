# Item icon inventory

129 non-recipe items + 47 recipes = 176 database records. 16 explicit state entries. 134 unique art entries on 9 sheets of at most 16.

Audit only. Names/effects from actual implementation. No game/UI changes and no new player-facing names.

## Sources

- `src/sim/sim_data.gd:_build_items`
- `src/ui/ui_kit.gd:ITEM_ICONS,item_icon,held_item_icon,item_icon_path`
- `src/ui/hud.gd:_item_icon,ITEM_TEXT,PASSIVE_TEXT,item_tip`
- `src/sim/sim_items.gd`
- `src/sim/sim_orbs.gd:take,POWER,NAMES`
- `tools/item_icons.py:make_icons`

## Scope and state handling

- No neutral item tiers, neutral item drops, or neutral-specific item definitions exist in SimData._build_items; neutral creeps/abilities are separate.
- Every recipe ID is a database record generated from positive recipe_cost; all use quest_letter.svg. Generate one shared recipe asset.
- Teleport Scroll is included although it currently references ui/teleport.svg.
- Current baseline lookup tries items/gen/<id>.svg, then ITEM_ICONS, then items/charm. Recipes bypass lookup and use quest_letter.svg.
- Switch Boots state keys are actual UiKit selectors, not separate database item IDs. Flask state keys are audit selectors, not database IDs.
- Flask can store all nine orb kinds, including wisdom, because SimOrbs.take stores any kind. It shows one base image plus a dynamic colored dot.
- Cooldown shading, backpack dimming, lock padlock, charge numbers and orb dots are UI overlays; do not generate duplicate item art for them.
- Empty Flask is additional requested art; current UiKit has no empty state branch. Filled 1/2/3 charge states share base art and a number.
- Legacy unreferenced assets are not gameplay items. net_staff_placeholder is an unused generator entry, not a database item.
- Source line numbers are from the original audit snapshot; concurrent parent changes may shift them.
- Nine semantic sheets contain 134 art entries. Empty cells remain blank; each sheet is at most 16 entries.

## Sheets

| Sheet | Group | Entries | Blank cells |
| --- | --- | ---: | ---: |
| items_01 | Consumables | 12 | 4 |
| items_02 | Attributes | 15 | 1 |
| items_03 | Weapons | 14 | 2 |
| items_04 | Armor and healing | 16 | 0 |
| items_05 | Mana and movement | 15 | 1 |
| items_06 | Boots and support | 15 | 1 |
| items_07 | Weapons and spellbook | 15 | 1 |
| items_08 | Magic and control | 16 | 0 |
| items_09 | Advanced items | 16 | 0 |

## items_01 - Consumables

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `tp_scroll` / `tp_scroll` | Teleport Scroll | Consume one scroll to channel 3 s and teleport to an allied building. | Rolled parchment opening into a blue teleport circle. | `assets/ui/ui/teleport.svg` |
| 2 | `bottle` / `bottle` | Flask | Drink a charge: 110 health and 60 mana over 2.7 seconds (lost if an enemy hero hurts you). Refills to 3 charges at the fountain. Taking an orb while carrying it stores the orb (for up to 90 seconds); drinking lets it out. | Clear stoppered round glass flask filled with blue-green restorative liquid, health and mana glints. | `assets/ui/items/elixir_rejuvenation.svg` |
| 3 | `tango` / `tango` | Vegan Picker | Eat a tree to regenerate 7 health per second for 16 seconds (32 seconds on a planted tree). The tree is destroyed and grows back after 3 minutes. | Small handheld plant picker clasping a fresh leaf, green healing glow; show an implement and leaf rather than a generic status symbol. | `assets/ui/status/regen.svg` |
| 4 | `salve` / `salve` | Healing Paste | Regenerate 30 health per second for 13 seconds. Broken by damage from enemy heroes. | Open small pot of thick green healing paste with dab on lid. | `assets/ui/items/potion_health.svg` |
| 5 | `clarity` / `clarity` | Mana Potion | Regenerate 6 mana per second for 25 seconds. Broken by damage from enemy heroes. | Small corked blue mana potion with luminous liquid. | `assets/ui/items/potion_mana.svg` |
| 6 | `mango` / `mango` | Ripe Mango | +0.4 health/s; Restore 100 mana. | Ripe yellow-orange mango with green leaf and blue mana glint. | `assets/ui/status/vigor.svg` |
| 7 | `faerie_fire` / `faerie_fire` | Firefly Jar | +2 attack damage; Restore 85 health. | Clear jar containing luminous healing fireflies; unmistakable glass jar. | `assets/ui/items/aether_shard.svg` |
| 8 | `observer_ward` / `observer_ward` | Eye Ward | Plant an invisible ward that sees 1600 range for 6 minutes. | Wooden stake topped by a large watchful golden eye and sight halo. | `assets/ui/status/keen.svg` |
| 9 | `reveal_ward` / `reveal_ward` | Reveal Ward | Place invisible True Sight ward in 1050 radius for 420 s; no normal sight. | Distinct blue eye-topped stake with an outward reveal halo; differ from Eye Ward. | `assets/ui/status/spirit_ward.svg` |
| 10 | `reveal_dust` / `reveal_dust` | Reveal Dust | Reveal invisible enemies within 1050 of you for 12 seconds and slow them 20% while they are invisible (the effect stays 8 seconds after they leave). Invisible enemies there take 25 damage. | Open pouch spilling pale sparkling dust that outlines a faint hidden figure. | `assets/ui/items/mat_arcane_dust.svg` |
| 11 | `bottle_empty` / `bottle` | Flask (empty) | Cannot restore health or mana until refilled; can still store a picked orb. | Same clear stoppered glass Flask, visibly empty with no liquid; faint residual blue-green glow only. | `assets/ui/items/elixir_rejuvenation.svg` |
| 12 | `recipe` / `recipe_*` | Recipe scroll (shared) | Crafting paper shared by all recipe items. | Rolled parchment sheet with simple equipment sketch and wax seal; no readable lettering. | `assets/ui/items/quest_letter.svg` |

## items_02 - Attributes

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `branch` / `branch` | Tree Twig | +1 strength, +1 agility, +1 intelligence; Plant a tree within 400 range. It stands for 20 seconds. Consumes the twig. | Forked brown twig with two green leaves and exposed plantable end. | `assets/ui/items/wand_2.svg` |
| 2 | `slippers` / `slippers` | Slippers | +3 agility | Pair of soft green cloth slippers, light and supple. | `assets/ui/items/boots_cloth.svg` |
| 3 | `gauntlets` / `gauntlets` | Heavy Gloves | +3 strength | Pair of heavy iron gloves with red strength accent. | `assets/ui/items/gloves_plate.svg` |
| 4 | `mantle` / `mantle` | Thinking Cap | +3 intelligence | Soft blue thinking cap with subtle sparks. | `assets/ui/items/helm_hood.svg` |
| 5 | `circlet` / `circlet` | Headband | +2 strength, +2 agility, +2 intelligence | Simple circular metal headband and small neutral jewel, no royal crown. | `assets/ui/ui/crown.svg` |
| 6 | `boots_elves` / `boots_elves` | Elf Band | +6 agility | Slim green arm band with leaf detail; band rather than boots. | `assets/ui/items/boots_cloth_2.svg` |
| 7 | `belt_str` / `belt_str` | Heavy Belt | +6 strength | Broad leather belt with heavy iron buckle and red strength accent. | `assets/ui/items/charm.svg` |
| 8 | `robe` / `robe` | Wizard Robe | +6 intelligence | Draped blue wizard robe with clear cloth folds. | `assets/ui/items/armor_robe.svg` |
| 9 | `blade_alacrity` / `blade_alacrity` | Quick Blade | +10 agility | Light narrow green-tinted blade with a quick motion trail. | `assets/ui/items/aether_sword.svg` |
| 10 | `giant_axe` / `giant_axe` | Giant Axe | +10 strength | Large broad iron axe, heavy wood handle, red strength accent. | `assets/ui/items/axe_2.svg` |
| 11 | `wizard_staff` / `wizard_staff` | Wizard Staff | +10 intelligence | Tall wood staff with a blue gem head. | `assets/ui/items/staff.svg` |
| 12 | `gold_band` / `gold_band` | Gold Band | +4 strength, +4 agility, +4 intelligence | Broad gold head band with small red-green-blue stones. | `assets/ui/items/gen/gold_band.svg` |
| 13 | `wraith_band` / `wraith_band` | Swift Band | +5 agility, +2 strength, +2 intelligence, +6 attack speed, +1.75 armor | Slim gold wrist band with green inset stone and slight speed trail. | `assets/ui/items/gen/wraith_band.svg` |
| 14 | `tough_band` / `tough_band` | Tough Band | +5 strength, +2 agility, +2 intelligence, +50 health, +0.75 health/s | Broad iron wrist band with red stone and health glow. | `assets/ui/items/gen/tough_band.svg` |
| 15 | `smart_band` / `smart_band` | Smart Band | +5 intelligence, +2 strength, +2 agility, +3% maximum mana, +1 mana/s | Gold wrist band with blue stone and mana sparkle. | `assets/ui/items/gen/smart_band.svg` |

## items_03 - Weapons

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `blades_attack` / `blades_attack` | Fist Blades | +9 attack damage | Two short fist-mounted steel blades with visible hand grips. | `assets/ui/items/dagger_2.svg` |
| 2 | `broadsword` / `broadsword` | Long Sword | +15 attack damage | Long straight steel sword with leather grip. | `assets/ui/items/greatsword.svg` |
| 3 | `gloves` / `gloves` | Fast Gloves | +20 attack speed | Pair of fitted leather gloves with fast motion streaks. | `assets/ui/items/gloves_cloth.svg` |
| 4 | `quelling_blade` / `quelling_blade` | Mini-Axe | Chop down a tree within 350 range; it grows back after 3 minutes. Passive: bonus attack damage against creeps.; Creep damage +8 melee / +4 ranged. | Compact wood-handled single-headed axe beside a cut twig. | `assets/ui/items/axe.svg` |
| 5 | `greatsword` / `greatsword` | Greatsword | +20 attack damage | Broad two-handed steel greatsword, substantial weight. | `assets/ui/items/greatsword_2.svg` |
| 6 | `steel_hammer` / `steel_hammer` | Steel Hammer | +24 attack damage | Heavy rectangular steel hammer on wood handle. | `assets/ui/items/mat_iron_shard.svg` |
| 7 | `spear` / `spear` | Spear | 25% attack proc: cannot miss and +60 magic damage. | Long wooden spear with a sharp steel point and piercing flash. | `assets/ui/items/spear.svg` |
| 8 | `rust_stone` / `rust_stone` | Rust Stone | Attacks lower armor by 2 for 3 s. | Rough rust-red stone shedding flakes onto corroding metal. | `assets/ui/status/armor_broken.svg` |
| 9 | `brass_knuckles` / `brass_knuckles` | Brass Knuckles | +35 attack speed | Four connected brass finger rings, unmistakable knuckle silhouette. | `assets/ui/items/gloves_plate_2.svg` |
| 10 | `huge_sword` / `huge_sword` | Huge Sword | +40 attack damage | Massive broad steel sword, visibly heavier than Greatsword. | `assets/ui/items/sword.svg` |
| 11 | `war_axe` / `war_axe` | War Axe | +25 strength | Massive double-edged red-iron axe, heavy haft, red strength gem. | `assets/ui/items/gen/war_axe.svg` |
| 12 | `relic` / `relic` | Relic | +55 attack damage | Old ornate gold weapon fragment with a sharp white damage gleam. | `assets/ui/items/gen/relic.svg` |
| 13 | `feather` / `feather` | Feather | +25 agility | Large green feather with gold quill and agile trail. | `assets/ui/items/gen/feather.svg` |
| 14 | `swift_stone` / `swift_stone` | Swift Stone | +60 attack speed | Green faceted stone with rapid sweeping motion trails. | `assets/ui/items/gen/swift_stone.svg` |

## items_04 - Armor and healing

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `ring_protection` / `ring_protection` | Armor Ring | +2 armor | Thick iron ring with protective metal sheen. | `assets/ui/items/ring.svg` |
| 2 | `chainmail` / `chainmail` | Chain Shirt | +4 armor | Short shirt made of visible linked steel rings. | `assets/ui/items/armor_robe_2.svg` |
| 3 | `plate_vest` / `plate_vest` | Plate Vest | +7 armor | Plain steel torso plate vest with straps. | `assets/ui/items/armor_plate.svg` |
| 4 | `plate_armor` / `plate_armor` | Plate Armor | +10 armor | Heavy full steel breastplate with layered shoulders, stronger than Plate Vest. | `assets/ui/items/gen/plate_armor.svg` |
| 5 | `iron_helm` / `iron_helm` | Iron Helm | +4 armor, +4 health/s | Dark iron helmet with clear face opening and green regeneration gleam. | `assets/ui/items/gen/iron_helm.svg` |
| 6 | `ring_regen` / `ring_regen` | Healing Ring | +1.25 health/s | Small gold ring with green healing gem. | `assets/ui/items/ring_3.svg` |
| 7 | `big_healing_ring` / `big_healing_ring` | Big Healing Ring | +4.5 health/s | Large gold ring with large green healing stone, clearly larger than Healing Ring. | `assets/ui/items/ring_2.svg` |
| 8 | `troll_ring` / `troll_ring` | Troll Ring | +12 health/s | Thick worn green-gem ring with strong regeneration wisps. | `assets/ui/items/gen/troll_ring.svg` |
| 9 | `health_crystal` / `health_crystal` | Health Crystal | +250 health | Red faceted crystal with warm health glow. | `assets/ui/items/mat_ember_core.svg` |
| 10 | `fur_hat` / `fur_hat` | Fur Hat | +125 health | Brown fur cap with thick fur trim and red health accent. | `assets/ui/items/helm_hood_3.svg` |
| 11 | `shawl` / `shawl` | Scarf | +10% magic resistance | Wrapped violet wool scarf with faint protective ring. | `assets/ui/items/gen/shawl.svg` |
| 12 | `cloak` / `cloak` | Spell Cloak | +18% magic resistance | Full violet cloak with protective magic sheen and opaque cloth. | `assets/ui/items/gen/cloak.svg` |
| 13 | `lifesteal` / `lifesteal` | Leech Mask | +18% lifesteal | Dark crimson face mask with small fangs and blood droplets. | `assets/ui/items/amulet_2.svg` |
| 14 | `sneak_charm` / `sneak_charm` | Sneak Charm | No standalone stats or active; crafting component only. | Small dark pendant half disappearing into translucent wisps; component only, no standalone active implied. | `assets/ui/items/amulet.svg` |
| 15 | `dodge_charm` / `dodge_charm` | Dodge Charm | +15% evasion | Hanging charm with displaced green afterimage evading a strike. | `assets/ui/items/charm_2.svg` |
| 16 | `giant_heart` / `giant_heart` | Giant Heart | +40 strength, +1% maximum health regeneration/s, +1.5% missing health regeneration/s; Regenerates 1% of your maximum health and 1.5% of your missing health every second. | Large red anatomical heart with pulse light and regeneration trail. | `assets/ui/items/gen/giant_heart.svg` |

## items_05 - Mana and movement

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `sobi_mask` / `sobi_mask` | Calm Mask | +0.7 mana/s | Blue calm face mask with closed peaceful eyes, soft mana glow. | `assets/ui/items/amulet_3.svg` |
| 2 | `mana_stone` / `mana_stone` | Mana Stone | +1.75 mana/s | Rough blue stone with steady blue mana glow. | `assets/ui/items/frost_crystal.svg` |
| 3 | `big_gem` / `big_gem` | Big Gem | +175 health, +175 mana | Large red-blue faceted gem with equal health and mana colors. | `assets/ui/items/storm_essence.svg` |
| 4 | `pointy_hat` / `pointy_hat` | Pointy Hat | +125 mana | Small blue pointed cloth hat with mana gem. | `assets/ui/items/helm_hood_2.svg` |
| 5 | `long_staff` / `long_staff` | Long Staff | +25 intelligence | Long slender blue-gem staff emphasizing shaft and intelligence glow. | `assets/ui/items/staff_3.svg` |
| 6 | `mana_tiara` / `mana_tiara` | Mana Tiara | +6 mana/s | Fine silver-blue tiara with blue mana stones, distinct from Headband. | `assets/ui/items/quest_crown_fragment.svg` |
| 7 | `mana_gem` / `mana_gem` | Mana Gem | +250 mana | Large clear blue eight-sided gem filled with mana light. | `assets/ui/items/gen/mana_gem.svg` |
| 8 | `wide_stone` / `wide_stone` | Wide Stone | +40 spell area | Broad violet-gray stone releasing expanding area circles. | `assets/ui/items/gen/wide_stone.svg` |
| 9 | `magic_stick` / `magic_stick` | Zap Stick | Restore 15 health and mana per charge. Charges when enemy heroes cast spells nearby.; 10 maximum charges. | Plain short wooden stick gathering stored sparks at tip. | `assets/ui/items/wand.svg` |
| 10 | `magic_wand` / `magic_wand` | Zap Wand | +3 strength, +3 agility, +3 intelligence; Restore 15 health and mana per charge. Charges when enemy heroes cast spells nearby.; 20 maximum charges. | Wooden wand with violet head and many stored bright sparks. | `assets/ui/items/gen/magic_wand.svg` |
| 11 | `mana_ring` / `mana_ring` | Mana Ring | +0.25 mana/s; Aura: +1 mana/s in 1200. | Gold blue-gem ring sending concentric blue mana waves. | `assets/ui/items/gen/mana_ring.svg` |
| 12 | `leaf_hat` / `leaf_hat` | Leaf Hat | +0.5 health/s; Aura: +2 health/s in 1200. | Green hat decorated with leaves, outward green healing waves. | `assets/ui/items/gen/leaf_hat.svg` |
| 13 | `steady_ring` / `steady_ring` | Steady Ring | +5.5 health/s, +2.25 mana/s | Two linked gold rings carrying red and blue gems for dual regeneration. | `assets/ui/items/gen/steady_ring.svg` |
| 14 | `boots` / `boots` | Running Shoes | +45 boot movement speed | Brown leather running shoes with short movement trail. | `assets/ui/items/gen/boots.svg` |
| 15 | `speed_ribbon` / `speed_ribbon` | Speed Ribbon | +15 movement speed | Long teal ribbon trailing in a fast curve. | `assets/ui/items/gen/speed_ribbon.svg` |

## items_06 - Boots and support

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `power_treads` / `power_treads` | Switch Boots | +25 attack speed; Melee: +55 boot movement speed; Ranged: +45 boot movement speed; Switch the bonus between strength, intelligence and agility.; +10 chosen attribute. | Brown boot surrounded by red, blue, green gems and curved switching arrows. | `assets/ui/items/gen/power_treads.svg` |
| 2 | `slip_boots` / `slip_boots` | Slip Boots | +50 boot movement speed, +4 armor; Melee: +18 attack damage; Ranged: +12 attack damage; For 3 seconds, walk through units and move 20% faster (10% for ranged heroes). 8 second cooldown. | Light leather boot with cyan translucent afterimages passing through faint figure. | `assets/ui/items/gen/slip_boots.svg` |
| 3 | `mana_boots` / `mana_boots` | Mana Boots | +45 boot movement speed, +0.25 mana/s, +125 mana; Restore 150 mana to yourself and allies within 1200. 55 second cooldown.; Aura: +1 mana/s in 1200. | Blue boot releasing outward blue mana pulse. | `assets/ui/items/gen/mana_boots.svg` |
| 4 | `travel_boots` / `travel_boots` | Travel Boots | +90 boot movement speed; Teleport without a scroll (Teleport key or the Teleport slot) to any allied building or creep. 40 second cooldown. | Golden winged boots over blue teleport circle. | `assets/ui/items/gen/travel_boots.svg` |
| 5 | `guard_boots` / `guard_boots` | Guard Boots | +50 boot movement speed, +5 armor, +150 mana, +1 mana/s; Mend: heal yourself and allies within 1200 for 325 health and 200 mana, and remove your own debuffs (a basic dispel). 45 second cooldown. Aura: +2.5 health regen (+17 below 25% health) and +1.5 mana regen.; Allied aura: +2.5 health/s, +1.5 mana/s in 1200. Below 25% health: +17 health/s, +1.5 mana/s. | Heavy iron boots, gold trim, green healing cross and healing-mana aura. | `assets/ui/items/gen/guard_boots.svg` |
| 6 | `medic_kit` / `medic_kit` | Medic Kit | +5 armor; Heal yourself and allies within 1200 for 250. Costs 100 mana, 50 second cooldown.; Aura: +2.5 health/s in 1200. | Bronze medallion with green cross and healing pulse; preserve established medallion representation. | `assets/ui/items/gen/medic_kit.svg` |
| 7 | `small_shield` / `small_shield` | Small Shield | +1 armor; Allied aura: +2 armor in 1200. | Small round iron shield, bronze rim, outward protective aura. | `assets/ui/items/gen/small_shield.svg` |
| 8 | `block_shield` / `block_shield` | Block Shield | +250 health, +4.5 health/s; 60% chance to block 50 attack damage (25 ranged). | Solid broad iron shield with gold rim stopping a blow. | `assets/ui/items/gen/block_shield.svg` |
| 9 | `team_shield` / `team_shield` | Team Shield | +250 health, +12 health/s, +6 armor; Guard: for 7 seconds you and allies within 1200 block 70 damage (+2% of your max health) from every attack. Costs 75 mana, 40 second cooldown.; 60% chance to block 75 attack damage (50 ranged). | Large red shield backed by two smaller allied shields and shared defense light. | `assets/ui/items/gen/team_shield.svg` |
| 10 | `war_drum` / `war_drum` | War Drum | +8 strength; Endurance: you and allies within 1200 get +35 attack speed and 13% more speed for 6 seconds. 45 second cooldown. Aura: +15 movement speed and +2.5 health regen.; Allied aura: +15 movement speed, +2.5 health/s in 1200. | Red wood hand drum with pale skin and gold trim, circular rhythm waves. | `assets/ui/items/gen/war_drum.svg` |
| 11 | `gold_glove` / `gold_glove` | Gold Glove | +40 attack speed; Kill an enemy creep (not an ancient) within 600 and gain 160 gold. Two charges, one comes back every 90 seconds. | Gold glove lifting several gold coins in its palm. | `assets/ui/items/gen/gold_glove.svg` |
| 12 | `leech_totem` / `leech_totem` | Leech Totem | +1 armor, +0.75 mana/s; Allied aura: +2 armor, +1 mana/s, +20% lifesteal, +18% base attack damage in 1200. Owner only receives +2 armor, +1 mana/s. Creeps receive +2 armor, +1 mana/s, +12% lifesteal, +18% base attack damage. | Wooden skull-topped totem inside red lifesteal aura. | `assets/ui/items/gen/leech_totem.svg` |
| 13 | `power_treads_str` / `power_treads` | Switch Boots (Strength) | +10 strength; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | Red boot with matching gem; small fist detail. | `assets/ui/items/gen/power_treads_str.svg` |
| 14 | `power_treads_int` / `power_treads` | Switch Boots (Intelligence) | +10 intelligence; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | Blue boot with matching gem; blue sparks. | `assets/ui/items/gen/power_treads_int.svg` |
| 15 | `power_treads_agi` / `power_treads` | Switch Boots (Agility) | +10 agility; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | Green boot with matching gem; feather and fast trail. | `assets/ui/items/gen/power_treads_agi.svg` |

## items_07 - Weapons and spellbook

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `heavy_sword` / `heavy_sword` | Kugmo | +16 strength, +25% slow resistance, +12% healing amplification | Heavy crimson sword with gold hilt and red health gem. | `assets/ui/items/gen/heavy_sword.svg` |
| 2 | `yasha` / `yasha` | Igit | +16 agility, +15 attack speed, +10% movement speed | Slim curved green blade with gold grip and speed streaks. | `assets/ui/items/gen/yasha.svg` |
| 3 | `spell_sword` / `spell_sword` | Atuli | +16 intelligence, +10% magic damage, +20% mana regeneration amplification | Open blue spellbook with bright burst above; Atuli is a book despite internal id. | `assets/ui/items/gen/spell_sword.svg` |
| 4 | `twin_swords` / `twin_swords` | Kugmo and Igit | +16 strength, +16 agility, +20 attack speed, +12% movement speed, +16% status resistance, +16% healing amplification, +30% slow resistance | Crossed heavy crimson sword and slim curved green blade. | `assets/ui/items/gen/twin_swords.svg` |
| 5 | `kugmo_atuli` / `kugmo_atuli` | Kugmo and Atuli | +16 strength, +16 intelligence, +25% slow resistance, +16% healing amplification, +12% magic damage, +30% mana regeneration amplification, +25% mana cost reduction | Heavy crimson sword crossing open blue spellbook. | `assets/ui/items/gen/kugmo_atuli.svg` |
| 6 | `igit_atuli` / `igit_atuli` | Igit and Atuli | +16 agility, +16 intelligence, +20 attack speed, +12% movement speed, +12% magic damage, +30% mana regeneration amplification, +25% cast speed | Slim curved green blade crossing open blue spellbook. | `assets/ui/items/gen/igit_atuli.svg` |
| 7 | `dragon_lance` / `dragon_lance` | Long Spear | +15 agility, +10 strength, +130 ranged attack range | Long steel-tipped wood spear with extended forward reach trail. | `assets/ui/items/gen/dragon_lance.svg` |
| 8 | `battle_staff` / `battle_staff` | Battle Staff | +10 intelligence, +35 attack speed, +1.25 mana/s | Black staff with violet orb and gold fittings, short attack-speed streaks. | `assets/ui/items/gen/battle_staff.svg` |
| 9 | `crit_sword` / `crit_sword` | Crit Sword | +32 attack damage; 30% attack chance for 160% critical damage. | Steel sword with gold hilt and sharp red impact flash. | `assets/ui/items/gen/crit_sword.svg` |
| 10 | `crit_bow` / `crit_bow` | Crit Bow | +88 attack damage; 30% attack chance for 225% critical damage. | Dark recurved bow with taut string and strong red-gold impact flash. | `assets/ui/items/gen/crit_bow.svg` |
| 11 | `armor_breaker` / `armor_breaker` | Armor Breaker | +55 attack damage; Attacks lower armor by 6 for 7 s. Gains +2 damage per kill/+1 per assist, capped +30. | Dark heavy axe striking cracked steel armor; established representation is an axe. | `assets/ui/items/gen/armor_breaker.svg` |
| 12 | `cleave_axe` / `cleave_axe` | Cleave Axe | +50 attack damage, +7.5 health/s, +2.75 mana/s; Chop down a tree within 350 range; it grows back after 3 minutes. Passive: bonus attack damage against creeps.; Creep damage +10 melee / +5 ranged.; Melee heroes: attacks also hit enemies in front for 60% of the damage (40% to creeps). | Large double-headed steel axe with broad curved sweep trail. | `assets/ui/items/gen/cleave_axe.svg` |
| 13 | `leech_blade` / `leech_blade` | Leech Blade | +25 strength, +25 attack damage, +25% lifesteal; Blood Rage: +145% lifesteal for 6 seconds. 40 second cooldown. | Jagged dark-red blade, red gem, blood droplets flowing toward grip. | `assets/ui/items/gen/leech_blade.svg` |
| 14 | `moth_blade` / `moth_blade` | Moth Blade | +30 agility, +35% evasion, +20 attack speed, +30 attack damage | Slim steel blade between green-cyan moth wings. | `assets/ui/items/gen/moth_blade.svg` |
| 15 | `mask_of_madness` / `mask_of_madness` | Frenzy Mask | +20 attack damage, +22% lifesteal; Frenzy: +100 attack speed and +6% movement speed (+12% for melee heroes), but -7 armor for 6 seconds. Costs 25 mana. | Angular red face mask, aggressive mouth, fast attack streaks. | `assets/ui/items/gen/mask_of_madness.svg` |

## items_08 - Magic and control

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `jump_knife` / `jump_knife` | Jump Knife | Teleport to a point up to 1200 away (a farther point jumps 960 toward it). Disabled for 3 seconds after taking damage from an enemy hero, a unit an enemy hero controls or the enemy fountain. 15 second cooldown. | Short steel knife with violet grip, displaced afterimage and small teleport ring. | `assets/ui/items/gen/jump_knife.svg` |
| 2 | `crash_knife` / `crash_knife` | Crash Knife | +25 strength; Teleport to a point up to 1200 away (a farther point jumps 960 toward it). Disabled for 3 seconds after taking damage from an enemy hero, a unit an enemy hero controls or the enemy fountain. 15 second cooldown.; Landing in 800 radius deals 100 + 50% strength magic damage, 100% strength over 6 s, -50% speed/-50 attack speed for 6 s. | Red knife landing point-first on cracked ground with broad orange-white shock ring. | `assets/ui/items/gen/crash_knife.svg` |
| 3 | `push_staff` / `push_staff` | Push Staff | +10 intelligence, +175 health; Push a unit 600 forward the way it faces, cutting trees in its path. Range 550 on allies (or yourself), 850 on enemies. Costs 150 mana, 19 second cooldown. | Wood staff with cyan head projecting a forward force wave. | `assets/ui/items/gen/push_staff.svg` |
| 4 | `spell_shield` / `spell_shield` | Spell Shield | +10 strength, +24 attack damage; Immune to debuffs (stuns, slows, pushes) and 60% magic resistance; removes slows and silences. Lasts 9 seconds, one second less each use down to 7. Costs 50 mana, 95 second cooldown. | Gold shield inside a continuous gold protective magic sphere. | `assets/ui/items/gen/spell_shield.svg` |
| 5 | `glimmer_cape` / `glimmer_cape` | Fade Cape | +20% magic resistance | Violet cape with one side fading to sparks inside protective ring. | `assets/ui/items/gen/glimmer_cape.svg` |
| 6 | `sneak_blade` / `sneak_blade` | Sneak Blade | +25 attack damage, +35 attack speed; Turn invisible after 0.3 seconds for 17 seconds and move 20% faster. Attacking breaks it and the attack deals 175 extra damage. Costs 75 mana, 25 second cooldown. | Slim steel blade with violet translucent duplicate and fading edge. | `assets/ui/items/gen/sneak_blade.svg` |
| 7 | `break_blade` / `break_blade` | Break Blade | +70 attack damage, +35 attack speed; Invisible after 0.3 s, +20% speed for 17 s; opening attack +300 damage and disables target passives for 5 s. | Heavy steel blade, violet gem, fading duplicate and fractured effect ring. | `assets/ui/items/gen/break_blade.svg` |
| 8 | `stun_club` / `stun_club` | Stun Club | +30 attack damage, +10 strength; 25% melee/10% ranged bash: 100 damage and 1.2 s stun, 2.3 s cooldown. | Short heavy iron club, blunt head and circling yellow stun sparks. | `assets/ui/items/gen/stun_club.svg` |
| 9 | `stun_blade` / `stun_blade` | Stun Blade | +35 attack damage, +30 strength, +30% slow resistance, +16% healing amplification; Stun an enemy within 150 for 1.6 s, even through debuff immunity. 75 mana, 35 s cooldown.; 25% melee/10% ranged bash: 120 damage and 1.2 s stun, 2.3 s cooldown. | Broad crimson blade, black hilt and circling yellow stun sparks. | `assets/ui/items/gen/stun_blade.svg` |
| 10 | `sure_hit_staff` / `sure_hit_staff` | Sure Hit Staff | +50 attack damage, +50 attack speed; Melee: +50 melee attack range; 80% attack proc: cannot miss and +70 magic damage. | Gold-tipped wooden staff piercing a target circle with straight clean impact. | `assets/ui/items/gen/sure_hit_staff.svg` |
| 11 | `silence_staff` / `silence_staff` | Silence Staff | +35 attack speed, +20 attack damage, +2.5 mana/s, +12 intelligence; Silence an enemy within 900 for 5 seconds. When it ends, 30% of the damage it took meanwhile hits it again as magic damage. Costs 125 mana, 18 second cooldown. | Black staff with violet orb and small crossed-out mouth effect. | `assets/ui/items/gen/silence_staff.svg` |
| 12 | `root_staff` / `root_staff` | Root Staff | +12 intelligence, +275 health; Throw a root at an enemy within 1100: it cannot move for 2 seconds (it can still attack and cast; a root also stops teleports). Costs 100 mana, 18 second cooldown. | Wooden green-gem staff with living roots curling from its base. | `assets/ui/items/gen/root_staff.svg` |
| 13 | `halberd` / `halberd` | Halberd | +9 armor, +6.5 health/s, +25% evasion; Disarm an enemy within 750 for 3.5 seconds: it cannot attack. Only a strong dispel removes it. Costs 25 mana, 15 second cooldown. | Steel polearm with axe blade and spear point, severed attack trail for disarm. | `assets/ui/items/gen/halberd.svg` |
| 14 | `hex_staff` / `hex_staff` | Hex Staff | +30 intelligence, +8.5 mana/s; Turn an enemy within 800 into a sheep for 2.8 seconds: it cannot attack, cast or use items, and its base speed is 140. Costs 250 mana, 20 second cooldown. | Black-violet staff beside clearly recognizable little white sheep. | `assets/ui/items/gen/hex_staff.svg` |
| 15 | `net_staff` / `net_staff` | Net Staff | +450 health, +200 mana, +12 intelligence, +75 spell area; Throw nets at every enemy in a 325 area within 1100: each one hit cannot move for 2 seconds. Costs 150 mana, 18 second cooldown. | Wooden green-gem staff casting visible weighted rope net. | `assets/ui/items/gen/net_staff.svg` |
| 16 | `burning_cape` / `burning_cape` | Burning Cape | +55 attack damage, +25% evasion; Burns enemies within 650 for 60 magic damage per second (Fire). | Orange-red cape burning along hem inside heat ring. | `assets/ui/items/gen/burning_cape.svg` |

## items_09 - Advanced items

Order: left to right, then top to bottom.

| Cell | Exact icon key / item id | Existing name | Gameplay effect | Visual brief | Current icon |
| ---: | --- | --- | --- | --- | --- |
| 1 | `upgrade_staff` / `upgrade_staff` | Upgrade Staff | +10 strength, +10 agility, +10 intelligence, +175 health, +175 mana; Upgrades hero abilities while carried. | Tall gold staff, blue main gem, smaller red and green side gems. | `assets/ui/items/gen/upgrade_staff.svg` |
| 2 | `upgrade_gem` / `upgrade_gem` | Upgrade Gem | Consumed on purchase for permanent ability upgrades; available at 15:00. | Large blue six-sided gem with upward improvement light, distinct from Mana Gem. | `assets/ui/items/gen/upgrade_gem.svg` |
| 3 | `dagon` / `dagon` | Blast Rod | +6 strength, +6 agility, +6 intelligence, +200 health, +350 mana, +60 cast range; Blast one enemy within 640 for 400 magic damage. | Black rod with orange head firing red-hot beam; 1 bright level dots, progressively stronger beam. | `assets/ui/items/gen/dagon.svg` |
| 4 | `dagon_2` / `dagon_2` | Blast Rod 2 | +7 strength, +7 agility, +7 intelligence, +210 health, +375 mana, +90 cast range; Blast one enemy within 640 for 500 magic damage. | Black rod with orange head firing red-hot beam; 2 bright level dots, progressively stronger beam. | `assets/ui/items/gen/dagon_2.svg` |
| 5 | `dagon_3` / `dagon_3` | Blast Rod 3 | +8 strength, +8 agility, +8 intelligence, +220 health, +400 mana, +120 cast range; Blast one enemy within 640 for 600 magic damage. | Black rod with orange head firing red-hot beam; 3 bright level dots, progressively stronger beam. | `assets/ui/items/gen/dagon_3.svg` |
| 6 | `dagon_4` / `dagon_4` | Blast Rod 4 | +9 strength, +9 agility, +9 intelligence, +230 health, +425 mana, +150 cast range; Blast one enemy within 640 for 700 magic damage. | Black rod with orange head firing red-hot beam; 4 bright level dots, progressively stronger beam. | `assets/ui/items/gen/dagon_4.svg` |
| 7 | `dagon_5` / `dagon_5` | Blast Rod 5 | +10 strength, +10 agility, +10 intelligence, +240 health, +450 mana, +180 cast range; Blast one enemy within 640 for 800 magic damage. | Black rod with orange head firing red-hot beam; 5 bright level dots, progressively stronger beam. | `assets/ui/items/gen/dagon_5.svg` |
| 8 | `shock_hammer` / `shock_hammer` | Shock Hammer | +25 attack damage, +25 attack speed; 25% attack proc: 110 magic lightning to 4 enemies. | Iron hammer with blue-white lightning splitting toward several points. | `assets/ui/items/gen/shock_hammer.svg` |
| 9 | `storm_hammer` / `storm_hammer` | Storm Hammer | +25 attack damage, +90 attack speed; Static Charge: for 12 seconds an ally (or yourself) has a 20% chance when attacked to strike up to 4 enemies within 900 with lightning for 225 magic damage (the attacker first). Costs 50 mana, 35 second cooldown.; 25% attack proc: 180 magic lightning to 12 enemies. | Large blue hammer surrounded by many branching blue-white lightning bolts. | `assets/ui/items/gen/storm_hammer.svg` |
| 10 | `soul_gem` / `soul_gem` | Soul Gem | +425 health, +425 mana | Bound pair of red and blue gems with bright shared center. | `assets/ui/items/gen/soul_gem.svg` |
| 11 | `time_crystal` / `time_crystal` | Time Crystal | +450 health, +450 mana, +6 mana/s, +25% cooldown reduction; Your spells and items cool down 25% faster (several of these do not stack). | Tall cyan crystal with clear small clock-face light effect. | `assets/ui/items/gen/time_crystal.svg` |
| 12 | `refresh_stone` / `refresh_stone` | Refresh Stone | +14 health/s, +7 mana/s; Finish the cooldowns of all your spells at once (not items). Costs 325 mana, 180 second cooldown. | Round blue polished stone inside curved reset arrows, clock detail. | `assets/ui/items/gen/refresh_stone.svg` |
| 13 | `long_lens` / `long_lens` | Long Lens | +300 mana, +2.5 mana/s, +225 cast range; +225 cast range for spells and items. A second Long Lens adds half as much, a third a quarter. | Large blue convex lens in gold frame, projecting a long straight beam. | `assets/ui/items/gen/long_lens.svg` |
| 14 | `spike_armor` / `spike_armor` | Spike Armor | +15 attack damage, +7 armor; For 5.5 seconds, 85% of all damage you take is sent back to whoever dealt it. Costs 25 mana, 25 second cooldown.; Attackers take back 10 + 15% of the damage of their attacks. | Steel breastplate with long outward spikes and red reflected impact streak. | `assets/ui/items/gen/spike_armor.svg` |
| 15 | `battle_armor` / `battle_armor` | Battle Armor | +30 attack speed, +10 armor; Allied aura: +30 attack speed, +5 armor in 1200. Includes buildings.; Enemy aura: -5 armor in 1200. Includes buildings. | Gold-steel breastplate, gold allied aura, cracked enemy armor detail. | `assets/ui/items/gen/battle_armor.svg` |
| 16 | `frost_plate` / `frost_plate` | Frost Plate | +17 armor, +75 spell area; A ring of frost spreads out to 825: enemies it reaches take 225 magic damage and move 40% slower for 4 seconds. Costs 75 mana, 27 second cooldown.; Enemy aura: -40 attack speed in 1200. | Pale icy blue breastplate with snowflake relief releasing spreading frost wave. | `assets/ui/items/gen/frost_plate.svg` |

## Exact recipe records

All rows use shared recipe scroll art.

| Exact item id | Existing name | Makes | Cost |
| --- | --- | --- | ---: |
| `recipe_wraith_band` | Recipe: Swift Band | `wraith_band` | 210 |
| `recipe_tough_band` | Recipe: Tough Band | `tough_band` | 210 |
| `recipe_smart_band` | Recipe: Smart Band | `smart_band` | 210 |
| `recipe_magic_wand` | Recipe: Zap Wand | `magic_wand` | 150 |
| `recipe_mana_ring` | Recipe: Mana Ring | `mana_ring` | 250 |
| `recipe_leaf_hat` | Recipe: Leaf Hat | `leaf_hat` | 250 |
| `recipe_mana_boots` | Recipe: Mana Boots | `mana_boots` | 325 |
| `recipe_medic_kit` | Recipe: Medic Kit | `medic_kit` | 850 |
| `recipe_spike_armor` | Recipe: Spike Armor | `spike_armor` | 450 |
| `recipe_gold_glove` | Recipe: Gold Glove | `gold_glove` | 1750 |
| `recipe_push_staff` | Recipe: Push Staff | `push_staff` | 950 |
| `recipe_spell_shield` | Recipe: Spell Shield | `spell_shield` | 1450 |
| `recipe_cleave_axe` | Recipe: Cleave Axe | `cleave_axe` | 400 |
| `recipe_glimmer_cape` | Recipe: Fade Cape | `glimmer_cape` | 800 |
| `recipe_yasha` | Recipe: Igit | `yasha` | 650 |
| `recipe_dragon_lance` | Recipe: Long Spear | `dragon_lance` | 550 |
| `recipe_heavy_sword` | Recipe: Kugmo | `heavy_sword` | 650 |
| `recipe_spell_sword` | Recipe: Atuli | `spell_sword` | 650 |
| `recipe_crit_sword` | Recipe: Crit Sword | `crit_sword` | 200 |
| `recipe_crit_bow` | Recipe: Crit Bow | `crit_bow` | 1000 |
| `recipe_stun_club` | Recipe: Stun Club | `stun_club` | 825 |
| `recipe_stun_blade` | Recipe: Stun Blade | `stun_blade` | 1275 |
| `recipe_sure_hit_staff` | Recipe: Sure Hit Staff | `sure_hit_staff` | 900 |
| `recipe_silence_staff` | Recipe: Silence Staff | `silence_staff` | 300 |
| `recipe_root_staff` | Recipe: Root Staff | `root_staff` | 250 |
| `recipe_halberd` | Recipe: Halberd | `halberd` | 350 |
| `recipe_hex_staff` | Recipe: Hex Staff | `hex_staff` | 700 |
| `recipe_break_blade` | Recipe: Break Blade | `break_blade` | 250 |
| `recipe_travel_boots` | Recipe: Travel Boots | `travel_boots` | 2000 |
| `recipe_net_staff` | Recipe: Net Staff | `net_staff` | 300 |
| `recipe_storm_hammer` | Recipe: Storm Hammer | `storm_hammer` | 550 |
| `recipe_time_crystal` | Recipe: Time Crystal | `time_crystal` | 400 |
| `recipe_small_shield` | Recipe: Small Shield | `small_shield` | 250 |
| `recipe_battle_armor` | Recipe: Battle Armor | `battle_armor` | 1300 |
| `recipe_frost_plate` | Recipe: Frost Plate | `frost_plate` | 1250 |
| `recipe_giant_heart` | Recipe: Giant Heart | `giant_heart` | 800 |
| `recipe_refresh_stone` | Recipe: Refresh Stone | `refresh_stone` | 1600 |
| `recipe_guard_boots` | Recipe: Guard Boots | `guard_boots` | 1175 |
| `recipe_team_shield` | Recipe: Team Shield | `team_shield` | 1050 |
| `recipe_war_drum` | Recipe: War Drum | `war_drum` | 525 |
| `recipe_long_lens` | Recipe: Long Lens | `long_lens` | 775 |
| `recipe_crash_knife` | Recipe: Crash Knife | `crash_knife` | 1750 |
| `recipe_dagon` | Recipe: Blast Rod | `dagon` | 1100 |
| `recipe_dagon_2` | Recipe: Blast Rod 2 | `dagon_2` | 1100 |
| `recipe_dagon_3` | Recipe: Blast Rod 3 | `dagon_3` | 1100 |
| `recipe_dagon_4` | Recipe: Blast Rod 4 | `dagon_4` | 1100 |
| `recipe_dagon_5` | Recipe: Blast Rod 5 | `dagon_5` | 1100 |

## Explicit inventory states

State keys describe selectors; database ids remain power_treads or bottle.

| State key | Item | Condition | Gameplay effect | Current art / overlay | Generate art |
| --- | --- | --- | --- | --- | --- |
| `power_treads_str` | Switch Boots (Strength) | `{"attr": "str"}` | +10 strength; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | `assets/ui/items/gen/power_treads_str.svg`; UiKit selects mode SVG | Yes |
| `power_treads_int` | Switch Boots (Intelligence) | `{"attr": "int"}` | +10 intelligence; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | `assets/ui/items/gen/power_treads_int.svg`; UiKit selects mode SVG | Yes |
| `power_treads_agi` | Switch Boots (Agility) | `{"attr": "agi"}` | +10 agility; +25 attack speed; +55 melee/+45 ranged boot movement speed. Active cycles strength -> intelligence -> agility. | `assets/ui/items/gen/power_treads_agi.svg`; UiKit selects mode SVG | Yes |
| `bottle_empty` | Flask (empty) | `{"charges": 0, "orb": ""}` | Cannot restore health or mana until refilled; can still store a picked orb. | `assets/ui/items/elixir_rejuvenation.svg`; Charge number 0; renderer currently has no empty icon selector. | Yes |
| `bottle_charge_1` | Flask (1 charges) | `{"charges": 1, "orb": ""}` | 1 charge(s); each restores 110 health and 60 mana over 2.7 s. | `assets/ui/items/elixir_rejuvenation.svg`; Charge number 1 | No; reuse base |
| `bottle_charge_2` | Flask (2 charges) | `{"charges": 2, "orb": ""}` | 2 charge(s); each restores 110 health and 60 mana over 2.7 s. | `assets/ui/items/elixir_rejuvenation.svg`; Charge number 2 | No; reuse base |
| `bottle_charge_3` | Flask (3 charges) | `{"charges": 3, "orb": ""}` | 3 charge(s); each restores 110 health and 60 mana over 2.7 s. | `assets/ui/items/elixir_rejuvenation.svg`; Charge number 3 | No; reuse base |
| `bottle_orb_gold` | Flask (Gold Orb) | `{"orb": "gold"}` | Use releases stored orb: Team gains 40 + 6 per 4 minutes reliable gold. Expires in flask after 90 s. Pickup refills to at least 2 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_rejuvenation` | Flask (Rejuvenation Orb) | `{"orb": "rejuvenation"}` | Use releases stored orb: Restore 40 health and 80 mana. Expires in flask after 90 s. Pickup refills to at least 2 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_wisdom` | Flask (Wisdom Orb) | `{"orb": "wisdom"}` | Use releases stored orb: Grant 280 experience per 7 minutes to picker and lowest-experience teammate. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_speed` | Flask (Speed Orb) | `{"orb": "speed"}` | Use releases stored orb: 550 movement speed and ignores slows for 22 s + 3 s per cycle. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_damage` | Flask (Damage Orb) | `{"orb": "damage"}` | Use releases stored orb: +80% base damage and +15% spell damage for 45 s. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_stealth` | Flask (Stealth Orb) | `{"orb": "stealth"}` | Use releases stored orb: Invisibility after 2 s for 45 s and damage reduction while invisible. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_healing` | Flask (Healing Orb) | `{"orb": "healing"}` | Use releases stored orb: Restore 6% max health/mana per second for 30 s; reduced after hero damage. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_magic` | Flask (Magic Orb) | `{"orb": "magic"}` | Use releases stored orb: 25% shorter cooldowns and 30% lower mana costs for 50 s. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |
| `bottle_orb_shield` | Flask (Shield Orb) | `{"orb": "shield"}` | Use releases stored orb: Barrier equal to 50% max health for 75 s. Expires in flask after 90 s. Pickup refills to at least 3 charges. | `assets/ui/items/elixir_rejuvenation.svg`; OrbView.COLORS orb dot in upper right plus charge number. | No; reuse base |

## Verification

- Parsed every literal item definition; expanded all five Blast Rod levels and every positive-cost recipe.
- Every non-recipe item is represented once among the generation sheets.
- Sheet keys match all 134 unique art entries; no sheet exceeds 16.
- Current icon paths were checked through file existence and UiKit lookup precedence.
- Raw exact data fields retained in JSON for reviewing concise effect summaries.
- Names checker returned Names OK.
- Runtime/visual acceptance is outside this inventory-only assignment.
