import AppKit
import UniformTypeIdentifiers
import AiTwinCore

/// Installs a character pack from a folder or a `.zip`, normalising it on the way in.
///
/// Normalising in the app rather than requiring the Python script means a pack
/// someone else made — however they generated it, whatever zoom each clip came
/// out at — lands on one consistent scale and one shared floor. That is the
/// difference between "drag this zip in" and "install Python first".
///
/// The arithmetic lives in `PackGeometry` in Core, where it is unit-tested. This
/// type only reads pixels and writes files.
public final class PackInstaller {

    public enum Failure: LocalizedError {
        case notReadable
        case noFramesFound
        case unpackFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notReadable:
                return "That file could not be read."
            case .noFramesFound:
                return "No character frames were found. Folders should be named after the animation — Idle, Walking, Waving — with PNGs inside."
            case .unpackFailed(let detail):
                return "The zip could not be unpacked: \(detail)"
            case .writeFailed(let detail):
                return "The pack could not be saved: \(detail)"
            }
        }
    }

    public struct Result: Sendable {
        public let name: String
        public let clipsInstalled: [String]
        public let framesInstalled: Int
        public let clipsMissing: [String]
        public let canvas: String
    }

    private let fileManager: FileManager
    private let destinationRoot: URL

    public init(fileManager: FileManager = .default, destinationRoot: URL) {
        self.fileManager = fileManager
        self.destinationRoot = destinationRoot
    }

    /// Installs from a `.zip` or a folder. The pack is named after the archive
    /// or folder unless a name is given.
    public func install(from source: URL, named overrideName: String? = nil) throws -> Result {
        let isZip = source.pathExtension.lowercased() == "zip"
        let workingDirectory: URL
        var scratch: URL?

        if isZip {
            let unpacked = try unzip(source)
            scratch = unpacked
            // A zip usually contains one wrapper folder; step into it so clip
            // folders are found where they are expected.
            workingDirectory = singleSubfolder(of: unpacked) ?? unpacked
        } else {
            workingDirectory = source
        }
        defer { if let scratch { try? fileManager.removeItem(at: scratch) } }

        let name = overrideName
            ?? (isZip ? source.deletingPathExtension().lastPathComponent : source.lastPathComponent)

        let discovered = try discoverFrames(in: workingDirectory)
        guard !discovered.isEmpty else { throw Failure.noFramesFound }

        return try normaliseAndWrite(discovered, name: sanitise(name))
    }

    /// Keeps a pack name usable as a folder name, and non-empty.
    private func sanitise(_ raw: String) -> String {
        let cleaned = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Character" : cleaned
    }

    // MARK: Reading

    private func unzip(_ archive: URL) throws -> URL {
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("aitwin-import-\(UUID().uuidString)")
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)

        // ditto rather than a zip library: it ships with macOS, handles the
        // resource forks and __MACOSX noise that Finder's "Compress" adds, and
        // adds no dependency.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, scratch.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do { try process.run() } catch { throw Failure.unpackFailed(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.unpackFailed(detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }
        return scratch
    }

    private func singleSubfolder(of directory: URL) -> URL? {
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let folders = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && $0.lastPathComponent != "__MACOSX"
        }
        // Only step in if there is exactly one and it is not itself a clip folder.
        guard folders.count == 1,
              !ClipDefinition.standard.contains(where: { $0.folder.lowercased() == folders[0].lastPathComponent.lowercased() })
        else { return nil }
        return folders[0]
    }

    /// Clip name -> the image files that belong to it, in play order.
    private func discoverFrames(in directory: URL) throws -> [String: [URL]] {
        var found: [String: [URL]] = [:]
        for definition in ClipDefinition.standard {
            // Match the folder case-insensitively: people rename these.
            let entries = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            guard let folder = entries.first(where: {
                $0.lastPathComponent.lowercased() == definition.folder.lowercased()
            }) else { continue }

            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            // Any prefix is accepted: what matters is the folder it is in and a
            // numeric suffix, so a pack named walking_01.png still imports.
            let ordered = FrameDiscovery.orderedFrames(withPrefix: definition.filePrefix, in: names)
            let fallback = ordered.isEmpty ? numberedImages(in: names) : ordered
            let urls = fallback.map { folder.appendingPathComponent($0) }
            if !urls.isEmpty { found[definition.name] = urls }
        }
        return found
    }

    /// Every image with a numeric suffix, whatever it is called.
    private func numberedImages(in names: [String]) -> [String] {
        let matches = names.compactMap { name -> (Int, String)? in
            let base = (name as NSString).deletingPathExtension
            guard FrameDiscovery.supportedExtensions.contains((name as NSString).pathExtension.lowercased()),
                  let digits = base.split(whereSeparator: { !$0.isNumber }).last,
                  let index = Int(digits)
            else { return nil }
            return (index, name)
        }
        return matches.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Normalising and writing

    private func normaliseAndWrite(_ discovered: [String: [URL]], name: String) throws -> Result {
        // Measure every frame, then let Core decide the layout.
        var images: [String: [NSImage]] = [:]
        var bounds: [String: [FrameBounds]] = [:]
        for (clip, urls) in discovered {
            var clipImages: [NSImage] = []
            var clipBounds: [FrameBounds] = []
            for url in urls {
                guard let image = NSImage(contentsOf: url),
                      let bitmap = Self.bitmap(from: image),
                      let measured = Self.measure(bitmap) else { continue }
                clipImages.append(image)
                clipBounds.append(measured)
            }
            if !clipImages.isEmpty {
                images[clip] = clipImages
                bounds[clip] = clipBounds
            }
        }
        guard !bounds.isEmpty else { throw Failure.noFramesFound }

        let layout = PackGeometry.layout(for: bounds)
        let packURL = destinationRoot.appendingPathComponent(name, isDirectory: true)

        do {
            // Replace only the clip folders being written, leaving anything else
            // in an existing pack of the same name alone.
            try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)
            var written = 0
            for definition in ClipDefinition.standard {
                guard let clipImages = images[definition.name],
                      let placement = layout.placements[definition.name] else { continue }
                let folder = packURL.appendingPathComponent(definition.folder, isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                for (index, image) in clipImages.enumerated() {
                    let target = folder.appendingPathComponent(
                        String(format: "%@_%02d.png", definition.filePrefix, index + 1)
                    )
                    guard let data = Self.render(image, placement: placement, layout: layout) else { continue }
                    try data.write(to: target)
                    written += 1
                }
            }

            let manifest: [String: Any] = [
                "characterHeight": layout.characterHeight,
                "canvasHeight": layout.canvasHeight,
                "canvasWidth": layout.canvasWidth,
                "baseline": layout.baseline,
                "clipTopFractions": layout.clipTopFractions,
            ]
            let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: packURL.appendingPathComponent("pack.json"))

            let installed = images.keys.sorted()
            return Result(
                name: name,
                clipsInstalled: installed,
                framesInstalled: written,
                clipsMissing: ClipName.all.filter { !installed.contains($0) },
                canvas: "\(layout.canvasWidth)×\(layout.canvasHeight)"
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.writeFailed(error.localizedDescription)
        }
    }

    // MARK: Pixels

    public static func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first { return rep }
        guard let data = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }

    /// The bounding box of the non-transparent pixels.
    public static func measure(_ bitmap: NSBitmapImageRep) -> FrameBounds? {
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let colour = bitmap.colorAt(x: x, y: y), colour.alphaComponent > 0.06 else { continue }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return FrameBounds(width: width, height: height,
                           left: minX, top: minY, right: maxX + 1, bottom: maxY + 1)
    }

    /// Draws one frame onto the shared canvas at its clip's transform.
    static func render(_ image: NSImage, placement: FramePlacement, layout: PackLayout) -> Data? {
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: layout.canvasWidth, pixelsHigh: layout.canvasHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        guard let source = bitmap(from: image) else { return nil }
        let width = Double(source.pixelsWide) * placement.scale
        let height = Double(source.pixelsHigh) * placement.scale

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSGraphicsContext.current?.imageInterpolation = .high
        // Bitmap coordinates run top-down, AppKit drawing bottom-up.
        let flippedY = Double(layout.canvasHeight) - Double(placement.offsetY) - height
        source.draw(in: NSRect(x: Double(placement.offsetX), y: flippedY, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        return canvas.representation(using: .png, properties: [:])
    }
}
