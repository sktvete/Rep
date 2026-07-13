import SwiftUI

struct WorkoutHistoryDetailView: View {
    let session: WorkoutSession
    let preferredUnit: WeightUnit

    private var orderedExercises: [WorkoutExercise] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var completedSetCount: Int {
        orderedExercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var body: some View {
        ZStack {
            RepScreenBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: RepVisualSystem.pageSpacing) {
                    summary

                    if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)
                            Text(session.notes)
                                .repSecondaryText()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .repSurface()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercises")
                            .font(.title2.bold())

                        ForEach(orderedExercises) { workoutExercise in
                            HistoricalExerciseCard(
                                workoutExercise: workoutExercise,
                                preferredUnit: preferredUnit
                            )
                        }
                    }
                }
                .padding(RepVisualSystem.pageSpacing)
            }
            .scrollIndicators(.hidden)
            .repSoftScrollEdges()
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.completedAt ?? session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.subheadline.weight(.medium))
                    .repSecondaryText()
                Text(session.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                HistoricalSummaryMetric(
                    title: "Duration",
                    value: session.historyDuration.formattedWorkoutDuration,
                    systemImage: "timer"
                )
                HistoricalSummaryMetric(
                    title: "Exercises",
                    value: orderedExercises.count.formatted(),
                    systemImage: "dumbbell"
                )
                HistoricalSummaryMetric(
                    title: "Sets",
                    value: completedSetCount.formatted(),
                    systemImage: "checkmark.circle"
                )
            }
        }
    }
}

private struct HistoricalSummaryMetric: View {
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

private struct HistoricalExerciseCard: View {
    let workoutExercise: WorkoutExercise
    let preferredUnit: WeightUnit

    private var completedSets: [WorkoutSet] {
        workoutExercise.sets
            .filter(\.isCompleted)
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(workoutExercise.exercise?.name ?? "Unavailable exercise")
                    .font(.headline)
                Spacer()
                Text("\(completedSets.count) set\(completedSets.count == 1 ? "" : "s")")
                    .font(.caption)
                    .repSecondaryText()
            }
            .padding(16)

            Divider().padding(.leading, 16)

            if completedSets.isEmpty {
                Text("No completed sets")
                    .font(.subheadline)
                    .repSecondaryText()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(Array(completedSets.enumerated()), id: \.element.id) { index, set in
                    HistoricalSetRow(set: set, preferredUnit: preferredUnit)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                    if index < completedSets.count - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }

            if !workoutExercise.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().padding(.leading, 16)
                Label(workoutExercise.notes, systemImage: "note.text")
                    .font(.subheadline)
                    .repSecondaryText()
                    .padding(16)
            }
        }
        .repSurface()
    }
}

private struct HistoricalSetRow: View {
    let set: WorkoutSet
    let preferredUnit: WeightUnit

    private var primaryDescription: String {
        var components: [String] = []

        if let weight = set.weight {
            components.append(UnitConversion.displayWeight(kilograms: weight, unit: preferredUnit, maximumFractionDigits: 2))
        }
        if let repetitions = set.repetitions {
            components.append("\(repetitions) reps")
        }
        if let durationSeconds = set.durationSeconds {
            components.append(TimeInterval(durationSeconds).formattedWorkoutDuration)
        }
        if let distance = set.distance {
            components.append("\(distance.formatted(.number.precision(.fractionLength(0...2)))) m")
        }
        if let assistance = set.assistanceWeight {
            let displayed = UnitConversion.displayWeight(kilograms: assistance, unit: preferredUnit, maximumFractionDigits: 2)
            components.append("\(displayed) assistance")
        }

        return components.isEmpty ? "Completed" : components.joined(separator: " × ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text((set.orderIndex + 1).formatted())
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(RepVisualSystem.tint)
                .frame(width: 26, height: 26)
                .background(RepVisualSystem.tint.opacity(0.1), in: Circle())
                .accessibilityLabel("Set \(set.orderIndex + 1)")

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryDescription)
                    .font(.body.weight(.medium).monospacedDigit())
                if set.setType != .working {
                    Text(set.setType.displayName)
                        .font(.caption)
                        .repSecondaryText()
                }
            }

            Spacer(minLength: 8)

            if let rpe = set.rpe {
                Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .repSecondaryText()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Set \(set.orderIndex + 1), \(primaryDescription)")
    }
}

extension String {
    var workoutDisplayName: String {
        guard !isEmpty else { return self }
        let spaced = replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
