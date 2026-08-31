import Foundation
import Testing
@testable import AiTwinCore

@Suite("Frame discovery")
struct FrameDiscoveryTests {

    @Test("frames are ordered numerically, not alphabetically")
    func numericOrdering() {
        // The alphabetical trap: "walk_10" sorts before "walk_2" as a string,
        // which would make the character moonwalk.
        let files = ["walk_10.png", "walk_2.png", "walk_1.png", "walk_11.png"]
        #expect(FrameDiscovery.orderedFrames(withPrefix: "walk", in: files)
                == ["walk_1.png", "walk_2.png", "walk_10.png", "walk_11.png"])
    }

    @Test("zero-padded names order correctly")
    func zeroPadded() {
        let files = ["idle_03.png", "idle_01.png", "idle_02.png"]
        #expect(FrameDiscovery.orderedFrames(withPrefix: "idle", in: files)
                == ["idle_01.png", "idle_02.png", "idle_03.png"])
    }

    @Test("gaps in the numbering are tolerated")
    func gapsTolerated() {
        let files = ["walk_01.png", "walk_02.png", "walk_05.png"]
        #expect(FrameDiscovery.orderedFrames(withPrefix: "walk", in: files).count == 3)
    }

    @Test("unrelated files are ignored")
    func ignoresUnrelatedFiles() {
        let files = ["walk_01.png", ".DS_Store", "notes.txt", "README.md", "walk_02.png"]
        #expect(FrameDiscovery.orderedFrames(withPrefix: "walk", in: files)
                == ["walk_01.png", "walk_02.png"])
    }

    @Test("a clip does not swallow its own glasses variant")
    func prefixDoesNotOverreach() {
        // Without the "underscore then digits only" rule, `idle` would match
        // idle_glasses_01.png and the two clips would fight.
        let files = ["idle_01.png", "idle_glasses_01.png", "idle_02.png"]
        #expect(FrameDiscovery.orderedFrames(withPrefix: "idle", in: files)
                == ["idle_01.png", "idle_02.png"])
        #expect(FrameDiscovery.orderedFrames(withPrefix: "idle_glasses", in: files)
                == ["idle_glasses_01.png"])
    }

    @Test("an empty folder yields no frames rather than an error")
    func emptyFolder() {
        #expect(FrameDiscovery.orderedFrames(withPrefix: "walk", in: []).isEmpty)
    }

    @Test("names with no numeric index are rejected")
    func rejectsNonNumeric() {
        #expect(FrameDiscovery.frameIndex(of: "walk_left.png", prefix: "walk") == nil)
        #expect(FrameDiscovery.frameIndex(of: "walk.png", prefix: "walk") == nil)
        #expect(FrameDiscovery.frameIndex(of: "walk_.png", prefix: "walk") == nil)
    }

    @Test("unsupported file types are rejected")
    func rejectsUnsupportedTypes() {
        #expect(FrameDiscovery.frameIndex(of: "walk_01.gif", prefix: "walk") == nil)
        #expect(FrameDiscovery.frameIndex(of: "walk_01.png", prefix: "walk") == 1)
    }

    @Test("full paths are matched on their last component")
    func matchesFullPaths() {
        let files = ["/tmp/pack/Walking/walk_02.png", "/tmp/pack/Walking/walk_01.png"]
        let ordered = FrameDiscovery.orderedFrames(withPrefix: "walk", in: files)
        #expect(ordered.first?.hasSuffix("walk_01.png") == true)
        #expect(ordered.count == 2)
    }
}

@Suite("FrameSequencer")
struct FrameSequencerTests {

    private func clip(_ count: Int, loops: Bool = true, frameDuration: TimeInterval = 0.125) -> AnimationClip {
        AnimationClip(
            name: "test",
            framePaths: (1...count).map { "frame_\($0).png" },
            frameDuration: frameDuration,
            loops: loops
        )
    }

    @Test("a sequencer starts on the first frame")
    func startsAtFirstFrame() {
        let sequencer = FrameSequencer(clip: clip(4))
        #expect(sequencer.currentIndex == 0)
        #expect(sequencer.currentFramePath == "frame_1.png")
    }

    @Test("frames advance in order at the configured rate")
    func advancesInOrder() {
        let sequencer = FrameSequencer(clip: clip(4, frameDuration: 0.1))
        sequencer.advance(by: 0.1)
        #expect(sequencer.currentFramePath == "frame_2.png")
        sequencer.advance(by: 0.1)
        #expect(sequencer.currentFramePath == "frame_3.png")
    }

    @Test("a frame holds for its full duration")
    func holdsFrameForDuration() {
        let sequencer = FrameSequencer(clip: clip(4, frameDuration: 0.1))
        sequencer.advance(by: 0.09)
        #expect(sequencer.currentIndex == 0)
        sequencer.advance(by: 0.01)
        #expect(sequencer.currentIndex == 1)
    }

    @Test("a looping clip wraps back to the start")
    func loops() {
        let sequencer = FrameSequencer(clip: clip(3, loops: true, frameDuration: 0.1))
        sequencer.advance(by: 0.3)
        #expect(sequencer.currentIndex == 0)
        #expect(sequencer.isFinished == false)
    }

    @Test("a one-shot clip holds its last frame and reports finished")
    func oneShotFinishes() {
        let sequencer = FrameSequencer(clip: clip(3, loops: false, frameDuration: 0.1))
        sequencer.advance(by: 1.0)
        #expect(sequencer.currentIndex == 2)
        #expect(sequencer.isFinished)
        #expect(sequencer.currentFramePath == "frame_3.png")
    }

