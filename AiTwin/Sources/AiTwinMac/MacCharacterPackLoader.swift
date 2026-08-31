import AppKit
import AiTwinCore
import AiTwinPlatform

/// Finds character packs on disk and turns folders of PNGs into `AnimationClip`s.
///
/// Two locations are searched, user packs first:
///
///   1. `~/Library/Application Support/AiTwin/Characters/<Name>/`  -- yours
///   2. `AiTwin.app/Contents/Resources/Characters/<Name>/`          -- bundled
///
/// A user pack shadows a bundled one of the same name, which is what makes
/// "generate your own character and drop it in" work without a rebuild. Nothing
/// here throws: a pack that is missing, unreadable or half-finished produces a
/// pack with fewer clips, and `CharacterPack.resolveClip` degrades from there.
public final class MacCharacterPackLoader: CharacterPackLoading {

    private let fileManager: FileManager
    private let bundle: Bundle

    public init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    /// `~/Library/Application Support/AiTwin/Characters`. Created on demand so
    /// the Settings window can always reveal it in Finder.
    public var userPacksDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AiTwin/Characters", isDirectory: true)
    }

    /// Bundled packs. Also checks the source tree so `swift run` works during
    /// development, before there is an `.app` at all.
    private var bundledPacksDirectory: URL? {
        if let resourceURL = bundle.resourceURL {
            let packs = resourceURL.appendingPathComponent("Characters", isDirectory: true)
            if fileManager.fileExists(atPath: packs.path) { return packs }
        }
        // Development fallback: <package root>/Resources/Characters
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AiTwinMac
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Resources/Characters", isDirectory: true)
        return fileManager.fileExists(atPath: devPath.path) ? devPath : nil
    }

    public func availablePackNames() -> [String] {
        var names: [String] = []
        for directory in [userPacksDirectory, bundledPacksDirectory].compactMap({ $0 }) {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if !names.contains(url.lastPathComponent) { names.append(url.lastPathComponent) }
            }
        }
        return names.sorted()
    }

    public func createUserPacksDirectoryIfNeeded() {
        try? fileManager.createDirectory(at: userPacksDirectory, withIntermediateDirectories: true)
    }

    /// Resolves a pack folder, preferring a user pack over a bundled one.
    private func packDirectory(named name: String) -> URL? {
        let candidates = [
            userPacksDirectory.appendingPathComponent(name, isDirectory: true),
            bundledPacksDirectory?.appendingPathComponent(name, isDirectory: true),
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    public func loadPack(named name: String, frameDuration: TimeInterval) -> CharacterPack? {
        guard let directory = packDirectory(named: name) else {
            NSLog("[AiTwin] Character pack '\(name)' not found.")
            return nil
        }

        var clips: [String: AnimationClip] = [:]
        for definition in ClipDefinition.standard {
            let folder = directory.appendingPathComponent(definition.folder, isDirectory: true)

            // Base clip, then its glasses variant. Both are optional.
            if let clip = loadClip(
                name: definition.name,
                prefix: definition.filePrefix,
                in: folder,
                frameDuration: frameDuration,
                loops: definition.loops
            ) {
                clips[definition.name] = clip
            }

            let glassesName = ClipName.glassesVariant(of: definition.name)
            if let glassesClip = loadClip(
                name: glassesName,
                prefix: "\(definition.filePrefix)_glasses",
                in: folder,
                frameDuration: frameDuration,
                loops: definition.loops
            ) {
                clips[glassesName] = glassesClip
            }
        }

        let pack = CharacterPack(name: name, clips: clips)
        if !pack.missingClipNames.isEmpty {
            NSLog("[AiTwin] Pack '\(name)' is missing clips: \(pack.missingClipNames.joined(separator: ", ")). They will fall back to idle.")
        }
        return pack.isUsable ? pack : nil
    }

    private func loadClip(
        name: String,
        prefix: String,
        in folder: URL,
        frameDuration: TimeInterval,
        loops: Bool
    ) -> AnimationClip? {
        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return nil }
        let ordered = FrameDiscovery.orderedFrames(withPrefix: prefix, in: fileNames)
        guard !ordered.isEmpty else { return nil }

        // Discard files that are named right but are not decodable images -- a
        // truncated download should cost one frame, not the whole animation.
        let validPaths = ordered.compactMap { fileName -> String? in
            let path = folder.appendingPathComponent(fileName).path
            guard NSImage(contentsOfFile: path) != nil else {
                NSLog("[AiTwin] Skipping unreadable frame: \(path)")
                return nil
            }
            return path
        }
        guard !validPaths.isEmpty else { return nil }

        return AnimationClip(name: name, framePaths: validPaths, frameDuration: frameDuration, loops: loops)
    }
}

/// Keeps decoded frames in memory so the animation timer never touches the disk.
///
/// A pixel-art frame is a few kilobytes, and a whole pack is a handful of
/// megabytes at most, so caching every frame is cheaper than the alternative and
/// keeps the animation from stuttering on first play.
@MainActor
public final class FrameImageCache {
    private var images: [String: NSImage] = [:]

    public init() {}

    public func image(at path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images[path] = image
        return image
    }

    /// Decodes a whole pack up front, so the first walk is as smooth as the tenth.
    public func preload(_ pack: CharacterPack) {
        for clip in pack.clips.values {
            for path in clip.framePaths { _ = image(at: path) }
        }
    }

    public func clear() { images.removeAll() }
}
