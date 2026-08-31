# Project: Ai_twin chracter — AI Digital Companion for macOS

Act as a **senior macOS/SwiftUI engineer, product architect, UI/UX designer, QA engineer, and open-source maintainer**.

I want to build a small macOS application called **Ai_twin chracter** — a pixel-art AI digital takes cares of Girl friend/ or boy friend, should be able to select on 1st run startup setting that lives on my desktop and acts as a lightweight personal reminder/companion.

The first version should be intentionally simple, polished, and reliable.

## 1. Core Product Concept

character is a small pixel-art character that lives on the user's Mac desktop.

When I on the mac.

- character should appear on the desktop left cornor walk and great me.
- She should initially greet the user with a simple animation/message such as on head os slide with small quit:
  - "Hi 👋"
  - "Good morning! depends on the time"
  - or another context-appropriate greeting.
- She should feel like a small desktop companion rather than a conventional application window.
- The character should be visually unobtrusive and lightweight.
- The application should continue running in the background/menu bar when appropriate.

The primary purpose of Version 1 is:

1. Water reminders, while appearing by walking in top of all screens present and then with animation saying take water.
2. Eye-break reminders by setting timmer, 
3. A simple desktop companion experience

Do NOT over-engineer the first version.

---

# 2. Core Reminder Behaviour

## Water Reminder

Implement a **"walk to remind" water interaction**.

When it is time for a water reminder:

1. character should start apper like walk from left to right and greating to take the water.
2. Example:
   - "Time to drink some water 💧"
   - "Hydration check!" (ever time some uniqe reminders)
3. After the reminder is acknowledged/dismissed, she can return to her normal position. that means going back to sleep or disappearing.  

### Important UI rule

The walking character/reminder should always use the **bottom-left corner** as the default walking/reminder location.

Make this configurable in code so it can later be changed to:

- bottom-left
- bottom-right
- top-left
- top-right

But Version 1 should use:\
\
and it one setting menu i should be able to do this things.

**bottom-left.**

---

# 3. Eye Break Behaviour

Implement a **40-minute eye-break cycle**.

Default behaviour:

```text
40 minutes of screen usage
        ↓
Eye break reminder
        ↓
Character walks to bottom-left
        ↓
Show eye-break message
        ↓
User acknowledges
        ↓
Start another 40-minute cycle
```

The 40-minute interval must be configurable.

Do NOT hard-code 40 minutes throughout the application.

Create a central configuration such as:

```swift
eyeBreakInterval = 40 * 60
```

so it can later be changed easily.

For development/testing, provide a way to use very short intervals such as:

```text
10 seconds
30 seconds
1 minute
```

without modifying production logic. \
\
everthing should be in the setting menu of the appliaction.

---

# 4. Suggested Additional Features

Before implementation, evaluate and suggest additional features that fit the chracter concept.

Prioritize features into:

### MVP

Features that should be implemented now.

### V1.1

Useful but not required initially.

### Future

Interesting ideas that should NOT complicate the MVP.

Potential ideas to evaluate:

- Menu bar controls
- Pause reminders
- Snooze reminder
- Custom reminder intervals
- Daily water goal
- Water intake counter
- Eye-break countdown
- Different character moods
- Idle animations
- Greeting when Mac wakes/unlocks
- Good morning / good night messages
- Character waving when application opens
- Character sitting/idle animation
- Character wearing/removing glasses
- Simple settings window
- Start at login
- Quiet hours / Do Not Disturb schedule
- Notification sounds
- Optional sound effects
- Multiple characters/skins
- Custom pixel-art characters
- Reminder statistics
- Streaks
- "character is tired too" style personality messages

However:

**Do not implement unnecessary features just because they are suggested.**

Keep the initial application small. and every customastion should be in the user settings, from the app. 

---

# 5. Technology

Use:

- Swift
- SwiftUI
- Native macOS APIs where appropriate
- Xcode
- macOS-native window management
- Swift Package Manager where appropriate

The application must run locally on a Mac m1 silicon chips .

I want the project to be understandable by a developer who knows basic programming but is not an expert in macOS development.

Avoid unnecessary third-party dependencies unless there is a strong reason.

Explain why any dependency is required.

---

# 6. Desktop Window Behaviour

This is important.

character should NOT behave like a normal application window.

Investigate and implement an appropriate macOS window configuration for:

- transparent background
- floating/desktop companion behaviour
- no unnecessary title bar
- appropriate window level
- character visible without a large opaque rectangle
- mouse interaction
- dragging, if appropriate
- keeping the character visible
- handling multiple monitors if feasible
- respecting screen boundaries

The character should appear like a small desktop companion.

Do not blindly implement a solution.

First explain:

1. Which macOS APIs/window configuration you recommend.
2. Why.
3. Any limitations.
4. How it behaves with multiple displays.
5. Whether it appears above other applications.
6. Whether it interferes with clicking other applications.

Then once i confirm then implement it

---

# 7. Pixel-Art Character

The character will be created separately using AI-generated pixel-art frames.

I will provide the character images.