    @Test("a finished one-shot clip does not advance further")
    func finishedClipStaysPut() {
        let sequencer = FrameSequencer(clip: clip(3, loops: false, frameDuration: 0.1))
        sequencer.advance(by: 1.0)
        sequencer.advance(by: 10.0)
        #expect(sequencer.currentIndex == 2)
    }

    @Test("a long delta catches up rather than dropping frames")
    func catchesUpAfterStall() {
        // Simulates a stalled main thread or a wake from sleep.
        let sequencer = FrameSequencer(clip: clip(4, loops: true, frameDuration: 0.1))
        sequencer.advance(by: 0.25)
        #expect(sequencer.currentIndex == 2)
    }

    @Test("switching clips restarts from the first frame")
    func setClipRestarts() {
        let sequencer = FrameSequencer(clip: clip(4, frameDuration: 0.1))
        sequencer.advance(by: 0.2)
        sequencer.setClip(clip(2, frameDuration: 0.1))
        #expect(sequencer.currentIndex == 0)
        #expect(sequencer.isFinished == false)
    }

    @Test("an empty clip is inert instead of crashing")
    func emptyClipIsSafe() {
        // This is the missing-artwork path: the character pack shipped no frames
        // for this animation. It must not trap on an index.
        let empty = AnimationClip(name: "empty", framePaths: [], frameDuration: 0.1, loops: true)
        let sequencer = FrameSequencer(clip: empty)
        sequencer.advance(by: 5)
        #expect(sequencer.currentFramePath == nil)
        #expect(sequencer.isFinished)
    }

    @Test("a zero frame duration does not spin forever")
    func zeroDurationIsSafe() {
        // A malformed pack could produce this; the while-loop must not hang.
        let sequencer = FrameSequencer(clip: clip(3, frameDuration: 0))
        sequencer.advance(by: 1)
        #expect(sequencer.currentIndex == 0)
    }

    @Test("restart returns to the first frame")
    func restart() {
        let sequencer = FrameSequencer(clip: clip(4, loops: false, frameDuration: 0.1))
        sequencer.advance(by: 10)
        sequencer.restart()
        #expect(sequencer.currentIndex == 0)
        #expect(sequencer.isFinished == false)
    }
}

@Suite("CharacterPack")
struct CharacterPackTests {

    private func clip(_ name: String, count: Int = 2) -> AnimationClip {
        AnimationClip(
            name: name,
            framePaths: (1...count).map { "\(name)_\($0).png" },
            frameDuration: 0.125,
            loops: true
        )
    }

    @Test("a pack resolves the clip that was asked for")
    func resolvesExactClip() {
        let pack = CharacterPack(name: "Test", clips: [
            ClipName.idle: clip(ClipName.idle),
            ClipName.walk: clip(ClipName.walk),
        ])
        #expect(pack.resolveClip(named: ClipName.walk, wearingGlasses: false)?.name == ClipName.walk)
    }

    @Test("a missing clip falls back to idle rather than nothing")
    func missingClipFallsBackToIdle() {
        // Half-finished character pack: the app must still work.
        let pack = CharacterPack(name: "Test", clips: [ClipName.idle: clip(ClipName.idle)])
        #expect(pack.resolveClip(named: ClipName.waterReminder, wearingGlasses: false)?.name == ClipName.idle)
    }

    @Test("glasses use the variant clip when the art exists")
    func glassesVariantUsed() {
        let pack = CharacterPack(name: "Test", clips: [
            ClipName.idle: clip(ClipName.idle),
            "idle_glasses": clip("idle_glasses"),
        ])
        #expect(pack.resolveClip(named: ClipName.idle, wearingGlasses: true)?.name == "idle_glasses")
    }

    @Test("glasses fall back to the plain clip when no variant exists")
    func glassesFallBack() {
        let pack = CharacterPack(name: "Test", clips: [ClipName.idle: clip(ClipName.idle)])
        #expect(pack.resolveClip(named: ClipName.idle, wearingGlasses: true)?.name == ClipName.idle)
    }

    @Test("an empty clip is treated as missing")
    func emptyClipTreatedAsMissing() {
        let pack = CharacterPack(name: "Test", clips: [
            ClipName.idle: clip(ClipName.idle),
            ClipName.walk: AnimationClip(name: ClipName.walk, framePaths: [], frameDuration: 0.1, loops: true),
        ])
        #expect(pack.resolveClip(named: ClipName.walk, wearingGlasses: false)?.name == ClipName.idle)
        #expect(pack.missingClipNames.contains(ClipName.walk))
    }

    @Test("a pack with no idle frames is not usable")
    func packWithoutIdleIsUnusable() {
        let pack = CharacterPack(name: "Broken", clips: [ClipName.walk: clip(ClipName.walk)])
        #expect(pack.isUsable == false)
        #expect(pack.resolveClip(named: ClipName.walk, wearingGlasses: false)?.name == ClipName.walk)
        #expect(pack.resolveClip(named: ClipName.wave, wearingGlasses: false) == nil)
    }

    @Test("missing clips are reported for display in Settings")
    func reportsMissingClips() {
        let pack = CharacterPack(name: "Test", clips: [ClipName.idle: clip(ClipName.idle)])
        #expect(pack.missingClipNames.contains(ClipName.walk))
        #expect(pack.missingClipNames.contains(ClipName.idle) == false)
    }
}
