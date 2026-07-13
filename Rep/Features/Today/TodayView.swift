import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]
    @Query private var learnedPatterns: [LearnedPattern]
    @Query private var settings: [UserSettings]

    @State private var dismissedSuggestionID: UUID?
    @State private var explanation: String?
    @State private var isChoosingRoutine = false
    @State private var operationError: String?

    private let onOpenWorkout: (WorkoutSession) -> Void

    init(onOpenWorkout: @escaping (WorkoutSession) -> Void = { _ in }) {
        self.onOpenWorkout = onOpenWorkout
    }

    private var activeSession: WorkoutSession? {
        sessions.first { $0.state == .active }
    }

    private var activeRoutines: [Routine] {
        routines.filter { !$0.isArchived }
    }

    private var suggestion: RoutineSuggestion? {
        guard settings.first?.patternSuggestionsEnabled ?? true else { return nil }
        return PatternDetectionService().suggestion(
            for: .now,
            sessions: sessions.filter { $0.state == .completed },
            routines: activeRoutines,
            learnedPatterns: learnedPatterns
        )
    }

    private var suggestedRoutine: Routine? {
        guard let suggestion, suggestion.routineID != dismissedSuggestionID else { return nil }
        return activeRoutines.first { $0.id == suggestion.routineID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RepScreenBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RepVisualSystem.pageSpacing) {
                        primarySection

                        WeeklyActivityCard(completedSessions: sessions.filter { $0.state == .completed })
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .repSoftScrollEdges()
            }
            .navigationTitle("Today")
            .sheet(isPresented: $isChoosingRoutine) {
                RoutineStartPicker(routines: activeRoutines) { routine in
                    isChoosingRoutine = false
                    start(routine)
                }
            }
            .alert("Why this routine?", isPresented: Binding(
                get: { explanation != nil },
                set: { if !$0 { explanation = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(explanation ?? "This is based on your completed workouts.")
            }
            .alert("Couldn’t start workout", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError ?? "Please try again.")
            }
        }
    }

    @ViewBuilder
    private var primarySection: some View {
        if let activeSession {
            ActiveWorkoutCard(session: activeSession) {
                onOpenWorkout(activeSession)
            }
        } else {
            StartWorkoutCard(
                hasRoutines: !activeRoutines.isEmpty,
                suggestedRoutine: suggestedRoutine,
                onStartSuggested: suggestedRoutine.map { routine in { start(routine) } },
                onSuggestionWhy: suggestion.map { s in { explanation = s.explanation } },
                onSuggestionNotToday: suggestion.map { s in { recordDismissal(of: s, suppress: false) } },
                onStopSuggesting: suggestion.map { s in { recordDismissal(of: s, suppress: true) } },
                onChooseRoutine: { isChoosingRoutine = true },
                onStartEmpty: startEmptyWorkout
            )
        }
    }

    private func start(_ routine: Routine) {
        do {
            let session = try WorkoutService(context: modelContext).startWorkout(from: routine)
            onOpenWorkout(session)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func startEmptyWorkout() {
        do {
            let session = try WorkoutService(context: modelContext).startEmptyWorkout(name: "Workout")
            onOpenWorkout(session)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func recordDismissal(of suggestion: RoutineSuggestion, suppress: Bool) {
        dismissedSuggestionID = suggestion.routineID
        let pattern: LearnedPattern
        if let existing = learnedPatterns.first(where: { $0.signature == suggestion.signature }) {
            pattern = existing
        } else {
            pattern = PatternDetectionService().learnedPattern(from: suggestion)
            modelContext.insert(pattern)
        }

        if suppress {
            pattern.isSuppressed = true
            pattern.updatedAt = .now
        } else {
            pattern.dismiss()
        }

        do {
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
        }
    }

}

private struct ActiveWorkoutCard: View {
    let session: WorkoutSession
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Workout in progress", systemImage: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(session.name)
                .font(.title.bold())
                .fontDesign(.rounded)
            HStack(spacing: 12) {
                Label(session.startedAt.formatted(.relative(presentation: .named)), systemImage: "clock")
                Spacer()
                Text("\(session.completedSetCount) sets logged")
                    .contentTransition(.numericText())
            }
            .font(.subheadline)
            .repSecondaryText()

            Button(action: onContinue) {
                Text("Continue Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .repPrimaryButton()
            .controlSize(.large)
            .accessibilityHint("Returns to the active workout")
        }
        .padding(22)
        .repSurface()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(.tint.opacity(0.1))
                .padding(18)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StartWorkoutCard: View {
    let hasRoutines: Bool
    var suggestedRoutine: Routine?
    var onStartSuggested: (() -> Void)?
    var onSuggestionWhy: (() -> Void)?
    var onSuggestionNotToday: (() -> Void)?
    var onStopSuggesting: (() -> Void)?
    let onChooseRoutine: () -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            Text("Ready when you are")
                .font(.title.bold())
                .fontDesign(.rounded)
            Text(
                hasRoutines
                    ? "Choose a routine, or start with a blank workout."
                    : "Create a routine for a quicker start next time, or begin with a blank workout."
            )
            .repSecondaryText()

            if let suggestedRoutine, let onStartSuggested {
                HStack(spacing: 10) {
                    Button(action: onStartSuggested) {
                        Label("Try \(suggestedRoutine.name)", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .repSecondaryButton()
                    .controlSize(.large)
                    .accessibilityHint("Starts this routine based on your workout history")

                    if onSuggestionWhy != nil || onSuggestionNotToday != nil || onStopSuggesting != nil {
                        Menu {
                            if let onSuggestionWhy {
                                Button("Why this?", systemImage: "questionmark.circle", action: onSuggestionWhy)
                            }
                            if let onSuggestionNotToday {
                                Button("Not today", systemImage: "xmark", action: onSuggestionNotToday)
                            }
                            if let onStopSuggesting {
                                Button("Stop suggesting this", systemImage: "eye.slash", role: .destructive, action: onStopSuggesting)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 22, height: 22)
                        }
                        .repSecondaryButton()
                        .accessibilityLabel("Suggestion options")
                    }
                }
            }

            if hasRoutines {
                Button(action: onChooseRoutine) {
                    Label("Choose Routine", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .repPrimaryButton()
                .controlSize(.large)

                Button(action: onStartEmpty) {
                    Label("Start Empty Workout", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .repSecondaryButton()
                .controlSize(.large)
            } else {
                Button(action: onStartEmpty) {
                    Label("Start Empty Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .repPrimaryButton()
                .controlSize(.large)
            }
        }
        .padding(22)
        .repSurface()
    }
}

private struct WeeklyActivityCard: View {
    let completedSessions: [WorkoutSession]
    @Environment(\.calendar) private var calendar

    private var startOfWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    private var thisWeek: [WorkoutSession] {
        completedSessions.filter { ($0.completedAt ?? $0.startedAt) >= startOfWeek }
    }

    private var setCount: Int {
        thisWeek.reduce(0) { $0 + $1.completedSetCount }
    }

    private var weeklyStreak: Int {
        ProgressCalculator.weeklyStreak(
            sessions: completedSessions,
            relativeTo: .now,
            calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("This Week", systemImage: "calendar")
            HStack(spacing: 12) {
                ActivityMetric(value: "\(weeklyStreak)", label: "Week streak", systemImage: "flame.fill")
                Divider()
                ActivityMetric(value: "\(thisWeek.count)", label: "Workouts")
                Divider()
                ActivityMetric(value: "\(setCount)", label: "Sets")
                Divider()
                ActivityMetric(value: activeDays, label: "Active days")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .repSurface()
        .accessibilityElement(children: .combine)
    }

    private var activeDays: String {
        let days = Set(thisWeek.map { calendar.startOfDay(for: $0.completedAt ?? $0.startedAt) })
        return "\(days.count)"
    }
}

private struct ActivityMetric: View {
    let value: String
    let label: String
    var systemImage: String?

    var body: some View {
        VStack(spacing: 3) {
            if let systemImage {
                Label(value, systemImage: systemImage)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.multicolor)
            } else {
                Text(value)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(label).font(.caption).repSecondaryText()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoutineStartPicker: View {
    @Environment(\.dismiss) private var dismiss
    let routines: [Routine]
    let onSelect: (Routine) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No routines yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create one in the Routines tab, or start an empty workout.")
                    )
                } else {
                    List(routines) { routine in
                        Button {
                            onSelect(routine)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(routine.name)
                                    Text("\(routine.exercises.count) exercises")
                                        .font(.caption)
                                        .repSecondaryText()
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .repSecondaryText()
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("\(routine.exercises.count) exercises")
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(RepScreenBackground())
            .navigationTitle("Choose Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
    }
}

#Preview {
    TodayView()
        .modelContainer(
            for: [
                WorkoutSession.self,
                WorkoutExercise.self,
                WorkoutSet.self,
                Routine.self,
                RoutineExercise.self,
                Exercise.self,
                LearnedPattern.self,
                UserSettings.self
            ],
            inMemory: true
        )
}
