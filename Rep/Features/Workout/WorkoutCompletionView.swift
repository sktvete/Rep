import SwiftUI

struct WorkoutCompletionView: View {
    let session: WorkoutSession
    let preferredUnit: WeightUnit
    let onDone: () -> Void

    @State private var didCelebrate = false

    private var orderedExercises: [WorkoutExercise] {
        session.orderedExercises
    }

    private var completedSetCount: Int {
        session.completedSetCount
    }

    private var applicableVolume: Double {
        orderedExercises.reduce(0) { $0 + $1.totalVolume }
    }

    private var volumeComparisons: [VolumeComparison] {
        VolumeComparisonCatalog.comparisons(forKilograms: applicableVolume)
    }

    var body: some View {
        ZStack {
            RepScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        RepMascot(pose: .celebrate, size: 120)
                            .scaleEffect(didCelebrate ? 1.06 : 0.82)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.68),
                                value: didCelebrate
                            )

                        Text("Workout complete")
                            .font(.largeTitle.bold())

                        Text(session.name)
                            .font(.title3.weight(.medium))
                            .repSecondaryText()
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                        spacing: 10
                    ) {
                        CompletionMetric(
                            title: "Duration",
                            value: session.historyDuration.formattedWorkoutDuration,
                            systemImage: "timer"
                        )
                        CompletionMetric(
                            title: "Exercises",
                            value: orderedExercises.count.formatted(),
                            systemImage: "dumbbell"
                        )
                        CompletionMetric(
                            title: "Sets",
                            value: completedSetCount.formatted(),
                            systemImage: "checkmark.circle"
                        )
                    }

                    if applicableVolume > 0 {
                        VolumeComparisonsCard(
                            volumeKilograms: applicableVolume,
                            preferredUnit: preferredUnit,
                            comparisons: volumeComparisons
                        )
                    }
                }
                .padding(RepVisualSystem.pageSpacing)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Done", action: onDone)
                    .repPrimaryButton()
                    .padding(.horizontal, RepVisualSystem.pageSpacing)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }

            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.success, trigger: didCelebrate)
        .onAppear { didCelebrate = true }
    }
}

private struct VolumeComparisonsCard: View {
    let volumeKilograms: Double
    let preferredUnit: WeightUnit
    let comparisons: [VolumeComparison]

    private var displayedVolume: Double {
        UnitConversion.weight(volumeKilograms, from: .kilograms, to: preferredUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("You moved", systemImage: "scalemass.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RepVisualSystem.tint)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(
                    "\(displayedVolume.formatted(.number.precision(.fractionLength(0...1)))) \(preferredUnit.symbol)"
                )
                .font(.title.bold().monospacedDigit())
                .fontDesign(.rounded)

                Text("That’s about:")
                    .font(.footnote)
                    .repSecondaryText()
            }

            VStack(spacing: 0) {
                ForEach(Array(comparisons.enumerated()), id: \.element.id) { index, comparison in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(comparison.label)
                            .font(.headline.monospacedDigit())
                            .fontDesign(.rounded)
                            .frame(minWidth: 56, alignment: .trailing)

                        Text(comparison.detail)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)

                    if index < comparisons.count - 1 {
                        Divider().opacity(0.28)
                    }
                }
            }
        }
        .padding(16)
        .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        .accessibilityElement(children: .combine)
    }
}

private struct CompletionMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RepVisualSystem.tint)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .repSecondaryText()
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        .accessibilityElement(children: .combine)
    }
}
