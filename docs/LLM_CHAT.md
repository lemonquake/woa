# Bot chat: the built-in chat brain, and an optional online language model

*Run 2026-10-19 d. Prices are list prices read from OpenRouter's public model list and Anthropic's price table on
2026-10-19; check them before you budget.*

## What runs now (free, offline, no key)

The bots already have their own chat brain, and it needs nothing from you:

* **Persona** (`src/core/persona.gd`): every ranked player has traits (how much they talk, kind, ego, temper, humor,
  how much they call the game), a typing style (lower case, short forms, typos, stretched letters, their laugh such
  as haha / wkwk / kkkk / 555 / jaja, their pet word such as lods / pre / bro / mate), a daily schedule in their own
  time zone, labels for the profile and a bio.
* **Chat brain** (`src/sim/sim_bot_chat.gd`, lines in `src/sim/chat_mind.gd`, typing in `src/sim/chat_style.gd`):
  remembers the match (who killed whom, revenge, rivals, kill steals, the ability that landed the kill, stuns before a
  death, double kills, wipes, escapes on 1 HP), reads the game (enemy ultimates used, ultimates ready, items done, the
  gold gap in thousands, fed enemies, respawn timers), gets tilted or cheers the team up, answers what you type (rank,
  where from, where is a hero, items, why no help, insults with your own score, praise, sorry, gg, ff, "are you a
  bot"), argues with other bots, and in ranked remembers earlier matches with you.
* It is deterministic: multiplayer machines show the same lines.

## The optional online writer (wired in, off by default)

`src/core/llm_chat.gd` (LlmChat). The chat brain still decides who speaks, when, about what and with which facts; the
model only writes that same moment in the bot's voice, with the match around it (the bot's hero, score, the gold gap,
the last lines of chat, what you just typed). If no answer comes in time (4 s), or the answer fails or is refused,
the bot's own line is shown. Single player only.

It talks to **OpenRouter** (your choice) with **DeepSeek V4.1 Flash** (`deepseek/deepseek-v4.1-flash`) by default.
Anthropic's own API also works (a key that does not start with `sk-or-`).

### Turn it on (about a minute)

1. On https://openrouter.ai: Keys > create a key, and add a few dollars of credit. (If you pasted a key anywhere
   public, or into a chat, delete it there and make a new one.)
2. Put the key in the game's data folder, in a file named `llm.json`:
   `%APPDATA%\Godot\app_userdata\Warriors of Aether\llm.json`
   ```json
   {"api_key": "sk-or-...your key..."}
   ```
   Or set the environment variable `OPENROUTER_API_KEY` instead. The key stays on your computer: it is not in the
   project folder and not in the build.
3. In the game: Options > Game > **Online bot chat**: on. The note under it says "Ready (deepseek/deepseek-v4.1-flash)"
   when the key is found, and how much it has cost so far.

Optional settings in `llm.json`:

| Key | Default | What it does |
|---|---|---|
| `model` | `deepseek/deepseek-v4.1-flash` | any OpenRouter model id, e.g. `anthropic/claude-haiku-5.5`, `mistralai/mistral-nemo` |
| `max_calls` | 150 | most lines rewritten in one match |
| `share` | 0.5 | share of ordinary lines rewritten (0..1). Answers to you, memories of earlier matches, revenge, kill steals and arguments are always tried |
| `timeout` | 4 | seconds to wait for an answer before the bot's own line is shown |

Every match prints its cost in the log ("Online bot chat: N lines, ... $0.00xx this match"); the running total is in
`llm_usage.json` next to `llm.json`. With OpenRouter the cost is the amount OpenRouter itself reports for each call.

### What it costs

One rewritten line sends the fixed game and chat rules (about 900 tokens; DeepSeek and Claude cache it, so after the
first call it is read at a small fraction of the price) plus the moment (about 250-350 tokens) and gets back about
10-15 tokens.

| Model (OpenRouter) | Per million tokens in / out / cached in | One line | One 40-min match (~100 lines) | You: 3 matches a day, a month |
|---|---|---|---|---|
| **DeepSeek V4.1 Flash** (default) | $0.038 / $0.08 / $0.0016 | $0.000014-0.000047 | $0.0015-0.005 | $0.13-0.42 |
| Claude Haiku 5.5 | $0.10 / $0.50 / $0.01 | about $0.000045 | about $0.0045 | about $0.40 |
| Mistral Nemo | $0.029 / $0.03 / none | about $0.00004 | about $0.004 | about $0.35 |

The range for DeepSeek is with and without its cache (the cache works when lines come close together, which they do
in a match). OpenRouter also takes a small fee when you buy credit; see their pricing page.

If you ever paid for every player of a released game: 1,000 daily players at 3 matches each is about 90,000 matches a
month, about $130-450 a month with DeepSeek at the default settings, much less with `"share": 0`.

### Advantages

* Endless variety: no line repeats, and it can answer anything you type, not only the questions the brain knows.
* It reads the whole moment (score, gold gap, recent chat) and can carry a conversation.
* Multilingual for free (English, Taglish, Bahasa, Portuguese... whatever the persona speaks).
* Very cheap with DeepSeek V4.1 Flash: a fraction of a cent a match.
* One OpenRouter key lets you try other models by changing one word in `llm.json`.

### Disadvantages

* Needs the internet and a key; costs money per line (tiny for you, real if you pay for every player of a release).
* Latency: usually well under 2 s. The bots' typing delay hides most of it; a slow answer falls back to the bot's own
  line after 4 s.
* Not deterministic, so multiplayer cannot use it (every machine must show the same chat), and replays would differ.
* Quality varies by model: DeepSeek is cheap and fast but its Taglish slang and its sense of each persona are not
  tested here yet; Claude Haiku follows the voice and the rules more closely for about 3 times the price.
* Privacy: each request sends the bot's name, the match situation and the last lines of chat (including what you
  typed) to OpenRouter and the model's host. OpenRouter's settings let you choose which hosts may serve your requests.
* A model can still write something off now and then (a wrong number, an odd phrase). The prompt forbids inventing
  facts, slurs and real-world threats; the line is cut to one line of 90 letters.
* Your key must never ship in a game you give to others: anyone can read it out of the exe. A public release needs a
  small server that holds the key and limits each player's calls (the game's own server program could do this).

### What I'd recommend

1. **Keep the built-in brain as the base** (done): free, offline, instant, multiplayer-safe, and it already knows the
   game.
2. **Turn the online writer on with DeepSeek**, play a few matches, and read the log's cost line and the chat. If the
   voice is off, try `"model": "anthropic/claude-haiku-5.5"` for comparison.
3. **To spend almost nothing**, set `"share": 0`: only your conversations with the bots, memories of earlier matches,
   revenge, kill steals and arguments are rewritten (about 10-30 lines a match), which is where a language model beats
   any line library.
4. **Grow the line library offline** some day: ask the model once (batch prices are half) for thousands of new lines
   per situation in each voice, review them, and ship them as data: no running cost, works in multiplayer.

## Testing without a key

`python tools/llm_mock.py --port=8765` runs a stand-in for both APIs (Anthropic and OpenRouter). Then
`godot --headless --path . -s tests/tools/llm_probe.gd -- --port=8765` checks the requests, the answers, the cap, slow
and failed answers, and the cost counting. No real API was called in this run.
