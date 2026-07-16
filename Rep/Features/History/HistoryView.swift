import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @Query private var routines: [Routine]
    @Query private var settings: [UserSettings]

    @State private var errorMessage: String?
    @State private var resumingSessionID: UUID?

    private let onOpenWorkout: (WorkoutSession) -> Void

    init(onOpenWorkout: @escaping (WorkoutSession) -> Void = { _ in }) {
        self.onOpenWorkout = onOpenWorkout
    }

    private var preferredUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kilograms
    }

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.state == .completed }
    }

    private var ongoingSessions: [WorkoutSession] {
        sessions.filter { $0.state == .active }
    }

    private var groupedSessions: [(date: Date, sessions: [WorkoutSession])] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: completedSessions) {
            calendar.startOfDay(for: $0.completedAt ?? $0.startedAt)
        }
        return grouped
            .map { (date: $0.key, sessions: $0.value.sorted { sessionDate($0) > sessionDate($1) }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RepScreenBackground()

                if completedSessions.isEmpty && ongoingSessions.isEmpty {
                    ContentUnavailableView {
                        Label("No workouts yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finished workouts will appear here with every exercise and set.")
                    }
                } else {
                    List {
                        if !ongoingSessions.isEmpty {
                            Section {
                                ForEach(ongoingSessions) { session in
                                    Button {
                                        resume(session)
                                    } label: {
                                        OngoingWorkoutRow(
                                            session: session,
                                            color: routineColor(for: session),
                                            isResuming: resumingSessionID == session.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(resumingSessionID != nil)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .accessibilityHint("Returns to this workout")
                                }
                            } header: {
                                Text("Ongoing")
                                    .font(.subheadline.weight(.semibold))
                                    .repSecondaryText()
                                    .textCase(nil)
                                    .padding(.top, 8)
                            }
                        }

                        if !completedSessions.isEmpty {
                            Section {
                                HistoryOverviewCard(sessions: completedSessions)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }

                        ForEach(groupedSessions, id: \.date) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    NavigationLink {
                                        WorkoutHistoryDetailView(session: session, preferredUnit: preferredUnit)
                                            .tint(routineColor(for: session))
                                    } label: {
                                        WorkoutHistoryRow(
                                            session: session,
                                            preferredUnit: preferredUnit,
                                            color: routineColor(for: session)
                                        )
                                    }
                                    .navigationLinkIndicatorVisibility(.hidden)
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .accessibilityHint("Shows exercises and completed sets")
                                    .contextMenu {
                                        Button("Delete workout", systemImage: "trash", role: .destructive) {
                                            delete(session)
                                        }
                                    }
                                }
                            } header: {
                                Text(group.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                    .font(.subheadline.weight(.semibold))
                                    .repSecondaryText()
                                    .textCase(nil)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, RepVisualSystem.pageSpacing, for: .scrollContent)
                    .repSoftScrollEdges()
                }
            }
            .repMainNavigationTitle("History")
            .onAppear { AppLog.breadcrumb("History opened") }
            .alert("Couldn’t delete the workout", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func sessionDate(_ session: WorkoutSession) -> Date {
        session.completedAt ?? session.startedAt
    }

    private func routineColor(for session: WorkoutSession) -> Color {
        if let routineID = session.routineID,
           let routine = routines.first(where: { $0.id == routineID }) {
            return routine.colorPreset.color
        }
        return session.routineColorPreset?.color ?? Color.accentColor
    }

    private func resume(_ session: WorkoutSession) {
        guard resumingSessionID == nil else { return }
        let sessionID = session.id
        resumingSessionID = sessionID
        AppLog.breadcrumb("History resume requested: \(sessionID.uuidString)")

        // Let the List finish its button transaction before the app swaps root pages.
        Task { @MainActor in
            await Task.yield()
            guard resumingSessionID == sessionID,
                  let currentSession = sessions.first(where: { $0.id == sessionID }),
                  currentSession.state == .active else {
                resumingSessionID = nil
                return
            }
            resumingSessionID = nil
            onOpenWorkout(currentSession)
        }
    }

    private func delete(_ session: WorkoutSession) {
        modelContext.delete(session)
        do {
            try modelContext.save()
        } catch {
            AppLog.persistenceFailure(operation: "Delete workout from history", error: error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct OngoingWorkoutRow: View {
    let session: WorkoutSession
    let color: Color
    let isResuming: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "bolt.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.13), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(session.duration(at: context.date).formattedWorkoutDuration)
                        .font(.subheadline.monospacedDigit())
                        .repSecondaryText()
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                if isResuming {
                    ProgressView()
                        .tint(color)
                        .accessibilityLabel("Opening workout")
                } else {
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text("\(session.completedSetCount) sets")
                    .font(.caption.monospacedDigit())
                    .repSecondaryText()
            }
        }
        .padding(16)
        .repSurface()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ongoing \(session.name), \(session.completedSetCount) sets completed")
    }
}

private struct HistoryOverviewCard: View {
    let sessions: [WorkoutSession]

    private var recentSessions: [WorkoutSession] {
        let cutoff = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -29, to: .now) ?? .distantPast
        return sessions.filter { ($0.completedAt ?? $0.startedAt) >= cutoff }
    }

    private var recentSets: Int {
        recentSessions.reduce(0) { $0 + $1.completedSetCount }
    }

    var body: some View {
        HStack(spacing: 0) {
            HistoryOverviewMetric(value: recentSessions.count.formatted(), label: "Workouts", systemImage: "calendar")
            Divider().frame(height: 42)
            HistoryOverviewMetric(value: recentSets.formatted(), label: "Sets", systemImage: "checkmark.circle")
            Divider().frame(height: 42)
            HistoryOverviewMetric(value: sessions.count.formatted(), label: "All time", systemImage: "clock.arrow.circlepath")
        }
        .padding(.vertical, 16)
        .repSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last 30 days")
    }
}

private struct HistoryOverviewMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Label(value, systemImage: systemImage)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .labelStyle(.titleAndIcon)
            Text(label)
                .font(.caption)
                .repSecondaryText()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession
    let preferredUnit: WeightUnit
    let color: Color

    private var completedSets: Int { session.completedSetCount }

    private var applicableVolume: Double {
        session.exercises.flatMap(\.sets).reduce(into: 0) { total, set in
            guard set.isCompleted,
                  let weight = set.weight,
                  let repetitions = set.repetitions,
                  weight > 0,
                  repetitions > 0 else { return }
            total += weight * Double(repetitions)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.13), in: .rect(cornerRadius: 11))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(session.completedAt ?? session.startedAt, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .repSecondaryText()
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 11)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 14) {
                HistoryRowMetric(value: session.historyDuration.formattedWorkoutDuration, systemImage: "timer")
                HistoryRowMetric(value: "\(session.exercises.count) exercises", systemImage: "dumbbell")
                HistoryRowMetric(value: "\(completedSets) sets", systemImage: "checkmark.circle")
            }

            if applicableVolume > 0 {
                let displayedVolume = UnitConversion.weight(applicableVolume, from: .kilograms, to: preferredUnit)
                Text("\(displayedVolume.formatted(.number.precision(.fractionLength(0)))) \(preferredUnit.symbol) volume")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .repSecondaryText()
            }
        }
        .padding(16)
        .repSurface()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRowMetric: View {
    let value: String
    let systemImage: String

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.caption)
            .repSecondaryText()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

extension WorkoutSession {
    var historyDuration: TimeInterval {
        max(0, (completedAt ?? Date()).timeIntervalSince(startedAt))
    }
}

extension TimeInterval {
    var formattedWorkoutDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 3_600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? "0 min"
    }
}
