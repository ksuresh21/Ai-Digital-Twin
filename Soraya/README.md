# Soraya — the talking half of the digital twin

`AiTwin/` already solved **presence**: a pixel-art character who lives on the
edge of your screen, walks in, waves, and reminds you to drink water. What she
cannot do is think, listen, or speak.

This folder is that half. She has a voice, ears, a memory, a read on how you
are doing, and a mind you can swap out. It runs on its own today, and it is
built to be wired into the Swift app over a single HTTP seam when you want it
to be.

```
cd Soraya
./run.sh --offline      # no key, no network, no model — see it all work
./run.sh                # with a real model, once you have a key
```

`--offline` matters: the entire application runs with no API key at all, using
a stub mind. That is how you judge the interface, the animation, the voice and
the mood-reading before spending anything.

---

## What she does

**She reads how you are.** Not sentiment scoring — two axes, valence and
arousal, because "tired and flat" and "angry and wired" are both negative and
want *opposite* responses. A fast lexical pass runs instantly so her pose and
voice can react before the model has answered; the model's own structured read
replaces it a moment later if it is more confident.

**She changes what she does about it.** Eight postures — `retreat`, `hold`,
`ground`, `support`, `lift`, `celebrate`, `answer`, `banter` — each with its
own instructions, word ceiling and pose. A direct question gets answered, not
therapised. "Leave me alone" outranks any reading of your mood. A safety signal
outranks everything, including her personality.

**She says it another way.** For the postures where it helps, she distils what
you told her back in fewer words before responding. Not paraphrasing — the
prompt is explicit that it should sound like understanding. This is the single
most useful move in the set, and it is deliberately *off* for direct questions
and celebrations, where reframing reads as evasion or as coldness.

**She talks.** macOS's own voices, off by default, with speed and volume, and
silent during quiet hours. Nothing is downloaded and no audio leaves the
machine.

**She listens.** "Hey Soraya" wakes her. Recognition runs in your browser, so
no Whisper install and no audio upload. The wake matcher is fuzzy on purpose —
speech recognition mangles her name consistently, and `hey sorry a` is the most
common way it comes back.

**She remembers.** Durable facts only, written deliberately rather than
scraped from everything you say, in `~/.soraya/`. One button shows you
everything she knows; one button deletes all of it.

**She comes over on her own.** Quiet / normal / lively, with a hard floor on
how often — because "emotionally responsive" turns into "interrupts you
constantly" without one.

**She looks things up.** Research mode uses Claude's server-side web search:
no scraper, no search API key, and citations come back with the answer.

---

## The map

Start with **[ARCHITECTURE.md](ARCHITECTURE.md)** — the seams, and why each one
is where it is. Then:

| File | What it is for |
|---|---|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | How the pieces fit, the art contract, the caching design |
| **[INTEGRATION.md](INTEGRATION.md)** | Wiring her into the Swift `AiTwin` app, step by step |
| **[ROADMAP.md](ROADMAP.md)** | The remaining 10%, and every open question, written down |

| Module | Responsibility |
|---|---|
| `soraya/config.py` | Every setting, one JSON file, tolerant loading |
| `soraya/emotion.py` | Reading how you are; choosing a posture. **Pure.** |
| `soraya/persona.py` | Who she is, assembled per turn |
| `soraya/memory.py` | The transcript, and durable notes |
| `soraya/pulse.py` | When she approaches unprompted. **Pure.** |
| `soraya/companion.py` | The one object that owns the side effects |
| `soraya/brain/` | Claude, any OpenAI-compatible local model, offline stub |
| `soraya/voice/` | `say` synthesis, wake-phrase matching |
| `soraya/presence/` | Which drawing of her to show |
| `soraya/agent/` | Research mode |
| `soraya/server.py` | Local HTTP + SSE. Standard library only |
| `soraya/ui/` | The browser interface. No framework, no build step |

```bash
python3 -m pytest              # 78 tests, no network, no cost
python3 scripts/check_brain.py # ONE real call, to prove the model path works
```

`check_brain.py` exists because the Claude request shape cannot be verified
without spending money, and that is your call to make. Everything else here is
tested offline. Run it once and it tells you whether the model name, streaming,
adaptive thinking, the effort setting and the cached system prompt were all
accepted — and run it twice to confirm prompt caching is actually working.

---

## Swapping the model

Settings → Mind, or edit `~/.soraya/settings.json`:

| Provider | `model` | `base_url` | Notes |
|---|---|---|---|
| `claude` | `claude-opus-5` | — | Needs `ANTHROPIC_API_KEY` or `ant auth login`. Only provider that can research. |
| `openai_compat` | `llama3.1:8b` | `http://localhost:11434/v1` | Ollama |
| `openai_compat` | whatever is loaded | `http://localhost:1234/v1` | LM Studio |
| `openai_compat` | `gpt-4o` | `https://api.openai.com/v1` | Needs `OPENAI_API_KEY` |
| `echo` | — | — | No model. Runs everywhere, costs nothing. |

`SORAYA_BRAIN=echo ./run.sh` forces offline for one run without editing
anything.

---

## Replacing the character

**The real artwork ships in this folder.** `assets/characters/Soraya/` holds
the Nish frames, imported from `AiTwin/Resources/Characters/Nish` so that
`Soraya/` works on its own — move it, zip it, put it on another machine, and she
still looks like herself with no Swift app beside her.

Re-import after changing the art over there:

```bash
python3 scripts/import_pack.py --from Nish --to Soraya --replace
```

Packs are still *looked up* across two roots, so nothing stops you pointing at
one where it sits:

1. `Soraya/assets/characters/` — this folder's own packs
2. `AiTwin/Resources/Characters/` — the Swift app's packs, read in place

`SORAYA_PACKS` adds more roots.

**Four clips are deliberately absent:** `Talking`, `Listening`, `Thinking`,
`Greeting`. The artwork predates them. Rather than fill those folders with
copies of other clips under a second name, each clip has a fallback chain —
`greeting` plays her real Waving frames and `thinking` plays Focus, her reading
pose — and the interface says which substitutions are in effect. Drawing two
mouth-open frames for `Talking` and a head-tilt for `Listening` is the only
thing that would improve the pack.

The stick-figure placeholders are still generated on demand, under their own
name so they can never be mistaken for the real art:

```bash
python3 scripts/make_placeholders.py     # writes a "Placeholder" pack
```

**The one rule that matters:** keep the feet at the same height in every frame
of every clip. If the feet move between clips, she appears to hop when the clip
changes, and no amount of code fixes that afterwards. See
[ARCHITECTURE.md § The art contract](ARCHITECTURE.md#the-art-contract).

---

## Privacy

Everything is local. Her memories and settings are in `~/.soraya/`, plain JSON
you can read and delete. The server binds to `127.0.0.1` only — this process
can read your conversations, spend against your API key, and talk out loud, so
it has no business being reachable from the network.

What does leave the machine, and only with `brain.provider = "claude"` or an
OpenAI endpoint: the text of the conversation, sent to that provider. With
`echo` or a local model, nothing does. Speech synthesis is always local. Speech
recognition uses your browser's engine, which on Chrome may be server-assisted
— if that matters, type instead.

This project never reads `.env`. Keys come from the environment only.
