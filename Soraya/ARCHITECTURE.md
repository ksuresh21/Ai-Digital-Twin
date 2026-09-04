# Architecture

The shape follows `AiTwin/` on purpose: **pure decisions in the middle, side
effects at the edges, one object that owns the wiring.** That is what makes a
companion testable, and a companion you cannot test is one whose behaviour you
can only discover by living with it.

```
      ┌──────────────────────────────────────────────┐
      │  soraya/ui/           browser: sprite, chat, │
      │                       microphone, settings   │
      └───────────────────┬──────────────────────────┘
                          │  HTTP + server-sent events
      ┌───────────────────▼──────────────────────────┐
      │  soraya/server.py     stdlib http.server     │
      └───────────────────┬──────────────────────────┘
                          │
      ┌───────────────────▼──────────────────────────┐
      │  soraya/companion.py  THE ONLY PLACE WITH    │
      │                       SIDE EFFECTS           │
      └──┬────────┬────────┬────────┬────────┬───────┘
         │        │        │        │        │
    ┌────▼───┐┌───▼───┐┌───▼────┐┌──▼─────┐┌─▼──────┐
    │emotion ││pulse  ││persona ││memory  ││presence│
    │        ││       ││        ││        ││        │
    │ PURE   ││ PURE  ││ PURE   ││ files  ││ files  │
    └────────┘└───────┘└────────┘└────────┘└────────┘
         │
    ┌────▼─────────────────────────────────────┐
    │  soraya/brain/   claude · local · echo   │
    │  soraya/voice/   say · wake matching     │
    │  soraya/agent/   research                │
    └──────────────────────────────────────────┘
```

## Why the decisions are pure

`emotion.posture_for` and `pulse.consider` take values in and return values
out. No clock they read themselves, no random they call, no model.

That is not tidiness. It is what makes these questions answerable:

- *Would she interrupt me at 3pm on a Tuesday when I have been heads-down for
  an hour?* → `pulse.consider(settings, now=…, idle_minutes=60, roll=0.0)`
- *If I say "not now" while clearly upset, does she respect it?* →
  `posture_for(read_fast("not now, busy"))` → `retreat`
- *Does a direct question get answered rather than therapised?* → one assertion

Those are the behaviours that decide whether she is worth having around, and
every one of them is a test rather than a thing you find out on a bad evening.

## The two-pass affect read

| | Fast pass | Considered pass |
|---|---|---|
| Where | `emotion.read_fast` | `Affect.from_model` |
| Cost | none | one small model call |
| Latency | microseconds | a second or so |
| Good at | shouting, obvious words | sarcasm, understatement, "I'm fine" |
| Confidence | capped at 0.35 | usually 0.6+ |

The fast pass runs on every message so her pose and voice can react *before*
the model answers. The considered read replaces it only if it comes back more
confident — so a failed model call degrades to the lexical answer instead of
losing the mood entirely.

Two things the fast pass keeps regardless of what the model says: an explicit
"leave me alone", and a safety signal. Both are acted on without a round-trip,
because acting on them a second later is the entire point, and a lexical hit on
self-harm language must not be talked out of by a model that read the sentence
more generously.

## Prompt caching is a layout decision

Caching is a **prefix match** — one changed byte invalidates everything after
it. So the system prompt is deliberately two blocks:

```
system = [
  { text: IDENTITY + CRAFT + SAFETY,  cache_control: ephemeral, ttl: 1h },  # never varies
  { text: posture + mood + memories },                                      # varies every turn
]
```

Her personality is ~2.4KB and identical on every single turn. Put the posture
first and you pay for the personality on every sentence; put it second and you
pay once an hour. The 1-hour TTL rather than the default five minutes is
because a companion is talked to in bursts across a working day — at five
minutes you re-cache her every time you come back from a meeting.

`test_the_stable_half_is_byte_identical_across_turns` guards this. It looks
like a trivial test. It is the one protecting the cost model.

## Dependencies, and what is deliberately absent

Not used: **fastapi, uvicorn, pydantic, flask, openai, websockets, numpy,
faster-whisper, torch.**

