import Foundation

/// Why the character was summoned onto the screen.
public enum SummonPurpose: Equatable, Sendable {
    case greeting
    case reminder(ReminderKind)
    /// Popping out to celebrate — currently only when the daily water goal is met.
    case celebration
    /// Showing one named clip on demand, for testing from Settings.
    case preview(String)
    /// Playing a whole routine on demand, so a behaviour can be checked end to
    /// end rather than one pose at a time.
    case previewSequence(String)
    /// An unprompted line. Uses the peeking pose, so she does not walk in.
    case chatter
    /// Sitting down to work alongside you for a focus session.
    case focus
    /// Showing how she feels about how the day is going.
    case mood(MoodMonitor.Mood)

    /// How the character arrives on screen for this purpose.
    ///
    /// Greetings and celebrations *appear* — she pops into place at the corner
    /// rather than trudging in from off screen. Walking in every single time
    /// reads as repetitive, and a spontaneous "hello" is not something you walk
    /// across the screen to deliver. Reminders still walk, because she is coming
    /// over to tell you something.
    public var entrance: Entrance {
        switch self {
        case .greeting, .celebration, .focus: return .pop
        // A preview of the peek slides in from the edge like the real thing,
        // rather than popping at the resting corner -- otherwise the Developer
        // tab shows a placement and an exit the feature does not have.
        case .preview(let clip):
            return clip == ClipName.peek ? .slide : .pop
        case .previewSequence(let name):
            return name == ClipSequence.peekRoutine.name ? .slide : .pop
        // Chatter is neither: she leans in from off the edge, already talking.
        // Popping first meant a silent appearance at the corner followed 0.9s
        // later by the window jumping to the edge and the message arriving --
        // one summon that read as two visits.
        case .chatter:                                            return .slide
        case .reminder:                                           return .walk
        // Concern is an errand -- she comes over to say it, the same as a
        // reminder. Sleepiness is not; she just appears, tired.
        case .mood(let mood):                                     return mood == .concerned ? .walk : .pop
        }
    }
}

/// How the character gets on screen.
public enum Entrance: Equatable, Sendable {
    /// Materialises in place at the resting corner.
    case pop
    /// Walks in from the nearest screen edge.
    case walk
    /// Slides straight into the destination state from just off the edge, with
    /// no separate arrival step. The destination positions and animates itself.
    case slide
}

/// What the character is doing right now.
///
/// One enum, one source of truth. The window manager reads it to decide whether
/// to move the window, and the view reads it to decide which clip to draw --
/// neither keeps a second copy of "is she walking?", which is where this kind of
/// code usually goes wrong.
public enum CharacterState: Equatable, Sendable {
    /// Off screen. The window is ordered out, costing nothing.
    case hidden
    /// Walking in from the screen edge toward the resting corner.
    case entering(SummonPurpose)
    /// Materialising in place at the resting corner.
    case appearing(SummonPurpose)
    /// Waving hello.
    case greeting
    /// Cheering. Used for the daily water goal.
    case celebrating
    /// Waiting out a timed eye break while the screen is dimmed.
    case onBreak
    /// Showing one clip on demand so it can be checked from Settings.
    case previewing(clip: String)
    /// Playing a whole routine on demand.
    case previewingSequence(name: String)
    /// Peeking in to say something unprompted.
    case chattering
    /// Sitting and reading through a focus session. Near-motionless by design.
    case focusing
    /// Expressing concern, or looking sleepy.
    case feeling(MoodMonitor.Mood)
    /// Dozed off. Follows a yawn at night, and stays until something happens.
    case sleeping
    /// Standing at the corner with a speech bubble up.
    case reminding(ReminderKind)
    /// Standing at the corner, no bubble.
    case idle
    /// Walking back off screen.
    case leaving

    public var isVisible: Bool { self != .hidden }

    /// True while the window's position should be animating.
    public var isWalking: Bool {
        switch self {
        case .entering, .leaving: return true
        default: return false
        }
    }

    /// The animation clip this state draws.
    ///
    /// Note `entering` and `leaving` share the walk clip and differ only in
    /// `facing` -- one walk cycle, mirrored. See Docs/ASSETS.md.
    public var clipName: String {
        switch self {
        case .hidden:            return ClipName.idle
        case .entering:          return ClipName.walk
        case .appearing:         return ClipName.wave
        case .onBreak:           return ClipName.eyeBreak
        case .previewing(let c):  return c
        case .previewingSequence(let name):
            return ClipSequence.named(name)?.clips.first ?? ClipName.idle
        case .chattering:        return ClipName.peek
        case .focusing:          return ClipName.focus
        case .feeling(let mood): return mood.clipName
        case .sleeping:          return ClipName.sleep
        case .leaving:           return ClipName.walk
        case .greeting:          return ClipName.wave
        case .celebrating:       return ClipName.happy
        case .idle:              return ClipName.idle
        case .reminding(let k):  return k.clipName
        }
    }
}

/// Events that can move the character between states.
public enum CharacterEvent: Equatable, Sendable {
    case summon(SummonPurpose)
    /// The walk-in finished and the character is at the corner.
    case arrivedAtCorner
    /// A one-shot clip (the wave) played its last frame.
    case animationFinished
    /// The user pressed Dismiss or Snooze.
    case reminderResolved
    /// The user accepted an eye break; the countdown starts.
    case breakStarted
    /// The eye-break countdown ran out, or was skipped.
    case breakFinished
    /// The focus session ended.
    case focusFinished
    /// The yawn finished and it is late: she settles down to sleep.
    case fellAsleep
    /// The character has been standing around long enough; send it away.
    case restTimeout
    /// The walk-out finished and the character is off screen.
    case exitedScreen
    /// Force back to hidden -- display disconnect, settings change, quit.
    case reset
}

