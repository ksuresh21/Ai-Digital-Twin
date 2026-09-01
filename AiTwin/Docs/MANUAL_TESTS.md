# Manual Test Checklist (macOS)

Everything the automated suite cannot prove. Work through it on your Mac.

```bash
./Scripts/build-app.sh && open build/AiTwin.app
```

**Before you start:** turn on Test Mode so you aren't waiting 40 minutes between
checks — Settings → General → *Test mode*, then Settings → Reminders and set
water to 30 seconds and eye break to 1 minute.

> **Verified so far on this machine:** the app builds, launches, runs without
> crashing, and terminates cleanly (macOS 26.6.2, Apple Silicon). Everything
> below that concerns *appearance and interaction* has **not** been verified —
> a screenshot required Screen Recording permission, which was not granted.
> That is what this checklist is for.

---

## A. Appearance and launch

**1. It launches with no Dock icon**
- [ ] A drop icon appears in the menu bar
- [ ] **No** icon appears in the Dock
- [ ] AiTwin does **not** appear in ⌘-Tab
- [ ] No application window opens

**2. The character greets you**
- [ ] The character walks in from the **left edge**
- [ ] It stops near the **bottom-left corner**
- [ ] A speech bubble shows a greeting matching the time of day
- [ ] After a few seconds it walks back off screen to the left

**3. There is no visible window (the important one)**
- [ ] **No grey or white rectangle** around the character
- [ ] No title bar, no traffic-light buttons
- [ ] No drop shadow behind an invisible box
- [ ] Your wallpaper shows through everywhere the sprite isn't
- [ ] The speech bubble has rounded corners and a blurred material background

**4. Pixel art is crisp**
- [ ] Sprite edges are **hard, blocky pixels** — not blurred or smoothed
- [ ] Still crisp at Settings → Character → Size = 256
- [ ] Still crisp on a Retina display

---

## B. Reminders

**5. Water fires on schedule** (Test Mode, 30s)
- [ ] After ~30 seconds the character walks in
- [ ] The bubble reads something like "Time to drink some water 💧"
- [ ] Buttons "Done 💧" and "Snooze" are visible
- [ ] The message **differs** from the previous water reminder
- [ ] Clicking "Done 💧" makes the character walk away
- [ ] Menu bar → "Water today" incremented by 1

**6. Animation quality**
- [ ] Legs animate *while* moving across the screen — no ice-skating
- [ ] Movement is smooth, not juddering
- [ ] The character faces **right** walking in, **left** walking out
- [ ] The drinking animation plays during a water reminder
- [ ] The character does not visibly bob up and down while walking

**7. Eye break fires on schedule** (Test Mode, 1 min)
- [ ] Fires after ~60 seconds
- [ ] The eye-break animation plays (eyes closed / hands up)
- [ ] "Looked away 👀" dismisses it
- [ ] The next cycle starts — it fires again ~60s later

**7a. The break itself dims the screen** — this regressed once, silently
- [ ] Accepting the eye break **dims every display** (~50% by default)
- [ ] A **large countdown** appears in the middle of the screen, not just in her cloud
- [ ] Under it, a line explaining why the screen went dark
- [ ] The countdown ticks down without the digits shifting sideways
- [ ] Her cloud shows a message and a "Skip" button, and the message **does not
      re-animate** every second
- [ ] Clicks and typing still work while dimmed — try switching apps
- [ ] The screen returns to normal when the countdown ends, and she fades out
- [ ] "Skip" ends the break early and undims immediately
- [ ] It dims on **every** display, not just the main one

> Why this has its own entry: accepting the break used to resolve the reminder
> before the break started, so she simply walked away — no dimming, no
> countdown, no error. The state machine tests now cover the ordering, but the
> coordinator that got it wrong lives in the executable target and cannot be
> unit-tested, so this checkbox is the guard.

