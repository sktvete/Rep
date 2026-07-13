import SwiftUI

/// Fires `action` immediately on press, then repeats after a short delay while held.
struct RepeatStepButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                if isPressing {
                    beginRepeat()
                } else {
                    endRepeat()
                }
            }, perform: {})
    }

    private func beginRepeat() {
        action()
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            var intervalMs = 140
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(intervalMs))
                intervalMs = max(60, intervalMs - 8)
            }
        }
    }

    private func endRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
