import SwiftData
import SwiftUI

@main
struct RepApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(
            for: [
                Exercise.self,
                Routine.self,
                RoutineExercise.self,
                WorkoutSession.self,
                WorkoutExercise.self,
                WorkoutSet.self,
                BodyweightEntry.self,
                LearnedPattern.self,
                UserSettings.self
            ]
        )
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var settings: [UserSettings]

    @State private var presentedWorkout: WorkoutSession?
    @State private var startupError: String?
    @State private var catalogService = ExerciseDBCatalogService()

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView(onOpenWorkout: present)
            }

            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }

            Tab("Progress", systemImage: "chart.xyaxis.line") {
                TrainingProgressView()
            }

            Tab("Routines", systemImage: "list.bullet.rectangle") {
                RoutinesView(onStartRoutine: start)
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(themeTint)
        .environment(\.repThemeSettings, themeSettings)
        .preferredColorScheme(preferredColorScheme)
        .repTabBarBehavior()
        .fullScreenCover(item: $presentedWorkout) { session in
            ActiveWorkoutView(session: session) {
                presentedWorkout = nil
            }
        }
        .task {
            HapticEngineManager.shared.warm()
            RestTimerLiveActivityManager.reconcileOnLaunch()
            bootstrapLocalStore()
            warmExercisePickerCache()
            await synchronizeExerciseCatalog()
        }
        .alert("Rep couldn’t prepare local data", isPresented: Binding(
            get: { startupError != nil },
            set: { if !$0 { startupError = nil } }
        )) {
            Button("Try Again") { bootstrapLocalStore() }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(startupError ?? "Please try again.")
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.first?.appearancePreference ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var themeTint: Color {
        themeSettings.resolved(for: activeColorScheme).accent
    }

    private var activeColorScheme: ColorScheme {
        switch settings.first?.appearancePreference ?? .system {
        case .system: systemColorScheme
        case .light: .light
        case .dark: .dark
        }
    }

    private var themeSettings: RepThemeSettings {
        guard let settings = settings.first else { return RepThemeSettings() }
        return RepThemeSettings(settings: settings)
    }

    private func present(_ session: WorkoutSession) {
        presentedWorkout = session
    }

    private func start(_ routine: Routine) {
        do {
            let preferredSettings = settings.first
            let session = try WorkoutService(
                context: modelContext,
                defaultRestSeconds: preferredSettings?.defaultRestSeconds ?? 90
            ).startWorkout(from: routine)
            presentedWorkout = session
        } catch {
            AppLog.persistenceFailure(operation: "Start routine workout", error: error)
            startupError = error.localizedDescription
        }
    }

    private func bootstrapLocalStore() {
        do {
            _ = try ExerciseSeedService.seedIfNeeded(in: modelContext)
            if let existing = settings.first {
                UserSettingsThemeMigration.backfill(existing)
            } else {
                modelContext.insert(UserSettings())
            }
            try modelContext.save()
        } catch {
            AppLog.persistenceFailure(operation: "Bootstrap local store", error: error)
            startupError = error.localizedDescription
        }
    }

    private func synchronizeExerciseCatalog() async {
        do {
            try await catalogService.synchronize(in: modelContext)
            _ = try catalogService.backfillMissingMediaLocally(in: modelContext)
            warmExercisePickerCache()
        } catch is CancellationError {
            return
        } catch {
            AppLog.persistenceFailure(operation: "Synchronize exercise catalog", error: error)
        }
    }

    private func warmExercisePickerCache() {
        let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>()))?
            .filter { !$0.isArchived } ?? []
        ExercisePickerSessionCache.scheduleWarm(exercises: exercises, in: modelContext)
    }
}