That started as a discovery rather than a principle: the FastAPI install on
this machine is broken (a pydantic v1/v2 mismatch), and a companion you cannot
start because of somebody else's dependency conflict is worse than one with a
plainer server. Having built it that way, the plainer version is better:

| Need | Chosen | Instead of |
|---|---|---|
| HTTP + streaming | `http.server` + SSE | FastAPI + uvicorn |
| Local model client | `urllib` | `openai` package |
| Speech **out** | `say` (macOS built-in) | Piper, ElevenLabs, TTS APIs |
| Speech **in** | Web Speech API, in the browser | faster-whisper + torch |
| Memory search | keyword overlap + recency | embeddings + a vector store |

Speech-in in the browser is the best of these: no install, no audio upload,
nothing to transcribe server-side. The cost is that it only works where the
browser supports it — Chrome and Edge do, Safari is unreliable — which the
interface says out loud rather than failing silently.

The one real casualty is memory search. Keyword overlap genuinely cannot find
"the thing at work" from a note that says "the data migration". That limit is
in [ROADMAP.md](ROADMAP.md); it buys zero dependencies and offline operation,
which for a few hundred notes is a fair trade.

## Quiet hours is not a voice setting

It reads like one, and it started as one. But `pulse.consider` uses it to
decide whether she **approaches at all** — so a switch labelled "silent at
night", sitting under Voice, also decided whether she could wander over at 3am
with a speech bubble. Two behaviours behind one switch, and the label described
only one of them.

It is now `Settings.quiet_hours`, top level, and it means what it says: during
the window she neither speaks nor appears. The one exception is an unlock
greeting, which is a response to you arriving rather than an interruption of
anything.

Same shape and same algorithm as `QuietHours.swift`, so the two halves cannot
disagree about when to shut up. A window saved under the old nested name is
still read, so nobody's setting silently reverts.

## The art contract

Frames live in `assets/characters/<Pack>/<Clip>/<prefix>_NN.png`, with clip
names and folders from `presence/sprite.py` — the same ones
`AiTwin/Sources/AiTwinCore/ClipName.swift` already uses.

Three rules, in order of how badly breaking them hurts:

1. **The feet sit at the same height in every frame of every clip.** Break this
   and she hops when the pose changes. It cannot be fixed downstream, because
   nothing in the code knows where her feet were supposed to be.
2. **One canvas size for the whole pack.** Mixed sizes make her grow and shrink.
3. **Transparent background**, and frames numbered so they sort — `_01`, `_02`.
   Sorting is numeric on the trailing digits, so `frame_10` correctly follows
   `frame_2`; a lexical sort would put 10 before 2, which looks like bad
   animation rather than a bug and therefore survives for months.

A missing clip falls back to `idle` and the interface *says which clips are
missing* — silent fallback alone leaves you wondering why she never changes
pose.

## The event stream

A turn is a generator of events, not a returned string, so the interface can
show her pose and start her voice before the sentence finishes. This is also
the contract the Swift app will consume — see [INTEGRATION.md](INTEGRATION.md).

| Event | Payload | Meaning |
|---|---|---|
| `pose` | `clip` | Show this animation now |
| `affect` | `label`, `valence`, `arousal`, `confidence`, `posture`, `evidence` | How she read you |
| `chunk` | `text` | A piece of the reply, as it arrives |
| `done` | `text`, `spoke`, `posture`, `usage` | The finished reply |
| `error` | `message` | Something to show the user, in their words |
| `approach` | `reason` | She started this, you did not |
| `end` | — | Stream closed |

`pose` arrives first and last. The last one is always `idle`, including on the
error path — otherwise a failed turn leaves her frozen mid-thought, which reads
as the app having crashed.

## Failure is a first-class path

She must always start. A missing API key, an unreachable local server, an
unknown provider name, a corrupt settings file, a pack with no frames — every
one of these degrades to something running, with a message in the interface
saying what to do about it.

`build_brain_or_echo` is the shape of it: it returns a working brain and a
warning, never an exception. A configuration problem is something to tell
somebody about, not a reason for the app to refuse to open.
