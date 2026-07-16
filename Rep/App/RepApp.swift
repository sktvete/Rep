import SwiftData
import SwiftUI

@main
struct RepApp: App {
    @UIApplicationDelegateAdaptor(RepAppDelegate.self) private var appDelegate

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

private enum AppTab: Int, CaseIterable {
    case today
    case history
    case progress
    case routines
    case settings

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .progress: "Progress"
        case .routines: "Routines"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .history: "clock.arrow.circlepath"
        case .progress: "chart.xyaxis.line"
        case .routines: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

private struct AppRootView: View {
    private static let pageTransitionDuration: TimeInterval = 0.1

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var settings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var presentedWorkout: WorkoutSession?
    @State private var hasRestoredActiveWorkout = false
    @State private var isPreparingApp = true
    @State private var startupError: String?

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    Group {
                        if let presentedWorkout {
                            ActiveWorkoutView(
                                session: presentedWorkout,
                                onKeyboardNavigate: navigateFromWorkoutKeyboard,
                                onClose: { self.presentedWorkout = nil }
                            )
                            .id(presentedWorkout.id)
                        } else {
                            TodayView(onOpenWorkout: present)
                        }
                    }
                    .repTabPage(.today, selection: selectedTab, width: geometry.size.width)

                    HistoryView(onOpenWorkout: present)
                        .repTabPage(.history, selection: selectedTab, width: geometry.size.width)

                    TrainingProgressView()
                        .repTabPage(.progress, selection: selectedTab, width: geometry.size.width)

                    RoutinesView(onStartRoutine: start)
                        .repTabPage(.routines, selection: selectedTab, width: geometry.size.width)

                    SettingsView()
                        .repTabPage(.settings, selection: selectedTab, width: geometry.size.width)
                }
                .simultaneousGesture(mainScreenSwipe())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    RepTransparentTabBar(
                        selection: selectedTab,
                        hasActiveWorkout: presentedWorkout != nil,
                        onSelect: selectTab
                    )
                }
            }

            if isPreparingApp {
                RepStartupView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .tint(themeTint)
        .environment(\.repThemeSettings, themeSettings)
        .preferredColorScheme(preferredColorScheme)
        .task {
            HapticEngineManager.shared.warm()
            RestTimerLiveActivityManager.reconcileOnLaunch()
            await bootstrapLocalStore()
            generateDevelopmentSampleDataIfRequested()
            restoreActiveWorkoutIfNeeded()
            warmExercisePickerCache()
            prewarmMainScreenData()
            withAnimation(.easeOut(duration: 0.22)) {
                isPreparingApp = false
            }
            AppLog.breadcrumb("Tab selected: \(selectedTab.title)")
        }
        .onChange(of: selectedTab) { _, tab in
            AppLog.breadcrumb("Tab selected: \(tab.title)")
        }
        .alert("Rep couldn’t prepare local data", isPresented: Binding(
            get: { startupError != nil },
            set: { if !$0 { startupError = nil } }
        )) {
            Button("Try Again") {
                Task { await bootstrapLocalStore() }
            }
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

    private func selectTab(_ tab: AppTab) {
        withAnimation(.easeOut(duration: Self.pageTransitionDuration)) {
            selectedTab = tab
        }
    }

    private func present(_ session: WorkoutSession) {
        if presentedWorkout?.id != session.id {
            withTransaction(Transaction(animation: nil)) {
                presentedWorkout = session
            }
        }

        guard selectedTab != .today else { return }
        Task { @MainActor in
            // Give the already-mounted Today tab one render pass to prepare the
            // workout before moving it onscreen from History or Routines.
            await Task.yield()
            selectTab(.today)
        }
    }

    private func navigateFromWorkoutKeyboard(_ destination: WorkoutKeyboardDestination) {
        let tab: AppTab = switch destination {
        case .workout: .today
        case .history: .history
        case .routines: .routines
        case .settings: .settings
        }
        selectTab(tab)
    }

    private func start(_ routine: Routine) {
        do {
            let preferredSettings = settings.first
            let session = try WorkoutService(
                context: modelContext,
                defaultRestSeconds: preferredSettings?.defaultRestSeconds ?? 90
            ).startWorkout(from: routine)
            present(session)
        } catch {
            AppLog.persistenceFailure(operation: "Start routine workout", error: error)
            startupError = error.localizedDescription
        }
    }

    private func restoreActiveWorkoutIfNeeded() {
        guard !hasRestoredActiveWorkout else { return }
        hasRestoredActiveWorkout = true

        do {
            if let session = try WorkoutService(context: modelContext).activeSession() {
                presentedWorkout = session
                selectedTab = .today
            }
        } catch {
            AppLog.persistenceFailure(operation: "Restore active workout", error: error)
        }
    }

    private func generateDevelopmentSampleDataIfRequested() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-RepGenerateSampleData") else { return }
        do {
            try DevelopmentSampleDataService(context: modelContext).generate(referenceDate: .now)
        } catch {
            AppLog.persistenceFailure(operation: "Generate launch sample data", error: error)
        }
#endif
    }

    private func bootstrapLocalStore() async {
        var catalogPreparationError: Error?

        do {
            _ = try BundledExerciseCatalogService.seedIfNeeded(in: modelContext)
        } catch {
            catalogPreparationError = error
            AppLog.persistenceFailure(operation: "Load bundled exercise catalog", error: error)
        }

        do {
            _ = try await LegacyExerciseDBDataRemovalService.removeUnlicensedData(in: modelContext)
        } catch {
            catalogPreparationError = catalogPreparationError ?? error
            AppLog.persistenceFailure(operation: "Remove legacy exercise catalog data", error: error)
        }

        do {
            _ = try ExerciseSeedService.seedIfNeeded(in: modelContext)
            _ = try RoutineColorSnapshotBackfillService.backfill(in: modelContext)
            if let helpVideoCatalog = try? ExerciseHelpVideoCatalog.load() {
                _ = try ExerciseHelpVideoEnrichmentService.enrichAll(
                    in: modelContext,
                    catalog: helpVideoCatalog
                )
            }
            if let existing = settings.first {
                UserSettingsThemeMigration.backfill(existing)
            } else {
                modelContext.insert(UserSettings())
            }
            try modelContext.save()
            if let catalogPreparationError {
                startupError = catalogPreparationError.localizedDescription
            }
        } catch {
            AppLog.persistenceFailure(operation: "Bootstrap local store", error: error)
            startupError = error.localizedDescription
        }
    }

    private func warmExercisePickerCache() {
        let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>()))?
            .filter { !$0.isArchived } ?? []
        ExercisePickerSessionCache.scheduleWarm(exercises: exercises, in: modelContext)
    }

    private func prewarmMainScreenData() {
        _ = try? modelContext.fetch(FetchDescriptor<Routine>())
        _ = try? modelContext.fetch(FetchDescriptor<WorkoutSession>())
        _ = try? modelContext.fetch(FetchDescriptor<BodyweightEntry>())
    }

    private func mainScreenSwipe() -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let projectedHorizontal = value.predictedEndTranslation.width
                guard (abs(horizontal) > 50 || abs(projectedHorizontal) > 110),
                      abs(horizontal) > abs(vertical) * 1.4 else { return }

                let tabs = AppTab.allCases
                guard let index = tabs.firstIndex(of: selectedTab) else { return }
                let direction = abs(projectedHorizontal) > abs(horizontal)
                    ? projectedHorizontal
                    : horizontal

                let destination: AppTab?
                if direction > 0, index > tabs.startIndex {
                    destination = tabs[index - 1]
                } else if direction < 0, index < tabs.index(before: tabs.endIndex) {
                    destination = tabs[index + 1]
                } else {
                    destination = nil
                }

                if let destination {
                    selectTab(destination)
                }
            }
    }
}

