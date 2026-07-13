import AudioToolbox
import CoreHaptics
import UIKit

/// Retains a Core Haptics engine so patterns play reliably (Apple recommends a long-lived engine).
@MainActor
final class HapticEngineManager {
    static let shared = HapticEngineManager()

    private var engine: CHHapticEngine?

    private init() {}

    func warm() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard engine == nil else { return }

        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { [weak self] _ in
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
        } catch {
            AppLog.timer.error("Haptic engine failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func playStrongBurst(duration: TimeInterval = 0.2) {
        guard let engine else { return }

        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: duration
            )
            let midTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: duration * 0.55
            )
            let endTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: duration + 0.03
            )
            let pattern = try CHHapticPattern(events: [continuous, midTap, endTap], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            AppLog.timer.error("Strong haptic burst failed: \(String(describing: error), privacy: .public)")
        }
    }
}

enum HapticFeedback {
    private enum SystemHaptic {
        static let pop: SystemSoundID = 1520
        static let peek: SystemSoundID = 1519
        static let failed: SystemSoundID = 1107
    }

    @MainActor
    static func tripleBuzz() {
        Task { @MainActor in
            await playRestTimerComplete()
        }
    }

    @MainActor
    static func tripleBuzzAndWait() async {
        await playRestTimerComplete()
    }

    @MainActor
    private static func playRestTimerComplete() async {
        HapticEngineManager.shared.warm()

        let notification = UINotificationFeedbackGenerator()
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        notification.prepare()
        rigid.prepare()

        for index in 0..<3 {
            notification.notificationOccurred(.error)
            rigid.impactOccurred(intensity: 1.0)
            AudioServicesPlaySystemSound(SystemHaptic.pop)
            HapticEngineManager.shared.playStrongBurst()

            guard index < 2 else { continue }
            try? await Task.sleep(for: .milliseconds(230))
        }
    }
}
