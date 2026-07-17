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

    @Query(sort: \BodyweightEntry.measuredAt)
    private var bodyweightEntries: [BodyweightEntry]

    @State private var selectedExerciseID: UUID?
    @State private var timeRange: ProgressTimeRange = .ninetyDays
    @State private var comparison: ExerciseProgressComparison = .none
    @State private var model = ExerciseProgressModel()

    private var preferredUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kilograms
    }

    private var selectedExercise: Exercise? {
        guard let id = model.resolvedSelection(for: selectedExerciseID) else { return nil }
        return model.availableExercises.first { $0.id == id }
    }

    private var comparisonPoints: [ExerciseProgressComparisonPoint] {
        switch comparison {
        case .none:
            return []
        case .bodyweight:
            return bodyweightEntries
                .compactMap {
                    guard timeRange.includes($0.measuredAt),
                          let value = validDisplayWeight($0.weightKilograms) else { return nil }
                    return ExerciseProgressComparisonPoint(
                        id: $0.id,
                        date: $0.measuredAt,
                        value: value
                    )
                }
        case .sessionLength:
            guard let exerciseID = model.resolvedSelection(for: selectedExerciseID) else { return [] }
            return completedSessions.compactMap { session in
                let date = session.completedAt ?? session.startedAt
                let includesExercise = session.exercises.contains { workoutExercise in
                    workoutExercise.exercise?.id == exerciseID
                        && workoutExercise.sets.contains(where: \.isCompleted)
                }
                guard includesExercise, timeRange.includes(date) else { return nil }
                let minutes = session.duration(at: date) / 60
                guard minutes.isFinite, minutes > 0 else { return nil }
                return ExerciseProgressComparisonPoint(id: session.id, date: date, value: minutes)
            }
        }
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
                RepMascotEmptyState(
                    pose: .empty,
                    title: "No exercise progress yet",
                    description: "Complete a workout to start seeing strength trends."
                )
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
                        .repSecondaryText()
                    Text(selectedExercise?.name ?? "Choose exercise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .repSecondaryText()
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
                        .repSecondaryText()
                }

                Spacer()

                if let latest = model.metrics.latestPerformance?.estimatedOneRepMax {
                    Text(formattedWeight(latest))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RepVisualSystem.tint)
                }
            }

            comparisonSelector

            if model.points.contains(where: { $0.estimatedOneRepMax != nil }) {
                if comparison == .none || comparisonPoints.isEmpty {
                    standardStrengthChart
                } else {
                    comparisonStrengthChart
                }

                if comparison != .none, comparisonPoints.isEmpty {
                    Text(comparison.emptyMessage)
                        .font(.caption)
                        .repSecondaryText()
                }
            } else {
                Text("Complete weighted sets with repetitions to calculate estimated 1RM.")
                    .font(.subheadline)
                    .repSecondaryText()
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .repSurface()
    }

    private var comparisonSelector: some View {
        Menu {
            Picker("Comparison", selection: $comparison) {
                ForEach(ExerciseProgressComparison.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: comparison.systemImage)
                Text(comparison == .none ? "Add comparison" : comparison.title)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(comparison == .none ? Color.secondary : comparison.color)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .repGlassControl(cornerRadius: RepVisualSystem.controlRadius)
        }
        .accessibilityLabel("Chart comparison, \(comparison.title)")
    }

    private var standardStrengthChart: some View {
        let yValues = model.points.compactMap { point in
            point.estimatedOneRepMax.flatMap(validDisplayWeight)
        }
        let yDomain = ProgressChartScale.niceYDomain(
            for: yValues,
            minimumPadding: preferredUnit == .kilograms ? 2.5 : 5
        )
        let yStride = yDomain.map { ProgressChartScale.axisStride(for: $0) } ?? 5
        let dayStride = ProgressChartScale.dayStride(for: model.points.map(\.date))

        return Chart(model.points) { point in
            if let estimatedOneRepMax = point.estimatedOneRepMax,
               let displayValue = validDisplayWeight(estimatedOneRepMax) {
                LineMark(
                    x: .value("Date", point.date, unit: .minute),
                    y: .value("Estimated 1RM", displayValue)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)

                if model.points.count <= 24 {
                    PointMark(
                        x: .value("Date", point.date, unit: .minute),
                        y: .value("Estimated 1RM", displayValue)
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
    }

    private var comparisonStrengthChart: some View {
        let strengthValues = model.points.compactMap { point in
            point.estimatedOneRepMax.flatMap(validDisplayWeight)
        }
        let strengthDomain = ProgressChartScale.niceYDomain(
            for: strengthValues,
            minimumPadding: preferredUnit == .kilograms ? 2.5 : 5
        ) ?? 0...100
        let overlayDomain = ProgressChartScale.niceYDomain(
            for: comparisonPoints.map(\.value),
            minimumPadding: comparison.minimumPadding(for: preferredUnit)
        ) ?? 0...100
        let dates = model.points.map(\.date) + comparisonPoints.map(\.date)
        let dayStride = ProgressChartScale.dayStride(for: dates)
        let axisFractions = [0.0, 0.25, 0.5, 0.75, 1.0]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                chartLegend(title: "1RM · \(preferredUnit.symbol)", color: RepVisualSystem.tint, dashed: false)
                chartLegend(title: "\(comparison.title) · \(comparison.unit(preferredUnit: preferredUnit))", color: comparison.color, dashed: true)
            }

            Chart {
                ForEach(model.points) { point in
                    if let estimatedOneRepMax = point.estimatedOneRepMax,
                       let value = validDisplayWeight(estimatedOneRepMax) {
                        LineMark(
                            x: .value("Date", point.date, unit: .minute),
                            y: .value("Estimated 1RM", normalized(value, in: strengthDomain))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(RepVisualSystem.tint)

                        if model.points.count <= 24 {
                            PointMark(
                                x: .value("Date", point.date, unit: .minute),
                                y: .value("Estimated 1RM", normalized(value, in: strengthDomain))
                            )
                            .symbolSize(24)
                            .foregroundStyle(RepVisualSystem.tint)
                        }
                    }
                }

                ForEach(comparisonPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .minute),
                        y: .value(comparison.title, normalized(point.value, in: overlayDomain))
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .foregroundStyle(comparison.color)

                    if comparisonPoints.count <= 24 {
                        PointMark(
                            x: .value("Date", point.date, unit: .minute),
                            y: .value(comparison.title, normalized(point.value, in: overlayDomain))
                        )
                        .symbolSize(20)
                        .foregroundStyle(comparison.color)
                    }
                }
            }
            .animation(.none, value: comparisonPoints)
            .chartYScale(domain: 0.0...1.0)
            .chartYAxis {
                AxisMarks(position: .leading, values: axisFractions) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    if let fraction = value.as(Double.self) {
                        AxisValueLabel {
                            Text(axisLabel(denormalized(fraction, in: strengthDomain)))
                                .foregroundStyle(RepVisualSystem.tint)
                        }
                    }
                }
                AxisMarks(position: .trailing, values: axisFractions) { value in
                    if let fraction = value.as(Double.self) {
                        AxisValueLabel {
                            Text(axisLabel(denormalized(fraction, in: overlayDomain)))
                                .foregroundStyle(comparison.color)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: dayStride)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 210)
            .accessibilityLabel("Estimated one repetition maximum compared with \(comparison.title.lowercased())")
        }
    }

    private func chartLegend(title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(color).frame(width: 5, height: 2)
                    }
                }
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: 18, height: 3)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func normalized(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard value.isFinite,
              domain.lowerBound.isFinite,
              domain.upperBound.isFinite,
              span.isFinite,
              span > 0 else { return 0.5 }
        let result = (value - domain.lowerBound) / span
        return result.isFinite ? min(max(result, 0), 1) : 0.5
    }

    private func denormalized(_ fraction: Double, in domain: ClosedRange<Double>) -> Double {
        let result = domain.lowerBound + fraction * (domain.upperBound - domain.lowerBound)
        return result.isFinite ? result : 0
    }

    private func axisLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
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
                    .repSecondaryText()
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

    private func validDisplayWeight(_ kilograms: Double) -> Double? {
        guard kilograms.isFinite, kilograms >= 0 else { return nil }
        let value = displayWeight(kilograms)
        return value.isFinite ? value : nil
    }

    private func formattedWeight(_ kilograms: Double) -> String {
        UnitConversion.displayWeight(kilograms: kilograms, unit: preferredUnit, maximumFractionDigits: 2)
    }
}

private enum ExerciseProgressComparison: String, CaseIterable, Identifiable {
    case none
    case bodyweight
    case sessionLength

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .bodyweight: "Bodyweight"
        case .sessionLength: "Session length"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "chart.xyaxis.line"
        case .bodyweight: "scalemass"
        case .sessionLength: "clock"
        }
    }

    var color: Color {
        switch self {
        case .none: .secondary
        case .bodyweight: .orange
        case .sessionLength: .purple
        }
    }

    var emptyMessage: String {
        switch self {
        case .none: ""
        case .bodyweight: "No bodyweight entries in this date range."
        case .sessionLength: "No matching completed sessions in this date range."
        }
    }

    func unit(preferredUnit: WeightUnit) -> String {
        switch self {
        case .none: ""
        case .bodyweight: preferredUnit.symbol
        case .sessionLength: "min"
        }
    }

    func minimumPadding(for preferredUnit: WeightUnit) -> Double {
        switch self {
        case .none: 1
        case .bodyweight: preferredUnit == .kilograms ? 0.5 : 1
        case .sessionLength: 5
        }
    }
}

private struct ExerciseProgressComparisonPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let value: Double
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
                .repSecondaryText()
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        .accessibilityElement(children: .combine)
    }
}