**7b. Snooze**
- [ ] "Snooze" makes the character leave
- [ ] It comes back after the snooze interval, not a full cycle
- [ ] Menu bar countdown reflects the snooze

---

## B2. Focus sessions and corners

**7c. The focus clock is calm**
- [ ] Start a session from the menu bar; she sits down with a clock above her
- [ ] The clock counts down **once a second**
- [ ] Only the digits change — the cloud does not flash, resize, or re-appear
- [ ] The digits do not shift left and right as the numbers change
- [ ] "End" stops the session

**7d. Top corners tuck her into the corner**
- [ ] Settings → General → corner → **top-left**; trigger a reminder
- [ ] Her head is close to the top of the screen, not floating well below it
- [ ] Her cloud appears **below** her, not above
- [ ] Trigger several different moods (Developer → Behaviours): she stays at the
      **same height** — no drifting up and down as the pose changes
- [ ] A jump or a stretch is not cut off at the top
- [ ] Repeat at top-right; bottom corners are unchanged

---

## C. Window behaviour — the risky part

**8. It floats above ordinary windows**
- [ ] Open Safari or Finder, maximise it (not full screen)
- [ ] Menu bar → Remind Me Now → Water
- [ ] The character appears **on top of** that window

**9. It follows you across Spaces**
- [ ] With the character on screen, swipe to another Space
- [ ] It is visible there too
- [ ] It did not visibly slide or jump during the transition

**10. Full-screen apps — ⚠️ NEEDS VERIFICATION**
- [ ] Put an app into true full screen (green button)
- [ ] Menu bar → Remind Me Now → Water
- [ ] Does the character appear? **Record yes or no.**

> This is the one behaviour I cannot promise. `.fullScreenAuxiliary` combined
> with `.statusBar` level is the correct configuration, but Apple has changed
> how it behaves between macOS releases. If it does not appear on macOS 26,
> that is a known limitation, not a bug in the code. Please note the result.

**11. Clicks pass through (the other important one)**
- [ ] Trigger a reminder so the character is on screen
- [ ] Click on a window *behind* the character — not on the bubble
- [ ] The click reaches that window normally
- [ ] Click directly on the **character sprite** while a bubble is showing
- [ ] Now click **through the sprite** while it is merely walking or idle — the click should reach whatever is underneath
- [ ] Typing in another app is never interrupted when the character appears
- [ ] **The frontmost app never loses focus when the character appears** ← the single most important UX property

---

## D. Multiple displays

*Skip if you only have one display. Do not mark these as passed.*

**12. It picks a sensible display**
- [ ] With two displays connected, the character appears on the active one
- [ ] It is in the bottom-left of that display, not spanning both

**13. Disconnect while visible**
- [ ] Trigger a reminder on the secondary display
- [ ] Unplug that display while the character is on screen
- [ ] The character reappears on the remaining display, fully visible
- [ ] It is **not** stranded off screen, and the app does not crash

**14. Resolution change**
- [ ] Change the display resolution in System Settings
- [ ] The character stays fully on screen

---

## E. System events

**15. Wake greeting**
- [ ] Settings → General → "Say hello when the Mac wakes up" is on
- [ ] Sleep the Mac (Apple menu → Sleep), wait 30s, wake it
- [ ] The character walks in and greets you
- [ ] Exactly **one** greeting, not two

**16. Timers survive sleep**
- [ ] Set eye break to 1 minute; note the menu bar countdown
- [ ] Sleep the Mac for 3 minutes, wake it
- [ ] The reminder fires promptly — the countdown did not freeze for the sleep duration
- [ ] Nothing fired repeatedly to "catch up"

**17. Start at login**
- [ ] Copy the app to `/Applications` first (`cp -R build/AiTwin.app /Applications/`)
- [ ] Settings → General → "Start AiTwin at login" on
- [ ] If a warning appears, approve AiTwin in System Settings › General › Login Items
- [ ] Log out and back in — AiTwin starts

