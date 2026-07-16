import SwiftUI

/// Uses the system repeat behavior so scrolling or cancelling a touch never changes the value.
struct RepeatStepButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .repSecondaryText()
                .frame(width: 26, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