The application should therefore NOT tightly couple animation logic to a single image.

Design an asset system where frames can easily be replaced.

Required animation states for the initial character:

```text
idle
walking
waving
glasses_on
glasses_off
water_reminder
eye_break
```

If some of these are better represented as combinations of animation states rather than separate animations, explain the recommended architecture. and give me prompt to generate and save it in a which folder say that too. 

---

# 8. Pixel-Art Asset Organization

Recommend the best format.

Compare:

### Option A

Individual PNG frames

### Option B

Sprite sheets

### Option C

GIF files

### Option D

Animated WebP/APNG if practical for native macOS

Tell me which one you recommend for a SwiftUI/macOS application and WHY.

My initial preference is to use **individual PNG frames or sprite sheets**, because I want precise control over animation timing.

Do NOT assume GIF is the best solution. and also later we should be able to paste the prompt generate it and upload in the setting according to that also tell me, the prompt inststutions, 
so that if anyone can use there character according to there needs.

Create a clean asset structure such as:

```text
character_ai_twin/
├── App/
├── Core/
├── Features/
├── UI/
├── Animation/
├── Reminders/
├── Window/
├── Models/
├── Services/
├── Utilities/
├── Resources/
│   └── Characters/
│       └── Ai_twin chracter(anyname)/
│           ├── Idle/
│           ├── Walking/
│           ├── Waving/
│           ├── GlassesOn/
│           ├── GlassesOff/
│           ├── WaterReminder/
│           └── EyeBreak/
├── Tests/
└── README.md
```

You may change this structure if you have a better professional architecture. and remeber at the end of the day it should be shareable app with just one tap install to mac and storage is local.

Explain the final folder structure before implementation.

Use predictable frame names such as:

```text
idle_01.png
idle_02.png
idle_03.png

walk_01.png
walk_02.png
walk_03.png
walk_04.png

wave_01.png
wave_02.png
wave_03.png
```

Explain how the animation system discovers/loads these frames. it should be some thing like image is moving its should be like game character.

---

# 9. Pixel-Art Generation Prompts

I will use ChatGPT/nanobananna image generation to create the individual character frames.

Give me separate optimized prompts for generating:

1. Character base/reference image
2. Idle frame
3. Walking animation frames
4. Walking-left frames
5. Walking-right frames
6. Waving animation
7. Glasses ON
8. Glasses OFF
9. Drinking water
10. Eye-break reminder
11. Happy mood
12. Sleep/tired mood

The prompts should focus on **consistent character design** based on the uploaded image.

Describe:

- pixel-art style
- camera/view angle
- character proportions
- clothing
- hairstyle
- facial style
- color palette
- lighting
- background/transparency
- pixel resolution/style
- pose
- consistency requirements

Do NOT invent unnecessary details about the character's physical appearance.

Leave clearly marked placeholders where I can insert my chosen appearance or take it from the image referneced.

The most important requirement is:

**Every generated frame must look like the exact same character.**

Also explain how I should provide a reference image to ChatGPT/nanobananna when generating subsequent frames to maintain consistency.

---

# 10. Test-First Development

This is extremely important.

Before writing the implementation, create a **test plan first**.

I want to follow:

```text
Requirements
    ↓
Architecture
    ↓
Test cases
    ↓
Implementation
    ↓
Run tests
    ↓
Manual macOS testing
    ↓
Polish
```

Do NOT immediately start writing the application.

First provide:

### Unit tests

Examples:

- Water timer starts correctly.
- Water timer triggers at the configured interval.
- Eye-break timer triggers after 40 minutes.
- Test mode correctly changes the interval.
- Snooze resets the correct timer.
- Reminder acknowledgement works.
- Timer cancellation works.
- Timer restart works.
- App launch initializes timers correctly.

### Animation tests

Verify:

- idle animation loads frames
- walking animation loads frames in correct order
- frame timing works
- animation stops correctly
- character returns to idle
- missing asset is handled gracefully

### Window tests

Verify:

- window is created
- transparent background works
- character appears in expected position
- bottom-left positioning works
- screen boundary handling works

### Integration tests

Test:

```text
Launch app
→ character appears
→ greeting animation
→ idle
→ timer expires
→ walking animation
→ bottom-left
→ reminder appears
→ user dismisses
→ return to idle
→ timer restarts
```

### Manual test cases

Create a checklist specifically for running the app on my Mac.

Since we currently cannot test Windows directly, clearly separate:

**Mac automated tests**

**Mac manual tests**

**Future Windows validation**

Do not claim Windows compatibility has been tested.

---

# 11. Windows Compatibility

I eventually want ai_twin character to work on Windows too.

However:

**Do NOT pretend the Windows version has been tested.**

Design the application architecture so that platform-specific code is isolated.

Identify:

```text
Shared logic
        ↓
Platform abstraction
        ↓
macOS implementation
        ↓
Future Windows implementation (phase 2 its later part)
```

For example:

```text
ReminderEngine
AnimationEngine
CharacterState
    ↓
PlatformWindowManager
    ├── MacWindowManager
    └── FutureWindowsWindowManager
```

