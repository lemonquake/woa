# Research for the bot chat edit

Read on 2026-10-19. The user's examples are the style authority. The web sources below inform vocabulary, rhythm and context; they do not supply a bulk corpus to copy. Candidate entries are individually edited, with requested examples retained where applicable.

## Sources examined

1. **Lim, Vungthong & Trakulkasemsuk (2024), Trash-talking versus Toxicity: An Analysis of /All Chat Exchanges between Southeast Asian Players of an Online Competitive Game.** [Full paper, LEARN Journal 17(1), 816–856](https://doi.nrct.go.th/admin/doc/doc_649658.pdf). The authors analyze 26 actual SEA Dota 2 all-chat logs with timestamps, game events and translations. Methods on printed pp. 828–830 retain informal spellings. Excerpts on pp. 842–845 and 848 show brief reactions, replies to earlier boasts, sarcastic praise, laughter and punctuation. Their contextual analysis is the strongest evidence for writing a reaction to a specific play rather than a standalone comedy monologue. The sample is small and all-chat only; it cannot establish universal Filipino word frequencies or the correct team-chat rate.

2. **Exelsis Deo A. Deloy (2022 publication), The Culture of Trash Talks among DOTA Players: An Ethnography.** [Full paper](https://ijrp.sfo3.cdn.digitaloceanspaces.com/journal/3851/1001091920223906.pdf). The author reports internet-cafe observation and interviews, with fieldwork dated October 2015–February 2016. PDF pp. 9–13 describe brief exclamations and longer complaints; pp. 3 and 5 explain the local setting and methods. This supports treating profanity as a whole utterance as well as an intensifier. Important limitation: this is mostly Cebuano speech from a particular Tagum City cafe, with some Tagalog; it is not a contemporary Tagalog chat corpus. Its prevalence findings are not generalized here.

3. **Jethro Ong & David Asuncion (2017), A Moment of Delight and Frustration.** [Ateneo Ethnographies field report](https://thehappyandgayexperience.wordpress.com/2017/05/01/a-moment-of-delight-and-frustration/). First-person observations describe Filipino teammates reacting to repeated deaths with compact insults and defeat complaints. The same account describes friendly banter among friends. This supports a teammate complaint pool distinct from an enemy kill pool. It is a student field report about a few games, not population research; its broad cultural judgments are not treated as facts.

4. **ded (2015), English-Tagalog Dota 2 Dictionary.** [Steam Community guide](https://steamcommunity.com/sharedfiles/filedetails/?id=512757097). The player-written phrase list mixes Filipino sentence structure with English lane and farming terms. It explains the gaming use of baog as failure to build items. This supports the user's carry complaint in the farming pool and retaining ordinary words such as carry, mid, support and farm inside Tagalog sentences. Some translations are tentative and imprecise; the guide is used as player vocabulary evidence, not a formal dictionary or translation authority.

5. **OB.Neon & T1.Karl chat banter discussion (2022).** [Community discussion](https://www.reddit.com/r/DotA2/comments/rwki3x/obneon_t1karl_chat_banter/). Commenters explain repeated letters for emphasis and discuss introboys as a reply when early advantage fails to become a win. The thread also illustrates disagreement about literal curse translations and joking intent. This supports restrained stretched spellings and situational comeback language. Comments are anecdotal; the linked Twitch clip was not independently watched, so no direct video observation is claimed.

6. **Ben Zimmer with Tagalog analysis from Chris Sundita (2016), What did Duterte call Obama?** [Language Log](https://languagelog.ldc.upenn.edu/nll/?p=27961). The linguistic discussion distinguishes a directed insult from a free-standing exclamation and identifies several contractions and spellings. This supports leaving familiar profanity as a brief reaction instead of attaching an insult paragraph. It is linguistic context outside gaming, not evidence for gaming frequency or current trends.

## Editorial decisions

- Prefer one immediate thought. Short expletives, disbelief, taunts and blunt complaints need no punchline appended.
- Keep informal forms such as san, bat, di, apaka and ampota; formalizing every spelling would change the requested voice.
- Mix Filipino grammar with familiar game terms naturally. Avoid turning every sentence into English with a curse attached.
- Keep revenge lines with enemy-kill reactions, item complaints with failed farming, role complaints with teammate criticism, and replies to earlier boasting with comebacks. These remain authoring pools: the JSON alone cannot enforce triggers.
- Keep some longer specific complaints, including the user's tank/armor line. Shortness is a preference across the library, not a reason to remove every useful longer entry.
- Cut repeated prefix/setup/suffix combinations and stacks of meme vocabulary. Retain a small slang pool because its existing key is part of the supplied structure.
- Keep profanity and harsh gameplay insults. Regional/ethnic slurs from the examples are omitted; neutral bai is retained. No racial, sexuality-based or disability-based insults, real-world threats or self-harm taunts are added.
- Preserve all ten existing category keys and metadata field names. There is no required line count; remove filler rather than regenerate it to reach 1,632 entries.

## Baseline and limits

The original has 1,632 entries, median eight words, 407 entries of six words or fewer, and one duplicate when case is ignored (no byte-for-byte duplicate strings). It is backed up as `before.json`.

Research supports the writing choices above; it cannot prove every authored line sounds natural to every Filipino player. The owner remains the final voice judge. The game does not reference this JSON in the searched source/tools/tests, so this edit does not claim to change live bot speech. Role, situation and channel selection would need separate runtime work if the library is integrated later.
