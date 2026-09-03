import AppKit
import AiTwinCore
import AiTwinPlatform

/// Plays macOS's built-in alert sounds.
///
/// Holds the `NSSound` it is playing in a property, which is not decoration:
/// `NSSound` stops the moment it is deallocated, so a local `NSSound(named:)?
/// .play()` is a silent no-op roughly as often as it works. One retained slot
/// also gives the behaviour we want when two cues land together — the newer
/// sound replaces the older one instead of both playing over each other.
public final class MacSoundPlayer: SoundPlaying {

    private var playing: NSSound?
    /// Sounds are cached after first use: reading and decoding the AIFF on every
    /// chime would put file I/O on the main thread for something that happens
    /// while the user is watching an animation.
    private var cache: [String: NSSound] = [:]

    public init() {}

    public func play(_ sound: AlertSound, at volume: Double) {
        guard let name = sound.systemName else { return }

        let audio: NSSound
        if let cached = cache[name] {
            audio = cached
        } else if let loaded = NSSound(named: name) {
            cache[name] = loaded
            audio = loaded
        } else {
            // A system sound missing is not worth an error path: the user hears
            // nothing, which is the same outcome as choosing None.
            return
        }

        // Restart rather than ignoring the request. Without this, a cached sound
        // asked to play while already playing does nothing, so pressing the
        // preview button twice would seem broken.
        if audio.isPlaying { audio.stop() }
        audio.currentTime = 0
        // Set every time, not once at load: the sounds are cached and reused, so
        // a volume change would otherwise not take effect until relaunch.
        audio.volume = Float(min(1, max(0, volume)))
        playing = audio
        audio.play()
    }
}
