import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerLockScreenView(context: context)
                // Let Lock Screen wallpaper show through so control materials read as glass.
                .activityBackgroundTint(.black.opacity(0.18))
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
                    HStack(spacing: 8) {
                        IslandTimerText(context: context, size: 15, weight: .semibold)
                        if context.state.isResting {
                            RestTimerQuickControls(
                                sessionID: context.attributes.sessionID,
                                isPaused: context.state.isPaused,
                                compact: true
                            )
                        }
                    }
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
            HStack(alignment: .center, spacing: 10) {
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

                if context.state.showsLoggedConfirmation {
                    LoggedConfirmationBadge(
                        confirmationID: context.state.loggedConfirmationID
                    )
                }

                IslandTimerText(context: context, size: 21, weight: .bold, forLockScreen: true)

                if context.state.isResting {
                    RestTimerQuickControls(
                        sessionID: context.attributes.sessionID,
                        isPaused: context.state.isPaused,
                        compact: false
                    )
                }
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
        .animation(
            .spring(response: 0.32, dampingFraction: 0.72),
            value: context.state.showsLoggedConfirmation
        )
        .animation(
            .spring(response: 0.32, dampingFraction: 0.72),
            value: context.state.loggedConfirmationID
        )
    }
}

private struct LoggedConfirmationBadge: View {
    let confirmationID: Int

    var body: some View {
        Label("Logged", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.green.opacity(0.16), in: Capsule())
            .symbolEffect(.bounce, value: confirmationID)
            .transition(.scale(scale: 0.72).combined(with: .opacity))
            .accessibilityLabel("Set logged")
    }
}

private struct RestTimerQuickControls: View {
    let sessionID: String
    let isPaused: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Button(
                intent: AdjustRestTimerIntent(sessionID: sessionID, seconds: 15)
            ) {
                Text("+15")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(minWidth: compact ? 34 : 40, minHeight: compact ? 28 : 32)
                    .padding(.horizontal, 4)
            }
            .liveActivityGlassControl(shape: .capsule)
            .accessibilityLabel("Add 15 seconds")

            Button(
                intent: ToggleRestTimerPauseIntent(sessionID: sessionID)
            ) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
            }
            .liveActivityGlassControl(shape: .circle)
            .accessibilityLabel(isPaused ? "Resume rest" : "Pause rest")
        }
    }
}

private struct WorkoutSetControls: View {
    let sessionID: String
    let set: WorkoutLiveActivitySet
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
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

                Spacer(minLength: 0)
            }

            HStack(spacing: compact ? 6 : 8) {
                Button(
                    intent: CompleteAnotherWorkoutSetIntent(
                        sessionID: sessionID,
                        setID: set.setID
                    )
                ) {
                    Label("Another", systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: compact ? 30 : 32)
                }
                .liveActivityGlassControl(shape: .capsule)
                .accessibilityLabel("Complete set and do another \(set.exerciseName)")

                Button(
                    intent: CompleteWorkoutSetIntent(
                        sessionID: sessionID,
                        setID: set.setID
                    )
                ) {
                    Label("Next", systemImage: "checkmark")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: compact ? 30 : 32)
                        .foregroundStyle(.white)
                }
                .liveActivityGlassControl(shape: .capsule, prominent: true)
                .accessibilityLabel("Complete set and move to the next set")
            }
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
        .liveActivityGlassSurface(cornerRadius: 10)
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
        // Keep ± as plain + shared surface glass so App Intents stay tappable.
        .buttonStyle(LiveActivityBobButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Classic press bob for Lock Screen ± — local scale only (no nested glass).
private struct LiveActivityBobButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.78 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.52),
                value: configuration.isPressed
            )
    }
}

private enum LiveActivityGlassShape {
    case capsule
    case circle
}

private extension View {
    /// Frosted control chrome for Live Activities.
    /// Note: `.buttonStyle(.glass)` and view-level `glassEffect` on App Intent
    /// buttons blank out / break Lock Screen controls — use materials instead.
    @ViewBuilder
    func liveActivityGlassControl(
        shape: LiveActivityGlassShape,
        prominent: Bool = false
    ) -> some View {
        buttonStyle(.plain)
            .background {
                switch shape {
                case .capsule where prominent:
                    ZStack {
                        Capsule().fill(.green.opacity(0.72))
                        Capsule().fill(.ultraThinMaterial.opacity(0.55))
                    }
                case .capsule:
                    Capsule().fill(.regularMaterial)
                case .circle:
                    Circle().fill(.regularMaterial)
                }
            }
    }

    @ViewBuilder
    func liveActivityGlassSurface(cornerRadius: CGFloat) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
