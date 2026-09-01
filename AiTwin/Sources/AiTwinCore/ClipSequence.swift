import Foundation

/// One beat of a behaviour: a clip, and how long to stay on it.
public struct ClipStep: Equatable, Sendable {
    public let clip: String
    /// How long this beat lasts. Ignored when `holdsUntilFinished` is set.
    public let duration: TimeInterval
    /// Play the clip once through and move on when its last frame lands.
    /// Only meaningful for non-looping clips.
    public let holdsUntilFinished: Bool
    /// Stay here until something outside the sequence moves things on — a
    /// button press, a countdown ending, the user coming back.
    public let holdsIndefinitely: Bool

    public init(
        _ clip: String,
        duration: TimeInterval = 1,
        holdsUntilFinished: Bool = false,
        holdsIndefinitely: Bool = false
    ) {
        self.clip = clip
        self.duration = max(0, duration)
        self.holdsUntilFinished = holdsUntilFinished
        self.holdsIndefinitely = holdsIndefinitely
    }
}

/// A short piece of acting, assembled from clips.
///
/// Standing up to stretch is three beats -- sitting, standing, reaching -- not
/// one animation. Building those in code rather than baking them into the
/// artwork means every pack gets the same choreography for free, a pack missing
/// one clip degrades a beat instead of losing the whole behaviour, and the
/// timing can be tuned without regenerating a single image.
public struct ClipSequence: Equatable, Sendable {
    public let name: String
    public let steps: [ClipStep]

    public init(name: String, steps: [ClipStep]) {
        self.name = name
        self.steps = steps
    }

    /// Total run time. Indefinite beats count as zero, since they end on an
    /// outside event rather than the clock.
    public var duration: TimeInterval {
        steps.reduce(0) { $0 + ($1.holdsIndefinitely ? 0 : $1.duration) }
    }

    public var clips: [String] { steps.map(\.clip) }

    // MARK: The catalogue

    /// She walks over, stretches, and goes. Sitting down first was tried and
    /// dropped: she has *walked in* to tell you something, so sitting down to
    /// demonstrate reads as a detour, and the extra beats delayed the message.
    public static let stretchRoutine = ClipSequence(name: "stretch", steps: [
        ClipStep(ClipName.stretch, duration: 3.4),
        ClipStep(ClipName.idle, duration: 0.9),
    ])

    /// A yawn that settles into sleep. The last beat holds: she stays asleep on
    /// the desktop until something wakes her.
    public static let sleepRoutine = ClipSequence(name: "sleep", steps: [
        ClipStep(ClipName.yawn, duration: 2.6),
        ClipStep(ClipName.sleep, holdsIndefinitely: true),
    ])

    /// Ending a focus session: she looks up from the book, stands, and cheers.
    public static let focusFinishedRoutine = ClipSequence(name: "focusFinished", steps: [
        ClipStep(ClipName.focus, duration: 0.7),
        ClipStep(ClipName.idle, duration: 0.8),
        ClipStep(ClipName.cheer, duration: 2.6),
    ])

    /// Logging a glass of water: a small pleased jump, no words.
    public static let waterLoggedRoutine = ClipSequence(name: "waterLogged", steps: [
        ClipStep(ClipName.happy, duration: 2.2),
    ])

    /// A streak milestone deserves more than the everyday jump. Wordless: the
    /// jump says it, and a cloud over a jumping character has to sit so high
    /// that it reads as detached from her.
    public static let milestoneRoutine = ClipSequence(name: "milestone", steps: [
        ClipStep(ClipName.happy, duration: 0.7),
        ClipStep(ClipName.cheer, duration: 3.0),
    ])

    /// Hello: a wave that settles.
    public static let greetingRoutine = ClipSequence(name: "greeting", steps: [
        ClipStep(ClipName.wave, duration: 2.6),
        ClipStep(ClipName.idle, duration: 1.2),
    ])

    /// Concern holds until you answer her.
    public static let concernRoutine = ClipSequence(name: "concern", steps: [
        ClipStep(ClipName.concerned, holdsIndefinitely: true),
    ])

    /// Peeking round the edge holds for as long as the caller allows.
    public static let peekRoutine = ClipSequence(name: "peek", steps: [
        ClipStep(ClipName.peek, holdsIndefinitely: true),
    ])

    /// Every routine, for the developer preview.
    public static let all: [ClipSequence] = [
        greetingRoutine, waterLoggedRoutine, stretchRoutine, focusFinishedRoutine,
        milestoneRoutine, sleepRoutine, concernRoutine, peekRoutine,
    ]

    public static func named(_ name: String) -> ClipSequence? {
        all.first { $0.name == name }
    }
}

/// Walks a `ClipSequence` forward in time.
///
/// Driven by an explicit clock like everything else in Core, so a four-second
/// routine is verifiable in microseconds instead of being watched.
public final class SequencePlayer {
    public private(set) var sequence: ClipSequence?
    public private(set) var stepIndex: Int = 0
    public private(set) var isFinished: Bool = true

    private var stepStartedAt: Date?

    public init() {}

    public var currentStep: ClipStep? {
        guard let sequence, sequence.steps.indices.contains(stepIndex) else { return nil }
        return sequence.steps[stepIndex]
    }

    public var currentClip: String? { currentStep?.clip }

    /// True when the sequence is parked on a beat that ends on an outside event.
    public var isHolding: Bool { currentStep?.holdsIndefinitely ?? false }

    public func start(_ sequence: ClipSequence, at now: Date) {
        self.sequence = sequence
        stepIndex = 0
        stepStartedAt = now
        isFinished = sequence.steps.isEmpty
    }

    public func stop() {
        sequence = nil
        stepIndex = 0
        stepStartedAt = nil
        isFinished = true
    }

    /// Advances if the current beat is over.
    /// - Parameter clipFinished: whether the current clip has played out, for
    ///   beats that wait on the animation rather than a duration.
    /// - Returns: true when the clip changed, so the caller can swap artwork.
    @discardableResult
    public func tick(at now: Date, clipFinished: Bool = false) -> Bool {
        guard let sequence, !isFinished, let started = stepStartedAt else { return false }
        guard let step = currentStep, !step.holdsIndefinitely else { return false }

        let elapsed = now.timeIntervalSince(started)
        let done = step.holdsUntilFinished ? clipFinished : elapsed >= step.duration
        guard done else { return false }

        let next = stepIndex + 1
        if next < sequence.steps.count {
            stepIndex = next
            stepStartedAt = now
            return true
        }
        isFinished = true
        return false
    }

    /// Ends an indefinite beat and moves on. Called when the outside event that
    /// the beat was waiting for happens.
    @discardableResult
    public func release(at now: Date) -> Bool {
        guard let sequence, currentStep?.holdsIndefinitely == true else { return false }
        let next = stepIndex + 1
        if next < sequence.steps.count {
            stepIndex = next
            stepStartedAt = now
            return true
        }
        isFinished = true
        return false
    }
}
