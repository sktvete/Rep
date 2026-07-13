import Charts
import SwiftData
import SwiftUI

struct ExerciseProgressView: View {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.stateRaw == "completed" },
        sort: \WorkoutSession.startedAt
    )
    private var completedSessions: [WorkoutSession]

    @Query private var settings: [UserSettings]

    @State private var selectedExerciseID: UUID?
    @State private var timeRange: ProgressTimeRange = .ninetyDays
    @State private var model = ExerciseProgressModel()

    private var preferredUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kilograms
    }

    private var selectedExercise: Exercise? {
        guard let id = model.resolvedSelection(for: selectedExerciseID) else { return nil }
        return model.availableExercises.first { $0.id == id }
    }

    private var rebuildSignature: String {
        var parts = [
            String(completedSessions.count),
            selectedExerciseID?.uuidString ?? "none",
            timeRange.rawValue,
            preferredUnit.rawValue
        ]
        if let last = completedSessions.last {
            parts.append(last.id.uuidString)
            parts.append(String(last.updatedAt.timeIntervalSinceReferenceDate))
        }
        return parts.joined(separator: "|")
    }

    var body: some View {
        Group {
            if model.availableExercises.isEmpty {
                ContentUnavailableView {
                    Label("No exercise progress yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Complete a workout to start seeing strength trends.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RepVisualSystem.pageSpacing) {
                        exerciseSelector
                        rangeSelector

                        if model.points.isEmpty {
                            ContentUnavailableView(
                                "No data in this range",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("Choose a longer time range to see earlier sessions.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            strengthChart
                            metricGrid
                            latestSummary
                        }
                    }
                    .padding(.horizontal, RepVisualSystem.pageSpacing)
                    .padding(.bottom, RepVisualSystem.pageSpacing)
                }
                .scrollIndicators(.hidden)
                .repSoftScrollEdges()
            }
        }
        .task(id: rebuildSignature) {
            model.update(
                sessions: completedSessions,
                selectedExerciseID: selectedExerciseID,
                timeRange: timeRange,
                preferredUnit: preferredUnit
            )
            if selectedExerciseID != model.resolvedSelection(for: selectedExerciseID) {
                selectedExerciseID = model.resolvedSelection(for: selectedExerciseID)
            }
        }
    }

    private var exerciseSelector: some View {
        Menu {
            Picker("Exercise", selection: Binding(
                get: { model.resolvedSelection(for: selectedExerciseID) },
                set: { selectedExerciseID = $0 }
            )) {
                ForEach(model.availableExercises) { exercise in
                    Text(exercise.name).tag(Optional(exercise.id))
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedExercise?.name ?? "Choose exercise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        }
        .accessibilityLabel("Exercise, \(selectedExercise?.name ?? "none selected")")
    }

    private var rangeSelector: some View {
        Picker("Time range", selection: $timeRange) {
            ForEach(ProgressTimeRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Changes the dates included in the chart")
    }

    private var strengthChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Estimated 1RM")
                        .font(.headline)
                    Text("Best set per day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let latest = model.metrics.latestPerformance?.estimatedOneRepMax {
                    Text(formattedWeight(latest))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RepVisualSystem.tint)
                }
            }
            if model.points.contains(where: { $0.estimatedOneRepMax != nil }) {
                let yValues = model.points.compactMap(\.estimatedOneRepMax).map(displayWeight)
                let yDomain = ProgressChartScale.niceYDomain(
                    for: yValues,
                    minimumPadding: preferredUnit == .kilograms ? 2.5 : 5
                )
                let yStride = yDomain.map { ProgressChartScale.axisStride(for: $0) } ?? 5
                let dayStride = ProgressChartScale.dayStride(for: model.points.map(\.date))

                Chart(model.points) { point in
                    if let estimatedOneRepMax = point.estimatedOneRepMax {
                        LineMark(
                            x: .value("Date", point.date, unit: .minute),
                            y: .value("Estimated 1RM", displayWeight(estimatedOneRepMax))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.tint)

                        if model.points.count <= 24 {
                            PointMark(
                                x: .value("Date", point.date, unit: .minute),
                                y: .value("Estimated 1RM", displayWeight(estimatedOneRepMax))
                            )
                            .symbolSize(24)
                            .foregroundStyle(.tint)
                        }
                    }
                }
                .animation(.none, value: model.points)
                .chartYScale(domain: yDomain ?? 0...100)
                .chartYAxisLabel(preferredUnit.symbol)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: yStride)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayStride)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 184)
                .accessibilityLabel("Estimated one repetition maximum chart")
            } else {
                Text("Complete weighted sets with repetitions to calculate estimated 1RM.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .repSurface()
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
            spacing: 12
        ) {
            ProgressMetricCard(
                title: "Best weight",
                value: model.metrics.bestWeight.map(formattedWeight) ?? "—",
                systemImage: "scalemass"
            )
            ProgressMetricCard(
                title: "Estimated 1RM",
                value: model.metrics.bestEstimatedOneRepMax.map(formattedWeight) ?? "—",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            ProgressMetricCard(
                title: "Best reps",
                value: model.metrics.bestRepetitions?.formatted() ?? "—",
                systemImage: "repeat"
            )
            ProgressMetricCard(
                title: "Total sets",
                value: model.metrics.totalSets.formatted(),
                systemImage: "checkmark.circle"
            )
            ProgressMetricCard(
                title: "Workout days",
                value: model.points.count.formatted(),
                systemImage: "calendar"
            )
            ProgressMetricCard(
                title: "Sessions in range",
                value: model.metrics.sessionsInRange.formatted(),
                systemImage: "figure.strengthtraining.traditional"
            )
            ProgressMetricCard(
                title: "Recent change",
                value: model.metrics.recentChangeDescription,
                systemImage: "arrow.up.right"
            )
        }
    }

    @ViewBuilder
    private var latestSummary: some View {
        if let latestPerformance = model.metrics.latestPerformance {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last performed")
                    .font(.headline)
                Text(latestPerformance.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    if let bestWeight = latestPerformance.bestWeight {
                        Label(formattedWeight(bestWeight), systemImage: "scalemass")
                    }
                    Label("\(latestPerformance.completedSetCount) sets", systemImage: "checkmark.circle")
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .repSurface()
        }
    }

    private func displayWeight(_ kilograms: Double) -> Double {
        UnitConversion.weight(kilograms, from: .kilograms, to: preferredUnit)
    }

    private func formattedWeight(_ kilograms: Double) -> String {
        UnitConversion.displayWeight(kilograms: kilograms, unit: preferredUnit, maximumFractionDigits: 2)
    }
}

private struct ProgressMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RepVisualSystem.tint)
                .frame(width: 30, height: 30)
                .background(RepVisualSystem.tint.opacity(0.1), in: .rect(cornerRadius: 9))
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        .accessibilityElement(children: .combine)
    }
}
