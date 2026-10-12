# Naming rule (mandatory)

This rule covers every name and every piece of text a player can see: heroes, abilities, items, units, buildings,
teams, places, menus, buttons, tabs, settings, tooltips, loading text, tips, errors, kill messages, outfit pieces,
presets, files the player sees (the exe), and new code identifiers. Read it before naming anything. It overrides any
habit of "flavourful" or "epic" naming.

## The test

Say the name out loud. It passes only if all of these are true:

1. **Ordinary words.** Every word is a normal English word a player already knows, used in its normal sense.
2. **Says what it is or does.** A player can guess the thing from the name: *Bracer, Mini-Axe, Vegan Picker, Jump
   Knife, Spell Shield, Healing Paste, Footman, Wolf, Options, Sell*.
3. **Short.** One to three words. Menu items and buttons: one or two words.
4. **Sounds like a person named it,** not a fantasy-name generator. Old DotA and Warcraft III names are the model:
   *Pudge, Sniper, Tiny, Axe, Lion, Bracer, Desolator, Black King Bar, Battle Fury, Magic Wand*. Simple, but they
   still sound good.

If two names both pass, pick the plainer one.

## Banned

* **Invented compound words** that glue two "cool" words together: Galewarden, Emberwarden, Crownfall, Ashenfall,
  Deepwarden, Gloomthread, Prismkeeper, Vaultpath, Stormstrider, Duskrunner, Sunforged, Riftwalker, Galeblade.
* **Lore titles and "X of the Y" names:** "the Crimson Huntress", "Bracers of Might", "Ring of Renewal", "Blade of
  Swiftness", "Shard of the Fallen Sun".
* **Fake-epic suffixes:** -warden, -fall, -forged, -bound, -born, -keeper, -caller, -walker, -strider, -weaver, -bane,
  -shard, -heart, -song, -fang, -guard, -wright, -mantle (when glued onto another word).
* **These words, anywhere:** aether, ashen, ember, gale, crown, gloom, rune, runic, sigil, veil, rift, void, astral,
  celestial, arcane, mystic, eternal, sanctum, bastion, spire, aegis, hallow, hallowed, dread, umbral, nether, ether,
  eclipse, oath, sworn, wraith, whisper, twilight, starlight, moonlit, sunforged, primal, fabled, abyssal, empyrean,
  radiant, verdant.
* **Copied Dota names** for heroes, abilities and items. Rename to a plain name that says what it does
  (Black King Bar → Spell Shield, Blink Dagger → Jump Knife).
* **Flavour text in UI.** Menus, buttons, tabs, settings, loading text and errors use plain product language:
  Play, Options, Audio, Video, Game, Controls, Shop, Sell, Back, Resume, Quit, "Loading terrain", "Not enough mana".
  Not "Shaping the land", "Summoning the heroes", "Sanctum of Settings".

## Names the owner chose

The owner's own names are never changed by an agent, even when they break this rule. Keep this list current:

* Game title: **Warriors of Aether**
* Teams: **Ancient Light** and **Black Sun**
* Heroes: **Blood Ranger**, **Ezee the Dark Paladin**, **Sludge**
* Abilities: Blood Ranger's **Burst Shot**, **Gale Impact**, **Masterful Archery**, **Blood Ranger**; Ezee's
  **Dark Stomp**, **Leap Strike**, **Tainted Touch**, **Unholy Might**
* Items: **Mini-Axe**, **Vegan Picker**
* Bot: **Bot Gerald**

When the owner gives a new name, add it here in the same change.

## Process

1. Before naming, read this file.
2. Write the plain name first. Do not "upgrade" it to sound cooler.
3. Run `python tools/check_names.py` (also run by `sh tools/check.sh`). It scans player-visible strings for the banned
   words and patterns. A failure blocks the change. The allow-list in that script holds only the owner's names above.
4. List every new name in the handoff (`docs/HANDOFF.md`) so the owner can veto it.

## Examples

| Bad | Good |
|---|---|
| Aether Core | Throne |
| Wraith Sigil | Swift Band |
| Ironwood Twig | Tree Twig |
| Sunguard Footman | Footman |
| Magma Colossus | Lava Golem |
| Deepwarden Coat | Sea Blue Coat |
| Glyph of Fortification | Fortify |
| Clear Mind Draught | Mana Potion |
| "Summoning the heroes" | "Loading heroes" |
| Settings Sanctum | Options |
