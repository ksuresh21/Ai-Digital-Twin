import Foundation

/// The two things AiTwin reminds you about in Version 1.
public enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case water
    case eyeBreak

    public var displayName: String {
        switch self {
        case .water:    return "Water"
        case .eyeBreak: return "Eye Break"
        }
    }

    /// The animation clip played while this reminder is on screen.
    public var clipName: String {
        switch self {
        case .water:    return ClipName.waterReminder
        case .eyeBreak: return ClipName.eyeBreak
        }
    }

    public var acknowledgeTitle: String {
        switch self {
        case .water:    return "Done 💧"
        case .eyeBreak: return "Looked away 👀"
        }
    }
}
