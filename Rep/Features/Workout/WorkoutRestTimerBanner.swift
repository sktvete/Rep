import SwiftUI

struct WorkoutRestTimerBanner: View {
    @Bindable var restTimer: WorkoutRestTimerViewModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: restTimer.isPaused ? "pause.circle.fill" : "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RepVisualSystem.tint)
                .symbolEffect(.pulse, isActive: !restTimer.isPaused)
                .accessibilityHidden(true)

            Text(RestTimerLiveActivityFormatting.clock(seconds: restTimer.remainingSeconds))
                .font(.headline.bold().monospacedDigit())
                .contentTransition(.numericText())

            Text(restTimer.isPaused ? "Paused" : restTimer.nextExerciseName)
                .font(.caption)
                .repSecondaryText()
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                restTimer.adjust(by: 15)
            } label: {
                Text("+15")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(minWidth: 32, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Add 15 seconds")

            Button {
                restTimer.togglePause()
            } label: {
                Image(systemName: restTimer.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(restTimer.isPaused ? "Resume rest" : "Pause rest")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }
}
