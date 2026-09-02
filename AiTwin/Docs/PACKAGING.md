# Packaging and Distribution

---

## The terms, and which one AiTwin is

| Term | What it actually is | AiTwin |
|---|---|---|
| **Source code** | The `.swift` files. Cannot be run by a user | ✅ this repo |
| **Xcode project** | An `.xcodeproj` bundle describing targets and build settings to Xcode's IDE | ❌ not used — see below |
| **Swift package** | A directory with `Package.swift` describing targets and dependencies. Built by SPM, with or without Xcode | ✅ this repo |
| **macOS `.app`** | A folder disguised as a file: an executable + `Info.plist` + resources. What a user double-clicks | ✅ `./Scripts/build-app.sh` |
| **`.dmg`** | A disk image. The conventional way to *ship* an `.app` — mount, drag to Applications | ✅ `./Scripts/package-dmg.sh` |
| **GitHub Release** | A tagged version on GitHub with files attached. Where the `.dmg` goes | you publish |

### Is "Swift Package" the right description?

**Partly — and the honest answer is worth spelling out.**

A Swift package is a *build system description*, not an application. Calling
AiTwin "a Swift package" would be accurate about how it is built and misleading
about what it is. It is:

> **A macOS application, built with Swift Package Manager, distributed as a
> `.app` inside a `.dmg`.**

Normally an app like this would be a `.xcodeproj`. AiTwin uses a package instead
for a specific reason: **a package builds with the Command Line Tools alone.**
No Xcode installation is required to build, test or ship it — `swift build`,
`swift test` and a shell script that assembles the bundle are enough. That is a
meaningfully lower barrier for anyone who wants to clone and run it.

The trade-off is that SPM does not produce an `.app` bundle, so
`Scripts/build-app.sh` assembles one: copy the executable into
`Contents/MacOS/`, copy the character packs into `Contents/Resources/`, write an
`Info.plist`, ad-hoc sign. That script is about 60 lines and does exactly what
Xcode would do.

**If you install Xcode**, `open Package.swift` opens the package natively —
full editor, debugger and test navigator, no `.xcodeproj` needed.

---

## Building

```bash
swift build                  # debug
swift test                   # 125 tests
./Scripts/build-app.sh       # → build/AiTwin.app  (release)
./Scripts/build-app.sh --debug
./Scripts/package-dmg.sh     # → build/AiTwin-1.0.0.dmg
```

Installing locally:

```bash
cp -R build/AiTwin.app /Applications/
open /Applications/AiTwin.app
```

`/Applications` matters if you want "Start at login": `SMAppService` is unhappy
with an app run from a build directory.

---

## Signing, and what other people will see

`build-app.sh` applies an **ad-hoc signature** (`codesign --sign -`). That is
enough to run on the machine that built it. It is **not** notarised.

Anyone who downloads your `.dmg` will see:

> *"AiTwin" cannot be opened because Apple cannot check it for malicious software.*

They can get past it by **right-clicking the app → Open → Open**, once. Document
that in your release notes rather than leaving people stuck.

To remove the warning you need a paid Apple Developer account ($99/year):

```bash
# Developer ID signing
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" build/AiTwin.app

# Notarisation
xcrun notarytool submit build/AiTwin-1.0.0.dmg \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD \
  --wait
xcrun stapler staple build/AiTwin-1.0.0.dmg
```

**Assumption:** you do not currently have a Developer ID, so the default path is
ad-hoc signed and documented as such. Nothing in the code needs to change if you
get one later.

---

## Sandboxing

AiTwin is **not** sandboxed, deliberately. A sandboxed app cannot freely read
`~/Library/Application Support/AiTwin/Characters`, which is the folder that makes
"drop in your own character" work without a rebuild. Sandboxing is required for
the Mac App Store and not otherwise, and direct distribution is the better fit
for a small companion app.

There is now a second obstacle to the App Store, worth knowing before anyone
tries. Screen-lock detection uses two **undocumented** distributed
notifications, `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` (see
`MacPresenceObserver.swift`). No public API reports the screen lock. They need
no entitlement in an unsandboxed, ad-hoc-signed build like this one, but a
sandboxed build is not guaranteed to receive them, and shipping private
notification names is a review risk.

If AiTwin ever has to be sandboxed, the lock half degrades on its own: the
observer latches sleep and fast user switching through public API, so it keeps
working at coarser granularity rather than breaking.

---

## Publishing a release

```bash
git tag v1.0.0
git push origin v1.0.0
./Scripts/build-app.sh && ./Scripts/package-dmg.sh
gh release create v1.0.0 build/AiTwin-1.0.0.dmg \
  --title "AiTwin 1.0.0" \
  --notes "First release. Unsigned — right-click → Open on first launch."
```

## Homebrew, later

Once releases are stable, a cask is straightforward:

```ruby
cask "aitwin" do
  version "1.0.0"
  sha256 "..."
  url "https://github.com/YOUR_USERNAME/YOUR_REPO/releases/download/v#{version}/AiTwin-#{version}.dmg"
  name "AiTwin"
  desc "Pixel-art desktop companion with water and eye-break reminders"
  homepage "https://github.com/YOUR_USERNAME/YOUR_REPO"
  app "AiTwin.app"
end
```

Homebrew's own cask repository requires a notarised app and some usage history.
A personal tap works immediately.

*(Repository URLs above are placeholders. Replace `YOUR_USERNAME/YOUR_REPO`.)*
