import AVFoundation
import Foundation
import PokerCoordinator

enum TableSoundPreference {
    static let storageKey = "riverClub.tableSoundEnabled"
    static let defaultEnabled = true
}

enum TableSoundCue: Equatable {
    case deal
    case chips
    case turn
    case win

    static func cue(for event: TableAnimationEvent) -> TableSoundCue? {
        switch event.kind {
        case .dealHoleCard, .revealCommunityCard:
            .deal
        case .postBlind, .moveCommitmentToPot, .returnUncalledBet:
            .chips
        case .awardPot:
            .win
        case .showAction, .streetChanged, .highlightWinner:
            nil
        }
    }
}

@MainActor protocol TableSoundPlaying: AnyObject {
    func play(_ cue: TableSoundCue)
    func stop()
}

@MainActor final class TableSoundPlayer: TableSoundPlaying {
    static let shared = TableSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    )!
    private var isConfigured = false

    private init() {}

    func play(_ cue: TableSoundCue) {
        do {
            try configureIfNeeded()
            let buffer = makeBuffer(for: cue)
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            // 音频不可用时保持静默，不影响牌局状态和交互。
        }
    }

    func stop() {
        player.stop()
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            if !engine.isRunning { try engine.start() }
            return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, options: [.mixWithOthers])
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.42
        engine.prepare()
        try engine.start()
        isConfigured = true
    }

    private func makeBuffer(for cue: TableSoundCue) -> AVAudioPCMBuffer {
        let duration = duration(for: cue)
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        )!
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return buffer }

        var noiseState: UInt32 = 0x6D2B_79F5
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let progress = min(max(time / duration, 0), 1)
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let noise = (Float(noiseState >> 8) / Float(0x00FF_FFFF)) * 2 - 1
            samples[frame] = sample(
                for: cue,
                time: time,
                progress: progress,
                noise: noise
            )
        }
        return buffer
    }

    private func duration(for cue: TableSoundCue) -> Double {
        switch cue {
        case .deal: 0.13
        case .chips: 0.16
        case .turn: 0.22
        case .win: 0.48
        }
    }

    private func sample(
        for cue: TableSoundCue,
        time: Double,
        progress: Double,
        noise: Float
    ) -> Float {
        let fade = Float(pow(max(1 - progress, 0), 1.8))
        switch cue {
        case .deal:
            let swish = noise * fade * 0.22
            let paper = Float(sin(2 * .pi * 920 * time)) * fade * 0.035
            return swish + paper
        case .chips:
            let first = Float(sin(2 * .pi * 1_850 * time)) * fade
            let secondProgress = max(progress - 0.32, 0) / 0.68
            let secondFade = Float(pow(max(1 - secondProgress, 0), 2))
            let second = progress > 0.32
                ? Float(sin(2 * .pi * 2_430 * time)) * secondFade
                : 0
            return (first * 0.16 + second * 0.11 + noise * fade * 0.025)
        case .turn:
            let frequency = progress < 0.52 ? 660.0 : 880.0
            return Float(sin(2 * .pi * frequency * time)) * fade * 0.12
        case .win:
            let noteIndex = min(Int(progress * 4), 3)
            let frequencies = [523.25, 659.25, 783.99, 1_046.5]
            let localProgress = (progress * 4).truncatingRemainder(dividingBy: 1)
            let localFade = Float(pow(max(1 - localProgress, 0), 1.3))
            return Float(sin(2 * .pi * frequencies[noteIndex] * time))
                * localFade * 0.13
        }
    }
}
