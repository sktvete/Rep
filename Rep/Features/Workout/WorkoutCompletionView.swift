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

    var body: some View {
        ZStack {
            RepScreenBackground()
                .ignoresSafeArea()

            ConfettiView()
                .frame(maxWidth: .infinity, maxHeight: 280, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: true)

                    Text("Workout complete")
                        .font(.largeTitle.bold())

                    Text(session.name)
                        .font(.title3.weight(.medium))
                        .repSecondaryText()
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
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
                    let displayedVolume = UnitConversion.weight(applicableVolume, from: .kilograms, to: preferredUnit)
                    Text("\(displayedVolume.formatted(.number.precision(.fractionLength(0)))) \(preferredUnit.symbol) volume")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .repSecondaryText()
                }

                Spacer()

                Button("Done", action: onDone)
                    .repPrimaryButton()
            }
            .padding(RepVisualSystem.pageSpacing)
        }
        .sensoryFeedback(.success, trigger: didCelebrate)
        .onAppear { didCelebrate = true }
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