private extension View {
    func repTabPage(_ tab: AppTab, selection: AppTab, width: CGFloat) -> some View {
        offset(x: CGFloat(tab.rawValue - selection.rawValue) * width)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .zIndex(selection == tab ? 1 : 0)
    }
}

private struct RepTransparentTabBar: View {
    let selection: AppTab
    let hasActiveWorkout: Bool
    let onSelect: (AppTab) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            tabContent
                .glassEffect(.clear.interactive(), in: Capsule())
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        } else {
            tabContent
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
    }

    private var tabContent: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: image(for: tab))
                            .font(.system(
                                size: 20,
                                weight: selection == tab ? .semibold : .medium
                            ))
                            .frame(height: 27)

                        Text(title(for: tab))
                            .font(.system(size: 11, weight: selection == tab ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(for: tab))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private func title(for tab: AppTab) -> String {
        tab == .today && hasActiveWorkout ? "Workout" : tab.title
    }

    private func image(for tab: AppTab) -> String {
        tab == .today && hasActiveWorkout ? "bolt.fill" : tab.systemImage
    }
}

private struct RepStartupView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.11, blue: 0.48),
                    Color(red: 0.02, green: 0.38, blue: 0.96),
                    Color(red: 0.0, green: 0.16, blue: 0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 330, height: 330)
                .blur(radius: 70)
                .offset(x: 150, y: -250)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 142, height: 142)
                        .overlay {
                            Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                        }
                        .scaleEffect(isPulsing ? 1.035 : 0.97)

                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(.white)

                    Circle()
                        .fill(Color(red: 0.03, green: 0.31, blue: 0.88))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
                }

                VStack(spacing: 7) {
                    Text("REP")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(7)
                    Text("Ready for your next set")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                }
                .foregroundStyle(.white)

                ProgressView()
                    .tint(.white)
                    .controlSize(.regular)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rep is getting ready")
        .task {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