Explain which parts can remain shared and which parts will require a Windows implementation.

Do NOT add Windows code unless necessary for the architecture and do not implement but give scope for future implematations.

---

# 12. Packaging / Distribution

I want Ai_twin chracter to eventually be easy for other people to download/use.

Design the project so it can eventually be distributed as:

- GitHub repository
- macOS application
- potentially a `.dmg`
- potentially a GitHub Release
- potentially Homebrew later

For now, prioritize:

**Clone GitHub repository → open in Xcode → Build & Run**

Explain the difference between:

- source code
- Xcode project
- Swift Package
- macOS `.app`
- `.dmg`
- GitHub Release

Also explain whether calling the project a "Swift Package" is actually appropriate.

If a normal Xcode macOS application with Swift Package Manager dependencies is more appropriate, say so.

---

# 13. GitHub README

Create a professional README.

It should contain:

```text
Ai_twin chracter
AI Digital Desktop Companion

Features

Demo

Requirements

Installation

Running locally

Project structure

Adding your own character

Creating animation frames

Configuration

Testing

Building

Packaging

Windows roadmap

Architecture

Contributing

License
```

Include clear commands where appropriate.

Example:

```bash
git clone ...
cd ...
open Ai_twin chracter.xcodeproj
```

Do not invent repository URLs.

Use placeholders where necessary.

---

# 14. Configuration

Centralize configurable values.

For example:

```swift
struct Ai_twin chracterConfiguration {
    let waterReminderInterval: TimeInterval
    let eyeBreakInterval: TimeInterval
    let walkingSpeed: Double
    let animationFrameDuration: TimeInterval
}
```

Development configuration should allow:

```text
water reminder = 30 seconds
eye break = 60 seconds
```

while production defaults are:

```text
water reminder = configurable
eye break = 40 minutes
```

Do not scatter magic numbers throughout the code.

---

# 15. Architecture

Before coding, propose a clean architecture.

I expect something approximately like:

```text
UI
↓
View Models
↓
Domain / Reminder Logic
↓
Services
↓
Platform-specific macOS layer
```

Keep responsibilities separated.

For example:

```text
ReminderEngine
TimerService
AnimationEngine
CharacterStateManager
WindowManager
ScreenPositionManager
SettingsManager
```

Avoid creating massive Swift files.

Prefer small, focused files.

---

# 16. Error Handling

The application should gracefully handle:

- missing animation frames
- invalid image files
- timer failures
- screen-size changes
- display disconnects
- application launch issues
- permission-related problems where applicable

The app should fail gracefully rather than crash because one animation frame is missing.

---

# 17. UX Principle

Ai_twin chracter should feel:

- cute
- lightweight
- calm
- unobtrusive
- slightly playful
- useful

Avoid:

- excessive notifications
- huge windows
- annoying sounds
- unnecessary UI
- resource-heavy animations

The character should feel like a tiny companion living on the desktop.

---

# 18. Development Process

Follow this exact process.

## Phase 1 — Product analysis

First analyze the requirements.

Identify:

- ambiguities
- technical risks
- macOS limitations
- assumptions
- features that should be postponed

## Phase 2 — MVP definition

Define exactly what belongs in Version 1.

## Phase 3 — Architecture

Provide the architecture and folder structure.

## Phase 4 — Asset specification

Define:

- image dimensions
- frame naming
- folder structure
- animation FPS
- recommended image format
- transparency requirements

## Phase 5 — Test plan

Write the tests BEFORE implementation.

## Phase 6 — Implementation

Only after the above, implement the application.

Create the files one by one and provide complete code.

## Phase 7 — Xcode setup

Give exact instructions for:

- creating/opening the project
- configuring the target
- adding assets
- running tests
- Build & Run

## Phase 8 — Manual testing

Give me a step-by-step checklist to verify the application on my Mac.

## Phase 9 — GitHub

Create the final README and explain how to publish the project.

---

# 19. Important Constraints

Do not:

- over-engineer the MVP
- add unnecessary dependencies
- assume Windows has been tested
- use GIF just because it is convenient
- hard-code timer values everywhere
- put all logic in ContentView\.swift
- create huge files
- skip testing
- start coding before presenting the architecture and tests
- invent missing character design details
- invent GitHub URLs
- claim something works on macOS without giving me a way to test it

If you need to make an assumption, explicitly label it:

**Assumption:** ...

If something requires verification on my Mac, say:

**Needs verification on macOS:** ...

---

# 20. Your First Response

DO NOT start coding yet.

Your first response should contain only:

1. Your understanding of Ai_twin chracter
2. Recommended MVP
3. Suggested additional features categorized as MVP / V1.1 / Future
4. Recommended architecture
5. Recommended folder structure
6. Recommended pixel-art asset format
7. Character animation strategy
8. macOS window strategy
9. Test-first strategy
10. Mac vs future Windows architecture
11. Potential technical risks
12. Exact next steps

After I approve the architecture, proceed to **Phase 4: Asset Specification → Phase 5: Test Plan → Phase 6: Implementation**.
