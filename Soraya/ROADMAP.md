# What is left, and what I decided without asking

Written the day the folder was built, while the reasons were still fresh.
Roughly 90% of the intended work is in place and runnable; this is the other
10%, plus every judgement call made along the way that you might want to
overturn.

## Decisions made without asking you

You asked for the work rather than an interview, so these were settled in the
moment. Each is cheap to reverse and worth a look.

| Decision | Why | To change |
|---|---|---|
| **Python, not Swift** | The model ecosystem is Python; one adapter covers Ollama, LM Studio, vLLM and OpenAI in 120 lines of `urllib`. | See INTEGRATION.md — the seam is HTTP so this stays a choice |
| **Standard library only** | The FastAPI install on this machine is broken. A companion you cannot start is worse than a plain server. | `requirements.txt` |
| **Browser UI, not a native window** | `AiTwin` already owns the desktop presence. Rebuilding it here would be two of everything. | — |
| **Voice OFF by default** | A companion that talks out loud the first time you run it is one you turn off and never turn back on. | Settings → Voice |
| **Bare "soraya" left out of the wake phrases** | After normalisation it is the same string as "sorry a", so it fires on "sorry about that". | Settings → Ears |
| **`claude-opus-5` at `medium` effort** | Thinking on, effort down: disabling thinking on Opus 5 can leak `<thinking>` tags and write tool calls into visible text. Research runs at `high`. | Settings → Mind |
| **Client-side refusal fallback** | The server-side `fallbacks` parameter needs the beta endpoint, and the pinned SDK (0.103.x) has no `betas` argument on `messages.create`. | `brain/claude.py` |
| **She notes memories after replying, not during** | Extraction costs a round-trip; nothing about it should make you wait. | `companion.note_from_last_exchange` |
| **Her name is Soraya** | It is the name you used for the wake phrase. | `settings.name` |

## The remaining 10%, in the order I would do it

### 1. The Swift bridge
Fully designed in [INTEGRATION.md](INTEGRATION.md), not built. One protocol,
one `URLSession` client, three wires in `AppCoordinator`. Until this lands she
lives in a browser tab rather than on your screen — which is the single biggest
gap between what this is and what you asked for.

### 2. Semantic memory
Keyword overlap cannot find "the thing at work" from a note reading "the data
migration". Two options: a small local embedding model (adds `torch`, which the
dependency argument in ARCHITECTURE.md was written to avoid), or ask the model
to expand the query into keywords before searching — no new dependency, one
extra cheap call. **Try the second first.**

### 3. Research on local models
`supports_web_research()` returns `False` for `openai_compat` because there is
no server-side search. Fixing it means a client-side tool loop plus a search
provider (Brave and Tavily both have usable free tiers). Real work, and it only
matters if you actually move off Claude.

### 4. Evaluating her
There are 78 tests and **not one of them checks whether her replies are any
good** — that is a judgement, not an assertion, and pretending otherwise
produces tests that pass while she says something awful.

What would actually work: 30 fixed situations (a bad evening, a shipped
feature, a direct question at 2am, "I'm fine" after a hard day), her reply to
each recorded, and a rubric — did she reframe when she should, stay under the
ceiling, avoid therapy voice, avoid advice nobody asked for. Then you can
change the persona and *see* whether it got better. `/claude-api build-eval`
generates this shape.

### 5. Interruption
`_mac_speaker.stop()` fires when you type. It does not fire when you start
*speaking* over her, which is the more natural way to interrupt someone.

### 6. Streaming her voice
She currently speaks once the full reply has arrived. Speaking sentence by
sentence as they stream would feel markedly more alive. The hard part is not
starting — it is stopping cleanly mid-queue when you interrupt.

### 7. Server-side refusal fallback
Once the SDK is on 1.x, replace the client-side retry with the real
`fallbacks` parameter (`betas: ["server-side-fallback-2026-07-01"]`,
`fallbacks: "default"`).

## Open questions only you can answer

1. **Should she read your screen?** "It should be a research agent altogether"
   could mean she notices what you are working on rather than waiting to be
   told. That needs screen-recording permission and changes what this is,
   privately and legally. Deliberately not built.
2. **Should she remember across devices?** Everything is in `~/.soraya/` on one
   machine. `AiTwin` has a parked `CloudSyncStore` for the same reason —
   it could not be verified without a paid developer account.
3. **How much should she cost per day?** At Opus 5 and `medium` effort a
   conversational turn is roughly a cent, plus an affect read and a note
   extraction. If that matters, Haiku for the two small calls and Opus only for
   the reply would cut most of it. Measure before optimising.
4. **Does she keep the same personality when the model changes?** The persona
   prompt is tuned against Claude. A local 8B model will read the same
   instructions and produce a noticeably blunter character. That is not a bug
   to fix in code — it is a prompt to write per model tier, and it needs the
   eval in item 4 to do honestly.
5. **What happens when she is wrong about your mood?** Right now: nothing. She
   hedges in the prompt and moves on. A "no, I'm fine" that visibly corrected
   her read would be better, and needs a way to push a correction back into the
   affect state.

## Known limitations, stated plainly

- **The wake word fires on "sorry about that"** if you add the bare name back.
  Not fixable at that layer; see `voice/wake.py`.
- **Speech recognition is Chrome/Edge only.** Safari's support is unreliable.
  The interface says so rather than failing silently.
- **Note deduplication is biased toward not storing.** A richer restatement of
  a known fact can be dropped. That is the cheaper mistake.
- **Notes have no usage reinforcement.** A `uses` counter was written into the
  recall score and nothing ever incremented it, so it contributed zero while
  reading as though the feature existed; it has been removed rather than left
  in as decoration. Doing it properly needs a store that can update a record in
  place, and `notes.jsonl` is append-only.
- **One `Companion` is shared across server threads.** Fine for one person in
  one tab, which is the only case that exists today. Two tabs sending at once
  could interleave writes to `turns.jsonl` and race `last_affect`. A lock
  around `respond` is the fix if it ever matters.
- **Only the last 12 turns reach the prompt.** Deliberate — a companion shaped
  by a 200-turn history starts repeating old moods back at you — but it means
  she genuinely forgets the middle of a long session.
- **`say` plays on the machine running the server.** If you ever run this on a
  different box from the browser, `MacSpeaker.to_file` exists for that and is
  not yet wired to the UI.
- **The affect read costs a model call per message.** Roughly doubles the
  request count. `read_fast` alone is free and is what runs in offline mode.
