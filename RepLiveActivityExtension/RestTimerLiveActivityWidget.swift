import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.currentSet?.exerciseName ?? "Workout")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let set = context.state.currentSet {
                            Text(set.setLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTimerText(context: context, size: 15, weight: .semibold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let set = context.state.currentSet {
                        WorkoutSetControls(
                            sessionID: context.attributes.sessionID,
                            set: set,
                            compact: true
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: compactStatusSymbol(for: context.state))
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

    private func compactStatusSymbol(
        for state: RestTimerAttributes.ContentState
    ) -> String {
        if state.isPaused { return "pause.fill" }
        return state.isResting ? "timer" : "checkmark.circle.fill"
    }
}

private struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let set = context.state.currentSet {
                        Text(set.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(set.setLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(context.state.isPaused ? "Rest paused" : "Rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.nextExerciseName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                IslandTimerText(context: context, size: 21, weight: .bold, forLockScreen: true)
            }

            if let set = context.state.currentSet {
                WorkoutSetControls(
                    sessionID: context.attributes.sessionID,
                    set: set,
                    compact: false
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct WorkoutSetControls: View {
    let sessionID: String
    let set: WorkoutLiveActivitySet
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            if set.supportsWeight {
                metricControl(
                    title: set.weightUnitSymbol,
                    value: weightText,
                    decrementIntent: AdjustWorkoutWeightIntent(
                        sessionID: sessionID,
                        setID: set.setID,
                        delta: -set.weightStep
                    ),
                    incrementIntent: AdjustWorkoutWeightIntent(
                        sessionID: sessionID,
                        setID: set.setID,
                        delta: set.weightStep
                    ),
                    decrementLabel: "Decrease weight",
                    incrementLabel: "Increase weight"
                )
            }

            if set.supportsRepetitions {
                metricControl(
                    title: "reps",
                    value: set.repetitions.map(String.init) ?? "—",
                    decrementIntent: AdjustWorkoutRepetitionsIntent(
                        sessionID: sessionID,
                        setID: set.setID,
                        delta: -1
                    ),
                    incrementIntent: AdjustWorkoutRepetitionsIntent(
                        sessionID: sessionID,
                        setID: set.setID,
                        delta: 1
                    ),
                    decrementLabel: "Remove one repetition",
                    incrementLabel: "Add one repetition"
                )
            }

            Button(
                intent: CompleteWorkoutSetIntent(
                    sessionID: sessionID,
                    setID: set.setID
                )
            ) {
                Label("Done", systemImage: "checkmark")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: compact ? 54 : 62, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Complete \(set.exerciseName), set \(set.setNumber)")
        }
    }

    private var weightText: String {
        guard let weight = set.displayedWeight else { return "—" }
        return weight.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func metricControl<DecrementIntent, IncrementIntent>(
        title: String,
        value: String,
        decrementIntent: DecrementIntent,
        incrementIntent: IncrementIntent,
        decrementLabel: String,
        incrementLabel: String
    ) -> some View where DecrementIntent: AppIntent, IncrementIntent: AppIntent {
        HStack(spacing: 2) {
            intentButton(
                systemName: "minus",
                intent: decrementIntent,
                accessibilityLabel: decrementLabel
            )

            VStack(spacing: 0) {
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: compact ? 30 : 34)

            intentButton(
                systemName: "plus",
                intent: incrementIntent,
                accessibilityLabel: incrementLabel
            )
        }
        .padding(3)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func intentButton<Intent: AppIntent>(
        systemName: String,
        intent: Intent,
        accessibilityLabel: String
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct IslandTimerText: View {
    let context: ActivityViewContext<RestTimerAttributes>
    let size: CGFloat
    let weight: Font.Weight
    var forLockScreen = false

    var body: some View {
        Group {
            if !context.state.isResting {
                Text("READY")
            } else if context.state.isPaused,
                      let paused = context.state.pausedRemainingSeconds {
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
        .minimumScaleFactor(0.7)
    }
}
