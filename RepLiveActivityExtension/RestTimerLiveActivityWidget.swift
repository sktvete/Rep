import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTimerText(context: context, size: 15, weight: .semibold)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                IslandTimerText(context: context, size: 12, weight: .semibold)
                    .frame(maxWidth: 46, alignment: .trailing)
            } minimal: {
                IslandTimerText(context: context, size: 10, weight: .bold)
                    .frame(maxWidth: 40, alignment: .trailing)
            }
        }
    }
}

private struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.isPaused ? "Rest paused" : "Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Next: \(context.state.nextExerciseName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            IslandTimerText(context: context, size: 22, weight: .bold, forLockScreen: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct IslandTimerText: View {
    let context: ActivityViewContext<RestTimerAttributes>
    let size: CGFloat
    let weight: Font.Weight
    var forLockScreen = false

    var body: some View {
        Group {
            if context.state.isPaused, let paused = context.state.pausedRemainingSeconds {
                Text(RestTimerLiveActivityFormatting.clock(seconds: paused))
            } else {
                Text(
                    timerInterval: context.state.timerInterval,
                    countsDown: true,
                    showsHours: false
                )
            }
        }
        .font(.system(size: size, weight: weight, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(forLockScreen ? Color.primary : Color.white)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}
