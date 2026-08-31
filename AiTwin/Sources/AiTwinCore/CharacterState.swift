import Foundation

/// Why the character was summoned onto the screen.
public enum SummonPurpose: Equatable, Sendable {
    case greeting
    case reminder(ReminderKind)
    /// Popping out to celebrate — currently only when the daily water goal is met.
    case celebration

    /// How the character arrives on screen for this purpose.
    ///
    /// Greetings and celebrations *appear* — she pops into place at the corner
    /// rather than trudging in from off screen. Walking in every single time
    /// reads as repetitive, and a spontaneous "hello" is not something you walk
    /// across the screen to deliver. Reminders still walk, because she is coming
    /// over to tell you something.
    public var entrance: Entrance {
        switch self {
        case .greeting, .celebration: return .pop
        case .reminder:               return .walk
        }
    }
}

/// How the character gets on screen.
public enum Entrance: Equatable, Sendable {
    /// Materialises in place at the resting corner.
    case pop
    /// Walks in from the nearest screen edge.
    case walk
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

    /// The transition table. Pure and static so it can be tested exhaustively
    /// without constructing a machine.
    public static func nextState(from state: CharacterState, on event: CharacterEvent) -> CharacterState {
        switch (state, event) {
        case (_, .reset):
            return .hidden

        case (.hidden, .summon(let purpose)):
            return purpose.entrance == .pop ? .appearing(purpose) : .entering(purpose)

        // Already on screen: switch straight to the new purpose instead of
        // walking off and back on, which would look like a glitch.
        case (.idle, .summon(.reminder(let kind))),
             (.greeting, .summon(.reminder(let kind))),
             (.celebrating, .summon(.reminder(let kind))),
             (.appearing, .summon(.reminder(let kind))),
             (.reminding, .summon(.reminder(let kind))):
            return .reminding(kind)

        // Already on screen and something worth celebrating happened.
        case (.idle, .summon(.celebration)),
             (.greeting, .summon(.celebration)):
            return .celebrating

        case (.leaving, .summon(let purpose)):
            return .entering(purpose)

        case (.entering(let purpose), .arrivedAtCorner),
             (.appearing(let purpose), .arrivedAtCorner):
            switch purpose {
            case .greeting:          return .greeting
            case .celebration:       return .celebrating
            case .reminder(let k):   return .reminding(k)
            }

        case (.greeting, .animationFinished),
             (.celebrating, .animationFinished):
            return .idle

        case (.reminding(.eyeBreak), .breakStarted):
            return .onBreak

        case (.onBreak, .breakFinished):
            return .leaving

        case (.reminding, .reminderResolved):
            return .leaving

        case (.idle, .restTimeout),
             (.celebrating, .restTimeout),
             (.onBreak, .restTimeout):
            return .leaving

        case (.leaving, .exitedScreen):
            return .hidden

        default:
            return state
        }
    }
}