**18. Idle detection**
- [ ] Settings → Reminders → "Only count time I'm actually using the Mac" on
- [ ] Note the eye-break countdown, then leave the Mac untouched past the idle threshold
- [ ] Menu bar reads "You're away — timers on hold"
- [ ] The countdown has not advanced
- [ ] Move the mouse — it resumes from where it stopped

**19. Quiet hours**
- [ ] Set quiet hours to a window covering the current time
- [ ] Menu bar reads "Quiet hours — staying quiet"
- [ ] No reminders fire
- [ ] Set a window that does **not** cover now — reminders resume

---

## F. Settings and configuration

**20. Every corner works**
- [ ] For each of bottom-left, bottom-right, top-left, top-right: set it, trigger a reminder
- [ ] The character walks in from the nearest edge and stops in that corner
- [ ] Top corners sit **below** the menu bar, not under it
- [ ] Bottom corners sit **above** the Dock, not behind it

**21. Size and glasses**
- [ ] Moving the size slider changes the character immediately
- [ ] At 256 it still fits in the corner
- [ ] "Wearing glasses" changes the sprite

**22. Settings persist**
- [ ] Change the corner, interval and size; quit; relaunch
- [ ] All three survived

**23. Pause**
- [ ] Menu bar → Pause Reminders → header reads "Paused"
- [ ] Nothing fires
- [ ] Resume → the countdown continues from where it stopped, not from zero

---

## G. Error handling

**24. A missing character pack**
```bash
mv "build/AiTwin.app/Contents/Resources/Characters/Default/Walking" /tmp/walking-backup
open build/AiTwin.app
```
- [ ] The app still launches
- [ ] Reminders still fire
- [ ] The character stands still instead of walking — it does **not** crash
- [ ] Settings → Character lists the missing clip

```bash
mv /tmp/walking-backup "build/AiTwin.app/Contents/Resources/Characters/Default/Walking"
```

**25. A corrupt frame**
```bash
echo "not an image" > "build/AiTwin.app/Contents/Resources/Characters/Default/Idle/idle_02.png"
open build/AiTwin.app
```
- [ ] The app launches; the idle animation plays with the remaining frames
- [ ] Then regenerate: `python3 Scripts/generate_placeholder_character.py`

**26. Your own character**
- [ ] Settings → Character → *Open Characters Folder…* opens Finder
- [ ] Add a folder with just `Idle/idle_01.png`
- [ ] *Reload Characters* → it appears in the picker
- [ ] Selecting it shows your character

---

## H. Resource use

**27. It stays lightweight**
- [ ] Open Activity Monitor, find AiTwin
- [ ] Idle (character off screen): CPU essentially **0%**
- [ ] While walking: a low single-digit percentage
- [ ] Memory: tens of MB, and **stable over an hour** — not climbing
- [ ] Energy Impact is low

---

## Future Windows validation

**No Windows implementation exists. Nothing below has been tested. Do not
report any of it as working.**

When a Windows port is attempted, this section becomes its checklist:

- [ ] `AiTwinCore` compiles on Windows unchanged (it imports only Foundation)
- [ ] The 125 core tests pass on Windows
- [ ] A layered/transparent window equivalent to `NSPanel` exists and works
- [ ] Always-on-top behaviour is achievable
- [ ] Click-through (`WS_EX_TRANSPARENT`) works
- [ ] Multi-monitor geometry maps onto `ScreenProviding`
- [ ] Idle detection via `GetLastInputInfo`
- [ ] Startup registration via the Run registry key or Task Scheduler
- [ ] Resume-from-sleep notifications

See [ARCHITECTURE.md](ARCHITECTURE.md) for what is shared and what is not.

---

## Reporting a problem

Include: macOS version, Apple Silicon or Intel, number of displays, which
checklist item, what you expected, what happened, and anything from:

```bash
log show --predicate 'process == "AiTwin"' --last 10m --style compact
```