/// The character's state machine.
///
/// Small and explicit: every legal transition is one line, and anything not
/// listed is ignored rather than crashing. An unexpected event on a desktop pet
/// should mean "nothing happens", never "the app dies".
public final class CharacterStateMachine {
    public private(set) var state: CharacterState = .hidden
    /// Fired on every *change* of state, never on a no-op transition.
    public var onStateChange: ((CharacterState) -> Void)?

    public init(state: CharacterState = .hidden) {
        self.state = state
    }

    @discardableResult
    public func handle(_ event: CharacterEvent) -> CharacterState {
        let next = Self.nextState(from: state, on: event)
        guard next != state else { return state }
        state = next
        onStateChange?(next)
        return next
    }

    /// Where a summon lands from off screen.
    ///
    /// A `.slide` purpose skips the arrival step entirely and goes straight to
    /// its destination, because the destination state does its own positioning
    /// and animation. Routing it through `.appearing` produced a silent
    /// pop-in at the resting corner followed by a jump to the real position.
    private static func arrival(for purpose: SummonPurpose) -> CharacterState {
        switch purpose.entrance {
        case .pop:   return .appearing(purpose)
        case .walk:  return .entering(purpose)
        case .slide: return destination(for: purpose)
        }
    }

    /// What a purpose becomes once she is in place.
    private static func destination(for purpose: SummonPurpose) -> CharacterState {
        switch purpose {
        case .greeting:          return .greeting
        case .celebration:       return .celebrating
        case .preview(let clip): return .previewing(clip: clip)
        case .previewSequence(let name): return .previewingSequence(name: name)
        case .chatter:           return .chattering
        case .focus:             return .focusing
        case .mood(let mood):    return .feeling(mood)
        case .reminder(let k):   return .reminding(k)
        }
    }

    /// The transition table. Pure and static so it can be tested exhaustively
    /// without constructing a machine.
    public static func nextState(from state: CharacterState, on event: CharacterEvent) -> CharacterState {
        switch (state, event) {
        case (_, .reset):
            return .hidden

        case (.hidden, .summon(let purpose)):
            return arrival(for: purpose)

        // Already on screen: switch straight to the new purpose instead of
        // walking off and back on, which would look like a glitch.
        case (.idle, .summon(.reminder(let kind))),
             (.greeting, .summon(.reminder(let kind))),
             (.celebrating, .summon(.reminder(let kind))),
             (.previewing, .summon(.reminder(let kind))),
             (.previewingSequence, .summon(.reminder(let kind))),
             (.chattering, .summon(.reminder(let kind))),
             (.feeling, .summon(.reminder(let kind))),
             (.sleeping, .summon(.reminder(let kind))),
             (.appearing, .summon(.reminder(let kind))),
             (.reminding, .summon(.reminder(let kind))):
            return .reminding(kind)

        // Already on screen and something worth celebrating happened.
        case (.idle, .summon(.celebration)),
             (.greeting, .summon(.celebration)):
            return .celebrating

        case (.previewing, .summon(.preview(let clip))),
             (.previewingSequence, .summon(.preview(let clip))),
             (.idle, .summon(.preview(let clip))):
            return .previewing(clip: clip)

        // Starting a focus session while she is already on screen sits her
        // down where she stands, rather than doing nothing at all.
        case (.idle, .summon(.focus)),
             (.greeting, .summon(.focus)),
             (.celebrating, .summon(.focus)),
             (.chattering, .summon(.focus)),
             (.feeling, .summon(.focus)),
             (.sleeping, .summon(.focus)),
             (.previewing, .summon(.focus)),
             (.previewingSequence, .summon(.focus)):
            return .focusing

        case (.previewing, .summon(.previewSequence(let name))),
             (.previewingSequence, .summon(.previewSequence(let name))),
             (.idle, .summon(.previewSequence(let name))):
            return .previewingSequence(name: name)

        case (.leaving, .summon(let purpose)):
            return arrival(for: purpose)

        case (.entering(let purpose), .arrivedAtCorner),
             (.appearing(let purpose), .arrivedAtCorner):
            return destination(for: purpose)

        case (.greeting, .animationFinished),
             (.celebrating, .animationFinished):
            return .idle

        case (.reminding, .summon(.celebration)):
            return .celebrating

        case (.reminding(.eyeBreak), .breakStarted):
            return .onBreak

        case (.onBreak, .breakFinished):
            return .leaving

        // Focus outranks a *timer*, but not a deliberate summon: the session's
        // own break has to be able to get her out of the chair, and a held
        // reminder released at the break must be able to reach her.
        case (.focusing, .focusFinished):
            return .leaving

        case (.focusing, .summon(.celebration)),
             (.feeling(.concerned), .summon(.celebration)):
            return .celebrating

        case (.focusing, .summon(.reminder(let kind))):
            return .reminding(kind)

        case (.reminding, .reminderResolved):
            return .leaving

        case (.idle, .restTimeout),
             (.celebrating, .restTimeout),
             (.onBreak, .restTimeout),
             (.previewing, .restTimeout),
             (.previewingSequence, .restTimeout),
             (.chattering, .restTimeout),
             (.feeling(.concerned), .restTimeout),
             (.sleeping, .restTimeout):
            return .leaving

        // A yawn at night settles into sleep instead of walking off.
        case (.feeling(.sleepy), .fellAsleep):
            return .sleeping

        case (.feeling(.sleepy), .restTimeout):
            return .leaving

        case (.leaving, .exitedScreen):
            return .hidden

        default:
            return state
        }
    }
}
