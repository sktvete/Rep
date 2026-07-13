import SwiftUI

struct WorkoutRestTimerBanner: View {
    @Bindable var restTimer: WorkoutRestTimerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: restTimer.isPaused ? "pause.circle.fill" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(RepVisualSystem.tint)
                .symbolEffect(.pulse, isActive: !restTimer.isPaused)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(RestTimerLiveActivityFormatting.clock(seconds: restTimer.remainingSeconds))
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())

                    if restTimer.isPaused {
                        Text("Paused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }

                Text(restTimer.nextExerciseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                restTimer.togglePause()
            } label: {
                Image(systemName: restTimer.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(restTimer.isPaused ? "Resume rest" : "Pause rest")

            Button {
                restTimer.skip()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("Skip rest")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}
