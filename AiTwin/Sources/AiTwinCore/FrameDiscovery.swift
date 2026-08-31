import Foundation

/// Turns a directory listing into an ordered list of animation frames.
///
/// Pure string work, deliberately: it is the part of asset loading most likely
/// to be wrong (ordering, gaps, stray files), and keeping it free of the file
/// system means it can be tested exhaustively without fixtures on disk.
public enum FrameDiscovery {

    /// Supported frame extensions. PNG is the recommended format (Docs/ASSETS.md);
    /// the others are accepted so a user's pack does not fail over a file suffix.
    public static let supportedExtensions: Set<String> = ["png", "tiff", "tif"]

    /// Selects the files named `<prefix>_<number>.<ext>` and returns them sorted
    /// by that number.
    ///
    /// Sorting numerically rather than alphabetically is the whole point: a
    /// lexicographic sort puts `walk_10.png` before `walk_2.png` and the
    /// character moonwalks. Gaps are tolerated -- `01, 02, 05` plays as three
    /// frames -- so a missing file degrades the animation instead of breaking it.
    public static func orderedFrames(withPrefix prefix: String, in fileNames: [String]) -> [String] {
        let matches: [(index: Int, name: String)] = fileNames.compactMap { fileName in
            guard let index = frameIndex(of: fileName, prefix: prefix) else { return nil }
            return (index, fileName)
        }
        return matches
            // Tie-break on name so the order is deterministic if a pack somehow
            // contains both walk_1.png and walk_01.png.
            .sorted { $0.index == $1.index ? $0.name < $1.name : $0.index < $1.index }
            .map(\.name)
    }

    /// Parses the numeric index out of a frame filename, or nil if the name does
    /// not belong to this clip.
    ///
    /// Matching requires the underscore and a purely numeric tail, which is what
    /// stops the `idle` clip from swallowing `idle_glasses_01.png`.
    public static func frameIndex(of fileName: String, prefix: String) -> Int? {
        let name = (fileName as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }

        let base = (name as NSString).deletingPathExtension
        let expectedPrefix = prefix + "_"
        guard base.lowercased().hasPrefix(expectedPrefix.lowercased()) else { return nil }

        let tail = String(base.dropFirst(expectedPrefix.count))
        guard !tail.isEmpty, tail.allSatisfy(\.isNumber) else { return nil }
        return Int(tail)
    }
}
