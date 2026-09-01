# Development vs Production

AiTwin ships developer tooling — behaviour previews, sample data, reminder
triggers — that must never reach anyone who installs the app.

It is kept out **by compilation, not by a toggle.** A release binary does not
contain the code at all.

---

## How it works

`Package.swift` defines a flag for debug configurations only:

```swift
let devOnly = SwiftSetting.define("AITWIN_DEV", .when(configuration: .debug))
```

Every developer-only file is wrapped in `#if AITWIN_DEV`. In a release build the
compiler never sees the contents, so there is nothing to hide, disable, or
accidentally expose through a setting.

| Build | Command | Developer tab | Sample data |
|---|---|---|---|
| **Production** | `./Scripts/build-app.sh` | ✗ not compiled in | ✗ not compiled in |
| **Development** | `./Scripts/build-app.sh --dev` | ✓ | ✓ |

Release is the default, so the plain command always produces something safe to
hand over.

### Verifying it

Not a claim to take on trust — check the binary:

```bash
./Scripts/build-app.sh
strings build/AiTwin.app/Contents/MacOS/AiTwin | grep -c DeveloperFixtures   # 0

./Scripts/build-app.sh --dev
strings build/AiTwin.app/Contents/MacOS/AiTwin | grep -c DeveloperFixtures   # >0
```

---

## What is developer-only

| File | Contains |
|---|---|
| `Sources/AiTwinCore/Development/DeveloperFixtures.swift` | 30 days of sample history |
| `Sources/AiTwinUI/DeveloperSettingsTab.swift` | The Developer settings section |
| `ReminderEngine.replaceActivityLog` | Overwrites history wholesale |
| `AppCoordinator.loadSampleHistory` / `clearHistory` | Sample-data actions |

Anything added to the Developer tab belongs in one of these, behind the flag.

**Test Mode is deliberately *not* developer-only.** The very short intervals are
how a real user checks the app is working after changing a setting, so it stays
in production — and it changes only the numbers, never the reminder logic.

---

## Sample data

**Developer tab → Sample data → Load Sample History.**

Thirty days of plausible activity: a seven-day streak, three deliberately missed
days, eye breaks split across accepted / snoozed / missed, stretches every other
day, and focus sessions every third. Deliberately imperfect — a chart where every
bar is full tells you nothing about whether the chart works.

*Clear History* empties it, which is how the empty states get checked. Those are
easy to break and easy to forget, because a populated fixture hides them.

Sample data is written to the same local store as real history, so it replaces
whatever is there. It never leaves the machine.

---

## Suggested git workflow

```
development  ← everything, built with --dev
     │
     └── main ← what people download, built with the plain command
```

Because the split is a compile-time flag rather than a branch difference, `main`
and `development` can hold **identical code**. The build command decides what
comes out. Nothing has to be stripped before a release, and there is no risk of a
merge quietly carrying a debug panel into production.

Before publishing from `main`:

```bash
swift test                     # currently 279 tests
./Scripts/build-app.sh         # production build
strings build/AiTwin.app/Contents/MacOS/AiTwin | grep -c DeveloperFixtures   # must be 0
./Scripts/package-dmg.sh
```

---

## Behaviour routines

Multi-pose behaviours are assembled in code, not baked into the artwork — see
`ClipSequence`. Standing up to stretch is three beats (sitting → standing →
reaching), not one animation.

Doing it this way means every character pack gets the same choreography for free,
a pack missing one clip degrades a single beat instead of losing the behaviour,
and the timing is tunable without regenerating a single image.

**Developer tab → Behaviours** plays any routine end to end, which is the only
way to check one reads correctly — previewing single poses cannot tell you
whether the transitions work.
