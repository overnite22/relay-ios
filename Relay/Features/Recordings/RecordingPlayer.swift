import RelayKit
import SwiftUI

/// Rendu des trames hors du thread principal.
actor PlaybackRenderer {
    private var display = GuacDisplay()

    func reset() { display = GuacDisplay() }

    func apply(_ frames: ArraySlice<RecordingTimeline.Frame>) -> GuacEngine.Frame {
        for frame in frames {
            for command in frame.commands { display.apply(command) }
        }
        return GuacEngine.Frame(image: display.composite(), size: display.size)
    }
}

/// Lecture d'un enregistrement : téléchargement, décodage, lecture, pause, déplacement et vitesse.
@MainActor @Observable final class RecordingPlayer {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let recording: Recording
    private(set) var phase: Phase = .loading
    private(set) var position = 0
    private(set) var duration = 0
    private(set) var playing = false
    var speed: Double = 1
    var skipIdle = true

    @ObservationIgnored let screen = RemoteScreenView()
    @ObservationIgnored private var timeline: RecordingTimeline?
    @ObservationIgnored private let renderer = PlaybackRenderer()
    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private var playTask: Task<Void, Never>?

    init(recording: Recording) {
        self.recording = recording
        screen.showsPointer = false
        screen.mode = .direct
    }

    func load(_ client: RelayClient?) async {
        guard phase == .loading, let client else { return }
        do {
            let data = try await client.recordingData(recording.id)
            let decoded = try await Task.detached(priority: .userInitiated) { try RecordingTimeline.decode(data) }.value
            guard !decoded.frames.isEmpty else {
                phase = .failed("Cet enregistrement est vide.")
                return
            }
            timeline = decoded
            duration = decoded.duration
            phase = .ready
            await move(to: 0)
            play()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    var atEnd: Bool { timeline.map { nextIndex >= $0.frames.count } ?? true }

    func toggle() {
        if playing { pause() } else { play() }
    }

    func play() {
        guard phase == .ready, !playing else { return }
        playing = true
        playTask = Task { [weak self] in
            guard let self else { return }
            if self.atEnd { await self.move(to: 0) }
            await self.loop()
        }
    }

    func pause() {
        playing = false
        playTask?.cancel()
        playTask = nil
    }

    func stop() { pause() }

    private func loop() async {
        while playing, !Task.isCancelled, let t = timeline, nextIndex < t.frames.count {
            let wait = t.delay(before: nextIndex, speed: speed, skipIdle: skipIdle)
            if wait > 0.001 {
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            }
            // Regroupe les trames rapprochées (moins de 15 ms) pour suivre la cadence.
            var end = nextIndex
            while end + 1 < t.frames.count, t.delay(before: end + 1, speed: speed, skipIdle: skipIdle) < 0.015 { end += 1 }
            // Les trames appliquées sont toujours comptées, même si la lecture vient d'être interrompue.
            let frame = await renderer.apply(t.frames[nextIndex...end])
            screen.show(frame)
            position = t.frames[end].time
            nextIndex = end + 1
            if Task.isCancelled { return }
        }
        if !Task.isCancelled { playing = false }
    }

    /// Se place à `time` (ms), puis reprend la lecture si elle était en cours.
    func seek(to time: Int) async {
        let wasPlaying = playing
        let running = playTask
        pause()
        await running?.value
        await move(to: time)
        if wasPlaying { play() }
    }

    /// Affiche la trame de `time` sans toucher à l'état de lecture (rejoue depuis le début pour reculer).
    private func move(to time: Int) async {
        guard let t = timeline, !t.frames.isEmpty else { return }
        let target = t.frameIndex(at: time)
        var frame: GuacEngine.Frame?
        if nextIndex == 0 || target < nextIndex - 1 {
            await renderer.reset()
            frame = await renderer.apply(t.frames[0...target])
        } else if target >= nextIndex {
            frame = await renderer.apply(t.frames[nextIndex...target])
        }
        if let frame { screen.show(frame) }
        nextIndex = target + 1
        position = t.frames[target].time
    }
}
